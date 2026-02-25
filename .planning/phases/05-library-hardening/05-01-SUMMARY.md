---
phase: 05-library-hardening
plan: 01
subsystem: build
tags: [shared-library, c-binding, babelizer, fortran, pkg-config]

# Dependency graph
requires:
  - phase: 03-python-validation
    provides: libbmiwrfhydrof.so with C bindings and Python ctypes tests
provides:
  - Rebuilt libbmiwrfhydrof.so without C binding symbols (babelizer-safe)
  - Auto-install in build.sh --shared mode (copies .so + .mod to $CONDA_PREFIX)
  - Clean build systems (build.sh + CMakeLists.txt) with no C binding references
affects: [06-babelizer-env, 07-babelizer-build]

# Tech tracking
tech-stack:
  added: []
  patterns: [auto-install-on-shared-build, versioned-symlink-install]

key-files:
  created: []
  modified:
    - bmi_wrf_hydro/build.sh
    - bmi_wrf_hydro/CMakeLists.txt

key-decisions:
  - "Removed bmi_wrf_hydro_c.f90 entirely -- babelizer generates its own C interop layer"
  - "Auto-install added to build.sh --shared mode with versioned symlinks (1.0.0)"

patterns-established:
  - "build.sh --shared auto-installs .so + .mod to CONDA_PREFIX after tests pass"

requirements-completed: [LIB-01, LIB-02, LIB-03, LIB-04]

# Metrics
duration: 6min
completed: 2026-02-25
---

# Phase 5 Plan 1: C Binding Removal Summary

**Removed hand-written C binding layer (bmi_wrf_hydro_c.f90) from shared library, eliminating 10 duplicate bmi_* symbols that would conflict with babelizer's auto-generated C interop layer**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-25T03:58:43Z
- **Completed:** 2026-02-25T04:04:53Z
- **Tasks:** 2
- **Files modified:** 2 modified, 3 deleted

## Accomplishments
- Deleted bmi_wrf_hydro_c.f90 (335 lines), test_bmi_python.py (312 lines), conftest.py (181 lines)
- Rebuilt libbmiwrfhydrof.so with zero C binding symbols (nm -D confirms no `bmi_*` exports)
- 151-test suite passes in BOTH static and shared linking modes
- Auto-install to $CONDA_PREFIX added to build.sh --shared (versioned symlinks + .mod files)
- All 4 babelizer readiness checks pass (nm, .mod, pkg-config, ldd)

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete C binding files and update both build systems** - `a83e4a3` (feat)
2. **Task 2: Rebuild, regression test in both modes, and run composite readiness check** - no code changes (verification-only task, all tests pass)

## Files Created/Modified
- `bmi_wrf_hydro/src/bmi_wrf_hydro_c.f90` - DELETED (C binding layer, 335 lines)
- `bmi_wrf_hydro/tests/test_bmi_python.py` - DELETED (Python ctypes test, 312 lines)
- `bmi_wrf_hydro/tests/conftest.py` - DELETED (Python ctypes fixtures, 181 lines)
- `bmi_wrf_hydro/build.sh` - Removed C binding compilation/linking, added auto-install block
- `bmi_wrf_hydro/CMakeLists.txt` - Removed C binding source and .mod install rule

## Decisions Made
- Removed bmi_wrf_hydro_c.f90 entirely -- babelizer auto-generates its own C interop layer (bmi_interoperability.f90), making hand-written C bindings redundant and harmful (duplicate symbol errors)
- Auto-install to $CONDA_PREFIX added to build.sh --shared mode with versioned symlinks (so.1 -> so.1.0.0)
- Python ctypes tests deleted since they tested C bindings that no longer exist

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Verification Results

### Babelizer Readiness Check (4/4 PASS)
1. **No C symbols:** `nm -D libbmiwrfhydrof.so | grep " T bmi_"` returns nothing
2. **.mod files present:** bmiwrfhydrof.mod + wrfhydro_bmi_state_mod.mod in $CONDA_PREFIX/include/
3. **pkg-config:** Returns `-I.../include -L.../lib -lbmiwrfhydrof -lbmif`
4. **ldd:** No missing dependencies

### Test Results
- Static mode: 151/151 tests pass, 0 failures
- Shared mode: 151/151 tests pass, 0 failures (linked against libbmiwrfhydrof.so)
- Minimal smoke test: PASS in both modes

## Next Phase Readiness
- libbmiwrfhydrof.so is clean (no C symbol conflicts) and ready for babelization
- pkg-config returns correct flags for babelizer's Meson build
- Both .mod files installed for Fortran module resolution
- Ready for Phase 5 Plan 2 (if any) or Phase 6 (babelizer environment setup)

## Self-Check: PASSED

- FOUND: 05-01-SUMMARY.md
- CONFIRMED DELETED: bmi_wrf_hydro_c.f90
- CONFIRMED DELETED: test_bmi_python.py
- CONFIRMED DELETED: conftest.py
- FOUND: commit a83e4a3
- FOUND: libbmiwrfhydrof.so (build dir)
- FOUND: libbmiwrfhydrof.so.1.0.0 (installed at $CONDA_PREFIX/lib/)

---
*Phase: 05-library-hardening*
*Completed: 2026-02-25*
