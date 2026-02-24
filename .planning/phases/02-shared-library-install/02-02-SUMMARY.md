---
phase: 02-shared-library-install
plan: 02
subsystem: build-infra
tags: [cmake, shared-library, pkg-config, babelizer, fortran, linker, whole-archive]

# Dependency graph
requires:
  - phase: 01-fpic-foundation
    provides: 22 WRF-Hydro static libraries rebuilt with -fPIC in build_fpic/
provides:
  - libbmiwrfhydrof.so shared library built via CMake
  - pkg-config bmiwrfhydrof discovery for babelizer
  - 2 .mod files installed to $CONDA_PREFIX/include/
  - CMakeLists.txt following bmi-example-fortran pattern
affects: [03-babelizer-python-validation]

# Tech tracking
tech-stack:
  added: [cmake, pkg-config, GNUInstallDirs, --whole-archive linker flag]
  patterns: [bmi-example-fortran CMakeLists.txt pattern for babelizer compatibility, recompile executable .o sources with -fPIC for shared library inclusion, hydro_stop shim pattern for bare external symbol resolution]

key-files:
  created:
    - bmi_wrf_hydro/bmiwrfhydrof.pc.cmake
    - bmi_wrf_hydro/src/hydro_stop_shim.f90
  modified:
    - bmi_wrf_hydro/CMakeLists.txt

key-decisions:
  - "Library named bmiwrfhydrof (not wrfhydro_bmi) to follow bmi-example-fortran bmi{model}f convention required by babelizer"
  - "Recompile WRF-Hydro driver source files from source with -fPIC instead of linking pre-built .o files (CMAKE_POSITION_INDEPENDENT_CODE only applies to library targets, not executable targets)"
  - "Created hydro_stop_shim.f90 to resolve bare hydro_stop_ symbol pulled in by --whole-archive from dead code in module_reservoir_routing.F90"
  - "pkg-config Requires: bmif (not model-specific .pc) because WRF-Hydro static libs are baked into the .so"

patterns-established:
  - "CMake bmi-example-fortran pattern: project name, set(bmi_name), pkg_check_modules(BMIF), add_library(SHARED), configure_file(.pc.cmake), install targets+mods+pc"
  - "WRF-Hydro source recompilation: include .F source files directly in add_library() to get -fPIC, rather than linking pre-built .o files from build_fpic/"
  - "Symbol shim pattern: provide bare external wrapper that delegates to module version when --whole-archive exposes dead-code references"

requirements-completed: [BUILD-02, BUILD-04, BUILD-05]

# Metrics
duration: 10min
completed: 2026-02-24
---

# Phase 2 Plan 2: CMake Install + pkg-config Summary

**CMake project builds libbmiwrfhydrof.so (4.9MB, 62 BMI symbols), installs to $CONDA_PREFIX with 2 .mod files and bmiwrfhydrof.pc, pkg-config discovery verified for babelizer compatibility**

## Performance

- **Duration:** 10 min
- **Started:** 2026-02-24T00:25:24Z
- **Completed:** 2026-02-24T00:36:05Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created CMakeLists.txt following bmi-example-fortran pattern with bmiwrfhydrof naming convention for babelizer compatibility
- Built libbmiwrfhydrof.so (4.9MB) with all 22 WRF-Hydro static libraries linked via --whole-archive, 62 BMI symbols exported
- Installed to conda prefix: .so in lib/, 2 .mod files in include/, .pc in lib/pkgconfig/
- pkg-config --libs bmiwrfhydrof returns `-lbmiwrfhydrof -lbmif`, pkg-config --modversion returns 1.0.0
- Zero unresolved symbols (ldd verified on both local and installed .so)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create CMakeLists.txt and pkg-config template** - `d941b13` (feat)
2. **Task 2: Build, install, and verify shared library via CMake** - `9f07016` (feat)

**Plan metadata:** `9a29bb6` (docs: complete plan)

## Files Created/Modified
- `bmi_wrf_hydro/CMakeLists.txt` - CMake project that builds libbmiwrfhydrof.so, installs it, and generates pkg-config file
- `bmi_wrf_hydro/bmiwrfhydrof.pc.cmake` - pkg-config template with Requires: bmif for babelizer Meson build discovery
- `bmi_wrf_hydro/src/hydro_stop_shim.f90` - Bare external hydro_stop wrapper delegating to module version (resolves --whole-archive dead code reference)

