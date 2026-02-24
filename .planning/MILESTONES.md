# Milestones

## v1.0 — Shared Library (Complete)

**Goal:** Build `libbmiwrfhydrof.so` — a shared library making WRF-Hydro discoverable by the CSDMS babelizer.

**Delivered:** 2026-02-24
**Phases:** 4 (fPIC Foundation → Shared Library + Install → Python Validation → Documentation)
**Requirements:** 13/13 complete (BUILD-01..05, CBIND-01/03/04, PYTEST-01..04, DOC-01)

**Key artifacts:**
- `libbmiwrfhydrof.so` (4.8 MB) installed to `$CONDA_PREFIX/lib/`
- `bmi_wrf_hydro_c.f90` — C binding layer (10 BMI functions)
- `bmiwrfhydrof.pc` — pkg-config discovery file
- Python ctypes test — validates Croton NY streamflow
- Doc 16 — Shared library architecture + babelizer readiness

**Last phase number:** 4

---

## v2.0 — Babelizer (Active)

**Goal:** Babelize WRF-Hydro into `pymt_wrfhydro` Python package, validated against Croton NY reference data.

**Started:** 2026-02-24
**Status:** Defining requirements
