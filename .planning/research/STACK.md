# Technology Stack: Fortran BMI Shared Library with C Bindings and Python Interop

**Project:** WRF-Hydro BMI Shared Library
**Researched:** 2026-02-23
**Confidence:** HIGH (verified against babelizer source code, SCHISM BMI reference, bmi-example-fortran)

---

## Executive Summary

Building a shared library from an existing Fortran BMI wrapper requires three layers: (1) the existing `bmi_wrf_hydro.f90` compiled as a shared library, (2) an `ISO_C_BINDING` interoperability layer that exposes flat C-callable functions, and (3) Python `ctypes` for testing. The critical discovery is that **the babelizer generates its own C binding layer** (`bmi_interoperability.f90`) -- so the project does NOT need to hand-write a NOAA-OWP-style `iso_c_bmi.f90`. Instead, the shared library just needs to expose the Fortran BMI module (`bmiwrfhydrof`) with the `bmi_wrf_hydro` type, and the babelizer will generate the C bindings automatically in Phase 2.

For the immediate milestone (pre-babelizer validation), a thin C binding layer is still needed to test from Python via `ctypes`. This layer follows the babelizer's own pattern: a module-level model array indexed by integer, with `bind(C)` free functions.

---

## Recommended Stack

### Core Framework

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Fortran 2003 | gfortran 14.3.0 | BMI wrapper + C binding layer | ISO_C_BINDING requires Fortran 2003; existing wrapper already uses it | HIGH |
| ISO_C_BINDING | intrinsic | Fortran-to-C interoperability | Standard Fortran 2003 intrinsic module; zero external dependencies | HIGH |
| CMake | 3.14+ (have 3.31.1) | Build system for shared library | Existing CMakeLists.txt (650 lines); babelizer requires CMake-built .so | HIGH |
| Python | 3.x (conda env) | Test script via ctypes | ctypes is stdlib; validates .so works from Python before babelizer | HIGH |

### Existing Dependencies (No Changes Needed)

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| bmi-fortran | 2.0.3 | BMI abstract interface (bmif_2_0 module) | Installed in conda; provides libbmif.so + bmif_2_0.mod |
| OpenMPI | 5.0.8 | MPI linking (serial execution, np=1) | WRF-Hydro libs compiled with MPI; must link |
| NetCDF-Fortran | 4.6.2 | WRF-Hydro I/O format | Already linked in CMakeLists.txt |
| NetCDF-C | 4.9.3 | Underlying NetCDF library | Required by NetCDF-Fortran |
| WRF-Hydro | v5.4.0 | The model being wrapped | 22 static .a libraries + 86 .mod files |

### Supporting Libraries for Python Test

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ctypes | stdlib | Python FFI to call .so C functions | Python test script (test_bmi_wrfhydro.py) |
| numpy | conda env | Array handling for get_value/set_value | Create/receive double arrays via ctypes |

---

## Critical Finding: Two Distinct C Binding Patterns Exist

Research uncovered two different C binding patterns used in the CSDMS/BMI ecosystem. Understanding the difference is essential to avoid wasted work.

### Pattern A: NOAA-OWP Opaque Handle (used by SCHISM_BMI for NextGen)

**Source:** `SCHISM_BMI/src/BMI/iso_c_fortran_bmi/src/iso_c_bmi.f90` (948 lines)

This pattern uses an opaque `c_ptr` handle containing a "boxed" Fortran polymorphic pointer. The caller gets a void pointer from `register_bmi()` and passes it to every subsequent BMI function.

```fortran
! Pattern A: opaque handle (NOAA-OWP / NextGen)
type box
  class(bmi), pointer :: ptr => null()
end type

function register_bmi(this) result(bmi_status) bind(C, name="register_bmi")
  type(c_ptr) :: this
  type(box), pointer :: bmi_box
  type(bmi_wrf_hydro), pointer :: bmi_model
  allocate(bmi_model)
  allocate(bmi_box)
  bmi_box%ptr => bmi_model
  this = c_loc(bmi_box)
  bmi_status = BMI_SUCCESS
end function

function initialize(this, config_file) result(bmi_status) bind(C, name="initialize")
  type(c_ptr) :: this
  character(kind=c_char, len=1), dimension(*), intent(in) :: config_file
  type(box), pointer :: bmi_box
  call c_f_pointer(this, bmi_box)
  bmi_status = bmi_box%ptr%initialize(c_to_f_string(config_file))
end function
```

