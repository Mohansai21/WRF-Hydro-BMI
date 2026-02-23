# Architecture

**Analysis Date:** 2026-02-23

## Pattern Overview

**Overall:** Initialize-Run-Finalize (IRF) wrapper pattern with non-invasive BMI interface layer

**Key Characteristics:**
- WRF-Hydro original time loop (main program) is decomposed into BMI-controlled lifecycle
- BMI wrapper makes zero modifications to WRF-Hydro source code
- All WRF-Hydro subroutines are called as-is from the wrapper layer
- Module-level state persistence tracks engine initialization (prevents double-allocation)
- CSDMS Standard Names map internal variables to discoverable external interface

## Layers

**Layer 1: BMI Specification (Abstract Interface)**
- Purpose: Defines 41 standardized functions that any model must implement
- Location: `bmi-fortran/bmi.f90`
- Contains: Abstract `bmi` type with 53 deferred procedures
- Depends on: None (Fortran 2003 standard only)
- Used by: All BMI wrapper implementations

**Layer 2: BMI Wrapper (WRF-Hydro Binding)**
- Purpose: Concrete implementation of BMI for WRF-Hydro v5.4.0
- Location: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90`
- Contains: `bmi_wrf_hydro` type extending abstract `bmi`, 41 function implementations
- Depends on: WRF-Hydro modules (module_noahmp_hrldas_driver, module_RT_data, etc.), bmif_2_0, iso_c_binding
- Used by: Test programs, external coupling frameworks (PyMT, NextGen)

**Layer 3: WRF-Hydro Model (Fortran 90 Physics)**
- Purpose: Hydrological simulation engine with Noah-MP LSM + routing
- Location: `wrf_hydro_nwm_public/src/`
- Contains: Land surface (Noah-MP), overland flow, subsurface, channel routing, reservoirs
- Depends on: NetCDF libraries, MPI
- Used by: BMI wrapper (non-invasively)

**Layer 4: State Management Module**
- Purpose: Persist WRF-Hydro state across BMI lifecycle transitions
- Location: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (module `wrfhydro_bmi_state_mod`)
- Contains: Module-level SAVE variables (wrfhydro_bmi_state, wrfhydro_engine_initialized, wrfhydro_saved_ntime)
- Depends on: WRF-Hydro state_type
- Used by: bmi_wrf_hydro type for state persistence

## Data Flow

**Initialize → Run → Finalize Pattern:**

1. **initialize(config_file)**
   - Read BMI config file (Fortran namelist) → extract `wrfhydro_run_dir`
   - chdir() to run directory
   - Call orchestrator%init() → reads WRF-Hydro namelists (namelist.hrldas, hydro.namelist)
   - Call land_driver_ini() → Noah-MP initialization (calls HYDRO_ini internally)
   - Capture grid dimensions from module variables (IX, JX, NSOIL, IXRT, JXRT, NLINKS)
   - Calculate grid spacing from config (nlst(1)%dxrt0)
   - Allocate coupling placeholders (sea_water_elevation, sea_water_x_velocity)
   - Set time tracking (start=0, end=ntime*dt, current=0)
   - chdir() back to original directory
   - Status: initialize=true, current_timestep=0

2. **update()**
   - Check initialized flag → fail if false
   - Increment current_timestep
   - chdir() to run directory
   - Call land_driver_exe(current_timestep) → Noah-MP step + HYDRO_exe internally
   - Update current_time = current_timestep * dt
   - chdir() back to original directory
   - Status: BMI_SUCCESS

3. **update_until(time)**
   - Calculate n_steps = (time - current_time) / dt
   - Loop: call update() n_steps times
   - Status: BMI_SUCCESS if all updates succeed

4. **finalize()**
   - Optional cleanup (files already closed by WRF-Hydro)
   - Do NOT call HYDRO_finish() — it contains stop statement + MPI_Finalize
   - MPI_Finalize must be called by test program, not wrapper
   - Status: BMI_SUCCESS

**Variable Data Flow (Get/Set):**

Get flow: WRF-Hydro internal arrays → reshape/flatten to 1D → caller's buffer
- QLINK1 (channel flow) ← rt_domain(1)%QLINK1
- SMOIS (soil moisture) ← SMOIS(i,1,j) [3D → 2D extract → 1D flatten]
- T2MVXY (temperature) ← T2MVXY + sentinel cleanup (replace >1e30 → 0)

Set flow: Caller's buffer → reshape to grid → WRF-Hydro arrays
- RAINBL (precip) ← incoming array reshaped (IX,JX)
- T2MVXY (temperature) ← incoming array reshaped (IX,JX)
- sea_water_elevation ← coupling placeholder (allocated but unused in Phase 1)
- sea_water_x_velocity ← coupling placeholder (allocated but unused in Phase 1)

**State Persistence:**

Module-level variables ensure state survives BMI's intent(out) on initialize():
```
wrfhydro_bmi_state      : WRF-Hydro state_type (SNOW, etc.)
wrfhydro_engine_initialized : .true. after first init, never resets
wrfhydro_saved_ntime    : Total timesteps (ntime) saved from first init
```

Reason: WRF-Hydro allocates module arrays (COSZEN, SMOIS, etc.) that cannot be re-allocated without modifying source. Once allocated, they persist. intent(out) on initialize resets bmi_wrf_hydro type but not module-level SAVE variables.

## Key Abstractions

**bmi_wrf_hydro Type:**
- Purpose: Encapsulates BMI contract for WRF-Hydro
- Members: initialized, current_timestep, ntime, start_time, current_time, end_time, dt, run_dir, grid dimensions (ix, jx, ixrt, jxrt, nlinks), coupling placeholders
- Pattern: extends abstract `bmi` type from bmif_2_0 module
- Example location: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90:159`