## Decisions Made
- Named library `bmiwrfhydrof` (not `wrfhydro_bmi` from pre-existing CMakeLists.txt) to match the bmi-example-fortran convention (`bmi{model}f`) which babelizer expects
- Recompile WRF-Hydro driver .F source files directly in CMake instead of linking pre-built .o files, because CMAKE_POSITION_INDEPENDENT_CODE=ON only applies to library targets (not the executable target those .o files came from)
- Use `--whole-archive` (not `--start-group/--end-group`) to ensure ALL symbols from static libraries are available in the .so for downstream consumers
- pkg-config `Requires: bmif` only (no separate WRF-Hydro .pc) because WRF-Hydro's 22 static libs are fully incorporated into our .so

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] WRF-Hydro executable .o files lack -fPIC**
- **Found during:** Task 2 (cmake --build)
- **Issue:** The plan specified linking `build_fpic/src/CMakeFiles/wrfhydro.dir/.../module_NoahMP_hrldas_driver.F.o` and `module_hrldas_netcdf_io.F.o` directly. These .o files have R_X86_64_PC32 relocations because CMake's POSITION_INDEPENDENT_CODE only applies to library targets, not the wrfhydro executable target they belong to.
- **Fix:** Changed CMakeLists.txt to include the WRF-Hydro `.F` source files directly in `add_library(SHARED ...)` instead of linking pre-built `.o` files. CMake recompiles them with `-fPIC` as part of the shared library target.
- **Files modified:** bmi_wrf_hydro/CMakeLists.txt
- **Verification:** cmake --build succeeds, ldd shows no unresolved symbols
- **Committed in:** 9f07016 (Task 2 commit)

**2. [Rule 3 - Blocking] Undefined bare `hydro_stop_` symbol from --whole-archive**
- **Found during:** Task 2 (cmake --build, test executable linking)
- **Issue:** `module_reservoir_routing.F90` contains `subroutine nwmCheck` which calls `hydro_stop()` without `use module_hydro_stop`, generating a bare `hydro_stop_` symbol reference. In normal WRF-Hydro builds, this dead code is excluded by selective linking. With `--whole-archive`, all object files are pulled in, exposing the unresolved reference.
- **Fix:** Created `src/hydro_stop_shim.f90` providing a bare external `hydro_stop` subroutine that delegates to the module version via `use module_hydro_stop`.
- **Files modified:** bmi_wrf_hydro/CMakeLists.txt, bmi_wrf_hydro/src/hydro_stop_shim.f90
- **Verification:** cmake --build succeeds for both .so and test executable, nm -D shows hydro_stop_ resolved
- **Committed in:** 9f07016 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking issues)
**Impact on plan:** Both fixes necessary to build the shared library. The plan's approach of linking pre-built .o files assumed they had -fPIC, and the --whole-archive approach exposed a dormant WRF-Hydro symbol resolution issue. No scope creep.

## Issues Encountered
- WSL2 clock skew warnings during cmake build ("Clock skew detected", "modification time in the future") -- harmless, known WSL2/NTFS issue documented in CLAUDE.md
- CMake output appears duplicated due to WSL2 buffering -- cosmetic only, build succeeds

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **Babelizer unblocked:** `pkg-config --libs bmiwrfhydrof` returns valid flags, the single requirement for babelizer to discover the library
- **Library installed:** libbmiwrfhydrof.so in $CONDA_PREFIX/lib/ with proper symlinks (.so -> .so.1 -> .so.1.0.0)
- **Module files installed:** bmiwrfhydrof.mod and wrfhydro_bmi_state_mod.mod in $CONDA_PREFIX/include/
- **No blockers:** All prerequisites for babelizer Phase 3 are satisfied

## Self-Check: PASSED

- FOUND: bmi_wrf_hydro/CMakeLists.txt
- FOUND: bmi_wrf_hydro/bmiwrfhydrof.pc.cmake
- FOUND: bmi_wrf_hydro/src/hydro_stop_shim.f90
- FOUND: $CONDA_PREFIX/lib/libbmiwrfhydrof.so
- FOUND: $CONDA_PREFIX/include/bmiwrfhydrof.mod
- FOUND: $CONDA_PREFIX/include/wrfhydro_bmi_state_mod.mod
- FOUND: $CONDA_PREFIX/lib/pkgconfig/bmiwrfhydrof.pc
- FOUND: d941b13 (Task 1 commit)
- FOUND: 9f07016 (Task 2 commit)

---
*Phase: 02-shared-library-install*
*Completed: 2026-02-24*
