---
phase: 06-babelizer-environment-skeleton
plan: 01
subsystem: babelizer
tags: [babelizer, babel.toml, pymt_wrfhydro, cython, fortran-interop, conda]

# Dependency graph
requires:
  - phase: 05-library-hardening
    provides: libbmiwrfhydrof.so without conflicting C symbols, pkg-config discovery working
provides:
  - babelizer 0.3.9 CLI installed in wrfhydro-bmi conda env
  - babel.toml with verified naming chain at project root
  - pymt_wrfhydro/ complete skeleton with bmi_interoperability.f90, wrfhydrobmi.pyx, setup.py
  - conda env snapshot for rollback safety
affects: [07-package-build, 08-bmi-validation, 09-pymt-integration]

# Tech tracking
tech-stack:
  added: [babelizer-0.3.9, cython-3.2.4, meson-1.10.1, ninja-1.13.2, meson-python-0.19.0, python-build-1.4.0]
  patterns: [babelizer-naming-chain, cookiecutter-skeleton-generation, setuptools-fortran-build]

key-files:
  created:
    - babel.toml
    - pymt_wrfhydro/pymt_wrfhydro/lib/bmi_interoperability.f90
    - pymt_wrfhydro/pymt_wrfhydro/lib/wrfhydrobmi.pyx
    - pymt_wrfhydro/pymt_wrfhydro/lib/bmi_interoperability.h
    - pymt_wrfhydro/pymt_wrfhydro/__init__.py
    - pymt_wrfhydro/pymt_wrfhydro/bmi.py
    - pymt_wrfhydro/setup.py
    - pymt_wrfhydro/pyproject.toml
    - wrfhydro-bmi-snapshot-20260225.yml
  modified: []

key-decisions:
  - "License field must use 'MIT License' not 'MIT' (cookiecutter choice variable constraint)"
  - "Babelizer 0.3.9 generates setup.py (not meson.build) -- this is expected and acceptable"
  - "Removed nested .git from pymt_wrfhydro so it is tracked by parent repo"
  - "Cleaned up dry-run build artifacts (.o, .c, .so) before committing skeleton"

patterns-established:
  - "Naming chain: library=bmiwrfhydrof -> use bmiwrfhydrof; entry_point=bmi_wrf_hydro -> type(bmi_wrf_hydro)"
  - "babelizer 0.3.9 generates setuptools + numpy.distutils based packages with cookiecutter templates"
  - "setup.py compiles bmi_interoperability.f90 then links Cython extension against libbmiwrfhydrof"

requirements-completed: [ENV-01, ENV-02, ENV-03]

# Metrics
duration: 5min
completed: 2026-02-25
---

# Phase 6 Plan 01: Babelizer Environment + Skeleton Summary

**Babelizer 0.3.9 installed, babel.toml written with verified naming chain, pymt_wrfhydro skeleton generated with correct bmi_interoperability.f90 referencing bmiwrfhydrof module and bmi_wrf_hydro type**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-25T14:28:38Z
- **Completed:** 2026-02-25T14:33:34Z
- **Tasks:** 2
- **Files modified:** 32

## Accomplishments
- Installed 6 babelizer toolchain packages (babelizer 0.3.9, cython 3.2.4, meson 1.10.1, ninja 1.13.2, meson-python 0.19.0, python-build 1.4.0) with zero conda conflicts
- Wrote babel.toml with pre-verified naming chain matching Fortran source, shared library, .mod files, and pkg-config
- Generated complete pymt_wrfhydro skeleton: bmi_interoperability.f90 (810 lines, 41+ bind(c) wrappers), wrfhydrobmi.pyx (526 lines, full Cython BMI class), setup.py, pyproject.toml, meta/WrfHydroBmi/
- Dry-run build: Cython compilation and Fortran interop compilation both succeeded; import fails with `undefined symbol: hydro_stop_` in libbmiwrfhydrof.so (Phase 7 linking fix)

## Task Commits

Each task was committed atomically:

1. **Task 1: Install babelizer toolchain** - `4f34b35` (chore)
2. **Task 2: Write babel.toml + generate skeleton** - `619836a` (feat)

