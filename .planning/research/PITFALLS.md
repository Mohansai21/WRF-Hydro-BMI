# Domain Pitfalls: Babelizing a Fortran+MPI BMI Shared Library

**Domain:** Babelizer integration for Fortran BMI shared library (MPI-linked, singleton model)
**Researched:** 2026-02-24
**Confidence:** HIGH for babelizer mechanics (source code verified), MEDIUM for runtime issues (community patterns + official docs)

---

## Critical Pitfalls

Mistakes that cause build failures, segfaults, or force rewrites.

---

### Pitfall 1: Meson Cannot Find Our Library via pkg-config

**What goes wrong:**
Running `pip install .` inside the babelized `pymt_wrfhydro/` directory fails with:
```
meson.build:XX: ERROR: Dependency "bmiwrfhydrof" not found, tried pkgconfig
```
The babelizer-generated `meson.build` contains `dependency('bmiwrfhydrof', method: 'pkg-config')`. Meson calls `pkg-config --cflags --libs bmiwrfhydrof` at build time and it fails because either the `.pc` file does not exist, is not on `PKG_CONFIG_PATH`, or contains incorrect paths.

**Why it happens:**
Three distinct failure modes converge here:

1. **Missing .pc file.** We created `bmiwrfhydrof.pc` and installed it to `$CONDA_PREFIX/lib/pkgconfig/`, but `pip install` launches a subprocess that may not inherit the conda environment. The `PKG_CONFIG_PATH` is not set in the build isolation environment.

2. **pip build isolation.** By default, `pip install .` creates an isolated build environment. This new environment does not have `$CONDA_PREFIX/lib/pkgconfig` on its `PKG_CONFIG_PATH`. Even if the parent shell has the correct paths, the isolated pip subprocess does not.

