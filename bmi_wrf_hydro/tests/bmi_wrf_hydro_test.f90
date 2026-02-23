! ============================================================================
! FILE: bmi_wrf_hydro_test.f90
! ============================================================================
!
! PURPOSE:
!   Comprehensive test driver for the WRF-Hydro BMI (Basic Model Interface)
!   wrapper. This program exercises ALL 41+ BMI functions defined by the
!   CSDMS BMI 2.0 specification against the Croton NY (Hurricane Irene 2011)
!   test case.
!
! WHAT IS A TEST DRIVER?
!   A test driver is a standalone program that calls every function in a
!   module and checks whether the results are correct. Think of it like
!   pytest for Python or JUnit for Java -- but written directly in Fortran.
!   Unlike those frameworks, Fortran has no built-in test framework, so we
!   build our own PASS/FAIL reporting with helper subroutines.
!
! WHAT IS BMI?
!   BMI = Basic Model Interface. It is a standardized set of 41+ functions
!   that any Earth-system model can implement so that other models (or
!   frameworks like PyMT) can control it without knowing its internals.
!   Think of BMI like an API contract: initialize, update, get_value, etc.
!   See: https://bmi.readthedocs.io
!
! STRUCTURE:
!   Section 1: Control Tests       -- initialize, update, update_until, finalize
!   Section 2: Model Info Tests    -- component name, item counts, var names
!   Section 3: Variable Info Tests -- var type, units, grid, itemsize, nbytes, location
!   Section 4: Time Tests          -- start/end/current time, time step, time units
!   Section 5: Grid Tests          -- grid type/rank/size/shape/spacing for 3 grids
!   Section 6: Get/Set Value Tests -- get_value, set_value for key variables
!   Section 7: Edge Case Tests     -- invalid names, invalid grids, expected failures
!   Section 8: Integration Tests   -- full IRF cycle, output evolution over time
!
! HOW TO COMPILE (once bmi_wrf_hydro.f90 is ready):
!   gfortran -c -I$CONDA_PREFIX/include bmi_wrf_hydro.f90
!   gfortran -o bmi_wrf_hydro_test bmi_wrf_hydro_test.f90 bmi_wrf_hydro.o \
!     -I$CONDA_PREFIX/include -L$CONDA_PREFIX/lib -lbmif <WRF-Hydro libs>
!
! HOW TO RUN:
!   ./bmi_wrf_hydro_test
!
! EXPECTED OUTPUT:
!   A list of PASS/FAIL for each test, followed by a summary count.
!   Target: ~70 tests, ALL should pass when the BMI wrapper is correct.
!
! FORTRAN CONCEPTS USED (for newcomers):
!   - "program"       : The main entry point, like Python's "if __name__..."
!   - "use"           : Import a module (like Python's "import")
!   - "implicit none"  : Forces you to declare all variables (prevents typos)
!   - "type(...)"      : Create an instance of a derived type (like a class)
!   - "allocatable"    : Array whose size is determined at runtime (like list)
!   - "pointer"        : A reference to data owned by someone else (like a ref)
!   - "contains"       : Starts the section of internal subroutines
!   - "intent(in/out)" : Documents whether a parameter is read, written, or both
!   - "character(len=*)" : A string whose length is determined by the caller
!   - "double precision" : 64-bit floating point (like Python's float / np.float64)
!   - "d0" suffix      : Marks a literal as double precision (e.g., 3600.0d0)
!   - ".true. / .false." : Fortran's boolean values (like Python's True/False)
!   - "trim()"         : Removes trailing spaces from a string (Fortran pads strings)
!   - "len_trim()"     : Returns the length of a string without trailing spaces
!   - "allocated()"    : Checks if an allocatable array has been allocated
!   - "associated()"   : Checks if a pointer is pointing to something
!   - "deallocate()"   : Frees memory for an allocatable array
!
! AUTHOR: WRF-Hydro BMI Project
! DATE:   February 2026
! ============================================================================

program bmi_wrf_hydro_test

  ! --------------------------------------------------------------------------
  ! MODULE IMPORTS
  ! --------------------------------------------------------------------------
  ! "use" is Fortran's version of Python's "import". We need three modules:
  !
  ! 1. bmiwrfhydrof  -- Our BMI wrapper module. Contains the bmi_wrf_hydro type
  !                     with all 41+ BMI functions. This is the code we test.
  !
  ! 2. bmif_2_0      -- The BMI Fortran specification module (from bmi-fortran
  !                     package). Provides constants like BMI_SUCCESS (=0),
  !                     BMI_FAILURE (=1), and BMI_MAX_VAR_NAME (=2048).
  !                     Think of it as the "interface definition" or "abstract
  !                     base class" that bmi_wrf_hydro must implement.
  ! --------------------------------------------------------------------------
  use bmiwrfhydrof                  ! Our BMI wrapper module for WRF-Hydro
  use bmif_2_0                      ! BMI constants and abstract interface
  use mpi                           ! MPI for clean shutdown (MPI_Finalize)
  implicit none                     ! CRITICAL: forces all variables to be declared

  ! ==========================================================================
  ! VARIABLE DECLARATIONS
  ! ==========================================================================
  ! In Fortran, ALL variables must be declared before any executable code.
  ! This is different from Python where you can create variables anywhere.
  ! Think of this section as defining your "schema" before running code.
  ! ==========================================================================

  ! --- The BMI model instance ---
  ! This is like creating an object:  model = BmiWrfHydro()  in Python.
  ! "type(bmi_wrf_hydro)" is the derived type (class) defined in bmiwrfhydrof.
  ! It contains all the model state and the 41+ BMI methods.
  type(bmi_wrf_hydro) :: model

  ! --- Test bookkeeping variables ---
  ! We track how many tests we run, how many pass, how many fail.
  ! These are plain integers -- Fortran's "int" type, like Python's int.
  integer :: status                    ! Return value from each BMI call (0=success, 1=failure)
  integer :: test_count                ! Total number of tests executed
  integer :: pass_count                ! Number of tests that passed
  integer :: fail_count                ! Number of tests that failed

  ! --- Configuration ---
  ! BMI's initialize() takes a config file path as a string.
  ! character(len=512) means a string that can hold up to 512 characters.
  ! Fortran strings are FIXED LENGTH and padded with spaces on the right.
  ! We use trim() later to remove those trailing spaces.
  character(len=512) :: config_file

  ! --- Variables for Model Info tests (Section 2) ---
  ! "pointer" means this variable will point to data owned by the BMI module,
  ! not a copy. The BMI spec requires get_component_name to return a pointer.
  ! Think of it like a Python reference -- changes to the target affect the pointer.
  character(len=BMI_MAX_COMPONENT_NAME), pointer :: comp_name

  ! Pointer array for variable names. BMI returns a pointer to an array of
  ! strings. Each string can be up to BMI_MAX_VAR_NAME (2048) chars long.
  ! The (:) means it is a 1-D array of unknown size (determined at runtime).
  character(len=BMI_MAX_VAR_NAME), pointer :: var_names(:)

  ! Item counts -- how many input/output variables the model exposes.
  integer :: input_count, output_count

  ! --- Variables for Variable Info tests (Section 3) ---
  ! These hold the results from get_var_type, get_var_units, etc.
  character(len=BMI_MAX_TYPE_NAME) :: var_type_str
  character(len=BMI_MAX_UNITS_NAME) :: var_units_str
  character(len=BMI_MAX_VAR_NAME) :: var_location_str
  integer :: grid_id, var_itemsize, var_nbytes

  ! --- Variables for Time tests (Section 4) ---
  ! "double precision" is 64-bit float, like Python's float or numpy's float64.
  ! BMI uses double precision for all time values (in seconds).
  double precision :: current_time, start_time, end_time, time_step
  character(len=BMI_MAX_UNITS_NAME) :: time_units_str

  ! --- Variables for Grid tests (Section 5) ---
  character(len=BMI_MAX_TYPE_NAME) :: grid_type_str
  integer :: grid_rank, grid_size_val
  integer :: node_count, edge_count, face_count
  ! "allocatable" means the array size is not known at compile time.
  ! We will allocate(array(N)) once we know N from get_grid_rank/size.
  ! This is like Python's list -- dynamically sized.
  integer, allocatable :: grid_shape_arr(:)
  double precision, allocatable :: grid_spacing_arr(:)
  double precision, allocatable :: grid_origin_arr(:)
  double precision, allocatable :: grid_x_arr(:), grid_y_arr(:)

  ! --- Variables for Get/Set Value tests (Section 6) ---
  double precision, allocatable :: values(:)
  double precision, allocatable :: values_copy(:)
  double precision, allocatable :: values_step1(:), values_step6(:)
  integer, allocatable :: test_indices(:)
  double precision, allocatable :: subset_values(:)
  double precision, allocatable :: set_src(:)

  ! For testing int/float type returns (should fail with BMI_FAILURE)
  integer, allocatable :: int_values(:)
  real, allocatable :: float_values(:)

  ! For get_value_ptr
  double precision, pointer :: ptr_values(:)

  ! --- Loop counters and temporaries ---
  ! "i", "j", "k" are loop counters. "n" is a temporary for sizes.
  ! These are plain integers, used throughout the test.
  integer :: i, j, k, n, mpi_ierr
  double precision :: dt, expected_time

  ! --- Output variable names (hardcoded for testing) ---
  ! We store the 8 output variable names as an array of strings.
  ! "parameter" means these are compile-time constants (like Python's CONST).
  ! Each string is exactly BMI_MAX_VAR_NAME characters, padded with spaces.
  integer, parameter :: N_OUTPUT_VARS = 8
  character(len=BMI_MAX_VAR_NAME), dimension(N_OUTPUT_VARS) :: output_var_list

  ! Expected grid IDs for each output variable (in same order as output_var_list)
  integer, dimension(N_OUTPUT_VARS) :: expected_grid_ids

  ! --- Input variable names ---
  integer, parameter :: N_INPUT_VARS = 4
  character(len=BMI_MAX_VAR_NAME), dimension(N_INPUT_VARS) :: input_var_list

  ! ==========================================================================
  ! INITIALIZATION: Set up test data and counters
  ! ==========================================================================

  ! Zero out the test counters. In Fortran, local variables are NOT
  ! automatically initialized to zero (unlike Python). You must set them.
  test_count = 0
  pass_count = 0
  fail_count = 0

  ! Nullify pointers -- Fortran pointers start in an "undefined" state,
  ! which is dangerous. nullify() sets them to "not pointing at anything",
  ! which is safe. It is like setting a Python variable to None.
  nullify(comp_name)
  nullify(var_names)
  nullify(ptr_values)

  ! --------------------------------------------------------------------------
  ! Define the output variable names we expect from WRF-Hydro BMI.
  ! These are CSDMS Standard Names -- a naming convention that uses
  ! <object>__<quantity> with double underscores. This lets different models
  ! share data using a common vocabulary.
  !
  ! Example: "channel_water__volume_flow_rate" means:
  !   object = channel_water (water in river channels)
  !   quantity = volume_flow_rate (how fast it flows, in m3/s)
  ! --------------------------------------------------------------------------
  output_var_list(1) = "channel_water__volume_flow_rate"
  output_var_list(2) = "land_surface_water__depth"
  output_var_list(3) = "soil_water__volume_fraction"
  output_var_list(4) = "snowpack__liquid-equivalent_depth"
  output_var_list(5) = "land_surface_water__evaporation_volume_flux"
  output_var_list(6) = "land_surface_water__runoff_volume_flux"
  output_var_list(7) = "soil_water__domain_time_integral_of_baseflow_volume_flux"
  output_var_list(8) = "land_surface_air__temperature"

  ! Grid IDs: which grid each variable lives on.
  ! Grid 0 = 1km uniform rectilinear (Noah-MP land surface)
  ! Grid 1 = 250m uniform rectilinear (terrain routing)
  ! Grid 2 = vector/network (channel routing)
  expected_grid_ids(1) = 2   ! streamflow -> channel network
  expected_grid_ids(2) = 1   ! surface water depth -> 250m routing grid
  expected_grid_ids(3) = 0   ! soil moisture -> 1km land grid
  expected_grid_ids(4) = 0   ! snow -> 1km land grid
  expected_grid_ids(5) = 0   ! evapotranspiration -> 1km land grid
  expected_grid_ids(6) = 0   ! surface runoff -> 1km land grid
  expected_grid_ids(7) = 0   ! baseflow -> 1km land grid
  expected_grid_ids(8) = 0   ! temperature -> 1km land grid

  ! Define the input variable names we expect.
  input_var_list(1) = "atmosphere_water__precipitation_leq-volume_flux"
  input_var_list(2) = "land_surface_air__temperature"
  input_var_list(3) = "sea_water_surface__elevation"
  input_var_list(4) = "sea_water__x_velocity"

  ! --------------------------------------------------------------------------
  ! Create a BMI configuration file for the test.
  ! --------------------------------------------------------------------------
  ! BMI's initialize() function takes a path to a configuration file.
  ! For WRF-Hydro, this config tells the BMI wrapper where to find the
  ! WRF-Hydro run directory (which contains namelists, forcing data, etc.).
  !
  ! We create a simple Fortran namelist file. A namelist is a Fortran-native
  ! config format that looks like:
  !   &group_name
  !     key = "value"
  !   /
  !
  ! The "&" starts the group, and "/" ends it. This is read with Fortran's
  ! built-in READ(unit, NML=group_name) statement.
  !
  ! "open(unit=10, ...)" opens file handle 10. Fortran uses integer "unit
  ! numbers" instead of file objects. Think of it like:
  !   f = open("bmi_config.nml", "w")   in Python.
  !
  ! "status='replace'" means overwrite if the file already exists.
  ! --------------------------------------------------------------------------
  config_file = "bmi_config.nml"

  write(0,*) "--- Creating BMI config file for testing ---"
  open(unit=10, file=trim(config_file), status="replace", action="write")
  write(10, '(A)') "&bmi_wrf_hydro_config"
  write(10, '(A)') '  wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/"'
  write(10, '(A)') "/"
  close(10)
  write(0,*) "  Config file created: ", trim(config_file)
  write(0,*)

  ! ==========================================================================
  ! PRINT TEST HEADER
  ! ==========================================================================
  write(0,*) "=============================================================="
  write(0,*) "  WRF-Hydro BMI 2.0 Comprehensive Test Driver"
  write(0,*) "  Testing all 41+ BMI functions"
  write(0,*) "  Test case: Croton NY (Hurricane Irene 2011)"
  write(0,*) "=============================================================="
  write(0,*)

  ! **************************************************************************
  ! SECTION 1: CONTROL TESTS (Initialize-Run-Finalize)
  ! **************************************************************************
  !
  ! The BMI "IRF" pattern is the foundation of the interface:
  !   initialize() -- Load config, allocate memory, read initial conditions
  !   update()     -- Advance the model by exactly ONE time step
  !   update_until(t) -- Advance the model until time reaches t
  !   finalize()   -- Clean up: free memory, close files, flush output
  !
  ! These MUST be called in order: initialize first, then updates, then
  ! finalize. This is the "lifecycle" of a BMI model -- similar to how a
  ! PyTorch model has __init__(), forward(), and you must init before forward.
  !
  ! The key insight: the CALLER controls the time loop, not the model.
  ! WRF-Hydro normally has its own internal time loop (in main_hrldas_driver.F).
  ! Our BMI wrapper decomposes that into single-step calls so PyMT can
  ! interleave WRF-Hydro steps with SCHISM steps.
  ! **************************************************************************
  write(0,*) "=============================================================="
  write(0,*) "  SECTION 1: Control Tests (IRF Pattern)"
  write(0,*) "=============================================================="

  ! --------------------------------------------------------------------------
  ! TEST 1: initialize
  ! --------------------------------------------------------------------------
  ! What: Call initialize() with our config file.
  ! Why:  This is the first thing any BMI caller does. It must succeed
  !       before any other BMI function can be called.
  ! How:  The wrapper reads the config file, then calls WRF-Hydro's
  !       land_driver_ini() and HYDRO_ini() internally.
  ! Pass: Returns BMI_SUCCESS (=0)
  ! --------------------------------------------------------------------------
  status = model%initialize(trim(config_file))
  call check_status(status, "T01: initialize with config file", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST 2: update (advance one time step)
  ! --------------------------------------------------------------------------
  ! What: Advance the model by exactly one time step (typically 3600s = 1hr).
  ! Why:  This is how PyMT controls the model -- one step at a time.
  ! How:  The wrapper calls land_driver_exe() + HYDRO_exe() for one step.
  ! Pass: Returns BMI_SUCCESS (=0)
  ! --------------------------------------------------------------------------
  status = model%update()
  call check_status(status, "T02: update (one time step)", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST 3: update_until (advance to a specific time)
  ! --------------------------------------------------------------------------
  ! What: Advance the model until the current time reaches 7200.0 seconds.
  ! Why:  Some callers want to jump ahead by multiple steps at once.
  !       update_until internally calls update() in a loop until the target
  !       time is reached.
  ! How:  If current_time is 3600 and dt is 3600, this will do one more step.
  !       The "d0" suffix marks 7200.0 as double precision (64-bit float).
  ! Pass: Returns BMI_SUCCESS (=0)
  ! --------------------------------------------------------------------------
  status = model%update_until(7200.0d0)
  call check_status(status, "T03: update_until(7200.0)", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST 4: finalize
  ! --------------------------------------------------------------------------
  ! What: Clean up the model -- free memory, close files, flush buffers.
  ! Why:  Every initialize() must have a matching finalize(). Failing to
  !       finalize can leak memory or leave files unclosed.
  ! How:  The wrapper calls HYDRO_finish() and deallocates all arrays.
  ! Pass: Returns BMI_SUCCESS (=0)
  ! --------------------------------------------------------------------------
  status = model%finalize()
  call check_status(status, "T04: finalize", &
       test_count, pass_count, fail_count)

  write(0,*)

  ! **************************************************************************
  ! RE-INITIALIZE FOR REMAINING TESTS
  ! **************************************************************************
  ! We finalized above, so we need a fresh model instance for the next tests.
  ! BMI spec allows re-initialization after finalize.
  !
  ! NOTE: In Fortran, when you call initialize() with intent(out), the
  ! compiler may re-create the object. This is fine -- it is a fresh start.
  ! **************************************************************************
  write(0,*) "--- Re-initializing model for remaining tests ---"
  status = model%initialize(trim(config_file))
  if (status /= BMI_SUCCESS) then
    write(0,*) "  FATAL: Could not re-initialize model. Aborting tests."
    stop 1
  end if
  write(0,*) "  Model re-initialized successfully."
  write(0,*)

  ! Advance one step so we have non-trivial state for variable/value tests
  status = model%update()
  if (status /= BMI_SUCCESS) then
    write(0,*) "  FATAL: Could not update model. Aborting tests."
    stop 1
  end if
  write(0,*) "  Model advanced one time step for state-dependent tests."
  write(0,*)

  ! **************************************************************************
  ! SECTION 2: MODEL INFO TESTS
  ! **************************************************************************
  !
  ! These functions provide metadata about the model:
  !   get_component_name  -- Human-readable model name
  !   get_input_item_count / get_output_item_count -- How many variables?
  !   get_input_var_names / get_output_var_names  -- What are they called?
  !
  ! This is how a coupling framework like PyMT discovers what a model
  ! can offer. It is like introspection / reflection in Python.
  ! **************************************************************************
  write(0,*) "=============================================================="
  write(0,*) "  SECTION 2: Model Info Tests"
  write(0,*) "=============================================================="

  ! --------------------------------------------------------------------------
  ! TEST 5: get_component_name
  ! --------------------------------------------------------------------------
  ! What: Get the human-readable name of the model.
  ! Why:  PyMT uses this to identify models in its registry.
  ! Expect: A string containing "WRF-Hydro" (or similar).
  ! Note: comp_name is a POINTER -- it points to a string owned by the
  !       BMI module, not a copy. This is the BMI spec's design choice.
  ! --------------------------------------------------------------------------
  status = model%get_component_name(comp_name)
  call check_status(status, "T05: get_component_name returns SUCCESS", &
       test_count, pass_count, fail_count)

  ! Also verify the name contains "WRF" (case-sensitive check).
  ! index() returns the position of a substring, or 0 if not found.
  ! This is like Python's "WRF" in name -- but Fortran uses index().
  if (associated(comp_name)) then
    call check_true(index(comp_name, "WRF") > 0, &
         "T05b: component name contains 'WRF'", &
         test_count, pass_count, fail_count)
    write(0,*) "       Component name = '", trim(comp_name), "'"
  else
    call check_true(.false., &
         "T05b: component name pointer is associated", &
         test_count, pass_count, fail_count)
  end if

  ! --------------------------------------------------------------------------
  ! TEST 6: get_input_item_count
  ! --------------------------------------------------------------------------
  ! What: Count how many input variables the model accepts.
  ! Why:  The caller needs to know how many variables it can push into
  !       the model (e.g., precipitation, tidal elevation).
  ! Expect: 4 (precipitation, temperature, sea water elevation, velocity)
  ! --------------------------------------------------------------------------
  status = model%get_input_item_count(input_count)
  call check_status(status, "T06: get_input_item_count returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(input_count == N_INPUT_VARS, &
       "T06b: input item count == 4", &
       test_count, pass_count, fail_count)
  write(0,*) "       Input item count =", input_count

  ! --------------------------------------------------------------------------
  ! TEST 7: get_output_item_count
  ! --------------------------------------------------------------------------
  ! What: Count how many output variables the model produces.
  ! Why:  The caller needs to know how many variables it can read from
  !       the model (e.g., streamflow, soil moisture, snow).
  ! Expect: 8 (streamflow, surface water, soil moisture, snow, ET, runoff,
  !            baseflow, temperature)
  ! --------------------------------------------------------------------------
  status = model%get_output_item_count(output_count)
  call check_status(status, "T07: get_output_item_count returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(output_count == N_OUTPUT_VARS, &
       "T07b: output item count == 8", &
       test_count, pass_count, fail_count)
  write(0,*) "       Output item count =", output_count

  ! --------------------------------------------------------------------------
  ! TEST 8: get_input_var_names
  ! --------------------------------------------------------------------------
  ! What: Get the list of input variable names as an array of strings.
  ! Why:  The caller needs actual names to call get_value/set_value on.
  ! Expect: Array of N_INPUT_VARS strings, each non-empty.
  ! Note: var_names is a pointer to an array -- the BMI module owns the data.
  ! --------------------------------------------------------------------------
  status = model%get_input_var_names(var_names)
  call check_status(status, "T08: get_input_var_names returns SUCCESS", &
       test_count, pass_count, fail_count)

  if (associated(var_names)) then
    call check_true(len_trim(var_names(1)) > 0, &
         "T08b: first input var name is non-empty", &
         test_count, pass_count, fail_count)
    write(0,*) "       Input variable names:"
    do i = 1, min(size(var_names), N_INPUT_VARS)
      write(0,*) "         [", i, "] ", trim(var_names(i))
    end do
  else
    call check_true(.false., &
         "T08b: input var names pointer is associated", &
         test_count, pass_count, fail_count)
  end if
  nullify(var_names)  ! Clear pointer for reuse

  ! --------------------------------------------------------------------------
  ! TEST 9: get_output_var_names
  ! --------------------------------------------------------------------------
  ! What: Get the list of output variable names.
  ! Why:  Same as input names -- the caller needs these to get_value().
  ! Expect: Array of N_OUTPUT_VARS strings, each non-empty.
  ! --------------------------------------------------------------------------
  status = model%get_output_var_names(var_names)
  call check_status(status, "T09: get_output_var_names returns SUCCESS", &
       test_count, pass_count, fail_count)

  if (associated(var_names)) then
    call check_true(len_trim(var_names(1)) > 0, &
         "T09b: first output var name is non-empty", &
         test_count, pass_count, fail_count)
    write(0,*) "       Output variable names:"
    do i = 1, min(size(var_names), N_OUTPUT_VARS)
      write(0,*) "         [", i, "] ", trim(var_names(i))
    end do
  else
    call check_true(.false., &
         "T09b: output var names pointer is associated", &
         test_count, pass_count, fail_count)
  end if
  nullify(var_names)

  write(0,*)

  ! **************************************************************************
  ! SECTION 3: VARIABLE INFO TESTS
  ! **************************************************************************
  !
  ! For each variable, BMI provides metadata:
  !   get_var_type     -- Data type as a string ("double precision", "real", "integer")
  !   get_var_units    -- Physical units ("m3 s-1", "m", "K", etc.)
  !   get_var_grid     -- Which grid this variable lives on (0, 1, or 2)
  !   get_var_itemsize -- Bytes per element (8 for double precision)
  !   get_var_nbytes   -- Total bytes = itemsize * grid_size
  !   get_var_location -- Where on the grid: "node", "edge", or "face"
  !
  ! We test each output variable for type, grid, and units.
  ! All WRF-Hydro BMI variables are "double precision" (8 bytes per element).
  ! **************************************************************************
  write(0,*) "=============================================================="
  write(0,*) "  SECTION 3: Variable Info Tests"
  write(0,*) "=============================================================="

  ! --------------------------------------------------------------------------
  ! TEST BLOCK: get_var_type for all output variables
  ! --------------------------------------------------------------------------
  ! What: Verify that every output variable reports type = "double precision".
  ! Why:  The BMI spec requires a string type name. PyMT uses this to know
  !       how to interpret the raw bytes. Our wrapper stores everything as
  !       double precision (64-bit float) for consistency.
  ! --------------------------------------------------------------------------
  do i = 1, N_OUTPUT_VARS
    status = model%get_var_type(trim(output_var_list(i)), var_type_str)
    call check_status(status, &
         "T10." // char(ichar('0') + i) // ": get_var_type(" // &
         trim(output_var_list(i)) // ")", &
         test_count, pass_count, fail_count)

    ! Verify the returned type is "double precision"
    call check_true(trim(var_type_str) == "double precision", &
         "      -> type is 'double precision'", &
         test_count, pass_count, fail_count)
  end do

  ! --------------------------------------------------------------------------
  ! TEST BLOCK: get_var_grid for all output variables
  ! --------------------------------------------------------------------------
  ! What: Verify that each variable maps to the correct grid ID.
  ! Why:  Grid IDs tell the caller which grid's shape/spacing/coordinates
  !       to use when interpreting the flattened 1D value array.
  !
  ! WRF-Hydro has 3 grids:
  !   Grid 0 = 1km uniform rectilinear  (Noah-MP land surface variables)
  !   Grid 1 = 250m uniform rectilinear (terrain routing variables)
  !   Grid 2 = vector/network           (channel routing -- river reaches)
  ! --------------------------------------------------------------------------
  do i = 1, N_OUTPUT_VARS
    status = model%get_var_grid(trim(output_var_list(i)), grid_id)
    call check_status(status, &
         "T11." // char(ichar('0') + i) // ": get_var_grid(" // &
         trim(output_var_list(i)) // ")", &
         test_count, pass_count, fail_count)

    call check_true(grid_id == expected_grid_ids(i), &
         "      -> grid ID matches expected", &
         test_count, pass_count, fail_count)
    write(0,*) "       ", trim(output_var_list(i)), " -> grid", grid_id
  end do

  ! --------------------------------------------------------------------------
  ! TEST BLOCK: get_var_units for all output variables
  ! --------------------------------------------------------------------------
  ! What: Verify that each variable has a non-empty units string.
  ! Why:  Units are critical for coupling. If WRF-Hydro reports discharge
  !       in m3/s but SCHISM expects L/s, the coupling would be wrong.
  !       CSDMS uses UDUNITS-compatible strings like "m3 s-1", "m", "K".
  ! --------------------------------------------------------------------------
  do i = 1, N_OUTPUT_VARS
    status = model%get_var_units(trim(output_var_list(i)), var_units_str)
    call check_status(status, &
         "T12." // char(ichar('0') + i) // ": get_var_units(" // &
         trim(output_var_list(i)) // ")", &
         test_count, pass_count, fail_count)

    call check_true(len_trim(var_units_str) > 0, &
         "      -> units string is non-empty", &
         test_count, pass_count, fail_count)
    write(0,*) "       ", trim(output_var_list(i)), " -> '", &
         trim(var_units_str), "'"
  end do

  ! --------------------------------------------------------------------------
  ! TEST: get_var_itemsize for a representative variable
  ! --------------------------------------------------------------------------
  ! What: Check that itemsize = 8 (bytes per element for double precision).
  ! Why:  8 bytes = 64 bits = double precision. This is how much memory
  !       one number takes. PyMT uses this to allocate the right buffer.
  !       Think of it like np.float64().nbytes == 8 in NumPy.
  ! --------------------------------------------------------------------------
  status = model%get_var_itemsize(trim(output_var_list(1)), var_itemsize)
  call check_status(status, "T13: get_var_itemsize(streamflow)", &
       test_count, pass_count, fail_count)
  call check_true(var_itemsize == 8, &
       "T13b: itemsize == 8 (double precision)", &
       test_count, pass_count, fail_count)
  write(0,*) "       itemsize =", var_itemsize, " bytes"

  ! --------------------------------------------------------------------------
  ! TEST: get_var_nbytes for a representative variable
  ! --------------------------------------------------------------------------
  ! What: Check that nbytes > 0 (total memory used by the variable).
  ! Why:  nbytes = itemsize * grid_size. The caller allocates a buffer
  !       this large to receive the data from get_value().
  ! --------------------------------------------------------------------------
  status = model%get_var_nbytes(trim(output_var_list(1)), var_nbytes)
  call check_status(status, "T14: get_var_nbytes(streamflow)", &
       test_count, pass_count, fail_count)
  call check_true(var_nbytes > 0, &
       "T14b: nbytes > 0", &
       test_count, pass_count, fail_count)
  write(0,*) "       nbytes =", var_nbytes, " bytes"

  ! --------------------------------------------------------------------------
  ! TEST: get_var_location for a representative variable
  ! --------------------------------------------------------------------------
  ! What: Check that location = "node".
  ! Why:  In BMI, data can live at grid "node"s, "edge"s, or "face"s.
  !       Most WRF-Hydro variables are defined at grid nodes (cell centers).
  !       This is important for grid mapping during coupling.
  ! --------------------------------------------------------------------------
  status = model%get_var_location(trim(output_var_list(1)), var_location_str)
  call check_status(status, "T15: get_var_location(streamflow)", &
       test_count, pass_count, fail_count)
  call check_true(trim(var_location_str) == "node", &
       "T15b: location == 'node'", &
       test_count, pass_count, fail_count)
  write(0,*) "       location = '", trim(var_location_str), "'"

  ! --------------------------------------------------------------------------
  ! TEST: get_var_type for invalid variable name -> BMI_FAILURE
  ! --------------------------------------------------------------------------
  ! What: Ask for a variable that does not exist.
  ! Why:  The wrapper must gracefully handle bad input and return BMI_FAILURE,
  !       NOT crash. This is defensive programming / error handling.
  ! --------------------------------------------------------------------------
  status = model%get_var_type("nonexistent_variable__does_not_exist", &
       var_type_str)
  call check_true(status == BMI_FAILURE, &
       "T16: get_var_type(invalid name) returns BMI_FAILURE", &
       test_count, pass_count, fail_count)

  write(0,*)

  ! **************************************************************************
  ! SECTION 4: TIME TESTS
  ! **************************************************************************
  !
  ! BMI tracks time in the model's native units (seconds for WRF-Hydro):
  !   get_start_time   -- When the simulation starts (typically 0.0)
  !   get_end_time     -- When the simulation ends
  !   get_current_time -- Where we are right now
  !   get_time_step    -- How big each step is (3600s = 1hr for WRF-Hydro)
  !   get_time_units   -- The unit string ("s" for seconds)
  !
  ! Time is always relative to the start of the simulation, in seconds.
  ! This is simpler than dealing with absolute dates. The BMI caller
  ! (e.g., PyMT) can convert to real dates if needed.
  ! **************************************************************************
  write(0,*) "=============================================================="
  write(0,*) "  SECTION 4: Time Tests"
  write(0,*) "=============================================================="

  ! --------------------------------------------------------------------------
  ! TEST: get_start_time
  ! --------------------------------------------------------------------------
  ! What: Get the simulation start time.
  ! Expect: 0.0 (simulations start at time zero in BMI convention).
  ! --------------------------------------------------------------------------
  status = model%get_start_time(start_time)
  call check_status(status, "T17: get_start_time returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(abs(start_time - 0.0d0) < 1.0d-6, &
       "T17b: start time == 0.0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Start time =", start_time, " seconds"

  ! --------------------------------------------------------------------------
  ! TEST: get_time_step
  ! --------------------------------------------------------------------------
  ! What: Get the model's time step size.
  ! Expect: > 0.0 (should be 3600.0 seconds for WRF-Hydro Croton case).
  ! Why:  The caller uses this to know how much time passes per update().
  ! --------------------------------------------------------------------------
  status = model%get_time_step(time_step)
  call check_status(status, "T18: get_time_step returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(time_step > 0.0d0, &
       "T18b: time step > 0.0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Time step =", time_step, " seconds"

  ! --------------------------------------------------------------------------
  ! TEST: get_time_units
  ! --------------------------------------------------------------------------
  ! What: Get the time units as a string.
  ! Expect: "s" (seconds). UDUNITS-compatible format.
  ! --------------------------------------------------------------------------
  status = model%get_time_units(time_units_str)
  call check_status(status, "T19: get_time_units returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(trim(time_units_str) == "s", &
       "T19b: time units == 's'", &
       test_count, pass_count, fail_count)
  write(0,*) "       Time units = '", trim(time_units_str), "'"

  ! --------------------------------------------------------------------------
  ! TEST: get_current_time
  ! --------------------------------------------------------------------------
  ! What: Get the current simulation time.
  ! Expect: >= 0.0 (we already did 2 updates, so it should be 2*dt).
  !         But we re-initialized and did 1 update, so current_time = 1*dt.
  ! --------------------------------------------------------------------------
  status = model%get_current_time(current_time)
  call check_status(status, "T20: get_current_time returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(current_time >= 0.0d0, &
       "T20b: current time >= 0.0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Current time =", current_time, " seconds"

  ! --------------------------------------------------------------------------
  ! TEST: get_end_time
  ! --------------------------------------------------------------------------
  ! What: Get the simulation end time.
  ! Expect: > 0.0 (Croton case runs for 6 hours = 21600 seconds).
  ! Why:  The caller uses this to know when to stop the time loop.
  ! --------------------------------------------------------------------------
  status = model%get_end_time(end_time)
  call check_status(status, "T21: get_end_time returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(end_time > 0.0d0, &
       "T21b: end time > 0.0", &
       test_count, pass_count, fail_count)
  write(0,*) "       End time =", end_time, " seconds"

  write(0,*)

  ! **************************************************************************
  ! SECTION 5: GRID TESTS
  ! **************************************************************************
  !
  ! WRF-Hydro has 3 computational grids:
  !
  ! Grid 0: "uniform_rectilinear" (1km)
  !   - The Noah-MP land surface model grid
  !   - rank=2 (2D: rows x cols), e.g., 15x16 for Croton
  !   - Variables: soil moisture, temperature, snow, ET, runoff, baseflow
  !   - Spacing: [1000.0, 1000.0] meters
  !
  ! Grid 1: "uniform_rectilinear" (250m)
  !   - The terrain routing grid (4x finer than Grid 0)
  !   - rank=2 (2D), e.g., 60x64 for Croton
  !   - Variables: surface water depth
  !   - Spacing: [250.0, 250.0] meters
  !
  ! Grid 2: "vector" (channel network)
  !   - The river channel routing network
  !   - rank=1 (1D: list of reaches/links)
  !   - Variables: streamflow (discharge)
  !   - Has x,y coordinates for each reach but NO shape/spacing
  !   - get_grid_shape() should return BMI_FAILURE for this grid
  !
  ! For uniform rectilinear grids, BMI provides shape+spacing+origin.
  ! For vector/unstructured grids, BMI provides x/y/z coordinates and
  ! node/edge/face counts instead.
  ! **************************************************************************
  write(0,*) "=============================================================="
  write(0,*) "  SECTION 5: Grid Tests"
  write(0,*) "=============================================================="

  ! ==========================================================
  ! GRID 0: 1km uniform rectilinear (Noah-MP land surface)
  ! ==========================================================
  write(0,*) "  --- Grid 0: 1km uniform rectilinear (Noah-MP) ---"

  ! get_grid_type(0)
  status = model%get_grid_type(0, grid_type_str)
  call check_status(status, "T22: get_grid_type(0) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(trim(grid_type_str) == "uniform_rectilinear", &
       "T22b: grid 0 type == 'uniform_rectilinear'", &
       test_count, pass_count, fail_count)
  write(0,*) "       Type = '", trim(grid_type_str), "'"

  ! get_grid_rank(0) -- should be 2 (2D grid)
  status = model%get_grid_rank(0, grid_rank)
  call check_status(status, "T23: get_grid_rank(0) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(grid_rank == 2, &
       "T23b: grid 0 rank == 2", &
       test_count, pass_count, fail_count)
  write(0,*) "       Rank =", grid_rank

  ! get_grid_size(0) -- total number of grid nodes (rows * cols)
  status = model%get_grid_size(0, grid_size_val)
  call check_status(status, "T24: get_grid_size(0) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(grid_size_val > 0, &
       "T24b: grid 0 size > 0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Size =", grid_size_val, " nodes"

  ! get_grid_shape(0) -- should be array of 2 elements, all > 0
  ! Allocate based on rank (we just learned it is 2)
  if (allocated(grid_shape_arr)) deallocate(grid_shape_arr)
  allocate(grid_shape_arr(grid_rank))
  status = model%get_grid_shape(0, grid_shape_arr)
  call check_status(status, "T25: get_grid_shape(0) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(all(grid_shape_arr > 0), &
       "T25b: grid 0 shape elements all > 0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Shape = [", grid_shape_arr(1), ",", grid_shape_arr(2), "]"

  ! Verify that shape product matches size
  call check_true(product(grid_shape_arr) == grid_size_val, &
       "T25c: product(shape) == grid_size", &
       test_count, pass_count, fail_count)

  ! get_grid_spacing(0) -- should be array of 2 elements, all > 0
  if (allocated(grid_spacing_arr)) deallocate(grid_spacing_arr)
  allocate(grid_spacing_arr(grid_rank))
  status = model%get_grid_spacing(0, grid_spacing_arr)
  call check_status(status, "T26: get_grid_spacing(0) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(all(grid_spacing_arr > 0.0d0), &
       "T26b: grid 0 spacing elements all > 0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Spacing = [", grid_spacing_arr(1), ",", &
       grid_spacing_arr(2), "] m"

  ! get_grid_origin(0) -- origin coordinates
  if (allocated(grid_origin_arr)) deallocate(grid_origin_arr)
  allocate(grid_origin_arr(grid_rank))
  status = model%get_grid_origin(0, grid_origin_arr)
  call check_status(status, "T27: get_grid_origin(0) returns SUCCESS", &
       test_count, pass_count, fail_count)
  write(0,*) "       Origin = [", grid_origin_arr(1), ",", &
       grid_origin_arr(2), "]"

  ! Clean up grid 0 arrays
  deallocate(grid_shape_arr)
  deallocate(grid_spacing_arr)
  deallocate(grid_origin_arr)

  write(0,*)

  ! ==========================================================
  ! GRID 1: 250m uniform rectilinear (terrain routing)
  ! ==========================================================
  write(0,*) "  --- Grid 1: 250m uniform rectilinear (routing) ---"

  ! get_grid_type(1)
  status = model%get_grid_type(1, grid_type_str)
  call check_status(status, "T28: get_grid_type(1) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(trim(grid_type_str) == "uniform_rectilinear", &
       "T28b: grid 1 type == 'uniform_rectilinear'", &
       test_count, pass_count, fail_count)
  write(0,*) "       Type = '", trim(grid_type_str), "'"

  ! get_grid_rank(1) -- should be 2
  status = model%get_grid_rank(1, grid_rank)
  call check_status(status, "T29: get_grid_rank(1) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(grid_rank == 2, &
       "T29b: grid 1 rank == 2", &
       test_count, pass_count, fail_count)
  write(0,*) "       Rank =", grid_rank

  ! get_grid_size(1) -- should be 4x the land grid (250m vs 1km)
  status = model%get_grid_size(1, grid_size_val)
  call check_status(status, "T30: get_grid_size(1) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(grid_size_val > 0, &
       "T30b: grid 1 size > 0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Size =", grid_size_val, " nodes"

  ! get_grid_shape(1) -- 2 elements, all > 0
  allocate(grid_shape_arr(grid_rank))
  status = model%get_grid_shape(1, grid_shape_arr)
  call check_status(status, "T31: get_grid_shape(1) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(all(grid_shape_arr > 0), &
       "T31b: grid 1 shape elements all > 0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Shape = [", grid_shape_arr(1), ",", grid_shape_arr(2), "]"
  deallocate(grid_shape_arr)

  ! get_grid_spacing(1) -- should be ~250m
  allocate(grid_spacing_arr(grid_rank))
  status = model%get_grid_spacing(1, grid_spacing_arr)
  call check_status(status, "T32: get_grid_spacing(1) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(all(grid_spacing_arr > 0.0d0), &
       "T32b: grid 1 spacing elements all > 0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Spacing = [", grid_spacing_arr(1), ",", &
       grid_spacing_arr(2), "] m"
  deallocate(grid_spacing_arr)

  write(0,*)

  ! ==========================================================
  ! GRID 2: vector / channel network
  ! ==========================================================
  write(0,*) "  --- Grid 2: vector (channel network) ---"

  ! get_grid_type(2) -- should be "vector"
  status = model%get_grid_type(2, grid_type_str)
  call check_status(status, "T33: get_grid_type(2) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(trim(grid_type_str) == "vector", &
       "T33b: grid 2 type == 'vector'", &
       test_count, pass_count, fail_count)
  write(0,*) "       Type = '", trim(grid_type_str), "'"

  ! get_grid_rank(2) -- should be 1 (1D network)
  status = model%get_grid_rank(2, grid_rank)
  call check_status(status, "T34: get_grid_rank(2) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(grid_rank == 1, &
       "T34b: grid 2 rank == 1", &
       test_count, pass_count, fail_count)
  write(0,*) "       Rank =", grid_rank

  ! get_grid_size(2) -- number of channel links/reaches
  status = model%get_grid_size(2, grid_size_val)
  call check_status(status, "T35: get_grid_size(2) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(grid_size_val > 0, &
       "T35b: grid 2 size > 0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Size =", grid_size_val, " nodes (channel links)"

  ! get_grid_node_count(2) -- should match grid size for vector grids
  status = model%get_grid_node_count(2, node_count)
  call check_status(status, "T36: get_grid_node_count(2) returns SUCCESS", &
       test_count, pass_count, fail_count)
  call check_true(node_count > 0, &
       "T36b: grid 2 node count > 0", &
       test_count, pass_count, fail_count)
  write(0,*) "       Node count =", node_count

  ! get_grid_x(2) and get_grid_y(2) -- channel reach coordinates
  if (node_count > 0) then
    allocate(grid_x_arr(node_count))
    allocate(grid_y_arr(node_count))

    status = model%get_grid_x(2, grid_x_arr)
    call check_status(status, "T37: get_grid_x(2) returns SUCCESS", &
         test_count, pass_count, fail_count)

    status = model%get_grid_y(2, grid_y_arr)
    call check_status(status, "T38: get_grid_y(2) returns SUCCESS", &
         test_count, pass_count, fail_count)

    write(0,*) "       x range: [", minval(grid_x_arr), ",", &
         maxval(grid_x_arr), "]"
    write(0,*) "       y range: [", minval(grid_y_arr), ",", &
         maxval(grid_y_arr), "]"

    deallocate(grid_x_arr)
    deallocate(grid_y_arr)
  end if

  ! get_grid_edge_count(2)
  status = model%get_grid_edge_count(2, edge_count)
  call check_status(status, "T39: get_grid_edge_count(2) returns SUCCESS", &
       test_count, pass_count, fail_count)
  write(0,*) "       Edge count =", edge_count

  ! get_grid_face_count(2)
  status = model%get_grid_face_count(2, face_count)
  call check_status(status, "T40: get_grid_face_count(2) returns SUCCESS", &
       test_count, pass_count, fail_count)
  write(0,*) "       Face count =", face_count

  ! --------------------------------------------------------------------------
  ! Grid 2: get_grid_shape should return BMI_FAILURE
  ! --------------------------------------------------------------------------
  ! Vector grids do NOT have a regular shape (they are not rectangular).
  ! Calling get_grid_shape on a vector grid is meaningless, so the wrapper
  ! must return BMI_FAILURE. This is an EXPECTED failure -- testing that the
  ! wrapper correctly rejects invalid requests.
  ! --------------------------------------------------------------------------
  allocate(grid_shape_arr(1))  ! Allocate a dummy array
  status = model%get_grid_shape(2, grid_shape_arr)
  call check_true(status == BMI_FAILURE, &
       "T41: get_grid_shape(grid=2) returns BMI_FAILURE (expected)", &
       test_count, pass_count, fail_count)
  deallocate(grid_shape_arr)

  ! Similarly, get_grid_spacing on a vector grid should fail
  allocate(grid_spacing_arr(1))
  status = model%get_grid_spacing(2, grid_spacing_arr)
  call check_true(status == BMI_FAILURE, &
       "T42: get_grid_spacing(grid=2) returns BMI_FAILURE (expected)", &
       test_count, pass_count, fail_count)
  deallocate(grid_spacing_arr)

  ! --------------------------------------------------------------------------
  ! Invalid grid ID test: grid 99 does not exist
  ! --------------------------------------------------------------------------
  status = model%get_grid_type(99, grid_type_str)
  call check_true(status == BMI_FAILURE, &
       "T43: get_grid_type(grid=99) returns BMI_FAILURE (expected)", &
       test_count, pass_count, fail_count)

  status = model%get_grid_rank(99, grid_rank)
  call check_true(status == BMI_FAILURE, &
       "T44: get_grid_rank(grid=99) returns BMI_FAILURE (expected)", &
       test_count, pass_count, fail_count)

  status = model%get_grid_size(99, grid_size_val)
  call check_true(status == BMI_FAILURE, &
       "T45: get_grid_size(grid=99) returns BMI_FAILURE (expected)", &
       test_count, pass_count, fail_count)

  write(0,*)

  ! **************************************************************************
  ! SECTION 6: GET/SET VALUE TESTS
  ! **************************************************************************
  !
  ! This is the core data exchange mechanism of BMI:
  !   get_value(name, dest)       -- Copy variable data into caller's array
  !   set_value(name, src)        -- Push caller's data into the model
  !   get_value_ptr(name, ptr)    -- Get a pointer to model's internal data
  !   get_value_at_indices(...)   -- Get specific elements by index
  !   set_value_at_indices(...)   -- Set specific elements by index
  !
  ! All arrays are FLATTENED to 1D, regardless of their native dimensionality.
  ! This is a key BMI design decision: it avoids row-major vs column-major
  ! issues between C, Fortran, and Python.
  !
  ! Example: A 15x16 2D soil moisture grid becomes a 240-element 1D array.
  !
  ! For WRF-Hydro BMI, all variables are "double precision" (float64).
  ! Calling get_value_int or get_value_float should return BMI_FAILURE.
  ! **************************************************************************
  write(0,*) "=============================================================="
  write(0,*) "  SECTION 6: Get/Set Value Tests"
  write(0,*) "=============================================================="

  ! --------------------------------------------------------------------------
  ! TEST: get_value for streamflow (channel_water__volume_flow_rate)
  ! --------------------------------------------------------------------------
  ! What: Read the streamflow values from the channel network (Grid 2).
  ! Why:  This is THE coupling variable -- river discharge flowing into
  !       SCHISM's coastal ocean model.
  ! How:  First get the grid size to know how many elements, then allocate
  !       an array of that size, then call get_value to fill it.
  ! Expect: Array of double precision values, some >= 0.0 (flow rates).
  !         After 1 time step, some reaches should have positive flow.
  ! --------------------------------------------------------------------------
  status = model%get_var_grid(trim(output_var_list(1)), grid_id)
  status = model%get_grid_size(grid_id, n)
  if (n > 0) then
    allocate(values(n))
    values = -999.0d0  ! Fill with sentinel value to verify data is written

    status = model%get_value_double(trim(output_var_list(1)), values)
    call check_status(status, &
         "T46: get_value(channel_water__volume_flow_rate)", &
         test_count, pass_count, fail_count)

    ! Check that at least some values are >= 0 (physically, streamflow >= 0)
    ! Using "any()" which returns .true. if any element satisfies the condition.
    call check_true(any(values >= 0.0d0), &
         "T46b: streamflow has some values >= 0.0", &
         test_count, pass_count, fail_count)

    write(0,*) "       Array size =", n
    write(0,*) "       Min =", minval(values)
    write(0,*) "       Max =", maxval(values)
    write(0,*) "       First 5 values:"
    do i = 1, min(5, n)
      write(0,*) "         [", i, "] =", values(i)
    end do

    deallocate(values)
  else
    call check_true(.false., &
         "T46: streamflow grid size > 0", &
         test_count, pass_count, fail_count)
  end if

  ! --------------------------------------------------------------------------
  ! TEST: get_value for soil moisture (soil_water__volume_fraction)
  ! --------------------------------------------------------------------------
  ! What: Read the soil moisture values from the 1km grid (Grid 0).
  ! Why:  Soil moisture is a key land surface variable. Values should be
  !       between 0.0 (completely dry) and 1.0 (fully saturated).
  !       This is a volume fraction -- dimensionless.
  ! --------------------------------------------------------------------------
  status = model%get_var_grid(trim(output_var_list(3)), grid_id)
  status = model%get_grid_size(grid_id, n)
  if (n > 0) then
    allocate(values(n))
    values = -999.0d0

    status = model%get_value_double(trim(output_var_list(3)), values)
    call check_status(status, "T47: get_value(soil_water__volume_fraction)", &
         test_count, pass_count, fail_count)

    ! Soil moisture should be between 0 and 1 (volume fraction)
    call check_true(all(values >= 0.0d0) .and. all(values <= 1.0d0), &
         "T47b: soil moisture in [0.0, 1.0]", &
         test_count, pass_count, fail_count)

    write(0,*) "       Array size =", n
    write(0,*) "       Min =", minval(values)
    write(0,*) "       Max =", maxval(values)

    deallocate(values)
  end if

  ! --------------------------------------------------------------------------
  ! TEST: get_value for temperature (land_surface_air__temperature)
  ! --------------------------------------------------------------------------
  ! What: Read the air temperature values from the 1km grid.
  ! Why:  Temperature is in Kelvin (K). Earth surface temperatures should
  !       be between 200K (-73C) and 350K (+77C) for any reasonable scenario.
  ! --------------------------------------------------------------------------
  status = model%get_var_grid(trim(output_var_list(8)), grid_id)
  status = model%get_grid_size(grid_id, n)
  if (n > 0) then
    allocate(values(n))
    values = -999.0d0

    status = model%get_value_double(trim(output_var_list(8)), values)
    call check_status(status, "T48: get_value(land_surface_air__temperature)", &
         test_count, pass_count, fail_count)

    ! Temperature sanity check: some cells should be in [200, 350] K.
    ! Not ALL cells, because masked/water cells may be 0 after cleanup.
    call check_true(any(values > 200.0d0 .and. values < 350.0d0), &
         "T48b: some temperatures in [200, 350] K", &
         test_count, pass_count, fail_count)

    write(0,*) "       Array size =", n
    write(0,*) "       Min =", minval(values), " K"
    write(0,*) "       Max =", maxval(values), " K"

    deallocate(values)
  end if

  ! --------------------------------------------------------------------------
  ! TEST: get_value for snow (snowpack__liquid-equivalent_depth)
  ! --------------------------------------------------------------------------
  ! What: Read the snow water equivalent (SWE) from the 1km grid.
  ! Why:  SWE is the depth of water you would get if you melted all the snow.
  !       Values should be >= 0.0 (in meters). The Croton NY case is
  !       Hurricane Irene in August -- little to no snow expected.
  ! --------------------------------------------------------------------------
  status = model%get_var_grid(trim(output_var_list(4)), grid_id)
  status = model%get_grid_size(grid_id, n)
  if (n > 0) then
    allocate(values(n))
    values = -999.0d0

    status = model%get_value_double(trim(output_var_list(4)), values)
    call check_status(status, &
         "T49: get_value(snowpack__liquid-equivalent_depth)", &
         test_count, pass_count, fail_count)

    ! SWE should be >= 0
    call check_true(all(values >= 0.0d0), &
         "T49b: snow water equivalent >= 0.0", &
         test_count, pass_count, fail_count)

    write(0,*) "       Array size =", n
    write(0,*) "       Min =", minval(values), " m"
    write(0,*) "       Max =", maxval(values), " m"

    deallocate(values)
  end if

  ! --------------------------------------------------------------------------
  ! TEST: set_value_double (round-trip: set then get, verify data matches)
  ! --------------------------------------------------------------------------
  ! What: Write new values into a variable, then read them back.
  ! Why:  This tests two-way data exchange. SCHISM needs to push tidal
  !       water levels INTO WRF-Hydro via set_value, and WRF-Hydro needs
  !       to push discharge OUT via get_value. Both directions must work.
  !
  ! Strategy:
  !   1. Get the current temperature array
  !   2. Set all values to 300.0 K (a round number)
  !   3. Get the values again
  !   4. Verify they are all 300.0 K
  ! --------------------------------------------------------------------------
  status = model%get_var_grid(trim(output_var_list(8)), grid_id)
  status = model%get_grid_size(grid_id, n)
  if (n > 0) then
    allocate(set_src(n))
    allocate(values_copy(n))

    ! Set all temperature values to 300.0 K
    set_src = 300.0d0

    status = model%set_value_double(trim(output_var_list(8)), set_src)
    call check_status(status, &
         "T50: set_value(land_surface_air__temperature, 300.0)", &
         test_count, pass_count, fail_count)

    ! Read them back
    values_copy = -999.0d0
    status = model%get_value_double(trim(output_var_list(8)), values_copy)
    call check_status(status, "T50b: get_value after set_value", &
         test_count, pass_count, fail_count)

    ! Verify round-trip: all values should be 300.0
    call check_true(all(abs(values_copy - 300.0d0) < 1.0d-10), &
         "T50c: round-trip set/get values match (300.0 K)", &
         test_count, pass_count, fail_count)

    deallocate(set_src)
    deallocate(values_copy)
  end if

  ! --------------------------------------------------------------------------
  ! TEST: get_value_at_indices_double
  ! --------------------------------------------------------------------------
  ! What: Read specific elements by their 1D index.
  ! Why:  Sometimes you only need a few values (e.g., one gauge station),
  !       not the entire array. This is more efficient for sparse access.
  ! --------------------------------------------------------------------------
  status = model%get_var_grid(trim(output_var_list(8)), grid_id)
  status = model%get_grid_size(grid_id, n)
  if (n >= 3) then
    allocate(test_indices(3))
    allocate(subset_values(3))

    ! Pick 3 indices (Fortran uses 1-based indexing)
    test_indices = (/1, 2, 3/)
    subset_values = -999.0d0

    status = model%get_value_at_indices_double( &
         trim(output_var_list(8)), subset_values, test_indices)
    call check_status(status, &
         "T51: get_value_at_indices(temperature, [1,2,3])", &
         test_count, pass_count, fail_count)

    ! Values should have been set to 300.0 in the previous test
    call check_true(all(abs(subset_values - 300.0d0) < 1.0d-10), &
         "T51b: indexed values match expected (300.0 K)", &
         test_count, pass_count, fail_count)

    write(0,*) "       Indices:", test_indices
    write(0,*) "       Values :", subset_values

    deallocate(test_indices)
    deallocate(subset_values)
  end if

  ! --------------------------------------------------------------------------
  ! TEST: set_value_at_indices_double
  ! --------------------------------------------------------------------------
  ! What: Write specific elements by index, then verify.
  ! Why:  Useful for boundary forcing -- set values only at boundary nodes.
  ! --------------------------------------------------------------------------
  status = model%get_var_grid(trim(output_var_list(8)), grid_id)
  status = model%get_grid_size(grid_id, n)
  if (n >= 3) then
    allocate(test_indices(3))
    allocate(subset_values(3))
    allocate(values(n))

    test_indices = (/1, 2, 3/)
    subset_values = (/273.15d0, 283.15d0, 293.15d0/)  ! 0C, 10C, 20C in K

    status = model%set_value_at_indices_double( &
         trim(output_var_list(8)), test_indices, subset_values)
    call check_status(status, &
         "T52: set_value_at_indices(temperature, [1,2,3])", &
         test_count, pass_count, fail_count)

    ! Read back the full array and check the 3 indices
    values = -999.0d0
    status = model%get_value_double(trim(output_var_list(8)), values)

    ! Tolerance is 1e-4 because WRF-Hydro stores temperature as REAL
    ! (single precision, ~7 digits), so double->single->double loses
    ! precision. 273.15d0 -> real(273.15d0) -> dble() ≈ 273.14999...
    call check_true(abs(values(1) - 273.15d0) < 1.0d-4 .and. &
                    abs(values(2) - 283.15d0) < 1.0d-4 .and. &
                    abs(values(3) - 293.15d0) < 1.0d-4, &
         "T52b: indexed set values match after get_value", &
         test_count, pass_count, fail_count)

    deallocate(test_indices)
    deallocate(subset_values)
    deallocate(values)
  end if

  ! --------------------------------------------------------------------------
  ! TEST: get_value_ptr_double
  ! --------------------------------------------------------------------------
  ! What: Get a POINTER to the model's internal data (not a copy).
  ! Why:  Pointers avoid copying large arrays. The caller gets direct access
  !       to the model's memory. Changes via the pointer affect the model.
  !       This is like getting a NumPy view instead of a copy.
  !
  ! NOTE: WRF-Hydro stores arrays as REAL (single precision), but BMI
  !       requires double precision pointers. We cannot return a pointer to
  !       a different type, so get_value_ptr returns BMI_FAILURE.
  !       This is a known limitation — use get_value() (copy) instead.
  ! --------------------------------------------------------------------------
  status = model%get_value_ptr_double(trim(output_var_list(8)), ptr_values)
  call check_true(status == BMI_FAILURE, &
       "T53: get_value_ptr returns BMI_FAILURE (REAL/DOUBLE mismatch)", &
       test_count, pass_count, fail_count)
  call check_true(.not. associated(ptr_values), &
       "T53b: pointer is NOT associated (expected)", &
       test_count, pass_count, fail_count)
  nullify(ptr_values)

  ! --------------------------------------------------------------------------
  ! TEST: get_value_int should return BMI_FAILURE
  ! --------------------------------------------------------------------------
  ! What: Try to read data as integer type (our variables are all double).
  ! Why:  The BMI spec says get_value_int must return BMI_FAILURE if the
  !       variable is not integer type. This tests type safety.
  ! --------------------------------------------------------------------------
  allocate(int_values(1))
  status = model%get_value_int(trim(output_var_list(1)), int_values)
  call check_true(status == BMI_FAILURE, &
       "T54: get_value_int(double var) returns BMI_FAILURE (expected)", &
       test_count, pass_count, fail_count)
  deallocate(int_values)

  ! --------------------------------------------------------------------------
  ! TEST: get_value_float should return BMI_FAILURE
  ! --------------------------------------------------------------------------
  ! What: Try to read data as single-precision float (our vars are double).
  ! Why:  Same reason -- type mismatch must return BMI_FAILURE.
  ! --------------------------------------------------------------------------
  allocate(float_values(1))
  status = model%get_value_float(trim(output_var_list(1)), float_values)
  call check_true(status == BMI_FAILURE, &
       "T55: get_value_float(double var) returns BMI_FAILURE (expected)", &
       test_count, pass_count, fail_count)
  deallocate(float_values)

  write(0,*)

  ! **************************************************************************
  ! SECTION 7: EDGE CASE TESTS
  ! **************************************************************************
  !
  ! Edge cases test that the BMI wrapper handles bad input gracefully.
  ! A robust wrapper should NEVER crash on bad input -- it should return
  ! BMI_FAILURE and let the caller decide what to do. This is like
  ! returning an error code instead of throwing an unhandled exception.
  ! **************************************************************************
  write(0,*) "=============================================================="
  write(0,*) "  SECTION 7: Edge Case Tests"
  write(0,*) "=============================================================="

  ! --------------------------------------------------------------------------
  ! TEST: get_var_grid with invalid variable name
  ! --------------------------------------------------------------------------
  status = model%get_var_grid("this_variable__does_not_exist", grid_id)
  call check_true(status == BMI_FAILURE, &
       "T56: get_var_grid(invalid name) returns BMI_FAILURE", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST: get_var_units with invalid variable name
  ! --------------------------------------------------------------------------
  status = model%get_var_units("this_variable__does_not_exist", var_units_str)
  call check_true(status == BMI_FAILURE, &
       "T57: get_var_units(invalid name) returns BMI_FAILURE", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST: get_var_itemsize with invalid variable name
  ! --------------------------------------------------------------------------
  status = model%get_var_itemsize("this_variable__does_not_exist", var_itemsize)
  call check_true(status == BMI_FAILURE, &
       "T58: get_var_itemsize(invalid name) returns BMI_FAILURE", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST: get_var_nbytes with invalid variable name
  ! --------------------------------------------------------------------------
  status = model%get_var_nbytes("this_variable__does_not_exist", var_nbytes)
  call check_true(status == BMI_FAILURE, &
       "T59: get_var_nbytes(invalid name) returns BMI_FAILURE", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST: get_var_location with invalid variable name
  ! --------------------------------------------------------------------------
  status = model%get_var_location("this_variable__does_not_exist", &
       var_location_str)
  call check_true(status == BMI_FAILURE, &
       "T60: get_var_location(invalid name) returns BMI_FAILURE", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST: get_grid_node_count with invalid grid ID
  ! --------------------------------------------------------------------------
  status = model%get_grid_node_count(99, node_count)
  call check_true(status == BMI_FAILURE, &
       "T61: get_grid_node_count(grid=99) returns BMI_FAILURE", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST: get_grid_edge_count with invalid grid ID
  ! --------------------------------------------------------------------------
  status = model%get_grid_edge_count(99, edge_count)
  call check_true(status == BMI_FAILURE, &
       "T62: get_grid_edge_count(grid=99) returns BMI_FAILURE", &
       test_count, pass_count, fail_count)

  ! --------------------------------------------------------------------------
  ! TEST: get_grid_face_count with invalid grid ID
  ! --------------------------------------------------------------------------
  status = model%get_grid_face_count(99, face_count)
  call check_true(status == BMI_FAILURE, &
       "T63: get_grid_face_count(grid=99) returns BMI_FAILURE", &
       test_count, pass_count, fail_count)

  write(0,*)

  ! **************************************************************************
  ! SECTION 8: INTEGRATION TESTS (Full IRF Cycle)
  ! **************************************************************************
  !
  ! Integration tests verify the WHOLE workflow, not individual functions.
  ! This is like a "smoke test" or "end-to-end test" in software testing.
  !
  ! Test A: Run a complete IRF cycle (init -> N updates -> finalize) and
  !         verify that the model time advances correctly.
  !
  ! Test B: Verify that model output evolves over time (values at step 1
  !         should differ from values at step 6).
  ! **************************************************************************
  write(0,*) "=============================================================="
  write(0,*) "  SECTION 8: Integration Tests (Full IRF Cycle)"
  write(0,*) "=============================================================="

  ! Clean up the current model instance before the integration test
  status = model%finalize()

  ! --------------------------------------------------------------------------
  ! INTEGRATION TEST A: Time advances correctly over multiple steps
  ! --------------------------------------------------------------------------
  ! What: Initialize, run 6 update() calls, verify current_time == 6*dt.
  ! Why:  This tests that the time bookkeeping works across multiple steps.
  !       If current_time drifts or does not advance, the coupling would
  !       lose synchronization between WRF-Hydro and SCHISM.
  ! --------------------------------------------------------------------------
  write(0,*) "  --- Integration Test A: Time advancement ---"

  status = model%initialize(trim(config_file))
  call check_status(status, "T64: integration init", &
       test_count, pass_count, fail_count)

  ! Get the time step
  status = model%get_time_step(dt)

  ! Run 6 time steps
  do i = 1, 6
    status = model%update()
    if (status /= BMI_SUCCESS) then
      write(0,*) "  WARNING: update() failed at step", i
      exit
    end if
  end do

  ! Check that current_time == 6 * dt
  status = model%get_current_time(current_time)
  expected_time = 6.0d0 * dt
  call check_true(abs(current_time - expected_time) < 1.0d-6, &
       "T65: after 6 updates, current_time == 6*dt", &
       test_count, pass_count, fail_count)
  write(0,*) "       Expected time:", expected_time, " seconds"
  write(0,*) "       Actual time  :", current_time, " seconds"

  status = model%finalize()
  call check_status(status, "T66: integration finalize", &
       test_count, pass_count, fail_count)

  write(0,*)

  ! --------------------------------------------------------------------------
  ! INTEGRATION TEST B: Output evolves over time
  ! --------------------------------------------------------------------------
  ! What: Get streamflow at step 1 and step 6, verify they differ.
  ! Why:  If the output does not change over time, the model is not actually
  !       running -- it might be stuck in an initialization-only state.
  !       This is a basic "liveness" test.
  !
  ! Strategy:
  !   1. Initialize and run 1 step, save streamflow
  !   2. Run 5 more steps, save streamflow again
  !   3. Compare: at least some values should differ
  ! --------------------------------------------------------------------------
  write(0,*) "  --- Integration Test B: Output evolution over time ---"

  status = model%initialize(trim(config_file))
  if (status /= BMI_SUCCESS) then
    write(0,*) "  FATAL: Could not initialize for integration test B."
    call check_true(.false., &
         "T67: init for evolution test", &
         test_count, pass_count, fail_count)
  else
    ! Step 1: run one step and capture streamflow
    status = model%update()
    status = model%get_var_grid(trim(output_var_list(1)), grid_id)
    status = model%get_grid_size(grid_id, n)

    if (n > 0) then
      allocate(values_step1(n))
      allocate(values_step6(n))

      values_step1 = -999.0d0
      status = model%get_value_double(trim(output_var_list(1)), values_step1)

      ! Step 2-6: run 5 more steps
      do i = 2, 6
        status = model%update()
      end do

      ! Capture streamflow at step 6
      values_step6 = -999.0d0
      status = model%get_value_double(trim(output_var_list(1)), values_step6)

      ! At least one value should differ between step 1 and step 6.
      ! We check if ANY element is different (not all -- some reaches might
      ! be consistently dry or at steady state).
      call check_true(any(abs(values_step1 - values_step6) > 1.0d-15), &
           "T67: streamflow differs between step 1 and step 6", &
           test_count, pass_count, fail_count)

      write(0,*) "       Step 1 streamflow range: [", &
           minval(values_step1), ",", maxval(values_step1), "]"
      write(0,*) "       Step 6 streamflow range: [", &
           minval(values_step6), ",", maxval(values_step6), "]"

      ! Count how many values changed
      j = 0
      do i = 1, n
        if (abs(values_step1(i) - values_step6(i)) > 1.0d-15) j = j + 1
      end do
      write(0,*) "       Values changed:", j, "out of", n

      deallocate(values_step1)
      deallocate(values_step6)
    else
      call check_true(.false., &
           "T67: streamflow grid size > 0 for evolution test", &
           test_count, pass_count, fail_count)
    end if

    status = model%finalize()
  end if

  write(0,*)

  ! --------------------------------------------------------------------------
  ! INTEGRATION TEST C: update_until accuracy
  ! --------------------------------------------------------------------------
  ! What: Use update_until to advance to 3*dt, then verify current_time.
  ! Why:  update_until must correctly loop internal update() calls and stop
  !       at the right time. This is how PyMT synchronizes two models
  !       with different time steps.
  ! --------------------------------------------------------------------------
  write(0,*) "  --- Integration Test C: update_until accuracy ---"

  status = model%initialize(trim(config_file))
  if (status == BMI_SUCCESS) then
    status = model%get_time_step(dt)
    expected_time = 3.0d0 * dt

    status = model%update_until(expected_time)
    call check_status(status, "T68: update_until(3*dt)", &
         test_count, pass_count, fail_count)

    status = model%get_current_time(current_time)
    call check_true(abs(current_time - expected_time) < 1.0d-6, &
         "T69: current_time == 3*dt after update_until", &
         test_count, pass_count, fail_count)
    write(0,*) "       Expected:", expected_time
    write(0,*) "       Actual  :", current_time

    status = model%finalize()
  else
    call check_true(.false., &
         "T68: init for update_until test", &
         test_count, pass_count, fail_count)
    call check_true(.false., &
         "T69: skipped (init failed)", &
         test_count, pass_count, fail_count)
  end if

  write(0,*)

  ! ==========================================================================
  ! FINAL SUMMARY
  ! ==========================================================================
  ! Print a clear summary of how many tests passed vs failed.
  ! The test driver exits with code 0 if ALL tests pass, or 1 if any fail.
  ! This exit code is used by CI systems (like GitHub Actions or CTest) to
  ! determine if the build is healthy.
  ! ==========================================================================
  write(0,*) "=============================================================="
  write(0,*) "=============================================================="
  write(0,*) "  WRF-Hydro BMI Test Summary"
  write(0,*) "=============================================================="
  write(0,*) "  Total tests: ", test_count
  write(0,*) "  Passed:      ", pass_count
  write(0,*) "  Failed:      ", fail_count
  write(0,*) "--------------------------------------------------------------"
  if (fail_count == 0) then
    write(0,*) "  >>> ALL TESTS PASSED <<<"
  else
    write(0,*) "  >>> SOME TESTS FAILED <<<"
  end if
  write(0,*) "=============================================================="
  write(0,*) "=============================================================="

  ! Clean up the config file we created at the start
  ! "status='delete'" removes the file when closing -- Fortran's way of
  ! deleting a temporary file.
  open(unit=10, file=trim(config_file), status="old", iostat=status)
  if (status == 0) close(10, status="delete")

  ! --- MPI Cleanup ---
  ! MPI was initialized by HYDRO_ini (inside land_driver_ini) during
  ! the first BMI initialize() call. Normally HYDRO_finish() calls
  ! MPI_Finalize + stop, but we skip HYDRO_finish because it has "stop".
  ! So WE must finalize MPI before exiting.
  call MPI_Finalize(mpi_ierr)

  ! Exit with appropriate return code for CI systems.
  ! "stop 0" means success, "stop 1" means failure.
  ! This is like sys.exit(0) or sys.exit(1) in Python.
  if (fail_count > 0) then
    stop 1
  else
    stop 0
  end if

! ============================================================================
! HELPER SUBROUTINES
! ============================================================================
!
! "contains" marks the boundary between the main program's executable code
! and its internal subroutines. Subroutines defined after "contains" can
! access the main program's variables (they are in the same scope).
!
! In Python terms, these are like nested functions that can see the
! enclosing function's local variables. But in Fortran, we pass everything
! explicitly via arguments -- it is cleaner and more predictable.
!
! We define two helpers:
!   check_status -- Tests that a BMI call returned BMI_SUCCESS (=0)
!   check_true   -- Tests that a logical condition is .true.
! ============================================================================
contains

  ! --------------------------------------------------------------------------
  ! SUBROUTINE: check_status
  ! --------------------------------------------------------------------------
  ! Purpose: Verify that a BMI function returned BMI_SUCCESS (=0).
  !
  ! Parameters:
  !   status_val  -- The integer return value from a BMI function call.
  !                  BMI_SUCCESS = 0, BMI_FAILURE = 1.
  !   test_name   -- A string describing what this test checks (for output).
  !   tc          -- Total test count (incremented by 1).
  !   pc          -- Pass count (incremented if status_val == BMI_SUCCESS).
  !   fc          -- Fail count (incremented if status_val /= BMI_SUCCESS).
  !
  ! How intent works:
  !   intent(in)    = read-only parameter (like a const reference)
  !   intent(inout) = read-write parameter (like a mutable reference)
  !
  ! "character(len=*)" means the string can be any length -- the actual
  ! length is determined by what the caller passes in. This is Fortran's
  ! way of handling variable-length strings as function arguments.
  ! --------------------------------------------------------------------------
  subroutine check_status(status_val, test_name, tc, pc, fc)
    integer, intent(in) :: status_val
    character(len=*), intent(in) :: test_name
    integer, intent(inout) :: tc, pc, fc

    tc = tc + 1

    if (status_val == BMI_SUCCESS) then
      pc = pc + 1
      write(0,*) "  PASS: ", trim(test_name)
    else
      fc = fc + 1
      write(0,*) "  FAIL: ", trim(test_name), " (status=", status_val, ")"
    end if
  end subroutine check_status

  ! --------------------------------------------------------------------------
  ! SUBROUTINE: check_true
  ! --------------------------------------------------------------------------
  ! Purpose: Verify that a logical (boolean) condition is .true.
  !
  ! This is the more general assertion helper. Use it for any check that
  ! is not just "did the BMI call succeed?", such as:
  !   - Value is in expected range
  !   - String contains expected substring
  !   - Array size matches expected count
  !
  ! Parameters:
  !   condition  -- A logical (boolean) expression to evaluate.
  !                 .true. = test passes, .false. = test fails.
  !   test_name  -- Description string for the test output.
  !   tc, pc, fc -- Counters (same as check_status).
  !
  ! Fortran booleans:
  !   .true.  = Python's True
  !   .false. = Python's False
  !   logical = the type name (like Python's "bool")
  ! --------------------------------------------------------------------------
  subroutine check_true(condition, test_name, tc, pc, fc)
    logical, intent(in) :: condition
    character(len=*), intent(in) :: test_name
    integer, intent(inout) :: tc, pc, fc

    tc = tc + 1

    if (condition) then
      pc = pc + 1
      write(0,*) "  PASS: ", trim(test_name)
    else
      fc = fc + 1
      write(0,*) "  FAIL: ", trim(test_name)
    end if
  end subroutine check_true

end program bmi_wrf_hydro_test