**Variable Name Mapping:**
- Purpose: Bridge CSDMS Standard Names to WRF-Hydro internal names
- Mapping table in `wrfhydro_get_double()` and `wrfhydro_set_double()` functions
- Example: 'channel_water__volume_flow_rate' → rt_domain(1)%QLINK1
- Pattern: Large select case statement matching CSDMS names to internal sources

**Grid Type Abstraction:**
- Purpose: Hide grid structure complexity from coupling frameworks
- Three grids: GRID_LSM (0, 1km Noah-MP), GRID_ROUTING (1, 250m terrain), GRID_CHANNEL (2, vector network)
- Each get_grid_*() function dispatches on grid_id to return appropriate metadata
- Example location: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90:1048-1227`

**Configuration Passthrough:**
- Purpose: Allow BMI caller to specify WRF-Hydro run directory
- Format: Fortran namelist with &bmi_wrf_hydro_config group
- Content: wrfhydro_run_dir = "/path/to/run/"
- Pattern: BMI config file → orchestrator → WRF-Hydro namelists (existing, unmodified)

## Entry Points

**bmi_wrf_hydro_test (Full Test Suite)**
- Location: `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90`
- Triggers: ./build/bmi_wrf_hydro_test (invoked by test runner or mpirun)
- Responsibilities: Execute 151 comprehensive tests covering all 41 BMI functions, verify outputs against Croton NY ground truth

**bmi_minimal_test (Smoke Test)**
- Location: `bmi_wrf_hydro/tests/bmi_minimal_test.f90`
- Triggers: ./build/bmi_minimal_test (quick verification)
- Responsibilities: Initialize → update 6 steps → finalize, verify basic lifecycle works

**External Entry Points (Future):**
- PyMT framework (Phase 2): Will call bmi_wrf_hydro via shared library libwrfhydro_bmi.so
- NextGen framework: Will call BMI functions to couple with precipitation generators

## Error Handling

**Strategy:** Return BMI_SUCCESS (0) or BMI_FAILURE (1) for all functions

**Patterns:**

1. **Allocation checks:** All get_value functions check if internal arrays are allocated before access
   - Pattern: `if (allocated(array))` → copy data, `else` → fill dest with 0.0d0 and return BMI_SUCCESS
   - Rationale: Graceful degradation; missing data doesn't break coupling

2. **Bounds checking:** Grid size queries validate against actual dimensions
   - Pattern: Check `this%nlinks > 0` before accessing rt_domain arrays
   - Rationale: Prevent out-of-bounds access

3. **Variable name validation:** get_var_* functions validate variable exists
   - Pattern: Select case on variable name; case default → BMI_FAILURE
   - Rationale: Caller discovers valid names via get_input/output_var_names first

4. **Time direction checks:** update_until rejects backward time movement
   - Pattern: `if (time < current_time) return BMI_FAILURE`
   - Rationale: Models cannot time-reverse

5. **Config file validation:** initialize checks file exists, is readable, contains required namelist
   - Pattern: inquire + open + read; if any fails → BMI_FAILURE
   - Rationale: Catch misconfiguration early

6. **Initialization guard:** Prevents double WRF-Hydro initialization via wrfhydro_engine_initialized flag
   - Pattern: Check flag; if true, skip orchestrator/land_driver init calls
   - Rationale: WRF-Hydro module arrays cannot be re-allocated

## Cross-Cutting Concerns

**Logging:**
- Method: write(0,*) for stderr output (unit 6/stdout redirected by WRF-Hydro to diag_hydro.00000)
- Pattern: Debug messages in initialize and update describe major steps
- Location: Multiple places in `bmi_wrf_hydro/src/bmi_wrf_hydro.f90`

**Validation:**
- Method: Sentinel value checks in get_value (T2MVXY > 1e30 replaced with 0)
- Pattern: Clean WRF-Hydro's undefined_real sentinel values before exposing to coupling framework
- Rationale: Coupling frameworks may not expect NaN/Inf equivalents

**Type Conversion:**
- Method: dble() conversion from REAL (single-precision) to double precision
- Pattern: All get_value operations convert to double for BMI output
- Location: Systematic in wrfhydro_get_double function body

**Directory Management:**
- Method: chdir before calling WRF-Hydro subroutines, chdir back after
- Pattern: getcwd() save → chdir(run_dir) → call WRF-Hydro → chdir(saved_dir)
- Rationale: WRF-Hydro reads/writes files from current directory; BMI caller may be elsewhere

**Array Flattening:**
- Method: reshape(2D_array, [nx*ny]) → 1D array (BMI standard)
- Pattern: All grid-like variables (SMOIS, RAINBL, etc.) reshaped to 1D before copying
- Rationale: Avoids row/column-major issues across language boundaries

---

*Architecture analysis: 2026-02-23*
