# Phase 6: Babelizer Environment + Skeleton - Research

**Researched:** 2026-02-24
**Domain:** CSDMS Babelizer toolchain, babel.toml configuration, Fortran-to-Python code generation
**Confidence:** HIGH

## Summary

The babelizer is a CSDMS command-line tool that auto-generates Python bindings for Fortran (and C/C++) BMI-wrapped models. It takes a `babel.toml` configuration file and produces a complete Python package directory with Fortran C-interoperability layer (`bmi_interoperability.f90`), Cython wrapper (`.pyx`), build system files, and metadata. Two versions exist: the conda-forge release (0.3.9, setuptools-based, cookiecutter templates) and the develop branch (0.3.10.dev0, meson-python-based, Jinja2 templates). Our environment (Python 3.10) is compatible with 0.3.9 from conda-forge, which is the recommended path because it avoids upgrading Python and is the stable release. The generated skeleton requires customization in Phase 7 to actually build, but Phase 6 only needs the files to exist and be verified.

The naming chain is fully confirmed: `library = "bmiwrfhydrof"` (matches our `.so` and Fortran module name), `entry_point = "bmi_wrf_hydro"` (matches our derived type name), `package.name = "pymt_wrfhydro"` (target Python package name). pkg-config discovery is already working (`pkg-config --libs bmiwrfhydrof` returns correct flags). All prerequisites from Phase 5 are in place.