**Pros:** Model-agnostic (any BMI model works), used by NOAA NextGen framework.
**Cons:** More complex; requires `bmif_2_0_iso` variant (not `bmif_2_0`); C caller manages memory.

### Pattern B: Babelizer Model Array Index (used by CSDMS babelizer for PyMT)

**Source:** Babelizer template `babelizer/data/templates/{{package.name}}/lib/bmi_interoperability.f90` (cloned from GitHub, verified 2026-02-23)

This pattern uses a fixed-size Fortran array of model instances, indexed by integer. The C caller gets an integer index from `bmi_new()` and passes it to every BMI function.

```fortran
! Pattern B: model array index (babelizer / PyMT)
integer, parameter :: N_MODELS = 2048
type (bmi_wrf_hydro) :: model_array(N_MODELS)
logical :: model_avail(N_MODELS) = .true.

function bmi_new() bind(c) result(model_index)
  integer (c_int) :: model_index
  integer :: i
  model_index = -1
  do i = 1, N_MODELS
     if (model_avail(i)) then
        model_avail(i) = .false.
        model_index = i
        exit
     end if
  end do
end function bmi_new

function bmi_initialize(model_index, config_file, n) bind(c) result(status)
  integer (c_int), intent(in), value :: model_index
  integer (c_int), intent(in), value :: n
  character (len=1, kind=c_char), intent(in) :: config_file(n)
  integer (c_int) :: status
  character (len=n, kind=c_char) :: config_file_
  integer :: i
  do i = 1, n
     config_file_(i:i) = config_file(i)
  enddo
  status = model_array(model_index)%initialize(config_file_)
end function bmi_initialize
```

**Pros:** Simpler; babelizer generates this automatically; direct method calls (no polymorphic dispatch).
**Cons:** Fixed array size (2048 slots); model type hard-coded in template.

### Recommendation: Use Pattern B (Babelizer Pattern)

**Use Pattern B because:**
1. The babelizer generates `bmi_interoperability.f90` automatically from the `babel.toml` `entry_point` field
2. Pattern B is what the babelizer Python layer (`_bmi.pyx` / Cython) expects to call
3. Pattern A is for NOAA NextGen integration (different ecosystem than PyMT)
4. Pattern B is simpler to test with Python `ctypes` (integer index vs opaque pointer)
5. Our project's goal is PyMT coupling, not NextGen

**However:** For the pre-babelizer Python test, write a simplified Pattern B manually. In Phase 2, the babelizer will replace it with its own generated version.

**Confidence: HIGH** -- Verified by reading the actual babelizer Jinja2 template source code.

---

## ISO_C_BINDING Patterns Specific to BMI

### String Conversion (Fortran strings <-> C strings)

BMI functions pass variable names as strings. Fortran strings are fixed-length, blank-padded; C strings are null-terminated. Every C binding function must convert.

```fortran
! Babelizer pattern: pass string as character array + length
function bmi_get_var_type(model_index, var_name, n, var_type, m) &
     bind(c) result(status)
  integer (c_int), intent(in), value :: model_index
  integer (c_int), intent(in), value :: n           ! length of var_name
  character (len=1, kind=c_char), intent(in) :: var_name(n)  ! C char array
  integer (c_int), intent(in), value :: m           ! length of var_type buffer
  character (len=1, kind=c_char), intent(out) :: var_type(m)  ! output buffer

  integer (c_int) :: i, status
  character (len=n, kind=c_char) :: var_name_       ! Fortran scalar string
  character (len=m, kind=c_char) :: var_type_

  ! Convert C char array to Fortran string
  do i = 1, n
     var_name_(i:i) = var_name(i)
  enddo

  status = model_array(model_index)%get_var_type(var_name_, var_type_)

  ! Convert Fortran string back to C char array with null terminator
  do i = 1, len(trim(var_type_))
      var_type(i) = var_type_(i:i)
  enddo
  var_type = var_type//C_NULL_CHAR
end function bmi_get_var_type
```

