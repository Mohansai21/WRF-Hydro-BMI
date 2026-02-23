# Architecture Patterns

**Domain:** Fortran BMI shared library with ISO_C_BINDING wrappers and Python interoperability
**Researched:** 2026-02-23
**Confidence:** HIGH (based on direct analysis of two working reference implementations in the codebase)

## Recommended Architecture

The architecture follows the established CSDMS/NOAA-OWP pattern used by both `bmi-example-fortran` and `LynkerIntel/SCHISM_BMI`. The key insight is that there are three distinct layers between Python and WRF-Hydro, each with a single responsibility.

```
                    PYTHON TEST (test_bmi_wrfhydro.py)
                         |
                    ctypes.cdll.LoadLibrary("libwrfhydro_bmi.so")
                         |
                    ctypes FFI calls (C ABI)
                         |
    +---------------------------------------------------------+
    |  Layer 3: ISO_C_BINDING WRAPPER (bmi_interop.f90)       |
    |  - bind(C, name="...") free functions                   |
    |  - "box" pattern: opaque handle (c_ptr) -> Fortran type |
    |  - String conversion: c_to_f_string / f_to_c_string     |
    |  - register_bmi() creates the model instance             |
    +---------------------------------------------------------+
                         |
                    Fortran procedure calls (class method dispatch)
                         |
    +---------------------------------------------------------+
    |  Layer 2: BMI WRAPPER (bmi_wrf_hydro.f90) [EXISTING]    |
    |  - type(bmi_wrf_hydro) extends(bmi)                     |
    |  - All 41 BMI functions implemented                      |
    |  - 55 procedure bindings (type-specific variants)        |
    |  - CSDMS Standard Names mapping                          |
    +---------------------------------------------------------+
                         |
                    Fortran USE + subroutine calls
                         |
    +---------------------------------------------------------+
    |  Layer 1: WRF-HYDRO MODEL (22 static libraries)         |
    |  - land_driver_ini/exe, HYDRO_ini/exe                   |
    |  - Module globals: SMOIS, SFCRUNOFF, rt_domain, etc.    |
    |  - 86 .mod files for module interfaces                   |
    +---------------------------------------------------------+
```

### Component Boundaries

| Component | File(s) | Responsibility | Communicates With |
|-----------|---------|----------------|-------------------|
| **WRF-Hydro Model** | 22 `.a` libraries + 86 `.mod` files | Physics simulation (Noah-MP, routing, channel) | Layer 2 via Fortran `use` modules |
| **BMI Wrapper** | `src/bmi_wrf_hydro.f90` (1,919 lines) | Implements all 41 BMI functions, maps CSDMS names, manages IRF lifecycle | Layer 1 (downstream) + Layer 3 (upstream) |
| **C Binding Layer** | `src/bmi_interop.f90` (~600-800 lines, NEW) | ISO_C_BINDING wrappers: opaque handle, string conversion, C ABI | Layer 2 (downstream) + Python/C (upstream) |
| **Register Function** | Inside `bmi_interop.f90` | Factory: allocates `bmi_wrf_hydro` instance, returns opaque `c_ptr` handle | Called first by any C/Python consumer |
| **Shared Library** | `libwrfhydro_bmi.so` (CMake/build.sh output) | Packages Layers 2+3 + links Layer 1 into one loadable binary | Loaded by Python ctypes or babelizer |
| **Python Test** | `tests/test_bmi_wrfhydro.py` (~200-300 lines, NEW) | Exercises all BMI functions via ctypes, validates against Croton NY data | Loads the .so, calls C ABI functions |
| **CMake Build** | `CMakeLists.txt` (650 lines, EXISTING) | Compiles .so, links 22 WRF-Hydro libs + BMI + MPI + NetCDF | Produces the .so and test executable |

### Data Flow

**Direction: Python --> C ABI --> Fortran OOP --> WRF-Hydro globals**

