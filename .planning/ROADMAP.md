# Roadmap: WRF-Hydro BMI Shared Library

## Overview

This roadmap delivers `libwrfhydrobmi.so` -- a shared library that makes WRF-Hydro discoverable by the CSDMS babelizer, which will auto-generate the full Python binding layer. The work starts with rebuilding WRF-Hydro's 22 static libraries with position-independent code (`-fPIC`), then builds and installs the shared library via CMake with pkg-config discovery (the only deliverable the babelizer actually needs), validates the Python-to-Fortran chain with a minimal ctypes test using a lightweight C binding layer (~100-200 lines of test infrastructure, NOT the full 41-function interop layer the babelizer generates automatically), and closes with project documentation. Each phase delivers a verifiable capability that unblocks the next.

**Key insight from research:** The babelizer auto-generates an 818-line `bmi_interoperability.f90` with full ISO_C_BINDING wrappers for all 41 BMI functions. We do NOT write that layer. Our deliverable is the shared library + pkg-config file. The minimal C binding layer in Phase 3 is purely test infrastructure to validate the .so before handing it off to the babelizer.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: fPIC Foundation** - Rebuild WRF-Hydro static libraries with position-independent code
- [x] **Phase 2: Shared Library + Install** - CMake and build.sh producing libwrfhydrobmi.so with conda install and pkg-config discovery
- [ ] **Phase 3: Python Validation** - Minimal C bindings + Python ctypes test exercising BMI lifecycle against Croton NY data
- [ ] **Phase 4: Documentation** - Doc 16 covering shared library architecture, babelizer readiness, and Python usage

## Phase Details

### Phase 1: fPIC Foundation
**Goal**: WRF-Hydro's 22 static libraries are compiled with position-independent code, enabling them to be linked into a shared object
**Depends on**: Nothing (first phase)
**Requirements**: BUILD-01
**Success Criteria** (what must be TRUE):
  1. All 22 WRF-Hydro `.a` libraries are rebuilt with `-fPIC` (`CMAKE_POSITION_INDEPENDENT_CODE=ON`)
  2. The existing Fortran 151-test BMI suite still passes against the fPIC-rebuilt libraries (no regression)
  3. `readelf -d` or `objdump` on a sample `.o` confirms PIC relocations are present
**Plans:** 1/1 plans complete
Plans:
- [x] 01-01-PLAN.md -- Create rebuild_fpic.sh + update build.sh --fpic + execute fPIC rebuild + verify 151-test regression

### Phase 2: Shared Library + Install
**Goal**: `libwrfhydrobmi.so` builds, links all dependencies with no unresolved symbols, and installs to conda prefix with pkg-config discovery -- making the library babelizer-ready
**Depends on**: Phase 1
**Requirements**: BUILD-02, BUILD-03, BUILD-04, BUILD-05
**Success Criteria** (what must be TRUE):
  1. `cmake --build` produces `libwrfhydrobmi.so` with zero unresolved symbols (`ldd` shows no "not found" entries)
  2. `build.sh` produces the same `libwrfhydrobmi.so` via `-shared` flag for fast dev iteration
  3. `cmake --install` places `libwrfhydrobmi.so` in `$CONDA_PREFIX/lib/`, both `.mod` files (`bmiwrfhydrof.mod`, `wrfhydro_bmi_state_mod.mod`) in `$CONDA_PREFIX/include/`, and `.pc` file in `$CONDA_PREFIX/lib/pkgconfig/`
  4. `pkg-config --libs bmiwrfhydrof` returns correct linker flags (babelizer's Meson build will use this for `dependency('bmiwrfhydrof', method: 'pkg-config')`)
  5. The existing Fortran 151-test BMI suite still passes when linked against the shared library instead of static objects (no regression)
**Plans:** 2 plans
Plans:
- [x] 02-01-PLAN.md -- Add --shared flag to build.sh producing libbmiwrfhydrof.so with 151-test regression
- [x] 02-02-PLAN.md -- Create CMake project, pkg-config template, build/install/verify shared library

### Phase 3: Python Validation
**Goal**: Python can load the shared library via ctypes, exercise key BMI functions through a minimal C binding layer, and produce validated results matching the Fortran test suite -- proving the .so works end-to-end before handing it to the babelizer
**Depends on**: Phase 2
**Requirements**: CBIND-01, CBIND-03, CBIND-04, PYTEST-01, PYTEST-02, PYTEST-03, PYTEST-04
**Success Criteria** (what must be TRUE):
  1. `bmi_wrf_hydro_c.f90` (~100-200 lines) compiles into the shared library and exports `bind(C)` symbols for 8-10 key BMI functions (verified via `nm -D libwrfhydrobmi.so | grep bmi_`)
  2. Python ctypes test loads `libwrfhydrobmi.so` and completes a full IRF cycle: `register_bmi` -> `initialize` -> `update` (6 hours of simulation) -> `get_value` -> `finalize` without segfault or error
  3. Croton NY channel streamflow values retrieved via Python match the Fortran 151-test suite reference output (within floating-point tolerance)
  4. MPI initialization is handled correctly (via `RTLD_GLOBAL` preload of `libmpi.so`) without segfault
  5. Grid sizes and array dimensions are queried dynamically from BMI functions (`get_grid_size`, `get_var_nbytes`) -- no hardcoded Croton NY dimensions in the test
**Plans:** 2 plans
Plans:
- [x] 03-01-PLAN.md -- Create bmi_wrf_hydro_c.f90 with bind(C) wrappers + update build systems + verify C symbols
- [ ] 03-02-PLAN.md -- Create Python pytest test with smoke and full modes + validate Croton NY results

### Phase 4: Documentation
**Goal**: Complete reference documentation covering the shared library architecture, babelizer readiness, minimal C binding rationale, and Python usage
**Depends on**: Phase 3
**Requirements**: DOC-01
**Success Criteria** (what must be TRUE):
  1. Doc 16 exists in `bmi_wrf_hydro/Docs/` covering: shared library build (CMake + build.sh), babelizer readiness checklist (what we deliver vs what babelizer generates), minimal C binding rationale (test infrastructure vs production interop), Python ctypes usage, and troubleshooting
  2. Doc follows project style (emojis, ASCII/Mermaid diagrams, ML analogies, detailed explanations)
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. fPIC Foundation | 1/1 | Complete    | 2026-02-23 |
| 2. Shared Library + Install | 2/2 | Complete | 2026-02-24 |
| 3. Python Validation | 1/2 | In Progress | - |
| 4. Documentation | 0/? | Not started | - |