3. **Meson discards PKG_CONFIG_PATH.** There is a known Meson issue (#14461) where pre-defined `PKG_CONFIG_LIBDIR` and related environment variables can be discarded during dependency resolution, especially in cross-compilation or native build scenarios.

**Consequences:**
Build fails immediately. No pymt_wrfhydro package is produced. This is the most likely first failure mode when attempting babelization.

**Prevention:**
1. **Use `--no-build-isolation` flag:**
   ```bash
   pip install --no-build-isolation .
   ```
   This uses the current conda environment directly (with all paths intact) instead of creating an isolated build env.

2. **Set PKG_CONFIG_PATH explicitly before pip install:**
   ```bash
   export PKG_CONFIG_PATH=$CONDA_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH
   pip install --no-build-isolation .
   ```

3. **Verify pkg-config works BEFORE attempting pip install:**
   ```bash
   pkg-config --cflags --libs bmiwrfhydrof
   # Expected: -I/path/include -L/path/lib -lbmiwrfhydrof
   ```

4. **Ensure the .pc file has correct absolute paths** (not relative, not stale from a different conda env activation).

**Detection:**
- `pip install .` fails with "Dependency not found" mentioning pkg-config
- The error appears during the Meson configure phase, before any compilation starts
- Running `pkg-config --cflags --libs bmiwrfhydrof` manually from the same shell works fine (because the parent shell has the correct env, but pip's subprocess does not)

**Phase to address:** Phase 2a (babel.toml + babelize init). Verify pkg-config discovery BEFORE running pip install. This is the gatekeeper for everything else.

---

### Pitfall 2: Babelizer's Multi-Instance model_array vs WRF-Hydro's Singleton

**What goes wrong:**
The babelizer auto-generates `bmi_interoperability.f90` with a `model_array(N_MODELS)` pattern supporting up to 2,048 simultaneous model instances:
```fortran
integer, parameter :: N_MODELS = 2048
type (bmi_wrf_hydro) :: model_array(N_MODELS)
logical :: model_avail(N_MODELS) = .true.
```
Each Python `WrfHydroBmi()` call invokes `bmi_new()` which allocates a new slot. But WRF-Hydro uses Fortran module-level globals (`COSZEN`, `SMOIS`, `rt_domain`, etc.) that are singletons. Creating a second instance either:
- Crashes (double allocation of module arrays)
- Silently corrupts state (two "instances" sharing the same global state)
- Succeeds on `bmi_new()` but crashes on the second `initialize()` due to `wrfhydro_engine_initialized` guard

**Why it happens:**
The babelizer's architecture ASSUMES models can support multiple instances. This is true for simple models (like the Heat example) that store all state inside the derived type. WRF-Hydro stores state in module globals (`module_RT_data`, `module_noahmp_hrldas_driver`, etc.) which are shared across all `type(bmi_wrf_hydro)` instances in the same process.

Our `wrfhydro_engine_initialized` flag correctly prevents double-initialization of WRF-Hydro internals. The second instance's `initialize()` will detect this and skip the engine init. But the second instance will then point to the same global state as the first, producing incorrect coupling behavior.

**Consequences:**
- If a user (or PyMT) creates two `WrfHydroBmi()` instances, the second one is silently broken
- bmi-tester might create multiple instances during test lifecycle
- PyMT's internal mechanics might attempt multi-instance patterns

**Prevention:**
1. **Document the singleton constraint prominently** in the generated package's README and docstrings
2. **The bmi_new() slot allocation will still work** -- the issue is at `initialize()` time, not allocation time. Our `wrfhydro_engine_initialized` guard prevents crashes but does NOT prevent confusion.
3. **Test with exactly ONE instance** and document that WRF-Hydro does not support multi-instance.
4. **Consider adding a module-level counter** in `bmi_wrf_hydro.f90` that explicitly returns `BMI_FAILURE` from `initialize()` if more than one instance has been initialized:
   ```fortran
   integer, save :: active_instance_count = 0
   ! In initialize():
   if (active_instance_count > 0) then
     bmi_status = BMI_FAILURE
     return
   end if
   active_instance_count = active_instance_count + 1
   ```
5. **Reset the counter in finalize()** so sequential init/finalize/init patterns work.

**Detection:**
- Second `WrfHydroBmi()` instance returns unexpected values
- Segfault on second `initialize()` call
- bmi-tester creates multiple model instances and they interfere

**Phase to address:** Phase 2a (pre-babelization wrapper hardening). Add explicit guard BEFORE babelizing.

---

### Pitfall 3: MPI Symbol Resolution Crash (RTLD_GLOBAL)

**What goes wrong:**
Importing `pymt_wrfhydro` or calling `initialize()` produces a segfault inside MPI internals. The crash occurs because the babelized Cython extension loads `libbmiwrfhydrof.so` (which depends on `libmpi.so`) with `RTLD_LOCAL` (the default). Open MPI's internal plugin system uses `dlopen()` to load its components, and those components depend on symbols from `libmpi.so`. With `RTLD_LOCAL`, those symbols are invisible.

**Why it happens:**
Open MPI 5.0.8 (our conda version) uses `dlopen()` internally to load MCA (Modular Component Architecture) plugins. These plugins do NOT explicitly link to `libmpi.so` -- they expect its symbols to be in the global namespace. Python's `ctypes.CDLL()` and Cython extension loading both use `RTLD_LOCAL` by default, which hides `libmpi` symbols from the plugins.

This is documented in Open MPI official docs (Section 11.4: "Dynamically loading libmpi at runtime") and GitHub issue #3705.

The babelizer-generated Cython extension does NOT handle this automatically. The Heat model example does not use MPI, so this issue is invisible in the reference implementation.

**Consequences:**
- Segfault on import or first BMI call
- Error manifests ONLY when loading from Python -- works fine from Fortran test executables
- May work with MPICH (which does not use dlopen for plugins) but fails with Open MPI

**Prevention:**
1. **Import mpi4py before importing pymt_wrfhydro:**
   ```python
   from mpi4py import MPI  # Loads MPI with correct RTLD_GLOBAL flags
   from pymt_wrfhydro import WrfHydroBmi
   ```
   mpi4py handles the RTLD_GLOBAL loading correctly.

2. **Or manually load MPI with RTLD_GLOBAL:**
   ```python
   import ctypes
   ctypes.CDLL("libmpi.so", mode=ctypes.RTLD_GLOBAL)
   from pymt_wrfhydro import WrfHydroBmi
   ```

3. **Or set environment variable before Python starts:**
   ```bash
   export LD_PRELOAD=libmpi.so
   python -c "from pymt_wrfhydro import WrfHydroBmi"
   ```

4. **Add an `__init__.py` guard** in the generated pymt_wrfhydro package that handles this automatically:
   ```python
   # pymt_wrfhydro/__init__.py (add at top, before extension import)
   import ctypes, os
   _mpi_path = os.path.join(os.environ.get('CONDA_PREFIX', ''), 'lib', 'libmpi.so')
   if os.path.exists(_mpi_path):
       ctypes.CDLL(_mpi_path, mode=ctypes.RTLD_GLOBAL)
   ```

**Detection:**
- Segfault with backtrace showing `dlopen`, `mca_base_component_find`, or `opal_init`
- "symbol lookup error" mentioning MPI-related symbols
- Works with `mpirun -np 1 python script.py` but NOT with `python script.py` directly

**Phase to address:** Phase 2c (first Python test). Must be solved immediately when testing the installed pymt_wrfhydro package. Document the mpi4py import requirement.

---

### Pitfall 4: pip Build Dependencies from PyPI Conflict with Conda Compilers

**What goes wrong:**
Running `pip install .` inside `pymt_wrfhydro/` triggers pip to install build dependencies (meson, meson-python, cython, numpy) from PyPI. These PyPI versions are incompatible with the conda-forge compilers (gfortran, gcc). The Meson build fails with cryptic compiler errors.

This is a documented issue (babelizer GitHub issue #73): "The requirements listed in the build-system section [of pyproject.toml] are installed from PyPI with pip but are unfortunately incompatible with the conda compilers."

**Why it happens:**
The babelizer-generated `pyproject.toml` specifies:
```toml
[build-system]
requires = ["cython", "numpy", "meson-python", "wheel"]
build-backend = "mesonpy"
```
When `pip install .` runs WITH build isolation (the default), pip creates a fresh venv and installs these from PyPI. The PyPI meson may find the wrong compiler, the PyPI numpy may have ABI incompatibilities, and the overall build environment is inconsistent with the conda environment where gfortran 14.3.0 and the Fortran libraries live.

**Consequences:**
- Build fails with compiler errors unrelated to our code
- Meson cannot find gfortran
- Cython extension compiled against wrong numpy ABI

**Prevention:**
1. **Install build deps with conda FIRST, then use --no-build-isolation:**
   ```bash
   conda install meson meson-python cython numpy wheel ninja -c conda-forge
   pip install --no-build-isolation .
   ```
   This is the canonical fix documented in babelizer issue #73.

2. **Never use `pip install .` with build isolation** for Fortran-containing packages in conda environments.

3. **Verify all build tools are from conda:**
   ```bash
   which meson  # Should be $CONDA_PREFIX/bin/meson
   which ninja  # Should be $CONDA_PREFIX/bin/ninja
   which gfortran  # Should be $CONDA_PREFIX/bin/gfortran
   ```

**Detection:**
- Error messages about missing compilers or wrong compiler versions
- Build fails during Meson configure or during Cython compilation
- Error mentions "Python dependency not found" in Meson output

**Phase to address:** Phase 2b (build pymt_wrfhydro). Document the `--no-build-isolation` requirement as the FIRST instruction.

---

### Pitfall 5: Babelizer Version Mismatch with Meson Build System

**What goes wrong:**
The babelizer version on conda-forge (latest: 0.3.9) generates code targeting a specific Meson build configuration. Older babelizer versions used setuptools; the transition to meson-python happened in recent versions. Installing the wrong version produces either:
- A setuptools-based package that requires `numpy.distutils` (removed in NumPy 2.0+)
- A meson-based package that requires features not in the installed Meson version

**Why it happens:**
The babelizer's template system evolved significantly:
- Older versions (< 0.3.8): Used `numpy.distutils` + `setup.py` for building Fortran extensions
- Current versions (0.3.9+): Use `meson-python` as the build backend
- `numpy.distutils` was removed in NumPy 2.0 (released 2024), so old templates fail on modern environments

Our conda environment likely has NumPy >= 2.0, so only the Meson-based babelizer templates will work.

**Consequences:**
- Build fails with "numpy.distutils is deprecated" or "ModuleNotFoundError: No module named 'numpy.distutils'"
- Or build fails with Meson version incompatibilities

**Prevention:**
1. **Pin babelizer >= 0.3.9** (Meson-based templates):
   ```bash
   conda install "babelizer>=0.3.9" -c conda-forge
   ```
2. **Pin compatible meson-python:**
   ```bash
   conda install meson-python -c conda-forge
   ```
3. **Check babelizer version before starting:**
   ```bash
   babelize --version
   # Must be >= 0.3.9 for Meson support
   ```

**Detection:**
- `babelize init` generates `setup.py` instead of `meson.build` (old version)
- Build fails with numpy.distutils import errors
- Build fails with Meson version feature errors

**Phase to address:** Phase 2a (environment setup). Verify version before running babelize init.

---

## Moderate Pitfalls

---

### Pitfall 6: bmi-tester Failures for Non-Standard BMI Implementations

**What goes wrong:**
Running `bmi-test pymt_wrfhydro:WrfHydroBmi --config-file=bmi_config.nml` fails on tests for BMI functions that return `BMI_FAILURE` or behave non-standardly. Known failure points:

1. **get_value_ptr** -- Returns BMI_FAILURE for all variables (REAL vs double mismatch). The Cython layer translates this to a Python `RuntimeError`. bmi-tester may test this and fail.

2. **get_value_at_indices / set_value_at_indices** -- Our int/float variants return BMI_FAILURE. If bmi-tester tests typed variants, these fail.

3. **Grid functions for unimplemented grid types** -- `get_grid_edge_nodes`, `get_grid_face_nodes`, `get_grid_face_edges`, `get_grid_nodes_per_face` all return BMI_FAILURE (not applicable for our grids). bmi-tester may test these.

4. **Start time convention** -- There was a CSDMS discussion (#26) about bmi-tester expecting start time to be 0.0. Our wrapper returns 0.0 (correct), but if this convention changes, it could break.

**Why it happens:**
The BMI spec says models that do not implement a function should return `BMI_FAILURE`. However, bmi-tester may treat `BMI_FAILURE` as a test failure rather than a skip. The boundary between "not applicable" and "broken" is unclear in automated testing.

**Consequences:**
- bmi-tester reports failures that are actually expected behavior
- Creates false impression that the BMI wrapper is broken
- May block PyMT registration if bmi-tester pass is required

**Prevention:**
1. **Run bmi-tester early** to identify which tests fail and why
2. **Document expected failures** with justification:
   - `get_value_ptr`: Not implemented (REAL->double mismatch, copy-based get_value works)
   - Grid edge/face functions: Not applicable for uniform rectilinear and vector grids
3. **Check bmi-tester's skip/xfail mechanism** -- newer versions may support marking expected failures
4. **Use `--config-file` and `--root-dir` flags** to ensure bmi-tester runs from the correct working directory with the correct config

**Detection:**
- bmi-tester reports X failures out of Y tests
- Failures are all in get_value_ptr, grid topology, or at_indices functions
- The model actually works correctly via get_value (copy-based)

**Phase to address:** Phase 2c (validation). Run bmi-tester, categorize failures as genuine bugs vs expected non-implementation.

---

### Pitfall 7: Working Directory Chaos with WRF-Hydro's chdir Pattern

**What goes wrong:**
WRF-Hydro's BMI `initialize()` and `update()` call `chdir()` to the run directory (for reading namelists and writing output), then `chdir()` back. PyMT also changes directories: its `setup()` method creates a temporary run directory, and `update_until()` runs from the initialization folder. These competing `chdir()` calls on the same process can leave the working directory in an unexpected state.

When bmi-tester or PyMT calls `initialize()`, our wrapper does:
1. `getcwd(saved_dir)` -- save current dir
2. `chdir(run_dir)` -- go to WRF-Hydro run dir
3. Initialize WRF-Hydro (reads namelists from cwd)
4. `chdir(saved_dir)` -- restore

But if PyMT calls `setup()` first, it creates a temp dir and sets expectations about where config files live. If our `initialize()` receives a relative path to the config file, the `chdir()` inside may break the relative path resolution.

**Why it happens:**
WRF-Hydro reads its namelists (`namelist.hrldas`, `hydro.namelist`) from the current working directory -- hardcoded behavior that cannot be changed without modifying WRF-Hydro source. Our BMI wrapper handles this by chdir'ing to the run directory. But bmi-tester and PyMT also manipulate the working directory.

**Consequences:**
- "File not found" errors for namelists or forcing data
- Output files written to wrong directory
- Tests pass when run manually but fail through bmi-tester/PyMT

**Prevention:**
1. **Use absolute paths in the BMI config file:**
   ```
   &bmi_wrf_hydro_config
     wrfhydro_run_dir = "/absolute/path/to/WRF_Hydro_Run_Local/run/"
   /
   ```
2. **Use absolute path for the config file itself** when calling `initialize()`
3. **Test with bmi-tester's `--root-dir` flag** to set the base directory
4. **Add a post-update check** in the Python test that verifies `os.getcwd()` is unchanged after each BMI call
5. **WSL2 specific:** Keep paths under 200 characters. Fortran `character(len=256)` allows up to 256 chars, but WRF-Hydro internally uses `character(len=80)` in some places, which can truncate long WSL2 paths like `/mnt/c/Users/username/Desktop/Projects/...`

**Detection:**
- "namelist.hrldas not found" or similar file-not-found errors
- Tests work from one directory but not another
- Different behavior between manual Python test and bmi-tester

**Phase to address:** Phase 2c (bmi-tester validation). Set up with absolute paths from the start.

---

### Pitfall 8: Our C Binding Layer Conflicts with Babelizer's Generated Interop

**What goes wrong:**
Our `bmi_wrf_hydro_c.f90` defines C-callable symbols like `bmi_initialize`, `bmi_update`, `bmi_finalize`, etc. The babelizer generates its own `bmi_interoperability.f90` with the SAME symbol names (`bmi_initialize`, `bmi_update`, etc.) but with DIFFERENT signatures (the generated ones take a `model_index` integer as the first argument).

When Meson compiles and links both files, you get either:
- Duplicate symbol errors at link time
- The wrong version of the function gets called (linker picks one, ignores the other)

**Why it happens:**
Our C binding layer was built for ctypes testing -- it exposes a singleton pattern with no model index. The babelizer's interop layer uses a model_array pattern with model index. Both define `bind(C, name="bmi_initialize")` functions, but with different argument lists.

The babelizer's Meson build compiles `bmi_interoperability.f90` and links it against our `libbmiwrfhydrof.so`. If our library exports the conflicting C symbols, the linker has two definitions.

**Consequences:**
- Duplicate symbol linker error during pymt_wrfhydro build
- Or silent symbol resolution to the wrong function, causing segfaults

**Prevention:**
1. **CRITICAL: Our C binding layer (`bmi_wrf_hydro_c.f90`) must NOT be compiled into `libbmiwrfhydrof.so`.**
   - The shared library should only contain `bmi_wrf_hydro.f90` (the Fortran BMI module) and the WRF-Hydro static libraries.
   - The C binding layer is for ctypes testing only and must be excluded from the shared library.
   - Rebuild the .so WITHOUT `bmi_wrf_hydro_c.o` in the link line.

2. **Or rename our C binding symbols** to avoid collision:
   ```fortran
   bind(C, name="wrfhydro_bmi_initialize")  ! Our test symbols
   ```
   Instead of:
   ```fortran
   bind(C, name="bmi_initialize")  ! Conflicts with babelizer
   ```

3. **Verify with `nm` that the shared library does not export conflicting symbols:**
   ```bash
   nm -D libbmiwrfhydrof.so | grep " T bmi_"
   # Should NOT show bmi_initialize, bmi_update, etc.
   # SHOULD show Fortran module symbols (__bmiwrfhydrof_MOD_...)
   ```

**Detection:**
- "multiple definition of `bmi_initialize`" linker error during pip install
- Segfault when babelizer's Cython calls the wrong bmi_initialize (ours expects no model_index, babelizer passes one)

**Phase to address:** Phase 2a (pre-babelization). Rebuild libbmiwrfhydrof.so WITHOUT the C binding layer BEFORE running babelize init. This is a prerequisite.

---

### Pitfall 9: Fortran .mod File Version Incompatibility

**What goes wrong:**
The babelizer's Meson build compiles `bmi_interoperability.f90`, which contains `use bmiwrfhydrof`. Meson invokes gfortran to compile this file, and gfortran reads `bmiwrfhydrof.mod` from `$CONDA_PREFIX/include/`. If the `.mod` file was generated by a different version of gfortran than what Meson uses, compilation fails:
```
Fatal Error: Reading module 'bmiwrfhydrof' at line X column Y: Unexpected EOF
```
Or:
```
Fatal Error: Cannot read module file 'bmiwrfhydrof.mod': File format not recognized
```

**Why it happens:**
Fortran `.mod` files are compiler-specific AND version-specific. A `.mod` file from gfortran 13.x cannot be read by gfortran 14.x (or vice versa). If we compiled our library with one gfortran version and the babelizer's Meson build uses a different version (e.g., system gfortran vs conda gfortran), the `.mod` file is unreadable.

**Consequences:**
- Build of pymt_wrfhydro fails during Fortran compilation of `bmi_interoperability.f90`
- Error message is often cryptic ("Unexpected EOF" or "File format not recognized")

**Prevention:**
1. **Ensure the SAME gfortran is used throughout:**
   ```bash
   which gfortran  # Must be $CONDA_PREFIX/bin/gfortran
   gfortran --version  # Must match what compiled libbmiwrfhydrof.so
   ```
2. **Build with `--no-build-isolation`** to ensure Meson uses the same compiler from the conda env
3. **Set `FC` environment variable explicitly:**
   ```bash
   export FC=$CONDA_PREFIX/bin/gfortran
   pip install --no-build-isolation .
   ```
4. **The .mod files and .so must be compiled by the same gfortran.** If you update gfortran, rebuild the .so and reinstall the .mod files.

**Detection:**
- "Cannot read module file" or "Unexpected EOF" errors during bmi_interoperability.f90 compilation
- The error points to a `use` statement, not our code

**Phase to address:** Phase 2b (pip install). Ensure consistent compiler before building.

---

### Pitfall 10: MPI_Init Not Called Before BMI Initialize

**What goes wrong:**
The babelized Python package calls `initialize()` but MPI has not been initialized. WRF-Hydro internally uses MPI calls (even in serial mode, np=1). Without `MPI_Init`, these calls segfault or produce "MPI not initialized" errors.

Neither the babelizer's Cython layer nor PyMT calls `MPI_Init`. The responsibility falls on the user script.

**Why it happens:**
WRF-Hydro was designed to run with `mpirun`, which calls `MPI_Init` before `main()`. Our Fortran test programs (`bmi_wrf_hydro_test.f90`) explicitly call `MPI_Init`. But when loaded from Python, there is no automatic MPI initialization unless the user imports `mpi4py`.

**Consequences:**
- Segfault on `initialize()` from Python
- "MPI_COMM_WORLD is not a valid communicator" error
- Works with `mpirun -np 1 python script.py` but fails with `python script.py`

**Prevention:**
1. **Document: "Import mpi4py.MPI before using WrfHydroBmi"**
2. **Add guard in wrapper:**
   ```python
   # In pymt_wrfhydro/__init__.py
   try:
       from mpi4py import MPI
   except ImportError:
       raise ImportError(
           "pymt_wrfhydro requires mpi4py. Install with: conda install mpi4py"
       )
   ```
3. **Add mpi4py to package requirements** in babel.toml:
   ```toml
   [package]
   requirements = ["mpi4py"]
   ```

**Detection:**
- Segfault or "MPI not initialized" on first `initialize()` call
- Works when run with `mpirun -np 1` but not standalone

**Phase to address:** Phase 2a (babel.toml configuration) and Phase 2c (first Python test).

---

## Minor Pitfalls

---

### Pitfall 11: WSL2 Long Path Truncation in Meson Build

**What goes wrong:**
Meson creates build directories with long paths (e.g., `pymt_wrfhydro/build/cp312-cp312-linux_x86_64/`). Combined with the already-long WSL2 mount path (`/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/`), the total path can exceed Fortran's `character(len=80)` or `character(len=256)` limits used in WRF-Hydro namelists and our config file.

**Prevention:**
- Work from a short base path (e.g., `/home/mohansai/wrfhydro-bmi/`)
- Or create a symlink: `ln -s /mnt/c/Users/.../WRF-Hydro-BMI ~/wbmi`
- Use absolute paths that are as short as possible in all config files

**Detection:**
- Path truncation errors or "file not found" for paths that clearly exist
- Works when project is at a shorter path

**Phase to address:** Phase 2 setup. Consider working from `$HOME` instead of `/mnt/c/`.

---

### Pitfall 12: get_var_type Returns "double precision" but WRF-Hydro Stores REAL

**What goes wrong:**
Our `get_var_type()` returns `"double precision"` for all variables. The babelizer's Cython layer maps this to `numpy.float64` and calls `bmi_get_value_double`. Our `get_value_double` internally copies from WRF-Hydro's single-precision REAL arrays to double-precision output buffers.

This works correctly but is semantically misleading: we report the TYPE as double precision when the actual storage is single precision. If bmi-tester or PyMT verifies type consistency (checking that `get_var_type` matches actual data precision), this mismatch could be flagged.

**Prevention:**
- This is already working correctly (REAL->double copy happens transparently)
- Document in the package that variables are stored as REAL but exposed as double
- If bmi-tester flags this, consider changing `get_var_type` to return `"real"` and implementing `get_value_float` instead (requires more wrapper changes)
- The Cython DTYPE_F_TO_PY mapping recognizes both `"real"` (float32) and `"double precision"` (float64)

**Phase to address:** Phase 2c (bmi-tester validation). Only change if bmi-tester actually flags it.

---

### Pitfall 13: Missing wrfhydro_bmi_state_mod.mod in Installed Files

**What goes wrong:**
Our `bmi_wrf_hydro.f90` defines TWO modules in one file:
1. `wrfhydro_bmi_state_mod` (state persistence, lines 1-25)
2. `bmiwrfhydrof` (the actual BMI module, lines 28+)

When the babelizer's `bmi_interoperability.f90` does `use bmiwrfhydrof`, gfortran reads `bmiwrfhydrof.mod`. But `bmiwrfhydrof.mod` has an internal dependency on `wrfhydro_bmi_state_mod.mod`. If `wrfhydro_bmi_state_mod.mod` is not installed to `$CONDA_PREFIX/include/`, compilation fails.

**Prevention:**
- Install BOTH .mod files to `$CONDA_PREFIX/include/`:
  ```bash
  cp bmiwrfhydrof.mod wrfhydro_bmi_state_mod.mod $CONDA_PREFIX/include/
  ```
- Verify both exist before attempting babelization
- The pkg-config `Cflags` must include the path to both: `-I$CONDA_PREFIX/include`

**Detection:**
- "Cannot read module file 'wrfhydro_bmi_state_mod.mod'" during bmi_interoperability.f90 compilation
- Build of pymt_wrfhydro fails at Fortran compile step

**Phase to address:** Phase 2a (pre-babelization). Ensure all .mod files are installed.

---

### Pitfall 14: babelizer Editable Install Does Not Work for Fortran

**What goes wrong:**
Attempting `pip install -e .` (editable install) for the babelized package fails because Meson editable installs for Fortran extensions require all build dependencies to remain available at execution time. The extension is rebuilt on every import, which is slow and fragile.

**Prevention:**
- Use regular install: `pip install --no-build-isolation .` (NOT `-e .`)
- For development iteration, uninstall and reinstall:
  ```bash
  pip uninstall pymt_wrfhydro
  pip install --no-build-isolation .
  ```
- If editable install is needed, install all build deps with conda first AND use `--no-build-isolation`

**Detection:**
- `pip install -e .` fails with Meson/linker errors
- Or install succeeds but import triggers slow rebuild every time

**Phase to address:** Phase 2b (build process). Use regular install from the start.

---

### Pitfall 15: NetCDF/HDF5 Library Conflicts

**What goes wrong:**
The babelized package links against `libbmiwrfhydrof.so`, which depends on `libnetcdff.so` and `libnetcdf.so`. If the Python environment also has NetCDF/HDF5 libraries (via xarray, h5py, etc.), there can be symbol conflicts or version mismatches when both are loaded in the same process.

**Prevention:**
- Use conda for ALL dependencies (ensures consistent NetCDF/HDF5 versions)
- Verify with `ldd libbmiwrfhydrof.so` that NetCDF resolves to conda's version
- Test importing alongside common scientific Python packages (xarray, h5py)

**Detection:**
- Segfault or HDF5 version mismatch errors when importing alongside xarray
- "HDF5 header version mismatch" warnings

**Phase to address:** Phase 2c (integration testing). Test with a realistic Python environment.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Environment setup | P5: Wrong babelizer version | Pin `babelizer>=0.3.9`, verify with `babelize --version` |
| Environment setup | P4: PyPI vs conda deps | Install all build deps with conda first |
| babel.toml writing | P2: Singleton not documented | Add instance guard to wrapper before babelizing |
| babel.toml writing | P10: MPI requirement | Add mpi4py to requirements |
| babelize init | P8: C binding symbol conflict | Rebuild .so WITHOUT bmi_wrf_hydro_c.o |
| babelize init | P13: Missing .mod files | Install all .mod files before babelizing |
| pip install | P1: pkg-config not found | Use --no-build-isolation + PKG_CONFIG_PATH |
| pip install | P9: .mod version mismatch | Same gfortran throughout + FC env var |
| pip install | P14: Editable install fails | Use regular pip install, not -e |
| First Python test | P3: MPI RTLD_GLOBAL crash | Import mpi4py before pymt_wrfhydro |
| First Python test | P7: Working directory chaos | Use absolute paths everywhere |
| bmi-tester | P6: Expected failures | Document which failures are by-design |
| bmi-tester | P12: Type reporting | Monitor if "double precision" causes issues |
| WSL2 platform | P11: Long path truncation | Work from short base path |
| WSL2 platform | P15: Library conflicts | Use conda for all deps |

---

## Priority Order for Prevention

Address these pitfalls in this order (most blocking first):

1. **P8: C binding conflict** -- Must rebuild .so without C bindings BEFORE babelizing
2. **P13: Missing .mod files** -- Must install ALL .mod files BEFORE babelizing
3. **P5: Babelizer version** -- Must verify correct version BEFORE babelize init
4. **P1: pkg-config discovery** -- Must verify BEFORE pip install
5. **P4: PyPI vs conda build deps** -- Must install conda deps BEFORE pip install
6. **P9: gfortran version consistency** -- Must verify BEFORE pip install
7. **P3: MPI RTLD_GLOBAL** -- Must solve BEFORE first Python test
8. **P10: MPI_Init** -- Must solve BEFORE first initialize() call
9. **P2: Singleton guard** -- Should add BEFORE babelizing (or document)
10. **P7: Working directory** -- Must use absolute paths from the start
11. **P6: bmi-tester failures** -- Address during validation
12. **P11-P15: Minor issues** -- Address as encountered

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| P1: pkg-config not found | LOW | Set PKG_CONFIG_PATH, use --no-build-isolation |
| P2: Singleton crash | MEDIUM | Add instance counter to bmi_wrf_hydro.f90, rebuild .so |
| P3: MPI RTLD_GLOBAL | LOW | Add `from mpi4py import MPI` to test script |
| P4: PyPI build deps | LOW | `conda install` build deps, use --no-build-isolation |
| P5: Wrong babelizer version | LOW | `conda install babelizer>=0.3.9` |
| P6: bmi-tester failures | LOW | Document expected failures, no code change needed |
| P7: Working directory | LOW | Switch to absolute paths in config |
| P8: C binding conflict | MEDIUM | Rebuild .so without bmi_wrf_hydro_c.o, re-babelize |
| P9: .mod version mismatch | MEDIUM | Rebuild everything with same gfortran, reinstall .mod |
| P10: MPI_Init missing | LOW | Add mpi4py import or requirement |
| P11: Long paths | LOW | Work from shorter base path |
| P12: Type reporting | LOW | Change get_var_type return if needed |
| P13: Missing .mod | LOW | Copy additional .mod files to $CONDA_PREFIX/include |
| P14: Editable install | LOW | Use regular install instead |
| P15: Library conflicts | MEDIUM | Ensure all deps from same conda env |

---

## Sources

### HIGH Confidence (source code verified)
- [CSDMS babelizer repository](https://github.com/csdms/babelizer) -- bmi_interoperability.f90 template, meson.build template, config.py validation (direct source code analysis)
- [Babelizer issue #73](https://github.com/csdms/babelizer/issues/73) -- PyPI vs conda compiler conflict (documented fix)
- [Open MPI docs: Dynamic loading](https://docs.open-mpi.org/en/v5.0.7/tuning-apps/dynamic-loading.html) -- RTLD_GLOBAL requirement (official documentation)
- [Open MPI issue #3705](https://github.com/open-mpi/ompi/issues/3705) -- dlopen RTLD_LOCAL issue (official issue)
- [CSDMS discussion #26](https://github.com/orgs/csdms/discussions/26) -- BMI start time convention
- [Meson issue #14461](https://github.com/mesonbuild/meson/issues/14461) -- PKG_CONFIG_LIBDIR discarded
- Local: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` -- module structure, get_var_type returns, get_value_ptr behavior
- Local: `bmi_wrf_hydro/src/bmi_wrf_hydro_c.f90` -- C binding symbols that conflict with babelizer
- Local: `.planning/research/CSDMS_BABELIZER_OFFICIAL.md` -- babelizer architecture verified from source

### MEDIUM Confidence (multiple sources agree)
- [Meson pkgconfig documentation](https://mesonbuild.com/Pkgconfig-module.html) -- pkg-config discovery patterns
- [meson-python editable installs](https://meson-python.readthedocs.io/en/latest/how-to-guides/editable-installs.html) -- editable install limitations
- [BMI time functions](https://bmi.csdms.io/en/stable/bmi.time_funcs.html) -- time convention documentation
- [BMI getter/setter docs](https://bmi.csdms.io/en/stable/bmi.getter_setter.html) -- get_value_ptr specification
- [mpi4py documentation](https://mpi4py.readthedocs.io/en/stable/overview.html) -- MPI initialization handling
- [bmi-tester repository](https://github.com/csdms/bmi-tester) -- test structure and behavior

### LOW Confidence (inference from patterns)
- Singleton model behavior with babelizer model_array -- inferred from template code, no documented test cases
- WSL2 path length issues with Meson -- inferred from known Fortran character limits, no specific Meson reports

---
*Pitfalls research for: Babelizing WRF-Hydro BMI shared library into pymt_wrfhydro*
*Researched: 2026-02-24*
