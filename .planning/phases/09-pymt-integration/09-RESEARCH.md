# Phase 9: PyMT Integration - Research

**Researched:** 2026-02-25
**Domain:** PyMT installation, plugin registration, metadata files, Jupyter notebook, documentation
**Confidence:** MEDIUM (PyMT dependency details from training data + web search, not Context7-verified)

## Summary

Phase 9 must install PyMT into the existing `wrfhydro-bmi` conda environment (which already has babelizer 0.3.9, OpenMPI 5.0.8, mpi4py 4.1.1, numpy 2.2.6, Cython 3.2.4, and the working pymt_wrfhydro package), create CSDMS model metadata files for the PyMT plugin registry, verify `from pymt.models import WrfHydroBmi` works, create a comprehensive Jupyter notebook, and write Doc 19.

The primary risk is **conda dependency conflicts** when installing PyMT into an environment that already has a carefully tuned toolchain. PyMT has a large dependency tree (scipy, xarray, model-metadata, gimli.units, jinja2, etc.) that could potentially downgrade or conflict with existing packages. The recommended strategy is: (1) export the environment first, (2) try `conda install --dry-run` to assess conflicts, (3) if clean, proceed with conda install; (4) if conflicts, try `pip install pymt` as fallback.

The plugin registration mechanism uses Python entry points (`pymt.plugins` group in setup.py), which pymt_wrfhydro already declares. The remaining work is creating the `meta/WrfHydroBmi/` metadata directory with YAML files that describe the model to PyMT's registry system. A previous research pass (from an earlier session) already established the metadata discovery mechanism and YAML file formats -- this updated research adds dependency analysis, installation strategy, and notebook architecture.

**Primary recommendation:** Install PyMT via conda after a dry-run safety check, create 4 YAML metadata files following the pymt_hydrotrend reference pattern, ensure the `data/` directory is properly synced, write a comprehensive Jupyter notebook in `pymt_wrfhydro/notebooks/`, and create Doc 19 as the capstone document.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- parameters.yaml scope: Claude's discretion (based on what other PyMT plugins expose)
- info.yaml content: Claude's discretion (follow CSDMS conventions, include NCAR references + wrapper author)
- api.yaml: Single class WrfHydroBmi (not sub-components) -- Claude's discretion confirmed
- run.yaml: Config template approach -- Claude's discretion (template-only vs bundled Croton NY)
- Path handling: Claude's discretion (Jinja2 template vs absolute -- follow PyMT conventions)
- Time control: Claude's discretion (PyMT controls time loop via update/update_until -- the BMI way)
- Doc 19 target audience: BOTH modelers/scientists AND developers/maintainers (split sections)
- Doc 19 code examples: 6-8 comprehensive examples
- Doc 19 scope: Full journey recap (Phases 1-9)
- Doc number: 19
- PyMT install strategy: Claude's discretion (assess --dry-run risk, try wrfhydro-bmi env first)
- PyMT install fallback: Claude's discretion (pip, separate env, or document as limitation)
- Env backup: Claude's discretion (export env before install if risk warrants it)
- Grid mapping: Claude's discretion (basic import test vs light demo -- full mapping is Phase 4 coupling)
- Jupyter notebook content: ALL of the following:
  - Full IRF cycle (~20-line demo from project vision)
  - Streamflow visualization (time series + spatial network)
  - All 8 output variables with summary statistics
  - Grid exploration (all 3 grids: 1km LSM, 250m routing, vector channel)
  - Exercise all 41 BMI functions (Python walkthrough of each function)
  - Run existing pytest suite from notebook (final validation cell)
