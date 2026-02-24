---
phase: 02-shared-library-install
plan: 01
subsystem: build-infra
tags: [shared-library, linker, fpic, gfortran, whole-archive, rpath, wrf-hydro]

# Dependency graph
requires:
  - phase: 01-fpic-foundation
    provides: 22 WRF-Hydro static libraries rebuilt with -fPIC in build_fpic/
provides:
  - build.sh --shared flag producing libbmiwrfhydrof.so (4.8M) in bmi_wrf_hydro/build/
  - link_executable_shared() function for linking test executables against the .so via -rpath
  - Auto-run test execution in --shared mode with pass/fail summary
affects: [02-shared-library-install/02-02, 03-python-validation]

# Tech tracking
tech-stack:
  added: [gfortran -shared, --whole-archive/--no-whole-archive, mpif90 --showme:link, -Wl,-rpath]
  patterns: [recompile executable-target .o files with -fPIC for shared library inclusion, extract MPI flags from mpif90 wrapper instead of using mpif90 as link driver]

key-files:
  created: []
  modified:
    - bmi_wrf_hydro/build.sh

key-decisions:
  - "Use gfortran -shared (not mpif90 -shared) for creating .so -- mpif90 wrapper can strip/mangle linker flags like --whole-archive"
  - "Recompile module_NoahMP_hrldas_driver.F and module_hrldas_netcdf_io.F with -fPIC in build/ -- original build_fpic/ .o files have -fPIE (from CMake executable target, not library target)"
  - "Extract MPI linker flags via mpif90 --showme:link and pass directly to gfortran for shared library linking"
  - "Auto-run tests from bmi_wrf_hydro/ directory (not WRF_Hydro_Run_Local/run/) because test program writes bmi_config.nml with relative path ../WRF_Hydro_Run_Local/run/"

patterns-established:
  - "Shared library build pattern: recompile non-PIC .o files from source, then link with gfortran -shared using --whole-archive for static libs"
  - "MPI flag extraction pattern: mpif90 --showme:link provides -L, -l, -Wl flags without mpif90 as driver"
  - "Shared vs static link selection pattern: link_executable_shared() uses -L -l -rpath; link_executable() uses direct .o and -L -l"

requirements-completed: [BUILD-03]

# Metrics
duration: 7min
completed: 2026-02-24
---

# Phase 2 Plan 1: Shared Library Build via build.sh Summary

**build.sh --shared flag produces 4.8M libbmiwrfhydrof.so via gfortran -shared with --whole-archive linking of 22 fPIC static libs, 151/151 tests pass when linked against .so**

## Performance

- **Duration:** 7 min
- **Started:** 2026-02-24T00:25:26Z
- **Completed:** 2026-02-24T00:32:22Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- build.sh --shared flag builds libbmiwrfhydrof.so (4.8M shared library) containing BMI wrapper + all 22 WRF-Hydro static libraries + MPI + NetCDF dependencies
- 151/151 BMI test suite passes when linked against the shared library instead of static objects (no regression)
- Auto-run test execution in --shared mode with pass/fail summary reporting
- Backward compatibility fully preserved: ./build.sh full (without --shared) still works with 151/151 tests passing
- Discovered and resolved -fPIE vs -fPIC issue: CMake's POSITION_INDEPENDENT_CODE=ON sets -fPIE for executable targets (not -fPIC), requiring recompilation of two driver .o files from source

## Task Commits

Each task was committed atomically:

1. **Task 1: Add --shared flag to build.sh producing libbmiwrfhydrof.so** - `89b3ca8` (feat)

## Files Created/Modified
- `bmi_wrf_hydro/build.sh` - Updated with --shared flag support: parses flag, auto-implies --fpic, recompiles extra .o files with -fPIC, builds .so via gfortran -shared with --whole-archive, links tests against .so with rpath, auto-runs tests