**Primary recommendation:** Install babelizer 0.3.9 from conda-forge (not the develop branch), write babel.toml following the pymt_heatf pattern, run `babelize init babel.toml` to generate pymt_wrfhydro/, then verify the generated bmi_interoperability.f90 contains correct `use bmiwrfhydrof` and `type (bmi_wrf_hydro)` references.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- pymt_wrfhydro/ generated at project root (alongside bmi_wrf_hydro/, wrf_hydro_nwm_public/)
- babel.toml also at project root (standard babelizer convention)
- pymt_wrfhydro/ tracked in git (will be customized in Phase 7, needs version control)
- Commit skeleton only after verification passes (not immediately after generation)
- Naming chain locked per requirements: `library = "bmiwrfhydrof"`, `entry_point = "bmi_wrf_hydro"`, `package.name = "pymt_wrfhydro"`
- Runtime requirements: mpi4py + netCDF4 (WRF-Hydro needs MPI and NetCDF at runtime)
- Build libraries: rely on pkg-config discovery (bmiwrfhydrof.pc already includes transitive deps)
- Install all babelizer toolchain packages into existing wrfhydro-bmi conda env (not a separate env)
- Snapshot env first (`conda env export`) before installing, for rollback safety
- Install all 6 packages in one command: babelizer, meson-python, meson, ninja, cython, python-build
- If dependency conflicts arise: resolve them (update packages, adjust pins) rather than creating a separate env
- File checklist: verify bmi_interoperability.f90, .pyx wrapper, meson.build, pyproject.toml, __init__.py all exist
- Inspect bmi_interoperability.f90 content: confirm it USEs correct Fortran module name (bmiwrfhydrof) and calls correct procedures
- Quick dry-run build attempt after skeleton verification (knowing it may fail -- fixes are Phase 7's job)
- Document build failure details (exact error + likely fix) to give Phase 7 planner a head start

### Claude's Discretion
- Python version constraint in babel.toml (pick based on babelizer defaults and conda env)
- Package metadata level (author, license, description -- keep appropriate for research tool)
- Whether pkg-config alone suffices or extra build flags needed in babel.toml

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ENV-01 | 6 conda packages installed: babelizer, meson-python, meson, ninja, cython, python-build | Standard Stack section covers exact package names, versions, and installation command. Babelizer 0.3.9 also pulls cookiecutter, gitpython, tomlkit, black, isort, click as dependencies. |
| ENV-02 | `babel.toml` written with correct naming chain and mpi4py in requirements | Code Examples section provides complete babel.toml with verified naming chain. Architecture Patterns section explains each field. |
| ENV-03 | `babelize init babel.toml` generates `pymt_wrfhydro/` with all auto-generated files | Architecture Patterns section documents exact generated directory structure and file inventory. Common Pitfalls covers verification steps. |
</phase_requirements>

## Standard Stack

### Core
| Package | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| babelizer | 0.3.9 (conda-forge) | CLI tool that generates Python bindings from babel.toml | Only stable release; conda-forge default; Python 3.10 compatible |
| cython | 3.0+ (conda-forge) | Compiles .pyx wrappers into C extensions | Required by babelizer-generated setup.py for Extension compilation |
| numpy | 2.2.6 (already installed) | Provides numpy.distutils.fcompiler for Fortran compilation | Already in env; babelizer 0.3.9 setup.py uses numpy.distutils |
| meson-python | 0.17+ (conda-forge) | Meson-based PEP 517 build backend | Listed in user requirements; needed for Phase 7 if switching to Meson build |
| meson | 1.6+ (conda-forge) | Build system for compiled extensions | Listed in user requirements; used by meson-python |
| ninja | 1.12+ (conda-forge) | Build executor for Meson | Listed in user requirements; backend for meson builds |
| python-build | 1.4+ (conda-forge) | PEP 517 build frontend | Listed in user requirements; enables `python -m build` |

### Supporting (auto-installed as babelizer 0.3.9 dependencies)
| Package | Version | Purpose | When Installed |
|---------|---------|---------|---------------|
| cookiecutter | latest | Template rendering engine for 0.3.9 | Auto-dependency of babelizer 0.3.9 |
| gitpython | latest | Git repository initialization | Auto-dependency of babelizer 0.3.9 |
| tomlkit | latest | TOML file parsing | Auto-dependency of babelizer 0.3.9 |
| black | latest | Code formatting | Auto-dependency of babelizer 0.3.9 |
| isort | >=5 | Import sorting | Auto-dependency of babelizer 0.3.9 |
| click | latest | CLI framework | Auto-dependency of babelizer 0.3.9 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| babelizer 0.3.9 (conda-forge) | babelizer develop branch (0.3.10.dev0, pip install from GitHub) | Develop uses Meson instead of setuptools; requires Python >= 3.11 (we have 3.10); not a stable release; would require Python upgrade which risks breaking WRF-Hydro deps |
| setuptools build (0.3.9 generated) | meson-python build (develop generated) | Meson is the future but 0.3.9 setuptools works with Python 3.10 + numpy.distutils; switching to Meson can be done in Phase 7 if needed |
| conda-forge install | pip install from PyPI | conda-forge ensures compiler compatibility; pip may install incompatible compiler toolchains |

**Installation:**
```bash
# Snapshot first (rollback safety)
conda env export > wrfhydro-bmi-snapshot-$(date +%Y%m%d).yml

# Install all packages in one command
conda install -c conda-forge babelizer meson-python meson ninja cython python-build
```

**CRITICAL NOTE on version choice:** The user's requirements list meson-python, meson, ninja as packages to install. These are needed for Phase 7 (build) even though babelizer 0.3.9 generates setuptools-based packages. The generated skeleton will include a `setup.py` (not `meson.build`). The meson toolchain is installed now as preparation for potential migration to Meson in Phase 7 or for use with the develop branch if needed as a fallback.

## Architecture Patterns

### Babelizer Naming Chain (CRITICAL)
The naming chain must be exactly right or the generated code won't link.

```
babel.toml                    Fortran Source                 Shared Library
─────────────                 ──────────────                 ──────────────
library = "bmiwrfhydrof"  ←→  module bmiwrfhydrof       ←→  libbmiwrfhydrof.so
entry_point = "bmi_wrf_hydro" ←→  type (bmi_wrf_hydro)
package.name = "pymt_wrfhydro"

What babelizer generates in bmi_interoperability.f90:
  use bmiwrfhydrof             ← from library field
  type (bmi_wrf_hydro)         ← from entry_point field
```

Verified against heat model pattern:
- Heat: module `bmiheatf`, type `bmi_heat`, library `bmiheatf`, entry_point `bmi_heat`
- WRF-Hydro: module `bmiwrfhydrof`, type `bmi_wrf_hydro`, library `bmiwrfhydrof`, entry_point `bmi_wrf_hydro`

### [library.ClassName] Section Name Convention
The key in `[library.WrfHydroBmi]` becomes the Python class name (CamelCase). This is what users import:
```python
from pymt_wrfhydro import WrfHydroBmi
```

The heat model uses `[library.HeatF]` -> class `HeatF`.

### Generated Directory Structure (babelizer 0.3.9)
Running `babelize init babel.toml` in the project root generates:

```
pymt_wrfhydro/                        # Generated package directory
├── .github/
│   └── workflows/                    # CI/CD workflows (GitHub Actions)
├── docs/                             # Sphinx documentation stubs
├── recipe/                           # Conda-forge recipe template
├── pymt_wrfhydro/                    # Python package source
│   ├── __init__.py                   # Package init (imports WrfHydroBmi)
│   ├── bmi.py                        # High-level BMI Python class
│   └── lib/                          # Compiled extension directory
│       ├── __init__.py               # Lib package init
│       ├── _fortran.pyx              # ★ Cython wrapper for Fortran BMI
│       ├── bmi_interoperability.f90  # ★ Auto-generated Fortran C bindings
│       └── bmi_interoperability.h    # ★ C header for Cython to call
├── .gitignore
├── CHANGES.rst
├── CREDITS.rst
├── LICENSE
├── MANIFEST.in
├── Makefile
├── README.rst
├── pyproject.toml
├── setup.py                          # ★ Build script (setuptools + numpy.distutils)
├── setup.cfg                         # Linting config
├── requirements.txt
├── requirements-build.txt
├── requirements-library.txt
└── requirements-testing.txt
```

**Key files to verify (Phase 6 success criteria):**
1. `pymt_wrfhydro/pymt_wrfhydro/lib/bmi_interoperability.f90` -- must contain `use bmiwrfhydrof` and `type (bmi_wrf_hydro)`
2. `pymt_wrfhydro/pymt_wrfhydro/lib/_fortran.pyx` -- Cython wrapper (named `wrfhydrobmi.pyx` or similar based on class name)
3. `pymt_wrfhydro/setup.py` -- build script with Fortran compilation logic
4. `pymt_wrfhydro/pyproject.toml` -- project metadata
5. `pymt_wrfhydro/pymt_wrfhydro/__init__.py` -- package init

**NOTE on .pyx naming:** The .pyx filename is derived from the class name in `[library.WrfHydroBmi]`. In the heat example with `[library.HeatModelF]`, the .pyx is `heatmodelf.pyx` (lowercased). For `[library.WrfHydroBmi]`, expect `wrfhydrobmi.pyx`.

### bmi_interoperability.f90 Architecture
The auto-generated Fortran file creates:
- A module `bmi_interoperability` with `use, intrinsic :: iso_c_binding`
- Imports our BMI module: `use bmiwrfhydrof`
- Manages up to 2048 model instances via array pool
- Wraps ALL 41+ BMI functions with `bind(c)` for C-callable interface
- Handles Fortran string <-> C char array conversion
- Returns integer status codes matching BMI conventions

This is exactly what our removed `bmi_wrf_hydro_c.f90` did, but auto-generated correctly.

### Pattern: babel.toml for WRF-Hydro

```toml
[library.WrfHydroBmi]
language = "fortran"
library = "bmiwrfhydrof"
header = ""
entry_point = "bmi_wrf_hydro"

[build]
undef_macros = []
define_macros = []
libraries = []
library_dirs = []
include_dirs = []
extra_compile_args = []

[package]
name = "pymt_wrfhydro"
requirements = ["mpi4py", "netCDF4"]

[info]
github_username = "VT-Hydroinformatics"
package_author = "Mohan Sai Movva"
package_author_email = ""
package_license = "MIT"
summary = "PyMT plugin for the WRF-Hydro hydrological model"

[ci]
python_version = ["3.10"]
os = ["linux"]
```

**Key decisions reflected:**
- `[library.WrfHydroBmi]` -- CamelCase class name matching CSDMS convention
- `header = ""` -- Fortran models have no C header (babelizer generates bmi_interoperability.h)
- `requirements = ["mpi4py", "netCDF4"]` -- runtime deps per user decision
- `[build]` all empty -- pkg-config handles library discovery; no extra flags needed
- `[ci]` -- Python 3.10 and linux only (our environment)

### Anti-Patterns to Avoid
- **Setting library/include_dirs in [build] manually:** pkg-config handles this. The babelizer-generated setup.py calls `pkg-config --libs --cflags bmiwrfhydrof` to find our library.
- **Using the develop branch without necessity:** Version 0.3.9 is tested and stable. The develop branch requires Python 3.11+ and is unreleased.
- **Committing before verifying:** The skeleton must pass file existence checks AND content verification before committing to git.
- **Including C/C++ .pyx files:** Babelizer generates `_c.pyx`, `_cxx.pyx`, AND `_fortran.pyx` but only the Fortran one is used. This is normal -- the others are dormant templates.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fortran-to-C interop layer | Custom `bmi_wrf_hydro_c.f90` (we removed this in Phase 5!) | babelizer's auto-generated `bmi_interoperability.f90` | Covers all 41+ BMI functions correctly, handles string conversion, manages multi-instance pool |
| Cython wrapper | Custom `.pyx` file | babelizer's auto-generated `_fortran.pyx` (or `wrfhydrobmi.pyx`) | Type-safe, handles numpy/C memory correctly, error handling via `ok_or_raise()` |
| Python package structure | Manual `__init__.py` + `setup.py` | babelizer's complete skeleton | Correct entry points, PyMT plugin registration, metadata |
| babel.toml | Guessing field names | Follow pymt_heatf example exactly | One wrong field name -> broken generated code |

**Key insight:** The entire point of the babelizer is that you do NOT write any of the Python/Cython/interop code yourself. You write babel.toml (10-20 lines), run one command, and get a complete package. Phase 5 removed our hand-written C bindings precisely because they conflicted with what the babelizer generates.

## Common Pitfalls

### Pitfall 1: Wrong naming chain breaks linking
**What goes wrong:** `babelize init` generates code that compiles but fails to link because the Fortran module name or type name doesn't match what's in the shared library.
**Why it happens:** The `library` field in babel.toml must exactly match the Fortran `module` name (lowercase, as gfortran mangles it). The `entry_point` must exactly match the Fortran `type` name.
**How to avoid:** Verify naming chain before running babelize init:
```bash
# Module name in source
grep "^module bmiwrfhydrof" bmi_wrf_hydro/src/bmi_wrf_hydro.f90
# Type name in source
grep "type.*extends.*bmi.*::.*bmi_wrf_hydro" bmi_wrf_hydro/src/bmi_wrf_hydro.f90
# Library name
ls $CONDA_PREFIX/lib/libbmiwrfhydrof.so
# .mod file
ls $CONDA_PREFIX/include/bmiwrfhydrof.mod
```
**Warning signs:** `babelize init` succeeds but generated `bmi_interoperability.f90` has wrong `use` or `type` statements.

### Pitfall 2: conda dependency conflicts during install
**What goes wrong:** Installing babelizer + 5 other packages triggers solver conflicts with existing packages (gfortran, MPI, NetCDF, etc.).
**Why it happens:** The wrfhydro-bmi env has specific compiler toolchain versions pinned. New packages may request incompatible versions.
**How to avoid:** Snapshot env before install. Use `--dry-run` first. Install all 6 in one command (lets solver find global solution). If conflicts arise, try `conda install --update-deps`.
**Warning signs:** Solver takes > 5 minutes, or reports "UnsatisfiableError".

### Pitfall 3: babelize init creates directory in wrong location
**What goes wrong:** `babelize init` creates `pymt_wrfhydro/` inside current directory. If run from wrong directory, skeleton lands in wrong place.
**Why it happens:** babelize init uses CWD as output location.
**How to avoid:** Always `cd` to project root before running `babelize init babel.toml`. Verify with `ls pymt_wrfhydro/` after.
**Warning signs:** `pymt_wrfhydro/` not at project root level.

### Pitfall 4: babelizer 0.3.9 generates setup.py (not meson.build)
**What goes wrong:** User expects meson.build (from readthedocs docs which track develop branch) but gets setup.py.
**Why it happens:** conda-forge only has 0.3.9 (released 2022-03-04). The develop branch (0.3.10.dev0) switched to Meson but hasn't been released. ReadTheDocs `latest` docs track the develop branch, creating confusion.
**How to avoid:** Know that 0.3.9 generates setuptools-based packages. This is fine for Python 3.10 + numpy.distutils. The phase success criteria should check for setup.py (not meson.build) as the build file.
**Warning signs:** Looking for meson.build in generated output and not finding it.

**IMPORTANT CLARIFICATION:** The CONTEXT.md file checklist mentions "meson.build" as a file to verify. However, babelizer 0.3.9 generates `setup.py` instead of `meson.build`. The success criteria should be adjusted: either accept setup.py from 0.3.9, OR install babelizer from develop branch to get meson.build. This is flagged as an Open Question below.

### Pitfall 5: setuptools version incompatibility with numpy.distutils
**What goes wrong:** The generated setup.py uses `numpy.distutils.fcompiler` which may break with very new setuptools versions.
**Why it happens:** numpy.distutils is deprecated (since NumPy 1.23) and only tested with setuptools < 60. Our env has setuptools 80.10.2.
**How to avoid:** If build fails in Phase 7, pin setuptools: `conda install "setuptools<65"`. Or switch to Meson build approach (develop branch).
**Warning signs:** ImportError or AttributeError from numpy.distutils during `pip install .`

### Pitfall 6: Forgetting `--no-build-isolation` during build (Phase 7 concern)
**What goes wrong:** `pip install .` downloads its own compilers from PyPI which are incompatible with conda's gfortran/MPI.
**Why it happens:** PEP 517 build isolation installs build deps from PyPI, but Fortran compilers from PyPI don't match conda toolchain.
**How to avoid:** Always use `pip install --no-build-isolation .` (already a locked decision in STATE.md).
**Warning signs:** Compiler errors about missing libraries or wrong ABI.

## Code Examples

### Complete babel.toml (verified against pymt_heatf pattern)
```toml
# babel.toml — WRF-Hydro BMI babelizer configuration
# Source: Adapted from pymt_heatf (https://github.com/pymt-lab/pymt_heatf/blob/main/babel.toml)

[library.WrfHydroBmi]
language = "fortran"
library = "bmiwrfhydrof"
header = ""
entry_point = "bmi_wrf_hydro"

[build]
undef_macros = []
define_macros = []
libraries = []
library_dirs = []
include_dirs = []
extra_compile_args = []

[package]
name = "pymt_wrfhydro"
requirements = ["mpi4py", "netCDF4"]

[info]
github_username = "VT-Hydroinformatics"
package_author = "Mohan Sai Movva"
package_author_email = ""
package_license = "MIT"
summary = "PyMT plugin for the WRF-Hydro hydrological model"

[ci]
python_version = ["3.10"]
os = ["linux"]
```

### Verification Script (post babelize init)
```bash
# Verify generated files exist
echo "=== File Existence Check ==="
test -d pymt_wrfhydro && echo "PASS: pymt_wrfhydro/ directory exists" || echo "FAIL: no pymt_wrfhydro/"
test -f pymt_wrfhydro/setup.py && echo "PASS: setup.py exists" || echo "FAIL: no setup.py"
test -f pymt_wrfhydro/pyproject.toml && echo "PASS: pyproject.toml exists" || echo "FAIL: no pyproject.toml"
test -f pymt_wrfhydro/pymt_wrfhydro/__init__.py && echo "PASS: __init__.py exists" || echo "FAIL: no __init__.py"

# Find the interop files (path may vary)
INTEROP=$(find pymt_wrfhydro -name "bmi_interoperability.f90" 2>/dev/null)
test -n "$INTEROP" && echo "PASS: bmi_interoperability.f90 at $INTEROP" || echo "FAIL: no bmi_interoperability.f90"

PYX=$(find pymt_wrfhydro -name "*.pyx" 2>/dev/null | head -1)
test -n "$PYX" && echo "PASS: .pyx file at $PYX" || echo "FAIL: no .pyx file"

# Verify naming chain in generated interop
echo ""
echo "=== Naming Chain Verification ==="
grep "use bmiwrfhydrof" $INTEROP && echo "PASS: correct module USE" || echo "FAIL: wrong module USE"
grep "bmi_wrf_hydro" $INTEROP && echo "PASS: correct type reference" || echo "FAIL: wrong type reference"
```

### Expected bmi_interoperability.f90 content (key lines)
```fortran
module bmi_interoperability
  use, intrinsic :: iso_c_binding
  use bmif_2_0                        ! BMI abstract interface
  use bmiwrfhydrof                    ! ← Our module (from library field)

  implicit none

  integer, parameter :: N_MODELS = 2048
  type (bmi_wrf_hydro) :: model_array(N_MODELS)  ! ← Our type (from entry_point field)
  logical :: model_avail(N_MODELS) = .true.

  ! ... 40+ bind(c) wrapper functions follow ...
end module bmi_interoperability
```

### Conda Environment Snapshot (pre-install safety)
```bash
conda env export > wrfhydro-bmi-snapshot-$(date +%Y%m%d).yml
```

### babelize init Command
```bash
cd /mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI
babelize init babel.toml
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| cookiecutter templates + setuptools (0.3.9) | Jinja2 templates + meson-python (develop) | 2025-02-18 (unreleased) | Generated packages switch from setup.py to meson.build |
| numpy.distutils for Fortran compilation | meson for Fortran compilation | NumPy 1.23+ deprecation | Python 3.12+ removes numpy.distutils entirely |
| Custom C binding layers (bmi_wrf_hydro_c.f90) | babelizer auto-generated bmi_interoperability.f90 | Phase 5 decision | No hand-written C bindings needed |

**Deprecated/outdated:**
- `babelizer.wrap` module: Removed in develop branch, replaced by `babelizer.render()`
- numpy.distutils: Deprecated in NumPy 1.23, removed for Python >= 3.12. Still works for Python 3.10.
- setuptools-based Fortran builds: Moving to Meson industry-wide (SciPy, NumPy already migrated)

**Current status for our project:** Python 3.10 + babelizer 0.3.9 + numpy.distutils is a working combination. The setuptools path is deprecated but functional. If we hit build issues in Phase 7, upgrading Python to 3.11+ and installing babelizer from develop (Meson path) is the fallback.

## Open Questions

1. **setup.py vs meson.build in generated skeleton**
   - What we know: Babelizer 0.3.9 (conda-forge) generates `setup.py`. The develop branch generates `meson.build`. The CONTEXT.md checklist mentions verifying "meson.build" exists.
   - What's unclear: Does the user expect meson.build specifically, or is setup.py acceptable? The pymt_heatf example on GitHub has been updated to use meson.build (develop branch version).
   - Recommendation: Install 0.3.9 first (stable, compatible). Verify with setup.py. If the user specifically wants meson.build, install babelizer from develop: `pip install git+https://github.com/csdms/babelizer.git@develop` (requires Python 3.11+ upgrade). Document both paths in the plan. **Adjust Phase 6 success criteria to accept setup.py OR meson.build depending on which babelizer version is installed.**

2. **setuptools 80.10.2 compatibility with numpy.distutils**
   - What we know: numpy.distutils is only tested with setuptools < 60. Our env has 80.10.2. numpy.distutils.fcompiler DOES work (tested: returns gfortran path correctly).
   - What's unclear: Whether the full build_ext pipeline works with setuptools 80. This is a Phase 7 concern, not Phase 6.
   - Recommendation: Note as a risk. If Phase 7 build fails, first try `SETUPTOOLS_USE_DISTUTILS=stdlib pip install --no-build-isolation .`, then try pinning setuptools < 65.

3. **Exact .pyx filename**
   - What we know: The heat example with `[library.HeatModelF]` generates `heatmodelf.pyx` (lowercased class name). For `[library.HeatF]` in babel.toml, the class is `HeatF` and the file is `_fortran.pyx` or derived name.
   - What's unclear: Exact naming pattern for `[library.WrfHydroBmi]`. Could be `wrfhydrobmi.pyx` or `_fortran.pyx`.
   - Recommendation: Don't hardcode .pyx filename in verification. Use `find pymt_wrfhydro -name "*.pyx"` to locate it.

## Sources

### Primary (HIGH confidence)
- [Babelizer ReadTheDocs - Fortran Example](https://babelizer.readthedocs.io/en/latest/example-fortran.html) - Complete step-by-step Fortran wrapping guide (develop branch docs)
- [Babelizer ReadTheDocs - README](https://babelizer.readthedocs.io/en/latest/readme.html) - babel.toml format, installation, overview
- [Babelizer ReadTheDocs - CLI](https://babelizer.readthedocs.io/en/latest/cli.html) - babelize init command syntax and options
- [pymt_heatf GitHub repo](https://github.com/pymt-lab/pymt_heatf) - Reference babelized Fortran package (generated from bmi-example-fortran)
- [pymt_heatf/babel.toml](https://github.com/pymt-lab/pymt_heatf/blob/main/babel.toml) - Reference babel.toml for Fortran BMI model
- [Babelizer GitHub - v0.3.9 templates](https://github.com/csdms/babelizer/tree/v0.3.9/babelizer/data) - Cookiecutter template structure for 0.3.9
- [Babelizer GitHub - develop templates](https://github.com/csdms/babelizer/tree/develop/babelizer/data/templates) - Jinja2 template structure for develop
- [Anaconda.org babelizer](https://anaconda.org/conda-forge/babelizer) - conda-forge package info (version 0.3.9)
- [Babelizer changelog](https://babelizer.readthedocs.io/en/latest/changelog.html) - Version history showing Meson switch is unreleased

### Secondary (MEDIUM confidence)
- [conda-forge babelizer-feedstock](https://github.com/conda-forge/babelizer-feedstock) - Recipe confirms version 0.3.9, Python >= 3.8
- [NumPy distutils migration](https://numpy.org/doc/stable/reference/distutils_status_migration.html) - numpy.distutils deprecation timeline
- [Babelizer GitHub develop pyproject.toml](https://github.com/csdms/babelizer/blob/develop/pyproject.toml) - Develop branch requires Python 3.11+

### Tertiary (LOW confidence)
- setuptools 80 + numpy.distutils compatibility: Only tested locally (fcompiler detection works); full build_ext pipeline not verified. Flag for Phase 7 validation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - conda-forge package versions verified, dependencies checked, naming chain confirmed against source code and reference examples
- Architecture: HIGH - Template structure verified from both 0.3.9 tag and develop branch on GitHub; pymt_heatf reference package examined
- Pitfalls: HIGH - Version mismatch (0.3.9 vs develop) identified and documented; numpy.distutils deprecation researched; naming chain verified against actual source

**Research date:** 2026-02-24
**Valid until:** 2026-03-24 (stable -- babelizer hasn't released since 2022)
