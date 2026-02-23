# 🌊 SCHISM BMI — Complete Guide: How to Build, Configure, and Run

> 📅 **Created**: February 20, 2026
> 📍 **Project**: WRF-Hydro + SCHISM Coupling via BMI

---

## 📑 Table of Contents

1. [🎯 What This Guide Covers](#1--what-this-guide-covers)
2. [🌍 Big Picture — Why Run SCHISM with BMI?](#2--big-picture--why-run-schism-with-bmi)
3. [🧱 What is SCHISM? (Quick Refresher)](#3--what-is-schism-quick-refresher)
4. [🔌 What is BMI? (Quick Refresher)](#4--what-is-bmi-quick-refresher)
5. [🏗️ How SCHISM Implements BMI (Architecture)](#5--how-schism-implements-bmi-architecture)
6. [📁 SCHISM Source Code Structure](#6--schism-source-code-structure)
7. [⚙️ Step-by-Step: Build SCHISM with BMI Enabled](#7--step-by-step-build-schism-with-bmi-enabled)
8. [📂 Input Files You Need to Run SCHISM](#8--input-files-you-need-to-run-schism)
9. [🚀 Step-by-Step: Run SCHISM with BMI](#9--step-by-step-run-schism-with-bmi)
10. [🔄 How SCHISM's IRF Pattern Works (The Time Loop)](#10--how-schisms-irf-pattern-works-the-time-loop)
11. [📥 How Data Flows In/Out via BMI](#11--how-data-flows-inout-via-bmi)
12. [📊 SCHISM BMI Variables (What Gets Exposed)](#12--schism-bmi-variables-what-gets-exposed)
13. [🔗 The LynkerIntel SCHISM_BMI Repository](#13--the-lynkerintel-schism_bmi-repository)
14. [🏛️ NOAA NextGen Framework Integration](#14--noaa-nextgen-framework-integration)
15. [🐍 Python BMI / PyMT Status](#15--python-bmi--pymt-status)
16. [❓ Frequently Asked Questions](#16--frequently-asked-questions)
17. [📚 References and Resources](#17--references-and-resources)

---

## 1. 🎯 What This Guide Covers

This guide explains **everything** you need to know about running SCHISM with BMI (Basic Model Interface) enabled. It covers:

- ✅ What SCHISM and BMI are (quick refresher)
- ✅ How SCHISM's BMI integration works internally (the `#ifdef` approach)
- ✅ How to **compile** SCHISM with the BMI flag turned on
- ✅ What **input files** you need
- ✅ How to **run** the model with BMI
- ✅ How **data flows** between WRF-Hydro and SCHISM through BMI
- ✅ The **LynkerIntel BMI wrapper** (separate repository with full BMI functions)
- ✅ NOAA's **NextGen framework** integration
- ✅ Current status of **Python/PyMT** bindings

> 💡 **Who is this for?** This guide is written for hydrology students who may not be familiar with Fortran compilation, CMake build systems, or preprocessor flags. Every technical term is explained.

---

## 2. 🌍 Big Picture — Why Run SCHISM with BMI?

### 🤔 The Problem

We want to simulate **compound flooding** — when river flooding (from rain) meets coastal flooding (from storm surge) at the same time and place. This requires two models working together:

```
┌─────────────────┐                          ┌─────────────────┐
│    WRF-Hydro     │    river discharge       │     SCHISM       │
│  (Hydrology)     │ ──────────────────────►  │  (Coastal Ocean) │
│                  │                          │                  │
│ Computes:        │    coastal water level   │ Computes:        │
│ • Rainfall runoff│ ◄──────────────────────  │ • Storm surge    │
│ • River flow     │                          │ • Tides          │
│ • Soil moisture  │                          │ • Ocean currents │
└─────────────────┘                          └─────────────────┘
```

### 🔌 The Solution: BMI

BMI (Basic Model Interface) is the **standardized bridge** that lets these two models exchange data without knowing each other's internal code. Think of it like a **universal USB port** — any model that implements BMI can plug into any other BMI model.

### 🎯 Our Specific Goal

```
WRF-Hydro                    BMI                           SCHISM
━━━━━━━━━                ━━━━━━━━━                      ━━━━━━━━
Computes streamflow  ──►  get_value("discharge")  ──►   Receives as
(QLINK variable)          returns river flow data        source/sink input
                          in standard format             (ath3 array)
```

**Right now**: We're studying how SCHISM's BMI works so we can build the same thing for WRF-Hydro.

---

## 3. 🧱 What is SCHISM? (Quick Refresher)

**SCHISM** = **S**emi-implicit **C**ross-scale **H**ydroscience **I**ntegrated **S**ystem **M**odel

| Aspect | Details |
|--------|---------|
| **What it does** | Simulates ocean/coastal/estuarine water circulation in 3D |
| **Grid type** | Unstructured triangular mesh (flexible resolution) |
| **Developed by** | VIMS (Virginia Institute of Marine Science) |
| **Language** | Fortran 90 |
| **Parallelism** | MPI (Message Passing Interface) — runs on multiple CPU cores |
| **Key outputs** | Water elevation (`eta2`), currents (`VX`, `VY`), salinity, temperature |
| **Key inputs** | Wind, pressure, river discharge, tidal boundaries |
| **Used in** | NOAA's STOFS-3D-Atlantic operational forecasting |

### 🌊 Why SCHISM for Compound Flooding?

SCHISM can simulate:
- Storm surge (ocean water pushed inland by hurricanes)
- Tidal cycles (daily rise/fall of ocean water)
- River plumes (where freshwater meets saltwater)
- Flooding on land (wetting/drying of grid elements)

When combined with WRF-Hydro's inland hydrology, you get a **complete picture** of compound flooding.

---

## 4. 🔌 What is BMI? (Quick Refresher)

**BMI** = **B**asic **M**odel **I**nterface

BMI is a **set of 41 standard functions** that any model must implement to be coupled with other models. Published by **CSDMS** (Community Surface Dynamics Modeling System) at University of Colorado Boulder.

### 🔑 The 3 Most Important BMI Functions

```fortran
! 1. INITIALIZE — Set up the model (read config, allocate memory)
call model%initialize("config_file.nml")

! 2. UPDATE — Run the model for exactly ONE time step
call model%update()

! 3. FINALIZE — Clean up (free memory, close files)
call model%finalize()
```

### 📦 Data Exchange Functions

```fortran
! GET data OUT of the model
call model%get_value("sea_water_surface__elevation", water_level_array)

! SET data INTO the model
call model%set_value("channel_water__volume_flow_rate", discharge_array)
```

> 💡 **Key insight**: BMI means the **caller** (Python script, another model, or a framework) controls the time loop — NOT the model itself. The model just does one step at a time when told to.

---

## 5. 🏗️ How SCHISM Implements BMI (Architecture)

### ⚠️ Important: Two Different Approaches Exist

There are **two different implementations** of BMI for SCHISM:

| Approach | Location | What It Is |
|----------|----------|------------|
| **Approach 1: `#ifdef` blocks** | Our local repo: `schism_NWM_BMI/src/` | Preprocessor flags in 3 source files that modify how SCHISM reads source/sink data. **NOT a full BMI wrapper.** |
| **Approach 2: Full BMI wrapper** | External repo: `LynkerIntel/SCHISM_BMI` on GitHub | A separate Fortran module (`bmischism.f90`) that implements all 41 BMI functions. **This is the real BMI.** |

### 📊 Approach 1: The `#ifdef USE_NWM_BMI` Blocks (In Our Local Code)

This is what we have in our `schism_NWM_BMI/` directory. It uses **C Preprocessor (CPP) flags** to conditionally compile BMI-related code.

#### What is `#ifdef`?

```fortran
! This is a preprocessor directive (runs BEFORE compilation)
#ifdef USE_NWM_BMI
  ! This code is INCLUDED only if USE_NWM_BMI flag is turned ON
  ! during compilation (cmake -DUSE_NWM_BMI=ON)
  print *, "BMI mode is active!"
#else
  ! This code is INCLUDED only if flag is OFF (normal mode)
  print *, "Running without BMI"
#endif
```

Think of `#ifdef` like a **light switch** in the code:
- 🔴 **Switch OFF** (`-DUSE_NWM_BMI=OFF`): SCHISM ignores all BMI code, runs normally
- 🟢 **Switch ON** (`-DUSE_NWM_BMI=ON`): SCHISM activates BMI coupling code

#### Where Are These `#ifdef` Blocks?

Only **3 files** are modified, with a total of **5 small code blocks**:

| File | Location | # of Blocks | What the Block Does |
|------|----------|:-----------:|---------------------|
| `schism_init.F90` | `src/Hydro/` | 1 | Validates that `if_source ≠ 0` (source/sink input must be enabled) |
| `schism_step.F90` | `src/Hydro/` | 2 | Replaces file-based source/sink reading with BMI array updates |
| `misc_subs.F90` | `src/Hydro/` | 2 | Initializes source/sink arrays for BMI mode (zeros instead of file data) |

#### Block 1: Validation in `schism_init.F90` (line 1141)

```fortran
#ifdef USE_NWM_BMI
      if(if_source==0) call parallel_abort('INIT: USE_NWM_BMI cannot go with if_source=0')
#endif
```

📖 **What this means in plain English:**
- `if_source` is a setting in SCHISM's config file (`param.nml`)
- `if_source = 0` means "no source/sink inputs" (no river discharge entering the ocean)
- `if_source = 1` means "read source/sink from ASCII text files"
- `if_source = -1` means "read source/sink from NetCDF files"
- When BMI is ON, you **must** have source/sink enabled (either 1 or -1)
- Because the whole point of BMI coupling is to **receive river discharge** from WRF-Hydro!

#### Block 2-3: Source/Sink Initialization in `misc_subs.F90` (line 599)

```fortran
#ifdef USE_NWM_BMI
      ! Instead of reading source/sink data from files,
      ! initialize time windows and set arrays to zero.
      ! BMI will provide the actual values later.
      ninv = time / th_dt3(1)
      th_time3(1,1) = ninv * th_dt3(1)          ! Current time window start
      th_time3(2,1) = th_time3(1,1) + th_dt3(1) ! Current time window end

      ! Initialize source arrays to zero (BMI will fill them)
      ath3(:,1,1,1:2) = 0.d0    ! Volume sources = 0 m³/s
      ath3(:,1,1,3) = -9999.d0  ! Mass sources = junk (use ambient values)
#else
      ! Normal mode: read from vsource.th, vsink.th, msource.th files
      if(myrank==0) then
        read(63,*) tmp, ath3(1:nsources,1,1,1)   ! Read volume sources from file
        read(63,*) th_dt3(1), ath3(1:nsources,1,2,1)
        ...
      endif
#endif
```

📖 **What this means in plain English:**
- Normal SCHISM reads river discharge values from **text files** (`vsource.th`)
- With BMI ON, it **skips the file reading** and sets everything to zero
- The external caller (WRF-Hydro via BMI) will **inject** the actual discharge values into the `ath3` array before each time step

#### Block 4-5: Time Step Update in `schism_step.F90` (line 1540)

```fortran
#ifdef USE_NWM_BMI
        ! Update source/sink data using BMI-provided values
        ! (instead of reading next record from file)
        if(nsources > 0) then
          if(time > th_time3(2,1)) then           ! Time to advance to next snapshot?
            ath3(:,1,1,1) = ath3(:,1,2,1)         ! Slide: new → old
            th_time3(1,1) = th_time3(2,1)         ! Advance time window
            th_time3(2,1) = th_time3(2,1) + th_dt3(1)
          endif
        endif
        ! Similar logic for sinks and mass sources...
#else
        ! Normal mode: read next record from file when time advances
        if(nsources > 0 .and. myrank == 0) then
          if(time > th_time3(2,1)) then
            read(63,*) tmp, ath3(1:nsources,1,1,1)  ! Read from vsource.th
            ...
          endif
        endif
#endif
```

📖 **What this means in plain English:**
- SCHISM uses a **sliding time window** for source/sink data
- It keeps two time snapshots: `ath3(:,:,1,:)` = old, `ath3(:,:,2,:)` = new
- Between snapshots, it **interpolates** to get the value at any time
- Normal mode reads the "new" snapshot from a file
- BMI mode expects the **external caller** to have already written the "new" values into `ath3(:,:,2,:)` via `set_value()`

### 📊 Approach 2: The Full BMI Wrapper (LynkerIntel/SCHISM_BMI)

This is a **separate repository** on GitHub maintained by LynkerIntel (contractors for NOAA):

🔗 **Repository**: https://github.com/LynkerIntel/SCHISM_BMI

This contains:
- `bmischism.f90` — A **proper Fortran BMI module** that extends the abstract BMI type
- `schism_BMI_driver_test.f90` — A test driver program
- `SCHISM_LIB_NWM_BMI/` — Pre-compiled SCHISM libraries with BMI enabled
- `iso_c_fortran_bmi/` — ISO C binding middleware for calling from C/Python

> ⚠️ **Our local `schism_NWM_BMI/` repo does NOT contain this wrapper.** We only have the `#ifdef` blocks. The full BMI wrapper is in the LynkerIntel repo, which we'd need to clone separately.

---

## 6. 📁 SCHISM Source Code Structure

Here's the directory layout of our local SCHISM code:

```
schism_NWM_BMI/
├── 📄 README.md               ← Project description
├── 📄 CONTRIBUTING.md          ← How to contribute
├── 📄 Dockerfile               ← Docker build config
├── 📁 cmake/                   ← CMake build configuration
│   ├── SCHISM.local.build      ← ⭐ Toggle USE_NWM_BMI here
│   ├── SCHISM.local.ubuntu     ← Compiler paths for Ubuntu/WSL
│   ├── SCHISM.local.intel      ← Compiler paths for Intel
│   └── ...
├── 📁 src/                     ← ⭐ All source code (437 files)
│   ├── CMakeLists.txt          ← ⭐ Master build file
│   ├── 📁 Driver/
│   │   └── schism_driver.F90   ← ⭐ Main program (180 lines) — IRF pattern!
│   ├── 📁 Hydro/
│   │   ├── schism_init.F90     ← ⭐ Initialization (BMI #ifdef block 1)
│   │   ├── schism_step.F90     ← ⭐ One timestep (BMI #ifdef blocks 2-3)
│   │   ├── schism_finalize.F90 ← Cleanup
│   │   └── misc_subs.F90       ← ⭐ Utilities (BMI #ifdef blocks 4-5)
│   ├── 📁 Core/
│   │   ├── schism_glbl.F90     ← ⭐ Global variables (ath3, eta2, nsources)
│   │   └── schism_msgp.F90     ← MPI message passing
│   └── ... (other physics modules)
├── 📁 sample_inputs/           ← Example configuration files
│   └── param.nml               ← ⭐ Main parameter namelist
├── 📁 mk/                      ← Legacy Makefile build system
├── 📁 doc/                     ← Documentation
└── 📁 test/                    ← Test cases
```

### 🔑 Key Files for BMI

| File | Lines | What It Does |
|------|------:|--------------|
| `schism_driver.F90` | 180 | Main program — calls `schism_init0()`, `schism_step0()`, `schism_finalize0()` |
| `schism_init.F90` | ~3000 | Full initialization — reads grids, allocates arrays, sets up physics |
| `schism_step.F90` | ~2000 | One timestep — solves hydrodynamic equations, updates all fields |
| `schism_finalize.F90` | ~50 | Cleanup — deallocates memory, closes files |
| `schism_glbl.F90` | ~600 | Global variables — `ath3`, `eta2`, `nsources`, `time`, etc. |
| `misc_subs.F90` | ~700 | Utility subroutines — includes source/sink reading |

---

## 7. ⚙️ Step-by-Step: Build SCHISM with BMI Enabled

### 📋 Prerequisites

You need these tools installed (all available via conda or system package manager):

| Tool | Version | What It Is | Why We Need It |
|------|---------|-----------|----------------|
| **gfortran** | 14.x+ | GNU Fortran compiler | Compiles SCHISM's Fortran source code |
| **gcc** | 14.x+ | GNU C compiler | Compiles C portions and NetCDF bindings |
| **OpenMPI** | 5.x+ | MPI library | SCHISM requires MPI even for single-core runs |
| **NetCDF-Fortran** | 4.6+ | Network Common Data Form | SCHISM reads/writes NetCDF input/output files |
| **NetCDF-C** | 4.9+ | NetCDF C library | Required by NetCDF-Fortran |
| **HDF5** | 1.14+ | Hierarchical Data Format | Backend for NetCDF-4 files |
| **CMake** | 3.12+ | Build system generator | Creates Makefiles from CMakeLists.txt |
| **ParMETIS** | 4.0.3 | Graph partitioning library | Decomposes mesh for parallel runs (included in SCHISM) |

### 🔧 Step 1: Set Up Your Environment

```bash
# If using conda (recommended):
source ~/miniconda3/etc/profile.d/conda.sh
conda activate wrfhydro-bmi

# Verify tools are available:
gfortran --version    # Should show 14.x.x
mpif90 --version      # Should show gfortran via OpenMPI wrapper
cmake --version       # Should show 3.12+
nf-config --all       # Should show NetCDF-Fortran paths
```

### 🔧 Step 2: Configure CMake with BMI Flag

Navigate to the SCHISM source directory and edit the build configuration:

```bash
cd /path/to/schism_NWM_BMI
```

**Option A: Edit the config file** (recommended for reproducibility)

Edit `cmake/SCHISM.local.build`:

```cmake
# Line 25 — Change OFF to ON:
set (USE_NWM_BMI ON CACHE BOOLEAN "Use NWM BMI for source and some b.c.")

# Also enable these if needed:
set (OLDIO ON CACHE BOOLEAN "Old nc output")        # Simpler I/O for single-core
set (USE_ATMOS ON CACHE BOOLEAN "Atmospheric model") # If using atmospheric forcing
```

**Option B: Pass flag directly to cmake** (simpler for testing)

```bash
cmake .. -DUSE_NWM_BMI=ON
```

### 🔧 Step 3: Add Position-Independent Code Flag

For building a **shared library** (`.so` file) that can be loaded by Python/BMI:

Edit `src/CMakeLists.txt` and add near the top:

```cmake
add_compile_options("-fPIC")
```

> 📖 **What is `-fPIC`?**
> PIC = Position-Independent Code. This tells the compiler to generate code that can be loaded at **any memory address** — required for shared libraries (`.so` files) that Python or other programs load at runtime. Without this, you can only create static executables.

### 🔧 Step 4: Create Build Directory and Run CMake

```bash
# Create a clean build directory (outside the source tree)
mkdir -p build
cd build

# Remove any old build cache
rm -rf *

# Run CMake with the configuration files
cmake -C ../cmake/SCHISM.local.build \
      -C ../cmake/SCHISM.local.ubuntu \
      -DUSE_NWM_BMI=ON \
      ../src/
```

📖 **What each flag means:**
- `-C ../cmake/SCHISM.local.build` — Load settings from this file (our BMI toggle)
- `-C ../cmake/SCHISM.local.ubuntu` — Load compiler paths for Ubuntu/WSL
- `-DUSE_NWM_BMI=ON` — Explicitly turn on BMI (overrides file setting if needed)
- `../src/` — Path to the source code's `CMakeLists.txt`

### 🔧 Step 5: Compile

```bash
# Compile using all available CPU cores
make -j$(nproc) pschism

# Or with verbose output (useful for debugging):
make VERBOSE=1 pschism
```

> ⏱️ **Build time**: ~5-15 minutes depending on your machine.

### 🔧 Step 6: Verify the Build

```bash
# Check the executable was created:
ls -lh bin/pschism*

# You should see something like:
# bin/pschism_SCHISM_NWM_BMI_TVD-VL
#
# The "NWM_BMI" in the name confirms USE_NWM_BMI was enabled!
```

If you see `NWM_BMI` in the executable name, the BMI flag was compiled in. ✅

### 🔧 (Optional) Step 7: Build as Shared Library

If you want to use SCHISM from Python or through the LynkerIntel BMI wrapper:

```bash
# Copy compiled libraries for BMI wrapper to use:
cp -r lib/ /path/to/SCHISM_BMI/SCHISM_LIB_NWM_BMI/
cp -r include/ /path/to/SCHISM_BMI/SCHISM_LIB_NWM_BMI/
```

---

## 8. 📂 Input Files You Need to Run SCHISM

SCHISM requires several input files. Here are the essential ones:

### 📁 Required Input Files

| File | Format | What It Contains |
|------|--------|------------------|
| **`param.nml`** | Fortran namelist | ⭐ Main configuration — time step, duration, physics options |
| **`hgrid.gr3`** | ASCII text | ⭐ Horizontal grid — node coordinates + element connectivity |
| **`vgrid.in`** | ASCII text | Vertical grid — number of levels, layer distribution |
| **`bctides.in`** | ASCII text | Tidal boundary conditions — which boundaries, which constituents |
| **`drag.gr3`** | ASCII text | Bottom friction coefficients at each node |

### 📁 Source/Sink Files (Required for BMI mode)

When `if_source = 1` (ASCII mode):

| File | What It Contains |
|------|------------------|
| **`source_sink.in`** | Lists which elements are sources (rivers) and which are sinks |
| **`vsource.th`** | Volume source time series — discharge in m³/s at each source element |
| **`vsink.th`** | Volume sink time series — water removal rates |
| **`msource.th`** | Mass source time series — tracer concentrations (salinity, temperature) |

When `if_source = -1` (NetCDF mode):

| File | What It Contains |
|------|------------------|
| **`source.nc`** | All source/sink data in a single NetCDF file (preferred for automated coupling) |

### 📁 Atmospheric Forcing (Optional but common)

| File | What It Contains |
|------|------------------|
| **`sflux/sflux_air_1.nc`** | Wind speed, air temperature, humidity, pressure |
| **`sflux/sflux_prc_1.nc`** | Precipitation |
| **`sflux/sflux_rad_1.nc`** | Solar radiation |

### ⭐ Critical `param.nml` Settings for BMI

```fortran
&CORE
  ipre = 0              ! 0 = non-hydrostatic, 1 = hydrostatic
  ibc = 0               ! Baroclinic flag (0 = barotropic only)
  rnday = 10.0          ! Simulation length in days
  dt = 100.0            ! Time step in seconds
  nspool = 36           ! Output every 36 steps (3600 sec = 1 hour)
/

&OPT
  ! ⭐ CRITICAL FOR BMI: Must NOT be 0 when USE_NWM_BMI is enabled!
  if_source = 1         ! 1 = ASCII source files, -1 = NetCDF source.nc
                        ! 0 = NO sources (⛔ FORBIDDEN with BMI!)

  dramp_ss = 2.0        ! Ramp-up period for sources in days
                        ! (gradually increases source strength to avoid shock)

  start_year = 2011     ! Simulation start date
  start_month = 8
  start_day = 27
  start_hour = 0
/
```

> ⚠️ **The most common error**: If you compile with `USE_NWM_BMI=ON` but leave `if_source=0` in `param.nml`, SCHISM will immediately **crash** with:
> ```
> INIT: USE_NWM_BMI cannot go with if_source=0
> ```
> **Fix**: Set `if_source = 1` or `if_source = -1`.

---

## 9. 🚀 Step-by-Step: Run SCHISM with BMI

### 🏃 Running SCHISM Standalone (Traditional Mode)

Even with BMI enabled, SCHISM can run standalone (reading source data from files instead of BMI):

```bash
# Navigate to the run directory (where your input files are)
cd /path/to/schism_run/

# Make sure all input files are present
ls param.nml hgrid.gr3 vgrid.in bctides.in source_sink.in vsource.th

# Run with MPI (even for 1 core, SCHISM needs MPI)
mpirun --oversubscribe -np 1 /path/to/build/bin/pschism_SCHISM_NWM_BMI_TVD-VL 0
```

📖 **Command breakdown:**
- `mpirun` — MPI launcher (starts parallel processes)
- `--oversubscribe` — Allow more processes than CPU cores (needed on some systems)
- `-np 1` — Number of processes (start with 1 for testing)
- `/path/to/pschism_...` — Path to the compiled executable
- `0` — Number of scribe processes (0 = no dedicated I/O process)

### 🔄 Running SCHISM via BMI (External Caller Mode)

When running through BMI, an **external program** controls the time loop:

#### Fortran BMI Driver Example

```fortran
program run_schism_bmi
  ! This program demonstrates how to run SCHISM through BMI
  ! An external caller (like this program, or PyMT) controls everything

  use bmischism       ! Import the SCHISM BMI wrapper module
  implicit none

  type(bmi_schism) :: model           ! Create a SCHISM BMI instance
  integer :: status                    ! Return code (0 = success, 1 = failure)
  real(8) :: current_time, end_time, dt
  real(8), allocatable :: discharge(:) ! Array for river discharge data

  ! ═══════════════════════════════════════
  ! STEP 1: INITIALIZE
  ! ═══════════════════════════════════════
  ! This reads param.nml, hgrid.gr3, vgrid.in, etc.
  ! Allocates all arrays, sets up the mesh, computes initial conditions
  status = model%initialize("namelist.input")

  if (status /= 0) then
    print *, "ERROR: SCHISM initialization failed!"
    stop
  end if

  print *, "SCHISM initialized successfully!"

  ! ═══════════════════════════════════════
  ! STEP 2: QUERY MODEL INFO
  ! ═══════════════════════════════════════
  status = model%get_start_time(current_time)
  status = model%get_end_time(end_time)
  status = model%get_time_step(dt)

  print *, "Start time:", current_time, "seconds"
  print *, "End time:  ", end_time, "seconds"
  print *, "Time step: ", dt, "seconds"

  ! ═══════════════════════════════════════
  ! STEP 3: TIME LOOP (WE control it, not SCHISM!)
  ! ═══════════════════════════════════════
  do while (current_time < end_time)

    ! --- Inject river discharge from WRF-Hydro ---
    ! In a real coupling scenario, this comes from WRF-Hydro's BMI:
    !   call wrfhydro%get_value("channel_water__volume_flow_rate", discharge)
    ! For testing, we can use dummy values:
    discharge = 100.0  ! 100 m³/s at each source element

    ! Set the discharge into SCHISM
    status = model%set_value("Q_bnd", discharge)

    ! --- Advance SCHISM by one time step ---
    status = model%update()

    ! --- Read outputs from SCHISM ---
    ! Get water elevation at all nodes
    status = model%get_value("ETA2", water_level)

    print *, "Time:", current_time, " Max elevation:", maxval(water_level)

    ! Update current time
    status = model%get_current_time(current_time)

  end do

  ! ═══════════════════════════════════════
  ! STEP 4: FINALIZE (cleanup)
  ! ═══════════════════════════════════════
  status = model%finalize()

  print *, "SCHISM simulation completed!"

end program run_schism_bmi
```

> ⚠️ **Note**: This Fortran driver requires the **LynkerIntel SCHISM_BMI** wrapper (`bmischism.f90`), which is NOT in our local repository. See [Section 13](#13--the-lynkerintel-schism_bmi-repository) for how to get it.

---

## 10. 🔄 How SCHISM's IRF Pattern Works (The Time Loop)

SCHISM **already** has an Initialize-Run-Finalize (IRF) pattern built in. This is why adding BMI to SCHISM was relatively easy compared to WRF-Hydro.

### 📊 The Driver Program Flow

Here's the actual code from `schism_driver.F90` (simplified):

```
┌──────────────────────────────────────────────────────────────┐
│  program schism_driver                                        │
│                                                               │
│    1. Parse command line arguments (number of scribe processes)│
│    2. Initialize MPI (parallel_init)                          │
│    3. Call schism_main()                                      │
│    4. Finalize MPI (parallel_finalize)                        │
│                                                               │
└──────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│  subroutine schism_main()                                     │
│                                                               │
│    ┌──────────────────────────────────────┐                   │
│    │  INITIALIZE                          │                   │
│    │  call schism_init0(iths, ntime)      │ ← BMI initialize()│
│    │    ├─ compute: schism_init()          │                   │
│    │    └─ scribe:  scribe_init()          │                   │
│    └──────────────────────────────────────┘                   │
│                    │                                          │
│                    ▼                                          │
│    ┌──────────────────────────────────────┐                   │
│    │  TIME LOOP                           │                   │
│    │  do it = iths+1, ntime               │ ← BMI controls   │
│    │    call schism_step0(it)             │ ← BMI update()    │
│    │      ├─ compute: schism_step(it)     │                   │
│    │      └─ scribe:  scribe_step(it)     │                   │
│    │  end do                              │    this loop      │
│    └──────────────────────────────────────┘                   │
│                    │                                          │
│                    ▼                                          │
│    ┌──────────────────────────────────────┐                   │
│    │  FINALIZE                            │                   │
│    │  call schism_finalize0()             │ ← BMI finalize()  │
│    │    ├─ compute: schism_finalize()     │                   │
│    │    └─ scribe:  scribe_finalize()     │                   │
│    └──────────────────────────────────────┘                   │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

### 🔑 Key Insight: `task_id` Separates Compute from I/O

```fortran
subroutine schism_init0(iths, ntime)
  use schism_msgp, only: task_id

  if (task_id == 1) then    ! This is a COMPUTE process
    call schism_init(0, './', iths, ntime)
  else                       ! This is an I/O SCRIBE process
    call scribe_init('./', iths, ntime)
  end if
end subroutine
```

📖 **What are scribes?**
- SCHISM can dedicate some MPI processes to **only handle file I/O** (reading/writing)
- Other processes do the **physics computation**
- This separation improves performance on large parallel runs
- For BMI/single-core testing, set scribes to 0 (all processes compute)

---

## 11. 📥 How Data Flows In/Out via BMI

### 🔵 Data IN: WRF-Hydro → SCHISM (River Discharge)

```
┌─────────────────┐     BMI get_value()      ┌──────────────────┐     BMI set_value()     ┌─────────────────┐
│    WRF-Hydro     │ ─────────────────────►   │   Coupling       │ ─────────────────────►  │     SCHISM       │
│                  │    "channel_water__       │   Framework      │    "Q_bnd"              │                  │
│  QLINK(:,2)     │     volume_flow_rate"     │   (PyMT)         │    discharge array      │  ath3(:,1,2,1)   │
│  RT_DOMAIN(1)   │    → 1D array of flow     │                  │    → fills source       │  source elements │
│                  │      rates in m³/s        │                  │      elements           │                  │
└─────────────────┘                           └──────────────────┘                         └─────────────────┘
```

#### The `ath3` Array — SCHISM's Source/Sink Storage

```fortran
! Declared in schism_glbl.F90 (line 386):
real(4), save, allocatable :: ath3(:,:,:,:)

! Dimensions:
! ath3(nsources, ntracers, 2, 3)
!       │         │        │  │
!       │         │        │  └─ File type: 1=volume source, 2=volume sink, 3=mass source
!       │         │        └──── Time level: 1=current, 2=next (for interpolation)
!       │         └───────────── Tracer index: 1=volume, 2+=concentrations
!       └─────────────────────── Source element index (which river mouth)
```

**Example**: To set the discharge at source element #5 to 250 m³/s:
```fortran
ath3(5, 1, 2, 1) = 250.0   ! 250 m³/s at source 5, next time level, volume source
```

### 🔴 Data OUT: SCHISM → WRF-Hydro (Water Elevation)

```fortran
! Water elevation at all nodes:
real(rkind), save, allocatable :: eta2(:)  ! Declared in schism_glbl.F90

! Access: eta2(node_index) gives water level in meters at that mesh node
```

> ⚠️ **Current limitation**: The `#ifdef USE_NWM_BMI` blocks in our SCHISM source code only handle **data IN** (receiving discharge). They do **NOT** export water elevation back. For 2-way coupling, additional code would be needed.

---

## 12. 📊 SCHISM BMI Variables (What Gets Exposed)

The LynkerIntel SCHISM BMI wrapper exposes **12 variables**:

### 📥 Input Variables (8) — Data Flowing INTO SCHISM

| Variable Name | Description | Units | Source |
|---------------|-------------|-------|--------|
| `ETA2_bnd` | Water level at open boundaries | m | Tidal/surge data |
| `Q_bnd` | ⭐ **Discharge at source elements** | m³/s | WRF-Hydro QLINK |
| `RAINRATE` | Precipitation rate | kg/m²/s | Atmospheric forcing |
| `SFCPRS` | Surface atmospheric pressure | Pa | Atmospheric forcing |
| `SPFH2m` | 2-meter specific humidity | kg/kg | Atmospheric forcing |
| `TMP2m` | 2-meter air temperature | K | Atmospheric forcing |
| `UU10m` | 10-meter U-wind component | m/s | Atmospheric forcing |
| `VV10m` | 10-meter V-wind component | m/s | Atmospheric forcing |

### 📤 Output Variables (4) — Data Flowing OUT OF SCHISM

| Variable Name | Description | Units | Used By |
|---------------|-------------|-------|---------|
| `ETA2` | ⭐ **Sea surface elevation** | m | WRF-Hydro (for 2-way coupling) |
| `VX` | X-component of velocity | m/s | Analysis / other models |
| `VY` | Y-component of velocity | m/s | Analysis / other models |
| `BEDLEVEL` | Bed level (bathymetry) | m | Static grid info |

### 🔗 The Coupling Variable Pair

For WRF-Hydro ↔ SCHISM coupling, the key variables are:

| Direction | WRF-Hydro Variable | CSDMS Standard Name | SCHISM Variable |
|-----------|--------------------|--------------------|-----------------|
| WRF-Hydro → SCHISM | `QLINK(:,2)` | `channel_water__volume_flow_rate` | `Q_bnd` → `ath3` |
| SCHISM → WRF-Hydro | (to be defined) | `sea_water_surface__elevation` | `ETA2` |

---

## 13. 🔗 The LynkerIntel SCHISM_BMI Repository

### 📦 What Is It?

The **full BMI wrapper** for SCHISM lives in a separate GitHub repository maintained by **LynkerIntel** (NOAA contractors):

🔗 **URL**: https://github.com/LynkerIntel/SCHISM_BMI

### 📁 Repository Structure

```
SCHISM_BMI/
├── 📁 SCHISM_BMI/              ← The BMI wrapper code
│   ├── bmischism.f90           ← ⭐ Full 41-function BMI module
│   ├── schism_BMI_driver_test.f90 ← Test driver program
│   ├── CMakeLists.txt          ← Build system for wrapper
│   ├── 📁 SCHISM_LIB_NWM_BMI/ ← Pre-compiled SCHISM libraries
│   │   ├── lib/                ← .a static libraries
│   │   └── include/            ← .mod Fortran module files
│   ├── iso_c_fortran_bmi.tar.gz ← C bindings middleware
│   ├── ParMetis-4.0.3.tar.gz   ← Graph partitioning library
│   └── metis-5.1.0.tar.gz      ← Mesh partitioning library
└── 📄 README.md
```

### 🔧 How to Build the BMI Wrapper

```bash
# 1. Clone the repository
git clone https://github.com/LynkerIntel/SCHISM_BMI.git
cd SCHISM_BMI/SCHISM_BMI

# 2. Extract dependencies
tar -xvf ParMetis-4.0.3.tar.gz
tar -xvf iso_c_fortran_bmi.tar.gz
tar -xvf metis-5.1.0.tar.gz

# 3. Copy your compiled SCHISM libraries here
# (from Step 7 of Section 7)
cp -r /path/to/schism_build/lib/ SCHISM_LIB_NWM_BMI/
cp -r /path/to/schism_build/include/ SCHISM_LIB_NWM_BMI/

# 4. Build the BMI wrapper and test driver
mkdir build && cd build
cmake ../
cmake --build . --target schism_driver

# 5. The output is a test driver executable
ls schism_driver
```

### 🏃 How to Run the BMI Test Driver

```bash
# Copy the driver to your model setup directory
cp schism_driver /path/to/model_setup/
cp namelist.input /path/to/model_setup/

# Run on single thread (serial mode for initial testing)
cd /path/to/model_setup/
mpirun -np 1 ./schism_driver namelist.input
```

> 💡 **Important**: Initial SCHISM BMI development is **serial-only** (single thread). This matches our approach for WRF-Hydro BMI — get it working on 1 core first, add parallelism later.

### 📄 Build Documentation

Detailed build instructions are on the LynkerIntel wiki:
🔗 https://github.com/LynkerIntel/SCHISM_BMI/wiki/SCHISM-BMI-Documentation-and-Build

---

## 14. 🏛️ NOAA NextGen Framework Integration

### 🤔 What is NextGen?

**NextGen** = NOAA's **Next Generation Water Resources Modeling Framework**

It's a **new modular framework** being developed by NOAA's Office of Water Prediction (OWP) to replace the current National Water Model (NWM). Key features:

- Models are **pluggable** — swap in any BMI-compliant model
- Supports **multiple languages** — C, C++, Fortran, Python via BMI
- **Catchment-based** — divides the landscape into hydrologic units
- Uses **BMI** as the standard interface for all models

🔗 **Repository**: https://github.com/NOAA-OWP/ngen

### 🔌 How SCHISM Connects to NextGen

NextGen supports Fortran BMI models through ISO_C_BINDING middleware:

```
┌──────────────────┐     ┌────────────────────┐     ┌──────────────┐
│  NextGen (C++)    │────►│ ISO_C_BINDING      │────►│ bmischism.f90│
│  Framework        │     │ middleware          │     │ (Fortran BMI)│
│                  │     │ register_bmi()      │     │              │
│  Loads .so file  │     │ C ↔ Fortran bridge  │     │ Calls SCHISM │
└──────────────────┘     └────────────────────┘     └──────────────┘
```

#### The `register_bmi` Function

For NextGen to load a Fortran BMI model, you need this special registration function:

```fortran
function register_bmi(this) result(bmi_status) bind(C, name="register_bmi")
  use, intrinsic :: iso_c_binding, only: c_ptr, c_loc, c_int
  use bmischism  ! Import the SCHISM BMI module
  implicit none

  type(c_ptr) :: this           ! C-compatible pointer
  integer(kind=c_int) :: bmi_status

  ! Create a SCHISM BMI instance that persists
  type(bmi_schism), target, save :: bmi_model
  type(box), pointer :: bmi_box

  allocate(bmi_box)
  bmi_box%ptr => bmi_model      ! Point to the model instance
  this = c_loc(bmi_box)         ! Return C-compatible pointer
  bmi_status = BMI_SUCCESS
end function register_bmi
```

#### NextGen Configuration File

```json
{
  "model_type_name": "bmi_fortran",
  "library_file": "/path/to/libschism_bmi.so",
  "init_config": "/path/to/namelist.input",
  "main_output_variable": "ETA2",
  "uses_forcing_file": false
}
```

### 📊 SCHISM BMI in NextGen — Current Status

From GitHub issue [NOAA-OWP/ngen#547](https://github.com/NOAA-OWP/ngen/issues/547):

| Task | Status |
|------|--------|
| Define coastal realization config structure | 🔶 In Progress |
| Implement BMI coastal formulation for ngen | 🔶 In Progress |
| Check multi-instance MPI constraints | 🔶 In Progress |
| Map nexus IDs to variable array indices | 🔶 In Progress |
| Lake Champlain test case | ✅ Created |
| 12 BMI variables defined (8 input, 4 output) | ✅ Done |

---

## 15. 🐍 Python BMI / PyMT Status

### Current Status: No `pymt_schism` Exists Yet

As of February 2026, SCHISM has **NOT** been babelized into a PyMT plugin. There is no `pymt_schism` Python package.

| Pathway | Status | Notes |
|---------|--------|-------|
| **Fortran BMI** (`bmischism.f90`) | ✅ Exists | In LynkerIntel/SCHISM_BMI repo |
| **NextGen Integration** | 🔶 In Progress | Active development by NOAA-OWP |
| **Babelizer** (Fortran → Python) | ❌ Not Done | Could be done using `babelizer` tool |
| **PyMT Plugin** (`pymt_schism`) | ❌ Not Done | Requires babelizing first |

### 🔮 What Would Be Needed for PyMT

To create a `pymt_schism` package:

1. **Get the Fortran BMI shared library** (`libschism_bmi.so`)
2. **Write a `babel.toml`** configuration:
   ```toml
   [library]
   language = "fortran"
   entry_point = "bmischism"

   [package]
   name = "pymt_schism"
   requirements = ["netcdf-fortran", "openmpi"]
   ```
3. **Run babelizer**: `babelize init babel.toml`
4. **Build and install**: `pip install ./pymt_schism`
5. **Use from Python**:
   ```python
   from pymt.MODELS import Schism
   model = Schism()
   model.initialize("namelist.input")
   model.update()
   eta = model.get_value("ETA2")
   ```

> 💡 This is exactly what we plan to do for WRF-Hydro in **Phase 2** of our project. Once both `pymt_wrfhydro` and `pymt_schism` exist, coupling becomes ~20 lines of Python!

---

## 16. ❓ Frequently Asked Questions

### Q: Can I run SCHISM with BMI right now?

**Yes, but with caveats:**
- ✅ You can compile SCHISM with `USE_NWM_BMI=ON` using our local source code
- ✅ It will run standalone, reading source/sink data from files
- ⚠️ For actual BMI control (external caller), you need the LynkerIntel wrapper (`bmischism.f90`) from their GitHub repo
- ⚠️ You need a proper SCHISM test case (mesh, boundary conditions, etc.)

### Q: Do I need to modify SCHISM's source code?

**No!** The BMI integration is done through:
1. A **preprocessor flag** (`-DUSE_NWM_BMI=ON`) that activates existing `#ifdef` blocks
2. A **separate wrapper module** (`bmischism.f90`) that calls SCHISM's existing subroutines

Zero lines of SCHISM's physics code are changed.

### Q: What's the difference between `#ifdef` blocks and the BMI wrapper?

| `#ifdef USE_NWM_BMI` | `bmischism.f90` (LynkerIntel) |
|-----------------------|-------------------------------|
| Inside SCHISM's source code | Separate file |
| Only modifies source/sink data handling | Implements all 41 BMI functions |
| 5 small code blocks in 3 files | Complete BMI module (~800+ lines) |
| No standard BMI interface | Extends abstract `bmi` type from `bmif_2_0` |
| Used for conditional compilation | Used for actual BMI coupling |

**Both are needed together**: The `#ifdef` blocks prepare SCHISM's internals for BMI-mode operation, and `bmischism.f90` provides the standard interface that external callers use.

### Q: Can SCHISM BMI do 2-way coupling?

**Partially:**
- ✅ **1-way** (WRF-Hydro → SCHISM): Fully supported — SCHISM receives discharge via `ath3` array / `Q_bnd` BMI variable
- ⚠️ **2-way** (SCHISM → WRF-Hydro): `ETA2` is exposed as an output variable, but WRF-Hydro doesn't have BMI yet to receive it. This is what our project is building!

### Q: Is MPI required?

**Yes.** SCHISM is fundamentally an MPI-parallel model. Even for single-core runs, you need MPI installed and must use `mpirun -np 1`. There is no serial-only mode.

### Q: Where do I get a SCHISM test case?

SCHISM test cases require specialized mesh files (`hgrid.gr3`) and boundary conditions. Options:
- Check SCHISM's official documentation: https://schism-dev.github.io/schism
- The `sample_inputs/` directory in the SCHISM repo has parameter templates
- NOAA's STOFS test cases (may require access)
- Create a simple rectangular domain for testing

---

## 17. 📚 References and Resources

### 🔗 Key Repositories

| Repository | URL | What It Has |
|------------|-----|-------------|
| **SCHISM Main** | https://github.com/schism-dev/schism | Official SCHISM source code |
| **SCHISM NWM BMI** | https://github.com/schism-dev/schism_NWM_BMI | SCHISM fork with USE_NWM_BMI flag |
| **LynkerIntel SCHISM_BMI** | https://github.com/LynkerIntel/SCHISM_BMI | ⭐ Full BMI wrapper + build guide |
| **Jason Ducker BMI Branch** | https://github.com/jduckerOWP/schism_NWM_BMI/tree/BMI_Branch | Active development branch |
| **NOAA NextGen (ngen)** | https://github.com/NOAA-OWP/ngen | NextGen framework |
| **ngen Issue #547** | https://github.com/NOAA-OWP/ngen/issues/547 | SCHISM BMI evaluation for NextGen |

### 📖 Documentation

| Resource | URL |
|----------|-----|
| **SCHISM Online Docs** | https://schism-dev.github.io/schism |
| **SCHISM Compilation Guide** | https://schism-dev.github.io/schism/master/getting-started/compilation.html |
| **SCHISM Code Structure** | https://schism-dev.github.io/schism/master/code-contribution.html |
| **LynkerIntel BMI Build Wiki** | https://github.com/LynkerIntel/SCHISM_BMI/wiki/SCHISM-BMI-Documentation-and-Build |
| **BMI Specification** | https://bmi.readthedocs.io |
| **CSDMS BMI Wiki** | https://csdms.colorado.edu/wiki/BMI |
| **NOAA Inland-Coastal Coupling** | https://coastaloceanmodels.noaa.gov/coupling/02_inland_coastal_coupling.html |

### 📄 Research Papers

| Paper | Link |
|-------|------|
| Two-Way NWM-SCHISM Coupling (2024) | https://www.mdpi.com/2306-5338/11/9/145 |
| Compound Flooding — Hurricane (2020) | https://link.springer.com/article/10.1007/s10236-020-01351-x |
| Cross-scale Compound Flooding (2021) | https://nhess.copernicus.org/articles/21/1703/2021/ |
| Forecasting Compound Floods (2023) | https://eos.org/science-updates/forecasting-compound-floods-in-complex-coastal-regions |
| NWM v3 Service Change Notice (PDF) | https://www.weather.gov/media/notification/pdf_2023_24/scn23-76_national_water_model_v3.0_aab.pdf |

### 🎓 Training Resources

| Resource | URL |
|----------|-----|
| CIROH BMI Workshop 2024 | https://ciroh.ua.edu/devconference/nextgen-workshops/bmi-workshop-2024/ |
| CIROH BMI Basics for NextGen 2025 | https://ciroh.ua.edu/devconference/2025-ciroh-developers-conference/community-nextgen/bmi-basics-for-nextgen-in-a-box-ngiab/ |
| LynkerIntel BMI Tutorial | https://github.com/LynkerIntel/bmi-tutorial |
| Babelizer Docs | https://babelizer.readthedocs.io |
| PyMT Docs | https://github.com/csdms/pymt |

---

## 📝 Summary

```
┌──────────────────────────────────────────────────────────────────────┐
│                    SCHISM BMI — Key Takeaways                         │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. SCHISM has TWO BMI layers:                                       │
│     • #ifdef USE_NWM_BMI blocks (in our local code, 5 blocks)        │
│     • Full bmischism.f90 wrapper (in LynkerIntel GitHub repo)        │
│                                                                      │
│  2. To compile with BMI:                                             │
│     cmake .. -DUSE_NWM_BMI=ON                                       │
│     make -j$(nproc) pschism                                          │
│                                                                      │
│  3. Critical config: if_source must NOT be 0 in param.nml            │
│                                                                      │
│  4. Data flows through ath3 array (source/sink):                     │
│     WRF-Hydro QLINK → BMI → SCHISM ath3 → ocean physics             │
│                                                                      │
│  5. 12 BMI variables: 8 input + 4 output                            │
│                                                                      │
│  6. Serial-first approach (single core) — same as our WRF-Hydro plan│
│                                                                      │
│  7. No pymt_schism yet — our project could be the first to           │
│     create a full PyMT-coupled hydro-coastal system!                 │
│                                                                      │
│  8. NextGen integration is in progress at NOAA-OWP                   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

> 📧 **Questions?** Contact Mohan (mohansai) for WRF-Hydro BMI questions, or check the LynkerIntel wiki for SCHISM BMI build issues.
>
> 📅 **Last Updated**: February 20, 2026
