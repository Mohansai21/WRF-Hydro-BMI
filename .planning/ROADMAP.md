# Roadmap: WRF-Hydro BMI

## Milestones

- v1.0 **Shared Library** - Phases 1-4 (shipped 2026-02-24)
- v2.0 **Babelizer** - Phases 5-9 (in progress)

## Phases

<details>
<summary>v1.0 Shared Library (Phases 1-4) - SHIPPED 2026-02-24</summary>

- [x] **Phase 1: fPIC Foundation** - Rebuild WRF-Hydro static libraries with position-independent code
- [x] **Phase 2: Shared Library + Install** - CMake and build.sh producing libbmiwrfhydrof.so with conda install and pkg-config discovery
- [x] **Phase 3: Python Validation** - Minimal C bindings + Python ctypes test exercising BMI lifecycle against Croton NY data
- [x] **Phase 4: Documentation** - Doc 16 covering shared library architecture, babelizer readiness, and Python usage

### Phase 1: fPIC Foundation
**Goal**: WRF-Hydro's 22 static libraries are compiled with position-independent code, enabling them to be linked into a shared object
**Depends on**: Nothing (first phase)
**Requirements**: BUILD-01
**Success Criteria** (what must be TRUE):
  1. All 22 WRF-Hydro `.a` libraries are rebuilt with `-fPIC`
  2. The existing Fortran 151-test BMI suite still passes against the fPIC-rebuilt libraries
  3. `readelf -d` on a sample `.o` confirms PIC relocations are present
**Plans:** 1/1 plans complete
Plans:
- [x] 01-01: fPIC rebuild + 151-test regression

### Phase 2: Shared Library + Install
**Goal**: `libbmiwrfhydrof.so` builds, links all dependencies with no unresolved symbols, and installs to conda prefix with pkg-config discovery
**Depends on**: Phase 1
**Requirements**: BUILD-02, BUILD-03, BUILD-04, BUILD-05
**Success Criteria** (what must be TRUE):
  1. `cmake --build` produces `libbmiwrfhydrof.so` with zero unresolved symbols
  2. `build.sh --shared` produces the same library for fast dev iteration
  3. `cmake --install` places `.so`, `.mod`, and `.pc` files in `$CONDA_PREFIX`
  4. `pkg-config --libs bmiwrfhydrof` returns correct linker flags
  5. 151-test suite passes when linked against the shared library
**Plans:** 2/2 plans complete
Plans:
- [x] 02-01: build.sh --shared producing libbmiwrfhydrof.so
- [x] 02-02: CMake project, pkg-config, install, verify

### Phase 3: Python Validation
**Goal**: Python can load the shared library via ctypes and produce validated results matching the Fortran test suite
**Depends on**: Phase 2
**Requirements**: CBIND-01, CBIND-03, CBIND-04, PYTEST-01, PYTEST-02, PYTEST-03, PYTEST-04
**Success Criteria** (what must be TRUE):
  1. C binding layer exports `bind(C)` symbols for 8-10 key BMI functions
  2. Python ctypes test completes a full IRF cycle without segfault
  3. Croton NY streamflow values from Python match Fortran reference output
  4. MPI initialization handled correctly via `RTLD_GLOBAL`
  5. Grid sizes queried dynamically from BMI functions
**Plans:** 2/2 plans complete
Plans:
- [x] 03-01: C binding layer + build system updates
- [x] 03-02: Python pytest test + Croton NY validation

### Phase 4: Documentation
**Goal**: Complete reference documentation covering shared library architecture and babelizer readiness
**Depends on**: Phase 3
**Requirements**: DOC-01
**Success Criteria** (what must be TRUE):
  1. Doc 16 exists covering shared library build, babelizer readiness, C binding rationale, Python usage
  2. Doc follows project style
**Plans:** 1/1 plans complete
Plans:
- [x] 04-01: Write Doc 16

</details>

### v2.0 Babelizer (In Progress)

**Milestone Goal:** Babelize WRF-Hydro's shared library into a `pymt_wrfhydro` Python package, validated against Croton NY reference data and registered with PyMT.

- [x] **Phase 5: Library Hardening** - Rebuild libbmiwrfhydrof.so without conflicting C binding symbols and verify all prerequisites for babelization
- [x] **Phase 6: Babelizer Environment + Skeleton** - Install babelizer toolchain, write babel.toml, generate pymt_wrfhydro package skeleton
- [ ] **Phase 7: Package Build** - Build and install pymt_wrfhydro so it imports and runs from Python
- [ ] **Phase 8: BMI Compliance Validation** - Pass bmi-tester stages and validate Croton NY results from Python match Fortran reference
- [ ] **Phase 9: PyMT Integration** - Install PyMT, create metadata files, register WrfHydroBmi in PyMT model registry, write documentation

## Phase Details

### Phase 5: Library Hardening
**Goal**: The shared library is clean of conflicting C binding symbols, all module files are verified, and pkg-config discovery works -- making libbmiwrfhydrof.so ready for the babelizer's auto-generated interop layer
**Depends on**: Phase 4 (v1.0 complete)
**Requirements**: LIB-01, LIB-02, LIB-03, LIB-04
**Success Criteria** (what must be TRUE):
  1. `nm -D libbmiwrfhydrof.so | grep " T bmi_"` returns nothing (no conflicting C binding symbols exported)
  2. Both `bmiwrfhydrof.mod` and `wrfhydro_bmi_state_mod.mod` are verified present in `$CONDA_PREFIX/include/`
  3. `pkg-config --cflags --libs bmiwrfhydrof` returns correct flags pointing to the rebuilt library
  4. The existing 151-test Fortran suite passes against the rebuilt `.so` with no regressions
