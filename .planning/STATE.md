# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-23)

**Core value:** WRF-Hydro must be callable from Python through a shared library -- gateway to Phase 2 (babelizer) and coupled simulations
**Current focus:** Phase 2 complete, ready to plan Phase 3

## Current Position

Phase: 2 of 4 (Shared Library + Install) -- COMPLETE
Plan: 2 of 2 in current phase
Status: Phase 2 complete, all plans executed
Last activity: 2026-02-24 -- Plan 02-02 complete (CMake + pkg-config install, libbmiwrfhydrof.so in conda prefix)

Progress: [#####.....] 50%

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: 7.7 min
- Total execution time: 0.4 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. fPIC Foundation | 1/1 | 6 min | 6 min |
| 2. Shared Library + Install | 2/2 | 17 min | 8.5 min |

**Recent Trend:**
- Last 5 plans: 01-01 (6 min), 02-01 (7 min), 02-02 (10 min)
- Trend: consistent ~6-10 min per plan

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap v1]: 5 phases derived from 14 requirements across 4 categories (BUILD, CBIND, PYTEST, DOC)
- [Roadmap v1]: fPIC rebuild isolated as Phase 1 because it is the single prerequisite that blocks all other work
- [Roadmap v1]: C binding layer (Phase 2) before shared library build (Phase 3) because bmi_interop.f90 must exist before CMake can compile it into the .so
- [Research]: Babelizer auto-generates 818-line bmi_interoperability.f90 with full ISO_C_BINDING wrappers -- we do NOT write the full layer
- [Research]: register_bmi + box/opaque-handle pattern is NextGen-specific, NOT needed for PyMT/babelizer pathway
- [Research]: bmi-example-fortran (CSDMS reference) has NO C binding wrappers -- just .so + .pc file
- [Roadmap v2]: Descoped full C binding layer (old Phase 2); merged minimal test bindings into Python Validation phase
- [Roadmap v2]: 4 phases from 13 requirements (was 5 phases from 14); CBIND-02 removed, CBIND-01/03/04 revised to minimal scope
- [Roadmap v2]: Shared library build moves up to Phase 2 (was Phase 3) since C binding layer is no longer a prerequisite for the .so
- [Phase 1]: Used conda gfortran 14.3.0 for fPIC rebuild (aligns with BMI wrapper compiler, replaces system gfortran 13.3.0)
- [Phase 1]: 22 libraries (not 24 as research estimated) -- actual count matches original build exactly
- [Phase 1]: Added build_fpic/ to .gitignore since compiled artifacts should not be version-controlled
- [Phase 2]: Use gfortran -shared (not mpif90 -shared) for creating .so -- mpif90 wrapper can strip --whole-archive linker flags
- [Phase 2]: Recompile module_NoahMP_hrldas_driver.F and module_hrldas_netcdf_io.F with -fPIC -- CMake's POSITION_INDEPENDENT_CODE sets -fPIE for executable targets, -fPIC for library targets only
- [Phase 2]: Extract MPI linker flags via mpif90 --showme:link and pass directly to gfortran for shared library linking
- [Phase 2]: Library named bmiwrfhydrof (not wrfhydro_bmi) to follow bmi-example-fortran bmi{model}f convention required by babelizer
- [Phase 2]: Recompile WRF-Hydro driver .F source files directly in CMake add_library(SHARED) instead of linking pre-built .o files (CMAKE_POSITION_INDEPENDENT_CODE only for library targets)
- [Phase 2]: Created hydro_stop_shim.f90 to resolve bare hydro_stop_ symbol pulled in by --whole-archive from dead code in module_reservoir_routing.F90
- [Phase 2]: pkg-config Requires: bmif only (no WRF-Hydro .pc) because static libs baked into .so

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 1 RESOLVED]: WRF-Hydro fPIC rebuild takes ~6 minutes on this WSL2 hardware (was estimated 5-30 min)
- [Phase 3]: Minimal C binding layer scope -- exactly which 8-10 BMI functions to wrap for Python test needs to be determined during Phase 3 planning
- [Phase 3]: mpi4py availability in wrfhydro-bmi env unknown -- affects MPI initialization strategy in Python test

## Session Continuity

Last session: 2026-02-24
Stopped at: Completed 02-02-PLAN.md (Phase 2 complete: CMake install + pkg-config)
Resume file: None
