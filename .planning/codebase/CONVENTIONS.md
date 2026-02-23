# Coding Conventions

**Analysis Date:** 2026-02-23

## Naming Patterns

### Files
- **Modules**: `module_name.f90` (lowercase with underscores)
  - Example: `bmi_wrf_hydro.f90`, `wrfhydro_bmi_state_mod.f90`
- **Test programs**: `test_name.f90` (lowercase)
  - Example: `bmi_wrf_hydro_test.f90`, `bmi_minimal_test.f90`
- **State module**: Must separate persistent state from implementation
  - Example: `wrfhydro_bmi_state_mod.f90` (state) + `bmiwrfhydrof` (wrapper)

### Functions/Subroutines
- **Procedure naming**: All lowercase with underscores connecting words
  - Pattern: `verb_object_descriptor`
  - Examples: `wrfhydro_initialize`, `wrfhydro_get_double`, `wrfhydro_var_grid`
- **Procedure bindings**: Use `=>` to bind type methods to implementations
  - Example: `procedure :: initialize => wrfhydro_initialize`
- **Helper subroutines**: Describe the check type clearly
  - Examples: `check_status`, `check_true` (in test programs)

### Variables
- **Type members**: lowercase with underscores
  - Examples: `initialized`, `current_timestep`, `run_dir`, `sea_water_elevation`
- **Local variables**: lowercase
  - Examples: `status`, `i`, `n_steps`, `bmi_status`, `rc`
- **Module-level constants**: UPPERCASE
  - Pattern: `GRID_LSM`, `GRID_ROUTING`, `GRID_CHANNEL` (parameter declarations)
  - Pattern: `N_INPUT_VARS`, `N_OUTPUT_VARS` (count parameters)
- **Saved module variables**: Indicate persistence in comments
  - Examples: `wrfhydro_bmi_state` (save attribute), `wrfhydro_engine_initialized` (save attribute)
  - Comment pattern: "! Module-level flag: [describes purpose and persistence]"

### Types
- **Derived type names**: CamelCase for class-like types
  - Examples: `type :: bmi_wrf_hydro`, `type :: bmi_heat`, `type :: state_type`
- **Type parameters**: Lowercase with underscores
  - Example: `double precision :: current_time`

## Code Style

### Formatting
- **Indentation**: 3 spaces per level (seen in all source files)
- **Line length**: Keep under 80 characters where possible (Fortran convention)
- **Continuation**: Use `&` at end of line and start of continuation line
- **Module structure**:
  1. Module header comment (file purpose)
  2. `module` declaration
  3. `use` statements (imports)
  4. `implicit none` (CRITICAL — forces declaration discipline)
  5. Type definitions with comments
  6. Module-level constants (`parameter`)
  7. Module-level variables (`save`)
  8. `contains` keyword
  9. Procedure implementations with detailed header comments
  10. `end module`

### Linting/Formatting
- **Compiler**: gfortran 14.3.0 (from conda-forge)
- **Compilation flags**: `-cpp -DWRF_HYDRO -DMPP_LAND` (C preprocessor + model defines)
- **Implicit behavior**: Always use `implicit none` (enforces declaration of all variables)
- **No automated formatter**: Code is formatted manually to conventions observed

## Import Organization

### Use Statement Order
1. **Standard library** (`use, intrinsic :: iso_c_binding`)
2. **BMI specification** (`use bmif_2_0`)
3. **State module** (must come before main module if they interact)
4. **WRF-Hydro modules** (`use module_noahmp_hrldas_driver`, etc.)
5. **Custom modules** (project-specific)

Example from `bmi_wrf_hydro.f90`:
```fortran
use bmif_2_0
use, intrinsic :: iso_c_binding, only: c_ptr, c_loc, c_f_pointer
use wrfhydro_bmi_state_mod, only: wrfhydro_bmi_state, &
     wrfhydro_engine_initialized, wrfhydro_saved_ntime
```

### Only Clauses
- **Pattern**: Use `only:` to explicitly import specific items (prevents namespace pollution)
- **Example**: `use module_RT_data, only: rt_domain`
- **Multi-line**: Continue with `&` and indent
  ```fortran
  use wrfhydro_bmi_state_mod, only: wrfhydro_bmi_state, &
       wrfhydro_engine_initialized, wrfhydro_saved_ntime
  ```

