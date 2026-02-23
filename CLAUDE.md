# CLAUDE.md — WRF-Hydro BMI Wrapper Project

## Project Overview
This project creates a BMI (Basic Model Interface) wrapper for WRF-Hydro
so it can be coupled with SCHISM coastal ocean model through PyMT.

WRF-Hydro is a Fortran 90 hydrological model developed by NCAR.
SCHISM already has a BMI wrapper (bmischism.f90).
WRF-Hydro does NOT have a BMI wrapper — that's what we're building.

## Project Goal
Write bmi_wrf_hydro.f90 — a Fortran 2003 module implementing all 41 BMI
functions to wrap WRF-Hydro's internals, enabling control from Python.

Ultimate vision: ~20 lines of Python in a Jupyter Notebook that runs
a coupled WRF-Hydro + SCHISM compound flooding simulation via PyMT.

## Directory Structure
- wrf_hydro_nwm_public/     -> WRF-Hydro v5.4.0 source code (Fortran 90, by NCAR)
- schism_NWM_BMI/            -> FULL SCHISM model (437 files) with BMI via #ifdef USE_NWM_BMI
- bmi-example-fortran/       -> CSDMS BMI heat example (BUILT & TESTED — 49/49 pass)
- bmi-fortran/               -> BMI Fortran specification (abstract interface, bmif_2_0)
- bmi_wrf_hydro/             -> OUR work directory (BMI wrapper)
  - bmi_wrf_hydro/src/       -> BMI wrapper source (bmi_wrf_hydro.f90, 1,919 lines)
  - bmi_wrf_hydro/tests/     -> Test programs (151-test suite + minimal test)
  - bmi_wrf_hydro/build/     -> Compiled artifacts (.o, .mod, executables)
  - bmi_wrf_hydro/build.sh   -> Build script (compile + link against 22 WRF-Hydro libs)
  - bmi_wrf_hydro/Docs/      -> 15 detailed project guide documents + Plan/
- SCHISM_BMI/                 -> LynkerIntel SCHISM BMI wrapper (bmi-integration-master branch)
- WRF_Hydro_Run_Local/       -> WRF-Hydro standalone run setup (Croton NY test case)

## Language & Conventions
- Primary language: Fortran 2003 (for BMI wrapper, needed for ISO_C_BINDING)
- Model language: Fortran 90 (WRF-Hydro internals)
- BMI spec: bmif_2_0 module from bmi-fortran (BMI 2.0, Hutton et al. 2020)
- Naming: Use CSDMS Standard Names for variable mapping
  Pattern: <object>__<quantity> with double underscore, all lowercase
  Only allowed chars: a-z, 0-9, _, -, ~
- Follow the pattern in bmi-example-fortran/bmi_heat/bmi_heat.f90
- Study bmischism.f90 for real-world patterns

## Key Files to Know
- bmi_wrf_hydro/src/bmi_wrf_hydro.f90        -> ★ OUR BMI WRAPPER (1,919 lines, 41 functions, 55 procedures)
- bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90 -> ★ Full test suite (1,777 lines, 151 tests, ALL PASS)
- bmi_wrf_hydro/tests/bmi_minimal_test.f90   -> ★ Quick smoke test (105 lines, init+6 updates+finalize)
- bmi_wrf_hydro/build.sh                     -> ★ Build script (compile + link, handles 22 WRF-Hydro libs)
- bmi-fortran/bmi.f90                        -> Abstract BMI interface (564 lines, 53 deferred procedures)
- bmi-example-fortran/bmi_heat/bmi_heat.f90  -> BMI wrapper TEMPLATE (935 lines) — OUR BLUEPRINT
- bmi-example-fortran/build_and_test.sh      -> BMI heat example build+test script (all 49 tests)
- wrf_hydro_nwm_public/src/Land_models/NoahMP/IO_code/main_hrldas_driver.F -> WRF-Hydro entry point
- wrf_hydro_nwm_public/src/Land_models/NoahMP/IO_code/module_NoahMP_hrldas_driver.F -> land_driver_ini/exe
- wrf_hydro_nwm_public/src/HYDRO_drv/module_HYDRO_drv.F90 -> HYDRO_ini/exe/finish
- wrf_hydro_nwm_public/src/Data_Rec/module_rt_inc.F90 -> RT_FIELD type (all routing state vars)
- schism_NWM_BMI/src/Hydro/schism_init.F90  -> SCHISM #ifdef USE_NWM_BMI pattern
- schism_NWM_BMI/src/Driver/schism_driver.F90 -> SCHISM IRF pattern (init0/step0/finalize0)

