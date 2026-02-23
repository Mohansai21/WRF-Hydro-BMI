---
phase: 01-fpic-foundation
plan: 01
subsystem: build-infra
tags: [cmake, fpic, position-independent-code, fortran, static-libraries, wrf-hydro]

# Dependency graph
requires:
  - phase: none
    provides: first phase - no dependencies
provides:
  - 22 WRF-Hydro static libraries rebuilt with explicit -fPIC in build_fpic/
  - rebuild_fpic.sh script for reproducible fPIC rebuilds
  - build.sh --fpic flag for linking against fPIC libraries
affects: [02-shared-library-install]

# Tech tracking
tech-stack:
  added: [CMAKE_POSITION_INDEPENDENT_CODE]
  patterns: [cmake wrapper script for flag injection without modifying upstream CMakeLists.txt, parallel build directories for library variants]

key-files:
  created:
    - bmi_wrf_hydro/rebuild_fpic.sh
  modified:
    - bmi_wrf_hydro/build.sh
    - .gitignore

key-decisions:
  - "Used conda gfortran 14.3.0 for fPIC rebuild (aligns with BMI wrapper compiler, replaces system gfortran 13.3.0 used in original build)"
  - "22 libraries (not 24 as research estimated) -- actual count matches original build exactly"
  - "Added build_fpic/ to .gitignore since compiled artifacts should not be version-controlled"

patterns-established:
  - "cmake wrapper script pattern: inject flags via command-line without modifying upstream source"
  - "Parallel build directory pattern: build/ (original) and build_fpic/ (fPIC) coexist"
  - "build.sh flag pattern: --fpic switches library paths, default behavior unchanged"

requirements-completed: [BUILD-01]

# Metrics
duration: 6min
completed: 2026-02-23
---

# Phase 1 Plan 1: fPIC Foundation Summary

**WRF-Hydro 22 static libraries rebuilt with explicit CMAKE_POSITION_INDEPENDENT_CODE=ON via cmake wrapper script, 151/151 BMI regression tests pass, ready for shared library linking in Phase 2**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-23T23:21:08Z
- **Completed:** 2026-02-23T23:27:33Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created `rebuild_fpic.sh` that rebuilds WRF-Hydro with explicit -fPIC into `build_fpic/` using conda gfortran 14.3.0, includes PIC verification via readelf and automatic regression test execution
- Updated `build.sh` with `--fpic` flag that switches library paths to `build_fpic/` while preserving backward compatibility (default still uses `build/`)
- All 22 WRF-Hydro static libraries compiled with -fPIC, zero R_X86_64_32S relocations confirmed across all libraries
- 151/151 BMI test suite passes against fPIC-rebuilt libraries (no regression from original build)
- Compiler aligned: both WRF-Hydro (build_fpic/) and BMI wrapper now use conda gfortran 14.3.0

## Task Commits

Each task was committed atomically:

1. **Task 1: Create rebuild_fpic.sh and update build.sh with --fpic flag** - `e3b93aa` (feat)
2. **Task 2: Execute fPIC rebuild and verify 151-test regression suite** - `7d1b67a` (chore)

**Plan metadata:** `61d38f0` (docs: complete plan)

## Files Created/Modified
- `bmi_wrf_hydro/rebuild_fpic.sh` - cmake wrapper script that rebuilds WRF-Hydro with -fPIC, verifies PIC, counts libraries, and runs 151-test regression suite
- `bmi_wrf_hydro/build.sh` - Updated with --fpic flag support for linking against build_fpic/ libraries
- `.gitignore` - Added build_fpic/ pattern to exclude compiled fPIC artifacts from version control

## Decisions Made
- Used conda gfortran 14.3.0 for fPIC rebuild to align compiler versions between WRF-Hydro libraries and BMI wrapper (original build used system gfortran 13.3.0)
- Library count is 22 (not 24 as research Finding 7 estimated) -- both build/ and build_fpic/ contain the same 22 libraries, matching exactly
- Added build_fpic/ to .gitignore since these are compiled artifacts, not source code

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Library count 22 vs plan expectation of 24**
- **Found during:** Task 2 (fPIC rebuild execution)
- **Issue:** The plan and research document stated 24 `.a` files expected in `build_fpic/lib/`. Actual count is 22, matching the original `build/lib/` exactly.
- **Fix:** No code change needed. The research Finding 7 was slightly inaccurate. All 22 libraries listed in `build.sh` `WRF_LIBS_SINGLE` are present and tested. The `libcrocus_surfex.a` and `libsnowcro.a` that research counted as "additional" are among the 22, not in addition to.
- **Files modified:** None
- **Verification:** `ls build_fpic/lib/*.a | wc -l` returns 22; `ls build/lib/*.a | wc -l` also returns 22; 151/151 tests pass
- **Committed in:** 7d1b67a (documented in Task 2 commit)

---

**Total deviations:** 1 (documentation inaccuracy in research, no code impact)
**Impact on plan:** Zero impact. The 22-library count is correct for both builds. All tests pass.

## Issues Encountered
- WSL2 clock skew warnings during cmake build ("Clock skew detected", "file has modification time in the future") -- harmless, documented in CLAUDE.md as known WSL2/NTFS issue
- `grep -c R_X86_64_32S` returns exit code 1 when no matches found, causing `|| true` to echo "0" on a separate line -- cosmetic only, PIC verification logic works correctly

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **Phase 2 unblocked:** 22 fPIC-compiled static libraries in `build_fpic/lib/` are ready for linking into `libwrfhydrobmi.so`
- **Compiler alignment complete:** Both WRF-Hydro and BMI wrapper now use conda gfortran 14.3.0
- **Build infrastructure ready:** `build.sh --fpic` provides the linking mechanism Phase 2 will extend for shared library creation
- **No blockers:** All prerequisites for shared library linking are satisfied

## Self-Check: PASSED

- FOUND: bmi_wrf_hydro/rebuild_fpic.sh (executable)
- FOUND: bmi_wrf_hydro/build.sh (--fpic flag present)
- FOUND: wrf_hydro_nwm_public/build_fpic/lib/ (22 .a files)
- FOUND: .planning/phases/01-fpic-foundation/01-01-SUMMARY.md
- FOUND: e3b93aa (Task 1 commit)
- FOUND: 7d1b67a (Task 2 commit)

---
*Phase: 01-fpic-foundation*
*Completed: 2026-02-23*
