# Feature Landscape

**Domain:** Babelizing a Fortran BMI shared library into a PyMT-compatible Python package
**Researched:** 2026-02-24
**Confidence:** HIGH for babelizer workflow (verified against babelizer source templates + pymt_heatf reference); HIGH for bmi-tester (verified against test source code); MEDIUM for PyMT metadata (verified against pymt_heatf meta/ files)

## Context: What Already Exists

These features are COMPLETE from prior milestones. The babelizer milestone builds on top of them.

| Existing Asset | Status | Relevance to This Milestone |
|---------------|--------|----------------------------|
| `bmi_wrf_hydro.f90` (41 BMI functions, 1919 lines) | COMPLETE | Babelizer's `bmi_interoperability.f90` will `use bmiwrfhydrof` and call `type(bmi_wrf_hydro)` methods |
| `libbmiwrfhydrof.so` (4.8 MB shared library) | COMPLETE | Babelizer finds this via pkg-config; Meson links against it |
| `bmiwrfhydrof.pc` (pkg-config file) | COMPLETE | Babelizer's `meson.build` calls `dependency('bmiwrfhydrof', method: 'pkg-config')` |
| `bmiwrfhydrof.mod` + `wrfhydro_bmi_state_mod.mod` installed | COMPLETE | Babelizer's interop layer compiles with `use bmiwrfhydrof` |
| `bmi_wrf_hydro_c.f90` (minimal C bindings, 10 functions) | COMPLETE | Test infrastructure only; babelizer generates its own C bindings |
| Python ctypes test (Croton NY validation) | COMPLETE | Reference output for post-babelizer validation |
| 151-test Fortran suite (all pass) | COMPLETE | Baseline correctness guarantee |

## Table Stakes

Features users expect from a babelized BMI plugin. Missing any = the plugin is broken or unusable.

| Feature | Why Expected | Complexity | Depends On |
|---------|--------------|------------|-----------|
| **babel.toml configuration file** | The single input to `babelize init`; defines library name (`bmiwrfhydrof`), entry point (`bmi_wrf_hydro`), package name (`pymt_wrfhydro`), metadata | Low | Existing shared library + pkg-config |
| **`babelize init` generates pymt_wrfhydro** | Core babelizer command; creates entire Python package directory with Cython bindings, Meson build, interop layer | Low (automated) | babel.toml + babelizer installed in conda env |
| **pymt_wrfhydro builds with `pip install .`** | Meson must find `libbmiwrfhydrof.so` via pkg-config, compile `bmi_interoperability.f90` (which `use bmiwrfhydrof`), compile Cython `_fortran.pyx`, link everything | Medium | pkg-config working, .mod files accessible, gfortran + Cython in env |
| **`from pymt_wrfhydro import WrfHydroBmi` works** | Basic import test; proves the compiled Cython extension loads and our shared library links correctly | Low | Successful pip install; `libbmiwrfhydrof.so` findable at runtime (LD_LIBRARY_PATH or rpath) |
| **initialize/update/finalize cycle from Python** | Core BMI IRF pattern must work end-to-end: Python -> Cython -> C interop -> Fortran BMI -> WRF-Hydro | Medium | Config file path accessible from Python working directory; MPI initialized |
| **get_value returns numpy arrays with correct data** | Scientists need to read model output; babelizer's Cython maps `"double precision"` to `numpy.float64` and dispatches to `bmi_get_value_double` in interop layer | Low | Our `get_var_type` returns `"double precision"` (verified compatible) |
| **set_value accepts numpy arrays** | Scientists need to inject forcing data; babelizer handles `float64` -> `c_double` -> Fortran `real(8)` conversion | Low | Our `set_value` already handles double-precision input |
| **All 8 output variables accessible** | QLINK1, sfcheadrt, SOIL_M, SNEQV, ACCET, T2, RAINRATE, UGDRNOFF must all be readable via CSDMS Standard Names | Low | Already working in Fortran; babelizer wraps transparently |
| **All 4 input variables settable** | RAINRATE, T2, QSTRMVOLRT, sfcheadrt must be writable | Low | Already working in Fortran; babelizer wraps transparently |
| **Grid metadata queries work** | `get_grid_type`, `get_grid_rank`, `get_grid_size`, `get_grid_shape` for all 3 grids (LSM 1km, routing 250m, channel vector) | Low | Already correct in Fortran; babelizer's interop layer passes through |
| **Time functions return correct values** | `get_current_time`, `get_start_time`, `get_end_time`, `get_time_step`, `get_time_units` | Low | Already correct in Fortran |
| **Config file path handling** | Babelizer passes config path as C string -> interop converts to Fortran string -> our `initialize()` reads it. Path must not exceed `character(len=80)` | Low | Use relative paths; Croton NY test case must be in working directory |
| **MPI compatibility** | WRF-Hydro requires MPI. Python process must have MPI loaded before calling initialize. `mpi4py` or `ctypes.CDLL("libmpi.so", RTLD_GLOBAL)` needed | Medium | OpenMPI in conda env; may need `mpi4py` as dependency |