## The 41 BMI Functions (6 Categories)
All must be implemented, even if some just return BMI_FAILURE.

### Control (4): initialize, update, update_until, finalize
### Model Info (4): get_component_name, get_input_item_count, get_output_item_count, get_input_var_names, get_output_var_names
### Variable Info (6): get_var_type, get_var_units, get_var_grid, get_var_itemsize, get_var_nbytes, get_var_location
### Time (5): get_current_time, get_start_time, get_end_time, get_time_step, get_time_units
### Get/Set (5): get_value, set_value, get_value_ptr, get_value_at_indices, set_value_at_indices
### Grid (17): get_grid_type/rank/size/shape/spacing/origin, get_grid_x/y/z, get_grid_node/edge/face_count, get_grid_edge_nodes, get_grid_face_nodes/edges, get_grid_nodes_per_face

## CSDMS Standard Names Mapping (WRF-Hydro)
Internal Name -> CSDMS Standard Name -> Units
- QLINK1       -> channel_water__volume_flow_rate -> m3/s (streamflow)
- sfcheadrt    -> land_surface_water__depth -> m
- SOIL_M       -> soil_water__volume_fraction -> dimensionless
- SNEQV        -> snowpack__liquid-equivalent_depth -> m
- ACCET        -> land_surface_water__evaporation_volume_flux -> mm
- T2           -> land_surface_air__temperature -> K
- RAINRATE     -> atmosphere_water__precipitation_leq-volume_flux -> mm/s
- UGDRNOFF     -> soil_water__domain_time_integral_of_baseflow_volume_flux -> mm

## CSDMS Standard Names Mapping (SCHISM — for coupling reference)
- elev         -> sea_water_surface__elevation -> m
- discharge    -> channel_water__volume_flow_rate -> m3/s

## Coupling Variables (shared between models)
WRF-Hydro OUTPUT -> SCHISM INPUT:
  channel_water__volume_flow_rate (river discharge)
SCHISM OUTPUT -> WRF-Hydro INPUT:
  sea_water_surface__elevation (coastal water levels)

## WRF-Hydro Grid Types for BMI
- Grid 0: uniform_rectilinear 1km (Noah-MP land surface variables)
- Grid 1: uniform_rectilinear 250m (terrain routing variables)
- Grid 2: vector/network (channel routing — 2.7M reaches in NWM)

