# Feature Landscape

**Domain:** Fortran BMI shared library with C bindings and Python interoperability
**Researched:** 2026-02-23
**Confidence:** HIGH for babelizer requirements (verified against babelizer source templates); MEDIUM for Python ctypes testing patterns

## Critical Finding: Babelizer Generates Its Own C Bindings

**The babelizer does NOT require users to write ISO_C_BINDING wrappers.** When you run
`babelize init babel.toml`, it auto-generates three files:

1. `bmi_interoperability.f90` -- Fortran `bind(C)` wrappers for all 41 BMI functions (uses a pool-based model array approach with `N_MODELS=2048` slots)
2. `bmi_interoperability.h` -- C header declaring ~29 functions (`bmi_new`, `bmi_initialize`, etc.)
3. `_fortran.pyx` -- Cython bindings calling the C functions from Python

The babelizer's `entry_point` in `babel.toml` is the **Fortran derived type name** (e.g., `bmi_heat` for the heat example). The babelizer instantiates this type in its generated code: `type(bmi_heat) :: model_array(2048)`.

**What this means for our milestone:**
- The shared library (.so) only needs to contain the existing Fortran BMI module (`bmiwrfhydrof` with type `bmi_wrf_hydro`)
- NO manual ISO_C_BINDING wrapper code is needed
- The babelizer generates the C bindings itself
- However, a Python ctypes test is still valuable for pre-babelizer validation

