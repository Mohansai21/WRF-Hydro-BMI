# Pitfalls Research: Fortran Shared Library + C Bindings + Python Interop

**Domain:** Fortran BMI shared library with ISO_C_BINDING, linking against MPI-dependent static libraries, Python interop via ctypes
**Researched:** 2026-02-23
**Confidence:** HIGH (verified against SCHISM_BMI reference implementation, bmi-example-fortran, iso_c_fortran_bmi library, and current project source code)

## Critical Pitfalls

Mistakes that cause build failures, segfaults, or rewrites.

### Pitfall 1: WRF-Hydro Static Libraries Compiled Without -fPIC

**What goes wrong:**
Building `libwrfhydro_bmi.so` fails at link time with errors like:
```
relocation R_X86_64_32 against `.rodata` can not be used when making a shared object; recompile with -fPIC
```
The 22 WRF-Hydro static libraries (`libhydro_driver.a`, `libnoahmp_phys.a`, etc.) were compiled by WRF-Hydro's CMake build without the `-fPIC` flag. On x86_64 Linux, static `.a` files built without `-fPIC` contain absolute address relocations that cannot be embedded in a position-independent shared library (`.so`).

**Why it happens:**
WRF-Hydro's own `CMakeLists.txt` has no `-fPIC` or `CMAKE_POSITION_INDEPENDENT_CODE` setting because its build target is a standalone executable (`wrf_hydro`), not a shared library. Executables do not require position-independent code. This is confirmed: grep found zero occurrences of `fPIC` or `POSITION_INDEPENDENT` in `wrf_hydro_nwm_public/`.

**How to avoid:**
Rebuild WRF-Hydro from source with `-fPIC` added globally. Two approaches:
1. **CMake flag** (cleanest): `cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON`
2. **Environment variable**: `FFLAGS="-fPIC" CFLAGS="-fPIC" cmake .. -DCMAKE_BUILD_TYPE=Release`

Both cause all object files to be compiled with `-fPIC`, making the resulting `.a` files safe to link into `.so`. This does NOT change WRF-Hydro source code -- it only changes compile flags.

**Warning signs:**
- Linker errors mentioning "relocation", "recompile with -fPIC", or "can not be used when making a shared object"
- These appear ONLY when building the shared library, not the test executables (executables work fine without -fPIC)
- The current `build.sh` links executables (not `.so`), so this issue is invisible until CMake `.so` build is attempted

**Phase to address:**
Shared Library Build (first milestone task). Must be done before ANY other work since everything depends on the `.so` linking successfully.

---

### Pitfall 2: Fortran String Passing Across the C Boundary

**What goes wrong:**
Python calls `initialize(handle, config_file)` via ctypes, but the Fortran side receives garbage characters, truncated strings, or segfaults. The BMI `initialize` function takes `character(len=*)` -- which is NOT C-interoperable. Fortran strings have no null terminator and carry a hidden length argument; C strings are null-terminated with no length.

**Why it happens:**
Fortran `character(len=*)` arguments are NOT interoperable with C. The ISO C standard requires `character(kind=c_char, len=1), dimension(*)` for C-interoperable strings. The existing `bmi_wrf_hydro.f90` uses standard Fortran string arguments (correct for Fortran-to-Fortran calls in the current test suite), but the ISO_C_BINDING wrapper layer must explicitly convert between C null-terminated strings and Fortran character arrays.

The SCHISM BMI iso_c_bmi.f90 has exactly this pattern: every function that accepts a string does:
```fortran
character(kind=c_char, len=1), dimension(BMI_MAX_FILE_NAME), intent(in) :: config_file
f_file = c_to_f_string(config_file)  ! Convert C string -> Fortran string
```

Every function that returns a string does:
```fortran
type(1:len_trim(f_type)+1) = f_to_c_string(f_type)  ! Append null terminator
```

