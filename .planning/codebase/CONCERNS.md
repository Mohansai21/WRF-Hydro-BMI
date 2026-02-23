# Codebase Concerns

**Analysis Date:** 2026-02-23

## Tech Debt

**Pointer Type Mismatch (get_value_ptr):**
- Issue: WRF-Hydro stores all data as single-precision REAL, but BMI requires double-precision pointers. Cannot safely return a double pointer to single-precision memory without data corruption or undefined behavior.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 1664-1678)
- Impact: All three `get_value_ptr_*` functions return `BMI_FAILURE`. Zero-copy data exchange via pointers is blocked. Coupling frameworks cannot directly read model state without copying through get_value_double.
- Fix approach: Phase 2 should introduce internal double-precision shadow arrays for key variables (QLINK1, SMOIS, etc.). Synchronize after each update(). Adds ~10-20% memory overhead but enables true zero-copy coupling. Alternative: use Fortran 2003's c_loc/c_f_pointer with type casting (unsafe but functional).

**Undefined Sentinel Values in Temperature:**
- Issue: WRF-Hydro initializes T2MVXY (2m temperature) to a sentinel value (~9.97E+036) for uncomputed cells (water bodies, boundaries). BMI output must clean these up but loses metadata about which cells were actually computed.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 1575-1592)
- Impact: Users cannot distinguish between "cell not computed" and "cell computed as 0K". May cause silent errors in coupling logic if coastal zones have invalid temps propagated to SCHISM.
- Fix approach: (1) Add mask array to BMI metadata (get_var_mask function) indicating which cells are valid, or (2) use NaN instead of hard-coded 0 replacement, or (3) document that values >1e30 indicate invalid cells and let coupling code handle it.

**Coupling Placeholders Never Used:**
- Issue: `sea_water_elevation` and `sea_water_x_velocity` fields in `bmi_wrf_hydro` type are allocated and can be set via set_value, but are never actually used to force WRF-Hydro. They're stubbed for Phase 2.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 187-191, 1824-1845, 1835-1843)
- Impact: SCHISM output can be received and stored, but has no effect on WRF-Hydro's surface water levels or coastal boundary conditions. One-way coupling only (WRF-Hydro → SCHISM). Two-way coupling requires integrating these into land_driver_exe() or HYDRO_exe().
- Fix approach: Phase 2 must connect sea_water_elevation to coastal head boundary conditions in HYDRO routing (likely via rt_domain%ELRTMAX or subsurface head). Requires detailed coupling logic design with domain oceanography team.

**Hardcoded 4 Input/8 Output Variables:**
- Issue: Only 4 input + 8 output variables exposed. WRF-Hydro has 154+ internal variables (per Doc 9). Variable inventory covers only ~5.2% of model state.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 319-320)
- Impact: Cannot couple on soil layer 2-4 (only layer 1 SMOIS exposed), cannot drive with radiation or humidity forcing, cannot observe reservoir elevation. Limits compound flooding scenarios to simple precipitation+discharge coupling.
- Fix approach: Expand variable mapping in phases: Phase 1 (current) = core variables, Phase 2 = add soil layers 2-4 + radiation, Phase 3 = add reservoir/lake vars. Requires careful CSDMS name selection for 150+ additional vars (substantial effort).

**Crash on Double Initialize:**
- Issue: WRF-Hydro module-level arrays (COSZEN, SMOIS, T2MVXY, etc.) persist across finalize(). Cannot re-allocate without explicit deallocation in WRF-Hydro source (which we cannot modify per project rules). Flag `wrfhydro_engine_initialized` prevents re-init but leaves dangling allocations.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 15-24, 394-471), `bmi_wrf_hydro/build.sh` (commented)
- Impact: Calling initialize() → finalize() → initialize() will succeed on second init but reuse stale allocation from first. If grids change (different domain in second run), memory corruption and segfault. Test suite has not verified re-initialization scenario.
- Fix approach: Document that only ONE initialize per process lifecycle is supported. Add explicit check in initialize() that prevents re-init and returns BMI_FAILURE with clear error message. For true re-init, require process restart or fork+MPI_Init per coupling framework instructions.