```
Python (test_bmi_wrfhydro.py)
  |
  | lib = ctypes.cdll.LoadLibrary("libwrfhydro_bmi.so")
  | handle = ctypes.c_void_p()
  | lib.register_bmi(ctypes.byref(handle))
  | lib.initialize(handle, config_path.encode())
  | lib.update(handle)
  | lib.get_value_double(handle, var_name.encode(), dest_array)
  |
  v
bmi_interop.f90 (ISO_C_BINDING layer)
  |
  | type(box), pointer :: bmi_box
  | call c_f_pointer(this, bmi_box)          -- unwrap opaque handle
  | f_str = c_to_f_string(name)              -- C string -> Fortran string
  | bmi_status = bmi_box%ptr%get_value_double(f_str, dest(:num_items))
  |
  v
bmi_wrf_hydro.f90 (BMI wrapper)
  |
  | use module_noahmp_hrldas_driver, only: SMOIS, ...
  | use module_RT_data, only: rt_domain
  | dest(1:n) = dble(reshape(SMOIS(...), [...]))  -- REAL -> double, 2D -> 1D
  |
  v
WRF-Hydro module globals (persistent Fortran state)
```

**Reverse direction (set_value):**
```
Python: lib.set_value_double(handle, name, src_array)
  -> bmi_interop.f90: converts C types, calls bmi_box%ptr%set_value_double(...)
    -> bmi_wrf_hydro.f90: RAINBL(1:ix, 1:jx) = reshape(real(src), [ix, jx])
      -> WRF-Hydro RAINBL module global is modified in-place
```

## The "Box" Pattern (Critical Architecture Decision)

**Confidence:** HIGH -- this is the exact pattern used by SCHISM_BMI (bmischism.f90 lines 1701-1727) and documented in the iso_c_fortran_bmi library by NOAA-OWP.

### The Problem
Fortran's polymorphic types (`class(bmi_wrf_hydro)`) cannot be directly passed across the C ABI boundary. C has no concept of Fortran class dispatch tables (vtables). Python's ctypes can only work with C-compatible types.

### The Solution: Opaque Handle via Box Type

```fortran
! In bmi_interop.f90:
type box
  class(bmi), pointer :: ptr => null()
end type

! register_bmi creates the instance and returns an opaque handle
function register_bmi(this) result(bmi_status) bind(C, name="register_bmi")
  type(c_ptr) :: this          ! void** from C perspective
  type(bmi_wrf_hydro), pointer :: bmi_model
  type(box), pointer :: bmi_box

  allocate(bmi_wrf_hydro :: bmi_model)   ! Create the BMI instance
  allocate(bmi_box)                       ! Create the box
  bmi_box%ptr => bmi_model               ! Point box at instance
  this = c_loc(bmi_box)                  ! Return address of box
  bmi_status = BMI_SUCCESS
end function

! Every subsequent call unwraps the handle
function initialize(this, config_file) result(bmi_status) bind(C, name="initialize")
  type(c_ptr) :: this
  type(box), pointer :: bmi_box
  call c_f_pointer(this, bmi_box)        ! Recover the box from the handle
  bmi_status = bmi_box%ptr%initialize(f_file)  ! Call the actual BMI method
end function
```

**In Python:**
```python
import ctypes
lib = ctypes.cdll.LoadLibrary("./libwrfhydro_bmi.so")
handle = ctypes.c_void_p()
lib.register_bmi(ctypes.byref(handle))     # handle is now the opaque box pointer
lib.initialize(handle, b"/path/to/config")  # pass handle to every call
```

### Why This Pattern (Not Alternatives)

| Approach | Verdict | Reason |
|----------|---------|--------|
| **Box pattern** (SCHISM/NOAA-OWP) | USE THIS | Proven in production (NextGen, SCHISM_BMI), handles polymorphism, babelizer expects it |
| Module-level singleton | Rejected | Cannot support multiple model instances, breaks if babelizer creates two instances |
| Direct C struct mapping | Rejected | Cannot represent Fortran class dispatch, lose polymorphism |
| Cython/f2py wrappers | Rejected | Adds build complexity, babelizer uses ctypes/cffi not Cython |

## File Organization Pattern

```
bmi_wrf_hydro/
  src/
    bmi_wrf_hydro.f90           # [EXISTING] BMI wrapper (Layer 2)
    bmi_interop.f90             # [NEW] ISO_C_BINDING wrappers (Layer 3)
  tests/
    bmi_wrf_hydro_test.f90      # [EXISTING] Fortran test (151 tests)
    bmi_minimal_test.f90        # [EXISTING] Fortran smoke test
    test_bmi_wrfhydro.py        # [NEW] Python ctypes test
  build/                        # [EXISTING] Build artifacts
  CMakeLists.txt                # [EXISTING, UPDATE] Add bmi_interop.f90 to sources
  build.sh                      # [EXISTING, UPDATE] Add bmi_interop.f90 to compile
```