**Source:** [babelizer GitHub templates](https://github.com/csdms/babelizer) -- verified by examining `babelizer/data/templates/{{package.name}}/lib/bmi_interoperability.f90` and `bmi_interoperability.h` in the repository tree. Confidence: HIGH.

## Table Stakes

Features that must work for the shared library to be useful. Missing any = cannot proceed to Phase 2 (babelizer).

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Shared library `libwrfhydro_bmi.so` via CMake | Babelizer requires a `.so` that can be found via pkg-config; static `.a` will not work | Medium | CMakeLists.txt exists (650 lines) but currently targets static + test exe; needs `SHARED` library target |
| `-fPIC` compilation of BMI wrapper | Position-Independent Code required for shared library on Linux; without it, linking fails | Low | Add `-fPIC` flag to wrapper compilation; WRF-Hydro static libs may need rebuild with `-fPIC` (this is a risk) |
| `.so` links against 22 WRF-Hydro static libraries | WRF-Hydro subroutines (land_driver_ini/exe, HYDRO_ini/exe) must be resolved at link time | High | Circular dependency issue: libraries need 3x repetition or `--start-group`/`--end-group`; already solved in build.sh but needs CMake equivalent |
| `.so` links against MPI, NetCDF, BMI-Fortran | External dependencies must all be resolved | Low | Already handled in CMakeLists.txt for the test exe |
| `cmake --install` puts `.so` + `.mod` in `$CONDA_PREFIX` | Babelizer finds the library via pkg-config which reads installed `.pc` files | Low-Med | Follow bmi-example-fortran pattern: install TARGETS, .mod files, .pc file |
| pkg-config `.pc` file for `wrfhydrobmi` | Babelizer's generated CMakeLists.txt uses `pkg_check_modules()` to find the model library | Low | Template from bmi-example-fortran `bmiheatf.pc.cmake`; fill in library name, version, requires |
| Fortran module file installed to `include/` | Babelizer-generated `bmi_interoperability.f90` needs `use bmiwrfhydrof` which requires the `.mod` file | Low | Standard CMake install of MODULE_DIRECTORY output |
| `build.sh` shared library target | Developer build workflow for fast iteration without full CMake | Medium | Add `-shared -fPIC` flags; output `build/libwrfhydro_bmi.so` |
| Python ctypes/cffi smoke test | Pre-babelizer validation that the .so is loadable and functional from Python | Medium | Load .so, call a C-callable function (or use nm to verify symbols), init/update/finalize cycle |

## Differentiators

Features that add value beyond minimal babelizer compatibility. Not strictly required but increase confidence and production quality.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Python test exercises init/update/finalize via Fortran name mangling | Proves the full IRF cycle works from Python before babelizer adds its own layer | Medium | Must handle gfortran name mangling (`__bmiwrfhydrof_MOD_wrfhydro_initialize`); MPI init required before Fortran BMI init |
| Python test: get_value_double validates data | Proves data flows correctly WRF-Hydro -> Fortran -> .so -> Python; compare to known Croton NY values | Medium | numpy arrays via ctypes, call Fortran mangled symbol or use a thin C wrapper |
| CTest integration for shared library | Existing 151 Fortran tests run via `ctest` against the .so instead of static link | Low-Med | Change test exe link from static objects to `libwrfhydro_bmi.so` |
| Manual C binding layer (`bmi_interop.f90`) | Enables cleaner Python ctypes testing with `bind(C)` symbols; also useful for NextGen integration (like SCHISM's `register_bmi`) | Medium | ~300-500 lines following SCHISM BMI pattern; provides `bmi_new`, `bmi_initialize`, etc. with `bind(C, name="...")` |
| Full Python test covering all 12 BMI variables | Catches variable mapping bugs before babelizer Phase 2 | Low | Loop over get_input/output_var_names from Python |
| Python test validates grid metadata | Ensures grid type/rank/size/shape correct from Python side | Low | Compare to known Croton NY dimensions (15x16 LSM, 60x64 routing) |
| Detailed documentation (Doc 16) | User preference for detailed docs with emojis, diagrams, ML analogies | Medium | Covers shared library build, installation, Python test, babelizer prep |

## Anti-Features

Features to explicitly NOT build in this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Full `bmi_interoperability.f90` with all 41 `bind(C)` functions | Babelizer generates this automatically; writing it manually duplicates work | Build a clean .so with the Fortran module; let babelizer generate C bindings in Phase 2 |
| babel.toml + `babelize init` | Phase 2 scope; depends on working .so installed in `$CONDA_PREFIX` first | Just verify .so installs correctly and can be found via pkg-config |
| PyMT plugin registration | Phase 3 scope, depends on successful babelization | Out of scope entirely |
| SCHISM coupling | Phase 4 scope | Out of scope entirely |
| MPI parallel execution (np > 1) | Adds enormous complexity; serial-first approach following SCHISM BMI | Run with `mpirun -np 1`; WRF-Hydro still needs MPI linked |
| Windows .dll support | WSL2 is the target platform; .dll has different linking rules entirely | Only build .so on Linux/WSL2 |
| get_value_ptr working implementation | WRF-Hydro REAL -> BMI double type mismatch makes zero-copy impossible | Return BMI_FAILURE (already decided in Phase 1) |
| Thread safety / multi-instance support | WRF-Hydro module globals are inherently single-instance; babelizer's pool (N_MODELS=2048) will work because only 1 instance is used at a time | Document as known limitation |
| NextGen `register_bmi` function | Only needed for NOAA NextGen framework, not CSDMS/PyMT pathway | Could add later behind `#ifdef NGEN_ACTIVE` like SCHISM does |
| C header file for ctypes | Babelizer generates its own header; ctypes can declare prototypes in Python code directly | Declare function signatures in Python test directly, or test via Fortran name mangling |

## Feature Dependencies

```
bmi_wrf_hydro.f90 compiled with -fPIC --> can be included in shared library
WRF-Hydro static libs (22) linked in --> libwrfhydro_bmi.so resolves all symbols
libwrfhydro_bmi.so built --> cmake --install puts it in $CONDA_PREFIX/lib
.mod files installed --> $CONDA_PREFIX/include/bmiwrfhydrof.mod accessible
.pc file installed --> pkg-config wrfhydrobmi returns correct flags
All installed --> Python can load .so (ctypes test)
All installed --> babelizer can find library via pkg-config (Phase 2)
```

Key dependency chain:
```
-fPIC compilation --> .so builds --> .so installs with .pc --> babelizer finds it
```

Risk: If the 22 WRF-Hydro static libraries were NOT compiled with `-fPIC`, they cannot be linked into a shared library. This would require recompiling WRF-Hydro with `-fPIC` (add `-fPIC` to WRF-Hydro's CMake flags).

## MVP Recommendation

Prioritize (in this order):

1. **Verify WRF-Hydro `-fPIC` status** -- Check if existing `.a` libraries have position-independent code; if not, recompile WRF-Hydro with `-DCMAKE_POSITION_INDEPENDENT_CODE=ON`
2. **CMake shared library target** -- Add `SHARED` library, install targets, `.pc` file (follow bmi-example-fortran pattern exactly)
3. **`cmake --install` to `$CONDA_PREFIX`** -- Verify library, .mod, and .pc install correctly
4. **`pkg-config wrfhydrobmi` test** -- Verify babelizer can discover the library
5. **build.sh shared library target** -- Add `-shared -fPIC` for developer builds
6. **Python smoke test** -- Load .so, verify symbols exist, attempt init/update/finalize cycle

Defer to Phase 2: babel.toml, `babelize init`, full bmi-tester compliance, NextGen `register_bmi`

**Optional but recommended:** Write a thin `bmi_interop.f90` with a minimal set of `bind(C)` functions (just `bmi_new`, `bmi_initialize`, `bmi_update`, `bmi_finalize`, `bmi_get_component_name`, `bmi_get_value_double`) to enable cleaner Python testing. This is NOT required for babelizer but makes pre-babelizer validation much easier than dealing with Fortran name mangling.

## Babelizer Compatibility Checklist

For Phase 2 readiness, the shared library milestone must produce:

| Requirement | How to Verify | Status |
|-------------|---------------|--------|
| `libwrfhydro_bmi.so` exists | `ls $CONDA_PREFIX/lib/libwrfhydro_bmi.so` | Pending |
| `bmiwrfhydrof.mod` installed | `ls $CONDA_PREFIX/include/bmiwrfhydrof.mod` | Pending |
| `wrfhydrobmi.pc` installed | `pkg-config --libs wrfhydrobmi` returns `-lwrfhydro_bmi` | Pending |
| Module contains `bmi_wrf_hydro` type | `nm -D libwrfhydro_bmi.so \| grep bmiwrfhydrof` shows symbols | Pending |
| Library resolves all symbols | `ldd libwrfhydro_bmi.so` shows no unresolved | Pending |

The babel.toml for Phase 2 will be:
```toml
[library.WrfHydroF]
language = "fortran"
library = "wrfhydrobmi"
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
```

Note: `entry_point = "bmi_wrf_hydro"` is the Fortran derived type name from `bmiwrfhydrof` module. The babelizer will generate `type(bmi_wrf_hydro) :: model_array(2048)` in its interoperability layer.

## Sources

- [babelizer GitHub repository](https://github.com/csdms/babelizer) -- template files in `babelizer/data/templates/` (HIGH confidence, verified against source)
- [babelizer Fortran example documentation](https://babelizer.readthedocs.io/en/latest/example-fortran.html) -- babel.toml format, build process (HIGH confidence)
- [bmi-example-fortran](https://github.com/csdms/bmi-example-fortran) -- CMakeLists.txt pattern for shared library + pkg-config (HIGH confidence, verified locally)
- [bmi-fortran](https://github.com/csdms/bmi-fortran) -- BMI Fortran specification, bmif_2_0 module (HIGH confidence)
- [SCHISM_BMI bmischism.f90](SCHISM_BMI/src/BMI/bmischism.f90) -- `register_bmi` pattern for NextGen, `#ifdef NGEN_ACTIVE` (HIGH confidence, verified locally)
- [bmi-tester](https://github.com/csdms/bmi-tester) -- Python BMI testing tool, runs against babelized models (MEDIUM confidence)
- CSDMS wiki: [Babelizer](https://csdms.colorado.edu/wiki/Babelizer), [WRF-Hydro](https://csdms.colorado.edu/wiki/Model:WRF-Hydro) -- no existing pymt_wrfhydro plugin exists (MEDIUM confidence)
