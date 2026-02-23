# 🌊 Doc 12: BMI Implementation Concepts — Heat, SCHISM & WRF-Hydro

## 📋 Table of Contents

| # | Section | Description |
|---|---------|-------------|
| 1 | [What is SCHISM?](#1--what-is-schism) | The coastal ocean model explained for ML engineers |
| 2 | [SCHISM Physics & What It Computes](#2--schism-physics--what-it-computes) | Core equations, outputs, grid system |
| 3 | [BMI Concept Recap](#3--bmi-concept-recap) | The 41-function standard interface |
| 4 | [How BMI Heat Was Implemented](#4--how-bmi-heat-was-implemented) | The simplest BMI wrapper — our template |
| 5 | [How SCHISM BMI Was Implemented](#5--how-schism-bmi-was-implemented) | Real-world production BMI wrapper |
| 6 | [SCHISM BMI Input Variables](#6--schism-bmi-input-variables-detailed) | All 12 inputs with full details |
| 7 | [SCHISM BMI Output Variables](#7--schism-bmi-output-variables-detailed) | All 5 outputs with full details |
| 8 | [SCHISM BMI Grid System](#8--schism-bmi-grid-system) | 9 grids explained |
| 9 | [Key Differences: Heat vs SCHISM BMI](#9--key-differences-heat-vs-schism-bmi) | Side-by-side comparison |
| 10 | [The t0/t1 Sliding Window Pattern](#10--the-t0t1-sliding-window-pattern) | Critical concept for forcing data |
| 11 | [RAINRATE — The Special Variable](#11--rainrate--the-special-variable) | Why one variable breaks the pattern |
| 12 | [How WRF-Hydro BMI Should Be Implemented](#12--how-wrf-hydro-bmi-should-be-implemented) | Our roadmap forward |
| 13 | [WRF-Hydro vs Heat vs SCHISM Comparison](#13--wrf-hydro-vs-heat-vs-schism-comparison) | Three-way architecture comparison |
| 14 | [Quick Reference & Glossary](#14--quick-reference--glossary) | Terms, commands, cheat sheet |

---

## 1. 🌊 What is SCHISM?

### 🎯 One-Sentence Summary

**SCHISM** (Semi-implicit Cross-scale Hydroscience Integrated System Model) is a coastal ocean model that simulates water levels, currents, and waves in estuaries, coasts, and oceans.

### 🧠 ML Analogy

> **Think of SCHISM as a "Diffusion Model for Water"**
>
> | ML Concept | SCHISM Equivalent |
> |-----------|-------------------|
> | Image generation on a pixel grid | Water simulation on a triangle mesh |
> | Diffusion steps refine noise → image | Time steps evolve initial conditions → water state |
> | U-Net processes at multiple resolutions | Unstructured mesh has variable resolution |
> | Conditioning on text prompt | Forcing from atmosphere (wind, rain, pressure) |
> | Generated image (output) | Water levels, currents, salinity (output) |

### 📍 Where Does SCHISM Fit?

```
    🌧️ ATMOSPHERE (WRF / GFS / HRRR)
         │ rain, wind, temperature, pressure
         ▼
    🏔️ LAND SURFACE (WRF-Hydro / Noah-MP)     ← What WE are wrapping
         │ river discharge (streamflow)
         ▼
    🌊 COASTAL OCEAN (SCHISM)                   ← Already has BMI
         │ water levels, currents
         ▼
    🏖️ Impact Assessment (flooding, erosion)
```

### 🏗️ Who Built SCHISM?

| Aspect | Details |
|--------|---------|
| 🏛️ Origin | Virginia Institute of Marine Science (VIMS) |
| 👨‍🔬 Lead Developer | Dr. Yinglong Joseph Zhang |
| 📝 Language | Fortran 90/2003 with MPI |
| 📊 Scale | Can handle 1M+ mesh elements |
| 🌍 Used By | NOAA, US Army Corps, EU agencies, universities worldwide |
| 📦 Size | 437 files in full source tree |

### 🔑 Why Do We Care About SCHISM?

**Because SCHISM is the model we want to COUPLE with WRF-Hydro!**

```
    ┌─────────────────┐         ┌─────────────────┐
    │   WRF-Hydro     │ ──────► │    SCHISM        │
    │  (Land/River)   │ discharge│  (Coastal Ocean) │
    │                 │ ◄────── │                  │
    │                 │ water   │                  │
    │                 │ levels  │                  │
    └─────────────────┘         └─────────────────┘
           │                           │
           │    Both wrapped in BMI    │
           │         ▼                 │
           │   ┌───────────┐           │
           └──►│   PyMT    │◄──────────┘
               │ (Python)  │
               └───────────┘
               ~20 lines of
               Jupyter code!
```

---

## 2. 🔬 SCHISM Physics & What It Computes

### 🌊 Core Equations

SCHISM solves the **shallow water equations** — the fundamental laws governing water flow:

| Equation | What It Describes | ML Analogy |
|----------|-------------------|------------|
| 📐 Continuity | Conservation of water mass | Like batch norm — ensures quantities are conserved |
| ➡️ Momentum (x) | East-west water velocity | Like horizontal gradient flow |
| ⬆️ Momentum (y) | North-south water velocity | Like vertical gradient flow |
| 🌡️ Transport | Salinity, temperature movement | Like feature propagation through layers |

### 🎯 What SCHISM Computes (Outputs)

```
    INPUT FORCING                    SCHISM ENGINE                   OUTPUT
    ─────────────                    ─────────────                   ──────
    🌧️ Rain rate            ┌─────────────────────┐
    💨 Wind (U, V)    ──►   │  Solve shallow      │   ──►  🌊 Water levels (ETA2)
    🌡️ Air temperature      │  water equations     │   ──►  ➡️ Currents (UU2, VV2)
    💧 Humidity        ──►  │  on unstructured     │   ──►  🏖️ Bed elevation
    📊 Pressure             │  triangle mesh       │   ──►  📍 Station measurements
    🌊 Boundary levels ──►  │  every time step     │
    🏞️ River discharge ──►  └─────────────────────┘
```

### 🔺 The Unstructured Mesh

> **ML Analogy: Graph Neural Network (GNN) vs CNN**
>
> - A regular grid (WRF-Hydro) is like a CNN — fixed pixel spacing everywhere
> - An unstructured mesh (SCHISM) is like a GNN — nodes connected by edges, variable spacing
> - SCHISM uses triangles (3 nodes) and quads (4 nodes) — like attention heads with 3-4 connections

```
    Regular Grid (WRF-Hydro):          Unstructured Mesh (SCHISM):
    ┌──┬──┬──┬──┬──┐                   *───────*
    │  │  │  │  │  │                  / \     / \
    ├──┼──┼──┼──┼──┤                /   \   /   \
    │  │  │  │  │  │              *─────*─*─────*
    ├──┼──┼──┼──┼──┤               \  /  \ \  /
    │  │  │  │  │  │                *──*───*──*
    └──┴──┴──┴──┴──┘                 \/ \/ \/
    Same resolution everywhere        *──*──*
                                     Fine near coast,
                                     coarse in deep ocean
```

---

## 3. 🔌 BMI Concept Recap

### 🎯 What is BMI?

**BMI (Basic Model Interface)** = A standard API with **41 functions** that any model must implement to be "BMI-compliant."

> **ML Analogy: PyTorch's `nn.Module` Interface**
>
> | PyTorch | BMI |
> |---------|-----|
> | `__init__(self)` | `initialize(config_file)` |
> | `forward(self, x)` | `update()` |
> | `model.eval()` / cleanup | `finalize()` |
> | `model.state_dict()` | `get_value(var_name)` |
> | `model.load_state_dict()` | `set_value(var_name, data)` |
> | `model.parameters()` | `get_input_var_names()` / `get_output_var_names()` |

### 📦 The 41 Functions in 6 Categories

```
    ┌─────────────────────────────────────────────────┐
    │              BMI 2.0 SPECIFICATION              │
    │                (41 Functions)                    │
    ├─────────────────────────────────────────────────┤
    │                                                 │
    │  🎮 CONTROL (4)         📊 MODEL INFO (5)      │
    │  ├─ initialize          ├─ get_component_name   │
    │  ├─ update              ├─ get_input_item_count │
    │  ├─ update_until        ├─ get_output_item_count│
    │  └─ finalize            ├─ get_input_var_names  │
    │                         └─ get_output_var_names │
    │                                                 │
    │  📏 VAR INFO (6)        ⏰ TIME (5)            │
    │  ├─ get_var_type        ├─ get_current_time     │
    │  ├─ get_var_units       ├─ get_start_time       │
    │  ├─ get_var_grid        ├─ get_end_time         │
    │  ├─ get_var_itemsize    ├─ get_time_step        │
    │  ├─ get_var_nbytes      └─ get_time_units       │
    │  └─ get_var_location                            │
    │                                                 │
    │  📤📥 GET/SET (5)       🗺️ GRID (17)           │
    │  ├─ get_value           ├─ get_grid_type        │
    │  ├─ set_value           ├─ get_grid_rank        │
    │  ├─ get_value_ptr       ├─ get_grid_size        │
    │  ├─ get_value_at_indices├─ get_grid_shape       │
    │  └─ set_value_at_indices├─ get_grid_spacing     │
    │                         ├─ get_grid_origin      │
    │                         ├─ get_grid_x/y/z       │
    │                         ├─ get_grid_node_count  │
    │                         ├─ get_grid_edge_count  │
    │                         ├─ get_grid_face_count  │
    │                         ├─ get_grid_edge_nodes  │
    │                         ├─ get_grid_face_edges  │
    │                         ├─ get_grid_face_nodes  │
    │                         └─ get_grid_nodes_per_face│
    └─────────────────────────────────────────────────┘
```

### 🔑 The IRF Pattern (Initialize-Run-Finalize)

This is THE most important concept in BMI:

```
    TRADITIONAL MODEL                    BMI MODEL
    ─────────────────                    ─────────
    program main                         ! CALLER controls the loop
      call init()                        s = model%initialize("config.cfg")
      do t = 1, 100        ──►          do while (time < end_time)
        call step()                        s = model%update()
      end do                               s = model%get_value("temp", data)
      call finish()                      end do
    end program                          s = model%finalize()

    MODEL controls the loop              CALLER controls the loop
    (can't pause, can't inject)          (can pause, inject, couple!)
```

> **ML Analogy: Training Loop Ownership**
>
> - Traditional model = model.fit() in scikit-learn — you hand over control
> - BMI model = custom PyTorch training loop — YOU control each step
> - This is why BMI enables coupling: you can interleave steps from two models!

---

## 4. 🔥 How BMI Heat Was Implemented

### 🏗️ Architecture Overview

The BMI Heat example has **3 files** with a crystal-clear separation:

```
    ┌─────────────────────────────────────────────────────┐
    │                    FILE STRUCTURE                     │
    ├─────────────────────────────────────────────────────┤
    │                                                      │
    │  📄 heat.f90 (158 lines)        ← The PHYSICS model │
    │  ├─ type :: heat_model           (like model.py)     │
    │  ├─ initialize_from_file()                           │
    │  ├─ advance_in_time()                                │
    │  └─ cleanup()                                        │
    │                                                      │
    │  📄 bmi_heat.f90 (935 lines)    ← The BMI WRAPPER   │
    │  ├─ type, extends(bmi) :: bmi_heat  (like api.py)   │
    │  ├─ All 41 BMI functions                             │
    │  └─ Maps names → model internals                     │
    │                                                      │
    │  📄 bmi_main.f90 (65 lines)     ← The DRIVER        │
    │  ├─ Creates bmi_heat instance    (like main.py)      │
    │  ├─ Calls initialize → update loop → finalize        │
    │  └─ Gets values and writes output                    │
    │                                                      │
    └─────────────────────────────────────────────────────┘
```

> **ML Analogy: Three-File Pattern**
>
> | File | ML Equivalent | Purpose |
> |------|---------------|---------|
> | `heat.f90` | `model.py` (defines the neural network) | The physics/math |
> | `bmi_heat.f90` | `api.py` (REST API wrapping the model) | The standard interface |
> | `bmi_main.f90` | `main.py` (calls the API) | The user's script |

### 🧬 Concept 1: The Derived Type (State Container)

The heat model stores ALL its state inside a single derived type:

```
    ┌─────────────────────────────────────┐
    │       type :: heat_model            │
    ├─────────────────────────────────────┤
    │  🔧 Configuration                  │
    │  ├─ dt (time step size)             │
    │  ├─ alpha (thermal diffusivity)     │
    │  ├─ n_x, n_y (grid dimensions)     │
    │  ├─ dx, dy (grid spacing)           │
    │  └─ t_end (end time)                │
    ├─────────────────────────────────────┤
    │  📊 State Variables                 │
    │  ├─ t (current time)                │
    │  ├─ temperature(:,:) (2D grid)      │
    │  └─ temperature_tmp(:,:) (scratch)  │
    └─────────────────────────────────────┘
```

> **ML Analogy:** This is like a `dataclass` or `nn.Module` that holds all model weights and buffers in one object. You pass this object around — never use global variables.

### 🧬 Concept 2: Type Extension (Inheritance)

The BMI wrapper "extends" the abstract BMI type:

```
    ┌───────────────────────┐
    │  type :: bmi           │  ← Abstract base class (from bmi-fortran library)
    │  ├─ 53 deferred procs │     Like PyTorch's nn.Module
    │  └─ (no data)         │     Has forward(), backward() etc. but no implementation
    └───────────┬───────────┘
                │ EXTENDS (inherits)
                ▼
    ┌───────────────────────────────┐
    │  type, extends(bmi) :: bmi_heat  │  ← Concrete implementation
    │  ├─ type(heat_model) :: model    │     Like MyCustomNetwork(nn.Module)
    │  ├─ initialize()  ──► calls model%initialize_from_file()
    │  ├─ update()      ──► calls model%advance_in_time()
    │  ├─ finalize()    ──► calls model%cleanup()
    │  ├─ get_value()   ──► reads model%temperature
    │  └─ set_value()   ──► writes model%temperature
    └───────────────────────────────┘
```

> **Key Insight:** The BMI wrapper CONTAINS the model as a member variable. It WRAPS the model — it doesn't modify it.

### 🧬 Concept 3: The `select case` Dispatch Pattern

Every BMI function that handles variables uses `select case` — like a Python dictionary lookup:

```
    ┌──────────────────────────────────────────────────┐
    │  function get_value(this, name, dest)             │
    │                                                   │
    │    select case(name)    ◄── Like dict[key]        │
    │                                                   │
    │    case("plate_surface__temperature")              │
    │      dest = reshape(this%model%temperature, [N])  │
    │      status = BMI_SUCCESS  ✅                     │
    │                                                   │
    │    case("plate_surface__thermal_diffusivity")      │
    │      dest = [this%model%alpha]                     │
    │      status = BMI_SUCCESS  ✅                     │
    │                                                   │
    │    case default                                    │
    │      status = BMI_FAILURE  ❌                     │
    │                                                   │
    │    end select                                      │
    └──────────────────────────────────────────────────┘
```

> **ML Analogy:** This is exactly like a Python dictionary that maps string keys to tensor values:
> ```python
> state_dict = {
>     "plate_surface__temperature": model.temperature.flatten(),
>     "plate_surface__thermal_diffusivity": model.alpha,
> }
> return state_dict.get(name, FAILURE)
> ```

### 🧬 Concept 4: Array Flattening (reshape)

BMI **always returns 1D arrays**, even if the model stores 2D/3D data internally:

```
    MODEL INTERNAL (2D):              BMI OUTPUT (1D):
    ┌──┬──┬──┐                        ┌──┬──┬──┬──┬──┬──┬──┬──┬──┐
    │1 │2 │3 │  row 1                 │1 │4 │7 │2 │5 │8 │3 │6 │9 │
    ├──┼──┼──┤             ──►        └──┴──┴──┴──┴──┴──┴──┴──┴──┘
    │4 │5 │6 │  row 2                  Column-major order (Fortran)
    ├──┼──┼──┤
    │7 │8 │9 │  row 3                 reshape(temperature, [n_x * n_y])
    └──┴──┴──┘
```

> **ML Analogy:** Like `tensor.flatten()` or `tensor.reshape(-1)` — converting a 2D feature map to a 1D vector for a fully connected layer. BMI does this to avoid row-major vs column-major confusion between languages.

### 🧬 Concept 5: The Variables & Grids

Heat model has a minimal setup:

```
    VARIABLES:                         GRIDS:
    ┌────────────────────────────┐    ┌──────────────────────────┐
    │ INPUT (3):                 │    │ Grid 0: uniform_rectilinear │
    │ ├─ plate_surface__         │    │   rank=2, shape=[n_y, n_x]  │
    │ │   temperature       [G0] │    │   spacing=[dy, dx]          │
    │ ├─ plate_surface__         │    │   For: temperature          │
    │ │   thermal_diffusivity[G1]│    ├──────────────────────────┤
    │ └─ model__identification   │    │ Grid 1: scalar              │
    │     _number           [G1] │    │   rank=0, size=1            │
    │                            │    │   For: alpha, id            │
    │ OUTPUT (1):                │    └──────────────────────────┘
    │ └─ plate_surface__         │
    │     temperature       [G0] │
    └────────────────────────────┘

    G0 = grid 0, G1 = grid 1
```

### 🧬 Concept 6: The Control Flow

```
    bmi_main.f90 (THE CALLER):

    ┌──────────────────────────────────────────────┐
    │  1. model%initialize("heat.cfg")             │
    │     └─► reads config file                    │
    │     └─► allocates temperature arrays         │
    │     └─► sets boundary conditions             │
    │                                              │
    │  2. LOOP: while (current_time <= end_time)   │
    │     │                                        │
    │     ├─ model%get_value("temperature", data)  │
    │     │  └─► copies temperature to 1D array    │
    │     │                                        │
    │     ├─ [write data to file]                  │
    │     │                                        │
    │     ├─ model%update()                        │
    │     │  └─► solves heat equation one step     │
    │     │  └─► t = t + dt                        │
    │     │                                        │
    │     └─ model%get_current_time(time)          │
    │                                              │
    │  3. model%finalize()                         │
    │     └─► deallocates arrays                   │
    └──────────────────────────────────────────────┘
```

> **ML Analogy:** This is exactly like a PyTorch evaluation loop:
> ```python
> model.load_state_dict(checkpoint)     # initialize
> for batch in dataloader:               # time loop
>     output = model(batch)              # update
>     save_predictions(output)           # get_value
> cleanup()                              # finalize
> ```

---

## 5. 🌊 How SCHISM BMI Was Implemented

### 🏗️ Architecture Overview

SCHISM BMI has a **fundamentally different architecture** from the Heat example:

```
    ┌───────────────────────────────────────────────────────────┐
    │                    SCHISM BMI FILE STRUCTURE               │
    ├───────────────────────────────────────────────────────────┤
    │                                                           │
    │  📄 schism_model_container.f90 (51 lines)                │
    │  ├─ type :: schism_type          ← Config/time only!     │
    │  └─ subroutine run()             ← Placeholder (unused)  │
    │                                                           │
    │  📄 bmischism.f90 (1,729 lines)  ← The REAL wrapper      │
    │  ├─ type, extends(bmi) :: bmi_schism                     │
    │  ├─ Uses schism_glbl for ALL physics state               │
    │  ├─ All 41 BMI functions                                 │
    │  └─ 12 inputs + 5 outputs + 9 grids                     │
    │                                                           │
    │  📁 SCHISM source (437 files)    ← The FULL model        │
    │  ├─ schism_glbl.F90 (global state variables)             │
    │  ├─ schism_init.F90 (initialization)                     │
    │  ├─ schism_step.F90 (one time step)                      │
    │  └─ schism_finalize.F90 (cleanup)                        │
    │                                                           │
    └───────────────────────────────────────────────────────────┘
```

### 🔑 Critical Difference: Where State Lives

This is the **MOST important concept** to understand:

```
    HEAT MODEL:                          SCHISM MODEL:
    ─────────────                        ─────────────
    State is EMBEDDED                    State is GLOBAL
    in the wrapper type                  in module variables

    type :: bmi_heat                     type :: bmi_schism
      type(heat_model) :: model            type(schism_type) :: model  ← config only!
    end type                             end type

    this%model%temperature  ✅           this%model%ETA2  ❌ NOT USED!
                                         eta2 from schism_glbl  ✅ GLOBAL!

    ┌─────────────┐                      ┌─────────────┐
    │  bmi_heat   │                      │ bmi_schism  │
    │ ┌─────────┐ │                      │ ┌─────────┐ │
    │ │  model   │ │◄── ALL state        │ │  model   │ │◄── config/time only
    │ │ temp[][] │ │    lives here        │ │ dt, dir  │ │
    │ │ alpha    │ │                      │ └─────────┘ │
    │ │ dt, t    │ │                      │             │
    │ └─────────┘ │                      │  schism_glbl │◄── REAL state
    └─────────────┘                      │  eta2(:)     │    lives here
                                         │  uu2(:,:)    │    (global module
                                         │  vv2(:,:)    │     variables)
                                         └─────────────┘
```

> **ML Analogy:**
>
> - **Heat** = All weights stored in `model.state_dict()` — clean, self-contained
> - **SCHISM** = Some weights in `model.state_dict()`, but most in global `torch.cuda` memory — messy but practical for large legacy models
>
> **WRF-Hydro will be more like SCHISM** — state lives in global module variables like `RT_DOMAIN(did)%QLINK`, not embedded in our wrapper type.

### 🧬 Concept 1: The Container Type (Config Only)

SCHISM's container holds ONLY configuration — NOT physics state:

```
    ┌──────────────────────────────────────┐
    │     type :: schism_type              │
    ├──────────────────────────────────────┤
    │  ⏰ Time Management                 │
    │  ├─ model_start_time                │
    │  ├─ model_end_time                  │
    │  ├─ current_model_time              │
    │  ├─ time_step_size                  │
    │  ├─ num_time_steps                  │
    │  ├─ iths (current step counter)     │
    │  └─ ntime (total steps)             │
    ├──────────────────────────────────────┤
    │  📁 Config                          │
    │  ├─ SCHISM_dir (path to run dir)    │
    │  └─ SCHISM_NSCRIBES (I/O procs)     │
    ├──────────────────────────────────────┤
    │  🔌 MPI                             │
    │  └─ given_communicator              │
    ├──────────────────────────────────────┤
    │  ⚠️ Placeholder physics vars        │
    │  ├─ ETA2, LatQ, SFCPRS, etc.        │
    │  └─ (NOT actually used by wrapper!) │
    └──────────────────────────────────────┘

    The REAL physics state (eta2, uu2, vv2, dp, etc.)
    lives in schism_glbl — a massive global module
    with hundreds of variables!
```

### 🧬 Concept 2: Global State Access via `use schism_glbl`

Instead of `this%model%temperature`, SCHISM BMI directly imports global arrays:

```
    bmischism.f90 imports (line 9-24):

    use schism_glbl, only:
    ├─ 🌊 eta2          → water surface elevation (output)
    ├─ ➡️ uu2, vv2      → current velocities (output)
    ├─ 📍 dp             → depth/bed level (output)
    ├─ 📊 sta_out_gb     → station outputs (output)
    ├─ 💨 windx1, windx2 → wind at t0, t1 (input, t0/t1 pair)
    ├─ 💨 windy1, windy2 → wind at t0, t1 (input, t0/t1 pair)
    ├─ 🌡️ airt1, airt2   → air temp at t0, t1 (input, t0/t1 pair)
    ├─ 📊 pr1, pr2       → pressure at t0, t1 (input, t0/t1 pair)
    ├─ 💧 shum1, shum2   → humidity at t0, t1 (input, t0/t1 pair)
    ├─ 🌊 ath2           → open boundary water levels (t0/t1)
    ├─ 🏞️ ath3           → source/sink discharge (t0/t1)
    ├─ 🔺 elnode, i34    → mesh connectivity
    ├─ 📐 xlon, ylat     → node coordinates
    └─ 📏 area, dp       → element areas, depths
```

> **ML Analogy:** Think of `schism_glbl` as a massive `global_state = {}` dictionary that SCHISM populates during initialization. The BMI wrapper just reads/writes to this shared state — it doesn't own it.

### 🧬 Concept 3: Initialize → Delegate to SCHISM

SCHISM BMI's initialize does NOT set up physics — it delegates to SCHISM's own init:

```
    schism_initialize(config_file):

    Step 1: Read BMI config file (namelist format)
    ┌─────────────────────────────────┐
    │  read_init_config()             │
    │  ├─ model_start_time = 0.0     │
    │  ├─ model_end_time = 86400.0   │
    │  ├─ time_step_size = 3600      │
    │  ├─ SCHISM_dir = "/path/to/"   │
    │  └─ SCHISM_NSCRIBES = 0        │
    └─────────────────────────────────┘
                │
                ▼
    Step 2: Compute time parameters
    ┌─────────────────────────────────┐
    │  num_time_steps = (end - start) │
    │                  / time_step    │
    └─────────────────────────────────┘
                │
                ▼
    Step 3: Initialize MPI
    ┌─────────────────────────────────┐
    │  call parallel_init(communicator)│
    └─────────────────────────────────┘
                │
                ▼
    Step 4: Call SCHISM's own init
    ┌─────────────────────────────────┐
    │  call schism_init(0, dir,       │
    │                   iths, ntime)  │
    │  └─► This sets up ALL of        │
    │      schism_glbl variables!     │
    │      (mesh, arrays, etc.)       │
    └─────────────────────────────────┘
```

### 🧬 Concept 4: Update = Increment Counter + Call schism_step

```
    schism_update():

    ┌───────────────────────────────────────┐
    │  this%model%iths = this%model%iths + 1│  ← Increment step counter
    │  call schism_step(this%model%iths)    │  ← Advance SCHISM one step
    │  return BMI_SUCCESS                   │
    └───────────────────────────────────────┘

    That's it! Just 2 lines of real work.
    SCHISM does everything internally via schism_step().
```

> **ML Analogy:** Like calling `optimizer.step()` — you don't implement gradient descent yourself, you just tell the optimizer to take one step.

### 🧬 Concept 5: Finalize = Cleanup + MPI Shutdown

```
    schism_finalizer():

    ┌───────────────────────────────┐
    │  call schism_finalize         │  ← SCHISM's own cleanup
    │  call parallel_finalize       │  ← Shut down MPI
    │  return BMI_SUCCESS           │
    └───────────────────────────────┘
```

### 🧬 Concept 6: NextGen Registration (Conditional Compilation)

SCHISM BMI supports two compilation modes:

```
    #ifdef NGEN_ACTIVE                    #else (standard BMI)
    ┌───────────────────────┐            ┌───────────────────────┐
    │ use bmif_2_0_iso      │            │ use bmif_2_0          │
    │ (ISO C binding for    │            │ (standard Fortran     │
    │  NextGen framework)   │            │  BMI module)          │
    │                       │            │                       │
    │ + register_bmi()      │            │ No register_bmi()     │
    │   function at bottom  │            │ needed                │
    └───────────────────────┘            └───────────────────────┘

    register_bmi() creates a bmi_schism instance and returns
    a C pointer to it — this is how NextGen "discovers" the model.
```

---

## 6. 📥 SCHISM BMI Input Variables (Detailed)

### 📊 Complete Input Variable Table

| # | Variable Name | Description | Units | Grid | Location | Data Type |
|---|--------------|-------------|-------|------|----------|-----------|
| 1 | 🏞️ `Q_bnd_source` | River discharge into ocean (sources) | m3/s | SOURCE_ELEMENTS (4) | face | double |
| 2 | 🚰 `Q_bnd_sink` | Water extraction from ocean (sinks) | m3/s | SINK_ELEMENTS (5) | face | double |
| 3 | 🌊 `ETA2_bnd` | Water levels at open ocean boundary | m | OFFSHORE_BOUNDARY (3) | node | double |
| 4 | 📊 `SFCPRS` | Surface atmospheric pressure | Pa | ALL_NODES (1) | node | double |
| 5 | 🌡️ `TMP2m` | 2-meter air temperature | K | ALL_NODES (1) | node | double |
| 6 | 💨 `U10m` | 10m wind speed (eastward) | m/s | ALL_NODES (1) | node | double |
| 7 | 💨 `V10m` | 10m wind speed (northward) | m/s | ALL_NODES (1) | node | double |
| 8 | 💧 `SPFH2m` | Specific humidity at 2m | kg/kg | ALL_NODES (1) | node | double |
| 9 | 🌧️ `RAINRATE` | Precipitation rate | kg/m2/s | ALL_ELEMENTS (2) | face | double |
| 10 | ⏰ `ETA2_dt` | Time step for water level boundary updates | s | ETA2_TIMESTEP (7) | scalar | double |
| 11 | ⏰ `Q_dt` | Time step for discharge source/sink updates | s | Q_TIMESTEP (8) | scalar | double |
| 12 | 🔌 `bmi_mpi_comm_handle` | MPI communicator handle | - | MPI_COMM (9) | scalar | integer |

### 🗂️ Input Variables by Category

```
    🌤️ ATMOSPHERIC FORCING (5 vars) — applied at ALL mesh nodes:
    ├─ SFCPRS  (pressure)      ─── drives pressure gradient forces
    ├─ TMP2m   (temperature)   ─── drives heat exchange
    ├─ U10m    (east wind)     ─── drives wind stress on water
    ├─ V10m    (north wind)    ─── drives wind stress on water
    └─ SPFH2m  (humidity)      ─── drives evaporation

    🌊 BOUNDARY CONDITIONS (3 vars) — applied at domain edges:
    ├─ ETA2_bnd     (water levels at open ocean boundary)
    ├─ Q_bnd_source (river discharge INTO domain)
    └─ Q_bnd_sink   (water extraction FROM domain)

    🌧️ PRECIPITATION (1 var) — applied at ALL mesh elements:
    └─ RAINRATE  (rain rate, converted to discharge flux)

    ⏰ TIME CONTROL (2 vars) — scalar values:
    ├─ ETA2_dt  (how often to update water level boundaries)
    └─ Q_dt     (how often to update discharge boundaries)

    🔌 SYSTEM (1 var) — scalar value:
    └─ bmi_mpi_comm_handle  (MPI communicator from framework)
```

> **ML Analogy:** These inputs are like a multi-modal model's input channels:
> - Atmospheric forcing = image features (spatial, applied everywhere)
> - Boundary conditions = edge padding / boundary tokens
> - RAINRATE = augmentation that accumulates
> - Time control = learning rate schedule
> - MPI handle = distributed training communicator

---

## 7. 📤 SCHISM BMI Output Variables (Detailed)

### 📊 Complete Output Variable Table

| # | Variable Name | Description | Units | Grid | Data Source |
|---|--------------|-------------|-------|------|-------------|
| 1 | 🌊 `ETA2` | Water surface elevation | m | ALL_NODES (1) | `eta2(:)` from schism_glbl |
| 2 | ➡️ `VX` | Eastward current velocity | m/s | ALL_NODES (1) | `uu2(1,:)` from schism_glbl |
| 3 | ⬆️ `VY` | Northward current velocity | m/s | ALL_NODES (1) | `vv2(1,:)` from schism_glbl |
| 4 | 📍 `TROUTE_ETA2` | Water levels at T-Route stations | m | STATION_POINTS (6) | `sta_out_gb(:,1)` |
| 5 | 🏖️ `BEDLEVEL` | Bed elevation above datum | m | ALL_NODES (1) | `-1.0 * dp(:)` (inverted!) |

### 🗂️ Output Variables Explained

```
    📤 SCHISM OUTPUTS:

    🌊 ETA2 — "The Main Product"
    ├─ What: Water surface height above/below datum (like sea level)
    ├─ Size: One value per mesh node (can be millions!)
    ├─ Used for: Flood mapping, coastal inundation, storm surge
    └─ THIS is what WRF-Hydro needs from SCHISM for 2-way coupling!

    ➡️ VX + ⬆️ VY — "Current Velocity Vector"
    ├─ What: Water flow direction and speed at surface
    ├─ Size: One 2D vector per mesh node
    ├─ Note: Only surface layer (index 1) exposed via BMI
    └─ Used for: Navigation, sediment transport, oil spill tracking

    📍 TROUTE_ETA2 — "Station Measurements"
    ├─ What: Water levels at specific monitoring stations
    ├─ Size: One value per station (defined in station.in file)
    ├─ Special: Uses station interpolation, not raw node values
    └─ Used for: T-Route integration, validation against tide gauges

    🏖️ BEDLEVEL — "Ocean Floor Elevation"
    ├─ What: Bed elevation relative to datum
    ├─ Size: One value per mesh node
    ├─ Note: INVERTED from SCHISM internal (dp is depth below datum)
    │         BEDLEVEL = -1.0 * dp (positive = above datum)
    └─ Used for: Understanding bathymetry, sanity checks
```

### 🔗 Coupling Variables (What Flows Between Models)

```
    ┌──────────────┐                      ┌──────────────┐
    │  WRF-Hydro   │   Q_bnd_source       │   SCHISM     │
    │              ├─────────────────────►│              │
    │  OUTPUT:     │   (river discharge)  │  INPUT:      │
    │  QLINK       │                      │  Q_bnd_source│
    │              │                      │              │
    │  INPUT:      │   ETA2               │  OUTPUT:     │
    │  (coastal    │◄─────────────────────┤  ETA2        │
    │   water lvl) │   (water levels)     │              │
    └──────────────┘                      └──────────────┘

    1-WAY coupling (currently possible):
    WRF-Hydro discharge → SCHISM Q_bnd_source ✅

    2-WAY coupling (needs WRF-Hydro additions):
    SCHISM ETA2 → WRF-Hydro coastal boundary ⚠️ Not yet implemented
```

---

## 8. 🗺️ SCHISM BMI Grid System

### 📊 The 9 Named Grid Constants

SCHISM defines **9 different grids** for different variable domains:

```
    ┌────┬─────────────────────────────┬─────────────┬──────┬────────────────┐
    │ ID │ Grid Name                   │ Type        │ Rank │ What It Holds  │
    ├────┼─────────────────────────────┼─────────────┼──────┼────────────────┤
    │  1 │ GRID_ALL_NODES              │ unstructured│  2   │ ETA2,VX,VY,    │
    │    │                             │             │      │ SFCPRS,TMP2m,  │
    │    │                             │             │      │ winds,humidity, │
    │    │                             │             │      │ BEDLEVEL       │
    ├────┼─────────────────────────────┼─────────────┼──────┼────────────────┤
    │  2 │ GRID_ALL_ELEMENTS           │ points      │  2   │ RAINRATE       │
    ├────┼─────────────────────────────┼─────────────┼──────┼────────────────┤
    │  3 │ GRID_OFFSHORE_BOUNDARY_PTS  │ points      │  2   │ ETA2_bnd       │
    ├────┼─────────────────────────────┼─────────────┼──────┼────────────────┤
    │  4 │ GRID_SOURCE_ELEMENTS        │ points      │  1   │ Q_bnd_source   │
    ├────┼─────────────────────────────┼─────────────┼──────┼────────────────┤
    │  5 │ GRID_SINK_ELEMENTS          │ points      │  1   │ Q_bnd_sink     │
    ├────┼─────────────────────────────┼─────────────┼──────┼────────────────┤
    │  6 │ GRID_STATION_POINTS         │ points      │  2   │ TROUTE_ETA2    │
    ├────┼─────────────────────────────┼─────────────┼──────┼────────────────┤
    │  7 │ ETA2_TIMESTEP               │ scalar      │  1   │ ETA2_dt        │
    ├────┼─────────────────────────────┼─────────────┼──────┼────────────────┤
    │  8 │ Q_TIMESTEP                  │ scalar      │  1   │ Q_dt           │
    ├────┼─────────────────────────────┼─────────────┼──────┼────────────────┤
    │  9 │ MPI_COMMUNICATOR            │ scalar      │  1   │ bmi_mpi_comm   │
    └────┴─────────────────────────────┴─────────────┴──────┴────────────────┘
```

### 🔺 Grid Types Explained

```
    1️⃣ "unstructured" (Grid 1 only):
    Full triangle/quad mesh with node/edge/face connectivity
    ├─ Has: get_grid_x/y/z, node_count, edge_count, face_count
    ├─ Has: edge_nodes, face_nodes, face_edges, nodes_per_face
    └─ Does NOT have: shape, spacing, origin (not applicable!)

    *─────*
    |\   /|        Triangles (i34=3) and Quads (i34=4)
    | \ / |        connected by edges
    |  *  |        Variable spacing everywhere
    | / \ |
    |/   \|
    *─────*

    2️⃣ "points" (Grids 2-6):
    Collection of points with x,y,z coordinates but NO connectivity
    ├─ Has: get_grid_x/y (coordinates)
    └─ No mesh topology (just scatter points)

    *     *         Just dots in space
       *        *   No connections between them
    *       *

    3️⃣ "scalar" (Grids 7-9):
    Single value, no spatial extent
    ├─ size = 1
    └─ No coordinates needed

    [42.0]          Just a number
```

> **ML Analogy:**
> - "unstructured" = graph data (like in PyG/DGL)
> - "points" = point cloud (like in PointNet)
> - "scalar" = single hyperparameter value

### ⚠️ Key Grid Behavior

```
    ┌────────────────────────────────────────────────────────┐
    │  SCHISM Grid Functions That Return BMI_FAILURE:        │
    │                                                        │
    │  ❌ get_grid_shape()   — No shape for unstructured!   │
    │  ❌ get_grid_spacing() — No uniform spacing!          │
    │  ❌ get_grid_origin()  — No single origin!            │
    │  ❌ get_value_ptr()    — Not implemented for any var  │
    │  ❌ set_value_float()  — All vars are double precision│
    │  ❌ get_value_int()    — No integer outputs           │
    │                                                        │
    │  This is NORMAL — BMI says "return BMI_FAILURE for    │
    │  functions that don't apply to your model."           │
    └────────────────────────────────────────────────────────┘
```

---

## 9. 🔄 Key Differences: Heat vs SCHISM BMI

### 📊 Side-by-Side Comparison Table

| Aspect | 🔥 Heat BMI | 🌊 SCHISM BMI |
|--------|------------|---------------|
| **Model Size** | 158 lines | 437 files, 100K+ lines |
| **Wrapper Size** | 935 lines | 1,729 lines |
| **State Storage** | Embedded in type (`this%model%temp`) | Global modules (`schism_glbl`) |
| **Grid Type** | uniform_rectilinear | unstructured mesh |
| **Grid Count** | 2 (grid + scalar) | 9 (mesh + points + scalars) |
| **Input Vars** | 3 | 12 |
| **Output Vars** | 1 | 5 |
| **Data Types** | real (32-bit float) | double precision (64-bit) |
| **MPI** | None (serial only) | Full MPI support |
| **Config Format** | Simple text file (4 numbers) | Fortran namelist |
| **Init Complexity** | Read file, allocate arrays | Read config, init MPI, call schism_init |
| **Update** | Call advance_in_time() | Increment counter, call schism_step() |
| **Finalize** | Deallocate arrays | Call schism_finalize + parallel_finalize |
| **get_value_ptr** | Implemented (c_loc/c_f_pointer) | Returns BMI_FAILURE for all |
| **set_value pattern** | Direct assignment | t0/t1 sliding window |
| **Compilation** | Standard | Conditional (#ifdef NGEN_ACTIVE) |
| **Array handling** | reshape() for 2D→1D | Direct 1D arrays (already flat) |

### 🧠 Architecture Pattern Comparison

```
    HEAT (Simple/Clean):               SCHISM (Production/Complex):

    ┌────────────┐                     ┌────────────┐
    │ bmi_heat   │                     │bmi_schism  │
    │ ┌────────┐ │                     │ ┌────────┐ │
    │ │ model  │ │ ◄── EVERYTHING      │ │ model  │ │ ◄── config/time only
    │ │ temp   │ │     is here         │ │ dt,dir │ │
    │ │ alpha  │ │                     │ └────────┘ │
    │ │ dt,t   │ │                     │            │
    │ └────────┘ │                     │ schism_glbl│ ◄── physics state
    └────────────┘                     │ eta2,uu2   │     is GLOBAL
                                       │ vv2,dp     │
                                       └────────────┘

    "Everything in one box"             "Config in box, state outside"
    Like a self-contained               Like a controller that
    nn.Module                           reads/writes shared memory
```

---

## 10. 🔄 The t0/t1 Sliding Window Pattern

### 🎯 What Is It?

SCHISM uses **two time slots** for every forcing variable — a "previous" (t0) and "current" (t1) value. When new data arrives, the old t1 slides to t0, and the new data goes into t1.

### 📊 The Pattern

```
    BEFORE set_value("SFCPRS", new_data):

    ┌──────────────┐    ┌──────────────┐
    │  pr1 (t0)    │    │  pr2 (t1)    │
    │  = 101300    │    │  = 101325    │
    │  (old data)  │    │  (current)   │
    └──────────────┘    └──────────────┘


    AFTER set_value("SFCPRS", [101350]):

    ┌──────────────┐    ┌──────────────┐
    │  pr1 (t0)    │    │  pr2 (t1)    │
    │  = 101325    │    │  = 101350    │
    │  (was t1!)   │    │  (NEW data)  │
    └──────────────┘    └──────────────┘
         ▲                    ▲
         │                    │
         └─ old t1 slides     └─ new data goes
            to become t0         into t1
```

### 🔁 Implementation Pattern (Same for All Forcing Vars)

```
    For EVERY atmospheric forcing variable, the set pattern is:

    ! Step 1: Slide old t1 → t0
    var_t0(:) = var_t1(:)

    ! Step 2: Store new data in t1
    var_t1(:) = new_data(:)

    Applied to:
    ├─ pr1/pr2       (SFCPRS - pressure)
    ├─ airt1/airt2   (TMP2m - temperature)
    ├─ windx1/windx2 (U10m - east wind)
    ├─ windy1/windy2 (V10m - north wind)
    ├─ shum1/shum2   (SPFH2m - humidity)
    ├─ ath2(:,:,t0)/ath2(:,:,t1)  (ETA2_bnd - boundary water levels)
    └─ ath3(:,:,t0)/ath3(:,:,t1)  (Q_bnd_source/sink - discharge)
```

> **ML Analogy: Exponential Moving Average (EMA)**
>
> This is similar to how EMA works in training:
> ```python
> # EMA update:
> shadow_weight = decay * shadow_weight + (1 - decay) * current_weight
>
> # SCHISM t0/t1 update:
> t0_value = t1_value        # old "current" becomes "previous"
> t1_value = new_value        # new data becomes "current"
> ```
>
> SCHISM then **interpolates between t0 and t1** during each sub-timestep, creating smooth transitions rather than abrupt jumps.

### ❓ Why Does SCHISM Do This?

```
    WITHOUT t0/t1 (abrupt):          WITH t0/t1 (smooth):

    Pressure                          Pressure
    │     ┌────                       │     ╱────
    │     │                           │    ╱
    │─────┘                           │───╱
    │                                 │
    └────────── time                  └────────── time

    Sudden jump causes                Gradual transition is
    numerical instabilities!          physically realistic
```

---

## 11. 🌧️ RAINRATE — The Special Variable

### ⚠️ Why RAINRATE Breaks the Pattern

Every other variable uses the t0/t1 slide-and-replace pattern. But RAINRATE is different — it **ADDS** to existing values instead of replacing them:

```
    NORMAL pattern (e.g., SFCPRS):          RAINRATE pattern:

    pr1 = pr2              (slide)          ! NO slide!
    pr2 = src              (replace)        ath3(:,1,2,1) = ath3(:,1,2,1)
                                                          + (src * area / 1000)
                                                            ▲
                                                            │ ADDS to existing!
```

### 🔍 Why Does RAINRATE Add Instead of Replace?

```
    The call ORDER matters:

    1. First:  set_value("Q_bnd_source", river_discharge)
               └─► Sets ath3 t1 = river discharge values

    2. Second: set_value("RAINRATE", rain_rate)
               └─► ADDS rain contribution ON TOP of river discharge
                   ath3_t1 = ath3_t1 + (rain * area / 1000)

    Because rain and river discharge BOTH contribute to
    the same source term (ath3), rain must ADD to it,
    not replace it!
```

> **ML Analogy:** It's like residual connections in ResNet:
> ```python
> # Normal layer: output = new_value
> # Residual layer: output = existing_value + new_contribution
> ```
> RAINRATE uses a residual/additive pattern because it contributes to an already-set source term.

### 📐 The Unit Conversion

```
    RAINRATE comes in:  kg/m2/s (mass flux per area)
    SCHISM needs:       m3/s    (volume flux per element)

    Conversion: Q_rain = RAINRATE * element_area / 1000
                         ▲          ▲               ▲
                         │          │               │
                    kg/m2/s    m2 (mesh      kg/m3 (water
                              element area)  density ≈ 1000)
```

---

## 12. 🚀 How WRF-Hydro BMI Should Be Implemented

### 🏗️ Our Architecture (Following SCHISM's Pattern)

WRF-Hydro is much more like SCHISM than the Heat example:

```
    ┌────────────────────────────────────────────────────────┐
    │              WRF-Hydro BMI Architecture                 │
    ├────────────────────────────────────────────────────────┤
    │                                                        │
    │  📄 bmi_wrf_hydro.f90 (~1,500-2,000 lines estimated) │
    │  ├─ type, extends(bmi) :: bmi_wrf_hydro               │
    │  ├─ type(wrf_hydro_type) :: model  ← config/time      │
    │  ├─ All 41 BMI functions                              │
    │  └─ Uses WRF-Hydro globals for physics state          │
    │                                                        │
    │  📁 WRF-Hydro source (existing, UNTOUCHED)            │
    │  ├─ module_HYDRO_drv.F90   → HYDRO_ini/exe/finish    │
    │  ├─ module_NoahMP_hrldas_driver.F → land_driver_*    │
    │  ├─ module_rt_inc.F90 → RT_FIELD type (state vars)   │
    │  └─ main_hrldas_driver.F → original entry point       │
    │                                                        │
    └────────────────────────────────────────────────────────┘
```

### 📋 Step-by-Step Implementation Plan

```
    Phase 1: Container Type
    ┌─────────────────────────────────────────────┐
    │  type :: wrf_hydro_type                     │
    │  ├─ model_start_time                        │
    │  ├─ model_end_time                          │
    │  ├─ current_model_time                      │
    │  ├─ time_step_size                          │
    │  ├─ config_dir (path to namelist directory) │
    │  └─ timestep_count                          │
    │                                             │
    │  type, extends(bmi) :: bmi_wrf_hydro        │
    │    type(wrf_hydro_type) :: model             │
    │  end type                                   │
    └─────────────────────────────────────────────┘

    Phase 2: IRF Decomposition (THE HARDEST PART)
    ┌─────────────────────────────────────────────┐
    │  initialize(config_file):                   │
    │  ├─ Read config (path to namelists)         │
    │  ├─ call land_driver_ini()  ← Noah-MP init  │
    │  └─ call HYDRO_ini()        ← Routing init  │
    │                                             │
    │  update():                                  │
    │  ├─ call land_driver_exe()  ← 1 land step   │
    │  ├─ call HYDRO_exe()        ← 1 hydro step  │
    │  └─ current_time += dt                      │
    │                                             │
    │  finalize():                                │
    │  └─ call HYDRO_finish()     ← cleanup       │
    └─────────────────────────────────────────────┘

    Phase 3: Variable Mapping
    ┌─────────────────────────────────────────────┐
    │  get_value("channel_water__volume_flow_rate")│
    │  └─► return RT_DOMAIN(did)%QLINK(:,1)      │
    │                                             │
    │  get_value("land_surface_water__depth")      │
    │  └─► return RT_DOMAIN(did)%sfcheadrt(:,:)   │
    │       reshaped to 1D!                       │
    │                                             │
    │  set_value("sea_water_surface__elevation")   │
    │  └─► write to coastal boundary array        │
    └─────────────────────────────────────────────┘

    Phase 4: Grid Definitions
    ┌─────────────────────────────────────────────┐
    │  Grid 0: uniform_rectilinear (1km)          │
    │  └─ Noah-MP land surface variables          │
    │                                             │
    │  Grid 1: uniform_rectilinear (250m)         │
    │  └─ Terrain routing variables               │
    │                                             │
    │  Grid 2: vector/network                     │
    │  └─ Channel routing (reaches)               │
    └─────────────────────────────────────────────┘
```

### 🎯 Key Variables to Expose (Starting Set)

```
    📤 OUTPUT VARIABLES (what WRF-Hydro produces):
    ┌────────────────────────────────────────────────────────────────┐
    │ # │ Internal Name   │ CSDMS Standard Name                    │ Units │
    ├───┼────────────────┼───────────────────────────────────────  ┼───────┤
    │ 1 │ QLINK(:,1)     │ channel_water__volume_flow_rate        │ m3/s  │
    │ 2 │ sfcheadrt      │ land_surface_water__depth              │ m     │
    │ 3 │ SOIL_M         │ soil_water__volume_fraction            │ -     │
    │ 4 │ SNEQV          │ snowpack__liquid-equivalent_depth      │ m     │
    │ 5 │ ACCET          │ land_surface_water__evaporation_vol_flux│ mm   │
    │ 6 │ T2             │ land_surface_air__temperature          │ K     │
    │ 7 │ UGDRNOFF       │ soil_water__baseflow_volume_flux       │ mm    │
    └───┴────────────────┴────────────────────────────────────────┴───────┘

    📥 INPUT VARIABLES (what WRF-Hydro receives):
    ┌────────────────────────────────────────────────────────────────┐
    │ # │ Internal Name   │ CSDMS Standard Name                    │ Units │
    ├───┼────────────────┼────────────────────────────────────────┼───────┤
    │ 1 │ RAINRATE       │ atmosphere_water__precipitation_flux    │ mm/s  │
    │ 2 │ (coastal_elev) │ sea_water_surface__elevation           │ m     │
    └───┴────────────────┴────────────────────────────────────────┴───────┘
```

### 🔑 What Makes WRF-Hydro Different from Both

```
    ┌──────────────────────────────────────────────────────────┐
    │  WRF-Hydro UNIQUE CHALLENGES:                            │
    │                                                          │
    │  1. 🔄 DUAL TIME LOOPS                                  │
    │     Noah-MP runs at 3600s, Hydro routing at 10s          │
    │     One update() call = 1 Noah-MP step + N hydro steps   │
    │     (Like a model with inner and outer training loops)   │
    │                                                          │
    │  2. 📐 MULTI-RESOLUTION GRIDS                           │
    │     1km (land) + 250m (routing) + network (channels)     │
    │     Need multiple grid IDs for different variable types  │
    │                                                          │
    │  3. 📦 DOMAIN ARRAY ACCESS                              │
    │     State lives in RT_DOMAIN(did)% not simple globals    │
    │     Need to handle domain index (did = 1 for serial)     │
    │                                                          │
    │  4. 🔗 LEGACY FORTRAN 77/90 PATTERNS                   │
    │     Common blocks, assumed-shape arrays, implicit typing │
    │     More "archaeological" work than SCHISM               │
    │                                                          │
    │  5. ⚙️ CONFIG PASS-THROUGH                              │
    │     BMI config file just points to namelist directory     │
    │     WRF-Hydro reads its own namelist.hrldas + hydro.nml  │
    └──────────────────────────────────────────────────────────┘
```

### 🗺️ Implementation Roadmap

```
    ┌──────┐     ┌──────┐     ┌──────┐     ┌──────┐     ┌──────┐
    │Step 1│────►│Step 2│────►│Step 3│────►│Step 4│────►│Step 5│
    │Stub  │     │IRF   │     │Vars  │     │Grids │     │Test  │
    └──────┘     └──────┘     └──────┘     └──────┘     └──────┘

    Step 1: Write skeleton bmi_wrf_hydro.f90
    ├─ All 41 functions returning BMI_FAILURE
    ├─ Container type with config fields
    ├─ Verify it compiles against bmif_2_0
    └─ ⏱️ ~1 day

    Step 2: Implement IRF (Initialize-Run-Finalize)
    ├─ initialize() calls land_driver_ini + HYDRO_ini
    ├─ update() calls land_driver_exe + HYDRO_exe
    ├─ finalize() calls HYDRO_finish
    ├─ THIS IS THE HARDEST PART — time loop extraction
    └─ ⏱️ ~3-5 days

    Step 3: Implement variable get/set
    ├─ Start with QLINK (streamflow) — the #1 coupling variable
    ├─ Add 5-6 more key outputs
    ├─ Add RAINRATE input
    ├─ Use select case dispatch (same as Heat/SCHISM)
    └─ ⏱️ ~2-3 days

    Step 4: Implement grid functions
    ├─ Grid 0: 1km uniform_rectilinear (read from geo_em)
    ├─ Grid 1: 250m uniform_rectilinear (read from Fulldom)
    ├─ Grid 2: vector/network (channel reaches)
    └─ ⏱️ ~2-3 days

    Step 5: Test with Fortran driver
    ├─ Write bmi_main.f90 for WRF-Hydro
    ├─ Run Croton NY test case through BMI
    ├─ Compare output to standalone run
    └─ ⏱️ ~2-3 days
```

---

## 13. 🔄 WRF-Hydro vs Heat vs SCHISM Comparison

### 📊 Three-Way Architecture Comparison

| Feature | 🔥 Heat | 🌊 SCHISM | 🏔️ WRF-Hydro (planned) |
|---------|---------|-----------|------------------------|
| **State Location** | Embedded type | Global module | Global module (RT_DOMAIN) |
| **Physics Complexity** | 1 equation | 100s of equations | 100s of equations |
| **Grid** | Regular 2D | Unstructured triangles | Regular 2D + network |
| **Grid Count** | 2 | 9 | 3 (planned) |
| **Input Vars** | 3 | 12 | ~2-10 (starting small) |
| **Output Vars** | 1 | 5 | ~7-15 (starting small) |
| **Init Calls** | 1 (initialize_from_file) | 2 (parallel_init + schism_init) | 2 (land_driver_ini + HYDRO_ini) |
| **Update Calls** | 1 (advance_in_time) | 1 (schism_step) | 2 (land_driver_exe + HYDRO_exe) |
| **MPI** | No | Yes | Start serial, add later |
| **Config** | Plain text (4 values) | Namelist | Pass-through to namelists |
| **Conditional Compile** | No | #ifdef NGEN_ACTIVE | #ifdef USE_NWM_BMI (planned) |
| **Time Step** | Uniform | Uniform | DUAL (3600s land + 10s routing) |
| **Data Type** | real (32-bit) | double (64-bit) | Mixed (real + double) |
| **Wrapper Size** | 935 lines | 1,729 lines | ~1,500-2,000 estimated |

### 🧠 Which Pattern Should We Follow?

```
    HEAT PATTERN (use for):           SCHISM PATTERN (use for):
    ├─ Type structure                 ├─ Global state access
    ├─ select case dispatch           ├─ Config-only container type
    ├─ Array flattening (reshape)     ├─ Delegating to model init/step/finalize
    ├─ get_value_ptr (c_loc)          ├─ Multiple grids for different var types
    ├─ update_until (loop logic)      ├─ Namelist config reading
    └─ BMI_FAILURE for unsupported    ├─ Conditional compilation (#ifdef)
       functions                       ├─ MPI communicator handling
                                       └─ Variable info functions pattern

    WRF-Hydro BMI = HEAT's simplicity + SCHISM's real-world patterns
```

---

## 14. 📚 Quick Reference & Glossary

### 🔤 Key Terms

| Term | ML Equivalent | Definition |
|------|---------------|------------|
| **BMI** | `nn.Module` interface | Standard 41-function API for model coupling |
| **IRF** | train/eval/cleanup | Initialize-Run-Finalize pattern |
| **Derived type** | Python class | Fortran's way of grouping data and methods |
| **Type extension** | Subclass / inheritance | `type, extends(parent) :: child` |
| **select case** | dict lookup / if-elif chain | Variable dispatch mechanism |
| **reshape** | tensor.flatten() | Convert 2D array to 1D for BMI |
| **Namelist** | YAML/JSON config | Fortran's config file format |
| **schism_glbl** | global state dict | Module holding all SCHISM physics variables |
| **RT_DOMAIN** | model.state_dict() | WRF-Hydro's routing state container |
| **t0/t1 pattern** | EMA / sliding window | Two-slot temporal interpolation |
| **CSDMS Standard Names** | Feature names | Standardized variable naming convention |
| **Babelizer** | ONNX converter | Tool to make Fortran BMI callable from Python |
| **PyMT** | Model hub / orchestrator | Python framework for coupled model runs |
| **BMI_SUCCESS** | return 0 | Function completed successfully |
| **BMI_FAILURE** | raise Exception | Function failed or not applicable |
| **c_loc / c_f_pointer** | ctypes / cffi | Fortran ↔ C memory pointer interop |

### 📁 Key File Locations

```
    📦 Reference Implementations:
    ├─ bmi-fortran/bmi.f90                              ← Abstract BMI interface
    ├─ bmi-example-fortran/heat/heat.f90                ← Heat physics model
    ├─ bmi-example-fortran/bmi_heat/bmi_heat.f90        ← Heat BMI wrapper (TEMPLATE)
    ├─ bmi-example-fortran/bmi_heat/bmi_main.f90        ← Heat BMI driver
    ├─ SCHISM_BMI/src/BMI/bmischism.f90                 ← SCHISM BMI wrapper
    └─ SCHISM_BMI/src/BMI/schism_model_container.f90    ← SCHISM config type

    🏔️ WRF-Hydro Source (what we're wrapping):
    ├─ wrf_hydro_nwm_public/src/Land_models/NoahMP/IO_code/
    │  ├─ main_hrldas_driver.F                          ← Entry point (time loop)
    │  └─ module_NoahMP_hrldas_driver.F                 ← land_driver_ini/exe
    ├─ wrf_hydro_nwm_public/src/HYDRO_drv/
    │  └─ module_HYDRO_drv.F90                          ← HYDRO_ini/exe/finish
    └─ wrf_hydro_nwm_public/src/Data_Rec/
       └─ module_rt_inc.F90                             ← RT_FIELD type

    ✍️ Our Work:
    └─ bmi_wrf_hydro/                                   ← Where bmi_wrf_hydro.f90 goes
```

### 🏁 Summary: The Path Forward

```
    WHERE WE ARE:                      WHERE WE'RE GOING:

    ✅ Studied Heat BMI (template)     → Use its patterns
    ✅ Studied SCHISM BMI (real-world) → Use its architecture
    ✅ WRF-Hydro compiled & running    → Ready to wrap
    ✅ IRF subroutines identified      → Ready to decompose
    ✅ Variables mapped to CSDMS names → Ready to expose
    ✅ Master Plan created             → Ready to execute

    NEXT STEP: Write bmi_wrf_hydro.f90!

    ┌─────────────────────────────────────────────┐
    │  The formula:                                │
    │                                              │
    │  Heat's clean patterns                       │
    │  + SCHISM's real-world architecture          │
    │  + WRF-Hydro's existing IRF subroutines      │
    │  ═══════════════════════════════════════      │
    │  bmi_wrf_hydro.f90 🎉                       │
    └─────────────────────────────────────────────┘
```

---

> 📝 **Document Info**
> - Created: February 2026
> - Author: Claude (AI Assistant)
> - Project: WRF-Hydro BMI Wrapper
> - Related Docs: Doc 8 (Heat Code Guide), Doc 9 (SCHISM vs WRF-Hydro), Doc 11 (SCHISM Deep Dive)
> - Source Files Studied: heat.f90, bmi_heat.f90, bmi_main.f90, bmischism.f90, schism_model_container.f90
