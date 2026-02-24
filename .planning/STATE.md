# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-23)

**Core value:** WRF-Hydro must be callable from Python through a shared library -- gateway to Phase 2 (babelizer) and coupled simulations
**Current focus:** Phase 2: Shared Library + Install

## Current Position

Phase: 2 of 4 (Shared Library + Install)
Plan: 1 of 2 in current phase
Status: Plan 02-01 complete (build.sh --shared), Plan 02-02 next (CMake + pkg-config)
Last activity: 2026-02-24 -- Plan 02-01 complete (libbmiwrfhydrof.so via build.sh, 151/151 tests pass)

Progress: [####......] 37%

## Performance Metrics

**Velocity:**
- Total plans completed: 2
- Average duration: 6.5 min
- Total execution time: 0.2 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. fPIC Foundation | 1/1 | 6 min | 6 min |
| 2. Shared Library + Install | 1/2 | 7 min | 7 min |

**Recent Trend:**
- Last 5 plans: 01-01 (6 min), 02-01 (7 min)
- Trend: consistent ~6-7 min per plan

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

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 1 RESOLVED]: WRF-Hydro fPIC rebuild takes ~6 minutes on this WSL2 hardware (was estimated 5-30 min)
- [Phase 3]: Minimal C binding layer scope -- exactly which 8-10 BMI functions to wrap for Python test needs to be determined during Phase 3 planning
- [Phase 3]: mpi4py availability in wrfhydro-bmi env unknown -- affects MPI initialization strategy in Python test

## Session Continuity

Last session: 2026-02-24
Stopped at: Completed 02-01-PLAN.md (build.sh --shared producing libbmiwrfhydrof.so)
Resume file: None
