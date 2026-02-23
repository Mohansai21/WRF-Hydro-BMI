# External Integrations

**Analysis Date:** 2026-02-23

## APIs & External Services

**CSDMS Basic Model Interface (BMI):**
- Service: Open-source model coupling standard (https://bmi.readthedocs.io)
- What it's used for: Standardized interface for external control of WRF-Hydro
  - 41 functions implemented: initialize, update, finalize, get/set values, grid operations
  - Enables coupling frameworks (PyMT, NextGen) to call model without internal knowledge
- SDK/Client: bmi-fortran 2.0.3 (Fortran bindings, abstract interface)
  - Location: `bmi-fortran/` (abstract module definition)
  - Installed: `$CONDA_PREFIX/include/bmif_2_0.mod`, `$CONDA_PREFIX/lib/libbmif.so`
- Auth: None (open-source specification)

**PyMT (Python Modeling Toolkit):**
- Service: Multi-model coupling framework for Earth systems (https://pymt.readthedocs.io)
- What it's used for: Will orchestrate WRF-Hydro + SCHISM coupling via BMI (Phase 2-3)
  - Handles time synchronization, grid mapping, data exchange
  - Provides grid mappers (rectilinear → unstructured triangle)
- Integration approach: Via "babelizer" tool (automated Python wrapper generation)
  - Generates `pymt_wrfhydro` Python package from BMI Fortran code
  - Not yet implemented (Phase 2 roadmap item)

**NOAA NextGen Framework:**
- Service: NOAA-OWP National Water Model integration framework (https://github.com/NOAA-OWP/ngen)
- What it's used for: Alternative coupling path (similar to PyMT, Phase 2-3)
- Integration approach: BMI wrapper bridges to NextGen's data exchange layer
  - NextGen issue #547 tracks WRF-Hydro BMI status
  - SCHISM already has BMI for NextGen integration (production usage)
- Reference: `SCHISM_BMI/` submodule uses same BMI pattern

**SCHISM Coastal Ocean Model:**
- Service: Structured-unstructured hybrid mesh coastal model (LynkerIntel/NOAA CSDMS)
- What it's used for: Coupled compound flooding simulation with WRF-Hydro
  - WRF-Hydro outputs: river discharge (channel_water__volume_flow_rate m3/s)
  - SCHISM inputs: discharge boundary conditions, precipitation, atmospheric pressure
  - SCHISM outputs: ocean elevation (sea_water_surface__elevation m), tidal/surge levels
  - WRF-Hydro inputs: back-water effects from coastal flooding (elevation feedback)
- Integration point: BMI get_value / set_value loop in coupling script (Phase 3)
  - Data exchange frequency: Hourly (default sync point)
  - Reference: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` input var #3: sea_water_surface__elevation
- SDK: SCHISM BMI wrapper (bmischism.f90 or #ifdef USE_NWM_BMI pattern)
  - Location: `SCHISM_BMI/` (submodule), `schism_NWM_BMI/` (full model copy)
  - Variables: 12 inputs (discharge, precip, temperature, etc.) + 5 outputs (elevation, velocity)

## Data Storage

**Databases:**
- None used directly by BMI wrapper
- Model state is in-memory (WRF-Hydro RT_FIELD struct @ `wrf_hydro_nwm_public/src/Data_Rec/module_rt_inc.F90`)
  - Contains routing variables: channel storage, overland depth, subsurface moisture, reservoir levels
  - No database persistence; state reset at each initialize() call

**File Storage:**

*Input Data:*
- Format: NetCDF (gridded binary with metadata)
- Location: `WRF_Hydro_Run_Local/run/DOMAIN/` and `FORCING/`
- Managed by: WRF-Hydro orchestrator (via orchestrator%init())
  - DOMAIN files: Static geometry (DEM, river network, soil properties)
  - FORCING files: Meteorological input (precipitation, temperature, radiation)
- Client: NetCDF-Fortran 4.6.2 (libnetcdff.so)
  - Imported indirectly via `module_NetCDF_layer`, `module_hydro_orchestrator`

*Output Data:*
- Format: NetCDF (gridded + river reach diagnostics)
- Location: `WRF_Hydro_Run_Local/run/OUTPUT/` (after run)
  - Files: routing_*.nc (channel flow), lakeout_*.nc (reservoir outflows), etc.
- Written by: WRF-Hydro I/O layer (during land_driver_exe → orchestrator output calls)
- Not controlled by BMI wrapper (output happens automatically during model run)

*Test/Reference Data:*
- Croton NY test case: `WRF_Hydro_Run_Local/croton_NY_training_example_v5.4.tar.gz` (120 MB)
  - Domain: Hurricane Irene 2011, ~100 km² NY watershed
  - Simulation: 6-hour run, generates 39 output files
  - Used for: BMI test execution, bit-for-bit validation

**Caching:**
- None explicit
- WRF-Hydro module-level SAVE variables act as persistent cache across updates
  - Example: SMOIS (soil moisture), SFCRUNOFF accumulation persist across update() calls
  - Note: Prevents re-initialization (wrfhydro_engine_initialized flag prevents double init)

## Authentication & Identity

**Auth Provider:**
- None (all components are open-source, no API keys or credentials required)

**Implementation Approach:**
- Conda environment isolation: Each user activates `wrfhydro-bmi` env
- File system permissions: Input/output directories must be read/write accessible
- MPI authentication: None (Open MPI single-node or local cluster)

## Monitoring & Observability

**Error Tracking:**
- Not configured
- Manual error handling: BMI functions return integer status codes
  - 0 = BMI_SUCCESS, 1 = BMI_FAILURE
  - Functions check return values but don't log to external service

**Logs:**

*Approach:*
- stderr output: `write(0,*)` for debug messages (bypasses WRF-Hydro's stdout redirect)
- WRF-Hydro diagnostics: File-based at `diag_hydro.00000` (opened via open_print_mpp)
- Test reporting: Custom console output in test driver (`bmi_wrf_hydro_test.f90`)

*Log Levels:*
- Debug: Only in `-DHYDRO_D` builds (verbose routing debug)
- Info: Test pass/fail counts, BMI function entry/exit
- Warning/Error: Return code checks in test driver

*Aggregation:*
- No centralized log collection
- Logs stay local in run directory

## CI/CD & Deployment

**Hosting:**
- Not applicable (pure simulation, no web service)
- Deployment artifact: Shared library (libwrfhydro_bmi.so)
  - Installed to: `$CONDA_PREFIX/lib/` (via CMake install)
  - Used by: Babelizer (Python wrapper generation, Phase 2)

**CI Pipeline:**
- None configured (manual testing only, Phase 1)
- Manual test execution:
  ```bash
  cd bmi_wrf_hydro
  ./build.sh full
  mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test  # 151 tests, ~2-3 min
  ```
- All 151 tests PASS as of Feb 2026

**Future CI (Phase 2+):**
- GitHub Actions (tentative) or cloud runner
- Would validate: CMake build, all tests pass, bmi-tester compliance
- Trigger: Commits to main branch or PR

## Environment Configuration

**Required env vars:**
- `CONDA_PREFIX` - Used by build.sh to find bmif, NetCDF (set by conda activate)
- `WRF_HYDRO=1` - Set by CMakeLists.txt (enables WRF-Hydro code paths)

**Optional env vars:**
- `HYDRO_D` - Debug logging (0=off, 1=on, default per build type)
- `WRF_HYDRO_NUDGING` - Streamflow nudging (0=off, default)
- Others: SPATIAL_SOIL, NCEP_WCOSS, NWM_META (all defaults 0)

**Secrets location:**
- None used
- No API keys, credentials, or secrets in codebase
- All configuration via namelists and environment

## Webhooks & Callbacks

**Incoming:**
- None (this is a library, not a service)

**Outgoing:**
- None configured
- No external notifications or webhook calls from BMI wrapper

**Data Exchange with Coupled Models:**

*WRF-Hydro → SCHISM (1-way, ready):*
- Variable: channel_water__volume_flow_rate (streamflow, m3/s)
- Mechanism: BMI get_value() called by PyMT coupling loop
- Synchronization: Hourly (sync point frequency configurable)
- Reference: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` output variable #1

*SCHISM → WRF-Hydro (2-way, requires additions):*
- Variable: sea_water_surface__elevation (tidal/flood elevation, m)
- Mechanism: BMI set_value() called by PyMT coupling loop
- Status: Input infrastructure ready, WRF-Hydro lateral inflow code may need updates
- Reference: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` input variable #3

## Integration Dependencies

**Critical for Phase 1 (BMI Wrapper - COMPLETE):**
- bmi-fortran 2.0.3 ✓
- gfortran 14.3.0 + Open MPI 5.0.8 ✓
- NetCDF-Fortran 4.6.2 ✓
- WRF-Hydro v5.4.0 ✓

**Critical for Phase 2 (Babelizer - TODO):**
- babelizer (conda-forge, not yet installed)
- Python 3.10+ environment
- pymt package (for development)

**Critical for Phase 3 (PyMT Coupling - TODO):**
- pymt package (conda-forge)
- pymt_wrfhydro plugin (generated by babelizer)
- pymt_schism plugin (TBD for SCHISM)

**Critical for Phase 3 (NextGen Coupling - TODO):**
- NOAA NextGen framework (private repo, contact NOAA-OWP)
- NextGen BMI transport layer

## Known Integration Issues

**SCHISM BMI Status:**
- Issue: SCHISM not in CSDMS/PyMT registry
- Impact: No automated Python binding generation (babelizer not configured for SCHISM)
- Status: SCHISM BMI built for NOAA NextGen only, not PyMT pathway
- Workaround: LynkerIntel/SCHISM_BMI repo (submodule) has manual bindings

**WRF-Hydro Lateral Inflow (Coastal Feedback):**
- Issue: BMI input for sea_water_surface__elevation (elevation) implemented, but WRF-Hydro's lateral inflow code may need extensions
- Current: set_value() accepts elevation, no validation that it affects routing
- Needed: Integrate elevation into channel routing equations (Phase 3 engineering)

**Grid Mapping (Unstructured → Rectilinear):**
- Issue: WRF-Hydro is 1km/250m regular grid; SCHISM is unstructured triangles
- Solution: PyMT grid_mappers (Phase 3) will handle interpolation
- Currently: Only single-point coupling tested (representative reach outlet)

---

*Integration audit: 2026-02-23*
