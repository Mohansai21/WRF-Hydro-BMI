# Technology Stack: Babelizer & PyMT Integration

**Project:** WRF-Hydro BMI -- Phase 2 (Babelizer)
**Researched:** 2026-02-24
**Confidence:** HIGH (verified against csdms/babelizer develop branch source code, pymt_heatf reference implementation, conda-forge package metadata, and existing wrfhydro-bmi conda environment)

---

## Executive Summary

Babelizing the existing `libbmiwrfhydrof.so` into a `pymt_wrfhydro` Python package requires adding six new packages to the conda environment: `babelizer`, `meson-python`, `meson`, `ninja`, `cython`, and `python-build`. PyMT installation (`pymt`) is needed only for the final PyMT plugin registration and testing phase, not for the babelizer step itself.

**Critical finding:** The conda-forge babelizer v0.3.9 (released March 2022) uses `setuptools + numpy.distutils` for Fortran projects, while the develop branch (0.3.10.dev0, updated Feb 2025) has migrated to Meson. Since `numpy.distutils` is deprecated and removed in NumPy 2.0+ (our env has NumPy 2.2.6 but Python 3.10 still has a deprecation-warning-only `numpy.distutils`), the recommended path is to **use the conda-forge v0.3.9 to generate the package skeleton, then manually replace the generated `setup.py` build with Meson**, following the exact pattern from the `pymt_heatf` reference implementation (pymt-lab/pymt_heatf, updated Feb 2025). This is what the CSDMS team themselves did.

**Existing infrastructure is ready:** `libbmiwrfhydrof.so` is installed, `bmiwrfhydrof.pc` is configured, pkg-config discovery works. The Fortran module name (`bmiwrfhydrof`) and type name (`bmi_wrf_hydro`) already match babelizer expectations exactly.

---

## Recommended Stack

### New Packages to Install

| Technology | Version | Purpose | Why This Version | Confidence |
|------------|---------|---------|------------------|------------|
| babelizer | 0.3.9 (conda-forge) | Generate pymt_wrfhydro package skeleton | Latest conda-forge release; generates babel.toml-driven package structure | HIGH |
| meson-python | 0.19.0 (conda-forge) | PEP 517 build backend for generated package | Latest stable; used by pymt_heatf reference; replaces numpy.distutils | HIGH |
| meson | 1.10.1 (conda-forge) | Build system for compiling Cython + Fortran interop | Latest stable; required by meson-python; has mature Fortran support | HIGH |
| ninja | latest (conda-forge) | Build executor (Meson backend) | Meson requires ninja; fast parallel builds | HIGH |
| cython | 3.2.4 (conda-forge) | Compile .pyx Fortran bindings to C extension | Latest stable; generates the Python<->C bridge from babelizer templates | HIGH |
| python-build | latest (conda-forge) | PEP 517 build frontend (`python -m build`) | Standard way to build Meson-based packages; pymt_heatf uses it | HIGH |

### Packages for Validation Phase

| Technology | Version | Purpose | Why This Version | Confidence |
|------------|---------|---------|------------------|------------|
| bmi-tester | 0.5.9 (conda-forge, already installed) | Automated BMI compliance testing | Already in env; tests all 41 BMI functions via Python interface | HIGH |
| pymt | 1.3.2 (conda-forge) | PyMT framework for plugin registration | Latest stable; provides `pymt.MODELS` registry and grid mappers | HIGH |
| bmipy | 2.0.1 (conda-forge) | Python BMI abstract interface | Required by pymt_heatf; provides Python-side BMI class | MEDIUM |

### Existing Packages (No Changes)

| Technology | Version | Status | Role |
|------------|---------|--------|------|
| numpy | 2.2.6 | Installed | Array handling in babelized package |
| pkg-config | 0.29.2 | Installed | Library discovery (bmiwrfhydrof.pc) |
| gfortran (fortran-compiler) | 14.3.0 | Installed | Compiles bmi_interoperability.f90 |
| c-compiler | 1.11.0 | Installed | Compiles Cython-generated C code |
| cmake | 3.31.1 | Installed | NOT used by babelizer (Meson replaces it) |
| bmi-fortran | 2.0.3 | Installed | Provides bmif_2_0.mod for interop compilation |
| pip | 26.0.1 | Installed | Alternative to python-build for installation |
| wheel | 0.46.3 | Installed | Wheel building support |
| bmi-tester | 0.5.9 | Installed | Already available |
| Python | 3.10.19 | Installed | Compatible with all required packages |

---

## Installation Commands

### Phase 2a: Babelizer + Meson Build Tools

```bash
source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi

# Install babelizer and Meson build toolchain
conda install -c conda-forge \
  babelizer=0.3.9 \
  meson-python=0.19.0 \
  meson=1.10.1 \
  ninja \
  cython=3.2.4 \
  python-build
```

