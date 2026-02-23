! ============================================================================
! Minimal BMI test: initialize, update a few steps, query info, finalize.
!
! WHY write(0,*) INSTEAD OF print *?
!   WRF-Hydro's HYDRO_ini() calls open_print_mpp(6) which redirects
!   Fortran unit 6 (stdout) to file "diag_hydro.00000". After that,
!   print * (which uses unit 6) goes to file, not terminal.
!   write(0,*) uses unit 0 = stderr, which is NOT redirected.
!
! WHY MPI_Finalize?
!   WRF-Hydro's HYDRO_ini() calls MPI_Init (via MPP_LAND_INIT).
!   Normally HYDRO_finish() calls MPI_Finalize + stop, but we skip
!   HYDRO_finish because it has "stop". So WE must finalize MPI.
! ============================================================================
program bmi_minimal_test
  use bmiwrfhydrof
  use bmif_2_0
  use mpi
  implicit none

  type(bmi_wrf_hydro) :: model
  integer :: status, ierr, i
  character(len=512) :: config_file
  character(len=256), pointer :: comp_name
  double precision :: t_start, t_end, t_now, t_step

  write(0,*) "=========================================="
  write(0,*) "  BMI WRF-Hydro Minimal Test"
  write(0,*) "=========================================="

  ! --- Step 1: Create config file ---
  write(0,*) ""
  write(0,*) "[1] Creating config file..."
  config_file = "bmi_config.nml"
  open(unit=10, file=trim(config_file), status="replace", action="write")
  write(10, '(A)') "&bmi_wrf_hydro_config"
  write(10, '(A)') '  wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/"'
  write(10, '(A)') "/"
  close(10)

  ! --- Step 2: Initialize ---
  write(0,*) "[2] Calling initialize..."
  status = model%initialize(trim(config_file))
  if (status /= BMI_SUCCESS) then
     write(0,*) "FATAL: initialize returned BMI_FAILURE"
     call MPI_Finalize(ierr)
     stop 1
  end if
  write(0,*) "    -> Initialize SUCCESS"

  ! --- Step 3: Query model info ---
  write(0,*) ""
  write(0,*) "[3] Querying model info..."

  status = model%get_component_name(comp_name)
  write(0,*) "    Component name: ", trim(comp_name)

  status = model%get_start_time(t_start)
  write(0,*) "    Start time:  ", t_start, " seconds"

  status = model%get_end_time(t_end)
  write(0,*) "    End time:    ", t_end, " seconds"

  status = model%get_time_step(t_step)
  write(0,*) "    Timestep:    ", t_step, " seconds"

  status = model%get_current_time(t_now)
  write(0,*) "    Current time:", t_now, " seconds"

  ! --- Step 4: Run all 6 update steps (full Croton NY 6-hour test case) ---
  write(0,*) ""
  write(0,*) "[4] Running 6 update steps (full 6-hour simulation)..."
  do i = 1, 6
     write(0,*) "    -> Calling update() step", i, "..."
     status = model%update()
     if (status /= BMI_SUCCESS) then
        write(0,*) "FATAL: update returned BMI_FAILURE at step", i
        call MPI_Finalize(ierr)
        stop 1
     end if
     status = model%get_current_time(t_now)
     write(0,*) "       Current time after step:", t_now, " seconds"
  end do

  ! --- Step 5: Finalize ---
  write(0,*) ""
  write(0,*) "[5] Calling finalize..."
  status = model%finalize()
  if (status /= BMI_SUCCESS) then
     write(0,*) "WARNING: finalize returned BMI_FAILURE"
  else
     write(0,*) "    -> Finalize SUCCESS"
  end if

  ! --- Step 6: MPI Cleanup ---
  write(0,*) ""
  write(0,*) "[6] Calling MPI_Finalize..."
  call MPI_Finalize(ierr)

  write(0,*) ""
  write(0,*) "=========================================="
  write(0,*) "  ALL TESTS PASSED"
  write(0,*) "=========================================="

end program bmi_minimal_test