- Import paths: Show BOTH standalone (`from pymt_wrfhydro import WrfHydroBmi`) and PyMT registry (`from pymt.models import WrfHydroBmi`) -- standalone as primary, PyMT as optional
- Visualization: Show BOTH matplotlib (primary) and plotly (optional cells)
- Notebook location: `pymt_wrfhydro/notebooks/`
- Notebook title: Claude's discretion (comprehensive walkthrough theme)

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

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PYMT-01 | PyMT installed in conda env (`conda install pymt`) | Installation Strategy section covers dry-run approach, dependency analysis, fallback to pip. PyMT latest is 1.3.2 on conda-forge (released 2024-10-11). |
| PYMT-02 | `meta/WrfHydroBmi/` directory with 4 YAML files (info.yaml, api.yaml, parameters.yaml, run.yaml) + template config | Architecture Patterns section documents all 4 YAML file formats. api.yaml already exists (partial). Prior research established model_metadata discovery mechanism. |
| PYMT-03 | `from pymt.models import WrfHydroBmi` works (PyMT model registry) | Plugin System section explains entry_points mechanism. pymt_wrfhydro setup.py already declares `pymt.plugins` entry point. Must re-install after adding metadata. |
| PYMT-04 | Doc 19 exists in `bmi_wrf_hydro/Docs/` covering complete babelizer workflow | Documentation section outlines capstone doc structure. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| pymt | 1.3.2 (conda-forge) | Model coupling framework, plugin registry | CSDMS standard; provides `from pymt.models import` |
| model-metadata | latest (PyMT dep) | YAML metadata parsing for plugin info | Required by PyMT to load plugin metadata files |
| scipy | latest (PyMT dep) | Scientific computing, interpolation for grid mappers | PyMT uses scipy for spatial operations |
| xarray | latest (PyMT dep) | N-D labeled arrays for model data | PyMT uses xarray for variable access (`model.var`) |
| gimli.units | latest (PyMT dep) | Unit parsing/conversion (replaced old cfunits) | PyMT uses for automatic unit conversion |
| matplotlib | latest (for notebook) | Visualization of streamflow, grids, time series | Standard Python plotting; primary viz in notebook |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| jupyter | latest | Interactive notebook environment | For the comprehensive demo notebook |
| plotly | optional | Interactive visualizations | Optional cells in notebook for spatial viz |
| jinja2 | latest (PyMT dep) | Template rendering for config files | PyMT uses for config template processing |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| conda install pymt | pip install pymt | Pip avoids conda solver conflicts but may miss compiled deps |
| Single wrfhydro-bmi env | Separate pymt env | Separate env avoids all conflicts but cannot test PyMT integration with pymt_wrfhydro |

**Installation:**
```bash
# Step 1: Backup environment
conda env export > wrfhydro-bmi-backup-$(date +%Y%m%d).yml

# Step 2: Dry-run to check for conflicts
conda install -c conda-forge pymt --dry-run

# Step 3: If clean, install
conda install -c conda-forge pymt

# Step 3b: If conflicts, try pip fallback
pip install pymt
```

## Architecture Patterns

### Recommended Project Structure for Phase 9
```
pymt_wrfhydro/
+-- meta/
|   +-- WrfHydroBmi/
|       +-- info.yaml           # Model identification metadata
|       +-- api.yaml            # API class definition (exists, needs update)
|       +-- parameters.yaml     # Exposed configuration parameters
|       +-- run.yaml            # Config template + staging info
|       +-- bmi_config.nml      # Jinja2 template config file
+-- pymt_wrfhydro/
|   +-- data/
|   |   +-- WrfHydroBmi/       # Must mirror meta/ (packaged location)
|   |       +-- info.yaml
|   |       +-- api.yaml
|   |       +-- parameters.yaml
|   |       +-- run.yaml
|   |       +-- bmi_config.nml
|   +-- __init__.py             # Already has MPI bootstrap
|   +-- bmi.py                  # Already has WrfHydroBmi class
|   +-- lib/                    # Already has Cython extension
+-- notebooks/
|   +-- wrfhydro_bmi_complete_walkthrough.ipynb
+-- tests/                      # Already has pytest suite
+-- setup.py                    # Already has pymt.plugins entry_point
+-- MANIFEST.in                 # Must include data/ files
```

### Pattern 1: PyMT Plugin Entry Points
**What:** PyMT discovers plugins via Python's `importlib.metadata.entry_points()` mechanism.
**When to use:** Required for `from pymt.models import WrfHydroBmi` to work.
**Current state:** pymt_wrfhydro/setup.py already declares:
```python
entry_points = {
    "pymt.plugins": [
        "WrfHydroBmi=pymt_wrfhydro.bmi:WrfHydroBmi",
    ]
}
```
**What's needed:** PyMT must be installed, and the metadata YAML files must exist in `pymt_wrfhydro/data/WrfHydroBmi/` for PyMT to fully register the model. After creating metadata, re-install: `pip install --no-build-isolation .`

