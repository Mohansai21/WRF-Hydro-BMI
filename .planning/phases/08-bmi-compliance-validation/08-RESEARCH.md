# Phase 8: BMI Compliance Validation — Research

**Completed:** 2026-02-25

## bmi-tester Architecture

### Tool Details
- **Package:** bmi-tester 0.5.9 (installed in wrfhydro-bmi conda env)
- **Executable:** `bmi-test` (NOT `bmi-tester`)
- **Entry point format:** `module:ClassName` → `pymt_wrfhydro:WrfHydroBmi`
- **Documentation:** https://bmi-tester.readthedocs.io/

### Command Syntax
```bash
mpirun --oversubscribe -np 1 bmi-test pymt_wrfhydro:WrfHydroBmi \
    --root-dir /path/to/WRF_Hydro_Run_Local/run/ \
    --config-file bmi_config.nml \
    -v
```

### 4 Test Stages (Sequential, Same Process)
Each stage is a separate `pytest.main()` call within the same process:

| Stage | Tests | What It Validates |
|-------|-------|-------------------|
| Bootstrap | 4 | has_initialize, has_finalize, initialize lifecycle, update lifecycle |
| Stage 1 | ~18 | Component name, var names/counts, start_time == 0.0, time_step, time_units |
| Stage 2 | ~72 | var_type, var_units (udunits2), var_itemsize, var_nbytes, var_location (per var) |
| Stage 3 | ~50-60 | Grid type/rank/size/shape/spacing/origin, grid x/y/z, get_value for outputs |

### Singleton Issue Analysis
bmi-tester calls `initialize()` ~8 times across all stages:
- Bootstrap: 2 init+finalize cycles on separate instances
- Stages 1-3: each stage's conftest does get_test_parameters() (init+query+finalize) + session fixture (init, no finalize)

**Our wrfhydro_initialize() singleton guard returns BMI_SUCCESS on re-init** (skips WRF-Hydro engine init, resets time tracking). This is safe because:
1. `wrfhydro_engine_initialized` flag prevents double engine init
2. `finalize()` only deallocates coupling placeholders + resets time — does NOT destroy WRF-Hydro module state
3. `bmi_interoperability.f90` allocates different model_array slots per instance, all sharing same module state

**Verdict: Singleton will work with bmi-tester.**

### tmpdir Staging Issue
Bootstrap copies manifest files to tmpdir and runs from there. With `--root-dir`, bmi-tester uses the actual directory. WRF-Hydro needs DOMAIN/, FORCING/, namelists in CWD. The BMI config uses `wrfhydro_run_dir` to set the working path.

**Mitigation:** Use `--root-dir` pointing to WRF_Hydro_Run_Local/run/ and BMI config with absolute path.

## Current BMI Function Analysis (Potential bmi-tester Issues)

### get_var_type() — SAFE
- Fortran returns `"double precision"` (line 780)
- Cython bridge converts via DTYPE_F_TO_PY dict: `"double precision"` → `"float64"`
- bmi-tester calls Python API, so conversion happens automatically
- **No fix needed**

### get_var_units() — NEEDS VERIFICATION
Current unit strings:
| Variable | Units String | UDUNITS2 Valid? |
|----------|-------------|----------------|
| channel_water__volume_flow_rate | `"m3 s-1"` | ✓ (space-separated exponents are valid) |
| land_surface_water__depth | `"m"` | ✓ |
| soil_water__volume_fraction | `"1"` | ✓ (udunits2 accepts "1" as dimensionless) |
| snowpack__liquid-equivalent_depth | `"mm"` | ✓ |
| land_surface_water__evaporation_volume_flux | `"mm"` | ✓ |
| land_surface_water__runoff_volume_flux | `"m"` | ✓ |
| soil_water__domain_time_integral_of_baseflow_volume_flux | `"mm"` | ✓ |
| land_surface_air__temperature | `"K"` | ✓ |
| atmosphere_water__precipitation_leq-volume_flux | `"mm s-1"` | ✓ |

**Risk: LOW** — udunits2 accepts these formats. gimli.units (available in env) will validate.

### get_start_time() — SAFE
Returns `0.0d0` (set in initialize at line 520). bmi-tester asserts `== approx(0.0)`. **PASS.**

### get_var_location() — SAFE
All variables return `"node"`. bmi-tester accepts `"node"`, `"edge"`, `"face"`, `"none"`. **PASS.**

### get_grid_type() — SAFE
- Grid 0 (LSM): `"uniform_rectilinear"` ✓
- Grid 1 (Routing): `"uniform_rectilinear"` ✓
- Grid 2 (Channel): `"vector"` ✓

### get_grid_x/y() — CONDITIONAL
- Grid 2 (vector): Returns CHLON/CHLAT arrays ✓
- Grids 0,1 (rectilinear): Returns BMI_FAILURE
- bmi-tester skips x/y tests for uniform_rectilinear grids ✓

### get_grid_edge_nodes/face_nodes() — CONDITIONAL
Returns BMI_FAILURE with -1 values. bmi-tester may skip for vector grids or expect failure.

### get_grid_spacing/origin/shape() — SAFE
- shape: [JX, IX] for both rectilinear grids ✓
- spacing: positive dx values ✓
- origin: [0.0, 0.0] ✓
- bmi-tester checks: all spacing > 0, all shape > 0

### get_value() — SAFE
Returns real data for all 8 output vars after update(). bmi-tester creates random buffer and checks it's changed.

### get_value_ptr() — EXPECTED FAILURE
Returns BMI_FAILURE (REAL4→double type mismatch). Documented as known non-implementation.

## Key Risks for Phase 8

| Risk | Severity | Mitigation |
|------|----------|------------|
| Singleton re-init during bmi-tester | Medium | Guard returns BMI_SUCCESS, finalize() is non-destructive → safe |
| tmpdir staging fails for large WRF-Hydro data | High | Use --root-dir to bypass tmpdir |
| Unit strings fail gimli validation | Low | udunits2 format should pass; fix if not |
| Grid 2 vector topology tests | Medium | edge_nodes/face_nodes return BMI_FAILURE; bmi-tester may skip or fail |
| MPI under bmi-test command | High | Must run under mpirun; Phase 7 MPI_Comm_dup fix handles pre-init |
| Config file path in tmpdir | Medium | Use absolute path in wrfhydro_run_dir |

## Recommended Plan Structure

**Plan 08-01: Run bmi-tester + fix failures + regression test**
- Run bmi-tester with --root-dir
- Diagnose and fix each failure category
- Rebuild .so + pymt_wrfhydro
- Re-run until all stages pass
- Run 151-test Fortran suite + 38 pytest for regression

**Plan 08-02: Full validation + documentation + validate.sh**
- Generate Fortran reference .npz for full Croton NY run
- Write comprehensive comparison test
- Write Doc 18 (compliance matrix + bmi-tester logs)
- Create validate.sh unified runner
- Commit all artifacts
