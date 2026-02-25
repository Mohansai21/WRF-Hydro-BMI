---
phase: 06-babelizer-environment-skeleton
verified: 2026-02-25T15:45:00Z
status: passed
score: 4/4 must-haves verified
re_verification: false
---

# Phase 6: Babelizer Environment + Skeleton Verification Report

**Phase Goal:** The babelizer toolchain is installed, babel.toml is written with the correct naming chain, and `babelize init` generates the complete pymt_wrfhydro package directory with all auto-generated files
**Verified:** 2026-02-25T15:45:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | babelizer CLI is available and can be invoked from the command line | VERIFIED | `babelize --version` returns `babelize, version 0.3.9` with exit code 0 |
| 2  | babel.toml exists at project root with correct naming chain matching our Fortran module/type | VERIFIED | `babel.toml` at project root: `library = "bmiwrfhydrof"`, `entry_point = "bmi_wrf_hydro"`, `package.name = "pymt_wrfhydro"`, `requirements = ["mpi4py", "netCDF4"]` |
| 3  | pymt_wrfhydro/ directory exists at project root with all auto-generated babelizer files | VERIFIED | Directory exists with `setup.py` (120 lines), `pyproject.toml`, `__init__.py`, `wrfhydrobmi.pyx` (525 lines), `bmi_interoperability.f90` (809 lines), `bmi_interoperability.h` |
| 4  | bmi_interoperability.f90 in the generated skeleton USEs the correct Fortran module name (bmiwrfhydrof) and references the correct type (bmi_wrf_hydro) | VERIFIED | Line 8: `use bmiwrfhydrof`; Line 13: `type (bmi_wrf_hydro) :: model_array(N_MODELS)` — naming chain complete |

**Score:** 4/4 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `babel.toml` | Babelizer config with naming chain and runtime requirements | VERIFIED | 28 lines, all required fields present, `mpi4py` + `netCDF4` in requirements |
| `pymt_wrfhydro/pymt_wrfhydro/__init__.py` | Python package init importing WrfHydroBmi | VERIFIED | Imports `WrfHydroBmi` from `.bmi`, exports in `__all__` |
| `pymt_wrfhydro/setup.py` | Build script for Fortran compilation | VERIFIED | 120 lines, uses `numpy.distutils.fcompiler`, links `bmiwrfhydrof`, compiles `bmi_interoperability.f90` to `.o` |
| `pymt_wrfhydro/pyproject.toml` | Project metadata and build system declaration | VERIFIED | Declares `[build-system]` with cython, numpy, setuptools, wheel |
| `pymt_wrfhydro/pymt_wrfhydro/lib/bmi_interoperability.f90` | Auto-generated Fortran C interop layer wrapping all BMI functions | VERIFIED | 809 lines, not a stub; `use bmiwrfhydrof` present; `bind(C)` wrappers for all 41 BMI functions |

All 5 artifacts: EXISTS + SUBSTANTIVE + WIRED.

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `babel.toml [library.WrfHydroBmi] library = "bmiwrfhydrof"` | `bmi_interoperability.f90` | babelize init code generation | VERIFIED | `bmi_interoperability.f90` line 8: `use bmiwrfhydrof` |
| `babel.toml [library.WrfHydroBmi] entry_point = "bmi_wrf_hydro"` | `bmi_interoperability.f90` | babelize init code generation | VERIFIED | `bmi_interoperability.f90` line 13: `type (bmi_wrf_hydro) :: model_array(N_MODELS)` |
| `$CONDA_PREFIX/lib/libbmiwrfhydrof.so` | `pymt_wrfhydro/setup.py` | direct library name in Extension | VERIFIED (with note) | `setup.py` line 35: `libraries=libraries + ["bmiwrfhydrof"]`. Babelizer uses direct name instead of pkg-config; functionally equivalent since `sys.prefix/lib` is `$CONDA_PREFIX/lib`. `pkg-config --libs bmiwrfhydrof` still returns correct flags with no regression. |

