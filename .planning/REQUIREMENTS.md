# Requirements: WRF-Hydro BMI Babelizer

**Defined:** 2026-02-24
**Core Value:** WRF-Hydro must be controllable from Python via PyMT — babelize init must produce a working pymt_wrfhydro package

## v1 Requirements

Requirements for the babelizer milestone. Each maps to roadmap phases.

### Library Hardening

- [x] **LIB-01**: `libbmiwrfhydrof.so` rebuilt WITHOUT `bmi_wrf_hydro_c.o` to remove conflicting C binding symbols (`nm -D` shows no `bmi_` exports)
- [x] **LIB-02**: Both `.mod` files (`bmiwrfhydrof.mod` + `wrfhydro_bmi_state_mod.mod`) verified installed in `$CONDA_PREFIX/include/`
- [x] **LIB-03**: `pkg-config --cflags --libs bmiwrfhydrof` returns correct flags after rebuild
- [x] **LIB-04**: Existing 151-test Fortran suite still passes against rebuilt `.so` (no regression)

### Environment & Configuration

- [x] **ENV-01**: 6 conda packages installed: babelizer, meson-python, meson, ninja, cython, python-build
- [x] **ENV-02**: `babel.toml` written with correct naming chain: `library = "bmiwrfhydrof"`, `entry_point = "bmi_wrf_hydro"`, `package.name = "pymt_wrfhydro"`, `mpi4py` in requirements
- [x] **ENV-03**: `babelize init babel.toml` generates `pymt_wrfhydro/` directory with all auto-generated files (bmi_interoperability.f90, .pyx, meson.build, pyproject.toml)

### Package Build

- [x] **BUILD-01**: `pip install --no-build-isolation .` completes successfully inside `pymt_wrfhydro/`
- [x] **BUILD-02**: `from pymt_wrfhydro import WrfHydroBmi` imports without error in Python
- [x] **BUILD-03**: MPI compatibility handled (mpi4py import before pymt_wrfhydro loads libmpi with RTLD_GLOBAL)
- [x] **BUILD-04**: Initialize/update/finalize cycle works end-to-end from Python with Croton NY data

### BMI Validation

- [x] **VAL-01**: bmi-tester Stage 1 passes (component name, var names/counts, time functions)
- [x] **VAL-02**: bmi-tester Stage 2 passes (var type/units/itemsize/nbytes/location for all 12 variables)
- [x] **VAL-03**: bmi-tester Stage 3 passes (grid metadata + get_value for all 3 grid types)
- [x] **VAL-04**: Croton NY channel streamflow values from Python match Fortran 151-test reference output (within floating-point tolerance)
- [x] **VAL-05**: Expected non-implementations documented (get_value_ptr returns BMI_FAILURE, etc.)

### PyMT Integration

- [ ] **PYMT-01**: PyMT installed in conda env (`conda install pymt`)
- [ ] **PYMT-02**: `meta/WrfHydroBmi/` directory with 4 YAML files (info.yaml, api.yaml, parameters.yaml, run.yaml) + template config
- [ ] **PYMT-03**: `from pymt.models import WrfHydroBmi` works (PyMT model registry)
- [ ] **PYMT-04**: Documentation (Doc 18) covering babelizer workflow, babel.toml, build steps, bmi-tester results, Python usage

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Extended Integration

- **EXT-01**: conda-forge recipe (`meta.yaml`) for `conda install pymt_wrfhydro`
- **EXT-02**: Full `parameters.yaml` covering all WRF-Hydro namelist options (200+)
- **EXT-03**: Example Jupyter notebook showing full IRF cycle with Croton NY
- **EXT-04**: Automated CI/CD (GitHub Actions) for pymt_wrfhydro

### NextGen Compatibility

- **NGEN-01**: Full `iso_c_bmi.f90` with ISO_C_BINDING `bind(C)` wrappers for all 41 BMI functions
- **NGEN-02**: `register_bmi()` with box/opaque-handle pattern for NOAA NextGen
- **NGEN-03**: `#ifdef NGEN_ACTIVE` guard for NextGen-specific code paths

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| SCHISM babelization | SCHISM BMI targets NextGen, not PyMT pathway |
| PyMT coupling (WRF-Hydro + SCHISM) | Phase 4 of overall project; requires both models babelized |
| MPI parallel execution (np > 1) | Serial-first; babelizer does not handle MPI process management |
| Multi-instance support | WRF-Hydro module globals prevent multiple instances |
| `get_value_ptr` from Python | WRF-Hydro REAL vs BMI double mismatch; PyMT falls back to get_value |
| Modifying WRF-Hydro source code | BMI is non-invasive by design |
| Windows/Mac builds | WSL2 Linux is target; WRF-Hydro deps are Linux-only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| LIB-01 | Phase 5 | Complete |
| LIB-02 | Phase 5 | Complete |
| LIB-03 | Phase 5 | Complete |
| LIB-04 | Phase 5 | Complete |
| ENV-01 | Phase 6 | Complete |
| ENV-02 | Phase 6 | Complete |
| ENV-03 | Phase 6 | Complete |
| BUILD-01 | Phase 7 | Complete |
| BUILD-02 | Phase 7 | Complete |
| BUILD-03 | Phase 7 | Complete |
| BUILD-04 | Phase 7 | Complete |
| VAL-01 | Phase 8 | Complete |
| VAL-02 | Phase 8 | Complete |
| VAL-03 | Phase 8 | Complete |
| VAL-04 | Phase 8 | Complete |
| VAL-05 | Phase 8 | Complete |
| PYMT-01 | Phase 9 | Pending |
| PYMT-02 | Phase 9 | Pending |
| PYMT-03 | Phase 9 | Pending |
| PYMT-04 | Phase 9 | Pending |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-02-24*
*Last updated: 2026-02-24 after roadmap creation (all 20 requirements mapped to Phases 5-9)*