**Linear Grid Lookup O(N) Performance:**
- Issue: `get_var_grid(name, grid)` and similar metadata queries use string comparisons in select-case statements. Twelve separate case blocks (output + input + temp + precip). No hash table or dictionary.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 1420-1640)
- Impact: Negligible for current 12 variables. If expanded to 150+ variables (Phase 3), each get_value call does O(N) string matching. For high-frequency coupling (1s timesteps), could add measurable overhead.
- Fix approach: Build internal lookup table (hash map) at initialization time. Fortran has no built-in hash; implement linked-list or sorted array (binary search). Not urgent but good for >50 variable expansion.

---

## Known Bugs

**Grid Spacing Extraction Fragile:**
- Symptoms: `dx_lsm` computed from `dx_rt * (ixrt / ix)` ratio. If IXRT=61 and IX=15, get integer truncation 61/15=4 instead of 4.067. Grid spacing off by 0.5-1%.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 492-499)
- Trigger: Any domain where IXRT/IX is not a clean integer factor (e.g., nested grids, irregular regridding).
- Workaround: Always use regular integer aggregation factors in config (IXRT=4*IX, JXRT=4*JX). For Croton: IXRT=60, IX=15 works (factor=4). Document as requirement.

**MPI Finalize Responsibility Confusion:**
- Symptoms: If caller does NOT invoke MPI_Finalize after using BMI, program hangs or crashes with "unpaired MPI_Finalize" messages.
- Files: `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90` (line ~1500), `bmi_wrf_hydro/tests/bmi_minimal_test.f90` (line ~105)
- Trigger: Any Python/C wrapper calling BMI without proper MPI shutdown. PyMT wrappers must be careful.
- Workaround: Tests explicitly call MPI_Finalize. Documentation must state: "Caller is responsible for MPI_Finalize. BMI wrapper does NOT call it."

**Undefined Return Value on Error:**
- Symptoms: Some BMI functions (e.g., `get_var_grid`) do not initialize output argument on BMI_FAILURE, leaving garbage in caller's variable.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 821, 861, 894, 921, 937)
- Trigger: Call `get_var_grid("bad_variable_name", grid)` — grid is undefined on return.
- Workaround: Always check return status before using output. Caller should initialize grid=-1 or grid=0 before call.
- Fix approach: Initialize all intent(out) arguments at function entry (e.g., `grid = -1` on entry to get_var_grid). Adds 5 lines per function, improves safety.

---

## Security Considerations

**Config File Path Not Validated:**
- Risk: `wrfhydro_run_dir` read from BMI config file without path canonicalization. Could be relative path like `../../../../etc/passwd` or symlink to sensitive data. chdir() then reads namelists from attacker-specified location.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 400-444)
- Current mitigation: Expected to run in trusted HPC environment. No sandboxing assumed.
- Recommendations: (1) Validate path is within expected domain or HPC storage, (2) use absolute paths only, (3) add logging of chdir operations for audit trail.

**Environment Variable Injection via Namelist:**
- Risk: WRF-Hydro namelists (namelist.hrldas, hydro.namelist) read from run directory. If attacker can write these files, can inject arbitrary model behavior (disable conservation checks, modify routing coefficients). Not a direct BMI issue but affects any BMI caller that doesn't secure the domain directory.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (line 460: `call orchestrator%init()`)
- Current mitigation: File permissions on shared HPC storage.
- Recommendations: Document that run_dir must have restricted write permissions. Consider read-only namelists in config_base before orchestrator%init().

**No Input Validation on Variable Values:**
- Risk: set_value accepts any double value (negative precipitation, impossible temperatures, etc.) without physical bounds checking.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 1793-1845)
- Current mitigation: WRF-Hydro internally clips unphysical values, but behavior is undefined.
- Recommendations: Add soft bounds checking with warnings (precipitation >= 0, temperature 200-330K, soil moisture 0-1). Return BMI_FAILURE if outside hard bounds.

---

## Performance Bottlenecks

