# Phase 8: BMI Compliance Validation - Context

**Gathered:** 2026-02-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Run the official CSDMS bmi-tester against the babelized pymt_wrfhydro to validate all 41 BMI functions through the Python-Cython-Fortran bridge. Fix any wrapper bugs discovered. Document expected non-implementations with justification. Validate Croton NY streamflow matches Fortran reference output across all timesteps.

</domain>

<decisions>
## Implementation Decisions

### Failure Handling Strategy
- Fix ALL bmi-tester failures in this phase, including grid topology for vector channel grids
- Fix BMI wrapper bugs discovered by bmi-tester (wrong units, incorrect var_type, etc.) — commit fixes here
- Iterate fix-and-rerun cycles until ALL 3 bmi-tester stages pass — no cap on iterations
- get_value_ptr returning BMI_FAILURE is an EXPECTED non-implementation (REAL4→double type mismatch), not a bug to fix

### Non-Implementation Documentation
- Create dedicated Doc 18 in bmi_wrf_hydro/Docs/ (following existing emoji/diagram/ML-analogy style)
- Document ALL BMI functions that return BMI_FAILURE, not just the ones bmi-tester tests
- Include a full 41-function compliance matrix (table: function name, status Pass/Expected Failure/N-A, justification)
- Include bmi-tester stdout/stderr logs as appendix for reproducibility

### Validation Test Scope
- Keep BOTH Phase 7 pytest suite (38 tests) AND bmi-tester — they're complementary (bmi-tester = spec compliance, pytest = WRF-Hydro-specific behavior)
- Install bmi-tester as standalone tool via pip into wrfhydro-bmi conda env, NOT as project dependency
- Create unified validation script at pymt_wrfhydro/validate.sh that runs all 3 suites (bmi-tester + pytest + standalone E2E) in sequence

### Streamflow Reference Matching
- Keep rtol=1e-5, atol=1e-6 (same as Phase 7, consistent across phases)
- Compare STREAMFLOW ONLY (channel_water__volume_flow_rate) against Fortran reference — other 7 vars are internal state, not exchanged with SCHISM
- Run FULL simulation (all timesteps in Croton NY case), not just 6 steps — catches late-divergence issues
- Report ALL divergent timesteps at end, don't fail on first mismatch — diagnostic-friendly
- Save Fortran reference output to NumPy .npz file for reproducible comparison (no Fortran re-run needed)
- Reference file stored at pymt_wrfhydro/tests/data/ (close to tests that use it)

### Claude's Discretion
- bmi-tester configuration details (config file format, stage selection flags)
- How to handle bmi-tester's expected failure mechanism (skip list vs error handling)
- validate.sh script structure and output formatting
- Whether to generate the .npz reference file via a Python helper script or inline in test setup

</decisions>

<specifics>
## Specific Ideas

- bmi-tester is the official CSDMS standard — passing it gives credibility for PyMT registration in Phase 9
- Doc 18 compliance matrix will be useful for CSDMS submission and for any future maintainers
- The .npz reference file makes CI/CD possible in the future (no need for WRF-Hydro build to validate Python side)
- validate.sh should have clear pass/fail output for each suite, with overall SUCCESS/FAIL at the end

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-bmi-compliance-validation*
*Context gathered: 2026-02-25*
