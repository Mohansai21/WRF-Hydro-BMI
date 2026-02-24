# Phase 3: Python Validation - Context

**Gathered:** 2026-02-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Minimal C binding layer (`bmi_wrf_hydro_c.f90`, ~100-200 lines) + Python ctypes test exercising the BMI lifecycle against Croton NY data. Proves `libbmiwrfhydrof.so` works end-to-end from Python before handing it to the babelizer. This is test infrastructure, not production code — the babelizer auto-generates the full 818-line interoperability layer.

</domain>

<decisions>
## Implementation Decisions

### Python test design
- Two test modes: quick smoke test (1-2 timesteps) + full 6-hour validation (matching Fortran suite)
- Both modes in the same test infrastructure — not separate scripts

### C binding scope
- Not discussed — Claude selects which 8-10 BMI functions to wrap based on what the Python test needs to exercise the full IRF cycle + data validation

### Claude's Discretion
- Test structure: single script vs pytest suite — pick what makes sense for ctypes + MPI
- Test output format: print-style vs pytest assertions — match the chosen structure
- File location: where Python test file(s) live within the project
- Validation tolerance: pick appropriate strictness based on double/float conversion behavior
- Which variables to validate: balance coverage vs complexity (streamflow is mandatory, others at Claude's judgment)
- Reference data format: hardcoded vs separate file — based on volume of comparison data
- Grid metadata checks: include if useful for proving the .so works, skip if redundant with Fortran tests
- MPI setup approach: self-contained vs wrapper script — pick cleanest for ctypes + RTLD_GLOBAL
- mpi4py dependency: use if helpful, skip if pure ctypes is sufficient
- Conda env requirement: practical choice based on where the .so and deps live
- Launch method: `python test.py` vs `mpirun -np 1 python test.py` — based on how WRF-Hydro expects MPI

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. User gave Claude broad discretion on implementation details for this phase since it's test infrastructure (not user-facing).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-python-validation*
*Context gathered: 2026-02-24*