**Memory Allocation on Every get_value_at_indices Call:**
- Problem: `get_value_at_indices_double` allocates full array (IX*JX or IXRT*JXRT) just to pick N elements. For large grids, wasteful.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 1717-1752)
- Cause: Easiest implementation — reuse get_value_double then extract. Not optimized for sparse access.
- Improvement path: (1) Direct element-by-element access in case statement (requires 12x more code), (2) cache last variable accessed (risky), (3) use pointer arithmetic if possible (requires grid layout knowledge).

**Directory Change Overhead on Every update():**
- Problem: Each `update()` calls getcwd() → chdir(run_dir) → land_driver_exe() → chdir(saved_dir). Four system calls per timestep.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 551-562)
- Cause: WRF-Hydro opens input/output files assuming current dir is run_dir. Unavoidable unless modify WRF-Hydro.
- Improvement path: (1) Use Fortran open() file units with absolute paths (requires analyzing all file I/O in WRF-Hydro), (2) keep cwd in run_dir after initialize (may break other applications), (3) pre-compute full paths in initialization.

**String Comparisons in get_value Hot Path:**
- Problem: Each get_value call does string matching (case statement on 12 names). For 1Hz coupling (3600 calls/hour), non-trivial CPU.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 1420-1640)
- Cause: Simple, understandable code. No pre-computed lookup.
- Improvement path: Build hash map at init time. For current 12 vars, overhead ~100 lines. Payoff > 50 vars.

---

## Fragile Areas

**WRF-Hydro Module Array Persistence:**
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (module-level `wrfhydro_engine_initialized` flag), `wrf_hydro_nwm_public/src/Land_models/NoahMP/IO_code/module_NoahMP_hrldas_driver.F` (COSZEN, SMOIS, T2MVXY declarations)
- Why fragile: If caller forks after initialize(), child process inherits parent's allocated arrays. Both parent and child try to deallocate → double-free crash. If caller OOM during update(), arrays leak. If caller re-initializes with different domain size, use-after-free.
- Safe modification: (1) Document: "No fork after initialize()", (2) Add finalize_memory() internal routine to explicitly deallocate WRF-Hydro arrays (requires WRF-Hydro code changes), (3) Use process-level resource management (cgroups on Linux).
- Test coverage: Test suite does NOT verify fork/multi-process scenarios. Integration with PyMT will expose this if not careful.

**Coupling Placeholder Allocation/Deallocation:**
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 509-516 allocate, lines 1826-1839 set/get)
- Why fragile: Allocate in initialize(), never deallocate in finalize(). If finalize() is called, these leak. If caller calls initialize → finalize → initialize twice, allocation on second init fails (already allocated). No guard against re-allocation.
- Safe modification: Add explicit deallocate in finalize(). Add allocated() check before allocate() in initialize(). Better: use intrinsic allocatable semantics properly.

**rt_domain(1) Array Access:**
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 484-486)
- Why fragile: Hard-coded rt_domain(1) assumes single domain. WRF-Hydro can have nested domains (rt_domain(1), rt_domain(2), ...). If user configures multi-domain setup, wrapper only sees first domain, ignores others.
- Safe modification: Add domain ID to BMI config or auto-detect via rt_domain size. For now, document: "Only domain 1 supported."

**Test Suite Grid Size Assumptions:**
- Files: `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90` (hard-coded expectations for Croton NY: IX=15, JX=16)
- Why fragile: If test domain changes, test counts become invalid. ~1/5 of tests are spatial (grid size, spacing). Would fail silently or report wrong grid metrics.
- Safe modification: Dynamically allocate test arrays based on grid query results. Remove hard-coded dimensions.

---

## Scaling Limits

**Current Capacity: Single Domain, ~1000 Grid Points, 8 Variables:**
- Numbers: IX=15, JX=16 (240 land cells), IXRT=60, JXRT=64 (3840 routing cells), NLINKS=2700 channel links, 8 output vars.
- Limit: Not tested above 10K total cells. Memory scales linearly. 100K cells → ~100x more data → potential memory pressure on embedded systems or real-time systems with fixed memory budgets.
- Scaling path: (1) No code changes needed for larger grids (arrays are allocatable), (2) test with 10K, 100K, 1M cell domains, (3) add progress reporting in long update loops, (4) consider lazy-loading of infrequently-used variables.