**How to avoid:**
1. Write `c_to_f_string()` and `f_to_c_string()` helper functions (copy from SCHISM's `iso_c_bmi.f90`)
2. In ALL C-binding wrappers that take string arguments (initialize, get_var_type, get_var_units, get_var_grid, get_value, set_value, etc.), convert C strings to Fortran strings before calling the Fortran BMI procedures, and convert Fortran strings back to C strings before returning
3. The C-binding wrapper functions must use `character(kind=c_char, len=1), dimension(*)` -- NOT `character(len=*)`
4. Add a safety bound in `c_to_f_string` to prevent scanning past `BMI_MAX_FILE_NAME` characters:
```fortran
do i = 1, min(size(c_string), BMI_MAX_FILE_NAME)
  if (c_string(i) == c_null_char) exit
end do
```

**Warning signs:**
- Variable names not matching in get_value/set_value calls (string comparison fails silently)
- get_component_name returns trailing garbage characters
- Fortran `name == 'channel_water__volume_flow_rate'` comparisons fail even with correct input
- Python ctypes `c_char_p` appears to work in simple tests but fails with longer names

**Phase to address:**
ISO_C_BINDING wrapper implementation. This is the core of the C-binding layer and must be tested for EVERY function that takes or returns a string (roughly 25 of the 41 BMI functions).

---

### Pitfall 3: MPI dlopen RTLD_GLOBAL Requirement

**What goes wrong:**
Python loads `libwrfhydro_bmi.so` via `ctypes.CDLL("libwrfhydro_bmi.so")`, calls `initialize()`, and gets a segmentation fault inside MPI internals. The crash occurs during `MPI_Init` or the first MPI call. The same `.so` works perfectly when loaded from a Fortran test executable.

**Why it happens:**
Open MPI uses `dlopen()` internally to load its plugin components. These components depend on symbols from `libmpi.so`. When Python's `ctypes.CDLL()` loads the shared library, it defaults to `RTLD_LOCAL`, which means MPI's symbols are not visible to its own dynamically loaded plugins. This is a well-documented issue (Open MPI GitHub issue #3705, official Open MPI docs Section 11.4).

The current project uses Open MPI 5.0.8 via conda, which is affected by this.

**How to avoid:**
In the Python test script, load MPI libraries with `RTLD_GLOBAL` BEFORE loading `libwrfhydro_bmi.so`:
```python
import ctypes

# CRITICAL: Load MPI with RTLD_GLOBAL before loading the BMI library
ctypes.CDLL("libmpi.so", mode=ctypes.RTLD_GLOBAL)

# Now load the BMI library
bmi = ctypes.CDLL("libwrfhydro_bmi.so")
```

Alternatively, use `mpi4py` which handles this automatically:
```python
from mpi4py import MPI  # Loads MPI with correct flags
import ctypes
bmi = ctypes.CDLL("libwrfhydro_bmi.so")
```

Also: `libmpifort.so` may need to be loaded before `libmpi.so` for Fortran MPI symbols to resolve correctly.

**Warning signs:**
- Segfault deep in MPI library code (backtrace shows `dlopen`, `mca_base_component_find`, or similar)
- The same shared library works when linked into a Fortran executable but crashes from Python
- "symbol lookup error" mentioning MPI-related symbols
- Works on MPICH but crashes on Open MPI (MPICH does not use dlopen for internal plugins)

**Phase to address:**
Python test script. This must be addressed in the very first Python test attempt. Document the workaround prominently in both the test script and the documentation.

---

### Pitfall 4: Opaque Handle / Box Pattern Not Implemented

**What goes wrong:**
The C-binding wrapper creates a `bmi_wrf_hydro` object but has no way to pass it as an opaque `void*` handle to C/Python callers. Without the "box" pattern, there is no way for C code to hold a reference to the polymorphic Fortran type. Attempts to use `c_loc` directly on a polymorphic type (`class(bmi)`) fail because polymorphic types are not C-interoperable.

**Why it happens:**
Fortran polymorphic types (`class(bmi)`) contain a hidden descriptor (vtable pointer) that is not representable in C. The `c_loc()` intrinsic requires `TARGET` attribute and works on non-polymorphic types, but the whole point of BMI is polymorphism (`type, extends(bmi) :: bmi_wrf_hydro`). You cannot directly expose a Fortran polymorphic object to C.

The SCHISM/NextGen ecosystem solves this with the "box" pattern (see `iso_c_bmi.f90` lines 17-19):
```fortran
type box
  class(bmi), pointer :: ptr => null()
end type
```
The C caller gets a `c_ptr` to the `box`, and each C-binding function unpacks it:
```fortran
call c_f_pointer(this, bmi_box)
bmi_status = bmi_box%ptr%initialize(f_file)
```
The model is allocated and boxed in `register_bmi`:
```fortran
function register_bmi(this) result(bmi_status) bind(C, name="register_bmi")
  allocate(bmi_wrf_hydro :: bmi_model)
  allocate(bmi_box)
  bmi_box%ptr => bmi_model
  this = c_loc(bmi_box)
end function
```

**How to avoid:**
1. Implement a `register_bmi()` function with `bind(C, name="register_bmi")` that allocates a `bmi_wrf_hydro` object, wraps it in a `box`, and returns `c_loc(bmi_box)` as a `c_ptr`
2. Every C-binding wrapper function receives this `c_ptr`, calls `c_f_pointer(this, bmi_box)`, then calls the Fortran BMI method through `bmi_box%ptr%<method>()`
3. The `finalize()` C-binding wrapper must deallocate both the model and the box to prevent memory leaks:
```fortran
bmi_status = bmi_box%ptr%finalize()
if(associated(bmi_box%ptr)) deallocate(bmi_box%ptr)
if(associated(bmi_box)) deallocate(bmi_box)
```
4. Add a module-level singleton guard since WRF-Hydro uses global state:
```fortran
logical, save :: instance_registered = .false.
```

The SCHISM BMI `iso_c_bmi.f90` (948 lines) is the exact template to follow. It is already in the project at `SCHISM_BMI/src/BMI/iso_c_fortran_bmi/src/iso_c_bmi.f90`.

**Warning signs:**
- Compiler errors about "polymorphic variable may not have the TARGET attribute" or "not C interoperable"
- Attempting to use `c_loc()` on `class(bmi_wrf_hydro)` fails
- Segfault when C code tries to dereference the Fortran pointer
- Memory leaks in Python when finalize does not clean up the box

**Phase to address:**
ISO_C_BINDING wrapper implementation. This is the architectural foundation -- the `register_bmi` + box pattern must be designed first, then all 41 C-binding wrappers follow the same pattern.

---

### Pitfall 5: bmif_2_0 vs bmif_2_0_iso Module Mismatch

**What goes wrong:**
The C-binding layer imports `bmif_2_0_iso` (SCHISM's version with ISO_C_BINDING types), but the BMI wrapper uses `bmif_2_0` (conda version). These are different modules with subtly different type definitions (e.g., `integer` vs `integer(kind=c_int)` for return values). Mixing them causes compile errors or, worse, silent ABI incompatibility at runtime.

**Why it happens:**
SCHISM's iso_c_fortran_bmi library ships its own `bmif_2_0_iso` module (at `iso_c_fortran_bmi/src/bmi.f90`) which is a C-interoperable copy of the standard `bmif_2_0`. The standard `bmif_2_0` from conda uses plain `integer` for return types, while `bmif_2_0_iso` uses `integer(kind=c_int)`. On most platforms these are the same size (both 4 bytes), but this is NOT guaranteed by the Fortran standard.

The SCHISM BMI switches between modules using `#ifdef NGEN_ACTIVE`:
```fortran
#ifdef NGEN_ACTIVE
  use bmif_2_0_iso
#else
  use bmif_2_0
#endif
```

**How to avoid:**
**Recommended approach**: Keep `bmi_wrf_hydro.f90` using `bmif_2_0` (from conda, unchanged) and write the C-binding wrappers as a SEPARATE module (`bmi_wrf_hydro_c.f90` or `bmi_interop.f90`) that:
- Uses `use bmiwrfhydrof` to access the Fortran BMI type
- Uses `use, intrinsic :: iso_c_binding` for C types
- Does NOT import `bmif_2_0_iso` at all
- Uses `bmif_2_0` constants (BMI_SUCCESS, BMI_FAILURE, BMI_MAX_COMPONENT_NAME) directly

This requires ZERO changes to the working, tested `bmi_wrf_hydro.f90` (1,919 lines, 151/151 tests pass).

**Warning signs:**
- Compile errors about type mismatches between `integer` and `integer(c_int)`
- Linker errors about duplicate or missing module symbols
- Functions appear to succeed but return wrong status codes
- Tests pass in Fortran but fail through the C-binding layer

**Phase to address:**
ISO_C_BINDING wrapper design (architecture decision). This must be decided BEFORE writing any C-binding code.

---

### Pitfall 6: Circular Dependencies in Static Library Linking

**What goes wrong:**
The shared library build fails with undefined symbol errors even though all 22 WRF-Hydro libraries are listed on the link line. Symbols that exist in library A reference symbols in library B, and vice versa. Single-pass linking resolves symbols left-to-right and misses these circular references.

**Why it happens:**
WRF-Hydro's 22 static libraries have circular dependencies. For example, `libhydro_routing.a` calls functions in `libhydro_mpp.a`, while `libhydro_mpp.a` calls functions in `libhydro_routing.a`. The GNU linker processes `.a` files in a single pass by default.

The current `build.sh` handles this by listing all libraries THREE times:
```bash
${WRF_LIBS_SINGLE} ${WRF_LIBS_SINGLE} ${WRF_LIBS_SINGLE}
```
But `build.sh` uses `mpif90` which wraps the compiler and does not pass `--start-group`/`--end-group` correctly.

**How to avoid:**
The CMakeLists.txt already has the correct solution:
```cmake
-Wl,--start-group
${WRFHYDRO_LIBRARIES}
-Wl,--end-group
```
This tells the GNU linker to scan the group repeatedly until all symbols are resolved. For the `build.sh` shared library build, use `gfortran` (not `mpif90`) to pass linker flags directly:
```bash
gfortran -shared -o libwrfhydro_bmi.so *.o \
  -Wl,--start-group ${WRF_LIBS_SINGLE} -Wl,--end-group \
  -lnetcdff -lnetcdf -lmpi_mpifh -lmpi
```

**Warning signs:**
- "undefined reference to `subroutine_name_`" errors during linking
- Errors that go away when you repeat the library list 3-4 times
- Different undefined symbols each time you reorder the libraries
- Build works with executables (3x repetition) but fails for shared library

**Phase to address:**
Shared Library Build. The CMakeLists.txt already addresses this; verify it works for the `.so` target.

---

## Moderate Pitfalls

### Pitfall 7: Working Directory (chdir) from Python

**What goes wrong:**
WRF-Hydro's `initialize()` changes the working directory to the run directory (for reading namelists and data files), then changes back. But Python's `os.chdir()` and Fortran's `chdir()` operate on the SAME process working directory. If the Fortran `chdir` fails silently or does not restore the original directory, subsequent Python operations break.

**How to avoid:**
1. **Short term**: Document that the Python test must be run from the correct working directory OR use absolute paths in the BMI config
2. **Validation**: After each Fortran `initialize()` and `update()` call from Python, verify `os.getcwd()` is unchanged
3. **WSL2 specific**: Ensure the run directory path is short (< 200 characters) to avoid `character(len=256)` truncation

**Warning signs:**
- FileNotFoundError in Python after calling BMI functions
- WRF-Hydro writing output files to unexpected locations
- Test works from the run directory but fails from other directories

**Phase to address:**
Python test script.

---

### Pitfall 8: LD_LIBRARY_PATH Not Set for Runtime Loading

**What goes wrong:**
The shared library compiles and links successfully, but at runtime Python's `ctypes.CDLL("libwrfhydro_bmi.so")` raises `OSError: cannot open shared object file: No such file or directory`.

**How to avoid:**
```bash
export LD_LIBRARY_PATH=/path/to/bmi_wrf_hydro/_build:$CONDA_PREFIX/lib:$LD_LIBRARY_PATH
```
Or in Python use an absolute path:
```python
bmi = ctypes.CDLL("/absolute/path/to/libwrfhydro_bmi.so")
```
Verify with `ldd libwrfhydro_bmi.so` that ALL dependencies resolve.

**Warning signs:**
- "cannot open shared object file" errors
- `ldd libwrfhydro_bmi.so` shows "not found" for any dependency

**Phase to address:**
Python test script and build documentation.

---

### Pitfall 9: MPI_Init Called Multiple Times or Not Called

**What goes wrong:**
WRF-Hydro requires MPI to be initialized before model initialization. If MPI is not initialized before `bmi_initialize`, the model crashes. If MPI is initialized twice (e.g., once by mpi4py and once inside WRF-Hydro), it crashes with "MPI already initialized."

**How to avoid:**
1. Check `MPI_Initialized` before calling `MPI_Init` inside the BMI initialize (guard in wrapper or document requirement)
2. In the Python test: either import `mpi4py` first (which initializes MPI) OR run via `mpirun -np 1 python test.py`
3. Document: "MPI must be initialized before calling BMI initialize"
4. Never call `MPI_Finalize` from the BMI wrapper (already correctly handled in existing code)

**Warning signs:**
- Segfault immediately on `initialize()` from Python
- "MPI not initialized" or "MPI already initialized" error messages
- Tests pass with `mpirun -np 1` but fail when run directly

**Phase to address:**
Python test script and C-binding wrapper.

---

### Pitfall 10: Array Memory Layout Mismatch (Column-Major vs Row-Major)

**What goes wrong:**
Python receives array data from `get_value_double` but 2D grid values appear transposed or scrambled.

**How to avoid:**
1. Document the memory layout: "All arrays from get_value are in Fortran column-major order"
2. In Python, reshape with `order='F'`:
   ```python
   grid_2d = data.reshape((jx, ix), order='F')
   ```
3. At the C boundary, arrays pass through as flat 1D -- no reshaping needed

**Warning signs:**
- Spatial plots show transposed features
- Values at known grid locations are wrong but total sum is correct

**Phase to address:**
Python test script validation.

---

### Pitfall 11: Compiler Flag Mismatch Between WRF-Hydro and BMI Wrapper

**What goes wrong:**
The BMI shared library links successfully but produces wrong numerical results, or crashes in WRF-Hydro physics routines. The bit-for-bit match with standalone WRF-Hydro is broken.

**How to avoid:**
1. Use the same Fortran compiler version for both (already: gfortran 14.3.0)
2. Match critical flags: `-fconvert=big-endian`, `-frecord-marker=4` (already in CMakeLists.txt)
3. Match preprocessor defines: `-DWRF_HYDRO -DMPP_LAND` (already in CMakeLists.txt)
4. When rebuilding WRF-Hydro with `-fPIC`, do NOT change any other flags

**Warning signs:**
- Results differ between standalone and BMI-wrapped runs
- Endian-related errors when reading binary files
- Segfaults in physics routines

**Phase to address:**
Shared Library Build. Verify bit-for-bit match after rebuild.

---

## Minor Pitfalls

### Pitfall 12: Fortran Module (.mod) Files Not Installed

**What goes wrong:** CMake builds the `.so` but `.mod` files are not installed to `$CONDA_PREFIX/include/`. Phase 2 (babelizer) cannot find the Fortran module.

**How to avoid:** The existing CMakeLists.txt Section 10 already has install rules for `.mod` files. Verify after `cmake --install _build` that the files appear.

**Phase to address:** Shared Library Build (install step).

---

### Pitfall 13: Python Test Hardcodes Array Sizes

**What goes wrong:** Test hardcodes sizes (e.g., 240 for LSM grid) that only work for Croton NY. Other domains break.

**How to avoid:** Query sizes from BMI functions (`get_grid_size`) before allocating arrays.

**Phase to address:** Python test script.

---

### Pitfall 14: stderr vs stdout Confusion

**What goes wrong:** WRF-Hydro redirects stdout (unit 6) to `diag_hydro.00000`. Debug output from C-binding wrappers or Python test disappears into the file.

**How to avoid:** Use `write(0,*)` (stderr) in Fortran for any debug output. In Python, use `sys.stderr`.

**Phase to address:** ISO_C_BINDING wrappers and Python test script.

---

### Pitfall 15: WRF-Hydro Single-Instance Constraint

**What goes wrong:** The box pattern supports multiple instances, but WRF-Hydro uses module-level globals (SMOIS, rt_domain, etc.) that cannot be re-allocated. A second `register_bmi` call creates a second handle pointing to the same global state.

**How to avoid:** Add a singleton guard in the C-binding module:
```fortran
logical, save :: instance_registered = .false.
! In register_bmi:
if (instance_registered) then
  bmi_status = BMI_FAILURE
  return
end if
```

**Phase to address:** ISO_C_BINDING wrapper (register_bmi implementation).

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip `register_bmi` and use module-level singleton | Simpler C API (no handle passing) | Cannot support babelizer or NextGen; both expect `register_bmi` | Never -- babelizer requires it |
| Hardcode MPI_COMM_WORLD | Works for serial (np=1) | Breaks multi-model coupling where each model needs its own communicator | Phase 1 only; parameterize by Phase 4 |
| Copy iso_c_bmi.f90 from SCHISM verbatim | Get C bindings quickly | Uses `bmif_2_0_iso` which conflicts with conda `bmif_2_0` | Never -- adapt to use `bmif_2_0` instead |
| Use ctypes instead of cffi for Python test | Simpler, no extra dependency | ctypes has weaker type safety | Acceptable for testing; babelizer replaces this in Phase 2 |
| Skip `get_value_ptr` C binding (return BMI_FAILURE) | Avoid pointer-across-boundary complexity | Some frameworks expect it for zero-copy | Acceptable -- already BMI_FAILURE in Fortran; consistent |

## Integration Gotchas

Common mistakes when connecting components in this project.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Python ctypes -> Fortran strings | Using `ctypes.c_char_p` directly | Use `ctypes.create_string_buffer(b"config.txt\0")` with explicit null |
| Python ctypes -> Fortran arrays | Passing Python list | Use `numpy.zeros(n, dtype=numpy.float64)` + `.ctypes.data_as(POINTER(c_double))` |
| Conda env -> shared library | Forgetting conda activation | Add conda activation to all scripts; use absolute `$CONDA_PREFIX/lib` paths |
| CMake build vs build.sh | Assuming identical outputs | CMake: `--start-group`/`--end-group`; build.sh: 3x repetition; CMake adds `-fPIC` for SHARED |
| babelizer -> libwrfhydro_bmi.so | Missing `register_bmi` entry point | Must implement `register_bmi` with `bind(C)` returning opaque handle |
| Python -> MPI library | Loading BMI library before MPI | Must load `libmpi.so` with `RTLD_GLOBAL` first, THEN `libwrfhydro_bmi.so` |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `get_value_at_indices` allocates full array then picks elements | Slow for sparse access | Currently acceptable; optimize if profiling shows bottleneck | NWM-scale grids (2.7M reaches) |
| String comparison in select case for every get/set | O(n) string compare per call | Use integer variable IDs internally | > 100 variables or tight coupling loops |
| `chdir()` in every `update()` call | Filesystem overhead + not thread-safe | Cache run directory; use absolute paths | Multi-instance or threaded coupling |
| Full array copy in `get_value_double` (REAL -> double) | Allocation + copy every call | Consider shadow double arrays | Large grids with frequent coupling |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Shared library builds**: Verify `ldd libwrfhydro_bmi.so` -- ALL dependencies resolved (no "not found")
- [ ] **C-binding wrappers**: Verify ALL 41 BMI functions have C wrappers. Babelizer calls ALL of them
- [ ] **register_bmi function**: Not a standard BMI function but REQUIRED by iso_c_bmi/babelizer pattern. Must be `bind(C)` with box allocation
- [ ] **String output functions**: Verify null terminators on get_component_name, get_var_type, get_var_units, get_time_units, get_grid_type, get_var_location
- [ ] **MPI lifecycle**: Verify MPI_Init called before initialize, MPI_Finalize after finalize, double-init guarded
- [ ] **Grid functions via C binding**: C wrapper must determine array sizes (via get_grid_rank, get_grid_size) before passing assumed-size arrays. See SCHISM's `get_grid_shape` wrapper
- [ ] **Memory cleanup in finalize**: C-binding `finalize` must deallocate BOTH model object AND box wrapper
- [ ] **Python test validates results**: Not just BMI_SUCCESS but actual numerical values match standalone WRF-Hydro (Croton NY bit-for-bit)

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| WRF-Hydro not compiled with -fPIC | LOW | Rebuild with `CMAKE_POSITION_INDEPENDENT_CODE=ON`, ~5 min compile |
| String passing segfaults | LOW | Add c_to_f_string/f_to_c_string helpers; mechanical pattern |
| MPI RTLD_GLOBAL segfault | LOW | Add 2 lines to Python (`import mpi4py` or `CDLL("libmpi.so", RTLD_GLOBAL)`) |
| Box pattern missing | MEDIUM | Write `register_bmi` + refactor all C wrappers to use handle pattern |
| bmif_2_0 vs bmif_2_0_iso mismatch | MEDIUM | Keep separate C-wrapper module using only `bmif_2_0` (recommended) |
| Circular link dep errors | LOW | Already solved in CMakeLists.txt; verify for `.so` target |
| Working directory issues | LOW | Use absolute paths; document requirement |
| Array layout mismatch | LOW | Add `order='F'` to numpy reshape; document convention |
| Compiler flag mismatch | MEDIUM | Rebuild everything with matching flags; verify bit-for-bit |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| P1: WRF-Hydro no -fPIC | Shared Library Build (first task) | Linker succeeds; `ldd` shows all deps resolved |
| P2: String passing | ISO_C_BINDING Wrappers | Python calls all string-taking functions without crash |
| P3: MPI RTLD_GLOBAL | Python Test Script | `initialize()` returns BMI_SUCCESS from Python |
| P4: Box/register_bmi | ISO_C_BINDING Wrappers (design first) | `register_bmi` returns valid handle; all funcs work through handle |
| P5: bmif_2_0 vs _iso | ISO_C_BINDING Wrappers (arch decision) | Compile succeeds; Fortran tests still 151/151 |
| P6: Circular link deps | Shared Library Build (CMake) | `cmake --build` succeeds; no undefined symbols |
| P7: Working directory | Python Test Script | `os.getcwd()` unchanged after BMI calls |
| P8: LD_LIBRARY_PATH | Python Test + Docs | Python finds and loads `.so` without path issues |
| P9: MPI_Init lifecycle | Python Test + C Wrappers | No double-init or uninitialized-MPI crashes |
| P10: Array layout | Python Test + Docs | Streamflow at Croton NY outlets matches standalone |
| P11: Compiler flags | Shared Library Build | Numerical results match within float tolerance |
| P12: .mod not installed | Shared Library Install | `ls $CONDA_PREFIX/include/*.mod` finds files |
| P13: Hardcoded sizes | Python Test Script | Test queries sizes dynamically from BMI |
| P14: stderr vs stdout | ISO_C_BINDING Wrappers | Debug output visible in terminal, not swallowed |
| P15: Single-instance | ISO_C_BINDING Wrappers | Second register_bmi returns BMI_FAILURE |

## Sources

- [SCHISM BMI iso_c_bmi.f90](file:///mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/SCHISM_BMI/src/BMI/iso_c_fortran_bmi/src/iso_c_bmi.f90) -- 948-line reference implementation of C-binding wrappers (HIGH confidence, direct code inspection)
- [SCHISM BMI register_bmi](file:///mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/SCHISM_BMI/src/BMI/bmischism.f90) -- Lines 1701-1727, box pattern (HIGH confidence, direct code inspection)
- [SCHISM iso_c_fortran_bmi README](file:///mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/SCHISM_BMI/src/BMI/iso_c_fortran_bmi/README.md) -- register_bmi + box pattern docs (HIGH confidence)
- [Open MPI dlopen documentation](https://docs.open-mpi.org/en/v5.0.7/tuning-apps/dynamic-loading.html) -- Official docs on RTLD_GLOBAL requirement (HIGH confidence)
- [Open MPI GitHub issue #3705](https://github.com/open-mpi/ompi/issues/3705) -- dlopen RTLD_LOCAL issue (HIGH confidence)
- [GNU Fortran ISO_C_BINDING](https://gcc.gnu.org/onlinedocs/gfortran/ISO_005fC_005fBINDING.html) -- Official gfortran C interop docs (HIGH confidence)
- [Fortran Discourse: Shared libraries with bind(C)](https://fortran-lang.discourse.group/t/shared-libraries-with-bind-c-for-dummies/6566) -- Community discussion (MEDIUM confidence)
- [Foreign Fortran: ctypes](https://foreign-fortran.readthedocs.io/en/latest/python/ctypes.html) -- Python ctypes + Fortran practices (MEDIUM confidence)
- [CSDMS babelizer](https://babelizer.readthedocs.io/en/latest/readme.html) -- Library requirements for babelizer (MEDIUM confidence)
- [bmi_wrf_hydro.f90](file:///mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro/src/bmi_wrf_hydro.f90) -- Current BMI wrapper analyzed for C-binding readiness (HIGH confidence)
- [build.sh](file:///mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro/build.sh) -- Current build process analyzed for shared library gaps (HIGH confidence)
- [CMakeLists.txt](file:///mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro/CMakeLists.txt) -- 649-line CMake config analyzed for correctness (HIGH confidence)

---
*Pitfalls research for: Fortran BMI shared library with C bindings and Python interop*
*Researched: 2026-02-23*
