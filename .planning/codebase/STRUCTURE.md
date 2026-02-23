# Codebase Structure

**Analysis Date:** 2026-02-23

## Directory Layout

```
WRF-Hydro-BMI/                           # Project root
├── bmi_wrf_hydro/                       # BMI wrapper + tests (OUR WORK)
│   ├── src/
│   │   └── bmi_wrf_hydro.f90            # BMI wrapper module (1919 lines)
│   ├── tests/
│   │   ├── bmi_minimal_test.f90         # Smoke test: init/6 updates/finalize
│   │   └── bmi_wrf_hydro_test.f90       # Full test suite: 151 tests
│   ├── build/                           # Compiled artifacts (.o, .mod, executables)
│   ├── Docs/                            # 15 detailed guides + weekly reports
│   ├── CMakeLists.txt                   # CMake build configuration
│   └── build.sh                         # Bash build script (compile + link)
│
├── wrf_hydro_nwm_public/                # WRF-Hydro v5.4.0 source (NCAR, not modified)
│   ├── src/
│   │   ├── Land_models/NoahMP/          # Noah-MP land surface model
│   │   │   ├── IO_code/
│   │   │   │   ├── main_hrldas_driver.F             # Original time loop (not used by BMI)
│   │   │   │   ├── module_NoahMP_hrldas_driver.F  # Land driver init/exe/fin (CALLED BY BMI)
│   │   │   │   └── module_hrldas_netcdf_io.F      # I/O routines
│   │   │   └── [physics modules]                   # Noah-MP equations
│   │   ├── HYDRO_drv/
│   │   │   └── module_HYDRO_drv.F90    # Hydro driver init/exe/fin (CALLED BY BMI indirectly)
│   │   ├── Routing/
│   │   │   ├── module_rt_inc.F90        # RT_FIELD type (routing state)
│   │   │   └── [routing subroutines]    # Overland, subsurface, channel, reservoirs
│   │   ├── Data_Rec/
│   │   ├── MPP/                         # MPI utilities
│   │   ├── IO/                          # I/O layer (NetCDF)
│   │   └── OrchestratorLayer/           # orchestrator type for config init
│   └── build/
│       ├── lib/                         # Compiled WRF-Hydro libraries (22 .a files)
│       ├── mods/                        # Compiled .mod files
│       ├── Run/                         # wrf_hydro executable
│       └── src/CMakeFiles/              # Object files (.F.o)
│
├── WRF_Hydro_Run_Local/                 # Croton NY test case (Hurricane Irene 2011, 6hr)
│   ├── run/
│   │   ├── namelist.hrldas              # Noah-MP configuration
│   │   ├── hydro.namelist               # Routing configuration
│   │   ├── *.TBL                        # Lookup tables (soil, veg, etc.)
│   │   ├── DOMAIN/                      # Static spatial data
│   │   ├── FORCING/                     # Meteorological forcing (3hr)
│   │   └── [output files]               # QOUT, CHRTOUT, etc.
│   ├── test_data/                       # Supporting files
│   └── Docs/
│       ├── Config_Files_Complete_Guide.md
│       └── VSCode_Settings_Guide.md
│
├── bmi-fortran/                         # BMI v2.0 Fortran specification (CSDMS)
│   └── bmi.f90                          # Abstract bmi type + 53 deferred procedures
│
├── bmi-example-fortran/                 # Reference heat diffusion example (CSDMS)
│   ├── bmi_heat/
│   │   ├── bmi_heat.f90                 # Heat example BMI (935 lines, BLUEPRINT)
│   │   └── heat.f90                     # Physics module
│   ├── heat/                            # Physics-only heat module
│   ├── example/                         # Example programs (8 different scenarios)
│   ├── test/                            # Test programs
│   └── _build/                          # CMake build artifacts (49/49 tests pass)
│
├── schism_NWM_BMI/                      # SCHISM v5.14 with BMI wrapper (full model, 437 files)
│   ├── src/
│   │   ├── Driver/
│   │   │   └── schism_driver.F90        # IRF pattern for SCHISM
│   │   ├── Hydro/
│   │   │   └── schism_init.F90          # Uses #ifdef USE_NWM_BMI
│   │   └── [physics modules]
│   └── [cmake, docs, tests]
│
├── SCHISM_BMI/                          # LynkerIntel SCHISM BMI wrapper (submodule, bmi-integration-master)
│   ├── src/
│   │   └── schism.f90                   # bmischism.f90 equivalent (1729 lines)
│   └── [cmake, docs]
│
├── bmi_wrf_hydro_test.f90               # Symlink or old test location (avoid)
├── .planning/
│   └── codebase/
│       ├── ARCHITECTURE.md              # This file
│       ├── STRUCTURE.md                 # This file
│       └── [STACK.md, INTEGRATIONS.md, CONVENTIONS.md, TESTING.md, CONCERNS.md when generated]
├── CLAUDE.md                            # Project instructions (MUST READ)
└── [git, cmake configs, ...]
```