**Plans:** 2 plans

Plans:
- [x] 05-01-PLAN.md — Remove C binding layer, update build systems, rebuild + regression test + readiness check
- [x] 05-02-PLAN.md — Update CLAUDE.md and Doc 16 to reflect C binding removal

### Phase 6: Babelizer Environment + Skeleton
**Goal**: The babelizer toolchain is installed, babel.toml is written with the correct naming chain, and `babelize init` generates the complete pymt_wrfhydro package directory with all auto-generated files
**Depends on**: Phase 5
**Requirements**: ENV-01, ENV-02, ENV-03
**Success Criteria** (what must be TRUE):
  1. All 6 conda packages (babelizer, meson-python, meson, ninja, cython, python-build) are installed and importable
  2. `babel.toml` exists with correct naming chain (`library = "bmiwrfhydrof"`, `entry_point = "bmi_wrf_hydro"`, `package.name = "pymt_wrfhydro"`) and `mpi4py` in requirements
  3. `pymt_wrfhydro/` directory exists with all auto-generated files (bmi_interoperability.f90, .pyx, meson.build, pyproject.toml)
**Plans:** 1/1 plans complete

Plans:
- [x] 06-01-PLAN.md — Install babelizer toolchain, write babel.toml, generate pymt_wrfhydro skeleton, verify naming chain

### Phase 7: Package Build
**Goal**: pymt_wrfhydro is built, installed, and importable from Python, with the full initialize/update/finalize cycle working end-to-end against Croton NY data
**Depends on**: Phase 6
**Requirements**: BUILD-01, BUILD-02, BUILD-03, BUILD-04
**Success Criteria** (what must be TRUE):
  1. `pip install --no-build-isolation .` completes successfully inside pymt_wrfhydro/
  2. `from pymt_wrfhydro import WrfHydroBmi` imports without error in Python
  3. MPI is loaded correctly before the Cython extension imports libbmiwrfhydrof.so (no segfault from Open MPI plugin system)
  4. A Python script calling `initialize()` / `update()` / `finalize()` with Croton NY data runs to completion without error
**Plans:** 2 plans

Plans:
- [ ] 07-01-PLAN.md — Fix hydro_stop_ symbol, MPI bootstrap __init__.py, pip install + import validation
- [ ] 07-02-PLAN.md — End-to-end Croton NY validation with Fortran reference comparison (pytest + standalone)

### Phase 8: BMI Compliance Validation
**Goal**: The babelized pymt_wrfhydro passes official CSDMS bmi-tester validation and produces Croton NY results that match the Fortran reference output
**Depends on**: Phase 7
**Requirements**: VAL-01, VAL-02, VAL-03, VAL-04, VAL-05
**Success Criteria** (what must be TRUE):
  1. bmi-tester Stage 1 passes (component name, var names/counts, time functions)
  2. bmi-tester Stage 2 passes (var type/units/itemsize/nbytes/location for all 12 variables)
  3. bmi-tester Stage 3 passes (grid metadata + get_value for all 3 grid types including vector channel network)
  4. Croton NY channel streamflow values from Python match Fortran 151-test reference output within floating-point tolerance
  5. Expected non-implementations are documented with justification (get_value_ptr returns BMI_FAILURE, grid topology for rectilinear grids)
**Plans**: TBD

Plans:
- [ ] 08-01: TBD

### Phase 9: PyMT Integration
**Goal**: WrfHydroBmi is registered in the PyMT model registry with proper metadata, importable via `from pymt.models import WrfHydroBmi`, with complete documentation of the babelizer workflow
**Depends on**: Phase 8
**Requirements**: PYMT-01, PYMT-02, PYMT-03, PYMT-04
**Success Criteria** (what must be TRUE):
  1. PyMT is installed in the conda environment without breaking the babelizer toolchain
  2. `meta/WrfHydroBmi/` directory exists with 4 YAML files (info.yaml, api.yaml, parameters.yaml, run.yaml) and a template config file
  3. `from pymt.models import WrfHydroBmi` works in Python (PyMT model registry integration)
  4. Doc 18 exists in `bmi_wrf_hydro/Docs/` covering the complete babelizer workflow, babel.toml, build steps, bmi-tester results, and Python usage examples
**Plans**: TBD

Plans:
- [ ] 09-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 5 -> 6 -> 7 -> 8 -> 9

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. fPIC Foundation | v1.0 | 1/1 | Complete | 2026-02-23 |
| 2. Shared Library + Install | v1.0 | 2/2 | Complete | 2026-02-24 |
| 3. Python Validation | v1.0 | 2/2 | Complete | 2026-02-24 |
| 4. Documentation | v1.0 | 1/1 | Complete | 2026-02-24 |
| 5. Library Hardening | v2.0 | 2/2 | Complete | 2026-02-25 |
| 6. Babelizer Environment + Skeleton | v2.0 | Complete    | 2026-02-25 | 2026-02-25 |
| 7. Package Build | v2.0 | 0/? | Not started | - |
| 8. BMI Compliance Validation | v2.0 | 0/? | Not started | - |
| 9. PyMT Integration | v2.0 | 0/? | Not started | - |
