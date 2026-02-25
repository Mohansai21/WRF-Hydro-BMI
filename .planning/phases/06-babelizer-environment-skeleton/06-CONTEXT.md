# Phase 6: Babelizer Environment + Skeleton - Context

**Gathered:** 2026-02-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Install the babelizer toolchain into the existing conda environment, write babel.toml with the correct naming chain, and run `babelize init` to generate the complete pymt_wrfhydro package directory with all auto-generated files. Building and installing the package is Phase 7.

</domain>

<decisions>
## Implementation Decisions

### Package Location
- pymt_wrfhydro/ generated at project root (alongside bmi_wrf_hydro/, wrf_hydro_nwm_public/)
- babel.toml also at project root (standard babelizer convention)
- pymt_wrfhydro/ tracked in git (will be customized in Phase 7, needs version control)
- Commit skeleton only after verification passes (not immediately after generation)

### babel.toml Configuration
- Naming chain locked per requirements: `library = "bmiwrfhydrof"`, `entry_point = "bmi_wrf_hydro"`, `package.name = "pymt_wrfhydro"`
- Runtime requirements: mpi4py + netCDF4 (WRF-Hydro needs MPI and NetCDF at runtime)
- Build libraries: rely on pkg-config discovery (bmiwrfhydrof.pc already includes transitive deps)

### Environment Strategy
- Install all babelizer toolchain packages into existing wrfhydro-bmi conda env (not a separate env)
- Snapshot env first (`conda env export`) before installing, for rollback safety
- Install all 6 packages in one command: babelizer, meson-python, meson, ninja, cython, python-build
- If dependency conflicts arise: resolve them (update packages, adjust pins) rather than creating a separate env

### Skeleton Verification
- File checklist: verify bmi_interoperability.f90, .pyx wrapper, meson.build, pyproject.toml, __init__.py all exist
- Inspect bmi_interoperability.f90 content: confirm it USEs correct Fortran module name (bmiwrfhydrof) and calls correct procedures
- Quick dry-run build attempt after skeleton verification (knowing it may fail — fixes are Phase 7's job)
- Document build failure details (exact error + likely fix) to give Phase 7 planner a head start

### Claude's Discretion
- Python version constraint in babel.toml (pick based on babelizer defaults and conda env)
- Package metadata level (author, license, description — keep appropriate for research tool)
- Whether pkg-config alone suffices or extra build flags needed in babel.toml

</decisions>

<specifics>
## Specific Ideas

- Follow CSDMS convention for babelized package layout (pymt_wrfhydro/ as standalone top-level directory)
- Build failure documentation should capture exact error message and suggest fix direction for Phase 7

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-babelizer-environment-skeleton*
*Context gathered: 2026-02-24*
