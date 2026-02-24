# Architecture Patterns

**Domain:** Babelizing a Fortran BMI shared library into a PyMT Python package
**Researched:** 2026-02-24
**Confidence:** HIGH (verified against pymt_heatf reference implementation, babelizer source templates, official documentation)

## Recommended Architecture

The babelizer integration follows a well-defined data flow from `babel.toml` configuration through auto-generated code to a working Python package. The architecture has **three distinct phases**: configuration, code generation, and build/install. Each phase produces artifacts consumed by the next.

The critical insight verified by examining the pymt_heatf reference implementation is that **the babelizer does NOT use our existing C binding layer** (`bmi_wrf_hydro_c.f90`). Instead, it auto-generates its own complete `bmi_interoperability.f90` file (~818 lines) with a multi-instance "box" pattern wrapping all 41 BMI functions. Our C binding layer (10 functions, singleton pattern) was test infrastructure only.

```
DATA FLOW: babel.toml -> pymt_wrfhydro Python Package

PHASE 1: CONFIGURATION
========================
    babel.toml                          WRF-Hydro Prerequisites
    +-----------------------+           +---------------------------+
    | [library.WrfHydroF]   |           | libbmiwrfhydrof.so        |
    | language = "fortran"  |           | bmiwrfhydrof.pc           |
    | library = "bmiwrfhydrof"|         | bmiwrfhydrof.mod          |
    | entry_point = "bmi_wrf_hydro" |   | (installed to $CONDA_PREFIX)|
    +-----------------------+           +---------------------------+
              |                                    |
              v                                    |
PHASE 2: CODE GENERATION                          |
========================                           |
    $ babelize init babel.toml                     |
              |                                    |
              v                                    |
    pymt_wrfhydro/  (auto-generated)               |
    +------------------------------------------+   |
    | pymt_wrfhydro/                            |   |
    |   __init__.py         (imports WrfHydroF) |   |
    |   _bmi.py             (re-exports class)  |   |
    |   lib/                                    |   |
    |     __init__.py                           |   |
    |     bmi_interoperability.f90  (818 lines) |---+  <-- links against .so
    |     bmi_interoperability.h    (C header)  |   |
    |     wrfhydrof.pyx     (Cython wrapper)    |   |
    | meta/WrfHydroF/                           |   |
    |   api.yaml, info.yaml, run.yaml, etc.     |   |
    | meson.build           (build system)      |---+  <-- pkg-config discovery
    | pyproject.toml        (Python packaging)  |
    | babel.toml            (preserved config)  |
    +------------------------------------------+
              |
              v
PHASE 3: BUILD & INSTALL
========================
    $ pip install . --no-build-isolation
              |
              v
    Meson Build System
    +------------------------------------------+
    | 1. pkg-config --libs bmiwrfhydrof        |---> Finds libbmiwrfhydrof.so
    | 2. pkg-config --libs bmif                |---> Finds libbmif.so
    | 3. Compile bmi_interoperability.f90      |---> .o file
    | 4. Cython compile wrfhydrof.pyx -> .c    |---> C extension
    | 5. Link .o + .c + deps -> wrfhydrof.so   |---> Python extension module
    | 6. Install to site-packages/pymt_wrfhydro|
    +------------------------------------------+
              |
              v
    RESULT: Working Python Package
    +------------------------------------------+
    | >>> from pymt_wrfhydro import WrfHydroF   |
    | >>> m = WrfHydroF()                       |
    | >>> m.initialize("config.nml")            |
    | >>> m.update()                             |
    | >>> vals = m.get_value("channel_water_...") |
    | >>> m.finalize()                           |
    +------------------------------------------+
```

### Component Boundaries