**Why this layout:** The C binding layer goes in `src/` alongside the BMI wrapper because they are both part of the shared library. The Python test goes in `tests/` because it is a consumer of the library, not a component of it.

## Patterns to Follow

### Pattern 1: Separate Fortran BMI from C Bindings

**What:** Keep `bmi_wrf_hydro.f90` (pure Fortran BMI) and `bmi_interop.f90` (C binding wrappers) as separate files/modules.

**When:** Always. This is the CSDMS ecosystem convention.

**Why:** The Fortran BMI wrapper is usable from Fortran directly (for testing, for Fortran-to-Fortran coupling). The C binding layer adds C ABI compatibility on top. Separating them means:
- `bmi_wrf_hydro.f90` never needs `bind(C)` attributes in its function signatures
- The C binding layer is a thin pass-through that can be generated or swapped
- The babelizer's generated code follows this same separation

**Evidence:** bmi-example-fortran has `bmi_heat.f90` (Fortran BMI) separate from any C bindings. SCHISM_BMI has `bmischism.f90` (Fortran BMI) + `iso_c_bmi.f90` (generic C bindings) + `register_bmi` function (model-specific factory).

### Pattern 2: Generic iso_c_bmi + Model-Specific Register

**What:** The iso_c_bmi.f90 module from NOAA-OWP is *generic* -- it works with any Fortran BMI model via the `box` pattern and polymorphism. The only model-specific piece is the `register_bmi` function that creates the concrete model instance.

**When:** For the C binding layer.

**Why:** This means we can reuse NOAA-OWP's existing `iso_c_bmi.f90` almost verbatim. We only need to write the `register_bmi` function that allocates our `bmi_wrf_hydro` type.

**Example structure:**
```fortran
! bmi_interop.f90 -- Model-specific C binding layer

module bmi_wrf_hydro_interop
  use bmiwrfhydrof        ! Our BMI wrapper module
  use iso_c_bmif_2_0      ! Generic C binding layer from NOAA-OWP
  use, intrinsic :: iso_c_binding
  implicit none
contains
  function register_bmi(this) result(bmi_status) bind(C, name="register_bmi")
    type(c_ptr) :: this
    integer(kind=c_int) :: bmi_status
    type(bmi_wrf_hydro), pointer :: bmi_model
    type(box), pointer :: bmi_box
    allocate(bmi_wrf_hydro :: bmi_model)
    allocate(bmi_box)
    bmi_box%ptr => bmi_model
    this = c_loc(bmi_box)
    bmi_status = BMI_SUCCESS
  end function
end module
```

### Pattern 3: bmif_2_0 vs bmif_2_0_iso (Two BMI Spec Variants)

**What:** The CSDMS BMI Fortran spec has two variants:
- `bmif_2_0` (standard) -- used by `bmi-fortran` conda package, used by `bmi_wrf_hydro.f90`
- `bmif_2_0_iso` (C-compatible) -- used by NOAA-OWP iso_c_fortran_bmi, uses `c_int` for return types

**When:** This matters when the C binding layer uses `iso_c_bmi.f90` which imports `bmif_2_0_iso`.

**Strategy:** Our `bmi_wrf_hydro.f90` uses `bmif_2_0` from the conda package. The C binding layer needs `bmif_2_0_iso`. Two options:
1. **Copy iso_c_bmi.f90 and modify to use `bmif_2_0`** -- simpler, avoids needing a second BMI spec module
2. **Include `bmif_2_0_iso` as a local file and compile alongside** -- matches SCHISM_BMI exactly

Option 1 is recommended because `bmi_wrf_hydro.f90` already extends `bmi` from `bmif_2_0`. Writing our own C binding wrappers that directly import from `bmiwrfhydrof` (our wrapper module) avoids the dual-spec issue entirely.

### Pattern 4: String Conversion Helpers

