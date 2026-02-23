# 🔬 SCHISM BMI Implementation — Deep Dive (Concepts Only)

> 📅 **Created**: February 20, 2026
> 🎯 **Focus**: How was SCHISM BMI built, what variables are exposed, does it work, where is NOAA using it
> 📍 **No code in this document** — pure concepts, architecture, and analysis
> 📁 **Source repo**: `SCHISM_BMI/` submodule (branch: `bmi-integration-master`)

---

## 📑 Table of Contents

1. [🎯 What This Document Answers](#1--what-this-document-answers)
2. [👤 Who Built the SCHISM BMI and When?](#2--who-built-the-schism-bmi-and-when)
3. [🏗️ The Two Layers of SCHISM BMI](#3--the-two-layers-of-schism-bmi)
4. [🧠 How the BMI Wrapper Was Designed (Architecture)](#4--how-the-bmi-wrapper-was-designed-architecture)
5. [📥 Input Variables — What Goes INTO SCHISM via BMI](#5--input-variables--what-goes-into-schism-via-bmi)
6. [📤 Output Variables — What Comes OUT of SCHISM via BMI](#6--output-variables--what-comes-out-of-schism-via-bmi)
7. [🗺️ The 9-Grid System — How SCHISM Describes Its Mesh](#7--the-9-grid-system--how-schism-describes-its-mesh)
8. [⏰ The Two-Timepoint Trick — How Forcing Data Works](#8--the-two-timepoint-trick--how-forcing-data-works)
9. [🔄 The Complete Data Flow — Step by Step](#9--the-complete-data-flow--step-by-step)
10. [🌧️ Special Case: How Rainfall Becomes River Discharge](#10--special-case-how-rainfall-becomes-river-discharge)
11. [⚙️ How MPI (Parallel Computing) Is Handled](#11--how-mpi-parallel-computing-is-handled)
12. [✅ Does It Work? Current Validation Status](#12--does-it-work-current-validation-status)
13. [🏛️ Where Is NOAA Using SCHISM Today?](#13--where-is-noaa-using-schism-today)
14. [🔮 The NextGen Framework — Where SCHISM BMI Is Headed](#14--the-nextgen-framework--where-schism-bmi-is-headed)
15. [📄 The 2024 Two-Way Coupling Paper — Key Findings](#15--the-2024-two-way-coupling-paper--key-findings)
16. [⚠️ Known Limitations](#16--known-limitations)
17. [🔑 Key Takeaways for Our WRF-Hydro BMI](#17--key-takeaways-for-our-wrf-hydro-bmi)

---

## 1. 🎯 What This Document Answers

Four questions:

| Question | Short Answer |
|----------|-------------|
| **How was the SCHISM BMI implemented?** | A separate 1,729-line Fortran module (`bmischism.f90`) wraps SCHISM's existing init/step/finalize functions, exposing 12 input + 5 output variables across 9 grids |
| **What variables were exposed?** | 17 total: river discharge, water levels, wind, pressure, temperature, humidity, rainfall (input) and water elevation, currents, bed level (output) |
| **Is it working correctly?** | Partially — framework integration works, but water level and source/sink connectors have NOT been fully validated yet |
| **Where is NOAA using it?** | SCHISM runs operationally in STOFS and NWM v3.0, but via ESMF (not BMI). The BMI version is experimental, being tested for the NextGen framework with a Lake Champlain test case |

---

## 2. 👤 Who Built the SCHISM BMI and When?

### The People

| Person | Role | Organization |
|--------|------|-------------|
| **Jason Ducker** | Primary developer, NextGen Forcings Technical Director | Lynker Technologies (contractor for NOAA OWP) |
| **Joseph Zhang** | SCHISM lead developer, collaborator | VIMS (Virginia Institute of Marine Science) |
| **Phil Miller** | NextGen framework integration lead | NOAA OWP (Office of Water Prediction) |

### Timeline

```
📅 December 2022   → Jason Ducker creates LynkerIntel/SCHISM_BMI repository
📅 April 2023      → schism-dev/schism_NWM_BMI created (official SCHISM dev org)
                      Joseph Zhang collaborates on USE_NWM_BMI flag design
📅 June 2023       → Issue #547 opened on NOAA-OWP/ngen:
                      "Evaluating SCHISM BMI as a NextGen Formulation"
📅 October 2023    → Build documentation wiki published
📅 January 2024    → Remaining framework work items identified by Phil Miller
📅 August 2024     → Issue #547 still OPEN — work continues
📅 September 2024  → Two-way coupling paper published (ESMF, not BMI)
📅 February 2026   → Still experimental, not in production within NextGen
```

> 💡 **Key insight**: The SCHISM BMI was built specifically for NOAA's NextGen framework — NOT for the CSDMS/PyMT ecosystem. That's why there's no `pymt_schism` package.

---

## 3. 🏗️ The Two Layers of SCHISM BMI

SCHISM's BMI is not a single thing — it has **two distinct layers** that work together:

### Layer 1: The `#ifdef` Blocks (Inside SCHISM Source Code)

These are small conditional code blocks **inside** SCHISM's own source files. They modify how SCHISM reads source/sink data.

```
┌─────────────────────────────────────────────────┐
│  SCHISM Source Code (437 files)                  │
│                                                  │
│  schism_init.F90:                                │
│    ... normal init code ...                      │
│    ┌─────────────────────────────────┐           │
│    │ #ifdef USE_NWM_BMI              │ ← Block 1 │
│    │   Validate if_source ≠ 0        │           │
│    │ #endif                          │           │
│    └─────────────────────────────────┘           │
│                                                  │
│  schism_step.F90:                                │
│    ... normal step code ...                      │
│    ┌─────────────────────────────────┐           │
│    │ #ifdef USE_NWM_BMI              │ ← Blocks  │
│    │   Skip file reading             │   2-3     │
│    │   Use BMI-provided arrays       │           │
│    │ #endif                          │           │
│    └─────────────────────────────────┘           │
│                                                  │
│  misc_subs.F90:                                  │
│    ┌─────────────────────────────────┐           │
│    │ #ifdef USE_NWM_BMI              │ ← Blocks  │
│    │   Initialize arrays to zero     │   4-5     │
│    │   (BMI will fill them later)    │           │
│    │ #endif                          │           │
│    └─────────────────────────────────┘           │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Purpose**: Makes SCHISM "BMI-ready" by replacing file-based forcing with array-based forcing that an external caller can write into.

### Layer 2: The BMI Wrapper Module (`bmischism.f90`)

This is a **completely separate file** (1,729 lines) that implements all 41 BMI functions.

```
┌─────────────────────────────────────────────────┐
│  bmischism.f90 (1,729 lines)                     │
│                                                  │
│  ┌───────────────────────────────────────┐       │
│  │ type bmi_schism extends(bmi)          │       │
│  │   Contains: model state, config       │       │
│  │                                       │       │
│  │   initialize()  → calls schism_init() │       │
│  │   update()      → calls schism_step() │       │
│  │   finalize()    → calls schism_fin()  │       │
│  │                                       │       │
│  │   get_value()   → reads from eta2,    │       │
│  │                    uu2, vv2, dp       │       │
│  │                                       │       │
│  │   set_value()   → writes into ath2,   │       │
│  │                    ath3, pr1/pr2,     │       │
│  │                    windx1/windx2, etc │       │
│  │                                       │       │
│  │   get_grid_*()  → describes the       │       │
│  │                    unstructured mesh   │       │
│  └───────────────────────────────────────┘       │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Purpose**: Provides the standardized BMI "door" that external frameworks (NextGen, PyMT) use to talk to SCHISM.

### How They Work Together

```
    External Caller (NextGen / PyMT)
              │
              │  BMI calls: initialize(), update(), get_value(), set_value()
              ▼
    ┌──────────────────────┐
    │   bmischism.f90       │  ← Layer 2: The standard BMI interface
    │   (BMI Wrapper)       │
    └──────────┬───────────┘
               │
               │  Internal calls: schism_init(), schism_step(), etc.
               │  Direct array access: ath3, eta2, pr1/pr2, etc.
               ▼
    ┌──────────────────────┐
    │   SCHISM Source Code   │  ← Layer 1: #ifdef blocks make arrays
    │   (with #ifdef blocks) │     available for BMI instead of files
    └──────────────────────┘
```

---

## 4. 🧠 How the BMI Wrapper Was Designed (Architecture)

### The Type Extension Pattern

The wrapper follows the same pattern as our BMI heat example:
- SCHISM's BMI module **extends** the abstract BMI type from `bmif_2_0`
- It embeds a **model container** inside itself that holds SCHISM's state
- Every BMI function is mapped to a corresponding SCHISM internal operation

### The Model Container

Instead of embedding the entire SCHISM model directly, the wrapper uses a small **container type** (`schism_model_container.f90`, ~50 lines) that stores:

| Field | What It Holds |
|-------|---------------|
| `iths` | Current timestep counter (integer) |
| `ntime` | Total number of timesteps |
| `model_start_time` | Start time from config file |
| `model_end_time` | End time from config file |
| `num_time_steps` | Number of steps to run |
| `time_step_size` | Size of each timestep (seconds) |
| `given_communicator` | MPI communicator provided by caller |

> 💡 **Why a container?** SCHISM stores most of its state in **global module variables** (inside `schism_glbl.F90`), not in a derived type. The container just holds the config and timestep tracking — SCHISM's actual physics state (water levels, currents, etc.) lives in global arrays that the wrapper accesses directly via Fortran `use` statements.

### The Variable Dispatch Pattern

Every BMI function that deals with variables uses a **select case** pattern:

```
When someone calls get_value("ETA2"):
  → The wrapper looks up "ETA2" in a select case block
  → Finds it maps to the global array eta2(:)
  → Copies eta2 into the output array
  → Returns BMI_SUCCESS

When someone calls get_value("UNKNOWN_VAR"):
  → The select case hits "case default"
  → Returns BMI_FAILURE
```

This is identical to what we will do in `bmi_wrf_hydro.f90`.

---

## 5. 📥 Input Variables — What Goes INTO SCHISM via BMI

SCHISM exposes **12 input variables** through BMI. These are things that external models or frameworks **send** to SCHISM:

### 🌊 Boundary Condition Variables

| Variable | What It Is | Units | Where It Goes Inside SCHISM |
|----------|-----------|-------|----------------------------|
| **`Q_bnd_source`** | ⭐ River discharge at source elements (this is what WRF-Hydro sends!) | m³/s | `ath3` array (volume source time series) |
| **`Q_bnd_sink`** | Water withdrawal at sink elements | m³/s | `ath3` array (volume sink time series) |
| **`ETA2_bnd`** | Water level at open ocean boundaries (tidal/surge forcing) | m | `ath2` array (boundary condition time series) |

### 🌤️ Atmospheric Forcing Variables

| Variable | What It Is | Units | Where It Goes |
|----------|-----------|-------|---------------|
| **`SFCPRS`** | Surface atmospheric pressure | Pa | `pr1`/`pr2` arrays (two timepoints) |
| **`TMP2m`** | Air temperature at 2 meters above surface | K (Kelvin) | `airt1`/`airt2` arrays |
| **`U10m`** | Eastward wind speed at 10 meters | m/s | `windx1`/`windx2` arrays |
| **`V10m`** | Northward wind speed at 10 meters | m/s | `windy1`/`windy2` arrays |
| **`SPFH2m`** | Specific humidity at 2 meters | kg/kg | `shum1`/`shum2` arrays |
| **`RAINRATE`** | Precipitation rate (special — gets converted to discharge!) | kg/m²/s | Added to `ath3` source discharge |

### ⚙️ Control Variables

| Variable | What It Is | Units | Purpose |
|----------|-----------|-------|---------|
| **`ETA2_dt`** | Time step for water level boundary updates | seconds | Tells SCHISM how often to expect new boundary data |
| **`Q_dt`** | Time step for discharge boundary updates | seconds | Tells SCHISM how often to expect new discharge data |
| **`bmi_mpi_comm_handle`** | MPI communicator handle | integer | Tells SCHISM which parallel computing group to use |

---

## 6. 📤 Output Variables — What Comes OUT of SCHISM via BMI

SCHISM exposes **5 output variables** — things that external models can **read** from SCHISM:

| Variable | What It Is | Units | Where It Comes From |
|----------|-----------|-------|---------------------|
| **`ETA2`** | ⭐ Sea surface water elevation at ALL mesh nodes | m | SCHISM's hydrodynamic solver (main output!) |
| **`VX`** | Eastward water current velocity (surface layer) | m/s | SCHISM's momentum equation solver |
| **`VY`** | Northward water current velocity (surface layer) | m/s | Same as above |
| **`TROUTE_ETA2`** | Water elevation at specific monitoring stations only | m | Extracted from `eta2` at station locations defined in `station.in` |
| **`BEDLEVEL`** | Ocean floor elevation (bathymetry, static) | m | SCHISM's depth array, inverted (positive = above datum) |

### 🔗 The Coupling Pair

For WRF-Hydro ↔ SCHISM coupling, the critical variable pair is:

```
    WRF-Hydro                                      SCHISM
    ═════════                                      ══════
    QLINK (streamflow)  ──── Q_bnd_source ────►   ath3 (source discharge)
                              (BMI input)

    (future: receive     ◄──── ETA2 ─────────     eta2 (water elevation)
     coastal water level)      (BMI output)
```

---

## 7. 🗺️ The 9-Grid System — How SCHISM Describes Its Mesh

One of the most interesting parts of the SCHISM BMI is how it describes its **unstructured triangular mesh** through BMI's grid system. SCHISM uses **9 different grids**, each for a different purpose:

### Spatial Grids (6)

| Grid ID | Name | Type | What It Represents |
|:-------:|------|------|--------------------|
| **1** | All Nodes | unstructured | Every point in the ocean mesh (where eta2, VX, VY, BEDLEVEL live) |
| **2** | All Elements | points | Center of every triangle in the mesh (where RAINRATE lives) |
| **3** | Offshore Boundary Points | points | Nodes on the open ocean boundary (where ETA2_bnd lives) |
| **4** | Source Elements | points | Mesh elements where rivers enter the ocean (where Q_bnd_source lives) |
| **5** | Sink Elements | points | Mesh elements where water is withdrawn (where Q_bnd_sink lives) |
| **6** | Station Points | points | Monitoring locations from `station.in` file (where TROUTE_ETA2 lives) |

### Virtual Scalar Grids (3)

| Grid ID | Name | Type | What It Represents |
|:-------:|------|------|--------------------|
| **7** | ETA2 Timestep | scalar | Single number: how often water level boundaries update |
| **8** | Q Timestep | scalar | Single number: how often discharge boundaries update |
| **9** | MPI Communicator | scalar | Single number: the MPI communicator handle |

### Why So Many Grids?

Different variables live on **different parts** of the mesh:

```
   ┌─────────────────────────────────────────────┐
   │  SCHISM OCEAN DOMAIN                        │
   │                                              │
   │     Grid 1: All Nodes (triangular mesh)      │
   │     ┌───┬───┬───┬───┐                       │
   │     │ △ │ △ │ △ │ △ │  Grid 2: Element      │
   │     ├───┼───┼───┼───┤  centers (inside       │
   │     │ △ │ △ │ △ │ △ │  each triangle)        │
   │     ├───┼───┼───┼───┤                        │
   │     │ △ │ △ │ △ │ △ │                        │
   │     └───┴───┴───┴───┘                        │
   │     ▲                 ▲                       │
   │     │                 │                       │
   │  Grid 3: Open        Grid 4: Source           │
   │  boundary nodes      elements (river          │
   │  (ocean side)        mouths)                  │
   │                                              │
   │     ★ Grid 6: Station points                  │
   │       (monitoring locations)                  │
   │                                              │
   └─────────────────────────────────────────────┘
```

> 💡 **Comparison to WRF-Hydro**: WRF-Hydro has 3 grids (1km LSM, 250m routing, channel network). SCHISM has 9 grids but they're all subsets of one mesh. Different approach, same BMI concept.

---

## 8. ⏰ The Two-Timepoint Trick — How Forcing Data Works

This is one of the **most important design decisions** in the SCHISM BMI, and it's quite clever.

### The Problem

SCHISM needs to **interpolate** between data snapshots. If you give it weather data at hour 0 and hour 1, SCHISM needs to smoothly transition between them during the timesteps in between.

### The Solution: t0/t1 Pattern

Every forcing variable inside SCHISM is stored as **two snapshots**:
- **t0** = the "old" value (from the previous update)
- **t1** = the "new" value (from the current update)

SCHISM interpolates between t0 and t1 based on the current simulation time.

### How set_value Updates Work

When the external caller provides new data:

```
BEFORE set_value("Q_bnd_source", new_discharge):

   t0 = [100, 200, 150]    ← old values
   t1 = [120, 180, 160]    ← current values

AFTER set_value("Q_bnd_source", new_discharge):

   t0 = [120, 180, 160]    ← old t1 slides to become new t0
   t1 = [140, 220, 170]    ← new data becomes t1
```

This "slide" operation happens automatically inside every `set_value` call:
1. Old t1 → becomes new t0
2. New input → becomes new t1
3. SCHISM interpolates between them during timesteps

### Why This Matters

This design means:
- The caller doesn't need to provide data at every single SCHISM timestep
- Data can come at a **coarser interval** (e.g., hourly) while SCHISM runs with finer timesteps (e.g., every 100 seconds)
- SCHISM smoothly interpolates between updates — no sudden jumps
- The caller only needs to provide ONE array per update — the wrapper handles the t0/t1 bookkeeping

> 💡 **For our WRF-Hydro BMI**: We should consider a similar approach. WRF-Hydro runs with ~1 hour timesteps, and SCHISM may run with ~100 second timesteps. The interpolation needs to happen somewhere — SCHISM handles it internally.

---

## 9. 🔄 The Complete Data Flow — Step by Step

Here is the complete lifecycle of a SCHISM BMI coupling session:

### Phase 1: Before Initialization

```
┌─────────────────────────────────────────────────────────┐
│  STEP 0: Set MPI Communicator                            │
│                                                          │
│  The caller tells SCHISM which parallel computing group  │
│  to use. This MUST happen BEFORE initialize().           │
│                                                          │
│  External Caller ──► set_value("bmi_mpi_comm_handle")    │
│                       ──► Stored in model container      │
└─────────────────────────────────────────────────────────┘
```

### Phase 2: Initialization

```
┌─────────────────────────────────────────────────────────┐
│  STEP 1: Initialize                                      │
│                                                          │
│  External Caller ──► initialize("config.nml")            │
│                       │                                  │
│                       ├─► Read config: start time,       │
│                       │   end time, timestep size,       │
│                       │   number of scribe processes     │
│                       │                                  │
│                       ├─► Initialize MPI with the        │
│                       │   communicator from Step 0       │
│                       │                                  │
│                       ├─► Call schism_init():             │
│                       │   • Read mesh (hgrid.gr3)        │
│                       │   • Read bathymetry              │
│                       │   • Allocate ALL arrays          │
│                       │   • Set initial conditions       │
│                       │   • Set up boundary conditions   │
│                       │                                  │
│                       └─► Return BMI_SUCCESS              │
└─────────────────────────────────────────────────────────┘
```

### Phase 3: Pre-Timestep Setup

```
┌─────────────────────────────────────────────────────────┐
│  STEP 2: Configure Forcing Timesteps                     │
│                                                          │
│  Tell SCHISM how often to expect new boundary data:      │
│                                                          │
│  set_value("ETA2_dt", 3600)   ← "I'll update water      │
│                                   levels every 3600 sec" │
│  set_value("Q_dt", 3600)      ← "I'll update discharge  │
│                                   every 3600 sec"        │
│                                                          │
│  This recalibrates SCHISM's internal interpolation       │
│  time windows to match the caller's update frequency.    │
└─────────────────────────────────────────────────────────┘
```

### Phase 4: The Coupling Loop

```
┌─────────────────────────────────────────────────────────┐
│  STEP 3: Coupling Loop (repeat until end time)           │
│                                                          │
│  ┌───────────────────────────────────────────────┐       │
│  │  3a. INJECT FORCING DATA                      │       │
│  │                                               │       │
│  │  set_value("Q_bnd_source", discharge_data)    │       │
│  │  set_value("ETA2_bnd", water_level_data)      │       │
│  │  set_value("SFCPRS", pressure_data)           │       │
│  │  set_value("TMP2m", temperature_data)         │       │
│  │  set_value("U10m", wind_u_data)               │       │
│  │  set_value("V10m", wind_v_data)               │       │
│  │  set_value("SPFH2m", humidity_data)           │       │
│  │  set_value("RAINRATE", rainfall_data)         │       │
│  │                                               │       │
│  │  Each set_value does the t0/t1 slide          │       │
│  │  (old t1 → new t0, new data → new t1)         │       │
│  └───────────────────┬───────────────────────────┘       │
│                      ▼                                   │
│  ┌───────────────────────────────────────────────┐       │
│  │  3b. ADVANCE ONE TIMESTEP                     │       │
│  │                                               │       │
│  │  update()                                     │       │
│  │    → Increments timestep counter              │       │
│  │    → Calls schism_step()                      │       │
│  │    → SCHISM solves hydrodynamic equations      │       │
│  │    → Updates eta2, uu2, vv2 arrays            │       │
│  └───────────────────┬───────────────────────────┘       │
│                      ▼                                   │
│  ┌───────────────────────────────────────────────┐       │
│  │  3c. READ OUTPUTS                             │       │
│  │                                               │       │
│  │  get_value("ETA2", water_levels)              │       │
│  │  get_value("VX", east_velocity)               │       │
│  │  get_value("VY", north_velocity)              │       │
│  │  get_value("TROUTE_ETA2", station_levels)     │       │
│  │                                               │       │
│  │  Each get_value copies from SCHISM's arrays   │       │
│  └───────────────────┬───────────────────────────┘       │
│                      ▼                                   │
│  ┌───────────────────────────────────────────────┐       │
│  │  3d. EXCHANGE WITH OTHER MODELS               │       │
│  │                                               │       │
│  │  Send water_levels to WRF-Hydro               │       │
│  │    (for 2-way coupling — future)              │       │
│  │  Get new discharge from WRF-Hydro             │       │
│  │    (via WRF-Hydro's BMI — what we're building)│       │
│  └───────────────────┬───────────────────────────┘       │
│                      ▼                                   │
│            Loop back to 3a                               │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Phase 5: Finalization

```
┌─────────────────────────────────────────────────────────┐
│  STEP 4: Finalize                                        │
│                                                          │
│  finalize()                                              │
│    → Calls schism_finalize()                             │
│    → Deallocates all arrays                              │
│    → Closes output files                                 │
│    → Calls MPI finalize                                  │
│    → Returns BMI_SUCCESS                                 │
└─────────────────────────────────────────────────────────┘
```

---

## 10. 🌧️ Special Case: How Rainfall Becomes River Discharge

One of the most interesting design decisions in the SCHISM BMI is how **rainfall** is handled. It is NOT treated as a separate forcing — it gets **converted into discharge** and **added** to the source/sink array.

### The Conversion

```
When set_value("RAINRATE", rainfall_array) is called:

  For each mesh element i:
    extra_discharge(i) = rainfall_rate(i) × element_area(i) ÷ 1000

    Units: (kg/m²/s) × (m²) ÷ 1000 = m³/s

  Then this extra discharge is ADDED to the existing source discharge:
    ath3(i) = ath3(i) + extra_discharge(i)
```

### Why This Design?

- SCHISM treats all water inputs as **volume sources** (m³/s)
- Whether water comes from a river or from rain falling on the ocean, it's all just "water entering the system"
- By converting rainfall to discharge and adding it to the source array, SCHISM handles all inputs uniformly
- This is different from WRF-Hydro, where rainfall is a separate atmospheric forcing

> ⚠️ **Important**: RAINRATE is the ONLY input variable that **adds** to existing values. All other `set_value` calls **replace** the existing values (with the t0/t1 slide).

---

## 11. ⚙️ How MPI (Parallel Computing) Is Handled

### What is MPI?

MPI (Message Passing Interface) is the standard way to run scientific models on **multiple CPU cores simultaneously**. SCHISM is fundamentally a parallel model — the ocean mesh is divided among cores, and each core simulates its portion.

### The Challenge

When SCHISM runs through BMI inside a framework like NextGen, the framework itself may also use MPI. So SCHISM can't just use `MPI_COMM_WORLD` (the "everyone" communicator) — it needs its own subset.

### The Solution: External Communicator

The SCHISM BMI solves this with a special variable:

```
BEFORE initialize():

  The caller creates an MPI communicator for SCHISM
  and passes it via set_value("bmi_mpi_comm_handle", comm)

DURING initialize():

  SCHISM initializes MPI using THAT communicator
  (not MPI_COMM_WORLD)

RESULT:

  SCHISM runs on the cores assigned by the caller
  The framework can run other models on other cores
  No conflicts between parallel models
```

### Scribe I/O

SCHISM has a concept of **scribe processes** — dedicated cores that only handle file I/O (reading/writing NetCDF output). The number of scribes is configurable.

For BMI/serial testing: set scribes to 0 (all cores compute).

---

## 12. ✅ Does It Work? Current Validation Status

### What Works ✅

| Aspect | Status | Evidence |
|--------|--------|---------|
| BMI interface compiles | ✅ Working | Build system produces executable |
| Initialize/Update/Finalize cycle | ✅ Working | Test driver (`schism_bmi_driver_test.f90`, 790 lines) runs through complete lifecycle |
| Variable querying (names, types, units, grids) | ✅ Working | Test driver queries all 17 variables successfully |
| Grid metadata (node counts, connectivity) | ✅ Working | Unstructured mesh info exposed correctly |
| MPI communicator passing | ✅ Working | Test driver passes MPI_COMM_WORLD successfully |
| Atmospheric forcing via set_value | ✅ Working | Wind, pressure, temperature, humidity can be set |
| ETA2 output via get_value | ✅ Working | Water elevation can be read at all nodes |

### What Is NOT Fully Validated ⚠️

| Aspect | Status | Issue |
|--------|--------|-------|
| **Water level boundary conditions** (ETA2_bnd) | ⚠️ Not fully validated | Interpolation timing may have edge cases |
| **Source/sink discharge** (Q_bnd_source, Q_bnd_sink) | ⚠️ Not fully validated | Discharge accumulation (especially with RAINRATE) needs more testing |
| **Two-way coupling data exchange** | ⚠️ Not tested in production | No real coupling test with WRF-Hydro/NWM via BMI yet |
| **Multi-instance** (multiple SCHISM on different cores) | ⚠️ Not tested | NextGen may need to run multiple coastal domains |

### From the LIMITATIONS File

The official `LIMITATIONS` file in the SCHISM BMI repository states:

> 1. MPI parallelization is **partially implemented**
> 2. Water level and source/sink connectors have **not been fully validated** yet

### What This Means for Us

The SCHISM BMI exists and the framework works, but the specific variables we need for coupling (**discharge input** and **water level output**) are the exact ones flagged as "not fully validated." This doesn't mean they're broken — it means thorough end-to-end testing hasn't been completed yet.

---

## 13. 🏛️ Where Is NOAA Using SCHISM Today?

### SCHISM in NOAA Operations (Using ESMF, NOT BMI)

| System | What It Does | SCHISM Grid Size | Status | Coupling Method |
|--------|-------------|-------------------|--------|----------------|
| **STOFS-3D-Atlantic** | Total water level forecasts for Atlantic/Gulf coasts | 2.9M nodes, 5.7M elements | ✅ **Operational** since Jan 2023 | ESMF/NUOPC |
| **STOFS-3D-Pacific** | Total water level forecasts for Pacific coast | TBD | 🔶 **Planned** for late 2025 | ESMF/NUOPC |
| **NWM v3.0 TWL** | Total water level guidance combining river + ocean | Uses STOFS SCHISM grid | ✅ **Operational** since summer 2023 | ESMF/NUOPC |
| **ICOGS** | Inland-Coastal Operational Guidance System | Regional domains | 🔶 **Pre-operational** since April 2021 | Direct coupling |

### SCHISM BMI in NextGen (Experimental)

| System | What It Does | Status | Coupling Method |
|--------|-------------|--------|----------------|
| **NextGen/ngen** | Next-generation modular water framework | 🔴 **Experimental** — Issue #547 still open | BMI 2.0 |
| **Lake Champlain test** | BMI validation test case | 🔶 **Created**, used for framework testing | BMI 2.0 |

### The Key Distinction

```
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  TODAY (Production):                                           │
│                                                                │
│  NWM ──── ESMF/NUOPC ────► SCHISM ────► STOFS forecasts       │
│           (Earth System                                        │
│            Modeling Framework)                                  │
│                                                                │
│  ══════════════════════════════════════════════════════════     │
│                                                                │
│  FUTURE (In Development):                                      │
│                                                                │
│  NWM ──── BMI 2.0 ────► SCHISM ────► NextGen forecasts        │
│  (or     (Basic Model                                          │
│  WRF-     Interface)                                           │
│  Hydro)                                                        │
│                                                                │
│  This transition from ESMF → BMI is exactly why                │
│  our project (WRF-Hydro BMI wrapper) matters!                  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

---

## 14. 🔮 The NextGen Framework — Where SCHISM BMI Is Headed

### What Is NextGen?

**NextGen** = NOAA's **Next Generation Water Resources Modeling Framework**. It's designed to replace the current NWM with a modular, pluggable system where any BMI model can be swapped in or out.

### How SCHISM Fits in NextGen

```
┌──────────────────────────────────────────────────────────────┐
│                    NextGen Framework (ngen)                    │
│                                                              │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐     │
│  │  Atmospheric   │   │  Hydrologic   │   │  Channel     │     │
│  │  Forcings      │   │  Models       │   │  Routing     │     │
│  │  (BMI)         │   │  (BMI)        │   │  (t-route)   │     │
│  │                │   │               │   │  (BMI)       │     │
│  │  • NWM Forcing │   │  • CFE        │   │              │     │
│  │  • ERA5        │   │  • TOPMODEL   │   │  Discharge   │     │
│  │  • AORC        │   │  • NoahOWP    │   │  at coastal  │     │
│  └───────┬────────┘   └───────┬───────┘   │  outlets     │     │
│          │                    │            └──────┬───────┘     │
│          │                    │                   │             │
│          ▼                    ▼                   ▼             │
│  ┌──────────────────────────────────────────────────────┐     │
│  │              COASTAL REALIZATION (new!)                │     │
│  │                                                       │     │
│  │  ┌─────────────┐         ┌─────────────┐              │     │
│  │  │  SCHISM      │   OR   │  D-Flow FM   │              │     │
│  │  │  (BMI)       │        │  (BMI)       │              │     │
│  │  │              │        │              │              │     │
│  │  │  Water level │        │  Water level │              │     │
│  │  │  Currents    │        │  Currents    │              │     │
│  │  └─────────────┘         └─────────────┘              │     │
│  └──────────────────────────────────────────────────────┘     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Remaining Work Items (as of 2024)

| Task | Status |
|------|--------|
| Define coastal realization config structure | 🔶 In progress |
| BMI coastal formulation in ngen | ✅ Completed |
| MPI process mapping for coastal models | 🔶 In progress |
| Map nexus IDs to BMI variable indices | 🔶 In progress |
| Lake Champlain test case | ✅ Created |
| Integration with t-route discharge | 🔶 In progress |
| Multi-instance SCHISM support | 🔶 Not yet tested |

### ESMF → BMI Transition Challenge

The 2024 two-way coupling paper explicitly notes:

> *"The proposed shift from ESMF to BMI for coastal coupling requires innovative solutions to bridge the gap between inland hydrological models based on hydrofabrics and coastal hydrodynamic models operating on a 2D grid."*

This is a fundamental challenge: inland models (WRF-Hydro, NWM) use catchment-based grids, while coastal models (SCHISM) use unstructured triangular meshes. BMI needs to handle this translation.

---

## 15. 📄 The 2024 Two-Way Coupling Paper — Key Findings

### Paper Details

| Field | Value |
|-------|-------|
| **Title** | Two-Way Coupling of the National Water Model (NWM) and Semi-Implicit Cross-Scale Hydroscience Integrated System Model (SCHISM) for Enhanced Coastal Discharge Predictions |
| **Authors** | Zhang, H., Shen, D., Bao, S., & Len, P. |
| **Journal** | Hydrology (MDPI), Volume 11, Issue 9, Article 145 |
| **Published** | September 2024 (open access) |
| **Coupling method used** | CoastalApp/ESMF (NOT BMI) |
| **Test case** | Hurricane Matthew (October 2016, South Carolina) |
| **Simulation period** | September 1 – November 10, 2016 |

### Key Findings

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  Finding 1: TWO-WAY IS BETTER THAN ONE-WAY                 │
│                                                             │
│  One-way (NWM → SCHISM only):                               │
│    • NWM doesn't know about storm surge                     │
│    • Rivers keep flowing normally even when ocean pushes     │
│      water upstream                                         │
│    • Discharge predictions WRONG during storm events         │
│                                                             │
│  Two-way (NWM ↔ SCHISM):                                    │
│    • SCHISM tells NWM about storm surge                     │
│    • Rivers slow down when ocean pushes back                │
│    • Much better discharge predictions during storms         │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Finding 2: TIDAL EFFECTS ON RIVERS                         │
│                                                             │
│  • Daily tides cause river discharge to oscillate            │
│  • One-way NWM completely misses this                        │
│  • Two-way captures tidal "breathing" of rivers              │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Finding 3: PEAK DISCHARGE TIMING                           │
│                                                             │
│  • Two-way coupling more accurately predicts WHEN            │
│    peak discharge occurs (not just how much)                 │
│  • Accounts for water storage in coastal floodplains         │
│  • Captures complex river-river interactions                 │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Finding 4: ESMF → BMI TRANSITION NEEDED                    │
│                                                             │
│  • Paper explicitly calls out that NextGen needs BMI         │
│  • Current ESMF coupling works but is framework-specific     │
│  • BMI would make coupling modular and portable              │
│  • THIS IS EXACTLY WHAT OUR PROJECT ADDRESSES               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Why This Paper Matters for Us

This paper **validates the scientific need** for our WRF-Hydro BMI project. It shows that:
1. Two-way coupling (which requires BMI on BOTH models) produces significantly better results
2. The transition from ESMF to BMI is recognized as an active research priority
3. The specific variables we're exposing (streamflow, water elevation) are exactly what the coupling needs

---

## 16. ⚠️ Known Limitations

### From the Official LIMITATIONS File

1. **MPI parallelization** is only **partially implemented**
2. **Water level and source/sink connectors** have **not been fully validated**

### From Code Analysis

| Limitation | Details |
|------------|---------|
| **No grid shape/spacing/origin** | Returns BMI_FAILURE (unstructured mesh doesn't have uniform spacing) |
| **Surface layer only** for VX/VY | Only the top vertical layer of velocity is exposed (not the full 3D field) |
| **RAINRATE accumulates** instead of replacing | Can cause unexpected behavior if caller doesn't account for this |
| **No set_value for outputs** | You cannot write INTO eta2 or VX/VY from outside — they're read-only |
| **First timestep cold start** | At t=0, no boundary forcing data exists yet. SCHISM uses zeros until first set_value call |
| **OLDIO required for serial** | Must use OLDIO=ON mode for single-core BMI runs (scribe I/O doesn't work in serial) |
| **No CSDMS Standard Names** | Variables use custom names (Q_bnd_source, ETA2, etc.) not CSDMS names (channel_water__volume_flow_rate) |

### Not Registered with CSDMS

SCHISM BMI is:
- ❌ NOT listed in the CSDMS model repository
- ❌ NOT available as a PyMT plugin
- ❌ NOT using CSDMS Standard Names
- ✅ Built for NOAA NextGen framework (different pathway)

---

## 17. 🔑 Key Takeaways for Our WRF-Hydro BMI

What we can learn from the SCHISM BMI implementation:

### Design Patterns to Follow

| SCHISM Pattern | Apply to WRF-Hydro |
|----------------|---------------------|
| Separate wrapper file (not inline #ifdef) | Write `bmi_wrf_hydro.f90` as a separate module |
| Model container for config + timestep tracking | Create container for WRF-Hydro config state |
| t0/t1 sliding pattern for forcing data | Consider for any input variables that need interpolation |
| Multiple grids for different variable domains | Use Grid 0 (1km), Grid 1 (250m), Grid 2 (channel) |
| MPI communicator via set_value before init | Follow same pattern for parallel WRF-Hydro |
| Serial-first approach (OLDIO/single-core) | Start with serial, add MPI later |

### Design Choices to Improve On

| SCHISM Approach | Our Improvement |
|-----------------|-----------------|
| Custom variable names (Q_bnd_source) | Use CSDMS Standard Names (channel_water__volume_flow_rate) |
| Not registered with CSDMS | Plan to register and babelize for PyMT |
| No pymt_schism plugin | Plan to create pymt_wrfhydro (and eventually pymt_schism) |
| Limited validation | Validate against standalone WRF-Hydro run from day one |

### Variable Count Comparison

| Model | Input Vars | Output Vars | Total | Grids |
|-------|:----------:|:-----------:|:-----:|:-----:|
| **SCHISM BMI** | 12 | 5 | 17 | 9 |
| **WRF-Hydro BMI** (our plan) | 2 | 8 | 10 | 3 |
| **BMI Heat Example** | 0 | 1 | 1 | 1 |

Our WRF-Hydro BMI is **between** the simple heat example and the complex SCHISM — a very reasonable scope to start with.

---

## 📝 Summary

```
┌──────────────────────────────────────────────────────────────────┐
│                    SCHISM BMI — Key Facts                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  WHO:   Jason Ducker (Lynker/NOAA OWP) + Joseph Zhang (VIMS)     │
│  WHEN:  Development started December 2022                        │
│  WHERE: LynkerIntel/SCHISM_BMI repo, bmi-integration-master      │
│  WHAT:  bmischism.f90 (1,729 lines) + 5 #ifdef blocks            │
│                                                                  │
│  VARIABLES: 12 input + 5 output = 17 total                      │
│  GRIDS:     9 (6 spatial + 3 virtual scalar)                     │
│  KEY IN:    Q_bnd_source (discharge from rivers)                 │
│  KEY OUT:   ETA2 (water elevation for 2-way coupling)            │
│                                                                  │
│  STATUS:                                                         │
│    ✅ Framework works (init/update/finalize cycle)               │
│    ⚠️ Water level + source/sink NOT fully validated              │
│    ❌ Not in production — experimental for NextGen               │
│    ❌ Not registered with CSDMS, no pymt_schism                  │
│                                                                  │
│  NOAA TODAY:     SCHISM runs in STOFS/NWM via ESMF (not BMI)     │
│  NOAA FUTURE:    SCHISM in NextGen via BMI (in development)      │
│  OUR PROJECT:    Building the WRF-Hydro side of this coupling    │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

> 📅 **Last Updated**: February 20, 2026
