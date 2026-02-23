# 🌊 WRF-Hydro: The Complete Beginner's Guide for ML Engineers

> **You know PyTorch. You know Python. You've never touched Fortran or hydrology.**
> This guide bridges that gap — explaining everything using ML analogies you already understand.

---

## 📑 Table of Contents

1. [What is Fortran? (ML Engineer's Perspective)](#1--what-is-fortran-ml-engineers-perspective)
2. [What is WRF-Hydro? (The Big Picture)](#2--what-is-wrf-hydro-the-big-picture)
3. [Complete Folder Structure](#3--complete-folder-structure)
4. [Key Source Files Explained](#4--key-source-files-explained)
5. [Configuration Files (The Namelists)](#5--configuration-files-the-namelists)
6. [Build Process Step-by-Step](#6--build-process-step-by-step)
7. [Input Data — What the Model Needs](#7--input-data--what-the-model-needs)
8. [Running the Model Step-by-Step](#8--running-the-model-step-by-step)
9. [Output Data — What the Model Produces](#9--output-data--what-the-model-produces)
10. [Quick Reference Card](#10--quick-reference-card)

---

## 1. 🖥️ What is Fortran? (ML Engineer's Perspective)

### 1.1 Why Fortran Exists (and Why It Won't Die)

Fortran (FORmula TRANslation) was born in 1957 — the **first high-level programming language ever**.
It's still alive because it does one thing extraordinarily well: **fast number crunching on arrays**.

> **🧠 ML Analogy:**
> Fortran is to physics/weather models what **CUDA C++** is to deep learning frameworks.
> You *could* write everything in Python, but when you need to simulate the entire U.S. river
> network (2.7 million river segments) at 10-second timesteps, you need raw compiled speed.
>
> - **Python + PyTorch** = flexible, GPU-accelerated deep learning
> - **Fortran + MPI** = flexible, CPU-accelerated physics simulation
>
> Both are "backends" that scientists control from higher-level interfaces.

### 1.2 Fortran Evolution (Quick Timeline)

| Year | Version | What Changed | ML Equivalent |
|------|---------|-------------|---------------|
| 1957 | Fortran | First compiler ever | Assembly language era |
| 1977 | Fortran 77 | Structured programming | Early C |
| 1990 | **Fortran 90** | Free-form, arrays, modules | C++ with STL |
| 2003 | **Fortran 2003** | OOP, ISO_C_BINDING | Modern C++ |
| 2008 | Fortran 2008 | Coarrays (parallel) | CUDA kernels |

- 📌 **WRF-Hydro** is written in **Fortran 90** (with some F77 legacy)
- 📌 **Our BMI wrapper** will be **Fortran 2003** (needed for `ISO_C_BINDING` to talk to Python)

### 1.3 File Extensions Explained

| Extension | Meaning | Preprocessor? | ML Equivalent |
|-----------|---------|--------------|---------------|
| `.f90` | Free-form Fortran 90+ | ❌ No | `.py` |
| `.F90` | Free-form Fortran 90+ | ✅ Yes (C preprocessor) | `.py` with `#ifdef` macros |
| `.F` | Free-form Fortran | ✅ Yes (C preprocessor) | `.py` with conditional imports |
| `.f` | Fixed-form (legacy F77) | ❌ No | Ancient code, columns matter |

> **💡 Key insight:** The **capital letter** means "run the C preprocessor first."
> WRF-Hydro uses `.F90` and `.F` extensively because it has `#ifdef MPP_LAND`, `#ifdef WRF_HYDRO`,
> etc. — compile-time switches that enable/disable features like MPI parallelism.
>
> Think of it like `#ifdef USE_CUDA` in C++ deep learning code.

### 1.4 Python vs Fortran: Side-by-Side Comparison

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PYTHON vs FORTRAN CHEAT SHEET                     │
├───────────────────────────┬─────────────────────────────────────────┤
│ PYTHON                    │ FORTRAN                                 │
├───────────────────────────┼─────────────────────────────────────────┤
│                           │                                         │
│ # Variables               │ ! Variables (! = comment)               │
│ x = 3.14                  │ real :: x = 3.14                        │
│ n = 42                    │ integer :: n = 42                       │
│ name = "hello"            │ character(len=5) :: name = "hello"      │
│                           │                                         │
│ # Arrays                  │ ! Arrays (1-indexed by default!)        │
│ a = np.zeros(100)         │ real, dimension(100) :: a               │
│ b = np.zeros((10, 20))    │ real, dimension(10, 20) :: b            │
│ a[0]  # first element     │ a(1)  ! first element (1-indexed!)      │
│                           │                                         │
│ # Loops                   │ ! Loops                                 │
│ for i in range(10):       │ do i = 1, 10                            │
│     print(i)              │     print *, i                          │
│                           │ end do                                  │
│                           │                                         │
│ # Functions               │ ! Functions                             │
│ def add(a, b):            │ function add(a, b) result(c)            │
│     return a + b          │     real, intent(in) :: a, b            │
│                           │     real :: c                           │
│                           │     c = a + b                           │
│                           │ end function add                        │
│                           │                                         │
│ # Subroutines (no return) │ ! Subroutines (modify args in place)    │
│ def update(arr):          │ subroutine update(arr)                  │
│     arr[:] = arr * 2      │     real, intent(inout) :: arr(:)       │
│     # no return needed    │     arr = arr * 2                       │
│                           │ end subroutine update                   │
│                           │                                         │
│ # Modules                 │ ! Modules                               │
│ import numpy as np        │ use module_routing, only: landrt_ini    │
│ from torch import nn      │                                         │
│                           │                                         │
│ # Classes                 │ ! Derived Types (= classes)             │
│ class Model:              │ type :: Model                           │
│     def __init__(self):   │     real :: weight                      │
│         self.weight = 0.0 │ end type Model                          │
│                           │                                         │
│ # if/else                 │ ! if/else                               │
│ if x > 0:                 │ if (x > 0) then                         │
│     print("positive")     │     print *, "positive"                 │
│ else:                     │ else                                    │
│     print("negative")     │     print *, "negative"                 │
│                           │ end if                                  │
├───────────────────────────┴─────────────────────────────────────────┤
│ KEY DIFFERENCES:                                                     │
│ ✅ Fortran arrays are 1-indexed (like MATLAB, unlike Python's 0)     │
│ ✅ Fortran is COLUMN-MAJOR (like MATLAB), Python/C are ROW-MAJOR     │
│ ✅ Fortran uses `intent(in/out/inout)` — like type hints for args    │
│ ✅ Fortran has subroutines (void) AND functions (return value)        │
│ ✅ Fortran `module` ≈ Python `module` — use `use` instead of import  │
│ ✅ Fortran is statically typed — every variable MUST be declared      │
└─────────────────────────────────────────────────────────────────────┘
```

> **🧠 ML Analogy:**
> - Fortran `module` = Python module (a `.py` file with functions/classes)
> - Fortran `type` = Python `class` (or `dataclass`)
> - Fortran `subroutine` = Python method with no return (modifies args in place)
> - Fortran `intent(in)` = `const` in C++ — promise not to modify
> - Fortran `intent(inout)` = mutable reference — will modify in place

### 1.5 The Column-Major Gotcha

This is the **#1 trap** for Python/C programmers:

```
Python/C (row-major):      Fortran (column-major):
Memory layout: [1,2,3,     Memory layout: [1,4,
                4,5,6]                      2,5,
                                            3,6]

arr[row][col]              arr(row, col)
Fastest varying: LAST dim  Fastest varying: FIRST dim
```

> **🧠 ML Analogy:** This is why BMI flattens all arrays to 1D — to avoid
> confusion between row-major (C/Python) and column-major (Fortran) layouts.
> It's the same reason you call `.contiguous()` in PyTorch before certain operations.

---

## 2. 🌧️ What is WRF-Hydro? (The Big Picture)

### 2.1 One-Sentence Summary

**WRF-Hydro is a physics-based model that simulates where water goes after it rains.**

It tracks water from the moment a raindrop hits the ground, through soil, across land surfaces,
into streams and rivers, and eventually out to the ocean.

### 2.2 The Water Journey (ASCII Flowchart)

```
    ☁️ ATMOSPHERE (forcing data: rain, temperature, wind, radiation)
    │
    │  🌧️ precipitation falls
    ▼
┌─────────────────────────────────────────────────────────┐
│  🌿 NOAH-MP LAND SURFACE MODEL (1km grid)               │
│                                                          │
│  What happens here:                                      │
│  • Rain hits vegetation canopy (some intercepted)        │
│  • Snow accumulates/melts on ground                      │
│  • Water infiltrates into soil (4 layers)                │
│  • Plants transpire water back to atmosphere             │
│  • Surface energy balance (radiation, heat fluxes)       │
│                                                          │
│  📊 Outputs: soil moisture, snow depth, evaporation,     │
│             surface runoff, underground drainage          │
└───────────────┬─────────────────────┬───────────────────┘
                │                     │
    surface runoff                underground drainage
    (excess water)                (slow seepage)
                │                     │
                ▼                     ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│ 🏔️ TERRAIN ROUTING       │  │ 💧 SUBSURFACE ROUTING     │
│ (250m grid)              │  │ (250m grid)               │
│                          │  │                           │
│ Overland flow: water     │  │ Shallow groundwater       │
│ runs downhill across     │  │ moves laterally through   │
│ land surface following   │  │ soil following water      │
│ elevation gradients      │  │ table gradients           │
│ (steepest descent/D8)    │  │                           │
└──────────┬───────────────┘  └────────────┬──────────────┘
           │                               │
           │    water reaches channels     │
           ▼                               ▼
┌─────────────────────────────────────────────────────────┐
│  🌊 CHANNEL ROUTING (river network)                      │
│                                                          │
│  Methods available:                                      │
│  • Diffusive Wave (gridded, 250m)                        │
│  • Muskingum-Cunge (reach-based, NHDPlus)               │
│  • Muskingum (reach-based, simpler)                      │
│                                                          │
│  Also handles:                                           │
│  • 🏞️ Lakes & Reservoirs (level pool routing)            │
│  • 🔄 Diversions (water withdrawals)                     │
│                                                          │
│  📊 Output: streamflow (discharge) at every river point  │
└───────────────┬─────────────────────────────────────────┘
                │
                │  ← 🔄 GROUNDWATER/BASEFLOW feeds back
                │     (exponential bucket model)
                ▼
        🌊 RIVER DISCHARGE → 🏖️ OCEAN (SCHISM receives this!)
```

### 2.3 The ML Pipeline Analogy

> **🧠 ML Analogy:** WRF-Hydro is a **multi-stage inference pipeline**, just like a production ML system:
>
> | WRF-Hydro Stage | ML Pipeline Equivalent |
> |----------------|----------------------|
> | Forcing data (rain, temp) | Input features / raw data |
> | Noah-MP land surface | Feature extraction layers |
> | Terrain routing | Convolutional processing (spatial) |
> | Channel routing | Sequence model (temporal, along rivers) |
> | Groundwater bucket | Skip connection / residual pathway |
> | Output (streamflow) | Model predictions |
> | Calibration parameters | Learned weights |
> | Namelist config files | Hyperparameter config (YAML) |
> | Restart files | Model checkpoints |
>
> The key difference: ML models **learn** patterns from data.
> WRF-Hydro **solves physics equations** (mass/energy conservation).
> But the architecture is strikingly similar!

### 2.4 The 4 Physics Components

#### 🌿 Component 1: Noah-MP Land Surface Model
- **Grid:** 1km uniform rectilinear
- **What it does:** Solves the land surface energy and water balance
- **Physics:** Radiation, heat transfer, evapotranspiration, snow, soil moisture
- **ML analogy:** Feature extraction backbone (like ResNet in an object detection pipeline)
- **Key variables:** soil moisture (SOIL_M), snow (SNEQV), evaporation (ACCET), temperature (T2)

#### 🏔️ Component 2: Terrain Routing (Overland + Subsurface)
- **Grid:** 250m uniform rectilinear (4x finer than Noah-MP)
- **What it does:** Routes water across the land surface and through shallow subsurface
- **Physics:** Steepest descent (D8) algorithm, Darcy's law for subsurface
- **ML analogy:** Spatial convolution layer — processes a finer-resolution feature map
- **Key variables:** surface head (sfcheadrt), subsurface flow

#### 🌊 Component 3: Channel Routing
- **Grid:** River network (vector/graph — NOT a regular grid)
- **What it does:** Routes water through rivers, streams, lakes, and reservoirs
- **Physics:** Diffusive wave equation or Muskingum-Cunge method
- **ML analogy:** Graph neural network — processes along edges of a river network graph
- **Key variables:** streamflow/discharge (QLINK), lake levels

#### 💧 Component 4: Groundwater/Baseflow
- **Grid:** Basin-level buckets
- **What it does:** Represents slow release of stored groundwater into streams
- **Physics:** Exponential decay bucket model
- **ML analogy:** Residual/skip connection — slow pathway that adds to the main signal
- **Key variables:** underground runoff (UGDRNOFF)

### 2.5 Multi-Resolution Architecture

```
┌──────────────────────────────────────────────────────┐
│                                                       │
│  🌿 Noah-MP Grid (1km)        🏔️ Routing Grid (250m)  │
│  ┌───┬───┬───┬───┐            ┌─┬─┬─┬─┬─┬─┬─┬─┐     │
│  │   │   │   │   │            │ │ │ │ │ │ │ │ │     │
│  │   │   │   │   │            ├─┼─┼─┼─┼─┼─┼─┼─┤     │
│  ├───┼───┼───┼───┤    ──►     │ │ │ │ │ │ │ │ │     │
│  │   │   │   │   │   4:1      ├─┼─┼─┼─┼─┼─┼─┼─┤     │
│  │   │   │   │   │  factor    │ │ │ │ │ │ │ │ │     │
│  ├───┼───┼───┼───┤            ├─┼─┼─┼─┼─┼─┼─┼─┤     │
│  │   │   │   │   │            │ │ │ │ │ │ │ │ │     │
│  │   │   │   │   │            ├─┼─┼─┼─┼─┼─┼─┼─┤     │
│  ├───┼───┼───┼───┤            │ │ │ │ │ │ │ │ │     │
│  │   │   │   │   │            ├─┼─┼─┼─┼─┼─┼─┼─┤     │
│  └───┴───┴───┴───┘            │ │ │ │ │ │ │ │ │     │
│   4×4 cells = 16km²           ├─┼─┼─┼─┼─┼─┼─┼─┤     │
│                                │ │ │ │ │ │ │ │ │     │
│  AGGFACTRT = 4                 ├─┼─┼─┼─┼─┼─┼─┼─┤     │
│  (aggregation factor)          │ │ │ │ │ │ │ │ │     │
│  Each 1km cell =               └─┴─┴─┴─┴─┴─┴─┴─┘     │
│  4×4 = 16 routing cells        8×8 cells = 16km²      │
│                                                       │
│  🌊 Channel Network (vector — NOT a grid)              │
│  ─────●────●────●─────●────────●──────►                │
│       │    │         ╱                                 │
│  ─────●────●────────●                                  │
│  (reaches with computed flow at each node)             │
│                                                       │
└──────────────────────────────────────────────────────┘
```

> **🧠 ML Analogy:** This is like a **Feature Pyramid Network (FPN)** in object detection —
> multiple resolution levels process different types of information, then results are
> combined. The 1km grid is the "coarse" backbone, the 250m grid is the "fine" feature
> map, and the channel network is the "detection head" that produces final outputs.

---

## 3. 📁 Complete Folder Structure

### 3.1 Top-Level Project Directory

```
WRF-Hydro-BMI/                          🏠 Our project root
├── 📂 wrf_hydro_nwm_public/            🌊 WRF-Hydro source (DON'T MODIFY!)
│   ├── 📂 src/                          📝 Source code (244 Fortran files, 172K+ lines)
│   ├── 📂 build/                        🔨 Compiled output
│   ├── 📂 tests/                        🧪 Test cases (Croton NY)
│   ├── 📄 CMakeLists.txt               ⚙️ Top-level build config
│   ├── 📄 LICENSE.txt                   📜 License
│   └── 📄 README.md                    📖 Official readme
│
├── 📂 schism_NWM_BMI/                   🏖️ SCHISM's BMI wrapper (OUR REFERENCE)
├── 📂 bmi-example-fortran/              📚 Simple BMI example (heat model)
├── 📂 bmi-fortran/                      📐 BMI Fortran specification (abstract interface)
│
├── 📂 bmi_wrf_hydro/                    ⭐ OUR WORK DIRECTORY
│   └── 📂 Docs/                         📖 Project documentation (you are here!)
│
├── 📄 CLAUDE.md                         🤖 Project instructions for AI assistant
└── 📄 .gitignore                        🚫 Git ignore rules
```

### 3.2 WRF-Hydro Source Tree (`src/`) — The Heart of the Model

```
wrf_hydro_nwm_public/src/
│
├── 📂 HYDRO_drv/                        🎯 MAIN DRIVER (the "training loop")
│   └── module_HYDRO_drv.F90             1,838 lines — orchestrates ALL hydro components
│                                         ⭐ CRITICAL for BMI: contains the time step logic
│
├── 📂 Land_models/                      🌿 LAND SURFACE MODELS
│   ├── 📂 NoahMP/                       ✅ ACTIVE — Noah Multi-Physics (our LSM)
│   │   ├── 📂 IO_code/                  📥 I/O and driver code
│   │   │   ├── main_hrldas_driver.F     🚀 ENTRY POINT — the `main()` function (42 lines)
│   │   │   ├── module_NoahMP_hrldas_driver.F  🔄 NoahMP driver (2,869 lines)
│   │   │   └── module_hrldas_netcdf_io.F      💾 NetCDF I/O (3,974 lines)
│   │   ├── 📂 phys/                     🔬 Physics code
│   │   │   ├── module_sf_noahmplsm.F   🧮 Core NoahMP physics (10,177 lines — LARGEST!)
│   │   │   ├── module_sf_noahmpdrv.F   🎛️ NoahMP driver interface (2,574 lines)
│   │   │   └── 📂 surfex/              ❄️ Crocus snow model (optional)
│   │   ├── 📂 data_structures/          📊 Data type definitions
│   │   ├── 📂 hydro/                    💧 Hydro coupling code
│   │   ├── 📂 run/                      🏃 Runtime files (parameter tables)
│   │   ├── 📂 Utility_routines/         🔧 Helper functions
│   │   └── 📂 HRLDAS_forcing/           🌦️ Forcing data processing
│   │
│   └── 📂 Noah/                         ⚠️ LEGACY — older Noah LSM (not used in NWM)
│       ├── 📂 IO_code/
│       ├── 📂 Noah/
│       └── ... (utility programs, verification, data collection)
│
├── 📂 Routing/                          🌊 CORE HYDRO ROUTING (the prediction head)
│   ├── module_HYDRO_io.F90              💾 Hydro I/O (11,399 lines — BIGGEST FILE!)
│   ├── module_RT.F90                    🔄 Main routing module (1,713 lines)
│   ├── module_channel_routing.F90       🌊 Channel/river routing (2,134 lines)
│   ├── module_NWM_io.F90               📊 NWM-specific I/O (5,557 lines)
│   ├── module_NWM_io_dict.F90          📖 Output variable dictionaries (2,799 lines)
│   ├── module_lsm_forcing.F90          🌦️ Forcing data interface (3,419 lines)
│   ├── module_gw_gw2d.F90             💧 2D groundwater model (2,130 lines)
│   ├── 📂 Overland/                    🏔️ Overland flow routing
│   ├── 📂 Subsurface/                  🌍 Subsurface flow routing
│   ├── 📂 Reservoirs/                  🏞️ Lake/reservoir models
│   │   ├── 📂 Level_Pool/             Basic reservoir routing
│   │   ├── 📂 Persistence_Level_Pool_Hybrid/  Advanced hybrid
│   │   └── 📂 RFC_Forecasts/          RFC forecast-based operations
│   └── 📂 Diversions/                  🔀 Water diversion handling
│
├── 📂 OrchestratorLayer/               🎼 NEW ORCHESTRATION ARCHITECTURE
│   └── (manages component execution order and data flow)
│
├── 📂 CPL/                              🔗 COUPLING LAYERS (how WRF-Hydro talks to others)
│   ├── 📂 NoahMP_cpl/                  🌿↔️🌊 Noah-MP ↔ Hydro coupling
│   ├── 📂 WRF_cpl/                     🌤️↔️🌊 WRF atmosphere ↔ Hydro coupling
│   ├── 📂 NUOPC_cpl/                   🔌 NUOPC/ESMF framework coupling
│   ├── 📂 Noah_cpl/                    Legacy Noah coupling
│   ├── 📂 CLM_cpl/                     CLM coupling
│   └── 📂 LIS_cpl/                     NASA LIS coupling
│
├── 📂 MPP/                              ⚡ MPI PARALLEL PROCESSING
│   ├── mpp_land.F90                     2,837 lines — MPI communication for land grid
│   └── module_mpp_ReachLS.F90          1,499 lines — MPI for reach routing
│
├── 📂 IO/                               💾 COMMON I/O UTILITIES
├── 📂 Data_Rec/                         📊 Data record definitions (global state)
├── 📂 Debug_Utilities/                  🐛 Debug helpers
├── 📂 nudging/                          📍 STREAMFLOW NUDGING (data assimilation)
│   ├── module_stream_nudging.F90        3,061 lines
│   └── 📂 io/                           Nudging I/O
│
├── 📂 Rapid_routing/                    🚀 RAPID routing model (optional, separate)
├── 📂 arc/                              📦 Archive utilities
├── 📂 utils/                            🔧 General utilities
│   └── 📂 fortglob/                     File globbing in Fortran
│
├── 📂 deprecated/                       🗑️ Deprecated code
├── 📂 cmake-modules/                    ⚙️ CMake helper modules (FindNetCDF.cmake)
├── 📂 Doc/                              📖 Internal documentation
│
└── 📂 template/                         📋 TEMPLATES & EXAMPLES
    ├── 📂 HYDRO/                        hydro.namelist template
    ├── 📂 NoahMP/                       namelist.hrldas template
    └── 📂 examples/nwm/                 NWM configuration examples
        ├── 📂 namelists/               v2.0, v2.1, v3.0 configs
        │   └── (short_range, medium_range, analysis_assim, etc.)
        └── 📂 parameter_tables/        CONUS, Alaska, Hawaii, Puerto Rico
```

> **🧠 ML Analogy:**
> | WRF-Hydro Directory | ML Project Equivalent |
> |---------------------|----------------------|
> | `src/` | `model/` — all model architecture code |
> | `HYDRO_drv/` | `train.py` — the main training/inference loop |
> | `Land_models/NoahMP/phys/` | `model/layers/` — neural network layer definitions |
> | `Routing/` | `model/heads/` — task-specific output heads |
> | `CPL/` | `model/adapters/` — adapters for different frameworks |
> | `MPP/` | `distributed/` — distributed training (DDP, FSDP) |
> | `IO/` | `data/` — data loading and saving |
> | `template/` | `configs/` — example YAML configs |
> | `build/` | `dist/` or `__pycache__/` — compiled artifacts |
> | `tests/` | `tests/` — test cases and eval scripts |
> | `build/Run/` | Model checkpoint + inference runtime directory |

### 3.3 Build Output Directory

```
wrf_hydro_nwm_public/build/
├── 📂 Run/                              🏃 RUNTIME DIRECTORY (run model from here)
│   ├── 🔴 wrf_hydro                    The compiled executable (4.5 MB)
│   ├── 🔗 wrf_hydro.exe → wrf_hydro   Symlink alias
│   ├── 🔗 wrf_hydro_NoahMP → wrf_hydro Symlink alias
│   ├── 📄 namelist.hrldas              Land surface config
│   ├── 📄 hydro.namelist               Hydrology config
│   ├── 📄 MPTABLE.TBL                  NoahMP vegetation parameters (48 KB)
│   ├── 📄 SOILPARM.TBL                 Soil parameters (5 KB)
│   ├── 📄 GENPARM.TBL                  General parameters
│   ├── 📄 CHANPARM.TBL                 Channel parameters
│   ├── 📄 HYDRO.TBL                    Hydrology parameters (2 KB)
│   └── 📄 Makefile                     For legacy compatibility
│
├── 📂 lib/                              📚 COMPILED LIBRARIES (22 libraries!)
│   ├── libhydro_driver.a               Main driver
│   ├── libhydro_routing.a              Core routing
│   ├── libhydro_routing_overland.a     Overland routing
│   ├── libhydro_routing_subsurface.a   Subsurface routing
│   ├── libhydro_routing_reservoirs.a   Reservoir routing (+ 3 sub-libraries)
│   ├── libhydro_routing_diversions.a   Diversion routing
│   ├── libhydro_mpp.a                  MPI layer
│   ├── libhydro_netcdf_layer.a         NetCDF I/O
│   ├── libhydro_noahmp_cpl.a           NoahMP coupling
│   ├── libhydro_orchestrator.a         Orchestration layer
│   ├── libhydro_data_rec.a             Data records
│   ├── libhydro_debug_utils.a          Debug utilities
│   ├── libhydro_utils.a                General utilities
│   ├── libnoahmp_phys.a                NoahMP physics
│   ├── libnoahmp_data.a                NoahMP data structures
│   ├── libnoahmp_util.a                NoahMP utilities
│   ├── libcrocus_surfex.a              Crocus snow model
│   ├── libsnowcro.a                    Snow processes
│   └── libfortglob.a                   File globbing
│
└── 📂 mods/                             📐 Compiled .mod files (Fortran module interfaces)
```

> **🧠 ML Analogy:** The `.a` (archive) libraries are like **compiled `.so` files** in
> a PyTorch C++ extension, or like a **TensorRT engine** — pre-compiled, optimized, ready
> to link. The `.mod` files are like Python `.pyi` type stubs — they describe the interface
> without containing the implementation.

---

## 4. 📄 Key Source Files Explained

### 4.1 The Most Important Files (Read These First)

| # | File | Lines | Role | ML Equivalent |
|---|------|-------|------|---------------|
| ⭐1 | `Land_models/NoahMP/IO_code/main_hrldas_driver.F` | 42 | **Entry point** — `program` that calls init → loop → finalize | `if __name__ == '__main__'` |
| ⭐2 | `HYDRO_drv/module_HYDRO_drv.F90` | 1,838 | **Hydro driver** — orchestrates all routing components | `trainer.py` — the training loop |
| ⭐3 | `Land_models/NoahMP/IO_code/module_NoahMP_hrldas_driver.F` | 2,869 | **NoahMP driver** — land surface init + timestep | `model.forward()` implementation |
| ⭐4 | `Routing/module_RT.F90` | 1,713 | **Routing core** — main routing control flow | `model.predict()` orchestrator |
| 5 | `Routing/module_channel_routing.F90` | 2,134 | Channel/river routing algorithms | Sequence model (GRU/LSTM layer) |
| 6 | `Routing/module_HYDRO_io.F90` | 11,399 | All hydro I/O operations | `dataloader.py` + `saver.py` |
| 7 | `Routing/module_NWM_io.F90` | 5,557 | NWM-specific output formatting | Output postprocessor |
| 8 | `Land_models/NoahMP/phys/module_sf_noahmplsm.F` | 10,177 | Core NoahMP physics equations | Core neural network forward pass |
| 9 | `Routing/module_lsm_forcing.F90` | 3,419 | Reads/interpolates forcing data | Data augmentation + preprocessing |
| 10 | `MPP/mpp_land.F90` | 2,837 | MPI parallel communication | `DistributedDataParallel` wrapper |
| 11 | `Data_Rec/module_rt_data.F90` | — | `rt_domain` type — GLOBAL state container | `model.state_dict()` |
| 12 | `OrchestratorLayer/orchestrator_base.F90` | — | New modular execution controller | Pipeline scheduler |
| 13 | `Routing/module_gw_gw2d.F90` | 2,130 | 2D groundwater model | Skip connection module |
| 14 | `nudging/module_stream_nudging.F90` | 3,061 | Data assimilation (obs → model correction) | Online learning / fine-tuning |
| 15 | `Routing/module_NWM_io_dict.F90` | 2,799 | Variable metadata dictionaries | Schema definitions |

### 4.2 The Entry Point: `main_hrldas_driver.F` (42 lines!)

This is the **entire main program**. Yes, really. Just 42 lines:

```fortran
program noah_hrldas_driver
  ! Import the land model driver
  use module_noahmp_hrldas_driver, only: land_driver_ini, land_driver_exe

  ! Import the hydro cleanup
  use module_HYDRO_drv, only: HYDRO_finish

  ! Import the new orchestrator architecture
  use orchestrator_base
  use state_module, only: state_type

  implicit none
  integer :: ITIME, NTIME
  type(state_type) :: state

  ! ① Initialize everything
  call orchestrator%init()
  call land_driver_ini(NTIME, state)

  ! ② Run the time loop (THIS is what BMI must decompose!)
  do ITIME = 1, NTIME
     call land_driver_exe(ITIME, state)    ! One timestep
  end do

  ! ③ Cleanup
  call hydro_finish()

end program noah_hrldas_driver
```

> **🧠 ML Analogy:** This is exactly like a PyTorch training script:
> ```python
> # Python equivalent of main_hrldas_driver.F
> model = WRFHydro()                          # orchestrator%init()
> model.load_config("namelist.hrldas")         # land_driver_ini()
>
> for timestep in range(NTIME):                # do ITIME = 1, NTIME
>     model.forward(timestep)                  #   land_driver_exe(ITIME)
>
> model.cleanup()                              # hydro_finish()
> ```
>
> **The BMI challenge:** We need to BREAK this loop apart so that the **caller**
> (PyMT/Python) controls when each timestep executes — not the model itself.

### 4.3 The Time Loop Deep Dive

Inside `land_driver_exe()`, each timestep does this:

```
land_driver_exe(ITIME):
    │
    ├── 1. Read forcing data for this timestep (rain, temp, etc.)
    ├── 2. Run Noah-MP physics (soil, snow, vegetation, energy balance)
    ├── 3. Compute surface runoff & drainage
    │
    ├── 4. HYDRO_ini() — pass land surface outputs to routing
    ├── 5. Run overland routing (250m grid)
    ├── 6. Run subsurface routing (250m grid)
    ├── 7. Run channel routing (river network)
    ├── 8. Run groundwater/baseflow
    │
    ├── 9. Write outputs (LDASOUT, CHRTOUT, RTOUT, etc.)
    └── 10. Write restart files if needed
```

> **💡 For BMI:** We need `initialize()` to do step 0 (all setup),
> `update()` to do steps 1-10 once, and `finalize()` to clean up.

---

## 5. ⚙️ Configuration Files (The Namelists)

### 5.1 What Are Namelists?

Fortran **namelists** are the language's built-in config file format. They're read directly
by the `read(unit, nml=namelist_name)` statement — no parsing library needed.

> **🧠 ML Analogy:** Namelists are Fortran's equivalent of **YAML/JSON config files**.
>
> | ML Config | Fortran Namelist |
> |-----------|-----------------|
> | `config.yaml` | `namelist.hrldas` |
> | `hparams.json` | `hydro.namelist` |
> | `--learning-rate 0.001` | `NOAH_TIMESTEP = 3600` |
> | `wandb.config` | Namelist variables |

### 5.2 `namelist.hrldas` — Land Surface Configuration

This controls the Noah-MP land surface model. Think of it as **model architecture + training hyperparameters**.

```fortran
&NOAHLSM_OFFLINE                        ! ← Namelist group name (like YAML section)

! ═══════════════════════════════════════
! 📂 FILE PATHS (= data directories)
! ═══════════════════════════════════════
HRLDAS_SETUP_FILE = "./DOMAIN/wrfinput_d01.nc"  ! Domain definition
INDIR = "./FORCING"                              ! Input forcing data directory
SPATIAL_FILENAME = "./DOMAIN/soil_properties.nc" ! Spatial soil parameters
OUTDIR = "./"                                    ! Output directory

! ═══════════════════════════════════════
! ⏰ TIME CONTROL (= training schedule)
! ═══════════════════════════════════════
START_YEAR  = 2011          ! Simulation start
START_MONTH = 08
START_DAY   = 26
START_HOUR  = 00
START_MIN   = 00
KHOUR = 24                  ! Run for 24 hours (= number of epochs)

! ═══════════════════════════════════════
! 🔄 RESTART (= model checkpoints)
! ═══════════════════════════════════════
RESTART_FILENAME_REQUESTED = "RESTART/RESTART.2011082600_DOMAIN1"
RESTART_FREQUENCY_HOURS = 24            ! Save checkpoint every 24h

! ═══════════════════════════════════════
! 🧮 PHYSICS OPTIONS (= architecture choices)
! ═══════════════════════════════════════
DYNAMIC_VEG_OPTION                = 4   ! Vegetation dynamics scheme
CANOPY_STOMATAL_RESISTANCE_OPTION = 1   ! How plants regulate water loss
BTR_OPTION                        = 1   ! Soil moisture stress function
RUNOFF_OPTION                     = 3   ! Runoff generation scheme
SURFACE_DRAG_OPTION               = 1   ! Surface drag coefficient
FROZEN_SOIL_OPTION                = 1   ! Frozen soil physics
SUPERCOOLED_WATER_OPTION          = 1   ! Supercooled water in soil
RADIATIVE_TRANSFER_OPTION         = 3   ! Radiation through canopy
SNOW_ALBEDO_OPTION                = 2   ! Snow reflectivity scheme
GLACIER_OPTION                    = 2   ! Glacier treatment
SURFACE_RESISTANCE_OPTION         = 4   ! Surface resistance to evap
IMPERV_OPTION                     = 9   ! Impervious surface handling

! ═══════════════════════════════════════
! ⏱️ TIMESTEPS (= batch processing intervals)
! ═══════════════════════════════════════
FORCING_TIMESTEP = 3600     ! Read new forcing every 3600s (1 hour)
NOAH_TIMESTEP    = 3600     ! Land model timestep: 3600s (1 hour)
OUTPUT_TIMESTEP  = 3600     ! Write output every 3600s (1 hour)

! ═══════════════════════════════════════
! 🌍 SOIL LAYERS (= hidden layer sizes)
! ═══════════════════════════════════════
NSOIL = 4                   ! 4 soil layers (like 4 hidden layers)
soil_thick_input(1) = 0.10  ! Layer 1: 0-10cm   (top soil)
soil_thick_input(2) = 0.30  ! Layer 2: 10-40cm  (root zone upper)
soil_thick_input(3) = 0.60  ! Layer 3: 40-100cm (root zone lower)
soil_thick_input(4) = 1.00  ! Layer 4: 100-200cm (deep soil)

/                           ! ← End of namelist group (like end of YAML block)
```

### 5.3 `hydro.namelist` — Hydrology Routing Configuration

This controls all the water routing. Think of it as **prediction head hyperparameters**.

```fortran
&HYDRO_nlist

! ═══════════════════════════════════════
! 🔗 COUPLING MODE
! ═══════════════════════════════════════
sys_cpl = 1                             ! 1=HRLDAS (offline), 2=WRF, 3=LIS, 4=CLM

! ═══════════════════════════════════════
! 📂 INPUT FILES (= model architecture definition)
! ═══════════════════════════════════════
GEO_STATIC_FLNM = "./DOMAIN/geo_em.d01.nc"         ! Land surface grid definition
GEO_FINEGRID_FLNM = "./DOMAIN/Fulldom_hires.nc"     ! High-res terrain (250m)
HYDROTBL_F = "./DOMAIN/hydro2dtbl.nc"                ! Hydro parameter table
LAND_SPATIAL_META_FLNM = "./DOMAIN/GEOGRID_LDASOUT_Spatial_Metadata.nc"

! ═══════════════════════════════════════
! 📐 GRID SETTINGS
! ═══════════════════════════════════════
DXRT = 250.0               ! Routing grid spacing: 250 meters
AGGFACTRT = 4              ! Land:routing ratio (1km / 250m = 4)
NSOIL = 4                  ! Soil layers (must match namelist.hrldas)
ZSOIL8(1) = -0.10          ! Soil layer boundaries (negative = depth)
ZSOIL8(2) = -0.40
ZSOIL8(3) = -1.00
ZSOIL8(4) = -2.00

! ═══════════════════════════════════════
! ⏱️ ROUTING TIMESTEPS
! ═══════════════════════════════════════
DTRT_CH  = 10              ! Channel routing timestep: 10 seconds
DTRT_TER = 10              ! Terrain routing timestep: 10 seconds
                           ! (Much shorter than Noah's 3600s — finer temporal resolution!)

! ═══════════════════════════════════════
! 🔀 ROUTING SWITCHES (= which "heads" to activate)
! ═══════════════════════════════════════
SUBRTSWCRT  = 1            ! Subsurface routing:  ON
OVRTSWCRT   = 1            ! Overland routing:    ON
CHANRTSWCRT = 1            ! Channel routing:     ON
channel_option = 3         ! 1=Muskingum, 2=Musk-Cunge, 3=Diff.Wave
rt_option = 1              ! 1=Steepest Descent (D8), 2=CASC2D
GWBASESWCRT = 1            ! Baseflow model:      ON (1=exp. bucket)
lake_option = 1            ! Lake model: 1=level pool

! ═══════════════════════════════════════
! 📊 OUTPUT CONTROL (= what to log)
! ═══════════════════════════════════════
out_dt = 60                ! Output every 60 minutes
CHRTOUT_DOMAIN = 1         ! Channel streamflow output:     ON
RTOUT_DOMAIN = 1           ! Terrain routing output:        ON
output_gw = 1              ! Groundwater output:            ON
outlake = 1                ! Lake output:                   ON
CHANOBS_DOMAIN = 0         ! Channel observation points:    OFF
CHRTOUT_GRID = 0           ! Gridded channel output:        OFF
LSMOUT_DOMAIN = 0          ! LSM-routing interface output:  OFF

/
```

### 5.4 Namelist vs ML Hyperparameters Comparison

| Namelist Parameter | ML Hyperparameter Equivalent | What It Controls |
|-------------------|-------------------------------|-----------------|
| `NOAH_TIMESTEP = 3600` | `batch_size = 32` | Processing granularity |
| `DTRT_CH = 10` | `accumulation_steps = 360` | Sub-stepping frequency |
| `KHOUR = 24` | `max_epochs = 100` | Total simulation duration |
| `NSOIL = 4` | `num_layers = 4` | Vertical discretization |
| `DXRT = 250.0` | `spatial_resolution = 256` | Grid resolution |
| `AGGFACTRT = 4` | `downsample_factor = 4` | Resolution ratio |
| `channel_option = 3` | `head_type = "transformer"` | Algorithm choice |
| `OVRTSWCRT = 1` | `use_attention = True` | Feature toggle |
| `RESTART_FREQUENCY = 24` | `save_every = 10` | Checkpoint frequency |
| `START_YEAR = 2011` | `data_split = "train"` | Data selection |

---

## 6. 🔨 Build Process Step-by-Step

### 6.1 Build Overview (ASCII Flowchart)

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  📝 Source    │     │  ⚙️ CMake     │     │  📋 Makefile  │
│  (.F90, .F)  │────▶│  Configure   │────▶│  Generated   │
│  244 files   │     │              │     │              │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                                  ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  🔴 wrf_hydro│     │  🔗 Link     │     │  🔨 Compile  │
│  executable  │◀────│  22 libs     │◀────│  .F90→.o     │
│  (4.5 MB)    │     │  together    │     │  .F→.o       │
└──────────────┘     └──────────────┘     └──────────────┘
```

> **🧠 ML Analogy:** Building WRF-Hydro is like **building a TensorRT engine from ONNX**:
>
> | Build Step | ML Equivalent |
> |-----------|---------------|
> | Source code (.F90) | Model definition (.py) |
> | CMake configure | `torch.jit.trace()` — analyze the graph |
> | Compile (.F90 → .o) | `torch.compile()` — optimize operations |
> | Link (.o → executable) | Bundle into deployable artifact |
> | `wrf_hydro` executable | `model.engine` (TensorRT) or `model.pt` (TorchScript) |
> | `.mod` files | `.pyi` type stubs |
> | `.a` libraries | `.so` shared libraries |

### 6.2 Prerequisites Checklist

```
✅ conda environment: wrfhydro-bmi
✅ gfortran: 13.3+ (system) or 14.3+ (conda)
✅ MPI: Open MPI via conda (mpif90 compiler wrapper)
✅ NetCDF-Fortran: 4.6.2 via conda
✅ cmake: 3.12+ (we have 3.31.1)
✅ make: GNU make
```

### 6.3 Step-by-Step Build Commands

```bash
# ① Activate the conda environment
conda activate wrfhydro-bmi

# ② Navigate to the WRF-Hydro source directory
cd wrf_hydro_nwm_public

# ③ Create a build directory (out-of-source build — like venv for compiling)
mkdir -p build && cd build

# ④ Run CMake to configure the build
#    This is like `pip install -e .` reading setup.py
#    CMake reads CMakeLists.txt, finds dependencies, generates Makefiles
cmake .. -DCMAKE_BUILD_TYPE=Release
#    └── tells cmake: look one directory UP for CMakeLists.txt
#                     build in Release mode (optimized, no debug symbols)

# ⑤ Compile everything
#    This reads the generated Makefiles and compiles all 244 Fortran files
make -j$(nproc)
#    └── -j$(nproc) = use all CPU cores for parallel compilation
#        (like num_workers in DataLoader!)

# The executable is now at: build/Run/wrf_hydro
```

### 6.4 What CMake Does (Behind the Scenes)

The top-level `CMakeLists.txt` does the following:

```
1. Sets project name: WRF_Hydro (version 5.4.0, NWM 3.1-beta)
2. Finds MPI library (required — even serial mode uses MPI stubs)
3. Finds NetCDF-Fortran library (required — for I/O)
4. Reads environment variables for feature flags:
   - WRF_HYDRO=1         (always on)
   - HYDRO_D=0/1          (debug printing)
   - SPATIAL_SOIL=0/1     (spatial soil parameters)
   - WRF_HYDRO_NUDGING=0/1 (data assimilation)
   - WRF_HYDRO_NUOPC=0/1  (NUOPC coupling)
   - NWM_META=0/1         (NWM metadata in output)
   - etc.
5. Sets compiler flags for gfortran:
   -cpp                    (enable C preprocessor)
   -ffree-form             (free-form source code)
   -ffree-line-length-none (no line length limit)
   -fconvert=big-endian    (binary file format)
   -O2                     (optimization level 2 for Release)
6. Processes all src/ subdirectories
7. Links 22 libraries into final executable
```

### 6.5 The 22 Libraries That Make Up WRF-Hydro

```
wrf_hydro executable
│
├── libhydro_driver.a               ← Main driver loop
├── libhydro_orchestrator.a         ← Component orchestration
├── libhydro_noahmp_cpl.a           ← NoahMP ↔ Hydro coupling
│
├── libnoahmp_phys.a                ← Noah-MP physics (THE SCIENCE)
├── libnoahmp_data.a                ← Noah-MP data structures
├── libnoahmp_util.a                ← Noah-MP utilities
│
├── libhydro_routing.a              ← Core routing
├── libhydro_routing_overland.a     ← Overland flow
├── libhydro_routing_subsurface.a   ← Subsurface flow
├── libhydro_routing_reservoirs.a   ← Reservoir base
├── libhydro_routing_reservoirs_levelpool.a    ← Level pool reservoirs
├── libhydro_routing_reservoirs_hybrid.a       ← Hybrid reservoirs
├── libhydro_routing_reservoirs_rfc.a          ← RFC reservoirs
├── libhydro_routing_diversions.a   ← Water diversions
│
├── libhydro_mpp.a                  ← MPI communication
├── libhydro_netcdf_layer.a         ← NetCDF I/O
├── libhydro_data_rec.a             ← Global state records
├── libhydro_debug_utils.a          ← Debug tools
├── libhydro_utils.a                ← General utilities
├── libfortglob.a                   ← File globbing
│
├── libcrocus_surfex.a              ← Crocus snow model
└── libsnowcro.a                    ← Snow processes
```

---

## 7. 📥 Input Data — What the Model Needs

### 7.1 Input Data Overview

```
┌─────────────────────────────────────────────────────────┐
│                WRF-Hydro Input Data                      │
│                                                          │
│  ┌───────────────┐  ┌───────────────┐  ┌─────────────┐ │
│  │ 🗺️ DOMAIN      │  │ 🌦️ FORCING    │  │ 🔄 RESTART  │ │
│  │ (architecture) │  │ (input data)  │  │ (checkpoint)│ │
│  │                │  │               │  │             │ │
│  │ geo_em.d01.nc │  │ hourly files  │  │ RESTART.*   │ │
│  │ Fulldom.nc    │  │ rain, temp,   │  │ HYDRO_RST.* │ │
│  │ Route_Link.nc │  │ wind, etc.    │  │             │ │
│  │ GWBASINS.nc   │  │               │  │             │ │
│  │ LAKEPARM.nc   │  │               │  │             │ │
│  └───────────────┘  └───────────────┘  └─────────────┘ │
│                                                          │
│  ┌───────────────┐  ┌───────────────┐                   │
│  │ 📊 PARAMETERS │  │ 🌍 SPATIAL     │                  │
│  │ (.TBL files)  │  │               │                   │
│  │               │  │ soil_props.nc │                   │
│  │ MPTABLE.TBL   │  │ hydro2dtbl.nc │                  │
│  │ SOILPARM.TBL  │  │               │                   │
│  │ GENPARM.TBL   │  │               │                   │
│  │ CHANPARM.TBL  │  │               │                   │
│  │ HYDRO.TBL     │  │               │                   │
│  └───────────────┘  └───────────────┘                   │
└─────────────────────────────────────────────────────────┘
```

### 7.2 Domain Files (= Model Architecture Definition)

These define the **spatial structure** of the simulation — where the grid cells are,
how rivers connect, where lakes exist, etc. You create these once per domain.

| File | What It Contains | ML Equivalent |
|------|-----------------|---------------|
| `geo_em.d01.nc` | Land surface grid (lat/lon, terrain height, land use, soil type) | Model architecture definition (input shape, layer dims) |
| `Fulldom_hires.nc` | High-res terrain (elevation, flow direction, channel grid) on 250m | Feature map dimensions at fine resolution |
| `wrfinput_d01.nc` | Initial land surface state (soil temp, moisture, snow) | Weight initialization (Xavier, random, etc.) |
| `Route_Link.nc` | River network connectivity (reach-based routing) | Graph adjacency matrix |
| `GWBASINS.nc` | Groundwater basin boundaries | Cluster/region assignments |
| `GWBUCKPARM.nc` | Groundwater bucket parameters per basin | Per-region hyperparameters |
| `LAKEPARM.nc` | Lake/reservoir parameters (area, volume curves) | Special node attributes in graph |
| `hydro2dtbl.nc` | 2D hydrology parameter table (derived from soil/land use) | Feature engineering lookup tables |
| `soil_properties.nc` | Spatially distributed soil parameters | Spatially varying model parameters |
| `GEOGRID_LDASOUT_Spatial_Metadata.nc` | Output grid projection metadata | Coordinate reference system |

### 7.3 Forcing Data (= Input Features)

Forcing data is the **time-varying input** that drives the model — weather!

```
FORCING/
├── 2011082600.LDASIN_DOMAIN1    ← Hour 0:  2011-08-26 00:00 UTC
├── 2011082601.LDASIN_DOMAIN1    ← Hour 1:  2011-08-26 01:00 UTC
├── 2011082602.LDASIN_DOMAIN1    ← Hour 2:  2011-08-26 02:00 UTC
├── ...                          (one file per hour)
└── 2011082700.LDASIN_DOMAIN1    ← Hour 24: 2011-08-27 00:00 UTC
```

Each file is a NetCDF file containing these variables:

| Variable | Name in Config | Description | Units |
|----------|---------------|-------------|-------|
| `T2D` | `forcing_name_T` | 2-meter air temperature | K |
| `Q2D` | `forcing_name_Q` | 2-meter specific humidity | kg/kg |
| `U2D` | `forcing_name_U` | 10-meter U-wind component | m/s |
| `V2D` | `forcing_name_V` | 10-meter V-wind component | m/s |
| `PSFC` | `forcing_name_P` | Surface pressure | Pa |
| `LWDOWN` | `forcing_name_LW` | Downward longwave radiation | W/m² |
| `SWDOWN` | `forcing_name_SW` | Downward shortwave radiation | W/m² |
| `RAINRATE` | `forcing_name_PR` | Precipitation rate | mm/s |
| `LQFRAC` | `forcing_name_LF` | Liquid fraction of precip | fraction |

> **🧠 ML Analogy:** Forcing data = **input features fed to the model at each timestep**.
> Like how an LSTM receives a new input vector at each time step.
> Each forcing file = one batch of input features.

### 7.4 Restart Files (= Model Checkpoints)

```
RESTART/
├── RESTART.2011082600_DOMAIN1           ← NoahMP land surface state
└── HYDRO_RST.2011-08-26_00:00_DOMAIN1  ← Hydro routing state
```

These contain the **full internal state** of the model at a point in time:
- Soil moisture in all 4 layers
- Snow depth and temperature
- Water in channels and reservoirs
- Groundwater bucket levels

> **🧠 ML Analogy:** Restart files are **exactly like model checkpoints** (`model.pt`).
> - Cold start = training from scratch (random initialization)
> - Warm start from restart = resuming training from checkpoint
> - You can "fine-tune" by starting from one simulation's restart and running with different forcing

### 7.5 Parameter Tables (= Pretrained Weights)

| File | Size | What It Contains |
|------|------|-----------------|
| `MPTABLE.TBL` | 48 KB | Noah-MP vegetation parameters (albedo, LAI, root depth per land use type) |
| `SOILPARM.TBL` | 5 KB | Soil hydraulic parameters (porosity, conductivity per soil type) |
| `GENPARM.TBL` | 261 B | General parameters (snow/rain threshold, roughness) |
| `CHANPARM.TBL` | 471 B | Channel parameters (Manning's N by stream order) |
| `HYDRO.TBL` | 2 KB | Hydrology routing parameters (infiltration, roughness by land use) |

> **🧠 ML Analogy:** Parameter tables are like **pretrained weights** — they encode
> expert knowledge about how different soil types, vegetation types, and channel types
> behave. A sandy soil has different parameters than a clay soil, just like different
> layers in a pretrained model have different learned weights.
>
> **Calibration** (adjusting these parameters to match observations) is the hydrology
> equivalent of **fine-tuning** a pretrained model.

### 7.6 About NetCDF (The File Format)

NetCDF (Network Common Data Form) is the **standard file format** for climate/weather data.

> **🧠 ML Analogy:** NetCDF is to Earth science what **HDF5** is to ML.
> In fact, NetCDF-4 IS HDF5 under the hood!
>
> | Feature | NetCDF | HDF5 | NumPy (.npy) |
> |---------|--------|------|-------------|
> | Multi-dimensional arrays | ✅ | ✅ | ✅ |
> | Named dimensions | ✅ | ❌ | ❌ |
> | Metadata attributes | ✅ | ✅ | ❌ |
> | Compression | ✅ | ✅ | ❌ |
> | Self-describing | ✅ | ✅ | ❌ |
> | Python library | `netCDF4` | `h5py` | `numpy` |
> | CLI inspection | `ncdump` | `h5dump` | — |

Quick inspection commands:
```bash
# See file structure (like h5ls)
ncdump -h file.nc

# See variable values
ncdump -v RAINRATE file.nc

# Python inspection
python -c "import netCDF4; print(netCDF4.Dataset('file.nc'))"
```

### 7.7 The Croton NY Test Case

The WRF-Hydro repository includes a test case for the **Croton River watershed** in New York state.
It's a small domain used for regression testing.

```
tests/config_file_meta/croton_NY/nwm_ana/
├── namelist.hrldas           ← Land surface config for Croton
├── hydro.namelist            ← Hydrology config for Croton
├── NWM/
│   └── DOMAIN/
│       ├── Fulldom_hires.nc  ← 250m terrain grid
│       ├── geo_em.d01.nc     ← 1km land surface grid
│       ├── Route_Link.nc     ← River network
│       ├── GWBASINS.nc       ← Groundwater basins
│       ├── GWBUCKPARM.nc     ← GW bucket parameters
│       ├── LAKEPARM.nc       ← Lake parameters
│       ├── hydro2dtbl.nc     ← Hydro parameter table
│       ├── nudgingParams.nc  ← Nudging parameters
│       └── soil_properties.nc← Soil parameters
```

> **🧠 ML Analogy:** Croton NY is like the **MNIST** of WRF-Hydro — a small, well-understood
> test case that everyone uses to verify their setup works before running on real data.

---

## 8. 🏃 Running the Model Step-by-Step

### 8.1 Run Process Overview

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│ 1. Download │    │ 2. Setup   │    │ 3. Config  │    │ 4. Run     │
│    test     │───▶│    run     │───▶│    edit     │───▶│            │
│    data     │    │    dir     │    │  namelists  │    │ ./wrf_hydro│
└────────────┘    └────────────┘    └────────────┘    └─────┬──────┘
                                                            │
                                                            ▼
                  ┌────────────┐    ┌────────────┐    ┌────────────┐
                  │ 7. Clean   │    │ 6. Inspect │    │ 5. Check   │
                  │    up      │◀───│    output  │◀───│    logs     │
                  │            │    │    files   │    │            │
                  └────────────┘    └────────────┘    └────────────┘
```

### 8.2 Setting Up a Run Directory

```bash
# ① Activate environment
conda activate wrfhydro-bmi

# ② Create a run directory (separate from source!)
mkdir -p ~/wrf_hydro_runs/croton_test
cd ~/wrf_hydro_runs/croton_test

# ③ Link or copy the executable
ln -s /path/to/wrf_hydro_nwm_public/build/Run/wrf_hydro .

# ④ Copy parameter tables
cp /path/to/wrf_hydro_nwm_public/build/Run/*.TBL .

# ⑤ Copy namelist templates
cp /path/to/wrf_hydro_nwm_public/build/Run/namelist.hrldas .
cp /path/to/wrf_hydro_nwm_public/build/Run/hydro.namelist .

# ⑥ Set up domain data (you need actual test case data for this)
mkdir -p DOMAIN FORCING RESTART

# ⑦ Edit namelists to point to your data and set simulation period
# (edit namelist.hrldas and hydro.namelist)

# ⑧ Run!
mpirun -np 1 ./wrf_hydro       # Serial (1 processor)
# OR
mpirun -np 4 ./wrf_hydro       # Parallel (4 processors)
```

### 8.3 What Happens When You Run

When you execute `./wrf_hydro`, this is the sequence:

```
$ mpirun -np 1 ./wrf_hydro

  ╔══════════════════════════════════════════════════════╗
  ║  1. INITIALIZATION                                   ║
  ╠══════════════════════════════════════════════════════╣
  ║  • Read namelist.hrldas                              ║
  ║  • Read hydro.namelist                               ║
  ║  • Initialize MPI (even with 1 process)              ║
  ║  • Read domain files (geo_em, Fulldom_hires, etc.)   ║
  ║  • Allocate memory for all grids                     ║
  ║  • Read restart files (if warm start)                ║
  ║  • Initialize all physics components                 ║
  ║  • Print configuration summary to stdout             ║
  ╚══════════════════════════════════════════════════════╝
              │
              ▼
  ╔══════════════════════════════════════════════════════╗
  ║  2. TIME LOOP (NTIME iterations)                     ║
  ╠══════════════════════════════════════════════════════╣
  ║  For each timestep:                                  ║
  ║    • Read forcing data for current time              ║
  ║    • Run Noah-MP land surface physics                ║
  ║    • Pass runoff to routing                          ║
  ║    • Run terrain routing (may sub-step)              ║
  ║    • Run channel routing (may sub-step)              ║
  ║    • Run groundwater model                           ║
  ║    • Write output files (if output time)             ║
  ║    • Write restart files (if restart time)           ║
  ║    • Advance clock                                   ║
  ╚══════════════════════════════════════════════════════╝
              │
              ▼
  ╔══════════════════════════════════════════════════════╗
  ║  3. FINALIZATION                                     ║
  ╠══════════════════════════════════════════════════════╣
  ║  • Write final restart files                         ║
  ║  • Close all open file handles                       ║
  ║  • Deallocate memory                                 ║
  ║  • Finalize MPI                                      ║
  ║  • Print timing summary                              ║
  ╚══════════════════════════════════════════════════════╝
```

### 8.4 Console Output: What to Look For

When WRF-Hydro runs, it prints status to stdout. Here's what to watch for:

```
✅ Good signs:
  "Namelist read successfully"
  "Domain dimensions: ix=XX, jx=XX"
  "Routing grid dimensions: ixrt=XX, jxrt=XX"
  "RESTART file read successfully"
  Output files appearing in the run directory

⚠️ Warning signs:
  "WARNING: restart file not found, cold start"
  "WARNING: forcing file not found"

❌ Error signs:
  "FATAL ERROR" or "HYDRO_stop"
  "NetCDF error"
  "Segmentation fault" (memory issue)
  Executable exits immediately with no output
```

> **🧠 ML Analogy:** Running WRF-Hydro is like **model inference** (a forward pass):
> - You provide inputs (forcing data) to a trained model (compiled executable with calibrated parameters)
> - It processes them through multiple layers (physics components)
> - And produces predictions (streamflow, soil moisture, etc.)
>
> The difference: WRF-Hydro is a **deterministic physics simulation**, not a learned model.
> Given the same inputs and parameters, it always produces the same outputs.

---

## 9. 📊 Output Data — What the Model Produces

### 9.1 Output File Types

| Output File Pattern | Content | Grid Type | ML Equivalent |
|--------------------|---------|-----------|---------------|
| `*LDASOUT_DOMAIN1` | Land surface variables (soil moisture, snow, ET) | 1km rectilinear | Feature map predictions |
| `*CHRTOUT_DOMAIN1` | Channel streamflow at all reach points | 1D point (network) | Node-level predictions (GNN) |
| `*RTOUT_DOMAIN1` | Terrain routing variables (surface/subsurface) | 250m rectilinear | High-res feature predictions |
| `*LAKEOUT_DOMAIN1` | Lake/reservoir water levels | 1D point (per lake) | Special node outputs |
| `*GWOUT_DOMAIN1` | Groundwater/baseflow variables | Basin-level | Aggregated region outputs |
| `*CHANOBS_DOMAIN1` | Streamflow at observation points only | 1D point (selected) | Evaluation metric locations |
| `*LSMOUT_DOMAIN1` | LSM ↔ routing interface variables | 2D grid | Intermediate layer outputs |

### 9.2 Key Output Variables

| Variable | In LDASOUT | Description | Units | BMI Standard Name |
|----------|-----------|-------------|-------|-------------------|
| SOIL_M | ✅ | Soil moisture (per layer) | m³/m³ | `soil_water__volume_fraction` |
| SNEQV | ✅ | Snow water equivalent | mm | `snowpack__liquid-equivalent_depth` |
| ACCET | ✅ | Accumulated evapotranspiration | mm | `land_surface_water__evaporation_volume_flux` |
| T2 | ✅ | 2-meter air temperature | K | `land_surface_air__temperature` |
| RAINRATE | ✅ | Precipitation rate | mm/s | `atmosphere_water__precipitation_leq-volume_flux` |

| Variable | In CHRTOUT | Description | Units | BMI Standard Name |
|----------|-----------|-------------|-------|-------------------|
| streamflow | ✅ | River discharge | m³/s | `channel_water__volume_flow_rate` |

| Variable | In RTOUT | Description | Units | BMI Standard Name |
|----------|---------|-------------|-------|-------------------|
| sfcheadrt | ✅ | Surface water depth | m | `land_surface_water__depth` |
| UGDRNOFF | ✅ | Baseflow | mm | `soil_water__domain_time_integral_of_baseflow_volume_flux` |

### 9.3 Inspecting Output Files

```bash
# ── View file structure ──
ncdump -h 202108260100.CHRTOUT_DOMAIN1

# ── View specific variable ──
ncdump -v streamflow 202108260100.CHRTOUT_DOMAIN1 | head -50

# ── Python quick look ──
python3 << 'EOF'
import netCDF4 as nc

# Open output file
ds = nc.Dataset("202108260100.CHRTOUT_DOMAIN1")

# List all variables
print("Variables:", list(ds.variables.keys()))

# Read streamflow
q = ds.variables['streamflow'][:]
print(f"Streamflow: min={q.min():.2f}, max={q.max():.2f}, mean={q.mean():.2f} m3/s")

# Read coordinates
lat = ds.variables['latitude'][:]
lon = ds.variables['longitude'][:]
print(f"Domain: lat=[{lat.min():.2f}, {lat.max():.2f}], lon=[{lon.min():.2f}, {lon.max():.2f}]")

ds.close()
EOF
```

### 9.4 Restart Files (Output Checkpoints)

When the model writes restart files, they appear as:

```
RESTART/
├── RESTART.2011082700_DOMAIN1           ← NoahMP state at 2011-08-27 00:00 UTC
└── HYDRO_RST.2011-08-27_00:00_DOMAIN1  ← Hydro state at 2011-08-27 00:00 UTC
```

> **🧠 ML Analogy:** Output files are **predictions** at each time step.
> - `LDASOUT` = spatial feature predictions (like segmentation maps)
> - `CHRTOUT` = point predictions along a graph (like node classification)
> - `RTOUT` = high-res spatial predictions
> - Restart files = **full model checkpoints** you can resume from
>
> Just like you'd save `model.state_dict()` and `optimizer.state_dict()`,
> WRF-Hydro saves the full state of every variable in the simulation.

---

## 10. 📋 Quick Reference Card

### 10.1 Command Cheat Sheet

```bash
# ══════════════════════════════════════
# 🔧 ENVIRONMENT
# ══════════════════════════════════════
conda activate wrfhydro-bmi          # Activate environment
which gfortran                        # Check Fortran compiler
which mpif90                          # Check MPI Fortran wrapper
nc-config --all                       # Check NetCDF installation
cmake --version                       # Check CMake

# ══════════════════════════════════════
# 🔨 BUILD
# ══════════════════════════════════════
cd wrf_hydro_nwm_public
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release   # Configure
make -j$(nproc)                       # Compile (parallel)
make clean                            # Clean compiled files
ls Run/wrf_hydro                      # Check executable exists

# ══════════════════════════════════════
# 🏃 RUN
# ══════════════════════════════════════
cd /path/to/run_directory
mpirun -np 1 ./wrf_hydro              # Run serial
mpirun -np 4 ./wrf_hydro              # Run parallel (4 cores)

# ══════════════════════════════════════
# 📊 INSPECT OUTPUT
# ══════════════════════════════════════
ncdump -h output.nc                   # View file header/structure
ncdump -v varname output.nc           # View specific variable
ncview output.nc                      # GUI viewer (if installed)
python -c "import netCDF4; print(netCDF4.Dataset('output.nc'))"

# ══════════════════════════════════════
# 🧪 BMI DEVELOPMENT
# ══════════════════════════════════════
# Compile BMI module only:
gfortran -c -I$CONDA_PREFIX/include bmi_wrf_hydro.f90

# Compile with BMI Fortran library:
gfortran -c -I$CONDA_PREFIX/include bmi_wrf_hydro.f90 \
    -L$CONDA_PREFIX/lib -lbmif

# Build bmi-example-fortran:
cd bmi-example-fortran
cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX
cmake --build _build
ctest --test-dir _build
```

### 10.2 Key File Locations

| What | Where |
|------|-------|
| WRF-Hydro source | `wrf_hydro_nwm_public/src/` |
| Main entry point | `src/Land_models/NoahMP/IO_code/main_hrldas_driver.F` |
| Hydro driver | `src/HYDRO_drv/module_HYDRO_drv.F90` |
| NoahMP physics | `src/Land_models/NoahMP/phys/module_sf_noahmplsm.F` |
| Channel routing | `src/Routing/module_channel_routing.F90` |
| Compiled executable | `wrf_hydro_nwm_public/build/Run/wrf_hydro` |
| Compiled libraries | `wrf_hydro_nwm_public/build/lib/` |
| Namelist templates | `src/template/NoahMP/` and `src/template/HYDRO/` |
| NWM example configs | `src/template/examples/nwm/namelists/v3.0/` |
| Parameter tables | `build/Run/*.TBL` |
| Test case metadata | `tests/config_file_meta/croton_NY/` |
| BMI specification | `bmi-fortran/bmi.f90` |
| BMI example | `bmi-example-fortran/bmi_heat/bmi_heat.f90` |
| SCHISM BMI reference | `schism_NWM_BMI/src/bmischism.f90` |
| Our BMI wrapper | `bmi_wrf_hydro/` (work directory) |

### 10.3 Troubleshooting Guide

| Problem | Likely Cause | Solution |
|---------|-------------|----------|
| `cmake` can't find NetCDF | Environment not activated | `conda activate wrfhydro-bmi` |
| `mpif90: command not found` | MPI not installed | `conda install openmpi` |
| Compile error: argument mismatch | Old gfortran version | Need gfortran >= 9 (uses `-fallow-argument-mismatch`) |
| Runtime: `FATAL ERROR` on start | Missing DOMAIN files | Check namelists point to valid paths |
| Runtime: `NetCDF error` | Wrong file format/path | Check with `ncdump -h` on input files |
| Runtime: `Segmentation fault` | Memory issue or wrong dims | Check grid dimensions match domain files |
| No output files created | Too short simulation | Check `KHOUR` and `out_dt` settings |
| Restart file not found | Wrong path in namelist | Comment out restart line for cold start |
| BMI compile error | Missing `bmif_2_0` module | `conda install bmi-fortran` and use `-I$CONDA_PREFIX/include` |

### 10.4 Glossary: Hydrology ↔ ML Terms

| Hydrology Term | Definition | ML Equivalent |
|---------------|------------|---------------|
| **Forcing data** | Time-varying atmospheric inputs (rain, temp) | Input features / training data |
| **Namelist** | Fortran configuration file format | YAML/JSON config |
| **Domain** | Geographic area being simulated | Input dimensions / spatial extent |
| **Grid cell** | One spatial unit of the model | One pixel in an image |
| **Timestep** | Temporal resolution (e.g., 3600s) | Batch / time step in sequence model |
| **Spinup** | Running model until it reaches equilibrium | Warmup training / burn-in period |
| **Calibration** | Adjusting parameters to match observations | Hyperparameter tuning / fine-tuning |
| **Validation** | Comparing model output to observations | Model evaluation on test set |
| **Restart file** | Full model state at a time point | Model checkpoint (.pt file) |
| **Cold start** | Starting with default/table initialization | Training from scratch |
| **Warm start** | Starting from a restart file | Resuming from checkpoint |
| **Routing** | Moving water through the landscape | Message passing in a GNN |
| **Runoff** | Water that doesn't infiltrate soil | Overflow / excess activation |
| **Streamflow** | Volume of water flowing in a river | Prediction output at graph nodes |
| **Discharge** | Same as streamflow (m³/s) | Same as above |
| **Evapotranspiration** | Water lost to atmosphere from land | "Loss" that leaves the system |
| **Infiltration** | Water entering the soil | Input absorption |
| **Baseflow** | Slow groundwater contribution to streams | Skip connection / residual |
| **Manning's N** | Channel roughness coefficient | Learned parameter (friction) |
| **DEM** | Digital Elevation Model (terrain height) | Static input feature map |
| **Catchment** | Area draining to a single point | Receptive field |
| **Reach** | One segment of a river | One edge in a graph |
| **NHDPlus** | National river network dataset | Graph structure dataset |
| **NetCDF** | Self-describing array file format | HDF5 / .npy |
| **MPI** | Message Passing Interface (parallelism) | DistributedDataParallel |
| **NUOPC** | Coupling framework for Earth models | Model orchestration framework |
| **BMI** | Basic Model Interface (standardized API) | ONNX Runtime API |
| **PyMT** | Python Modeling Toolkit (coupling framework) | PyTorch Hub / model registry |
| **Babelizer** | Fortran→Python wrapper generator | pybind11 / ctypes auto-generator |

### 10.5 Numbers to Know

| Metric | Value | Context |
|--------|-------|---------|
| Source files | 244 | Fortran files in `src/` |
| Total lines of code | 172,817 | All Fortran source |
| Compiled libraries | 22 | Linked into final executable |
| Executable size | 4.5 MB | `wrf_hydro` binary |
| Largest source file | 11,399 lines | `module_HYDRO_io.F90` (I/O) |
| Largest physics file | 10,177 lines | `module_sf_noahmplsm.F` (NoahMP core) |
| WRF-Hydro version | 5.4.0 | Current release |
| NWM version | 3.1-beta | National Water Model |
| BMI functions | 41 | Must implement all 41 |
| NWM river reaches | ~2.7 million | Continental U.S. river network |
| Noah-MP grid | 1km | Land surface resolution |
| Routing grid | 250m | Terrain routing resolution |
| Land model timestep | 3600s (1 hour) | Physics update frequency |
| Routing timestep | 10s | Hydraulic update frequency |
| Soil layers | 4 | Vertical discretization |

---

## 🎯 What's Next?

Now that you understand WRF-Hydro's architecture, the next step is to:

1. **Build and run the BMI heat example** (`bmi-example-fortran/`) to understand the BMI pattern
2. **Study SCHISM's BMI wrapper** (`schism_NWM_BMI/src/bmischism.f90`) as a real-world reference
3. **Write `bmi_wrf_hydro.f90`** — our BMI wrapper that decomposes the time loop into
   `initialize()`, `update()`, and `finalize()` calls

The key challenge: **extracting the time loop** from `main_hrldas_driver.F` so that
Python (via PyMT) can control when each timestep executes, enabling coupling with SCHISM.

---

> **📝 Document Info**
> - Created: 2026-02-17
> - Source: Verified against WRF-Hydro v5.4.0 source code
> - Audience: ML Engineers with zero Fortran/hydrology background
> - Project: WRF-Hydro BMI Wrapper (Phase 1)