**What:** C strings are null-terminated arrays of `c_char`. Fortran strings are fixed-length with trailing spaces. Every C binding function that takes or returns a string needs conversion.

**When:** Every function in the C binding layer that touches strings (most of them).

**Example from SCHISM_BMI iso_c_bmi.f90 (verified in codebase):**
```fortran
pure function c_to_f_string(c_string) result(f_string)
  character(kind=c_char, len=1), intent(in) :: c_string(:)
  character(len=:), allocatable :: f_string
  ! Scan for null terminator, then transfer
end function

pure function f_to_c_string(f_string) result(c_string)
  character(len=*), intent(in) :: f_string
  character(kind=c_char, len=1), dimension(len_trim(f_string)+1) :: c_string
  ! Copy chars, append c_null_char
end function
```

### Pattern 5: Array Size Discovery in C Binding

**What:** C binding `get_value_*` functions receive `dest(*)` (assumed-size arrays). The C binding layer must determine the array size by querying `get_var_nbytes` and `get_var_itemsize` before passing to the Fortran BMI.

**When:** Every `get_value_*` and `set_value_*` C binding function.

**Evidence from SCHISM_BMI iso_c_bmi.f90 (line 396-408):**
```fortran
bmi_status = bmi_box%ptr%get_var_nbytes(f_str, num_bytes)
bmi_status = bmi_box%ptr%get_var_itemsize(f_str, item_size)
num_items = num_bytes / item_size
bmi_status = bmi_box%ptr%get_value_int(f_str, dest(:num_items))
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Modifying bmi_wrf_hydro.f90 to Add bind(C)
**What:** Adding `bind(C)` attributes directly to the BMI wrapper's type-bound procedures.
**Why bad:** Breaks the Fortran BMI abstract interface contract (`bmif_2_0` doesn't use `bind(C)` in its deferred procedures). Would break the existing 151-test Fortran test suite. Makes the wrapper unusable from pure Fortran callers.
**Instead:** Keep the Fortran wrapper clean. Add C bindings as a separate layer.

### Anti-Pattern 2: Module-Level Singleton Instead of Box Pattern
**What:** Declaring `type(bmi_wrf_hydro), save :: global_model` at module level and having C functions operate on it.
**Why bad:** Cannot support multiple instances (babelizer may create more than one). Not thread-safe. Breaks the CSDMS convention that callers manage model instances via handles.
**Instead:** Use the box pattern where each call to `register_bmi` creates a new independent instance.

### Anti-Pattern 3: Using f2py or CFFI Generator for the Binding Layer
**What:** Auto-generating the C binding layer using f2py, SWIG, or similar tools.
**Why bad:** BMI functions have specific conventions (assumed-size arrays, string handling) that auto-generators don't handle correctly. The CSDMS ecosystem expects hand-written iso_c_bmi wrappers. The babelizer's generated code expects specific function signatures (e.g., `register_bmi`).
**Instead:** Follow the NOAA-OWP iso_c_bmi.f90 pattern -- it is essentially a boilerplate template.

### Anti-Pattern 4: Writing the Python Test with cffi Instead of ctypes
**What:** Using CFFI's out-of-line mode which requires a build step and C header parsing.
**Why bad:** Adds a compile dependency for the test. ctypes is stdlib, works directly with the .so, and is what the babelizer's generated code uses under the hood.
**Instead:** Use ctypes, which is included in Python's standard library and needs no compilation.

## Build Dependencies and Order

### Compilation DAG (Directed Acyclic Graph)

```
     WRF-Hydro 22 .a libs       bmi-fortran (bmif_2_0.mod + libbmif.so)
              \                   /
               \                 /
                v               v
         bmi_wrf_hydro.f90  (uses bmif_2_0, uses WRF-Hydro modules)
                     |
                     v
              bmi_interop.f90  (uses bmiwrfhydrof, uses iso_c_binding)
                     |
                     v
            libwrfhydro_bmi.so  (links bmi_wrf_hydro.o + bmi_interop.o
                |                + 22 WRF-Hydro .a + libbmif + MPI + NetCDF)
               / \
              /   \
             v     v
  bmi_wrf_hydro_test    test_bmi_wrfhydro.py
  (Fortran, links .so)  (Python, loads .so via ctypes)
