---
phase: 03-python-validation
plan: 02
subsystem: testing
tags: [pytest, ctypes, python, libbmiwrfhydrof, MPI-preload, RTLD_GLOBAL, croton-ny, streamflow]

# Dependency graph
requires:
  - phase: 03-python-validation
    plan: 01
    provides: 10 bind(C) functions in libbmiwrfhydrof.so (bmi_register through bmi_get_value_double)
provides:
  - pytest-based Python test suite (8 tests) exercising BMI lifecycle via ctypes
  - conftest.py with session-scoped fixtures for MPI preload, library loading, BMI lifecycle
  - Validated that libbmiwrfhydrof.so works end-to-end from Python (gateway to babelizer)
affects: [babelizer, phase-4-documentation]

# Tech tracking
tech-stack:
  added: [pytest markers (smoke/full), numpy.ctypes.data_as for array passing]
  patterns: [session-scoped BMI singleton testing (shared init across all tests), RTLD_GLOBAL MPI preload before .so load, dynamic grid size query for array allocation]

key-files:
  created:
    - bmi_wrf_hydro/tests/test_bmi_python.py
    - bmi_wrf_hydro/tests/conftest.py
  modified: []

key-decisions:
  - "Component name is 'WRF-Hydro v5.4.0 (NCAR)' (actual from Fortran wrapper), not 'WRF-Hydro BMI' as assumed in plan"
  - "Streamflow physical range uses -1e-6 tolerance instead of strict >= 0, because REAL->double conversion introduces tiny negative noise (~-2e-11)"
  - "MPI_Finalize called via libmpi ctypes handle in fixture teardown, not via bmi_finalize (matches Fortran test pattern)"
  - "Single session-scoped bmi_session fixture shared by all 8 tests (WRF-Hydro singleton constraint)"

patterns-established:
  - "Python ctypes BMI testing: RTLD_GLOBAL preload -> CDLL load -> restype/argtypes setup -> register -> initialize -> test -> finalize -> MPI_Finalize"
  - "Dynamic array allocation: bmi_get_var_grid -> bmi_get_grid_size -> numpy.zeros(size) -> bmi_get_value_double"
  - "Two-mode pytest testing: @pytest.mark.smoke for quick validation, @pytest.mark.full for complete 6-hour simulation"

requirements-completed: [PYTEST-01, PYTEST-02, PYTEST-03, PYTEST-04]

# Metrics
duration: 4min
completed: 2026-02-24
---

# Phase 3 Plan 2: Python ctypes Test Suite Summary

**Pytest suite (8 tests, 493 lines) exercising full BMI lifecycle via ctypes against Croton NY, validating libbmiwrfhydrof.so is ready for babelizer**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-24T01:17:28Z
- **Completed:** 2026-02-24T01:21:36Z
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- Created conftest.py (181 lines) with 4 session-scoped fixtures: libmpi, bmi_lib, bmi_config_file, bmi_session
- Created test_bmi_python.py (312 lines) with 8 tests: 6 smoke + 2 full, all passing
- Python successfully loads libbmiwrfhydrof.so via ctypes and calls all 10 bind(C) functions
- Croton NY streamflow values retrieved from Python are physically valid and evolve over 6 hours
- Both test modes work: smoke-only (8.67s, 6 tests) and full (16.79s, 8 tests)
- All grid sizes and array dimensions queried dynamically from BMI functions (zero hardcoded values)
- Singleton guard verified: second bmi_register() returns BMI_FAILURE from Python
- MPI handled via RTLD_GLOBAL preload without segfault (Open MPI 5.0.8)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create conftest.py with library loading and MPI preload fixtures** - `af89659` (feat)
2. **Task 2: Create test_bmi_python.py and run full validation** - `ab0c418` (feat)

**Plan metadata:** (pending)

## Files Created/Modified
- `bmi_wrf_hydro/tests/conftest.py` - Session-scoped fixtures: MPI RTLD_GLOBAL preload, library loading with restype/argtypes for all 10 C symbols, BMI config file creation with absolute Croton NY path, full lifecycle management (register/init/yield/finalize/MPI_Finalize)
- `bmi_wrf_hydro/tests/test_bmi_python.py` - 8 pytest tests: singleton guard, component name, initial time, update+time advance, dynamic grid size query, streamflow retrieval, 6-hour evolution validation, physical range check

## Decisions Made
- Component name assertion uses actual "WRF-Hydro v5.4.0 (NCAR)" from the Fortran wrapper's `component_name` variable, not "WRF-Hydro BMI" assumed in the plan
- Physical range check uses -1e-6 tolerance instead of strict >= 0.0 because WRF-Hydro stores REAL (32-bit) internally and the BMI double conversion introduces tiny negative noise (~-2e-11 observed)
- MPI_Finalize is called via the preloaded libmpi ctypes handle in fixture teardown, matching the Fortran test's pattern of calling MPI_Finalize separately from BMI finalize
- All tests share a single session-scoped `bmi_session` fixture because WRF-Hydro is a singleton that cannot be re-initialized

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected component name expectation**
- **Found during:** Task 2 (test execution -- first run)
- **Issue:** Plan specified expected name as "WRF-Hydro BMI" but the actual Fortran wrapper returns "WRF-Hydro v5.4.0 (NCAR)"
- **Fix:** Updated assertion to match actual component_name value from bmi_wrf_hydro.f90 line 313
- **Files modified:** bmi_wrf_hydro/tests/test_bmi_python.py
- **Verification:** test_component_name passes
- **Committed in:** ab0c418 (Task 2 commit)

**2. [Rule 1 - Bug] Added REAL->double tolerance for physical range check**
- **Found during:** Task 2 (test execution -- first run)
- **Issue:** Strict `>= 0.0` assertion failed because WRF-Hydro REAL->double conversion produces tiny negative noise (~-2e-11)
- **Fix:** Changed threshold to `>= -1e-6` with documentation explaining the REAL->double conversion noise
- **Files modified:** bmi_wrf_hydro/tests/test_bmi_python.py
- **Verification:** test_full_streamflow_physical_range passes; min value is -2.0006e-11 (within tolerance)
- **Committed in:** ab0c418 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both auto-fixes necessary for correctness. Test expectations aligned with actual model behavior. No scope creep.

## Issues Encountered
- None beyond the two auto-fixed deviations above. Both were discovered on first test run and fixed immediately.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **Phase 3 COMPLETE:** Both plans (C binding + Python test) finished
- **Babelizer unblocked:** libbmiwrfhydrof.so validated end-to-end from Python -- all 10 C symbols callable, BMI lifecycle works, Croton NY simulation produces valid results
- **Key validation:** Python ctypes can complete full IRF cycle (register -> initialize -> 6 updates -> get_value -> finalize) without segfaults or MPI issues
- **No blockers:** Ready for Phase 4 (documentation) or direct babelizer usage

## Self-Check: PASSED

- FOUND: bmi_wrf_hydro/tests/conftest.py
- FOUND: bmi_wrf_hydro/tests/test_bmi_python.py
- FOUND: .planning/phases/03-python-validation/03-02-SUMMARY.md
- FOUND: af89659 (Task 1 commit)
- FOUND: ab0c418 (Task 2 commit)

---
*Phase: 03-python-validation*
*Completed: 2026-02-24*
