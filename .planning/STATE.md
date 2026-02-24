# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-23)

**Core value:** WRF-Hydro must be callable from Python through a shared library -- gateway to Phase 2 (babelizer) and coupled simulations
**Current focus:** All 4 phases COMPLETE -- shared library milestone delivered

## Current Position

Phase: 4 of 4 (Documentation) -- COMPLETE
Plan: 1 of 1 in current phase -- COMPLETE
Status: All phases complete. Shared library milestone delivered. Doc 16 written (1,427 lines).
Last activity: 2026-02-24 -- Phase 4 execution complete (Doc 16 created)

Progress: [##########] 100%

## Performance Metrics

**Velocity:**
- Total plans completed: 6
- Average duration: 6.7 min
- Total execution time: 0.7 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. fPIC Foundation | 1/1 | 6 min | 6 min |
| 2. Shared Library + Install | 2/2 | 17 min | 8.5 min |
| 3. Python Validation | 2/2 | 9 min | 4.5 min |
| 4. Documentation | 1/1 | 8 min | 8 min |

**Recent Trend:**
- Last 6 plans: 01-01 (6 min), 02-01 (7 min), 02-02 (10 min), 03-01 (5 min), 03-02 (4 min), 04-01 (8 min)
- Trend: consistent ~5-10 min per plan

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
- [Phase 3]: Singleton C binding pattern (module-level the_model + is_registered guard) -- WRF-Hydro cannot support multiple instances
- [Phase 3]: f_to_c_string as subroutine with buffer length parameter (not function returning array) -- prevents stack overflow with large strings
- [Phase 3]: Character-by-character copy in c_to_f_string instead of transfer() -- avoids compiler-specific issues
- [Phase 3]: bmi_get_component_name takes buffer size n as integer(c_int), value -- follows C calling convention
- [Phase 3]: Component name is 'WRF-Hydro v5.4.0 (NCAR)' (actual from Fortran wrapper), not 'WRF-Hydro BMI' as assumed
- [Phase 3]: Streamflow physical range uses -1e-6 tolerance (not strict >= 0) for REAL->double conversion noise (~-2e-11)
- [Phase 3]: MPI_Finalize called via libmpi ctypes handle in fixture teardown, not via bmi_finalize
- [Phase 3]: Single session-scoped bmi_session fixture shared by all 8 tests (WRF-Hydro singleton constraint)
- [Phase 4]: Doc 16 is self-contained -- reader can understand shared library milestone without reading all 15 prior docs
- [Phase 4]: Babelizer readiness checklist has 7 runnable verification commands with expected outputs
- [Phase 4]: SCHISM comparison uses side-by-side table format to highlight PyMT vs NextGen pathway differences

### Pending Todos

None -- all 4 phases complete.

### Blockers/Concerns

- [Phase 1 RESOLVED]: WRF-Hydro fPIC rebuild takes ~6 minutes on this WSL2 hardware (was estimated 5-30 min)
- [Phase 3 RESOLVED]: Minimal C binding layer scope -- 10 BMI functions wrapped (register, initialize, update, finalize, get_component_name, get_current_time, get_var_grid, get_grid_size, get_var_nbytes, get_value_double)
- [Phase 3 RESOLVED]: mpi4py not needed -- ctypes RTLD_GLOBAL preload of libmpi.so is sufficient for singleton serial case

## Session Continuity

Last session: 2026-02-24
Stopped at: Completed 04-01-PLAN.md -- All 4 phases complete, shared library milestone delivered
Resume file: None
Next action: Phase 2 of overall project (babelizer: babelize init babel.toml)