### Path Aliases
- **Not used** in this codebase (Fortran doesn't have path aliases like Python)
- **Module reuse pattern**: Import widely-used modules at top, local imports inside procedures via `block...use` constructs
  - Example in `wrfhydro_initialize`: `block` → `use config_base, only: nlst` → `end block`

## Error Handling

### Return Value Pattern (BMI-specific)
- **Pattern**: All BMI functions return `integer :: bmi_status`
  - `BMI_SUCCESS = 0` (successful execution)
  - `BMI_FAILURE = 1` (error occurred)
- **Check pattern**: `if (status /= BMI_SUCCESS) then` or `if (status == BMI_FAILURE) then`

### Input Validation
- **File existence check**: `inquire(file=config_file, iostat=rc)` then check `rc /= 0`
- **Array bounds**: `min(this%nlinks, size(x))` to avoid out-of-bounds access
- **Allocation check**: `if (allocated(array))` before reading, `if (.not. allocated(array))` before allocating
- **Pointer checks**: `nullify(pointer)` at start, `if (associated(pointer))` to check, `nullify(pointer)` after use

### Graceful Degradation
- **Unknown variables**: Return `BMI_FAILURE` without crashing
  - Pattern: `case default` in `select case` statements returns `BMI_FAILURE`
- **Missing data**: Return zeros instead of crashing
  - Example from `wrfhydro_get_double`: If array not allocated, `dest(:) = 0.0d0; bmi_status = BMI_SUCCESS`
- **Sentinel value cleanup**: Replace WRF-Hydro's undefined_real (~9.97E+036) with 0.0 in output
  - Example: T2MVXY temperature checks `if (abs(dest(i)) > 1.0d30) dest(i) = 0.0d0`

### Guard Clauses
- **Early return pattern**: Check preconditions first, return immediately on failure
  ```fortran
  if (.not. this%initialized) then
     bmi_status = BMI_FAILURE
     return
  end if
  ```
- **Module-level guards**: Prevent double-initialization via persistent flags
  ```fortran
  if (.not. wrfhydro_engine_initialized) then
     ! Initialize for first time only
     wrfhydro_engine_initialized = .true.
  else
     ! Re-initialization: restore from saved state
  end if
  ```

## Logging

### Framework
- **No external logging library** (Fortran standard I/O only)
- **Output destination**: `write(0,*)` (stderr, not stdout) — WRF-Hydro redirects stdout to file

### Patterns
- **Informational messages**: `write(0,*) "[BMI] Calling function_name()..."`
- **Status reports**: `write(0,*) "Component name: ", trim(comp_name)`
- **Section headers**:
  ```fortran
  write(0,*) "=============================================================="
  write(0,*) "  Section Name"
  write(0,*) "=============================================================="
  ```
- **Test output**: `write(0,*) "  PASS: ", trim(test_name)` or `write(0,*) "  FAIL: ", trim(test_name)`

### Stderr Output Rationale
- WRF-Hydro calls `open_print_mpp(6)` which redirects Fortran unit 6 (stdout) to file `diag_hydro.00000`
- Using `write(0,*)` (stderr) ensures debugging output goes to terminal, not into diag files
- Pattern: Comments explain why—example in `bmi_minimal_test.f90` lines 4-8

## Comments

### When to Comment
- **Header comment (every module)**: Purpose, what it does, Fortran concepts for newcomers
  - Example: `bmi_wrf_hydro.f90` lines 32-109 (77 lines of explanation)
- **Section headers**: Separate major logical sections with clear markers
  ```fortran
  ! **************************************************************************
  ! SECTION 1: CONTROL FUNCTIONS (4)
  ! **************************************************************************
  ! These manage the model lifecycle: create, run, destroy.
  ! **************************************************************************
  ```
- **Non-obvious logic**: Explain WHY, not WHAT
  - Example: Lines 455-458 explain why stderr is used instead of stdout
  - Example: Lines 394-398 explain the intent(out) issue and persistent state solution
- **Domain knowledge references**: Link to external specs or models
  - Example: Line 37 mentions "BMI spec" with concept explanation
- **Gotchas and design decisions**: Document non-obvious choices
  - Example: Lines 606-611 explain why HYDRO_finish() is not called (has "stop")

### JSDoc/Documentation Comments
- **Function/procedure header pattern**:
  ```fortran
  ! --------------------------------------------------------------------------
  ! function_name: One-line description.
  ! --------------------------------------------------------------------------
  ! Detailed explanation of what it does.
  ! Why it's needed.
  ! Specific implementation notes.
  ! --------------------------------------------------------------------------
  ```
- **Parameter documentation**: Include in header comment, reference `intent(in/out/inout)`
  - Not separate — all grouped in header
- **Examples provided in comments**: Actual Fortran code snippets or pseudocode
  - Example: Lines 373-376 show namelist format

### Code Comments Pattern
- **Inline comments**: Describe WHY the line is there, not WHAT it does
  - Good: `! intent(out) resets all type fields → use module-level saved vars`
  - Bad: `! Set initialized to .false.`
- **Range comments**: Multi-line blocks explained at top
  ```fortran
  ! --- Step 1: Read the BMI configuration file ---
  ! [5-6 lines of code]
  ```

## Function Design

### Size Guidelines
- **Maximum**: ~150 lines per procedure (seen in `wrfhydro_initialize` at 145 lines)
- **Strategy**: Break into logical steps with clear section comments
  - Example: `wrfhydro_initialize` has 7 numbered steps (lines 404-518)
- **Refactoring**: Use helper subroutines for repeated logic
  - Example: Test helpers `check_status` and `check_true` factor out test assertions

### Parameters
- **Always declare intent**: `intent(in)`, `intent(out)`, `intent(inout)` (REQUIRED)
- **Optional arguments**: Not used in this codebase (BMI spec doesn't allow them)
- **Pass-by-value vs reference**: Arrays are always passed by reference (Fortran default)
  - Use `dimension(:)` for assumed-shape arrays (flexible size)
  - Example: `double precision, dimension(:), intent(out) :: dest`

### Return Values
- **BMI functions**: Always return `integer :: bmi_status` (0 = success, 1 = failure)
- **Intent specification**: Result variable must match return type
  ```fortran
  function wrfhydro_initialize(this, config_file) result(bmi_status)
     integer :: bmi_status  ! Must be declared and returned
  end function
  ```
- **Multiple outputs**: Use intent(out) parameters, not multiple returns (Fortran limitation)
  - Example: `get_var_type(name, var_type_str)` outputs via `var_type_str` parameter

## Module Design

### Exports
- **Public interface**: Declare at module level
  ```fortran
  private
  public :: bmi_wrf_hydro
  ```
- **Pattern**: Make only the main type public, keep helpers private
- **Type members**: Mark as `private` within type definition to enforce encapsulation

### Barrel Files (Aggregation)
- **Not used** in this codebase (Fortran doesn't have true barrel file concept)
- **Alternative pattern**: Main module (`bmiwrfhydrof`) imports from state module (`wrfhydro_bmi_state_mod`)
  - Keeps concerns separate: state persistence ≠ BMI implementation
  - Prevents circular dependencies (state module is pure data)

### Module Variables with Save Attribute
- **Persistent across procedure calls**: `double precision, save :: wrfhydro_saved_ntime`
- **Used for**: Module-level state that persists across BMI lifecycle calls
- **Reason**: BMI `initialize(this, config_file)` has `intent(out)` on `this`, which resets type members
- **Example pattern**:
  ```fortran
  module wrfhydro_bmi_state_mod
    type(state_type), save :: wrfhydro_bmi_state
    logical, save :: wrfhydro_engine_initialized = .false.
  end module
  ```

## Type-Based Dispatch (Generic Overloading)

### Generic Procedure Pattern
- **Problem**: BMI requires get_value_int, get_value_float, get_value_double (3 variants)
- **Solution**: Use `generic` binding to create overloaded interface
  ```fortran
  procedure :: get_value_int => wrfhydro_get_int
  procedure :: get_value_float => wrfhydro_get_float
  procedure :: get_value_double => wrfhydro_get_double
  generic :: get_value => &
       get_value_int, &
       get_value_float, &
       get_value_double
  ```
- **Caller sees**: Single `get_value()` method that dispatches by argument type (like Python's `@overload`)
- **Implementation**: Three separate subroutines with type-specific logic
  - `wrfhydro_get_int` returns BMI_FAILURE (WRF-Hydro is double precision only)
  - `wrfhydro_get_float` returns BMI_FAILURE (type mismatch)
  - `wrfhydro_get_double` returns actual data (copies from WRF-Hydro arrays)

## Case Statements for Variable Dispatch

### Pattern for Variable Lookup
- **Problem**: Given a variable name (string), return its metadata or value
- **Solution**: Use `select case(name)` to dispatch
  ```fortran
  select case(name)
  case('channel_water__volume_flow_rate')
     grid = GRID_CHANNEL
     bmi_status = BMI_SUCCESS
  case('land_surface_water__depth')
     grid = GRID_ROUTING
     bmi_status = BMI_SUCCESS
  case default
     grid = -1
     bmi_status = BMI_FAILURE
  end select
  ```
- **Consistency**: All 10-12 known variable names in same order across all switch statements
- **Naming**: Use exact CSDMS Standard Names (e.g., `channel_water__volume_flow_rate`)

## Array Flattening

### Why Flatten?
- **BMI standard**: Requires 1D arrays (avoids row/column-major ambiguity between languages)
- **WRF-Hydro uses**: 2D arrays (IX, JX) for grids, 3D (IX, NSOIL, JX) for soil layers
- **Pattern**: Convert 2D/3D → 1D on output, 1D → 2D/3D on input

### Reshape Function Usage
- **Fortran built-in**: `reshape(array, shape)` flattens and reshapes
  ```fortran
  dest(1:this%ix*this%jx) = dble(reshape( &
       SFCRUNOFF(1:this%ix, 1:this%jx), [this%ix * this%jx]))
  ```
- **Pattern**: Extract slice (1:ix, 1:jx), reshape to [ix*jx] (1D), convert to double via `dble()`
- **Type conversion**: `dble()` converts single-precision REAL (4 bytes) to double (8 bytes)

### Safety Bounds
- **Slice extraction**: `array(1:ix, 1:jx)` avoids garbage dimensions
- **Min function**: `min(this%nlinks, size(x))` prevents writing past array bounds
  ```fortran
  do i = 1, min(this%nlinks, size(x))
     x(i) = dble(rt_domain(1)%CHLON(i))
  end do
  ```

## Pointer vs Allocatable

### Allocatable (Fortran ownership)
- **Pattern**: Used when BMI wrapper controls the array
  ```fortran
  double precision, allocatable :: sea_water_elevation(:,:)
  allocate(this%sea_water_elevation(this%ix, this%jx))
  deallocate(this%sea_water_elevation)
  ```
- **When to use**: Temporary buffers, coupling placeholders
- **Example**: `wrfhydro_get_double` has allocatable `dest(:)` to hold output

### Pointer (Borrowed references)
- **Pattern**: Used when BMI returns reference to data owned elsewhere
  ```fortran
  character(len=BMI_MAX_COMPONENT_NAME), pointer, intent(out) :: name
  name => component_name   ! Pointer assignment (=> not =)
  ```
- **When to use**: String/data return from BMI spec (zero-copy semantics)
- **Why: get_value_ptr_double returns BMI_FAILURE**: WRF-Hydro uses single-precision REAL (4 bytes), BMI expects double (8 bytes) — types don't match, so pointer can't be created safely

### Nullify Pattern
- **Defensive**: Always nullify pointers at declaration/start of procedure
  ```fortran
  nullify(comp_name)
  nullify(var_names)
  ```
- **Why**: Uninitialized Fortran pointers point to random memory (undefined behavior)
- **End of use**: Nullify again after use (optional but clean)
  ```fortran
  nullify(var_names)
  ```

---

*Convention analysis: 2026-02-23*