**Note on key link 3:** The PLAN specified pkg-config as the `via` mechanism. Babelizer 0.3.9's cookiecutter template generates direct `libraries=["bmiwrfhydrof"]` linkage rather than pkg-config subprocess calls. The functional outcome is identical — the library is correctly discovered at build time via `sys.prefix/lib` ($CONDA_PREFIX/lib). This is not a gap.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ENV-01 | 06-01-PLAN.md | 6 conda packages installed: babelizer, meson-python, meson, ninja, cython, python-build | SATISFIED | `babelize 0.3.9`, `cython 3.2.4`, `meson 1.10.1`, `ninja 1.13.2`, `meson-python 0.19.0`, `python-build 1.4.0` — all verified from conda env |
| ENV-02 | 06-01-PLAN.md | babel.toml with correct naming chain: library=bmiwrfhydrof, entry_point=bmi_wrf_hydro, package.name=pymt_wrfhydro, mpi4py in requirements | SATISFIED | babel.toml at project root contains all specified fields exactly |
| ENV-03 | 06-01-PLAN.md | pymt_wrfhydro/ with bmi_interoperability.f90, .pyx, pyproject.toml | SATISFIED | All files present and substantive; setup.py generated (not meson.build — expected for babelizer 0.3.9, explicitly documented in PLAN as acceptable) |

**Orphaned requirements:** None. REQUIREMENTS.md maps ENV-01, ENV-02, ENV-03 to Phase 6. The PLAN claims all three. All three are satisfied.

**Note on ENV-03 wording:** REQUIREMENTS.md lists "meson.build" as one of the expected files. Babelizer 0.3.9 generates `setup.py` instead (meson.build is from the develop branch). The PLAN explicitly states this is acceptable. The requirement is satisfied by setup.py + pyproject.toml presence.

---

### Naming Chain End-to-End Verification

This is the critical correctness check for the phase. Verified against primary source:

```
bmi_wrf_hydro/src/bmi_wrf_hydro.f90 line 111:
  module bmiwrfhydrof                    <- module name

bmi_wrf_hydro/src/bmi_wrf_hydro.f90 line 159:
  type, extends (bmi) :: bmi_wrf_hydro   <- type name

babel.toml lines 3-4:
  library = "bmiwrfhydrof"               <- matches module name EXACTLY
  entry_point = "bmi_wrf_hydro"          <- matches type name EXACTLY

pymt_wrfhydro/pymt_wrfhydro/lib/bmi_interoperability.f90 lines 8 and 13:
  use bmiwrfhydrof                       <- babelizer used library field CORRECTLY
  type (bmi_wrf_hydro) :: model_array    <- babelizer used entry_point CORRECTLY
```

Naming chain is complete and correct at all levels.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

Scanned: `babel.toml`, `pymt_wrfhydro/pymt_wrfhydro/__init__.py`, `pymt_wrfhydro/setup.py`. No TODO/FIXME/placeholder patterns found. All implementations are substantive.

---

### Regression Check

| Tool | Status | Details |
|------|--------|---------|
| `gfortran --version` | PASS | GNU Fortran 14.3.0 (conda-forge) |
| `mpif90 --version` | PASS | GNU Fortran 14.3.0 (conda-forge) |
| `pkg-config --libs bmiwrfhydrof` | PASS | `-L$CONDA_PREFIX/lib -lbmiwrfhydrof -lbmif` |

No regressions from babelizer toolchain install.

---

### Human Verification Required

None required. All critical checks are verifiable programmatically:
- Package versions confirmed via CLI commands
- babel.toml field values confirmed by direct file read
- bmi_interoperability.f90 naming chain confirmed by grep
- Artifact substantiveness confirmed by line counts and content inspection

The dry-run build failure (`undefined symbol: hydro_stop_`) is a KNOWN and DOCUMENTED issue for Phase 7. It is not a gap for Phase 6 — the phase goal is the skeleton generation, not a successful build install. The PLAN explicitly scoped this as "Phase 7's job."

---

## Summary

Phase 6 achieved its goal completely.

The babelizer toolchain (6 packages) is installed with zero conda conflicts and zero regressions to existing tools. `babel.toml` exists at project root with the correct naming chain verified against the actual Fortran source (`module bmiwrfhydrof`, `type bmi_wrf_hydro`). The `pymt_wrfhydro/` package skeleton was generated by `babelize init` and contains all required auto-generated files — most critically, `bmi_interoperability.f90` (809 lines, 41+ bind(C) wrappers) with the correct `use bmiwrfhydrof` and `type (bmi_wrf_hydro)` references.

Both task commits (4f34b35, 619836a) are verified in git log. All three requirement IDs (ENV-01, ENV-02, ENV-03) are satisfied. The one deviation from the plan (direct library linkage vs pkg-config in setup.py) is babelizer's standard behavior and is functionally equivalent.

Phase 7 (package build) can proceed. The known blocker (`undefined symbol: hydro_stop_`) is documented in the SUMMARY for the Phase 7 planner.

---

_Verified: 2026-02-25T15:45:00Z_
_Verifier: Claude (gsd-verifier)_