### Array Passing (flattened 1D arrays)

BMI already flattens arrays to 1D. The C binding passes array size explicitly.

```fortran
! Babelizer pattern: array with explicit size
function bmi_get_value_double(model_index, var_name, n, buffer, m) &
     bind(c) result(status)
  integer (c_int), intent(in), value :: model_index
  integer (c_int), intent(in), value :: n           ! var_name length
  character (len=1, kind=c_char), intent(in) :: var_name(n)
  integer (c_int), intent(in), value :: m           ! buffer size
  real (c_double), intent(out) :: buffer(m)         ! NOT assumed-shape (:)!

  character (len=n, kind=c_char) :: var_name_
  integer :: i
  do i = 1, n
     var_name_(i:i) = var_name(i)
  enddo
  status = model_array(model_index)%get_value(var_name_, buffer)
end function bmi_get_value_double
```

### Key ISO_C_BINDING Constraints for BMI

| Constraint | Impact | Solution |
|-----------|--------|----------|
| No assumed-shape arrays with `bind(C)` | Cannot use `array(:)` in C-bound functions | Use explicit-size `array(n)` with size passed as argument |
| No type-bound procedures with `bind(C)` | Cannot directly expose Fortran OOP methods | Use free functions that call methods on module-level instances |
| No Fortran `pointer` attribute with `bind(C)` | `get_component_name` returns pointer to string | Dereference pointer, copy to C-compatible buffer |
| `value` attribute required for scalar inputs | C passes by value; Fortran by reference | Add `value` to all scalar `intent(in)` arguments |
| Strings must be null-terminated for C | Fortran strings are blank-padded | Use `C_NULL_CHAR` terminator in output strings |

**Confidence: HIGH** -- These constraints are verified from the ISO Fortran 2003 standard and confirmed by both the babelizer template and SCHISM BMI implementation.

---

## CMake Shared Library Configuration

### Current State

The existing `CMakeLists.txt` (650 lines, 11 sections) already builds `libwrfhydro_bmi.so` as a shared library. It correctly:
- Uses `add_library(wrfhydro_bmi SHARED src/bmi_wrf_hydro.f90)`
- Links 22 WRF-Hydro static libs with `--start-group/--end-group` for circular deps
- Sets `-fPIC` for position-independent code
- Installs to `$CONDA_PREFIX/lib/` and `$CONDA_PREFIX/include/`
- Generates `pkg-config` metadata (not yet, but the babelizer expects it)

### Changes Needed for C Binding Layer

```cmake
# Add the C interop source file alongside the existing BMI wrapper
add_library(wrfhydro_bmi SHARED
  src/bmi_wrf_hydro.f90
  src/bmi_interoperability.f90    # NEW: C binding layer
)
```

### What Babelizer Expects from CMake Install

The babelizer's `babel.toml` `[build]` section specifies `library = "bmiwrfhydrof"`. After `cmake --install`, babelizer expects:

```
$CONDA_PREFIX/lib/libbmiwrfhydrof.so    # or libwrfhydro_bmi.so -- name must match
$CONDA_PREFIX/include/bmiwrfhydrof.mod  # Fortran module file
$CONDA_PREFIX/lib/pkgconfig/bmiwrfhydrof.pc  # pkg-config metadata
```

The `entry_point` field (`bmi_wrf_hydro`) tells the babelizer what Fortran type name to instantiate in its auto-generated `bmi_interoperability.f90`. It uses this in:
```fortran
use {{ component.library }}     ! e.g., use bmiwrfhydrof
type ({{ component.entry_point }}) :: model_array(N_MODELS)  ! e.g., type(bmi_wrf_hydro)
```

### Critical: pkg-config File

The babelizer discovers the installed library via pkg-config. The existing CMakeLists.txt does NOT generate a `.pc` file. This must be added:

```cmake
# Generate pkg-config file (required for babelizer)
configure_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/wrfhydro_bmi.pc.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/wrfhydro_bmi.pc
  @ONLY
)
install(
  FILES ${CMAKE_CURRENT_BINARY_DIR}/wrfhydro_bmi.pc
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig
)
```

