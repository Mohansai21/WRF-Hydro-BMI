# 🌊 WRF-Hydro Model — Complete Deep Dive

> **Document 14** | WRF-Hydro BMI Wrapper Project
>
> 📅 Created: February 2026
>
> 🎯 **Purpose**: Everything you need to know about WRF-Hydro — the model itself, its physics, equations, grids, variables, architecture, NOAA operations, and how it all connects to our BMI wrapper project.

---

## 📑 Table of Contents

### Part I: WRF-Hydro — The Model
| # | Section | Description |
|---|---------|-------------|
| 1 | [What is WRF-Hydro?](#1--what-is-wrf-hydro) | Origin, purpose, the big picture |
| 2 | [History & Development](#2--history--development) | Timeline from 2003 to v5.4.0 |
| 3 | [Physics Components Overview](#3--physics-components-overview) | The 5 physics engines inside |
| 4 | [Noah-MP Land Surface Model](#4--noah-mp-land-surface-model) | Soil, snow, vegetation, energy balance |
| 5 | [Terrain Routing — Overland Flow](#5--terrain-routing--overland-flow) | Water flowing across the land surface |
| 6 | [Terrain Routing — Subsurface Flow](#6--terrain-routing--subsurface-flow) | Water moving underground laterally |
| 7 | [Channel Routing](#7--channel-routing) | Streamflow through rivers |
| 8 | [Groundwater & Baseflow](#8--groundwater--baseflow) | The bucket model |
| 9 | [Lake & Reservoir Routing](#9--lake--reservoir-routing) | Level-pool routing |
| 10 | [Governing Equations](#10--governing-equations) | All the math behind the physics |
| 11 | [Multi-Resolution Grid System](#11--multi-resolution-grid-system) | 1km, 250m, and channel network |
| 12 | [Time Stepping & Subcycling](#12--time-stepping--subcycling) | How time advances in WRF-Hydro |
| 13 | [Comparison with Other Models](#13--comparison-with-other-models) | vs VIC, SWAT, HEC-HMS, MIKE-SHE |
| 14 | [NOAA National Water Model](#14--noaa-national-water-model) | WRF-Hydro powering national forecasts |

### Part II: WRF-Hydro — Architecture & Internals
| # | Section | Description |
|---|---------|-------------|
| 15 | [Source Code Architecture](#15--source-code-architecture) | Directory tree, 235 files, modules |
| 16 | [Main Program & Time Loop](#16--main-program--time-loop) | The 43-line entry point |
| 17 | [Key Subroutines (IRF Pattern)](#17--key-subroutines-irf-pattern) | init/run/finalize decomposition |
| 18 | [RT_FIELD — The Master State Type](#18--rt_field--the-master-state-type) | 2000+ variables in one structure |
| 19 | [Input Data Requirements](#19--input-data-requirements) | Domain files, forcing, restarts, tables |
| 20 | [Output Data & File Types](#20--output-data--file-types) | LDASOUT, CHRTOUT, RTOUT, etc. |
| 21 | [All Key Variables — Detailed Tables](#21--all-key-variables--detailed-tables) | 80+ variables across all components |
| 22 | [Configuration — Namelists](#22--configuration--namelists) | namelist.hrldas + hydro.namelist |
| 23 | [Build System & Dependencies](#23--build-system--dependencies) | CMake, compilers, libraries |
| 24 | [MPI Parallelization](#24--mpi-parallelization) | Domain decomposition, halos |
| 25 | [Coupling Capabilities](#25--coupling-capabilities) | WRF, SCHISM, NUOPC, NextGen |
| 26 | [Repository & Resources](#26--repository--resources) | All links, papers, tools |
| 27 | [Summary & Key Numbers](#27--summary--key-numbers) | Quick reference |

---

# Part I: WRF-Hydro — The Model

---

## 1. 🌍 What is WRF-Hydro?

### 🔹 The One-Liner
**WRF-Hydro** (Weather Research and Forecasting Model — Hydrological Extension) is a **physically-based, distributed hydrological modeling system** that simulates how water moves across and through landscapes — from rainfall to river discharge.

### 🔹 The ML Analogy

> **🤖 ML Analogy**: Think of WRF-Hydro as a **multi-stage inference pipeline**:
>
> | ML Pipeline Stage | WRF-Hydro Equivalent |
> |---|---|
> | Input preprocessing | Read forcing data (rain, temperature, wind) |
> | Feature extraction (Stage 1) | Noah-MP: compute soil moisture, snow, evaporation |
> | Feature extraction (Stage 2) | Overland routing: route surface water on 250m grid |
> | Feature extraction (Stage 3) | Subsurface routing: route underground water |
> | Main model inference | Channel routing: compute streamflow in rivers |
> | Post-processing | Write outputs (streamflow, soil moisture, snow) |
> | Checkpoint saving | Write restart files for next run |
>
> Just like a deep learning pipeline where each stage transforms data and passes it forward, WRF-Hydro processes water through multiple physics stages.

### 🔹 What Makes WRF-Hydro Special?

| Feature | Description |
|---------|-------------|
| 🌧️ **Atmosphere Coupling** | Can directly couple with WRF weather model (unique among hydro models) |
| 🗺️ **Multi-Resolution** | Runs physics at different resolutions (1km land + 250m routing + vector channels) |
| 🇺🇸 **National Operations** | Powers NOAA's National Water Model (2.7M river reaches, real-time forecasts) |
| 🔧 **Modular Physics** | Swap in/out different routing schemes, snow models, runoff options |
| 🖥️ **HPC Ready** | Full MPI parallelization for supercomputers |
| 📂 **Open Source** | Publicly available on GitHub |

### 🔹 The Water Cycle in WRF-Hydro

```
                    ☁️ ATMOSPHERE
                    │
          ┌─────────┼─────────┐
          │    Rain/Snow ↓    │
          │                   │
    ┌─────▼─────────────────────────┐
    │  🌱 NOAH-MP LAND SURFACE (1km) │
    │  ├─ Canopy interception        │
    │  ├─ Snow accumulation/melt     │
    │  ├─ Evapotranspiration (ET)    │
    │  ├─ Infiltration               │
    │  └─ Surface + subsurface runoff│
    └─────┬────────────┬────────────┘
          │            │
    ┌─────▼────┐ ┌─────▼─────┐
    │🏔️ OVERLAND│ │💧SUBSURFACE│
    │  (250m)  │ │  (250m)   │
    │ Surface  │ │Underground│
    │  water   │ │  lateral  │
    │  flow    │ │   flow    │
    └─────┬────┘ └─────┬─────┘
          │            │
          └──────┬─────┘
                 │
    ┌────────────▼────────────┐
    │  🏞️ CHANNEL ROUTING      │
    │  Rivers, streams, creeks │
    │  (Muskingum-Cunge or    │
    │   Diffusive Wave)       │
    └────────────┬────────────┘
                 │
          ┌──────┼──────┐
          │      │      │
    ┌─────▼──┐ ┌─▼────┐ ┌▼──────┐
    │🏗️ LAKES│ │🌊 GW │ │📊 OUT │
    │Reserv. │ │Bucket│ │Stream-│
    │Level   │ │Base- │ │flow   │
    │Pool    │ │flow  │ │Data   │
    └────────┘ └──────┘ └───────┘
```

---

## 2. 📜 History & Development

### 🔹 Who Built It?
- **Institution**: NCAR (National Center for Atmospheric Research), Research Applications Laboratory (RAL)
- **Lead Developer**: Dr. David Gochis (gochis@ucar.edu)
- **Manager**: UCAR (University Corporation for Atmospheric Research)
- **Funding**: NOAA, NASA, NSF
- **Collaborators**: CUAHSI, USGS, USACE, FEMA, Israel Hydrologic Service

> **🤖 ML Analogy**: NCAR building WRF-Hydro is like Google DeepMind building AlphaFold — a government-funded research lab creating a flagship model that becomes the operational standard for an entire field.

### 🔹 Timeline

```
2003 ──── "Noah-distributed" born at NCAR (3D variably-saturated model)
  │
2004 ──── Coupled to WRF atmospheric model (land-atmosphere feedback)
  │
2011 ──── Major restructuring for extensibility
  │
2014 ──── Noah-MP integration (replacing older Noah LSM)
  │
2016 ──── 🎉 NOAA National Water Model v1.0 goes OPERATIONAL
  │         (First-ever continental-scale real-time streamflow forecast)
  │
2018 ──── Code moved to public GitHub, v5.0 architecture
  │
2020 ──── NWM v2.0 (WRF-Hydro v5.1.1), 107-page tech description
  │
2021 ──── NWM v2.1 (WRF-Hydro v5.2.0)
  │
2022 ──── NWM v3.0 prep (WRF-Hydro v5.3.0) — Alaska, Crocus snow
  │
2023 ──── 🎉 NWM v3.0 operational — Alaska domain, coastal coupling
  │
2025 ──── WRF-Hydro v5.4.0 (NWM v3.1) — CMake build, gage diversions
  │
  ▼
TODAY ─── Our project: Building BMI wrapper for v5.4.0
```

### 🔹 Version History Table

| Version | Year | NWM Version | Key Changes |
|---------|------|-------------|-------------|
| v1.0-v4.x | 2003-2017 | Pre-NWM / NWM v1.0 | Initial development, WRF coupling |
| **v5.0** | 2018 | — | Major architecture rewrite, GitHub release |
| **v5.0.1-3** | 2020 | — | Bug fixes |
| **v5.1.1** | 2020 | NWM v2.0 | 107-page technical description |
| **v5.2.0** | 2021 | NWM v2.1 | 108-page technical description |
| **v5.3.0** | 2022 | NWM v3.0 | Impervious runoff, Crocus snowpack, spatial params |
| **v5.4.0** | 2025 | NWM v3.1 | CMake preferred, gage-assisted diversions |

### 🔹 Publications & Impact

| Metric | Value |
|--------|-------|
| 📄 Total publications | 232 |
| 📈 Total citations | 2,926 |
| 📊 h-index | 29 |
| 📖 Primary reference | Gochis et al. (2020), 107 pages |
| 🏆 Operational usage | NOAA NWM (since 2016) |

---

## 3. ⚙️ Physics Components Overview

WRF-Hydro has **5 major physics engines** that work together. Each one handles a different part of the water cycle.

> **🤖 ML Analogy**: Think of WRF-Hydro as an **ensemble model** where 5 specialized sub-models each handle a different task, and their outputs feed into each other — like a mixture-of-experts architecture.

### 🔹 The 5 Components at a Glance

| # | Component | Resolution | What It Computes | ML Analogy |
|---|-----------|-----------|-----------------|------------|
| 1 | 🌱 **Noah-MP LSM** | 1 km | Soil moisture, snow, ET, infiltration | Feature extractor (ResNet backbone) |
| 2 | 🏔️ **Overland Routing** | 250 m | Surface water flow across terrain | Convolution layer (spatial filtering) |
| 3 | 💧 **Subsurface Routing** | 250 m | Underground lateral water movement | Another conv layer (different kernel) |
| 4 | 🏞️ **Channel Routing** | Vector | Streamflow through river network | Graph neural network (message passing) |
| 5 | 🌊 **Groundwater Bucket** | Per basin | Baseflow to rivers | Simple linear layer |
| +  | 🏗️ **Lake/Reservoir** | Per lake | Water level, inflow/outflow | Lookup table with constraints |

### 🔹 Data Flow Between Components

```
    FORCING DATA (rain, temp, wind, radiation)
              │
              ▼
    ┌────────────────────┐
    │  🌱 NOAH-MP (1 km)  │──────► LDASOUT (soil, snow, ET)
    │  Energy + Water     │
    │  Balance per column │
    └────┬──────────┬─────┘
         │          │
    INFXS│     SOIL_M│
  (surface│   (soil  │
   runoff)│  moisture)│
         │          │
    ┌────▼──────────▼─────┐
    │  DISAGGREGATION      │  1km ──► 250m
    │  (weighted mapping)  │
    └────┬──────────┬──────┘
         │          │
    ┌────▼────┐ ┌───▼──────┐
    │🏔️OVERLAND│ │💧SUBSURFACE│
    │ Diffusive│ │ Lateral   │
    │ Wave     │ │ Flow      │
    │ (250m)   │ │ (250m)    │
    └────┬────┘ └───┬──────┘
         │          │
    ┌────▼──────────▼──────┐
    │  AGGREGATION          │  250m ──► channel
    │  (to channel reaches) │
    └──────────┬───────────┘
               │
    ┌──────────▼───────────┐
    │  🏞️ CHANNEL ROUTING   │──────► CHRTOUT (streamflow)
    │  Muskingum-Cunge or  │
    │  Diffusive Wave      │
    └────┬─────────┬───────┘
         │         │
    ┌────▼───┐ ┌───▼────┐
    │🏗️ LAKES│ │🌊 GW   │──────► GWOUT (baseflow)
    │Reserv. │ │Bucket  │
    │Level   │ │Model   │
    │Pool    │ │        │
    └────┬───┘ └───┬────┘
         │         │
         └────┬────┘
              │
    ┌─────────▼──────────┐
    │  📊 FINAL OUTPUT    │
    │  Streamflow (m³/s)  │──────► CHRTOUT, CHANOBS
    │  + all diagnostics  │
    └────────────────────┘
```

---

## 4. 🌱 Noah-MP Land Surface Model

### 🔹 What is Noah-MP?

**Noah-MP** (Noah Multi-Parameterization) is the **land surface model** inside WRF-Hydro. It computes what happens to water and energy at each 1km grid cell — like a "column model" that looks at one patch of ground at a time.

> **🤖 ML Analogy**: Noah-MP is like the **backbone/feature extractor** in a computer vision pipeline (e.g., ResNet). It processes each grid cell independently (like processing each pixel) to extract features (soil moisture, snow, runoff) that downstream modules use.

### 🔹 What Noah-MP Computes

```
         ☀️ Solar      ☁️ Longwave    🌧️ Rain/Snow    💨 Wind
          │              │              │              │
          ▼              ▼              ▼              ▼
    ┌─────────────────────────────────────────────────────┐
    │                🌳 CANOPY LAYER                       │
    │  ├─ Radiation interception (two-stream model)        │
    │  ├─ Rain/snow interception                           │
    │  ├─ Canopy evaporation (ECAN)                        │
    │  ├─ Transpiration (ETRAN) via Ball-Berry stomata     │
    │  └─ Canopy temperature (T_canopy)                    │
    └────────────────────┬────────────────────────────────┘
                         │
    ┌────────────────────▼────────────────────────────────┐
    │              ❄️ SNOW PACK (multi-layer)               │
    │  ├─ Up to 3 snow layers                              │
    │  ├─ Accumulation, compaction, melt, refreeze         │
    │  ├─ Liquid water storage within snowpack             │
    │  ├─ Snow water equivalent (SNEQV)                    │
    │  └─ Snow depth (SNOWH)                               │
    └────────────────────┬────────────────────────────────┘
                         │
    ┌────────────────────▼────────────────────────────────┐
    │              🟤 SOIL COLUMN (4 layers)                │
    │                                                      │
    │  Layer 1: 0.0 - 0.1 m  ─── Top soil                 │
    │  Layer 2: 0.1 - 0.4 m  ─── Root zone upper          │
    │  Layer 3: 0.4 - 1.0 m  ─── Root zone lower          │
    │  Layer 4: 1.0 - 2.0 m  ─── Deep soil                │
    │                                                      │
    │  Each layer tracks:                                  │
    │  ├─ SMC  = total soil moisture (m³/m³)               │
    │  ├─ SH2O = liquid soil moisture (m³/m³)              │
    │  ├─ STC  = soil temperature (K)                      │
    │  └─ SICE = frozen soil moisture (m³/m³)              │
    │                                                      │
    │  Processes:                                          │
    │  ├─ Richards equation (vertical water movement)      │
    │  ├─ Heat conduction (soil temperature)               │
    │  ├─ Freeze/thaw dynamics                             │
    │  ├─ Direct soil evaporation (EDIR)                   │
    │  └─ Infiltration / runoff generation                 │
    └────────────────────┬────────────────────────────────┘
                         │
              ┌──────────┼──────────┐
              │          │          │
         RUNOFF1    RUNOFF2    RUNOFF3
        (surface)  (subsurface) (drainage)
              │          │          │
              ▼          ▼          ▼
         To Overland  To Subsurface  To GW Bucket
         Routing      Routing        (baseflow)
```

### 🔹 Noah-MP Physics Options

Noah-MP is "Multi-Parameterization" because you can choose different physics schemes:

| Physics Category | Options | Default |
|-----------------|---------|---------|
| 🌿 Dynamic Vegetation | 1-10 (off, on, DVEG, table LAI, etc.) | 4 (table LAI) |
| 🌡️ Stomatal Resistance | 1-2 (Ball-Berry, Jarvis) | 1 (Ball-Berry) |
| 💧 Runoff & Groundwater | 1-8 (TOPMODEL, Schaake96, original, etc.) | 3 (original) |
| ☀️ Radiation Transfer | 1-3 (gap=F(zenith), no gap, two-stream) | 3 (two-stream) |
| ❄️ Snow Albedo | 1-2 (BATS, CLASS) | 2 (CLASS) |
| 🌊 Frozen Soil Permeability | 1-2 (linear, nonlinear) | 1 (linear) |
| 🏔️ Glacier | 1-2 (off, phase-change + Crocus) | 2 |

### 🔹 Key Noah-MP State Variables

| Variable | Name | Units | Description |
|----------|------|-------|-------------|
| `SMC` | Soil Moisture Content | m³/m³ | Total volumetric soil moisture (4 layers) |
| `SH2O` | Liquid Soil Moisture | m³/m³ | Liquid water content only (4 layers) |
| `STC` | Soil Temperature | K | Temperature of each soil layer (4 layers) |
| `SNEQV` | Snow Water Equivalent | kg/m² | Total water stored as snow |
| `SNOWH` | Snow Depth | m | Physical depth of snowpack |
| `CANLIQ` | Canopy Liquid | mm | Water intercepted on leaves |
| `CANICE` | Canopy Ice | mm | Ice intercepted on leaves |
| `LAI` | Leaf Area Index | m²/m² | Leaf area per ground area |
| `T2` | 2m Air Temperature | K | Near-surface air temperature |
| `TSK` | Skin Temperature | K | Land surface temperature |
| `ZWT` | Water Table Depth | m | Depth to water table |

### 🔹 Key Noah-MP Flux Variables

| Variable | Name | Units | Description |
|----------|------|-------|-------------|
| `RAINRATE` | Precipitation Rate | mm/s | Incoming rain + snowmelt |
| `ECAN` / `ACCECAN` | Canopy Evaporation | mm | Water evaporated from canopy |
| `ETRAN` / `ACCETRAN` | Transpiration | mm | Water pulled up by plant roots |
| `EDIR` / `ACCEDIR` | Direct Soil Evap | mm | Evaporation directly from soil |
| `ACCET` | Total ET | mm | ECAN + ETRAN + EDIR accumulated |
| `SFCRUNOFF` | Surface Runoff | mm | Accumulated surface runoff |
| `UDRUNOFF` | Subsurface Runoff | mm | Accumulated underground runoff |
| `HFX` | Sensible Heat Flux | W/m² | Heat warming the air |
| `LH` | Latent Heat Flux | W/m² | Heat used for evaporation |
| `GRDFLX` | Ground Heat Flux | W/m² | Heat going into the soil |
| `FSA` | Absorbed Shortwave | W/m² | Solar radiation absorbed |
| `FIRA` | Net Longwave | W/m² | Thermal radiation emitted |
| `RUNOFF1` | Surface Runoff | mm/step | This-timestep surface runoff → overland |
| `RUNOFF2` | Subsurface Runoff | mm/step | This-timestep subsurface runoff → subsurface |
| `RUNOFF3` | Drainage | mm/step | This-timestep deep drainage → GW bucket |

---

## 5. 🏔️ Terrain Routing — Overland Flow

### 🔹 What is Overland Flow?

After Noah-MP computes how much water can't infiltrate the soil (infiltration excess = `INFXS`), that water sits on the land surface. **Overland routing** moves this water across the terrain following topographic slopes — like water flowing downhill after a rainstorm.

> **🤖 ML Analogy**: Overland routing is like a **2D convolution** operation on the terrain grid. Each cell's water depth is updated based on its neighbors' water depths and terrain slopes — exactly like how a conv kernel computes output from neighboring pixels.

### 🔹 How It Works

```
    250m Routing Grid (Fine Resolution)
    ┌───┬───┬───┬───┬───┬───┐
    │ ↘ │ ↓ │ ↓ │ ↓ │ ↙ │   │  ← Each cell has:
    ├───┼───┼───┼───┼───┼───┤     - Water depth (h)
    │ → │ ↘ │ ↓ │ ↙ │ ← │   │     - Terrain elevation
    ├───┼───┼───┼───┼───┼───┤     - Manning's roughness (n)
    │ → │ → │ 🔵│ ← │ ← │   │     - Flow direction (D8)
    ├───┼───┼───┼───┼───┼───┤
    │ → │ ↗ │ ↑ │ ↖ │ ← │   │  Water flows from high
    ├───┼───┼───┼───┼───┼───┤  to low elevation cells
    │ ↗ │ ↑ │ ↑ │ ↑ │ ↖ │   │
    └───┴───┴───┴───┴───┴───┘
              │
              ▼
         🏞️ Channel
         (stream)
```

### 🔹 Two Routing Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **2D (x+y)** | Water flows in both x and y directions | Research, high-fidelity |
| **1D (D8 steepest descent)** | Water flows only toward steepest downhill neighbor | Faster, NWM operational |

### 🔹 Physics: Diffusive Wave

The overland flow uses the **diffusive wave** approximation of the shallow water equations:

1. **Continuity**: `∂h/∂t + ∂qx/∂x + ∂qy/∂y = ie` (water balance)
2. **Momentum**: `Sfx = Sox - ∂h/∂x` (friction slope = terrain slope - pressure gradient)
3. **Manning's equation**: `qx = (√Sfx / n) × h^(5/3)` (flow rate from depth)

Where:
- `h` = surface water depth (m)
- `qx, qy` = discharge per unit width in x, y (m²/s)
- `ie` = infiltration excess rate (m/s) — what Noah-MP couldn't infiltrate
- `Sox` = terrain slope (from DEM)
- `n` = Manning's roughness coefficient (dimensionless)

---

## 6. 💧 Terrain Routing — Subsurface Flow

### 🔹 What is Subsurface Lateral Flow?

Water that infiltrates the soil doesn't just sit there — it moves **laterally underground** following the water table slope. This is especially important in mountainous areas where steep terrain drives significant subsurface flow.

> **🤖 ML Analogy**: If overland flow is a surface-level convolution, subsurface flow is like a **deeper convolution layer** operating on hidden features (underground water) rather than visible surface data.

### 🔹 Physics: Dupuit-Forchheimer Approximation

Based on DHSVM (Wigmosta et al. 1994):

```
    Ground Surface
    ═══════════════════════════
           ╲  Unsaturated  ╱
            ╲    Zone     ╱
    ─ ─ ─ ─ ╲─ ─ ─ ─ ─╱─ ─ ─ ─  Water Table
              ╲ Saturated ╱
               ╲  Zone   ╱
    ▓▓▓▓▓▓▓▓▓▓▓╲▓▓▓▓▓▓╱▓▓▓▓▓▓▓  Bedrock

    Flow direction: follows water table slope →
    Flow rate: q = -T × β × w

    Where:
    T = transmissivity (depends on saturated depth)
    β = water table slope (negative = downhill)
    w = cell width
```

### 🔹 Key Equations

**Transmissivity** (how easily water moves through soil):
```
T = (Ksat × D / n) × (1 - z/D)^n    when z ≤ D
T = 0                                  when z > D (dry)
```

**Water table update**:
```
Δz = (1/φ) × [Qnet/A - R] × Δt
```

Where: `Ksat` = saturated hydraulic conductivity, `D` = soil depth, `z` = water table depth, `φ` = porosity, `R` = recharge rate

### 🔹 Exfiltration

When the water table rises to the surface (supersaturation), excess water **exfiltrates** — pops back out of the ground and adds to surface runoff. This is a key feedback mechanism between subsurface and overland routing.

---

## 7. 🏞️ Channel Routing

### 🔹 What is Channel Routing?

Once water reaches a stream or river channel, it must be routed downstream through the channel network. This is the most important output for flood forecasting — **streamflow** (discharge in m³/s).

> **🤖 ML Analogy**: Channel routing is remarkably similar to a **Graph Neural Network (GNN)**. The river network is a directed acyclic graph where each node (river reach) receives messages (lateral inflow) from its neighbors and its own state (water volume), processes them, and passes the result (discharge) downstream. The Muskingum-Cunge method is essentially a **message-passing** operation.

### 🔹 Two Channel Routing Methods

| Method | Description | Used In |
|--------|-------------|---------|
| **Muskingum-Cunge** | Simplified wave routing with time-varying parameters | NWM operational, reach-based |
| **Diffusive Wave** | Full hydraulic routing with Newton-Raphson solver | Research, gridded channels |

### 🔹 Muskingum-Cunge Routing (NWM Method)

```
    Reach i (upstream)          Reach i+1 (downstream)
    ┌──────────────┐            ┌──────────────┐
    │  Qup (inflow)│──────────►│  Qdown        │
    │              │   route    │  (outflow)    │
    │  + qlateral  │            │  + qlateral   │
    │  (from       │            │  (from        │
    │   overland + │            │   overland +  │
    │   baseflow)  │            │   baseflow)   │
    └──────────────┘            └──────────────┘

    Routing equation:
    Qd(t+1) = C1×Qu(t) + C2×Qu(t+1) + C3×Qd(t) + qlat×Δt/D

    Where:
    C1, C2, C3 = routing coefficients (sum to 1.0)
    K = travel time through reach = Δx / ck
    X = weighting factor (0 to 0.5)
    ck = wave celerity (speed of flood wave)
```

### 🔹 Channel Cross-Section

```
              Water Surface
         ─────────────────────
        ╱    Tw (top width)    ╲
       ╱                        ╲
      ╱ ChSSlp                   ╲ ChSSlp
     ╱ (side slope)    h          ╲ (side slope)
    ╱                (depth)       ╲
    ══════════════════════════════════
         Bw (bottom width)

    Cross-section area: A = h × (Bw + ChSSlp × h)
    Wetted perimeter:   P = Bw + 2h × √(1 + ChSSlp²)
    Hydraulic radius:   R = A / P
    Manning's discharge: Q = (1/n) × A × R^(2/3) × √So
```

### 🔹 Key Channel Parameters (from Route_Link.nc)

| Parameter | Description | Units |
|-----------|-------------|-------|
| `BtmWdth` | Channel bottom width | m |
| `ChSlp` | Channel side slope | m/m |
| `n` / `MannN` | Manning's roughness coefficient | — |
| `Length` | Reach length | m |
| `So` | Channel bed slope | m/m |
| `MusK` | Muskingum K parameter | s |
| `MusX` | Muskingum X parameter | — |
| `order` | Strahler stream order | — |
| `NHDWaterbodyComID` | Lake/reservoir ID (if applicable) | — |

---

## 8. 🌊 Groundwater & Baseflow

### 🔹 What is the Bucket Model?

WRF-Hydro uses a simple **conceptual bucket** to represent groundwater storage and baseflow. Each sub-basin has one "bucket" that fills with deep drainage from Noah-MP and slowly releases water back to streams as baseflow.

> **🤖 ML Analogy**: The bucket model is like a **simple linear layer with an exponential activation function**. Input (drainage) fills a bucket, and output (baseflow) is an exponential function of the fill level — `Q = C × (e^(E×z/zmax) - 1)`.

### 🔹 How It Works

```
    Noah-MP Deep Drainage (RUNOFF3)
              │
              ▼
    ┌─────────────────────┐
    │   🪣 GROUNDWATER     │
    │      BUCKET          │
    │                      │
    │   z ─── current      │  Water level update:
    │         depth (mm)   │  z = z_prev + (Qin × Δt) / Area
    │                      │
    │   zmax ── maximum    │  Baseflow (exponential):
    │           depth (mm) │  Q = C × (e^(E×z/zmax) - 1)
    │                      │
    │   C ── coefficient   │  If z > zmax:
    │   E ── exponent      │  Qspill = overflow → channel
    │                      │
    └─────────┬───────────┘
              │
         Baseflow (Q)
              │
              ▼
         🏞️ Channel Network
```

### 🔹 Bucket Parameters (from GWBUCKPARM.nc)

| Parameter | Description | Units |
|-----------|-------------|-------|
| `Coeff` (C) | Discharge coefficient | m³/s |
| `Expon` (E) | Exponential exponent | — |
| `Zmax` | Maximum bucket depth | mm |
| `Zinit` | Initial water level | mm |
| `Area_sqkm` | Basin area | km² |
| `ComID` | Basin/catchment ID | — |
| `Loss` | Loss fraction (removed from system) | — |

### 🔹 Bucket Options

| Option (`gwbaseswcrt`) | Description |
|------------------------|-------------|
| 0 | No baseflow (pass-through: output = input) |
| 1 | Exponential bucket model |
| 2 | Pass-through with loss |
| 4 | Exponential + NHDPlus mapping (NWM default) |

---

## 9. 🏗️ Lake & Reservoir Routing

### 🔹 Level-Pool Routing

Lakes and reservoirs in WRF-Hydro use **level-pool routing** — water comes in, the level rises, and water flows out over a weir or through an orifice.

> **🤖 ML Analogy**: A reservoir is like a **queue/buffer** in a data pipeline. Water (data) enters, gets stored temporarily, and exits at a rate determined by the water level — similar to how a message queue controls throughput.

### 🔹 Outflow Equations

**Weir outflow** (overflow over dam crest):
```
Qweir = Cw × L × h^(3/2)    when h > hmax
Qweir = 0                     when h ≤ hmax
```

**Orifice outflow** (through controlled gates):
```
Qorifice = Co × Oa × √(2 × g × h)
```

| Parameter | Description | Units |
|-----------|-------------|-------|
| `Cw` | Weir discharge coefficient | — |
| `L` / `WeirL` | Weir crest length | m |
| `Co` | Orifice discharge coefficient | — |
| `Oa` / `OrificeA` | Orifice cross-section area | m² |
| `hmax` / `LkMxE` | Maximum lake elevation | m |
| `LkArea` | Lake surface area | km² |

---

## 10. 📐 Governing Equations

Here's a consolidated view of ALL the key equations in WRF-Hydro:

### 🔹 Surface Energy Balance (Noah-MP)

```
Rnet = FSA - FIRA

Full balance:
FSA + PAH - FIRA - HFX - LH - GRDFLX - CANHS = 0

Where:
FSA    = Absorbed shortwave radiation (W/m²)
PAH    = Precipitation advected heat (W/m²)
FIRA   = Net upward longwave radiation (W/m²)
HFX    = Sensible heat flux (W/m²)
LH     = Latent heat flux (W/m²)
GRDFLX = Ground heat flux (W/m²)
CANHS  = Canopy heat storage change (W/m²)
```

### 🔹 Richards Equation (Soil Water Movement)

```
∂θ/∂t = ∂/∂z [K(θ) × (∂ψ/∂z + 1)] - S(z)

Where:
θ = volumetric soil moisture (m³/m³)
K = hydraulic conductivity (m/s) — depends on moisture
ψ = soil water potential (m) — suction pressure
S = sink term (root water uptake)
z = depth (m, positive downward)
```

### 🔹 Overland Flow (Diffusive Wave + Manning's)

```
Continuity:  ∂h/∂t + ∂qx/∂x + ∂qy/∂y = ie

Friction slope:  Sfx = Sox - ∂h/∂x

Manning's:  qx = (√|Sfx| / n) × h^(5/3) × sign(Sfx)

Where:
h   = surface water depth (m)
qx  = unit discharge in x-direction (m²/s)
ie  = infiltration excess rate (m/s)
Sox = terrain slope in x-direction (m/m)
n   = Manning's roughness coefficient
```

### 🔹 Subsurface Lateral Flow

```
Transmissivity:  T = (Ksat × D / n) × (1 - z/D)^n

Lateral flow:    q = -T × β × w    (when β < 0)

Water table:     Δz = (1/φ) × [Qnet/A - R] × Δt

Where:
Ksat = saturated hydraulic conductivity (m/s)
D    = total soil depth (m)
z    = water table depth below surface (m)
β    = water table slope (m/m, negative = downhill)
φ    = porosity (m³/m³)
R    = recharge rate from above (m/s)
```

### 🔹 Muskingum-Cunge Channel Routing

```
Storage:  S = K × [X × I + (1-X) × Q]

Routing:  Qd(t+1) = C1×Qu(t) + C2×Qu(t+1) + C3×Qd(t) + qlat×Δt/D

Where:
D  = K(1-X) + Δt/2
C1 = (Δt - 2KX) / (2D)
C2 = (Δt + 2KX) / (2D)
C3 = (2K(1-X) - Δt) / (2D)

Time-varying parameters:
K = Δx / ck        (travel time = reach length / wave speed)
X = 0.5 × (1 - Q/(Tw × ck × So × Δx))
ck = dQ/dA          (kinematic wave celerity)
```

### 🔹 Gridded Channel Routing (Diffusive Wave)

```
Continuity:   ∂A/∂t + ∂Q/∂x = qlat

Conveyance:   K = (1/n) × A × R^(2/3)

Diffusive:    Q = -sign(∂Z/∂x) × K × √|∂Z/∂x|

Solved with:  Newton-Raphson iteration
              Adaptive Δt (halved on non-convergence)
```

### 🔹 Groundwater Bucket

```
Water level:   z = z_prev + (Qin × Δt) / Area

Exponential discharge:
  Qexp = C × (e^(E × z/zmax) - 1)

Total outflow:
  Qout = Qspill + Qexp

Where:
C    = coefficient (m³/s)
E    = unitless exponent
zmax = maximum bucket depth (mm)
```

### 🔹 Lake/Reservoir Level-Pool

```
Weir:     Qw = Cw × L × h^(3/2)       when h > hmax
Orifice:  Qo = Co × Oa × √(2×g×h)     always (when h > 0)
Total:    Qout = Qw + Qo
```

---

## 11. 🗺️ Multi-Resolution Grid System

### 🔹 The Three Grids

WRF-Hydro's most distinctive feature is its **multi-resolution grid system**. Three grids operate simultaneously at different resolutions:

> **🤖 ML Analogy**: This is like a **Feature Pyramid Network (FPN)** in object detection. FPN processes images at multiple resolutions (P2=high-res, P5=low-res) and combines them. WRF-Hydro does the same with water — coarse grid for energy balance, fine grid for routing, vector network for rivers.

```
    ┌─────────────────────────────────────────┐
    │         GRID 0: LSM Grid (1 km)          │
    │                                          │
    │   ┌────┬────┬────┬────┐                  │
    │   │    │    │    │    │  Each cell:       │
    │   │ A  │ B  │ C  │ D  │  - Soil moisture  │
    │   │    │    │    │    │  - Snow depth      │
    │   ├────┼────┼────┼────┤  - Temperature     │
    │   │    │    │    │    │  - ET fluxes        │
    │   │ E  │ F  │ G  │ H  │  - Runoff          │
    │   │    │    │    │    │                    │
    │   └────┴────┴────┴────┘                  │
    │         (IX × JX cells)                  │
    └──────────────────┬──────────────────────┘
                       │ DISAGGREGATE
                       │ (AGGFACTRT = 4)
                       ▼
    ┌─────────────────────────────────────────┐
    │      GRID 1: Routing Grid (250 m)        │
    │                                          │
    │   ┌──┬──┬──┬──┬──┬──┬──┬──┐             │
    │   │  │  │  │  │  │  │  │  │ Each cell:  │
    │   ├──┼──┼──┼──┼──┼──┼──┼──┤ - Surface   │
    │   │  │  │  │  │  │  │  │  │   water depth│
    │   ├──┼──┼──┼──┼──┼──┼──┼──┤ - Flow      │
    │   │  │  │  │  │  │  │  │  │   direction  │
    │   ├──┼──┼──┼──┼──┼──┼──┼──┤ - Subsurface│
    │   │  │  │  │  │  │  │  │  │   moisture   │
    │   ├──┼──┼──┼──┼──┼──┼──┼──┤             │
    │   │  │  │  │  │  │  │  │  │             │
    │   ├──┼──┼──┼──┼──┼──┼──┼──┤             │
    │   │  │  │  │  │  │  │  │  │             │
    │   └──┴──┴──┴──┴──┴──┴──┴──┘             │
    │       (IXRT × JXRT cells)                │
    └──────────────────┬──────────────────────┘
                       │ MAP TO REACHES
                       │ (spatial weights)
                       ▼
    ┌─────────────────────────────────────────┐
    │    GRID 2: Channel Network (Vector)      │
    │                                          │
    │        ●──●──●                           │
    │              ╲                            │
    │    ●──●──●──●──●──●                      │
    │                    ╲                      │
    │         ●──●──●──●──●──●──► outlet       │
    │                                          │
    │    Each reach (link):                    │
    │    - Length, slope, width, roughness      │
    │    - Upstream/downstream connectivity     │
    │    - QLINK (discharge in m³/s)           │
    │                                          │
    │    (NLINKS reaches, e.g. 2.7M in NWM)    │
    └─────────────────────────────────────────┘
```

### 🔹 Grid Parameters

| Parameter | Grid 0 (LSM) | Grid 1 (Routing) | Grid 2 (Channel) |
|-----------|--------------|-------------------|-------------------|
| **Type** | Uniform rectilinear | Uniform rectilinear | Unstructured network |
| **Resolution (NWM)** | 1 km | 250 m | Variable (reach-based) |
| **Dimensions** | IX × JX | IXRT × JXRT | NLINKS |
| **BMI grid_type** | `uniform_rectilinear` | `uniform_rectilinear` | `vector` / `unstructured` |
| **Variables** | Soil, snow, ET, temp | Surface head, infiltration | Streamflow, velocity, depth |
| **Relation** | Base grid | AGGFACTRT × finer | Mapped via spatial weights |

### 🔹 Disaggregation / Aggregation

The **aggregation factor** (`AGGFACTRT`) defines how many routing cells fit inside one LSM cell:

```
1 km LSM cell "A"
┌────────────────┐
│ ┌──┬──┬──┬──┐  │
│ │a1│a2│a3│a4│  │  AGGFACTRT = 4
│ ├──┼──┼──┼──┤  │  → 4×4 = 16 routing cells per LSM cell
│ │a5│a6│a7│a8│  │
│ ├──┼──┼──┼──┤  │  Disaggregation: LSM → Routing
│ │a9│..│..│..│  │    INFXS, SFHEAD, SMC spread to fine grid
│ ├──┼──┼──┼──┤  │
│ │..│..│..│a16│ │  Aggregation: Routing → LSM
│ └──┴──┴──┴──┘  │    Average routing results back to LSM
└────────────────┘
```

---

## 12. ⏱️ Time Stepping & Subcycling

### 🔹 Multiple Timesteps

WRF-Hydro uses **different timesteps** for different physics components. The land surface runs slowly (hourly), while routing runs much faster (seconds) for numerical stability.

> **🤖 ML Analogy**: This is like **mixed-precision training** in deep learning — different parts of the computation run at different precisions (FP16 vs FP32). In WRF-Hydro, different parts run at different time resolutions. The "expensive" land model runs at coarse time steps, while the "cheap" routing runs many fine sub-steps.

### 🔹 Timestep Hierarchy

```
    ┌─────────────────────────────────────────┐
    │  FORCING_TIMESTEP = 3600s (1 hour)       │
    │  ├─ Read new atmospheric forcing data    │
    │                                          │
    │  ┌──────────────────────────────────┐    │
    │  │ NOAH_TIMESTEP = 3600s (1 hour)    │    │
    │  │ ├─ Run Noah-MP land surface model │    │
    │  │ ├─ Compute infiltration, runoff   │    │
    │  │ └─ Update soil moisture, snow     │    │
    │  │                                    │    │
    │  │  ┌───────────────────────────┐    │    │
    │  │  │ ROUTING SUBCYCLING         │    │    │
    │  │  │ (240 cycles at 15s each)   │    │    │
    │  │  │                            │    │    │
    │  │  │ Each cycle:                │    │    │
    │  │  │ ├─ DTRT_TER = 10-15s      │    │    │
    │  │  │ │  (overland routing)      │    │    │
    │  │  │ ├─ DTRT_CH = 10-300s      │    │    │
    │  │  │ │  (channel routing)       │    │    │
    │  │  │ └─ GW bucket update        │    │    │
    │  │  └───────────────────────────┘    │    │
    │  └──────────────────────────────────┘    │
    │                                          │
    │  OUTPUT_TIMESTEP = 3600s (1 hour)        │
    │  └─ Write LDASOUT, CHRTOUT, etc.         │
    └─────────────────────────────────────────┘
```

### 🔹 Timestep Parameters

| Parameter | Namelist | Typical Value | Description |
|-----------|----------|---------------|-------------|
| `FORCING_TIMESTEP` | namelist.hrldas | 3600 s | How often forcing data is read |
| `NOAH_TIMESTEP` | namelist.hrldas | 3600 s | Land surface model timestep |
| `OUTPUT_TIMESTEP` | namelist.hrldas | 3600 s | How often LSM output is written |
| `DTRT_TER` | hydro.namelist | 10-15 s | Overland routing timestep |
| `DTRT_CH` | hydro.namelist | 10-300 s | Channel routing timestep |
| `out_dt` | hydro.namelist | 60 min | Hydro output frequency |
| `rst_dt` | hydro.namelist | 1440 min | Restart file frequency (24 hrs) |

### 🔹 Courant Stability Requirement

The routing timestep must satisfy the **Courant condition** for numerical stability:

```
Courant number: Cn = c × (Δt/Δx) < 1.0

Where:
c  = wave celerity (speed of flood wave, m/s)
Δt = timestep (s)
Δx = grid spacing (m)
```

| Grid Spacing (m) | Suggested Δt (s) | Subcycles per hour |
|------------------|-------------------|-------------------|
| 30 | 2 | 1,800 |
| 100 | 6 | 600 |
| 250 | 15 | 240 |
| 500 | 30 | 120 |
| 1000 | 60 | 60 |

---

## 13. ⚖️ Comparison with Other Models

### 🔹 Feature Comparison Table

| Feature | 🌊 WRF-Hydro | 🏔️ VIC | 🌾 SWAT | 🏗️ HEC-HMS | 🔬 MIKE-SHE |
|---------|-------------|--------|---------|-----------|------------|
| **Type** | Physically-based distributed | Physically-based distributed | Semi-distributed conceptual | Event-based lumped | Fully physically-based |
| **Developer** | NCAR | U. Washington | USDA-ARS | US Army Corps | DHI (commercial) |
| **Year** | 2003 | 1994 | 1998 | 1992 | 1986 |
| **Open Source** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No | ❌ No ($$) |
| **Language** | Fortran 90 | C/Fortran | Fortran | Java | C++ |
| **Grid** | Multi-resolution | Regular grid | HRU-based | Lumped/sub-basin | Regular grid |
| **Atmosphere Coupling** | ✅ Direct WRF | ❌ Offline only | ❌ Offline only | ❌ Offline only | ❌ Offline only |
| **Overland Flow** | ✅ 2D diffusive wave | ❌ No lateral | ❌ No explicit | ✅ Kinematic wave | ✅ Full 2D |
| **Subsurface** | ✅ Lateral (DHSVM) | ❌ Column only | ❌ Conceptual | ❌ No | ✅ Full 3D (MODFLOW) |
| **Channel Routing** | ✅ Muskingum/Diffusive | ❌ External (RAPID) | ✅ Variable storage | ✅ Multiple methods | ✅ Full dynamic wave |
| **Groundwater** | ⚠️ Bucket (conceptual) | ❌ None | ⚠️ Simple baseflow | ⚠️ Baseflow methods | ✅ Full 3D |
| **Snow Physics** | ✅ Multi-layer (Noah-MP) | ✅ Energy balance | ⚠️ Temp-index | ⚠️ Temp-index | ✅ Energy balance |
| **Scalability** | 🌎 Continental | 🌎 Continental | 🏞️ Watershed | 🏞️ Watershed | 🏞️ Watershed |
| **MPI Parallel** | ✅ Yes | ⚠️ Limited | ❌ No | ❌ No | ✅ Yes |
| **Operational** | ✅ NWM (NOAA) | ⚠️ Limited | ❌ No | ✅ RFC | ❌ No |
| **BMI Support** | 🔨 Building (our project!) | ❌ No | ❌ No | ❌ No | ❌ No |

### 🔹 WRF-Hydro Strengths

| Strength | Details |
|----------|---------|
| 🌧️ **Atmosphere coupling** | Only model that directly couples to WRF weather model |
| 🇺🇸 **Operational status** | Powers NOAA NWM — proven at continental scale |
| 📏 **Multi-resolution** | Separate grids for land surface, terrain, channels |
| 🔄 **Active development** | NCAR team with NOAA funding, regular releases |
| 🌐 **Community** | Large user base, training workshops, Google Groups |

### 🔹 WRF-Hydro Weaknesses

| Weakness | Details |
|----------|---------|
| 🪣 **Conceptual groundwater** | Simple bucket model, not physically-based 3D |
| 🐌 **Computationally expensive** | Requires HPC for large domains (100K+ CPU-hrs/day for NWM) |
| 📚 **Steep learning curve** | Complex configuration (100+ parameters, many files) |
| 🧩 **No BMI** | Not yet in CSDMS ecosystem — that's what we're building! |

---

## 14. 🇺🇸 NOAA National Water Model

### 🔹 What is the NWM?

The **National Water Model (NWM)** is NOAA's operational hydrological forecasting system, and **WRF-Hydro is its core engine**. It provides real-time streamflow forecasts for the entire continental United States.

> **🤖 ML Analogy**: The NWM is like **GPT deployed as ChatGPT** — WRF-Hydro is the foundation model, and NWM is the production deployment with API endpoints, monitoring, and real-time inference serving millions of "predictions" (streamflow forecasts) simultaneously.

### 🔹 Key Numbers

| Metric | Value |
|--------|-------|
| 🏞️ River reaches modeled | **2.7 million** (3.4M river miles) |
| 🏗️ Reservoirs included | **5,000+** |
| 📍 USGS gauges assimilated | **~7,000** (every 15 minutes) |
| 🗺️ Land surface grid | **1 km** resolution |
| 🏔️ Routing grid | **250 m** resolution |
| 🌎 Coverage | CONUS + Alaska + Hawaii + Puerto Rico |
| 📅 Operational since | **August 2016** |
| 🖥️ CPU-hours/day | **100,000+** on NOAA WCOSS |
| 💾 Data output/day | **Terabytes** |

### 🔹 Forecast Configurations

| Configuration | Forecast Length | Frequency | Forcing Data | Members |
|--------------|----------------|-----------|-------------|---------|
| ⚡ **Short-Range (CONUS)** | 18 hours | Hourly | HRRR/RAP | 1 (deterministic) |
| 📊 **Medium-Range Blend** | 10 days | 4× daily | NBM/GFS | 1 (deterministic) |
| 📊 **Medium-Range** | 10 days | 4× daily | GFS | 6 ensemble members |
| 📅 **Long-Range** | 30 days | Every 6 hrs | CFS | 4 members/cycle |
| 🔍 **Standard AnA** | Hourly analysis | Hourly | MRMS/RAP | 1 |
| 🔍 **Extended AnA** | 28-hr lookback | Daily | MRMS/RAP | 1 |
| 🏔️ **Short-Range (Alaska)** | 15/45 hours | Every 3 hrs | — | 1 |
| 🌴 **Short-Range (HI/PR)** | 48 hours | 2× daily | NAM/WRF-ARW | 1 |

### 🔹 NWM Version History

| NWM Version | WRF-Hydro Version | Year | Key Addition |
|------------|-------------------|------|-------------|
| v1.0 | ~v5.0 | 2016 | Initial operational deployment |
| v2.0 | v5.1.1 | 2020 | Enhanced configurations |
| v2.1 | v5.2.0 | 2021 | Incremental improvements |
| v3.0 | v5.3.0 | 2023 | Alaska domain, coastal TWL, MRMS precip |
| v3.1 | v5.4.0 | 2025 | Gage-assisted diversions, CMake build |

### 🔹 Data Assimilation

The NWM assimilates real-time observations to improve accuracy:

```
    USGS Streamflow Gauges (~7,000)
              │
              ▼
    ┌─────────────────────┐
    │  NUDGING SCHEME       │
    │                       │
    │  For each gauge:      │
    │  Qnudged = Qmodel +  │
    │    α × (Qobs - Qmodel)│
    │                       │
    │  α = nudging weight   │
    │  (time-decaying)      │
    └──────────┬────────────┘
               │
    Model adjusts streamflow
    at gauged locations
```

---

# Part II: WRF-Hydro — Architecture & Internals

---

## 15. 🏗️ Source Code Architecture

### 🔹 Repository Structure

```
wrf_hydro_nwm_public/
├── 📄 CMakeLists.txt          ← Top-level build file
├── 📄 NEWS.md                 ← Release notes
├── 📄 LICENSE.txt             ← UCAR license
├── 📁 cmake/                  ← Build configuration
│
└── 📁 src/                    ← ALL SOURCE CODE (235 Fortran files)
    │
    ├── 📁 Land_models/        ← 🌱 Land Surface Models (121 files, 6.2 MB)
    │   ├── 📁 Noah/           ←   Original Noah LSM (deprecated)
    │   └── 📁 NoahMP/         ←   Noah-MP (ACTIVE)
    │       ├── 📁 IO_code/    ←     ⭐ main_hrldas_driver.F (ENTRY POINT)
    │       │                  ←     ⭐ module_NoahMP_hrldas_driver.F
    │       ├── 📁 phys/       ←     Physics modules (10,177-line core)
    │       └── 📁 data_structures/ ← Noah-MP data types
    │
    ├── 📁 Routing/            ← 🏞️ Routing Modules (49 files, 1.9 MB)
    │   ├── 📄 module_RT.F90              ← Routing initialization
    │   ├── 📄 module_channel_routing.F90 ← ⭐ Channel physics (2,134 lines)
    │   ├── 📄 module_GW_baseflow.F90     ← Groundwater bucket
    │   ├── 📄 module_HYDRO_io.F90        ← ⭐ I/O system (11,399 lines!)
    │   ├── 📄 module_NWM_io.F90          ← NWM-format output (5,557 lines)
    │   ├── 📄 module_NWM_io_dict.F90     ← Variable name mappings (2,799 lines)
    │   ├── 📄 module_UDMAP.F90           ← NHDPlus user-defined mapping
    │   ├── 📄 Noah_distr_routing.F90     ← Overland/subsurface physics
    │   ├── 📁 Overland/                  ← Surface runoff modules
    │   ├── 📁 Subsurface/                ← Underground routing modules
    │   ├── 📁 Reservoirs/                ← Level-pool, RFC, persistence
    │   └── 📁 Diversions/                ← Channel diversions (v5.4+)
    │
    ├── 📁 HYDRO_drv/          ← 🚗 Main Driver (1 file, 1,838 lines)
    │   └── 📄 module_HYDRO_drv.F90       ← ⭐ HYDRO_ini / HYDRO_exe / HYDRO_finish
    │
    ├── 📁 Data_Rec/           ← 📊 Data Structures (5 files, 68 KB)
    │   ├── 📄 module_rt_inc.F90          ← ⭐ RT_FIELD type (ALL routing state)
    │   └── 📄 module_namelist.F90        ← Namelist reading
    │
    ├── 📁 CPL/                ← 🔗 Coupling Layers (16 files, 624 KB)
    │   ├── 📁 Noah_cpl/                  ← Offline Noah coupling
    │   ├── 📁 NoahMP_cpl/                ← Offline Noah-MP coupling
    │   ├── 📁 WRF_cpl/                   ← WRF atmospheric coupling
    │   ├── 📁 CLM_cpl/                   ← CLM coupling (experimental)
    │   ├── 📁 LIS_cpl/                   ← LIS coupling (experimental)
    │   └── 📁 NUOPC_cpl/                 ← NUOPC/ESMF coupling
    │
    ├── 📁 MPP/                ← 🖥️ MPI Parallelization (5 files, 176 KB)
    │   ├── 📄 mpp_land.F90              ← Domain decomposition (2,837 lines)
    │   ├── 📄 module_mpp_ReachLS.F90    ← Reach-based MPI
    │   └── 📄 module_mpp_GWBUCKET.F90   ← GW bucket MPI
    │
    ├── 📁 OrchestratorLayer/  ← 🎼 Configuration (3 files, 64 KB)
    │   └── 📄 config.F90               ← All config data types (51 KB)
    │
    ├── 📁 nudging/            ← 📍 Data Assimilation (4 files, 228 KB)
    │
    ├── 📁 Debug_Utilities/    ← 🔧 Debug tools
    ├── 📁 utils/              ← 🛠️ Utilities (versioning)
    └── 📁 template/           ← 📋 Example namelists & tables (1.2 MB)
```

### 🔹 Largest Source Files

| File | Lines | Purpose |
|------|-------|---------|
| `module_HYDRO_io.F90` | 11,399 | NetCDF I/O for all routing data |
| `module_sf_noahmplsm.F` | 10,177 | Noah-MP core physics |
| `module_snowcro.F` | 5,664 | Crocus snowpack model |
| `module_NWM_io.F90` | 5,557 | NWM-format output |
| `module_lsm_forcing.F90` | 3,419 | Forcing data handling |
| `module_NoahMP_hrldas_driver.F` | 2,869 | HRLDAS Noah-MP driver |
| `mpp_land.F90` | 2,837 | MPI domain decomposition |
| `module_NWM_io_dict.F90` | 2,799 | Variable name dictionaries |
| `module_channel_routing.F90` | 2,134 | Channel routing algorithms |
| `module_HYDRO_drv.F90` | 1,838 | Hydro driver (IRF target) |

---

## 16. 🔄 Main Program & Time Loop

### 🔹 The 43-Line Entry Point

WRF-Hydro's entire main program is surprisingly compact — just 43 lines. It has an **integrated time loop** that we must decompose for BMI.

```
main_hrldas_driver.F (simplified):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

program noah_hrldas_driver
    use module_noahmp_hrldas_driver   ← land_driver_ini, land_driver_exe
    use module_HYDRO_drv              ← HYDRO_finish
    use state_module                  ← state_type
    use orchestrator_base             ← orchestrator%init()

    implicit none
    integer :: ITIME, NTIME
    type(state_type) :: state

    call orchestrator%init()           ← Read configs
    call land_driver_ini(NTIME, state) ← INITIALIZE (land + hydro)

    do ITIME = 1, NTIME               ← THE TIME LOOP (BMI must control this)
        call land_driver_exe(ITIME, state) ← ONE TIMESTEP
    end do

    call hydro_finish()                ← FINALIZE (cleanup)
end program
```

### 🔹 The BMI Challenge

```
    CURRENT (main_hrldas_driver.F):
    ┌─────────────────────────────┐
    │ call land_driver_ini()       │ ─── Initialize
    │                              │
    │ do ITIME = 1, NTIME         │ ─── Model controls loop
    │   call land_driver_exe()     │
    │ end do                       │
    │                              │
    │ call hydro_finish()          │ ─── Finalize
    └─────────────────────────────┘

    BMI REQUIRED (bmi_wrf_hydro.f90):
    ┌─────────────────────────────┐
    │ bmi%initialize(config_file)  │ ─── Initialize
    └──────────────┬──────────────┘
                   │
    ┌──────────────▼──────────────┐
    │ bmi%update()                 │ ─── CALLER controls loop
    │ bmi%update()                 │     (PyMT calls this
    │ bmi%update()                 │      repeatedly)
    │ ...                          │
    └──────────────┬──────────────┘
                   │
    ┌──────────────▼──────────────┐
    │ bmi%finalize()               │ ─── Finalize
    └─────────────────────────────┘
```

> **🤖 ML Analogy**: This is like converting a training script with a built-in `for epoch in range(100)` loop into a **callable class** where the caller decides when to call `model.train_one_step()`. The model shouldn't control its own training loop — the framework should.

---

## 17. 🔧 Key Subroutines (IRF Pattern)

### 🔹 Initialize-Run-Finalize Decomposition

For BMI, we need to map WRF-Hydro's existing subroutines to the IRF pattern:

| BMI Function | WRF-Hydro Subroutine | Location | Line |
|-------------|---------------------|----------|------|
| `initialize()` | `land_driver_ini()` | module_NoahMP_hrldas_driver.F | ~422 |
| `initialize()` | `HYDRO_ini()` | module_HYDRO_drv.F90 | ~1350 |
| `update()` | `land_driver_exe()` | module_NoahMP_hrldas_driver.F | ~1646 |
| `update()` | `HYDRO_exe()` | module_HYDRO_drv.F90 | ~561 |
| `finalize()` | `HYDRO_finish()` | module_HYDRO_drv.F90 | ~1800 |

### 🔹 What Each Subroutine Does

**`land_driver_ini()` — Noah-MP Initialization (~1,200 lines)**
```
├── Read namelist.hrldas configuration
├── Read geo_em domain file (land cover, soil types, elevation)
├── Read or create restart file (soil moisture, snow, temperature)
├── Allocate all Noah-MP arrays
├── Initialize Noah-MP physics tables (.TBL files)
├── Set up forcing data readers
├── Call HYDRO_ini() internally
└── Return NTIME (number of timesteps to run)
```

**`HYDRO_ini()` — Routing Initialization (~450 lines)**
```
├── Read hydro.namelist configuration
├── Read Fulldom_hires.nc (terrain, flow direction, channels)
├── Read Route_Link.nc (channel parameters)
├── Read LAKEPARM.nc (lake/reservoir parameters)
├── Read GWBUCKPARM.nc (groundwater parameters)
├── Allocate RT_FIELD arrays (the master state)
├── Initialize MPI decomposition
├── Read or create hydro restart file
└── Initialize channel network connectivity
```

**`land_driver_exe()` — One Land Surface Timestep (~1,200 lines)**
```
├── Read forcing data (if new forcing time)
├── Call Noah-MP physics (energy + water balance for each cell)
├── Compute infiltration excess (INFXS), surface/subsurface runoff
├── Call HYDRO_exe() (run all routing)
├── Write output files (if output time)
└── Write restart files (if restart time)
```

**`HYDRO_exe()` — One Routing Timestep (~800 lines)**
```
├── Disaggregate LSM outputs to routing grid (1km → 250m)
├── Routing subcycling loop:
│   ├── Subsurface lateral flow (if SUBRTSWCRT > 0)
│   ├── Overland flow routing (if OVRTSWCRT > 0)
│   ├── Groundwater bucket update (if GWBASESWCRT > 0)
│   └── Channel routing + nudging (if CHANRTSWCRT > 0)
├── Lake/reservoir routing
├── Aggregate routing results back to LSM grid
├── Write hydro outputs (CHRTOUT, RTOUT, LAKEOUT, GWOUT)
└── Update mass balance tracking
```

**`HYDRO_finish()` — Cleanup (~40 lines)**
```
├── Write final restart file
├── Close all open files
├── Deallocate arrays
└── Finalize MPI
```

---

## 18. 📦 RT_FIELD — The Master State Type

### 🔹 What is RT_FIELD?

`RT_FIELD` is a single Fortran derived type that contains **ALL routing state variables**. It's defined in `module_rt_inc.F90` (270 lines) and is the most important data structure for BMI variable access.

> **🤖 ML Analogy**: `RT_FIELD` is like the `model.state_dict()` in PyTorch — one dictionary that contains ALL the model's parameters and buffers. When you do `get_value("streamflow")`, the BMI wrapper looks into `RT_FIELD` to find the data.

### 🔹 RT_FIELD Organization

```
RT_FIELD
├── 🏔️ Overland Structure
│   ├── control (surface head, infiltration, ponding)
│   ├── streams_and_lakes (channel/lake interface)
│   ├── properties (roughness, retention depth, slopes)
│   └── mass_balance (runoff accumulations)
│
├── 💧 Subsurface Structure
│   ├── state (soil moisture on routing grid)
│   ├── properties (porosity, K_sat)
│   └── grid_transform (LSM ↔ routing mapping)
│
├── 🏗️ Reservoir Array
│   └── reservoirs(:) — level pool objects
│
├── 🏞️ Channel Variables
│   ├── NLINKS — number of channel reaches
│   ├── QLINK(:,:) — discharge (m³/s) ⭐ KEY OUTPUT
│   ├── HLINK(:) — water depth (m)
│   ├── CVOL(:) — channel volume (m³)
│   ├── ZELEV(:) — channel elevation (m)
│   ├── CHANLEN(:) — reach length (m)
│   ├── MannN(:) — Manning's roughness
│   ├── So(:) — channel slope
│   ├── Bw(:), Tw(:) — bottom/top width
│   ├── MUSK(:), MUSX(:) — Muskingum parameters
│   ├── LINK(:) — reach IDs
│   ├── TO_NODE(:) — downstream connectivity
│   └── FROM_NODE(:) — upstream connectivity
│
├── 🌊 Groundwater Variables
│   ├── numbasns — number of GW basins
│   ├── z_gwsubbas(:) — bucket water level (mm)
│   ├── qin_gwsubbas(:) — inflow to bucket
│   ├── qout_gwsubbas(:) — outflow (baseflow)
│   ├── gw_buck_coeff(:) — discharge coefficient
│   └── gw_buck_exp(:) — exponential exponent
│
├── 🗺️ Grid & Geometry
│   ├── IX, JX — LSM grid dimensions
│   ├── IXRT, JXRT — routing grid dimensions
│   ├── DX — grid spacing (m)
│   ├── ELRT(:,:) — terrain elevation
│   ├── LATVAL(:,:), LONVAL(:,:) — coordinates
│   └── AGGFACYRT, AGGFACXRT — aggregation factors
│
├── 🟤 Soil Variables (on routing grid)
│   ├── SMC(:,:,:) — total soil moisture (routing grid)
│   ├── SH2OX(:,:,:) — liquid soil moisture
│   ├── STC(:,:,:) — soil temperature
│   ├── SMCMAX1(:,:) — porosity
│   ├── SMCWLT1(:,:) — wilting point
│   └── SMCREF1(:,:) — field capacity
│
├── 🏞️ Lake Variables
│   ├── NLAKES — number of lakes
│   ├── LAKEIDA(:) — lake IDs
│   ├── HRZAREA(:) — lake area (km²)
│   ├── WEIRL(:), WEIRC(:) — weir length/coefficient
│   ├── ORIFICEC(:), ORIFICEA(:) — orifice params
│   └── LAKEMAXH(:) — maximum lake depth
│
├── 📊 Surface Routing Variables
│   ├── INFXSRT(:,:) — infiltration excess
│   ├── sfcheadsubrt(:,:) — surface water head
│   ├── SOLDRAIN(:,:) — soil drainage
│   ├── q_sfcflx_x(:,:) — surface flux x
│   └── q_sfcflx_y(:,:) — surface flux y
│
└── ⚙️ Control & Counters
    ├── timestep_flag
    ├── initialized (logical)
    ├── out_counts, rst_counts
    └── mass balance trackers (DCMC, DSWE, etc.)
```

### 🔹 Accessing RT_FIELD in the BMI Wrapper

In serial mode, there's one global instance: `rt_domain(1)`

```
For BMI get_value("channel_water__volume_flow_rate"):
  → Access rt_domain(1)%QLINK(:,1)
  → Flatten to 1D array
  → Return to caller

For BMI get_value("land_surface_water__depth"):
  → Access rt_domain(1)%overland%control%surface_water_head_lsm(:,:)
  → Flatten to 1D
  → Return to caller
```

---

## 19. 📥 Input Data Requirements

### 🔹 Domain/Static Files

These files define the model's **spatial structure** — they don't change during a run.

| File | Description | Key Variables |
|------|-------------|---------------|
| 📄 `geo_em.d01.nc` | GEOGRID base grid | `LU_INDEX` (land cover), `SCT_DOM` (soil), `HGT_M` (elevation), `XLAT_M`, `XLONG_M` |
| 📄 `wrfinput.d01.nc` | Initial conditions | `SMOIS` (soil moisture), `TSLB` (soil temp), `SNOW`, `CANWAT`, `TSK`, `LAI`, `TMN` |
| 📄 `Fulldom_hires.nc` | Routing stack | `TOPOGRAPHY`, `FLOWDIRECTION`, `FLOWACC`, `CHANNELGRID`, `STREAMORDER`, `LKSATFAC` |
| 📄 `Route_Link.nc` | Channel parameters | `BtmWdth`, `ChSlp`, `n`, `MusK`, `MusX`, `Length`, `So`, `order`, `NHDWaterbodyComID` |
| 📄 `LAKEPARM.nc` | Lake parameters | `LkArea`, `LkMxE`, `WeirC`, `WeirL`, `OrificeC`, `OrificeA`, `OrificeE` |
| 📄 `GWBUCKPARM.nc` | GW bucket parameters | `Coeff`, `Expon`, `Zmax`, `Zinit`, `Area_sqkm`, `ComID`, `Loss` |
| 📄 `GWBASINS.nc` | GW basin definitions | `BASIN` (basin IDs per routing cell) |
| 📄 `spatialweights.nc` | Mapping weights | Weights for NHDPlus catchment mapping |
| 📄 `hydro2dtbl.nc` | 2D hydro parameters | `SMCMAX1`, `SMCREF1`, `SMCWLT1`, `OV_ROUGH2D`, `LKSAT` |

### 🔹 Parameter Tables (.TBL Files)

| File | Description | Example Parameters |
|------|-------------|-------------------|
| 📋 `GENPARM.TBL` | Global parameters | `SLOPE_DATA`, `CSOIL_DATA`, `ZBOT_DATA`, `CZIL_DATA` |
| 📋 `SOILPARM.TBL` | Soil by texture class | `BB`, `MAXSMC`, `SATDK`, `SATPSI`, `WLTSMC`, `QTZ` |
| 📋 `VEGPARM.TBL` | Vegetation by land cover | `SHDFAC`, `NROOT`, `RS`, `SNUP`, `LAI`, `Z0` |
| 📋 `MPTABLE.TBL` | Noah-MP parameters | `CH2OP`, `DLEAF`, `Z0MVT`, `HVT`, `VCMX25` |
| 📋 `CHANPARM.TBL` | Channel by stream order | `Bw`, `HLINK`, `ChSSlp`, `MannN` |
| 📋 `HYDRO.TBL` | Terrain routing params | `SFC_ROUGH`, `SATDK`, `MAXSMC`, `REFSMC`, `WLTSMC` |

### 🔹 Forcing Data (LDASIN Files)

Atmospheric forcing at regular intervals (typically hourly):

| Variable | Description | Units |
|----------|-------------|-------|
| `T2D` | 2-meter air temperature | K |
| `Q2D` | 2-meter specific humidity | kg/kg |
| `U2D` | 10-meter U-wind | m/s |
| `V2D` | 10-meter V-wind | m/s |
| `PSFC` | Surface pressure | Pa |
| `LWDOWN` | Downward longwave radiation | W/m² |
| `SWDOWN` | Downward shortwave radiation | W/m² |
| `RAINRATE` | Precipitation rate | mm/s |
| `LQFRAC` | Liquid precipitation fraction | — (optional) |

> **🤖 ML Analogy**: Domain files = model architecture definition, Parameter tables = pretrained weights, Forcing data = input features for inference, Restart files = model checkpoints.

### 🔹 Restart Files

| File | Description | Key Variables |
|------|-------------|---------------|
| `RESTART.*` | Noah-MP restart | `SMC`, `SH2O`, `STC`, `SNEQV`, `SNOWH`, `CANLIQ`, `LAI`, `ZWT` |
| `HYDRO_RST.*` | Routing restart | `qlink1`, `qlink2`, `hlink`, `cvol`, `sfcheadrt`, `sh2ox`, `resht`, `qlakeo` |

---

## 20. 📤 Output Data & File Types

### 🔹 Output File Types

| File | Format | Content | Activation |
|------|--------|---------|-----------|
| 📊 `LDASOUT_DOMAIN` | Multi-dim NetCDF | Land surface (soil, snow, ET, energy) | `OUTPUT_TIMESTEP` |
| 📊 `CHRTOUT_DOMAIN` | Point NetCDF | Streamflow at ALL channel reaches | `CHRTOUT_DOMAIN` |
| 📊 `CHANOBS_DOMAIN` | Point NetCDF | Streamflow at forecast/gage points only | `CHANOBS_DOMAIN` |
| 📊 `CHRTOUT_GRID` | 2D NetCDF | Streamflow on 2D grid | `CHRTOUT_GRID` |
| 📊 `RTOUT_DOMAIN` | 2D NetCDF | Terrain routing (overland/subsurface) | `RTOUT_DOMAIN` |
| 📊 `LAKEOUT_DOMAIN` | Point NetCDF | Lake inflow, outflow, elevation | `outlake` |
| 📊 `GWOUT_DOMAIN` | NetCDF | GW bucket inflow/outflow/depth | `output_gw` |
| 📊 `LSMOUT_DOMAIN` | NetCDF | LSM-routing exchange diagnostics | `LSMOUT_DOMAIN` |
| 📝 `frxst_pts_out.txt` | ASCII text | Forecast point timeseries | `frxst_pts_out` |

### 🔹 Croton NY Test Case Output (6-hour run)

Our test case produces **39 output files** in 6 hours:

```
Output files generated:
├── LDASOUT_DOMAIN1 ×7  (hourly land surface)
├── CHRTOUT_DOMAIN1 ×7  (hourly streamflow)
├── CHANOBS_DOMAIN1 ×7  (hourly gage points)
├── RTOUT_DOMAIN1   ×7  (hourly terrain routing)
├── LAKEOUT_DOMAIN1 ×7  (hourly lakes)
├── GWOUT_DOMAIN1   ×4  (every 2 hours GW)
└── RESTART + HYDRO_RST  (end-of-run checkpoints)
```

---

## 21. 📋 All Key Variables — Detailed Tables

### 🔹 Land Surface Output Variables (LDASOUT)

| # | Variable | CSDMS Standard Name | Units | Description | Layers |
|---|----------|-------------------|-------|-------------|--------|
| 1 | `SOIL_M` / `SMC` | `soil_water__volume_fraction` | m³/m³ | Total soil moisture | 4 |
| 2 | `SOIL_W` / `SH2O` | — | m³/m³ | Liquid soil moisture | 4 |
| 3 | `SOIL_T` / `STC` | — | K | Soil temperature | 4 |
| 4 | `SNEQV` | `snowpack__liquid-equivalent_depth` | kg/m² | Snow water equivalent | 1 |
| 5 | `SNOWH` | — | m | Snow depth | 1 |
| 6 | `T2` | `land_surface_air__temperature` | K | 2m air temperature | 1 |
| 7 | `TSK` | — | K | Skin temperature | 1 |
| 8 | `RAINRATE` | `atmosphere_water__precipitation_leq-volume_flux` | mm/s | Precipitation rate | 1 |
| 9 | `ACCET` | `land_surface_water__evaporation_volume_flux` | mm | Accumulated ET | 1 |
| 10 | `ACCECAN` | — | mm | Accumulated canopy evaporation | 1 |
| 11 | `ACCETRAN` | — | mm | Accumulated transpiration | 1 |
| 12 | `ACCEDIR` | — | mm | Accumulated direct soil evaporation | 1 |
| 13 | `SFCRUNOFF` | — | mm | Accumulated surface runoff | 1 |
| 14 | `UDRUNOFF` | `soil_water__domain_time_integral_of_baseflow_volume_flux` | mm | Accumulated subsurface runoff | 1 |
| 15 | `CANLIQ` | — | mm | Canopy liquid water | 1 |
| 16 | `CANICE` | — | mm | Canopy ice | 1 |
| 17 | `LAI` | — | m²/m² | Leaf area index | 1 |
| 18 | `HFX` | — | W/m² | Sensible heat flux | 1 |
| 19 | `LH` | — | W/m² | Latent heat flux | 1 |
| 20 | `GRDFLX` | — | W/m² | Ground heat flux | 1 |
| 21 | `FSA` | — | W/m² | Absorbed shortwave radiation | 1 |
| 22 | `FIRA` | — | W/m² | Net longwave radiation | 1 |
| 23 | `ZWT` | — | m | Water table depth | 1 |
| 24 | `ACCPRCP` | — | mm | Accumulated precipitation | 1 |

### 🔹 Channel Output Variables (CHRTOUT)

| # | Variable | CSDMS Standard Name | Units | Description |
|---|----------|-------------------|-------|-------------|
| 1 | `streamflow` / `QLINK` | `channel_water__volume_flow_rate` | m³/s | ⭐ Stream discharge |
| 2 | `velocity` | — | m/s | Flow velocity |
| 3 | `Head` / `HLINK` | — | m | Water depth/stage |
| 4 | `qSfcLatRunoff` | — | m³/s | Surface lateral inflow |
| 5 | `qBucket` | — | m³/s | Baseflow from GW bucket |
| 6 | `qBtmVertRunoff` | — | m³/s | Bottom vertical runoff to bucket |
| 7 | `feature_id` | — | — | NHDPlus reach identifier |

### 🔹 Terrain Routing Variables (RTOUT)

| # | Variable | Units | Description |
|---|----------|-------|-------------|
| 1 | `sfcheadsubrt` | mm | Surface water head on routing grid |
| 2 | `INFXSRT` | mm | Infiltration excess |
| 3 | `soldrain` | mm | Soil drainage |
| 4 | `q_sfcflx_x` | m³/s | Surface flux in x-direction |
| 5 | `q_sfcflx_y` | m³/s | Surface flux in y-direction |

### 🔹 Groundwater Variables (GWOUT)

| # | Variable | Units | Description |
|---|----------|-------|-------------|
| 1 | `z_gwsubbas` | mm | Bucket water level |
| 2 | `qin_gwsubbas` | m³/s | Inflow to bucket |
| 3 | `qout_gwsubbas` | m³/s | Outflow (baseflow) |
| 4 | `qloss_gwsubbas` | m³/s | Loss from bucket |

### 🔹 Lake Variables (LAKEOUT)

| # | Variable | Units | Description |
|---|----------|-------|-------------|
| 1 | `water_sfc_elev` / `resht` | m | Lake water surface elevation |
| 2 | `inflow` | m³/s | Total inflow to lake |
| 3 | `outflow` / `qlakeo` | m³/s | Total outflow from lake |

### 🔹 Variables Selected for Initial BMI (Priority)

| # | Variable | CSDMS Name | Direction | Grid | Why |
|---|----------|-----------|-----------|------|-----|
| 1 | `QLINK` | `channel_water__volume_flow_rate` | OUTPUT | Channel | ⭐ Coupling with SCHISM |
| 2 | `sfcheadrt` | `land_surface_water__depth` | OUTPUT | Routing | Flooding indicator |
| 3 | `SMC` | `soil_water__volume_fraction` | OUTPUT | LSM | Soil wetness |
| 4 | `SNEQV` | `snowpack__liquid-equivalent_depth` | OUTPUT | LSM | Snow state |
| 5 | `ACCET` | `land_surface_water__evaporation_volume_flux` | OUTPUT | LSM | Water budget |
| 6 | `T2` | `land_surface_air__temperature` | OUTPUT | LSM | Surface temperature |
| 7 | `UDRUNOFF` | `soil_water__domain_time_integral_of_baseflow_volume_flux` | OUTPUT | LSM | Baseflow |
| 8 | `SFCRUNOFF` | — | OUTPUT | LSM | Surface runoff |
| 9 | `RAINRATE` | `atmosphere_water__precipitation_leq-volume_flux` | INPUT | LSM | Forcing override |
| 10 | `ETA2` | `sea_water_surface__elevation` | INPUT | Channel | ⭐ From SCHISM |

---

## 22. ⚙️ Configuration — Namelists

### 🔹 namelist.hrldas (Land Surface Configuration)

| Parameter | Type | Example | Description |
|-----------|------|---------|-------------|
| `START_YEAR/MONTH/DAY/HOUR` | int | 2011, 8, 25, 00 | Simulation start time |
| `KHOUR` | int | 6 | Number of hours to run |
| `FORCING_TIMESTEP` | int | 3600 | Forcing input interval (s) |
| `NOAH_TIMESTEP` | int | 3600 | LSM physics timestep (s) |
| `OUTPUT_TIMESTEP` | int | 3600 | LSM output frequency (s) |
| `RESTART_FREQUENCY_HOURS` | int | 24 | Restart file frequency |
| `NSOIL` | int | 4 | Number of soil layers |
| `soil_thick_input` | real(4) | 0.1,0.3,0.6,1.0 | Soil layer thicknesses (m) |
| `DYNAMIC_VEG_OPTION` | int | 4 | Vegetation phenology scheme |
| `RUNOFF_OPTION` | int | 3 | Runoff generation scheme |
| `FROZEN_SOIL_OPTION` | int | 1 | Frozen soil physics |
| `GLACIER_OPTION` | int | 2 | Glacier treatment |
| `INDIR` | char | "./FORCING" | Forcing data directory |
| `OUTDIR` | char | "./" | Output directory |
| `RESTART_FILENAME_REQUESTED` | char | "RESTART..." | Restart file path |

### 🔹 hydro.namelist (Routing Configuration)

| Parameter | Type | Example | Description |
|-----------|------|---------|-------------|
| `NSOIL` | int | 4 | Number of soil layers |
| `DXRT` | real | 250.0 | Routing grid resolution (m) |
| `AGGFACTRT` | int | 4 | Aggregation factor (LSM/routing) |
| `DTRT_TER` | real | 10.0 | Overland routing timestep (s) |
| `DTRT_CH` | real | 300.0 | Channel routing timestep (s) |
| `SUBRTSWCRT` | int | 1 | Subsurface routing switch |
| `OVRTSWCRT` | int | 1 | Overland routing switch |
| `CHANRTSWCRT` | int | 1 | Channel routing switch |
| `GWBASESWCRT` | int | 4 | GW bucket switch |
| `RT_OPTION` | int | 1 | Routing scheme (1=Muskingum) |
| `CHANNEL_OPTION` | int | 2 | Channel connectivity |
| `UDMP_OPT` | int | 1 | User-defined mapping |
| `out_dt` | int | 60 | Hydro output frequency (min) |
| `rst_dt` | int | 1440 | Restart output frequency (min) |
| `CHRTOUT_DOMAIN` | int | 1 | Enable channel output |
| `CHANOBS_DOMAIN` | int | 1 | Enable gage output |
| `RTOUT_DOMAIN` | int | 1 | Enable terrain routing output |
| `outlake` | int | 1 | Enable lake output |
| `output_gw` | int | 1 | Enable GW output |
| `route_link_f` | char | "Route_Link.nc" | Channel parameter file |
| `route_lake_f` | char | "LAKEPARM.nc" | Lake parameter file |
| `gwbasmskfil` | char | "GWBASINS.nc" | GW basin mask file |

> **🤖 ML Analogy**: Namelists are WRF-Hydro's **YAML config files**. `namelist.hrldas` = training config (epochs, learning rate, batch size), `hydro.namelist` = model architecture config (layers, channels, activation functions).

---

## 23. 🔨 Build System & Dependencies

### 🔹 CMake Build (Preferred since v5.4.0)

```bash
# Build commands
cd wrf_hydro_nwm_public
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Output: build/Run/wrf_hydro (executable)
```

### 🔹 Compile-Time Options

| Option | Default | Description |
|--------|---------|-------------|
| `WRF_HYDRO` | 1 | Enable WRF-Hydro (always 1) |
| `HYDRO_D` | 0 | Enhanced diagnostic output |
| `SPATIAL_SOIL` | 1 | Spatially distributed soil parameters |
| `WRF_HYDRO_NUDGING` | 0 | Streamflow data assimilation |
| `NCEP_WCOSS` | 0 | NOAA supercomputer compilation |
| `NWM_META` | 0 | NWM-style output metadata |
| `WRF_HYDRO_NUOPC` | 0 | NUOPC coupling (experimental) |
| `PRECIP_DOUBLE` | 0 | Double precipitation (debug) |

### 🔹 Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| **Fortran Compiler** | gfortran 11+, ifort 2023+ | Compile Fortran 90 code |
| **MPI** | OpenMPI 4+, MPICH 3+ | Parallelization (required even for serial!) |
| **NetCDF-Fortran** | 4.5+ | Read/write NetCDF files |
| **NetCDF-C** | 4.7+ | Underlying C library |
| **CMake** | 3.10+ | Build system |

### 🔹 Build Dependency Tree

```
Libraries compiled in order:
━━━━━━━━━━━━━━━━━━━━━━━━━━

1. MPP (mpp_land, hashtable)           ← MPI symbols first
2. Utils (versioning)                   ← Utilities
3. IO (netcdf_layer)                   ← NetCDF interface
4. OrchestratorLayer (config)          ← Configuration types
5. Debug_Utilities                      ← Debug tools
6. Routing/Overland (overland_struct)   ← Surface routing types
7. Routing/Subsurface (subsurface)     ← Underground routing types
8. Routing/Reservoirs (levelpool)      ← Lake routing
9. Routing/Diversions                  ← Channel diversions
10. Data_Rec (RT_FIELD, namelists)     ← Master state type
11. Routing (channel, GW, I/O)        ← Routing physics + I/O
12. HYDRO_drv (HYDRO driver)           ← Main driver
13. CPL (coupling layers)              ← WRF/NUOPC interfaces
14. nudging (optional)                 ← Data assimilation
15. Land_models/NoahMP                 ← Land surface model

Final link: all → wrf_hydro executable
```

### 🔹 Our Build Environment (conda: wrfhydro-bmi)

| Component | Version |
|-----------|---------|
| gfortran | 14.3.0 (conda-forge) |
| OpenMPI | 5.0.8 |
| NetCDF-Fortran | 4.6.2 |
| NetCDF-C | 4.9.3 |
| CMake | 3.31.1 |
| bmi-fortran | 2.0.3 |

---

## 24. 🖥️ MPI Parallelization

### 🔹 How WRF-Hydro Parallelizes

WRF-Hydro uses **geographic domain decomposition** — the spatial grid is split into tiles, and each MPI process handles one tile.

> **🤖 ML Analogy**: This is like **data parallelism** in distributed training. Each GPU (MPI rank) processes a portion of the batch (spatial domain), and they synchronize at boundaries (halo exchange = gradient all-reduce).

### 🔹 Domain Decomposition

```
    Full Domain (IXRT × JXRT)
    ┌──────┬──────┬──────┐
    │      │      │      │
    │ Rank │ Rank │ Rank │
    │  0   │  1   │  2   │
    │      │      │      │
    ├──────┼──────┼──────┤  Each rank has "halo" cells
    │      │      │      │  shared with neighbors for
    │ Rank │ Rank │ Rank │  boundary communication
    │  3   │  4   │  5   │
    │      │      │      │
    └──────┴──────┴──────┘

    Halo exchange: each rank shares boundary
    rows/columns with adjacent ranks via MPI
```

### 🔹 Key MPI Patterns

| Pattern | Description |
|---------|-------------|
| **Domain decomposition** | Grid split into rectangular tiles |
| **Halo exchange** | Boundary arrays shared between neighbors |
| **ReachLS decomposition** | Separate decomposition for channel reaches |
| **GW bucket decomposition** | Basins distributed across ranks |
| **I/O rank** | Rank 0 typically handles all file I/O |

### 🔹 For Our BMI Wrapper

We start with **serial mode only** (1 MPI rank). This means:
- `rt_domain(1)` contains the entire domain
- No halo exchange needed
- All I/O on single process
- Simplest possible implementation

---

## 25. 🔗 Coupling Capabilities

### 🔹 Available Coupling Interfaces

```
                    ┌─────────────┐
                    │   WRF ATM   │
                    │  (Weather)  │
                    └──────┬──────┘
                           │ WRF_cpl/
                    ┌──────▼──────┐
                    │             │
    CLM_cpl/ ──────►│  WRF-Hydro  │◄────── LIS_cpl/
    (CLM LSM)       │   (Core)    │        (LIS LSM)
                    │             │
    NUOPC_cpl/ ────►│             │◄────── NoahMP_cpl/
    (ESMF/NEMS)     └──────┬──────┘        (Standalone)
                           │
                    ┌──────▼──────┐
                    │   SCHISM    │  (via NUOPC or BMI)
                    │  (Coastal)  │
                    └─────────────┘
```

| Coupling | Interface | Status | Purpose |
|----------|-----------|--------|---------|
| 🌤️ **WRF** | `CPL/WRF_cpl/` | ✅ Production | Atmosphere-hydrology feedback |
| 🌊 **SCHISM** | NUOPC / BMI | ✅ / 🔨 | Coastal-riverine compound flooding |
| 🌍 **NUOPC/ESMF** | `CPL/NUOPC_cpl/` | ⚠️ Experimental | Earth system model coupling |
| 🌱 **CLM** | `CPL/CLM_cpl/` | ⚠️ Experimental | Alternative land surface model |
| 📡 **LIS** | `CPL/LIS_cpl/` | ⚠️ Experimental | NASA Land Information System |
| 🏞️ **RAPID** | External | ✅ Available | Alternative river routing |
| 📊 **DART** | External | ✅ Available | Ensemble data assimilation |
| 🔧 **NextGen** | BMI 2.0 | 🔨 In progress | NOAA next-gen water modeling framework |

### 🔹 The Coupling We're Building

```
    WRF-Hydro (our BMI wrapper)          SCHISM (existing BMI)
    ┌──────────────────────┐            ┌──────────────────────┐
    │                      │            │                      │
    │  bmi_wrf_hydro.f90   │            │  bmischism.f90       │
    │                      │            │                      │
    │  OUTPUT:             │            │  INPUT:              │
    │  channel_water__     │───────────►│  channel_water__     │
    │  volume_flow_rate    │ discharge  │  volume_flow_rate    │
    │  (QLINK, m³/s)      │            │  (Q_bnd, m³/s)      │
    │                      │            │                      │
    │  INPUT:              │            │  OUTPUT:             │
    │  sea_water_surface__ │◄───────────│  sea_water_surface__ │
    │  elevation           │ water level│  elevation           │
    │  (ETA2, m)           │            │  (ETA2, m)           │
    │                      │            │                      │
    └──────────────────────┘            └──────────────────────┘
              ▲                                    ▲
              │         Layer 3: Babelizer          │
              │    (Fortran → Python wrappers)      │
              │                                    │
              └────────────┬───────────────────────┘
                           │
                    ┌──────▼──────┐
                    │    PyMT     │  Layer 4: Coupling framework
                    │ (Python)    │  Grid mapping + time sync
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  Jupyter    │  Layer 5: ~20 lines of Python
                    │  Notebook   │
                    └─────────────┘
```

---

## 26. 🔗 Repository & Resources

### 🔹 Official Repositories

| Resource | URL |
|----------|-----|
| 🏠 GitHub Repository | `https://github.com/NCAR/wrf_hydro_nwm_public` |
| 📖 Documentation (ReadTheDocs) | `https://wrf-hydro.readthedocs.io/` |
| 🌐 Project Website | `https://ral.ucar.edu/projects/wrf_hydro` |
| 📄 V5.1.1 Technical Description (PDF) | `https://ral.ucar.edu/sites/default/files/docs/water/wrf-hydro-v511-technical-description.pdf` |
| 📄 V5 Technical Description (PDF) | `https://ral.ucar.edu/sites/default/files/public/WRF-HydroV5TechnicalDescription.pdf` |

### 🔹 Training & Tools

| Resource | URL |
|----------|-----|
| 📓 Training Notebooks | `https://github.com/NCAR/wrf_hydro_training` |
| 🐳 Docker Training | `https://github.com/NCAR/wrf_hydro_docker` |
| 📊 R Tools (rwrfhydro) | `https://github.com/NCAR/rwrfhydro` |
| 🗺️ GIS Preprocessor (Python) | `https://github.com/NCAR/wrf_hydro_gis_preprocessor` |
| 🗺️ GIS Preprocessor (ArcGIS) | `https://github.com/NCAR/wrf_hydro_arcgis_preprocessor` |

### 🔹 Community & Data

| Resource | URL |
|----------|-----|
| 💬 User Forum (Google Groups) | `https://groups.google.com/a/ucar.edu/g/wrf-hydro_users` |
| 📧 Team Email | wrfhydro@ucar.edu |
| 🗺️ CUAHSI Domain Subsetter | `https://subset.cuahsi.org/` |
| 📡 NWM Data (NOMADS) | `https://www.nco.ncep.noaa.gov/pmb/products/nwm/` |
| ☁️ NWM Data (AWS) | `https://registry.opendata.aws/noaa-nwm-pds/` |
| 📊 CSDMS Model Page | `https://csdms.colorado.edu/wiki/Model:WRF-Hydro` |

### 🔹 Key Publications

| Paper | Details |
|-------|---------|
| 📖 **Gochis et al. (2020)** | "The WRF-Hydro modeling system technical description, (Version 5.1.1)." NCAR Technical Note. 107 pages. |
| 📖 **Cosgrove et al. (2024)** | "NOAA's National Water Model." JAWRA. DOI: 10.1111/1752-1688.13184 |
| 📖 **Niu et al. (2011)** | Noah-MP land surface model description |
| 📖 **Julien et al. (1995)** | CASC2D overland flow formulation |
| 📖 **Wigmosta et al. (1994)** | Subsurface lateral flow (DHSVM) |
| 📖 **Sengupta et al. (2021)** | Ensemble streamflow data assimilation with WRF-Hydro and DART |

---

## 27. 📊 Summary & Key Numbers

### 🔹 WRF-Hydro at a Glance

| Category | Detail |
|----------|--------|
| **Full Name** | Weather Research and Forecasting Model — Hydrological Extension |
| **Developer** | NCAR Research Applications Laboratory |
| **First Version** | 2003 (as "Noah-distributed") |
| **Current Version** | v5.4.0 (January 2025) |
| **Language** | Fortran 90 |
| **Source Files** | 235 Fortran files |
| **License** | Custom UCAR (open source) |
| **Operational Deployment** | NOAA National Water Model (since 2016) |

### 🔹 Physics Summary

| Component | Method | Resolution |
|-----------|--------|-----------|
| 🌱 Land Surface | Noah-MP (4 soil layers, multi-layer snow) | 1 km |
| 🏔️ Overland Flow | Diffusive wave + Manning's equation | 250 m |
| 💧 Subsurface Flow | DHSVM Dupuit-Forchheimer | 250 m |
| 🏞️ Channel Routing | Muskingum-Cunge (NWM) or Diffusive wave | Vector reaches |
| 🌊 Groundwater | Exponential bucket model | Per basin |
| 🏗️ Lakes/Reservoirs | Level-pool (weir + orifice) | Per lake |

### 🔹 Key Numbers

| Metric | Value |
|--------|-------|
| 📏 LSM grid resolution | 1 km |
| 📏 Routing grid resolution | 250 m |
| 🏞️ NWM river reaches | 2.7 million |
| 🏗️ NWM reservoirs | 5,000+ |
| 📍 USGS gauges assimilated | ~7,000 |
| ⏱️ Land surface timestep | 3600 s (1 hour) |
| ⏱️ Routing timestep | 10-15 s |
| 🟤 Soil layers | 4 (0.1 + 0.3 + 0.6 + 1.0 = 2.0 m) |
| 🖥️ NWM CPU-hours/day | 100,000+ |
| 📄 Publications | 232 papers, 2,926 citations |
| 🧮 BMI functions needed | 41 (for our wrapper) |

### 🔹 For Our BMI Wrapper Project

```
What we're wrapping:
━━━━━━━━━━━━━━━━━━━

initialize()  →  land_driver_ini() + HYDRO_ini()
update()      →  land_driver_exe() + HYDRO_exe()
finalize()    →  HYDRO_finish()

Key variables to expose (initial 10):
  OUTPUT: QLINK, sfcheadrt, SMC, SNEQV, ACCET, T2, UDRUNOFF, SFCRUNOFF
  INPUT:  RAINRATE, ETA2

Three grids:
  Grid 0: uniform_rectilinear (1 km LSM)
  Grid 1: uniform_rectilinear (250 m routing)
  Grid 2: vector (channel network)

State access: rt_domain(1) → RT_FIELD type
```

---

> 📝 **Document Info**
> - **File**: `14_WRF_Hydro_Model_Complete_Deep_Dive.md`
> - **Project**: WRF-Hydro BMI Wrapper
> - **Location**: `bmi_wrf_hydro/Docs/`
> - **Related**: Doc 13 (SCHISM Deep Dive), Doc 7 (WRF-Hydro Beginner's Guide)