### Pattern 2: ModelMetadata Discovery
**What:** PyMT's `model_metadata` package finds YAML files via the `METADATA` attribute or `search_paths()`.
**Discovery order:**
1. If `hasattr(model, "METADATA")`, resolves path relative to model's module
2. Uses `model.__class__.__name__` as directory name under `data/`
3. Fallback: `$CONDA_PREFIX/share/csdms/ModelName/`

**What's needed:** The WrfHydroBmi class (in `bmi.py`) should have a `METADATA` attribute:
```python
import os
class WrfHydroBmi:
    METADATA = os.path.join(os.path.dirname(__file__), "data", "WrfHydroBmi")
```
The babelizer convention has `pymt_wrfhydro/data/` as a symlink to `../meta/`. Our package has them as separate real directories. Recommendation: write to both `meta/WrfHydroBmi/` and `pymt_wrfhydro/data/WrfHydroBmi/` (the latter is what gets packaged).

### Pattern 3: CSDMS Model Metadata (4 YAML files)
**What:** Metadata files that describe a BMI model to the PyMT registry.

**info.yaml** -- Model identification:
```yaml
name: WrfHydroBmi
summary: "WRF-Hydro v5.4.0 hydrological model with BMI wrapper for coupled simulation via PyMT"
url: https://ral.ucar.edu/projects/wrf_hydro
author: "Mohan Sai Movva (BMI wrapper); NCAR (WRF-Hydro model)"
email: ""
version: 0.1.0
license: MIT License
doi: ""
cite_as: "Gochis et al. (2020). The WRF-Hydro modeling system technical description, Version 5.1.1. NCAR Technical Note."
```

**api.yaml** -- API class definition (update existing):
```yaml
name: WrfHydroBmi
language: fortran
package: pymt_wrfhydro
class: WrfHydroBmi
initialize_args: bmi_config.nml
```

**parameters.yaml** -- Exposed configuration parameters (keep minimal):
```yaml
wrfhydro_run_dir:
  description: "Path to WRF-Hydro run directory containing namelists and forcing data"
  value:
    type: string
    default: "."
    units: "-"
```

**run.yaml** -- Run configuration:
```yaml
config_file: bmi_config.nml
```

**bmi_config.nml** -- Jinja2 template config:
```
&bmi_wrfhydro_config
  wrfhydro_run_dir = "{{ wrfhydro_run_dir }}"
/
```

### Pattern 4: PyMT Model Usage (the 20-line vision)
**What:** The project goal -- model control from Python via PyMT.
```python
# Standalone import (works without PyMT installed)
from pymt_wrfhydro import WrfHydroBmi

model = WrfHydroBmi()
model.initialize("bmi_config.nml")

for _ in range(6):  # 6 hours
    model.update()
    q = model.get_value("channel_water__volume_flow_rate")
    print(f"Streamflow max={q.max():.4f} m3/s")

model.finalize()

# PyMT registry import (enhanced with grid mapping, unit conversion)
from pymt.models import WrfHydroBmi as PymtModel
model = PymtModel()
model.initialize(*model.setup())
# ... PyMT extras: model.var["name"], model.quick_plot() ...
```

### Anti-Patterns to Avoid
- **Installing PyMT without dry-run:** Could silently downgrade numpy/scipy/mpi4py
- **Creating metadata without re-installing pymt_wrfhydro:** Metadata discovered at install time
- **Running notebook without mpirun:** WRF-Hydro requires MPI; use `mpirun --oversubscribe -np 1 jupyter notebook`
- **Hardcoding absolute paths in metadata/notebook:** Use relative paths or template variables
- **Writing to meta/ but not data/:** Only `pymt_wrfhydro/data/` gets packaged and installed

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Plugin discovery | Custom model registry | PyMT entry_points (`pymt.plugins`) | Standard Python packaging mechanism |
| Unit conversion | Manual conversion code | PyMT's gimli.units (automatic) | Handles all UDUNITS2-compatible strings |
| Grid mapping | Custom interpolation | PyMT's grid mappers | Already handles rectilinear-to-unstructured |
| Config templating | Custom config parser | PyMT's Jinja2 template system | Standard approach for all PyMT plugins |
| Metadata format | Custom JSON/dict | CSDMS model-metadata YAML schema | model_metadata package expects this format |

