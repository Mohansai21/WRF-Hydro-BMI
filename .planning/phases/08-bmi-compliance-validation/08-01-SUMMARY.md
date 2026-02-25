---
phase: 08-bmi-compliance-validation
plan: 01
subsystem: testing
tags: [bmi-tester, compliance, validation, pytest, regression, pymt_wrfhydro]

# Dependency graph
requires:
  - phase: 07-package-build
    provides: pymt_wrfhydro installed and importable from Python
provides:
  - bmi-tester validation results (118 passed, 40 skipped, 1 bmi-tester bug)
  - run_bmi_tester.py wrapper with rootdir fix for bmi-tester 0.5.9
  - Full regression verification (151 Fortran + 38 Python + E2E standalone)
affects: [08-02-documentation, 09-pymt-integration]

# Tech tracking
tech-stack:
  added: [bmi-tester 0.5.9, gimli udunits2]
  patterns: [monkey-patch check_bmi for rootdir injection, manifest staging for WRF-Hydro singleton]

key-files:
  created:
    - bmi_wrf_hydro/tests/run_bmi_tester.py
    - WRF_Hydro_Run_Local/run/bmi_config.nml
    - WRF_Hydro_Run_Local/run/bmi_manifest.txt
    - WRF_Hydro_Run_Local/run/bmi_staging/bmi_config.nml
  modified: []

key-decisions:
  - "No BMI wrapper changes needed -- all bmi-tester stages pass except one bmi-tester bug"
  - "Grid 2 type stays 'vector' (correct per BMI spec); bmi-tester 0.5.9 has unhandled branch for vector grids"
  - "Monkey-patch check_bmi with --rootdir to fix conftest discovery when CWD differs from test tree"
  - "Manifest staging directory with only bmi_config.nml avoids copying DOMAIN/FORCING dirs to tmpdir"

patterns-established:
  - "run_bmi_tester.py: bmi-tester wrapper that patches conftest discovery for external CWD"
  - "bmi_staging/ directory pattern for minimal file manifest"

requirements-completed: [VAL-01, VAL-02, VAL-03, VAL-05]

# Metrics
duration: 9min
completed: 2026-02-25
---

# Phase 8 Plan 01: Run bmi-tester + Fix Failures + Regression Test Summary

**bmi-tester 0.5.9 passes 118/159 tests (40 skipped, 1 bmi-tester bug) with zero BMI wrapper changes needed; 151 Fortran + 38 Python + E2E standalone regression suites all green**

## Performance

- **Duration:** 9 min
- **Started:** 2026-02-25T20:19:52Z
- **Completed:** 2026-02-25T20:29:31Z
- **Tasks:** 8 (Tasks 4-5 skipped -- no fixes needed)
- **Files created:** 4

## Accomplishments
- All 4 bmi-tester stages run successfully (bootstrap + stages 1-3)
- 118 tests passed across all stages with no BMI wrapper or Cython bridge changes
- Single failure is a bmi-tester 0.5.9 bug (UnboundLocalError for "vector" grid type in test_grid_x)
- Created run_bmi_tester.py wrapper that fixes conftest discovery issue
- Full regression verified: 151 Fortran + 38 Python pytest + E2E standalone all pass

## bmi-tester Results Summary

| Stage | Passed | Skipped | Failed | Notes |
|-------|--------|---------|--------|-------|
| Bootstrap | 2 | 2 | 0 | test_initialize/test_update skipped (bmi-tester dependency names) |
| Stage 1 (Info+Time) | 16 | 6 | 0 | get_input_var_name_count skipped (BMI 2.0 uses get_input_item_count) |
| Stage 2 (Variables) | 66 | 0 | 0 | All 11 vars: type, units, itemsize, nbytes, location, grid |
| Stage 3 (Grids+Values) | 34 | 32 | 1 | 1 fail = bmi-tester bug for "vector" grid type |
| **Total** | **118** | **40** | **1** | 1 failure is bmi-tester limitation, not our code |

### Bootstrap Details (2 passed, 2 skipped)
- PASSED: test_has_initialize, test_has_finalize
- SKIPPED: test_initialize, test_update (dependency names mismatch in bmi-tester)

