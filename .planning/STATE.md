# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-24)

**Core value:** WRF-Hydro must be controllable from Python via PyMT — babelize init must produce a working pymt_wrfhydro package
**Current focus:** Research COMPLETE — ready to define requirements for v2.0

## Current Position

Phase: Not started (research complete, defining requirements next)
Plan: —
Status: Research complete. 4 research files + SUMMARY.md written. Requirements definition next.
Last activity: 2026-02-24 — Research complete (STACK, FEATURES, ARCHITECTURE, PITFALLS, SUMMARY)

Progress: [██░░░░░░░░] 20% (research done, requirements + roadmap remaining)

## Performance Metrics

**Velocity:**
- Total plans completed: 6 (from v1.0)
- Average duration: 6.7 min
- Total execution time: 0.7 hours

**By Phase (v1.0 Shared Library):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. fPIC Foundation | 1/1 | 6 min | 6 min |
| 2. Shared Library + Install | 2/2 | 17 min | 8.5 min |
| 3. Python Validation | 2/2 | 9 min | 4.5 min |
| 4. Documentation | 1/1 | 8 min | 8 min |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [v2.0 Scope]: WRF-Hydro only (no SCHISM babelization) — SCHISM BMI targets NextGen, not PyMT
- [v2.0 Validation]: Full validation required — bmi-tester + Croton NY result comparison
- [v2.0 Version]: v2.0 (major version bump — new capability layer)
- [v1.0]: Library named bmiwrfhydrof following CSDMS bmi{model}f convention (babelizer expects this)
- [v1.0]: Babelizer auto-generates 818-line bmi_interoperability.f90 — our C binding is test infrastructure only
- [v1.0]: pkg-config discovery via bmiwrfhydrof.pc — babelizer's Meson build uses this

### Research Key Findings (from SUMMARY.md)

- **C binding conflict**: Must rebuild libbmiwrfhydrof.so WITHOUT bmi_wrf_hydro_c.o before babelizing (symbol conflict with auto-generated interop)
- **Babelizer v0.3.9**: conda-forge stable; generates setuptools (deprecated). Must migrate to Meson following pymt_heatf pattern.
- **--no-build-isolation**: MANDATORY for pip install (pkg-config not found in isolated builds)
- **MPI RTLD_GLOBAL**: Must import mpi4py before pymt_wrfhydro to prevent Open MPI segfaults
- **Singleton guard**: Add explicit instance counter to bmi_wrf_hydro.f90 (babelizer generates 2048-slot model_array)
- **6 new conda packages**: babelizer, meson-python, meson, ninja, cython, python-build
- **PyMT separate install**: Large dependency tree (esmpy, landlab, scipy) — may conflict with existing env
- **Suggested 5 phases**: Pre-babelization hardening → Environment + babel.toml → Build package → BMI validation → PyMT metadata + full integration

### Pending Todos

- Define REQUIREMENTS.md (from research findings)
- Create ROADMAP.md (from requirements)
- Both need user approval before execution

### Blockers/Concerns

- [RESOLVED by research]: Babelizer v0.3.9 works with Python 3.10; must migrate generated build to Meson
- [RESOLVED by research]: MPI handled via mpi4py import before pymt_wrfhydro
- [NEW]: C binding symbol conflict requires .so rebuild before babelizing
- [NEW]: PyMT + OpenMPI 5.0.8 ABI compatibility unknown — test with --dry-run

## Session Continuity

Last session: 2026-02-24
Stopped at: Research COMPLETE (4 files + SUMMARY). Context exhausted before requirements/roadmap.
Resume file: .planning/research/SUMMARY.md
Next action: /gsd:new-milestone (RESUME from Step 9 — Define Requirements). Read SUMMARY.md + FEATURES.md, scope categories, generate REQUIREMENTS.md, then spawn roadmapper.