**Key insight:** PyMT provides the orchestration layer -- Phase 9 only needs to create the metadata files that tell PyMT about our model. All heavy lifting (grid mapping, time sync, data exchange) is PyMT's job when actual coupling happens in Phase 4 of the overall project.

## Common Pitfalls

### Pitfall 1: PyMT Conda Install Downgrades Packages
**What goes wrong:** `conda install pymt` triggers solver to downgrade numpy, scipy, or mpi4py.
**Why it happens:** PyMT conda-forge package may be pinned to older dependency versions, especially if not rebuilt for numpy 2.x.
**How to avoid:** Always `conda install --dry-run` first. Check for downgrades of: numpy, scipy, mpi4py, cython, setuptools.
**Warning signs:** Solver takes > 5 minutes; "DOWNGRADED" in output; numpy drops below 2.0.

### Pitfall 2: PyMT Not Finding Plugin After Metadata Addition
**What goes wrong:** `from pymt.models import WrfHydroBmi` fails with KeyError.
**Why it happens:** Entry points recorded at pip install time. Adding files doesn't update registry.
**How to avoid:** After creating YAML files, re-run `pip install --no-build-isolation .` in pymt_wrfhydro/.
**Warning signs:** `import pymt; print(pymt.MODELS)` doesn't include `WrfHydroBmi`.

### Pitfall 3: METADATA Attribute Not Set on WrfHydroBmi
**What goes wrong:** PyMT finds the entry point but can't locate metadata YAML files.
**Why it happens:** model_metadata uses `METADATA` attribute to find the data directory. Without it, falls back to search that may fail.
**How to avoid:** Add `METADATA = os.path.join(os.path.dirname(__file__), "data", "WrfHydroBmi")` to the WrfHydroBmi class in bmi.py.
**Warning signs:** ImportError from model_metadata about missing metadata files.

### Pitfall 4: Jupyter Notebook Requires MPI
**What goes wrong:** Notebook cells segfault on pymt_wrfhydro import.
**Why it happens:** WRF-Hydro requires MPI; Jupyter starts without MPI context.
**How to avoid:** Launch: `mpirun --oversubscribe -np 1 jupyter notebook`
**Warning signs:** Segfault on first import cell; "MPI not initialized" errors.

### Pitfall 5: data/ vs meta/ Directory Sync
**What goes wrong:** YAML files exist in `meta/WrfHydroBmi/` but not in `pymt_wrfhydro/data/WrfHydroBmi/`.
**Why it happens:** Only `pymt_wrfhydro/data/` is included in the installed package. `meta/` is project-level, not packaged.
**How to avoid:** Write YAML files to both locations, or make data/ a symlink to ../meta/WrfHydroBmi.
**Warning signs:** `pip install` works but PyMT can't find metadata at runtime.

### Pitfall 6: PyMT setup() Staging vs WRF-Hydro Directory Requirements
**What goes wrong:** `model.setup()` returns tmpdir path, but WRF-Hydro needs DOMAIN/, FORCING/ in CWD.
**Why it happens:** PyMT stages config to tmpdir. WRF-Hydro expects full directory structure.
**How to avoid:** BMI config has `wrfhydro_run_dir` which sets the working directory. Test both `model.setup()` and direct `model.initialize(config)` pathways.
**Warning signs:** WRF-Hydro errors about missing DOMAIN/ or FORCING/ directories.

### Pitfall 7: numpy 2.x ABI Compatibility
**What goes wrong:** PyMT (or scipy) built against numpy 1.x segfaults with numpy 2.x.
**Why it happens:** numpy 2.0 changed C ABI; packages built against 1.x may be incompatible.
**How to avoid:** Conda solver should handle this. If pip, ensure compiled deps are numpy 2.x compatible.
**Warning signs:** ImportError about numpy ABI version mismatch.

## PyMT Installation Strategy (Detailed)

### PyMT 1.3.2 Version Details (MEDIUM confidence)
- **Release date:** 2024-10-11 (from pymt.readthedocs.io release notes)
- **Current dev version:** 1.3.3.dev0 (visible on readthedocs)
- **Python support:** Python 3.8+ (from official quickstart)
- **Conda-forge:** Available as `conda-forge::pymt`
- **PyPI:** Available as `pip install pymt`