### Phase 2b: PyMT (for plugin validation)

```bash
# Install PyMT (has many dependencies: esmpy, landlab, scipy, etc.)
conda install -c conda-forge pymt=1.3.2

# Also install bmipy (Python BMI interface)
conda install -c conda-forge bmipy=2.0.1
```

**Note:** PyMT pulls in substantial dependencies (esmpy, landlab, scipy, shapely, xarray, matplotlib-base, netcdf4, jinja2, pyyaml). Install it in a separate step to isolate any dependency conflicts from the core babelizer toolchain.

### Verification

```bash
# Verify babelizer
babelize --version                    # 0.3.9

# Verify Meson toolchain
meson --version                       # 1.10.1
ninja --version                       # should print version
cython --version                      # 3.2.x

# Verify pkg-config finds our library
pkg-config --cflags --libs bmiwrfhydrof
# Expected: -I/.../include -L/.../lib -lbmiwrfhydrof -lbmif

# Verify bmi-tester
bmi-test --version                    # 0.5.9

# Verify pymt (after Phase 2b install)
python -c "import pymt; print(pymt.__version__)"
```

---

## Critical: Babelizer v0.3.9 Generates setuptools, Not Meson

### The Problem

The conda-forge babelizer v0.3.9 (the only stable release) generates Fortran packages with this build system:

```python
# v0.3.9 generated setup.py (USES DEPRECATED numpy.distutils)
from numpy.distutils.fcompiler import new_fcompiler  # DEPRECATED
from setuptools import Extension, setup

class build_ext(_build_ext):
    def run(self):
        with as_cwd('pymt_wrfhydro/lib'):
            build_interoperability()    # Compiles Fortran via numpy.distutils
        _build_ext.run(self)
```

**Status:** `numpy.distutils` is deprecated since NumPy 1.23.0 and REMOVED for Python >= 3.12. With our Python 3.10 + NumPy 2.2.6, it still works (with deprecation warnings), but this path is fragile and will break if we upgrade Python.

### The Solution: Follow pymt_heatf Pattern

The CSDMS team's own reference implementation (`pymt-lab/pymt_heatf`) has already migrated from the babelizer-generated setuptools build to Meson. The workflow is:

1. **Generate** the package skeleton with `babelize init babel.toml` (gets the Fortran interop layer, Cython bindings, package structure)
2. **Replace** the generated `setup.py` + `pyproject.toml` with Meson-based equivalents
3. **Build** with `pip install .` or `python -m build` (uses meson-python backend)

This is not a workaround -- it is the intended migration path. The babelizer develop branch (0.3.10.dev0) already generates Meson-based packages natively, but that version is not yet released to conda-forge.

### Alternative: Install Babelizer from Git Develop Branch

```bash
pip install "git+https://github.com/csdms/babelizer.git@develop"
```

**Risk:** The develop branch requires Python >= 3.11 (our env is 3.10). It also has unreleased dependency changes (uses `jinja2` directly instead of `cookiecutter`, requires `logoizer`). NOT recommended unless we upgrade Python.

### Recommendation

Use the conda-forge v0.3.9 for skeleton generation, then manually migrate to Meson. Rationale:

1. v0.3.9 is the tested, stable release on conda-forge
2. The key output (bmi_interoperability.f90, _fortran.pyx, bmi_interoperability.h) is the same regardless of build system
3. pymt_heatf proves this approach works (actively maintained, v3.2 released Dec 2024)
4. Avoids Python version upgrade risk
5. The Meson migration is well-documented by the pymt_heatf reference

---

## Build System Architecture

### How It All Fits Together

```
EXISTING (Phase 1.5):                    NEW (Phase 2):
========================                 ========================

libbmiwrfhydrof.so (4.8 MB)
  installed at $CONDA_PREFIX/lib/
  |
  | pkg-config discovery
  | (bmiwrfhydrof.pc)
  v
babelize init babel.toml ---------> pymt_wrfhydro/ (GENERATED)
                                      |
                                      |  Contains:
                                      |  - bmi_interoperability.f90 (809 lines, auto-generated)
                                      |  - bmi_interoperability.h (79 lines, static)
                                      |  - wrfhydrobmi.pyx (529 lines, Cython bindings)
                                      |  - meson.build (replaces setup.py)
                                      |  - pyproject.toml (meson-python backend)
                                      |
                                      v
                                    pip install .  (or python -m build)
                                      |
                                      | Meson build steps:
                                      | 1. pkg-config finds libbmiwrfhydrof.so
                                      | 2. gfortran compiles bmi_interoperability.f90
                                      |    (use bmiwrfhydrof -> use bmi_wrf_hydro type)
                                      | 3. Cython compiles wrfhydrobmi.pyx -> .c
                                      | 4. gcc compiles .c -> wrfhydrobmi.cpython-310-*.so
                                      | 5. Extension links against libbmiwrfhydrof.so
                                      v
                                    pymt_wrfhydro installed in site-packages/
                                      |
                                      v
                                    from pymt_wrfhydro import WrfHydroBmi
                                    m = WrfHydroBmi()
                                    m.initialize("bmi_config.txt")
```

