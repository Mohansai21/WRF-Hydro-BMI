! ============================================================================
! MODULE: wrfhydro_bmi_state_mod (must come before bmiwrfhydrof)
! ============================================================================
! Holds the WRF-Hydro state_type object that persists across BMI calls.
! This is a separate module because the BMI initialize() uses intent(out)
! on "this", which would reset member variables. By keeping the state in
! a module-level SAVE variable, it persists across all BMI function calls.
!
! This is similar to SCHISM's approach where model globals live in
! schism_glbl and are accessed via "use schism_glbl, only: ...".
! ============================================================================
module wrfhydro_bmi_state_mod
  use state_module, only: state_type
  implicit none
  type(state_type), save :: wrfhydro_bmi_state
  ! Module-level flag: tracks whether WRF-Hydro internals have been initialized.
  ! Once true, never goes back to false because WRF-Hydro module-level arrays
  ! (COSZEN, SMOIS, etc.) persist and cannot be re-allocated without modifying
  ! WRF-Hydro source code. This prevents double-allocation crashes when the
  ! BMI caller does finalize() then initialize() again.
  logical, save :: wrfhydro_engine_initialized = .false.
  ! Saved ntime from first initialization (intent(out) on initialize resets
  ! the bmi_wrf_hydro type, so we save ntime here for re-initialization).
  integer, save :: wrfhydro_saved_ntime = 0
end module wrfhydro_bmi_state_mod


! ============================================================================
! FILE: bmi_wrf_hydro.f90
! ============================================================================
!
! PURPOSE:
!   BMI (Basic Model Interface) 2.0 wrapper for WRF-Hydro v5.4.0.
!   This module implements ALL 41 BMI functions (55 procedure bindings
!   including type-specific variants for get/set) so that WRF-Hydro can be
!   controlled externally by coupling frameworks like PyMT or NextGen.
!
! WHAT IS BMI?
!   BMI = Basic Model Interface. It is a set of 41+ standardized functions
!   that let external code control a model without knowing its internals.
!   Think of it like an API contract:
!     - initialize(config) -> load model
!     - update()           -> advance one timestep
!     - get_value(name)    -> read a variable
!     - set_value(name)    -> write a variable
!     - finalize()         -> clean up
!
! WHAT IS WRF-HYDRO?
!   WRF-Hydro is NCAR's hydrological model that simulates:
!     - Land surface processes (Noah-MP: soil, snow, vegetation)
!     - Overland flow routing (2D surface water)
!     - Subsurface flow routing (saturated lateral flow)
!     - Channel routing (1D river flow via Muskingum-Cunge)
!     - Reservoir/lake routing
!
! HOW THIS WRAPPER WORKS:
!   WRF-Hydro normally runs with its own internal time loop (in
!   main_hrldas_driver.F). This BMI wrapper decomposes that loop into
!   the Initialize-Run-Finalize (IRF) pattern:
!
!     initialize() -> orchestrator%init() + land_driver_ini() + HYDRO_ini()
!     update()     -> land_driver_exe() (which calls HYDRO_exe() internally)
!     finalize()   -> custom cleanup (NOT HYDRO_finish, which has stop!)
!
!   The CALLER (PyMT/NextGen) controls the time loop, not the model.
!
! VARIABLES EXPOSED (8 output + 4 input):
!   Output (what the model produces):
!     1. channel_water__volume_flow_rate        -> streamflow (m3/s)
!     2. land_surface_water__depth              -> surface water head (m)
!     3. soil_water__volume_fraction            -> soil moisture (-)
!     4. snowpack__liquid-equivalent_depth       -> snow water equiv (mm)
!     5. land_surface_water__evaporation_volume_flux -> ET (mm)
!     6. land_surface_water__runoff_volume_flux  -> surface runoff (m)
!     7. soil_water__domain_time_integral_of_baseflow_volume_flux -> baseflow (mm)
!     8. land_surface_air__temperature           -> 2m temperature (K)
!
!   Input (what the caller can push in):
!     1. atmosphere_water__precipitation_leq-volume_flux -> precip (mm/s)
!     2. land_surface_air__temperature           -> 2m temperature (K)
!     3. sea_water_surface__elevation            -> tidal elevation (m)
!     4. sea_water__x_velocity                   -> coastal current (m/s)
!
! GRIDS (3 types):
!   Grid 0: 1km uniform rectilinear  (Noah-MP land surface, IX x JX)
!   Grid 1: 250m uniform rectilinear (terrain routing, IXRT x JXRT)
!   Grid 2: vector/network           (channel routing, NLINKS)
!
! FORTRAN CONCEPTS (for newcomers from Python/ML):
!   - "module"    : Like a Python module/class — groups data + functions
!   - "type"      : Like a Python class — has data members + methods
!   - "extends"   : Like Python inheritance — bmi_wrf_hydro extends bmi
!   - "procedure" : Like a method in a class
!   - "generic"   : Like Python's @overload — dispatch by argument type
!   - "use"       : Like Python's "import" — import another module
!   - "implicit none" : Forces declaring all variables (prevents typos)
!   - "intent(in/out/inout)" : Documents if arg is read, written, or both
!   - "allocatable" : Array size determined at runtime (like Python list)
!   - "target"    : Marks a variable that can have pointers to it
!   - "pointer"   : A reference to data owned elsewhere (like Python ref)
!   - "select case" : Like Python's match/case — choose by value
!   - "BMI_SUCCESS/BMI_FAILURE" : Integer constants (0 and 1)
!   - "dble(x)"   : Convert single-precision REAL to double precision
!   - "reshape()" : Flatten a 2D array to 1D (like numpy.ravel())
!
! AUTHOR:  WRF-Hydro BMI Project
! DATE:    February 2026
! LICENSE: See project root
! ============================================================================