### PyMT Expected Dependencies (MEDIUM confidence)
Based on PyMT's known dependency tree (from training data, verified by web search where possible):

| Dependency | Purpose | Already In Env? | Risk of Conflict |
|------------|---------|-----------------|-----------------|
| numpy | Array operations | YES (2.2.6) | LOW -- PyMT should accept 2.x |
| scipy | Interpolation, grid mappers | NO | MEDIUM -- compiled, may constrain numpy |
| xarray | N-D labeled data | NO | LOW -- pure Python |
| model-metadata | YAML metadata parsing | NO | LOW -- CSDMS-specific |
| gimli.units | Unit conversion | NO | LOW -- small package |
| jinja2 | Config templates | YES (babelizer dep) | LOW |
| pyyaml | YAML parsing | YES | LOW |
| click | CLI | YES (babelizer dep) | LOW |
| deprecated | Deprecation decorators | NO | LOW -- pure Python |
| netCDF4 | NetCDF I/O | YES | LOW |

**Highest-risk dependency:** scipy (compiled, may have numpy version constraints)

### Step-by-Step Install Approach
1. **Export environment backup:**
   ```bash
   conda env export > wrfhydro-bmi-backup-$(date +%Y%m%d).yml
   ```

2. **Dry-run install:**
   ```bash
   conda install -c conda-forge pymt --dry-run 2>&1 | tee pymt-dryrun.log
   ```

3. **Analyze dry-run output:**
   - Check for DOWNGRADED packages (especially numpy, scipy, mpi4py, cython)
   - Check for REMOVED packages
   - If clean (no critical downgrades): proceed with conda install
   - If downgrades: try pip install as fallback

4. **Conda install (if clean):**
   ```bash
   conda install -c conda-forge pymt
   ```

5. **Pip fallback (if conda conflicts):**
   ```bash
   pip install pymt
   ```
   Note: pip will use existing conda packages (scipy, netCDF4) if compatible.

6. **Verify install:**
   ```python
   python -c "import pymt; print(pymt.__version__); print(pymt.MODELS)"
   ```

7. **Verify no regressions:**
   ```bash
   python -c "from pymt_wrfhydro import WrfHydroBmi; print('OK')"
   ```

### If Both Conda and Pip Fail
Document the situation and proceed with pymt_wrfhydro standalone mode. The plugin system (`from pymt_wrfhydro import WrfHydroBmi`) works without PyMT installed. PyMT adds: grid mapping, time sync, unit conversion, NetCDF output, `model.var[]` xarray interface. These are Phase 4 coupling features, not Phase 9 requirements.

Minimum viable Phase 9: PyMT install documented as requiring separate env + metadata files created + notebook works in standalone mode + Doc 19 written. This still satisfies the spirit of the requirements.

## Plugin Registration Deep Dive

### How PyMT Discovers Plugins
1. `pymt` is imported
2. PyMT calls `importlib.metadata.entry_points(group="pymt.plugins")`
3. Each entry point format: `PluginName=package.module:ClassName`
4. PyMT lazily loads these into `pymt.MODELS` dict
5. `from pymt.models import WrfHydroBmi` triggers entry point resolution
6. PyMT wraps BMI class with `SetupMixIn` which calls `ModelMetadata.from_obj(bmi_obj)`
7. `ModelMetadata` searches for YAML files via `search_paths()`

### What's Already in Place
- `pymt_wrfhydro/setup.py` declares `pymt.plugins` entry point
- `meta/WrfHydroBmi/api.yaml` exists (partial -- needs update)
- `pymt_wrfhydro/data/WrfHydroBmi/api.yaml` exists (partial -- needs update)
- `MANIFEST.in` has `recursive-include pymt_wrfhydro/data *`
- `setup.py` has `include_package_data=True`

### What's Missing
- `info.yaml` in both `meta/WrfHydroBmi/` and `pymt_wrfhydro/data/WrfHydroBmi/`
- `parameters.yaml` in both locations
- `run.yaml` in both locations
- `bmi_config.nml` template in both locations
- `METADATA` class attribute on WrfHydroBmi in `bmi.py`
- Re-install after adding files

## Jupyter Notebook Architecture

