# 🏗️ BMI Implementation Master Plan — WRF-Hydro BMI Wrapper
### *Complete Roadmap: From Source Code Study to Validated `bmi_wrf_hydro.f90`*

---

## 🗺️ Table of Contents

1. [📌 Executive Summary](#1--executive-summary)
2. [📦 What We Already Have](#2--what-we-already-have)
3. [🎯 What We Need to Build](#3--what-we-need-to-build)
4. [🧠 Deep Dive: BMI Spec + Heat Example (The Blueprint)](#4--deep-dive-bmi-spec--heat-example-the-blueprint)
5. [🌊 Deep Dive: SCHISM's BMI Approach (Reference)](#5--deep-dive-schisms-bmi-approach-reference)
6. [⚙️ Deep Dive: WRF-Hydro Internals (What We're Wrapping)](#6--deep-dive-wrf-hydro-internals-what-were-wrapping)
7. [🗺️ Variable Mapping Dictionary](#7--variable-mapping-dictionary)
8. [📐 Grid Architecture](#8--grid-architecture)
9. [📋 Phase 1: Build & Validate BMI Example (Environment Test)](#9--phase-1-build--validate-bmi-example-environment-test)
10. [📋 Phase 2: Write `bmi_wrf_hydro.f90` (The Main Work)](#10--phase-2-write-bmi_wrf_hydrof90-the-main-work)
11. [📋 Phase 3: Compile & Link (Build the Library)](#11--phase-3-compile--link-build-the-library)
12. [📋 Phase 4: Test Driver & Validation](#12--phase-4-test-driver--validation)
13. [📋 Phase 5: Babelizer + PyMT (Future)](#13--phase-5-babelizer--pymt-future)
14. [📋 Phase 6: Couple WRF-Hydro + SCHISM (The Goal)](#14--phase-6-couple-wrf-hydro--schism-the-goal)
15. [🚧 Risk Analysis & Challenges](#15--risk-analysis--challenges)
16. [📎 Quick Reference — Key File Paths](#16--quick-reference--key-file-paths)

---

## 1. 📌 Executive Summary

### 🎯 The Mission

Write `bmi_wrf_hydro.f90` — a Fortran 2003 module implementing all **41 BMI
functions** that wraps WRF-Hydro's internals, enabling it to be controlled
from Python via PyMT for compound flooding simulations.

### 🏗️ Architecture (5-Layer Stack)

```
┌─────────────────────────────────────────────────────────┐
│  Layer 5: 🐍 Jupyter Notebook (~20 lines of Python)    │
│           scientist writes coupling logic here          │
├─────────────────────────────────────────────────────────┤
│  Layer 4: 🔄 PyMT Framework                            │
│           grid mapping, time sync, data exchange         │
├─────────────────────────────────────────────────────────┤
│  Layer 3: 📦 Babelized Plugins                         │
│           pymt_wrfhydro + pymt_schism                   │
├─────────────────────────────────────────────────────────┤
│  Layer 2: 🔌 BMI Wrappers ← WE ARE BUILDING THIS      │
│           bmi_wrf_hydro.f90 + bmischism (exists)        │
├─────────────────────────────────────────────────────────┤
│  Layer 1: 🌊 Original Models (Fortran)                 │
│           WRF-Hydro v5.4.0 + SCHISM                    │
└─────────────────────────────────────────────────────────┘
```

### 🐍 ML Engineer Analogy

Think of BMI like building a **standardized model API wrapper**:

```python
# What we're building (conceptually):
class WRFHydroBMI(AbstractBMI):
    """Wraps WRF-Hydro's Fortran internals with standard interface."""

    def __init__(self):
        self.model = WRFHydroModel()   # The actual 172K-line Fortran model

    def initialize(self, config_file):
        self.model.land_driver_ini()    # Read configs, allocate grids
        self.model.HYDRO_ini()          # Set up routing network

    def update(self):
        self.model.land_driver_exe()    # ONE timestep: LSM + routing

    def finalize(self):
        self.model.HYDRO_finish()       # Cleanup, deallocate

    def get_value(self, name):
        mapping = {
            "channel_water__volume_flow_rate": self.model.QLINK,
            "land_surface_water__depth": self.model.sfcheadrt,
        }
        return mapping[name].flatten()  # Always return 1D!
```

**That's it!** The BMI wrapper is an adapter pattern — it doesn't change
WRF-Hydro, it just provides a standard interface to control it.

---

## 2. 📦 What We Already Have

### Repository Contents

```
WRF-Hydro-BMI/
│
├── 📚 bmi-fortran/                    ← BMI abstract interface spec
│   └── bmi.f90                         (564 lines, all 41 function signatures)
│
├── 📖 bmi-example-fortran/            ← Working BMI example (our TEMPLATE)
│   ├── bmi_heat/bmi_heat.f90           (935 lines, implements all 41 functions)
│   ├── heat/heat.f90                   (158 lines, simple model being wrapped)
│   ├── bmi_heat/bmi_main.f90           (test driver program)
│   └── test/                           (54 test files, 1 per BMI function)
│
├── 🌊 wrf_hydro_nwm_public/           ← WRF-Hydro v5.4.0 source + build
│   ├── src/                            (244 source files, 172K+ lines)
│   └── build/Run/wrf_hydro            (compiled executable ✅)
│
├── 🏖️ schism_NWM_BMI/                 ← FULL SCHISM model with BMI hooks
│   └── src/                            (437 Fortran files, uses #ifdef USE_NWM_BMI)
│
├── 🏗️ bmi_wrf_hydro/                  ← OUR WORK DIRECTORY
│   └── Docs/                           (7 guide documents, 6,294 lines)
│
└── 🏃 WRF_Hydro_Run_Local/            ← Test run infrastructure
    ├── run/                            (6-hour Croton NY test, 39 output files ✅)
    ├── test_data/                      (Croton NY test case data)
    └── run_and_test.sh                 (automated run script ✅)
```

### Do We Need to Clone the SCHISM Repo?

**❌ NO.** We already have the full SCHISM model in `schism_NWM_BMI/`.

More importantly: **we don't need SCHISM at all to write the WRF-Hydro BMI
wrapper.** SCHISM is only a reference for how BMI was integrated into
another model. The actual resources we need are:

| Resource | Why We Need It | Priority |
|----------|----------------|----------|
| `bmi.f90` (spec) | Defines all 41 abstract function interfaces | 🔴 Critical |
| `bmi_heat.f90` (template) | Working example of all 41 implementations | 🔴 Critical |
| `heat.f90` (model example) | Shows model type + init/advance/cleanup pattern | 🔴 Critical |
| WRF-Hydro source code | What we're wrapping — need to know subroutines | 🔴 Critical |
| SCHISM BMI hooks | Reference for `#ifdef` pattern and coupling vars | 🟡 Nice to have |
| SCHISM full model | Not needed until Phase 6 (coupling) | 🟢 Future |

---

## 3. 🎯 What We Need to Build

### Primary Deliverable

```
bmi_wrf_hydro/
├── bmi_wrf_hydro.f90      ← THE BMI wrapper module (~1,000-1,500 lines)
├── bmi_main.f90            ← Test driver program (~100-200 lines)
├── CMakeLists.txt          ← Build configuration
├── tests/                  ← Test files (adapted from bmi-example-fortran)
└── Docs/Plan/              ← This document + future design docs
```

### The 41 Functions We Must Implement

```
┌──────────────────────────────────────────────────────────────┐
│                  41 BMI FUNCTIONS                             │
│                                                              │
│  🟢 CONTROL (4)                                              │
│  ├── initialize(config_file)  → calls land_driver_ini()     │
│  ├── update()                 → calls land_driver_exe()     │
│  ├── update_until(time)       → loops update() until time   │
│  └── finalize()               → calls HYDRO_finish()        │
│                                                              │
│  🔵 MODEL INFO (5)                                           │
│  ├── get_component_name()     → "WRF-Hydro v5.4.0"         │
│  ├── get_input_item_count()   → 2 (precip + coastal elev)  │
│  ├── get_output_item_count()  → 5-8 (streamflow, soil...)  │
│  ├── get_input_var_names()    → CSDMS standard names        │
│  └── get_output_var_names()   → CSDMS standard names        │
│                                                              │
│  🟡 VARIABLE INFO (6)                                        │
│  ├── get_var_type()           → "real", "double precision"  │
│  ├── get_var_units()          → "m3 s-1", "m", "K"         │
│  ├── get_var_grid()           → grid ID (0, 1, or 2)       │
│  ├── get_var_itemsize()       → sizeof(variable_element)    │
│  ├── get_var_nbytes()         → itemsize × grid_size        │
│  └── get_var_location()       → "node"                      │
│                                                              │
│  ⏰ TIME (5)                                                 │
│  ├── get_current_time()       → model%t (in seconds)        │
│  ├── get_start_time()         → 0.0                         │
│  ├── get_end_time()           → NTIME × dt (in seconds)     │
│  ├── get_time_step()          → NOAH_TIMESTEP (3600s)       │
│  └── get_time_units()         → "s"                         │
│                                                              │
│  📊 GET/SET VALUES (6 per type × 3 types = 18)              │
│  ├── get_value(name, dest)    → flatten & copy              │
│  ├── get_value_ptr(name)      → direct pointer (no copy)    │
│  ├── get_value_at_indices()   → subset of values            │
│  ├── set_value(name, src)     → unflatten & assign          │
│  └── set_value_at_indices()   → subset assignment           │
│                                                              │
│  🗺️ GRID (17) — per grid ID                                 │
│  ├── get_grid_type()          → "uniform_rectilinear" / "vector" │
│  ├── get_grid_rank()          → 2 (for 2D grids) / 1        │
│  ├── get_grid_size()          → nx × ny / nlinks             │
│  ├── get_grid_shape()         → [ny, nx]                     │
│  ├── get_grid_spacing()       → [dy, dx] in meters           │
│  ├── get_grid_origin()        → [lat0, lon0]                 │
│  ├── get_grid_x/y/z()        → coordinate arrays             │
│  ├── get_grid_node/edge/face_count() → topology              │
│  ├── get_grid_edge_nodes()    → connectivity                 │
│  ├── get_grid_face_nodes/edges() → connectivity              │
│  └── get_grid_nodes_per_face() → face topology               │
└──────────────────────────────────────────────────────────────┘
```

---

## 4. 🧠 Deep Dive: BMI Spec + Heat Example (The Blueprint)

### The Abstract Interface (`bmi.f90` — 564 lines)

The BMI specification defines an **abstract Fortran type** that our wrapper
must extend:

```fortran
module bmif_2_0
  implicit none

  integer, parameter :: BMI_SUCCESS = 0
  integer, parameter :: BMI_FAILURE = 1
  integer, parameter :: BMI_MAX_COMPONENT_NAME = 2048
  integer, parameter :: BMI_MAX_VAR_NAME = 2048

  type, abstract :: bmi
  contains
    ! 41 deferred procedures — ALL must be implemented
    procedure(bmif_initialize), deferred :: initialize
    procedure(bmif_update), deferred :: update
    ! ... 39 more ...
  end type bmi
end module bmif_2_0
```

**Key Rules:**
- Every function returns an `integer` status (`BMI_SUCCESS` or `BMI_FAILURE`)
- All arrays are **1D flattened** (no 2D/3D returns — avoids row/col-major issues)
- String outputs use `pointer` with `TARGET` attribute
- Time is always `double precision` in seconds

### The Heat Example Implementation Pattern (`bmi_heat.f90` — 935 lines)

This is our **exact blueprint**. Here's the pattern we'll follow:

```fortran
module bmiheatf
  use heatf                    ! ← Import the model module
  use bmif_2_0                 ! ← Import BMI abstract interface
  use iso_c_binding            ! ← For get_value_ptr (C interop)
  implicit none

  ! ─── Static module-level data (with TARGET for pointers) ───
  character(len=BMI_MAX_COMPONENT_NAME), target :: &
      component_name = "The 2D Heat Equation"

  integer, parameter :: input_item_count = 3
  integer, parameter :: output_item_count = 1

  character(len=BMI_MAX_VAR_NAME), target, &
      dimension(output_item_count) :: output_items

  ! ─── The BMI wrapper type ───
  type, extends(bmi) :: bmi_heat
    private
    type(heat_model) :: model    ! ← Wrapped model instance
  contains
    procedure :: initialize => heat_initialize
    procedure :: update => heat_update
    ! ... all 41 bindings ...
  end type bmi_heat

contains

  ! ─── Implementation of each function ───
  function heat_initialize(this, config_file) result(bmi_status)
    class(bmi_heat), intent(out) :: this
    character(len=*), intent(in) :: config_file
    integer :: bmi_status

    call initialize_from_file(this%model, config_file)
    bmi_status = BMI_SUCCESS
  end function

  ! ... 40 more functions ...
end module bmiheatf
```

### Critical Implementation Patterns from Heat Example

#### Pattern 1: Variable Name Mapping (select case)

```fortran
function heat_get_float(this, name, dest) result(bmi_status)
  select case(name)
  case("plate_surface__temperature")
    dest = reshape(this%model%temperature, [nx*ny])  ! Flatten 2D→1D
    bmi_status = BMI_SUCCESS
  case("plate_surface__thermal_diffusivity")
    dest = [this%model%alpha]                         ! Scalar→1D array
    bmi_status = BMI_SUCCESS
  case default
    dest(:) = -1.0
    bmi_status = BMI_FAILURE
  end select
end function
```

#### Pattern 2: Grid Information Mapping

```fortran
function heat_var_grid(this, name, grid) result(bmi_status)
  select case(name)
  case("plate_surface__temperature")
    grid = 0          ! Uniform rectilinear grid
  case("plate_surface__thermal_diffusivity")
    grid = 1          ! Scalar grid
  case default
    grid = -1
    bmi_status = BMI_FAILURE
  end select
end function
```

#### Pattern 3: Pointer Access (Zero-Copy, ISO_C_BINDING)

```fortran
function heat_get_ptr_float(this, name, dest_ptr) result(bmi_status)
  type(c_ptr) :: src
  select case(name)
  case("plate_surface__temperature")
    src = c_loc(this%model%temperature(1,1))        ! Get C pointer
    call c_f_pointer(src, dest_ptr, [nx*ny])         ! Flatten to 1D pointer
    bmi_status = BMI_SUCCESS
  end select
end function
```

#### Pattern 4: Unimplemented Functions (Graceful Failure)

```fortran
function heat_grid_edge_count(this, grid, count) result(bmi_status)
  count = -1
  bmi_status = BMI_FAILURE    ! Not applicable — return failure, don't crash
end function
```

---

## 5. 🌊 Deep Dive: SCHISM's BMI Approach (Reference)

### How SCHISM Did It (Different from Our Approach)

SCHISM does **NOT** have a separate BMI wrapper file. Instead, it uses
`#ifdef USE_NWM_BMI` preprocessor flags scattered throughout 3 main files:

```
schism_NWM_BMI/src/
├── Hydro/schism_init.F90    ← BMI-aware initialization
├── Hydro/schism_step.F90    ← BMI-aware time stepping
├── Hydro/misc_subs.F90      ← BMI data structure init
└── Driver/schism_driver.F90 ← Main program (6,931 lines)
```

### SCHISM's IRF Pattern

```fortran
! schism_driver.F90 — SCHISM's main program
program schism_driver
  call parallel_init
  call schism_main         ! Contains the time loop
  call parallel_finalize
end program

subroutine schism_main
  call schism_init0(iths, ntime)       ! ← INIT
  do it = iths+1, ntime                ! ← TIME LOOP (internal!)
    call schism_step0(it)              !    ONE TIMESTEP
  end do
  call schism_finalize0                ! ← FINALIZE
end subroutine
```

### What USE_NWM_BMI Changes in SCHISM

**In `schism_init.F90` (line 1141):**
```fortran
#ifdef USE_NWM_BMI
  if(if_source==0) call parallel_abort('USE_NWM_BMI cannot go with if_source=0')
#endif
```
> Enforces that external data sources are enabled (no file I/O bypass)

**In `schism_step.F90` (lines 1540-1616):**
```fortran
#ifdef USE_NWM_BMI
  ! Skip file reading — data comes from BMI wrapper externally
  if(nsources > 0) then
    ! Only do time bookkeeping, no file I/O
    ath3(:,1,1,1) = ath3(:,1,2,1)       ! Shift arrays
    th_time3(1,1) = th_time3(2,1)
    th_time3(2,1) = th_time3(2,1) + th_dt3(1)
  endif
#else
  ! Normal mode: read source/sink data from files
  call read_source_sink_files(...)
#endif
```
> Replaces file I/O with external data injection via BMI `set_value()`

**In `misc_subs.F90` (lines 599-614):**
```fortran
#ifdef USE_NWM_BMI
  ath3(:,1,1,1:2) = 0.d0          ! Initialize source arrays to zero
  ath3(:,1,1,3) = -9999.d0        ! Use ambient values for tracers
#endif
```
> Initializes data structures expecting external BMI data

### SCHISM's Coupling Variables

| Direction | Variable | CSDMS Name | Units |
|-----------|----------|------------|-------|
| **SCHISM → WRF-Hydro** | Elevation | `sea_water_surface__elevation` | m |
| **WRF-Hydro → SCHISM** | Discharge | `channel_water__volume_flow_rate` | m³/s |

### Our Approach vs SCHISM's

| Aspect | SCHISM's Approach | Our Approach |
|--------|-------------------|--------------|
| BMI file | No separate file (`#ifdef` in main code) | Separate `bmi_wrf_hydro.f90` module |
| Invasiveness | Modifies SCHISM source with CPP flags | NON-INVASIVE — wrapper calls model |
| Time loop | Still model-internal | Caller controls (true BMI) |
| Complexity | Minimal changes (~100 lines across 3 files) | Full 41-function implementation |
| Flexibility | Limited to source/sink injection | Full variable get/set capability |
| Reusability | Tightly coupled to NWM | Works with any BMI-compatible framework |

**We chose the separate wrapper approach because:**
- ✅ Doesn't modify WRF-Hydro source code
- ✅ Follows CSDMS best practices (`bmi_heat.f90` pattern)
- ✅ More flexible for future coupling scenarios
- ✅ Easier to test independently
- ✅ Works with Babelizer out of the box

---

## 6. ⚙️ Deep Dive: WRF-Hydro Internals (What We're Wrapping)

### Entry Point — `main_hrldas_driver.F` (42 lines)

```fortran
program HRLDAS_driver
  use module_noahmp_hrldas_driver   ! Land surface model driver
  implicit none

  integer :: ITIME, NTIME
  type(state_type) :: state

  call land_driver_ini(NTIME, state, ...)     ! ← INIT
  do ITIME = 1, NTIME                         ! ← TIME LOOP
    call land_driver_exe(ITIME, state)         !    ONE STEP
  end do
  call HYDRO_finish()                          ! ← FINALIZE
end program
```

> 🎯 **This is already the IRF pattern!** We just need to expose it
> through BMI functions instead of having the time loop embedded.

### Module Hierarchy

```
main_hrldas_driver.F
│
├── module_NoahMP_hrldas_driver
│   ├── land_driver_ini()      ─────→ INITIALIZE
│   │   ├── Read namelist.hrldas
│   │   ├── Allocate LSM arrays (SMOIS, TSLB, SH2O, etc.)
│   │   ├── Allocate coupling arrays (infxsrt, sfcheadrt, soldrain)
│   │   ├── Call hrldas_drv_HYDRO_ini()
│   │   └── Return NTIME (total timesteps)
│   │
│   └── land_driver_exe()      ─────→ ONE TIMESTEP
│       ├── Call noahmplsm()   (Noah-MP physics: soil, snow, canopy)
│       ├── Compute runoff, infiltration, evapotranspiration
│       ├── Call HYDRO_exe()   (6-step routing sequence)
│       │   ├── Step 1-2: disaggregateDomain_drv() (1km → 250m)
│       │   ├── Step 3:   SubsurfaceRouting_drv()  (soil water)
│       │   ├── Step 4:   OverlandRouting_drv()     (surface flow)
│       │   ├── Step 5:   driveGwBaseflow()         (groundwater)
│       │   ├── Step 6:   driveChannelRouting()     (rivers)
│       │   ├── Step 7:   aggregateDomain()         (250m → 1km)
│       │   └── Step 8:   HYDRO_out()              (write outputs)
│       └── Call ldas_output() (write LSM outputs)
│
└── module_HYDRO_drv
    ├── HYDRO_ini()            ─────→ HYDRO INIT
    │   ├── Read hydro.namelist
    │   ├── Get file dimensions
    │   ├── getChanDim() — allocate channel arrays
    │   ├── lsm_input() — read land surface params
    │   ├── LandRT_ini() — setup routing grids
    │   ├── Initialize groundwater
    │   └── HYDRO_rst_in() — read restart
    │
    ├── HYDRO_exe()            ─────→ HYDRO ONE STEP
    │   └── (6-step sequence above)
    │
    └── HYDRO_finish()         ─────→ HYDRO FINALIZE
        ├── finish_stream_nudging()
        ├── mpp_land_sync()
        └── MPI_Finalize()
```

### Where State Variables Live

The main data container is `rt_domain(did)` of type `RT_FIELD`, defined
in `module_rt_inc.F90`:

```fortran
type RT_FIELD
  ! Overland routing
  type(overland_struct) :: overland
  ! Subsurface
  type(subsurface_struct) :: subsurface
  ! Channel network
  real, allocatable :: QLINK(:,:)        ! ← STREAMFLOW (nlinks × 2)
  real, allocatable :: QLateral(:)       ! Lateral inflow to channels
  ! Lakes
  real, allocatable :: LAKEINFLOW(:)
  real, allocatable :: LAKEAREA(:)
  ! Groundwater
  real, allocatable :: z_gwsubbas(:)     ! GW bucket depth
  ! ... hundreds more fields ...
end type RT_FIELD

type(RT_FIELD), allocatable :: rt_domain(:)   ! Global access
```

### Key State Variables & Their Locations

| Variable | CSDMS Standard Name | Internal Location | Shape | Type |
|----------|---------------------|-------------------|-------|------|
| `QLINK(:,2)` | `channel_water__volume_flow_rate` | `rt_domain(did)%QLINK(:,2)` | (NLINKS) | REAL |
| `sfcheadrt` | `land_surface_water__depth` | allocated in `land_driver_ini` | (IX,JX) | REAL |
| `SMOIS` | `soil_water__volume_fraction` | `state%SMOIS` | (IX,JX,NSOIL) | REAL |
| `SNEQVOXY` | `snowpack__liquid-equivalent_depth` | `state%SNEQVOXY` | (IX,JX) | REAL |
| `ACCET` | `land_surface_water__evaporation_volume_flux` | module variable | (IX,JX) | REAL |
| `T2` | `land_surface_air__temperature` | computed in NoahMP | (IX,JX) | REAL |
| `RAINBL` | `atmosphere_water__precipitation_leq-volume_flux` | `state%RAINBL` | (IX,JX) | REAL |
| `UDRUNOFF` | `soil_water__domain_time_integral_of_baseflow_volume_flux` | state | (IX,JX) | REAL |

### CPP Flags Already Used in WRF-Hydro

| Flag | Purpose | Status |
|------|---------|--------|
| `-DWRF_HYDRO` | Enable hydro coupling | ✅ Always ON |
| `-DMPP_LAND` | MPI parallelization | ✅ Always ON |
| `-DHYDRO_D` | Debug diagnostics | 🟡 Debug builds |
| `-DWRF_HYDRO_NUDGING` | Streamflow data assimilation | ⬜ Optional |
| `-DWRF_HYDRO_RAPID` | RAPID routing coupling | ⬜ Optional |
| `-DSPATIAL_SOIL` | Distributed soil params | ⬜ Optional |
| **`-DUSE_NWM_BMI`** | **Our new BMI flag** | 🔴 TO BE ADDED |

---

## 7. 🗺️ Variable Mapping Dictionary

### Output Variables (WRF-Hydro → External)

| # | Internal Name | CSDMS Standard Name | Units | Grid | Priority |
|---|--------------|---------------------|-------|------|----------|
| 1 | `QLINK(:,2)` | `channel_water__volume_flow_rate` | m³/s | 2 (network) | 🔴 Must |
| 2 | `sfcheadrt` | `land_surface_water__depth` | m | 1 (250m) | 🔴 Must |
| 3 | `SMOIS` | `soil_water__volume_fraction` | - | 0 (1km) | 🟡 Should |
| 4 | `SNEQVOXY` | `snowpack__liquid-equivalent_depth` | m | 0 (1km) | 🟡 Should |
| 5 | `ACCET` | `land_surface_water__evaporation_volume_flux` | mm | 0 (1km) | 🟢 Nice |
| 6 | `UGDRNOFF` | `soil_water__domain_time_integral_of_baseflow_volume_flux` | mm | 0 (1km) | 🟢 Nice |

### Input Variables (External → WRF-Hydro)

| # | Internal Name | CSDMS Standard Name | Units | Grid | Priority |
|---|--------------|---------------------|-------|------|----------|
| 1 | `RAINBL` | `atmosphere_water__precipitation_leq-volume_flux` | mm/s | 0 (1km) | 🟡 Should |
| 2 | `T2` | `land_surface_air__temperature` | K | 0 (1km) | 🟢 Nice |

### Coupling Variables (WRF-Hydro ↔ SCHISM)

```
┌──────────────────┐                      ┌──────────────────┐
│    WRF-Hydro     │                      │     SCHISM       │
│                  │                      │                  │
│  QLINK(:,2)  ───────── streamflow ──────────→ ath3()      │
│  (m³/s)          │   (river discharge)  │  (source terms)  │
│                  │                      │                  │
│  sfcheadrt   ◄─────── elevation ────────────  elev()      │
│  (m)             │   (coastal water)    │  (m)             │
└──────────────────┘                      └──────────────────┘
```

> 🎯 The SHARED variable: `channel_water__volume_flow_rate`
> This is what WRF-Hydro outputs and SCHISM consumes.

---

## 8. 📐 Grid Architecture

### Three Grids in WRF-Hydro BMI

```
┌─────────────────────────────────────────────────────────┐
│  Grid 0: Noah-MP Land Surface (1 km)                    │
│  Type: uniform_rectilinear                               │
│  Rank: 2                                                 │
│  Shape: [JX, IX] (rows × cols)                          │
│  Spacing: [1000.0, 1000.0] meters                       │
│  Variables: SMOIS, SNEQV, ACCET, T2, RAINRATE           │
│                                                          │
│  ┌─────┬─────┬─────┬─────┐                             │
│  │ 1km │ 1km │ 1km │ 1km │                             │
│  ├─────┼─────┼─────┼─────┤                             │
│  │     │     │     │     │  (each cell has 4 soil layers)│
│  ├─────┼─────┼─────┼─────┤                             │
│  │     │     │     │     │                              │
│  └─────┴─────┴─────┴─────┘                             │
├─────────────────────────────────────────────────────────┤
│  Grid 1: Terrain Routing (250 m)                        │
│  Type: uniform_rectilinear                               │
│  Rank: 2                                                 │
│  Shape: [JX×4, IX×4] (4× finer)                        │
│  Spacing: [250.0, 250.0] meters                         │
│  Variables: sfcheadrt                                    │
│  AGGFACTRT = 4 (aggregation factor)                     │
│                                                          │
│  ┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐  │
│  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │
│  ├──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┼──┤  │
│  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │  │
│  └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘  │
├─────────────────────────────────────────────────────────┤
│  Grid 2: Channel Network (vector / unstructured)         │
│  Type: vector (1D network)                               │
│  Rank: 1                                                 │
│  Size: NLINKS (185 reaches in Croton, 2.7M in NWM)     │
│  Variables: QLINK (streamflow)                           │
│                                                          │
│       ╲    ╱                                            │
│        ╲  ╱                                             │
│    ─────╲╱────→                                         │
│          ╲                                               │
│           ╲                                              │
│            ─────→  (river network topology)              │
└─────────────────────────────────────────────────────────┘
```

### Grid Function Implementation Map

| Grid Function | Grid 0 (1km) | Grid 1 (250m) | Grid 2 (network) |
|---------------|-------------|---------------|------------------|
| `get_grid_type` | `"uniform_rectilinear"` | `"uniform_rectilinear"` | `"vector"` |
| `get_grid_rank` | 2 | 2 | 1 |
| `get_grid_size` | IX×JX | IX×4 × JX×4 | NLINKS |
| `get_grid_shape` | [JX, IX] | [JX×4, IX×4] | [NLINKS] |
| `get_grid_spacing` | [1000, 1000] | [250, 250] | BMI_FAILURE |
| `get_grid_origin` | [lat₀, lon₀] | [lat₀, lon₀] | BMI_FAILURE |
| `get_grid_x` | BMI_FAILURE* | BMI_FAILURE* | reach_x(:) |
| `get_grid_y` | BMI_FAILURE* | BMI_FAILURE* | reach_y(:) |
| `get_grid_node_count` | IX×JX | IX×4 × JX×4 | NLINKS |
| `get_grid_edge_count` | BMI_FAILURE | BMI_FAILURE | NLINKS-1 |
| `get_grid_face_count` | BMI_FAILURE | BMI_FAILURE | BMI_FAILURE |

*For uniform_rectilinear grids, x/y are computed from origin+spacing, not stored.

---

## 9. 📋 Phase 1: Build & Validate BMI Example (Environment Test)

### 🎯 Goal
Compile and run the `bmi-example-fortran` (heat model) to confirm our
conda environment can build BMI code and all 54 tests pass.

### 📝 Steps

```
Phase 1: Environment Validation
│
├── Step 1.1: Compile bmi-example-fortran
│   ├── cd bmi-example-fortran/
│   ├── cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX
│   ├── cmake --build _build
│   └── Expected: builds without errors
│
├── Step 1.2: Run all 54 tests
│   ├── ctest --test-dir _build
│   └── Expected: 54/54 tests pass
│
├── Step 1.3: Run the test driver
│   ├── cd _build/
│   ├── ./run_bmiheatf heat.cfg
│   └── Expected: output file with temperature values
│
└── Step 1.4: Study the output
    ├── Examine bmiheatf.out
    └── Confirm: init → update → get_value → finalize pattern works
```

### ⏱️ Estimated Time: 5-10 minutes

### ✅ Success Criteria
- All 54 tests pass
- Test driver produces valid output
- Confirms: gfortran + bmi-fortran + cmake work together

---

## 10. 📋 Phase 2: Write `bmi_wrf_hydro.f90` (The Main Work)

### 🎯 Goal
Implement all 41 BMI functions following the `bmi_heat.f90` template.

### 📝 Steps (Incremental — Build → Test → Expand)

```
Phase 2: Write BMI Wrapper
│
├── Step 2.1: Create module skeleton
│   ├── Create bmi_wrf_hydro/bmi_wrf_hydro.f90
│   ├── Define module bmiwrfhydrof
│   ├── Use bmif_2_0 (abstract interface)
│   ├── Define type bmi_wrf_hydro extending bmi
│   ├── Declare all 41 procedure bindings
│   └── Stub every function with BMI_FAILURE
│
├── Step 2.2: Implement Control Functions (4)
│   ├── initialize() → call land_driver_ini()
│   │   NOTE: Must refactor to separate init from time loop
│   ├── update() → call land_driver_exe(itime)
│   │   NOTE: itime must be tracked internally
│   ├── update_until(time) → loop update() until time reached
│   └── finalize() → call HYDRO_finish()
│
├── Step 2.3: Implement Model Info Functions (5)
│   ├── get_component_name() → "WRF-Hydro v5.4.0 (NoahMP)"
│   ├── get_input_item_count() → N_INPUT_VARS
│   ├── get_output_item_count() → N_OUTPUT_VARS
│   ├── get_input_var_names() → CSDMS standard names array
│   └── get_output_var_names() → CSDMS standard names array
│
├── Step 2.4: Implement Variable Info Functions (6)
│   ├── get_var_type() → select case mapping
│   ├── get_var_units() → select case mapping
│   ├── get_var_grid() → select case mapping to grid IDs
│   ├── get_var_itemsize() → sizeof()
│   ├── get_var_nbytes() → itemsize × grid_size
│   └── get_var_location() → "node" for all
│
├── Step 2.5: Implement Time Functions (5)
│   ├── get_current_time() → model's current time in seconds
│   ├── get_start_time() → 0.0d0
│   ├── get_end_time() → NTIME × dt
│   ├── get_time_step() → NOAH_TIMESTEP (3600.0d0)
│   └── get_time_units() → "s"
│
├── Step 2.6: Implement Get/Set Value (18 functions)
│   ├── get_value_int/float/double → flatten & copy
│   │   Focus: QLINK (streamflow), sfcheadrt, SMOIS
│   ├── get_value_ptr_int/float/double → c_loc + c_f_pointer
│   ├── get_value_at_indices_int/float/double → indexed access
│   ├── set_value_int/float/double → unflatten & assign
│   │   Focus: RAINBL (precipitation), T2 (temperature)
│   └── set_value_at_indices_int/float/double → indexed set
│
├── Step 2.7: Implement Grid Functions (17)
│   ├── Grid 0 (1km): type, rank, size, shape, spacing, origin
│   ├── Grid 1 (250m): type, rank, size, shape, spacing, origin
│   ├── Grid 2 (network): type, rank, size, x, y, node_count
│   └── Return BMI_FAILURE for inapplicable functions
│
└── Step 2.8: Compile check after each sub-step
    └── gfortran -c -I$CONDA_PREFIX/include bmi_wrf_hydro.f90
```

### 🏗️ Module Structure (What We'll Write)

```fortran
module bmiwrfhydrof
  use module_noahmp_hrldas_driver    ! WRF-Hydro LSM
  use module_HYDRO_drv               ! WRF-Hydro routing
  use bmif_2_0                       ! BMI abstract interface
  use iso_c_binding                  ! For get_value_ptr
  implicit none

  ! ─── CSDMS Standard Name Mapping ───
  integer, parameter :: N_OUTPUT_VARS = 6
  integer, parameter :: N_INPUT_VARS = 2

  character(len=BMI_MAX_VAR_NAME), target, &
      dimension(N_OUTPUT_VARS) :: output_items = (/ &
      'channel_water__volume_flow_rate                          ', &
      'land_surface_water__depth                                ', &
      'soil_water__volume_fraction                              ', &
      'snowpack__liquid-equivalent_depth                        ', &
      'land_surface_water__evaporation_volume_flux              ', &
      'soil_water__domain_time_integral_of_baseflow_volume_flux ' /)

  character(len=BMI_MAX_VAR_NAME), target, &
      dimension(N_INPUT_VARS) :: input_items = (/ &
      'atmosphere_water__precipitation_leq-volume_flux          ', &
      'land_surface_air__temperature                            ' /)

  ! ─── The BMI Wrapper Type ───
  type, extends(bmi) :: bmi_wrf_hydro
    private
    integer :: itime = 0              ! Current timestep counter
    integer :: ntime = 0              ! Total timesteps
    double precision :: dt = 3600.d0  ! Timestep (seconds)
    double precision :: t = 0.d0      ! Current time (seconds)
    type(state_type) :: state         ! WRF-Hydro state container
  contains
    procedure :: initialize         => wrfhydro_initialize
    procedure :: update             => wrfhydro_update
    procedure :: update_until       => wrfhydro_update_until
    procedure :: finalize           => wrfhydro_finalize
    ! ... all 41 bindings ...
  end type bmi_wrf_hydro

contains
  ! ... 41 function implementations ...
end module bmiwrfhydrof
```

### ⏱️ Estimated Effort: This is the biggest step — iterative development

### ✅ Success Criteria
- Compiles without errors
- All 41 functions have implementations (even if some return BMI_FAILURE)
- Key functions work: initialize, update, finalize, get_value for streamflow

---

## 11. 📋 Phase 3: Compile & Link (Build the Library)

### 🎯 Goal
Compile `bmi_wrf_hydro.f90` and link it with WRF-Hydro libraries to
produce a shared library `libwrfhydro_bmi.so`.

### 📝 Steps

```
Phase 3: Build System
│
├── Step 3.1: Create CMakeLists.txt for BMI wrapper
│   ├── Find bmi-fortran package
│   ├── Find WRF-Hydro libraries (from build/)
│   ├── Compile bmi_wrf_hydro.f90
│   ├── Link against WRF-Hydro libs + NetCDF + MPI
│   └── Produce: libwrfhydro_bmi.so
│
├── Step 3.2: Build
│   ├── cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX
│   ├── cmake --build _build
│   └── Expected: library compiles and links
│
└── Step 3.3: Install
    ├── cmake --install _build
    └── Expected: library + .mod files in $CONDA_PREFIX
```

### ⏱️ Estimated Time: 30-60 minutes (mostly debugging link issues)

---

## 12. 📋 Phase 4: Test Driver & Validation

### 🎯 Goal
Write a Fortran test driver that exercises BMI functions and validates
output against our standalone 39-file baseline run.

### 📝 Steps

```
Phase 4: Validation
│
├── Step 4.1: Write bmi_main.f90 (test driver)
│   ├── Initialize with Croton NY config
│   ├── Query model info (name, var names, grid info)
│   ├── Run 6 timesteps (= 6 hours to match baseline)
│   ├── get_value("channel_water__volume_flow_rate") each step
│   ├── Compare against standalone CHRTOUT files
│   └── Finalize
│
├── Step 4.2: Write automated test script
│   ├── Run standalone WRF-Hydro (39 files baseline)
│   ├── Run BMI driver (should produce same streamflow)
│   ├── Compare: ncdump CHRTOUT vs BMI get_value output
│   └── Tolerance: < 1% difference
│
├── Step 4.3: Adapt test suite from bmi-example-fortran
│   ├── Copy test/ directory
│   ├── Modify for WRF-Hydro variable names
│   └── Run: ctest — all tests should pass
│
└── Step 4.4: Edge case testing
    ├── Cold start (no restart file)
    ├── Single timestep only
    ├── update_until() with fractional step
    └── Invalid variable name → BMI_FAILURE
```

### ✅ Success Criteria
- BMI driver produces same streamflow as standalone run (within tolerance)
- All adapted tests pass
- No memory leaks (valgrind clean)
- No segmentation faults

---

## 13. 📋 Phase 5: Babelizer + PyMT (Future)

### 🎯 Goal
Wrap the Fortran BMI library into a Python package using Babelizer,
then register with PyMT.

```
Phase 5: Python Integration
│
├── Step 5.1: Install Babelizer
│   └── conda install -c conda-forge babelizer
│
├── Step 5.2: Write babel.toml
│   ├── [library] section → libwrfhydro_bmi.so
│   ├── [build] section → cmake config
│   └── [package] section → pymt_wrfhydro metadata
│
├── Step 5.3: Babelize
│   ├── babelize init babel.toml
│   ├── cd pymt_wrfhydro/
│   ├── pip install -e .
│   └── python -c "from pymt_wrfhydro import WrfHydro; print('OK')"
│
├── Step 5.4: PyMT registration
│   ├── conda install -c conda-forge pymt
│   ├── Register plugin
│   └── Verify: python -c "import pymt; print(pymt.MODELS)"
│
└── Step 5.5: Python validation
    ├── Write test_bmi.py
    ├── model = WrfHydro()
    ├── model.initialize("namelist.hrldas")
    ├── model.update()
    ├── q = model.get_value("channel_water__volume_flow_rate")
    └── assert q.shape == (185,)  # 185 reaches in Croton
```

---

## 14. 📋 Phase 6: Couple WRF-Hydro + SCHISM (The Goal)

### 🎯 Goal
Run a coupled compound flooding simulation from a Jupyter Notebook.

```
Phase 6: The Dream — ~20 Lines of Python
│
├── Step 6.1: Babelize SCHISM (same process as Phase 5)
│
├── Step 6.2: Write coupling script
│   │
│   │  import pymt
│   │
│   │  wrf = pymt.WrfHydro()
│   │  sch = pymt.Schism()
│   │
│   │  wrf.initialize("wrfhydro_config/")
│   │  sch.initialize("schism_config/")
│   │
│   │  for t in range(0, 86400, 3600):  # 24 hours
│   │      wrf.update()
│   │      discharge = wrf.get_value("channel_water__volume_flow_rate")
│   │      sch.set_value("channel_water__volume_flow_rate", discharge)
│   │      sch.update()
│   │      elevation = sch.get_value("sea_water_surface__elevation")
│   │      wrf.set_value("sea_water_surface__elevation", elevation)
│   │
│   │  wrf.finalize()
│   │  sch.finalize()
│   │
│
├── Step 6.3: Grid mapping configuration
│   ├── WRF-Hydro 1km grid → SCHISM unstructured mesh
│   ├── Use PyMT's built-in grid mappers
│   └── Configure: pymt.GridMapper(method="nearest_neighbor")
│
└── Step 6.4: Run compound flooding case study
    ├── Hurricane Irene 2011 (Croton NY)
    ├── Validate: river discharge + coastal surge interaction
    └── Compare against observations (USGS_obs.csv)
```

---

## 15. 🚧 Risk Analysis & Challenges

### 🔴 High Risk

| Challenge | Description | Mitigation |
|-----------|-------------|------------|
| **IRF Refactoring** | WRF-Hydro's time loop is embedded in `land_driver_exe()` — need to ensure single-step execution works correctly when called repeatedly from external code | Start with serial mode (np=1), test incrementally, compare against standalone run |
| **MPI Complications** | WRF-Hydro uses MPI internally (`MPP_LAND`). BMI wrapper must handle MPI init/finalize correctly without conflicting with PyMT's own MPI | Phase 1: serial only. Phase 2: add MPI support after serial works |
| **State Variable Access** | Key variables (`QLINK`, `sfcheadrt`) may be in deeply nested data structures or have access restrictions | Map every variable's exact module path and access pattern first |

### 🟡 Medium Risk

| Challenge | Description | Mitigation |
|-----------|-------------|------------|
| **Memory Management** | WRF-Hydro allocates large arrays internally. BMI's `get_value_ptr` gives external code direct pointers to internal memory | Use `get_value` (copy) first, add `get_value_ptr` later |
| **Build System Complexity** | Linking against 22 WRF-Hydro libraries + NetCDF + MPI | Start with simple gfortran command, move to CMake later |
| **Fortran Module Dependencies** | WRF-Hydro's modules have circular dependencies via `USE` statements | Map full dependency graph before writing CMakeLists.txt |

### 🟢 Low Risk

| Challenge | Description | Mitigation |
|-----------|-------------|------------|
| **Grid Functions** | 17 grid functions is a lot, but most are straightforward for regular grids | Use `BMI_FAILURE` for inapplicable functions |
| **Variable Type Handling** | Need separate functions for int/float/double | Most WRF-Hydro variables are REAL — double and int are minority |
| **Standard Name Mapping** | CSDMS names are long and must be exact | Define once in module-level arrays, test with string comparison |

---

## 16. 📎 Quick Reference — Key File Paths

### 📚 BMI Specification & Examples

| File | Lines | Purpose |
|------|-------|---------|
| `bmi-fortran/bmi.f90` | 564 | Abstract BMI interface (the spec) |
| `bmi-example-fortran/bmi_heat/bmi_heat.f90` | 935 | Complete BMI implementation (TEMPLATE) |
| `bmi-example-fortran/heat/heat.f90` | 158 | Simple model being wrapped |
| `bmi-example-fortran/bmi_heat/bmi_main.f90` | ~80 | Test driver program |
| `bmi-example-fortran/test/` | ~2,700 | 54 test files (1 per function) |

### 🌊 WRF-Hydro Source (What We're Wrapping)

| File | Lines | Purpose |
|------|-------|---------|
| `wrf_hydro_nwm_public/src/Land_models/NoahMP/IO_code/main_hrldas_driver.F` | 42 | Entry point (IRF pattern) |
| `wrf_hydro_nwm_public/src/Land_models/NoahMP/IO_code/module_NoahMP_hrldas_driver.F` | ~2,200 | LSM driver: `land_driver_ini()`, `land_driver_exe()` |
| `wrf_hydro_nwm_public/src/HYDRO_drv/module_HYDRO_drv.F90` | ~1,838 | Hydro driver: `HYDRO_ini()`, `HYDRO_exe()`, `HYDRO_finish()` |
| `wrf_hydro_nwm_public/src/Data_Rec/module_rt_inc.F90` | ~500 | `RT_FIELD` type (all routing state variables) |
| `wrf_hydro_nwm_public/src/Routing/module_RT.F90` | ~2,000 | Routing core: `LandRT_ini()` |
| `wrf_hydro_nwm_public/src/Routing/module_channel_routing.F90` | ~1,200 | Channel routing physics |
| `wrf_hydro_nwm_public/CMakeLists.txt` | 262 | Build configuration + CPP flags |

### 🏖️ SCHISM Reference (How Another Model Did BMI)

| File | Lines | Purpose |
|------|-------|---------|
| `schism_NWM_BMI/src/Hydro/schism_init.F90` | ~1,200 | `#ifdef USE_NWM_BMI` init hooks |
| `schism_NWM_BMI/src/Hydro/schism_step.F90` | ~1,600 | `#ifdef USE_NWM_BMI` step hooks |
| `schism_NWM_BMI/src/Driver/schism_driver.F90` | 6,931 | Main driver (IRF structure) |

### 🏗️ Our Work Directory

| File | Status | Purpose |
|------|--------|---------|
| `bmi_wrf_hydro/bmi_wrf_hydro.f90` | ❌ TO CREATE | The BMI wrapper |
| `bmi_wrf_hydro/bmi_main.f90` | ❌ TO CREATE | Test driver |
| `bmi_wrf_hydro/CMakeLists.txt` | ❌ TO CREATE | Build configuration |
| `bmi_wrf_hydro/Docs/` | ✅ EXISTS | 7 guides + this plan |

---

## 📊 Overall Timeline Visualization

```
                         NOW
                          │
Phase 1 ─────────────── ►│◄ Build & test bmi-example-fortran
(Environment)             │   (gfortran + BMI + cmake work?)
                          │
Phase 2 ─────────────── ►│◄◄◄◄◄◄◄ Write bmi_wrf_hydro.f90
(THE MAIN WORK)           │        (41 functions, iterative)
                          │        ├── 2.1: Skeleton + stubs
                          │        ├── 2.2: Control (init/update/finalize)
                          │        ├── 2.3: Model info
                          │        ├── 2.4: Variable info
                          │        ├── 2.5: Time functions
                          │        ├── 2.6: Get/Set value
                          │        └── 2.7: Grid functions
                          │
Phase 3 ─────────────── ►│◄ Compile + link as library
(Build)                   │   (libwrfhydro_bmi.so)
                          │
Phase 4 ─────────────── ►│◄◄ Test driver + validation
(Validate)                │   (compare vs standalone 39-file run)
                          │
Phase 5 ─────────────── ►│◄◄ Babelize + PyMT plugin
(Python)                  │   (pymt_wrfhydro package)
                          │
Phase 6 ─────────────── ►│◄◄◄ Couple WRF-Hydro + SCHISM
(THE GOAL)                │   (~20 lines of Python!)
                          ▼
                     🏆 COMPOUND
                        FLOODING
                       SIMULATION
```

---

*Document created for WRF-Hydro BMI Wrapper Project*
*Location: `bmi_wrf_hydro/Docs/Plan/BMI_Implementation_Master_Plan.md`*
*Based on analysis of: bmi.f90, bmi_heat.f90, SCHISM #ifdef pattern, WRF-Hydro IRF decomposition*
