---
phase: 07-package-build
plan: 01
subsystem: build
tags: [shared-library, mpi, rtld-global, pip, pymt, cython, hydro-stop-shim]

# Dependency graph
requires:
  - phase: 06-babelizer-environment-skeleton
    provides: "pymt_wrfhydro skeleton with Cython extension and babel.toml"
provides:
  - "libbmiwrfhydrof.so with hydro_stop_ symbol resolved"
  - "pymt_wrfhydro installable via pip with MPI bootstrap"
  - "from pymt_wrfhydro import WrfHydroBmi works under mpirun"
affects: [07-02-PLAN, 08-python-validation, 09-pymt-integration]

# Tech tracking
tech-stack:
  added: [importlib.metadata, ctypes.RTLD_GLOBAL]
  patterns: [MPI-bootstrap-before-cython-load, hydro-stop-shim-linking]

key-files:
  created: []
  modified:
    - bmi_wrf_hydro/build.sh
    - pymt_wrfhydro/pymt_wrfhydro/__init__.py

key-decisions:
  - "hydro_stop_shim.f90 compiled with -fPIC and linked into .so to resolve bare external symbol from dead code in module_reservoir_routing.F90"
  - "RTLD_GLOBAL set before mpi4py import to prevent Open MPI 5.0.8 plugin segfaults when Cython extension loads libbmiwrfhydrof.so"
  - "Replaced pkg_resources with importlib.metadata for version retrieval (no deprecation warnings)"

patterns-established:
  - "MPI bootstrap pattern: setdlopenflags(RTLD_GLOBAL) -> mpi4py import -> restore flags -> Cython import"
  - "Shim object linking: hydro_stop_shim.o must be included in gfortran -shared alongside main .o files"

requirements-completed: [BUILD-01, BUILD-02, BUILD-03]

# Metrics
duration: 3min
completed: 2026-02-25
---

# Phase 7 Plan 01: Package Build Summary

**Resolved hydro_stop_ undefined symbol in libbmiwrfhydrof.so and added MPI RTLD_GLOBAL bootstrap to pymt_wrfhydro __init__.py for clean Python import under mpirun**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-25T18:14:47Z
- **Completed:** 2026-02-25T18:17:51Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Fixed hydro_stop_ undefined symbol by compiling hydro_stop_shim.f90 with -fPIC and linking into .so
- 151-test Fortran regression suite passes against rebuilt shared library
- Rewrote __init__.py with MPI bootstrap (RTLD_GLOBAL before Cython load) and importlib.metadata
- `pip install --no-build-isolation .` completes successfully
- `from pymt_wrfhydro import WrfHydroBmi` imports cleanly under mpirun with no segfaults

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix hydro_stop_ symbol in libbmiwrfhydrof.so and reinstall** - `12e53c6` (fix)
2. **Task 2: Modify __init__.py for MPI bootstrap, pip install, and verify import** - `74db1fc` (feat)

## Files Created/Modified
- `bmi_wrf_hydro/build.sh` - Added hydro_stop_shim.f90 compilation and linking in --shared mode
- `pymt_wrfhydro/pymt_wrfhydro/__init__.py` - MPI bootstrap with RTLD_GLOBAL, importlib.metadata, info() helper

## Decisions Made
- hydro_stop_shim.f90 was already in src/ but never compiled/linked into .so -- added to both Step 2a (compile) and Step 2b (link)
- Used importlib.metadata instead of pkg_resources for Python 3.10+ forward compatibility
- RTLD_GLOBAL flags restored after mpi4py import (minimal scope of flag change)
- Missing mpi4py raises ImportError with clear install instructions (hard error, not silent)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - both tasks completed on first attempt. Build succeeded, all 151 tests passed, pip install worked, and import verification under mpirun showed clean output with no warnings.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- pymt_wrfhydro is importable from Python under mpirun
- libbmiwrfhydrof.so has all symbols resolved
- Ready for Plan 07-02 (bmi-tester validation or further Python-side testing)
- Ready for Phase 8 (Python validation with live BMI calls)

## Self-Check: PASSED

All files verified present, all commit hashes found in git log.

---
*Phase: 07-package-build*
*Completed: 2026-02-25*