### Launch Requirements
```bash
# Must launch Jupyter under MPI
cd /path/to/WRF_Hydro_Run_Local/run/
mpirun --oversubscribe -np 1 jupyter notebook

# Or for headless execution:
mpirun --oversubscribe -np 1 jupyter nbconvert --execute --to notebook \
    pymt_wrfhydro/notebooks/wrfhydro_bmi_complete_walkthrough.ipynb
```

### Notebook Sections (from CONTEXT.md requirements)
1. **Environment and MPI Check** -- verify mpi4py, pymt_wrfhydro importable
2. **The 20-Line Vision** -- full IRF cycle showcasing project goal
3. **All 8 Output Variables** -- get_value for each, summary statistics
4. **All 4 Input Variables** -- get/set cycle demonstration
5. **Grid Exploration** -- all 3 grids (1km LSM, 250m routing, vector channel)
6. **41 BMI Functions Walkthrough** -- Python equivalent of Fortran 151-test
7. **Streamflow Visualization** -- matplotlib time series + optional plotly spatial
8. **PyMT Registry Import** -- `from pymt.models import WrfHydroBmi` (if installed)
9. **Pytest Validation Cell** -- run existing test suite from notebook
10. **Summary and Next Steps**

### Notebook Dependencies
- matplotlib (required -- primary visualization)
- plotly (optional -- interactive spatial viz)
- jupyter (required -- notebook runtime)
- numpy (already installed)
- pymt_wrfhydro (already installed)
- pymt (required for PyMT registry cells, optional for standalone cells)

### File Size Consideration
Pre-run outputs include potentially large arrays (505 channel reaches, 16x15 LSM grid, 64x60 routing grid). Recommendation: keep outputs for key cells (vision demo, plots), clear for repetitive cells (41 BMI function walkthrough) to balance readability and file size.

## Code Examples

### Example 1: PyMT Plugin Verification
```python
import pymt
print(f"PyMT version: {pymt.__version__}")
print(f"Available models: {pymt.MODELS}")
assert "WrfHydroBmi" in pymt.MODELS, "Plugin not registered!"
```

### Example 2: Full 20-Line Vision
```python
import os
os.chdir("/path/to/WRF_Hydro_Run_Local/run/")

from pymt_wrfhydro import WrfHydroBmi

model = WrfHydroBmi()
model.initialize("bmi_config.nml")

for hour in range(6):
    model.update()
    q = model.get_value("channel_water__volume_flow_rate")
    print(f"Hour {hour+1}: max streamflow = {q.max():.4f} m3/s")

import numpy as np
streamflow = model.get_value("channel_water__volume_flow_rate")
soil = model.get_value("soil_water__volume_fraction")
snow = model.get_value("snowpack__liquid-equivalent_depth")
print(f"\nFinal: {len(streamflow)} reaches, "
      f"{np.prod(soil.shape)} soil cells, {np.prod(snow.shape)} snow cells")

model.finalize()
print("Simulation complete!")
```

### Example 3: MPI Safety Check Cell
```python
import sys
try:
    from mpi4py import MPI
    comm = MPI.COMM_WORLD
    print(f"MPI rank: {comm.Get_rank()} of {comm.Get_size()}")
    print(f"MPI library: {MPI.Get_library_version().split(chr(10))[0][:60]}")
except ImportError:
    print("WARNING: mpi4py not available.")
    print("Launch with: mpirun --oversubscribe -np 1 jupyter notebook")
```