| Component | Files | Responsibility | Communicates With |
|-----------|-------|----------------|-------------------|
| **babel.toml** | 1 file (we write) | Configuration: library name, entry point, package name, build settings | babelize init command |
| **babelize init** | babelizer CLI tool | Template rendering: generates entire pymt_wrfhydro package from babel.toml + Jinja2 templates | babel.toml (input), pymt_wrfhydro/ directory (output) |
| **bmi_interoperability.f90** | 1 file (auto-generated) | C interop bridge: wraps ALL 41 BMI functions with ISO_C_BINDING bind(C), multi-instance box pattern | `use bmiwrfhydrof` -> our BMI module; linked into Cython extension |
| **bmi_interoperability.h** | 1 file (auto-generated) | C header: declares all functions from .f90 for Cython `cdef extern` | Consumed by .pyx file |
| **wrfhydrof.pyx** | 1 file (auto-generated) | Cython extension: Python class WrfHydroF with all BMI methods, type-dispatched get/set, numpy array I/O | Calls C functions from bmi_interoperability.h; imports numpy |
| **meson.build** | 1 file (auto-generated) | Build system: discovers deps via pkg-config, compiles Fortran + Cython, builds Python extension | pkg-config -> bmiwrfhydrof.pc, bmif.pc |
| **pyproject.toml** | 1 file (auto-generated) | Python packaging: meson-python backend, dependencies, pymt.plugins entry point | pip, meson-python build backend |
| **meta/WrfHydroF/** | 5 files (we write) | Model metadata: API description, parameters, config, run settings | PyMT framework for model registration |
| **libbmiwrfhydrof.so** | 1 file (pre-existing) | Fortran shared library with all 41 BMI functions + 22 WRF-Hydro static libs baked in | Linked by Meson at build time; loaded at Python runtime |
| **bmiwrfhydrof.pc** | 1 file (pre-existing) | pkg-config discovery: tells Meson where to find .so and .mod files | Meson `dependency('bmiwrfhydrof', method: 'pkg-config')` |

### Data Flow: From Python Call to Fortran Execution

When a Python user calls `m.get_value("channel_water__volume_flow_rate", buffer)`, the data flows through 4 layers:

```
Layer 4: Python (user code)
  m.get_value("channel_water__volume_flow_rate", buffer)
       |
       v
Layer 3: Cython (wrfhydrof.pyx / wrfhydrof.cpython-3xx-x86_64-linux-gnu.so)
  WrfHydroF.get_value(self, var_name, buffer):
    - Queries var type via bmi_get_var_type()
    - Dispatches to bmi_get_value_double() for "double precision"
    - Fills numpy buffer with data from C double array
       |
       v
Layer 2: Fortran C-interop (bmi_interoperability.f90, compiled into extension)
  bmi_get_value_double(model_index, name, dest):
    - Converts C string to Fortran string
    - Calls model_array(model_index)%get_value_double(name, dest)
    - Returns BMI_SUCCESS/BMI_FAILURE as int
       |
       v
Layer 1: Fortran BMI wrapper (libbmiwrfhydrof.so)
  bmi_wrf_hydro%get_value_double(name, dest):
    - Maps CSDMS name to internal WRF-Hydro array
    - Copies from rt_domain(1)%QLINK(:,1) to dest(:)
    - Returns BMI_SUCCESS
       |
       v
Layer 0: WRF-Hydro internals (22 static libs baked into .so)
  rt_domain(1)%QLINK(:,1)  -- streamflow at all channel reaches
```

## Patterns to Follow

### Pattern 1: entry_point Maps to Fortran Type Name

**What:** The `entry_point` field in babel.toml is the **Fortran derived type name** that extends BMI, NOT a function name or module name.

**Verified from pymt_heatf:**
- babel.toml: `library = "bmiheatf"`, `entry_point = "bmi_heat"`
- bmi_heat.f90: `module bmiheatf` contains `type, extends(bmi) :: bmi_heat`
- bmi_interoperability.f90: `use bmiheatf` then `type(bmi_heat) :: model_array(N_MODELS)`

**For WRF-Hydro:**
- babel.toml: `library = "bmiwrfhydrof"`, `entry_point = "bmi_wrf_hydro"`
- bmi_wrf_hydro.f90: `module bmiwrfhydrof` contains `type, extends(bmi) :: bmi_wrf_hydro`
- Auto-generated bmi_interoperability.f90 will: `use bmiwrfhydrof` then `type(bmi_wrf_hydro) :: model_array(N_MODELS)`

**Confidence:** HIGH -- directly verified from pymt_heatf source code.

### Pattern 2: Box/Handle Pattern (Multi-Instance)

**What:** The babelizer-generated `bmi_interoperability.f90` uses a static array of model instances (N_MODELS = 2048) with availability tracking. Each `bmi_new()` call returns an integer handle (1-2048). All subsequent BMI calls pass this handle to identify which model instance to operate on.

**Why it matters for WRF-Hydro:** WRF-Hydro cannot support multiple instances (module globals are singletons). However, the babelizer always generates the box pattern. This is fine -- it just means only model_array(1) will ever be used in practice, and calling bmi_new() a second time would succeed at the interop level but WRF-Hydro's internal `wrfhydro_engine_initialized` flag would prevent re-initialization.

**Our existing C binding uses a singleton pattern** (module-level `the_model` variable with `is_registered` guard). The babelizer's box pattern supersedes this. Our C binding layer is NOT used by the babelizer.

```
OUR C BINDING (test-only):          BABELIZER GENERATED (production):
+-------------------------+         +------------------------------------+
| bmi_wrf_hydro_c_mod     |         | bmi_interoperability               |
|  the_model (singleton)  |         |  model_array(2048) + model_avail() |
|  is_registered flag     |         |  bmi_new() -> returns handle       |
|  10 bind(C) functions   |         |  41+ bind(C) functions             |
|  Used by: ctypes tests  |         |  Used by: Cython extension         |
+-------------------------+         +------------------------------------+
```

**Confidence:** HIGH -- verified from babelizer template source and pymt_heatf implementation.

### Pattern 3: pkg-config Discovery Chain

**What:** The babelizer's Meson build system discovers all Fortran dependencies via pkg-config, not direct filesystem paths. The discovery chain is:

```
meson.build
  dependency('bmiwrfhydrof', method: 'pkg-config')
       |
       v
  $PKG_CONFIG_PATH / $CONDA_PREFIX/lib/pkgconfig/bmiwrfhydrof.pc
       |
       v
  Libs: -L${libdir} -lbmiwrfhydrof
  Requires: bmif
       |
       v
  $CONDA_PREFIX/lib/pkgconfig/bmif.pc
       |
       v
  Libs: -L${libdir} -lbmif
```

**Prerequisite:** `libbmiwrfhydrof.so` and `bmiwrfhydrof.pc` MUST be installed to `$CONDA_PREFIX/lib/` and `$CONDA_PREFIX/lib/pkgconfig/` respectively BEFORE running `babelize init` or building the generated package.

**Our current state:** This is already done. The CMake install step (`cmake --install _build`) puts everything in the right place. Verified with `pkg-config --libs bmiwrfhydrof` returning `-L.../lib -lbmiwrfhydrof`.

**Confidence:** HIGH -- verified from pymt_heatf meson.build and our installed bmiwrfhydrof.pc.

### Pattern 4: Cython Type Dispatch for get_value/set_value

**What:** The Cython extension queries the variable type via `bmi_get_var_type()` and dispatches to the appropriate typed function:

```python
# Simplified from wrfhydrof.pyx
def get_value(self, var_name, buffer):
    var_type = self.get_var_type(var_name)
    if var_type == "double precision":
        bmi_get_value_double(self._model_index, name_bytes, <double*>buffer.data)
    elif var_type == "real":
        bmi_get_value_float(self._model_index, name_bytes, <float*>buffer.data)
    elif var_type == "integer":
        bmi_get_value_int(self._model_index, name_bytes, <int*>buffer.data)
```

**For WRF-Hydro:** Our `get_var_type()` returns `"double precision"` for all variables because the BMI wrapper converts WRF-Hydro's single-precision REAL to double. This means only `bmi_get_value_double()` will be called in practice.

**Confidence:** HIGH -- verified from pymt_heatf Cython source.

### Pattern 5: PyMT Plugin Entry Point Registration

**What:** The generated `pyproject.toml` registers the babelized class as a PyMT plugin via entry points:

```toml
[project.entry-points."pymt.plugins"]
WrfHydroF = "pymt_wrfhydro._bmi:WrfHydroF"
```

This allows PyMT to discover the model via:
```python
import pymt.models
pymt.models.WrfHydroF  # auto-discovered via entry point
```

**Confidence:** HIGH -- verified from pymt_heatf pyproject.toml.

### Pattern 6: Model Metadata Directory (meta/)

**What:** PyMT requires a `meta/WrfHydroF/` directory with YAML metadata files:

| File | Purpose | Content |
|------|---------|---------|
| `api.yaml` | Variable names, grids, exchange items | Input/output var names, grid types |
| `info.yaml` | Model description, author, license | Human-readable model card |
| `parameters.yaml` | Configurable parameters and defaults | Namelist parameters exposed to PyMT |
| `run.yaml` | Runtime configuration template | Config file paths, working directory |
| `heat.cfg` (or equivalent) | Example/default config file | Template configuration for testing |

**For WRF-Hydro:** We need to create `meta/WrfHydroF/` with WRF-Hydro-specific metadata. The `api.yaml` should list our 8 output + 4 input CSDMS standard names and 3 grid types.

**Confidence:** MEDIUM -- verified structure from pymt_heatf, but WRF-Hydro content must be created manually.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Writing bmi_interoperability.f90 by Hand

**What:** Manually coding the C interop layer for all 41 BMI functions.

**Why bad:** The babelizer auto-generates this file (~818 lines) from templates, customized to match the entry_point and library specified in babel.toml. Hand-writing it duplicates effort, introduces bugs, and creates maintenance burden when the babelizer template evolves.

**Instead:** Let `babelize init` generate it. Our existing `bmi_wrf_hydro_c.f90` (10 functions, 335 lines) served its purpose for pre-babelizer testing and should NOT be extended.

### Anti-Pattern 2: Modifying Auto-Generated Files

**What:** Editing files that `babelize init` produces (bmi_interoperability.f90, wrfhydrof.pyx, meson.build, pyproject.toml).

**Why bad:** `babelize update` regenerates these files from templates, overwriting manual changes. The babelizer uses a cookie-cutter approach -- regeneration is expected.

**Instead:** For customization, modify `babel.toml` configuration or the `meta/` metadata files. If Cython code needs changes, contribute upstream to the babelizer templates.

### Anti-Pattern 3: Building pymt_wrfhydro Before Installing libbmiwrfhydrof.so

**What:** Running `pip install .` in the generated pymt_wrfhydro directory without first installing the shared library to `$CONDA_PREFIX`.

**Why bad:** Meson calls `pkg-config --libs bmiwrfhydrof` which fails if the .pc file is not in the search path. The build silently fails or produces a broken extension.

**Instead:** Always follow this order:
1. Build libbmiwrfhydrof.so (CMake or build.sh --shared)
2. Install to $CONDA_PREFIX (`cmake --install _build`)
3. Verify: `pkg-config --libs bmiwrfhydrof`
4. THEN build pymt_wrfhydro

### Anti-Pattern 4: Using --build-isolation for pip install

**What:** Running `pip install .` (default uses build isolation) in a complex conda environment.

**Why bad:** Build isolation creates a fresh virtual environment that does not inherit `$CONDA_PREFIX`, `$PKG_CONFIG_PATH`, or compiled Fortran libraries. Meson cannot find bmiwrfhydrof.pc in an isolated environment.

**Instead:** Use `pip install . --no-build-isolation` or `python -m build --no-isolation` to build within the existing conda environment where all dependencies are visible.

### Anti-Pattern 5: Expecting Multiple WRF-Hydro Instances

**What:** Trying to create two WrfHydroF() instances in Python and run them independently.

**Why bad:** WRF-Hydro uses module-level globals (rt_domain, SMOIS, COSZEN, etc.) that are allocated once and cannot be re-allocated. The `wrfhydro_engine_initialized` flag prevents double-init. Even though the babelizer generates a 2048-slot model array, only one slot can actually be used.

**Instead:** Document this as a known limitation. Use a single instance per process. For ensemble runs, use separate processes.

## Relationship Between Our C Binding and Babelizer's Interop Layer

This is a critical architectural clarification:

```
WHAT WE BUILT (Phase 1.5):           WHAT BABELIZER GENERATES (Phase 2):
+----------------------------------+  +--------------------------------------+
| bmi_wrf_hydro_c.f90 (335 lines)  |  | bmi_interoperability.f90 (818 lines) |
| Module: bmi_wrf_hydro_c_mod      |  | Module: bmi_interoperability         |
| Pattern: Singleton                |  | Pattern: Box/handle (2048 slots)     |
| Functions: 10 (subset)            |  | Functions: 41+ (complete BMI)        |
| Uses: bmiwrfhydrof, bmif_2_0     |  | Uses: bmiwrfhydrof, bmif_2_0         |
| Compiled into: libbmiwrfhydrof.so|  | Compiled into: wrfhydrof.so (Cython) |
| Called by: Python ctypes          |  | Called by: Cython wrfhydrof.pyx      |
| Status: TEST INFRASTRUCTURE      |  | Status: PRODUCTION                   |
+----------------------------------+  +--------------------------------------+
```

Key differences:
1. **Instance management:** Our C binding uses a singleton (`the_model`); babelizer uses array slots (`model_array(N_MODELS)`)
2. **Scope:** Our C binding exposes 10 functions; babelizer exposes all 41+ BMI functions
3. **Compilation target:** Our C binding is compiled INTO libbmiwrfhydrof.so; babelizer's interop is compiled into the Cython extension module
4. **Consumer:** Our C binding is called by ctypes; babelizer's interop is called by Cython

**They do NOT conflict.** The babelizer-generated interop calls `model_array(i)%initialize()` etc., which invokes the type-bound procedures in module `bmiwrfhydrof` (our BMI wrapper). Our C binding module (`bmi_wrf_hydro_c_mod`) remains inside libbmiwrfhydrof.so but is simply unused by the babelizer pathway.

## Complete Build Order (Dependencies Mapped)

```
STEP 1: Prerequisites (already done)
========================================
  WRF-Hydro compiled with -fPIC
  bmi-fortran 2.0.3 installed
  libbmiwrfhydrof.so built + installed
  bmiwrfhydrof.pc in $CONDA_PREFIX/lib/pkgconfig/
  bmiwrfhydrof.mod in $CONDA_PREFIX/include/

STEP 2: Install Babelizer
========================================
  conda install -c conda-forge babelizer
  (brings: babelizer, cython, meson-python, numpy, bmipy)

STEP 3: Write babel.toml
========================================
  [library.WrfHydroF]
  language = "fortran"
  library = "bmiwrfhydrof"
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
  requirements = [""]

  [info]
  github_username = "pymt-lab"
  package_author = "..."
  package_author_email = "..."
  package_license = "MIT"
  summary = "PyMT plugin for WRF-Hydro hydrological model"

  [ci]
  python_version = ["3.11"]
  os = ["linux"]

STEP 4: Generate Package
========================================
  babelize init babel.toml
  -> Creates pymt_wrfhydro/ directory with all auto-generated files

STEP 5: Create Model Metadata
========================================
  Write meta/WrfHydroF/api.yaml (variable names, grids)
  Write meta/WrfHydroF/info.yaml (model description)
  Write meta/WrfHydroF/parameters.yaml (config parameters)
  Write meta/WrfHydroF/run.yaml (runtime config)
  Write examples/bmi_config.nml (test config file)

STEP 6: Build & Install pymt_wrfhydro
========================================
  cd pymt_wrfhydro
  pip install . -v --no-build-isolation
  (Meson discovers bmiwrfhydrof via pkg-config,
   compiles bmi_interoperability.f90 + wrfhydrof.pyx,
   links into Python extension module)

STEP 7: Verify Import
========================================
  python -c "from pymt_wrfhydro import WrfHydroF; print('OK')"

STEP 8: Run bmi-tester
========================================
  bmi-test pymt_wrfhydro._bmi:WrfHydroF \
    --config-file=examples/bmi_config.nml \
    --root-dir=examples \
    --bmi-version="2.0" -vvv

STEP 9: Validate Against Reference
========================================
  Python script comparing pymt_wrfhydro output
  to standalone WRF-Hydro Croton NY reference data
```

## Generated Package Structure (pymt_wrfhydro)

After `babelize init babel.toml`, the generated directory contains:

```
pymt_wrfhydro/
+-- .github/
|   +-- workflows/          # CI configuration (GitHub Actions)
+-- docs/                   # Documentation stubs
+-- examples/               # Example config files (WE ADD)
+-- external/               # Git submodules for deps (if needed)
+-- meta/
|   +-- WrfHydroF/          # Model metadata (WE WRITE)
|       +-- api.yaml        #   Variable names, grids, exchange items
|       +-- info.yaml       #   Model description, author, license
|       +-- parameters.yaml #   Configurable parameters
|       +-- run.yaml        #   Runtime configuration
+-- pymt_wrfhydro/
|   +-- __init__.py         # from pymt_wrfhydro._bmi import WrfHydroF
|   +-- _bmi.py             # from pymt_wrfhydro.lib import WrfHydroF
|   +-- _version.py         # Version info
|   +-- data/ -> meta/WrfHydroF  # Symlink to metadata
|   +-- lib/
|       +-- __init__.py     # Package init
|       +-- bmi_interoperability.f90  # AUTO-GENERATED: 41+ bind(C) functions
|       +-- bmi_interoperability.h    # AUTO-GENERATED: C header for .f90
|       +-- wrfhydrof.pyx   # AUTO-GENERATED: Cython wrapper class
+-- .gitignore
+-- .pre-commit-config.yaml
+-- babel.toml              # Preserved configuration
+-- CHANGES.rst             # Changelog
+-- CREDITS.rst             # Credits
+-- LICENSE.rst              # License
+-- Makefile                # Convenience targets (test, install, clean)
+-- meson.build             # AUTO-GENERATED: Meson build system
+-- noxfile.py              # Test runner configuration
+-- pyproject.toml          # AUTO-GENERATED: Python packaging
+-- requirements*.txt       # Dependency files
+-- setup.cfg               # Additional setuptools config
```

Files we write or modify: babel.toml, meta/WrfHydroF/*.yaml, examples/
Files the babelizer generates: everything else (DO NOT EDIT)

## Scalability Considerations

| Concern | Current State | At Scale (NWM Domain) | Mitigation |
|---------|---------------|----------------------|------------|
| Library load time | ~2s (Croton NY, 200 reaches) | ~10-30s (NWM, 2.7M reaches) | One-time cost at initialize() |
| Memory for model_array(2048) | Negligible (only 1 used) | Negligible (only 1 used) | N/A -- WRF-Hydro is singleton |
| get_value array copy | Fast (200 doubles) | Slower (2.7M doubles = ~21 MB per call) | Use get_value_ptr if possible; batch calls |
| Cython overhead per BMI call | ~1 microsecond | ~1 microsecond (constant) | Negligible vs. model computation |
| Config file path length | OK (WSL2 relative paths) | OK if < 80 chars | Use relative paths from run directory |

## Sources

- [pymt_heatf babel.toml](https://github.com/pymt-lab/pymt_heatf/blob/main/babel.toml) -- Reference Fortran babelizer configuration (HIGH confidence)
- [pymt_heatf meson.build](https://github.com/pymt-lab/pymt_heatf/blob/main/meson.build) -- Reference Meson build showing pkg-config dependency chain (HIGH confidence)
- [pymt_heatf bmi_interoperability.f90](https://github.com/pymt-lab/pymt_heatf/blob/main/pymt_heatf/lib/bmi_interoperability.f90) -- Auto-generated interop layer, verified box pattern and use statements (HIGH confidence)
- [pymt_heatf heatmodelf.pyx](https://github.com/pymt-lab/pymt_heatf/blob/main/pymt_heatf/lib/heatmodelf.pyx) -- Cython wrapper showing type dispatch pattern (HIGH confidence)
- [pymt_heatf pyproject.toml](https://github.com/pymt-lab/pymt_heatf/blob/main/pyproject.toml) -- PyMT entry point registration (HIGH confidence)
- [babelizer GitHub](https://github.com/csdms/babelizer) -- Template source, meson.build template, supported languages (HIGH confidence)
- [babelizer templates](https://github.com/csdms/babelizer/tree/develop/babelizer/data/templates) -- Jinja2 templates for generated files (HIGH confidence)
- [bmi-tester GitHub](https://github.com/csdms/bmi-tester) -- BMI testing tool, CLI usage `bmi-test module:Class` (HIGH confidence)
- [babelizer readthedocs](https://babelizer.readthedocs.io/en/latest/readme.html) -- babel.toml configuration format (MEDIUM confidence)
- [CSDMS bmi.readthedocs](https://bmi.csdms.io/en/latest/csdms.html) -- BMI-based tools overview (MEDIUM confidence)
- Our existing files: bmi_wrf_hydro_c.f90, CMakeLists.txt, build.sh, bmiwrfhydrof.pc.cmake -- Direct source analysis (HIGH confidence)
