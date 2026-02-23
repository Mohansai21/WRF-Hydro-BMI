# Technology Stack

**Analysis Date:** 2026-02-23

## Languages

**Primary:**
- Fortran 2003 - BMI wrapper implementation (`bmi_wrf_hydro/src/bmi_wrf_hydro.f90`, 1,919 lines)
- Fortran 90 - WRF-Hydro v5.4.0 hydrological model internals (`wrf_hydro_nwm_public/`)
- Fortran 77/90 - SCHISM coastal model (`schism_NWM_BMI/`, 437 files with BMI extensions via preprocessor)

**Secondary:**
- C - NetCDF C library bindings (underlying NetCDF-C, conda-managed)
- Bash - Build and test automation (`bmi_wrf_hydro/build.sh`, `WRF_Hydro_Run_Local/run_and_test.sh`)

## Runtime

**Environment:**
- Conda environment: `wrfhydro-bmi` at `/home/mohansai/miniconda3/envs/wrfhydro-bmi/`
- Active activation: `source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi`

**Fortran Compiler:**
- gfortran 14.3.0 (conda-forge gcc 14.3.0-17_gcc_impl_linux-64)
- Supports free-form Fortran, unlimited line length, C preprocessor (#ifdef)
- Flags: `-cpp`, `-fPIC`, `-ffree-form`, `-ffree-line-length-none`, `-fallow-argument-mismatch` (gfortran 10+)

**MPI Runtime:**
- Open MPI 5.0.8 (conda-forge, mpif90 compiler wrapper, mpirun command)
- Parallel transport for WRF-Hydro land domain decomposition (MPP_LAND mode)
- Execution: `mpirun --oversubscribe -np 1 ./executable` (serial mode, 1 process override)

**Package Manager:**
- Conda (Miniconda3, conda-forge channel primary)
- No lockfile explicitly tracked (environment via CLAUDE.md specifications)

## Frameworks

**Core Model:**
- WRF-Hydro v5.4.0 (NCAR hydrological model)
  - Location: `wrf_hydro_nwm_public/` (full source, ~5.4GB compiled)
  - Build system: CMake 3.31.1
  - Components: Noah-MP land surface (LSM), overland routing, subsurface routing, channel routing (Muskingum-Cunge), reservoirs
  - State container: `RT_FIELD` type @ `wrf_hydro_nwm_public/src/Data_Rec/module_rt_inc.F90`

**BMI (Basic Model Interface):**
- bmi-fortran 2.0.3 (conda-forge)
  - Abstract interface: `bmif_2_0` module (564 lines)
  - Provides: 41 deferred procedures (initialize, update, get/set value, grid operations)
  - Location: `bmi-fortran/` subdirectory, installed in conda env at `$CONDA_PREFIX/include/bmif_2_0.mod`
  - Library: `libbmif.so` (shared library for linking)
  - Reference: BMI 2.0 specification (Hutton et al. 2020)

**Reference Implementation:**
- bmi-example-fortran (CSDMS heat model example, 49/49 tests passing)
  - Location: `bmi-example-fortran/` subdirectory
  - Build system: CMake with ctest runner
  - Used as blueprint for `bmi_wrf_hydro.f90` structure and patterns

**Coupled Model (Reference):**
- SCHISM coastal ocean model with BMI
  - Location: `schism_NWM_BMI/` (full 437 files, submodule branch bmi-integration-master)
  - Also: `SCHISM_BMI/` (LynkerIntel wrapper, git submodule)
  - BMI implementation: Fortran with `#ifdef USE_NWM_BMI` preprocessor pattern (not separate wrapper)
  - 12 input variables (river discharge Q_bnd + forcings) + 4-5 output variables (elevation eta, velocities)

## Key Dependencies

**Critical (Must-Have):**
- bmi-fortran 2.0.3 - Provides BMI 2.0 abstract interface and libbmif.so
  - Import: `use bmif_2_0` (defines bmi type with 41 deferred procedures)
  - Purpose: Enables external control of WRF-Hydro via standard BMI contract
- gfortran 14.3.0 - Fortran compiler with C preprocessor and free-form support
  - Compile flags: `-cpp -DWRF_HYDRO -DMPP_LAND -DUSE_NWM_BMI`
  - Required for ISO_C_BINDING support (BMI 2.0 requirement)
- Open MPI 5.0.8 - MPI runtime for WRF-Hydro land parallelism
  - Wrapper: `mpif90` (for linking), `mpirun` (for execution)
  - Purpose: Resolves MPI_Init, MPI_Finalize, domain decomposition symbols

**Scientific (WRF-Hydro Internals):**
- NetCDF-Fortran 4.6.2 (libnetcdff.so) - Fortran bindings for NetCDF I/O
  - Import: Indirect via WRF-Hydro modules (orchestrator, netcdf_layer)
  - Purpose: Read/write meteorological forcing, output files (.nc format)
  - Pair: NetCDF-C 4.9.3 (libnetcdf.so, underlying C library)

**Build Infrastructure:**
- CMake 3.31.1 (conda-forge)
  - Used by: `wrf_hydro_nwm_public/`, `bmi_wrf_hydro/CMakeLists.txt`, `bmi-example-fortran/`
  - Configuration: pkg-config to find bmif, NetCDF, MPI

**WRF-Hydro 22 Linked Libraries (from `bmi_wrf_hydro/build.sh`):**
1. libhydro_driver (HYDRO_ini, HYDRO_exe)
2. libhydro_noahmp_cpl (Noah-MP <-> Hydro coupling)
3. libhydro_orchestrator (I/O orchestration)
4. libnoahmp_data (Noah-MP parameter tables)
5. libnoahmp_phys (Noah-MP physics: energy, soil, snow)
6. libnoahmp_util (Noah-MP utilities)
7. libhydro_routing (Channel routing, Muskingum-Cunge)
8. libhydro_routing_overland (2D surface water)
9. libhydro_routing_subsurface (Saturated lateral flow)
10. libhydro_routing_reservoirs (Reservoir base)
11. libhydro_routing_reservoirs_levelpool (Level-pool method)
12. libhydro_routing_reservoirs_hybrid (Hybrid persistence + level-pool)
13. libhydro_routing_reservoirs_rfc (RFC Forecast Center method)
14. libhydro_routing_diversions (Channel diversions)
15. libhydro_data_rec (Data record types, RT_FIELD)
16. libhydro_mpp (MPI parallelism wrappers)
17. libhydro_netcdf_layer (NetCDF I/O abstraction)
18. libhydro_debug_utils (Debug printing)
19. libhydro_utils (General utilities)
20. libfortglob (File pattern matching)
21. libcrocus_surfex (Crocus snow model)
22. libsnowcro (Crocus surface exchange)

**Testing:**
- bmi-tester 0.5.9 (conda-forge) - BMI validation tool
  - Purpose: Validate BMI wrapper compliance (not yet run)
- Fortran built-in: No framework; custom test harness in `bmi_wrf_hydro_test.f90` (1,777 lines, 151 tests)

## Configuration

**Environment Variables (Build-Time):**
```
CONDA_PREFIX         -> /home/mohansai/miniconda3/envs/wrfhydro-bmi
HYDRO_LSM            -> "NoahMP" (default in CMakeLists.txt)
WRF_HYDRO            -> "1" (must be set for model)
HYDRO_D              -> "0" (release) or "1" (debug) - debug logging
WRF_HYDRO_RAPID      -> "0" (RAPID routing model disabled)
SPATIAL_SOIL         -> "0" (distributed soil params disabled)
WRFIO_NCD_LARGE_FILE_SUPPORT -> "0" (large NetCDF files disabled)
NCEP_WCOSS           -> "0" (WCOSS file units disabled)
NWM_META             -> "0" (NWM output metadata disabled)
WRF_HYDRO_NUDGING    -> "0" (streamflow nudging disabled)
OUTPUT_CHAN_CONN     -> unset
PRECIP_DOUBLE        -> unset
WRF_HYDRO_NUOPC      -> unset
```

**Preprocessing Flags (C Preprocessor):**
- `-DWRF_HYDRO` - Enable WRF-Hydro code paths in bmi_wrf_hydro.f90
- `-DMPP_LAND` - Enable MPI land domain decomposition (required for open_print_mpp)
- `-DUSE_NWM_BMI` - Enable BMI-specific code blocks in wrapper (like SCHISM's pattern)

**WRF-Hydro Configuration Files (Runtime):**
- `namelist.hrldas` - Noah-MP land surface namelist (at `WRF_Hydro_Run_Local/run/`)
- `hydro.namelist` - Hydro routing configuration (at `WRF_Hydro_Run_Local/run/`)
- `.TBL` files - Parameter lookup tables (VEGPARM.TBL, SOILPARM.TBL, etc.)
- Input data: DOMAIN/ (static domain files), FORCING/ (meteorological forcing)

**BMI Configuration:**
- Currently: Pass-through to existing namelists (BMI initialize() reads same config files)
- Future: Explicit BMI config file (YAML/TOML) mapping to namelist parameters

**Compiler Flags (Build):**
- Compile: `gfortran -c -cpp -DWRF_HYDRO -DMPP_LAND -fPIC -ffree-form -ffree-line-length-none`
- Link: `mpif90 -o executable ... -L$CONDA_PREFIX/lib -lbmif -L$WRF_BUILD/lib <22 WRF libs> -lnetcdff -lnetcdf`
- Fortran module search: `-I$CONDA_PREFIX/include -I$WRF_BUILD/mods -I_build/mod`

## Platform Requirements

**Development:**
- OS: Linux (WSL2 on Windows, Ubuntu-like on native Linux)
- Fortran compiler: gfortran 10+ (for `-fallow-argument-mismatch`)
- MPI: OpenMPI 4.0+ (conda-forge preferred to avoid system conflicts)
- NetCDF: Fortran 4.6+, C 4.9+ (conda-forge binaries)
- Disk: ~20 GB total (WRF-Hydro source + build + test data)
  - WRF source: ~5.4 GB
  - WRF build/lib: ~2 GB
  - Test data (Croton NY): 120 MB
  - Conda env: ~3 GB
- RAM: 8+ GB recommended (WRF-Hydro initialization uses ~1-2 GB)

**Production (Deployment):**
- Deployment target: NOAA NextGen framework (Phase 3+) or PyMT (Phase 2+)
- Output format: Shared library `libwrfhydro_bmi.so` (via CMake install)
- Installation path: `$CONDA_PREFIX/lib/libwrfhydro_bmi.so` + `$CONDA_PREFIX/include/bmi_wrf_hydro.mod`
- Runtime requirement: Conda environment with bmi-fortran, NetCDF, Open MPI available

**CI/CD:**
- No explicit CI/CD configured (Phase 1 - testing manual)
- Test execution: `mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test` from test data directory
- Expected runtime: ~2-3 minutes for full test suite (151 tests)
- Test data location: `WRF_Hydro_Run_Local/run/` (namelist + DOMAIN + FORCING directories)

## Build System Summary

**Tool Chain:**
- Build automation: Bash scripts (`build.sh` for incremental, CMake for shared lib)
- Configuration generation: CMake 3.12+ (project minimum)
- Compilation database: CMake generates Makefiles (for IDE integration if needed)
- Dependency resolution: pkg-config (for BMI, NetCDF), manual for WRF libraries

**Two Build Paths:**
1. **Bash script** (`bmi_wrf_hydro/build.sh`) - Direct gfortran + mpif90
   - Targets: bmi_minimal_test (105 lines), bmi_wrf_hydro_test (1,777 lines)
   - Output: `build/bmi_minimal_test`, `build/bmi_wrf_hydro_test` (executables)
   - Currently used for rapid iteration during Phase 1

2. **CMake** (`bmi_wrf_hydro/CMakeLists.txt`) - Production shared library
   - Target: libwrfhydro_bmi.so (shared library, 1.0.0 version)
   - Also builds: bmi_wrf_hydro_test executable via CTest
   - Installation: `cmake --install _build` → conda env lib/include dirs
   - Currently development (Phase 1 completion), will be primary in Phase 2 (babelizer)

---

*Stack analysis: 2026-02-23*
