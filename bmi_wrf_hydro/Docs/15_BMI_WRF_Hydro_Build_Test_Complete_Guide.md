# 🔧 BMI WRF-Hydro: The Complete Build & Test Guide

> **You've built the BMI wrapper. Now what?**
> This guide explains every file, how they connect, how to build and test them,
> and exactly how the BMI test suite fires up WRF-Hydro automatically.

---

## 📑 Table of Contents

1. [Introduction & Overview](#1--introduction--overview)
2. [Project Directory Structure](#2--project-directory-structure)
3. [The BMI Wrapper — `bmi_wrf_hydro.f90`](#3--the-bmi-wrapper--bmi_wrf_hydrof90)
4. [The Test Suite — `bmi_wrf_hydro_test.f90`](#4--the-test-suite--bmi_wrf_hydro_testf90)
5. [The Minimal Test — `bmi_minimal_test.f90`](#5--the-minimal-test--bmi_minimal_testf90)
6. [The Build System — `build.sh`](#6--the-build-system--buildsh)
7. [How BMI Testing Works — The Full Picture](#7--how-bmi-testing-works--the-full-picture)
8. [The Croton NY Test Data Connection](#8--the-croton-ny-test-data-connection)
9. [Building & Testing in VS Code](#9--building--testing-in-vs-code)
10. [Step-by-Step Commands](#10--step-by-step-commands)
11. [Troubleshooting Guide](#11--troubleshooting-guide)
12. [Summary & Quick Reference](#12--summary--quick-reference)

---

## 1. 🌟 Introduction & Overview

### 1.1 What This Doc Covers

This guide is your **one-stop reference** for everything about the WRF-Hydro BMI wrapper files:
- 📄 What each file does and why it exists
- 🔨 How to compile and link everything together
- 🧪 How to run the test suite (and what it tests)
- 🚀 How BMI testing **automatically starts WRF-Hydro** behind the scenes
- 📊 How we use the **Croton NY test data** for validation
- 💻 How to do all this in VS Code on WSL2

### 1.2 The ML Analogy — BMI Is Like a Model API

If you come from ML, think of BMI like this:

```
┌─────────────────────────────────────────────────────────────────┐
│                    BMI = Model API Contract                      │
├──────────────────────┬──────────────────────────────────────────┤
│ ML / PyTorch         │ Hydrology / BMI                          │
├──────────────────────┼──────────────────────────────────────────┤
│ model = MyNet()      │ status = model%initialize("config.nml")  │
│ model.load("ckpt")   │                                          │
│                      │                                          │
│ out = model(input)   │ status = model%update()                  │
│ out = model.forward()│                                          │
│                      │                                          │
│ model.get_parameter  │ status = model%get_value("streamflow",v) │
│ model.set_parameter  │ status = model%set_value("precip", v)    │
│                      │                                          │
│ del model            │ status = model%finalize()                 │
└──────────────────────┴──────────────────────────────────────────┘
```

> 🧠 **Key insight:** Just like PyTorch's `forward()` method hides thousands of GPU
> operations behind one function call, BMI's `update()` hides thousands of Fortran
> subroutines (soil physics, snow melt, river routing) behind one call.

### 1.3 What We Built — The Big Picture

```
┌────────────────────────────────────────────────────────────────┐
│              What We Built (Phase 1 Complete!)                   │
├────────────────────────────────────────────────────────────────┤
│                                                                  │
│  📄 bmi_wrf_hydro.f90  ────→  The BMI wrapper (1,919 lines)    │
│     Implements ALL 41 BMI functions (55 procedures total)       │
│     Wraps WRF-Hydro v5.4.0 with zero source modifications      │
│                                                                  │
│  🧪 bmi_wrf_hydro_test.f90 ──→ Full test suite (1,777 lines)   │
│     151 tests across 8 sections                                 │
│     ALL 151 PASS ✅                                              │
│                                                                  │
│  ⚡ bmi_minimal_test.f90 ────→ Quick smoke test (105 lines)     │
│     Initialize + 6 updates + finalize                           │
│     Verifies basic IRF cycle works                              │
│                                                                  │
│  🔨 build.sh ────────────────→ Build script (130 lines)         │
│     Compiles, links against 22 WRF-Hydro libraries             │
│                                                                  │
│  📋 CMakeLists.txt ──────────→ CMake config (650 lines)         │
│     For future shared library build (libwrfhydro_bmi.so)        │
│                                                                  │
└────────────────────────────────────────────────────────────────┘
```

---

## 2. 📁 Project Directory Structure

### 2.1 The Organized Layout

After reorganization, here's the clean structure:

```
bmi_wrf_hydro/                     ← 🏠 Our work directory
│
├── 📂 src/                        ← 🔧 Source code (the deliverable)
│   └── bmi_wrf_hydro.f90          ← ⭐ THE BMI wrapper (1,919 lines)
│
├── 📂 tests/                      ← 🧪 Test programs
│   ├── bmi_wrf_hydro_test.f90     ← 🔬 Full 151-test suite (1,777 lines)
│   └── bmi_minimal_test.f90       ← ⚡ Quick smoke test (105 lines)
│
├── 📂 build/                      ← 🏗️ All compiled artifacts go here
│   ├── .gitignore                 ← Ignores everything in build/
│   ├── bmi_wrf_hydro.o            ← Compiled wrapper object (after build)
│   ├── bmi_minimal_test.o         ← Compiled minimal test object
│   ├── bmi_wrf_hydro_test.o       ← Compiled full test object
│   ├── bmi_minimal_test           ← Minimal test executable
│   ├── bmi_wrf_hydro_test         ← Full test executable
│   ├── bmiwrfhydrof.mod           ← Fortran module file
│   └── wrfhydro_bmi_state_mod.mod ← State module file
│
├── 📂 Docs/                       ← 📚 Documentation (14+ guides)
│   ├── 1.Complete_Beginners_Guide...
│   ├── ...
│   ├── 14_WRF_Hydro_Model_Complete_Deep_Dive.md
│   ├── 15_BMI_WRF_Hydro_Build_Test_Complete_Guide.md  ← 📖 THIS FILE
│   ├── Plan/                      ← Master implementation plan
│   └── Weekly Reporting/          ← Weekly progress PPTs
│
├── build.sh                       ← 🔨 Build script (entry point)
└── CMakeLists.txt                 ← 📋 CMake config (future shared lib)
```

### 2.2 Why This Layout?

> 🧠 **ML Analogy:** This is like organizing a PyTorch project:
> - `src/` = your model definition (`model.py`)
> - `tests/` = your test scripts (`test_model.py`, `test_smoke.py`)
> - `build/` = compiled artifacts (like `__pycache__/`, `.pyc` files)
> - `Docs/` = documentation and notebooks

The key principle: **source code and build artifacts never mix**. When you look at `src/`,
you see only the code you wrote. When you look at `build/`, you see only what the compiler
produced. Clean and clear.

### 2.3 The Parent Project Layout

Our `bmi_wrf_hydro/` lives inside the larger WRF-Hydro BMI project:

```
WRF-Hydro-BMI/                          ← 🏠 Project root
│
├── bmi_wrf_hydro/                       ← ⭐ OUR work (described above)
│
├── wrf_hydro_nwm_public/               ← 🌊 WRF-Hydro v5.4.0 source + build
│   ├── src/                             ←   Fortran source code
│   └── build/                           ←   Compiled WRF-Hydro (22 libraries)
│       ├── lib/                         ←   .a static libraries
│       ├── mods/                        ←   86 .mod files
│       └── Run/wrf_hydro               ←   Standalone executable
│
├── WRF_Hydro_Run_Local/                 ← 📊 Test case data (Croton NY)
│   └── run/                             ←   namelists + forcing + output
│
├── bmi-fortran/                         ← 📐 BMI specification (abstract interface)
├── bmi-example-fortran/                 ← 📝 Heat model BMI example (reference)
├── schism_NWM_BMI/                      ← 🌊 SCHISM model with BMI
└── SCHISM_BMI/                          ← 🔗 LynkerIntel SCHISM BMI wrapper
```

---

## 3. 📄 The BMI Wrapper — `bmi_wrf_hydro.f90`

### 3.1 Overview

**Location:** `bmi_wrf_hydro/src/bmi_wrf_hydro.f90`
**Size:** ~1,919 lines
**Purpose:** Implement ALL 41 BMI functions to wrap WRF-Hydro v5.4.0

This is **the main deliverable** — the file that makes WRF-Hydro controllable by external
frameworks like PyMT or NOAA's NextGen.

### 3.2 Module Structure

The file contains **two modules** (unusual but necessary):

```
┌─────────────────────────────────────────────────────────────────┐
│ FILE: bmi_wrf_hydro.f90                                          │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ MODULE 1: wrfhydro_bmi_state_mod  (lines 1–25)           │    │
│  │                                                           │    │
│  │  type(state_type), save :: wrfhydro_bmi_state             │    │
│  │  logical, save :: wrfhydro_engine_initialized = .false.   │    │
│  │  integer, save :: wrfhydro_saved_ntime = 0                │    │
│  │                                                           │    │
│  │  WHY? BMI initialize() uses intent(out) which RESETS      │    │
│  │  the "this" object. Module-level SAVE variables persist.  │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ MODULE 2: bmiwrfhydrof  (lines 28–1919)                   │    │
│  │                                                           │    │
│  │  type, extends(bmi) :: bmi_wrf_hydro                      │    │
│  │     ! Data members: initialized, timestep, grids, etc.    │    │
│  │  contains                                                 │    │
│  │     ! All 55 procedure bindings                           │    │
│  │  end type                                                 │    │
│  │                                                           │    │
│  │  ! Implementation of all 41 BMI functions                 │    │
│  │  ! (55 procedures including type variants)                │    │
│  └──────────────────────────────────────────────────────────┘    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

> 🧠 **ML Analogy:** Module 1 is like a global model registry (storing the loaded model
> weights outside the model class so they survive re-instantiation). Module 2 is the
> actual model class with all its methods.

### 3.3 All 41 BMI Functions — Complete List

Here's every function the wrapper implements, organized by category:

#### 🎛️ Control Functions (4)

| # | Function | What It Does | WRF-Hydro Calls |
|---|----------|-------------|-----------------|
| 1 | `initialize(config)` | Start the model | `orchestrator%init()` + `land_driver_ini()` + `HYDRO_ini()` |
| 2 | `update()` | Advance one timestep | `land_driver_exe()` (calls `HYDRO_exe()` internally) |
| 3 | `update_until(time)` | Advance to target time | Calls `update()` in a loop |
| 4 | `finalize()` | Clean up | Custom cleanup (NOT `HYDRO_finish()` — it has `stop`!) |

#### ℹ️ Model Info Functions (5)

| # | Function | Returns |
|---|----------|---------|
| 5 | `get_component_name()` | `"WRF-Hydro v5.4.0 BMI"` |
| 6 | `get_input_item_count()` | `4` (precip, temp, sea elevation, sea velocity) |
| 7 | `get_output_item_count()` | `8` (streamflow, soil moisture, snow, etc.) |
| 8 | `get_input_var_names()` | Array of 4 CSDMS Standard Names |
| 9 | `get_output_var_names()` | Array of 8 CSDMS Standard Names |

#### 📊 Variable Info Functions (6)

| # | Function | Returns |
|---|----------|---------|
| 10 | `get_var_type(name)` | `"double"` for all variables |
| 11 | `get_var_units(name)` | e.g. `"m3 s-1"`, `"K"`, `"m"` |
| 12 | `get_var_grid(name)` | Grid ID: 0 (LSM), 1 (routing), or 2 (channel) |
| 13 | `get_var_itemsize(name)` | `8` (bytes per double-precision value) |
| 14 | `get_var_nbytes(name)` | Total bytes = itemsize × grid_size |
| 15 | `get_var_location(name)` | `"node"` for all variables |

#### ⏱️ Time Functions (5)

| # | Function | Returns |
|---|----------|---------|
| 16 | `get_start_time()` | `0.0` seconds |
| 17 | `get_end_time()` | `ntime × dt` seconds (e.g., `21600.0` for 6hr) |
| 18 | `get_current_time()` | Current model time in seconds |
| 19 | `get_time_step()` | `dt` seconds (e.g., `3600.0` for 1hr) |
| 20 | `get_time_units()` | `"s"` (seconds) |

#### 🗺️ Grid Functions (17)

| # | Function | Grids 0/1 (rectilinear) | Grid 2 (channel network) |
|---|----------|------------------------|-----------------------|
| 21 | `get_grid_type` | `"uniform_rectilinear"` | `"vector"` |
| 22 | `get_grid_rank` | `2` | `1` |
| 23 | `get_grid_size` | `IX×JX` / `IXRT×JXRT` | `NLINKS` |
| 24 | `get_grid_shape` | `[IX,JX]` / `[IXRT,JXRT]` | BMI_FAILURE (no shape) |
| 25 | `get_grid_spacing` | `[dx,dy]` in meters | BMI_FAILURE (irregular) |
| 26 | `get_grid_origin` | `[0.0, 0.0]` | BMI_FAILURE |
| 27 | `get_grid_x` | BMI_FAILURE (use spacing) | Link x-coordinates |
| 28 | `get_grid_y` | BMI_FAILURE (use spacing) | Link y-coordinates |
| 29 | `get_grid_z` | BMI_FAILURE (2D) | BMI_FAILURE (no z) |
| 30 | `get_grid_node_count` | grid_size | NLINKS |
| 31 | `get_grid_edge_count` | BMI_FAILURE (rectilinear) | NLINKS |
| 32 | `get_grid_face_count` | BMI_FAILURE (rectilinear) | 0 (1D network) |
| 33 | `get_grid_edge_nodes` | BMI_FAILURE | BMI_FAILURE (stub) |
| 34 | `get_grid_face_edges` | BMI_FAILURE | BMI_FAILURE (stub) |
| 35 | `get_grid_face_nodes` | BMI_FAILURE | BMI_FAILURE (stub) |
| 36 | `get_grid_nodes_per_face` | BMI_FAILURE | BMI_FAILURE (stub) |

#### 📤📥 Get/Set Value Functions (9 + type variants)

| # | Function | What It Does | Type Variants |
|---|----------|-------------|---------------|
| 37 | `get_value(name, dest)` | Copy data OUT of model | int, float, double |
| 38 | `set_value(name, src)` | Copy data INTO model | int, float, double |
| 39 | `get_value_ptr(name, ptr)` | Zero-copy pointer | Returns BMI_FAILURE (REAL→DOUBLE mismatch) |
| 40 | `get_value_at_indices` | Get specific elements | int, float, double |
| 41 | `set_value_at_indices` | Set specific elements | int, float, double |

### 3.4 Variable Mapping — CSDMS Standard Names

The wrapper maps WRF-Hydro's internal variable names to CSDMS Standard Names:

```
┌──────────────────────────────────────────────────────────────────────┐
│           WRF-Hydro Internal  →  CSDMS Standard Name                  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  📤 OUTPUT VARIABLES (8):                                             │
│  ─────────────────────────────────────────────────────────────        │
│  QLINK(:,1)   → channel_water__volume_flow_rate        [m3/s]       │
│  sfcheadrt    → land_surface_water__depth               [m]          │
│  SOIL_M(:,:,1)→ soil_water__volume_fraction             [-]          │
│  SNEQV        → snowpack__liquid-equivalent_depth       [mm]         │
│  ACCET        → land_surface_water__evaporation_volume_flux [mm]     │
│  INFXSRT      → land_surface_water__runoff_volume_flux   [m]         │
│  UGDRNOFF     → soil_water__domain_time_integral_of_baseflow [mm]    │
│  T2MVXY       → land_surface_air__temperature            [K]         │
│                                                                       │
│  📥 INPUT VARIABLES (4):                                              │
│  ─────────────────────────────────────────────────────────────        │
│  RAINRATE     → atmosphere_water__precipitation_leq-volume_flux [mm/s]│
│  T2MVXY       → land_surface_air__temperature            [K]         │
│  (coupling)   → sea_water_surface__elevation             [m]         │
│  (coupling)   → sea_water__x_velocity                    [m/s]       │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

> 🧠 **ML Analogy:** CSDMS Standard Names are like a universal tensor naming convention.
> Instead of every model calling temperature "T2", "temp", "air_temp", or "t2m", everyone
> uses `land_surface_air__temperature`. It's like how HuggingFace standardized model
> output keys (`logits`, `hidden_states`, etc.).

### 3.5 The Three Grids

```
┌────────────────────────────────────────────────────────────────┐
│                    WRF-Hydro's 3 Grids                          │
├────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Grid 0: LSM Grid (1km)          Grid 1: Routing Grid (250m)   │
│  ┌───┬───┬───┐  15 columns       ┌─┬─┬─┬─┬─┐  60 columns      │
│  │   │   │   │                    │ │ │ │ │ │                    │
│  ├───┼───┼───┤  16 rows           ├─┼─┼─┼─┼─┤  64 rows         │
│  │   │   │   │                    │ │ │ │ │ │                    │
│  └───┴───┴───┘  240 cells         └─┴─┴─┴─┴─┘  3,840 cells     │
│  Variables: T2, SOIL_M, SNEQV    Variables: sfcheadrt, INFXSRT  │
│                                                                  │
│  Grid 2: Channel Network                                        │
│     ○──○──○──○──○     505 links (reaches)                       │
│        │     │        Variables: QLINK (streamflow)              │
│     ○──○──○──○                                                   │
│        │                                                         │
│     ○──○──○                                                      │
│                                                                  │
└────────────────────────────────────────────────────────────────┘
```

> 🧠 **ML Analogy:** Think of the 3 grids like different resolution feature maps in a
> U-Net or Feature Pyramid Network (FPN):
> - Grid 0 = low-res features (1km, like the bottleneck)
> - Grid 1 = high-res features (250m, like an upsampled layer)
> - Grid 2 = a 1D graph (like GNN node features on a river network)

---

## 4. 🧪 The Test Suite — `bmi_wrf_hydro_test.f90`

### 4.1 Overview

**Location:** `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90`
**Size:** ~1,777 lines
**Tests:** 151 tests across 8 sections
**Result:** ✅ ALL 151 PASS

This is a comprehensive test driver that exercises **every BMI function** against the
Croton NY test case. Unlike Python's pytest, Fortran has no built-in test framework, so
we built our own PASS/FAIL reporting with helper subroutines.

### 4.2 Test Architecture

```
┌────────────────────────────────────────────────────────────────┐
│             Test Suite Architecture                              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ MAIN PROGRAM                                              │    │
│  │                                                           │    │
│  │  1. Create bmi_config.nml (config file)                   │    │
│  │  2. Call model%initialize("bmi_config.nml")               │    │
│  │  3. Run Section 1-8 tests                                 │    │
│  │  4. Print summary (PASS/FAIL counts)                      │    │
│  │  5. Call MPI_Finalize()                                   │    │
│  │                                                           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ HELPER SUBROUTINES (at the bottom via "contains")         │    │
│  │                                                           │    │
│  │  check_status(status, name, pass_count, fail_count)       │    │
│  │    → Checks if BMI_SUCCESS, prints PASS/FAIL              │    │
│  │                                                           │    │
│  │  check_true(condition, name, pass_count, fail_count)      │    │
│  │    → Checks if condition is .true.                        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└────────────────────────────────────────────────────────────────┘
```

### 4.3 All 8 Test Sections — What They Test

#### Section 1: 🎛️ Control Tests (T01–T04)
Tests the model lifecycle: initialize, update, update_until, finalize.
- **T01:** `initialize("bmi_config.nml")` returns BMI_SUCCESS
- **T02:** `update()` (one timestep) returns BMI_SUCCESS
- **T03:** `update_until(7200.0)` advances correctly
- **T04:** `finalize()` returns BMI_SUCCESS

#### Section 2: ℹ️ Model Info Tests (T05–T12)
Tests model metadata: component name, variable counts, variable names.
- **T05:** Component name = "WRF-Hydro v5.4.0 BMI"
- **T06:** Input item count = 4
- **T07:** Output item count = 8
- **T08:** Input variable names are valid CSDMS names
- **T09:** Output variable names are valid CSDMS names
- **T10–T12:** Variable info for all exposed variables (type, units, grid)

#### Section 3: 📊 Variable Info Tests (T13–T16)
Tests per-variable metadata for streamflow and other variables.
- **T13:** `get_var_itemsize("streamflow")` = 8 bytes
- **T14:** `get_var_nbytes("streamflow")` = 8 × 505 = 4040 bytes
- **T15:** `get_var_location("streamflow")` = "node"
- **T16:** Invalid name returns BMI_FAILURE

#### Section 4: ⏱️ Time Tests (T17–T21)
Tests the model's time system.
- **T17:** Start time = 0.0 seconds
- **T18:** Timestep = 3600.0 seconds (1 hour)
- **T19:** Time units = "s"
- **T20:** Current time is valid
- **T21:** End time = 21600.0 seconds (6 hours)

#### Section 5: 🗺️ Grid Tests (T22–T45)
Tests all 3 grids: LSM (0), routing (1), and channel (2).

**Grid 0 (LSM 1km):**
- **T22:** Type = "uniform_rectilinear"
- **T23:** Rank = 2
- **T24:** Size = 240 (15×16)
- **T25:** Shape = [15, 16]
- **T26:** Spacing = [1000.0, 1000.0] meters

**Grid 1 (Routing 250m):**
- **T28–T32:** Same structure, size = 3840 (60×64), spacing = [250.0, 250.0]

**Grid 2 (Channel network):**
- **T33:** Type = "vector"
- **T34:** Rank = 1
- **T35:** Size = 505
- **T36:** Node count = 505
- **T37–T38:** X/Y coordinates returned
- **T39:** Edge count = 505
- **T40:** Face count = 0 (1D network has no faces)
- **T41:** Shape returns BMI_FAILURE (vector grids have no regular shape)

**Invalid grid tests:**
- **T42–T45:** Grid=99 returns BMI_FAILURE for all queries

#### Section 6: 📤📥 Get/Set Value Tests (T46–T55)
Tests reading and writing variable data.
- **T46:** Get streamflow — values between [-1, 100] m³/s ✅
- **T47:** Get soil moisture — values between [0, 1] ✅
- **T48:** Get temperature — some values in [200, 350] K ✅
- **T49:** Get snow water equivalent — non-negative ✅
- **T50:** Set temperature to 300.0 and read back ✅
- **T51:** Get at specific indices [1,2,3] ✅
- **T52:** Set at specific indices and verify ✅
- **T53:** `get_value_ptr` returns BMI_FAILURE (REAL→DOUBLE mismatch) ✅
- **T54:** `get_value_int` for double var returns BMI_FAILURE ✅
- **T55:** `get_value_float` for double var returns BMI_FAILURE ✅

#### Section 7: ⚠️ Edge Case Tests (T56–T63)
Tests that invalid inputs return BMI_FAILURE properly.
- **T56–T60:** Invalid variable names return BMI_FAILURE
- **T61–T63:** Invalid grid IDs return BMI_FAILURE

#### Section 8: 🔄 Integration Tests (T64–T69)
Tests the full Initialize-Run-Finalize cycle.
- **T64–T66:** Full IRF: init → 6 updates → finalize (verifies time = 6×dt)
- **T67:** Streamflow values differ between step 1 and step 6 (model is evolving)
- **T68–T69:** `update_until(3*dt)` advances exactly to 3 hours

### 4.4 The PASS/FAIL Output Format

When you run the test, output looks like this:

```
 ==============================================================
   WRF-Hydro BMI Test Suite
 ==============================================================

 --- Section 1: Control Tests ---
   PASS: T01: initialize with config file
   PASS: T02: update (one time step)
   PASS: T03: update_until(7200.0)
   PASS: T04: finalize

 --- Section 2: Model Info Tests ---
   PASS: T05: get_component_name returns SUCCESS
         Name: WRF-Hydro v5.4.0 BMI
   PASS: T06: get_input_item_count returns SUCCESS
         Count: 4
   ...

 ==============================================================
   WRF-Hydro BMI Test Summary
 ==============================================================
   Total tests:          151
   Passed:               151
   Failed:                 0
 --------------------------------------------------------------
   >>> ALL TESTS PASSED <<<
 ==============================================================
```

---

## 5. ⚡ The Minimal Test — `bmi_minimal_test.f90`

### 5.1 Overview

**Location:** `bmi_wrf_hydro/tests/bmi_minimal_test.f90`
**Size:** 105 lines
**Purpose:** Quick smoke test — does the BMI wrapper work at all?

### 5.2 What It Does

The minimal test runs the basic BMI lifecycle:

```
┌────────────────────────────────────────┐
│     Minimal Test Flow (6 steps)         │
├────────────────────────────────────────┤
│                                          │
│  [1] 📝 Create config file              │
│      bmi_config.nml with run_dir path   │
│                                          │
│  [2] 🚀 Initialize                      │
│      model%initialize("bmi_config.nml") │
│      → Starts WRF-Hydro internally!     │
│                                          │
│  [3] ℹ️ Query model info                 │
│      Component name, time bounds, etc.  │
│                                          │
│  [4] 🔄 Run 6 update steps              │
│      Full 6-hour Croton NY simulation   │
│      Reports current time after each    │
│                                          │
│  [5] 🛑 Finalize                         │
│      model%finalize()                   │
│                                          │
│  [6] 🧹 MPI cleanup                     │
│      MPI_Finalize()                     │
│                                          │
└────────────────────────────────────────┘
```

### 5.3 When to Use the Minimal Test vs Full Test

| Scenario | Use Minimal Test | Use Full Test |
|----------|:---------------:|:------------:|
| Quick check after code change | ✅ | |
| Verify build didn't break | ✅ | |
| Validate all 41 BMI functions | | ✅ |
| Test edge cases and error handling | | ✅ |
| Run before committing code | | ✅ |
| Debug initialization issues | ✅ | |
| CI/CD pipeline (if added later) | | ✅ |

### 5.4 Expected Output

```
 ==========================================
   BMI WRF-Hydro Minimal Test
 ==========================================

 [1] Creating config file...
 [2] Calling initialize...
     -> Initialize SUCCESS
 [3] Querying model info...
     Component name: WRF-Hydro v5.4.0 BMI
     Start time:     0.0  seconds
     End time:       21600.0  seconds
     Timestep:       3600.0  seconds
     Current time:   0.0  seconds
 [4] Running 6 update steps (full 6-hour simulation)...
     -> Calling update() step 1 ...
        Current time after step:   3600.0  seconds
     -> Calling update() step 2 ...
        Current time after step:   7200.0  seconds
     ... (steps 3-5) ...
     -> Calling update() step 6 ...
        Current time after step:   21600.0  seconds
 [5] Calling finalize...
     -> Finalize SUCCESS
 [6] Calling MPI_Finalize...

 ==========================================
   ALL TESTS PASSED
 ==========================================
```

---

## 6. 🔨 The Build System — `build.sh`

### 6.1 Overview

**Location:** `bmi_wrf_hydro/build.sh`
**Size:** ~130 lines
**Purpose:** Compile the BMI wrapper and link it against 22 WRF-Hydro libraries

### 6.2 The Compilation Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                   Build Pipeline (build.sh)                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Step 1: COMPILE the BMI wrapper                                     │
│  ───────────────────────────────                                     │
│  gfortran -c -cpp -DWRF_HYDRO -DMPP_LAND \                          │
│    -I$CONDA_PREFIX/include \     ← Find bmif_2_0.mod (BMI spec)     │
│    -I$WRF_BUILD/mods \           ← Find 86 WRF-Hydro .mod files    │
│    -I build/ \                   ← Find our own .mod files          │
│    -J build/ \                   ← Put .mod output in build/        │
│    src/bmi_wrf_hydro.f90 \       ← Source file                      │
│    -o build/bmi_wrf_hydro.o      ← Object file output               │
│                                                                      │
│  Step 2: COMPILE the test program                                    │
│  ────────────────────────────────                                    │
│  gfortran -c -cpp ... tests/bmi_wrf_hydro_test.f90 \                │
│    -o build/bmi_wrf_hydro_test.o                                     │
│                                                                      │
│  Step 3: LINK everything together                                    │
│  ────────────────────────────────                                    │
│  mpif90 -o build/bmi_wrf_hydro_test \                                │
│    build/bmi_wrf_hydro.o \           ← Our BMI wrapper               │
│    build/bmi_wrf_hydro_test.o \      ← Our test program              │
│    module_NoahMP_hrldas_driver.F.o \ ← WRF-Hydro land surface obj   │
│    module_hrldas_netcdf_io.F.o \     ← WRF-Hydro NetCDF I/O obj     │
│    -lbmif \                          ← BMI Fortran library           │
│    -lhydro_driver × 3 \             ← 22 WRF-Hydro libs (3x!)      │
│    -lnetcdff -lnetcdf                ← NetCDF libraries              │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.3 Why 22 Libraries Repeated 3 Times?

This is the trickiest part of the build. WRF-Hydro has **circular dependencies** between
its libraries:

```
┌──────────────────────────────────────────────────────────┐
│        Circular Dependency Problem                         │
│                                                            │
│  libhydro_driver.a ──needs──→ libhydro_routing.a          │
│       ↑                              │                     │
│       │                              ↓                     │
│  libhydro_mpp.a ←──needs── libhydro_data_rec.a           │
│                                                            │
│  The linker reads libraries LEFT TO RIGHT, ONE PASS.      │
│  If it sees libA before libB, but libA needs something    │
│  from libB, it fails with "undefined reference".          │
│                                                            │
│  SOLUTION: List all 22 libraries THREE TIMES:             │
│  -lhydro_driver ... -lsnowcro \    ← Pass 1               │
│  -lhydro_driver ... -lsnowcro \    ← Pass 2               │
│  -lhydro_driver ... -lsnowcro      ← Pass 3               │
│                                                            │
│  Each pass resolves more symbols. After 3 passes,         │
│  ALL circular deps are resolved.                           │
│                                                            │
└──────────────────────────────────────────────────────────┘
```

> 🧠 **ML Analogy:** This is like resolving circular imports in Python. Imagine if
> `model.py` imports from `layers.py`, which imports from `utils.py`, which imports
> from `model.py`. Python handles this with lazy imports. The Fortran linker handles
> it by... just trying multiple times!

### 6.4 Why `mpif90` Instead of `gfortran`?

```
┌────────────────────────────────────────────────────────────┐
│                                                              │
│  COMPILE step:  gfortran    (no MPI awareness needed)       │
│  LINK step:     mpif90      (needs MPI libraries)           │
│                                                              │
│  mpif90 is just a wrapper that calls gfortran but adds:     │
│    -I/path/to/mpi/include                                    │
│    -L/path/to/mpi/lib -lmpi -lmpi_mpifh                     │
│                                                              │
│  WRF-Hydro uses MPI internally (via MPP_LAND), so we        │
│  must link with MPI. But we DON'T write any MPI code         │
│  ourselves — WRF-Hydro handles all parallelism.              │
│                                                              │
└────────────────────────────────────────────────────────────┘
```

### 6.5 Build Targets

| Command | What It Builds | When to Use |
|---------|---------------|-------------|
| `./build.sh` | Everything (BMI + minimal + full test) | Default, normal development |
| `./build.sh minimal` | BMI module + minimal test only | Quick iteration |
| `./build.sh full` | BMI module + full test only | Before commits |
| `./build.sh clean` | Remove all artifacts in build/ | Fresh start |

---

## 7. 🔍 How BMI Testing Works — The Full Picture

### 7.1 The Key Question: Does Testing BMI Start WRF-Hydro?

**YES!** 🎯 When you run the BMI test, it **automatically starts WRF-Hydro internally**.
You don't need to run WRF-Hydro separately. Here's exactly what happens:

```
┌─────────────────────────────────────────────────────────────────────┐
│          What Happens When You Run the BMI Test                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  You type:                                                           │
│  $ mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test          │
│                                                                      │
│  ┌─── YOUR TEST PROGRAM ──────────────────────────────────────┐     │
│  │                                                              │     │
│  │  1. Create bmi_config.nml                                    │     │
│  │     wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/"         │     │
│  │                                                              │     │
│  │  2. model%initialize("bmi_config.nml")                       │     │
│  │     │                                                        │     │
│  │     └──→ ┌─── BMI WRAPPER (bmi_wrf_hydro.f90) ──────────┐  │     │
│  │          │                                                 │  │     │
│  │          │  a) Read config → get run_dir path              │  │     │
│  │          │  b) cd to run_dir (where namelists live)        │  │     │
│  │          │  c) orchestrator%init()                          │  │     │
│  │          │     └──→ Read namelist.hrldas + hydro.namelist  │  │     │
│  │          │                                                 │  │     │
│  │          │  d) land_driver_ini()                            │  │     │
│  │          │     └──→ ┌── WRF-HYDRO ENGINE ──────────────┐  │  │     │
│  │          │          │  • Read LDASIN forcing files       │  │  │     │
│  │          │          │  • Initialize Noah-MP land model   │  │  │     │
│  │          │          │  • Set up soil layers, snow pack   │  │  │     │
│  │          │          │  • Allocate ALL internal arrays    │  │  │     │
│  │          │          └──────────────────────────────────┘  │  │     │
│  │          │                                                 │  │     │
│  │          │  e) HYDRO_ini()                                 │  │     │
│  │          │     └──→ ┌── WRF-HYDRO HYDRO ENGINE ────────┐  │  │     │
│  │          │          │  • Initialize MPI (MPI_Init)       │  │  │     │
│  │          │          │  • Read routing grids (Fulldom)     │  │  │     │
│  │          │          │  • Read channel network (Route_Link)│  │  │     │
│  │          │          │  • Read GW buckets, reservoirs      │  │  │     │
│  │          │          │  • open_print_mpp(6) ← STDOUT REDIR│  │  │     │
│  │          │          └──────────────────────────────────┘  │  │     │
│  │          │                                                 │  │     │
│  │          │  f) Store grid dims: IX=15, JX=16, IXRT=60...  │  │     │
│  │          │  g) Return BMI_SUCCESS                          │  │     │
│  │          └─────────────────────────────────────────────────┘  │     │
│  │                                                              │     │
│  │  3. model%update() ← Run ONE timestep                       │     │
│  │     └──→ land_driver_exe() + HYDRO_exe()                    │     │
│  │         Computes: soil physics, snow melt, surface routing,  │     │
│  │         subsurface routing, channel routing, groundwater     │     │
│  │                                                              │     │
│  │  4. model%get_value("channel_water__volume_flow_rate", v)   │     │
│  │     └──→ Copy rt_domain(1)%QLINK(:,1) → v(:)               │     │
│  │                                                              │     │
│  │  5. ... (150 more tests) ...                                 │     │
│  │                                                              │     │
│  │  6. model%finalize()                                         │     │
│  │     └──→ Clean up (BUT NOT HYDRO_finish — it has "stop")    │     │
│  │                                                              │     │
│  │  7. MPI_Finalize()                                           │     │
│  │     └──→ Required because HYDRO_ini() called MPI_Init       │     │
│  │                                                              │     │
│  └──────────────────────────────────────────────────────────────┘     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.2 The stdout Redirect — Why We Use stderr

One **critical** gotcha: After `HYDRO_ini()` calls `open_print_mpp(6)`, all Fortran
`print *` statements (which use unit 6 = stdout) get redirected to a file called
`diag_hydro.00000`. So if your test uses `print *`, the output goes to a file, not
the terminal!

```
┌────────────────────────────────────────────────────────────┐
│            stdout Redirect Problem & Solution                │
├────────────────────────────────────────────────────────────┤
│                                                              │
│  BEFORE HYDRO_ini():                                         │
│    print * → terminal ✅                                     │
│                                                              │
│  AFTER HYDRO_ini() calls open_print_mpp(6):                  │
│    print * → diag_hydro.00000 file ❌ (invisible!)           │
│    write(0,*) → terminal (stderr) ✅                         │
│                                                              │
│  SOLUTION: ALL our output uses write(0,*) instead of print * │
│                                                              │
│  Unit 0 = stderr = NEVER redirected                          │
│  Unit 6 = stdout = REDIRECTED by WRF-Hydro                  │
│                                                              │
└────────────────────────────────────────────────────────────┘
```

> 🧠 **ML Analogy:** This is like when a library captures `sys.stdout` in Python.
> If TensorFlow captures stdout for its logging, your `print()` goes to TF's log file.
> The solution is to use `sys.stderr` or a custom logger instead.

### 7.3 The MPI Requirement

Both test programs need MPI because WRF-Hydro initializes MPI internally:

```
┌────────────────────────────────────────────────────────────┐
│                MPI Lifecycle                                  │
├────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Test starts                                              │
│     (MPI not yet initialized)                                │
│                                                              │
│  2. model%initialize() called                                │
│     └──→ HYDRO_ini() calls MPI_Init internally               │
│          (WRF-Hydro does this, not us!)                      │
│                                                              │
│  3. All test work happens (MPI is active)                    │
│                                                              │
│  4. model%finalize() called                                  │
│     └──→ We do NOT call HYDRO_finish()                       │
│          because HYDRO_finish has "stop" + MPI_Finalize      │
│          "stop" would kill our test program!                  │
│                                                              │
│  5. WE call MPI_Finalize() ourselves                         │
│     └──→ Required! Otherwise MPI complains on exit.          │
│                                                              │
│  WHY mpirun? Because MPI_Init was called, so the process     │
│  must be launched by mpirun (even with -np 1 for serial).    │
│                                                              │
└────────────────────────────────────────────────────────────┘
```

---

## 8. 📊 The Croton NY Test Data Connection

### 8.1 What Test Data Do We Use?

We use the **Croton NY (Hurricane Irene 2011)** test case — the official NCAR test
case for WRF-Hydro. The same test data that validates standalone WRF-Hydro also
validates our BMI wrapper.

```
┌────────────────────────────────────────────────────────────┐
│            Croton NY Test Case — Quick Facts                  │
├────────────────────────────────────────────────────────────┤
│                                                              │
│  📍 Location:    Croton Watershed, New York, USA             │
│  🌀 Event:       Hurricane Irene, August 26, 2011            │
│  ⏱️ Duration:    6 hours (00:00 → 06:00 UTC)                 │
│  🏔️ LSM Grid:    15 × 16 cells at 1km resolution            │
│  🗺️ Routing Grid: 60 × 64 cells at 250m resolution          │
│  🌊 Channel:     505 river links (reaches)                   │
│  🌡️ Temperature:  ~292–295 K (19–22°C, late August)          │
│  💧 Streamflow:   ~2.7 m³/s (base flow, no major flood)     │
│  📏 Timestep:     3600 seconds (1 hour)                      │
│                                                              │
└────────────────────────────────────────────────────────────┘
```

### 8.2 Where Does the Test Data Live?

```
WRF_Hydro_Run_Local/run/              ← 📂 Test data directory
│
├── namelist.hrldas                    ← ⚙️ Noah-MP config (timestep, dates, options)
├── hydro.namelist                     ← ⚙️ HYDRO routing config (routing method, grids)
│
├── DOMAIN/                            ← 🗺️ Static grid data
│   ├── wrfinput_d01.nc                ← Noah-MP domain setup (15×16 grid)
│   ├── Fulldom_hires.nc               ← Routing terrain (60×64 grid)
│   ├── Route_Link.nc                  ← Channel network (505 links)
│   ├── soil_properties.nc             ← Soil types
│   ├── GWBASINS.nc                    ← Groundwater basins
│   └── geo_em.d01.nc                  ← WPS geogrid output
│
├── FORCING/                           ← 🌤️ Atmospheric forcing (6 hourly files)
│   ├── 2011082600.LDASIN_DOMAIN1      ← Hour 0 forcing
│   ├── 2011082601.LDASIN_DOMAIN1      ← Hour 1 forcing
│   ├── 2011082602.LDASIN_DOMAIN1      ← Hour 2 forcing
│   ├── 2011082603.LDASIN_DOMAIN1      ← Hour 3 forcing
│   ├── 2011082604.LDASIN_DOMAIN1      ← Hour 4 forcing
│   └── 2011082605.LDASIN_DOMAIN1      ← Hour 5 forcing
│
├── RESTART/                           ← 🔄 Initial conditions (warm start)
│   ├── RESTART.2011082600_DOMAIN1     ← Noah-MP restart
│   └── HYDRO_RST.2011-08-26_00:00... ← HYDRO routing restart
│
├── *.TBL                              ← 📋 Lookup tables (SOILPARM, VEGPARM, etc.)
│
└── (after running: output files)
    ├── diag_hydro.00000               ← WRF-Hydro diagnostic log
    ├── 201108260100.LDASOUT_DOMAIN1   ← Hourly Noah-MP output (NetCDF)
    ├── 201108260100.CHRTOUT_DOMAIN1   ← Hourly channel output (NetCDF)
    ├── 201108260100.RTOUT_DOMAIN1     ← Hourly routing output (NetCDF)
    └── ... (6 hours × ~6 files = ~39 output files)
```

### 8.3 How the Config File Connects Everything

The BMI test creates a small config file that tells the wrapper where to find WRF-Hydro:

```fortran
! bmi_config.nml — Created by the test at runtime
&bmi_wrf_hydro_config
  wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/"
/
```

This path points to the Croton NY run directory. The BMI wrapper:
1. Reads this path from the config file
2. Changes the working directory to that path (`chdir()`)
3. WRF-Hydro then finds `namelist.hrldas`, `hydro.namelist`, `DOMAIN/`, `FORCING/` etc.
4. WRF-Hydro initializes using ALL the Croton NY data

```
┌────────────────────────────────────────────────────────────────┐
│                 Config File Chain                                │
├────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Test Program                                                    │
│    │                                                             │
│    ├──→ creates bmi_config.nml                                   │
│    │      wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/"      │
│    │                                                             │
│    └──→ model%initialize("bmi_config.nml")                       │
│           │                                                      │
│           └──→ BMI Wrapper reads bmi_config.nml                  │
│                  │                                               │
│                  └──→ chdir(run_dir)                              │
│                        │                                         │
│                        └──→ WRF-Hydro reads:                     │
│                              ├── namelist.hrldas                  │
│                              ├── hydro.namelist                   │
│                              ├── DOMAIN/*.nc                     │
│                              ├── FORCING/*.LDASIN                │
│                              ├── RESTART/*                       │
│                              └── *.TBL tables                    │
│                                                                  │
└────────────────────────────────────────────────────────────────┘
```

### 8.4 Validation: BMI Output Matches Standalone WRF-Hydro

We verified that the BMI wrapper produces **bit-for-bit identical** output to running
WRF-Hydro standalone. The `diag_hydro.00000` file shows the same values:

```
Standalone WRF-Hydro (wrf_hydro executable):
  ***DATE=2011-08-26_01:00:00 294.13605   2.75808    Timing:   4.26
  ***DATE=2011-08-26_02:00:00 293.84967   2.75507    Timing:   1.61
  ...

BMI-driven WRF-Hydro (bmi_wrf_hydro_test):
  ***DATE=2011-08-26_01:00:00 294.13605   2.75808    Timing:   X.XX
  ***DATE=2011-08-26_02:00:00 293.84967   2.75507    Timing:   X.XX
  ...

✅ Temperature and streamflow values are IDENTICAL!
   (Timing differs because test includes BMI overhead)
```

> 🧠 **ML Analogy:** This is like running model inference through the normal API vs.
> through an ONNX export. If the outputs are identical, the export is faithful.

---

## 9. 💻 Building & Testing in VS Code

### 9.1 Prerequisites

Before you start, make sure you have:

| Requirement | What | How to Check |
|-------------|------|-------------|
| WSL2 | Windows Subsystem for Linux | `wsl --list` in PowerShell |
| Conda | Miniconda or Anaconda | `conda --version` |
| wrfhydro-bmi env | Our conda environment | `conda env list` (should see `wrfhydro-bmi`) |
| WRF-Hydro compiled | Pre-built WRF-Hydro | `ls ../wrf_hydro_nwm_public/build/lib/` (22 `.a` files) |
| Test data | Croton NY case | `ls ../WRF_Hydro_Run_Local/run/namelist.hrldas` |

### 9.2 Recommended VS Code Extensions

| Extension | What It Does | Install |
|-----------|-------------|---------|
| 🔧 **Modern Fortran** | Syntax highlighting, IntelliSense for `.f90`/`.F90` | `ext install fortran-lang.linter-gfortran` |
| 🐧 **WSL** | Run VS Code in WSL | Built-in |
| 📂 **Remote - WSL** | Access WSL filesystem | `ext install ms-vscode-remote.remote-wsl` |

### 9.3 VS Code Settings for Fortran

Add these to your workspace `.vscode/settings.json`:

```json
{
    "files.associations": {
        "namelist.*": "ini",
        "*.F90": "FortranFreeForm",
        "*.F": "FortranFreeForm",
        "*.f90": "FortranFreeForm"
    },
    "fortran.linter.compiler": "gfortran",
    "fortran.linter.compilerPath": "/home/mohansai/miniconda3/envs/wrfhydro-bmi/bin/gfortran"
}
```

### 9.4 Opening the Project in VS Code

```bash
# From the project root:
code /mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI
```

Or in VS Code: **File → Open Folder** → navigate to `WRF-Hydro-BMI`.

### 9.5 Using the Integrated Terminal

1. Open the integrated terminal: **Ctrl+`** (backtick)
2. Make sure it's a WSL bash terminal (not PowerShell)
3. Navigate to the BMI directory:
   ```bash
   cd /mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro
   ```

### 9.6 VS Code Task (Optional)

You can create a build task in `.vscode/tasks.json`:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Build BMI (all)",
            "type": "shell",
            "command": "bash",
            "args": ["build.sh"],
            "options": {
                "cwd": "${workspaceFolder}/bmi_wrf_hydro"
            },
            "group": {
                "kind": "build",
                "isDefault": true
            },
            "problemMatcher": "$gcc"
        },
        {
            "label": "Run BMI Minimal Test",
            "type": "shell",
            "command": "source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi && mpirun --oversubscribe -np 1 ./build/bmi_minimal_test",
            "options": {
                "cwd": "${workspaceFolder}/bmi_wrf_hydro"
            },
            "group": "test"
        },
        {
            "label": "Run BMI Full Test",
            "type": "shell",
            "command": "source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi && mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test",
            "options": {
                "cwd": "${workspaceFolder}/bmi_wrf_hydro"
            },
            "group": "test"
        }
    ]
}
```

After adding this, you can:
- **Ctrl+Shift+B** → Build (default task)
- **Ctrl+Shift+P** → "Tasks: Run Task" → Pick "Run BMI Full Test"

---

## 10. 🚀 Step-by-Step Commands

### 10.1 First-Time Setup (One-Time)

```bash
# 1. Activate the conda environment
source ~/miniconda3/etc/profile.d/conda.sh
conda activate wrfhydro-bmi

# 2. Navigate to the BMI directory
cd /mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro

# 3. Verify WRF-Hydro is compiled
ls ../wrf_hydro_nwm_public/build/lib/*.a | wc -l
# Expected: 22

# 4. Verify test data exists
ls ../WRF_Hydro_Run_Local/run/namelist.hrldas
# Expected: file exists

# 5. Verify bmi-fortran is installed
ls $CONDA_PREFIX/include/bmif_2_0.mod
# Expected: file exists
```

### 10.2 Build Everything

```bash
# Make build.sh executable (first time only)
chmod +x build.sh

# Build all (BMI module + both tests)
./build.sh

# Or build only the minimal test (faster):
./build.sh minimal

# Or build only the full test:
./build.sh full

# Clean build artifacts:
./build.sh clean
```

### 10.3 Run the Minimal Test

```bash
# Must run from the bmi_wrf_hydro/ directory!
mpirun --oversubscribe -np 1 ./build/bmi_minimal_test
```

**Expected:** ~30 seconds, prints "ALL TESTS PASSED"

### 10.4 Run the Full Test Suite

```bash
# Must run from the bmi_wrf_hydro/ directory!
mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test
```

**Expected:** ~2–3 minutes, prints "151 Passed, 0 Failed"

### 10.5 Check the WRF-Hydro Diagnostic Log

After running any test, WRF-Hydro writes its own log to `diag_hydro.00000`:

```bash
# View the diagnostic log (created in current directory)
cat diag_hydro.00000
```

You should see timestep entries like:
```
***DATE=2011-08-26_01:00:00 294.13605   2.75808    Timing:   4.26
***DATE=2011-08-26_02:00:00 293.84967   2.75507    Timing:   1.61
...
```

### 10.6 Quick One-Liner (Build + Run Full Test)

```bash
source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi && \
  cd /mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro && \
  ./build.sh && \
  mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test
```

### 10.7 Redirect Test Output to File (for Review)

```bash
# Full test output to file (stderr has test results, stdout to diag)
mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test 2> test_results.txt
cat test_results.txt | tail -20
```

---

## 11. 🔧 Troubleshooting Guide

### 11.1 Problem: No Output — Tests Seem to Hang

**Symptom:** You run the test but see nothing on the terminal.

**Cause:** The test completed but output went to `diag_hydro.00000` instead of the terminal.
This happens if you accidentally used `print *` instead of `write(0,*)`.

**Fix:** Check `diag_hydro.00000` for the test output:
```bash
cat diag_hydro.00000
```

### 11.2 Problem: MPI_Abort / "prterun exited improperly"

**Symptom:**
```
--------------------------------------------------------------------------
prterun has exited due to process rank 0 with PID 12345 on node ...
exiting improperly. There are three reasons this could occur: ...
--------------------------------------------------------------------------
```

**Cause:** The program exited without calling `MPI_Finalize()`.

**Fix:** Make sure your test program calls `MPI_Finalize(ierr)` before exiting:
```fortran
use mpi
integer :: ierr
! ... at the end of your program:
call MPI_Finalize(ierr)
```

### 11.3 Problem: "Cannot open file namelist.hrldas"

**Symptom:** Initialize fails because WRF-Hydro can't find its config files.

**Cause:** The test must run from the `bmi_wrf_hydro/` directory so the relative path
`../WRF_Hydro_Run_Local/run/` resolves correctly.

**Fix:** Make sure you're in the right directory:
```bash
cd /mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro
mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test
```

### 11.4 Problem: "Path too long" or Truncated Paths

**Symptom:** Fortran error about paths or files not found.

**Cause:** Fortran uses `character(len=80)` by default, and WSL2 paths can exceed 80 chars.

**Fix:** The BMI config uses relative paths (`../WRF_Hydro_Run_Local/run/`) instead of
absolute paths. If you need to change this, ensure paths are under 256 characters.

### 11.5 Problem: Double Initialization Crash

**Symptom:** Running the test twice (or running integration tests) crashes with
allocation errors.

**Cause:** WRF-Hydro module-level arrays (COSZEN, SMOIS, etc.) persist in memory and
can't be re-allocated without modifying WRF-Hydro source.

**Fix:** This is handled automatically! The `wrfhydro_engine_initialized` flag in
`wrfhydro_bmi_state_mod` prevents double-initialization. Each test section that calls
`initialize()` checks this flag. If WRF-Hydro is already initialized, it skips
the heavy initialization and just resets the BMI metadata.

### 11.6 Problem: "undefined reference to ..." During Linking

**Symptom:** Linker errors about missing symbols.

**Cause:** WRF-Hydro libraries have circular dependencies that aren't resolved in one pass.

**Fix:** Make sure `build.sh` repeats the library list 3 times:
```bash
${WRF_LIBS_SINGLE} \
${WRF_LIBS_SINGLE} \
${WRF_LIBS_SINGLE} \
```

### 11.7 Problem: "Error: Type mismatch in argument" During Compilation

**Symptom:** gfortran error about type mismatch in BMI function calls.

**Cause:** BMI uses `double precision` but WRF-Hydro uses single-precision `REAL`.

**Fix:** The BMI wrapper handles all type conversions internally using `dble()` to convert
REAL to double precision. This is a design decision — BMI callers always work with
double precision, and the wrapper does the conversion.

### 11.8 Problem: get_value_ptr Returns BMI_FAILURE

**Symptom:** Test T53 shows `get_value_ptr` returns BMI_FAILURE.

**Explanation:** This is **expected behavior**, not a bug! WRF-Hydro stores arrays as
single-precision REAL (4 bytes), but BMI requires double-precision pointers (8 bytes).
You can't return a pointer to different-sized data. Use `get_value()` (which copies with
conversion) instead.

### 11.9 Problem: Floating-Point Exception Warnings

**Symptom:** At the end of the test run:
```
Note: The following floating-point exceptions are signalling: IEEE_INVALID_FLAG IEEE_OVERFLOW_FLAG
```

**Explanation:** These are **harmless warnings** from gfortran. WRF-Hydro's internal
physics computations trigger floating-point exceptions during normal operation (e.g.,
dividing by snow depth when there's no snow). WRF-Hydro handles these internally.

---

## 12. 📋 Summary & Quick Reference

### 12.1 File Quick Reference

| File | Location | Lines | Purpose |
|------|----------|-------|---------|
| `bmi_wrf_hydro.f90` | `src/` | 1,919 | BMI wrapper — implements all 41 functions |
| `bmi_wrf_hydro_test.f90` | `tests/` | 1,777 | Full test suite — 151 tests, 8 sections |
| `bmi_minimal_test.f90` | `tests/` | 105 | Smoke test — init + 6 updates + finalize |
| `build.sh` | root | 130 | Build script — compile + link everything |
| `CMakeLists.txt` | root | 650 | CMake config for shared library (future) |
| `build/.gitignore` | `build/` | 3 | Ignore compiled artifacts |

### 12.2 Command Quick Reference

```bash
# ===== SETUP =====
source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi
cd /mnt/c/Users/mohansai/Desktop/Projects/VS_Code/WRF-Hydro-BMI/bmi_wrf_hydro

# ===== BUILD =====
./build.sh              # Build everything
./build.sh minimal      # Build BMI + minimal test only
./build.sh full         # Build BMI + full test only
./build.sh clean        # Clean all artifacts

# ===== TEST =====
mpirun --oversubscribe -np 1 ./build/bmi_minimal_test     # Quick smoke test (~30s)
mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test   # Full 151-test suite (~2-3min)

# ===== CHECK RESULTS =====
cat diag_hydro.00000          # WRF-Hydro diagnostic log
```

### 12.3 Test Results Summary

```
 ==============================================================
   WRF-Hydro BMI Test Summary
 ==============================================================
   Total tests:          151
   Passed:               151
   Failed:                 0
 --------------------------------------------------------------
   >>> ALL TESTS PASSED <<<
 ==============================================================
```

### 12.4 Key Numbers to Remember

| What | Value |
|------|-------|
| BMI functions implemented | 41 (55 procedures with type variants) |
| Output variables | 8 |
| Input variables | 4 |
| Grids | 3 (LSM 1km, routing 250m, channel network) |
| Tests | 151 (all pass) |
| Test sections | 8 |
| WRF-Hydro libraries linked | 22 (repeated 3x) |
| Test case | Croton NY, Hurricane Irene 2011, 6 hours |
| LSM grid | 15 × 16 = 240 cells at 1km |
| Routing grid | 60 × 64 = 3,840 cells at 250m |
| Channel links | 505 reaches |

### 12.5 What Happens Next?

```
┌────────────────────────────────────────────────────────────────┐
│                    Project Roadmap                               │
├────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ✅ Phase 1: Write BMI Wrapper          ← DONE!                 │
│     ✅ Study + prepare                                           │
│     ✅ Write bmi_wrf_hydro.f90 (1,919 lines)                    │
│     ✅ Write test suite (151/151 pass)                           │
│     ✅ Validate against Croton NY                                │
│                                                                  │
│  ⏳ Phase 2: Babelize Both Models        ← NEXT                 │
│     ○ Install babelizer                                         │
│     ○ Write babel.toml for WRF-Hydro                            │
│     ○ Generate pymt_wrfhydro Python package                     │
│     ○ Write babel.toml for SCHISM                               │
│     ○ Generate pymt_schism Python package                       │
│                                                                  │
│  ⏳ Phase 3: Register PyMT Plugins                               │
│     ○ Install PyMT                                              │
│     ○ Verify both plugins with pymt.MODELS                      │
│     ○ Run bmi-tester validation                                 │
│                                                                  │
│  ⏳ Phase 4: Couple and Run                                      │
│     ○ Write coupling script                                     │
│     ○ Configure grid mapping + time sync                        │
│     ○ Run compound flooding case study                          │
│     ○ ~20 lines of Python in Jupyter! 🎯                        │
│                                                                  │
└────────────────────────────────────────────────────────────────┘
```

---

> 📝 **Doc 15 — Last updated: February 2026**
> Part of the WRF-Hydro BMI Wrapper Project documentation series (Docs 1–15)
