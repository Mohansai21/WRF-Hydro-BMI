# Testing Patterns

**Analysis Date:** 2026-02-23

## Test Framework

### Runner
- **Framework**: Custom Fortran test driver (no external framework)
  - Reason: Fortran lacks a built-in standard testing library like pytest or JUnit
  - Approach: Write standalone programs that call functions and verify results
- **Programs**: Two test programs in `bmi_wrf_hydro/tests/`
  - `bmi_minimal_test.f90` (105 lines) — Quick smoke test, 6 steps + finalize
  - `bmi_wrf_hydro_test.f90` (1,777 lines) — Comprehensive test suite, 151 tests

### Build Configuration
- **Config file**: `bmi_wrf_hydro/build.sh` (bash script, not CMake-based)
- **Compiler**: gfortran 14.3.0
- **Compilation flags**: `-c -cpp -DWRF_HYDRO -DMPP_LAND`
  - `-c` = compile (no linking)
  - `-cpp` = C preprocessor (for conditional compilation)
  - `-DWRF_HYDRO` = define preprocessor symbol
  - `-DMPP_LAND` = MPI-related symbol
- **Linker**: mpif90 (MPI Fortran wrapper, handles MPI libraries)
- **Libraries**: WRF-Hydro (22 libraries, repeated 3x for circular deps), NetCDF, BMI Fortran

### Run Commands
```bash
# From bmi_wrf_hydro/ directory:
./build.sh                    # Build all (minimal + full test)
./build.sh minimal            # Build only minimal test
./build.sh full               # Build only full test
./build.sh clean              # Clean artifacts

# Run tests (requires successful build):
mpirun --oversubscribe -np 1 ./build/bmi_minimal_test   # ~30 seconds
mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test # ~2-3 minutes
```

### Assertion Library
- **No external library** — custom assertions via helper subroutines
- **Helpers**:
  - `check_status(status_val, test_name, tc, pc, fc)` — Verify BMI function returned success
  - `check_true(condition, test_name, tc, pc, fc)` — Verify a logical condition
- **Pattern**: Counters track total (`tc`), pass (`pc`), fail (`fc`) counts incremented by helpers

## Test File Organization

### Location
- **Path**: `bmi_wrf_hydro/tests/`
- **Pattern**: Co-located with source, not in separate `test/` directory
- **Rationale**: Small Fortran projects often keep tests adjacent to source

### Naming
- **Program names**: `{minimal|full}_test.f90` (lowercase, underscore-separated)
- **Standalone programs**: Each is a complete Fortran program, not a module
  - Pattern: `program test_name ... end program`
  - Unlike compiled libraries, these are executable entry points

### Structure
```
bmi_wrf_hydro/
├── src/
│   └── bmi_wrf_hydro.f90          (main wrapper module)
├── tests/
│   ├── bmi_minimal_test.f90       (quick smoke test)
│   ├── bmi_wrf_hydro_test.f90     (full test suite)
│   └── [test data files — config namelists created at runtime]
├── build/
│   ├── bmi_wrf_hydro.o            (compiled module)
│   ├── bmi_minimal_test.o         (compiled test program)
│   ├── bmi_wrf_hydro_test.o       (compiled test program)
│   ├── bmi_minimal_test           (executable)
│   └── bmi_wrf_hydro_test         (executable)
└── build.sh
```

## Test Structure

### Program Structure (Main Test)
The comprehensive test (`bmi_wrf_hydro_test.f90`) follows this structure:

```fortran
program bmi_wrf_hydro_test
  ! 1. Module imports (bmiwrfhydrof, bmif_2_0, mpi)
  ! 2. Variable declarations (type declarations, counters, arrays)
  ! 3. Initialize counters (test_count=0, pass_count=0, fail_count=0)
  ! 4. Nullify pointers (protection against undefined memory)
  ! 5. Create config file (write Fortran namelist to disk)
  ! 6. Print header (test framework banner)
  ! 7. SECTION 1: Control Tests (initialize, update, update_until, finalize)
  ! 8. SECTION 2: Model Info Tests (component name, item counts, variable names)
  ! 9. SECTION 3: Variable Info Tests (type, units, grid, itemsize, nbytes, location)
  ! 10. SECTION 4: Time Tests (start, end, current, step, units)
  ! 11. SECTION 5: Grid Tests (shape, spacing, origin, coordinates, counts)
  ! 12. SECTION 6: Get/Set Value Tests (actual data I/O for key variables)
  ! 13. SECTION 7: Edge Case Tests (invalid inputs, expected failures)
  ! 14. SECTION 8: Integration Tests (multi-step runs, output evolution)
  ! 15. Print summary (total/pass/fail counts)
  ! 16. Cleanup (delete config file, MPI_Finalize)
  ! 17. Exit with appropriate code (0=success, 1=failure)
  contains
    subroutine check_status(...)  ! Helper 1
    subroutine check_true(...)    ! Helper 2
  end program
```