### Example 4: Standalone vs PyMT Import
```python
# Method 1: Standalone (direct BMI, no PyMT needed)
from pymt_wrfhydro import WrfHydroBmi as StandaloneBmi
model1 = StandaloneBmi()
model1.initialize("bmi_config.nml")

# Method 2: PyMT registry (enhanced with grid mapping, unit conversion)
try:
    from pymt.models import WrfHydroBmi as PymtModel
    model2 = PymtModel()
    model2.initialize(*model2.setup())
    print("PyMT import: SUCCESS")
except ImportError:
    print("PyMT not installed -- using standalone mode")
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| PyMT cfunits (internal) | gimli.units (external) | PyMT ~1.2+ | Unit parsing is now external dependency |
| pkg_resources for plugins | importlib.metadata | Python 3.10+ | Our __init__.py already uses importlib.metadata |
| Babelizer setuptools (0.3.9) | Babelizer meson-python (0.3.10.dev) | Not yet released | We use 0.3.9 (stable) |
| PyMT 1.3.1 (2021-03-18) | PyMT 1.3.2 (2024-10-11) | Oct 2024 | Latest stable |

## Open Questions

1. **PyMT numpy 2.x compatibility**
   - What we know: PyMT 1.3.2 released Oct 2024; conda-forge numpy 2.x migration was ongoing
   - What's unclear: Whether conda-forge PyMT 1.3.2 is built against numpy 2.x or 1.x
   - Recommendation: Dry-run will reveal. If built against 1.x, conda may try to downgrade. Pip avoids this.

2. **PyMT model.setup() with WRF-Hydro directory structure**
   - What we know: setup() stages config to tmpdir; WRF-Hydro needs DOMAIN/, FORCING/
   - What's unclear: Whether wrfhydro_run_dir in config template resolves correctly from tmpdir
   - Recommendation: Test both setup() and direct initialize() pathways.

3. **PyMT quick_plot() with vector grids**
   - What we know: WRF-Hydro grid 2 is "vector" (channel network)
   - What's unclear: Whether PyMT's quick_plot handles vector grid type
   - Recommendation: Test; if fails, use matplotlib directly in notebook.

4. **MANIFEST.in coverage for meta/ files**
   - What we know: `MANIFEST.in` has `recursive-include pymt_wrfhydro/data *`
   - What's unclear: Whether this captures all YAML files after we add them
   - Recommendation: Verify with `python setup.py sdist` and check tarball contents.

## Sources

### Primary (HIGH confidence)
- Project CLAUDE.md -- definitive project structure, naming, conventions
- pymt_wrfhydro/setup.py -- actual entry_points declaration (verified in codebase)
- pymt_wrfhydro/__init__.py -- MPI bootstrap pattern (verified in codebase)
- pymt_wrfhydro/meta/WrfHydroBmi/api.yaml -- existing partial metadata
- Phase 7 RESEARCH.md -- build stack versions (numpy 2.2.6, mpi4py 4.1.1, etc.)
- Phase 8 RESEARCH.md -- bmi-tester results, singleton behavior
- Doc 5 (5.PyMT_Complete_Guide.md) -- PyMT architecture, plugin ecosystem, coupling patterns

### Secondary (MEDIUM confidence)
- [PyMT ReadTheDocs](https://pymt.readthedocs.io/en/latest/) -- version 1.3.3.dev0 docs
- [PyMT Release Notes](https://pymt.readthedocs.io/en/latest/history.html) -- version 1.3.2 release (2024-10-11)
- [PyMT conda-forge](https://anaconda.org/conda-forge/pymt) -- availability confirmed
- [PyMT GitHub](https://github.com/csdms/pymt) -- source repo
- [model-metadata PyPI](https://pypi.org/project/model-metadata/) -- metadata package
- [pymt_hydrotrend GitHub](https://github.com/mcflugen/pymt_hydrotrend) -- reference plugin
- [conda-forge numpy 2.x migration](https://conda-forge.org/news/2025/05/28/numpy-2-migration-closure/) -- migration timeline
- [pymt conda-environments docs](https://pymt.readthedocs.io/en/latest/conda-environments.html) -- env setup guidance

### Tertiary (LOW confidence)
- PyMT exact dependency list -- could not verify current setup.cfg from GitHub; listed dependencies are from training data + partial web search verification
- PyMT 1.3.2 numpy 2.x build compatibility -- unverified; dry-run install will reveal
- model_metadata YAML schema version -- based on training data; may have evolved

## Metadata

**Confidence breakdown:**
- Standard stack: MEDIUM - PyMT version confirmed (1.3.2), but exact dep versions not verified from current source
- Architecture: HIGH - plugin mechanism verified from setup.py code + Python packaging docs + prior research pass
- Pitfalls: MEDIUM - dependency conflicts primary concern; based on conda solver patterns + prior v2.0 experience
- Metadata files: MEDIUM-HIGH - YAML format from prior research + pymt_hydrotrend reference; discovery mechanism verified from model_metadata analysis

**Research date:** 2026-02-25
**Valid until:** 2026-03-25 (30 days -- PyMT is slowly evolving; main risk is conda solver behavior)
