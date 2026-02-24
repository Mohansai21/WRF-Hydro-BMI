! ============================================================================
! MODULE: bmi_wrf_hydro_c_mod
! ============================================================================
!
! PURPOSE:
!   Provides a minimal C binding layer that exposes 10 key BMI functions as
!   flat C symbols callable from Python ctypes. This is TEST INFRASTRUCTURE
!   only -- the babelizer auto-generates the full 818-line interop layer
!   (bmi_interoperability.f90) for production use.
!
! WHY THIS FILE EXISTS:
!   The BMI wrapper module (bmiwrfhydrof) exports Fortran module-mangled
!   symbols like __bmiwrfhydrof_MOD_wrfhydro_initialize which are NOT
!   callable from C or Python. This thin C interop layer uses ISO_C_BINDING
!   bind(C) to expose clean symbols (e.g., bmi_initialize) that Python
!   ctypes can call directly via ctypes.CDLL("libbmiwrfhydrof.so").
!
! PATTERN:
!   Singleton (module-level bmi_wrf_hydro instance) -- NOT the box/opaque-
!   handle pattern used by SCHISM for NextGen. WRF-Hydro cannot support
!   multiple instances (module globals are singletons), so the simpler
!   module-level pattern is appropriate.
!
! FUNCTIONS EXPOSED (10):
!   1. bmi_register          -> Singleton guard (first call OK, second fails)
!   2. bmi_initialize        -> Initialize model from config file
!   3. bmi_update            -> Advance model one timestep
!   4. bmi_finalize          -> Clean up model resources
!   5. bmi_get_component_name -> Get model's human-readable name
!   6. bmi_get_current_time  -> Get current simulation time
!   7. bmi_get_var_grid      -> Get grid ID for a named variable
!   8. bmi_get_grid_size     -> Get number of cells in a grid
!   9. bmi_get_var_nbytes    -> Get total bytes for a variable
!  10. bmi_get_value_double  -> Get variable values as double array
!
! STRING HELPERS (2):
!   - c_to_f_string: Convert null-terminated C string to Fortran string
!   - f_to_c_string: Copy Fortran string into C char buffer with null term
!
! USAGE FROM PYTHON:
!   import ctypes
!   lib = ctypes.CDLL("libbmiwrfhydrof.so")
!   lib.bmi_register()
!   lib.bmi_initialize(b"/path/to/config.nml\x00")
!   lib.bmi_update()
!   lib.bmi_finalize()
!
! ============================================================================

module bmi_wrf_hydro_c_mod
  use bmiwrfhydrof, only: bmi_wrf_hydro
  use bmif_2_0, only: BMI_SUCCESS, BMI_FAILURE, BMI_MAX_COMPONENT_NAME
  use, intrinsic :: iso_c_binding
  implicit none
  private

  ! Singleton model instance (module-level, SAVE by default in F2003).
  ! WRF-Hydro cannot support multiple instances because its module-level
  ! arrays (COSZEN, SMOIS, etc.) are allocated once and cannot be
  ! re-allocated without modifying WRF-Hydro source code.
  type(bmi_wrf_hydro), save, target :: the_model

  ! Singleton guard flag. Once registered, subsequent calls to
  ! bmi_register return BMI_FAILURE to prevent double allocation.
  ! Reset by bmi_finalize so the process can be reused (though
  ! WRF-Hydro itself prevents re-init via wrfhydro_engine_initialized).
  logical, save :: is_registered = .false.

