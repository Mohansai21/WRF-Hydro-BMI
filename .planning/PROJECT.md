# WRF-Hydro BMI Shared Library

## What This Is

A shared library (`libwrfhydro_bmi.so`) that packages the existing WRF-Hydro BMI wrapper for use from Python and other languages. This builds on the completed Phase 1 BMI wrapper (bmi_wrf_hydro.f90, 151/151 tests passing) by adding ISO_C_BINDING interoperability wrappers, a CMake-based shared library build, and Python verification — making WRF-Hydro controllable from Python via ctypes/cffi.

## Core Value

WRF-Hydro must be callable from Python through a shared library — this is the gateway to Phase 2 (babelizer) and ultimately to coupled WRF-Hydro + SCHISM simulations from a Jupyter Notebook.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ BMI wrapper implements all 41 BMI functions — existing (`bmi_wrf_hydro/src/bmi_wrf_hydro.f90`, ~1919 lines)
- ✓ 151-test suite passes for all BMI categories — existing (`bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90`)
- ✓ 8 output + 4 input variables exposed via CSDMS Standard Names — existing
- ✓ 3 grid types (1km LSM, 250m routing, vector channel) all tested — existing
- ✓ Initialize-Run-Finalize pattern working with WRF-Hydro (Croton NY, 6hr) — existing
- ✓ build.sh compiles + links against 22 WRF-Hydro libraries — existing
- ✓ CMakeLists.txt configured for shared library build — existing (650 lines)
- ✓ Minimal smoke test (init + 6 updates + finalize) — existing

### Active

<!-- Current scope. Building toward these. -->

- [ ] ISO_C_BINDING wrapper functions exposing all 41 BMI procedures as C-callable
- [ ] libwrfhydro_bmi.so builds and links successfully via CMake
- [ ] libwrfhydro_bmi.so builds via updated build.sh (dev builds)
- [ ] Python test script exercises most BMI functions via ctypes/cffi
- [ ] Python test runs against Croton NY test case and validates results
- [ ] Detailed documentation covering shared library build, C bindings, and Python usage

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Babelizer integration (babel.toml, pymt_wrfhydro) — that's Phase 2, depends on working .so first
- PyMT plugin registration — Phase 3, depends on babelizer
- SCHISM coupling — Phase 4, depends on both models being babelized
- MPI parallel execution — serial mode only (np=1), following SCHISM's approach
- Modifying WRF-Hydro source code — BMI is non-invasive by design
- Full bmi-tester compliance — nice to have later, not blocking shared library

## Context

- **Existing codebase:** WRF-Hydro v5.4.0 compiled, BMI wrapper complete (Phase 1 done)
- **Test infrastructure:** Croton NY test case (Hurricane Irene 2011, 6hr run) at `WRF_Hydro_Run_Local/run/`
- **Reference implementation:** bmi-example-fortran has working C bindings pattern (`bmi_heat/bmi_interoperability.f90`)
- **SCHISM BMI reference:** LynkerIntel/SCHISM_BMI (bmischism.f90) uses ISO_C_BINDING for NextGen
- **CMakeLists.txt:** Already written (650 lines), finds all 22 WRF-Hydro libs, BMI, MPI, NetCDF
- **Build environment:** conda wrfhydro-bmi (gfortran 14.3.0, OpenMPI 5.0.8, bmi-fortran 2.0.3)
- **ISO_C_BINDING status:** Not yet in bmi_wrf_hydro.f90 — needs C-interoperable wrapper procedures
- **Key pattern:** bmi-example-fortran separates Fortran BMI implementation from C binding wrappers

## Constraints

- **Tech stack**: Fortran 2003 with ISO_C_BINDING for C interop, Python ctypes/cffi for testing — must work with gfortran 14.3.0
- **Compatibility**: Shared library must link against same 22 WRF-Hydro static libraries as current build
- **Non-invasive**: Zero changes to WRF-Hydro source code (`wrf_hydro_nwm_public/`)
- **Serial only**: MPI required for linking but execution is single-process (`mpirun -np 1`)
- **Test data**: Croton NY test case required in `WRF_Hydro_Run_Local/run/` — Python test uses same data
- **Platform**: WSL2 Linux (long path issues with Fortran `character(len=80)`)

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| CMake as primary build + keep build.sh | CMake needed for babelizer (Phase 2), build.sh for fast dev iteration | — Pending |
| Python test via ctypes/cffi (not babelizer) | Verify .so works before adding babelizer complexity | — Pending |
| Follow bmi-example-fortran C binding pattern | Proven pattern in CSDMS ecosystem, babelizer expects it | — Pending |
| Full documentation in Docs/ | User preference for detailed docs with emojis, diagrams, ML analogies | — Pending |

---
*Last updated: 2026-02-23 after initialization*