**Time Loop: Up to 365 Days Tested:**
- Numbers: Croton test case runs 6 hours with 3600s timestep = 7 updates. Not tested for multi-month simulations.
- Limit: WRF-Hydro accumulates runoff in SFCRUNOFF, UDRUNOFF, etc. These are single-precision floats (32-bit). After ~30 days of continuous rain (1000mm/day), accumulation approaches 1e7 mm = single-precision rounding error threshold. Bit-truncation errors accumulate.
- Scaling path: (1) Test long runs (1 year) with validation data, (2) compare against standalone WRF-Hydro to detect drift, (3) consider double-precision accumulators in Phase 2, (4) add water balance checks to finalize().

**Coupling Frequency: Hourly Sync Points:**
- Numbers: Design assumes ~1Hz or lower frequency (PyMT typically syncs hourly). 3600s timestep default.
- Limit: Not designed for sub-second coupling (e.g., if SCHISM runs 10s timesteps). Would require interpolation/extrapolation logic or subcycling.
- Scaling path: (1) Implement time interpolation (linear interp between WRF-Hydro hourly outputs), (2) add subcycling option where BMI runs N internal steps per get_value call, (3) support Adaptive Time Stepping via update_until().

---

## Dependencies at Risk

**WRF-Hydro v5.4.0 Maintenance Risk:**
- Risk: NCAR released v5.4.0 in 2019. Latest versions (v6.x) have significant refactors. Coupling to v5.4.0 locks us into 5-year-old code. WRF-Hydro → v6.0 requires refactoring all 22 libraries and subroutine calls.
- Impact: Bug fixes in newer versions won't be available. Security patches if any will miss us. Future students/PIs can't easily adopt latest research.
- Migration plan: (1) Plan Phase 3 upgrade to v6.x (estimated 2-3 weeks effort), (2) contact NCAR for v6.x BMI integration, (3) use git submodule pinning to make upgrade explicit, (4) test v6.x build in parallel branch before cutover.

**Fortran 2003 → Fortran 2008+ Gap:**
- Risk: BMI spec targets Fortran 2003 compatibility (for NCAR Fortran 90/95 code). Modern Fortran 2008+ has better memory management, coarrays, etc. C bindings (iso_c_binding) in use are available but not optimal.
- Impact: Cannot easily adopt modern Fortran patterns. No object finalization semantics. Manual memory management error-prone.
- Migration plan: Consider Modern Fortran 2008+ rewrite in Phase 3 if WRF-Hydro moves beyond Fortran 2003. Benefit: automatic cleanup via final() procedures.

**OpenMPI 5.0.8 Version Lock:**
- Risk: Current build uses OpenMPI 5.0.8 (very recent). Conda-forge may deprecate or change MPI ABI. mpif90 compiler script may change.
- Impact: Build scripts break if conda OpenMPI recipe changes. Hard to reproduce on different machines.
- Migration plan: (1) Pin OpenMPI version in conda environment.yml, (2) test reproducibility on 2-3 machines, (3) consider building minimal MPI library locally for CI/CD.

**bmi-fortran 2.0.3 Development Status:**
- Risk: CSDMS BMI spec is maintained but bmi-fortran bindings are not actively developed. If bmi-fortran package is deprecated or moved, conda install fails.
- Impact: New users cannot set up environment. Breakage in CI/CD pipelines.
- Migration plan: (1) Fork bmi-fortran into project repo as fallback, (2) publish our modifications upstream, (3) pin version in environment.yml with hash, (4) monitor CSDMS GitHub for deprecation notices.

---

## Missing Critical Features

**Two-Way Coastal Coupling:**
- Problem: SCHISM can send sea_water_surface__elevation back to WRF-Hydro (via set_value), but WRF-Hydro does not use it. No coastal head boundary condition forcing in land_driver_exe or HYDRO_exe. Cannot simulate storm surge + compound flooding.
- Blocks: Cannot run realistic Hurricane Irene + SCHISM two-way coupling scenario.
- Fix scope: Requires design with hydro domain expertise. Where does coastal head feed in? Via subsurface head at coastal cells? Via channel routing head? Requires ~1 week of physics discussion + 1 week of coding + validation.

