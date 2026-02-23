# 🔥 BMI Template & Heat Model — Complete Code Guide for ML Engineers

> 📖 **What this doc covers:** A line-by-line, function-by-function breakdown of the
> BMI Fortran specification (`bmi.f90`) and the BMI Heat Model example (`bmi-example-fortran/`).
> Both the **conceptual "why"** and the **code-level "how"** — written for someone who
> knows PyTorch but has never touched Fortran.

---

## 📑 Table of Contents

1. [🎯 The Big Picture — What Are We Looking At?](#1--the-big-picture--what-are-we-looking-at)
2. [📂 Repository Structure — File Map](#2--repository-structure--file-map)
3. [📜 The BMI Spec — `bmi.f90` (The Abstract Interface)](#3--the-bmi-spec--bmif90-the-abstract-interface)
4. [🌡️ The Heat Model — `heat.f90` (The Actual Physics)](#4--the-heat-model--heatf90-the-actual-physics)
5. [🔌 The BMI Wrapper — `bmi_heat.f90` (The Bridge)](#5--the-bmi-wrapper--bmi_heatf90-the-bridge)
6. [🚀 The Driver Program — `bmi_main.f90` (The Runner)](#6--the-driver-program--bmi_mainf90-the-runner)
7. [🧪 The Test Suite — 42 Tests Explained](#7--the-test-suite--42-tests-explained)
8. [📚 The Example Programs — 7 Demos Explained](#8--the-example-programs--7-demos-explained)
9. [🔨 The Build System — CMake Explained](#9--the-build-system--cmake-explained)
10. [🧠 Key Patterns for WRF-Hydro — What We'll Reuse](#10--key-patterns-for-wrf-hydro--what-well-reuse)
11. [📋 Quick Reference Card](#11--quick-reference-card)

---

## 1. 🎯 The Big Picture — What Are We Looking At?

### 🤔 The Problem BMI Solves

Imagine you have two ML models that need to talk to each other:
- **Model A** produces embeddings that **Model B** needs as input
- But they were written by different teams, with different data formats, different training loops

In ML, you'd solve this with a **standard interface** — like ONNX Runtime or TorchServe.
Every model exports the same API (`predict()`, `load()`, `get_input_shape()`), and a
**framework** handles the plumbing.

**BMI is exactly that, but for physics models.**

```
┌─────────────────────────────────────────────────────────────────┐
│                    🧠 ML WORLD ANALOGY                          │
│                                                                 │
│   ONNX Runtime Interface          BMI Interface                 │
│   ─────────────────────          ──────────────                 │
│   load_model(path)          ←→   initialize(config_file)        │
│   predict(input)            ←→   update()                       │
│   get_input_shape()         ←→   get_grid_shape()               │
│   get_output_names()        ←→   get_output_var_names()         │
│   get_tensor("layer_out")   ←→   get_value("temperature")      │
│   set_tensor("layer_in",x)  ←→   set_value("temperature",x)    │
│   cleanup()                 ←→   finalize()                     │
│                                                                 │
│   TorchServe orchestrates        PyMT orchestrates              │
│   multiple ONNX models           multiple BMI models            │
└─────────────────────────────────────────────────────────────────┘
```

### 🏗️ The Architecture (4 Layers)

```
┌─────────────────────────────────────────────────────┐
│  Layer 4: DRIVER / FRAMEWORK (bmi_main.f90 / PyMT)  │  ← Controls everything
│  "The training script / orchestrator"                │
├─────────────────────────────────────────────────────┤
│  Layer 3: BMI WRAPPER (bmi_heat.f90)                 │  ← Standard interface
│  "The ONNX export / TorchServe adapter"              │
├─────────────────────────────────────────────────────┤
│  Layer 2: MODEL CODE (heat.f90)                      │  ← Actual physics
│  "The PyTorch model (nn.Module)"                     │
├─────────────────────────────────────────────────────┤
│  Layer 1: BMI SPEC (bmi.f90)                         │  ← Abstract contract
│  "The abstract base class / protocol"                │
└─────────────────────────────────────────────────────┘
```

### 🔄 How They Connect (Data Flow)

```
    bmi.f90                    heat.f90                bmi_heat.f90
    ───────                    ────────                ────────────
    "You MUST have             "I simulate heat        "I translate BMI
     initialize()"              diffusion on a          calls into heat
                                2D plate"               model calls"
         │                          │                        │
         │    defines contract      │    wraps model         │
         ▼                          ▼                        ▼
    ┌──────────┐  extends    ┌────────────┐  contains  ┌──────────┐
    │ type bmi │◄────────────│ bmi_heat   │───────────►│heat_model│
    │(abstract)│             │(concrete)  │            │ (data)   │
    └──────────┘             └────────────┘            └──────────┘
         │                          │
         │                          │  called by
         │                          ▼
         │                   ┌────────────┐
         │                   │ bmi_main   │
         │                   │ (driver)   │
         │                   └────────────┘
         │
    > 🧠 ML Analogy:
    > bmi.f90      = nn.Module (abstract base class with forward() etc.)
    > heat.f90     = Your actual neural network (ResNet, BERT, etc.)
    > bmi_heat.f90 = The wrapper that makes your model ONNX-compatible
    > bmi_main.f90 = The inference script (load model → loop → get output)
```

---

## 2. 📂 Repository Structure — File Map

```
bmi-example-fortran/                    📦 The complete example project
│
├── CMakeLists.txt                      🔨 Top-level build config (like setup.py)
├── fpm.toml                            📦 Fortran Package Manager config
├── LICENSE                             📄 MIT license
├── README.md                           📖 Project readme
│
├── heat/                               🌡️ THE MODEL (what we're wrapping)
│   ├── CMakeLists.txt                  🔨 Build config for model library
│   ├── heat.f90                        ⭐ Heat equation model (158 lines)
│   └── main.f90                        🚀 Standalone runner (25 lines)
│
├── bmi_heat/                           🔌 THE BMI WRAPPER (the bridge)
│   ├── CMakeLists.txt                  🔨 Build config for wrapper library
│   ├── bmi_heat.f90                    ⭐ BMI implementation (935 lines)
│   └── bmi_main.f90                    🚀 BMI driver program (65 lines)
│
├── test/                               🧪 UNIT TESTS (42 test files)
│   ├── CMakeLists.txt                  🔨 Test build config (defines 42 tests)
│   ├── fixtures.f90                    🧰 Shared test utilities
│   ├── test_initialize.f90             ✅ Test: initialize with/without config
│   ├── test_finalize.f90               ✅ Test: cleanup works
│   ├── test_update.f90                 ✅ Test: one timestep advances correctly
│   ├── test_update_until.f90           ✅ Test: advance to target time
│   ├── test_get_component_name.f90     ✅ Test: returns "The 2D Heat Equation"
│   ├── test_get_input_item_count.f90   ✅ Test: returns 3
│   ├── test_get_output_item_count.f90  ✅ Test: returns 1
│   ├── test_get_input_var_names.f90    ✅ Test: returns correct names
│   ├── test_get_output_var_names.f90   ✅ Test: returns correct names
│   ├── test_get_start_time.f90         ✅ Test: returns 0.0
│   ├── test_get_end_time.f90           ✅ Test: returns 20.0
│   ├── test_get_current_time.f90       ✅ Test: returns 0.0 before update
│   ├── test_get_time_step.f90          ✅ Test: returns 0.333...
│   ├── test_get_time_units.f90         ✅ Test: returns "s"
│   ├── test_get_var_grid.f90           ✅ Test: temperature→grid 0
│   ├── test_get_grid_type.f90          ✅ Test: grid 0→"uniform_rectilinear"
│   ├── test_get_grid_rank.f90          ✅ Test: grid 0→rank 2
│   ├── test_get_grid_shape.f90         ✅ Test: grid 0→[20, 10]
│   ├── test_get_grid_size.f90          ✅ Test: grid 0→200
│   ├── test_get_grid_spacing.f90       ✅ Test: [1.0, 1.0]
│   ├── test_get_grid_origin.f90        ✅ Test: [0.0, 0.0]
│   ├── test_get_grid_x.f90             ✅ Test: scalar grid→[0.0]
│   ├── test_get_grid_y.f90             ✅ Test: scalar grid→[0.0]
│   ├── test_get_grid_z.f90             ✅ Test: scalar grid→[0.0]
│   ├── test_get_grid_node_count.f90    ✅ Test: same as grid size
│   ├── test_get_grid_edge_count.f90    ✅ Test: returns BMI_FAILURE (N/A)
│   ├── test_get_grid_face_count.f90    ✅ Test: returns BMI_FAILURE (N/A)
│   ├── test_get_grid_edge_nodes.f90    ✅ Test: returns BMI_FAILURE (N/A)
│   ├── test_get_grid_face_edges.f90    ✅ Test: returns BMI_FAILURE (N/A)
│   ├── test_get_grid_face_nodes.f90    ✅ Test: returns BMI_FAILURE (N/A)
│   ├── test_get_grid_nodes_per_face.f90 ✅ Test: returns BMI_FAILURE (N/A)
│   ├── test_get_var_type.f90           ✅ Test: temperature→"real"
│   ├── test_get_var_units.f90          ✅ Test: temperature→"K"
│   ├── test_get_var_itemsize.f90       ✅ Test: temperature→4 bytes
│   ├── test_get_var_nbytes.f90         ✅ Test: temperature→800 bytes
│   ├── test_get_var_location.f90       ✅ Test: all vars→"node"
│   ├── test_get_value.f90              ✅ Test: get temperature array
│   ├── test_get_value_ptr.f90          ✅ Test: get pointer to temperature
│   ├── test_get_value_at_indices.f90   ✅ Test: get specific elements
│   ├── test_set_value.f90              ✅ Test: overwrite temperature
│   ├── test_set_value_at_indices.f90   ✅ Test: set specific elements
│   └── test_by_reference.f90           ✅ Test: ptr updates after model step
│
└── example/                            📚 DEMO PROGRAMS (7 examples)
    ├── CMakeLists.txt                  🔨 Example build config
    ├── testing_helpers.f90             🧰 Shared print utility
    ├── info_ex.f90                     📊 Demo: component name, var names
    ├── irf_ex.f90                      🔄 Demo: init→run→finalize lifecycle
    ├── vargrid_ex.f90                  📐 Demo: variable & grid metadata
    ├── get_value_ex.f90                📤 Demo: get_value, get_value_ptr, at_indices
    ├── set_value_ex.f90                📥 Demo: set_value, set_value_at_indices
    ├── conflicting_instances_ex.f90    👥 Demo: two independent model instances
    └── change_diffusivity_ex.f90       🎛️ Demo: change parameter mid-run
```

> 🧠 **ML Analogy:** This is like a PyTorch example repo:
> - `heat/` = the model definition (`model.py`)
> - `bmi_heat/` = the serving adapter (`onnx_export.py` + `serve.py`)
> - `test/` = unit tests (`test_model.py`)
> - `example/` = demo notebooks (`demo.ipynb`)

---

## 3. 📜 The BMI Spec — `bmi.f90` (The Abstract Interface)

### 📍 File: `bmi-fortran/bmi.f90` — 564 lines

This is the **abstract interface** — it defines WHAT functions every BMI model must have,
but NOT how they work. No physics here. Just the contract.

> 🧠 **ML Analogy:** This is like Python's `abc.ABC` (Abstract Base Class):
> ```python
> # Python equivalent of bmi.f90
> from abc import ABC, abstractmethod
>
> class BMI(ABC):
>     @abstractmethod
>     def initialize(self, config_file: str) -> int: ...
>     @abstractmethod
>     def update(self) -> int: ...
>     @abstractmethod
>     def get_value(self, name: str) -> np.ndarray: ...
>     # ... 38 more abstract methods
> ```

### 🔧 Part 1: Module Header & Constants (Lines 1-18)

```fortran
module bmif_2_0                    ! Module name = "bmif version 2.0"

  implicit none                    ! Force explicit variable declarations

  ! Maximum string lengths for names
  integer, parameter :: BMI_MAX_COMPONENT_NAME = 2048
  integer, parameter :: BMI_MAX_VAR_NAME = 2048
  integer, parameter :: BMI_MAX_TYPE_NAME = 2048
  integer, parameter :: BMI_MAX_UNITS_NAME = 2048

  ! Return codes (like HTTP status codes)
  integer, parameter :: BMI_FAILURE = 1    ! Something went wrong
  integer, parameter :: BMI_SUCCESS = 0    ! All good
```

**Line-by-line breakdown:**

| Line | Code | What It Does | ML Equivalent |
|------|------|-------------|---------------|
| 7 | `module bmif_2_0` | Starts a module (namespace) | `import bmif_2_0` |
| 9 | `implicit none` | All variables must be declared | Like Python type hints being required |
| 11-14 | `BMI_MAX_*` | Max string buffer sizes | `MAX_NAME_LENGTH = 2048` |
| 16 | `BMI_FAILURE = 1` | Error return code | `raise RuntimeError()` |
| 17 | `BMI_SUCCESS = 0` | Success return code | `return True` |

> 💡 **Why `implicit none`?** Without it, Fortran auto-assigns types based on the
> first letter of the variable name (i-n = integer, everything else = real). This is
> a legacy feature from the 1950s that causes horrific bugs. `implicit none` disables it.

### 🔧 Part 2: The Abstract Type Declaration (Lines 19-99)

```fortran
  type, abstract :: bmi            ! "abstract" = can't create instances directly
    contains                       ! Methods follow

      ! ═══════════ IRF: Initialize, Run, Finalize ═══════════
      procedure(bmif_initialize), deferred :: initialize
      procedure(bmif_update), deferred :: update
      procedure(bmif_update_until), deferred :: update_until
      procedure(bmif_finalize), deferred :: finalize

      ! ═══════════ Exchange Items (Model Info) ═══════════
      procedure(bmif_get_component_name), deferred :: get_component_name
      procedure(bmif_get_input_item_count), deferred :: get_input_item_count
      procedure(bmif_get_output_item_count), deferred :: get_output_item_count
      procedure(bmif_get_input_var_names), deferred :: get_input_var_names
      procedure(bmif_get_output_var_names), deferred :: get_output_var_names

      ! ═══════════ Variable Information ═══════════
      procedure(bmif_get_var_grid), deferred :: get_var_grid
      procedure(bmif_get_var_type), deferred :: get_var_type
      procedure(bmif_get_var_units), deferred :: get_var_units
      procedure(bmif_get_var_itemsize), deferred :: get_var_itemsize
      procedure(bmif_get_var_nbytes), deferred :: get_var_nbytes
      procedure(bmif_get_var_location), deferred :: get_var_location

      ! ═══════════ Time Information ═══════════
      procedure(bmif_get_current_time), deferred :: get_current_time
      procedure(bmif_get_start_time), deferred :: get_start_time
      procedure(bmif_get_end_time), deferred :: get_end_time
      procedure(bmif_get_time_units), deferred :: get_time_units
      procedure(bmif_get_time_step), deferred :: get_time_step

      ! ═══════════ Getters (by type: int, float, double) ═══════════
      procedure(bmif_get_value_int), deferred :: get_value_int
      procedure(bmif_get_value_float), deferred :: get_value_float
      procedure(bmif_get_value_double), deferred :: get_value_double
      procedure(bmif_get_value_ptr_int), deferred :: get_value_ptr_int
      procedure(bmif_get_value_ptr_float), deferred :: get_value_ptr_float
      procedure(bmif_get_value_ptr_double), deferred :: get_value_ptr_double
      procedure(bmif_get_value_at_indices_int), deferred :: get_value_at_indices_int
      procedure(bmif_get_value_at_indices_float), deferred :: get_value_at_indices_float
      procedure(bmif_get_value_at_indices_double), deferred :: get_value_at_indices_double

      ! ═══════════ Setters (by type: int, float, double) ═══════════
      procedure(bmif_set_value_int), deferred :: set_value_int
      procedure(bmif_set_value_float), deferred :: set_value_float
      procedure(bmif_set_value_double), deferred :: set_value_double
      procedure(bmif_set_value_at_indices_int), deferred :: set_value_at_indices_int
      procedure(bmif_set_value_at_indices_float), deferred :: set_value_at_indices_float
      procedure(bmif_set_value_at_indices_double), deferred :: set_value_at_indices_double

      ! ═══════════ Grid Information ═══════════
      procedure(bmif_get_grid_rank), deferred :: get_grid_rank
      procedure(bmif_get_grid_size), deferred :: get_grid_size
      procedure(bmif_get_grid_type), deferred :: get_grid_type
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
      procedure(bmif_get_grid_face_edges), deferred :: get_grid_face_edges
      procedure(bmif_get_grid_face_nodes), deferred :: get_grid_face_nodes
      procedure(bmif_get_grid_nodes_per_face), deferred :: get_grid_nodes_per_face

  end type bmi
```

**Key Fortran concepts explained:**

| Fortran Keyword | What It Means | Python Equivalent |
|----------------|---------------|-------------------|
| `type, abstract :: bmi` | Abstract class definition | `class BMI(ABC):` |
| `contains` | "Methods follow below" | (implicit in Python classes) |
| `procedure(...), deferred` | Must be implemented by child | `@abstractmethod` |
| `end type bmi` | End of class definition | (implicit via indentation in Python) |

> ⚠️ **Critical Fortran Concept — `deferred`:**
> The word `deferred` means "I'm NOT implementing this here — whoever inherits from me MUST."
> If you extend `bmi` and forget to implement even ONE of these 53 procedures, the compiler
> will refuse to compile. It's like Python's `@abstractmethod` but enforced at compile time.

### 🔧 Part 3: The Abstract Interface Signatures (Lines 101-562)

Each `deferred` procedure needs a **signature** — what arguments it takes and returns.
These are defined in an `abstract interface` block. Let me show the key patterns:

#### 🔹 Pattern A: Simple output parameter

```fortran
  ! "Tell me the model name"
  function bmif_get_component_name(this, name) result(bmi_status)
    import :: bmi                              ! Bring in the bmi type
    class(bmi), intent(in) :: this             ! The model instance (self)
    character(len=*), pointer, intent(out) :: name  ! OUTPUT: the name string
    integer :: bmi_status                      ! RETURN: success/failure
  end function
```

> 🧠 **ML Analogy (Python):**
> ```python
> def get_component_name(self) -> Tuple[str, int]:
>     return "ResNet50", BMI_SUCCESS
> ```
> But Fortran returns values through **output arguments** (`intent(out)`) instead of
> a return value. The actual `result` is just the status code (0 or 1).

#### 🔹 Pattern B: Input name → Output value

```fortran
  ! "Give me the grid ID for variable named 'temperature'"
  function bmif_get_var_grid(this, name, grid) result(bmi_status)
    import :: bmi
    class(bmi), intent(in) :: this             ! self
    character(len=*), intent(in) :: name       ! INPUT: variable name string
    integer, intent(out) :: grid               ! OUTPUT: grid ID number
    integer :: bmi_status                      ! RETURN: 0=ok, 1=fail
  end function
```

#### 🔹 Pattern C: Array output (get_value)

```fortran
  ! "Copy the float values of variable 'name' into array 'dest'"
  function bmif_get_value_float(this, name, dest) result(bmi_status)
    import :: bmi
    class(bmi), intent(in) :: this
    character(len=*), intent(in) :: name       ! INPUT: which variable
    real, intent(inout) :: dest(:)             ! OUTPUT: 1D flattened array!
    integer :: bmi_status
  end function
```

> ⚠️ **THE MOST IMPORTANT BMI RULE:** `dest(:)` is ALWAYS a **1D flattened array**.
> Even if the model internally stores data as a 2D grid (10×20), BMI always returns
> it flattened to 1D (200 elements). This avoids row-major vs column-major confusion
> between Fortran (column-major) and C/Python (row-major).
>
> 🧠 **ML Analogy:** This is like `tensor.flatten()` or `tensor.reshape(-1)` in PyTorch.
> You always exchange flat tensors through ONNX, then reshape on the receiving end.

#### 🔹 Pattern D: Pointer output (get_value_ptr — zero-copy)

```fortran
  ! "Give me a POINTER to the float values (no copy!)"
  function bmif_get_value_ptr_float(this, name, dest_ptr) result(bmi_status)
    import :: bmi
    class(bmi), intent(in) :: this
    character(len=*), intent(in) :: name
    real, pointer, intent(inout) :: dest_ptr(:)  ! POINTER to model memory!
    integer :: bmi_status
  end function
```

> 🧠 **ML Analogy:** `get_value` = `tensor.clone()` (copy), `get_value_ptr` = `tensor.data_ptr()`
> (zero-copy reference). The pointer version is faster but dangerous — if the model
> frees memory, your pointer becomes invalid (dangling pointer = use-after-free bug).

### 📊 Complete Function Count Summary

```
┌──────────────────────────────────────────────────────────────────┐
│                  📊 BMI 2.0 FUNCTION COUNT                       │
├──────────────────────┬───────┬───────────────────────────────────┤
│ Category             │ Count │ Functions                         │
├──────────────────────┼───────┼───────────────────────────────────┤
│ 🔄 IRF Control       │   4   │ initialize, update,               │
│                      │       │ update_until, finalize             │
├──────────────────────┼───────┼───────────────────────────────────┤
│ 📋 Model Info        │   5   │ get_component_name,               │
│                      │       │ get_input/output_item_count,       │
│                      │       │ get_input/output_var_names         │
├──────────────────────┼───────┼───────────────────────────────────┤
│ 📊 Variable Info     │   6   │ get_var_grid/type/units/           │
│                      │       │ itemsize/nbytes/location           │
├──────────────────────┼───────┼───────────────────────────────────┤
│ ⏰ Time Info         │   5   │ get_current/start/end_time,        │
│                      │       │ get_time_step/units                │
├──────────────────────┼───────┼───────────────────────────────────┤
│ 📤 Getters           │   9   │ get_value_{int,float,double}       │
│                      │       │ get_value_ptr_{int,float,double}   │
│                      │       │ get_value_at_indices_{i,f,d}       │
├──────────────────────┼───────┼───────────────────────────────────┤
│ 📥 Setters           │   6   │ set_value_{int,float,double}       │
│                      │       │ set_value_at_indices_{i,f,d}       │
├──────────────────────┼───────┼───────────────────────────────────┤
│ 📐 Grid Info         │  18   │ get_grid_rank/size/type/shape/     │
│                      │       │ spacing/origin/x/y/z/              │
│                      │       │ node_count/edge_count/face_count/  │
│                      │       │ edge_nodes/face_edges/face_nodes/  │
│                      │       │ nodes_per_face                     │
├──────────────────────┼───────┼───────────────────────────────────┤
│                TOTAL │  53   │ (in bmi.f90 abstract interface)    │
│                      │       │ Note: BMI spec says "41" because   │
│                      │       │ typed getters/setters count as 1   │
│                      │       │ each (get_value = 1, not 3)        │
└──────────────────────┴───────┴───────────────────────────────────┘
```

> 💡 **Why 53 in the code but "41 BMI functions" in the spec?**
> The BMI spec counts `get_value` as ONE function. But Fortran doesn't have generics
> like Python, so you need separate implementations for `int`, `float`, and `double`.
> That's 3×(get_value + get_value_ptr + get_value_at_indices) = 9 getters, plus
> 3×(set_value + set_value_at_indices) = 6 setters. So 53 actual Fortran procedures
> implement the 41 logical BMI functions.

---

## 4. 🌡️ The Heat Model — `heat.f90` (The Actual Physics)

### 📍 File: `bmi-example-fortran/heat/heat.f90` — 158 lines

This is a simple 2D heat diffusion model. It simulates how temperature spreads across
a flat metal plate over time. **No BMI here — just pure physics.**

> 🧠 **ML Analogy:** This file is like your `model.py` that defines the neural network.
> It has no idea about serving, ONNX, or APIs. It just knows how to do forward passes.

### 🌡️ The Physics: 2D Heat Equation

```
  ∂T       ∂²T     ∂²T
  ── = α ( ─── + ─── )
  ∂t       ∂x²    ∂y²

  Where:
    T = temperature at each point
    α = thermal diffusivity (how fast heat spreads)
    t = time
    x, y = spatial coordinates
```

> 🧠 **ML Analogy:** This is like a 2D convolution with a fixed Laplacian kernel:
> ```python
> kernel = torch.tensor([[0, 1, 0],
>                        [1,-4, 1],
>                        [0, 1, 0]], dtype=torch.float32)
> # Each "time step" = one conv2d pass with this kernel
> T_next = T + alpha * dt * F.conv2d(T, kernel)
> ```
> Literally — the heat equation IS a convolution. Each timestep, every cell averages
> its neighbors, weighted by the diffusivity coefficient.

### 🔧 The Model Type Definition (Lines 7-24)

```fortran
  type :: heat_model
     integer :: id                         ! Model instance identifier

     real :: dt                            ! Time step size (seconds)
     real :: t                             ! Current time
     real :: t_end                         ! End time

     real :: alpha                         ! Thermal diffusivity coefficient

     integer :: n_x                        ! Grid columns (width)
     integer :: n_y                        ! Grid rows (height)

     real :: dx                            ! Grid spacing in x (meters)
     real :: dy                            ! Grid spacing in y (meters)

     real, pointer :: temperature(:,:)     ! 2D temperature grid [n_y × n_x]
     real, pointer :: temperature_tmp(:,:) ! Temporary buffer for solver
  end type heat_model
```

> 🧠 **ML Analogy (Python dataclass):**
> ```python
> @dataclass
> class HeatModel:
>     id: int = 0
>     dt: float = 0.0          # Like learning_rate
>     t: float = 0.0           # Like current_epoch
>     t_end: float = 20.0      # Like max_epochs
>     alpha: float = 0.75      # Like a hyperparameter
>     n_x: int = 10            # Like input_width
>     n_y: int = 20            # Like input_height
>     dx: float = 1.0          # Like pixel_size
>     dy: float = 1.0
>     temperature: np.ndarray  # The 2D state tensor [n_y, n_x]
>     temperature_tmp: np.ndarray  # Buffer (like a gradient accumulator)
> ```

> ⚠️ **Why `pointer` and not just `real :: temperature(n_y, n_x)`?**
> Because `n_y` and `n_x` aren't known at compile time — they come from the config file.
> `pointer` means "I'll allocate memory for this later at runtime."
> In ML terms: it's like `self.weights = None` in `__init__`, then
> `self.weights = torch.zeros(n)` in `setup()`.

### 🔧 The Initialization Functions (Lines 31-70)

There are TWO ways to initialize:

```fortran
  ! Method 1: From a config file (like loading a YAML config)
  subroutine initialize_from_file(model, config_file)
    character (len=*), intent(in) :: config_file
    type (heat_model), intent(out) :: model

    open(15, file=config_file)
    read(15, *) model%alpha, model%t_end, model%n_x, model%n_y
    close(15)
    call initialize(model)       ! Then do the common setup
  end subroutine

  ! Method 2: From hardcoded defaults (like default hyperparameters)
  subroutine initialize_from_defaults(model)
    type (heat_model), intent(out) :: model

    model%alpha = 0.75           ! Default diffusivity
    model%t_end = 20.            ! Default end time
    model%n_x = 10               ! Default grid width
    model%n_y = 20               ! Default grid height
    call initialize(model)       ! Then do the common setup
  end subroutine
```

The **common setup** that both call:

```fortran
  subroutine initialize(model)
    type (heat_model), intent(inout) :: model

    model%id = 0
    model%dx = 1.                            ! 1 meter spacing
    model%dy = 1.
    model%t = 0.                             ! Start at time 0
    model%dt = 1. / (4. * model%alpha)       ! CFL condition for stability!

    ! Allocate 2D arrays (like torch.zeros(n_y, n_x))
    allocate(model%temperature(model%n_y, model%n_x))
    allocate(model%temperature_tmp(model%n_y, model%n_x))

    ! Random initial temperatures (like random weight init)
    call random_number(model%temperature)
    call random_number(model%temperature_tmp)

    ! Set edges to 0 (boundary conditions)
    call set_boundary_conditions(model%temperature)
    call set_boundary_conditions(model%temperature_tmp)
  end subroutine
```

> 💡 **The CFL condition `dt = 1/(4*alpha)`:** This is a stability constraint. If `dt`
> is too large, the simulation explodes (values go to infinity). Same concept as learning
> rate in ML — too high and gradients explode.
>
> 🧠 **ML Analogy:**
> ```python
> def __init__(self, config):
>     self.lr = 1.0 / (4.0 * config.alpha)  # "Stable learning rate"
>     self.weights = torch.rand(config.n_y, config.n_x)
>     self.weights[0, :] = 0  # Boundary = zero
>     self.weights[-1, :] = 0
>     self.weights[:, 0] = 0
>     self.weights[:, -1] = 0
> ```

### 🔧 Boundary Conditions (Lines 73-89)

```fortran
  subroutine set_boundary_conditions(z)
    real, dimension(:,:), intent(out) :: z
    integer :: i, nx, ny

    nx = size(z, 2)      ! Number of columns
    ny = size(z, 1)      ! Number of rows

    ! Top and bottom rows = 0
    do i = 1, nx
       z(1, i) = 0.      ! Top edge
       z(ny, i) = 0.      ! Bottom edge
    end do
    ! Left and right columns = 0
    do i = 1, ny
       z(i, 1) = 0.       ! Left edge
       z(i, nx) = 0.       ! Right edge
    end do
  end subroutine
```

```
  ┌───────────────────────────────┐
  │ 0.0  0.0  0.0  0.0  0.0  0.0 │  ← Top boundary (always 0)
  │ 0.0  0.3  0.7  0.5  0.2  0.0 │
  │ 0.0  0.8  0.4  0.9  0.1  0.0 │  ← Interior: random initial values
  │ 0.0  0.6  0.2  0.3  0.7  0.0 │     that diffuse over time
  │ 0.0  0.1  0.5  0.8  0.4  0.0 │
  │ 0.0  0.0  0.0  0.0  0.0  0.0 │  ← Bottom boundary (always 0)
  └───────────────────────────────┘
     ↑                         ↑
   Left boundary            Right boundary
   (always 0)               (always 0)
```

### 🔧 The Solver — One Time Step (Lines 99-130)

```fortran
  ! Advance the model by one time step
  subroutine advance_in_time(model)
    type (heat_model), intent(inout) :: model

    call solve_2d(model)                       ! Compute new temperatures
    model%temperature = model%temperature_tmp  ! Copy buffer → main array
    model%t = model%t + model%dt               ! Advance clock
  end subroutine

  ! The actual 2D heat equation solver
  subroutine solve_2d(model)
    type (heat_model), intent(inout) :: model
    real :: dx2, dy2, coef
    integer :: i, j

    dx2 = model%dx**2                          ! dx squared
    dy2 = model%dy**2                          ! dy squared
    coef = model%alpha * model%dt / (2. * (dx2 + dy2))  ! Diffusion coefficient

    ! Loop over interior points only (skip boundaries)
    do j = 2, model%n_x - 1          ! columns 2 to n_x-1
       do i = 2, model%n_y - 1       ! rows 2 to n_y-1
          model%temperature_tmp(i,j) = &
               model%temperature(i,j) + coef * ( &
               dx2*(model%temperature(i-1,j) + model%temperature(i+1,j)) + &
               dy2*(model%temperature(i,j-1) + model%temperature(i,j+1)) - &
               2.*(dx2 + dy2)*model%temperature(i,j) )
       end do
    end do
  end subroutine
```

> 🧠 **ML Analogy — This IS a convolution:**
> ```python
> def forward(self, T):
>     """One 'timestep' = one conv2d pass with Laplacian kernel"""
>     coef = self.alpha * self.dt / (2 * (dx2 + dy2))
>     # The stencil operation:
>     T_new[i,j] = T[i,j] + coef * (
>         dx2 * (T[i-1,j] + T[i+1,j]) +   # vertical neighbors
>         dy2 * (T[i,j-1] + T[i,j+1]) -   # horizontal neighbors
>         2*(dx2+dy2) * T[i,j]             # center point
>     )
>     return T_new
> ```
> It's literally a 3×3 stencil applied to every interior cell. The `do j / do i` loops
> are the equivalent of `F.conv2d()` — just written out explicitly.

### 🔧 Cleanup (Lines 92-97)

```fortran
  subroutine cleanup(model)
    type (heat_model), intent(inout) :: model
    deallocate(model%temperature)         ! Free memory
    deallocate(model%temperature_tmp)     ! Free memory
  end subroutine
```

> 🧠 **ML Analogy:** `del model` or `torch.cuda.empty_cache()`. Fortran requires
> explicit memory management for `pointer` arrays — no garbage collector like Python.

### 🔧 Standalone Runner — `main.f90` (25 lines)

This runs the heat model **without BMI** — just direct calls:

```fortran
program main
  use heatf                                    ! Import the heat module
  implicit none
  type (heat_model) :: model

  call initialize_from_defaults(model)         ! Setup with defaults

  do while (model%t < model%t_end)             ! Time loop
     call advance_in_time(model)               ! One step
     call print_values(model)                  ! Print grid
  end do

  call cleanup(model)                          ! Free memory
end program main
```

> 🧠 **ML Analogy:**
> ```python
> model = HeatModel(config=default_config)
> while model.t < model.t_end:
>     model.step()
>     print(model.temperature)
> del model
> ```

---

## 5. 🔌 The BMI Wrapper — `bmi_heat.f90` (The Bridge)

### 📍 File: `bmi-example-fortran/bmi_heat/bmi_heat.f90` — 935 lines

This is **THE file we need to understand deeply** — it's the template for `bmi_wrf_hydro.f90`.

It takes the abstract `bmi` type from `bmi.f90` and fills in EVERY function with
concrete code that talks to the `heat_model`.

> 🧠 **ML Analogy:** If `bmi.f90` is `nn.Module`, and `heat.f90` is your actual network,
> then `bmi_heat.f90` is the **ONNX export wrapper** that makes your model queryable
> through a standard API.

### 🔧 Part 1: Module Header & Type Definition (Lines 1-100)

```fortran
module bmiheatf

  use heatf                          ! Import the heat model
  use bmif_2_0                       ! Import the BMI spec
  use, intrinsic :: iso_c_binding, only: c_ptr, c_loc, c_f_pointer
  implicit none

  type, extends(bmi) :: bmi_heat     ! "bmi_heat INHERITS FROM bmi"
     private                         ! Internal data is hidden
     type (heat_model) :: model      ! ← THE MODEL LIVES HERE!
   contains
     ! ... 53 procedure mappings ...
     procedure :: get_component_name => heat_component_name
     procedure :: initialize => heat_initialize
     procedure :: update => heat_update
     ! ... etc ...

     ! GENERIC interfaces (Fortran's version of function overloading)
     generic :: get_value => get_value_int, get_value_float, get_value_double
     generic :: get_value_ptr => get_value_ptr_int, get_value_ptr_float, get_value_ptr_double
     generic :: get_value_at_indices => get_value_at_indices_int, ...
     generic :: set_value => set_value_int, set_value_float, set_value_double
     generic :: set_value_at_indices => set_value_at_indices_int, ...
  end type bmi_heat

  private                            ! Everything private by default
  public :: bmi_heat                 ! Only expose the bmi_heat type

  ! Module-level variables for names
  character(len=BMI_MAX_COMPONENT_NAME), target :: &
       component_name = "The 2D Heat Equation"

  integer, parameter :: input_item_count = 3
  integer, parameter :: output_item_count = 1
  character(len=BMI_MAX_VAR_NAME), target, &
       dimension(input_item_count) :: input_items
  character(len=BMI_MAX_VAR_NAME), target, &
       dimension(output_item_count) :: &
       output_items = (/'plate_surface__temperature'/)
```

**Line-by-line key concepts:**

| Line | Code | What It Does | ML Equivalent |
|------|------|-------------|---------------|
| 3 | `use heatf` | Import model module | `from model import HeatModel` |
| 4 | `use bmif_2_0` | Import BMI spec | `from bmi import BMI` |
| 5 | `use iso_c_binding` | Import C interop tools | `import ctypes` |
| 8 | `type, extends(bmi) :: bmi_heat` | Inherit from abstract BMI | `class BmiHeat(BMI):` |
| 9 | `private` | Hide internals | `__slots__` / `_private` convention |
| 10 | `type(heat_model) :: model` | Store a model instance | `self.model = HeatModel()` |
| 12 | `procedure :: initialize => heat_initialize` | Map BMI method to our impl | Method binding |
| 51-54 | `generic :: get_value => ...` | One name, multiple types | `@overload` in Python |

> 💡 **The `generic` keyword is crucial:** In Python, `get_value("temp", array)` works
> whether `array` is `int`, `float`, or `double` because Python is dynamically typed.
> Fortran is statically typed — so you need THREE separate functions. The `generic`
> keyword lets callers write `m%get_value(name, arr)` and the compiler picks the right
> one based on the type of `arr`.

> 💡 **The `target` keyword on name strings:** This tells Fortran "someone might take
> a pointer to this variable." Without `target`, you can't return a pointer to it.
> BMI's `get_component_name` returns a pointer, so the string needs `target`.

### 🔧 Part 2: IRF Control Functions (Lines 103-259)

These are the **4 most important functions** — they control the model lifecycle.

#### ⚡ `initialize` — Start the model

```fortran
  function heat_initialize(this, config_file) result(bmi_status)
    class(bmi_heat), intent(out) :: this
    character(len=*), intent(in) :: config_file
    integer :: bmi_status

    if (len(config_file) > 0) then
       call initialize_from_file(this%model, config_file)  ! Use config
    else
       call initialize_from_defaults(this%model)           ! Use defaults
    end if
    bmi_status = BMI_SUCCESS
  end function
```

> 🧠 **ML Analogy:**
> ```python
> def initialize(self, config_file):
>     if config_file:
>         self.model = HeatModel.from_config(config_file)
>     else:
>         self.model = HeatModel()  # defaults
>     return BMI_SUCCESS
> ```

**Key pattern:** The BMI wrapper doesn't do the initialization itself — it **delegates**
to the model's own init routine. This is the non-invasive principle.

#### ⚡ `update` — Advance one time step

```fortran
  function heat_update(this) result(bmi_status)
    class(bmi_heat), intent(inout) :: this
    integer :: bmi_status

    call advance_in_time(this%model)    ! Delegate to model
    bmi_status = BMI_SUCCESS
  end function
```

> 🧠 **ML Analogy:**
> ```python
> def update(self):
>     self.model.step()  # One forward pass
>     return BMI_SUCCESS
> ```

#### ⚡ `update_until` — Advance to a target time

```fortran
  function heat_update_until(this, time) result(bmi_status)
    class(bmi_heat), intent(inout) :: this
    double precision, intent(in) :: time
    integer :: bmi_status
    double precision :: n_steps_real
    integer :: n_steps, i, s

    if (time < this%model%t) then        ! Can't go backwards!
       bmi_status = BMI_FAILURE
       return
    end if

    n_steps_real = (time - this%model%t) / this%model%dt
    n_steps = floor(n_steps_real)        ! Whole steps
    do i = 1, n_steps
       s = this%update()                 ! Take each whole step
    end do
    ! Handle fractional remainder
    call update_frac(this, n_steps_real - dble(n_steps))
    bmi_status = BMI_SUCCESS
  end function
```

> 🧠 **ML Analogy:**
> ```python
> def update_until(self, target_time):
>     if target_time < self.model.t:
>         return BMI_FAILURE  # Can't time-travel backwards
>     n_steps = (target_time - self.model.t) / self.model.dt
>     for _ in range(int(n_steps)):
>         self.update()
>     # Handle fractional step
>     self._update_frac(n_steps - int(n_steps))
>     return BMI_SUCCESS
> ```

#### ⚡ `finalize` — Cleanup

```fortran
  function heat_finalize(this) result(bmi_status)
    class(bmi_heat), intent(inout) :: this
    integer :: bmi_status

    call cleanup(this%model)             ! Delegate to model
    bmi_status = BMI_SUCCESS
  end function
```

### 🔧 Part 3: Model Info Functions (Lines 103-155)

These tell the outside world WHAT the model is and what variables it exposes.

```fortran
  ! "What's your name?"
  function heat_component_name(this, name) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    character(len=*), pointer, intent(out) :: name
    integer :: bmi_status

    name => component_name     ! Point to the module-level string
    bmi_status = BMI_SUCCESS
  end function

  ! "How many input variables do you have?"
  function heat_input_item_count(this, count) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    integer, intent(out) :: count
    integer :: bmi_status

    count = input_item_count   ! = 3
    bmi_status = BMI_SUCCESS
  end function

  ! "What are your input variable names?"
  function heat_input_var_names(this, names) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    character(*), pointer, intent(out) :: names(:)
    integer :: bmi_status

    input_items(1) = 'plate_surface__temperature'
    input_items(2) = 'plate_surface__thermal_diffusivity'
    input_items(3) = 'model__identification_number'
    names => input_items       ! Point to the module-level array
    bmi_status = BMI_SUCCESS
  end function
```

> 💡 **Notice the CSDMS Standard Names:** Variables are NOT called `temperature` or `alpha`.
> They use the CSDMS naming convention: `plate_surface__temperature` (double underscore!).
> This is like using canonical tensor names in ONNX: `input_0`, `output_logits`, etc.

### 🔧 Part 4: The Variable Info Functions — `select case` Pattern (Lines 261-631)

This is where the **most important coding pattern** appears — the `select case` statement.
Almost every variable-info function uses the same structure:

```fortran
  ! "What data type is variable X?"
  function heat_var_type(this, name, type) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    character(len=*), intent(in) :: name
    character(len=*), intent(out) :: type
    integer :: bmi_status

    select case(name)
    case("plate_surface__temperature")
       type = "real"
       bmi_status = BMI_SUCCESS
    case("plate_surface__thermal_diffusivity")
       type = "real"
       bmi_status = BMI_SUCCESS
    case("model__identification_number")
       type = "integer"
       bmi_status = BMI_SUCCESS
    case default
       type = "-"
       bmi_status = BMI_FAILURE
    end select
  end function
```

> 🧠 **ML Analogy — This is a dictionary lookup:**
> ```python
> VAR_TYPES = {
>     "plate_surface__temperature": "real",
>     "plate_surface__thermal_diffusivity": "real",
>     "model__identification_number": "integer",
> }
>
> def get_var_type(self, name):
>     if name in VAR_TYPES:
>         return VAR_TYPES[name], BMI_SUCCESS
>     return "-", BMI_FAILURE
> ```

**This `select case` pattern repeats across these functions:**

| Function | Input | Returns | Example |
|----------|-------|---------|---------|
| `get_var_type` | var name | data type string | `"real"`, `"integer"` |
| `get_var_units` | var name | units string | `"K"`, `"m2 s-1"`, `"1"` |
| `get_var_grid` | var name | grid ID integer | `0` (2D grid), `1` (scalar) |
| `get_var_itemsize` | var name | bytes per element | `4` (real), `4` (integer) |
| `get_var_location` | var name | location on grid | `"node"` (always, here) |

> ⚠️ **For WRF-Hydro:** We'll have a MUCH bigger `select case` with all our variables:
> `channel_water__volume_flow_rate`, `land_surface_water__depth`, etc. Same pattern!

### 🔧 Part 5: The `get_var_nbytes` Function — Composing BMI Calls (Lines 598-616)

This function is special because it **calls other BMI functions** to compute its answer:

```fortran
  function heat_var_nbytes(this, name, nbytes) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    character(len=*), intent(in) :: name
    integer, intent(out) :: nbytes
    integer :: bmi_status
    integer :: s1, s2, s3, grid, grid_size, item_size

    s1 = this%get_var_grid(name, grid)           ! Which grid?
    s2 = this%get_grid_size(grid, grid_size)     ! How many elements?
    s3 = this%get_var_itemsize(name, item_size)  ! Bytes per element?

    if ((s1 == BMI_SUCCESS) .and. (s2 == BMI_SUCCESS) .and. (s3 == BMI_SUCCESS)) then
       nbytes = item_size * grid_size            ! Total bytes!
       bmi_status = BMI_SUCCESS
    else
       nbytes = -1
       bmi_status = BMI_FAILURE
    end if
  end function
```

> 🧠 **ML Analogy:**
> ```python
> def get_var_nbytes(self, name):
>     grid = self.get_var_grid(name)       # Which tensor?
>     size = self.get_grid_size(grid)      # numel()
>     itemsize = self.get_var_itemsize(name)  # element_size()
>     return size * itemsize              # Like tensor.nbytes
> ```

> 💡 **Pattern for WRF-Hydro:** We can copy this function EXACTLY — it's
> model-independent! It works for any model because it only calls other BMI functions.

### 🔧 Part 6: Grid Functions — The `select case(grid)` Pattern (Lines 284-444)

Grid functions take a **grid ID** (integer) instead of a variable name:

```fortran
  ! "What type of grid is grid #0?"
  function heat_grid_type(this, grid, type) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    integer, intent(in) :: grid
    character(len=*), intent(out) :: type
    integer :: bmi_status

    select case(grid)
    case(0)
       type = "uniform_rectilinear"    ! 2D regular grid for temperature
       bmi_status = BMI_SUCCESS
    case(1)
       type = "scalar"                 ! Single value (diffusivity, id)
       bmi_status = BMI_SUCCESS
    case default
       type = "-"
       bmi_status = BMI_FAILURE
    end select
  end function
```

**The heat model has 2 grids:**

```
  Grid 0: uniform_rectilinear (2D)     Grid 1: scalar (0D)
  ┌───────────────────────┐            ┌───┐
  │ T T T T T T T T T T   │            │ α │  ← single value
  │ T T T T T T T T T T   │            └───┘
  │ T T T T T T T T T T   │
  │ ... (20 rows × 10 cols)│            Used for:
  └───────────────────────┘            - thermal_diffusivity (α)
  Used for:                            - identification_number
  - plate_surface__temperature

  rank=2, shape=[20,10], size=200      rank=0, shape=[], size=1
  spacing=[1.0, 1.0], origin=[0,0]
```

> 🧠 **For WRF-Hydro, we'll have 3 grids:**
> - Grid 0: 1km uniform_rectilinear (Noah-MP land surface)
> - Grid 1: 250m uniform_rectilinear (terrain routing)
> - Grid 2: vector/network (channel routing — reach network)

### 🔧 Part 7: Get/Set Value Functions — The Core Data Exchange (Lines 632-912)

This is the **heart of BMI** — how data flows in and out of the model.

#### 📤 `get_value` — Copy data OUT of the model (flattened!)

```fortran
  ! Get FLOAT values — the most common case
  function heat_get_float(this, name, dest) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    character(len=*), intent(in) :: name
    real, intent(inout) :: dest(:)      ! 1D output array (caller provides)
    integer :: bmi_status

    select case(name)
    case("plate_surface__temperature")
       ! ⭐ THE KEY LINE: reshape 2D → 1D (flatten!)
       dest = reshape(this%model%temperature, [this%model%n_x * this%model%n_y])
       bmi_status = BMI_SUCCESS
    case("plate_surface__thermal_diffusivity")
       dest = [this%model%alpha]        ! Scalar → 1-element array
       bmi_status = BMI_SUCCESS
    case default
       dest(:) = -1.0
       bmi_status = BMI_FAILURE
    end select
  end function
```

> ⭐ **THE CRITICAL PATTERN — `reshape` for flattening:**
> ```fortran
> dest = reshape(this%model%temperature, [this%model%n_x * this%model%n_y])
> ```
> This is the Fortran equivalent of `tensor.flatten()` or `np.ravel()`.
> It takes the 2D `temperature(20,10)` array and copies it into the 1D `dest(200)` array.
>
> 🧠 **ML Analogy:**
> ```python
> def get_value(self, name, dest):
>     if name == "plate_surface__temperature":
>         dest[:] = self.model.temperature.flatten()  # 2D → 1D
>     elif name == "plate_surface__thermal_diffusivity":
>         dest[:] = [self.model.alpha]                # scalar → [scalar]
> ```

#### 📤 `get_value_ptr` — Zero-copy pointer (advanced!)

```fortran
  function heat_get_ptr_float(this, name, dest_ptr) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    character(len=*), intent(in) :: name
    real, pointer, intent(inout) :: dest_ptr(:)  ! Fortran POINTER
    integer :: bmi_status
    type(c_ptr) :: src                           ! C-compatible pointer
    integer :: n_elements

    select case(name)
    case("plate_surface__temperature")
       src = c_loc(this%model%temperature(1,1))  ! Get C address of first element
       n_elements = this%model%n_y * this%model%n_x
       call c_f_pointer(src, dest_ptr, [n_elements])  ! Cast to 1D Fortran pointer
       bmi_status = BMI_SUCCESS
    case default
       bmi_status = BMI_FAILURE
    end select
  end function
```

> ⚠️ **This is the tricky one!** It uses `iso_c_binding` to get a raw memory pointer:
> 1. `c_loc(array(1,1))` — Get the C address of the first element
> 2. `c_f_pointer(c_addr, fortran_ptr, [size])` — Reinterpret as 1D Fortran pointer
>
> The result is a 1D view into the 2D array — **NO COPY**. Changes through the pointer
> directly modify the model's internal data.
>
> 🧠 **ML Analogy:**
> ```python
> # get_value:     data_copy = tensor.clone().flatten()     # Safe but slow
> # get_value_ptr: data_view = tensor.storage()              # Fast but dangerous
> ```

#### 📤 `get_value_at_indices` — Get specific elements only

```fortran
  function heat_get_at_indices_float(this, name, dest, inds) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    character(len=*), intent(in) :: name
    real, intent(inout) :: dest(:)
    integer, intent(in) :: inds(:)       ! Which indices to get
    integer :: bmi_status
    type(c_ptr) :: src
    real, pointer :: src_flattened(:)
    integer :: i, n_elements

    select case(name)
    case("plate_surface__temperature")
       src = c_loc(this%model%temperature(1,1))
       call c_f_pointer(src, src_flattened, [this%model%n_y * this%model%n_x])
       n_elements = size(inds)
       do i = 1, n_elements
          dest(i) = src_flattened(inds(i))    ! Cherry-pick elements
       end do
       bmi_status = BMI_SUCCESS
    case default
       bmi_status = BMI_FAILURE
    end select
  end function
```

> 🧠 **ML Analogy:**
> ```python
> def get_value_at_indices(self, name, dest, indices):
>     flat = self.model.temperature.flatten()
>     dest[:] = flat[indices]  # Like tensor[indices]
> ```

#### 📥 `set_value` — Push data INTO the model

```fortran
  function heat_set_float(this, name, src) result(bmi_status)
    class(bmi_heat), intent(inout) :: this
    character(len=*), intent(in) :: name
    real, intent(in) :: src(:)           ! 1D input array
    integer :: bmi_status

    select case(name)
    case("plate_surface__temperature")
       ! ⭐ REVERSE reshape: 1D → 2D (unflatten!)
       this%model%temperature = reshape(src, [this%model%n_y, this%model%n_x])
       bmi_status = BMI_SUCCESS
    case("plate_surface__thermal_diffusivity")
       this%model%alpha = src(1)         ! Take first element
       bmi_status = BMI_SUCCESS
    case default
       bmi_status = BMI_FAILURE
    end select
  end function
```

> ⭐ **Reverse reshape pattern:**
> ```fortran
> ! get_value: 2D → 1D (flatten)
> dest = reshape(model%temperature, [n_x * n_y])
>
> ! set_value: 1D → 2D (unflatten)
> model%temperature = reshape(src, [n_y, n_x])
> ```
> These are perfect inverses. What goes out flat comes back in flat.

### 🔧 Part 8: Functions That Return BMI_FAILURE (Not Applicable)

Some BMI functions don't apply to the heat model. They're still implemented (required
by the abstract interface) but they just return `BMI_FAILURE`:

```fortran
  ! Edge count — not applicable for a regular grid
  function heat_grid_edge_count(this, grid, count) result(bmi_status)
    class(bmi_heat), intent(in) :: this
    integer, intent(in) :: grid
    integer, intent(out) :: count
    integer :: bmi_status

    count = -1
    bmi_status = BMI_FAILURE      ! "I don't support this"
  end function
```

**Functions that return BMI_FAILURE in the heat model (8 functions):**

| Function | Why N/A |
|----------|---------|
| `get_grid_edge_count` | Regular grid, no explicit edges |
| `get_grid_face_count` | Regular grid, no explicit faces |
| `get_grid_edge_nodes` | Regular grid, no edge connectivity |
| `get_grid_face_edges` | Regular grid, no face connectivity |
| `get_grid_face_nodes` | Regular grid, no face connectivity |
| `get_grid_nodes_per_face` | Regular grid, no face topology |
| `get_value_double` (all) | No double-precision variables |
| `get_value_ptr_int` | No pointer access for integers |

> 💡 **For WRF-Hydro:** We'll need MORE of these to succeed — Grid 2 (channel network)
> IS an unstructured grid, so we'll need edge/node connectivity functions to work.

### 🔧 Part 9: The Non-BMI Helper — `update_frac` (Lines 914-926)

```fortran
  subroutine update_frac(this, time_frac)
    class(bmi_heat), intent(inout) :: this
    double precision, intent(in) :: time_frac
    real :: time_step

    if (time_frac > 0.0) then
       time_step = this%model%dt           ! Save original dt
       this%model%dt = time_step * real(time_frac)  ! Shrink dt
       call advance_in_time(this%model)    ! Take partial step
       this%model%dt = time_step           ! Restore original dt
    end if
  end subroutine
```

> 💡 This is a helper for `update_until` — when you need to advance by, say, 2.7 steps,
> you take 2 full steps and then 0.7 of a step by temporarily reducing `dt`.

---

## 6. 🚀 The Driver Program — `bmi_main.f90` (The Runner)

### 📍 File: `bmi-example-fortran/bmi_heat/bmi_main.f90` — 65 lines

This is **how you USE a BMI model** from the outside. It's the calling code.

```fortran
program bmi_main
  use bmiheatf                             ! Import the BMI wrapper
  use, intrinsic :: iso_fortran_env, only : file_unit => input_unit
  implicit none

  character(len=*), parameter :: output_file = "bmiheatf.out"
  character(len=*), parameter :: var_name = "plate_surface__temperature"
  integer, parameter :: ndims = 2

  type(bmi_heat) :: model                  ! ① Declare BMI model
  integer :: s, grid_id, grid_size, grid_shape(ndims)
  double precision :: current_time, end_time
  real, allocatable :: temperature(:)
  character(len=80) :: arg

  ! Get config file from command line
  call get_command_argument(1, arg)

  ! ② INITIALIZE
  s = model%initialize(arg)

  ! ③ QUERY model metadata
  s = model%get_current_time(current_time)
  s = model%get_end_time(end_time)
  s = model%get_var_grid(var_name, grid_id)
  s = model%get_grid_size(grid_id, grid_size)
  s = model%get_grid_shape(grid_id, grid_shape)

  allocate(temperature(grid_size))         ! Allocate output buffer

  ! ④ TIME LOOP — run until end
  do while (current_time <= end_time)
     s = model%get_value(var_name, temperature)  ! Read data
     ! ... write temperature to file ...
     s = model%update()                           ! Advance one step
     s = model%get_current_time(current_time)     ! Check time
  end do

  ! ⑤ FINALIZE
  deallocate(temperature)
  s = model%finalize()
end program
```

> 🧠 **ML Analogy — This is the inference script:**
> ```python
> # ① Declare
> model = BmiHeat()
>
> # ② Initialize
> model.initialize("config.cfg")
>
> # ③ Query metadata
> grid_id = model.get_var_grid("plate_surface__temperature")
> grid_size = model.get_grid_size(grid_id)
> temperature = np.zeros(grid_size)
>
> # ④ Time loop
> while model.get_current_time() <= model.get_end_time():
>     model.get_value("plate_surface__temperature", temperature)
>     save_output(temperature)
>     model.update()
>
> # ⑤ Finalize
> model.finalize()
> ```

### 🔄 The BMI Lifecycle Flow

```
  ┌─────────────────────────────────────────────────────────────┐
  │                    BMI LIFECYCLE                             │
  │                                                             │
  │  ┌──────────────┐                                           │
  │  │ INITIALIZE   │  model%initialize("config.cfg")           │
  │  │  • Read config│  • Allocate arrays                        │
  │  │  • Setup model│  • Set initial conditions                 │
  │  └──────┬───────┘                                           │
  │         │                                                    │
  │         ▼                                                    │
  │  ┌──────────────────────────────────────────────────┐        │
  │  │            QUERY PHASE (optional)                 │        │
  │  │  • get_component_name()                           │        │
  │  │  • get_input_var_names() / get_output_var_names() │        │
  │  │  • get_var_grid() → get_grid_shape()              │        │
  │  │  • get_var_type() / get_var_units()               │        │
  │  └──────────────────────┬───────────────────────────┘        │
  │                         │                                    │
  │                         ▼                                    │
  │  ┌──────────────────────────────────────────────────┐        │
  │  │              TIME LOOP                            │        │
  │  │                                                   │  ←── THE CALLER    │
  │  │  do while (time <= end_time)                      │      controls      │
  │  │     get_value("temperature", array)  ← read       │      the loop!     │
  │  │     set_value("forcing", new_data)   ← write      │                    │
  │  │     update()                         ← step       │                    │
  │  │  end do                                           │                    │
  │  └──────────────────────┬───────────────────────────┘        │
  │                         │                                    │
  │                         ▼                                    │
  │  ┌──────────────┐                                           │
  │  │  FINALIZE    │  model%finalize()                          │
  │  │  • Free memory│  • Close files                            │
  │  │  • Cleanup    │  • Reset state                            │
  │  └──────────────┘                                           │
  └─────────────────────────────────────────────────────────────┘
```

---

## 7. 🧪 The Test Suite — 42 Tests Explained

### 📍 Folder: `bmi-example-fortran/test/` — 43 files (42 tests + 1 fixture)

All 49 CTest cases pass (42 unit tests + 7 example programs = 49 total).

### 🧰 Test Fixtures — `fixtures.f90`

Shared utilities for all tests:

```fortran
module fixtures
  implicit none
  character(len=*), parameter :: config_file = ""      ! Use defaults
  double precision, parameter :: tolerance = 0.001d0   ! Float comparison tolerance
  integer :: status                                    ! Reusable status var
contains
  subroutine print_array(array, dims)  ! Pretty-print a 1D array as 2D
    ! ...
  end subroutine
end module
```

> 🧠 **ML Analogy:** This is like `conftest.py` in pytest — shared fixtures and helpers.

### 📋 Test Pattern — Every Test Follows This Structure

```fortran
program test_SOMETHING
  use bmif_2_0, only: BMI_SUCCESS, BMI_FAILURE   ! Import constants
  use bmiheatf                                    ! Import BMI wrapper
  use fixtures, only: status                      ! Import fixture

  type(bmi_heat) :: m                             ! Declare model

  ! ① Setup
  status = m%initialize("")                       ! Init with defaults

  ! ② Execute
  status = m%SOMETHING(args, result)              ! Call the function

  ! ③ Teardown
  status = m%finalize()

  ! ④ Assert
  if (result .ne. expected) then
     stop BMI_FAILURE                             ! Exit code 1 = test failed
  end if
end program
```

> 🧠 **ML Analogy:** Same as pytest `assert`:
> ```python
> def test_something():
>     model = BmiHeat()
>     model.initialize("")
>     result = model.something()
>     model.finalize()
>     assert result == expected
> ```

### 📊 All 42 Tests Grouped by Category

#### 🔄 IRF Tests (4 tests)

| Test File | What It Tests | Expected Value |
|-----------|--------------|----------------|
| `test_initialize.f90` | Init with empty string AND config file | Both return `BMI_SUCCESS` |
| `test_finalize.f90` | Finalize after init | Returns `BMI_SUCCESS` |
| `test_update.f90` | Time after one step | `0.333...s` (= dt = 1/(4×0.75)) |
| `test_update_until.f90` | Advance to time 3.0 | Time within tolerance of 3.0 |

#### 📋 Model Info Tests (5 tests)

| Test File | What It Tests | Expected Value |
|-----------|--------------|----------------|
| `test_get_component_name.f90` | Model name string | `"The 2D Heat Equation"` |
| `test_get_input_item_count.f90` | Number of inputs | `3` |
| `test_get_output_item_count.f90` | Number of outputs | `1` |
| `test_get_input_var_names.f90` | Input variable names | 3 CSDMS names |
| `test_get_output_var_names.f90` | Output variable names | `"plate_surface__temperature"` |

#### ⏰ Time Tests (5 tests)

| Test File | What It Tests | Expected Value |
|-----------|--------------|----------------|
| `test_get_start_time.f90` | Simulation start | `0.0` |
| `test_get_end_time.f90` | Simulation end | `20.0` |
| `test_get_current_time.f90` | Current time at init | `0.0` |
| `test_get_time_step.f90` | Time step size | `0.333...` |
| `test_get_time_units.f90` | Time unit string | `"s"` |

#### 📊 Variable Info Tests (6 tests)

| Test File | What It Tests | Expected Value |
|-----------|--------------|----------------|
| `test_get_var_grid.f90` | Grid ID for temperature | `0` |
| `test_get_var_type.f90` | Type of temperature | `"real"` |
| `test_get_var_units.f90` | Units of temperature | `"K"` |
| `test_get_var_itemsize.f90` | Bytes per element | `4` (real = 4 bytes) |
| `test_get_var_nbytes.f90` | Total bytes | `800` (200 elements × 4 bytes) |
| `test_get_var_location.f90` | Grid location | `"node"` |

#### 📐 Grid Tests (16 tests)

| Test File | What It Tests | Expected Value |
|-----------|--------------|----------------|
| `test_get_grid_type.f90` | Grid 0 type | `"uniform_rectilinear"` |
| `test_get_grid_rank.f90` | Grid 0 dimensions | `2` |
| `test_get_grid_shape.f90` | Grid 0 shape | `[20, 10]` |
| `test_get_grid_size.f90` | Grid 0 total elements | `200` |
| `test_get_grid_spacing.f90` | Grid 0 cell size | `[1.0, 1.0]` |
| `test_get_grid_origin.f90` | Grid 0 origin | `[0.0, 0.0]` |
| `test_get_grid_x.f90` | Grid 1 x-coords | `[0.0]` |
| `test_get_grid_y.f90` | Grid 1 y-coords | `[0.0]` |
| `test_get_grid_z.f90` | Grid 1 z-coords | `[0.0]` |
| `test_get_grid_node_count.f90` | Grid 0 nodes | `200` |
| `test_get_grid_edge_count.f90` | Grid 0 edges | `BMI_FAILURE` (N/A) |
| `test_get_grid_face_count.f90` | Grid 0 faces | `BMI_FAILURE` (N/A) |
| `test_get_grid_edge_nodes.f90` | Edge connectivity | `BMI_FAILURE` (N/A) |
| `test_get_grid_face_edges.f90` | Face-edge map | `BMI_FAILURE` (N/A) |
| `test_get_grid_face_nodes.f90` | Face-node map | `BMI_FAILURE` (N/A) |
| `test_get_grid_nodes_per_face.f90` | Nodes per face | `BMI_FAILURE` (N/A) |

#### 📤📥 Get/Set Value Tests (6 tests)

| Test File | What It Tests | Key Assertion |
|-----------|--------------|---------------|
| `test_get_value.f90` | Get 3 variables | Temperature boundaries = 0, diffusivity = 1.0, id = 0 |
| `test_get_value_ptr.f90` | Get pointer to temp | Same boundary check as get_value |
| `test_get_value_at_indices.f90` | Get specific indices | Values at indices match full array |
| `test_set_value.f90` | Set 3 variables | Set then get = same values |
| `test_set_value_at_indices.f90` | Set specific indices | Modified values at indices |
| `test_by_reference.f90` | Ptr vs copy after update | Pointer updates, copy doesn't |

### ⭐ The `test_by_reference` Test — Most Instructive

This test proves that `get_value_ptr` returns a LIVE reference:

```fortran
  ! Get by VALUE (copy) and by REFERENCE (pointer)
  status = m%get_value("plate_surface__temperature", tval)     ! copy
  status = m%get_value_ptr("plate_surface__temperature", tref) ! pointer

  ! Both are the same at time 0
  ! Now advance the model...
  status = m%update()

  ! tval is STALE (still has time=0 values) — it was a copy!
  ! tref is UPDATED (has time=1 values) — it's a live pointer!
  if (sum(tval) .eq. sum(tref)) then
     code = BMI_FAILURE  ! They should differ!
  end if
```

> 🧠 **ML Analogy:**
> ```python
> copy = model.temperature.clone()    # Snapshot — won't change
> ref = model.temperature             # Live reference — changes with model
> model.step()
> assert not torch.equal(copy, ref)   # copy is stale, ref is updated
> ```

---

## 8. 📚 The Example Programs — 7 Demos Explained

### 📍 Folder: `bmi-example-fortran/example/` — 8 files (7 demos + 1 helper)

These show HOW to use BMI in practice. Each demonstrates a different capability.

### 📊 `info_ex.f90` — Query Model Metadata

```fortran
  s = m%get_component_name(name)      → "The 2D Heat Equation"
  s = m%get_input_var_names(names)    → 3 CSDMS standard names
  s = m%get_output_var_names(names)   → "plate_surface__temperature"
```

> 🧠 **Like:** `model.summary()` in Keras or `print(model)` in PyTorch.

### 🔄 `irf_ex.f90` — Full IRF Lifecycle Demo

Shows the complete `initialize → update → update_until → finalize` cycle:

```fortran
  s = m%initialize("")                     ! Setup
  s = m%get_start_time(time0)              ! → 0.0
  s = m%get_end_time(time1)                ! → 20.0

  s = m%update()                           ! One step
  do i = 1, 10                             ! 10 more steps
     s = m%update()
  end do

  s = m%update_until(time0 + 0.5d0)       ! Fractional step
  s = m%update_until(end_time)             ! Run to completion
  s = m%finalize()                         ! Cleanup
```

> 🧠 **Like:** A training loop: `model.train()` → `for epoch in range(10)` → `model.eval()`

### 📐 `vargrid_ex.f90` — Variable & Grid Introspection

Queries ALL metadata for a variable:

```fortran
  s = m%get_var_grid(names(1), grid_id)    ! → 0
  s = m%get_grid_type(grid_id, astring)    ! → "uniform_rectilinear"
  s = m%get_grid_rank(grid_id, asize)      ! → 2
  s = m%get_grid_shape(grid_id, iarray)    ! → [20, 10]
  s = m%get_grid_size(grid_id, asize)      ! → 200
  s = m%get_grid_spacing(grid_id, darray)  ! → [1.0, 1.0]
  s = m%get_grid_origin(grid_id, darray)   ! → [0.0, 0.0]
  s = m%get_var_itemsize(names(1), asize)  ! → 4 bytes
  s = m%get_var_nbytes(names(1), asize)    ! → 800 bytes
  s = m%get_var_type(names(1), astring)    ! → "real"
  s = m%get_var_units(names(1), astring)   ! → "K"
```

> 🧠 **Like:** `tensor.shape`, `tensor.dtype`, `tensor.device`, `tensor.nbytes`

### 📤 `get_value_ex.f90` — Three Ways to Read Data

Demonstrates ALL getter methods back-to-back:

```fortran
  ! Method 1: get_value (copy)
  allocate(z(grid_size))
  s = m%get_value("plate_surface__temperature", z)

  ! Method 2: get_value_at_indices (cherry-pick)
  locations = [21, 41, 62]
  allocate(y(3))
  s = m%get_value_at_indices("plate_surface__temperature", y, locations)

  ! Method 3: get_value_ptr (zero-copy pointer)
  s = m%get_value_ptr("plate_surface__temperature", x)
  ! x now points directly into model memory — no copy!
```

### 📥 `set_value_ex.f90` — Overwrite Model State

```fortran
  ! Set ALL values to 42.0
  z = 42.0
  s = m%set_value("plate_surface__temperature", z)

  ! Set specific locations to -1.0
  locations = [21, 41, 62]
  values = [-1.0, -1.0, -1.0]
  s = m%set_value_at_indices("plate_surface__temperature", locations, values)
```

> 🧠 **Like:** `tensor.fill_(42.0)` or `tensor[indices] = -1.0`

### 👥 `conflicting_instances_ex.f90` — Multiple Independent Models

**This is critical for coupling!** Shows that two BMI model instances don't interfere:

```fortran
  type(bmi_heat) :: m1            ! Instance 1
  type(bmi_heat) :: m2            ! Instance 2

  s = m1%initialize(cfg_file1)   ! Different configs!
  s = m2%initialize(cfg_file2)

  ! Change model 2's data — does it affect model 1?
  s = m2%set_value_at_indices("plate_surface__temperature", [20], [42.0])

  ! Answer: NO! Each instance is independent.
  s = m1%get_value(...)  ! m1 is unchanged
  s = m2%get_value(...)  ! Only m2 was modified
```

> 🧠 **Like:** Two separate PyTorch models loaded in the same script don't share weights.
> `model1 = ResNet50(); model2 = ResNet50()` — changing `model2.fc.weight` doesn't
> affect `model1.fc.weight`.

> ⭐ **For WRF-Hydro + SCHISM coupling:** This proves we can have `bmi_wrf_hydro` and
> `bmi_schism` running simultaneously without data corruption.

### 🎛️ `change_diffusivity_ex.f90` — Modify Parameters Mid-Run

Shows how BMI's `set_value` can change model parameters:

```fortran
  ! Run 1: default alpha=1.0
  s = m%initialize(config_file)
  s = m%update_until(20.d0)
  s = m%get_value(tname, temperature)   ! Get final state
  s = m%finalize()

  ! Run 2: change alpha to 0.25 via BMI
  s = m%initialize(config_file)
  diffusivity = 0.25
  s = m%set_value("plate_surface__thermal_diffusivity", diffusivity)
  s = m%update_until(20.d0)
  s = m%get_value(tname, temperature)   ! Different result!
  s = m%finalize()
```

> 🧠 **Like:** Changing `model.learning_rate = 0.001` between training runs.

> ⭐ **For coupling:** This is exactly how SCHISM will inject coastal water levels
> into WRF-Hydro: `wrf%set_value("sea_water_surface__elevation", schism_output)`

---

## 9. 🔨 The Build System — CMake Explained

### 📍 File: `bmi-example-fortran/CMakeLists.txt` — 30 lines

```cmake
cmake_minimum_required(VERSION 3.12)

project(bmi-example-fortran
  VERSION 2.1.4
  LANGUAGES Fortran            # We're building Fortran code
)

include(GNUInstallDirs)

# ── Find the BMI Fortran library (installed via conda) ──
find_package(PkgConfig REQUIRED)
pkg_check_modules(BMIF REQUIRED IMPORTED_TARGET bmif)

# ── Build settings ──
set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod)

# ── Build each component ──
add_subdirectory(heat)          # Builds libheatf.so
add_subdirectory(bmi_heat)      # Builds libbmiheatf.so + run_bmiheatf
add_subdirectory(test)          # Builds 42 test executables
add_subdirectory(example)       # Builds 7 example executables

include(CTest)                  # Enable testing
```

> 🧠 **ML Analogy:**
> ```python
> # This is like setup.py / pyproject.toml:
> # - find_package ≈ pip install dependency
> # - add_subdirectory ≈ packages=find_packages()
> # - CTest ≈ pytest integration
> ```

### 🔗 What Gets Built

```
  CMake Build Output
  ──────────────────

  Libraries (shared .so files):
  ├── libheatf.so         ← The model (heat.f90)
  └── libbmiheatf.so      ← The BMI wrapper (bmi_heat.f90) — links to libheatf

  Executables:
  ├── run_heatf           ← Standalone model runner (main.f90)
  ├── run_bmiheatf        ← BMI driver (bmi_main.f90)
  ├── test_*              ← 42 test executables
  └── *_ex                ← 7 example executables

  Build commands:
    cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX
    cmake --build _build
    ctest --test-dir _build    ← Runs all 49 tests
```

---

## 10. 🧠 Key Patterns for WRF-Hydro — What We'll Reuse

### ✅ Pattern 1: Type Extension (Inheritance)

```fortran
! HEAT:
type, extends(bmi) :: bmi_heat
   type(heat_model) :: model         ! Holds the model instance
end type

! WRF-HYDRO (our version):
type, extends(bmi) :: bmi_wrf_hydro
   type(???) :: model                ! Will hold WRF-Hydro state
end type
```

### ✅ Pattern 2: `select case` for Variable Dispatch

```fortran
! HEAT:
select case(name)
case("plate_surface__temperature")
   dest = reshape(this%model%temperature, [...])

! WRF-HYDRO (our version):
select case(name)
case("channel_water__volume_flow_rate")
   dest = reshape(RT_DOMAIN(1)%QLINK(:,1), [...])
case("land_surface_water__depth")
   dest = reshape(RT_DOMAIN(1)%sfcheadrt, [...])
```

### ✅ Pattern 3: `reshape` for 2D↔1D Flattening

```fortran
! get_value: 2D → 1D
dest = reshape(model%temperature, [n_x * n_y])

! set_value: 1D → 2D
model%temperature = reshape(src, [n_y, n_x])
```

### ✅ Pattern 4: `c_loc` + `c_f_pointer` for Zero-Copy Pointers

```fortran
src = c_loc(model%temperature(1,1))
call c_f_pointer(src, dest_ptr, [n_elements])
```

### ✅ Pattern 5: `BMI_SUCCESS` / `BMI_FAILURE` Return Convention

Every function returns an integer: 0=success, 1=failure. Unknown variables get `case default → BMI_FAILURE`.

### ✅ Pattern 6: Initialize Delegates to Model

```fortran
! BMI wrapper never does physics — it delegates:
call initialize_from_file(this%model, config_file)  ! heat
call land_driver_ini(this%model)                    ! WRF-Hydro (our target)
```

### ✅ Pattern 7: `generic` for Type Overloading

```fortran
generic :: get_value => get_value_int, get_value_float, get_value_double
```

### ✅ Pattern 8: Functions That Return BMI_FAILURE for N/A Features

```fortran
! Not supported? Still implement it, but return failure:
function my_grid_edge_count(this, grid, count) result(bmi_status)
  count = -1
  bmi_status = BMI_FAILURE
end function
```

### 📊 Summary: What We Copy vs What We Customize

```
┌────────────────────────────────┬─────────────┬────────────────────────┐
│ Component                      │ Copy/Modify │ Notes                  │
├────────────────────────────────┼─────────────┼────────────────────────┤
│ Module structure & imports     │ Copy        │ Change names only      │
│ Type definition (extends bmi)  │ Copy        │ Change model type      │
│ Procedure mapping block        │ Copy        │ Change function names  │
│ generic interfaces             │ Copy        │ Identical              │
│ get_component_name             │ Copy        │ Change name string     │
│ input/output_item_count        │ Copy        │ Change counts          │
│ input/output_var_names         │ Customize   │ Our CSDMS names        │
│ initialize                     │ Customize   │ Call WRF-Hydro init    │
│ update                         │ Customize   │ Call WRF-Hydro step    │
│ update_until                   │ Copy        │ Loop logic identical   │
│ finalize                       │ Customize   │ Call WRF-Hydro cleanup │
│ get_var_type/units/grid        │ Customize   │ Our variable mappings  │
│ get_var_itemsize               │ Customize   │ Our variable sizes     │
│ get_var_nbytes                 │ Copy        │ Model-independent!     │
│ get_var_location               │ Customize   │ Our grid locations     │
│ Time functions (5)             │ Customize   │ Our time handling      │
│ Grid functions (uniform)       │ Customize   │ 1km and 250m grids    │
│ Grid functions (unstructured)  │ Customize   │ Channel network        │
│ get_value (by type)            │ Customize   │ Our variables + reshape│
│ set_value (by type)            │ Customize   │ Our variables + reshape│
│ get_value_ptr                  │ Customize   │ Our pointers           │
│ get/set_value_at_indices       │ Customize   │ Our index access       │
│ N/A functions                  │ Copy        │ Return BMI_FAILURE     │
└────────────────────────────────┴─────────────┴────────────────────────┘
```

---

## 11. 📋 Quick Reference Card

### 🔑 Key Fortran Syntax Cheat Sheet (for this code)

| Fortran | Python | What It Does |
|---------|--------|-------------|
| `module name ... end module` | `class Name:` | Namespace/container |
| `type :: name ... end type` | `@dataclass class Name:` | Data structure |
| `type, extends(parent)` | `class Child(Parent):` | Inheritance |
| `type, abstract` | `class ABC(ABC):` | Abstract base class |
| `procedure, deferred` | `@abstractmethod` | Must implement in child |
| `intent(in)` | (read-only param) | Argument won't be modified |
| `intent(out)` | (write-only param) | Argument is the "return value" |
| `intent(inout)` | (read-write param) | Argument is modified in-place |
| `select case(x)` | `match x:` / `if/elif` | Switch statement |
| `allocate(arr(n))` | `arr = np.zeros(n)` | Dynamic memory allocation |
| `deallocate(arr)` | `del arr` | Free memory |
| `reshape(arr, [n])` | `arr.reshape(n)` | Reshape array |
| `this%model%field` | `self.model.field` | Access nested object field |
| `result(bmi_status)` | `-> int` | Return type annotation |
| `pointer` | Reference/view | Points to existing data |
| `target` | (allows references) | Marks variable as "pointable" |
| `c_loc(x)` | `ctypes.addressof(x)` | Get raw memory address |
| `c_f_pointer(ptr, arr, [n])` | `ctypes.cast(...)` | Cast C pointer to Fortran array |

### 📊 The 3 Variable Exchange Methods

| Method | Speed | Safety | When to Use |
|--------|-------|--------|-------------|
| `get_value` | Slow (copies) | Safe | Default — always works |
| `get_value_ptr` | Fast (zero-copy) | Dangerous | Performance-critical inner loops |
| `get_value_at_indices` | Medium | Safe | Only need a few values |

### 🔢 Numbers to Remember

| Metric | Heat Model | WRF-Hydro (Croton) |
|--------|-----------|---------------------|
| Source lines | 158 | 172,000+ |
| BMI wrapper lines | 935 | ~1,500-2,000 (estimated) |
| Input variables | 3 | ~10 |
| Output variables | 1 | ~8 |
| Grids | 2 (2D + scalar) | 3 (1km + 250m + network) |
| Time step | 0.333s | 3600s (1 hour) |
| Grid size | 200 (10×20) | ~16,000+ cells |

### 📁 File Locations Quick Reference

```
bmi-fortran/bmi.f90                          ← Abstract BMI spec (564 lines)
bmi-example-fortran/heat/heat.f90            ← Heat model physics (158 lines)
bmi-example-fortran/bmi_heat/bmi_heat.f90    ← BMI wrapper template (935 lines)
bmi-example-fortran/bmi_heat/bmi_main.f90    ← Driver program (65 lines)
bmi-example-fortran/test/                    ← 42 unit tests
bmi-example-fortran/example/                 ← 7 demo programs
```

---

> 🎯 **Next Step:** Use everything learned here to write `bmi_wrf_hydro.f90` —
> following the exact patterns from `bmi_heat.f90` but connecting to WRF-Hydro's
> `land_driver_ini()`, `land_driver_exe()`, and `HYDRO_finish()` subroutines.