contains

  ! ==========================================================================
  ! STRING HELPERS
  ! ==========================================================================
  ! These convert between null-terminated C strings (character arrays) and
  ! Fortran character scalars. Needed because bind(C) functions receive
  ! strings as character(kind=c_char) :: str(*) arrays, while the BMI
  ! wrapper expects normal Fortran character(len=*) strings.
  ! ==========================================================================

  ! --------------------------------------------------------------------------
  ! c_to_f_string: Convert a null-terminated C string to a Fortran string.
  ! --------------------------------------------------------------------------
  ! Input:  c_string(*) -- assumed-size array of c_char, null-terminated
  ! Output: f_string    -- allocatable Fortran string (no null terminator)
  !
  ! Uses a do-while loop to find the null terminator, then allocates and
  ! copies character by character (NOT transfer, which can produce incorrect
  ! results with some compilers for character arrays).
  ! --------------------------------------------------------------------------
  pure function c_to_f_string(c_string) result(f_string)
    character(kind=c_char, len=1), intent(in) :: c_string(*)
    character(len=:), allocatable :: f_string
    integer :: i, n

    ! Find the null terminator
    i = 1
    do while (c_string(i) /= c_null_char)
      i = i + 1
    end do
    n = i - 1

    ! Allocate and copy character by character
    allocate(character(len=n) :: f_string)
    do i = 1, n
      f_string(i:i) = c_string(i)
    end do
  end function c_to_f_string

  ! --------------------------------------------------------------------------
  ! f_to_c_string: Copy a Fortran string into a C char buffer.
  ! --------------------------------------------------------------------------
  ! Input:  f_string -- Fortran character string
  !         c_len    -- size of the output buffer (prevents overflow)
  ! Output: c_string -- pre-allocated c_char array, null-terminated
  !
  ! Copies trimmed content of f_string into c_string, then appends
  ! c_null_char. If the string is longer than the buffer, it is truncated
  ! to (c_len - 1) characters to leave room for the null terminator.
  ! --------------------------------------------------------------------------
  pure subroutine f_to_c_string(f_string, c_string, c_len)
    character(len=*), intent(in) :: f_string
    integer(c_int), intent(in) :: c_len
    character(kind=c_char, len=1), intent(out) :: c_string(c_len)
    integer :: i, n

    n = len_trim(f_string)
    ! Truncate if buffer is too small (leave room for null terminator)
    if (n > c_len - 1) n = c_len - 1

    do i = 1, n
      c_string(i) = f_string(i:i)
    end do
    c_string(n + 1) = c_null_char
  end subroutine f_to_c_string

  ! ==========================================================================
  ! BMI C BINDING FUNCTIONS (10)
  ! ==========================================================================
  ! All functions return integer(c_int) as the result:
  !   BMI_SUCCESS = 0 (operation succeeded)
  !   BMI_FAILURE = 1 (operation failed)
  ! ==========================================================================

  ! --------------------------------------------------------------------------
  ! 1. bmi_register: Singleton guard for model registration.
  ! --------------------------------------------------------------------------
  ! First call: sets is_registered = .true., returns BMI_SUCCESS.
  ! Subsequent calls: returns BMI_FAILURE (singleton -- only one allowed).
  ! No model allocation needed since the_model is module-level SAVE.
  ! --------------------------------------------------------------------------
  function bmi_register() result(status) bind(C, name="bmi_register")
    integer(c_int) :: status

    if (is_registered) then
      status = BMI_FAILURE
      return
    end if
    is_registered = .true.
    status = BMI_SUCCESS
  end function bmi_register

  ! --------------------------------------------------------------------------
  ! 2. bmi_initialize: Initialize the model from a config file.
  ! --------------------------------------------------------------------------
  ! Receives a null-terminated C string path to the BMI config namelist,
  ! converts it to a Fortran string, and delegates to the_model%initialize.
  ! --------------------------------------------------------------------------
  function bmi_initialize(config_file) result(status) &
      bind(C, name="bmi_initialize")
    character(kind=c_char), intent(in) :: config_file(*)
    integer(c_int) :: status
    character(len=:), allocatable :: f_file

    f_file = c_to_f_string(config_file)
    status = the_model%initialize(f_file)
    deallocate(f_file)
  end function bmi_initialize

  ! --------------------------------------------------------------------------
  ! 3. bmi_update: Advance the model by one timestep.
  ! --------------------------------------------------------------------------
  function bmi_update() result(status) bind(C, name="bmi_update")
    integer(c_int) :: status

    status = the_model%update()
  end function bmi_update

  ! --------------------------------------------------------------------------
  ! 4. bmi_finalize: Clean up model resources.
  ! --------------------------------------------------------------------------
  ! Also resets is_registered so the singleton can be reused in a future
  ! process (though WRF-Hydro itself prevents re-init via
  ! wrfhydro_engine_initialized flag).
  ! --------------------------------------------------------------------------
  function bmi_finalize() result(status) bind(C, name="bmi_finalize")
    integer(c_int) :: status

    status = the_model%finalize()
    is_registered = .false.
  end function bmi_finalize

  ! --------------------------------------------------------------------------
  ! 5. bmi_get_component_name: Get the model's human-readable name.
  ! --------------------------------------------------------------------------
  ! The BMI wrapper's get_component_name returns a pointer to an internal
  ! character variable. We use f_to_c_string to copy the trimmed content
  ! into the caller-provided output buffer.
  !
  ! Arguments:
  !   name(n) -- caller-provided buffer (character(c_char) array)
  !   n       -- buffer size (integer, passed by value)
  ! --------------------------------------------------------------------------
  function bmi_get_component_name(name, n) result(status) &
      bind(C, name="bmi_get_component_name")
    integer(c_int), value, intent(in) :: n
    character(kind=c_char), intent(out) :: name(n)
    integer(c_int) :: status
    character(len=BMI_MAX_COMPONENT_NAME), pointer :: f_name

    status = the_model%get_component_name(f_name)
    if (status == BMI_SUCCESS) then
      call f_to_c_string(f_name, name, n)
    end if
  end function bmi_get_component_name

  ! --------------------------------------------------------------------------
  ! 6. bmi_get_current_time: Get the current simulation time.
  ! --------------------------------------------------------------------------
  ! Output: time (real(c_double), passed by reference)
  ! --------------------------------------------------------------------------
  function bmi_get_current_time(time) result(status) &
      bind(C, name="bmi_get_current_time")
    real(c_double), intent(out) :: time
    integer(c_int) :: status

    status = the_model%get_current_time(time)
  end function bmi_get_current_time

  ! --------------------------------------------------------------------------
  ! 7. bmi_get_var_grid: Get the grid ID for a named variable.
  ! --------------------------------------------------------------------------
  ! Converts the variable name from C string, then queries the BMI wrapper.
  ! --------------------------------------------------------------------------
  function bmi_get_var_grid(name, grid) result(status) &
      bind(C, name="bmi_get_var_grid")
    character(kind=c_char), intent(in) :: name(*)
    integer(c_int), intent(out) :: grid
    integer(c_int) :: status
    character(len=:), allocatable :: f_name

    f_name = c_to_f_string(name)
    status = the_model%get_var_grid(f_name, grid)
    deallocate(f_name)
  end function bmi_get_var_grid

  ! --------------------------------------------------------------------------
  ! 8. bmi_get_grid_size: Get the number of cells/nodes in a grid.
  ! --------------------------------------------------------------------------
  ! Grid ID is passed by value (C convention for scalar int arguments).
  ! --------------------------------------------------------------------------
  function bmi_get_grid_size(grid, size) result(status) &
      bind(C, name="bmi_get_grid_size")
    integer(c_int), value, intent(in) :: grid
    integer(c_int), intent(out) :: size
    integer(c_int) :: status

    status = the_model%get_grid_size(grid, size)
  end function bmi_get_grid_size

  ! --------------------------------------------------------------------------
  ! 9. bmi_get_var_nbytes: Get the total bytes needed for a variable.
  ! --------------------------------------------------------------------------
  ! Converts the variable name from C string, then queries the BMI wrapper.
  ! The caller uses this to allocate the right amount of memory for
  ! get_value_double.
  ! --------------------------------------------------------------------------
  function bmi_get_var_nbytes(name, nbytes) result(status) &
      bind(C, name="bmi_get_var_nbytes")
    character(kind=c_char), intent(in) :: name(*)
    integer(c_int), intent(out) :: nbytes
    integer(c_int) :: status
    character(len=:), allocatable :: f_name

    f_name = c_to_f_string(name)
    status = the_model%get_var_nbytes(f_name, nbytes)
    deallocate(f_name)
  end function bmi_get_var_nbytes

  ! --------------------------------------------------------------------------
  ! 10. bmi_get_value_double: Get variable values as a double array.
  ! --------------------------------------------------------------------------
  ! Queries var_nbytes and var_itemsize to determine the array length,
  ! then fills the caller-provided dest array. The caller must allocate
  ! dest with enough space (use bmi_get_var_nbytes to determine size).
  !
  ! Arguments:
  !   name(*)  -- null-terminated C string (variable name)
  !   dest(*)  -- caller-allocated double array (output)
  ! --------------------------------------------------------------------------
  function bmi_get_value_double(name, dest) result(status) &
      bind(C, name="bmi_get_value_double")
    character(kind=c_char), intent(in) :: name(*)
    real(c_double), intent(out) :: dest(*)
    integer(c_int) :: status
    character(len=:), allocatable :: f_name
    integer :: nbytes_val, itemsize_val, n_items

    f_name = c_to_f_string(name)

    ! Query size from BMI metadata
    status = the_model%get_var_nbytes(f_name, nbytes_val)
    if (status /= BMI_SUCCESS) then
      deallocate(f_name)
      return
    end if

    status = the_model%get_var_itemsize(f_name, itemsize_val)
    if (status /= BMI_SUCCESS) then
      deallocate(f_name)
      return
    end if

    if (itemsize_val == 0) then
      status = BMI_FAILURE
      deallocate(f_name)
      return
    end if

    n_items = nbytes_val / itemsize_val

    status = the_model%get_value_double(f_name, dest(1:n_items))
    deallocate(f_name)
  end function bmi_get_value_double

end module bmi_wrf_hydro_c_mod