## Decisions Made
- Used gfortran -shared instead of mpif90 -shared because mpif90 wrapper can strip/mangle linker flags like --whole-archive. MPI flags extracted via mpif90 --showme:link and passed directly.
- Recompile module_NoahMP_hrldas_driver.F and module_hrldas_netcdf_io.F from WRF-Hydro source with -fPIC into build/ directory. The originals in build_fpic/ have -fPIE because CMake's CMAKE_POSITION_INDEPENDENT_CODE only sets -fPIC for library targets, not executable targets.
- Tests auto-run from bmi_wrf_hydro/ directory (not WRF_Hydro_Run_Local/run/) because the test program writes bmi_config.nml with a relative path (../WRF_Hydro_Run_Local/run/) that is correct relative to bmi_wrf_hydro/.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Extra .o files had -fPIE instead of -fPIC**
- **Found during:** Task 1 (first shared library link attempt)
- **Issue:** The two extra .o files (module_NoahMP_hrldas_driver.F.o, module_hrldas_netcdf_io.F.o) in build_fpic/ were compiled with -fPIE (Position Independent Executable) by CMake, not -fPIC (Position Independent Code). The linker reported: "relocation R_X86_64_PC32 against symbol... recompile with -fPIC". CMake's CMAKE_POSITION_INDEPENDENT_CODE=ON applies -fPIC to library targets but -fPIE to executable targets.
- **Fix:** Added Step 2a in build.sh to recompile these two source files from wrf_hydro_nwm_public/src/ with explicit -fPIC into build/, using the same compile flags as the original build (minus -fPIE, plus -fPIC).
- **Files modified:** bmi_wrf_hydro/build.sh
- **Verification:** libbmiwrfhydrof.so links successfully, ldd shows no missing deps, 151/151 tests pass
- **Committed in:** 89b3ca8

**2. [Rule 1 - Bug] Test auto-run used wrong working directory**
- **Found during:** Task 1 (first test auto-run attempt)
- **Issue:** Auto-run was cd'ing to WRF_Hydro_Run_Local/run/ before running the test. But the test program writes bmi_config.nml with wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/" which is a path relative to bmi_wrf_hydro/. Running from the run directory made the relative path resolve incorrectly, causing initialize() to fail (T01 FAIL).
- **Fix:** Changed auto-run to cd to ${BMI_DIR} (bmi_wrf_hydro/) instead of the run directory.
- **Files modified:** bmi_wrf_hydro/build.sh
- **Verification:** T01 initialize passes, all 151/151 tests pass
- **Committed in:** 89b3ca8

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both fixes were essential for the shared library to build and tests to run. The -fPIE vs -fPIC distinction was a CMake behavior that the plan didn't account for. No scope creep.

## Issues Encountered
- CMake's CMAKE_POSITION_INDEPENDENT_CODE=ON applies different flags depending on target type: -fPIC for SHARED/MODULE library targets, -fPIE for EXECUTABLE targets. This meant the two .o files from WRF-Hydro's wrfhydro executable target needed recompilation from source. This is an important finding for Plan 02-02 (CMake build) as well.
- Floating-point exception warnings (IEEE_INVALID_FLAG, IEEE_OVERFLOW_FLAG, etc.) in test output are pre-existing WRF-Hydro behavior, not caused by shared library changes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **Phase 2 Plan 2 unblocked:** libbmiwrfhydrof.so verified with 151/151 tests, ready for CMake project + pkg-config + conda install
- **Key insight for Plan 02-02:** CMake project must include the two WRF-Hydro driver source files directly in the SHARED library target (not link pre-compiled .o files) to ensure -fPIC compilation
- **No blockers:** All prerequisites for CMake shared library build are satisfied

## Self-Check: PASSED

- FOUND: bmi_wrf_hydro/build.sh (--shared flag present)
- FOUND: 89b3ca8 (Task 1 commit)
- FOUND: .planning/phases/02-shared-library-install/02-01-SUMMARY.md

---
*Phase: 02-shared-library-install*
*Completed: 2026-02-24*