## Files Created/Modified
- `babel.toml` - Babelizer configuration with naming chain: library=bmiwrfhydrof, entry_point=bmi_wrf_hydro
- `wrfhydro-bmi-snapshot-20260225.yml` - Conda environment snapshot before installing babelizer packages
- `pymt_wrfhydro/pymt_wrfhydro/lib/bmi_interoperability.f90` - Auto-generated Fortran C-interop layer (810 lines, 41+ bind(c) functions)
- `pymt_wrfhydro/pymt_wrfhydro/lib/wrfhydrobmi.pyx` - Auto-generated Cython wrapper (526 lines, WrfHydroBmi class)
- `pymt_wrfhydro/pymt_wrfhydro/lib/bmi_interoperability.h` - C header for Cython to call interop layer
- `pymt_wrfhydro/pymt_wrfhydro/__init__.py` - Package init importing WrfHydroBmi
- `pymt_wrfhydro/pymt_wrfhydro/bmi.py` - High-level BMI Python class
- `pymt_wrfhydro/setup.py` - Setuptools build script with Fortran compilation (numpy.distutils.fcompiler)
- `pymt_wrfhydro/pyproject.toml` - Project metadata and build system declaration
- `pymt_wrfhydro/meta/WrfHydroBmi/api.yaml` - PyMT metadata template
- `pymt_wrfhydro/recipe/meta.yaml` - Conda-forge recipe template
- `pymt_wrfhydro/.github/workflows/` - CI workflows (test, black, flake8)

## Decisions Made
- **License field**: Changed from "MIT" to "MIT License" -- cookiecutter template requires exact match from choice list
- **Babelizer version**: Confirmed 0.3.9 from conda-forge (generates setup.py, not meson.build) -- acceptable for Python 3.10
- **Nested .git**: Removed babelizer-generated .git from pymt_wrfhydro so it is tracked by the parent WRF-Hydro-BMI repo
- **Build artifact cleanup**: Removed dry-run artifacts (.o, .c, .so) to commit clean skeleton only

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed license field in babel.toml**
- **Found during:** Task 2 (babelize init)
- **Issue:** babel.toml had `package_license = "MIT"` but cookiecutter expects `"MIT License"` from its choice list
- **Fix:** Changed to `package_license = "MIT License"` and re-ran babelize init
- **Files modified:** babel.toml
- **Verification:** babelize init completed successfully after fix
- **Committed in:** 619836a (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor config value fix. No scope creep.

## Issues Encountered
- pkg_resources deprecation warning on every babelize invocation -- harmless, caused by babelizer 0.3.9 using `import pkg_resources` which is deprecated since setuptools 81
- babelize init created its own .git directory inside pymt_wrfhydro -- removed to keep single git repo structure

## Dry-Run Build Results (for Phase 7)

**Build command:** `pip install --no-build-isolation -e .` inside pymt_wrfhydro/
**Outcome:** Editable install succeeded (setup.py ran, bmi_interoperability.f90 compiled, Cython wrfhydrobmi.pyx compiled)
**Import test:** `from pymt_wrfhydro import WrfHydroBmi` -- FAILED
**Error:** `ImportError: /home/mohansai/miniconda3/envs/wrfhydro-bmi/lib/libbmiwrfhydrof.so: undefined symbol: hydro_stop_`
**Root cause:** The `hydro_stop_` symbol is from WRF-Hydro's `HYDRO_finish` subroutine, called via our `hydro_stop_shim.f90`. The shared library was built with `--whole-archive` on all 22 WRF-Hydro .a libraries, but this particular symbol may need explicit resolution at link time or the shared library may need to be rebuilt with the missing object.
**Suggested fix for Phase 7:** Check if `hydro_stop_shim.o` is included in the .so build, or if the symbol needs to be resolved differently when loaded dynamically by Python/Cython.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All Phase 6 artifacts in place: babel.toml, pymt_wrfhydro/ skeleton, babelizer toolchain
- Phase 7 (Package Build) can proceed with building and installing pymt_wrfhydro
- Key Phase 7 focus: resolve `hydro_stop_` undefined symbol, ensure MPI initialization before import, validate full IRF cycle from Python
- Babelizer generates setuptools-based package (setup.py) -- numpy.distutils.fcompiler handles Fortran compilation
- If setuptools path fails in Phase 7, meson/ninja/meson-python are pre-installed for potential migration

## Self-Check: PASSED

All 7 key files verified present. Both task commits (4f34b35, 619836a) verified in git log.

---
*Phase: 06-babelizer-environment-skeleton*
*Completed: 2026-02-25*
