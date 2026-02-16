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
- wrf_hydro_nwm_public/     -> WRF-Hydro source code (Fortran 90, by NCAR)
- schism_NWM_BMI/            -> SCHISM's BMI wrapper (our REFERENCE template)
- bmi-example-fortran/       -> CSDMS simple BMI example (LEARNING template)
- bmi-fortran/               -> BMI Fortran specification (abstract interface)
- bmi_wrf_hydro/             -> OUR work directory (BMI wrapper we're writing)
- bmi_wrf_hydro/Docs/        -> 6 detailed project guide documents

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
- bmi-example-fortran/bmi_heat/bmi_heat.f90  -> Simple BMI example (41 functions)
- bmi-example-fortran/heat/heat.f90          -> Simple model being wrapped
- bmi-example-fortran/bmi_heat/bmi_main.f90  -> BMI driver program
- schism_NWM_BMI/src/bmischism.f90           -> SCHISM's real BMI (our reference)
- bmi-fortran/bmi.f90                        -> The abstract BMI interface
- wrf_hydro_nwm_public/src/                  -> WRF-Hydro source code

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
WRF-Hydro's main program has an integrated time loop. Must decompose:
- initialize() -> calls WRF-Hydro init routines, NO time stepping
- update()     -> executes exactly ONE time step
- finalize()   -> cleanup, free memory, close files
The CALLER (PyMT) controls the time loop, not the model.

## Compile Commands
- Compile BMI module only:
  gfortran -c -I$CONDA_PREFIX/include bmi_wrf_hydro.f90
- Compile with BMI Fortran lib:
  gfortran -c -I$CONDA_PREFIX/include bmi_wrf_hydro.f90 -L$CONDA_PREFIX/lib -lbmif
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

### Phase 1: Write BMI Wrapper for WRF-Hydro (MAIN WORK)
- [x] Study BMI examples, SCHISM BMI, documentation
- [ ] Build and run bmi-example-fortran (heat model) as learning exercise
- [ ] Install Fortran BMI bindings (conda install bmi-fortran)
- [ ] Study WRF-Hydro internals (time loop, key subroutines, state variables)
- [ ] Identify WRF-Hydro variables to expose (start with 5-10)
- [ ] Refactor WRF-Hydro time loop (IRF pattern)
- [ ] Write bmi_wrf_hydro.f90 (all 41 functions)
- [ ] Compile as shared library (libwrfhydro_bmi.so)
- [ ] Write Fortran test driver to validate BMI

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
- gfortran: 13.3.0 (system) / 14.3.0 (conda)
- MPI: Open MPI via conda (mpif90, mpirun)
- NetCDF-Fortran: 4.6.2 via conda
- cmake: 3.31.1 via conda
- bmi-fortran: 2.0.3 via conda
- WRF-Hydro build: wrf_hydro_nwm_public/build/Run/wrf_hydro (compiled, NoahMP LSM)
- Activate: conda activate wrfhydro-bmi

## WRF-Hydro Build Commands
```bash
cd wrf_hydro_nwm_public
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
# Executable: build/Run/wrf_hydro
# Symlinks: wrf_hydro_NoahMP, wrf_hydro.exe
```

## Current Status
- SCHISM: BMI exists (bmischism.f90), no PyMT plugin yet
- WRF-Hydro: Compiled successfully, NO BMI yet, no PyMT plugin
- Phase 1 in progress: studying examples and documentation
- Next immediate step: build and run bmi-example-fortran heat model

## Key Design Decisions Made
- Serial first (no MPI) — following SCHISM's approach
- Start with channel discharge + soil moisture + snow variables
- Use CPP flag USE_NWM_BMI
- Config: pass-through to existing namelists
- Start with 1km grid + channel network, add 250m later

## Reference Docs (in bmi_wrf_hydro/Docs/)
1. Complete_Beginners_Guide — Big picture, spatial/temporal concepts, model overview
2. BMI_Complete_Detailed_Guide — All 41 functions, grid types, best practices
3. CSDMS_Standard_Names_Complete_Guide — Naming conventions, mapping guide
4. Babelizer_Complete_Guide — Fortran->Python translation, babel.toml format
5. PyMT_Complete_Guide — Coupling framework, grid mappers, time steppers
6. Project_Framework_Complete_Guide — Full architecture, roadmap, status