## Differentiators

Features that set the plugin apart from a minimal "it imports" state. Not strictly required but make the plugin production-quality and scientist-usable.

| Feature | Value Proposition | Complexity | Depends On |
|---------|-------------------|------------|-----------|
| **bmi-tester passes all stages** | Official CSDMS validation; proves BMI compliance from Python side. Tests 30+ assertions across 3 stages: info (component name, var names, counts), time (start/end/step/units), vars (type/units/itemsize/nbytes/location/grid), grids (rank/size/type/shape/spacing/origin/node_count), values (get_value/set_value) | Medium | Working initialize + all BMI getters returning correct types |
| **Croton NY reference validation** | End-to-end: run 6-hour Croton NY simulation from Python, compare streamflow output to Fortran reference values. Proves no data corruption through the Fortran->C->Cython->Python chain | Medium | Croton NY test data accessible; reference values from ctypes test or Fortran 151-test |
| **PyMT metadata files** (`meta/WrfHydroBmi/`) | 4 YAML files + 1 template config that let PyMT auto-discover, configure, and run the model. Enables `from pymt.models import WrfHydroBmi` | Medium | Understanding of WRF-Hydro config parameters (namelist.hrldas, hydro.namelist) |
| **`info.yaml`** (model metadata) | Summary, URL, author, email, version, license. PyMT uses this for model catalog display | Low | Just metadata |
| **`api.yaml`** (API description) | Language, package name, class name. PyMT uses this to find the BMI class | Low | Just metadata |
| **`parameters.yaml`** (input parameters) | Describes configurable parameters with types, defaults, ranges, units. PyMT uses this for parameter validation and templated config generation | High | Must map WRF-Hydro namelist options to YAML parameter descriptions |
| **`run.yaml`** (runtime config) | Points to the template config file. Tells PyMT which config file to generate | Low | Template config file must exist |
| **Template config file** (e.g., `wrfhydro.cfg`) | Jinja2 template with `{{parameter}}` placeholders that PyMT fills from `parameters.yaml` defaults | High | Must understand which WRF-Hydro namelist values are safe to template |
| **Example Jupyter notebook** | Scientists can copy-paste to start using the model. Shows import, initialize, time loop, get_value, plot results | Low-Med | Working babelized plugin |
| **conda-forge recipe** (`meta.yaml`) | Enables `conda install pymt_wrfhydro` for easy distribution. Babelizer auto-generates a skeleton | High | Requires all runtime deps specified; complex linking |
| **Documentation (Doc 18)** | Covers babelizer workflow, babel.toml rationale, build steps, bmi-tester results, Python usage examples | Medium | User preference for detailed docs |

## Anti-Features

Features to explicitly NOT build in this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **SCHISM babelization** | SCHISM BMI targets NOAA NextGen, not PyMT; no `pymt_schism` exists in CSDMS ecosystem; different pathway entirely | Document as out-of-scope; Phase 4 concern |
| **PyMT coupling (WRF-Hydro + SCHISM)** | Phase 4 of overall project; requires both models babelized + grid mapping + time sync | Just validate WRF-Hydro standalone via PyMT |
| **MPI parallel execution (np > 1)** | Enormous complexity; serial-first following SCHISM approach. Babelizer does not handle MPI process management | Always run with `-np 1`; document single-instance limitation |
| **Multi-instance support** | WRF-Hydro module globals prevent multiple instances; babelizer's pool (`N_MODELS=2048`) works but only 1 slot usable | Document as known limitation; return error on second `bmi_new()` |
| **`get_value_ptr` from Python** | Our Fortran wrapper returns `BMI_FAILURE` (WRF-Hydro REAL vs BMI double mismatch). Cython layer raises `RuntimeError`. PyMT falls back to `get_value` (copy-based) | Accept copy overhead; document as known limitation |
| **Full `parameters.yaml` for all WRF-Hydro config** | WRF-Hydro has 200+ namelist options across 2 files + `.TBL` tables. Parameterizing all is massive scope | Start with 5-10 essential parameters (timestep, duration, output frequency); expand later |
| **Windows/Mac builds** | WSL2 Linux is the target; WRF-Hydro's build system and MPI deps are Linux-only | Set `os = ["linux"]` in `[ci]` section of babel.toml |
| **NextGen `register_bmi` integration** | Different pathway from babelizer/PyMT; requires box/opaque-handle pattern. Our existing C binding already has `bmi_register` but it is not the NextGen pattern | Could add later behind `#ifdef NGEN_ACTIVE` |
| **Modifying WRF-Hydro source code** | BMI is non-invasive by design | Wrapper calls model as-is |
| **conda-forge package publication** | Requires maintainer approval, CI infrastructure, and dependency packaging. Premature for initial development | Generate recipe skeleton but do not submit; use `pip install -e .` locally |
| **Automated CI/CD** | Babelizer generates GitHub Actions workflow but WRF-Hydro's build deps (22 libs, MPI, NetCDF) make CI extremely complex | Test locally; CI is a future concern |

