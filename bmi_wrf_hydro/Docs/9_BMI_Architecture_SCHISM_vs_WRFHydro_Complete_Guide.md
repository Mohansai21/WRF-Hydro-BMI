# 📘 Doc 9: BMI Architecture — SCHISM vs WRF-Hydro Complete Guide

> **📅 Created:** February 20, 2026
> **🎯 Purpose:** Understand SCHISM's BMI approach, why it won't work for WRF-Hydro, the BMI template & Heat Model patterns, SCHISM coupling compatibility, and complete WRF-Hydro variable inventory with CSDMS Standard Names
> **👤 Audience:** ML engineer learning hydrology model coupling (you!)
> **📁 Location:** `bmi_wrf_hydro/Docs/`

---

## 📑 Table of Contents

| # | Section | What You'll Learn |
|---|---------|-------------------|
| 1 | [The Big Picture](#1--the-big-picture) | Why we're comparing SCHISM and WRF-Hydro BMI approaches |
| 2 | [SCHISM's BMI Approach](#2--schisms-bmi-approach-inline-ifdef) | How SCHISM enables BMI with `#ifdef` |
| 3 | [Why SCHISM's Approach Won't Work for WRF-Hydro](#3--why-schisms-approach-wont-work-for-wrf-hydro) | 5 architectural reasons |
| 4 | [Our Solution: Separate Wrapper](#4--our-solution-separate-non-invasive-wrapper) | The bmi_wrf_hydro.f90 architecture |
| 5 | [BMI Fortran Template Deep Dive](#5--bmi-fortran-template-deep-dive-bmif90) | The abstract interface (bmi.f90) |
| 6 | [BMI Heat Model Example](#6--bmi-heat-model-example-deep-dive) | Complete walkthrough of the reference implementation |
| 7 | [Will SCHISM's BMI Work for Coupling?](#7--will-schisms-bmi-work-for-coupling-with-our-wrapper) | Compatibility analysis |
| 8 | [WRF-Hydro Complete Variable Inventory](#8--wrf-hydro-complete-variable-inventory) | ALL input/output variables with CSDMS names |
| 9 | [CSDMS Standard Names: What's Next?](#9--csdms-standard-names-whats-next) | How to register new names |
| 10 | [Summary & Action Items](#10--summary--action-items) | Key takeaways and next steps |

---

## 1. 🌊 The Big Picture

### 🤔 Why This Comparison Matters

We're building a **BMI wrapper for WRF-Hydro** so it can exchange data with **SCHISM** through PyMT. But before writing our wrapper, we need to answer:

> "SCHISM already has BMI support via `#ifdef USE_NWM_BMI`. Can we just do the same thing for WRF-Hydro?"

**Short answer: No.** This document explains why in detail, and then shows you exactly how we *will* build it instead.

### 🗺️ Where We Are in the Project

```
Phase 1a: Study & Preparation          ✅ DONE
  ├── Study BMI spec                    ✅
  ├── Build/test BMI Heat example       ✅ (49/49 tests pass)
  ├── Compile WRF-Hydro                 ✅ (Croton NY test case)
  ├── Study SCHISM BMI approach         ✅ (this document!)
  └── Create Master Plan                ✅

Phase 1b: Write BMI Wrapper             ⬅️ YOU ARE HERE
  ├── Refactor time loop (IRF)          🔲
  ├── Write bmi_wrf_hydro.f90           🔲
  ├── Compile shared library            🔲
  └── Test with Fortran driver          🔲
```

### 🧠 ML Analogy: What's Happening

Think of it this way:

| ML World | Hydrology World |
|----------|----------------|
| You have a PyTorch model | You have WRF-Hydro (Fortran) |
| You want to export it to ONNX | You want to wrap it with BMI |
| ONNX = standard format anyone can run | BMI = standard API anyone can call |
| `torch.onnx.export(model)` | `bmi_wrf_hydro.f90` wrapper |
| Model Hub (load any model) | PyMT (run any BMI model) |
| Ensemble models | Coupled models (WRF-Hydro + SCHISM) |

---

## 2. 🔧 SCHISM's BMI Approach: Inline `#ifdef`

### 📖 What is SCHISM?

**SCHISM** = **S**emi-implicit **C**ross-scale **H**ydroscience **I**ntegrated **S**ystem **M**odel

- An **ocean/coastal circulation model** developed at VIMS (Virginia Institute of Marine Science)
- Simulates water levels, currents, salinity, temperature in coastal waters
- Uses an **unstructured triangular mesh** (like a finite-element mesh in ML simulations)
- Written in **Fortran 90/2003** (~437 source files in our copy)

### 🔑 The Key Finding

> **SCHISM does NOT have a separate BMI wrapper file.**
> Instead, it adds small code blocks inside its *own* source files using `#ifdef USE_NWM_BMI`.

This is fundamentally different from what we're doing. Let's understand exactly how it works.

### 📝 What is `#ifdef`?

`#ifdef` is a **C/Fortran preprocessor directive**. It works at **compile time**, not at runtime:

```fortran
! This code is processed BEFORE compilation:

#ifdef USE_NWM_BMI
  ! This code is INCLUDED in the compiled binary
  ! only if -DUSE_NWM_BMI was passed to the compiler
  print *, "BMI mode is ON"
#else
  ! This code is included when the flag is NOT set
  print *, "BMI mode is OFF"
#endif
```

🧠 **ML Analogy:** It's like `#ifdef DEBUG` in C++ code, or Python's:
```python
if os.environ.get("USE_BMI"):
    model.enable_coupling()
else:
    model.standalone_mode()
```

Except `#ifdef` happens at **compile time** — the unused code doesn't even exist in the binary!

### 📁 Where SCHISM Uses `#ifdef USE_NWM_BMI`

Only **3 files** and **5 code blocks** total:

```
schism_NWM_BMI/src/
├── Hydro/
│   ├── schism_init.F90     ─── 1 block  (line 1141)
│   ├── schism_step.F90     ─── 2 blocks (lines 1540, 1616)
│   └── misc_subs.F90       ─── 2 blocks (lines 599, 709)
└── Driver/
    └── schism_driver.F90   ─── 0 blocks (already has IRF!)
```

### 📄 Block-by-Block Analysis

#### Block 1: `schism_init.F90` (Line 1141) — Validation Check

```fortran
#ifdef USE_NWM_BMI
  if(if_source==0) call parallel_abort('INIT: USE_NWM_BMI cannot go with if_source=0')
#endif
```

**What it does:** Ensures that source/sink support is enabled. When BMI coupling is active, SCHISM must be able to receive external discharge data — so `if_source` must be non-zero.

**Why it's needed:** Without source/sink support, SCHISM can't accept river discharge from WRF-Hydro.

#### Block 2-3: `misc_subs.F90` (Lines 599-709) — Source/Sink Initialization

```fortran
#ifdef USE_NWM_BMI
  ! Initialize time stepping for sources/sinks
  ninv = time / th_dt3(1)
  th_time3(1,1) = ninv * th_dt3(1)
  th_time3(2,1) = th_time3(1,1) + th_dt3(1)

  ! Initialize source arrays to zero (BMI will populate these)
  ath3(:,1,1,1:2) = 0.d0
  ath3(:,1,1,3) = -9999.d0  ! -9999 = "use ambient concentration"
#else
  ! Non-BMI mode: reads from ASCII files (vsource.th, msource.th)
  ! ... 100+ lines of file I/O code ...
#endif
```

**What it does:** In BMI mode, SCHISM **skips reading from files** and instead initializes empty arrays that an external caller (via BMI) will populate with discharge data.

**Key insight:** The `-9999` value means "inject ambient concentration" for temperature and salinity — SCHISM doesn't need WRF-Hydro to provide water temperature at river mouths.

#### Block 4-5: `schism_step.F90` (Lines 1540-1616) — Time Stepping

```fortran
#ifdef USE_NWM_BMI
  ! Update source/sink time series
  if(nsources > 0) then
    if(time > th_time3(2,1)) then
      ath3(:,1,1,1) = ath3(:,1,2,1)      ! Shift: future → current
      th_time3(1,1) = th_time3(2,1)       ! Update time window
      th_time3(2,1) = th_time3(2,1) + th_dt3(1)
    endif
  endif
#else
  ! Non-BMI mode: reads next time slice from files
  ! ... file I/O code ...
#endif
```

**What it does:** During each timestep, SCHISM checks if it needs to update its source/sink data. In BMI mode, it shifts time arrays forward (expecting the external caller to have already provided new data). In non-BMI mode, it reads from files.

### 🏗️ How SCHISM's Architecture Makes This Work

SCHISM's main driver is only **180 lines** and already has the IRF pattern:

```fortran
! schism_driver.F90 — The entire main program!
program schism_driver
  call schism_init0(iths, ntime)      ! ← INITIALIZE
  do it = iths+1, ntime
    call schism_step0(it)              ! ← RUN (one timestep)
  end do
  call schism_finalize0                ! ← FINALIZE
end program
```

```
┌─────────────────────────────────────────────────┐
│           SCHISM Call Stack (3 levels)           │
├─────────────────────────────────────────────────┤
│                                                 │
│  Level 1: schism_driver.F90                     │
│      │                                          │
│      ├── schism_init0()   ← #ifdef here (1)     │
│      │                                          │
│      ├── DO timestep                            │
│      │    └── schism_step0()  ← #ifdef here (2) │
│      │                                          │
│      └── schism_finalize0()                     │
│                                                 │
│  Total depth: 3 levels                          │
│  Total files with #ifdef: 3                     │
│  Total #ifdef blocks: 5                         │
│  Grid types: 1 (unstructured triangular)        │
│                                                 │
└─────────────────────────────────────────────────┘
```

### ✅ Why Inline `#ifdef` Works for SCHISM

| Reason | Details |
|--------|---------|
| **1. Already has IRF** | `schism_init0` / `schism_step0` / `schism_finalize0` already exist |
| **2. Single grid** | One unstructured triangular mesh — no branching in grid functions |
| **3. Shallow nesting** | Only 3 levels deep — easy to insert `#ifdef` |
| **4. Simple coupling** | Only needs to receive discharge + send water levels |
| **5. Minimal changes** | Only 5 small code blocks across 3 files |

### ⚠️ Important: This is NOT Full BMI!

SCHISM's `#ifdef USE_NWM_BMI` is **NOT** a complete 41-function BMI implementation. It's:

- ✅ **Data exchange hooks** (receive discharge, potentially send elevation)
- ❌ **Not** `get_value()` / `set_value()` functions
- ❌ **Not** grid metadata functions
- ❌ **Not** time query functions
- ❌ **Not** variable info functions
- ❌ **Not** a standard BMI API that PyMT can call

It's more like "BMI-compatible plumbing" — the internal wiring that allows external data to flow in, but not the full standard interface.

---

## 3. 🚫 Why SCHISM's Approach Won't Work for WRF-Hydro

### The 5 Architectural Differences

#### ❌ Reason 1: Deep Nesting (5 Levels vs 3)

WRF-Hydro's physics are buried **5 levels deep**:

```
WRF-Hydro Call Stack:

Level 1: main_hrldas_driver.F (42 lines)
    │
    ├── land_driver_ini()                              ← INIT
    │
    ├── DO ITIME = 1, NTIME                            ← TIME LOOP
    │    │
    │    └── Level 2: land_driver_exe() (2,869 lines!)
    │         │
    │         ├── Read forcing data                    Phase 1
    │         ├── Run NoahMP LSM                       Phase 2
    │         ├── WTABLE (groundwater)                 Phase 3
    │         │
    │         └── Level 3: hrldas_drv_HYDRO()
    │              │
    │              └── Level 4: hrldas_cpl_HYDRO()
    │                   │
    │                   └── Level 5: HYDRO_exe()
    │                        ├── disaggregateDomain
    │                        ├── SubsurfaceRouting
    │                        ├── OverlandRouting
    │                        ├── GW Baseflow
    │                        ├── ChannelRouting
    │                        └── aggregateDomain
    │
    └── land_driver_finish()                           ← FINALIZE
```

To add `#ifdef` at Level 5, you'd need to modify **every level above it** to pass control flags downward. That means touching 4+ driver files and breaking WRF-Hydro's own code structure.

🧠 **ML Analogy:** Imagine your model has `model.forward()` → `model.encoder()` → `model.attention()` → `model.head()` → `model.output()`. You want to intercept `output()` but it's 5 levels deep. You'd have to modify every layer above it just to pass a flag down.

#### ❌ Reason 2: 5 Sequential Physics Phases

Each WRF-Hydro timestep runs **5 sequential phases with data dependencies**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                ONE WRF-Hydro Timestep                               │
├─────────┬──────────────┬───────────┬──────────────┬────────────────┤
│ Phase 1 │   Phase 2    │  Phase 3  │   Phase 4    │    Phase 5     │
│ Read    │  NoahMP LSM  │ Ground-   │  HYDRO_exe() │  Write         │
│ Forcing │  (soil,snow, │ water     │  (subsurface,│  Output        │
│ Data    │  vegetation) │ WTABLE    │  overland,   │  Files         │
│         │              │           │  channel)    │                │
├─────────┤              │           │              │                │
│ Rain,   │  Produces:   │ Modifies: │ Produces:    │ Writes:        │
│ Temp,   │  soil moist, │ water     │ streamflow,  │ LDASOUT,       │
│ Wind,   │  snow, ET,   │ table     │ surface      │ CHRTOUT,       │
│ Solar   │  runoff      │ depth     │ water depth  │ RTOUT          │
└─────┬───┴──────┬───────┴─────┬─────┴──────┬───────┴────────────────┘
      │          │             │            │
      └──────────┴─────────────┴────────────┘
          Data flows sequentially: Phase 2 NEEDS Phase 1 output,
          Phase 4 NEEDS Phase 2 output, etc.
```

BMI's `update()` must do **exactly one timestep** — meaning it must orchestrate all 5 phases. An `#ifdef` can't do this; you need a wrapper function that calls them in order.

🧠 **ML Analogy:** A training step = data_loading → forward → loss → backward → optimizer. You can't `#ifdef` just the backward pass — they're sequential!

#### ❌ Reason 3: 3 Simultaneous Grids

WRF-Hydro operates on **3 different grids** at the same time:

| Grid | Type | Resolution | Variables | BMI Grid Type |
|------|------|-----------|-----------|---------------|
| **Grid 0** | Regular 2D | 1 km | Soil moisture, snow, ET, temp | `uniform_rectilinear` |
| **Grid 1** | Regular 2D | 250 m | Surface water, subsurface flow | `uniform_rectilinear` |
| **Grid 2** | Network/vector | Varies | Streamflow, channel properties | `unstructured` |

Every BMI grid function (`get_grid_type`, `get_grid_size`, `get_grid_shape`, etc.) must **branch on the grid ID** and return different answers. An `#ifdef` block can't handle this — you need a `select case` lookup table:

```fortran
! This REQUIRES a separate wrapper — can't do with #ifdef:
select case(grid_id)
case(0)  ! LSM grid
  grid_type = "uniform_rectilinear"
  grid_shape = [jx, ix]         ! 1km
  grid_spacing = [1000.0, 1000.0]
case(1)  ! Routing grid
  grid_type = "uniform_rectilinear"
  grid_shape = [jxrt, ixrt]     ! 250m
  grid_spacing = [250.0, 250.0]
case(2)  ! Channel network
  grid_type = "unstructured"
  grid_size = NLINKS             ! ~2.7M reaches in NWM
end select
```

SCHISM has only **1 grid** — every grid function returns one answer, no branching needed.

#### ❌ Reason 4: 235 Source Files

WRF-Hydro has **235 source files** with complex interdependencies. SCHISM has a simpler structure. Adding `#ifdef` blocks to WRF-Hydro would mean:

- Modifying 10+ existing files
- Risk of breaking NCAR's official code
- Merging nightmare when WRF-Hydro gets updated
- Difficult to test BMI code independently

#### ❌ Reason 5: No Existing IRF Separation

SCHISM already had `schism_init0()` / `schism_step0()` / `schism_finalize0()`. WRF-Hydro does **NOT** — its time loop is integrated into `land_driver_exe()` which is a 2,869-line function that mixes init, run, and output.

We need to **decompose** the time loop into separate init/step/finalize calls — this is the IRF (Initialize-Run-Finalize) refactoring.

### 📊 Side-by-Side Comparison Table

| Aspect | SCHISM (✅ inline works) | WRF-Hydro (❌ inline won't work) |
|--------|------------------------|--------------------------------|
| Call stack depth | 3 levels | 5 levels |
| Main driver size | 180 lines | 2,869 lines |
| Number of grids | 1 (triangular mesh) | 3 (1km + 250m + channel) |
| Source files | ~50 | 235 |
| IRF pattern exists? | ✅ Yes (init0/step0/finalize0) | ❌ No (integrated time loop) |
| Physics phases/step | 1 (ocean step) | 5 (forcing→LSM→GW→routing→output) |
| `#ifdef` blocks needed | 5 small blocks | 50+ blocks across 10+ files |
| Code invasiveness | Minimal | Massive (breaks NCAR code) |
| Testability | Can test inline | Can't test `#ifdef` independently |
| Maintainability | Easy to update SCHISM | Breaking changes on every update |

---

## 4. ✅ Our Solution: Separate Non-Invasive Wrapper

### 🏗️ Architecture: bmi_wrf_hydro.f90

We'll write a **single Fortran file** (~800 lines) that sits **outside** WRF-Hydro's source code and calls into it:

```
┌────────────────────────────────────────────────────────────────────┐
│                    EXTERNAL CALLER                                 │
│     (PyMT / Python / Jupyter Notebook / Fortran driver)           │
│                                                                    │
│  call bmi%initialize("config.yaml")                                │
│  do while (time < end_time)                                        │
│    call bmi%update()                                               │
│    call bmi%get_value("channel_water__volume_flow_rate", Q)        │
│  end do                                                            │
│  call bmi%finalize()                                               │
└────────────────────────┬───────────────────────────────────────────┘
                         │
                    BMI API calls
                         │
┌────────────────────────▼───────────────────────────────────────────┐
│                  bmi_wrf_hydro.f90  (OUR WRAPPER)                  │
│                                                                    │
│  module bmiwrfhydrof                                               │
│    use bmif_2_0          ! BMI abstract interface                  │
│    use module_HYDRO_drv  ! WRF-Hydro routing                      │
│    use module_NoahMP_hrldas_driver  ! Land surface                 │
│                                                                    │
│    type, extends(bmi) :: bmi_wrf_hydro                             │
│      private                                                       │
│      ! Embed WRF-Hydro state here                                  │
│    contains                                                        │
│      procedure :: initialize => wrfhydro_init                      │
│      procedure :: update => wrfhydro_update                        │
│      procedure :: finalize => wrfhydro_finalize                    │
│      procedure :: get_value_double => wrfhydro_get_double          │
│      procedure :: set_value_double => wrfhydro_set_double          │
│      ! ... all 41 BMI functions                                    │
│    end type                                                        │
│                                                                    │
│    ! Variable name mapping (CSDMS Standard Names):                 │
│    ! "channel_water__volume_flow_rate" → QLINK(:,1)                │
│    ! "soil_water__volume_fraction"     → SOIL_M(:,:,:)             │
│    ! "land_surface_water__depth"       → sfcheadrt(:,:)            │
│  end module                                                        │
└────────────────────────┬───────────────────────────────────────────┘
                         │
              Calls WRF-Hydro subroutines
              (NO modifications to source!)
                         │
┌────────────────────────▼───────────────────────────────────────────┐
│               WRF-Hydro Source Code (UNTOUCHED)                    │
│                                                                    │
│  module_HYDRO_drv.F90:     HYDRO_ini(), HYDRO_exe(), HYDRO_finish()│
│  module_NoahMP_hrldas_driver.F: land_driver_ini(), land_driver_exe()│
│  module_rt_inc.F90:        RT_FIELD type (all state variables)     │
│  module_channel_routing.F90: channel routing physics               │
│  ... 235 source files, all unmodified ...                          │
└────────────────────────────────────────────────────────────────────┘
```

### 🎯 IRF Mapping

| BMI Function | What Our Wrapper Does | WRF-Hydro Subroutine |
|-------------|----------------------|---------------------|
| `initialize(config)` | Read config, init model | `land_driver_ini()` + `HYDRO_ini()` |
| `update()` | Run exactly ONE timestep | `land_driver_exe()` (all 5 phases) |
| `finalize()` | Clean up, free memory | `HYDRO_finish()` + close files |
| `get_value(name, dest)` | Copy state to caller | `select case` → `reshape` to 1D |
| `set_value(name, src)` | Inject data into model | `select case` → assign to state |

### 💪 Benefits Over Inline `#ifdef`

| Benefit | Why It Matters |
|---------|---------------|
| **Non-invasive** | Zero changes to WRF-Hydro. Model stays as-is from NCAR. |
| **Single file** | ~800 lines in 1 file vs `#ifdef` spaghetti in 10+ files |
| **Testable** | Can test BMI wrapper independently with a simple Fortran driver |
| **Maintainable** | Update WRF-Hydro version? Just rebuild — wrapper calls same subroutines |
| **Full BMI** | All 41 functions, 3 grids, CSDMS Standard Names, ready for PyMT |
| **Standard pattern** | Same design as bmi_heat.f90 (our proven template, 49/49 tests pass) |

---

## 5. 📐 BMI Fortran Template Deep Dive (bmi.f90)

### 📖 What is bmi.f90?

**File:** `bmi-fortran/bmi.f90` (564 lines)
**Module name:** `bmif_2_0` (BMI version 2.0)
**Published by:** CSDMS (Hutton et al. 2020)
**Install:** `conda install bmi-fortran` (provides `libbmif.so` and the `.mod` file)

This file defines the **abstract interface** — it declares what every BMI model **must** implement, but provides **no implementation**. It's a contract.

🧠 **ML Analogy:** Like Python's `abc.ABC`:
```python
from abc import ABC, abstractmethod

class BMI(ABC):
    @abstractmethod
    def initialize(self, config_file: str) -> int: ...

    @abstractmethod
    def update(self) -> int: ...
    # ... 39 more abstract methods
```

### 🔢 Key Constants

```fortran
module bmif_2_0

  ! Status codes — every BMI function returns one of these:
  integer, parameter :: BMI_SUCCESS = 0    ! Function worked
  integer, parameter :: BMI_FAILURE = 1    ! Function failed or not applicable

  ! Maximum string lengths:
  integer, parameter :: BMI_MAX_COMPONENT_NAME = 2048
  integer, parameter :: BMI_MAX_VAR_NAME       = 2048
  integer, parameter :: BMI_MAX_TYPE_NAME      = 2048
  integer, parameter :: BMI_MAX_UNITS_NAME     = 2048
```

### 📋 The 53 Deferred Procedures

The abstract `bmi` type declares **53 procedures** (41 logical functions × some with type overloads):

```fortran
type, abstract :: bmi
contains
  ! ── Control (4) ──
  procedure(bmif_initialize), deferred :: initialize
  procedure(bmif_update), deferred :: update
  procedure(bmif_update_until), deferred :: update_until
  procedure(bmif_finalize), deferred :: finalize

  ! ── Model Info (5) ──
  procedure(bmif_get_component_name), deferred :: get_component_name
  procedure(bmif_get_input_item_count), deferred :: get_input_item_count
  procedure(bmif_get_output_item_count), deferred :: get_output_item_count
  procedure(bmif_get_input_var_names), deferred :: get_input_var_names
  procedure(bmif_get_output_var_names), deferred :: get_output_var_names

  ! ── Variable Info (6) ──
  procedure(bmif_get_var_grid), deferred :: get_var_grid
  procedure(bmif_get_var_type), deferred :: get_var_type
  procedure(bmif_get_var_units), deferred :: get_var_units
  procedure(bmif_get_var_itemsize), deferred :: get_var_itemsize
  procedure(bmif_get_var_nbytes), deferred :: get_var_nbytes
  procedure(bmif_get_var_location), deferred :: get_var_location

  ! ── Time (5) ──
  procedure(bmif_get_current_time), deferred :: get_current_time
  procedure(bmif_get_start_time), deferred :: get_start_time
  procedure(bmif_get_end_time), deferred :: get_end_time
  procedure(bmif_get_time_step), deferred :: get_time_step
  procedure(bmif_get_time_units), deferred :: get_time_units

  ! ── Get/Set Value (with type overloads) ──
  ! Each of these has 3 type-specific versions (int, float, double):
  procedure(bmif_get_value_int), deferred :: get_value_int
  procedure(bmif_get_value_float), deferred :: get_value_float
  procedure(bmif_get_value_double), deferred :: get_value_double
  ! Plus: set_value, get_value_ptr, get_value_at_indices, set_value_at_indices
  ! (each with int/float/double = 5 functions × 3 types = 15 procedures)

  ! Generic interfaces (callers use these — Fortran dispatches by type):
  generic :: get_value => get_value_int, get_value_float, get_value_double
  generic :: set_value => set_value_int, set_value_float, set_value_double
  ! ... same for get_value_ptr, *_at_indices

  ! ── Grid (17) ──
  procedure(bmif_get_grid_type), deferred :: get_grid_type
  procedure(bmif_get_grid_rank), deferred :: get_grid_rank
  procedure(bmif_get_grid_size), deferred :: get_grid_size
  procedure(bmif_get_grid_shape), deferred :: get_grid_shape
  procedure(bmif_get_grid_spacing), deferred :: get_grid_spacing
  procedure(bmif_get_grid_origin), deferred :: get_grid_origin
  procedure(bmif_get_grid_x), deferred :: get_grid_x
  procedure(bmif_get_grid_y), deferred :: get_grid_y
  procedure(bmif_get_grid_z), deferred :: get_grid_z
  procedure(bmif_get_grid_node_count), deferred :: get_grid_node_count
  procedure(bmif_get_grid_edge_count), deferred :: get_grid_edge_count
  procedure(bmif_get_grid_face_count), deferred :: get_grid_face_count
  procedure(bmif_get_grid_edge_nodes), deferred :: get_grid_edge_nodes
  procedure(bmif_get_grid_face_nodes), deferred :: get_grid_face_nodes
  procedure(bmif_get_grid_face_edges), deferred :: get_grid_face_edges
  procedure(bmif_get_grid_nodes_per_face), deferred :: get_grid_nodes_per_face
end type
```

### 📝 Interface Signatures

Every function follows the same pattern — return an integer status, pass outputs via `intent(out)` parameters:

```fortran
abstract interface
  ! Initialize: read config, allocate memory, set initial conditions
  function bmif_initialize(self, config_file) result(bmi_status)
    import :: bmi
    class(bmi), intent(out) :: self              ! The model instance
    character(len=*), intent(in) :: config_file  ! Path to config file
    integer :: bmi_status                         ! 0=success, 1=failure
  end function

  ! Update: advance model by exactly ONE timestep
  function bmif_update(self) result(bmi_status)
    import :: bmi
    class(bmi), intent(inout) :: self
    integer :: bmi_status
  end function

  ! Get value: copy a variable's data into a caller-provided array
  function bmif_get_value_double(self, name, dest) result(bmi_status)
    import :: bmi
    class(bmi), intent(in) :: self
    character(len=*), intent(in) :: name           ! CSDMS Standard Name
    double precision, intent(inout) :: dest(:)     ! 1D output array!
    integer :: bmi_status
  end function
end interface
```

### ⚠️ Critical BMI Rules

| Rule | Details | Why |
|------|---------|-----|
| **1D arrays only** | All `get_value` / `set_value` use 1D arrays (`dest(:)`) | Avoids row-major vs column-major confusion between languages |
| **Caller allocates** | The caller must provide a pre-allocated array | BMI doesn't know the caller's memory management |
| **Status on everything** | Every function returns `integer` (0 or 1) | Consistent error handling across all languages |
| **Non-invasive** | Wrapper CALLS model, doesn't CHANGE model code | Model stays upstream-compatible |
| **CSDMS names** | Variables identified by CSDMS Standard Names, not internal names | Enables coupling without knowing internals |

---

## 6. 🔥 BMI Heat Model Example Deep Dive

### 🌡️ The Heat Model (heat.f90 — 158 lines)

A simple 2D heat diffusion model. This is the "model" that gets wrapped by BMI, just like WRF-Hydro is what we'll wrap.

**What it simulates:** Heat spreading across a 2D metal plate. Top edge is hot (fixed boundary condition), heat diffuses to neighbors over time.

```fortran
type :: heat_model
  integer :: n_x = 0              ! Grid columns
  integer :: n_y = 0              ! Grid rows
  real :: dt = 0.                 ! Timestep (seconds)
  real :: t  = 0.                 ! Current simulation time
  real :: t_end = 0.              ! End time
  real :: alpha = 0.              ! Thermal diffusivity

  real, pointer :: temperature(:,:) => null()      ! 2D state variable
  real, pointer :: temperature_tmp(:,:) => null()  ! Workspace
end type
```

**3 subroutines:**

| Subroutine | What It Does | Analogous WRF-Hydro Call |
|-----------|-------------|------------------------|
| `initialize_from_file(model, file)` | Reads config (4 values), allocates arrays, sets boundary | `HYDRO_ini()` + `land_driver_ini()` |
| `advance_in_time(model)` | One timestep: 5-point stencil on each cell, copy result, increment t | `land_driver_exe()` (all 5 phases) |
| `cleanup(model)` | Deallocate temperature arrays | `HYDRO_finish()` |

### 🎯 The BMI Wrapper (bmi_heat.f90 — 935 lines)

This is our **blueprint**. Every pattern here gets reused for WRF-Hydro.

#### Pattern 1: Type Extension

```fortran
module bmiheatf
  use heatf            ! Import the model module
  use bmif_2_0         ! Import BMI abstract interface
  use, intrinsic :: iso_c_binding, only: c_ptr, c_loc, c_f_pointer

  type, extends(bmi) :: bmi_heat    ! Inherit from abstract BMI
    private
    type(heat_model) :: model       ! EMBED the model as private member
  contains
    procedure :: initialize => heat_initialize
    procedure :: update => heat_update
    procedure :: finalize => heat_finalize
    procedure :: get_component_name => heat_component_name
    ! ... all 53 procedure mappings
  end type bmi_heat
end module
```

🧠 **ML Analogy:** Like `class BMIHeat(BMI): self._model = HeatModel()`

#### Pattern 2: Control Functions (IRF)

```fortran
! Initialize: delegate to model's own init
function heat_initialize(self, config_file) result(bmi_status)
  class(bmi_heat), intent(out) :: self
  character(len=*), intent(in) :: config_file

  call initialize_from_file(self%model, config_file)  ! ← Just delegate!
  bmi_status = BMI_SUCCESS
end function

! Update: exactly ONE timestep
function heat_update(self) result(bmi_status)
  class(bmi_heat), intent(inout) :: self

  call advance_in_time(self%model)  ! ← Just delegate!
  bmi_status = BMI_SUCCESS
end function

! Finalize: cleanup
function heat_finalize(self) result(bmi_status)
  class(bmi_heat), intent(inout) :: self

  call cleanup(self%model)  ! ← Just delegate!
  bmi_status = BMI_SUCCESS
end function
```

#### Pattern 3: Variable Name Dispatch (`select case`)

Every variable-info function uses the same pattern:

```fortran
function heat_var_type(self, name, type) result(bmi_status)
  class(bmi_heat), intent(in) :: self
  character(len=*), intent(in) :: name
  character(len=BMI_MAX_TYPE_NAME), intent(out) :: type
  integer :: bmi_status

  select case(name)
  case("plate_surface__temperature")         ! CSDMS Standard Name
    type = "real"
    bmi_status = BMI_SUCCESS
  case("plate_surface__thermal_diffusivity") ! Another variable
    type = "real"
    bmi_status = BMI_SUCCESS
  case default                                ! Unknown variable
    type = "-"
    bmi_status = BMI_FAILURE
  end select
end function
```

🧠 **ML Analogy:** Like a Python dictionary lookup:
```python
VAR_TYPES = {
    "plate_surface__temperature": "real",
    "plate_surface__thermal_diffusivity": "real",
}
return VAR_TYPES.get(name, BMI_FAILURE)
```

#### Pattern 4: get_value with Reshape (2D → 1D)

```fortran
function heat_get_double(self, name, dest) result(bmi_status)
  class(bmi_heat), intent(in) :: self
  character(len=*), intent(in) :: name
  double precision, intent(inout) :: dest(:)  ! Always 1D!
  integer :: bmi_status

  select case(name)
  case("plate_surface__temperature")
    ! FLATTEN 2D array → 1D array:
    dest = reshape(self%model%temperature, &
                   [self%model%n_y * self%model%n_x])
    bmi_status = BMI_SUCCESS
  case default
    bmi_status = BMI_FAILURE
  end select
end function
```

**Why flatten?** BMI requires all arrays as 1D to avoid row-major (C) vs column-major (Fortran) confusion. The caller can reshape back if needed.

#### Pattern 5: set_value with Reshape (1D → 2D)

```fortran
function heat_set_double(self, name, src) result(bmi_status)
  class(bmi_heat), intent(inout) :: self
  character(len=*), intent(in) :: name
  double precision, intent(in) :: src(:)  ! 1D input
  integer :: bmi_status

  select case(name)
  case("plate_surface__temperature")
    ! UNFLATTEN 1D → 2D:
    self%model%temperature = reshape(src, &
        [self%model%n_y, self%model%n_x])
    bmi_status = BMI_SUCCESS
  case default
    bmi_status = BMI_FAILURE
  end select
end function
```

#### Pattern 6: get_value_ptr (Zero-Copy)

```fortran
function heat_get_ptr(self, name, dest_ptr) result(bmi_status)
  use iso_c_binding, only: c_ptr, c_loc
  class(bmi_heat), intent(in) :: self
  character(len=*), intent(in) :: name
  type(c_ptr), intent(inout) :: dest_ptr  ! C pointer (no copy!)
  integer :: bmi_status

  select case(name)
  case("plate_surface__temperature")
    ! Return raw memory pointer — no data copying!
    dest_ptr = c_loc(self%model%temperature(1,1))
    bmi_status = BMI_SUCCESS
  end select
end function
```

**When to use:** For large arrays where copying is expensive. The caller gets a direct pointer to the model's memory. Changes to the model update the pointer's data automatically.

#### Pattern 7: Grid Functions

```fortran
! Grid type
function heat_grid_type(self, grid, type) result(bmi_status)
  class(bmi_heat), intent(in) :: self
  integer, intent(in) :: grid
  character(len=*), intent(out) :: type

  select case(grid)
  case(0)
    type = "uniform_rectilinear"
    bmi_status = BMI_SUCCESS
  case default
    type = "-"
    bmi_status = BMI_FAILURE
  end select
end function

! Grid shape (rows, columns)
function heat_grid_shape(self, grid, shape) result(bmi_status)
  class(bmi_heat), intent(in) :: self
  integer, intent(in) :: grid
  integer, intent(out) :: shape(:)

  select case(grid)
  case(0)
    shape = [self%model%n_y, self%model%n_x]  ! [rows, cols]
    bmi_status = BMI_SUCCESS
  case default
    bmi_status = BMI_FAILURE
  end select
end function
```

### 🧪 Test Results: 52/52 Pass

We built and tested the entire BMI Heat example suite:

```
FINAL RESULTS:
  Standalone model:     PASS
  BMI driver:           PASS
  CTest suite:       49/49 PASS
  Individual tests:  42/42 PASS
  Example programs:   7/7  PASS

  TOTAL: 52/52 ALL TESTS PASSED ✅
```

Script: `bmi-example-fortran/build_and_test.sh`

---

## 7. 🔗 Will SCHISM's BMI Work for Coupling with Our Wrapper?

This is the critical question: once we write `bmi_wrf_hydro.f90`, can we actually couple with SCHISM?

### ✅ Short Answer: YES for 1-Way, PARTIALLY for 2-Way

### 📊 Detailed Analysis

#### What SCHISM Can RECEIVE (Input from WRF-Hydro) ✅

SCHISM's `#ifdef USE_NWM_BMI` blocks already support receiving:

| Data | Internal Array | CSDMS Name | Units | Status |
|------|---------------|------------|-------|--------|
| River discharge (volume) | `ath3(:,1,1:2,1)` | `channel_water__volume_flow_rate` | m³/s | ✅ Ready |
| Water temperature | `ath3(:,1:ntracers,1:2,3)` | (tracer concentrations) | °C | ✅ Ready |
| Salinity | `ath3(:,1:ntracers,1:2,3)` | (tracer concentrations) | psu | ✅ Ready |

**How it works:** SCHISM skips reading from `vsource.th` / `msource.th` files and instead expects an external caller to populate the `ath3()` arrays. Our BMI coupling loop would do:

```fortran
! 1-Way Coupling: WRF-Hydro → SCHISM
call wrfhydro%get_value("channel_water__volume_flow_rate", discharge)
! Map WRF-Hydro reaches to SCHISM source elements...
call schism%set_value("channel_water__volume_flow_rate", discharge_mapped)
```

#### What SCHISM Can SEND (Output to WRF-Hydro) ⚠️ Needs Work

SCHISM produces these key variables internally, but there's **no `#ifdef` block to export them**:

| Data | Internal Variable | CSDMS Name | Units | Status |
|------|------------------|------------|-------|--------|
| Water surface elevation | `eta2(:)` | `sea_water_surface__elevation` | m | ⚠️ Available but no BMI export |
| Current velocity (u) | `uu2(:,:)` | `sea_water_x_velocity` | m/s | ⚠️ Available but no BMI export |
| Current velocity (v) | `vv2(:,:)` | `sea_water_y_velocity` | m/s | ⚠️ Available but no BMI export |

For **2-way coupling** (coastal backflooding → river routing), SCHISM would need additional `get_value()` exports. But this is a **Phase 4** concern — we'll start with 1-way coupling first.

### 🔄 Coupling Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                    PyMT Coupling Loop                             │
│                                                                  │
│  do while (time < end_time)                                      │
│    │                                                             │
│    │  ┌─ WRF-Hydro ────────────────────────────────┐             │
│    ├──│  call wrfhydro_bmi%update()                 │             │
│    │  │  (runs all 5 phases for one timestep)       │             │
│    │  └─────────────────────────────────────────────┘             │
│    │                      │                                      │
│    │               get_value()                                   │
│    │     "channel_water__volume_flow_rate" → Q(:)                │
│    │                      │                                      │
│    │            Grid Mapping (PyMT)                              │
│    │     NWM channel reaches → SCHISM source elements            │
│    │                      │                                      │
│    │               set_value()                                   │
│    │     "channel_water__volume_flow_rate" → ath3()              │
│    │                      │                                      │
│    │  ┌─ SCHISM ───────────────────────────────────┐             │
│    ├──│  call schism_bmi%update()                   │             │
│    │  │  (runs ocean model with river discharge)    │             │
│    │  └─────────────────────────────────────────────┘             │
│    │                      │                                      │
│    │  [Future: 2-way]     │                                      │
│    │  get eta2() from SCHISM → set in WRF-Hydro                 │
│    │  (backflooding signal at coastal boundary)                  │
│    │                                                             │
│  end do                                                          │
└──────────────────────────────────────────────────────────────────┘
```

### 📝 What Needs to Happen for Full Coupling

| Step | Who Does It | Status |
|------|------------|--------|
| 1. Write bmi_wrf_hydro.f90 | Us (Phase 1b) | 🔲 Next |
| 2. WRF-Hydro exports discharge | Us (bmi_wrf_hydro.f90 `get_value`) | 🔲 Next |
| 3. SCHISM receives discharge | Already works (`#ifdef USE_NWM_BMI`) | ✅ Done |
| 4. Grid mapping (reaches → elements) | PyMT / preprocessing script | 🔲 Phase 4 |
| 5. Time synchronization | PyMT framework | 🔲 Phase 4 |
| 6. SCHISM exports water level | SCHISM team / us (add `get_value` for `eta2`) | 🔲 Phase 4 |
| 7. WRF-Hydro receives water level | Us (bmi_wrf_hydro.f90 `set_value`) | 🔲 Phase 4 |

---

## 8. 📊 WRF-Hydro Complete Variable Inventory

### 📁 Output File Types

WRF-Hydro produces **8 types of output files** with a total of **154+ unique variables**:

| Output Type | File Prefix | Grid | Variables | Purpose |
|-------------|-------------|------|-----------|---------|
| CHRTOUT | `*CHRTOUT*` | Channel network | 11 | Channel routing diagnostics |
| LDASOUT | `*LDASOUT*` | 1km LSM | 116 | Land surface fluxes & states |
| RT_DOMAIN | `*RTOUT*` | 250m terrain | 5 | Routing grid states |
| LAKEOUT | `*LAKEOUT*` | Network (lakes) | 2 | Lake inflow/outflow |
| CHRTOUT_GRID | `*CHRTOUT_GRID*` | 1km grid | 1 | Channel flow on LSM grid |
| LSMOUT | `*LSMOUT*` | 1km LSM | 14 | Soil layer details |
| CHANOBS | `*CHANOBS*` | Network (gages) | 1 | Observation point discharge |
| GWOUT | `*GWOUT*` | Basin | 4 | Groundwater bucket |

### 📊 Complete Output Variables Table with CSDMS Standard Names

> **Legend:**
> - ✅ = Existing CSDMS Standard Name available
> - 🔶 = Proposed Standard Name (not yet in CSDMS registry)
> - **Grid:** 0 = LSM 1km, 1 = Routing 250m, 2 = Channel network

#### 🌊 Channel Routing Output (CHRTOUT) — 11 Variables

| # | Internal Name | Description | Units | Grid | CSDMS Standard Name | Status |
|---|--------------|-------------|-------|------|---------------------|--------|
| 1 | `QLINK(:,1)` / `streamflow` | River discharge/streamflow | m³/s | 2 | `channel_water__volume_flow_rate` | ✅ Exists (as `channel_water_x-section__volume_flow_rate`) |
| 2 | `nudge` | Data assimilation stream flow alteration | m³/s | 2 | NA | 🔶 `channel_water__nudge_volume_flow_rate` |
| 3 | `QLateral` / `q_lateral` | Runoff entering channel reach | m³/s | 2 | NA | 🔶 `channel_water__lateral_inflow_volume_flow_rate` |
| 4 | `velocity` | Flow velocity in channel | m/s | 2 | `channel_water_flow__speed` | ✅ Exists |
| 5 | `HLINK` / `Head` | Water surface elevation in channel | m | 2 | NA | 🔶 `channel_water_surface__elevation` |
| 6 | `qSfcLatRunoff` | Surface lateral runoff to channel | m³/s | 2 | NA | 🔶 `land_surface_water__lateral_runoff_volume_flow_rate` |
| 7 | `qBucket` | Groundwater bucket outflow to channel | m³/s | 2 | NA | 🔶 `land_subsurface_water__baseflow_volume_flow_rate` |
| 8 | `qBtmVertRunoff` | Bottom-of-soil to GW bucket flux | m³/s | 2 | NA | 🔶 `soil_bottom_water__vertical_runoff_volume_flow_rate` |
| 9 | `accSfcLatRunoff` | Accumulated surface lateral runoff | m³ | 2 | NA | 🔶 `land_surface_water__lateral_runoff_volume` |
| 10 | `accBucket` | Accumulated GW bucket outflow | m³ | 2 | NA | 🔶 `land_subsurface_water__baseflow_volume` |
| 11 | `qloss` | Channel infiltration loss | m³/s | 2 | NA | 🔶 `channel_water__infiltration_volume_flow_rate` |

#### 🌿 Land Surface Output (LDASOUT) — Key Variables (top 40 of 116)

| # | Internal Name | Description | Units | Grid | CSDMS Standard Name | Status |
|---|--------------|-------------|-------|------|---------------------|--------|
| 1 | `RAINRATE` | Precipitation rate | kg/m²/s | 0 | `atmosphere_water__precipitation_leq-volume_flux` | ✅ Exists |
| 2 | `SWFORC` | Incoming shortwave radiation | W/m² | 0 | `atmosphere_radiation~incoming~shortwave__energy_flux` | ✅ Exists (partial) |
| 3 | `LWFORC` | Incoming longwave radiation | W/m² | 0 | NA | 🔶 `atmosphere_radiation~incoming~longwave__energy_flux` |
| 4 | `SOIL_M` | Volumetric soil moisture (total) | m³/m³ | 0 | NA | 🔶 `soil_water__volume_fraction` |
| 5 | `SOIL_W` | Liquid volumetric soil moisture | m³/m³ | 0 | NA | 🔶 `soil_water~liquid__volume_fraction` |
| 6 | `SOIL_T` | Soil temperature | K | 0 | NA | 🔶 `soil__temperature` |
| 7 | `SNEQV` | Snow water equivalent | kg/m² | 0 | NA | 🔶 `snowpack__liquid-equivalent_depth` |
| 8 | `SNOWH` | Physical snow depth | m | 0 | NA | 🔶 `snowpack__depth` |
| 9 | `FSNO` | Snow cover fraction | - | 0 | NA | 🔶 `snowpack__area_fraction` |
| 10 | `ACCET` | Accumulated evapotranspiration | mm | 0 | `land_surface_water__evaporation_volume_flux` | ✅ Exists (partial) |
| 11 | `ECAN` | Canopy evaporation rate | kg/m²/s | 0 | NA | 🔶 `canopy_water__evaporation_mass_flux` |
| 12 | `EDIR` | Direct soil evaporation rate | kg/m²/s | 0 | NA | 🔶 `soil_surface_water__evaporation_mass_flux` |
| 13 | `ETRAN` | Transpiration rate | kg/m²/s | 0 | NA | 🔶 `vegetation__transpiration_mass_flux` |
| 14 | `SFCRNOFF` | Accumulated surface runoff | mm | 0 | `land_surface_water__runoff_volume_flux` | ✅ Exists |
| 15 | `UGDRNOFF` | Accumulated subsurface/baseflow runoff | mm | 0 | NA | 🔶 `soil_water__domain_time_integral_of_baseflow_volume_flux` |
| 16 | `FSA` | Total absorbed shortwave radiation | W/m² | 0 | NA | 🔶 `land_surface__absorbed_shortwave_energy_flux` |
| 17 | `FIRA` | Total net longwave to atmosphere | W/m² | 0 | NA | 🔶 `land_surface__net_longwave_energy_flux` |
| 18 | `HFX` | Sensible heat flux to atmosphere | W/m² | 0 | NA | 🔶 `land_surface__sensible_heat_flux` |
| 19 | `LH` | Latent heat flux to atmosphere | W/m² | 0 | NA | 🔶 `land_surface__latent_heat_flux` |
| 20 | `GRDFLX` | Ground heat flux into soil | W/m² | 0 | NA | 🔶 `soil_surface__heat_flux` |
| 21 | `TG` | Ground surface temperature | K | 0 | `land_surface__temperature` | ✅ Exists |
| 22 | `TV` | Vegetation temperature | K | 0 | NA | 🔶 `vegetation__temperature` |
| 23 | `TAH` | Canopy air temperature | K | 0 | NA | 🔶 `canopy_air__temperature` |
| 24 | `ALBEDO` | Surface albedo | - | 0 | NA | 🔶 `land_surface__albedo` |
| 25 | `EMISS` | Surface emissivity | - | 0 | NA | 🔶 `land_surface__emissivity` |
| 26 | `ZWT` | Depth to water table | m | 0 | `land_subsurface_sat-zone_top__depth` | ✅ Exists |
| 27 | `WA` | Water in aquifer | kg/m² | 0 | NA | 🔶 `aquifer_water__mass-per-area` |
| 28 | `FVEG` | Green vegetation fraction | - | 0 | NA | 🔶 `vegetation__area_fraction` |
| 29 | `LAI` | Leaf area index | m²/m² | 0 | NA | 🔶 `vegetation__leaf_area_index` |
| 30 | `CANWAT` | Total canopy water (liquid+ice) | mm | 0 | NA | 🔶 `canopy_water__depth` |
| 31 | `CANLIQ` | Canopy liquid water | mm | 0 | NA | 🔶 `canopy_water~liquid__depth` |
| 32 | `CANICE` | Canopy ice water | mm | 0 | NA | 🔶 `canopy_water~ice__depth` |
| 33 | `NEE` | Net ecosystem CO₂ exchange | g/m²/s | 0 | NA | 🔶 `ecosystem__net_co2_exchange_mass_flux` |
| 34 | `GPP` | Gross primary productivity | g/m²/s | 0 | NA | 🔶 `vegetation__gross_primary_productivity_mass_flux` |
| 35 | `ACCPRCP` | Accumulated precipitation | mm | 0 | NA | 🔶 `atmosphere_water__precipitation_leq-volume` |
| 36 | `QSNOW` | Snowfall rate on ground | mm/s | 0 | `atmosphere_water__snowfall_leq-volume_flux` | ✅ Exists |
| 37 | `QRAIN` | Rainfall rate on ground | mm/s | 0 | `atmosphere_water__rainfall_volume_flux` | ✅ Exists |
| 38 | `ACSNOW` | Accumulated snowfall | mm | 0 | NA | 🔶 `atmosphere_water__snowfall_leq-volume` |
| 39 | `ACSNOM` | Accumulated snowmelt | mm | 0 | NA | 🔶 `snowpack__melt_volume` |
| 40 | `ISNOW` | Number of snow layers | count | 0 | NA | 🔶 `snowpack__layer_count` |

#### 🗺️ Terrain Routing Output (RT_DOMAIN) — 5 Variables

| # | Internal Name | Description | Units | Grid | CSDMS Standard Name | Status |
|---|--------------|-------------|-------|------|---------------------|--------|
| 1 | `zwattablrt` | Depth to water table (routing) | m | 1 | `land_subsurface_sat-zone_top__depth` | ✅ Exists |
| 2 | `sfcheadsubrt` | Subsurface water head | m | 1 | NA | 🔶 `land_subsurface_water__head` |
| 3 | `sfcheadrt` | Surface water depth | m | 1 | `land_surface_water__depth` | ✅ Exists |
| 4 | `QSTRMVOLRT` | Channel volume on routing grid | m³ | 1 | NA | 🔶 `channel_water__volume` |
| 5 | `QBDRYRT` | Boundary flux | m | 1 | NA | 🔶 `domain_boundary_water__flux` |

#### 🏞️ Lake Output (LAKEOUT) — 2 Variables

| # | Internal Name | Description | Units | Grid | CSDMS Standard Name | Status |
|---|--------------|-------------|-------|------|---------------------|--------|
| 1 | `QLAKEI` / `inflow` | Lake inflow | m³/s | 2 | NA | 🔶 `lake_water__inflow_volume_flow_rate` |
| 2 | `QLAKEO` / `outflow` | Lake outflow | m³/s | 2 | NA | 🔶 `lake_water__outflow_volume_flow_rate` |

#### 💧 Groundwater Output (GWOUT) — 4 Variables

| # | Internal Name | Description | Units | Grid | CSDMS Standard Name | Status |
|---|--------------|-------------|-------|------|---------------------|--------|
| 1 | `qin_gwsubbas` | GW bucket inflow | m³/s | basin | NA | 🔶 `groundwater_bucket__inflow_volume_flow_rate` |
| 2 | `qout_gwsubbas` | GW bucket outflow | m³/s | basin | NA | 🔶 `groundwater_bucket__outflow_volume_flow_rate` |
| 3 | `qloss_gwsubbas` | GW bucket loss (deep seepage) | m³/s | basin | NA | 🔶 `groundwater_bucket__loss_volume_flow_rate` |
| 4 | `z_gwsubbas` | GW bucket depth/storage | mm | basin | NA | 🔶 `groundwater_bucket__depth` |

### 📥 Input/Forcing Variables

#### 🌤️ Atmospheric Forcing (from LDASIN files, hourly)

| # | Internal Name | Description | Units | Grid | CSDMS Standard Name | Status |
|---|--------------|-------------|-------|------|---------------------|--------|
| 1 | `T2` (T2D) | 2-meter air temperature | K | 0 | `land_surface_air__temperature` | ✅ Exists |
| 2 | `Q2` (Q2D) | 2-meter specific humidity | kg/kg | 0 | `atmosphere_air_water~vapor__relative_saturation` | ✅ Exists (partial) |
| 3 | `U10` (U2D) | 10-meter U wind component | m/s | 0 | NA | 🔶 `atmosphere_air_flow__east_component_of_velocity` |
| 4 | `V10` (V2D) | 10-meter V wind component | m/s | 0 | NA | 🔶 `atmosphere_air_flow__north_component_of_velocity` |
| 5 | `PSFC` | Surface air pressure | Pa | 0 | `atmosphere_air__static_pressure` | ✅ Exists (partial) |
| 6 | `GLW` (LWDOWN) | Downward longwave radiation | W/m² | 0 | NA | 🔶 `atmosphere_radiation~incoming~longwave__energy_flux` |
| 7 | `SWDOWN` | Downward shortwave radiation | W/m² | 0 | `atmosphere_radiation~incoming~shortwave__energy_flux` | ✅ Exists (partial) |
| 8 | `RAINBL` (PCP) | Total precipitation | mm | 0 | `atmosphere_water__precipitation_leq-volume_flux` | ✅ Exists |
| 9 | `VEGFRA` | Vegetation fraction | - | 0 | NA | 🔶 `vegetation__area_fraction` |
| 10 | `LAI` | Leaf area index | m²/m² | 0 | NA | 🔶 `vegetation__leaf_area_index` |
| 11 | `SNOWBL` | Snowfall component | mm | 0 | `atmosphere_water__snowfall_leq-volume_flux` | ✅ Exists |

#### 🗺️ Static Domain Data (from GEO_EM / wrfinput, read once)

| # | Internal Name | Description | Units | Grid | CSDMS Standard Name | Status |
|---|--------------|-------------|-------|------|---------------------|--------|
| 1 | `XLAT` | Latitude | degrees | 0 | NA | (grid coordinate) |
| 2 | `XLONG` | Longitude | degrees | 0 | NA | (grid coordinate) |
| 3 | `HGT` | Terrain elevation / DEM | m | 0 | `land_surface__elevation` | ✅ Exists |
| 4 | `IVGTYP` | Vegetation type (USGS/MODIS) | category | 0 | NA | (classification) |
| 5 | `ISLTYP` | Soil type (STATSGO) | category | 0 | NA | (classification) |
| 6 | `XLAND` | Land/water mask | 1=land, 2=water | 0 | NA | (mask) |
| 7 | `TMN` | Deep soil temperature (bottom BC) | K | 0 | NA | 🔶 `soil_bottom__temperature` |
| 8 | `SEAICE` | Sea ice fraction | - | 0 | `sea_ice__area_fraction` | ✅ Exists |

#### 🌊 Channel Network Data (from Route_Link.nc)

| # | Internal Name | Description | Units | Grid | CSDMS Standard Name | Status |
|---|--------------|-------------|-------|------|---------------------|--------|
| 1 | `CHANLEN` (length) | Reach length | m | 2 | NA | 🔶 `channel__length` |
| 2 | `MannN` (n) | Manning's roughness coefficient | s/m^(1/3) | 2 | NA | 🔶 `channel_bed__manning_coefficient` |
| 3 | `So` (s0) | Channel slope | m/m | 2 | NA | 🔶 `channel_bed__slope` |
| 4 | `Bw` (bw) | Channel bottom width | m | 2 | NA | 🔶 `channel_x-section__bottom_width` |
| 5 | `Tw` (tw) | Channel top width | m | 2 | NA | 🔶 `channel_x-section__top_width` |
| 6 | `ChSSlp` (cs) | Channel side slope | - | 2 | NA | 🔶 `channel_x-section__side_slope` |
| 7 | `CHLAT` (lat) | Reach latitude | degrees | 2 | NA | (grid coordinate) |
| 8 | `CHLON` (lon) | Reach longitude | degrees | 2 | NA | (grid coordinate) |

### 📊 Summary Statistics

| Category | Variable Count | ✅ Existing CSDMS Names | 🔶 Need New Names |
|----------|---------------|------------------------|-------------------|
| CHRTOUT (channel) | 11 | 2 | 9 |
| LDASOUT (land surface) | 40 (key) | 8 | 32 |
| RT_DOMAIN (routing) | 5 | 2 | 3 |
| LAKEOUT (lakes) | 2 | 0 | 2 |
| GWOUT (groundwater) | 4 | 0 | 4 |
| Atmospheric forcing | 11 | 5 | 6 |
| Static domain | 8 | 3 | 5 |
| Channel network | 8 | 0 | 8 |
| **Total** | **~89 key variables** | **~20 (22%)** | **~69 (78%)** |

---

## 9. 🏷️ CSDMS Standard Names: What's Next?

### 🤔 What Are CSDMS Standard Names?

**CSDMS Standard Names** are a universal naming convention for scientific variables. They were developed by **Scott Peckham** at the University of Colorado Boulder as part of the **CSDMS** (Community Surface Dynamics Modeling System) project.

The goal: **any model can talk to any other model** by using the same names for the same physical quantities. Instead of WRF-Hydro calling streamflow "QLINK" and SCHISM calling it "vsource", both use `channel_water__volume_flow_rate`.

### 📐 Naming Rules

CSDMS Standard Names follow the pattern: **`<object>__<quantity>`**

```
channel_water__volume_flow_rate
├──────────┘  ├──────────────┘
   object         quantity
```

Rules:
- **Double underscore** (`__`) separates object from quantity
- All **lowercase** letters
- Only characters: `a-z`, `0-9`, `_`, `-`, `~`
- Tilde (`~`) indicates adjective modifiers: `atmosphere_water~vapor` = "atmospheric water vapor"
- Hyphen (`-`) in compound words: `liquid-equivalent`
- Single underscore (`_`) separates words within object or quantity

### 📋 Examples of the Pattern

| Variable | Object | Quantity | Full CSDMS Name |
|----------|--------|----------|-----------------|
| Streamflow | `channel_water` | `volume_flow_rate` | `channel_water__volume_flow_rate` |
| Soil moisture | `soil_water` | `volume_fraction` | `soil_water__volume_fraction` |
| Precipitation | `atmosphere_water` | `precipitation_leq-volume_flux` | `atmosphere_water__precipitation_leq-volume_flux` |
| Surface elevation | `land_surface` | `elevation` | `land_surface__elevation` |
| Water table depth | `land_subsurface_sat-zone_top` | `depth` | `land_subsurface_sat-zone_top__depth` |
| Snow depth | `snowpack` | `depth` | `snowpack__depth` |

### 🔶 What We Need to Do for Missing Names

Out of ~89 key WRF-Hydro variables, only ~20 have existing CSDMS Standard Names. For the remaining ~69:

#### Step 1: Check the CSDMS Registry (Already Done ✅)

We searched the [CSN Searchable List](https://csdms.colorado.edu/wiki/CSN_Searchable_List) and the [Scientific Variables Ontology](https://geoscienceontology.org/) for existing matches.

#### Step 2: Propose Standard Names Following Conventions

For variables without existing names, we construct proposed names following the `object__quantity` pattern. Example:

```
WRF-Hydro internal name: qBucket
Physical meaning: Groundwater bucket outflow to channel
Units: m³/s

Proposed CSDMS name:
  Object:   land_subsurface_water    (groundwater in the subsurface)
  Quantity:  baseflow_volume_flow_rate (baseflow = GW contribution to streamflow)
  Full name: land_subsurface_water__baseflow_volume_flow_rate
```

#### Step 3: Start with Priority Variables for BMI

We don't need all 89 variables on day one. Our initial BMI wrapper will expose **5-10 key variables**:

| Priority | Variable | CSDMS Standard Name | Why It's Important |
|----------|---------|---------------------|-------------------|
| 🥇 1 | Streamflow (QLINK) | `channel_water__volume_flow_rate` ✅ | **Primary coupling variable** — this is what SCHISM needs |
| 🥇 2 | Surface water depth (sfcheadrt) | `land_surface_water__depth` ✅ | Key routing diagnostic |
| 🥇 3 | Soil moisture (SOIL_M) | `soil_water__volume_fraction` 🔶 | Essential land surface state |
| 🥇 4 | Snow water equivalent (SNEQV) | `snowpack__liquid-equivalent_depth` 🔶 | Critical for cold-season hydrology |
| 🥈 5 | Evapotranspiration (ACCET) | `land_surface_water__evaporation_volume_flux` ✅ | Water balance closure |
| 🥈 6 | Air temperature (T2) | `land_surface_air__temperature` ✅ | Forcing input for coupling |
| 🥈 7 | Precipitation (RAINRATE) | `atmosphere_water__precipitation_leq-volume_flux` ✅ | Forcing input |
| 🥈 8 | Subsurface runoff (UGDRNOFF) | `soil_water__domain_time_integral_of_baseflow_volume_flux` 🔶 | Baseflow contribution |
| 🥉 9 | Water table depth (ZWT) | `land_subsurface_sat-zone_top__depth` ✅ | Groundwater coupling |
| 🥉 10 | Channel velocity (velocity) | `channel_water_flow__speed` ✅ | Transport/routing diagnostic |

#### Step 4: Register New Names (Future — Phase 2+)

For proposed names, we can:

1. **Use them internally** in our BMI wrapper right now (no registration needed)
2. **Submit them to CSDMS** when we publish the wrapper — CSDMS maintains the registry and accepts community contributions
3. **Check the Scientific Variables Ontology** at [geoscienceontology.org](https://geoscienceontology.org/) for near-matches
4. **Coordinate with NOAA/NWM team** since WRF-Hydro is their operational model

#### Step 5: Document in Our Wrapper

In `bmi_wrf_hydro.f90`, we'll have a mapping dictionary:

```fortran
! Variable name mapping: CSDMS Standard Name → Internal Name
select case(name)
case("channel_water__volume_flow_rate")     ! ✅ Official
  ! Maps to: QLINK(:,1) — channel discharge
case("soil_water__volume_fraction")          ! 🔶 Proposed
  ! Maps to: SOIL_M(:,:,:) — volumetric soil moisture
case("land_surface_water__depth")            ! ✅ Official
  ! Maps to: sfcheadrt(:,:) — surface water depth
case("snowpack__liquid-equivalent_depth")    ! 🔶 Proposed
  ! Maps to: SNEQV(:,:) — snow water equivalent
end select
```

### 📊 CSDMS Name Status Summary

```
┌─────────────────────────────────────────────────────────────┐
│              CSDMS Standard Names Status                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ✅ Existing (can use immediately):  ~20 variables (22%)    │
│     Examples: streamflow, precipitation, surface temp,      │
│     water table depth, rainfall, snowfall                   │
│                                                             │
│  🔶 Proposed (we construct following rules): ~69 vars (78%) │
│     Examples: soil_water__volume_fraction,                  │
│     snowpack__liquid-equivalent_depth,                      │
│     land_surface__sensible_heat_flux                        │
│                                                             │
│  Priority for Phase 1b: Start with 10 key variables        │
│  (7 have official names, 3 need proposed names)             │
│                                                             │
│  Registration: Not needed now. Use proposed names           │
│  internally, register with CSDMS in Phase 2+.              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 10. ✅ Summary & Action Items

### 🔑 Key Takeaways

| # | Topic | Finding |
|---|-------|---------|
| 1 | **SCHISM's BMI** | Uses inline `#ifdef USE_NWM_BMI` in 3 files (5 blocks). Works because SCHISM is simple: single grid, shallow nesting, already has IRF. |
| 2 | **WRF-Hydro** | Inline `#ifdef` won't work: 5-level nesting, 3 grids, 5 phases/step, 235 files. Need separate wrapper. |
| 3 | **Our approach** | Write `bmi_wrf_hydro.f90` — non-invasive, single file, follows `bmi_heat.f90` template (all 49 tests pass). |
| 4 | **SCHISM coupling** | ✅ 1-way works (receive discharge). ⚠️ 2-way needs SCHISM to add `get_value` for water elevation. |
| 5 | **Variables** | 154+ output variables, ~89 key ones. 22% have CSDMS names, 78% need proposed names. |
| 6 | **CSDMS names** | Start with 10 priority variables. Use proposed names internally. Register with CSDMS later. |

### 📋 Action Items for Phase 1b

| # | Task | Priority | Status |
|---|------|----------|--------|
| 1 | Refactor WRF-Hydro time loop into IRF pattern | 🔴 Critical | 🔲 Next |
| 2 | Write `bmi_wrf_hydro.f90` with 10 priority variables | 🔴 Critical | 🔲 |
| 3 | Implement all 41 BMI functions (many return BMI_FAILURE initially) | 🔴 Critical | 🔲 |
| 4 | Compile as `libwrfhydro_bmi.so` | 🟡 Important | 🔲 |
| 5 | Write Fortran test driver (like `bmi_main.f90`) | 🟡 Important | 🔲 |
| 6 | Validate BMI output against standalone WRF-Hydro run | 🟡 Important | 🔲 |
| 7 | Expand to full variable set (89+ variables) | 🟢 Later | 🔲 |
| 8 | Register proposed CSDMS names | 🟢 Phase 2+ | 🔲 |

---

> **📖 Related Documents:**
> - Doc 1: `Complete_Beginners_Guide` — Big picture, spatial/temporal concepts
> - Doc 2: `BMI_Complete_Detailed_Guide` — All 41 functions, grid types
> - Doc 3: `CSDMS_Standard_Names_Complete_Guide` — Naming conventions
> - Doc 7: `WRF_Hydro_Beginners_Guide_For_ML_Engineers` — WRF-Hydro internals
> - Doc 8: `BMI_Template_And_Heat_Model_Complete_Code_Guide` — Line-by-line walkthrough
> - Master Plan: `Plan/BMI_Implementation_Master_Plan.md` — 6-phase roadmap

---

*Document created: February 20, 2026*
*Total variables catalogued: 89+ key variables across 8 output types*
*CSDMS coverage: 22% existing, 78% proposed*
