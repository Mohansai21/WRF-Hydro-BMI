# 🌊 Doc 13: SCHISM & Its BMI — Complete Deep Dive

> 📖 **This document covers EVERYTHING about SCHISM and how its BMI was implemented.**
> Written for ML engineers with no prior oceanography background.
> Concepts only — no raw code dumps, just clear explanations with ML analogies.

---

## 📋 Table of Contents

| # | Section | Description |
|---|---------|-------------|
| **PART I** | **SCHISM — THE MODEL** | |
| 1 | [What is SCHISM?](#1--what-is-schism) | Origin, history, who built it, where it's used |
| 2 | [SCHISM Physics](#2--schism-physics--what-it-computes) | Equations, what it actually computes |
| 3 | [The Unstructured Mesh](#3--the-unstructured-mesh) | Triangle/quad hybrid grids explained |
| 4 | [Vertical Coordinate System](#4--vertical-coordinate-system) | SZ hybrid, LSC2 — unique to SCHISM |
| 5 | [Semi-Implicit Time Stepping](#5--semi-implicit-time-stepping) | Why SCHISM has NO CFL constraint |
| 6 | [SCHISM vs Other Ocean Models](#6--schism-vs-other-ocean-models) | ADCIRC, FVCOM, ROMS comparison |
| 7 | [SCHISM in NOAA Operations](#7--schism-in-noaa-operations) | STOFS-3D, NWM, NextGen |
| 8 | [SCHISM Modules & Capabilities](#8--schism-modules--capabilities) | 12 tracer + non-tracer modules |
| **PART II** | **SCHISM BMI — THE WRAPPER** | |
| 9 | [What is BMI? (Quick Recap)](#9--what-is-bmi-quick-recap) | The 41-function standard |
| 10 | [SCHISM BMI Architecture](#10--schism-bmi-architecture) | Who built it, file structure, design |
| 11 | [BMI Initialize — How SCHISM Starts](#11--bmi-initialize--how-schism-starts) | Config reading, MPI, schism_init |
| 12 | [BMI Update — How SCHISM Steps](#12--bmi-update--how-schism-steps) | One timestep execution |
| 13 | [BMI Finalize — How SCHISM Stops](#13--bmi-finalize--how-schism-stops) | Cleanup and MPI shutdown |
| 14 | [BMI Input Variables (12)](#14--bmi-input-variables-12-detailed) | All 12 inputs with full details |
| 15 | [BMI Output Variables (5)](#15--bmi-output-variables-5-detailed) | All 5 outputs with full details |
| 16 | [BMI Grid System (9 Grids)](#16--bmi-grid-system-9-grids) | Every grid explained |
| 17 | [The t0/t1 Sliding Window Pattern](#17--the-t0t1-sliding-window-pattern) | Critical temporal interpolation |
| 18 | [RAINRATE — The Special Variable](#18--rainrate--the-special-variable) | Why one variable breaks the pattern |
| 19 | [Variable Info Functions](#19--variable-info-functions) | Type, units, grid, itemsize, nbytes, location |
| 20 | [Grid Functions Deep Dive](#20--grid-functions-deep-dive) | Unstructured mesh topology via BMI |
| 21 | [Get/Set Value Patterns](#21--getset-value-patterns) | How data flows in and out |
| 22 | [Time Functions](#22--time-functions) | Start, end, current, step, units |
| 23 | [NextGen Integration](#23--nextgen-integration) | NGEN_ACTIVE, register_bmi, ISO C |
| 24 | [Build System & Configuration](#24--build-system--configuration) | CMake flags, namelist, serial/parallel |
| 25 | [Current Limitations](#25--current-limitations) | What's not working yet |
| 26 | [Repository Links & References](#26--repository-links--references) | All URLs, papers, docs |
| 27 | [Summary & Key Takeaways](#27--summary--key-takeaways) | Everything in one place |

---

# PART I: SCHISM — THE MODEL

---

## 1. 🌊 What is SCHISM?

### 📝 Full Name

**S**emi-implicit **C**ross-scale **H**ydroscience **I**ntegrated **S**ystem **M**odel

### 🎯 One-Sentence Definition

SCHISM is an open-source, community-supported, 3D coastal ocean model that simulates water levels, currents, temperature, salinity, and waves on unstructured meshes — from tiny creeks to the entire Atlantic Ocean in a single simulation.

### 🧠 ML Analogy

> Think of SCHISM as a **Graph Neural Network (GNN) simulator for water**:
>
> | ML Concept | SCHISM Equivalent |
> |-----------|-------------------|
> | Graph with variable-density nodes | Unstructured triangle/quad mesh |
> | Message passing between neighbors | Finite element/volume discretization |
> | Multi-scale feature extraction | Creek-to-ocean in one mesh (8m → 2km) |
> | Forward pass | One timestep of physics simulation |
> | Input features | Wind, rain, pressure, river discharge |
> | Output predictions | Water levels, currents, temperature |
> | Training loop | Time integration loop |
> | Inference | Forecast mode (predict future water states) |

### 👨‍🔬 Who Built SCHISM?

| Aspect | Details |
|--------|---------|
| 🏛️ **Institution** | Virginia Institute of Marine Science (VIMS), College of William & Mary |
| 👤 **Lead Developer** | Dr. Y. Joseph Zhang (Professor of Marine Science) |
| 🎓 **Education** | Ph.D. University of Wollongong, Australia (1996) |
| 📧 **Contact** | yjzhang@vims.edu |
| 🆔 **ORCID** | 0000-0002-2561-1241 |
| 🏢 **Office** | Davis Hall 224, VIMS, Gloucester Point, Virginia |

### 📜 History & Evolution

```
    1996-2008: SELFE Model (Dr. Zhang at Oregon Health & Science University)
         │
         │  Paper: Zhang & Baptista (2008), Ocean Modelling
         │  "SELFE: A semi-implicit Eulerian-Lagrangian
         │   finite-element model for cross-scale ocean circulation"
         │
         ▼
    2014: Dr. Zhang moves to VIMS
         │
         │  Forks SELFE v3.1dc → Major upgrades begin
         │
         ▼
    2016: SCHISM Released
         │
         │  Paper: Zhang, Ye, Stanev, Grashorn (2016), Ocean Modelling
         │  "Seamless cross-scale modeling with SCHISM"
         │  Key upgrades: LSC2 vertical coords, hybrid tri-quad mesh,
         │  model polymorphism, improved transport
         │
         ▼
    2020+: Production Use
         │
         ├─ NOAA STOFS-3D-Atlantic (Jan 2023, operational)
         ├─ EPA Chesapeake Bay Phase 7 model (2022)
         ├─ Taiwan CWB ROCFORS (daily operational)
         ├─ NextGen BMI integration (2023-present)
         └─ v5.11.0 latest release (Feb 2025)
```

### 🌍 Who Uses SCHISM?

| Organization | Use Case | Scale |
|-------------|----------|-------|
| 🇺🇸 **NOAA/NOS** | STOFS-3D-Atlantic operational forecasts | 2.9M nodes, 5.6M elements |
| 🇺🇸 **NOAA/OWP** | NextGen Water Resources Framework | Experimental BMI integration |
| 🇺🇸 **US EPA** | Chesapeake Bay Phase 7 water quality | Replaces 30+ year old Bay Model |
| 🇺🇸 **Oregon DOGAMI** | Official tsunami inundation maps | NTHMP-certified |
| 🇹🇼 **Taiwan CWB** | Daily ROCFORS operational forecasts | National coverage |
| 🇩🇪 **HZG Germany** | North Sea & Baltic Sea dynamics | EU operational |
| 🇺🇸 **CA Dept. Water Resources** | Bay-Delta water quality | State-level policy |
| 🏛️ **Universities worldwide** | Research: storm surge, flooding, ecology | Various scales |

### 📊 SCHISM by the Numbers

| Metric | Value |
|--------|-------|
| 📦 Source files | 437+ Fortran files |
| ⭐ GitHub stars | 125+ |
| 🔀 GitHub forks | 106+ |
| 👥 Contributors | 43+ |
| 📝 Total commits | 2,086+ |
| 📅 Latest release | v5.11.0 (Feb 2025) |
| 📄 License | Apache 2.0 (open source) |
| 🔧 Languages | Fortran 90/2003, C, Python |

---

## 2. 🔬 SCHISM Physics & What It Computes

### 🌊 Core Equations

SCHISM solves the **3D Reynolds-averaged Navier-Stokes equations** in hydrostatic form. In simple terms:

| Equation | What It Describes | ML Analogy |
|----------|-------------------|------------|
| 📐 **Continuity** | Conservation of water mass — water can't appear/disappear | Like batch normalization — conserving total activation |
| ➡️ **Momentum (x)** | East-west water acceleration from forces | Like horizontal gradient update in optimizer |
| ⬆️ **Momentum (y)** | North-south water acceleration from forces | Like vertical gradient update in optimizer |
| ⬇️ **Vertical velocity** | Up-down water movement | Like skip connections propagating info vertically |
| 🌡️ **Transport** | Movement of heat, salt, tracers | Like feature propagation through network layers |
| 📊 **Equation of State** | Density from temperature + salinity | Like activation function — transforms inputs to density |

### 📐 The Governing Equations (Conceptual)

```
    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │  CONTINUITY (Mass Conservation):                            │
    │  ∂η/∂t + ∇·(∫u dz) = sources - sinks                      │
    │     ▲         ▲            ▲         ▲                      │
    │     │         │            │         │                      │
    │  water     depth-       river     evaporation               │
    │  level    integrated   discharge                            │
    │  change   velocity                                          │
    │                                                             │
    │  MOMENTUM (Force Balance):                                  │
    │  ∂u/∂t = -g∇η + wind_stress + Coriolis + mixing - friction │
    │    ▲       ▲        ▲           ▲         ▲         ▲       │
    │    │       │        │           │         │         │       │
    │  accel.  gravity   wind      Earth's   turbulent  bottom   │
    │          pushing   pushing   rotation  diffusion  drag     │
    │          water     water                                    │
    │                                                             │
    │  TRANSPORT (Tracer Movement):                               │
    │  ∂T/∂t + u·∇T = ∇·(K∇T) + sources                         │
    │    ▲      ▲        ▲          ▲                             │
    │    │      │        │          │                             │
    │  tracer  advection diffusion  heating/                     │
    │  change  (carrying) (mixing)  cooling                      │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘
```

### 🎯 What SCHISM Actually Computes

```
    ┌─────────────────────────────────────────────────────────────┐
    │                     INPUTS → ENGINE → OUTPUTS               │
    ├─────────────────────────────────────────────────────────────┤
    │                                                             │
    │  INPUTS (Forcing):              OUTPUTS (Predictions):      │
    │  ├─ 💨 Wind speed & direction   ├─ 🌊 Water surface level  │
    │  ├─ 📊 Atmospheric pressure     │     (η or ETA2)          │
    │  ├─ 🌡️ Air temperature          ├─ ➡️ Current velocity     │
    │  ├─ 💧 Humidity                  │     (u, v, w)            │
    │  ├─ 🌧️ Rainfall                 ├─ 🌡️ Water temperature    │
    │  ├─ 🏞️ River discharge          ├─ 🧂 Salinity             │
    │  ├─ 🌊 Ocean boundary tides     ├─ 🔄 Turbulent mixing     │
    │  └─ 🏖️ Bathymetry (fixed)       ├─ 🌊 Wetting/drying      │
    │                                  ├─ 📊 Wave parameters      │
    │                                  ├─ 🏔️ Sediment transport   │
    │                                  └─ 🐟 Water quality        │
    │                                                             │
    │  TIME STEPPING:                                             │
    │  ├─ Typical dt: 120-300 seconds                             │
    │  ├─ Simulation length: hours to months                      │
    │  └─ Output frequency: every N steps                         │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘
```

### 🔑 Physical Processes Handled

| Process | Description | When It Matters |
|---------|-------------|-----------------|
| 🌊 **Tides** | Gravitational pull of moon/sun | Always (oceanic domains) |
| 🌪️ **Storm surge** | Wind/pressure pushing water onshore | Hurricanes, nor'easters |
| 🏞️ **River plumes** | Freshwater spreading into saltwater | Estuaries, deltas |
| 🌡️ **Thermal stratification** | Warm water on top, cold below | Lakes, deep water |
| 🧂 **Salinity intrusion** | Saltwater moving upstream | Droughts, sea level rise |
| 💨 **Wind-driven currents** | Surface currents from wind stress | Open ocean, large lakes |
| 🌍 **Coriolis effect** | Earth's rotation deflecting currents | Large domains only |
| 🏖️ **Wetting/drying** | Water flooding/receding from land | Coastal flooding, marshes |
| 🌱 **Vegetation drag** | Plants slowing water flow | Wetlands, marshes |
| 🌊 **Waves** | Wind-generated surface waves | Coupled with WWM-III |

---

## 3. 🔺 The Unstructured Mesh

### 🎯 What Is It?

SCHISM uses an **unstructured mesh** — a collection of triangles and quadrilaterals that tile the domain. Unlike a regular grid (same spacing everywhere), an unstructured mesh allows variable resolution.

### 🧠 ML Analogy: CNN vs GNN

```
    REGULAR GRID (WRF-Hydro = CNN):       UNSTRUCTURED MESH (SCHISM = GNN):

    ┌──┬──┬──┬──┬──┬──┐                  *─────────*─────*
    │  │  │  │  │  │  │                  /\        / \   / \
    ├──┼──┼──┼──┼──┼──┤                /  \      /   \ /   \
    │  │  │  │  │  │  │              *────*────*─────*─────*
    ├──┼──┼──┼──┼──┼──┤               \  /\  / \  / \  /
    │  │  │  │  │  │  │                \/  \/   \/   \/
    ├──┼──┼──┼──┼──┼──┤              *──*──*──*──*──*──*
    │  │  │  │  │  │  │               \/\/\/\/\/\/\/\/
    └──┴──┴──┴──┴──┴──┘              *──*──*──*──*──*──*

    Same resolution everywhere         Fine near coast (8m!)
    (1km or 250m)                      Coarse in deep ocean (2km)
    Wastes compute on "boring"         Focuses compute where
    open-ocean areas                   physics are complex
```

### 🔺 Triangles vs Quads

SCHISM uniquely supports **BOTH** triangle and quadrilateral elements in the same mesh:

```
    TRIANGLE (i34 = 3):              QUAD (i34 = 4):
    3 nodes, 3 edges                 4 nodes, 4 edges

         *                           *─────────*
        / \                          │         │
       /   \                         │         │
      /     \                        │         │
     *───────*                       *─────────*

    Better for:                      Better for:
    ├─ Complex coastlines            ├─ Channels & rivers
    ├─ Irregular boundaries          ├─ Straight boundaries
    └─ Transition zones              └─ Higher accuracy per element
```

### 📊 Mesh Terminology

| Term | Definition | ML Analogy |
|------|-----------|------------|
| **Node** | A point/vertex in the mesh | Graph node in GNN |
| **Edge/Side** | Line connecting two nodes | Edge in graph |
| **Element/Face** | Triangle or quad defined by 3-4 nodes | "Pixel" equivalent |
| **i34** | Array indicating element type (3=tri, 4=quad) | Node degree/type |
| **elnode** | Which nodes form each element | Adjacency list |
| **isidenode** | Which nodes form each edge | Edge index |
| **elside** | Which edges form each element | Face-to-edge mapping |

### 📐 Variable Staggering (Where Things Are Computed)

```
    SCHISM uses an Arakawa-like staggering:

    Node (vertex):                  Element center:
    ├─ Water surface elevation η    ├─ Vertical velocity w
    ├─ Horizontal coordinates       ├─ Tracer concentrations
    └─ Depth                        └─ (finite-volume method)

    Side center (edge midpoint):
    └─ Horizontal velocities (u, v)

    ┌─────────────────────────────────┐
    │        * η, depth               │
    │       / \                       │
    │  u,v /   \ u,v                  │
    │     /  ●  \    ● = w, T, S      │
    │    / tracer\                    │
    │   *─────────*                   │
    │       u,v                       │
    └─────────────────────────────────┘
```

### 📏 Real-World Mesh Scales (STOFS-3D-Atlantic)

| Feature | Resolution | Node Count |
|---------|-----------|------------|
| 🏖️ Shoreline | 1.5-2 km | |
| 🏘️ Floodplain | 600 m | |
| 🏞️ Major rivers | 50-100 m | |
| 🏞️ Watershed rivers | 8 m (!) | |
| 🏗️ Levees | 2-10 m | |
| **Total** | Variable | **2,926,236 nodes** |
| **Total elements** | Variable | **5,654,157 elements** |

### 📁 Grid Input Files

| File | Purpose | Format |
|------|---------|--------|
| `hgrid.gr3` | Horizontal grid (Cartesian coords) | Text: node coords + element connectivity |
| `hgrid.ll` | Horizontal grid (lon/lat coords) | Same format, geographic coords |
| `vgrid.in` | Vertical grid definition | S-levels or SZ-hybrid levels |

---

## 4. 📐 Vertical Coordinate System

### 🎯 The Problem

Ocean depth varies enormously — from 1m in marshes to 5,000m in deep ocean. The vertical grid must handle this range without losing accuracy.

### 🔧 SCHISM's Two Options

#### Option A: SZ Hybrid (Sigma + Z-levels)

```
    Shallow area (10m):           Deep area (1000m):

    ── sea surface ──             ── sea surface ──
    ├─ σ layer 1                  ├─ σ layer 1     ┐
    ├─ σ layer 2                  ├─ σ layer 2     │ Sigma
    ├─ σ layer 3                  ├─ σ layer 3     │ (terrain-
    ├─ σ layer 4                  ├─ σ layer 4     ┘ following)
    ── bottom ──                  ├─────────────── h_s demarcation
                                  ├─ Z layer 5     ┐
    σ layers follow the           ├─ Z layer 6     │ Z-levels
    terrain shape                 ├─ Z layer 7     │ (fixed
    (good for shallow)            ├─ Z layer 8     │ depth)
                                  ├─ Z layer 9     ┘
                                  ── bottom ──
```

#### Option B: LSC2 (Unique to SCHISM!)

**Localized Sigma Coordinates with Shaved Cell** — each node gets its OWN vertical grid:

```
    Node A (shallow):     Node B (mid-depth):     Node C (deep):

    ── surface ──         ── surface ──            ── surface ──
    ├─ level 1            ├─ level 1               ├─ level 1
    ├─ level 2            ├─ level 2               ├─ level 2
    ── bottom ──          ├─ level 3               ├─ level 3
    (only 2 levels!)      ├─ level 4               ├─ level 4
                          ── bottom ──             ├─ level 5
                          (4 levels)               ├─ level 6
                                                   ├─ level 7
                                                   ── bottom ──
                                                   (7 levels)

    Each node has a DIFFERENT number of vertical levels!
    No other ocean model can do this.
```

> **ML Analogy:** LSC2 is like **adaptive computation** in neural networks — more layers where needed (deep water), fewer layers where not (shallow water). Similar to early-exit networks or mixture-of-depths.

---

## 5. ⚡ Semi-Implicit Time Stepping

### 🎯 The Key Innovation

Most ocean models use **explicit** time stepping which has a **CFL stability constraint** — you MUST use small enough time steps or the simulation "explodes." SCHISM uses **semi-implicit** stepping which has **NO CFL constraint**.

### 📊 CFL Constraint Explained

```
    CFL number = (velocity × dt) / dx

    EXPLICIT models (ADCIRC, FVCOM):
    ├─ CFL MUST be < 1.0 for stability
    ├─ Fine mesh (dx = 10m) with fast flow (v = 2 m/s):
    │   dt < dx/v = 10/2 = 5 seconds maximum!
    └─ This is very expensive computationally

    SEMI-IMPLICIT (SCHISM):
    ├─ CFL can be > 1.0 — NO upper limit
    ├─ Same fine mesh: dt = 120-300 seconds works fine!
    └─ 10-100x fewer time steps than explicit models

    ⚠️ COUNTERINTUITIVE: SCHISM actually WANTS large CFL!
    When CFL < 0.4, numerical diffusion INCREASES (bad)
    Large time steps = less diffusion = better accuracy
```

> **ML Analogy:** Think of explicit vs implicit like learning rates:
> - Explicit = SGD with strict max learning rate — go too fast and loss explodes
> - Semi-implicit = Adam with adaptive lr — inherently stable, can use large steps

### 🔧 How Semi-Implicit Works

```
    EXPLICIT (simple but limited):        SEMI-IMPLICIT (SCHISM):

    η(t+dt) = η(t) + dt * f(η(t))        η(t+dt) = η(t) + dt * f(η(t+dt))
                    ▲                                            ▲
                    │                                            │
            Uses ONLY old                               Uses NEW (unknown)
            values                                      values
            = easy to compute                           = requires solving
            = conditionally stable                        a linear system
                                                        = UNCONDITIONALLY stable
```

### 🔄 The Eulerian-Lagrangian Method (ELM)

For advection (carrying things with the flow), SCHISM uses ELM:

```
    Step 1: BACKTRACKING (Lagrangian)
    ─────────────────────────────────
    From current position, trace BACKWARD along the flow
    to find where the water "came from":

    Current time (t+dt):    *  ← Where is the water now?
                           /
                          / ← Trace back along flow
                         /
    Previous time (t):  ●  ← Where did it come from? (FOCL)


    Step 2: INTERPOLATION (Eulerian)
    ─────────────────────────────────
    Interpolate the value at the "foot of characteristic line" (FOCL)
    using the surrounding grid nodes.

    This method is unconditionally stable for ANY time step!
```

> **ML Analogy:** ELM is like **attention mechanism** — instead of processing data on a fixed grid, it looks back to find the most relevant previous information (the FOCL), then interpolates. Like computing Q, K, V but for fluid dynamics.

---

## 6. 🏆 SCHISM vs Other Ocean Models

### 📊 Detailed Comparison Table

| Feature | 🌊 SCHISM | ⚡ ADCIRC | 🔺 FVCOM | 📐 ROMS |
|---------|----------|----------|---------|--------|
| **Grid Type** | Hybrid tri+quad (unstructured) | Triangles only (unstructured) | Triangles only (unstructured) | Regular rectangular (structured) |
| **Time Stepping** | Semi-implicit | Explicit | Explicit | Mode-split (baro/baroclinic) |
| **CFL Constraint** | ❌ **None** | ✅ Required | ✅ Required | ✅ Required |
| **Max dt (fine mesh)** | 120-300s | 1-10s | 1-10s | 10-60s |
| **Vertical Coords** | LSC2/SZ (node-specific!) | Sigma only | Sigma | Terrain-following s-coord |
| **Model Polymorphism** | ✅ 1D+2D+3D in one domain | 2D or 3D | 3D only | 3D only |
| **Wetting/Drying** | ✅ Natural (built-in) | ⚠️ Special treatment | ✅ Supported | ⚠️ Limited |
| **Cross-Scale** | ✅ Creek-to-ocean (8m → 2km) | ⚠️ Limited range | ⚠️ Limited range | ❌ Fixed resolution |
| **Compound Flooding** | ✅ Full support | ⚠️ Limited | ⚠️ Limited | ❌ No |
| **Wave Coupling** | ✅ WWM-III built-in | ✅ SWAN coupling | ✅ FVCOM-SWAVE | ✅ COAWST |
| **BMI Support** | ✅ (LynkerIntel) | ❌ No | ❌ No | ❌ No |
| **NOAA Operational** | ✅ STOFS-3D-Atlantic | ✅ ETSS, ESTOFS | ✅ NGOFS2 | ✅ CBOFS, DBOFS |
| **Primary Developer** | VIMS (Y.J. Zhang) | UNC (R. Luettich) | UMass (C. Chen) | Rutgers (H. Shchepetkin) |

### 🏆 SCHISM's Unique Advantages

```
    1. ⚡ NO CFL CONSTRAINT
       └─ 10-100x larger time steps = 10-100x faster
          (for same mesh resolution)

    2. 🔺 HYBRID TRI-QUAD MESH
       └─ Only SCHISM can mix triangles and quads
          Quads for channels, triangles for coastlines

    3. 📐 LSC2 VERTICAL COORDS
       └─ Each node has its own vertical grid
          No other ocean model has this flexibility

    4. 🔄 MODEL POLYMORPHISM
       └─ 1D rivers + 2D floodplains + 3D estuaries
          ALL in one simulation

    5. 🌊 SEAMLESS CROSS-SCALE
       └─ 8m river resolution to 2km open ocean
          in a single mesh, single simulation
```

---

## 7. 🏛️ SCHISM in NOAA Operations

### 🌊 STOFS-3D-Atlantic (Operational Since Jan 2023)

| Aspect | Details |
|--------|---------|
| 📅 **Operational since** | January 2023 |
| ⏰ **Run schedule** | Daily at 12 UTC |
| 🔮 **Forecast** | 24-hour nowcast + up to 96-hour forecast |
| 📊 **Outputs** | Water level, 2D/3D temperature, salinity, currents |
| 🗺️ **Domain** | US Atlantic coast + Gulf of Mexico |
| 📐 **Grid** | 2.9M nodes, 5.6M elements |
| 📏 **Resolution** | 8m (rivers) to 2km (shoreline) |
| 🏞️ **Hydrology** | Uses National Water Model (NWM) outputs |
| 🏗️ **Developed by** | NOAA/NOS + NWS/NCEP + VIMS jointly |

### 🔗 NextGen Framework Integration

```
    ┌──────────────────────────────────────────────────────┐
    │           NOAA NextGen Framework                      │
    │                                                      │
    │  ┌─────────┐   ┌─────────┐   ┌─────────────┐       │
    │  │  NWM    │   │ T-Route │   │   SCHISM     │       │
    │  │(inland) │──►│(routing)│──►│  (coastal)   │       │
    │  │  BMI    │   │  BMI    │   │    BMI       │       │
    │  └─────────┘   └─────────┘   └─────────────┘       │
    │       ▲              ▲              ▲                │
    │       │              │              │                │
    │       └──────────────┴──────────────┘                │
    │              ngen framework                          │
    │          (BMI-based coupling)                        │
    └──────────────────────────────────────────────────────┘

    GitHub Issue: NOAA-OWP/ngen#547
    "Evaluating SCHISM BMI as a NextGen Formulation"
    Status: Open (experimental, in development)
    Key person: Jason Ducker (NOAA/NWS), Phil Miller
```

### 🔄 ESMF vs BMI (Two Coupling Approaches)

| Aspect | ESMF (Production) | BMI (Experimental) |
|--------|-------------------|-------------------|
| **Purpose** | NOAA operational coupling | NextGen framework integration |
| **Maturity** | ✅ Production-ready | ⚠️ Experimental |
| **Complexity** | High (NUOPC cap, ESMF library) | Low (41 functions, simple API) |
| **Coupling** | SCHISM ↔ WW3, NWM via NUOPC | SCHISM ↔ ngen via BMI |
| **Use case** | STOFS-3D-Atlantic daily ops | Research, future NWM v3.0 |
| **Validation** | Fully validated | Partially validated |

---

## 8. 📦 SCHISM Modules & Capabilities

### 🧪 12 Tracer Modules

| # | Module | Full Name | What It Computes |
|---|--------|-----------|------------------|
| 1 | 🌡️ **TEM** | Temperature | Water temperature distribution |
| 2 | 🧂 **SAL** | Salinity | Salt concentration |
| 3 | 📊 **GEN** | Generic Tracer | User-customizable passive tracer |
| 4 | ⏳ **AGE** | Water Age | How long water has been in domain |
| 5 | 🏔️ **SED3D** | 3D Sediment | Non-cohesive sediment transport |
| 6 | 🐟 **EcoSim** | Ecological Simulation | Marine ecosystem (Paul Bissett) |
| 7 | 🧫 **ICM** | CE-QUAL-ICM | USACE water quality model |
| 8 | 🌿 **CoSINE** | C-Si-N Ecosystem | Carbon, Silicate, Nitrogen |
| 9 | 🦠 **FIB** | Fecal Indicator Bacteria | Bacteria tracking |
| 10 | ⏸️ **TIMOR** | - | Currently inactive |
| 11 | 🔬 **FABM** | Aquatic BGC Framework | Generic biogeochemistry |
| 12 | 📈 **DVD** | Numerical Mixing | Mixing analysis diagnostic |

### 🌊 Non-Tracer Modules

| Module | What It Does |
|--------|-------------|
| 🏖️ **SED2D** | 2D sediment transport (morphodynamics) |
| 🚧 **Hydraulics** | Culverts, weirs, hydraulic structures |
| 📍 **Particle Tracking** | Lagrangian particle trajectories |
| 🌊 **WWM-III** | Spectral wind wave model (fully coupled) |
| 🧊 **Ice** | Single-class sea ice model |
| 🧊 **Multi_ice** | Multi-class sea ice (thickness categories) |
| 🌿 **TMM** | Tidal marsh migration |
| 📊 **PDAF** | Data assimilation framework |
| 🔍 **Analysis** | Flow/stress derived quantities |
| 🌀 **PaHM** | Parametric hurricane model |

---

# PART II: SCHISM BMI — THE WRAPPER

---

## 9. 🔌 What is BMI? (Quick Recap)

### 🎯 Definition

**BMI (Basic Model Interface)** is a standardized API with **41 functions** that any model implements to become "BMI-compliant." It's created by CSDMS (Community Surface Dynamics Modeling System) at CU Boulder.

### 📦 The 41 Functions

```
    ┌──────────────────────────────────────────────────────┐
    │              BMI 2.0 — 41 Functions                   │
    ├──────────────────────────────────────────────────────┤
    │  🎮 CONTROL (4)           │  📊 MODEL INFO (5)       │
    │  ├─ initialize            │  ├─ get_component_name   │
    │  ├─ update                │  ├─ get_input_item_count │
    │  ├─ update_until          │  ├─ get_output_item_count│
    │  └─ finalize              │  ├─ get_input_var_names  │
    │                           │  └─ get_output_var_names │
    ├───────────────────────────┼──────────────────────────┤
    │  📏 VAR INFO (6)          │  ⏰ TIME (5)             │
    │  ├─ get_var_type          │  ├─ get_current_time     │
    │  ├─ get_var_units         │  ├─ get_start_time       │
    │  ├─ get_var_grid          │  ├─ get_end_time         │
    │  ├─ get_var_itemsize      │  ├─ get_time_step        │
    │  ├─ get_var_nbytes        │  └─ get_time_units       │
    │  └─ get_var_location      │                          │
    ├───────────────────────────┼──────────────────────────┤
    │  📤📥 GET/SET (5)         │  🗺️ GRID (17)            │
    │  ├─ get_value             │  ├─ get_grid_type        │
    │  ├─ set_value             │  ├─ get_grid_rank/size   │
    │  ├─ get_value_ptr         │  ├─ shape/spacing/origin │
    │  ├─ get_value_at_indices  │  ├─ get_grid_x/y/z      │
    │  └─ set_value_at_indices  │  ├─ node/edge/face_count │
    │                           │  ├─ edge_nodes           │
    │                           │  ├─ face_nodes/edges     │
    │                           │  └─ nodes_per_face       │
    └───────────────────────────┴──────────────────────────┘
```

---

## 10. 🏗️ SCHISM BMI Architecture

### 👷 Who Built It?

| Aspect | Details |
|--------|---------|
| 🏢 **Organization** | LynkerIntel (Lynker Intelligence) |
| 🎯 **Purpose** | Enable SCHISM in NOAA NextGen framework |
| 📦 **Repository** | github.com/LynkerIntel/SCHISM_BMI |
| 🌿 **Branch** | bmi-integration-master |
| 📝 **Main file** | `src/BMI/bmischism.f90` (1,729 lines) |
| 📄 **License** | Apache 2.0 |
| 📊 **Commits** | 1,540+ |

### 📁 File Structure

```
    SCHISM_BMI/src/BMI/
    ├── bmischism.f90                    ← 🔑 Main BMI wrapper (1,729 lines)
    │   └── module bmischism
    │       └── type, extends(bmi) :: bmi_schism
    │           └── 41+ BMI procedures
    │
    ├── schism_model_container.f90       ← 📦 Config container (51 lines)
    │   └── module schism_model_container
    │       └── type :: schism_type
    │           └── time, config, MPI fields
    │
    ├── bmi.f90                          ← 📐 Abstract BMI interface
    │   └── module bmif_2_0
    │       └── type, abstract :: bmi
    │           └── 53 deferred procedures
    │
    ├── schism_bmi_driver_test.f90       ← 🧪 Test driver (790 lines)
    │   └── program schism_driver_test
    │       └── Tests ALL BMI functions
    │
    ├── LIMITATIONS                      ← ⚠️ Known issues
    │
    ├── CMakeLists.txt                   ← 🔨 Build config
    │   └── Builds: libschism_bmi.so + schism_bmi_driver
    │
    └── iso_c_fortran_bmi/               ← 🔗 C interop layer
        ├── src/bmi.f90                  ← Abstract interface copy
        ├── src/iso_c_bmi.f90            ← ISO C binding wrapper
        └── test/                        ← C test program
```

### 🏛️ Architecture Diagram

```
    ┌───────────────────────────────────────────────────────────┐
    │                    CALLER (NextGen / Test Driver)          │
    │  ┌─────────────────────────────────────────────────────┐ │
    │  │  type(bmi_schism) :: m                               │ │
    │  │  m%initialize("config.nml")                          │ │
    │  │  m%set_value("Q_bnd_source", discharge_data)         │ │
    │  │  m%update()                                          │ │
    │  │  m%get_value("ETA2", water_levels)                   │ │
    │  │  m%finalize()                                        │ │
    │  └──────────────────────┬──────────────────────────────┘ │
    └─────────────────────────┼────────────────────────────────┘
                              │ calls
                              ▼
    ┌─────────────────────────────────────────────────────────┐
    │              bmischism.f90 (BMI WRAPPER LAYER)           │
    │                                                         │
    │  type, extends(bmi) :: bmi_schism                       │
    │  ├─ type(schism_type) :: model   ← Config/time ONLY    │
    │  │   ├─ model_start_time, model_end_time                │
    │  │   ├─ time_step_size, iths, ntime                     │
    │  │   ├─ SCHISM_dir, SCHISM_NSCRIBES                     │
    │  │   └─ given_communicator                              │
    │  │                                                      │
    │  ├─ initialize() → read_init_config + schism_init()     │
    │  ├─ update()     → iths++ ; schism_step(iths)           │
    │  ├─ finalize()   → schism_finalize + parallel_finalize  │
    │  ├─ get_value()  → reads from schism_glbl variables     │
    │  └─ set_value()  → writes to schism_glbl variables      │
    └──────────────────────┬──────────────────────────────────┘
                           │ reads/writes
                           ▼
    ┌─────────────────────────────────────────────────────────┐
    │          SCHISM ENGINE (437+ source files)               │
    │                                                         │
    │  schism_glbl.F90 ← ALL physics state (global module)    │
    │  ├─ eta2(:)       → water surface elevation             │
    │  ├─ uu2(:,:)      → eastward velocity                   │
    │  ├─ vv2(:,:)      → northward velocity                  │
    │  ├─ dp(:)         → depth                               │
    │  ├─ windx1/2(:)   → wind at t0/t1                       │
    │  ├─ airt1/2(:)    → air temp at t0/t1                   │
    │  ├─ pr1/2(:)      → pressure at t0/t1                   │
    │  ├─ ath2(:,:,:,:) → boundary water levels                │
    │  ├─ ath3(:,:,:,:) → source/sink discharge               │
    │  └─ ...hundreds more...                                 │
    │                                                         │
    │  schism_init.F90  ← initialization (7,074 lines)        │
    │  schism_step.F90  ← one timestep (10,742 lines)         │
    │  schism_finalize.F90 ← cleanup (155 lines)              │
    └─────────────────────────────────────────────────────────┘
```

### 🔑 Key Design Decision: Global State

```
    WHY GLOBAL STATE?

    SCHISM is a massive legacy Fortran model (437 files).
    It would be impractical to refactor ALL state into a derived type.

    Instead, the BMI wrapper:
    1. Keeps a TINY container (schism_type) for config/time tracking
    2. Reads/writes DIRECTLY to schism_glbl module variables
    3. Delegates init/step/finalize to existing SCHISM subroutines

    This is the NON-INVASIVE approach — wrap without modifying!
```

> **ML Analogy:** It's like wrapping a pre-trained model with an API:
> - You don't refactor the model's internals
> - You write a thin API layer that calls model.forward() and reads model.output
> - The model's weights/state stay where they are

---

## 11. 🚀 BMI Initialize — How SCHISM Starts

### 📋 Step-by-Step Flow

```
    schism_initialize(config_file):

    ┌─────────────────────────────────────────────────────────┐
    │  Step 1: Read BMI Config File (Namelist)                │
    │  ┌───────────────────────────────────────────────────┐  │
    │  │  &test                                            │  │
    │  │    model_start_time = 0.0                         │  │
    │  │    model_end_time = 86400.0  (24 hours in sec)    │  │
    │  │    time_step_size = 3600     (1 hour in sec)      │  │
    │  │    SCHISM_dir = "/path/to/schism/run/"            │  │
    │  │    SCHISM_NSCRIBES = 0       (serial mode)        │  │
    │  │  /                                                │  │
    │  └───────────────────────────────────────────────────┘  │
    │  → Stores in this%model%model_start_time, etc.          │
    │  → Sets dt global variable = time_step_size             │
    └─────────────────────────┬───────────────────────────────┘
                              │
                              ▼
    ┌─────────────────────────────────────────────────────────┐
    │  Step 2: Compute Time Parameters                        │
    │  ├─ num_time_steps = (end - start) / time_step_size     │
    │  ├─ If both end_time and num_steps are 0: default to 24 │
    │  └─ current_model_time = 0.0                            │
    └─────────────────────────┬───────────────────────────────┘
                              │
                              ▼
    ┌─────────────────────────────────────────────────────────┐
    │  Step 3: Initialize MPI                                 │
    │  ├─ nscribes = SCHISM_NSCRIBES (from config)            │
    │  └─ call parallel_init(given_communicator)               │
    │     └─► Sets up MPI ranks, communicators                │
    └─────────────────────────┬───────────────────────────────┘
                              │
                              ▼
    ┌─────────────────────────────────────────────────────────┐
    │  Step 4: Call SCHISM's Own Init                         │
    │                                                         │
    │  #ifdef OLDIO (serial):                                 │
    │  │  call schism_init(0, SCHISM_dir, iths, ntime)        │
    │  │                                                      │
    │  #else (parallel):                                      │
    │  │  if (task_id == 1) then  ! compute process           │
    │  │    call schism_init(0, SCHISM_dir, iths, ntime)      │
    │  │  else                   ! I/O scribe process         │
    │  │    call scribe_init(SCHISM_dir, iths, ntime)         │
    │  │  endif                                               │
    │  │                                                      │
    │  └─► schism_init reads param.nml, hgrid.gr3, vgrid.in   │
    │      Allocates ALL global arrays in schism_glbl          │
    │      Sets up mesh connectivity, boundary conditions      │
    │      7,074 lines of initialization!                     │
    └─────────────────────────┬───────────────────────────────┘
                              │
                              ▼
    ┌─────────────────────────────────────────────────────────┐
    │  Step 5: Store Time Loop Variables                       │
    │  ├─ this%model%iths = iths   (starting step number)     │
    │  └─ this%model%ntime = ntime (total steps from config)  │
    └─────────────────────────────────────────────────────────┘
```

### ⚠️ Important: MPI Communicator Must Be Set BEFORE Initialize

```
    ! In the test driver, MPI comm is set BEFORE calling initialize:
    schism_mpi_comm(1) = MPI_COMM_WORLD
    status = m%set_value('bmi_mpi_comm_handle', schism_mpi_comm)  ← FIRST
    status = m%initialize(arg)                                     ← SECOND
```

---

## 12. 🔄 BMI Update — How SCHISM Steps

### 📋 update() — Single Time Step

```
    schism_update():

    ┌─────────────────────────────────────────┐
    │                                         │
    │  ! Increment timestep counter           │
    │  this%model%iths = this%model%iths + 1  │
    │                                         │
    │  ! Call SCHISM to advance one step      │
    │  call schism_step(this%model%iths)      │
    │  └─► 10,742 lines of physics!           │
    │      Solves continuity equation          │
    │      Solves momentum equations           │
    │      Solves transport (T, S, tracers)    │
    │      Updates eta2, uu2, vv2, etc.        │
    │      Handles wetting/drying              │
    │      Writes output files (if scheduled)  │
    │                                         │
    │  return BMI_SUCCESS                      │
    └─────────────────────────────────────────┘

    Just 2 lines of real work!
```

### 📋 update_until(time) — Run Until Target Time

```
    schism_update_until(time):

    ┌────────────────────────────────────────────────────┐
    │                                                    │
    │  model_time = iths * dt                            │
    │                                                    │
    │  do while (model_time < target_time)               │
    │    │                                               │
    │    ├─ iths = iths + 1                              │
    │    ├─ call schism_step(iths)                       │
    │    └─ model_time = iths * dt                       │
    │                                                    │
    │  end do                                            │
    │                                                    │
    │  return BMI_SUCCESS                                │
    └────────────────────────────────────────────────────┘

    Loops until reaching the target time.
    Each iteration = one full schism_step().
```

---

## 13. 🛑 BMI Finalize — How SCHISM Stops

```
    schism_finalizer():

    ┌──────────────────────────────────────────┐
    │                                          │
    │  call schism_finalize                    │
    │  └─► Close output files                  │
    │      Deallocate global arrays            │
    │      Write final diagnostics             │
    │      (155 lines)                         │
    │                                          │
    │  call parallel_finalize                  │
    │  └─► MPI_Finalize                        │
    │      Shut down all MPI communications    │
    │                                          │
    │  return BMI_SUCCESS                      │
    └──────────────────────────────────────────┘
```

---

## 14. 📥 BMI Input Variables (12 Detailed)

### 📊 Master Input Variable Table

| # | Name | Full Description | Units | Grid ID | Grid Type | Location | Data Type | t0/t1? |
|---|------|-----------------|-------|---------|-----------|----------|-----------|--------|
| 1 | 🏞️ `Q_bnd_source` | Discharge into domain from rivers/streams (volumetric flow rate) | m³/s | 4 (SOURCE_ELEMENTS) | points | face | double | ✅ Yes |
| 2 | 🚰 `Q_bnd_sink` | Water extraction from domain (pumping, diversions) | m³/s | 5 (SINK_ELEMENTS) | points | face | double | ✅ Yes |
| 3 | 🌊 `ETA2_bnd` | Water surface elevation at open ocean boundary nodes | m | 3 (OFFSHORE_BOUNDARY) | points | node | double | ✅ Yes |
| 4 | 📊 `SFCPRS` | Surface atmospheric pressure (weight of air column) | Pa | 1 (ALL_NODES) | unstructured | node | double | ✅ Yes |
| 5 | 🌡️ `TMP2m` | Air temperature measured 2 meters above surface | K | 1 (ALL_NODES) | unstructured | node | double | ✅ Yes |
| 6 | 💨 `U10m` | Eastward wind speed at 10 meters above surface | m/s | 1 (ALL_NODES) | unstructured | node | double | ✅ Yes |
| 7 | 💨 `V10m` | Northward wind speed at 10 meters above surface | m/s | 1 (ALL_NODES) | unstructured | node | double | ✅ Yes |
| 8 | 💧 `SPFH2m` | Specific humidity (mass of water vapor / mass of air) at 2m | kg/kg | 1 (ALL_NODES) | unstructured | node | double | ✅ Yes |
| 9 | 🌧️ `RAINRATE` | Precipitation rate (mass flux of rain per unit area) | kg/m²/s | 2 (ALL_ELEMENTS) | points | face | double | ⚠️ ADDS |
| 10 | ⏰ `ETA2_dt` | Time interval between water level boundary updates | s | 7 (ETA2_TIMESTEP) | scalar | - | double | ❌ No |
| 11 | ⏰ `Q_dt` | Time interval between discharge source/sink updates | s | 8 (Q_TIMESTEP) | scalar | - | double | ❌ No |
| 12 | 🔌 `bmi_mpi_comm_handle` | MPI communicator handle from calling framework | - | 9 (MPI_COMM) | scalar | - | integer | ❌ No |

### 🗂️ Input Variables by Physical Category

```
    ┌─────────────────────────────────────────────────────────────┐
    │                                                             │
    │  🌤️ ATMOSPHERIC FORCING (5 variables):                     │
    │  Applied at EVERY mesh node (Grid 1: ALL_NODES)            │
    │  ├─ SFCPRS  — Pressure pushes/pulls water (storm surge!)  │
    │  ├─ TMP2m   — Temperature drives heat exchange w/ ocean    │
    │  ├─ U10m    — East wind creates surface currents + waves   │
    │  ├─ V10m    — North wind creates surface currents + waves  │
    │  └─ SPFH2m  — Humidity controls evaporation rate           │
    │                                                             │
    │  🌊 BOUNDARY CONDITIONS (3 variables):                     │
    │  Applied at domain EDGES only                               │
    │  ├─ ETA2_bnd    — Tides/surge at open ocean boundary       │
    │  │                (Grid 3: OFFSHORE_BOUNDARY)               │
    │  ├─ Q_bnd_source — River discharge INTO ocean              │
    │  │                (Grid 4: SOURCE_ELEMENTS)                 │
    │  └─ Q_bnd_sink   — Water extraction FROM ocean             │
    │                   (Grid 5: SINK_ELEMENTS)                   │
    │                                                             │
    │  🌧️ PRECIPITATION (1 variable):                            │
    │  Applied at EVERY mesh element (Grid 2: ALL_ELEMENTS)       │
    │  └─ RAINRATE  — Rain falling directly on water surface     │
    │     ⚠️ Special: ADDS to existing source term!               │
    │                                                             │
    │  ⏰ TIME CONTROL (2 variables):                             │
    │  Scalar values (size = 1)                                    │
    │  ├─ ETA2_dt  — How often boundary water levels update      │
    │  └─ Q_dt     — How often discharge sources update          │
    │                                                             │
    │  🔌 SYSTEM (1 variable):                                    │
    │  Scalar value (size = 1)                                     │
    │  └─ bmi_mpi_comm_handle — MPI communicator (integer!)      │
    │     ⚠️ Must be set BEFORE calling initialize()              │
    │                                                             │
    └─────────────────────────────────────────────────────────────┘
```

### 🔍 Where Do Input Variables Come From?

```
    In a coupled NextGen simulation:

    Atmospheric Forcing:          From NOAA weather models
    (SFCPRS, TMP2m, winds,  ←── (GFS, HRRR, RAP)
     humidity)                    via atmospheric preprocessor

    River Discharge:              From inland hydrology
    (Q_bnd_source)          ←── WRF-Hydro / NWM / T-Route
                                  THIS is our coupling variable!

    Ocean Boundary:               From global ocean models
    (ETA2_bnd)              ←── (RTOFS, HYCOM, tidal databases)

    Precipitation:                From atmospheric analysis
    (RAINRATE)              ←── (MRMS, HRRR precip products)

    Time Control:                 From framework configuration
    (ETA2_dt, Q_dt)         ←── (ngen config files)
```

---

## 15. 📤 BMI Output Variables (5 Detailed)

### 📊 Master Output Variable Table

| # | Name | Full Description | Units | Grid ID | Grid Type | Location | Data Type | Source Array |
|---|------|-----------------|-------|---------|-----------|----------|-----------|-------------|
| 1 | 🌊 `ETA2` | Total water surface elevation above/below datum | m | 1 (ALL_NODES) | unstructured | node | double | `eta2(:)` |
| 2 | ➡️ `VX` | Eastward current velocity (surface layer) | m/s | 1 (ALL_NODES) | unstructured | node | double | `uu2(1,:)` |
| 3 | ⬆️ `VY` | Northward current velocity (surface layer) | m/s | 1 (ALL_NODES) | unstructured | node | double | `vv2(1,:)` |
| 4 | 📍 `TROUTE_ETA2` | Water levels at T-Route monitoring stations | m | 6 (STATION_POINTS) | points | node | double | `sta_out_gb(:,1)` |
| 5 | 🏖️ `BEDLEVEL` | Bed elevation above datum | m | 1 (ALL_NODES) | unstructured | node | double | `-1.0 * dp(:)` |

### 🔍 Output Variables Deep Dive

```
    🌊 ETA2 — THE PRIMARY OUTPUT
    ┌────────────────────────────────────────────────────────┐
    │  What: Water surface height relative to vertical datum │
    │  Size: npa values (one per mesh node)                  │
    │  Range: typically -2m to +10m (storm surge can be 5m+) │
    │  Source: eta2(:) from schism_glbl                      │
    │                                                        │
    │  THIS is what WRF-Hydro would receive for 2-way        │
    │  coupling (coastal water levels affecting rivers)      │
    │                                                        │
    │  Use cases:                                            │
    │  ├─ Flood inundation mapping                           │
    │  ├─ Storm surge prediction                             │
    │  ├─ Tidal analysis                                     │
    │  └─ Coastal boundary condition for river models        │
    └────────────────────────────────────────────────────────┘

    ➡️ VX + ⬆️ VY — CURRENT VELOCITY VECTOR
    ┌────────────────────────────────────────────────────────┐
    │  What: Horizontal water flow speed and direction       │
    │  Size: npa values each (one per mesh node)             │
    │  Note: Only SURFACE layer exposed (index 1)            │
    │  Source: uu2(1,:) and vv2(1,:) from schism_glbl        │
    │                                                        │
    │  uu2 is dimensioned (nvrt, npa):                       │
    │  ├─ nvrt = number of vertical levels                   │
    │  └─ npa = number of nodes (including ghost nodes)      │
    │                                                        │
    │  Only surface (level 1) is exposed via BMI!            │
    │  Full 3D velocity field stays internal to SCHISM.      │
    └────────────────────────────────────────────────────────┘

    📍 TROUTE_ETA2 — STATION WATER LEVELS
    ┌────────────────────────────────────────────────────────┐
    │  What: Water levels interpolated to specific stations  │
    │  Size: nout_sta values (from station.in file)          │
    │  Source: sta_out_gb(:,1) — station output global buffer│
    │                                                        │
    │  These are NOT raw node values — they're interpolated  │
    │  to user-defined monitoring points (like tide gauges). │
    │  Used for T-Route two-way coupling feedback.           │
    └────────────────────────────────────────────────────────┘

    🏖️ BEDLEVEL — BED ELEVATION
    ┌────────────────────────────────────────────────────────┐
    │  What: Ocean floor elevation relative to datum         │
    │  Size: npa values (one per mesh node)                  │
    │  Source: -1.0 * dp(:) — INVERTED from SCHISM internal! │
    │                                                        │
    │  ⚠️ SCHISM stores depth as POSITIVE BELOW datum:       │
    │     dp = 10.0 means 10m below sea level                │
    │                                                        │
    │  BMI returns BEDLEVEL = -dp = NEGATIVE BELOW datum:    │
    │     BEDLEVEL = -10.0 means 10m below sea level         │
    │                                                        │
    │  Convention: positive = above datum (like land elev.)  │
    │  Static: doesn't change during simulation              │
    │  (unless sediment transport is enabled)                 │
    └────────────────────────────────────────────────────────┘
```

---

## 16. 🗺️ BMI Grid System (9 Grids)

### 📊 Complete Grid Table

| Grid ID | Constant Name | Grid Type | Rank | Size | Variables On This Grid |
|---------|---------------|-----------|------|------|----------------------|
| 1 | `SCHISM_BMI_GRID_ALL_NODES` | **unstructured** | 2 | npa (all nodes) | ETA2, VX, VY, SFCPRS, TMP2m, U10m, V10m, SPFH2m, BEDLEVEL |
| 2 | `SCHISM_BMI_GRID_ALL_ELEMENTS` | **points** | 2 | ne_global | RAINRATE |
| 3 | `SCHISM_BMI_GRID_OFFSHORE_BOUNDARY_POINTS` | **points** | 2 | nnode_et | ETA2_bnd |
| 4 | `SCHISM_BMI_GRID_SOURCE_ELEMENTS` | **points** | 1 | nsources_bmi | Q_bnd_source |
| 5 | `SCHISM_BMI_GRID_SINK_ELEMENTS` | **points** | 1 | nsinks | Q_bnd_sink |
| 6 | `SCHISM_BMI_GRID_STATION_POINTS` | **points** | 2 | nout_sta | TROUTE_ETA2 |
| 7 | `SCHISM_BMI_ETA2_TIMESTEP` | **scalar** | 1 | 1 | ETA2_dt |
| 8 | `SCHISM_BMI_Q_TIMESTEP` | **scalar** | 1 | 1 | Q_dt |
| 9 | `SCHISM_MPI_COMMUNICATOR` | **scalar** | 1 | 1 | bmi_mpi_comm_handle |

### 🔺 Grid Type Details

```
    TYPE 1: "unstructured" (Grid 1 ONLY)
    ═══════════════════════════════════════
    The FULL triangle/quad mesh with complete topology.

    Functions that WORK:
    ├─ get_grid_x(grid, x)         → node x-coordinates (lon or cartesian)
    ├─ get_grid_y(grid, y)         → node y-coordinates (lat or cartesian)
    ├─ get_grid_z(grid, z)         → node z-coordinates (3D only, ics=2)
    ├─ get_grid_node_count(grid)   → np_global (total nodes)
    ├─ get_grid_edge_count(grid)   → ns_global (total edges/sides)
    ├─ get_grid_face_count(grid)   → ne_global (total elements)
    ├─ get_grid_edge_nodes(grid)   → which 2 nodes form each edge
    ├─ get_grid_face_nodes(grid)   → which 3-4 nodes form each element
    ├─ get_grid_face_edges(grid)   → which edges form each element
    └─ get_grid_nodes_per_face(grid) → i34 array (3 or 4 per element)

    Functions that return BMI_FAILURE:
    ├─ get_grid_shape()    → N/A (not a regular grid!)
    ├─ get_grid_spacing()  → N/A (not uniform!)
    └─ get_grid_origin()   → N/A (no single origin!)


    TYPE 2: "points" (Grids 2-6)
    ═══════════════════════════════
    Just a collection of x,y,z coordinates — NO connectivity.

    Functions that WORK:
    ├─ get_grid_x()  → x-coordinates of points
    └─ get_grid_y()  → y-coordinates of points

    NO mesh topology (no edges, no faces).
    Used for: element centroids, boundary nodes, stations, sources/sinks.


    TYPE 3: "scalar" (Grids 7-9)
    ═══════════════════════════════
    Single value — no spatial extent at all.

    size = 1, rank = 1
    No coordinates needed.
    Used for: timestep scalars, MPI communicator handle.
```

### 📐 Coordinate System Handling

```
    SCHISM supports two coordinate systems (ics parameter):

    ics=1 (Cartesian):                  ics=2 (Geographic):
    ├─ x,y in meters                    ├─ x,y in degrees (lon/lat)
    ├─ Used for small domains           ├─ Used for large/global domains
    └─ get_grid_x → xnd(ip)            └─ get_grid_x → rad2deg * xlon(ip)

    The BMI wrapper handles this automatically:
    if (ics==2) then
      grid_x(ip) = rad2deg * xlon(ip)   ! Convert radians → degrees
    else
      grid_x(ip) = xnd(ip)              ! Use Cartesian directly
    end if
```

---

## 17. 🔄 The t0/t1 Sliding Window Pattern

### 🎯 What Is This Pattern?

SCHISM stores **two time snapshots** for every forcing variable — "previous" (t0) and "current" (t1). When new data arrives via `set_value()`, the old t1 slides to t0 and the new data goes into t1.

### 📊 Complete t0/t1 Variable Pairs

| BMI Variable | t0 Array (previous) | t1 Array (current) | Description |
|-------------|---------------------|---------------------|-------------|
| `SFCPRS` | `pr1(:)` | `pr2(:)` | Surface pressure |
| `TMP2m` | `airt1(:)` | `airt2(:)` | Air temperature |
| `U10m` | `windx1(:)` | `windx2(:)` | Eastward wind |
| `V10m` | `windy1(:)` | `windy2(:)` | Northward wind |
| `SPFH2m` | `shum1(:)` | `shum2(:)` | Specific humidity |
| `ETA2_bnd` | `ath2(:,:,:,1,:)` | `ath2(:,:,:,2,:)` | Boundary water levels |
| `Q_bnd_source` | `ath3(:,1,1,1)` | `ath3(:,1,2,1)` | Source discharge |
| `Q_bnd_sink` | `ath3(:,1,1,2)` | `ath3(:,1,2,2)` | Sink discharge |

### 🔁 The Sliding Mechanism

```
    BEFORE set_value("TMP2m", [295.0]):

    Time ═══════════════════════════►

    ┌──────────────┐    ┌──────────────┐
    │  airt1 (t0)  │    │  airt2 (t1)  │
    │  = 290.0 K   │    │  = 293.0 K   │
    │  (old data)  │    │  (current)   │
    └──────────────┘    └──────────────┘


    DURING set_value — TWO OPERATIONS:

    Operation 1: Slide t1 → t0
    airt1(:) = airt2(:)    →    airt1 becomes 293.0

    Operation 2: Store new data in t1
    airt2(:) = src(:)      →    airt2 becomes 295.0


    AFTER set_value("TMP2m", [295.0]):

    ┌──────────────┐    ┌──────────────┐
    │  airt1 (t0)  │    │  airt2 (t1)  │
    │  = 293.0 K   │    │  = 295.0 K   │
    │  (was t1!)   │    │  (NEW data)  │
    └──────────────┘    └──────────────┘
```

### ❓ Why Does SCHISM Need Two Time Slots?

```
    SCHISM interpolates between t0 and t1 during each timestep:

    forcing(t) = t0_value + (t - t0_time) / (t1_time - t0_time) * (t1_value - t0_value)

    This creates SMOOTH forcing transitions:

    WITH interpolation:              WITHOUT interpolation:
    Temperature                      Temperature
    │        ╱                       │     ┌────
    │       ╱                        │     │
    │      ╱                         │     │
    │─────╱                          │─────┘
    └──────────── time               └──────────── time
    Gradual = physically             Abrupt = numerical
    realistic                        instabilities!
```

> **ML Analogy: Learning Rate Warmup/Decay**
>
> - Without interpolation = step learning rate schedule (sudden jumps)
> - With t0/t1 interpolation = linear learning rate schedule (smooth transitions)
> - The t0→t1 update is like updating the lr schedule boundaries

### 📐 Time Control Variables (ETA2_dt, Q_dt)

These scalars tell SCHISM how often the boundary data updates:

```
    set_value("ETA2_dt", [3600.0])  ← Water levels update every hour
    set_value("Q_dt", [3600.0])     ← Discharge updates every hour

    SCHISM uses these to compute interpolation weights:

    th_time2(1,1) = ninv * ETA2_dt           ← t0 time
    th_time2(2,1) = th_time2(1,1) + ETA2_dt  ← t1 time

    Where ninv = floor(current_time / ETA2_dt)
```

---

## 18. 🌧️ RAINRATE — The Special Variable

### ⚠️ Why RAINRATE Is Different

Every other input variable uses the standard t0/t1 slide-and-replace. RAINRATE is the **ONLY variable that ADDS** to an existing value instead of replacing it.

### 🔍 The Reason

```
    Call Order in a Coupled Simulation:

    Step 1: set_value("Q_bnd_source", river_discharge)
            └─► ath3(sources, 1, 2, 1) = river_discharge
                (Sets source term to river flow)

    Step 2: set_value("RAINRATE", rain_rate)
            └─► ath3(:, 1, 2, 1) += rain_rate * area / 1000
                (ADDS rain contribution ON TOP of river flow!)

    ┌──────────────────────────────────────────────────────┐
    │  Total source = River discharge + Rain contribution  │
    │                                                      │
    │  ath3 stores BOTH together because they represent    │
    │  the same physical quantity: total water input to    │
    │  the ocean at each source element.                   │
    └──────────────────────────────────────────────────────┘
```

### 📐 Unit Conversion

```
    RAINRATE input:  kg/m²/s  (mass flux per unit area)
    SCHISM needs:    m³/s     (volumetric flow rate per element)

    Conversion formula:
    Q_rain = RAINRATE × element_area / 1000

    Where:
    ├─ RAINRATE = kg/m²/s
    ├─ area(:) = m² (area of each mesh element, from schism_glbl)
    ├─ 1000 = kg/m³ (density of water)
    └─ Q_rain = m³/s (volume flow rate)

    Example:
    RAINRATE = 0.001 kg/m²/s (= 3.6 mm/hr, moderate rain)
    area = 10,000 m² (100m × 100m element)
    Q_rain = 0.001 × 10,000 / 1000 = 0.01 m³/s
```

> **ML Analogy:** RAINRATE's additive behavior is like a **residual connection**:
> ```python
> # Standard layer: output = transform(input)
> # Residual layer: output = input + transform(new_input)
> #
> # Standard set_value: ath3 = new_value        (replace)
> # RAINRATE set_value: ath3 = ath3 + rain_flux  (add/residual)
> ```

---

## 19. 📏 Variable Info Functions

### 📊 Complete Variable Info Table

| Variable | Type | Units | Grid | Itemsize | Location |
|----------|------|-------|------|----------|----------|
| `ETA2` | double precision | m | 1 (ALL_NODES) | 8 bytes | node |
| `VX` | double precision | m s-1 | 1 (ALL_NODES) | 8 bytes | node |
| `VY` | double precision | m s-1 | 1 (ALL_NODES) | 8 bytes | node |
| `TROUTE_ETA2` | double precision | m | 6 (STATION_POINTS) | 8 bytes | node |
| `BEDLEVEL` | double precision | m | 1 (ALL_NODES) | 8 bytes | node |
| `Q_bnd_source` | double precision | m3 s-1 | 4 (SOURCE_ELEMENTS) | 8 bytes | face |
| `Q_bnd_sink` | double precision | m3 s-1 | 5 (SINK_ELEMENTS) | 8 bytes | face |
| `ETA2_bnd` | double precision | m | 3 (OFFSHORE_BOUNDARY) | 8 bytes | node |
| `SFCPRS` | double precision | Pa | 1 (ALL_NODES) | 8 bytes | node |
| `TMP2m` | double precision | K | 1 (ALL_NODES) | 8 bytes | node |
| `U10m` | double precision | m s-1 | 1 (ALL_NODES) | 8 bytes | node |
| `V10m` | double precision | m s-1 | 1 (ALL_NODES) | 8 bytes | node |
| `SPFH2m` | double precision | kg kg-1 | 1 (ALL_NODES) | 8 bytes | node |
| `RAINRATE` | double precision | kg m-2 s-1 | 2 (ALL_ELEMENTS) | 8 bytes | face |
| `ETA2_dt` | double precision | s | 7 (ETA2_TIMESTEP) | 8 bytes | - |
| `Q_dt` | double precision | s | 8 (Q_TIMESTEP) | 8 bytes | - |
| `bmi_mpi_comm_handle` | integer | - | 9 (MPI_COMM) | 4 bytes | - |

### 🔑 Key Observations

```
    1. Almost ALL variables are "double precision" (64-bit float, 8 bytes)
       └─ Only exception: bmi_mpi_comm_handle is "integer" (4 bytes)

    2. Node vs Face location:
       ├─ "node" = value lives at mesh vertices
       │   (ETA2, velocities, atmospheric forcing, bed level)
       └─ "face" = value lives at element centers
           (RAINRATE, Q_bnd_source, Q_bnd_sink)

    3. get_var_nbytes = get_var_itemsize × get_grid_size
       Example: ETA2 with 1 million nodes:
       nbytes = 8 bytes × 1,000,000 = 8,000,000 bytes = 8 MB

    4. Float operations return BMI_FAILURE
       └─ set_value_float() always fails — all vars are double!
       └─ get_value_float() always fails — no float outputs!
```

---

## 20. 🔺 Grid Functions Deep Dive

### 🗺️ Unstructured Mesh Functions (Grid 1)

```
    For Grid 1 (SCHISM_BMI_GRID_ALL_NODES), the FULL mesh
    topology is available through these BMI functions:

    ┌──────────────────────────────────────────────────────────┐
    │  COORDINATES:                                            │
    │  ├─ get_grid_x() → longitude or x-coord of ALL nodes    │
    │  ├─ get_grid_y() → latitude or y-coord of ALL nodes     │
    │  └─ get_grid_z() → z-coord (only if ics=2, geographic)  │
    │                                                          │
    │  COUNTS:                                                 │
    │  ├─ get_grid_node_count() → np_global (total nodes)      │
    │  ├─ get_grid_edge_count() → ns_global (total sides)      │
    │  └─ get_grid_face_count() → ne_global (total elements)   │
    │                                                          │
    │  CONNECTIVITY:                                           │
    │  ├─ get_grid_edge_nodes() → pairs of nodes forming edges │
    │  │   [n1,n2, n1,n2, n1,n2, ...]  (flat array)           │
    │  │                                                       │
    │  ├─ get_grid_face_nodes() → nodes forming each element   │
    │  │   [n1,n2,n3, n1,n2,n3,n4, ...]  (varies 3 or 4)     │
    │  │                                                       │
    │  ├─ get_grid_face_edges() → edges forming each element   │
    │  │   [e1,e2,e3, e1,e2,e3,e4, ...]  (varies 3 or 4)     │
    │  │                                                       │
    │  └─ get_grid_nodes_per_face() → i34 array                │
    │      [3, 3, 4, 3, 4, 3, ...]  (triangle=3, quad=4)      │
    │                                                          │
    └──────────────────────────────────────────────────────────┘
```

> **ML Analogy:** This is exactly the data you'd need to build a PyG (PyTorch Geometric) graph:
> - `get_grid_x/y/z` → node features (positions)
> - `get_grid_edge_nodes` → `edge_index` tensor
> - `get_grid_face_nodes` → face connectivity (for mesh convolution)
> - `get_grid_nodes_per_face` → face type labels (3=tri, 4=quad)

### ❌ Functions That Return BMI_FAILURE

| Function | Why It Fails |
|----------|-------------|
| `get_grid_shape()` | Unstructured mesh has no regular shape |
| `get_grid_spacing()` | Variable spacing — no uniform dx/dy |
| `get_grid_origin()` | No single origin for unstructured mesh |
| `get_value_ptr()` | Not implemented (returns FAILURE for ALL vars) |
| `set_value_float()` | All SCHISM vars are double precision |
| `get_value_int()` | No integer output variables |
| `get_value_float()` | No float output variables |

---

## 21. 📤📥 Get/Set Value Patterns

### 📤 get_value — Reading SCHISM State

```
    get_value_double(name, dest):

    ┌────────────────────────────────────────────────────────┐
    │                                                        │
    │  select case(name)                                     │
    │                                                        │
    │  case("ETA2")                                          │
    │    dest = [eta2]          ← Copy global array          │
    │                                                        │
    │  case("VX")                                            │
    │    dest = [uu2(1,:)]      ← Surface layer only!        │
    │                                                        │
    │  case("VY")                                            │
    │    dest = [vv2(1,:)]      ← Surface layer only!        │
    │                                                        │
    │  case("TROUTE_ETA2")                                   │
    │    dest = [sta_out_gb(:,1)] ← Station interpolation    │
    │                                                        │
    │  case("BEDLEVEL")                                      │
    │    dest = [-1.0 * dp(:)]  ← INVERTED sign!            │
    │                                                        │
    │  case default                                          │
    │    status = BMI_FAILURE                                 │
    │                                                        │
    │  end select                                            │
    └────────────────────────────────────────────────────────┘

    Key: Output arrays are ALREADY 1D (no reshape needed)
    Unlike Heat model where 2D→1D reshape is required
```

### 📥 set_value — Writing to SCHISM State

```
    set_value_double(name, src):

    ┌────────────────────────────────────────────────────────┐
    │  STANDARD PATTERN (t0/t1 slide):                       │
    │                                                        │
    │  case("SFCPRS")                                        │
    │    pr1(:) = pr2(:)         ← Slide t1 → t0            │
    │    pr2(:) = src(:)         ← Store new in t1           │
    │                                                        │
    │  case("TMP2m")                                         │
    │    airt1(:) = airt2(:)     ← Slide t1 → t0            │
    │    airt2(:) = src(:)       ← Store new in t1           │
    │                                                        │
    │  ... same pattern for U10m, V10m, SPFH2m ...           │
    ├────────────────────────────────────────────────────────┤
    │  BOUNDARY PATTERN (multi-dimensional t0/t1):           │
    │                                                        │
    │  case("ETA2_bnd")                                      │
    │    ath2(1,1,:,1,1) = ath2(1,1,:,2,1)  ← t1 → t0       │
    │    ath2(1,1,:,2,1) = src(:)            ← New in t1     │
    │                                                        │
    │  case("Q_bnd_source")                                  │
    │    ath3(indices,1,1,1) = ath3(indices,1,2,1)           │
    │    ath3(indices,1,2,1) = src(:)                         │
    ├────────────────────────────────────────────────────────┤
    │  SPECIAL PATTERN (RAINRATE — additive):                │
    │                                                        │
    │  case("RAINRATE")                                      │
    │    ath3(:,1,2,1) = ath3(:,1,2,1) + src(:)*area(:)/1000│
    │                    ▲                                   │
    │                    └─ ADDS to existing, not replaces!  │
    ├────────────────────────────────────────────────────────┤
    │  INTEGER PATTERN:                                      │
    │                                                        │
    │  case("bmi_mpi_comm_handle")                           │
    │    this%model%given_communicator = src(1)               │
    │    └─ Stored in container type (not global)            │
    └────────────────────────────────────────────────────────┘
```

### 📍 get_value_at_indices — Selective Reading

```
    For output variables, you can read SPECIFIC indices:

    get_value_at_indices_double("ETA2", dest, [1, 5, 100]):

    Instead of copying ALL million+ node values,
    only copies values at nodes 1, 5, and 100.

    ┌──────────────────────────────────┐
    │  do i = 1, size(inds)           │
    │    dest(i) = eta2(inds(i))      │
    │  end do                         │
    └──────────────────────────────────┘

    Available for: ETA2, TROUTE_ETA2, VX, VY, BEDLEVEL
```

---

## 22. ⏰ Time Functions

### 📊 Time Function Table

| Function | Returns | Source | Notes |
|----------|---------|-------|-------|
| `get_start_time()` | `model_start_time` | From config namelist | Usually 0.0 |
| `get_end_time()` | `model_end_time` | From config or computed | In seconds |
| `get_current_time()` | `iths * dt` | Computed at runtime | Steps × step size |
| `get_time_step()` | `time_step_size` | From config namelist | In seconds |
| `get_time_units()` | `"s"` | Hardcoded | Always seconds |

### 📐 Time Tracking Mechanism

```
    SCHISM BMI tracks time TWO ways:

    1. Step counter: this%model%iths
       └─ Incremented by 1 each update() call
       └─ Used as argument to schism_step(iths)

    2. Computed time: iths * dt
       └─ current_time = step_number × time_step_size
       └─ Example: step 100 × 3600s = 360,000s = 100 hours

    Time line:
    ├─ start_time ────────── current_time ────────── end_time
    │  (from config)         (iths * dt)              (from config)
    │  usually 0.0           updates each step        e.g. 86400.0
```

---

## 23. 🔗 NextGen Integration

### 🔧 Conditional Compilation (#ifdef)

```
    SCHISM BMI uses two key preprocessor flags:

    ┌─────────────────────────────────────────────────────────┐
    │  #ifdef NGEN_ACTIVE                                     │
    │  ├─ use bmif_2_0_iso    (ISO C binding version)         │
    │  ├─ Adds register_bmi() function at end of module       │
    │  └─ Required for NextGen framework discovery             │
    │                                                         │
    │  #ifndef NGEN_ACTIVE (standard mode)                    │
    │  ├─ use bmif_2_0        (standard Fortran BMI)          │
    │  └─ No register_bmi() needed                            │
    └─────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────┐
    │  #ifdef OLDIO                                           │
    │  ├─ Serial I/O mode (each rank writes its own files)    │
    │  ├─ Simple: just call schism_init() directly            │
    │  └─ Used for serial BMI mode                            │
    │                                                         │
    │  #ifndef OLDIO (parallel I/O)                           │
    │  ├─ Scribe-based parallel I/O                           │
    │  ├─ Compute ranks call schism_init()                    │
    │  ├─ I/O ranks call scribe_init()                        │
    │  └─ Requires MPI with dedicated I/O processes           │
    └─────────────────────────────────────────────────────────┘
```

### 🔌 register_bmi() — How NextGen Finds the Model

```
    When compiled with NGEN_ACTIVE, the module includes:

    function register_bmi(this) result(bmi_status) bind(C, name="register_bmi")
    ┌────────────────────────────────────────────────────────┐
    │  1. Allocate a new bmi_schism instance                 │
    │  2. Wrap it in a C pointer (via "box" wrapper)         │
    │  3. Return the pointer to the caller                   │
    │                                                        │
    │  NextGen calls this C function to "discover" SCHISM:   │
    │  ├─ void* handle = register_bmi()                      │
    │  ├─ bmi_initialize(handle, "config.nml")               │
    │  ├─ bmi_update(handle)                                 │
    │  └─ bmi_finalize(handle)                               │
    └────────────────────────────────────────────────────────┘
```

### 🔗 ISO C Binding Layer

```
    iso_c_fortran_bmi/ provides the bridge:

    Python/C caller                Fortran BMI
    ─────────────────              ───────────
    register_bmi() ──► C function ──► allocate bmi_schism
    bmi_initialize() ─► C function ──► call schism_initialize()
    bmi_update()    ──► C function ──► call schism_update()
    bmi_get_value() ──► C function ──► call schism_get_double()

    This is the iso_c_bmi.f90 file (39.8 KB) that wraps
    every BMI function with ISO_C_BINDING for C interop.
```

---

## 24. 🔨 Build System & Configuration

### 🔧 CMake Build Flags

| Flag | Default | Purpose |
|------|---------|---------|
| `USE_BMI` | ON | Enable BMI wrapper compilation |
| `BUILD_SHARED_LIBS` | ON | Build libschism_bmi.so (required for BMI) |
| `OLDIO` | ON | Serial I/O mode (vs. parallel scribe I/O) |
| `USE_ATMOS` | ON | Enable atmospheric forcing via BMI |
| `BLD_STANDALONE` | ON | Build SCHISM standalone executable |
| `NO_PARMETIS` | OFF | Turn off ParMETIS graph partitioning |
| `TVD_LIM` | VL | Flux limiter (VanLeer, Superbee, Minmod, Osher) |
| `USE_GOTM` | OFF | GOTM turbulence model |
| `USE_WWM` | OFF | Wind wave model |
| `USE_ICE` | OFF | Sea ice model |
| `USE_SED` | OFF | Sediment transport |

### 📁 Build Output

```
    After cmake + make:

    ├─ libschism_bmi.so           ← Shared library (THE BMI product)
    ├─ libiso_c_bmi.so            ← ISO C binding library
    ├─ schism_bmi_driver           ← Test executable
    └─ libhydro.so, libcore.so    ← SCHISM internal libraries
```

### 📋 BMI Config File (Namelist Format)

```
    The BMI initialize() reads a simple namelist file:

    &test
      model_start_time = 0.0
      model_end_time = 86400.0
      num_time_steps = 0
      time_step_size = 3600
      SCHISM_dir = "/path/to/schism/run/directory/"
      SCHISM_NSCRIBES = 0
    /

    Key fields:
    ├─ model_start_time  — Simulation start (seconds)
    ├─ model_end_time    — Simulation end (seconds)
    ├─ num_time_steps    — Alternative to end_time
    ├─ time_step_size    — dt in seconds
    ├─ SCHISM_dir        — Path to SCHISM run directory
    │                      (contains param.nml, hgrid.gr3, etc.)
    └─ SCHISM_NSCRIBES   — Number of I/O scribe processes (0 = serial)
```

---

## 25. ⚠️ Current Limitations

### 📋 Official Limitations (from LIMITATIONS file)

| # | Limitation | Details | Impact |
|---|-----------|---------|--------|
| 1 | ⚠️ **MPI partially implemented** | Can set communicator via `bmi_mpi_comm_handle`, but parallel execution has edge cases | Prefer serial mode for BMI |
| 2 | ⚠️ **Connectors not fully validated** | Water level (ETA2_bnd) and source/sink (Q_bnd_source/sink) connectors need more testing | Use with caution, validate outputs |

### 📋 Additional Observed Limitations

| # | Limitation | Details |
|---|-----------|---------|
| 3 | ❌ `get_value_ptr()` not implemented | Returns BMI_FAILURE for ALL variables — no zero-copy access |
| 4 | ❌ `set_value_float()` not implemented | All SCHISM variables are double precision — no 32-bit support |
| 5 | ❌ No CSDMS Standard Names | Variables use internal names (ETA2, VX) not CSDMS names |
| 6 | ❌ Only surface layer for velocity | VX/VY expose only surface (level 1), not full 3D |
| 7 | ⚠️ No PyMT pathway | Babelizer has not been run — no pymt_schism package exists |
| 8 | ⚠️ Not in CSDMS catalog | SCHISM BMI built for NOAA NextGen, not CSDMS/PyMT ecosystem |

---

## 26. 🔗 Repository Links & References

### 📦 Official Repositories

| Resource | URL |
|----------|-----|
| 🏠 **SCHISM Official Website** | http://ccrm.vims.edu/schismweb/ |
| 📦 **SCHISM GitHub (main)** | https://github.com/schism-dev/schism |
| 📖 **SCHISM Online Documentation** | https://schism-dev.github.io/schism/master/index.html |
| 📖 **SCHISM Wiki** | http://ccrm.vims.edu/w/index.php/About_SCHISM |
| 🔌 **SCHISM NWM BMI (schism-dev)** | https://github.com/schism-dev/schism_NWM_BMI |
| 🔌 **SCHISM BMI (LynkerIntel)** | https://github.com/LynkerIntel/SCHISM_BMI |
| 🐍 **PySchism (Python interface)** | https://github.com/schism-dev/pyschism |
| 🔗 **SCHISM-ESMF coupling** | https://github.com/schism-dev/schism-esmf |
| 📊 **NOAA NextGen (ngen)** | https://github.com/NOAA-OWP/ngen |
| 📊 **NextGen SCHISM Issue #547** | https://github.com/NOAA-OWP/ngen/issues/547 |
| 🌊 **UFS Coastal App** | https://github.com/oceanmodeling/ufs-coastal-app |
| 📏 **NOAA STOFS-3D Data** | https://registry.opendata.aws/noaa-nos-stofs3d/ |

### 📖 Key Publications

| Year | Citation | Topic |
|------|----------|-------|
| 2008 | Zhang & Baptista, "SELFE: A semi-implicit Eulerian-Lagrangian finite-element model," *Ocean Modelling* 21(3-4), 71-96 | Original SELFE paper |
| 2015 | Zhang et al., "A new vertical coordinate system for a 3D unstructured-grid model," *Ocean Modelling* 85, 16-31 | LSC2 vertical coords |
| 2016 | Zhang, Ye, Stanev, Grashorn, "Seamless cross-scale modeling with SCHISM," *Ocean Modelling* 102, 64-81 | **THE** SCHISM paper |
| 2020 | Zhang et al., "Simulating compound flooding events in a hurricane," *Ocean Dynamics* 70, 621-640 | Compound flooding |
| 2020 | SCHISM v5.8 Manual (PDF) | Full reference manual |

### 📄 Document Links

| Document | URL |
|----------|-----|
| 📐 SCHISM Geometry & Discretization | https://schism-dev.github.io/schism/master/schism/geometry-discretization.html |
| ⚡ Barotropic Solver | https://schism-dev.github.io/schism/master/schism/barotropic-solver.html |
| 🔄 Eulerian-Lagrangian Method | https://schism-dev.github.io/schism/master/schism/eulerian-lagrangian-method.html |
| 📋 Model Parameters (param.nml) | https://schism-dev.github.io/schism/master/input-output/param.html |
| 📦 Modules Overview | https://schism-dev.github.io/schism/master/modules/overview.html |
| 🗺️ Grid Generation | https://schism-dev.github.io/schism/master/getting-started/grid-generation.html |
| 📐 Horizontal Grid Format | https://schism-dev.github.io/schism/master/input-output/hgrid.html |
| 🔗 NUOPC Coupling | https://schism-dev.github.io/schism/master/coupling/nuopc.html |
| 📊 Case Studies | https://schism-dev.github.io/schism/master/case-study.html |
| 📄 v5.8 Manual PDF | https://ccrm.vims.edu/schismweb/SCHISM_v5.8-Manual.pdf |
| 📄 SCHISM 2016 Paper PDF | https://ccrm.vims.edu/yinglong/Courses/Marsh-2017/Zhang_etal_OM_2016-SCHISMpaper.pdf |
| 📄 LSC2 Paper PDF | https://ccrm.vims.edu/schismweb/paper-LSC2.pdf |

### 👤 Key People

| Person | Affiliation | Role |
|--------|-------------|------|
| Dr. Y. Joseph Zhang | VIMS, College of William & Mary | SCHISM lead developer |
| Jason Ducker | NOAA/NWS | NextGen team, SCHISM BMI integration |
| Phil Miller | NOAA | SCHISM BMI NextGen evaluation |
| Dr. Fei Ye | VIMS | STOFS-3D-Atlantic, SCHISM development |
| E.V. Stanev | HZG Germany | North/Baltic Sea SCHISM co-developer |

---

## 27. 📝 Summary & Key Takeaways

### 🌊 SCHISM Model Summary

```
    ┌─────────────────────────────────────────────────────────────┐
    │  SCHISM = Coastal Ocean Simulator                           │
    │                                                             │
    │  📐 Grid: Unstructured triangles + quads (variable resolution) │
    │  ⚡ Time: Semi-implicit (NO CFL constraint, large dt OK)   │
    │  📏 Vertical: LSC2 (each node has own vertical levels)     │
    │  🔄 Advection: ELM (unconditionally stable)                │
    │  🌍 Scale: Creek (8m) to ocean (2km) in one simulation     │
    │  📦 Modules: 12 tracer + 10 non-tracer                     │
    │  🏛️ Operations: NOAA STOFS-3D-Atlantic (since Jan 2023)    │
    │  📊 Size: 437 files, 100K+ lines of Fortran                │
    │  📄 License: Apache 2.0                                    │
    └─────────────────────────────────────────────────────────────┘
```

### 🔌 SCHISM BMI Summary

```
    ┌─────────────────────────────────────────────────────────────┐
    │  SCHISM BMI = API Wrapper for SCHISM                        │
    │                                                             │
    │  👷 Built by: LynkerIntel (for NOAA NextGen)               │
    │  📄 Main file: bmischism.f90 (1,729 lines)                 │
    │  📦 Container: schism_type (config/time only, 51 lines)    │
    │  🔑 State: Global variables in schism_glbl (NOT embedded)  │
    │                                                             │
    │  📥 12 Input Variables:                                     │
    │  ├─ 5 atmospheric (SFCPRS, TMP2m, U10m, V10m, SPFH2m)     │
    │  ├─ 3 boundary (ETA2_bnd, Q_bnd_source, Q_bnd_sink)       │
    │  ├─ 1 precipitation (RAINRATE — additive!)                 │
    │  ├─ 2 time control (ETA2_dt, Q_dt)                         │
    │  └─ 1 system (bmi_mpi_comm_handle)                         │
    │                                                             │
    │  📤 5 Output Variables:                                     │
    │  ├─ ETA2 (water levels — THE coupling variable)            │
    │  ├─ VX, VY (surface current velocity)                      │
    │  ├─ TROUTE_ETA2 (station water levels for T-Route)         │
    │  └─ BEDLEVEL (bed elevation, inverted from dp)             │
    │                                                             │
    │  🗺️ 9 Grids:                                               │
    │  ├─ 1 unstructured (full mesh with topology)                │
    │  ├─ 5 points (elements, boundaries, stations, sources)      │
    │  └─ 3 scalar (timestep controls, MPI communicator)          │
    │                                                             │
    │  🔄 Key Patterns:                                           │
    │  ├─ t0/t1 sliding window (temporal interpolation)           │
    │  ├─ RAINRATE additive (residual connection)                 │
    │  ├─ Global state access (use schism_glbl, not embedded)     │
    │  ├─ Delegate to model (init→schism_init, step→schism_step) │
    │  └─ Conditional compilation (#ifdef NGEN_ACTIVE, OLDIO)     │
    │                                                             │
    │  ⚠️ Limitations:                                            │
    │  ├─ MPI partially implemented                               │
    │  ├─ Connectors not fully validated                          │
    │  ├─ No get_value_ptr (not implemented)                      │
    │  ├─ No CSDMS Standard Names                                 │
    │  └─ No PyMT/babelizer pathway yet                          │
    └─────────────────────────────────────────────────────────────┘
```

### 🎯 Why This Matters for WRF-Hydro BMI

```
    SCHISM BMI teaches us:

    1. ✅ Global state pattern → WRF-Hydro uses RT_DOMAIN (similar)
    2. ✅ Config-only container → We'll do the same for wrf_hydro_type
    3. ✅ Delegate to model → We'll call land_driver_ini/exe, HYDRO_ini/exe
    4. ✅ select case dispatch → Same pattern for all variable functions
    5. ✅ Multiple grids → We need Grid 0 (1km), Grid 1 (250m), Grid 2 (network)
    6. ✅ Conditional compilation → We'll use #ifdef USE_NWM_BMI
    7. ✅ Non-invasive wrapper → We wrap WRF-Hydro without modifying it

    SCHISM BMI is our REAL-WORLD REFERENCE.
    Heat BMI is our TEMPLATE.
    Together they guide our bmi_wrf_hydro.f90 implementation.
```

---

> 📝 **Document Info**
> - Created: February 2026
> - Author: Claude (AI Assistant)
> - Project: WRF-Hydro BMI Wrapper
> - Lines: ~1,600+
> - Related Docs: Doc 11 (SCHISM BMI Deep Dive), Doc 12 (BMI Implementation Concepts)
> - Source Files: bmischism.f90, schism_model_container.f90, schism_bmi_driver_test.f90
> - Research: SCHISM official docs, LynkerIntel repo, NOAA NextGen, publications
