! ============================================================================
! hydro_stop_shim.f90 -- Provides bare external hydro_stop subroutine
! ============================================================================
!
! PURPOSE:
!   WRF-Hydro defines hydro_stop as a MODULE subroutine inside
!   module_hydro_stop. Most callers use `use module_hydro_stop, only: HYDRO_stop`
!   which generates the module-mangled symbol __module_hydro_stop_MOD_hydro_stop.
!
!   However, one call site (nwmCheck in module_reservoir_routing.F90) calls
!   `call hydro_stop(msg)` WITHOUT a `use` statement, generating a reference
!   to the bare external symbol `hydro_stop_`.
!
!   In normal WRF-Hydro executable builds, this dead code is not pulled in
!   by the linker (selective linking from .a files). But when we use
!   --whole-archive to build libbmiwrfhydrof.so, ALL object files are included,
!   creating an unresolved reference to `hydro_stop_`.
!
!   This shim provides the bare external symbol by delegating to the module
!   version. It is compiled with -fPIC as part of our shared library.
! ============================================================================
subroutine hydro_stop(msg)
  use module_hydro_stop, only: HYDRO_stop_mod => HYDRO_stop
  implicit none
  character(len=*), intent(in) :: msg
  call HYDRO_stop_mod(msg)
end subroutine hydro_stop