## Feature Dependencies

```
babel.toml written
  |
  v
babelize init babel.toml -> generates pymt_wrfhydro/ directory
  |
  +-- requires: babelizer installed in conda env
  |
  v
pip install . (inside pymt_wrfhydro/)
  |
  +-- requires: pkg-config finds bmiwrfhydrof (shared lib + .mod + .pc)
  +-- requires: gfortran (compiles bmi_interoperability.f90)
  +-- requires: Cython + numpy (compiles _fortran.pyx)
  +-- requires: meson-python (build backend)
  |
  v
from pymt_wrfhydro import WrfHydroBmi works
  |
  +-- requires: libbmiwrfhydrof.so findable at runtime (LD_LIBRARY_PATH / rpath / conda prefix)
  +-- requires: MPI library loadable
  |
  v
model.initialize("config.txt") works
  |
  +-- requires: config file accessible from working directory
  +-- requires: Croton NY test data (DOMAIN/, FORCING/, namelists) in path
  +-- requires: MPI initialized (either by mpi4py import or explicit init)
  |
  v
bmi-tester passes
  |
  +-- requires: all BMI getters return correct types
  +-- requires: get_var_type returns "double precision" (mapped to float64 in Cython)
  +-- requires: grid functions work for all 3 grid types
  |
  v
PyMT metadata added (meta/WrfHydroBmi/)
  |
  +-- requires: info.yaml, api.yaml, parameters.yaml, run.yaml, template config
  |
  v
from pymt.models import WrfHydroBmi works (PyMT integration)
  |
  +-- requires: pymt installed + metadata files present + babelized plugin installed
```

Key dependency chain:
```
shared lib installed -> babel.toml -> babelize init -> pip install -> bmi-tester -> PyMT metadata -> full integration
```

## bmi-tester Test Coverage (What It Actually Checks)