With `wrfhydro_bmi.pc.cmake`:
```
prefix=@CMAKE_INSTALL_PREFIX@
libdir=${prefix}/@CMAKE_INSTALL_LIBDIR@
includedir=${prefix}/@CMAKE_INSTALL_INCLUDEDIR@

Name: wrfhydro_bmi
Description: WRF-Hydro BMI wrapper shared library
Version: @PROJECT_VERSION@
Libs: -L${libdir} -lwrfhydro_bmi
Cflags: -I${includedir}
```

**Confidence: HIGH** -- Verified from bmi-example-fortran's `bmi_heat/bmiheatf.pc.cmake` template and babelizer's `find_package(PkgConfig)` usage.

### Handling 22 WRF-Hydro Static Library Dependencies in .so

When building a shared library that depends on static libraries, ALL symbols from the static libraries get absorbed into the .so. This is the current approach and it works because:

1. `--start-group/--end-group` resolves circular dependencies between the 22 WRF-Hydro libs
2. `-fPIC` is set (required for code going into .so)
3. The resulting `libwrfhydro_bmi.so` is self-contained (minus system libs like MPI, NetCDF)

**Warning:** The WRF-Hydro static libraries MUST have been compiled with `-fPIC`. If they were compiled without it, the shared library build will fail with "relocation" errors. The existing WRF-Hydro CMake build uses `CMAKE_POSITION_INDEPENDENT_CODE=ON` by default, so this should work. If it does not, WRF-Hydro must be recompiled with:
```bash
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON
```

**Confidence: MEDIUM** -- WRF-Hydro's CMake likely sets `-fPIC` but this was not explicitly verified in the WRF-Hydro CMakeLists.txt.

---

## Python Interop: ctypes for BMI Testing

### Why ctypes (not cffi)

| Criterion | ctypes | cffi |
|-----------|--------|------|
| Installation | stdlib (always available) | pip install required |
| C header needed | No (define types in Python) | Yes (parses C declarations) |
| Build step | None | Yes (out-of-line mode) |
| Error messages | Segfault on type mismatch | Better error messages |
| Babelizer compatibility | Babelizer uses Cython internally, not ctypes | Not used by babelizer |
| Simplicity for testing | Simpler for one-off testing | Overkill for validation |

**Use ctypes because** it has zero dependencies, needs no build step, and is sufficient for validating the .so before babelizer takes over in Phase 2. The babelizer itself uses Cython (not ctypes) for its Python bindings, so neither ctypes nor cffi need to be "compatible" with it.

### Python ctypes Pattern for BMI

```python
import ctypes
import numpy as np
import os

# Load the shared library
lib = ctypes.CDLL("./libwrfhydro_bmi.so")

# Define function signatures
# bmi_new() -> int
lib.bmi_new.restype = ctypes.c_int
lib.bmi_new.argtypes = []

# bmi_initialize(model_index, config_file, n) -> int
lib.bmi_initialize.restype = ctypes.c_int
lib.bmi_initialize.argtypes = [
    ctypes.c_int,                    # model_index (value)
    ctypes.c_char_p,                 # config_file (char array)
    ctypes.c_int,                    # n (string length, value)
]

# bmi_update(model_index) -> int
lib.bmi_update.restype = ctypes.c_int
lib.bmi_update.argtypes = [ctypes.c_int]

# bmi_get_value_double(model_index, var_name, n, buffer, m) -> int
lib.bmi_get_value_double.restype = ctypes.c_int
lib.bmi_get_value_double.argtypes = [
    ctypes.c_int,                    # model_index
    ctypes.c_char_p,                 # var_name
    ctypes.c_int,                    # n (name length)
    np.ctypeslib.ndpointer(dtype=np.float64, flags='C_CONTIGUOUS'),  # buffer
    ctypes.c_int,                    # m (buffer size)
]

# Usage
model_idx = lib.bmi_new()
config = b"bmi_config.nml"
status = lib.bmi_initialize(model_idx, config, len(config))

# Get streamflow
var_name = b"channel_water__volume_flow_rate"
nlinks = 200  # from get_grid_size
buffer = np.zeros(nlinks, dtype=np.float64)
status = lib.bmi_get_value_double(model_idx, var_name, len(var_name), buffer, nlinks)
```

