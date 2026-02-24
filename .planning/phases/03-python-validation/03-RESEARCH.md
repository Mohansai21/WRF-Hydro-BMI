# Phase 3: Python Validation - Research

**Researched:** 2026-02-24
**Domain:** Fortran ISO_C_BINDING wrappers + Python ctypes interop for MPI-linked shared libraries
**Confidence:** HIGH

## Summary

Phase 3 bridges the gap between the installed `libbmiwrfhydrof.so` (Phase 2 output) and Python-level verification. The shared library currently exports only Fortran module-mangled symbols (e.g., `__bmiwrfhydrof_MOD_wrfhydro_initialize`) which are not callable from C or Python. A minimal `bmi_wrf_hydro_c.f90` (~100-200 lines) using ISO_C_BINDING `bind(C)` will expose 8-10 key BMI functions as flat C symbols (e.g., `bmi_initialize`), which Python ctypes can call directly.

The critical technical challenges are: (1) the singleton pattern -- WRF-Hydro cannot support multiple instances, so the C binding uses a module-level `bmi_wrf_hydro` object rather than the box/opaque-handle pattern used by NextGen/SCHISM, (2) MPI initialization -- Open MPI requires `RTLD_GLOBAL` preloading of `libmpi.so` before loading any MPI-linked library via ctypes, and (3) string marshalling -- Fortran strings must be converted to/from null-terminated C strings. All three patterns are well-established with HIGH confidence from existing SCHISM BMI code and verified test infrastructure.

The Python side is straightforward: ctypes is a stdlib module, numpy (2.2.6) and pytest (9.0.2) are already installed in the conda environment. mpi4py is NOT installed and is not needed -- `ctypes.CDLL("libmpi.so", RTLD_GLOBAL)` is sufficient for the singleton serial case.

**Primary recommendation:** Write `bmi_wrf_hydro_c.f90` as a separate Fortran source file (not inside `bmi_wrf_hydro.f90`) following the SCHISM `iso_c_bmi.f90` pattern but simplified to a singleton. Compile it into `libbmiwrfhydrof.so`. Write a pytest-based Python test that exercises the full IRF cycle against Croton NY data.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Two test modes: quick smoke test (1-2 timesteps) + full 6-hour validation (matching Fortran suite)
- Both modes in the same test infrastructure -- not separate scripts

