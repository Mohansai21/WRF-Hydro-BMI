# Phase 9: PyMT Integration - Context

**Gathered:** 2026-02-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Register WrfHydroBmi in the PyMT model registry with metadata files, verify `from pymt.models import WrfHydroBmi` works, create a comprehensive Jupyter notebook exercising all 41 BMI functions with visualizations, and write Doc 19 covering the full source-to-PyMT journey.

</domain>

<decisions>
## Implementation Decisions

### Metadata Files
- parameters.yaml scope: Claude's discretion (based on what other PyMT plugins expose)
- info.yaml content: Claude's discretion (follow CSDMS conventions, include NCAR references + wrapper author)
- api.yaml: Single class WrfHydroBmi (not sub-components) — Claude's discretion confirmed
- run.yaml: Config template approach — Claude's discretion (template-only vs bundled Croton NY)

### Config Template Design
- Path handling: Claude's discretion (Jinja2 template vs absolute — follow PyMT conventions)
- Time control: Claude's discretion (PyMT controls time loop via update/update_until — the BMI way)

### Documentation Scope (Doc 19)
- Target audience: BOTH modelers/scientists AND developers/maintainers (split sections)
- Code examples: 6-8 comprehensive examples (install, IRF cycle, streamflow, grid info, set values, comparison, visualization, time series)
- Scope: Full journey recap (Phases 1-9) — shows complete pipeline from source to PyMT
- Doc number: 19 (Doc 18 is already BMI Compliance Validation from Phase 8)

### PyMT Install Strategy
- Primary approach: Claude's discretion (assess --dry-run risk, try wrfhydro-bmi env first)
- Fallback: Claude's discretion (pip, separate env, or document as limitation)
- Env backup: Claude's discretion (export env before install if risk warrants it)
- Grid mapping: Claude's discretion (basic import test vs light demo — full mapping is Phase 4 coupling)

### Jupyter Notebook
- Content: ALL of the following:
  - Full IRF cycle (~20-line demo from project vision)
  - Streamflow visualization (time series + spatial network)
  - All 8 output variables with summary statistics
  - Grid exploration (all 3 grids: 1km LSM, 250m routing, vector channel)
  - Exercise all 41 BMI functions (Python walkthrough of each function)
  - Run existing pytest suite from notebook (final validation cell)
- Import paths: Show BOTH standalone (`from pymt_wrfhydro import WrfHydroBmi`) and PyMT registry (`from pymt.models import WrfHydroBmi`) — standalone as primary, PyMT as optional
- Visualization: Show BOTH matplotlib (primary) and plotly (optional cells)
- Location: `pymt_wrfhydro/notebooks/`
- Pre-run outputs: Claude's discretion (consider file size vs readability)
- Title: Claude's discretion (comprehensive walkthrough theme)

### Claude's Discretion
- parameters.yaml scope and content
- info.yaml metadata details
- run.yaml staging approach (template-only vs bundled)
- Config path handling (Jinja2 vs absolute)
- PyMT install strategy and fallback
- Env backup decision
- Grid mapping test depth
- Notebook pre-run vs clean outputs
- Notebook title

</decisions>

<specifics>
## Specific Ideas

- The ~20-line Python demo is the project vision from CLAUDE.md — notebook should showcase this prominently
- Notebook should work as both a runnable demo AND a readable report (for presentations, GitHub rendering)
- Doc 19 should be the "capstone" document — someone reading just this doc should understand the entire Fortran-to-Python journey
- The 41 BMI function walkthrough in the notebook essentially creates a Python equivalent of the Fortran 151-test suite

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-pymt-integration*
*Context gathered: 2026-02-25*