**Confidence: HIGH** -- Pattern verified from `foreign-fortran.readthedocs.io` documentation and consistent with the babelizer's own C binding conventions.

---

## Babelizer Ecosystem Expectations

### What babel.toml Needs for WRF-Hydro

```toml
[library.WRFHydro]
language = "fortran"
library = "bmiwrfhydrof"           # Fortran module name (use bmiwrfhydrof)
header = ""                        # Fortran has no headers
entry_point = "bmi_wrf_hydro"      # Fortran TYPE name within the module

[build]
undef_macros = []
define_macros = ["WRF_HYDRO", "MPP_LAND", "USE_NWM_BMI"]
libraries = ["wrfhydro_bmi"]       # -lwrfhydro_bmi (our .so)
library_dirs = []                  # babelizer uses pkg-config
include_dirs = []                  # babelizer uses pkg-config
extra_compile_args = ["-fallow-argument-mismatch"]

[package]
name = "pymt_wrfhydro"
requirements = []

[info]
github_username = "your-org"
package_author = "WRF-Hydro BMI Project"
package_author_email = ""
package_license = "MIT License"
summary = "PyMT component for WRF-Hydro hydrological model"
```

### How the Babelizer Uses These Fields

1. `library = "bmiwrfhydrof"` -- The babelizer generates `use bmiwrfhydrof` in its `bmi_interoperability.f90`
2. `entry_point = "bmi_wrf_hydro"` -- It generates `type(bmi_wrf_hydro) :: model_array(2048)` in the interop layer
3. The babelizer generates its OWN `bmi_interoperability.f90` (we do NOT need to provide one for Phase 2)
4. The babelizer compiles this interop layer alongside a Cython `_bmi.pyx` that calls the `bind(C)` functions

### What Must Be Installed Before Babelizer Runs

```
$CONDA_PREFIX/lib/libwrfhydro_bmi.so         # Our shared library
$CONDA_PREFIX/include/bmiwrfhydrof.mod        # Fortran module file
$CONDA_PREFIX/include/wrfhydro_bmi_state_mod.mod  # State module
$CONDA_PREFIX/lib/pkgconfig/wrfhydro_bmi.pc   # pkg-config metadata
```

The babelizer runs `pkg-config --cflags --libs wrfhydro_bmi` (or whatever the .pc file is named) to find include paths and library flags.

**Confidence: HIGH** -- Verified by cloning the babelizer repository and reading the template source code directly.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| C binding approach | Babelizer-compatible model array (Pattern B) | NOAA-OWP opaque handle (Pattern A) | Pattern A is for NextGen; babelizer generates its own Pattern B interop layer |
| Python FFI | ctypes (stdlib) | cffi (ABI mode) | ctypes is zero-dependency, sufficient for pre-babelizer validation |
| Build system | CMake (existing 650 lines) | Meson, fpm, Makefile | CMake already written; babelizer requires CMake; fpm cannot build shared libs |
| BMI spec | bmif_2_0 (conda) | bmif_2_0_iso (NOAA-OWP) | Already using bmif_2_0 in wrapper; Pattern A needs bmif_2_0_iso (different abstract type) |
| Shared lib format | .so (Linux shared) | .a (static) | Python ctypes and babelizer REQUIRE .so; cannot dlopen a static library |
| Library naming | bmiwrfhydrof (matches module name) | wrfhydro_bmi | Babelizer's `library` field maps to `use <library>` in Fortran; must match module name |

---

## What NOT To Do (Anti-Patterns)

### 1. Do NOT Write a Full NOAA-OWP-Style iso_c_bmi.f90

The SCHISM_BMI's `iso_c_bmi.f90` (948 lines) is for the NOAA NextGen framework, not for PyMT/babelizer. The babelizer generates its own C binding layer. Writing one manually for the babelizer path is wasted effort -- the babelizer will overwrite it.