## Directory Purposes

**bmi_wrf_hydro/src/**
- Purpose: BMI wrapper source code
- Contains: Single file `bmi_wrf_hydro.f90` (~1919 lines) implementing 41 BMI functions
- Key files: `bmi_wrf_hydro.f90` (module `wrfhydro_bmi_state_mod` + module `bmiwrfhydrof`)

**bmi_wrf_hydro/tests/**
- Purpose: Test executables for BMI wrapper
- Contains: Two Fortran programs exercising the BMI interface
- Key files:
  - `bmi_minimal_test.f90` (105 lines): Quick sanity check — init/6 updates/finalize
  - `bmi_wrf_hydro_test.f90` (1777 lines): Comprehensive 151-test suite with all BMI functions

**bmi_wrf_hydro/build/**
- Purpose: Compiled artifacts
- Contains: Object files (.o), module files (.mod), executables (bmi_minimal_test, bmi_wrf_hydro_test)
- Generated by: `./build.sh` script
- Consumed by: `mpirun` to run tests

**bmi_wrf_hydro/Docs/**
- Purpose: Detailed documentation guides
- Contains: 15 markdown files + weekly reporting PPTs
  - Doc 1-6: Basic to advanced BMI concepts
  - Doc 7: WRF-Hydro for ML engineers (beginners guide)
  - Doc 8: BMI template + heat model code walkthrough
  - Doc 9: SCHISM vs WRF-Hydro BMI + variable inventory
  - Doc 10: SCHISM BMI how-to guide
  - Doc 11-14: Deep dive implementations
  - Doc 15: Build & test complete guide
  - `Plan/`: Implementation master plan with 16 sections
  - `Weekly Reporting/`: Feb 13, Feb 20 PPT updates

**wrf_hydro_nwm_public/src/Land_models/NoahMP/IO_code/**
- Purpose: WRF-Hydro driver that BMI calls directly
- Contains: Main program + driver subroutines for land surface model
- Critical files (CALLED BY BMI):
  - `module_NoahMP_hrldas_driver.F:422` — `land_driver_ini()` (Noah-MP initialization)
  - `module_NoahMP_hrldas_driver.F:1646` — `land_driver_exe()` (one timestep execution)
  - `module_hrldas_netcdf_io.F` — I/O helpers

**wrf_hydro_nwm_public/src/HYDRO_drv/**
- Purpose: Hydrologic routing driver (called indirectly by land_driver_ini/exe)
- Contains: Routing initialization and execution
- Critical files (CALLED INTERNALLY):
  - `module_HYDRO_drv.F90:1350` — `HYDRO_ini()` (initialization, called by land_driver_ini)
  - `module_HYDRO_drv.F90:561` — `HYDRO_exe()` (one step, called by land_driver_exe)
  - `module_HYDRO_drv.F90:1800` — `HYDRO_finish()` (cleanup, NOT CALLED by BMI)

**wrf_hydro_nwm_public/src/Data_Rec/**
- Purpose: Data record structures and routing state
- Contains: RT_FIELD type definition + helper arrays
- Critical files:
  - `module_rt_inc.F90` — RT_FIELD type (contains all routing state vars: QLINK1, ZELEV, etc.)

**wrf_hydro_nwm_public/build/lib/**
- Purpose: Compiled WRF-Hydro libraries
- Contains: 22 .a files (liblibro_driver.a, libhydro_orchestrator.a, etc.)
- Built by: WRF-Hydro CMake build (./build.sh in wrf_hydro_nwm_public)

**WRF_Hydro_Run_Local/run/**
- Purpose: Croton NY test case execution directory
- Contains: Namelists, forcing data, static files, output
- Critical files:
  - `namelist.hrldas` — Noah-MP configuration (domain size, timestep, etc.)
  - `hydro.namelist` — Routing config (grid spacing, routing model choice, etc.)
  - `DOMAIN/` — static files (soil, elevation, land use masks)
  - `FORCING/` — meteorological input (precip, temp, wind, etc., 3-hourly)
  - Output: QOUT.*, CHRTOUT.* (6hr sim = 39 files)

**bmi-example-fortran/**
- Purpose: Reference implementation of BMI (heat diffusion model)
- Contains: Physics module + BMI wrapper + test suite
- Critical files:
  - `bmi_heat/bmi_heat.f90` — Reference BMI wrapper (BLUEPRINT for WRF-Hydro wrapper)
  - `heat/heat.f90` — Physics (1D heat equation)
  - `example/` — 8 example programs showing different BMI usage patterns
  - `_build/` — CMake artifacts (49 CTest pass)

**schism_NWM_BMI/** and **SCHISM_BMI/**
- Purpose: SCHISM coastal ocean model with BMI (for future coupling)
- Contains: Full SCHISM model with #ifdef USE_NWM_BMI conditional compilation
- Critical files:
  - `src/Hydro/schism_init.F90` — Shows #ifdef pattern for BMI integration
  - `src/Driver/schism_driver.F90` — IRF pattern applied to SCHISM

## Key File Locations

**Entry Points:**

| File | Purpose | Invoked by |
|------|---------|-----------|
| `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` | BMI wrapper implementation | Test programs, PyMT framework |
| `bmi_wrf_hydro/tests/bmi_minimal_test.f90` | Smoke test (quick) | Test runner, manual |
| `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90` | Full test suite (151 tests) | CI pipeline, manual |
| `bmi_wrf_hydro/CMakeLists.txt` | CMake build config | cmake command |
| `bmi_wrf_hydro/build.sh` | Bash build wrapper | ./build.sh from bmi_wrf_hydro/ |

**Configuration:**

| File | Purpose | Format |
|------|---------|--------|
| `WRF_Hydro_Run_Local/run/namelist.hrldas` | Noah-MP config | Fortran namelist |
| `WRF_Hydro_Run_Local/run/hydro.namelist` | Routing config | Fortran namelist |
| `bmi_wrf_hydro/tests/bmi_config.nml` | BMI config (created by test) | Fortran namelist with &bmi_wrf_hydro_config |

**Core Logic:**

| File | Lines | Purpose |
|------|-------|---------|
| `bmi_wrf_hydro/src/bmi_wrf_hydro.f90:1-25` | 25 | Module wrfhydro_bmi_state_mod (state persistence) |
| `bmi_wrf_hydro/src/bmi_wrf_hydro.f90:111-297` | 187 | Type bmi_wrf_hydro definition + 55 procedure bindings |
| `bmi_wrf_hydro/src/bmi_wrf_hydro.f90:378-523` | 146 | initialize() function |
| `bmi_wrf_hydro/src/bmi_wrf_hydro.f90:535-565` | 31 | update() function |
| `bmi_wrf_hydro/src/bmi_wrf_hydro.f90:1470-1637` | 168 | wrfhydro_get_double() — variable data retrieval |
| `bmi_wrf_hydro/src/bmi_wrf_hydro.f90:1750-1900+` | 150+ | wrfhydro_set_double() — variable data setting |
| `wrf_hydro_nwm_public/src/Land_models/NoahMP/IO_code/module_NoahMP_hrldas_driver.F:422` | N/A | land_driver_ini() subroutine |
| `wrf_hydro_nwm_public/src/Land_models/NoahMP/IO_code/module_NoahMP_hrldas_driver.F:1646` | N/A | land_driver_exe() subroutine |
| `wrf_hydro_nwm_public/src/HYDRO_drv/module_HYDRO_drv.F90:1350` | N/A | HYDRO_ini() subroutine |
| `wrf_hydro_nwm_public/src/HYDRO_drv/module_HYDRO_drv.F90:561` | N/A | HYDRO_exe() subroutine |

**Testing:**

| File | Lines | Purpose |
|------|-------|---------|
| `bmi_wrf_hydro/tests/bmi_minimal_test.f90` | 105 | Minimal test: init + 6 updates + finalize |
| `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90` | 1777 | Full suite: 151 tests across all BMI functions |

## Naming Conventions

**Files:**

- `bmi_*.f90` — BMI-related code (wrapper, tests)
- `module_*.F` or `.F90` — WRF-Hydro module definitions (Fortran 90 style, uppercase extension)
- `*.f90` — Fortran 2003+ code (lowercase extension)
- `namelist.*` — Configuration files (Fortran namelists)
- `build.sh` — Shell build script (lowercase)
- `CMakeLists.txt` — CMake configuration (uppercase)

**Directories:**

- `src/` — Source code (modules, programs)
- `tests/` — Test programs
- `build/` — Compiled artifacts
- `Docs/` — Documentation
- `DOMAIN/` — Static spatial domain data
- `FORCING/` — Forcing data (meteorological input)
- `HYDRO_*` — Hydro/routing related
- `Land_models/` — Land surface model code (Noah-MP)

**Fortran Types/Modules:**

- `bmi_*` — BMI-related types/modules
- `wrfhydro_*` — WRF-Hydro BMI wrapper specifics
- `module_*` — Fortran modules (WRF-Hydro naming convention)
- `state_type` — State structure (holds arrays like SNOW)
- `RT_FIELD` — Routing field (holds arrays like QLINK1, ZELEV)

## Where to Add New Code

**New BMI Variable (Add to Input or Output):**

1. Add variable name to input_items or output_items array initialization (near line 325-329)
2. Add case in `wrfhydro_var_type()` function (line ~746)
3. Add case in `wrfhydro_var_units()` function (line ~779)
4. Add case in `wrfhydro_var_grid()` function (line ~832)
5. Add case in `wrfhydro_var_itemsize()` function (line ~872)
6. Add case in `wrfhydro_var_location()` function (line ~931)
7. Add case in `wrfhydro_get_double()` function (line ~1470) for output vars
8. Add case in `wrfhydro_set_double()` function (line ~1750) for input vars
9. Add corresponding test case in `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90`
10. Rebuild with `./build.sh`

**New Grid Type (e.g., sub-grid details):**

1. Add grid constant near line 331-336 (e.g., `integer, parameter :: GRID_LSM_DETAILS = 3`)
2. Add cases in all `wrfhydro_grid_*()` functions to handle new grid_id
3. Ensure get_grid_shape, get_grid_size, get_grid_spacing, get_grid_origin implemented
4. Add test cases in bmi_wrf_hydro_test.f90
5. Rebuild

**New Test:**

1. Create subroutine in `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90` (contains section)
2. Call from main program test loop
3. Use helper function `check_result()` for pass/fail tracking
4. Rebuild with `./build.sh full`
5. Run: `mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test`

**Coupling Variable from SCHISM (Future):**

1. Add to N_INPUT_VARS count (currently 4)
2. Add name to input_items array
3. Allocate corresponding 2D array in bmi_wrf_hydro type (like sea_water_elevation)
4. Add case in wrfhydro_set_double() to copy from coupling array into WRF-Hydro array
5. Modify land_driver_exe() call to pass coupling data (requires WRF-Hydro refactoring)
6. Test with bmi_wrf_hydro_test suite

## Special Directories

**bmi_wrf_hydro/build/**
- Generated by: `./build.sh`
- Contains: All .o files, .mod files, executables
- Cleaned by: `./build.sh clean`
- Committed: No (.gitignore excludes)

**wrf_hydro_nwm_public/build/**
- Generated by: CMake build in wrf_hydro_nwm_public/
- Contains: WRF-Hydro libraries (22 .a files in lib/), mods/, src/CMakeFiles/
- Consumed by: bmi_wrf_hydro/build.sh (links against these libraries)
- Committed: No (.gitignore excludes)

**WRF_Hydro_Run_Local/run/**
- Purpose: Working directory for WRF-Hydro execution (Croton NY test case)
- Contains: Namelists, domain data, forcing data, output files
- Generated by: WRF-Hydro standalone run (run_and_test.sh)
- Committed: Partially (namelists + small test files, not large outputs)

**bmi-example-fortran/_build/**
- Generated by: CMake build of bmi-example-fortran
- Contains: Heat diffusion model library + test executables (49 pass)
- Committed: No

**bmi_wrf_hydro/Docs/Plan/**
- Purpose: Master plan for BMI implementation
- Contains: 16-section document with roadmap, phases, variable inventory
- Committed: Yes (version controlled)

---

*Structure analysis: 2026-02-23*