## BMI Critical Rules
- Arrays are ALWAYS flattened to 1D (avoids row/column-major issues)
- BMI is NON-INVASIVE: wrapper calls model, doesn't change model code
- ZERO DEPENDENCIES: BMI wrapper uses only standard language features
- Memory allocation is the MODEL's job, not the BMI wrapper's
- Use CPP flag USE_NWM_BMI (following SCHISM's pattern)
- Config file: pass-through to existing namelists initially

## IRF Refactoring (The Hardest Part)
WRF-Hydro's main program (main_hrldas_driver.F, 42 lines) has an integrated time loop.
Must decompose into BMI's Initialize-Run-Finalize pattern:
- initialize() -> orchestrator%init() + land_driver_ini() + HYDRO_ini(), NO time stepping
- update()     -> land_driver_exe() (which calls HYDRO_exe() internally)
- finalize()   -> custom cleanup (NOT HYDRO_finish — it has stop!)
The CALLER (PyMT) controls the time loop, not the model.

Key WRF-Hydro subroutines (already identified):
- land_driver_ini() @ module_NoahMP_hrldas_driver.F:422 — Noah-MP initialization
- land_driver_exe() @ module_NoahMP_hrldas_driver.F:1646 — Noah-MP one timestep
- HYDRO_ini() @ module_HYDRO_drv.F90:1350 — Hydro routing initialization
- HYDRO_exe() @ module_HYDRO_drv.F90:561 — Hydro routing one timestep
- HYDRO_finish() @ module_HYDRO_drv.F90:1800 — Cleanup

## Compile Commands
- Build BMI wrapper + all tests (from bmi_wrf_hydro/ directory):
  ./build.sh              # Build everything
  ./build.sh minimal      # Build BMI + minimal test only
  ./build.sh full         # Build BMI + full test only
  ./build.sh clean        # Clean all artifacts
- Run tests (from bmi_wrf_hydro/ directory):
  mpirun --oversubscribe -np 1 ./build/bmi_minimal_test     # Quick smoke test (~30s)
  mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test   # Full 151-test suite (~2-3min)
- Build bmi-example-fortran with cmake:
  cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX
  cmake --build _build
  ctest --test-dir _build

## Important Rules
- NEVER modify WRF-Hydro source code directly
- Our BMI wrapper CALLS WRF-Hydro subroutines, it doesn't replace them
- Start with serial mode only (no MPI, no parallel)
- Map internal variable names to CSDMS Standard Names in a dictionary
- Don't rename internal variables — create a mapping dictionary instead
- Start with 5-10 key variables, expand later

## 5-Layer Architecture
Layer 1: Original Models (WRF-Hydro + SCHISM in Fortran)
Layer 2: BMI Wrappers + Standard Names (bmi_wrf_hydro.f90 + bmischism.f90)
Layer 3: Babelized Plugins (pymt_wrfhydro + pymt_schism Python packages)
Layer 4: PyMT Framework (grid mapping, time sync, data exchange)
Layer 5: Scientist / Jupyter Notebook (~20 lines of Python)

## Project Roadmap (4 Phases)

### Phase 1: Write BMI Wrapper for WRF-Hydro (MAIN WORK — COMPLETE)
- [x] Study BMI examples, SCHISM BMI, documentation
- [x] Build and run bmi-example-fortran (49/49 tests pass, build_and_test.sh)
- [x] Install Fortran BMI bindings (bmi-fortran 2.0.3 in wrfhydro-bmi env)
- [x] Study WRF-Hydro internals (time loop, key subroutines, state variables)
- [x] Identify WRF-Hydro variables to expose (8 output + 4 input mapped)
- [x] Study SCHISM BMI approach (#ifdef USE_NWM_BMI in 3 files)
- [x] Create detailed Master Plan (bmi_wrf_hydro/Docs/Plan/BMI_Implementation_Master_Plan.md)
- [x] WRF-Hydro compiled and running (Croton NY test case, 6hr = 39 output files)
- [x] Refactor WRF-Hydro time loop (IRF pattern via land_driver_ini/exe)
- [x] Write bmi_wrf_hydro.f90 (all 41 functions, ~1900 lines)
- [x] Write bmi_wrf_hydro_test.f90 (151 tests, ~1780 lines)
- [x] Build and link against WRF-Hydro libraries (build.sh)
- [x] ALL 151 BMI TESTS PASS (Croton NY test case, 6-hour simulation)
- [ ] Compile as shared library (libwrfhydro_bmi.so) ← NEXT

### Phase 2: Babelize Both Models (mostly automated)
- [ ] Install babelizer (conda install babelizer)
- [ ] Write babel.toml for WRF-Hydro
- [ ] Run: babelize init babel.toml -> pymt_wrfhydro
- [ ] Write babel.toml for SCHISM
- [ ] Run: babelize init babel.toml -> pymt_schism

### Phase 3: Register PyMT Plugins
- [ ] Install PyMT (conda install pymt)
- [ ] Install both plugins, verify with pymt.MODELS
- [ ] Run bmi-tester on both plugins
- [ ] Validate results match standalone model runs

### Phase 4: Couple and Run
- [ ] Write coupling script (get_value -> set_value loop)
- [ ] Configure grid mapping (1km regular -> unstructured triangles)
- [ ] Configure time synchronization (hourly sync points)
- [ ] Test with simple coastal domain
- [ ] Run compound flooding case study

## Build Environment (conda: wrfhydro-bmi)
- conda env: wrfhydro-bmi (/home/mohansai/miniconda3/envs/wrfhydro-bmi)
- gfortran: 14.3.0 (conda-forge gcc 14.3.0-17)
- MPI: Open MPI 5.0.8 via conda (mpif90, mpirun --oversubscribe -np 1)
- NetCDF-Fortran: 4.6.2 / NetCDF 4.9.3 via conda
- cmake: 3.31.1 via conda
- bmi-fortran: 2.0.3 via conda (provides bmif_2_0 module, libbmif.so)
- WRF-Hydro build: wrf_hydro_nwm_public/build/Run/wrf_hydro (compiled, NoahMP LSM)
- BMI Heat build: bmi-example-fortran/_build/ (libheatf.so + libbmiheatf.so + 51 exes)
- Activate: source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi

## WRF-Hydro Build Commands
```bash
cd wrf_hydro_nwm_public
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
# Executable: build/Run/wrf_hydro
# Symlinks: wrf_hydro_NoahMP, wrf_hydro.exe
```

## Current Status (Updated Feb 2026)
- BMI WRAPPER COMPLETE: bmi_wrf_hydro.f90 (~1900 lines) + test suite (151/151 pass)
- WRF-Hydro: v5.4.0 compiled, running Croton NY test case (6hr, 39 output files)
- BMI wrapper: initialize/update/finalize working, bit-for-bit match with standalone
- BMI variables: 8 output + 4 input exposed via CSDMS Standard Names
- BMI grids: 3 types (1km LSM, 250m routing, vector channel) all tested
- Build script: bmi_wrf_hydro/build.sh (compile + link against 22 WRF-Hydro libs)
- Run: mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test (from bmi_wrf_hydro/)
- Directory reorganized: src/ (wrapper), tests/ (test programs), build/ (artifacts)
- BMI Heat Example: Built and fully tested (49/49 CTest pass, build_and_test.sh works)
- SCHISM: Full model in schism_NWM_BMI/ (uses #ifdef, no separate bmischism.f90)
- bmi-fortran 2.0.3 installed in conda env, all BMI build deps verified
- Master Plan created with 6 implementation phases
- Phase 1 COMPLETE, NEXT = shared library (libwrfhydro_bmi.so) then Phase 2 (babelizer)
- SCHISM BMI analysis: 1-way coupling ready (receive discharge), 2-way needs SCHISM additions
- WRF-Hydro variable inventory: 154+ output vars, ~89 key, 22% have CSDMS names, 78% proposed
- Weekly Reporting PPTs in bmi_wrf_hydro/Docs/Weekly Reporting/ (Feb 13, Feb 20)
- Doc 10: SCHISM BMI complete guide — build, run, LynkerIntel wrapper, NextGen, PyMT status
- Doc 11: SCHISM BMI deep dive — concepts only, 17 vars, 9 grids, t0/t1 pattern, NOAA usage, validation status
- LynkerIntel/SCHISM_BMI added as git submodule (bmi-integration-master branch, bmischism.f90 = 1,729 lines)
- SCHISM NOT in CSDMS/PyMT catalog — BMI built for NOAA NextGen, not PyMT pathway

## Key Design Decisions Made
- Serial first (no MPI) — following SCHISM's approach
- Start with channel discharge + soil moisture + snow variables
- Use CPP flag USE_NWM_BMI
- Config: pass-through to existing namelists via BMI namelist
- 3 grids: 1km LSM (grid 0), 250m routing (grid 1), channel vector (grid 2)
- BMI wrapper uses write(0,*) for stderr output (stdout redirected by WRF-Hydro)
- Module-level wrfhydro_engine_initialized flag prevents double WRF-Hydro init
- MPI_Finalize must be called by the test program, NOT the BMI wrapper
- Grid spacing from nlst(1)%dxrt0 (rt_domain%DX is never set by WRF-Hydro)
- get_value_ptr returns BMI_FAILURE (WRF-Hydro uses single-precision REAL, BMI needs double)

## Reference Docs (in bmi_wrf_hydro/Docs/)
1. Complete_Beginners_Guide — Big picture, spatial/temporal concepts, model overview
2. BMI_Complete_Detailed_Guide — All 41 functions, grid types, best practices
3. CSDMS_Standard_Names_Complete_Guide — Naming conventions, mapping guide
4. Babelizer_Complete_Guide — Fortran->Python translation, babel.toml format
5. PyMT_Complete_Guide — Coupling framework, grid mappers, time steppers
6. Project_Framework_Complete_Guide — Full architecture, roadmap, status
7. WRF_Hydro_Beginners_Guide_For_ML_Engineers — WRF-Hydro from zero (1,439 lines)
8. BMI_Template_And_Heat_Model_Complete_Code_Guide — Line-by-line code walkthrough (1,980 lines)
9. BMI_Architecture_SCHISM_vs_WRFHydro_Complete_Guide — SCHISM vs WRF-Hydro BMI, variable inventory, CSDMS names (1,286 lines)
10. SCHISM_BMI_How_To_Run_Complete_Guide — How to build, configure, run SCHISM with BMI, LynkerIntel repo, NextGen integration
11. SCHISM_BMI_Implementation_Deep_Dive_Concepts — Concepts only (no code), 17 variables, 9 grids, t0/t1 pattern, NOAA usage, validation
12. BMI_Implementation_Concepts_Heat_SCHISM_WRFHydro — Concepts: Heat BMI + SCHISM BMI implementation patterns, all I/O vars, 9 grids, t0/t1, WRF-Hydro roadmap
13. SCHISM_And_Its_BMI_Complete_Deep_Dive — SCHISM model physics, unstructured mesh, semi-implicit method, BMI implementation, 12 input + 5 output vars, 9 grids, t0/t1 pattern, NextGen, repo links (MD + DOCX)
14. WRF_Hydro_Model_Complete_Deep_Dive — WRF-Hydro physics (Noah-MP, overland, subsurface, channel, GW), equations, 3 grids, 80+ variables, RT_FIELD, NWM operations, architecture, build system, coupling
15. BMI_WRF_Hydro_Build_Test_Complete_Guide — All BMI files explained, build system, test suite, VS Code setup, Croton NY data, troubleshooting, step-by-step commands
Plan/BMI_Implementation_Master_Plan.md — 16-section detailed implementation plan (1,115 lines)

## Reference Docs (in WRF_Hydro_Run_Local/Docs/)
2. Config_Files_Complete_Guide — namelist.hrldas, hydro.namelist, .TBL files explained
3. VSCode_Settings_Guide — VS Code settings for Fortran/BMI development

## Scripts
- bmi_wrf_hydro/build.sh — Build BMI wrapper + tests (compile + link 22 WRF-Hydro libs)
- WRF_Hydro_Run_Local/run_and_test.sh — Run WRF-Hydro Croton NY + validate output
- bmi-example-fortran/build_and_test.sh — Clean build + run all 49 BMI tests

## WSL2/NTFS Known Issues
- Long paths (>80 chars) truncated by Fortran character(len=80) — use relative paths
- `local var=$(command)` in bash causes output duplication — separate declaration from assignment
- Clock skew warnings during cmake build — harmless, caused by WSL2 filesystem