**Exception:** A simplified version IS needed for the Python ctypes test (pre-babelizer validation). Keep it minimal (~200 lines covering the ~10 functions you actually test).

### 2. Do NOT Use Assumed-Shape Arrays in bind(C) Functions

```fortran
! WRONG: will not compile with bind(C)
function bmi_get_value(idx, name, buffer) bind(c) result(s)
  real(c_double), intent(out) :: buffer(:)  ! ERROR: assumed-shape

! CORRECT: explicit size
function bmi_get_value(idx, name, n, buffer, m) bind(c) result(s)
  real(c_double), intent(out) :: buffer(m)  ! explicit-size OK
```

### 3. Do NOT Use Generic/Overloaded Procedures with bind(C)

Fortran's `generic :: get_value => get_value_int, get_value_float, get_value_double` cannot have `bind(C)`. Write separate C-named functions: `bmi_get_value_int`, `bmi_get_value_float`, `bmi_get_value_double`.

### 4. Do NOT Forget `-fPIC` for WRF-Hydro Libraries

If WRF-Hydro's 22 static libraries were not compiled with `-fPIC`, the shared library link will fail with `relocation R_X86_64_32S against ... can not be used when making a shared object`. Recompile WRF-Hydro with `CMAKE_POSITION_INDEPENDENT_CODE=ON` if this occurs.

### 5. Do NOT Name the Library Differently from the Module

The babelizer's `library` field in `babel.toml` becomes `use <library>` in generated Fortran. If your module is `bmiwrfhydrof` but you set `library = "wrfhydro_bmi"`, the generated code will do `use wrfhydro_bmi` which will not find the module.

### 6. Do NOT Skip the pkg-config File

Without a `.pc` file in `$CONDA_PREFIX/lib/pkgconfig/`, the babelizer cannot find your library at Phase 2. This is the single most commonly missed step.

---

## No New Installations Required

All dependencies exist in the `wrfhydro-bmi` conda environment. The C binding layer uses only `iso_c_binding` (intrinsic to Fortran 2003). The Python test uses only `ctypes` (stdlib) and `numpy` (already installed).

```bash
# Verify existing setup (nothing new to install):
source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi
gfortran --version        # 14.3.0
cmake --version           # 3.31.1
python -c "import ctypes; print('ctypes OK')"
python -c "import numpy; print('numpy', numpy.__version__)"
pkg-config --modversion bmif  # 2.0.3
```

---

## Sources

- **Babelizer template source** (cloned and verified 2026-02-23): `babelizer/data/templates/{{package.name}}/lib/bmi_interoperability.f90` -- Pattern B model array with `bind(C)` functions
- **SCHISM BMI iso_c_bmi.f90** (local): `SCHISM_BMI/src/BMI/iso_c_fortran_bmi/src/iso_c_bmi.f90` -- Pattern A opaque handle (NOAA-OWP/NextGen)
- **SCHISM BMI README** (local): `SCHISM_BMI/src/BMI/iso_c_fortran_bmi/README.md` -- Documents `register_bmi` pattern
- **Babelizer Fortran example**: [babel_heatf.toml](https://babelizer.readthedocs.io/en/latest/example-fortran.html) -- babel.toml format for Fortran (HIGH confidence)
- **Babelizer documentation**: [babelizer.readthedocs.io](https://babelizer.readthedocs.io/en/latest/readme.html) -- Shared library requirements, CMake preferred over fpm
- **CSDMS bmi-fortran**: [github.com/csdms/bmi-fortran](https://github.com/csdms/bmi-fortran) -- BMI 2.0 Fortran spec
- **bmi-example-fortran CMakeLists.txt** (local): Build pattern for shared library with pkg-config
- **Foreign Fortran docs**: [foreign-fortran.readthedocs.io](https://foreign-fortran.readthedocs.io/en/latest/python/ctypes.html) -- Python ctypes + ISO_C_BINDING patterns
- **Intel ISO_C_BINDING reference**: [intel.com Fortran docs](https://www.intel.com/content/www/us/en/docs/fortran-compiler/developer-guide-reference/2025-0/iso-c-binding.html) -- Complete ISO_C_BINDING spec
