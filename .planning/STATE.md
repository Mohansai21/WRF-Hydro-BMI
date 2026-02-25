# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-24)

**Core value:** WRF-Hydro must be controllable from Python via PyMT -- babelize init must produce a working pymt_wrfhydro package
**Current focus:** Phase 7 (Package Build) -- Plan 1 of 2 COMPLETE

## Current Position

Phase: 7 of 9 (Package Build) -- IN PROGRESS
Plan: 2 of 2
Status: Plan 07-01 complete, Plan 07-02 next
Last activity: 2026-02-25 -- Completed 07-01 (hydro_stop_ fix + MPI bootstrap + pip install)

Progress: [████████░░] 80% (v1.0 complete: 6/6 plans; v2.0: 4/? plans)

## Performance Metrics

**Velocity:**
- Total plans completed: 10 (v1.0: 6, v2.0: 4)
- Average duration: 6.0 min
- Total execution time: 1.0 hours

**By Phase (v1.0 Shared Library):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. fPIC Foundation | 1/1 | 6 min | 6 min |
| 2. Shared Library + Install | 2/2 | 17 min | 8.5 min |
| 3. Python Validation | 2/2 | 9 min | 4.5 min |
| 4. Documentation | 1/1 | 8 min | 8 min |

**By Phase (v2.0 Babelizer):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 5. Library Hardening | 2/2 | 13 min | 6.5 min |
| 6. Babelizer Env + Skeleton | 1/1 | 5 min | 5 min |
| 7. Package Build | 1/2 | 3 min | 3 min |

*Updated after each plan completion*

## Accumulated Context

### Decisions

- [v2.0 Scope]: WRF-Hydro only (no SCHISM babelization)
- [v2.0 Phases]: 5 phases (5-9) following dependency chain: lib hardening -> env+skeleton -> build -> validate -> PyMT
- [v2.0]: C binding conflict RESOLVED -- bmi_wrf_hydro_c.f90 deleted, .so rebuilt with zero C symbols
- [v2.0]: pip --no-build-isolation MANDATORY for all pip install commands
- [v2.0]: PyMT installed separately in final phase to isolate large dep tree
- [v2.0 Phase 5]: CLAUDE.md and Doc 16 updated to reflect C binding removal (no stale references for future sessions)
- [v2.0 Phase 6]: babel.toml license must be "MIT License" not "MIT" (cookiecutter choice constraint)
- [v2.0 Phase 6]: Babelizer 0.3.9 generates setup.py (not meson.build) -- acceptable for Python 3.10
- [v2.0 Phase 6]: Dry-run build reveals `undefined symbol: hydro_stop_` -- Phase 7 must resolve shared library linking
- [v2.0 Phase 7]: hydro_stop_shim.o compiled with -fPIC and linked into .so -- resolves bare external symbol from dead code
- [v2.0 Phase 7]: RTLD_GLOBAL set before mpi4py import -- prevents Open MPI 5.0.8 segfaults when Cython loads .so
- [v2.0 Phase 7]: pkg_resources replaced with importlib.metadata -- no deprecation warnings

### Blockers/Concerns

- ~~[Phase 7]: `undefined symbol: hydro_stop_` when importing pymt_wrfhydro~~ -- RESOLVED in 07-01
- [Phase 8]: bmi-tester Stage 3 vector grid behavior for grid 2 (channel) -- needs live verification
- [Phase 9]: PyMT + OpenMPI 5.0.8 ABI compatibility -- test with --dry-run before install

## Session Continuity

Last session: 2026-02-25
Stopped at: Completed 07-01-PLAN.md (hydro_stop_ fix + MPI bootstrap + pip install pymt_wrfhydro)
Resume file: None
Next action: /gsd:execute-phase 07-package-build (Plan 07-02)