### Meson Build Details (from pymt_heatf reference)

The generated `meson.build` does this for Fortran BMI packages:

```meson
project('pymt_wrfhydro', 'fortran', 'cython')

py = import('python').find_installation(pure: false)
fc = meson.get_compiler('fortran')

# Find our library via pkg-config (this is why bmiwrfhydrof.pc matters)
bmiwrfhydrof_dep = dependency('bmiwrfhydrof', method: 'pkg-config')

py.extension_module(
    'wrfhydrobmi',                                    # output .so name
    [
        'pymt_wrfhydro/lib/bmi_interoperability.f90', # Fortran interop
        'pymt_wrfhydro/lib/wrfhydrobmi.pyx',          # Cython bindings
    ],
    dependencies: [bmiwrfhydrof_dep],                 # links libbmiwrfhydrof.so
    install: true,
    subdir: 'pymt_wrfhydro/lib',
)
```

### pkg-config Integration

The Meson `dependency('bmiwrfhydrof', method: 'pkg-config')` call runs:

```bash
pkg-config --cflags --libs bmiwrfhydrof
# Returns: -I/home/mohansai/miniconda3/envs/wrfhydro-bmi/include \
#          -L/home/mohansai/miniconda3/envs/wrfhydro-bmi/lib \
#          -lbmiwrfhydrof -lbmif
```

This gives Meson the include paths (for .mod files) and linker flags (for .so). Our existing `bmiwrfhydrof.pc` already produces the correct output -- verified on 2026-02-24.

---

## Key Version Compatibility Matrix

| Package | Version | Python | NumPy | Notes |
|---------|---------|--------|-------|-------|
| babelizer | 0.3.9 | >= 3.9 | any | conda-forge stable; generates setuptools (must migrate to Meson) |
| babelizer | 0.3.10.dev0 | >= 3.11 | any | develop branch; generates Meson natively; NOT released |
| pymt | 1.3.2 | 3.10-3.13 | >= 1.19, < 3 | Latest stable; large dependency tree |
| bmi-tester | 0.5.9 | >= 3.10 | any | Latest on conda-forge; v0.5.10 exists on GitHub only |
| meson-python | 0.19.0 | 3.10+ | any | Latest stable; PEP 517 build backend |
| meson | 1.10.1 | any | N/A | Latest stable; Fortran support since v0.40 |
| cython | 3.2.4 | 3.10+ | any | Latest stable; compiles .pyx to C |
| bmipy | 2.0.1 | any | any | Python BMI abstract interface |

**Our environment:** Python 3.10.19, NumPy 2.2.6 -- compatible with all packages.

---

## What NOT To Install

| Package | Why Not |
|---------|---------|
| `babelizer` from develop branch | Requires Python >= 3.11; unreleased; has `logoizer` dependency (git-only) |
| `numpy < 2.0` | Would break existing setup; numpy.distutils removal is the symptom, Meson is the cure |
| `setuptools < 60` | Would conflict with existing packages; Meson replaces setuptools entirely |
| `cookiecutter` (standalone) | Babelizer v0.3.9 bundles its own cookiecutter dependency |
| `cffi` | Not used by babelizer/PyMT; ctypes is already validated |
| `f2py` | Babelizer uses its own Fortran interop layer, not f2py |
| `scikit-build` / `scikit-build-core` | Alternative to meson-python, but pymt_heatf uses meson-python |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Babelizer version | 0.3.9 conda-forge + Meson migration | 0.3.10.dev0 from git | Requires Python 3.11+; unreleased; dependency issues |
| Build backend | meson-python | setuptools (babelizer default) | numpy.distutils deprecated; will break on Python 3.12+ |
| Build backend | meson-python | scikit-build-core | CSDMS ecosystem uses Meson (pymt_heatf reference); consistency |
| PyMT version | 1.3.2 conda-forge | 1.3.3.dev0 from git | Development version; 1.3.2 is latest stable |
| bmi-tester | 0.5.9 conda-forge | 0.5.10 from git | 0.5.9 is already installed; minor version bump |
| Python version | Keep 3.10 | Upgrade to 3.12 | Risk of breaking WRF-Hydro conda env; no benefit for Phase 2 |

---

## PyMT Dependency Tree (Large)