### Minimal Test Structure
```fortran
program bmi_minimal_test
  ! Very short: just 6 update steps (full 6-hour Croton simulation)
  ! [1] Create config file
  ! [2] Call initialize()
  ! [3] Query info (component name, times)
  ! [4] Loop: update() × 6 times, report time after each
  ! [5] Call finalize()
  ! [6] MPI_Finalize()
end program
```

### Test Case Data
- **Test case**: Croton NY (Hurricane Irene 2011, August 28-30)
- **Duration**: 6 hours (21,600 seconds)
- **Timestep**: 3,600 seconds (1 hour)
- **Steps**: 6 updates to complete the simulation
- **Data location**: `WRF_Hydro_Run_Local/run/` directory
  - Contains namelists, forcing files, initial conditions
  - Specified in BMI config file: `wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/"`

## Patterns

### Setup/Initialization Pattern
```fortran
! Zero out counters
test_count = 0
pass_count = 0
fail_count = 0

! Nullify pointers
nullify(comp_name)
nullify(var_names)

! Create config file (Fortran namelist)
config_file = "bmi_config.nml"
open(unit=10, file=trim(config_file), status="replace", action="write")
write(10, '(A)') "&bmi_wrf_hydro_config"
write(10, '(A)') '  wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/"'
write(10, '(A)') "/"
close(10)

! Print header
write(0,*) "=============================================================="
write(0,*) "  Test Suite Header"
write(0,*) "=============================================================="
```

### Teardown/Finalization Pattern
```fortran
! Print summary
write(0,*) "  Total tests: ", test_count
write(0,*) "  Passed:      ", pass_count
write(0,*) "  Failed:      ", fail_count

! Cleanup temp files
open(unit=10, file=trim(config_file), status="old", iostat=status)
if (status == 0) close(10, status="delete")

! MPI cleanup (required because BMI wrapper doesn't call HYDRO_finish)
call MPI_Finalize(mpi_ierr)

! Exit with code
if (fail_count > 0) then
  stop 1  ! Exit code 1 = failure (for CI systems)
else
  stop 0  ! Exit code 0 = success
end if
```

### Assertion Pattern
```fortran
! Pattern 1: Check BMI return code
status = model%get_component_name(comp_name)
call check_status(status, "T01: get_component_name returns SUCCESS", &
     test_count, pass_count, fail_count)

! Pattern 2: Check a logical condition
call check_true(len_trim(comp_name) > 0, &
     "T01b: component name is non-empty", &
     test_count, pass_count, fail_count)

! Pattern 3: Check numeric value
call check_true(abs(start_time - 0.0d0) < 1.0d-6, &
     "T17b: start time == 0.0", &
     test_count, pass_count, fail_count)

! Pattern 4: Check string value
call check_true(trim(var_type_str) == "double precision", &
     "      -> type is 'double precision'", &
     test_count, pass_count, fail_count)

! Pattern 5: Check array condition
call check_true(allocated(var_names), &
     "T09b: output var names pointer is associated", &
     test_count, pass_count, fail_count)
```

### Helper Subroutine: check_status
```fortran
subroutine check_status(status_val, test_name, tc, pc, fc)
  integer, intent(in) :: status_val              ! BMI return code
  character(len=*), intent(in) :: test_name      ! Test description
  integer, intent(inout) :: tc, pc, fc           ! Test counters

  tc = tc + 1                                    ! Increment total

  if (status_val == BMI_SUCCESS) then
    pc = pc + 1                                  ! Increment pass
    write(0,*) "  PASS: ", trim(test_name)
  else
    fc = fc + 1                                  ! Increment fail
    write(0,*) "  FAIL: ", trim(test_name), " (status=", status_val, ")"
  end if
end subroutine
```

