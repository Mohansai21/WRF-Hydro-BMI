# 📋 WRF-Hydro BMI (`bmi_wrf_hydro.f90`) — Detailed Technical Plan

> 🎯 **Purpose:** This document is the definitive technical blueprint for building `bmi_wrf_hydro.f90` — the Fortran 2003 BMI wrapper that enables WRF-Hydro to be controlled externally by PyMT, coupled with SCHISM, and used in ~20 lines of Python.
>
> 📌 **Scope:** Concepts only — NO code. Covers every variable, every grid, every BMI function, the t0/t1 sliding window pattern, 2-way coupling architecture, SCHISM BMI comparison, and the full testing plan.
>
> 📅 **Created:** February 2026 | **Status:** Phase 1 — Pre-Implementation Planning

---

## 📑 Table of Contents

1. [🏗️ Architecture Overview](#1-️-architecture-overview)
2. [🔄 The IRF Pattern — Decomposing WRF-Hydro's Time Loop](#2--the-irf-pattern--decomposing-wrf-hydros-time-loop)
3. [📤 Output Variables (WRF-Hydro → Outside World)](#3--output-variables-wrf-hydro--outside-world)
4. [📥 Input Variables (Outside World → WRF-Hydro)](#4--input-variables-outside-world--wrf-hydro)
5. [🔗 The Key Coupling Variable: `Q_bnd_source`](#5--the-key-coupling-variable-q_bnd_source)
6. [↔️ 2-Way Coupling Architecture (WRF-Hydro ⟺ SCHISM)](#6-️-2-way-coupling-architecture-wrf-hydro--schism)
7. [🗺️ Grid Types & Spatial Architecture](#7-️-grid-types--spatial-architecture)
8. [⏱️ The t0/t1 Sliding Window Pattern](#8-️-the-t0t1-sliding-window-pattern)
9. [🆚 SCHISM BMI vs WRF-Hydro BMI — Complete Comparison](#9--schism-bmi-vs-wrf-hydro-bmi--complete-comparison)
10. [📦 All 41 BMI Functions — Detailed Breakdown](#10--all-41-bmi-functions--detailed-breakdown)
11. [🧪 Testing Plan — Functions, Strategies, Validation](#11--testing-plan--functions-strategies-validation)
12. [🧮 Summary — Numbers at a Glance](#12--summary--numbers-at-a-glance)

---

## 1. 🏗️ Architecture Overview

### 🎯 What We're Building

We're building a **single Fortran file** (`bmi_wrf_hydro.f90`) that wraps WRF-Hydro's internals behind the BMI (Basic Model Interface) standard. Think of it like writing an **adapter** — the same way you'd write a PyTorch `DataLoader` wrapper around a custom dataset.

```
🧠 ML Analogy:
┌──────────────────────────────────────────────────────────────┐
│  BMI Wrapper = PyTorch DataLoader                            │
│  WRF-Hydro   = Your custom dataset/model                    │
│  PyMT        = The training framework (like PyTorch Lightning)│
│  SCHISM      = Another model in the ensemble                 │
│  CSDMS Names = Standardized tensor names (like HuggingFace)  │
└──────────────────────────────────────────────────────────────┘
```

### 🏛️ The 5-Layer Stack

```
┌─────────────────────────────────────────────────────────┐
│  Layer 5: 🐍 Jupyter Notebook (~20 lines Python)        │  ← Scientist
│           model.update() / model.get_value()            │
├─────────────────────────────────────────────────────────┤
│  Layer 4: 🔧 PyMT Framework                             │  ← Grid mapping
│           Time sync, data exchange, unit conversion     │     + time sync
├─────────────────────────────────────────────────────────┤
│  Layer 3: 📦 Babelized Plugins                          │  ← Fortran→Python
│           pymt_wrfhydro + pymt_schism                   │     bridge
├─────────────────────────────────────────────────────────┤
│  Layer 2: 🔌 BMI Wrappers + CSDMS Standard Names        │  ← THIS IS WHAT
│           bmi_wrf_hydro.f90 + bmischism.f90             │     WE'RE BUILDING
├─────────────────────────────────────────────────────────┤
│  Layer 1: 🌊 Original Models (Fortran)                  │  ← Untouched
│           WRF-Hydro v5.4.0  +  SCHISM                  │     source code
└─────────────────────────────────────────────────────────┘
```

### 🧩 The Adapter Pattern (Non-Invasive)

The single most important principle: **we NEVER modify WRF-Hydro's source code.** Our wrapper sits outside and CALLS existing subroutines through a standardized interface.

```
❌ WRONG: Editing WRF-Hydro source files, adding #ifdef blocks
✅ RIGHT: Writing a separate file that imports and calls WRF-Hydro modules

┌──────────────────────┐     calls     ┌────────────────────────┐
│  bmi_wrf_hydro.f90   │ ──────────►  │  WRF-Hydro subroutines │
│  (OUR wrapper)       │              │  (UNTOUCHED originals)  │
│                      │  ◄──────────  │                        │
│  Exposes 41 BMI      │   returns    │  land_driver_ini()     │
│  functions           │   state      │  land_driver_exe()     │
│                      │              │  HYDRO_ini/exe/finish  │
└──────────────────────┘              └────────────────────────┘
```

### 📂 Module Structure of `bmi_wrf_hydro.f90`

The wrapper file will contain a single Fortran module called `bmiwrfhydrof` with:

| Component | Description | ML Analogy |
|-----------|-------------|------------|
| `type :: bmi_wrf_hydro` | Main BMI type extending abstract `bmi` | Like a `nn.Module` subclass |
| `state` member | WRF-Hydro state container (holds time counters) | Like `self.model` in a wrapper |
| `itime` | Current timestep counter | Like `self.global_step` |
| `ntime` | Total number of timesteps | Like `max_epochs * steps_per_epoch` |
| `dt` | Timestep size in seconds (3600.0) | Like `learning_rate` (fixed step size) |
| `t` | Current model time in seconds | Like accumulated training time |
| `output_items(6)` | Array of output CSDMS variable names | Like `model.output_names` |
| `input_items(4)` | Array of input CSDMS variable names | Like `model.input_names` |
| 41 procedure bindings | All BMI functions | Like `forward()`, `parameters()`, etc. |

> 📏 **Estimated size:** 1,500–2,000 lines of Fortran 2003 (SCHISM BMI = 1,729 lines, Heat BMI = 935 lines)

---

## 2. 🔄 The IRF Pattern — Decomposing WRF-Hydro's Time Loop

### 🧠 ML Analogy: IRF = Separating Training Loop from Model

```
🧠 In ML terms:
   Traditional WRF-Hydro = model.fit(epochs=100)     ← Model controls the loop
   BMI WRF-Hydro         = model.train_one_step()    ← CALLER controls the loop

   initialize() = model.__init__() + model.load_weights()
   update()     = model.train_one_step(batch)
   finalize()   = model.save_checkpoint() + cleanup
```

### 🔧 WRF-Hydro's Current Main Program (43 lines)

WRF-Hydro's entry point (`main_hrldas_driver.F`) has an **integrated time loop** — the model controls when to start, step, and stop. BMI requires the CALLER to control the loop.

```
┌─────────────────────────────────────────────────────────────────┐
│  CURRENT WRF-Hydro (model controls loop):                      │
│                                                                 │
│    call land_driver_ini(NTIME, state)    ← Init + allocate     │
│    DO ITIME = 1, NTIME                   ← MODEL-controlled    │
│       call land_driver_exe(ITIME, state) ← One timestep        │
│    END DO                                                       │
│    call HYDRO_finish()                   ← Cleanup             │
└─────────────────────────────────────────────────────────────────┘

                            ▼ BMI REFACTORING ▼

┌─────────────────────────────────────────────────────────────────┐
│  BMI WRF-Hydro (CALLER controls loop):                         │
│                                                                 │
│  initialize(config_file):                                       │
│    ├── Parse config → get NTIME, dt, paths                     │
│    ├── call land_driver_ini(NTIME, state)                      │
│    ├── call HYDRO_ini()                                        │
│    └── Set itime=0, t=0.0                                      │
│                                                                 │
│  update():                     ← Called by PyMT, NOT by us     │
│    ├── itime = itime + 1                                       │
│    ├── call land_driver_exe(itime, state)                      │
│    ├── (internally: read forcing → NoahMP → GW → HYDRO_exe)   │
│    └── t = t + dt                                              │
│                                                                 │
│  update_until(target_time):    ← Loop update() until time      │
│    └── DO WHILE (t < target_time): call update()               │
│                                                                 │
│  finalize():                                                    │
│    ├── call HYDRO_finish()                                     │
│    ├── Deallocate arrays                                       │
│    └── Close files                                             │
└─────────────────────────────────────────────────────────────────┘
```

### 🧬 The 5 Sequential Physics Phases Per Timestep

Every time `update()` is called, WRF-Hydro runs 5 sequential phases internally. This is why a simple `#ifdef` won't work — we need a wrapper function that orchestrates all 5 phases.

```
                    One update() Call
                    ═══════════════
    ┌───────────────────────────────────────────┐
    │  Phase 1: 📖 Read Forcing Data            │  ← LDASIN files (T2, RAIN, etc.)
    │           (or accept from BMI set_value)  │
    ├───────────────────────────────────────────┤
    │  Phase 2: 🌱 Noah-MP Land Surface Model   │  ← Grid 0 (1km)
    │           Soil moisture, snow, ET          │     Produces: infiltration, runoff
    ├───────────────────────────────────────────┤
    │  Phase 3: 💧 Groundwater Table Update      │  ← Grid 0 (1km)
    │           Water table depth adjustment     │     Uses: soil drainage
    ├───────────────────────────────────────────┤
    │  Phase 4: 🌊 HYDRO_exe Routing             │  ← Grids 0→1→2
    │           ├── Disaggregate 1km → 250m      │     Overland + subsurface
    │           ├── Overland flow (250m)          │     + channel routing
    │           ├── Subsurface lateral flow (250m)│
    │           ├── Channel routing (network)     │     Produces: QLINK (streamflow)
    │           └── Aggregate 250m → 1km          │
    ├───────────────────────────────────────────┤
    │  Phase 5: 📝 Write Output Files            │  ← LDASOUT, CHRTOUT, RTOUT...
    │           (or expose via BMI get_value)    │
    └───────────────────────────────────────────┘
```

### 🎯 Key IRF Subroutines (Already Identified)

| BMI Function | WRF-Hydro Subroutine | Location | Lines | What It Does |
|-------------|----------------------|----------|-------|-------------|
| `initialize()` | `land_driver_ini()` | `module_NoahMP_hrldas_driver.F:422` | ~1,200 | Read namelists, allocate arrays, init Noah-MP |
| `initialize()` | `HYDRO_ini()` | `module_HYDRO_drv.F90:1350` | ~450 | Read hydro config, load channel network, init routing |
| `update()` | `land_driver_exe()` | `module_NoahMP_hrldas_driver.F:1646` | ~1,200 | Read forcing, run Noah-MP, trigger HYDRO_exe |
| `update()` | `HYDRO_exe()` | `module_HYDRO_drv.F90:561` | ~800 | Disaggregate, route, aggregate, output |
| `finalize()` | `HYDRO_finish()` | `module_HYDRO_drv.F90:1800` | ~40 | Final restart, close files, deallocate |

> 💡 **Total subroutine lines being wrapped:** ~3,690 lines across 5 subroutines. Our BMI wrapper calls these as black boxes.

---

## 3. 📤 Output Variables (WRF-Hydro → Outside World)

These are the variables that external callers (PyMT, SCHISM, Jupyter) can READ from WRF-Hydro via `get_value()`.

### 🔵 Priority Output Variables (Phase 1 — Initial 8)

| # | Internal Name | CSDMS Standard Name | Units | Grid | Type | Size | Description |
|---|---------------|---------------------|-------|------|------|------|-------------|
| 1 | `QLINK(:,2)` | `channel_water__volume_flow_rate` | m³/s | 2 (channel) | `double` | NLINKS | ⭐ **PRIMARY** — Streamflow at every reach. THE coupling variable to SCHISM |
| 2 | `sfcheadrt` | `land_surface_water__depth` | m | 1 (250m) | `double` | IXRT×JXRT | Surface water depth on terrain routing grid |
| 3 | `SMOIS` / `SOIL_M` | `soil_water__volume_fraction` | dimensionless | 0 (1km) | `double` | IX×JX×NSOIL | Soil moisture by layer (4 layers: 0–10, 10–40, 40–100, 100–200 cm) |
| 4 | `SNEQV` | `snowpack__liquid-equivalent_depth` | m | 0 (1km) | `double` | IX×JX | Snow water equivalent (how much water if all snow melted) |
| 5 | `ACCET` | `land_surface_water__evaporation_volume_flux` | mm | 0 (1km) | `double` | IX×JX | Accumulated evapotranspiration |
| 6 | `SFCRUNOFF` | `land_surface_water__runoff_volume_flux` | mm | 0 (1km) | `double` | IX×JX | Surface runoff (infiltration excess) |
| 7 | `UGDRNOFF` | `soil_water__domain_time_integral_of_baseflow_volume_flux` | mm | 0 (1km) | `double` | IX×JX | Underground/subsurface drainage runoff |
| 8 | `T2` | `land_surface_air__temperature` | K | 0 (1km) | `double` | IX×JX | 2-meter air temperature (from forcing or computed) |

### 🟡 Expansion Output Variables (Phase 2 — Additional 10)

| # | Internal Name | CSDMS Standard Name | Units | Grid |
|---|---------------|---------------------|-------|------|
| 9 | `HLINK` | `channel_water__depth` | m | 2 |
| 10 | `velocity` | `channel_water__mean-of_velocity` | m/s | 2 |
| 11 | `ZWT` | `soil_water_table__depth` | m | 0 |
| 12 | `SNOWH` | `snowpack__depth` | m | 0 |
| 13 | `HFX` | `land_surface__sensible_heat_flux` | W/m² | 0 |
| 14 | `LH` | `land_surface__latent_heat_flux` | W/m² | 0 |
| 15 | `GRDFLX` | `land_surface_soil__heat_flux` | W/m² | 0 |
| 16 | `INFXSRT` | `soil_surface_water__infiltration_volume_flux` | mm | 1 |
| 17 | `qout_gwsubbas` | `basin_groundwater__volume_flow_rate` | m³/s | 0 |
| 18 | `resht` / `water_sfc_elev` | `lake_water_surface__elevation` | m | 0 |

### 📊 Variable Access Pattern — Where the Data Lives

```
🧠 ML Analogy: Like accessing model.layer3.weight.data

WRF-Hydro state variables live in deeply nested Fortran module globals:

  Channel streamflow:  rt_domain(1)%QLINK(:,2)      ← RT_FIELD type in module_rt_inc.F90
  Surface water:       rt_domain(1)%sfcheadrt(:,:)   ← 2D array, flatten to 1D for BMI
  Soil moisture:       SMOIS(:,:,:)                   ← 3D array (i, j, layer), flatten
  Snow equivalent:     SNEQV(:,:)                     ← 2D array, flatten to 1D
  Temperature:         T2(:,:)                        ← 2D array, flatten to 1D

⚠️ BMI RULE: ALL arrays must be flattened to 1D before returning via get_value()
   2D array (JX, IX) → 1D array (JX × IX) using Fortran reshape()
   3D array (JX, IX, NSOIL) → 1D array (JX × IX × NSOIL)
```

### 📊 Full Variable Inventory Summary

| Category | Total Variables | Priority (Phase 1) | Expansion (Phase 2) |
|----------|----------------|--------------------|--------------------|
| Channel output (CHRTOUT) | 11 | 1 (QLINK) | 2 (HLINK, velocity) |
| Land surface (LDASOUT) | 40 | 5 (SMOIS, SNEQV, ACCET, SFCRUNOFF, UGDRNOFF) | 5 (ZWT, SNOWH, HFX, LH, GRDFLX) |
| Terrain routing (RTOUT) | 5 | 1 (sfcheadrt) | 1 (INFXSRT) |
| Groundwater (GWOUT) | 4 | 0 | 1 (qout_gwsubbas) |
| Lakes (LAKEOUT) | 3 | 0 | 1 (resht) |
| Diagnostic | 1 | 1 (T2) | 0 |
| **Total** | **~89** | **8** | **10** |

---

## 4. 📥 Input Variables (Outside World → WRF-Hydro)

These are the variables external callers can WRITE into WRF-Hydro via `set_value()`. This is how SCHISM sends coastal water levels back, and how a user could override forcing data.

### 🔴 Input Variables for 2-Way Coupling

| # | CSDMS Standard Name | Units | Grid | Source | Purpose |
|---|---------------------|-------|------|--------|---------|
| 1 | `atmosphere_water__precipitation_leq-volume_flux` | mm/s | 0 (1km) | Forcing override | Override RAINRATE from external source |
| 2 | `land_surface_air__temperature` | K | 0 (1km) | Forcing override | Override T2D from external source |
| 3 | `sea_water_surface__elevation` | m | 2 (channel) | ⭐ **FROM SCHISM** | Coastal water level at river outlets — **the 2-way coupling variable** |
| 4 | `sea_water__x_velocity` | m/s | 2 (channel) | From SCHISM | Coastal current velocity (future expansion) |

### 🔍 Deep Dive: `sea_water_surface__elevation` (The 2-Way Input)

This is the variable that makes 2-way coupling possible. Without it, rivers in WRF-Hydro don't "know" that the ocean is pushing water upstream during a storm surge.

```
Without 2-Way Coupling (1-Way Only):
═══════════════════════════════════
  WRF-Hydro: "River flows to ocean at 500 m³/s"  ──────►  SCHISM receives
  WRF-Hydro: "River still flows at 500 m³/s"     ──────►  (even during surge)
  ❌ WRONG: During storm surge, ocean pushes water BACK upstream!

With 2-Way Coupling:
════════════════════
  WRF-Hydro: "River flows at 500 m³/s"     ──────►  SCHISM receives
  SCHISM: "Ocean level +2m at river mouth"  ◄──────  SCHISM sends back
  WRF-Hydro: "Backwater! Flow reduced to 200 m³/s" ──────► SCHISM receives
  ✅ RIGHT: Captures storm surge backwater effects!
```

### 📊 Input Variable Access — How `set_value` Works

```
When PyMT calls set_value("sea_water_surface__elevation", eta2_from_schism):

  1. BMI wrapper receives the 1D array of water levels
  2. Maps SCHISM coastal nodes → WRF-Hydro channel reach endpoints
     (grid mapping done by PyMT, not by us)
  3. Modifies downstream boundary condition in rt_domain(1)
     Specifically: adjusts sfcheadrt at coastal boundary cells
  4. Next update() call uses these modified boundary conditions
     Result: Reduced discharge when ocean level is high (backwater)

🧠 ML Analogy: Like injecting external embeddings into a model
   set_value = model.encoder.set_external_context(schism_output)
```

---

## 5. 🔗 The Key Coupling Variable: `Q_bnd_source`

### 🎯 What Is `Q_bnd_source`?

`Q_bnd_source` is **SCHISM's BMI input variable** that receives river discharge from WRF-Hydro. It is the single most critical variable for coupling these two models. Think of it as the "handshake point" where WRF-Hydro's output becomes SCHISM's input.

```
┌──────────────────────┐                    ┌──────────────────────┐
│     WRF-HYDRO        │                    │       SCHISM         │
│                      │                    │                      │
│  QLINK(:,2)          │   grid mapping    │  Q_bnd_source        │
│  (streamflow at      │ ═══════════════►  │  (discharge into     │
│   2.7M NWM reaches)  │   by PyMT        │   ocean mesh at      │
│                      │                    │   source elements)   │
│  CSDMS name:         │                    │                      │
│  channel_water__     │                    │  Stored in:          │
│  volume_flow_rate    │                    │  ath3(:,1,1:2,1)     │
│                      │                    │  (t0/t1 slots)       │
└──────────────────────┘                    └──────────────────────┘
```

### 🔧 How the Data Flows (Step by Step)

```
Step 1: WRF-Hydro update()
        ├── Runs land surface + routing physics
        └── Produces QLINK(:,2) = streamflow at all channel reaches

Step 2: PyMT calls wrfhydro.get_value("channel_water__volume_flow_rate")
        ├── BMI wrapper reads rt_domain(1)%QLINK(:,2)
        ├── Returns 1D array of size NLINKS
        └── Values in m³/s

Step 3: PyMT Grid Mapping
        ├── WRF-Hydro has NLINKS reaches (e.g., 50 for Croton, 2.7M for NWM)
        ├── SCHISM has nsources_bmi source elements (e.g., 5–50 river mouths)
        ├── Spatial mapping: which WRF-Hydro reaches drain into which SCHISM elements?
        ├── Aggregation: sum all upstream reaches that contribute to each ocean source point
        └── Result: mapped_Q array of size nsources_bmi

Step 4: PyMT calls schism.set_value("Q_bnd_source", mapped_Q)
        ├── SCHISM BMI receives the array
        ├── Slides old t1 → t0 (the t0/t1 pattern, see Section 8)
        ├── Stores new values in t1 slot: ath3(:,1,2,1) = mapped_Q
        └── SCHISM will interpolate between t0 and t1 during its fine timesteps

Step 5: SCHISM update()
        ├── Uses interpolated discharge as source term in hydrodynamic equations
        ├── Fresh water enters ocean at source elements
        └── Affects water level, salinity, currents near river mouths
```

### ⚡ Why `Q_bnd_source` and Not Just "discharge"?

SCHISM's BMI uses its own custom names, NOT CSDMS Standard Names:

| What We Call It | What SCHISM BMI Calls It | CSDMS Standard Name |
|----------------|--------------------------|---------------------|
| Streamflow | `Q_bnd_source` | `channel_water__volume_flow_rate` |
| Water level output | `ETA2` | `sea_water_surface__elevation` |
| Water level boundary | `ETA2_bnd` | (no standard assigned) |

> ⚠️ **Important Design Decision:** Our WRF-Hydro BMI will use **proper CSDMS Standard Names** from the start (e.g., `channel_water__volume_flow_rate`), even though SCHISM BMI uses custom names. PyMT handles the name translation between models during coupling.

### 📐 Grid Mismatch Challenge

```
WRF-Hydro Grid 2 (channel network):
  ┌─ 50 reaches (Croton NY) or 2.7M reaches (NWM)
  ├─ Each reach has: QLINK (discharge), HLINK (depth), lat/lon
  ├─ Tree structure: FROM_NODE → TO_NODE connectivity
  └─ BMI grid type: "vector" (1D network)

SCHISM Grid 4 (source elements):
  ┌─ nsources_bmi source points (5–50 river mouths)
  ├─ Each point is a mesh element (triangle/quad) in the ocean
  ├─ Located at river-ocean interface
  └─ BMI grid type: "points" (no connectivity)

Grid Mapping (done by PyMT, NOT by our BMI):
  ┌─ Many-to-one: multiple WRF-Hydro reaches → one SCHISM source element
  ├─ Spatial: find WRF-Hydro reaches nearest to each SCHISM source point
  ├─ Aggregation: typically sum or take the terminal reach discharge
  └─ Method: PyMT's InMemoryGridMapper with nearest-neighbor or weighted
```

---

## 6. ↔️ 2-Way Coupling Architecture (WRF-Hydro ⟺ SCHISM)

### 🌊 Why 2-Way Coupling Matters

Real-world compound flooding happens when **river flooding AND coastal storm surge collide**. 1-way coupling misses the interaction.

```
🧠 ML Analogy:
  1-Way = Teacher Forcing: Model A's output feeds Model B, but B never feeds back
  2-Way = Full Sequence-to-Sequence: Both models inform each other at every step

  1-Way: WRF-Hydro → SCHISM  (rivers push water into ocean)
  2-Way: WRF-Hydro ⟺ SCHISM  (rivers push, AND ocean pushes back)
```

### 📊 2-Way Coupling — Complete Variable Flow

```
╔═══════════════════════════════════════════════════════════════════╗
║                    2-WAY COUPLING LOOP                           ║
║                                                                   ║
║   ┌──────────────┐         Q (discharge)        ┌──────────────┐ ║
║   │              │ ════════════════════════════► │              │ ║
║   │  WRF-HYDRO   │                               │    SCHISM    │ ║
║   │              │ ◄════════════════════════════ │              │ ║
║   │  Hydrology   │        ETA2 (water level)     │  Coastal     │ ║
║   │  + Routing   │                               │  Ocean       │ ║
║   └──────────────┘                               └──────────────┘ ║
║                                                                   ║
║   OUTPUT from WRF-Hydro:                                         ║
║   ├── channel_water__volume_flow_rate (QLINK, m³/s)             ║
║   └── → mapped to SCHISM's Q_bnd_source                         ║
║                                                                   ║
║   OUTPUT from SCHISM:                                            ║
║   ├── sea_water_surface__elevation (ETA2, m)                    ║
║   └── → mapped to WRF-Hydro's coastal boundary condition        ║
║                                                                   ║
║   Per coupling timestep (e.g., every 1 hour):                    ║
║   1. WRF-Hydro.update()           ← run 1 hour of hydrology    ║
║   2. get_value(Q) from WRF-Hydro  ← extract streamflow         ║
║   3. Grid map Q → Q_bnd_source    ← PyMT spatial mapping       ║
║   4. set_value(Q) into SCHISM     ← inject river discharge     ║
║   5. SCHISM.update()              ← run 1 hour of ocean        ║
║   6. get_value(ETA2) from SCHISM  ← extract water levels       ║
║   7. Grid map ETA2 → boundary     ← PyMT spatial mapping       ║
║   8. set_value(ETA2) into WRF-Hydro ← inject coastal levels   ║
║   9. Repeat from Step 1                                          ║
╚═══════════════════════════════════════════════════════════════════╝
```

### 🔀 Coupling Variables Summary Table

| Direction | WRF-Hydro Side | CSDMS Standard Name | SCHISM Side | Units | Status |
|-----------|---------------|---------------------|-------------|-------|--------|
| WRF-Hydro → SCHISM | `QLINK(:,2)` (output) | `channel_water__volume_flow_rate` | `Q_bnd_source` (input) | m³/s | ✅ Architecturally ready |
| SCHISM → WRF-Hydro | coastal boundary (input) | `sea_water_surface__elevation` | `ETA2` (output) | m | 🔧 Needs implementation |
| (Future) SCHISM → WRF-Hydro | coastal velocity (input) | `sea_water__x_velocity` | `VX` (output) | m/s | 📋 Planned |
| (Future) WRF-Hydro → SCHISM | water temp (output) | `land_surface_water__temperature` | (temp tracer input) | K | 📋 Planned |

### 🔧 What Needs to Be Built for 2-Way Coupling

**In our WRF-Hydro BMI (this project):**

1. ✅ `get_value("channel_water__volume_flow_rate")` — Extract QLINK (1-way direction)
2. 🔧 `set_value("sea_water_surface__elevation")` — Accept ETA2 from SCHISM (2-way direction)
3. 🔧 Internal logic to apply received coastal water levels as downstream boundary conditions in the routing module
4. 🔧 New input variable registration in `get_input_var_names()`

**In SCHISM BMI (already exists in LynkerIntel repo):**

5. ✅ `set_value("Q_bnd_source")` — Already accepts discharge (1-way direction)
6. ✅ `get_value("ETA2")` — Already exports water levels (2-way direction)

**In PyMT / coupling script:**

7. 🔧 Grid mapping configuration: WRF-Hydro channel reaches ↔ SCHISM source elements
8. 🔧 Grid mapping configuration: SCHISM boundary nodes ↔ WRF-Hydro coastal cells
9. 🔧 Time synchronization: align 1-hour WRF-Hydro steps with SCHISM's finer steps
10. 🔧 Unit checking: ensure m³/s and m are consistent

### ⏰ Time Synchronization for 2-Way Coupling

```
Timeline showing how both models advance:

WRF-Hydro (dt=3600s):  |─────────────|─────────────|─────────────|
                        t=0          t=3600        t=7200        t=10800

SCHISM (dt=120s):       |──|──|──|──|──|──|──|──|──|──|──|──|──|──|──|──|
                        t=0                t=3600              t=7200

Sync Points:            ↕                 ↕                   ↕
                     Exchange           Exchange            Exchange
                     Q + ETA2           Q + ETA2            Q + ETA2

Between sync points:
  - WRF-Hydro runs 1 big step (3600s)
  - SCHISM runs 30 small steps (30 × 120s = 3600s)
  - SCHISM interpolates Q between t0 and t1 during its small steps
  - WRF-Hydro uses the most recent ETA2 as boundary condition
```

---

## 7. 🗺️ Grid Types & Spatial Architecture

### 🌐 WRF-Hydro's 3-Grid System

WRF-Hydro uniquely operates on **3 simultaneous grids** at different resolutions. This is one of the biggest differences from SCHISM (which uses 1 grid).

```
🧠 ML Analogy:
  Grid 0 (1km)    = Low-resolution feature map (like a 7×7 feature map in ResNet)
  Grid 1 (250m)   = High-resolution feature map (like a 28×28 feature map)
  Grid 2 (network) = Graph neural network nodes (like edges in a GNN)

  Disaggregation (1km→250m) = Upsampling / interpolation
  Aggregation (250m→1km)    = Average pooling / downsampling
```

### 📋 Grid 0 — Noah-MP Land Surface Grid (1km)

| Property | Value | BMI Function |
|----------|-------|-------------|
| **Grid ID** | 0 | - |
| **BMI Type** | `uniform_rectilinear` | `get_grid_type(0)` |
| **Rank** | 2 | `get_grid_rank(0)` |
| **Shape** | [JX, IX] (e.g., [15, 16] for Croton) | `get_grid_shape(0)` |
| **Size** | JX × IX (e.g., 240 cells) | `get_grid_size(0)` |
| **Spacing** | [1000.0, 1000.0] meters | `get_grid_spacing(0)` |
| **Origin** | [south_lat, west_lon] from geo_em | `get_grid_origin(0)` |
| **Variables** | SMOIS, SNEQV, ACCET, T2, SFCRUNOFF, UGDRNOFF, ZWT, SNOWH, HFX, LH | - |

```
Grid 0 Layout (Croton NY example):
  ┌────────────────────────────────────┐
  │  ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪│  ← 16 columns (IX)
  │  ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪│     15 rows (JX)
  │  ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪│     1km spacing
  │  . . . . . . . . . . . . . . . .│
  │  ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪ ▪│     Each ▪ = 1 km² cell
  └────────────────────────────────────┘     Total: 240 cells

  Each cell computes: soil moisture, snow, ET, temperature, runoff
```

### 📋 Grid 1 — Terrain Routing Grid (250m)

| Property | Value | BMI Function |
|----------|-------|-------------|
| **Grid ID** | 1 | - |
| **BMI Type** | `uniform_rectilinear` | `get_grid_type(1)` |
| **Rank** | 2 | `get_grid_rank(1)` |
| **Shape** | [JXRT, IXRT] = [JX×4, IX×4] (e.g., [60, 64]) | `get_grid_shape(1)` |
| **Size** | JXRT × IXRT (e.g., 3,840 cells) | `get_grid_size(1)` |
| **Spacing** | [250.0, 250.0] meters | `get_grid_spacing(1)` |
| **Origin** | Same as Grid 0 (aligned) | `get_grid_origin(1)` |
| **Variables** | sfcheadrt, INFXSRT, soldrain | - |
| **Disaggregation Factor** | AGGFACTRT = 4 (each 1km cell = 4×4 = 16 routing cells) | - |

```
Grid 0 → Grid 1 Disaggregation:
  ┌─────┐     ┌──┬──┬──┬──┐
  │     │     │  │  │  │  │
  │ 1km │ ──► ├──┼──┼──┼──┤    1 LSM cell = 16 routing cells
  │     │     │  │  │  │  │    Each routing cell = 250m × 250m
  │     │     ├──┼──┼──┼──┤
  └─────┘     │  │  │  │  │
              ├──┼──┼──┼──┤
              │  │  │  │  │
              └──┴──┴──┴──┘
```

### 📋 Grid 2 — Channel Routing Network (Vector)

| Property | Value | BMI Function |
|----------|-------|-------------|
| **Grid ID** | 2 | - |
| **BMI Type** | `vector` (1D network) | `get_grid_type(2)` |
| **Rank** | 1 | `get_grid_rank(2)` |
| **Shape** | [NLINKS] (e.g., 50 for Croton, 2.7M for NWM) | `get_grid_shape(2)` — returns shape |
| **Size** | NLINKS | `get_grid_size(2)` |
| **Spacing** | ❌ BMI_FAILURE (irregular spacing) | `get_grid_spacing(2)` |
| **Origin** | ❌ BMI_FAILURE (no single origin) | `get_grid_origin(2)` |
| **X coordinates** | Longitude of each reach centroid | `get_grid_x(2)` |
| **Y coordinates** | Latitude of each reach centroid | `get_grid_y(2)` |
| **Variables** | QLINK, HLINK, velocity, CVOL | - |
| **Connectivity** | FROM_NODE(:) → TO_NODE(:) | `get_grid_edge_nodes(2)` |

```
Grid 2 Layout (schematic channel network):

         ●──────●──────●          ● = Node (channel reach endpoint)
         │      │      │          ─ = Edge (channel reach segment)
         ▼      ▼      ▼          ▼ = Flow direction
    ●────●──────●──────●────●
                │
                ▼
           ●────●────●
                │
                ▼
                ●  ← Outlet (connects to SCHISM source element)

  Each ● has: QLINK (discharge), HLINK (depth), lat, lon
  Each segment has: CHANLEN (length), MannN (roughness), Bw (width), So (slope)
```

### 🔍 Grid Comparison: WRF-Hydro vs SCHISM

| Aspect | WRF-Hydro | SCHISM |
|--------|-----------|--------|
| **Number of grids** | 3 | 9 |
| **Grid 0 type** | `uniform_rectilinear` (1km) | `unstructured` (triangles/quads) |
| **Grid 1 type** | `uniform_rectilinear` (250m) | `points` (all elements) |
| **Grid 2 type** | `vector` (channel network) | `points` (ocean boundary) |
| **Has regular spacing?** | ✅ Yes (Grids 0 & 1) | ❌ No (all unstructured) |
| **Has shape/origin?** | ✅ Yes (Grids 0 & 1) | ❌ No (returns BMI_FAILURE) |
| **Has x/y coordinates?** | ✅ Grid 2 only (reaches) | ✅ All grids |
| **Has topology (edges/faces)?** | Partial (Grid 2 has FROM/TO_NODE) | ✅ Grid 1 (full mesh connectivity) |
| **Scalar grids?** | ❌ No | ✅ Yes (Grids 7, 8, 9 for dt and MPI) |

### 📐 Grid Functions by Grid ID — What Works and What Fails

| BMI Grid Function | Grid 0 (1km) | Grid 1 (250m) | Grid 2 (channel) |
|------------------|-------------|---------------|-------------------|
| `get_grid_type` | ✅ "uniform_rectilinear" | ✅ "uniform_rectilinear" | ✅ "vector" |
| `get_grid_rank` | ✅ 2 | ✅ 2 | ✅ 1 |
| `get_grid_size` | ✅ IX×JX | ✅ IXRT×JXRT | ✅ NLINKS |
| `get_grid_shape` | ✅ [JX, IX] | ✅ [JXRT, IXRT] | ❌ BMI_FAILURE |
| `get_grid_spacing` | ✅ [1000, 1000] | ✅ [250, 250] | ❌ BMI_FAILURE |
| `get_grid_origin` | ✅ [lat, lon] | ✅ [lat, lon] | ❌ BMI_FAILURE |
| `get_grid_x` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ✅ lon array |
| `get_grid_y` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ✅ lat array |
| `get_grid_z` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ✅ elev array |
| `get_grid_node_count` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ✅ NLINKS |
| `get_grid_edge_count` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ✅ NLINKS-1 |
| `get_grid_face_count` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ❌ BMI_FAILURE |
| `get_grid_edge_nodes` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ✅ FROM/TO_NODE |
| `get_grid_face_nodes` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ❌ BMI_FAILURE |
| `get_grid_face_edges` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ❌ BMI_FAILURE |
| `get_grid_nodes_per_face` | ❌ BMI_FAILURE | ❌ BMI_FAILURE | ❌ BMI_FAILURE |

> 💡 **Key insight:** Grids 0 & 1 are simple — BMI provides shape/spacing/origin and that's enough to reconstruct the full coordinate system. Grid 2 is the complex one — it needs explicit x/y/z coordinates and edge connectivity.

---

## 8. ⏱️ The t0/t1 Sliding Window Pattern

### 🎯 What Is the t0/t1 Pattern?

The t0/t1 sliding window is a **temporal interpolation technique** used when two models run at different timestep sizes. It ensures smooth data transitions instead of abrupt jumps.

```
🧠 ML Analogy:
  t0/t1 = Linear interpolation between keyframes in animation
          OR: Learning rate warmup that smoothly transitions between values
          OR: Exponential moving average (EMA) of model weights

  Problem: Model A updates every 3600s, Model B needs data every 120s
  Solution: Store TWO snapshots (t0 old, t1 new), interpolate in between
```

### 🔄 How SCHISM Uses t0/t1 (Reference Pattern)

SCHISM runs at fine timesteps (120–300s) but receives forcing data at coarser intervals (hourly). To avoid abrupt discontinuities:

```
                    ┌── t0 (old) ──────── interpolation ──────── t1 (new) ──┐
                    │                                                        │
Forcing timeline:   ●════════════════════════════════════════════════════════●
                  Q=500 m³/s                                            Q=600 m³/s
                    │                                                        │
SCHISM steps:       │──│──│──│──│──│──│──│──│──│──│──│──│──│──│──│──│──│──│──│
                    ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑  ↑
                   500 505 510 516 521 527 532 537 543 548 553 558 563 568 574...600

                    Linear interpolation: Q(t) = t0_val + (t - t0_time)/(t1_time - t0_time) × (t1_val - t0_val)
```

### 📦 SCHISM's t0/t1 Variable Pairs

Every forcing variable in SCHISM BMI stores TWO time snapshots:

| BMI Variable | t0 Array (previous) | t1 Array (current) | Description |
|-------------|---------------------|---------------------|-------------|
| `Q_bnd_source` | `ath3(:,1,1,1)` | `ath3(:,1,2,1)` | River discharge |
| `Q_bnd_sink` | `ath3(:,1,1,2)` | `ath3(:,1,2,2)` | Water extraction |
| `ETA2_bnd` | `ath2(:,:,:,1,:)` | `ath2(:,:,:,2,:)` | Ocean boundary levels |
| `SFCPRS` | `pr1(:)` | `pr2(:)` | Surface pressure |
| `TMP2m` | `airt1(:)` | `airt2(:)` | Air temperature |
| `U10m` | `windx1(:)` | `windx2(:)` | Wind speed (east) |
| `V10m` | `windy1(:)` | `windy2(:)` | Wind speed (north) |
| `SPFH2m` | `shum1(:)` | `shum2(:)` | Humidity |

### 🔀 The Slide Mechanism (What Happens at Each `set_value` Call)

```
When set_value("Q_bnd_source", new_data) is called:

  BEFORE:
    t0 slot: ath3(:,1,1,1) = [400, 300, 250]  ← "old" values
    t1 slot: ath3(:,1,2,1) = [500, 350, 280]  ← "current" values (about to become old)

  SLIDE OPERATION:
    Step 1: Copy t1 → t0     ath3(:,1,1,1) = ath3(:,1,2,1)    ← old = current
    Step 2: Store new in t1   ath3(:,1,2,1) = new_data          ← current = new

  AFTER:
    t0 slot: ath3(:,1,1,1) = [500, 350, 280]  ← was t1, now t0
    t1 slot: ath3(:,1,2,1) = [600, 400, 320]  ← fresh data from WRF-Hydro

  BETWEEN set_value calls, SCHISM interpolates:
    At internal timestep t: Q(t) = Q_t0 + fraction × (Q_t1 - Q_t0)
    where fraction = (t - t0_time) / (t1_time - t0_time)
```

### 🤔 Does WRF-Hydro BMI Need t0/t1?

**For WRF-Hydro's OWN OUTPUTS:** ❌ No.

WRF-Hydro runs at coarser timesteps (1 hour) than SCHISM. When PyMT calls `get_value("channel_water__volume_flow_rate")`, it gets the instantaneous streamflow at the END of the current timestep. The interpolation (if needed) happens on the SCHISM side or in the PyMT coupling layer.

**For WRF-Hydro's INPUTS (2-way coupling):** 🤔 Depends.

| Scenario | Need t0/t1? | Reason |
|----------|-------------|--------|
| WRF-Hydro receives ETA2 at every coupling step | ❌ No | WRF-Hydro uses fixed boundary per step |
| WRF-Hydro has sub-cycling (routing dt < coupling dt) | 🟡 Maybe | Sub-cycling within `update()` might benefit from interpolation |
| PyMT handles temporal interpolation | ❌ No | The framework does the interpolation, not our BMI |

### 🎯 Our Decision: Simplified Input Handling (No t0/t1 Initially)

```
WRF-Hydro BMI Input Pattern (Phase 1):
═══════════════════════════════════════

  set_value("sea_water_surface__elevation", eta2_from_schism)
    └── Simply stores the value in the boundary array
    └── Next update() uses this value AS-IS for the entire timestep
    └── No interpolation within the BMI wrapper

  Rationale:
  ├── WRF-Hydro's routing sub-cycling is INTERNAL to update()
  ├── The 3600s coupling interval is already WRF-Hydro's native timestep
  ├── Routing sub-steps (10-15s) within one hour see constant boundary
  ├── This is physically reasonable for slowly-changing coastal water levels
  └── If needed later, t0/t1 can be added WITHOUT changing the BMI interface

🧠 ML Analogy:
  Phase 1 = "Step function" learning rate schedule (constant per epoch)
  Phase 2 = "Linear warmup" learning rate schedule (smooth interpolation)
  Both use the same API (optimizer.step()), the internal behavior changes later.
```

### 🆚 t0/t1 Comparison: SCHISM vs WRF-Hydro BMI

| Aspect | SCHISM BMI | WRF-Hydro BMI (Planned) |
|--------|-----------|------------------------|
| Uses t0/t1 for inputs? | ✅ Yes (8 variables) | ❌ No (Phase 1) |
| Why? | Fine timesteps (120s) need smooth forcing | Coarse timestep (3600s) = coupling interval |
| Interpolation method | Linear between t0 and t1 | None (constant per step) |
| Slide operation in set_value? | ✅ Yes (shifts arrays) | ❌ No (direct overwrite) |
| Time control variables? | ✅ ETA2_dt, Q_dt (scalars) | ❌ Not needed |
| Can add t0/t1 later? | N/A | ✅ Yes, without API change |

---

## 9. 🆚 SCHISM BMI vs WRF-Hydro BMI — Complete Comparison

### 📊 Side-by-Side Architecture Comparison

| Aspect | SCHISM BMI (`bmischism.f90`) | WRF-Hydro BMI (`bmi_wrf_hydro.f90`) |
|--------|------------------------------|--------------------------------------|
| **File size** | 1,729 lines | ~1,500–2,000 lines (estimated) |
| **Model language** | Fortran 90/2003 | Fortran 90 |
| **BMI spec version** | BMI 2.0 | BMI 2.0 |
| **Module name** | `bmischismf` | `bmiwrfhydrof` |
| **Type name** | `bmi_schism` | `bmi_wrf_hydro` |
| **Component name** | "SCHISM" | "WRF-Hydro v5.4.0" |
| **Target framework** | NOAA NextGen | CSDMS PyMT (+ NextGen later) |
| **Variable naming** | ❌ Custom names (Q_bnd_source) | ✅ CSDMS Standard Names |
| **Number of grids** | 9 | 3 |
| **Primary grid type** | Unstructured (triangles) | Uniform rectilinear (regular) |
| **Input variables** | 12 | 4 (initially) |
| **Output variables** | 5 | 8 (initially) |
| **Has IRF natively?** | ✅ Yes (init0/step0/finalize0) | ❌ No (must decompose) |
| **MPI support** | ✅ Built-in | ❌ Serial only (Phase 1) |
| **t0/t1 pattern** | ✅ Used for 8 input vars | ❌ Not needed (Phase 1) |
| **Time unit** | "s" (seconds) | "s" (seconds) |
| **Typical dt** | 120–300s | 3600s |
| **get_value_ptr** | ❌ Returns BMI_FAILURE | 🟡 Planned (via c_loc/c_f_pointer) |
| **Babelizer pathway** | ❌ Not done (NextGen only) | ✅ Planned (babel.toml → pymt_wrfhydro) |

### 🏗️ Implementation Approach Comparison

```
SCHISM BMI — "Inline Wiring" Approach:
══════════════════════════════════════
  ├── 3 source files modified with #ifdef USE_NWM_BMI (5 code blocks)
  ├── Minimal changes to existing code
  ├── BUT: the #ifdef blocks are NOT a full 41-function BMI
  │        They are "BMI-ready plumbing" for data I/O
  ├── The actual BMI wrapper (bmischism.f90) is a SEPARATE file
  │   written by LynkerIntel for NOAA NextGen
  └── Works because SCHISM already had clean IRF separation

WRF-Hydro BMI — "External Wrapper" Approach:
═════════════════════════════════════════════
  ├── 0 source files modified (purely non-invasive)
  ├── One new file: bmi_wrf_hydro.f90
  ├── Wrapper calls existing subroutines via USE statements
  ├── IRF decomposition done IN the wrapper, not in WRF-Hydro
  │   (the wrapper controls which subroutines to call and when)
  └── Must work because WRF-Hydro lacks clean IRF separation
```

### 🔀 Variable Naming Philosophy

```
SCHISM BMI (custom names):
  Input:  Q_bnd_source, Q_bnd_sink, ETA2_bnd, SFCPRS, TMP2m...
  Output: ETA2, VX, VY, TROUTE_ETA2, BEDLEVEL

  ❌ Problem: Not CSDMS-compatible, can't use PyMT standard name matching
  ❌ Problem: Other BMI models won't recognize these names

WRF-Hydro BMI (CSDMS Standard Names):
  Output: channel_water__volume_flow_rate, land_surface_water__depth,
          soil_water__volume_fraction, snowpack__liquid-equivalent_depth...
  Input:  atmosphere_water__precipitation_leq-volume_flux,
          sea_water_surface__elevation...

  ✅ Benefit: PyMT auto-matches coupled variables by standard name
  ✅ Benefit: Any BMI model using CSDMS names can couple automatically
  ✅ Benefit: Follows CSDMS community standards (discoverable, documented)
```

### 🗺️ Grid Architecture Comparison

```
SCHISM: 9 Grids, Mostly Points/Scalar
══════════════════════════════════════
  Grid 1: unstructured (full mesh, triangles+quads, the BIG one)
  Grid 2: points (all elements)
  Grid 3: points (ocean boundary)
  Grid 4: points (source elements)      ← Where Q_bnd_source lives
  Grid 5: points (sink elements)
  Grid 6: points (monitoring stations)
  Grid 7: scalar (ETA2 timestep)
  Grid 8: scalar (Q timestep)
  Grid 9: scalar (MPI communicator)

  Supports: get_grid_x/y/z, node/edge/face counts, connectivity (Grid 1 only)
  Fails: get_grid_shape/spacing/origin (all grids, unstructured)

WRF-Hydro: 3 Grids, 2 Regular + 1 Network
═══════════════════════════════════════════
  Grid 0: uniform_rectilinear (1km, Noah-MP)   ← Land surface variables
  Grid 1: uniform_rectilinear (250m, routing)   ← Terrain routing variables
  Grid 2: vector (channel network)              ← Streamflow (coupling var)

  Supports: get_grid_shape/spacing/origin (Grids 0 & 1), get_grid_x/y (Grid 2)
  Fails: get_grid_face_nodes/edges (all grids, not needed)

Key Differences:
  ├── SCHISM has MORE grids (9 vs 3) but most are simple "points"
  ├── WRF-Hydro has FEWER grids but they are richer (regular grids have shape/spacing)
  ├── SCHISM's Grid 1 is the most complex (full unstructured mesh topology)
  ├── WRF-Hydro's Grid 2 is moderately complex (network with FROM/TO_NODE)
  └── WRF-Hydro's Grids 0 & 1 are the SIMPLEST (regular grid = just shape + spacing)
```

### ⏰ Time Handling Comparison

| Time Aspect | SCHISM BMI | WRF-Hydro BMI |
|-------------|-----------|---------------|
| Timestep (dt) | 120–300s (fine) | 3600s (1 hour) |
| Time unit | "s" | "s" |
| Start time | 0.0 | 0.0 |
| End time | ndays × 86400 | NTIME × dt |
| Sub-cycling? | ❌ No (single physics) | ✅ Yes (routing: 10–300s within 3600s) |
| update_until? | Loops update() | Loops update() |
| Time control scalars? | ✅ ETA2_dt, Q_dt | ❌ Not needed |

### 🔗 Coupling Direction Comparison

| Direction | SCHISM BMI | WRF-Hydro BMI |
|-----------|-----------|---------------|
| **Accepts discharge (from WRF-Hydro)** | ✅ Q_bnd_source (set_value) | N/A (WRF-Hydro IS the source) |
| **Exports discharge** | ❌ (not a hydrology model) | ✅ channel_water__volume_flow_rate (get_value) |
| **Exports water level** | ✅ ETA2 (get_value) | ❌ (not an ocean model) |
| **Accepts water level (from SCHISM)** | N/A (SCHISM IS the source) | 🔧 sea_water_surface__elevation (set_value, to be built) |
| **Accepts atmospheric forcing** | ✅ 6 variables (set_value) | 🔧 2 variables (set_value, planned) |

---

## 10. 📦 All 41 BMI Functions — Detailed Breakdown

### 📊 Function Count Summary

| Category | Count | Implementation Complexity | Notes |
|----------|-------|--------------------------|-------|
| 🔧 Control | 4 | 🔴 HIGH (IRF decomposition) | The hardest part |
| ℹ️ Model Info | 5 | 🟢 LOW (return constants) | Simple string/int returns |
| 📋 Variable Info | 6 | 🟡 MEDIUM (select case dispatch) | One function per property |
| ⏰ Time | 5 | 🟢 LOW (return counters) | Simple arithmetic |
| 📦 Get/Set Values | 6 (×3 types = 18) | 🟡 MEDIUM (array handling) | reshape + copy |
| 🗺️ Grid | 17 | 🟡 MEDIUM (3 grids × select case) | Most return BMI_FAILURE |
| **TOTAL** | **41 (55 with type variants)** | | |

> 📌 **Note on counting:** BMI 2.0 abstract interface has 53 deferred procedures (because `get_value`, `set_value`, etc. have `_int`, `_float`, `_double` variants). The conceptual 41 unique functions expand to 55 when counting all type variants. We implement ALL 55.

### 🔧 Category 1: Control Functions (4) — 🔴 HIGH complexity

These are the heart of the BMI wrapper. They control the model lifecycle.

| # | Function | Signature | Returns | WRF-Hydro Mapping |
|---|----------|-----------|---------|-------------------|
| 1 | `initialize` | `(self, config_file)` | `BMI_SUCCESS` / `BMI_FAILURE` | Parse config → `land_driver_ini()` → `HYDRO_ini()` → set t=0, itime=0 |
| 2 | `update` | `(self)` | `BMI_SUCCESS` / `BMI_FAILURE` | itime++ → `land_driver_exe(itime, state)` → t = t + dt |
| 3 | `update_until` | `(self, time)` | `BMI_SUCCESS` / `BMI_FAILURE` | Loop: call `update()` while t < target_time |
| 4 | `finalize` | `(self)` | `BMI_SUCCESS` / `BMI_FAILURE` | `HYDRO_finish()` → deallocate → close files |

**Complexity details:**
- `initialize` is ~200 lines: must parse config, call 2 init subroutines, set up variable name dictionaries, populate grid metadata
- `update` is ~30 lines: increment counter, call 1 subroutine (which internally calls HYDRO_exe), update time
- `update_until` is ~10 lines: simple while loop
- `finalize` is ~30 lines: call cleanup, deallocate any BMI-allocated memory

### ℹ️ Category 2: Model Info Functions (5) — 🟢 LOW complexity

| # | Function | Returns for WRF-Hydro |
|---|----------|-----------------------|
| 5 | `get_component_name` | "WRF-Hydro v5.4.0" |
| 6 | `get_input_item_count` | 4 (Phase 1: RAINRATE, T2, ETA2, sea_velocity) |
| 7 | `get_output_item_count` | 8 (Phase 1: QLINK, sfcheadrt, SMOIS, SNEQV, ACCET, SFCRUNOFF, UGDRNOFF, T2) |
| 8 | `get_input_var_names` | Array of 4 CSDMS standard name strings |
| 9 | `get_output_var_names` | Array of 8 CSDMS standard name strings |

### 📋 Category 3: Variable Info Functions (6) — 🟡 MEDIUM complexity

Each function takes a variable name (CSDMS standard name) and returns a property. Uses `select case(name)` dispatch.

| # | Function | Example: QLINK | Example: SMOIS | Example: RAINRATE |
|---|----------|---------------|----------------|-------------------|
| 10 | `get_var_type` | "double" | "double" | "double" |
| 11 | `get_var_units` | "m3 s-1" | "1" | "mm s-1" |
| 12 | `get_var_grid` | 2 | 0 | 0 |
| 13 | `get_var_itemsize` | 8 | 8 | 8 |
| 14 | `get_var_nbytes` | NLINKS × 8 | IX×JX×NSOIL × 8 | IX×JX × 8 |
| 15 | `get_var_location` | "node" | "node" | "node" |

> 💡 All WRF-Hydro variables are `double` precision. `get_var_itemsize` is always 8 bytes. `get_var_location` is always "node" (cell-centered in BMI terminology).

### ⏰ Category 4: Time Functions (5) — 🟢 LOW complexity

| # | Function | Returns | Formula |
|---|----------|---------|---------|
| 16 | `get_current_time` | Current model time | `self%t` (starts at 0.0, increments by dt) |
| 17 | `get_start_time` | 0.0 | Always 0.0 (BMI convention) |
| 18 | `get_end_time` | Total simulation time | `self%ntime * self%dt` |
| 19 | `get_time_step` | 3600.0 | `self%dt` (from namelist) |
| 20 | `get_time_units` | "s" | Always "s" (seconds) |

### 📦 Category 5: Get/Set Value Functions (6 × 3 types = 18) — 🟡 MEDIUM complexity

Each function has `_int`, `_float`, `_double` variants. WRF-Hydro uses almost exclusively `double`, so `_int` and `_float` variants return `BMI_FAILURE`.

| # | Function | What It Does | Array Handling |
|---|----------|-------------|----------------|
| 21-23 | `get_value` (int/float/double) | Copy variable to caller's array | 2D/3D → reshape to 1D → copy |
| 24-26 | `set_value` (int/float/double) | Copy caller's array into variable | 1D → reshape to 2D/3D → store |
| 27-29 | `get_value_ptr` (int/float/double) | Return pointer (zero-copy) | `c_loc()` → `c_f_pointer()` |
| 30-32 | `get_value_at_indices` (int/float/double) | Get specific elements only | Index into 1D representation |
| 33-35 | `set_value_at_indices` (int/float/double) | Set specific elements only | Index into 1D representation |
| 36 | (additional type variants) | | Total: 18 procedure bindings |

**Key implementation patterns:**

```
get_value("channel_water__volume_flow_rate"):
  ├── Locate: rt_domain(1)%QLINK(:,2)     ← 1D array, NLINKS elements
  ├── Copy: dest(1:NLINKS) = QLINK(1:NLINKS, 2)
  └── Return BMI_SUCCESS

get_value("soil_water__volume_fraction"):
  ├── Locate: SMOIS(:,:,:)                 ← 3D array (IX, JX, NSOIL)
  ├── Flatten: reshape(SMOIS, [IX*JX*NSOIL])
  ├── Copy: dest(1:IX*JX*NSOIL) = flattened
  └── Return BMI_SUCCESS

set_value("sea_water_surface__elevation"):
  ├── Receive: 1D array of coastal water levels
  ├── Store in coastal boundary condition array
  ├── Next update() will use these values
  └── Return BMI_SUCCESS
```

### 🗺️ Category 6: Grid Functions (17) — 🟡 MEDIUM complexity

Each function takes a grid ID and returns grid metadata. Uses `select case(grid_id)` dispatch across 3 grids.

| # | Function | Grid 0 (1km) | Grid 1 (250m) | Grid 2 (channel) |
|---|----------|-------------|---------------|-------------------|
| 37 | `get_grid_type` | "uniform_rectilinear" | "uniform_rectilinear" | "vector" |
| 38 | `get_grid_rank` | 2 | 2 | 1 |
| 39 | `get_grid_size` | IX × JX | IXRT × JXRT | NLINKS |
| 40 | `get_grid_shape` | [JX, IX] | [JXRT, IXRT] | BMI_FAILURE |
| 41 | `get_grid_spacing` | [1000.0, 1000.0] | [250.0, 250.0] | BMI_FAILURE |
| 42 | `get_grid_origin` | [lat0, lon0] | [lat0, lon0] | BMI_FAILURE |
| 43 | `get_grid_x` | BMI_FAILURE | BMI_FAILURE | lon(:) |
| 44 | `get_grid_y` | BMI_FAILURE | BMI_FAILURE | lat(:) |
| 45 | `get_grid_z` | BMI_FAILURE | BMI_FAILURE | elev(:) |
| 46 | `get_grid_node_count` | BMI_FAILURE | BMI_FAILURE | NLINKS |
| 47 | `get_grid_edge_count` | BMI_FAILURE | BMI_FAILURE | NLINKS - 1 |
| 48 | `get_grid_face_count` | BMI_FAILURE | BMI_FAILURE | BMI_FAILURE |
| 49 | `get_grid_edge_nodes` | BMI_FAILURE | BMI_FAILURE | FROM/TO_NODE |
| 50 | `get_grid_face_nodes` | BMI_FAILURE | BMI_FAILURE | BMI_FAILURE |
| 51 | `get_grid_face_edges` | BMI_FAILURE | BMI_FAILURE | BMI_FAILURE |
| 52 | `get_grid_nodes_per_face` | BMI_FAILURE | BMI_FAILURE | BMI_FAILURE |
| 53 | (additional grid helpers) | | | |

### 📊 BMI Function Implementation Status Matrix

```
Legend: ✅ = Returns data | ❌ = Returns BMI_FAILURE | 🟡 = Returns constant

Category               Total  Working  BMI_FAILURE  Notes
═══════════════════════════════════════════════════════════════
Control (4)              4      4         0          All must work
Model Info (5)           5      5         0          All return constants
Variable Info (6)        6      6         0          All use select case
Time (5)                 5      5         0          All return numbers
Get/Set Values (18)     18      6        12          Only _double works
Grid (17)               17      ~9        ~8         Depends on grid ID
═══════════════════════════════════════════════════════════════
TOTAL                   55     ~35       ~20

Of the ~20 BMI_FAILURE returns:
  ├── 12 are type variants (_int, _float) that don't apply
  └── ~8 are grid functions for grid types that don't support them
```

---

## 11. 🧪 Testing Plan — Functions, Strategies, Validation

### 🎯 Testing Philosophy

```
🧠 ML Analogy:
  Unit Tests      = Testing individual layers (Linear, Conv2d work correctly)
  Integration Test = Testing the full model.forward() produces correct output
  Validation Test  = Testing against held-out test set (Croton NY baseline)
  Regression Test  = Testing that new commits don't break old results
```

### 📋 Test Suite Overview

| Test Category | Count | Framework | Description |
|---------------|-------|-----------|-------------|
| 🔬 Unit Tests (BMI functions) | 41+ | CTest / Fortran driver | Test each BMI function individually |
| 🔗 Integration Tests | 6 | Fortran driver | Test full IRF cycle + coupling |
| ✅ Validation Tests | 4 | Fortran driver + Python | Compare against standalone baseline |
| 🛡️ Edge Case Tests | 8 | CTest / Fortran driver | Error handling, invalid inputs |
| 🧮 Grid Tests | 12 | CTest | All grid functions × all grid IDs |
| **TOTAL** | **~71+** | | |

### 🔬 Unit Tests — One Per BMI Function (41+ tests)

#### Control Function Tests (4)

| Test # | Test Name | What It Validates |
|--------|-----------|-------------------|
| T01 | `test_initialize` | Calls initialize(config_file), returns BMI_SUCCESS, internal state is set up |
| T02 | `test_update` | After init, calls update(), time advances by dt, itime increments |
| T03 | `test_update_until` | Calls update_until(7200.0), verifies time = 7200.0, itime = 2 |
| T04 | `test_finalize` | After running, calls finalize(), returns BMI_SUCCESS, memory released |

#### Model Info Tests (5)

| Test # | Test Name | What It Validates |
|--------|-----------|-------------------|
| T05 | `test_component_name` | Returns "WRF-Hydro v5.4.0" |
| T06 | `test_input_item_count` | Returns 4 (or current count) |
| T07 | `test_output_item_count` | Returns 8 (or current count) |
| T08 | `test_input_var_names` | Returns array of 4 CSDMS standard name strings |
| T09 | `test_output_var_names` | Returns array of 8 CSDMS standard name strings |

#### Variable Info Tests (6 × n_variables = ~72 sub-tests)

| Test # | Test Name | What It Validates |
|--------|-----------|-------------------|
| T10 | `test_var_type` | Every variable returns "double" (or appropriate type) |
| T11 | `test_var_units` | QLINK → "m3 s-1", SMOIS → "1", etc. |
| T12 | `test_var_grid` | QLINK → 2, SMOIS → 0, sfcheadrt → 1, etc. |
| T13 | `test_var_itemsize` | Every double variable → 8 bytes |
| T14 | `test_var_nbytes` | QLINK → NLINKS×8, SMOIS → IX×JX×NSOIL×8, etc. |
| T15 | `test_var_location` | Every variable → "node" |

#### Time Function Tests (5)

| Test # | Test Name | What It Validates |
|--------|-----------|-------------------|
| T16 | `test_current_time` | After init: 0.0. After 1 update: 3600.0. After 3: 10800.0 |
| T17 | `test_start_time` | Always returns 0.0 |
| T18 | `test_end_time` | Returns NTIME × dt (e.g., 6 × 3600 = 21600 for 6-hour run) |
| T19 | `test_time_step` | Returns 3600.0 |
| T20 | `test_time_units` | Returns "s" |

#### Get/Set Value Tests (6 function groups)

| Test # | Test Name | What It Validates |
|--------|-----------|-------------------|
| T21 | `test_get_value_streamflow` | After update(), QLINK values are > 0 at some reaches, physically reasonable |
| T22 | `test_get_value_soil_moisture` | SMOIS values between 0.0 and 1.0 (physically bounded) |
| T23 | `test_get_value_snow` | SNEQV values ≥ 0.0 |
| T24 | `test_get_value_surface_water` | sfcheadrt values ≥ 0.0 |
| T25 | `test_set_value_rainfall` | Set RAINRATE, update(), verify it affected output |
| T26 | `test_set_value_coastal_elev` | Set ETA2 boundary, update(), verify boundary effect |
| T27 | `test_get_value_ptr` | get_value_ptr returns valid pointer, dereference matches get_value |
| T28 | `test_get_value_at_indices` | Get subset of streamflow (e.g., indices [1,5,10]), matches full array at those indices |
| T29 | `test_set_value_at_indices` | Set specific indices of RAINRATE, verify only those changed |
| T30 | `test_get_value_int_fails` | Calling get_value_int returns BMI_FAILURE (all vars are double) |
| T31 | `test_get_value_float_fails` | Calling get_value_float returns BMI_FAILURE |

#### Grid Function Tests (17 × 3 grids = up to 51 sub-tests)

| Test # | Test Name | What It Validates |
|--------|-----------|-------------------|
| T32 | `test_grid_type_grid0` | Returns "uniform_rectilinear" |
| T33 | `test_grid_type_grid1` | Returns "uniform_rectilinear" |
| T34 | `test_grid_type_grid2` | Returns "vector" |
| T35 | `test_grid_rank` | Grid 0 → 2, Grid 1 → 2, Grid 2 → 1 |
| T36 | `test_grid_size` | Grid 0 → IX×JX, Grid 1 → IXRT×JXRT, Grid 2 → NLINKS |
| T37 | `test_grid_shape_grid0` | Returns [JX, IX] |
| T38 | `test_grid_shape_grid1` | Returns [JXRT, IXRT] |
| T39 | `test_grid_shape_grid2_fails` | Returns BMI_FAILURE |
| T40 | `test_grid_spacing` | Grid 0 → [1000,1000], Grid 1 → [250,250], Grid 2 → FAILURE |
| T41 | `test_grid_origin` | Grid 0/1 → [lat,lon], Grid 2 → FAILURE |
| T42 | `test_grid_x_grid2` | Returns NLINKS longitude values (all valid coordinates) |
| T43 | `test_grid_y_grid2` | Returns NLINKS latitude values (all valid coordinates) |
| T44 | `test_grid_edge_nodes_grid2` | Returns FROM_NODE/TO_NODE arrays with valid node IDs |
| T45 | `test_grid_node_count_grid2` | Returns NLINKS |
| T46 | `test_grid_face_count_fails` | Returns BMI_FAILURE for all grids |

### 🔗 Integration Tests (6)

| Test # | Test Name | What It Validates |
|--------|-----------|-------------------|
| I01 | `test_full_irf_cycle` | init → 6 × update → finalize (no crashes, clean exit) |
| I02 | `test_multi_step_time` | After 6 updates: current_time = 21600.0, itime = 6 |
| I03 | `test_update_until_full` | update_until(21600.0) produces same result as 6 × update() |
| I04 | `test_output_evolves` | Streamflow changes between timesteps (model is actually running) |
| I05 | `test_reinitialize` | finalize → initialize again → works (no leftover state) |
| I06 | `test_set_then_get` | set_value(RAINRATE) → update() → get_value(SFCRUNOFF) → runoff changed |

### ✅ Validation Tests — Against Standalone Baseline (4)

The gold standard: run WRF-Hydro standalone (Croton NY, 6 hours) and via BMI, compare outputs.

| Test # | Test Name | Tolerance | What It Compares |
|--------|-----------|-----------|------------------|
| V01 | `test_streamflow_match` | < 1% relative error | QLINK values at all reaches vs standalone CHRTOUT |
| V02 | `test_soil_moisture_match` | < 1% relative error | SMOIS at all grid cells vs standalone LDASOUT |
| V03 | `test_surface_water_match` | < 1% relative error | sfcheadrt vs standalone RTOUT |
| V04 | `test_snow_match` | < 1% relative error | SNEQV vs standalone LDASOUT |

```
Validation Procedure:
═════════════════════
  Step 1: Run standalone WRF-Hydro (Croton NY, 6 hours)
          → Produces 39 output files (LDASOUT, CHRTOUT, RTOUT, etc.)
          → These are the BASELINE (already generated, in WRF_Hydro_Run_Local/run/)

  Step 2: Run BMI-wrapped WRF-Hydro (same config, 6 hours)
          → init(config) → 6 × update() → finalize()
          → After each update(), get_value() all output variables

  Step 3: Compare
          → For each output variable:
             relative_error = abs(bmi_value - baseline_value) / max(abs(baseline_value), epsilon)
          → All relative errors must be < 1%
          → Exact match expected for integer fields (grid sizes, counts)

  Expected result: EXACT match (bit-for-bit) if our wrapper correctly delegates
  to the same subroutines. Any difference indicates a wrapper bug.
```

### 🛡️ Edge Case Tests (8)

| Test # | Test Name | What It Tests |
|--------|-----------|---------------|
| E01 | `test_invalid_var_name` | get_var_type("nonexistent_variable") → BMI_FAILURE |
| E02 | `test_invalid_grid_id` | get_grid_type(99) → BMI_FAILURE |
| E03 | `test_update_before_init` | update() without initialize() → BMI_FAILURE (graceful) |
| E04 | `test_get_before_init` | get_value() without initialize() → BMI_FAILURE |
| E05 | `test_single_step` | init → 1 update → finalize (minimal run) |
| E06 | `test_zero_rainfall` | Set RAINRATE = 0.0 everywhere → model runs without crash |
| E07 | `test_config_file_missing` | initialize("nonexistent.cfg") → BMI_FAILURE with clean error |
| E08 | `test_double_finalize` | finalize() twice → second call returns gracefully |

### 🏗️ Test Driver Structure

We will create **two test programs**:

```
1. bmi_wrf_hydro_test.f90 — Comprehensive Fortran Test Driver
   ├── ~400–600 lines
   ├── Tests all 41 BMI functions
   ├── Uses CTest framework (like bmi-example-fortran)
   ├── Runs against Croton NY test case
   ├── Reports: PASS/FAIL for each test
   └── Validates against standalone baseline

2. test_coupling_mock.f90 — Coupling Simulation Test
   ├── ~200 lines
   ├── Simulates 2-way coupling WITHOUT actual SCHISM
   ├── Mock SCHISM: provides fake ETA2 values via set_value
   ├── Tests: get_value(Q) → transform → set_value(ETA2) → update → repeat
   └── Validates: model runs, values change, no crashes
```

### 📊 Test Execution Plan

```
Phase A: Build Tests (CMake)
  ├── cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX
  ├── cmake --build _build
  └── Creates: _build/bmi_wrf_hydro_test, _build/test_coupling_mock

Phase B: Run Unit + Integration Tests
  ├── ctest --test-dir _build (runs all registered tests)
  ├── Expected: 41+ unit tests + 6 integration + 8 edge cases = 55+ tests
  └── Target: ALL PASS (like bmi-example-fortran's 49/49)

Phase C: Run Validation Tests
  ├── ./bmi_wrf_hydro_test --validate (compares against Croton baseline)
  ├── Reads baseline from WRF_Hydro_Run_Local/run/output files
  ├── Compares: CHRTOUT (streamflow), LDASOUT (soil), RTOUT (routing)
  └── Reports: max relative error per variable, PASS if < 1%

Phase D: Memory Check
  ├── valgrind --leak-check=full ./bmi_wrf_hydro_test
  ├── No memory leaks from BMI wrapper allocations
  └── No segfaults during any test
```

---

## 12. 🧮 Summary — Numbers at a Glance

### 📊 The Complete Count

```
╔═══════════════════════════════════════════════════════════╗
║              WRF-HYDRO BMI — BY THE NUMBERS               ║
╠═══════════════════════════════════════════════════════════╣
║                                                           ║
║  📁 Files to Create:                                      ║
║     ├── bmi_wrf_hydro.f90      (BMI wrapper, ~1,500-2K)  ║
║     ├── bmi_wrf_hydro_test.f90 (test driver, ~400-600)   ║
║     ├── test_coupling_mock.f90 (coupling test, ~200)      ║
║     └── CMakeLists.txt          (build system additions)  ║
║     Total: 4 files, ~2,500 lines                         ║
║                                                           ║
║  📦 BMI Functions to Implement:                           ║
║     ├── Control:       4  (init, update, update_until,    ║
║     │                      finalize)                      ║
║     ├── Model Info:    5  (name, counts, var names)       ║
║     ├── Variable Info: 6  (type, units, grid, size, etc.) ║
║     ├── Time:          5  (current, start, end, step,     ║
║     │                      units)                         ║
║     ├── Get/Set:      18  (6 functions × 3 types)         ║
║     ├── Grid:         17  (type through nodes_per_face)   ║
║     └── TOTAL:        55  procedure bindings              ║
║         (41 unique concepts, 55 with type variants)       ║
║                                                           ║
║  📤 Output Variables:          8  (Phase 1)               ║
║  📥 Input Variables:           4  (Phase 1, incl. 2-way)  ║
║  🗺️  Grids:                    3  (1km, 250m, channel)    ║
║                                                           ║
║  🧪 Tests to Create:                                      ║
║     ├── Unit tests:       41+ (one per BMI function)      ║
║     ├── Integration:       6  (full cycle, multi-step)    ║
║     ├── Validation:        4  (vs Croton NY baseline)     ║
║     ├── Edge cases:        8  (errors, invalid inputs)    ║
║     ├── Grid tests:       12  (3 grids × key functions)   ║
║     └── TOTAL:           ~71+ tests                       ║
║                                                           ║
║  🔗 Coupling Variables:                                   ║
║     ├── WRF-Hydro → SCHISM: 1 (streamflow/Q)             ║
║     ├── SCHISM → WRF-Hydro: 1 (water level/ETA2)         ║
║     └── TOTAL 2-way:        2 variables                   ║
║                                                           ║
║  📊 Functions Returning BMI_FAILURE:  ~20                  ║
║     ├── 12 type variants (_int, _float not applicable)    ║
║     └── ~8 grid functions (not applicable to grid type)   ║
║                                                           ║
║  📊 Functions Returning Data:         ~35                  ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
```

### 🗓️ Implementation Phases

```
Phase 1: IRF Decomposition + Core BMI (Weeks 1-3)
  ├── Decompose WRF-Hydro time loop into init/step/finalize
  ├── Implement 4 control functions
  ├── Implement 5 model info functions
  ├── Implement 5 time functions
  └── Test: init → update → finalize cycle works

Phase 2: Variables + Grids (Weeks 3-5)
  ├── Implement 6 variable info functions
  ├── Implement get_value for 8 output variables
  ├── Implement set_value for 4 input variables
  ├── Implement 17 grid functions for 3 grids
  └── Test: all unit tests pass

Phase 3: Validation + Testing (Weeks 5-6)
  ├── Write full test driver
  ├── Run validation against Croton NY baseline
  ├── Fix any discrepancies
  ├── Memory check with valgrind
  └── Test: 71+ tests pass, < 1% error vs baseline

Phase 4: Coupling Test (Weeks 6-7)
  ├── Write mock coupling test
  ├── Test 2-way variable exchange
  ├── Verify grid metadata for PyMT compatibility
  └── Test: coupling mock runs without crashes

Phase 5: Build System + Library (Week 7-8)
  ├── Integrate into WRF-Hydro CMake
  ├── Build libwrfhydro_bmi.so shared library
  ├── Verify installation into $CONDA_PREFIX
  └── Ready for babelizer in Phase 2 of project
```

### 🔑 Key Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Wrapper approach | External file (not #ifdef) | 235 source files, 5 call levels, no existing IRF |
| Variable names | CSDMS Standard Names | Target PyMT pathway, community standard |
| Initial variables | 8 output + 4 input | Covers key coupling + science variables |
| Grid count | 3 grids | Matches WRF-Hydro's resolution levels |
| t0/t1 pattern | Not used (Phase 1) | WRF-Hydro dt = coupling dt, no interpolation needed |
| MPI | Serial only (Phase 1) | Simplify first, add parallel later |
| Data types | Double only (Phase 1) | All WRF-Hydro physics are double precision |
| get_value_ptr | Planned | Zero-copy for performance with large arrays |
| 2-way coupling | Planned from start | Design input variables for SCHISM → WRF-Hydro |
| Testing baseline | Croton NY 6-hour run | Already generated, 39 output files available |

---

> 📝 **This document is the technical reference for implementing `bmi_wrf_hydro.f90`.** It should be read alongside:
> - `BMI_Implementation_Master_Plan.md` — the higher-level project plan with 6 phases
> - Doc 9 (`9_BMI_Architecture_SCHISM_vs_WRFHydro_Complete_Guide.md`) — full variable inventory
> - Doc 14 (`14_WRF_Hydro_Model_Complete_Deep_Dive.md`) — WRF-Hydro physics and architecture
> - Doc 12 (`12_BMI_Implementation_Concepts_Heat_SCHISM_WRFHydro.md`) — implementation patterns from Heat + SCHISM BMI