module bmiwrfhydrof

  ! --------------------------------------------------------------------------
  ! MODULE IMPORTS
  ! --------------------------------------------------------------------------
  ! bmif_2_0: The abstract BMI interface from CSDMS. It defines the "bmi"
  !           abstract type with 53 deferred procedures. Our bmi_wrf_hydro
  !           type must implement ALL of them (like implementing an interface
  !           in Java or an abstract base class in Python).
  !
  ! iso_c_binding: Fortran 2003 interoperability with C. We need c_ptr,
  !                c_loc, and c_f_pointer for the get_value_ptr functions
  !                which return raw memory pointers (needed by coupling
  !                frameworks for zero-copy data exchange).
  !
  ! WRF-Hydro modules: These provide access to the model's internal state.
  !   - module_noahmp_hrldas_driver: Land surface model driver + module vars
  !   - module_RT_data: Routing state (rt_domain global variable)
  !   - state_module: state_type for snow/temperature state
  !   - orchestrator_base: Model initialization orchestrator
  !   - config_base: Namelist configuration (nlst, noah_lsm)
  ! --------------------------------------------------------------------------

  use bmif_2_0
  use, intrinsic :: iso_c_binding, only: c_ptr, c_loc, c_f_pointer
  use wrfhydro_bmi_state_mod, only: wrfhydro_bmi_state, &
       wrfhydro_engine_initialized, wrfhydro_saved_ntime

  implicit none

  ! ==========================================================================
  ! TYPE DEFINITION: bmi_wrf_hydro
  ! ==========================================================================
  !
  ! This is the main BMI wrapper type. It "extends" (inherits from) the
  ! abstract "bmi" type, meaning it MUST implement all 53 deferred procedures.
  !
  ! Think of this like:
  !   class bmi_wrf_hydro(bmi):
  !       def __init__(self):
  !           self.initialized = False
  !           self.state = state_type()
  !           ...
  !
  ! The "private" keyword means external code cannot directly access member
  ! variables — they must go through BMI functions (encapsulation).
  ! ==========================================================================

  type, extends (bmi) :: bmi_wrf_hydro
     private

     ! --- Model lifecycle tracking ---
     logical :: initialized = .false.    ! Has initialize() been called?
     integer :: current_timestep = 0     ! Timestep counter (1, 2, 3, ...)
     integer :: ntime = 0                ! Total number of timesteps

     ! --- Time tracking (all in seconds) ---
     double precision :: start_time = 0.0d0    ! Model start (always 0)
     double precision :: current_time = 0.0d0  ! Current model time
     double precision :: end_time = 0.0d0      ! Model end time
     double precision :: dt = 0.0d0            ! Timestep size (from config)

     ! --- Configuration ---
     character(len=256) :: run_dir = ""   ! WRF-Hydro run directory path

     ! --- Grid dimensions (populated during initialize) ---
     ! These come from WRF-Hydro's internal state after initialization.
     integer :: ix = 0        ! LSM grid x-dimension (1km, e.g. 15 for Croton)
     integer :: jx = 0        ! LSM grid y-dimension (1km, e.g. 16 for Croton)
     integer :: ixrt = 0      ! Routing grid x-dimension (250m)
     integer :: jxrt = 0      ! Routing grid y-dimension (250m)
     integer :: nlinks = 0    ! Number of channel links
     integer :: nsoil = 0     ! Number of soil layers (typically 4)
     double precision :: dx_lsm = 0.0d0    ! LSM grid spacing (m)
     double precision :: dx_rt = 0.0d0     ! Routing grid spacing (m)

     ! --- Coupling placeholders (for SCHISM 2-way coupling) ---
     ! In Phase 1, these store values set by set_value() but don't feed
     ! into WRF-Hydro. In Phase 2, they will drive coastal boundary forcing.
     double precision, allocatable :: sea_water_elevation(:,:)  ! (IX,JX)
     double precision, allocatable :: sea_water_x_velocity(:,:) ! (IX,JX)

   contains

     ! --- Control functions (4) ---
     ! These manage the model lifecycle: create, run, destroy.
     procedure :: initialize => wrfhydro_initialize
     procedure :: update => wrfhydro_update
     procedure :: update_until => wrfhydro_update_until
     procedure :: finalize => wrfhydro_finalize

     ! --- Model info functions (5) ---
     ! These let callers discover what the model is and what it offers.
     procedure :: get_component_name => wrfhydro_component_name
     procedure :: get_input_item_count => wrfhydro_input_item_count
     procedure :: get_output_item_count => wrfhydro_output_item_count
     procedure :: get_input_var_names => wrfhydro_input_var_names
     procedure :: get_output_var_names => wrfhydro_output_var_names

     ! --- Variable info functions (6) ---
     ! For each variable, provide metadata: type, units, grid, size, location.
     procedure :: get_var_type => wrfhydro_var_type
     procedure :: get_var_units => wrfhydro_var_units
     procedure :: get_var_grid => wrfhydro_var_grid
     procedure :: get_var_itemsize => wrfhydro_var_itemsize
     procedure :: get_var_nbytes => wrfhydro_var_nbytes
     procedure :: get_var_location => wrfhydro_var_location

     ! --- Time functions (5) ---
     ! Report the model's time state (all in seconds since start).
     procedure :: get_start_time => wrfhydro_start_time
     procedure :: get_end_time => wrfhydro_end_time
     procedure :: get_current_time => wrfhydro_current_time
     procedure :: get_time_step => wrfhydro_time_step
     procedure :: get_time_units => wrfhydro_time_units

     ! --- Grid functions (17) ---
     ! Describe the spatial grids the variables live on.
     procedure :: get_grid_type => wrfhydro_grid_type
     procedure :: get_grid_rank => wrfhydro_grid_rank
     procedure :: get_grid_shape => wrfhydro_grid_shape
     procedure :: get_grid_size => wrfhydro_grid_size
     procedure :: get_grid_spacing => wrfhydro_grid_spacing
     procedure :: get_grid_origin => wrfhydro_grid_origin
     procedure :: get_grid_x => wrfhydro_grid_x
     procedure :: get_grid_y => wrfhydro_grid_y
     procedure :: get_grid_z => wrfhydro_grid_z
     procedure :: get_grid_node_count => wrfhydro_grid_node_count
     procedure :: get_grid_edge_count => wrfhydro_grid_edge_count
     procedure :: get_grid_face_count => wrfhydro_grid_face_count
     procedure :: get_grid_edge_nodes => wrfhydro_grid_edge_nodes
     procedure :: get_grid_face_edges => wrfhydro_grid_face_edges
     procedure :: get_grid_face_nodes => wrfhydro_grid_face_nodes
     procedure :: get_grid_nodes_per_face => wrfhydro_grid_nodes_per_face

     ! --- Get value functions (3 type variants + generic) ---
     ! Copy variable data OUT of the model into caller's array.
     ! BMI requires all three type variants; WRF-Hydro uses double.
     procedure :: get_value_int => wrfhydro_get_int
     procedure :: get_value_float => wrfhydro_get_float
     procedure :: get_value_double => wrfhydro_get_double
     generic :: get_value => &
          get_value_int, &
          get_value_float, &
          get_value_double

     ! --- Get value pointer functions (3 type variants + generic) ---
     ! Return a pointer to the model's internal data (zero-copy).
     procedure :: get_value_ptr_int => wrfhydro_get_ptr_int
     procedure :: get_value_ptr_float => wrfhydro_get_ptr_float
     procedure :: get_value_ptr_double => wrfhydro_get_ptr_double
     generic :: get_value_ptr => &
          get_value_ptr_int, &
          get_value_ptr_float, &
          get_value_ptr_double

     ! --- Get value at indices functions (3 type variants + generic) ---
     ! Get specific elements by their flat array indices.
     procedure :: get_value_at_indices_int => wrfhydro_get_at_indices_int
     procedure :: get_value_at_indices_float => wrfhydro_get_at_indices_float
     procedure :: get_value_at_indices_double => wrfhydro_get_at_indices_double
     generic :: get_value_at_indices => &
          get_value_at_indices_int, &
          get_value_at_indices_float, &
          get_value_at_indices_double

     ! --- Set value functions (3 type variants + generic) ---
     ! Copy variable data INTO the model from caller's array.
     procedure :: set_value_int => wrfhydro_set_int
     procedure :: set_value_float => wrfhydro_set_float
     procedure :: set_value_double => wrfhydro_set_double
     generic :: set_value => &
          set_value_int, &
          set_value_float, &
          set_value_double

     ! --- Set value at indices functions (3 type variants + generic) ---
     ! Set specific elements by their flat array indices.
     procedure :: set_value_at_indices_int => wrfhydro_set_at_indices_int
     procedure :: set_value_at_indices_float => wrfhydro_set_at_indices_float
     procedure :: set_value_at_indices_double => wrfhydro_set_at_indices_double
     generic :: set_value_at_indices => &
          set_value_at_indices_int, &
          set_value_at_indices_float, &
          set_value_at_indices_double

  end type bmi_wrf_hydro

  ! ==========================================================================
  ! MODULE-LEVEL CONSTANTS
  ! ==========================================================================
  ! These are shared by all instances of bmi_wrf_hydro (like class variables
  ! in Python). They define the model's identity and variable catalog.
  ! ==========================================================================

  private
  public :: bmi_wrf_hydro

  ! --- Model identity ---
  ! BMI_MAX_COMPONENT_NAME is defined in bmif_2_0 (typically 2048 chars).
  ! The "target" attribute allows pointers to point to this variable.
  character (len=BMI_MAX_COMPONENT_NAME), target :: &
       component_name = "WRF-Hydro v5.4.0 (NCAR)"

  ! --- Variable counts ---
  ! How many input/output variables this BMI exposes.
  ! Named N_INPUT_VARS / N_OUTPUT_VARS to avoid collision with the
  ! procedure names wrfhydro_input_item_count / wrfhydro_output_item_count.
  integer, parameter :: N_INPUT_VARS = 4
  integer, parameter :: N_OUTPUT_VARS = 8

  ! --- Variable name arrays ---
  ! BMI_MAX_VAR_NAME is defined in bmif_2_0 (typically 2048 chars).
  ! "target" allows get_var_names to return a pointer to these.
  character (len=BMI_MAX_VAR_NAME), target, &
       dimension(N_INPUT_VARS) :: input_items

  character (len=BMI_MAX_VAR_NAME), target, &
       dimension(N_OUTPUT_VARS) :: output_items

  ! --- Grid ID constants ---
  ! Named constants for readability. Using integer parameters so the
  ! compiler can optimize and catch typos at compile time.
  integer, parameter :: GRID_LSM = 0       ! 1km Noah-MP land surface grid
  integer, parameter :: GRID_ROUTING = 1   ! 250m terrain routing grid
  integer, parameter :: GRID_CHANNEL = 2   ! Vector channel network

! ============================================================================
! IMPLEMENTATION OF ALL BMI FUNCTIONS
! ============================================================================
! Everything below "contains" implements the 55 procedure bindings declared
! above. Each function follows the pattern:
!   function name(this, args...) result(bmi_status)
!     class(bmi_wrf_hydro), intent(...) :: this
!     ... argument declarations ...
!     integer :: bmi_status   ! return value: BMI_SUCCESS or BMI_FAILURE
!     ... implementation ...
!   end function name
! ============================================================================

