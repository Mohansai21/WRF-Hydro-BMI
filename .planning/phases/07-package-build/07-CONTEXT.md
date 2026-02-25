# Phase 7: Package Build - Context

**Gathered:** 2026-02-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Build and install the babelizer-generated pymt_wrfhydro package so it imports and runs from Python. The skeleton already exists from Phase 6 (bmi_interoperability.f90, wrfhydrobmi.pyx, setup.py, pyproject.toml). This phase resolves build issues (including the known hydro_stop_ undefined symbol), installs the package, and validates end-to-end with Croton NY data. BMI compliance testing is Phase 8; PyMT registration is Phase 9.

</domain>

<decisions>
## Implementation Decisions

### MPI Bootstrap Pattern
- Auto-handle MPI in `__init__.py` — user does NOT need to manually import mpi4py first
- Set `RTLD_GLOBAL` via `sys.setdlopenflags()` or `ctypes.CDLL` in `__init__.py` before Cython extension loads
- Hard error (ImportError) with clear install instructions if mpi4py is not available
- Require `mpirun` to execute — users must run `mpirun -np 1 python script.py`
- Do NOT call MPI_Finalize in the package; leave that to mpirun/mpi4py shutdown

### Validation Depth
- Full value comparison: all 8 output variables checked against Fortran 151-test reference output
- Reference values extracted from 151-test stdout and stored as a dict/JSON in the test file
- Both test formats: pytest (`test_bmi_wrfhydro.py`) for CI + standalone script for quick manual checks
- Floating-point tolerance: Claude's discretion based on the actual REAL(4)->double->float data path

### Import Ergonomics
- Primary import: `from pymt_wrfhydro import WrfHydroBmi` (standard babelizer pattern)
- Also expose `__version__`, `__bmi_version__`, and `pymt_wrfhydro.info()` for debugging
- Initialization errors surface as Python exceptions (RuntimeError) with helpful context messages, not integer status codes
- WRF-Hydro diagnostic output goes to files (diag_hydro.00000 etc.) in the working directory — stdout stays clean for Python

### Install & Iteration Strategy
- Editable install (`pip install --no-build-isolation -e .`) during development/debugging
- Full install (`pip install --no-build-isolation .`) for the final success validation
- Library discovery via `pkg-config --libs bmiwrfhydrof` (set up in Phase 2)
- Always build with `-v` flag for full compiler output (diagnose linking errors)
- Fix-and-rebuild cycle: diagnose error, fix, rebuild, repeat
- Minimal setup.py changes — keep babelizer's generated structure intact, only add what's needed

### Claude's Discretion
- MPI_Finalize handling details (whether package atexit or leave to runtime)
- Multi-process behavior documentation (serial-first, np > 1 untested)
- Error message wording and formatting
- Floating-point tolerance selection for value comparison
- Exact approach to resolve `hydro_stop_` undefined symbol (rebuild .so, modify setup.py linker flags, or other)
- How bmi_interoperability.f90 gets compiled (setup.py Extension configuration)

</decisions>

<specifics>
## Specific Ideas

- Phase 3 Python validation (ctypes test) already solved the RTLD_GLOBAL + mpi4py bootstrap — reuse that pattern in `__init__.py`
- The `hydro_stop_` undefined symbol (documented in Phase 6 06-01-SUMMARY.md) is the primary known blocker — likely a linking issue where setup.py doesn't include the shim or the .so needs rebuilding
- 151-test Fortran suite prints values that can be captured as reference — no need to generate new reference data
- Keep babelizer's cookiecutter structure as intact as possible for future `babelize update` compatibility

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-package-build*
*Context gathered: 2026-02-25*