### Stage 1 Details (16 passed, 6 skipped)
- PASSED: get_component_name, 11 var_names, get_start_time, get_time_step, time_units_is_str, time_units_is_valid
- SKIPPED: input/output_var_name_count (deprecated API), get_input/output_var_names (dependency), get_current_time (dependency), get_end_time (skipped by bmi-tester)

### Stage 2 Details (66 passed)
- All 11 variables (8 output + 3 input) tested for: itemsize, nbytes, location, var_on_grid, type, units
- Unit strings validated by gimli/udunits2: "m3 s-1", "m", "1", "mm", "K", "mm s-1" all accepted

### Stage 3 Details (34 passed, 32 skipped, 1 failed)
- PASSED: grid rank/size/type for all 3 grids, shape/spacing/origin for grids 0+1, get_value for all 8 output vars, get_var_location for all 11 vars
- SKIPPED: unstructured topology tests (grids 0+1 = uniform_rectilinear), grid x/y/z for grids 0+1 (uniform_rectilinear), set_input_values (marked "too dangerous" by bmi-tester)
- FAILED: test_grid_x[2] -- bmi-tester doesn't handle "vector" grid type in size calculation (UnboundLocalError)

### The Single Failure: test_grid_x[2]
- **Root cause:** bmi-tester's `grid_unstructured_test.py::test_grid_x` only handles "unstructured" and "rectilinear" grid types. Our grid 2 returns "vector" (correct per BMI spec). The variable `size` is never assigned, causing UnboundLocalError.
- **Our grid type is correct:** "vector" is in bmi-tester's own VALID_GRID_TYPES list
- **Resolution:** Document as bmi-tester limitation. No wrapper changes.

## Task Commits

Each task was committed atomically:

1. **Tasks 1-3: bmi-tester config + runner + diagnostic** - `98c3245` (feat)
2. **Tasks 4-5: Fix wrapper + rebuild** - SKIPPED (no fixes needed)
3. **Tasks 6-8: Validation + regression + logs** - `a147be1` (docs)

## Files Created/Modified
- `bmi_wrf_hydro/tests/run_bmi_tester.py` - bmi-tester wrapper with rootdir monkey-patch
- `WRF_Hydro_Run_Local/run/bmi_config.nml` - BMI config for bmi-tester (gitignored)
- `WRF_Hydro_Run_Local/run/bmi_manifest.txt` - Minimal manifest for tmpdir staging (gitignored)
- `WRF_Hydro_Run_Local/run/bmi_staging/` - Staging directory with only config file (gitignored)
- `.planning/phases/08-bmi-compliance-validation/bmi-tester-output.txt` - Full bmi-tester output

## Decisions Made
- No BMI wrapper changes needed -- bmi-tester validates our implementation as-is
- Grid 2 type remains "vector" (correct per BMI 2.0 spec for 1D channel networks)
- Monkey-patch approach chosen over modifying bmi-tester source or creating conftest proxy
- Manifest staging directory avoids copying WRF-Hydro's large DOMAIN/FORCING dirs to tmpdir

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] bmi-tester conftest discovery failure**
- **Found during:** Task 2 (first diagnostic run)
- **Issue:** bmi-tester 0.5.9 passes test directories to pytest.main() without --rootdir, causing conftest.py to not be discovered when CWD is a different filesystem tree
- **Fix:** Created run_bmi_tester.py that monkey-patches check_bmi to inject --rootdir for proper conftest discovery
- **Files created:** bmi_wrf_hydro/tests/run_bmi_tester.py
- **Verification:** All stages run with fixtures properly resolved
- **Committed in:** 98c3245

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking issue)
**Impact on plan:** Necessary workaround for bmi-tester conftest discovery. No scope creep.

## Issues Encountered
- Bootstrap test_initialize and test_update are skipped due to bmi-tester's dependency marker name mismatch (depends on "has_initialize" but test is named "test_has_initialize")
- Stage 1 get_input_var_name_count skipped because our wrapper uses BMI 2.0 `get_input_item_count` (bmi-tester tests both old and new API names)
- These are all bmi-tester version 0.5.9 quirks, not our code issues

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- bmi-tester validation complete (118 passed, 1 bmi-tester bug)
- Ready for Plan 08-02: Full Croton NY validation + Doc 18 + validate.sh
- All regression suites verified green (no regressions from any phase)

---
*Phase: 08-bmi-compliance-validation*
*Completed: 2026-02-25*