contains

  ! **************************************************************************
  ! SECTION 1: CONTROL FUNCTIONS (4)
  ! **************************************************************************
  ! These manage the model lifecycle:
  !   initialize() -> Load config, call WRF-Hydro init routines
  !   update()     -> Advance one timestep
  !   update_until(t) -> Advance until time t
  !   finalize()   -> Clean up memory and files
  ! **************************************************************************

  ! --------------------------------------------------------------------------
  ! initialize: Set up the model from a configuration file.
  ! --------------------------------------------------------------------------
  ! This is the first BMI function any caller must invoke. It:
  !   1. Reads the BMI config file (Fortran namelist with run_dir path)
  !   2. Changes to the WRF-Hydro run directory
  !   3. Calls orchestrator%init() to read WRF-Hydro namelists
  !   4. Calls land_driver_ini() which internally calls HYDRO_ini()
  !   5. Captures grid dimensions from WRF-Hydro internal state
  !
  ! The config file format (Fortran namelist):
  !   &bmi_wrf_hydro_config
  !     wrfhydro_run_dir = "/path/to/run/directory/"
  !   /
  ! --------------------------------------------------------------------------
  function wrfhydro_initialize(this, config_file) result (bmi_status)
    use module_noahmp_hrldas_driver, only: land_driver_ini, IX, JX, &
         NSOIL, DTBL
    use module_RT_data, only: rt_domain
    use orchestrator_base, only: orchestrator

    class (bmi_wrf_hydro), intent(out) :: this
    character (len=*), intent(in) :: config_file
    integer :: bmi_status

    ! Local variables for config reading
    integer :: rc, fu
    character(len=256) :: wrfhydro_run_dir
    character(len=256) :: saved_dir
    integer :: ntime_local

    ! --- Guard: WRF-Hydro cannot be initialized twice ---
    ! WRF-Hydro's module-level arrays (COSZEN, SMOIS, etc.) are persistent.
    ! Once allocated (by land_driver_ini), they cannot be re-allocated
    ! without modifying WRF-Hydro source. The wrfhydro_engine_initialized
    ! flag (in wrfhydro_bmi_state_mod) tracks this permanently.

    ! Namelist definition — this tells Fortran how to parse the config file.
    ! The group name "&bmi_wrf_hydro_config" must match what's in the file.
    namelist /bmi_wrf_hydro_config/ wrfhydro_run_dir

    ! --- Step 1: Read the BMI configuration file ---
    wrfhydro_run_dir = ""

    if (len_trim(config_file) == 0) then
       bmi_status = BMI_FAILURE
       return
    end if

    ! Check if config file exists
    inquire(file=config_file, iostat=rc)
    if (rc /= 0) then
       bmi_status = BMI_FAILURE
       return
    end if

    ! Open and read the namelist
    open(action='read', file=trim(config_file), iostat=rc, newunit=fu)
    if (rc /= 0) then
       bmi_status = BMI_FAILURE
       return
    end if

    read(nml=bmi_wrf_hydro_config, iostat=rc, unit=fu)
    close(fu)

    if (rc /= 0) then
       bmi_status = BMI_FAILURE
       return
    end if

    this%run_dir = trim(wrfhydro_run_dir)

    ! --- Step 2: Change to WRF-Hydro run directory ---
    ! WRF-Hydro reads its namelists (namelist.hrldas, hydro.namelist) from
    ! the current working directory, so we must chdir there before init.
    call getcwd(saved_dir)
    call chdir(trim(this%run_dir), rc)
    if (rc /= 0) then
       bmi_status = BMI_FAILURE
       return
    end if

    ! --- Step 3: Initialize WRF-Hydro (only if engine not yet initialized) ---
    ! WRF-Hydro module-level arrays (COSZEN, SMOIS, etc.) persist across
    ! calls and cannot be re-allocated. We only call the WRF-Hydro init
    ! routines on the very first initialize. Subsequent initialize() calls
    ! (after finalize) just re-read dimensions from the persisted state.
    if (.not. wrfhydro_engine_initialized) then
       ! orchestrator%init() reads the configuration namelists.
       ! land_driver_ini() sets up Noah-MP + calls HYDRO_ini() internally.
       !
       ! NOTE: We use write(0,*) = stderr for debug output because
       ! HYDRO_ini (called inside land_driver_ini) redirects stdout
       ! (unit 6) to file "diag_hydro.00000" via open_print_mpp(6).
       ! After that redirect, print * goes to file, not terminal.

       ! --- MPI communicator fix for external init (Python/mpi4py) ---
       ! When MPI is already initialized by an external caller (e.g., mpi4py),
       ! WRF-Hydro's MPP_LAND_INIT skips MPI_Comm_dup, leaving HYDRO_COMM_WORLD
       ! as MPI_COMM_NULL. We must set it here before any WRF-Hydro code runs.
       block
          use mpi
          use MODULE_CPL_LAND, only: HYDRO_COMM_WORLD
          integer :: mpi_ierr
          logical :: mpi_is_init
          call MPI_Initialized(mpi_is_init, mpi_ierr)
          if (mpi_is_init .and. HYDRO_COMM_WORLD == MPI_COMM_NULL) then
             call MPI_Comm_dup(MPI_COMM_WORLD, HYDRO_COMM_WORLD, mpi_ierr)
             write(0,*) "[BMI] Set HYDRO_COMM_WORLD from pre-initialized MPI"
          end if
       end block

       write(0,*) "[BMI] Calling orchestrator%init()..."
       call orchestrator%init()
       write(0,*) "[BMI] Calling land_driver_ini()..."
       call land_driver_ini(ntime_local, wrfhydro_bmi_state)
       write(0,*) "[BMI] land_driver_ini() complete. ntime =", ntime_local
       wrfhydro_engine_initialized = .true.
       wrfhydro_saved_ntime = ntime_local  ! persist for re-init
    else
       ! Engine already initialized from a previous BMI lifecycle.
       ! intent(out) resets all type fields, so we restore ntime from
       ! the module-level saved value.
       ntime_local = wrfhydro_saved_ntime
    end if

    ! --- Step 4: Capture grid dimensions from WRF-Hydro state ---
    ! These module-level variables persist across calls, so safe to read
    ! even on re-initialization.
    if (ntime_local == 0) ntime_local = 1  ! safety fallback
    this%ntime = ntime_local
    this%ix = IX           ! From module_noahmp_hrldas_driver
    this%jx = JX           ! From module_noahmp_hrldas_driver
    this%nsoil = NSOIL     ! From module_noahmp_hrldas_driver
    this%dt = dble(DTBL)   ! Timestep in seconds (REAL -> double)

    ! Routing grid dimensions from rt_domain (populated by HYDRO_ini)
    this%ixrt = rt_domain(1)%IXRT
    this%jxrt = rt_domain(1)%JXRT
    this%nlinks = rt_domain(1)%NLINKS

    ! Grid spacing from namelist config (rt_domain%DX is never set).
    ! nlst(1)%dxrt0 = the routing grid spacing from hydro.namelist (DXRT).
    ! LSM spacing = routing spacing * aggregation factor (IXRT/IX).
    ! Example: Croton NY -> DXRT=250m, AGGFACT=4, LSM=1000m.
    block
       use config_base, only: nlst
       this%dx_rt = dble(nlst(1)%dxrt0)
       if (this%ixrt > 0 .and. this%ix > 0) then
          this%dx_lsm = this%dx_rt * dble(this%ixrt) / dble(this%ix)
       else
          this%dx_lsm = this%dx_rt   ! fallback
       end if
    end block

    ! --- Step 5: Set up time tracking ---
    this%start_time = 0.0d0
    this%current_time = 0.0d0
    this%end_time = dble(this%ntime) * this%dt
    this%current_timestep = 0

    ! --- Step 6: Allocate coupling placeholders ---
    if (.not. allocated(this%sea_water_elevation)) then
       allocate(this%sea_water_elevation(this%ix, this%jx))
       this%sea_water_elevation = 0.0d0
    end if
    if (.not. allocated(this%sea_water_x_velocity)) then
       allocate(this%sea_water_x_velocity(this%ix, this%jx))
       this%sea_water_x_velocity = 0.0d0
    end if

    ! --- Step 7: Change back to original directory ---
    call chdir(trim(saved_dir), rc)

    this%initialized = .true.
    bmi_status = BMI_SUCCESS
  end function wrfhydro_initialize

  ! --------------------------------------------------------------------------
  ! update: Advance the model by exactly ONE timestep.
  ! --------------------------------------------------------------------------
  ! This is the heart of the BMI pattern. Each call:
  !   1. Increments the timestep counter
  !   2. Changes to the WRF-Hydro run directory (for I/O)
  !   3. Calls land_driver_exe() which runs Noah-MP + HYDRO_exe()
  !   4. Updates the current time
  !   5. Changes back to original directory
  ! --------------------------------------------------------------------------
  function wrfhydro_update(this) result (bmi_status)
    use module_noahmp_hrldas_driver, only: land_driver_exe

    class (bmi_wrf_hydro), intent(inout) :: this
    integer :: bmi_status
    integer :: rc
    character(len=256) :: saved_dir

    if (.not. this%initialized) then
       bmi_status = BMI_FAILURE
       return
    end if

    ! Increment timestep counter (WRF-Hydro uses 1-based timesteps)
    this%current_timestep = this%current_timestep + 1

    ! Change to run directory for file I/O
    call getcwd(saved_dir)
    call chdir(trim(this%run_dir), rc)

    ! Execute one timestep of Noah-MP land surface + HYDRO routing
    call land_driver_exe(this%current_timestep, wrfhydro_bmi_state)

    ! Update time tracking
    this%current_time = dble(this%current_timestep) * this%dt

    ! Return to original directory
    call chdir(trim(saved_dir), rc)

    bmi_status = BMI_SUCCESS
  end function wrfhydro_update

  ! --------------------------------------------------------------------------
  ! update_until: Advance the model until a target time.
  ! --------------------------------------------------------------------------
  ! This calls update() in a loop until current_time >= target_time.
  ! If target_time is in the past, it returns BMI_FAILURE.
  !
  ! Example: If current_time=3600 and dt=3600, calling update_until(7200)
  ! will execute exactly one update() call.
  ! --------------------------------------------------------------------------
  function wrfhydro_update_until(this, time) result (bmi_status)
    class (bmi_wrf_hydro), intent(inout) :: this
    double precision, intent(in) :: time
    integer :: bmi_status
    integer :: n_steps, i, s

    ! Cannot go backward in time
    if (time < this%current_time) then
       bmi_status = BMI_FAILURE
       return
    end if

    ! Calculate how many steps needed (integer division, round down)
    n_steps = nint((time - this%current_time) / this%dt)

    ! Execute that many update() calls
    do i = 1, n_steps
       s = this%update()
       if (s /= BMI_SUCCESS) then
          bmi_status = BMI_FAILURE
          return
       end if
    end do

    bmi_status = BMI_SUCCESS
  end function wrfhydro_update_until

  ! --------------------------------------------------------------------------
  ! finalize: Clean up the model — free memory, close files.
  ! --------------------------------------------------------------------------
  ! IMPORTANT: We do NOT call HYDRO_finish() because it contains a "stop"
  ! statement (line 1827/1831 of module_HYDRO_drv.F90) which would terminate
  ! the entire process. Instead, we do our own cleanup.
  !
  ! Every initialize() must have a matching finalize(). Failing to call
  ! finalize can leak memory or leave output files unclosed.
  ! --------------------------------------------------------------------------
  function wrfhydro_finalize(this) result (bmi_status)
    class (bmi_wrf_hydro), intent(inout) :: this
    integer :: bmi_status

    ! Deallocate coupling placeholders
    if (allocated(this%sea_water_elevation)) &
         deallocate(this%sea_water_elevation)
    if (allocated(this%sea_water_x_velocity)) &
         deallocate(this%sea_water_x_velocity)

    ! Reset state tracking
    this%initialized = .false.
    this%current_timestep = 0
    this%current_time = 0.0d0

    bmi_status = BMI_SUCCESS
  end function wrfhydro_finalize


  ! **************************************************************************
  ! SECTION 2: MODEL INFO FUNCTIONS (5)
  ! **************************************************************************
  ! These provide metadata about the model for discovery and introspection.
  ! A coupling framework (PyMT) uses these to find out what a model offers.
  ! **************************************************************************

  ! --------------------------------------------------------------------------
  ! get_component_name: Return the model's human-readable name.
  ! --------------------------------------------------------------------------
  function wrfhydro_component_name(this, name) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), pointer, intent(out) :: name
    integer :: bmi_status

    ! "=>" is pointer assignment (not copy). The caller gets a reference
    ! to our module-level string, not a copy. This is the BMI convention.
    name => component_name
    bmi_status = BMI_SUCCESS
  end function wrfhydro_component_name

  ! --------------------------------------------------------------------------
  ! get_input_item_count: How many input variables does the model accept?
  ! --------------------------------------------------------------------------
  function wrfhydro_input_item_count(this, count) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(out) :: count
    integer :: bmi_status

    count = N_INPUT_VARS
    bmi_status = BMI_SUCCESS
  end function wrfhydro_input_item_count

  ! --------------------------------------------------------------------------
  ! get_output_item_count: How many output variables does the model produce?
  ! --------------------------------------------------------------------------
  function wrfhydro_output_item_count(this, count) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(out) :: count
    integer :: bmi_status

    count = N_OUTPUT_VARS
    bmi_status = BMI_SUCCESS
  end function wrfhydro_output_item_count

  ! --------------------------------------------------------------------------
  ! get_input_var_names: Return the list of input variable names.
  ! --------------------------------------------------------------------------
  ! Names follow the CSDMS Standard Names convention:
  !   <object>__<quantity> with double underscores, all lowercase.
  ! This enables interoperability between different models.
  ! --------------------------------------------------------------------------
  function wrfhydro_input_var_names(this, names) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (*), pointer, intent(out) :: names(:)
    integer :: bmi_status

    ! Precipitation rate entering the land model
    input_items(1) = 'atmosphere_water__precipitation_leq-volume_flux'
    ! 2-meter air temperature (also an output — shared variable)
    input_items(2) = 'land_surface_air__temperature'
    ! Coastal water level from SCHISM (for 2-way coupling)
    input_items(3) = 'sea_water_surface__elevation'
    ! Coastal current velocity from SCHISM (for 2-way coupling)
    input_items(4) = 'sea_water__x_velocity'

    names => input_items
    bmi_status = BMI_SUCCESS
  end function wrfhydro_input_var_names

  ! --------------------------------------------------------------------------
  ! get_output_var_names: Return the list of output variable names.
  ! --------------------------------------------------------------------------
  function wrfhydro_output_var_names(this, names) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (*), pointer, intent(out) :: names(:)
    integer :: bmi_status

    ! Streamflow in channel network (Muskingum-Cunge routing output)
    output_items(1) = 'channel_water__volume_flow_rate'
    ! Surface water depth on terrain routing grid
    output_items(2) = 'land_surface_water__depth'
    ! Volumetric soil moisture (top layer)
    output_items(3) = 'soil_water__volume_fraction'
    ! Snow water equivalent
    output_items(4) = 'snowpack__liquid-equivalent_depth'
    ! Total evapotranspiration (canopy + transpiration + direct soil)
    output_items(5) = 'land_surface_water__evaporation_volume_flux'
    ! Accumulated surface runoff
    output_items(6) = 'land_surface_water__runoff_volume_flux'
    ! Accumulated subsurface baseflow
    output_items(7) = 'soil_water__domain_time_integral_of_baseflow_volume_flux'
    ! 2-meter air temperature
    output_items(8) = 'land_surface_air__temperature'

    names => output_items
    bmi_status = BMI_SUCCESS
  end function wrfhydro_output_var_names


  ! **************************************************************************
  ! SECTION 3: VARIABLE INFO FUNCTIONS (6)
  ! **************************************************************************
  ! For each variable, these functions provide metadata: data type, units,
  ! grid assignment, memory footprint, and spatial location on the grid.
  ! **************************************************************************

  ! --------------------------------------------------------------------------
  ! get_var_type: Return the data type of a variable as a string.
  ! --------------------------------------------------------------------------
  ! WRF-Hydro stores all physical variables as single-precision REAL (4 bytes).
  ! BMI convention for PyMT is to report the native storage type.
  ! The get_value_double functions handle REAL->double conversion internally.
  ! --------------------------------------------------------------------------
  function wrfhydro_var_type(this, name, type) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    character (len=*), intent(out) :: type
    integer :: bmi_status

    select case(name)
    ! All WRF-Hydro physical variables are stored as REAL (single precision)
    case('channel_water__volume_flow_rate', &
         'land_surface_water__depth', &
         'soil_water__volume_fraction', &
         'snowpack__liquid-equivalent_depth', &
         'land_surface_water__evaporation_volume_flux', &
         'land_surface_water__runoff_volume_flux', &
         'soil_water__domain_time_integral_of_baseflow_volume_flux', &
         'land_surface_air__temperature', &
         'atmosphere_water__precipitation_leq-volume_flux')
       type = "double precision"
       bmi_status = BMI_SUCCESS
    ! Coupling placeholders are stored as double precision
    case('sea_water_surface__elevation', &
         'sea_water__x_velocity')
       type = "double precision"
       bmi_status = BMI_SUCCESS
    case default
       type = "-"
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_var_type

  ! --------------------------------------------------------------------------
  ! get_var_units: Return the units of a variable (UDUNITS-compatible).
  ! --------------------------------------------------------------------------
  function wrfhydro_var_units(this, name, units) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    character (len=*), intent(out) :: units
    integer :: bmi_status

    select case(name)
    case('channel_water__volume_flow_rate')
       units = "m3 s-1"          ! Cubic meters per second
       bmi_status = BMI_SUCCESS
    case('land_surface_water__depth')
       units = "m"               ! Meters
       bmi_status = BMI_SUCCESS
    case('soil_water__volume_fraction')
       units = "1"               ! Dimensionless (m3/m3)
       bmi_status = BMI_SUCCESS
    case('snowpack__liquid-equivalent_depth')
       units = "mm"              ! Millimeters of water equivalent
       bmi_status = BMI_SUCCESS
    case('land_surface_water__evaporation_volume_flux')
       units = "mm"              ! Accumulated ET in mm
       bmi_status = BMI_SUCCESS
    case('land_surface_water__runoff_volume_flux')
       units = "m"               ! Accumulated runoff in meters
       bmi_status = BMI_SUCCESS
    case('soil_water__domain_time_integral_of_baseflow_volume_flux')
       units = "mm"              ! Accumulated baseflow in mm
       bmi_status = BMI_SUCCESS
    case('land_surface_air__temperature')
       units = "K"               ! Kelvin
       bmi_status = BMI_SUCCESS
    case('atmosphere_water__precipitation_leq-volume_flux')
       units = "mm s-1"          ! Precipitation rate
       bmi_status = BMI_SUCCESS
    case('sea_water_surface__elevation')
       units = "m"               ! Meters above datum
       bmi_status = BMI_SUCCESS
    case('sea_water__x_velocity')
       units = "m s-1"           ! Meters per second
       bmi_status = BMI_SUCCESS
    case default
       units = "-"
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_var_units

  ! --------------------------------------------------------------------------
  ! get_var_grid: Return the grid ID for a variable.
  ! --------------------------------------------------------------------------
  ! Grid 0 = 1km LSM grid (IX x JX) — most land surface variables
  ! Grid 1 = 250m routing grid (IXRT x JXRT) — surface water depth
  ! Grid 2 = channel network (NLINKS) — streamflow
  ! --------------------------------------------------------------------------
  function wrfhydro_var_grid(this, name, grid) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    integer, intent(out) :: grid
    integer :: bmi_status

    select case(name)
    ! Channel network variables (Grid 2)
    case('channel_water__volume_flow_rate')
       grid = GRID_CHANNEL
       bmi_status = BMI_SUCCESS
    ! Routing grid variables (Grid 1)
    case('land_surface_water__depth')
       grid = GRID_ROUTING
       bmi_status = BMI_SUCCESS
    ! LSM grid variables (Grid 0)
    case('soil_water__volume_fraction', &
         'snowpack__liquid-equivalent_depth', &
         'land_surface_water__evaporation_volume_flux', &
         'land_surface_water__runoff_volume_flux', &
         'soil_water__domain_time_integral_of_baseflow_volume_flux', &
         'land_surface_air__temperature', &
         'atmosphere_water__precipitation_leq-volume_flux', &
         'sea_water_surface__elevation', &
         'sea_water__x_velocity')
       grid = GRID_LSM
       bmi_status = BMI_SUCCESS
    case default
       grid = -1
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_var_grid

  ! --------------------------------------------------------------------------
  ! get_var_itemsize: Return bytes per element of a variable.
  ! --------------------------------------------------------------------------
  ! WRF-Hydro uses single-precision REAL (4 bytes per element).
  ! But we report double precision (8 bytes) since that's what get_value
  ! returns after conversion.
  ! --------------------------------------------------------------------------
  function wrfhydro_var_itemsize(this, name, size) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    integer, intent(out) :: size
    integer :: bmi_status

    select case(name)
    case('channel_water__volume_flow_rate', &
         'land_surface_water__depth', &
         'soil_water__volume_fraction', &
         'snowpack__liquid-equivalent_depth', &
         'land_surface_water__evaporation_volume_flux', &
         'land_surface_water__runoff_volume_flux', &
         'soil_water__domain_time_integral_of_baseflow_volume_flux', &
         'land_surface_air__temperature', &
         'atmosphere_water__precipitation_leq-volume_flux', &
         'sea_water_surface__elevation', &
         'sea_water__x_velocity')
       size = 8   ! double precision = 8 bytes
       bmi_status = BMI_SUCCESS
    case default
       size = -1
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_var_itemsize

  ! --------------------------------------------------------------------------
  ! get_var_nbytes: Return total bytes needed for a variable.
  ! --------------------------------------------------------------------------
  ! Total bytes = itemsize * grid_size.
  ! This tells the caller how much memory to allocate for get_value().
  ! --------------------------------------------------------------------------
  function wrfhydro_var_nbytes(this, name, nbytes) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    integer, intent(out) :: nbytes
    integer :: bmi_status
    integer :: s1, s2, s3, grid, grid_size, item_size

    s1 = this%get_var_grid(name, grid)
    s2 = this%get_grid_size(grid, grid_size)
    s3 = this%get_var_itemsize(name, item_size)

    if ((s1 == BMI_SUCCESS) .and. (s2 == BMI_SUCCESS) .and. &
        (s3 == BMI_SUCCESS)) then
       nbytes = item_size * grid_size
       bmi_status = BMI_SUCCESS
    else
       nbytes = -1
       bmi_status = BMI_FAILURE
    end if
  end function wrfhydro_var_nbytes

  ! --------------------------------------------------------------------------
  ! get_var_location: Return where on the grid a variable is defined.
  ! --------------------------------------------------------------------------
  ! Possible values: "node", "edge", or "face".
  ! All WRF-Hydro variables live at grid nodes (cell centers).
  ! --------------------------------------------------------------------------
  function wrfhydro_var_location(this, name, location) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    character (len=*), intent(out) :: location
    integer :: bmi_status

    ! All known variables are node-centered. Unknown names return FAILURE.
    select case(name)
    case('channel_water__volume_flow_rate', &
         'land_surface_water__depth', &
         'soil_water__volume_fraction', &
         'snowpack__liquid-equivalent_depth', &
         'land_surface_water__evaporation_volume_flux', &
         'land_surface_water__runoff_volume_flux', &
         'soil_water__domain_time_integral_of_baseflow_volume_flux', &
         'land_surface_air__temperature', &
         'atmosphere_water__precipitation_leq-volume_flux', &
         'sea_water_surface__elevation', &
         'sea_water__x_velocity')
       location = "node"
       bmi_status = BMI_SUCCESS
    case default
       location = ""
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_var_location


  ! **************************************************************************
  ! SECTION 4: TIME FUNCTIONS (5)
  ! **************************************************************************
  ! Report the model's temporal state. All times are in seconds since
  ! the start of the simulation (epoch = model start time).
  ! **************************************************************************

  ! --------------------------------------------------------------------------
  ! get_start_time: Model start time (always 0.0 seconds).
  ! --------------------------------------------------------------------------
  function wrfhydro_start_time(this, time) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    double precision, intent(out) :: time
    integer :: bmi_status

    time = this%start_time
    bmi_status = BMI_SUCCESS
  end function wrfhydro_start_time

  ! --------------------------------------------------------------------------
  ! get_end_time: Model end time (ntime * dt seconds).
  ! --------------------------------------------------------------------------
  function wrfhydro_end_time(this, time) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    double precision, intent(out) :: time
    integer :: bmi_status

    time = this%end_time
    bmi_status = BMI_SUCCESS
  end function wrfhydro_end_time

  ! --------------------------------------------------------------------------
  ! get_current_time: How far the model has advanced (in seconds).
  ! --------------------------------------------------------------------------
  function wrfhydro_current_time(this, time) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    double precision, intent(out) :: time
    integer :: bmi_status

    time = this%current_time
    bmi_status = BMI_SUCCESS
  end function wrfhydro_current_time

  ! --------------------------------------------------------------------------
  ! get_time_step: Timestep size in seconds (typically 3600s = 1 hour).
  ! --------------------------------------------------------------------------
  function wrfhydro_time_step(this, time_step) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    double precision, intent(out) :: time_step
    integer :: bmi_status

    time_step = this%dt
    bmi_status = BMI_SUCCESS
  end function wrfhydro_time_step

  ! --------------------------------------------------------------------------
  ! get_time_units: Units string for time values (always "s" = seconds).
  ! --------------------------------------------------------------------------
  function wrfhydro_time_units(this, units) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(out) :: units
    integer :: bmi_status

    units = "s"
    bmi_status = BMI_SUCCESS
  end function wrfhydro_time_units


  ! **************************************************************************
  ! SECTION 5: GRID FUNCTIONS (17)
  ! **************************************************************************
  ! These describe the spatial grids that variables live on.
  !
  ! WRF-Hydro has 3 grids:
  !   Grid 0 (GRID_LSM):     1km uniform rectilinear, rank 2, IX x JX
  !   Grid 1 (GRID_ROUTING): 250m uniform rectilinear, rank 2, IXRT x JXRT
  !   Grid 2 (GRID_CHANNEL): vector/network, rank 1, NLINKS
  !
  ! For uniform rectilinear grids, BMI uses:
  !   shape   = [n_rows, n_cols]  (Y first, then X — C-order)
  !   spacing = [dy, dx]          (Y first, then X)
  !   origin  = [y0, x0]         (Y first, then X)
  !
  ! For vector grids, BMI uses get_grid_x/y/z for node coordinates.
  ! **************************************************************************

  ! --------------------------------------------------------------------------
  ! get_grid_type: Return the grid type as a string.
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_type(this, grid, type) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    character (len=*), intent(out) :: type
    integer :: bmi_status

    select case(grid)
    case(GRID_LSM)
       type = "uniform_rectilinear"
       bmi_status = BMI_SUCCESS
    case(GRID_ROUTING)
       type = "uniform_rectilinear"
       bmi_status = BMI_SUCCESS
    case(GRID_CHANNEL)
       type = "vector"
       bmi_status = BMI_SUCCESS
    case default
       type = "-"
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_type

  ! --------------------------------------------------------------------------
  ! get_grid_rank: Number of dimensions of a grid.
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_rank(this, grid, rank) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, intent(out) :: rank
    integer :: bmi_status

    select case(grid)
    case(GRID_LSM)
       rank = 2     ! 2D: rows x columns
       bmi_status = BMI_SUCCESS
    case(GRID_ROUTING)
       rank = 2     ! 2D: rows x columns (finer resolution)
       bmi_status = BMI_SUCCESS
    case(GRID_CHANNEL)
       rank = 1     ! 1D: linear network of links
       bmi_status = BMI_SUCCESS
    case default
       rank = -1
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_rank

  ! --------------------------------------------------------------------------
  ! get_grid_shape: Dimensions of a grid [n_rows, n_cols].
  ! --------------------------------------------------------------------------
  ! BMI convention: shape is in C-order (row-major): [n_y, n_x].
  ! For WRF-Hydro, JX is Y-direction (rows) and IX is X-direction (columns).
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_shape(this, grid, shape) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, dimension(:), intent(out) :: shape
    integer :: bmi_status

    select case(grid)
    case(GRID_LSM)
       shape(:) = [this%jx, this%ix]     ! [n_rows, n_cols]
       bmi_status = BMI_SUCCESS
    case(GRID_ROUTING)
       shape(:) = [this%jxrt, this%ixrt] ! [n_rows, n_cols]
       bmi_status = BMI_SUCCESS
    case(GRID_CHANNEL)
       ! Vector/network grids do NOT have a regular shape.
       shape(:) = -1
       bmi_status = BMI_FAILURE
    case default
       shape(:) = -1
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_shape

  ! --------------------------------------------------------------------------
  ! get_grid_size: Total number of elements in a grid.
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_size(this, grid, size) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, intent(out) :: size
    integer :: bmi_status

    select case(grid)
    case(GRID_LSM)
       size = this%ix * this%jx           ! e.g., 15 * 16 = 240
       bmi_status = BMI_SUCCESS
    case(GRID_ROUTING)
       size = this%ixrt * this%jxrt       ! e.g., 60 * 64 = 3840
       bmi_status = BMI_SUCCESS
    case(GRID_CHANNEL)
       size = this%nlinks                 ! e.g., ~200 for Croton
       bmi_status = BMI_SUCCESS
    case default
       size = -1
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_size

  ! --------------------------------------------------------------------------
  ! get_grid_spacing: Distance between nodes [dy, dx] in meters.
  ! --------------------------------------------------------------------------
  ! Only valid for uniform rectilinear grids (Grids 0 and 1).
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_spacing(this, grid, spacing) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    double precision, dimension(:), intent(out) :: spacing
    integer :: bmi_status

    select case(grid)
    case(GRID_LSM)
       spacing(:) = [this%dx_lsm, this%dx_lsm]  ! [dy, dx] both same
       bmi_status = BMI_SUCCESS
    case(GRID_ROUTING)
       spacing(:) = [this%dx_rt, this%dx_rt]     ! [dy, dx] both same
       bmi_status = BMI_SUCCESS
    case default
       spacing(:) = -1.d0
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_spacing

  ! --------------------------------------------------------------------------
  ! get_grid_origin: Coordinates of the grid origin [y0, x0].
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_origin(this, grid, origin) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    double precision, dimension(:), intent(out) :: origin
    integer :: bmi_status

    select case(grid)
    case(GRID_LSM)
       origin(:) = [0.d0, 0.d0]   ! Origin at (0,0)
       bmi_status = BMI_SUCCESS
    case(GRID_ROUTING)
       origin(:) = [0.d0, 0.d0]   ! Origin at (0,0)
       bmi_status = BMI_SUCCESS
    case default
       origin(:) = -1.d0
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_origin

  ! --------------------------------------------------------------------------
  ! get_grid_x: X-coordinates of grid nodes.
  ! --------------------------------------------------------------------------
  ! For channel network (Grid 2), returns longitude of each link.
  ! For rectilinear grids, not typically used (spacing+origin suffice).
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_x(this, grid, x) result (bmi_status)
    use module_RT_data, only: rt_domain

    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    double precision, dimension(:), intent(out) :: x
    integer :: bmi_status
    integer :: i

    select case(grid)
    case(GRID_CHANNEL)
       ! Channel link longitude from rt_domain
       if (allocated(rt_domain(1)%CHLON)) then
          do i = 1, min(this%nlinks, size(x))
             x(i) = dble(rt_domain(1)%CHLON(i))
          end do
          bmi_status = BMI_SUCCESS
       else
          x(:) = -1.d0
          bmi_status = BMI_FAILURE
       end if
    case default
       x(:) = -1.d0
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_x

  ! --------------------------------------------------------------------------
  ! get_grid_y: Y-coordinates of grid nodes.
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_y(this, grid, y) result (bmi_status)
    use module_RT_data, only: rt_domain

    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    double precision, dimension(:), intent(out) :: y
    integer :: bmi_status
    integer :: i

    select case(grid)
    case(GRID_CHANNEL)
       ! Channel link latitude from rt_domain
       if (allocated(rt_domain(1)%CHLAT)) then
          do i = 1, min(this%nlinks, size(y))
             y(i) = dble(rt_domain(1)%CHLAT(i))
          end do
          bmi_status = BMI_SUCCESS
       else
          y(:) = -1.d0
          bmi_status = BMI_FAILURE
       end if
    case default
       y(:) = -1.d0
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_y

  ! --------------------------------------------------------------------------
  ! get_grid_z: Z-coordinates of grid nodes.
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_z(this, grid, z) result (bmi_status)
    use module_RT_data, only: rt_domain

    class (bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    double precision, dimension(:), intent(out) :: z
    integer :: bmi_status
    integer :: i

    select case(grid)
    case(GRID_CHANNEL)
       ! Channel node elevation from rt_domain
       if (allocated(rt_domain(1)%ZELEV)) then
          do i = 1, min(this%nlinks, size(z))
             z(i) = dble(rt_domain(1)%ZELEV(i))
          end do
          bmi_status = BMI_SUCCESS
       else
          z(:) = -1.d0
          bmi_status = BMI_FAILURE
       end if
    case default
       z(:) = -1.d0
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_z

  ! --------------------------------------------------------------------------
  ! get_grid_node_count: Number of nodes in a grid.
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_node_count(this, grid, count) result(bmi_status)
    class(bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, intent(out) :: count
    integer :: bmi_status

    select case(grid)
    case(GRID_LSM, GRID_ROUTING, GRID_CHANNEL)
       bmi_status = this%get_grid_size(grid, count)
    case default
       count = -1
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_node_count

  ! --------------------------------------------------------------------------
  ! get_grid_edge_count: Number of edges in a grid.
  ! --------------------------------------------------------------------------
  ! Only applicable to unstructured grids. For WRF-Hydro's structured and
  ! vector grids, we return BMI_FAILURE.
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_edge_count(this, grid, count) result(bmi_status)
    class(bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, intent(out) :: count
    integer :: bmi_status

    select case(grid)
    case(GRID_CHANNEL)
       ! In a channel network, each link is an edge.
       count = this%nlinks
       bmi_status = BMI_SUCCESS
    case default
       count = -1
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_edge_count

  ! --------------------------------------------------------------------------
  ! get_grid_face_count: Number of faces in a grid.
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_face_count(this, grid, count) result(bmi_status)
    class(bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, intent(out) :: count
    integer :: bmi_status

    select case(grid)
    case(GRID_CHANNEL)
       ! 1D channel network has no faces.
       count = 0
       bmi_status = BMI_SUCCESS
    case default
       count = -1
       bmi_status = BMI_FAILURE
    end select
  end function wrfhydro_grid_face_count

  ! --------------------------------------------------------------------------
  ! get_grid_edge_nodes: Edge-node connectivity (unstructured only).
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_edge_nodes(this, grid, edge_nodes) result(bmi_status)
    class(bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, dimension(:), intent(out) :: edge_nodes
    integer :: bmi_status

    edge_nodes(:) = -1
    bmi_status = BMI_FAILURE
  end function wrfhydro_grid_edge_nodes

  ! --------------------------------------------------------------------------
  ! get_grid_face_edges: Face-edge connectivity (unstructured only).
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_face_edges(this, grid, face_edges) result(bmi_status)
    class(bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, dimension(:), intent(out) :: face_edges
    integer :: bmi_status

    face_edges(:) = -1
    bmi_status = BMI_FAILURE
  end function wrfhydro_grid_face_edges

  ! --------------------------------------------------------------------------
  ! get_grid_face_nodes: Face-node connectivity (unstructured only).
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_face_nodes(this, grid, face_nodes) result(bmi_status)
    class(bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, dimension(:), intent(out) :: face_nodes
    integer :: bmi_status

    face_nodes(:) = -1
    bmi_status = BMI_FAILURE
  end function wrfhydro_grid_face_nodes

  ! --------------------------------------------------------------------------
  ! get_grid_nodes_per_face: Number of nodes per face (unstructured only).
  ! --------------------------------------------------------------------------
  function wrfhydro_grid_nodes_per_face(this, grid, nodes_per_face) &
       result(bmi_status)
    class(bmi_wrf_hydro), intent(in) :: this
    integer, intent(in) :: grid
    integer, dimension(:), intent(out) :: nodes_per_face
    integer :: bmi_status

    nodes_per_face(:) = -1
    bmi_status = BMI_FAILURE
  end function wrfhydro_grid_nodes_per_face


  ! **************************************************************************
  ! SECTION 6: GET VALUE FUNCTIONS (9 = 3 types x 3 access patterns)
  ! **************************************************************************
  ! These copy variable data OUT of WRF-Hydro into the caller's arrays.
  !
  ! Three access patterns:
  !   get_value         -> Copy entire variable (flattened to 1D)
  !   get_value_ptr     -> Return a pointer to internal data (zero-copy)
  !   get_value_at_indices -> Get specific elements by flat index
  !
  ! Three data types: int, float (single), double.
  ! WRF-Hydro stores everything as REAL. We support double precision
  ! as the primary interface (with dble() conversion) and return
  ! BMI_FAILURE for int and float variants (not used for WRF-Hydro vars).
  !
  ! KEY DESIGN: All arrays are flattened to 1D. A 2D array of shape
  ! (IX, JX) becomes a 1D array of size IX*JX using Fortran's column-major
  ! memory layout (which is natural with reshape()).
  ! **************************************************************************

  ! --------------------------------------------------------------------------
  ! get_value_int: Get integer variable values (not used by WRF-Hydro).
  ! --------------------------------------------------------------------------
  function wrfhydro_get_int(this, name, dest) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    integer, intent(inout) :: dest(:)
    integer :: bmi_status

    ! WRF-Hydro physical variables are all floating-point, not integer.
    dest(:) = -1
    bmi_status = BMI_FAILURE
  end function wrfhydro_get_int

  ! --------------------------------------------------------------------------
  ! get_value_float: Get single-precision float values (not primary).
  ! --------------------------------------------------------------------------
  function wrfhydro_get_float(this, name, dest) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    real, intent(inout) :: dest(:)
    integer :: bmi_status

    ! We report type as "double precision", so callers should use get_double.
    dest(:) = -1.0
    bmi_status = BMI_FAILURE
  end function wrfhydro_get_float

  ! --------------------------------------------------------------------------
  ! get_value_double: Get double-precision values (PRIMARY get function).
  ! --------------------------------------------------------------------------
  ! This is the main data access function. For each recognized variable name,
  ! it accesses WRF-Hydro's internal state and copies values to dest(:).
  !
  ! WRF-Hydro stores data as REAL (4 bytes). We convert to double precision
  ! using dble() for compatibility with BMI and PyMT expectations.
  !
  ! All 2D arrays are flattened to 1D using reshape() which uses Fortran's
  ! column-major memory layout (first index varies fastest).
  ! --------------------------------------------------------------------------
  function wrfhydro_get_double(this, name, dest) result (bmi_status)
    use module_noahmp_hrldas_driver, only: SMOIS, SFCRUNOFF, UDRUNOFF, &
         RAINBL, T2MVXY, ACCECAN, ACCETRAN, ACCEDIR, sfcheadrt, IX, JX
    use module_RT_data, only: rt_domain

    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    double precision, intent(inout) :: dest(:)
    integer :: bmi_status
    integer :: i

    select case(name)

    ! --- Output variable 1: Streamflow (m3/s) ---
    ! Source: rt_domain(1)%QLINK(:,2) — column 2 = current outflow
    ! QLINK is (NLINKS, 2) where:
    !   column 1 = previous timestep outflow
    !   column 2 = current timestep outflow (what we want)
    case('channel_water__volume_flow_rate')
       if (allocated(rt_domain(1)%QLINK)) then
          do i = 1, min(this%nlinks, size(dest))
             dest(i) = dble(rt_domain(1)%QLINK(i, 2))
          end do
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Output variable 2: Surface water depth (m) ---
    ! Source: rt_domain(1)%overland%control%surface_water_head_routing
    ! This is at routing resolution (IXRT x JXRT = 250m)
    case('land_surface_water__depth')
       if (this%ixrt > 0 .and. this%jxrt > 0) then
          dest(1:this%ixrt*this%jxrt) = dble(reshape( &
               rt_domain(1)%overland%control%surface_water_head_routing, &
               [this%ixrt * this%jxrt]))
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Output variable 3: Soil moisture (dimensionless, m3/m3) ---
    ! Source: SMOIS(:,1,:) — top soil layer only
    ! SMOIS is 3D: (IX, NSOIL, JX). We extract layer 1 -> (IX, JX) -> 1D
    case('soil_water__volume_fraction')
       if (allocated(SMOIS)) then
          dest(1:this%ix*this%jx) = dble(reshape( &
               SMOIS(1:this%ix, 1, 1:this%jx), [this%ix * this%jx]))
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Output variable 4: Snow water equivalent (mm) ---
    ! Source: wrfhydro_bmi_state%SNOW(:,:) — from state_type
    ! This is the SWE (Snow Water Equivalent) in mm of water.
    case('snowpack__liquid-equivalent_depth')
       if (allocated(wrfhydro_bmi_state%SNOW)) then
          dest(1:this%ix*this%jx) = dble(reshape( &
               wrfhydro_bmi_state%SNOW(1:this%ix, 1:this%jx), &
               [this%ix * this%jx]))
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Output variable 5: Evapotranspiration (mm) ---
    ! Source: ACCECAN + ACCETRAN + ACCEDIR (accumulated canopy evap +
    !         transpiration + direct soil evap)
    ! These are all (IX, JX) arrays in mm.
    case('land_surface_water__evaporation_volume_flux')
       if (allocated(ACCECAN) .and. allocated(ACCETRAN) .and. &
           allocated(ACCEDIR)) then
          dest(1:this%ix*this%jx) = dble(reshape( &
               ACCECAN(1:this%ix, 1:this%jx) + &
               ACCETRAN(1:this%ix, 1:this%jx) + &
               ACCEDIR(1:this%ix, 1:this%jx), &
               [this%ix * this%jx]))
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Output variable 6: Surface runoff (m) ---
    ! Source: SFCRUNOFF(:,:) — accumulated surface runoff in meters
    case('land_surface_water__runoff_volume_flux')
       if (allocated(SFCRUNOFF)) then
          dest(1:this%ix*this%jx) = dble(reshape( &
               SFCRUNOFF(1:this%ix, 1:this%jx), [this%ix * this%jx]))
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Output variable 7: Baseflow (mm) ---
    ! Source: UDRUNOFF(:,:) — accumulated sub-surface runoff in mm
    case('soil_water__domain_time_integral_of_baseflow_volume_flux')
       if (allocated(UDRUNOFF)) then
          dest(1:this%ix*this%jx) = dble(reshape( &
               UDRUNOFF(1:this%ix, 1:this%jx), [this%ix * this%jx]))
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Output variable 8: 2-meter air temperature (K) ---
    ! Source: T2MVXY(:,:) — 2m temperature of vegetation part
    ! NOTE: WRF-Hydro initializes T2MVXY to "undefined_real" (~9.97E+036)
    ! for cells that haven't been computed (water cells, etc.).
    ! We replace those sentinel values with 0.0 for clean BMI output.
    case('land_surface_air__temperature')
       if (allocated(T2MVXY)) then
          dest(1:this%ix*this%jx) = dble(reshape( &
               T2MVXY(1:this%ix, 1:this%jx), [this%ix * this%jx]))
          ! Replace WRF-Hydro's undefined_real sentinel with 0
          do i = 1, this%ix * this%jx
             if (abs(dest(i)) > 1.0d30) dest(i) = 0.0d0
          end do
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Input variable 1: Precipitation rate (mm/s) ---
    ! Source: RAINBL(:,:) — precipitation entering land model
    case('atmosphere_water__precipitation_leq-volume_flux')
       if (allocated(RAINBL)) then
          dest(1:this%ix*this%jx) = dble(reshape( &
               RAINBL(1:this%ix, 1:this%jx), [this%ix * this%jx]))
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Input variable 3: Sea water elevation (m) ---
    ! Source: BMI type member (coupling placeholder)
    case('sea_water_surface__elevation')
       if (allocated(this%sea_water_elevation)) then
          dest(1:this%ix*this%jx) = reshape( &
               this%sea_water_elevation(1:this%ix, 1:this%jx), &
               [this%ix * this%jx])
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    ! --- Input variable 4: Sea water velocity (m/s) ---
    ! Source: BMI type member (coupling placeholder)
    case('sea_water__x_velocity')
       if (allocated(this%sea_water_x_velocity)) then
          dest(1:this%ix*this%jx) = reshape( &
               this%sea_water_x_velocity(1:this%ix, 1:this%jx), &
               [this%ix * this%jx])
          bmi_status = BMI_SUCCESS
       else
          dest(:) = 0.0d0
          bmi_status = BMI_SUCCESS
       end if

    case default
       dest(:) = -1.d0
       bmi_status = BMI_FAILURE

    end select
  end function wrfhydro_get_double

  ! --------------------------------------------------------------------------
  ! get_value_ptr_int: Return pointer to integer data (not used).
  ! --------------------------------------------------------------------------
  function wrfhydro_get_ptr_int(this, name, dest_ptr) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    integer, pointer, intent(inout) :: dest_ptr(:)
    integer :: bmi_status

    bmi_status = BMI_FAILURE
  end function wrfhydro_get_ptr_int

  ! --------------------------------------------------------------------------
  ! get_value_ptr_float: Return pointer to float data (not used).
  ! --------------------------------------------------------------------------
  function wrfhydro_get_ptr_float(this, name, dest_ptr) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    real, pointer, intent(inout) :: dest_ptr(:)
    integer :: bmi_status

    bmi_status = BMI_FAILURE
  end function wrfhydro_get_ptr_float

  ! --------------------------------------------------------------------------
  ! get_value_ptr_double: Return pointer to double data (not used in Phase 1).
  ! --------------------------------------------------------------------------
  ! NOTE: get_value_ptr is tricky because WRF-Hydro stores data as REAL
  ! (single precision), but BMI expects double precision pointers.
  ! We cannot safely return a double pointer to single-precision data.
  ! In Phase 2, we may add internal double-precision shadow arrays.
  ! --------------------------------------------------------------------------
  function wrfhydro_get_ptr_double(this, name, dest_ptr) result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    double precision, pointer, intent(inout) :: dest_ptr(:)
    integer :: bmi_status

    bmi_status = BMI_FAILURE
  end function wrfhydro_get_ptr_double

  ! --------------------------------------------------------------------------
  ! get_value_at_indices_int: Get specific integer values (not used).
  ! --------------------------------------------------------------------------
  function wrfhydro_get_at_indices_int(this, name, dest, inds) &
       result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    integer, intent(inout) :: dest(:)
    integer, intent(in) :: inds(:)
    integer :: bmi_status

    dest(:) = -1
    bmi_status = BMI_FAILURE
  end function wrfhydro_get_at_indices_int

  ! --------------------------------------------------------------------------
  ! get_value_at_indices_float: Get specific float values (not used).
  ! --------------------------------------------------------------------------
  function wrfhydro_get_at_indices_float(this, name, dest, inds) &
       result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    real, intent(inout) :: dest(:)
    integer, intent(in) :: inds(:)
    integer :: bmi_status

    dest(:) = -1.0
    bmi_status = BMI_FAILURE
  end function wrfhydro_get_at_indices_float

  ! --------------------------------------------------------------------------
  ! get_value_at_indices_double: Get specific double values by flat index.
  ! --------------------------------------------------------------------------
  ! This gets specific elements from a variable using 1-based flat indices.
  ! It first gets the entire variable via get_value_double, then picks
  ! the requested elements. Not the most efficient, but simple and correct.
  ! --------------------------------------------------------------------------
  function wrfhydro_get_at_indices_double(this, name, dest, inds) &
       result (bmi_status)
    class (bmi_wrf_hydro), intent(in) :: this
    character (len=*), intent(in) :: name
    double precision, intent(inout) :: dest(:)
    integer, intent(in) :: inds(:)
    integer :: bmi_status
    double precision, allocatable :: full_array(:)
    integer :: grid, grid_size, i, s1, s2

    ! Get the grid size for this variable
    s1 = this%get_var_grid(name, grid)
    s2 = this%get_grid_size(grid, grid_size)

    if (s1 /= BMI_SUCCESS .or. s2 /= BMI_SUCCESS) then
       dest(:) = -1.d0
       bmi_status = BMI_FAILURE
       return
    end if

    ! Get the full array, then pick elements
    allocate(full_array(grid_size))
    bmi_status = this%get_value_double(name, full_array)

    if (bmi_status == BMI_SUCCESS) then
       do i = 1, size(inds)
          if (inds(i) >= 1 .and. inds(i) <= grid_size) then
             dest(i) = full_array(inds(i))
          else
             dest(i) = -1.d0
          end if
       end do
    end if

    deallocate(full_array)
  end function wrfhydro_get_at_indices_double


  ! **************************************************************************
  ! SECTION 7: SET VALUE FUNCTIONS (9 = 3 types x 3 access patterns)
  ! **************************************************************************
  ! These copy variable data INTO WRF-Hydro from the caller's arrays.
  ! Only input variables can be set (precipitation, temperature, coupling).
  ! **************************************************************************

  ! --------------------------------------------------------------------------
  ! set_value_int: Set integer variable values (not used by WRF-Hydro).
  ! --------------------------------------------------------------------------
  function wrfhydro_set_int(this, name, src) result (bmi_status)
    class (bmi_wrf_hydro), intent(inout) :: this
    character (len=*), intent(in) :: name
    integer, intent(in) :: src(:)
    integer :: bmi_status

    bmi_status = BMI_FAILURE
  end function wrfhydro_set_int

  ! --------------------------------------------------------------------------
  ! set_value_float: Set single-precision float values (not primary).
  ! --------------------------------------------------------------------------
  function wrfhydro_set_float(this, name, src) result (bmi_status)
    class (bmi_wrf_hydro), intent(inout) :: this
    character (len=*), intent(in) :: name
    real, intent(in) :: src(:)
    integer :: bmi_status

    bmi_status = BMI_FAILURE
  end function wrfhydro_set_float

  ! --------------------------------------------------------------------------
  ! set_value_double: Set double-precision values (PRIMARY set function).
  ! --------------------------------------------------------------------------
  ! This pushes data INTO WRF-Hydro's internal state. For WRF-Hydro
  ! variables stored as REAL, we convert from double using real().
  ! For coupling placeholders, we store directly as double.
  ! --------------------------------------------------------------------------
  function wrfhydro_set_double(this, name, src) result (bmi_status)
    use module_noahmp_hrldas_driver, only: RAINBL, T2MVXY

    class (bmi_wrf_hydro), intent(inout) :: this
    character (len=*), intent(in) :: name
    double precision, intent(in) :: src(:)
    integer :: bmi_status

    select case(name)

    ! --- Set precipitation rate ---
    ! Converts double -> REAL and reshapes 1D -> 2D (IX, JX)
    case('atmosphere_water__precipitation_leq-volume_flux')
       if (allocated(RAINBL)) then
          RAINBL(1:this%ix, 1:this%jx) = reshape( &
               real(src(1:this%ix*this%jx)), [this%ix, this%jx])
          bmi_status = BMI_SUCCESS
       else
          bmi_status = BMI_FAILURE
       end if

    ! --- Set 2m air temperature ---
    case('land_surface_air__temperature')
       if (allocated(T2MVXY)) then
          T2MVXY(1:this%ix, 1:this%jx) = reshape( &
               real(src(1:this%ix*this%jx)), [this%ix, this%jx])
          bmi_status = BMI_SUCCESS
       else
          bmi_status = BMI_FAILURE
       end if

    ! --- Set sea water elevation (coupling placeholder) ---
    case('sea_water_surface__elevation')
       if (allocated(this%sea_water_elevation)) then
          this%sea_water_elevation(1:this%ix, 1:this%jx) = reshape( &
               src(1:this%ix*this%jx), [this%ix, this%jx])
          bmi_status = BMI_SUCCESS
       else
          bmi_status = BMI_FAILURE
       end if

    ! --- Set sea water x-velocity (coupling placeholder) ---
    case('sea_water__x_velocity')
       if (allocated(this%sea_water_x_velocity)) then
          this%sea_water_x_velocity(1:this%ix, 1:this%jx) = reshape( &
               src(1:this%ix*this%jx), [this%ix, this%jx])
          bmi_status = BMI_SUCCESS
       else
          bmi_status = BMI_FAILURE
       end if

    case default
       bmi_status = BMI_FAILURE

    end select
  end function wrfhydro_set_double

  ! --------------------------------------------------------------------------
  ! set_value_at_indices_int: Set specific integer values (not used).
  ! --------------------------------------------------------------------------
  function wrfhydro_set_at_indices_int(this, name, inds, src) &
       result (bmi_status)
    class (bmi_wrf_hydro), intent(inout) :: this
    character (len=*), intent(in) :: name
    integer, intent(in) :: inds(:)
    integer, intent(in) :: src(:)
    integer :: bmi_status

    bmi_status = BMI_FAILURE
  end function wrfhydro_set_at_indices_int

  ! --------------------------------------------------------------------------
  ! set_value_at_indices_float: Set specific float values (not used).
  ! --------------------------------------------------------------------------
  function wrfhydro_set_at_indices_float(this, name, inds, src) &
       result (bmi_status)
    class (bmi_wrf_hydro), intent(inout) :: this
    character (len=*), intent(in) :: name
    integer, intent(in) :: inds(:)
    real, intent(in) :: src(:)
    integer :: bmi_status

    bmi_status = BMI_FAILURE
  end function wrfhydro_set_at_indices_float

  ! --------------------------------------------------------------------------
  ! set_value_at_indices_double: Set specific double values by flat index.
  ! --------------------------------------------------------------------------
  ! This sets specific elements using 1-based flat indices. It first gets
  ! the full array, modifies the requested elements, then sets it back.
  ! --------------------------------------------------------------------------
  function wrfhydro_set_at_indices_double(this, name, inds, src) &
       result (bmi_status)
    class (bmi_wrf_hydro), intent(inout) :: this
    character (len=*), intent(in) :: name
    integer, intent(in) :: inds(:)
    double precision, intent(in) :: src(:)
    integer :: bmi_status
    double precision, allocatable :: full_array(:)
    integer :: grid, grid_size, i, s1, s2

    ! Get the grid size for this variable
    s1 = this%get_var_grid(name, grid)
    s2 = this%get_grid_size(grid, grid_size)

    if (s1 /= BMI_SUCCESS .or. s2 /= BMI_SUCCESS) then
       bmi_status = BMI_FAILURE
       return
    end if

    ! Get current values, modify requested elements, set back
    allocate(full_array(grid_size))
    bmi_status = this%get_value_double(name, full_array)

    if (bmi_status == BMI_SUCCESS) then
       do i = 1, size(inds)
          if (inds(i) >= 1 .and. inds(i) <= grid_size) then
             full_array(inds(i)) = src(i)
          end if
       end do
       bmi_status = this%set_value_double(name, full_array)
    end if

    deallocate(full_array)
  end function wrfhydro_set_at_indices_double

end module bmiwrfhydrof