```

### Build Order (Sequential Dependencies)

1. **bmi_wrf_hydro.f90** must compile first (produces `bmiwrfhydrof.mod` and `wrfhydro_bmi_state_mod.mod`)
2. **bmi_interop.f90** must compile second (depends on `bmiwrfhydrof.mod`)
3. **libwrfhydro_bmi.so** links both `.o` files + all dependencies
4. **Tests** (Fortran or Python) run against the built `.so`

### CMakeLists.txt Changes Required

The existing CMakeLists.txt (650 lines) needs minimal changes:

```cmake
# SECTION 7: Add bmi_interop.f90 to the shared library sources
add_library(wrfhydro_bmi SHARED
  src/bmi_wrf_hydro.f90
  src/bmi_interop.f90          # NEW: C binding layer
)
```

That is the primary change. The compile flags, include directories, and link libraries already handle everything needed.

### build.sh Changes Required

```bash
# Compile bmi_interop.f90 (after bmi_wrf_hydro.f90)
${FC} ${FFLAGS} ${INCLUDES} ${MOD_OUT} "${SRC_DIR}/bmi_interop.f90" -o "${BUILD_DIR}/bmi_interop.o"

# Add bmi_interop.o to the link step
# For shared library: add -shared -fPIC to link command
```

## Scalability Considerations

| Concern | Current (Croton NY) | At Production Scale (NWM) | Mitigation |
|---------|---------------------|---------------------------|------------|
| Shared library size | ~50-100 MB (includes 22 static libs) | Same binary, larger data | Static libs are absorbed into .so at link time |
| Memory per model instance | ~200 MB (Croton 15x16 grid) | 5-20 GB (NWM 4608x3840 grid) | WRF-Hydro globals limit to 1 instance anyway |
| Python ctypes overhead | Negligible (1 FFI call per BMI call) | Negligible (data copy dominates) | get_value_ptr could eliminate copies if implemented |
| Multiple instances | Prevented by WRF-Hydro module globals | Same constraint | Document as limitation; Phase 2+ may address |

## Suggested Implementation Order

Based on the dependency graph and risk profile:

1. **Write bmi_interop.f90** (C binding layer) -- the core new code
   - Start with `register_bmi` + `initialize` + `update` + `finalize`
   - Add string conversion helpers (c_to_f_string, f_to_c_string)
   - Add all remaining BMI function wrappers
   - Follow SCHISM_BMI's iso_c_bmi.f90 as template

2. **Update CMakeLists.txt** -- add bmi_interop.f90 to sources

3. **Build libwrfhydro_bmi.so via CMake** -- verify the .so builds and links

4. **Update build.sh** -- add bmi_interop.f90 compile + shared lib link target

5. **Write test_bmi_wrfhydro.py** -- Python ctypes test
   - Load .so, call register_bmi, initialize, update, get_value_double, finalize
   - Verify output values match Fortran test expectations

6. **Run full validation** -- both Fortran (151 tests) and Python test pass

## Sources

- **SCHISM_BMI iso_c_bmi.f90** (NOAA-OWP, Nels Frazier, Aug 2021): `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/SCHISM_BMI/src/BMI/iso_c_fortran_bmi/src/iso_c_bmi.f90` -- 948 lines, all 41 BMI functions wrapped with C bindings
- **SCHISM_BMI bmischism.f90 register_bmi**: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/SCHISM_BMI/src/BMI/bmischism.f90` lines 1701-1727 -- the box pattern factory function
- **SCHISM_BMI test_iso_c.c**: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/SCHISM_BMI/src/BMI/iso_c_fortran_bmi/test/test_iso_c.c` -- 402-line C test demonstrating the complete calling convention
- **bmi-example-fortran bmi_heat.f90**: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi-example-fortran/bmi_heat/bmi_heat.f90` -- CSDMS reference implementation (935 lines)
- **bmif_2_0_iso spec**: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/SCHISM_BMI/src/BMI/iso_c_fortran_bmi/src/bmi.f90` -- C-compatible BMI abstract interface
- **Existing bmi_wrf_hydro.f90**: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro/src/bmi_wrf_hydro.f90` -- 1,919 lines, all 41 BMI functions
- **Existing CMakeLists.txt**: `/mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro/CMakeLists.txt` -- 650 lines, fully configured