### Helper Subroutine: check_true
```fortran
subroutine check_true(condition, test_name, tc, pc, fc)
  logical, intent(in) :: condition               ! Boolean to test
  character(len=*), intent(in) :: test_name      ! Test description
  integer, intent(inout) :: tc, pc, fc           ! Test counters

  tc = tc + 1                                    ! Increment total

  if (condition) then
    pc = pc + 1                                  ! Increment pass
    write(0,*) "  PASS: ", trim(test_name)
  else
    fc = fc + 1                                  ! Increment fail
    write(0,*) "  FAIL: ", trim(test_name)
  end if
end subroutine
```

## Mocking

### Framework
- **No mocking library** — Fortran doesn't support dynamic mocking
- **Approach**: Use actual WRF-Hydro model (not mocked)
  - Tests call real `initialize()`, `update()`, `finalize()` linked against actual WRF-Hydro libraries
  - Mocking would require preprocessor `#ifdef` or separate compilation — overhead not justified

### What to Mock
- **Not used** in this project (tests run full model)
- **Could be used if needed**: Preprocessor conditionals (`#ifdef TEST_MOCK`)
  - Would require conditional WRF-Hydro init (return stub data instead of calling model)

### What NOT to Mock
- **Model execution**: Tests explicitly test the full initialize/run/finalize cycle
- **Data I/O**: Tests verify actual data comes from WRF-Hydro arrays (not stubbed)
- **Grid topology**: Tests read actual grid dimensions from model state

## Fixtures and Factories

### Test Data (Fixtures)
- **Pattern**: Created at runtime, not pre-built files
- **Config file**: Generated in each test program
  ```fortran
  open(unit=10, file=trim(config_file), status="replace", action="write")
  write(10, '(A)') "&bmi_wrf_hydro_config"
  write(10, '(A)') '  wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/"'
  write(10, '(A)') "/"
  close(10)
  ```
- **Real data**: Croton NY test case files reside in `WRF_Hydro_Run_Local/run/`
  - Pre-computed from NCAR WRF-Hydro v5.4.0 build
  - Not generated on the fly (too expensive)

### Factory Pattern
- **Not explicitly used** — Data creation is straightforward
- **Manual setup**: Test programs manually allocate and populate arrays as needed
  ```fortran
  integer, allocatable :: test_indices(:)
  allocate(test_indices(3))
  test_indices(1) = 0
  test_indices(2) = this%ix / 2
  test_indices(3) = this%ix * this%jx - 1
  ```

## Coverage

### Requirements
- **No explicit coverage target** mentioned in code
- **Implicit goal**: 100% (all 41 BMI functions must be tested)
- **Status**: 151 comprehensive tests covering:
  - Section 1: 4 control functions (initialize, update, update_until, finalize)
  - Section 2: 5 model info functions
  - Section 3: 6 variable info functions × 8 output variables + edge cases
  - Section 4: 5 time functions
  - Section 5: 17 grid functions for 3 grids
  - Section 6: Get/set value for key variables
  - Section 7: Edge cases (invalid names, invalid grids)
  - Section 8: Integration tests (multi-step evolution)

### View Coverage
- **Manual inspection**: Grep for function names in test file and verify they're called
  ```bash
  grep -c "model%get_component_name" bmi_wrf_hydro_test.f90  # Should be ≥ 1
  grep -c "model%initialize" bmi_wrf_hydro_test.f90          # Should be ≥ 1
  ```
- **Test results**: Final output shows pass/fail counts
  ```
  Total tests: 151
  Passed:      151
  Failed:      0
  >>> ALL TESTS PASSED <<<
  ```

## Test Types

### Unit Tests
- **Scope**: Individual BMI functions (e.g., `get_component_name`, `get_var_units`)
- **Approach**: Call function, check return value and output parameters
- **Example** (test T01 in comprehensive test):
  ```fortran
  status = model%get_component_name(comp_name)
  call check_status(status, "T01: get_component_name returns SUCCESS", ...)
  call check_true(len_trim(comp_name) > 0, "T01b: name is non-empty", ...)
  ```

### Integration Tests
- **Scope**: Full IRF (Initialize-Run-Finalize) lifecycle
- **Approach**: Call initialize → update × N → finalize, verify state consistency
- **Example** (Section 8 in comprehensive test):
  ```fortran
  ! Initialize
  status = model%initialize(trim(config_file))

  ! Run 6 steps
  do i = 1, 6
     status = model%update()
     status = model%get_value(streamflow_var, values)
  end do

  ! Finalize
  status = model%finalize()

  ! Verify: values changed over time
  call check_true(size(values_step1) == size(values_step6), ...)
  ```