**Reservoir/Lake State Variables:**
- Problem: WRF-Hydro has reservoir routing (RFC scheme, level-pool), but not exposed in BMI. Only channel routing (QLINK1) visible. Cannot couple reservoir operations (dam releases) or observe lake levels.
- Blocks: Cannot model operation of dams, cannot validate against USGS gage data if located on reservoir.
- Fix scope: Add 5-10 new CSDMS names (reservoir_water__elevation, reservoir_water__volume_flow_rate, etc.), map to rt_domain fields, ~2-3 days.

**Distributed Forcing Input:**
- Problem: Currently can only set_value spatially uniform precipitation and temperature (broadcast to whole grid). Cannot drive with high-resolution spatially-varying forcing from SCHISM (different precip/temp each grid cell).
- Blocks: Cannot couple with regional climate models or ensemble forecast data.
- Fix scope: Requires set_value to accept multi-grid arrays, 1-2 days.

**Radiation and Humidity Forcing:**
- Problem: Only precipitation and temperature exposed as input. WRF-Hydro's Noah-MP land model needs radiation (shortwave, longwave) and humidity for energy balance. Currently using MRMS/HRRR defaults from config.
- Blocks: Cannot couple with atmospheric radiative transfer models or advanced weather systems.
- Fix scope: Add 4 new input variables, test with synthetic/satellite radiation data, ~1 week.

**Parallel/MPI-Aware Mode:**
- Problem: BMI wrapper is serial (single-rank). WRF-Hydro can run in MPI parallel. Only serial workflow tested.
- Blocks: Cannot couple on HPC clusters with MPI WRF-Hydro instances.
- Fix scope: Requires careful MPI_Comm handling, collective operations for global statistics, ~2-3 weeks.

---

## Test Coverage Gaps

**Re-initialization Scenario:**
- What's not tested: initialize() → finalize() → initialize() with same/different config.
- Files: `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90` (test suite has init + update + finalize, but no re-init)
- Risk: Memory corruption, segfault, silent stale-data bugs. Currently guarded by `wrfhydro_engine_initialized` flag, but untested.
- Priority: High — required for multi-run experiments or batch processing.

**Multi-Domain Configuration:**
- What's not tested: rt_domain(1) vs rt_domain(2,3,...) for nested domains.
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (line 484 hard-codes rt_domain(1))
- Risk: If user configures nested domains, wrapper silently ignores all but domain 1. No error raised.
- Priority: Medium — only affects nesting users (niche use case).

**Boundary Condition Errors:**
- What's not tested: set_value() with out-of-bounds values (negative precip, T<0K, moisture<0 or >1).
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 1805, 1815)
- Risk: Physically invalid forcing propagates silently into model. May cause numerical instability or divergence.
- Priority: Medium — bounds checking would improve robustness.

**Long-Duration Runs (>30 days):**
- What's not tested: Accumulator overflow, floating-point rounding in SFCRUNOFF/UDRUNOFF.
- Files: WRF-Hydro internal SFCRUNOFF, UDRUNOFF arrays
- Risk: Bit truncation after month-long simulation. Water balance drift.
- Priority: Low — most use cases are <7 days. Should validate before production multi-month runs.

**Coupling Handshake Timing:**
- What's not tested: Rapid set_value() → update() → get_value() → set_value() cycles (simulating 1s timestep coupling).
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (update function and set/get value)
- Risk: Racing conditions if coupling framework is multi-threaded (though Fortran is not thread-safe).
- Priority: Low — unlikely with Python GIL + MPI, but should document thread-safety limitations.

**Edge Case: Zero-Length Simulation:**
- What's not tested: initialize() with ntime=1 (single timestep), or ntime=0 (no-op model).
- Files: `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` (lines 476-481)
- Risk: Undefined behavior if ntime=0 is read from config. Division by zero in update_until?
- Priority: Low — edge case, but good defensive programming.

---

*Concerns audit: 2026-02-23*