The bmi-tester runs pytest in 3 stages against the babelized plugin. Verified from source code at [csdms/bmi-tester](https://github.com/csdms/bmi-tester).

### Stage 1: Info + Time (No model initialization needed beyond basic setup)

| Test | BMI Functions Checked | Our Status |
|------|----------------------|------------|
| `test_get_component_name` | `get_component_name()` returns a string | PASS (returns "WRF-Hydro v5.4.0") |
| `test_input_var_name_count` | `get_input_var_name_count()` returns int | PASS (returns 4) |
| `test_output_var_name_count` | `get_output_var_name_count()` returns int | PASS (returns 8) |
| `test_get_input_var_names` | `get_input_var_names()` returns tuple of strings | PASS |
| `test_get_output_var_names` | `get_output_var_names()` returns tuple of strings | PASS |
| `test_var_names` | Validates variable name format | PASS (CSDMS Standard Names) |
| `test_get_start_time` | `get_start_time()` returns float | PASS |
| `test_get_time_step` | `get_time_step()` returns float | PASS |
| `test_time_units_is_str` | `get_time_units()` returns string | PASS (returns "s") |
| `test_time_units_is_valid` | `get_time_units()` is valid unit string | PASS |
| `test_get_current_time` | start <= current <= end | PASS |
| `test_get_end_time` | end >= start | PASS |

### Stage 2: Variable Info (Parametrized over all variables)

| Test | BMI Functions Checked | Our Status |
|------|----------------------|------------|
| `test_get_var_type` | `get_var_type()` returns recognized type string | PASS ("double precision" -> float64) |
| `test_get_var_units` | `get_var_units()` returns string | PASS |
| `test_get_var_itemsize` | `get_var_itemsize()` returns int | PASS (8 for double) |
| `test_get_var_nbytes` | `get_var_nbytes()` returns int | PASS |
| `test_get_var_location` | `get_var_location()` returns "node"/"edge"/"face" | PASS (returns "node") |
| `test_var_on_grid` | Checks grid ID from `get_var_grid()`, then queries grid type and node/edge/face counts | LIKELY PASS |

### Stage 3: Grids + Values (Parametrized over grids and variables)

| Test | BMI Functions Checked | Risk |
|------|----------------------|------|
| `test_get_grid_rank` | `get_grid_rank()` | PASS for grids 0,1; needs verification for grid 2 (vector) |
| `test_get_grid_size` | `get_grid_size()` | PASS |
| `test_get_grid_type` | `get_grid_type()` | PASS ("uniform_rectilinear", "vector") |
| `test_get_grid_node_count` | `get_grid_node_count()` | PASS |
| `test_get_grid_edge_count` | `get_grid_edge_count()` | RISK: bmi-tester may expect 0 for rectilinear grids |
| `test_get_grid_face_count` | `get_grid_face_count()` | RISK: same as above |
| `test_get_grid_shape` | `get_grid_shape()` (rectilinear only) | PASS for grids 0,1 |
| `test_get_grid_spacing` | `get_grid_spacing()` (rectilinear only) | PASS for grids 0,1 |
| `test_grid_x/y/z` | `get_grid_x/y/z()` (unstructured only) | RISK: grid 2 (channel) needs x/y coordinates |
| `test_get_output_values` | `get_value()` for output vars | PASS |
| `test_set_input_values` | `set_value()` for input vars | SKIPPED (marked "too dangerous") |

### Risk Areas for bmi-tester

1. **Grid 2 (vector/channel)**: bmi-tester will query `get_grid_node_count`, `get_grid_x`, `get_grid_y` for our vector grid. Our wrapper must return CHLON/CHLAT coordinates correctly.
2. **Edge/face counts**: For uniform_rectilinear grids, bmi-tester checks `get_grid_edge_count` and `get_grid_face_count`. Our wrapper returns 0 for these, which should be correct.
3. **MPI initialization**: bmi-tester does not handle MPI. We may need a conftest.py or wrapper that initializes MPI before tests run.

## Babelizer Workflow Steps (The Complete Process)

For reference, the exact steps to babelize WRF-Hydro's BMI:

```
Step 1: Install babelizer
  conda install -c conda-forge babelizer

Step 2: Verify prerequisites
  pkg-config --cflags --libs bmiwrfhydrof    # Must return flags
  test -f $CONDA_PREFIX/include/bmiwrfhydrof.mod  # Must exist

Step 3: Write babel.toml (see below)

Step 4: Generate package
  babelize init babel.toml
  # Creates: pymt_wrfhydro/ directory with ~20 files

Step 5: Build and install
  cd pymt_wrfhydro
  pip install -e ".[dev]"
  # Meson finds library -> compiles interop -> compiles Cython -> installs

Step 6: Test import
  python -c "from pymt_wrfhydro import WrfHydroBmi; print('OK')"

Step 7: Run bmi-tester
  bmi-test pymt_wrfhydro:WrfHydroBmi --config-file=bmi_config.txt --root-dir=/path/to/croton

Step 8: Add PyMT metadata (optional, for pymt.models integration)
  # Create meta/WrfHydroBmi/ with info.yaml, api.yaml, parameters.yaml, run.yaml

Step 9: Validate Croton NY results
  # Python script comparing output to Fortran reference
```

## babel.toml for WRF-Hydro (Verified Against pymt_heatf Reference)

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
requirements = []

[info]
github_username = "mohansai"
package_author = "Mohan Sai"
package_author_email = "mohan@example.com"
package_license = "MIT"
summary = "PyMT plugin for WRF-Hydro / National Water Model hydrological model"

[ci]
python_version = ["3.10", "3.11", "3.12"]
os = ["linux"]
```

### Critical Naming Chain (Verified HIGH Confidence)

| Field | Value | Where It Appears |
|-------|-------|-----------------|
| `WrfHydroBmi` (class key) | Python class name | `from pymt_wrfhydro import WrfHydroBmi` |
| `bmiwrfhydrof` (library) | Fortran module name | `use bmiwrfhydrof` in interop layer; `dependency('bmiwrfhydrof')` in Meson |
| `bmi_wrf_hydro` (entry_point) | Fortran derived type | `type(bmi_wrf_hydro) :: model_array(2048)` in interop layer |
| `pymt_wrfhydro` (package name) | Python package | `pip install pymt_wrfhydro`; `import pymt_wrfhydro` |

## PyMT Metadata Files (From pymt_heatf Reference)

If full PyMT integration is desired (`from pymt.models import WrfHydroBmi`), these files go in `meta/WrfHydroBmi/`:

### `api.yaml`
```yaml
name: pymt_wrfhydro
language: fortran
package: pymt_wrfhydro
class: WrfHydroBmi
```

### `info.yaml`
```yaml
summary: BMI wrapper for WRF-Hydro v5.4.0 hydrological model (NCAR).
  Simulates land surface processes, overland flow, subsurface flow,
  and channel routing. Part of the NOAA National Water Model.
url: https://github.com/mohansai/WRF-Hydro-BMI
author: Mohan Sai
email: mohan@example.com
version: 1.0.0
license: MIT
```

### `parameters.yaml` (minimal starting set)
```yaml
simulation_duration:
  description: Total simulation time in hours
  value:
    type: int
    default: 6
    range:
      min: 1
      max: 8760
    units: h

timestep:
  description: Land model timestep in seconds
  value:
    type: int
    default: 3600
    range:
      min: 60
      max: 86400
    units: s

output_frequency:
  description: Output write frequency in timesteps
  value:
    type: int
    default: 1
    range:
      min: 1
      max: 100
    units: "-"
```

### `run.yaml`
```yaml
config_file: wrfhydro.cfg
```

### `wrfhydro.cfg` (template)
```
# WRF-Hydro BMI configuration (pass-through to namelists)
# Parameters filled by PyMT from parameters.yaml defaults
simulation_duration: {{simulation_duration}}
timestep: {{timestep}}
output_frequency: {{output_frequency}}
```

## MVP Recommendation

Prioritize (in this order):

1. **Install babelizer** -- `conda install -c conda-forge babelizer` into wrfhydro-bmi env
2. **Write babel.toml** -- Use the verified config above; low effort, high impact
3. **Run `babelize init babel.toml`** -- Generates pymt_wrfhydro/ directory (automated)
4. **Build with `pip install -e .`** -- This is the critical step where things can break (Meson + pkg-config + gfortran + Cython all must work together)
5. **Test import** -- `from pymt_wrfhydro import WrfHydroBmi` must work
6. **Test IRF cycle** -- initialize/update/finalize from Python with Croton NY data
7. **Run bmi-tester** -- Official CSDMS validation; likely needs MPI handling
8. **Validate Croton NY output** -- Compare Python-side get_value to Fortran reference

Defer:
- PyMT metadata files (info.yaml, parameters.yaml, etc.) -- nice but not blocking
- conda-forge recipe -- premature for initial development
- Jupyter notebook example -- after core validation passes
- Documentation -- after workflow is proven

## Sources

- [csdms/babelizer GitHub repository](https://github.com/csdms/babelizer) -- template files, config validation (HIGH confidence, verified against source code)
- [babelizer Fortran example docs](https://babelizer.readthedocs.io/en/latest/example-fortran.html) -- workflow steps (HIGH confidence)
- [pymt-lab/pymt_heatf GitHub](https://github.com/pymt-lab/pymt_heatf) -- reference babelized Fortran project, babel.toml, meta/ files (HIGH confidence)
- [csdms/bmi-tester GitHub](https://github.com/csdms/bmi-tester) -- test source code for stages 1-3 (HIGH confidence, verified test files)
- [csdms/model_metadata GitHub](https://github.com/csdms/model_metadata) -- PyMT metadata format (MEDIUM confidence)
- [bmi-tester stage_1 tests](https://github.com/csdms/bmi-tester/tree/master/src/bmi_tester/_tests/stage_1) -- info_test.py, time_test.py (HIGH confidence)
- [bmi-tester stage_2 tests](https://github.com/csdms/bmi-tester/tree/master/src/bmi_tester/_tests/stage_2) -- var_test.py (HIGH confidence)
- [bmi-tester stage_3 tests](https://github.com/csdms/bmi-tester/tree/master/src/bmi_tester/_tests/stage_3) -- grid_test.py, value_test.py, grid_uniform_rectilinear_test.py, grid_unstructured_test.py (HIGH confidence)
- [CSDMS Babelizer wiki](https://csdms.colorado.edu/wiki/Babelizer) -- overview (MEDIUM confidence)
- [PyMT documentation](https://pymt.readthedocs.io/) -- coupling framework (MEDIUM confidence)
- [bmi 2.0 documentation](https://bmi.csdms.io/en/latest/csdms.html) -- BMI-based tools overview (HIGH confidence)
- Local project files: `.planning/research/CSDMS_BABELIZER_OFFICIAL.md` (HIGH confidence, verified against babelizer source)
- Local project files: `bmi_wrf_hydro/Docs/4.Babelizer_Complete_Guide.md` (MEDIUM confidence, pre-milestone documentation)