### Smoke Tests
- **Scope**: Minimal happy-path coverage
- **Approach**: Quick sanity check that code compiles and runs
- **Example**: `bmi_minimal_test.f90` runs init/6-updates/finalize in ~30 seconds
- **Purpose**: Catch egregious build/link errors before comprehensive tests

## Edge Cases and Expected Failures

### Testing Invalid Input
```fortran
! Invalid variable name should return BMI_FAILURE
status = model%get_var_type("nonexistent_variable__does_not_exist", var_type_str)
call check_true(status == BMI_FAILURE, &
     "T16: get_var_type(invalid name) returns BMI_FAILURE", ...)
```

### Testing Type Mismatches
```fortran
! WRF-Hydro uses double precision only — int/float variants return FAILURE
status = model%get_value_int(var_name, int_values)
call check_true(status == BMI_FAILURE, &
     "TXX: get_value_int(double var) returns BMI_FAILURE", ...)
```

### Testing Uninitialized State
```fortran
! Create a new model instance, don't call initialize()
type(bmi_wrf_hydro) :: model2
integer :: status2

status2 = model2%update()  ! Should fail
call check_true(status2 == BMI_FAILURE, &
     "TXX: update() before initialize() returns BMI_FAILURE", ...)
```

### Testing Grid Operations
```fortran
! Grid 2 (channel vector) has no shape/spacing
status = model%get_grid_shape(GRID_CHANNEL, shape_arr)
call check_true(status == BMI_FAILURE, &
     "TXX: get_grid_shape(vector grid) returns BMI_FAILURE", ...)
```

## Common Test Patterns

### Multi-Variable Loop Testing
```fortran
! Test metadata for all 8 output variables
do i = 1, N_OUTPUT_VARS
  status = model%get_var_type(trim(output_var_list(i)), var_type_str)
  call check_status(status, &
       "T10." // char(ichar('0') + i) // ": get_var_type(" // &
       trim(output_var_list(i)) // ")", ...)

  call check_true(trim(var_type_str) == "double precision", ...)
end do
```

### Array Allocation and Bounds
```fortran
! Allocate result array based on queried size
integer :: grid_size_val
double precision, allocatable :: grid_x_arr(:)

status = model%get_grid_size(GRID_LSM, grid_size_val)
allocate(grid_x_arr(grid_size_val))

status = model%get_grid_x(GRID_LSM, grid_x_arr)
call check_status(status, ...)
deallocate(grid_x_arr)
```

### Time Evolution Verification
```fortran
double precision, allocatable :: values_step1(:), values_step6(:)

! Capture step 1 state
status = model%update()
allocate(values_step1(grid_size))
status = model%get_value(var_name, values_step1)

! Run to step 6
do i = 2, 6
  status = model%update()
end do

! Capture step 6 state
allocate(values_step6(grid_size))
status = model%get_value(var_name, values_step6)

! Verify they're different (model is advancing)
call check_true(any(values_step1 /= values_step6), &
     "TXX: output values change over time", ...)
```

## Build and Test Execution

### Build Process (from `build.sh`)
1. **Activate conda env**: `conda activate wrfhydro-bmi`
2. **Compile BMI wrapper**: `gfortran -c [flags] src/bmi_wrf_hydro.f90 → build/bmi_wrf_hydro.o`
3. **Compile test program**: `gfortran -c [flags] tests/bmi_minimal_test.f90 → build/bmi_minimal_test.o`
4. **Link executable**: `mpif90 -o build/bmi_minimal_test [objects] [libraries]`
5. **Repeat** for `bmi_wrf_hydro_test`

### Test Execution
```bash
cd /mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro
mpirun --oversubscribe -np 1 ./build/bmi_minimal_test     # Quick: ~30 sec
mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test   # Full: ~2-3 min
```

### Expected Output (Success)
```
==============================================================
  WRF-Hydro BMI 2.0 Comprehensive Test Driver
  Testing all 41+ BMI functions
  Test case: Croton NY (Hurricane Irene 2011)
==============================================================

============================================================
  SECTION 1: Control Tests
============================================================
  PASS: T01: initialize() returns BMI_SUCCESS
  PASS: T02: first update() succeeds
  PASS: T03: update_until(7200) advances to correct time
  ...
  Total tests: 151
  Passed:      151
  Failed:      0
  >>> ALL TESTS PASSED <<<
```

---

*Testing analysis: 2026-02-23*