PyMT 1.3.2 pulls in significant dependencies. These are listed here for awareness -- some may conflict with existing packages in the wrfhydro-bmi env.

```
pymt 1.3.2
  +-- deprecated
  +-- esmpy >= 8.x         (ESMF regridding; pulls in esmf, mpi4py)
  +-- gimli.units >= 0.3.3 (unit conversion)
  +-- jinja2               (templating)
  +-- landlab              (grid/topo analysis; large package)
  +-- matplotlib-base      (plotting)
  +-- model_metadata       (CSDMS model metadata)
  +-- netcdf4              (already have NetCDF)
  +-- numpy >= 1.19, < 3   (compatible with 2.2.6)
  +-- pyyaml               (YAML parsing)
  +-- scipy                (numerical methods)
  +-- shapely              (geometric operations)
  +-- xarray               (labeled arrays)
```

**Risk mitigation:** Install PyMT in a separate conda install step. If conflicts arise, consider creating a child environment or using `conda install --dry-run` first.

---

## Tool Roles in the Workflow

| Step | Tool | What It Does |
|------|------|-------------|
| 1. Generate skeleton | `babelize init babel.toml` | Creates pymt_wrfhydro/ directory with all template files |
| 2. Migrate build | Manual edit | Replace setup.py with meson.build + update pyproject.toml |
| 3. Build package | `pip install .` | meson-python compiles Fortran interop + Cython + links .so |
| 4. Test import | `python -c "from pymt_wrfhydro import WrfHydroBmi"` | Verify Python can import the babelized model |
| 5. BMI compliance | `bmi-test pymt_wrfhydro:WrfHydroBmi --config-file=...` | Run automated BMI test suite (41 function categories) |
| 6. PyMT registration | Add meta/ YAML files | Register as PyMT plugin (`pymt.MODELS`) |
| 7. PyMT validation | `python -c "from pymt.models import WrfHydroBmi"` | Verify plugin appears in PyMT registry |
| 8. Croton NY validation | Custom Python script | Run 6-hour simulation, compare to Fortran reference output |

---

## Sources

### Primary (HIGH confidence)

- **csdms/babelizer develop branch** (cloned 2026-02-24): Template source code, version 0.3.10.dev0, Meson migration confirmed
  - Repository: [github.com/csdms/babelizer](https://github.com/csdms/babelizer)
  - Key files: `babelizer/data/templates/meson.build`, `babelizer/data/templates/pyproject.toml`
- **csdms/babelizer v0.3.9 tag**: Cookiecutter-based templates, setuptools + numpy.distutils
  - Commit: `5a8ca7f` (2022-03-05)
- **pymt-lab/pymt_heatf** (cloned 2026-02-24): Reference Fortran babelized package using Meson
  - Repository: [github.com/pymt-lab/pymt_heatf](https://github.com/pymt-lab/pymt_heatf)
  - Version: 3.3.dev0, last updated 2025-02-12
  - `meson.build`, `pyproject.toml`, `environment.yml` -- exact build recipe
- **conda-forge package metadata** (queried 2026-02-24):
  - `conda search --info babelizer=0.3.9` -- deps: black, click, cookiecutter, gitpython, isort, pyyaml, tomlkit
  - `conda search --info pymt=1.3.2` -- deps: esmpy, landlab, scipy, shapely, xarray, etc.
  - `conda search --info bmi-tester=0.5.9` -- deps: gimli.units, model_metadata, numpy, pytest
  - `conda search meson-python` -- v0.19.0 latest on conda-forge (Jan 2026)
- **Existing wrfhydro-bmi env** (verified 2026-02-24):
  - `pkg-config --cflags --libs bmiwrfhydrof` -- returns correct flags
  - Python 3.10.19, NumPy 2.2.6, bmi-tester 0.5.9 already installed
  - Missing: meson, ninja, cython, meson-python, babelizer, pymt

### Secondary (MEDIUM confidence)

- **numpy.distutils deprecation**: [numpy.org/doc/stable/reference/distutils_status_migration.html](https://numpy.org/doc/stable/reference/distutils_status_migration.html) -- deprecated NumPy 1.23.0, removed for Python >= 3.12
- **meson-python PyPI**: [pypi.org/project/meson-python/](https://pypi.org/project/meson-python/) -- v0.19.0 released Jan 15, 2026
- **csdms/bmi-tester** (cloned 2026-02-24): v0.5.10 released June 2025 on GitHub, not yet on conda-forge
- **CSDMS babelizer documentation**: [babelizer.readthedocs.io](https://babelizer.readthedocs.io/en/latest/)
- **Anaconda conda-forge**: [anaconda.org/conda-forge/babelizer](https://anaconda.org/conda-forge/babelizer)