### Claude's Discretion
- Test structure: single script vs pytest suite -- pick what makes sense for ctypes + MPI
- Test output format: print-style vs pytest assertions -- match the chosen structure
- File location: where Python test file(s) live within the project
- Validation tolerance: pick appropriate strictness based on double/float conversion behavior
- Which variables to validate: balance coverage vs complexity (streamflow is mandatory, others at Claude's judgment)
- Reference data format: hardcoded vs separate file -- based on volume of comparison data
- Grid metadata checks: include if useful for proving the .so works, skip if redundant with Fortran tests
- MPI setup approach: self-contained vs wrapper script -- pick cleanest for ctypes + RTLD_GLOBAL
- mpi4py dependency: use if helpful, skip if pure ctypes is sufficient
- Conda env requirement: practical choice based on where the .so and deps live
- Launch method: `python test.py` vs `mpirun -np 1 python test.py` -- based on how WRF-Hydro expects MPI

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CBIND-01 | Minimal `bmi_wrf_hydro_c.f90` with `bind(C)` wrappers for 8-10 key BMI functions | SCHISM `iso_c_bmi.f90` provides complete pattern; singleton simplifies from box pattern; c_to_f_string/f_to_c_string helpers needed for string args |
| CBIND-03 | String conversion helpers (`c_to_f_string`, `f_to_c_string`) for null-terminated C strings to/from Fortran character arrays | SCHISM iso_c_bmi.f90 has exact implementation (lines 22-55); copy and adapt directly |
| CBIND-04 | Singleton guard in `register_bmi` prevents second allocation | Module-level `type(bmi_wrf_hydro), save :: the_model` with `logical, save :: registered = .false.` guard; matches WRF-Hydro's `wrfhydro_engine_initialized` constraint |
| PYTEST-01 | Python ctypes test loads `libwrfhydrobmi.so` and exercises full IRF cycle | Verified: `ctypes.CDLL(path)` loads the .so successfully; bind(C) symbols will be callable via `lib.bmi_initialize(...)` |
| PYTEST-02 | Python test validates Croton NY channel streamflow values match Fortran reference | Fortran test uses range checks (>= 0, evolves between step 1 and step 6); Python test should use same tolerance (1e-15 for evolution, range checks for physical validity) |
| PYTEST-03 | MPI `RTLD_GLOBAL` requirement handled via `ctypes.CDLL("libmpi.so", RTLD_GLOBAL)` | Verified working: `ctypes.CDLL(conda_lib/libmpi.so, RTLD_GLOBAL)` succeeds in wrfhydro-bmi env; Open MPI 5.0.8 |
| PYTEST-04 | Python test queries grid sizes dynamically from BMI functions | C binding wraps `get_grid_size` and `get_var_nbytes`; Python allocates arrays based on returned sizes using `numpy.zeros(n, dtype=numpy.float64)` |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ISO_C_BINDING (Fortran intrinsic) | F2003+ | C interoperability types and attributes | Standard Fortran 2003 feature; supported by gfortran 14.3.0; provides `bind(C)`, `c_int`, `c_double`, `c_char`, `c_null_char` |
| ctypes (Python stdlib) | 3.10+ | Load shared libraries and call C functions | Part of Python stdlib; zero dependencies; used for all CSDMS/BMI Python interop |
| numpy | 2.2.6 | Array allocation and ctypes bridge | Already installed; `numpy.ctypeslib` provides `ndpointer` for typed array passing |
| pytest | 9.0.2 | Test framework with fixtures and parametrize | Already installed; better than plain script for two test modes (smoke + full) via markers |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| os (Python stdlib) | 3.10+ | Path manipulation, chdir, environ | Config file creation, finding .so path |
| tempfile (Python stdlib) | 3.10+ | Create temporary config files | Safe config file creation that cleans up |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| ctypes | cffi | cffi is more Pythonic but adds a dependency; ctypes is zero-dependency and sufficient for our minimal 8-10 functions |
| pytest | plain script | User wants two modes in same infrastructure; pytest markers (`@pytest.mark.smoke`, `@pytest.mark.full`) handle this cleanly |
| mpi4py | ctypes RTLD_GLOBAL preload | mpi4py is NOT installed and not needed; ctypes preload is simpler for singleton serial-only usage |
| numpy arrays | ctypes arrays | numpy is already installed and provides cleaner array creation + comparison via `numpy.allclose` |

**Installation:**
No new packages needed. Everything is already in the `wrfhydro-bmi` conda environment:
```bash
source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi
# ctypes, os, tempfile: Python stdlib
# numpy 2.2.6: already installed
# pytest 9.0.2: already installed
```

## Architecture Patterns

### Recommended Project Structure
```
bmi_wrf_hydro/
  src/
    bmi_wrf_hydro.f90           # Existing Fortran BMI wrapper (1,919 lines)
    bmi_wrf_hydro_c.f90         # NEW: Minimal C binding (~100-200 lines)
    hydro_stop_shim.f90         # Existing linker shim
  tests/
    bmi_wrf_hydro_test.f90      # Existing Fortran test (1,777 lines)
    bmi_minimal_test.f90        # Existing Fortran smoke test (105 lines)
    test_bmi_python.py          # NEW: Python ctypes test (pytest-based)
  build/                        # Compiled artifacts
  build.sh                      # Updated: compile bmi_wrf_hydro_c.f90 into .so
  CMakeLists.txt                # Updated: add bmi_wrf_hydro_c.f90 source
```

### Pattern 1: Singleton C Binding (vs Box/Opaque-Handle)

**What:** A module-level `bmi_wrf_hydro` instance with `bind(C)` free functions that delegate to it. No box pointer, no c_ptr handle, no heap allocation.

**When to use:** When the model cannot support multiple instances (WRF-Hydro module globals are singletons). The box/opaque-handle pattern (used by SCHISM for NextGen) is unnecessary overhead for a model that can only exist once.

**Why NOT the box pattern:** REQUIREMENTS explicitly state "CBIND-04: Singleton guard in register_bmi prevents second allocation (WRF-Hydro module globals cannot support multiple instances)." The box pattern allocates on heap and returns a c_ptr -- unnecessary when there is exactly one instance.

**Example:**
```fortran
! Source: Adapted from SCHISM iso_c_bmi.f90 (simplified to singleton)
module bmi_wrf_hydro_c
  use bmiwrfhydrof, only: bmi_wrf_hydro
  use bmif_2_0, only: BMI_SUCCESS, BMI_FAILURE, BMI_MAX_FILE_NAME
  use, intrinsic :: iso_c_binding
  implicit none

  ! Singleton model instance (module-level, SAVE by default in F2003)
  type(bmi_wrf_hydro), save, target :: the_model
  logical, save :: registered = .false.

contains

  function bmi_register() result(status) bind(C, name="bmi_register")
    integer(c_int) :: status
    if (registered) then
      status = BMI_FAILURE  ! Singleton guard: only one instance allowed
      return
    end if
    registered = .true.
    status = BMI_SUCCESS
  end function bmi_register

  function bmi_initialize(config_file) result(status) bind(C, name="bmi_initialize")
    character(kind=c_char), intent(in) :: config_file(*)
    integer(c_int) :: status
    character(len=:), allocatable :: f_file
    f_file = c_to_f_string(config_file)
    status = the_model%initialize(f_file)
    deallocate(f_file)
  end function bmi_initialize

  function bmi_update() result(status) bind(C, name="bmi_update")
    integer(c_int) :: status
    status = the_model%update()
  end function bmi_update

  ! ... remaining functions follow same pattern
end module bmi_wrf_hydro_c
```

### Pattern 2: Python ctypes Loading with MPI Preload

**What:** Load `libmpi.so` with `RTLD_GLOBAL` before loading `libbmiwrfhydrof.so` to ensure Open MPI's plugin system can find all symbols.

**When to use:** Always, for any MPI-linked Fortran shared library loaded via ctypes.

**Verified:** Successfully tested in this environment (Open MPI 5.0.8, conda wrfhydro-bmi).

**Example:**
```python
# Source: Verified in this project's conda environment
import ctypes
import os

def load_bmi_library():
    """Load libbmiwrfhydrof.so with MPI preloading."""
    conda_prefix = os.environ["CONDA_PREFIX"]
    lib_dir = os.path.join(conda_prefix, "lib")

    # Step 1: Preload libmpi with RTLD_GLOBAL (required by Open MPI)
    ctypes.CDLL(os.path.join(lib_dir, "libmpi.so"), ctypes.RTLD_GLOBAL)

    # Step 2: Load BMI library (now MPI symbols are globally visible)
    lib = ctypes.CDLL(os.path.join(lib_dir, "libbmiwrfhydrof.so"))
    return lib
```

### Pattern 3: String Passing (Python -> Fortran bind(C))

**What:** Fortran `bind(C)` functions receive C strings as `character(kind=c_char), intent(in) :: str(*)` -- an assumed-size array of c_char. Python ctypes sends bytes via `ctypes.c_char_p(b"string")`.

**When to use:** For `initialize(config_file)`, `get_component_name()`, variable name strings.

**Example:**
```python
# Python side: encode string to bytes for ctypes
config_bytes = b"/path/to/bmi_config.nml\x00"  # Must be null-terminated
status = lib.bmi_initialize(config_bytes)

# For output strings: pre-allocate a buffer
name_buf = ctypes.create_string_buffer(256)
status = lib.bmi_get_component_name(name_buf)
name = name_buf.value.decode("ascii")  # Read until null terminator
```

```fortran
! Fortran side: c_to_f_string strips null terminator
! Source: SCHISM iso_c_bmi.f90 lines 22-40
pure function c_to_f_string(c_string) result(f_string)
  character(kind=c_char, len=1), intent(in) :: c_string(:)
  character(len=:), allocatable :: f_string
  integer :: i, n
  i = 1
  do
    if (c_string(i) == c_null_char) exit
    i = i + 1
  end do
  n = i - 1
  allocate(character(len=n) :: f_string)
  f_string = transfer(c_string(1:n), f_string)
end function c_to_f_string
```

### Pattern 4: Array Retrieval (get_value_double)

**What:** The C binding wraps `get_value_double` to fill a caller-allocated array. Python allocates a numpy array and passes its data pointer.

**Example:**
```python
import numpy as np

# Query grid size dynamically (PYTEST-04)
grid_id = ctypes.c_int()
nbytes = ctypes.c_int()
grid_size = ctypes.c_int()

lib.bmi_get_var_grid(b"channel_water__volume_flow_rate\x00", ctypes.byref(grid_id))
lib.bmi_get_grid_size(grid_id, ctypes.byref(grid_size))

# Allocate array based on queried size
values = np.zeros(grid_size.value, dtype=np.float64)
values_ptr = values.ctypes.data_as(ctypes.POINTER(ctypes.c_double))
lib.bmi_get_value_double(b"channel_water__volume_flow_rate\x00", values_ptr)
```

```fortran
! Fortran side: receives a C double array and fills it
function bmi_get_value_double(name, dest) result(status) bind(C, name="bmi_get_value_double")
  character(kind=c_char), intent(in) :: name(*)
  real(kind=c_double), intent(out) :: dest(*)
  integer(c_int) :: status
  character(len=:), allocatable :: f_name
  integer :: nbytes_val, itemsize_val, n_items

  f_name = c_to_f_string(name)
  ! Query size from BMI metadata
  status = the_model%get_var_nbytes(f_name, nbytes_val)
  if (status /= BMI_SUCCESS) return
  status = the_model%get_var_itemsize(f_name, itemsize_val)
  if (status /= BMI_SUCCESS) return
  n_items = nbytes_val / itemsize_val

  status = the_model%get_value_double(f_name, dest(1:n_items))
  deallocate(f_name)
end function bmi_get_value_double
```

### Pattern 5: pytest with Two Test Modes

**What:** Use pytest markers to define `smoke` and `full` test categories. Both share the same fixture for library loading and MPI setup.

**Example:**
```python
import pytest

@pytest.fixture(scope="session")
def bmi_lib():
    """Load BMI library once per test session."""
    lib = load_bmi_library()
    yield lib

@pytest.fixture(scope="session")
def bmi_initialized(bmi_lib, tmp_path_factory):
    """Initialize BMI once, finalize at end of session."""
    lib = bmi_lib
    # register
    status = lib.bmi_register()
    assert status == 0
    # create config, initialize, ...
    yield lib
    # finalize
    lib.bmi_finalize()

@pytest.mark.smoke
def test_initialize_finalize(bmi_initialized):
    """Quick: just verify init/finalize cycle works."""
    pass  # bmi_initialized fixture already did init

@pytest.mark.full
def test_streamflow_after_6_hours(bmi_initialized):
    """Full: run 6 hours and validate streamflow."""
    lib = bmi_initialized
    for _ in range(6):
        assert lib.bmi_update() == 0
    # ... validate streamflow values ...
```

**Run commands:**
```bash
# Quick smoke test (1-2 timesteps)
pytest test_bmi_python.py -m smoke -v
# Full 6-hour validation
pytest test_bmi_python.py -m full -v
# All tests
pytest test_bmi_python.py -v
```

### Anti-Patterns to Avoid
- **Using the box/opaque-handle pattern for WRF-Hydro:** WRF-Hydro is a singleton model. The box pattern (used by SCHISM for NextGen) adds complexity for zero benefit. It requires heap allocation, c_ptr passing, and memory management -- all unnecessary when there is exactly one model instance.
- **Calling MPI_Init from Python:** WRF-Hydro's `HYDRO_ini()` calls `MPI_Init` internally via `MPP_LAND_INIT`. The Python test must NOT call `MPI_Init` separately. The `RTLD_GLOBAL` preload ensures MPI symbols are available without Python touching MPI.
- **Hardcoding Croton NY grid dimensions:** The test must query `get_grid_size` and `get_var_nbytes` dynamically. Croton NY has 240 LSM cells (15x16), 3840 routing cells (60x64), and ~200 channel links -- but these must be discovered, not hardcoded.
- **Running pytest from the wrong directory:** The BMI config file points to `../WRF_Hydro_Run_Local/run/`. If the test runs from the wrong directory, the path will be wrong. Use absolute paths in the config file to avoid this.
- **Forgetting null terminator on C strings:** All strings passed from Python to Fortran `bind(C)` functions must be null-terminated. Use `b"string\x00"` or `ctypes.c_char_p(b"string")` (c_char_p auto-adds null).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| String conversion (C<->Fortran) | Custom string marshalling | Copy `c_to_f_string`/`f_to_c_string` from SCHISM `iso_c_bmi.f90` | Battle-tested in production NOAA code; handles null terminators correctly; exact pattern needed |
| Array passing to Fortran | Manual ctypes pointer arithmetic | `numpy.ctypeslib` + `ndpointer` or `array.ctypes.data_as(POINTER(c_double))` | numpy handles memory layout, alignment, and type safety |
| Full 41-function C binding | Write wrappers for all BMI functions | Only wrap 8-10 needed for test; babelizer generates the full layer | Babelizer auto-generates 818-line `bmi_interoperability.f90`; our layer is test infrastructure only |
| MPI initialization from Python | mpi4py or manual MPI_Init | `ctypes.CDLL("libmpi.so", RTLD_GLOBAL)` preload | WRF-Hydro calls MPI_Init internally; we just need symbols globally visible |

**Key insight:** This C binding layer is explicitly test infrastructure, not production code. The babelizer will generate the full interop layer for the PyMT pathway. Keep it minimal -- only what the Python test needs to exercise the IRF cycle and validate data.

## Common Pitfalls

### Pitfall 1: MPI Segfault on Library Load
**What goes wrong:** Python loads `libbmiwrfhydrof.so` without `RTLD_GLOBAL`, then the first call to any function that touches MPI (like `initialize`) causes a segfault in Open MPI's plugin loading.
**Why it happens:** Open MPI uses `dlopen` internally to load its components (BTL, PML, etc.) from `$prefix/lib/openmpi/`. These plugins reference symbols from `libmpi.so`. If `libmpi.so` was loaded with `RTLD_LOCAL` (the default), those symbols are not visible to the plugins.
**How to avoid:** Always preload libmpi with RTLD_GLOBAL BEFORE loading the BMI library:
```python
ctypes.CDLL(os.path.join(conda_lib, "libmpi.so"), ctypes.RTLD_GLOBAL)
```
**Warning signs:** Segfault or "undefined symbol: mca_patcher_base_patch_t_class" errors.

### Pitfall 2: Double MPI_Init
**What goes wrong:** Python code (or mpi4py import) calls `MPI_Init`, then `bmi_initialize` calls it again via WRF-Hydro's `MPP_LAND_INIT`, causing "MPI already initialized" error.
**Why it happens:** WRF-Hydro assumes it owns MPI lifecycle. Its `HYDRO_ini()` calls `MPP_LAND_INIT()` which calls `MPI_Init()`.
**How to avoid:** Do NOT import mpi4py or call MPI_Init from Python. Do NOT use `mpirun` to launch the test. Let WRF-Hydro handle MPI_Init internally. Also need to handle MPI_Finalize: either call it from Python ctypes after `bmi_finalize()`, or let the process exit naturally (MPI_Finalize is only strictly required for clean shutdown).
**Warning signs:** "MPI_Init called after MPI_Finalize" or "MPI already initialized".

### Pitfall 3: Working Directory for Config File
**What goes wrong:** The BMI config file contains a relative path (`../WRF_Hydro_Run_Local/run/`), but the Python test runs from a different directory, making the path resolve incorrectly.
**Why it happens:** The Fortran test creates the config file in `bmi_wrf_hydro/` and runs from there. Python/pytest may run from the project root or any other directory.
**How to avoid:** Use absolute paths in the BMI config file:
```python
run_dir = os.path.abspath(os.path.join(project_root, "WRF_Hydro_Run_Local", "run"))
config_content = f'&bmi_wrf_hydro_config\n  wrfhydro_run_dir = "{run_dir}/"\n/\n'
```
**Warning signs:** "File not found" errors for namelist.hrldas or hydro.namelist.

### Pitfall 4: Fortran String Length Truncation
**What goes wrong:** Config file path exceeds Fortran's `character(len=256)` limit, causing silent truncation and file-not-found errors.
**Why it happens:** WSL2 paths can be very long (e.g., `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/WRF_Hydro_Run_Local/run/` = 87 chars). The BMI wrapper uses `character(len=256)` for paths, which is sufficient, but the C binding's `c_to_f_string` must allocate enough space.
**How to avoid:** The `c_to_f_string` function uses allocatable strings (no fixed length limit). Verify config file path length stays under 256 chars (the `bmi_wrf_hydro.f90` limit).
**Warning signs:** Paths silently truncated; model fails to find namelists.

### Pitfall 5: MPI_Finalize Cleanup
**What goes wrong:** Process exits without calling `MPI_Finalize`, causing warning messages or zombie processes.
**Why it happens:** The Fortran test calls `MPI_Finalize` explicitly. The Python test using ctypes must do the same, but the function is in `libmpi.so`, not our library.
**How to avoid:** Call `MPI_Finalize` from Python via ctypes on the preloaded libmpi:
```python
libmpi = ctypes.CDLL("libmpi.so", ctypes.RTLD_GLOBAL)
# ... run BMI lifecycle ...
ierr = ctypes.c_int()
libmpi.MPI_Finalize(ctypes.byref(ierr))
```
Or: Add a `bmi_mpi_finalize` convenience function to the C binding layer.
**Warning signs:** "MPI was not finalized" warnings on process exit.

### Pitfall 6: c_char_p vs c_char Array for bind(C) Functions
**What goes wrong:** Using `ctypes.c_char_p` for string arguments that Fortran expects as `character(kind=c_char) :: str(*)` may not null-terminate correctly, causing Fortran to read garbage past the string.
**Why it happens:** `ctypes.c_char_p` passes a pointer to a bytes object. Fortran's assumed-size `str(*)` array reads until it finds `c_null_char`. If the bytes object happens to have a null terminator at the right place, it works; otherwise, it reads garbage.
**How to avoid:** Always explicitly null-terminate: `b"string\x00"`. Or use `ctypes.create_string_buffer(b"string")` which always null-terminates. `ctypes.c_char_p` also null-terminates, but being explicit is safer.
**Warning signs:** Fortran reads incorrect string content; variable name lookups fail.

## Code Examples

### Complete C Binding Module (bmi_wrf_hydro_c.f90)
```fortran
! Source: Pattern from SCHISM iso_c_bmi.f90, simplified to singleton
module bmi_wrf_hydro_c_mod
  use bmiwrfhydrof, only: bmi_wrf_hydro
  use bmif_2_0, only: BMI_SUCCESS, BMI_FAILURE, BMI_MAX_COMPONENT_NAME
  use, intrinsic :: iso_c_binding
  implicit none
  private

  type(bmi_wrf_hydro), save, target :: the_model
  logical, save :: is_registered = .false.

contains

  ! --- String helpers (from SCHISM iso_c_bmi.f90) ---
  pure function c_to_f_string(c_string) result(f_string)
    character(kind=c_char, len=1), intent(in) :: c_string(*)
    character(len=:), allocatable :: f_string
    integer :: i, n
    i = 1
    do while (c_string(i) /= c_null_char)
      i = i + 1
    end do
    n = i - 1
    allocate(character(len=n) :: f_string)
    do i = 1, n
      f_string(i:i) = c_string(i)
    end do
  end function c_to_f_string

  pure function f_to_c_string(f_string) result(c_string)
    character(len=*), intent(in) :: f_string
    character(kind=c_char, len=1) :: c_string(len_trim(f_string) + 1)
    integer :: i, n
    n = len_trim(f_string)
    do i = 1, n
      c_string(i) = f_string(i:i)
    end do
    c_string(n + 1) = c_null_char
  end function f_to_c_string

  ! --- BMI functions (8-10 key functions) ---
  function bmi_register() result(status) bind(C, name="bmi_register")
    integer(c_int) :: status
    if (is_registered) then
      status = BMI_FAILURE
      return
    end if
    is_registered = .true.
    status = BMI_SUCCESS
  end function bmi_register

  function bmi_initialize(config_file) result(status) bind(C, name="bmi_initialize")
    character(kind=c_char), intent(in) :: config_file(*)
    integer(c_int) :: status
    character(len=:), allocatable :: f_file
    f_file = c_to_f_string(config_file)
    status = the_model%initialize(f_file)
    deallocate(f_file)
  end function bmi_initialize

  function bmi_update() result(status) bind(C, name="bmi_update")
    integer(c_int) :: status
    status = the_model%update()
  end function bmi_update

  function bmi_finalize() result(status) bind(C, name="bmi_finalize")
    integer(c_int) :: status
    status = the_model%finalize()
  end function bmi_finalize

  function bmi_get_component_name(name) result(status) bind(C, name="bmi_get_component_name")
    character(kind=c_char), intent(out) :: name(*)
    integer(c_int) :: status
    character(len=BMI_MAX_COMPONENT_NAME), pointer :: f_name
    status = the_model%get_component_name(f_name)
    if (status == BMI_SUCCESS) then
      name(1:len_trim(f_name)+1) = f_to_c_string(f_name)
    end if
  end function bmi_get_component_name

  function bmi_get_current_time(time) result(status) bind(C, name="bmi_get_current_time")
    real(c_double), intent(out) :: time
    integer(c_int) :: status
    status = the_model%get_current_time(time)
  end function bmi_get_current_time

  function bmi_get_var_grid(name, grid) result(status) bind(C, name="bmi_get_var_grid")
    character(kind=c_char), intent(in) :: name(*)
    integer(c_int), intent(out) :: grid
    integer(c_int) :: status
    character(len=:), allocatable :: f_name
    f_name = c_to_f_string(name)
    status = the_model%get_var_grid(f_name, grid)
    deallocate(f_name)
  end function bmi_get_var_grid

  function bmi_get_grid_size(grid, size) result(status) bind(C, name="bmi_get_grid_size")
    integer(c_int), value, intent(in) :: grid
    integer(c_int), intent(out) :: size
    integer(c_int) :: status
    status = the_model%get_grid_size(grid, size)
  end function bmi_get_grid_size

  function bmi_get_var_nbytes(name, nbytes) result(status) bind(C, name="bmi_get_var_nbytes")
    character(kind=c_char), intent(in) :: name(*)
    integer(c_int), intent(out) :: nbytes
    integer(c_int) :: status
    character(len=:), allocatable :: f_name
    f_name = c_to_f_string(name)
    status = the_model%get_var_nbytes(f_name, nbytes)
    deallocate(f_name)
  end function bmi_get_var_nbytes

  function bmi_get_value_double(name, dest) result(status) bind(C, name="bmi_get_value_double")
    character(kind=c_char), intent(in) :: name(*)
    real(c_double), intent(out) :: dest(*)
    integer(c_int) :: status
    character(len=:), allocatable :: f_name
    integer :: nbytes_val, itemsize_val, n_items
    f_name = c_to_f_string(name)
    status = the_model%get_var_nbytes(f_name, nbytes_val)
    if (status /= BMI_SUCCESS) then; deallocate(f_name); return; end if
    status = the_model%get_var_itemsize(f_name, itemsize_val)
    if (status /= BMI_SUCCESS) then; deallocate(f_name); return; end if
    if (itemsize_val == 0) then; status = BMI_FAILURE; deallocate(f_name); return; end if
    n_items = nbytes_val / itemsize_val
    status = the_model%get_value_double(f_name, dest(1:n_items))
    deallocate(f_name)
  end function bmi_get_value_double

end module bmi_wrf_hydro_c_mod
```

### Complete Python ctypes Test Pattern
```python
# Source: Verified patterns from this project's conda environment
import ctypes
import os
import numpy as np
import pytest

BMI_SUCCESS = 0
BMI_FAILURE = 1

@pytest.fixture(scope="session")
def bmi_lib():
    """Load BMI shared library with MPI preloading."""
    conda_prefix = os.environ["CONDA_PREFIX"]
    lib_dir = os.path.join(conda_prefix, "lib")

    # Preload MPI with RTLD_GLOBAL (required by Open MPI)
    ctypes.CDLL(os.path.join(lib_dir, "libmpi.so"), ctypes.RTLD_GLOBAL)

    # Load BMI library
    lib = ctypes.CDLL(os.path.join(lib_dir, "libbmiwrfhydrof.so"))

    # Set return types for all functions
    lib.bmi_register.restype = ctypes.c_int
    lib.bmi_initialize.restype = ctypes.c_int
    lib.bmi_update.restype = ctypes.c_int
    lib.bmi_finalize.restype = ctypes.c_int
    lib.bmi_get_component_name.restype = ctypes.c_int
    lib.bmi_get_current_time.restype = ctypes.c_int
    lib.bmi_get_var_grid.restype = ctypes.c_int
    lib.bmi_get_grid_size.restype = ctypes.c_int
    lib.bmi_get_var_nbytes.restype = ctypes.c_int
    lib.bmi_get_value_double.restype = ctypes.c_int

    return lib

@pytest.mark.smoke
def test_full_irf_cycle(bmi_lib, tmp_path):
    """Smoke test: register -> initialize -> 1 update -> finalize."""
    lib = bmi_lib

    # Register (singleton)
    assert lib.bmi_register() == BMI_SUCCESS

    # Create config file with absolute path
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    run_dir = os.path.join(project_root, "WRF_Hydro_Run_Local", "run")
    config_file = str(tmp_path / "bmi_config.nml")
    with open(config_file, "w") as f:
        f.write(f'&bmi_wrf_hydro_config\n')
        f.write(f'  wrfhydro_run_dir = "{run_dir}/"\n')
        f.write(f'/\n')

    # Initialize
    assert lib.bmi_initialize(config_file.encode() + b"\x00") == BMI_SUCCESS

    # Update 1 step
    assert lib.bmi_update() == BMI_SUCCESS

    # Check current time advanced
    time = ctypes.c_double()
    assert lib.bmi_get_current_time(ctypes.byref(time)) == BMI_SUCCESS
    assert time.value > 0.0

    # Finalize
    assert lib.bmi_finalize() == BMI_SUCCESS
```

### Verifying bind(C) Symbols in .so
```bash
# After rebuilding with bmi_wrf_hydro_c.f90:
nm -D libbmiwrfhydrof.so | grep "T bmi_"
# Expected output:
# ... T bmi_register
# ... T bmi_initialize
# ... T bmi_update
# ... T bmi_finalize
# ... T bmi_get_component_name
# ... T bmi_get_current_time
# ... T bmi_get_var_grid
# ... T bmi_get_grid_size
# ... T bmi_get_var_nbytes
# ... T bmi_get_value_double
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Full 41-function C binding layer | Minimal 8-10 function layer (babelizer generates the rest) | 2026-02 (this project research) | 90% less code to write; test infrastructure only |
| Box/opaque-handle pattern | Module-level singleton | 2026-02 (WRF-Hydro singleton constraint) | Simpler code; matches WRF-Hydro's inability to support multiple instances |
| mpi4py for MPI init | `ctypes.CDLL(libmpi, RTLD_GLOBAL)` preload | 2020+ (standard pattern) | Zero additional dependency; lets model handle MPI_Init |
| Manual ctypes array management | numpy.ctypeslib | numpy 1.x+ | Type-safe array passing; automatic memory management |

**Deprecated/outdated:**
- `ctypes.windll` / `ctypes.oledll`: Windows-only, irrelevant (WSL2 Linux)
- `ctypes.cdll.LoadLibrary()` without mode: Still works but risky for MPI-linked libs; always use `ctypes.CDLL()` with explicit mode for MPI

## Open Questions

1. **MPI_Finalize from Python**
   - What we know: WRF-Hydro calls MPI_Init via HYDRO_ini(). The Fortran test explicitly calls MPI_Finalize. The BMI finalize() does NOT call MPI_Finalize (by design -- documented in CLAUDE.md).
   - What's unclear: Whether not calling MPI_Finalize from Python will cause issues (warnings, zombie processes) or if process exit handles it cleanly.
   - Recommendation: Add a `bmi_mpi_finalize` convenience function to the C binding, or call `libmpi.MPI_Finalize(byref(ierr))` directly from Python after bmi_finalize(). Test both approaches.

2. **pytest Session Scope with Singleton**
   - What we know: WRF-Hydro cannot be re-initialized after finalize (wrfhydro_engine_initialized flag). The smoke test and full test both need initialize/finalize.
   - What's unclear: Whether pytest can cleanly separate smoke and full tests when the model can only be initialized once per process.
   - Recommendation: Design tests to share a single initialization. Run smoke assertions early, then continue to full validation. OR use pytest-forked to run in separate processes. OR accept that both test modes run sequentially in one session with a single init/finalize cycle.

3. **Validation Tolerance for Streamflow**
   - What we know: Fortran test uses `any(values >= 0.0d0)` for physical validity and `any(abs(step1 - step6) > 1.0d-15)` for evolution. WRF-Hydro stores REAL (32-bit) internally but BMI converts to double (64-bit).
   - What's unclear: Whether the REAL->double conversion introduces enough noise that bit-for-bit comparison is unreliable.
   - Recommendation: Use range-based validation (physical plausibility) plus evolution checking (values change over time), matching the Fortran test's approach. Do NOT attempt bit-for-bit comparison between Python and Fortran -- use tolerance of 1e-6 for REAL-origin values.

4. **Launch Method: python vs mpirun**
   - What we know: WRF-Hydro calls MPI_Init internally. If launched without mpirun, MPI_Init may self-initialize a "singleton" MPI communicator. If launched with mpirun, MPI is already initialized by the launcher.
   - What's unclear: Whether `python test.py` (without mpirun) will cause WRF-Hydro's MPI_Init to succeed or fail.
   - Recommendation: Test both approaches. Prefer `python test.py` (simpler) if WRF-Hydro's MPI_Init handles the singleton case. Fall back to `mpirun --oversubscribe -np 1 python test.py` if needed. Open MPI 5.0.8 typically supports singleton init.

## Sources

### Primary (HIGH confidence)
- SCHISM BMI `iso_c_bmi.f90` -- Complete C binding reference (818 lines, Nels Frazier/NOAA, used in production NextGen)
  - File: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/SCHISM_BMI/src/BMI/iso_c_fortran_bmi/src/iso_c_bmi.f90`
- SCHISM BMI `bmischism.f90` -- register_bmi singleton pattern with box (lines 1700-1728)
  - File: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/SCHISM_BMI/src/BMI/bmischism.f90`
- WRF-Hydro BMI wrapper `bmi_wrf_hydro.f90` -- Current Fortran BMI implementation (1,919 lines)
  - File: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro/src/bmi_wrf_hydro.f90`
- WRF-Hydro BMI test `bmi_wrf_hydro_test.f90` -- Reference output patterns (1,777 lines, 151 tests)
  - File: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90`
- Verified environment: ctypes loads `libbmiwrfhydrof.so` and `libmpi.so` with RTLD_GLOBAL successfully in wrfhydro-bmi conda env

### Secondary (MEDIUM confidence)
- [Foreign Fortran Documentation - ctypes](https://foreign-fortran.readthedocs.io/en/latest/python/ctypes.html) -- Fortran bind(C) + Python ctypes patterns
- [Open MPI RTLD_GLOBAL Issue #3705](https://github.com/open-mpi/ompi/issues/3705) -- MPI dlopen RTLD_LOCAL problem and workaround
- [Python ctypes documentation](https://docs.python.org/3/library/ctypes.html) -- Official ctypes API reference
- [GNU Fortran ISO_C_BINDING](https://gcc.gnu.org/onlinedocs/gfortran/ISO_005fC_005fBINDING.html) -- Compiler-specific ISO_C_BINDING documentation

### Tertiary (LOW confidence)
- None -- all findings verified with primary sources or environment testing

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools (ctypes, numpy, pytest) verified installed; ISO_C_BINDING is Fortran standard
- Architecture: HIGH -- singleton C binding pattern derived directly from SCHISM iso_c_bmi.f90 (production NOAA code); MPI preload verified in this environment
- Pitfalls: HIGH -- MPI RTLD_GLOBAL issue documented by Open MPI maintainers and verified; working directory issue observed in existing Fortran test; string handling patterns from production SCHISM code

**Research date:** 2026-02-24
**Valid until:** 2026-03-24 (stable domain -- Fortran interop and ctypes have not changed in years)
