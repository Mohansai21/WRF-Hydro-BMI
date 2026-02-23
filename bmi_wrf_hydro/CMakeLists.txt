# ============================================================================
# CMakeLists.txt -- WRF-Hydro BMI Wrapper Build Configuration
# ============================================================================
#
# PURPOSE:
#   This file tells CMake how to compile two things:
#     1. libwrfhydro_bmi.so  -- The BMI wrapper shared library
#     2. bmi_wrf_hydro_test  -- The test executable that validates all 41 BMI functions
#
# WHAT IS CMAKE?
#   CMake is a build system generator. Instead of writing Makefiles by hand,
#   you describe your project in CMakeLists.txt and CMake generates the
#   Makefile for you. Think of it like a "build recipe" that works on any OS.
#
#   ML analogy: CMake is like a Dockerfile for compiling code -- it describes
#   what to build and what dependencies are needed, and the tool figures out
#   the exact compilation commands.
#
# PREREQUISITES (must be done before running cmake):
#   1. Activate conda environment:
#        source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi
#   2. WRF-Hydro must be compiled at ../wrf_hydro_nwm_public/build/
#   3. bmi-fortran 2.0.3 must be installed in $CONDA_PREFIX (via conda)
#
# HOW TO BUILD:
#   source ~/miniconda3/etc/profile.d/conda.sh
#   conda activate wrfhydro-bmi
#   cd bmi_wrf_hydro
#   cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX
#   cmake --build _build
#   ctest --test-dir _build
#
# HOW TO INSTALL (optional, puts library into conda env):
#   cmake --install _build
# ============================================================================


# ============================================================================
# SECTION 1: Project Setup
# ============================================================================
# cmake_minimum_required: Sets the oldest CMake version that can process this
# file. Version 3.14 is needed for "install()" improvements and the
# FetchContent module. If the user has an older CMake, they get a clear error.
cmake_minimum_required(VERSION 3.14)

# project(): Declares the project name, version, and language.
#   - "wrfhydro_bmi" becomes the project name (used in variable names)
#   - VERSION 1.0.0 sets PROJECT_VERSION and related variables
#   - LANGUAGES Fortran tells CMake we only need a Fortran compiler
#     (no C, no C++ -- keeps the build simpler)
project(wrfhydro_bmi
  VERSION 1.0.0
  LANGUAGES Fortran
)

# include(GNUInstallDirs): Provides standard installation directory variables
# like CMAKE_INSTALL_LIBDIR (usually "lib"), CMAKE_INSTALL_INCLUDEDIR
# (usually "include"), etc. This ensures our install paths follow conventions.
include(GNUInstallDirs)

# CMAKE_BUILD_TYPE: Controls optimization level.
#   - Release: -O2 (fast code, no debug symbols) -- for production runs
#   - Debug: -O0 -g (no optimization, debug symbols) -- for debugging
#   - RelWithDebInfo: -O2 -g (optimized but with debug info) -- best of both
# If the user didn't specify one on the command line, default to Release.
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING
    "Build type: Release, Debug, or RelWithDebInfo" FORCE)
endif()
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")

# CMAKE_Fortran_MODULE_DIRECTORY: When gfortran compiles a Fortran module
# (e.g., "module bmi_wrf_hydro"), it produces a .mod file (like a header file
# in C). This setting tells CMake to put ALL .mod files into _build/mod/ so
# they are easy to find. Without this, .mod files scatter across build dirs.
set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod)


# ============================================================================
# SECTION 2: Find BMI Fortran Library (bmi-fortran 2.0.3)
# ============================================================================
# The BMI Fortran library provides the abstract interface that our wrapper
# must implement. It defines the "bmi" type with 41 deferred procedures.
#
# Installed by: conda install -c conda-forge bmi-fortran
# Provides:
#   - $CONDA_PREFIX/include/bmif_2_0.mod  (Fortran module file)
#   - $CONDA_PREFIX/lib/libbmif.so        (shared library)
#
# We use pkg-config to find it, matching the approach in bmi-example-fortran.
# pkg-config reads .pc files that describe library locations and flags.
# ============================================================================

# PkgConfig is a CMake module that wraps the pkg-config command-line tool.
# pkg-config is widely used on Linux to find installed libraries.
find_package(PkgConfig REQUIRED)

# pkg_check_modules: Runs "pkg-config --cflags --libs bmif" to find:
#   BMIF_INCLUDE_DIRS  -> where bmif_2_0.mod lives (e.g., $CONDA_PREFIX/include)
#   BMIF_LINK_LIBRARIES -> full path to libbmif.so
#   BMIF_VERSION        -> version string (e.g., "2.0.3")
# REQUIRED means cmake will STOP with an error if bmif is not found.
# IMPORTED_TARGET creates a CMake target "PkgConfig::BMIF" we can link against.
pkg_check_modules(BMIF REQUIRED IMPORTED_TARGET bmif)

# Display what we found (helps with debugging build issues)
message(STATUS "BMI Fortran version: ${BMIF_VERSION}")
message(STATUS "BMI Fortran library: ${BMIF_LINK_LIBRARIES}")
message(STATUS "BMI Fortran include: ${BMIF_INCLUDE_DIRS}")

# Make BMI module files visible to all targets in this project.
# include_directories() adds -I flags to the compiler command line.
# This tells gfortran: "look here for .mod files when you see 'use bmif_2_0'".
include_directories(${BMIF_INCLUDE_DIRS})


# ============================================================================
# SECTION 3: Find MPI (Message Passing Interface)
# ============================================================================
# WRF-Hydro is an MPI-parallel application. Even though our BMI wrapper
# starts in serial mode, the WRF-Hydro libraries were compiled with MPI,
# so we must link against MPI to resolve symbols like MPI_Init, MPI_Comm_rank.
#
# find_package(MPI): CMake's built-in MPI finder. It locates:
#   - MPI Fortran compiler wrapper (mpif90)
#   - MPI include directories (for mpif.h / mpi.mod)
#   - MPI libraries (libmpi_mpifh.so, libmpi.so, etc.)
# REQUIRED means cmake stops if MPI is not found.
# ============================================================================
find_package(MPI REQUIRED)
message(STATUS "MPI Fortran compiler: ${MPI_Fortran_COMPILER}")
message(STATUS "MPI Fortran include: ${MPI_Fortran_INCLUDE_DIRS}")


# ============================================================================
# SECTION 4: Find NetCDF Libraries
# ============================================================================
# WRF-Hydro reads/writes NetCDF files (a standard scientific data format,
# like HDF5 but for climate/weather data). We need both:
#   - NetCDF-Fortran (libnetcdff.so) -- Fortran bindings
#   - NetCDF-C (libnetcdf.so)       -- underlying C library
#
# These are installed via conda in $CONDA_PREFIX/lib/.
# We use find_library() which searches for a library file by name.
# ============================================================================

# NETCDF_PREFIX: Where to look for NetCDF. Defaults to $CONDA_PREFIX but
# can be overridden on the command line:
#   cmake -DNETCDF_PREFIX=/custom/path ...
set(NETCDF_PREFIX "$ENV{CONDA_PREFIX}" CACHE PATH
  "Path to NetCDF installation (default: CONDA_PREFIX)")

# find_library: Searches for a library file.
#   NAMES netcdff   -> look for libnetcdff.so (or .a, .dylib)
#   PATHS ...       -> search in this directory
#   REQUIRED        -> stop with error if not found
# The result (full path to the library) is stored in the variable.
find_library(NETCDFF_LIBRARY
  NAMES netcdff
  PATHS "${NETCDF_PREFIX}/lib"
  REQUIRED
)
find_library(NETCDF_LIBRARY
  NAMES netcdf
  PATHS "${NETCDF_PREFIX}/lib"
  REQUIRED
)
message(STATUS "NetCDF-Fortran library: ${NETCDFF_LIBRARY}")
message(STATUS "NetCDF-C library: ${NETCDF_LIBRARY}")


# ============================================================================
# SECTION 5: Find WRF-Hydro Libraries
# ============================================================================
# WRF-Hydro was already compiled (via cmake) into static libraries (.a files)
# at ../wrf_hydro_nwm_public/build/lib/. We need to link against ALL of them
# because our BMI wrapper calls WRF-Hydro subroutines (HYDRO_ini, HYDRO_exe,
# land_driver_ini, land_driver_exe, etc.) which depend on the full model.
#
# WRF-Hydro also produces .mod files (Fortran module files) that we need
# so our wrapper can "use" WRF-Hydro modules and access their types/variables.
#
# LIBRARY DEPENDENCY ORDER MATTERS for static libraries!
# When linking .a files, the linker processes them left to right. If library A
# calls functions in library B, then A must come BEFORE B in the link line.
# This is the opposite of how you might expect it to work.
#
# ML analogy: Think of it like a DAG (directed acyclic graph) of dependencies.
# The "leaf" libraries (no dependencies) go last, and the "root" libraries
# (depend on everything) go first.
# ============================================================================

# WRFHYDRO_BUILD_DIR: Path to the WRF-Hydro build directory.
# Default: ../wrf_hydro_nwm_public/build/ (relative to this CMakeLists.txt)
# Can be overridden: cmake -DWRFHYDRO_BUILD_DIR=/path/to/build ...
set(WRFHYDRO_BUILD_DIR
  "${CMAKE_SOURCE_DIR}/../wrf_hydro_nwm_public/build"
  CACHE PATH "Path to WRF-Hydro build directory")

# Verify the WRF-Hydro build directory exists (fail early with a clear message)
if(NOT EXISTS "${WRFHYDRO_BUILD_DIR}/lib")
  message(FATAL_ERROR
    "WRF-Hydro build directory not found at: ${WRFHYDRO_BUILD_DIR}/lib\n"
    "Please compile WRF-Hydro first:\n"
    "  cd ../wrf_hydro_nwm_public && mkdir -p build && cd build\n"
    "  cmake .. -DCMAKE_BUILD_TYPE=Release && make -j$(nproc)\n"
    "Or set -DWRFHYDRO_BUILD_DIR=/path/to/build when running cmake.")
endif()

# --- Locate WRF-Hydro .mod files ---
# WRF-Hydro puts all its .mod files in build/mods/. We need these so that
# when bmi_wrf_hydro.f90 says "use module_hydro_drv", gfortran can find
# module_hydro_drv.mod. The -I flag tells gfortran where to look.
set(WRFHYDRO_MOD_DIR "${WRFHYDRO_BUILD_DIR}/mods")
if(NOT EXISTS "${WRFHYDRO_MOD_DIR}")
  message(FATAL_ERROR
    "WRF-Hydro module directory not found at: ${WRFHYDRO_MOD_DIR}\n"
    "This directory should contain .mod files from the WRF-Hydro build.")
endif()
message(STATUS "WRF-Hydro module dir: ${WRFHYDRO_MOD_DIR}")

# --- Locate each WRF-Hydro static library (.a file) ---
# We use find_library() for each one. This is more robust than hardcoding
# paths because find_library() checks that the file actually exists.
#
# The libraries are listed in dependency order (highest-level first):
#   hydro_noahmp_cpl -> depends on hydro_driver, hydro_routing, hydro_mpp
#   hydro_driver     -> depends on hydro_routing, hydro_debug_utils
#   hydro_routing    -> depends on all sub-routing libs, hydro_mpp, hydro_utils
#   ... and so on down to the leaf libraries
set(WRFHYDRO_LIB_DIR "${WRFHYDRO_BUILD_DIR}/lib")

# Helper macro to find a WRF-Hydro library and store it in a variable.
# Usage: find_wrfhydro_lib(VARNAME libname)
# Example: find_wrfhydro_lib(WRFHYDRO_DRIVER hydro_driver)
#   -> finds libhydro_driver.a in WRFHYDRO_LIB_DIR
#   -> stores full path in WRFHYDRO_DRIVER
macro(find_wrfhydro_lib VARNAME LIBNAME)
  find_library(${VARNAME}
    NAMES ${LIBNAME}
    PATHS "${WRFHYDRO_LIB_DIR}"
    NO_DEFAULT_PATH       # Only look in our specified path, not system dirs
    REQUIRED
  )
  message(STATUS "  Found ${LIBNAME}: ${${VARNAME}}")
endmacro()

message(STATUS "Locating WRF-Hydro libraries in: ${WRFHYDRO_LIB_DIR}")

# --- High-level libraries (depend on lower-level ones) ---
# hydro_noahmp_cpl: Coupling layer between Noah-MP land model and hydro routing
find_wrfhydro_lib(WRF_LIB_NOAHMP_CPL    hydro_noahmp_cpl)

# hydro_driver: Main hydro driver (HYDRO_ini, HYDRO_exe, HYDRO_finish)
find_wrfhydro_lib(WRF_LIB_DRIVER        hydro_driver)

# --- Routing libraries ---
# hydro_routing: Channel routing (Muskingum-Cunge, diffusive wave)
find_wrfhydro_lib(WRF_LIB_ROUTING       hydro_routing)

# hydro_routing_overland: Overland flow routing (2D surface water)
find_wrfhydro_lib(WRF_LIB_ROUTING_OVR   hydro_routing_overland)

# hydro_routing_subsurface: Subsurface/saturated lateral flow
find_wrfhydro_lib(WRF_LIB_ROUTING_SUB   hydro_routing_subsurface)

# hydro_routing_reservoirs: Reservoir routing (base module)
find_wrfhydro_lib(WRF_LIB_ROUTING_RES   hydro_routing_reservoirs)

# hydro_routing_reservoirs_levelpool: Level-pool reservoir method
find_wrfhydro_lib(WRF_LIB_ROUTING_LP    hydro_routing_reservoirs_levelpool)

# hydro_routing_reservoirs_hybrid: Hybrid persistence + level-pool reservoirs
find_wrfhydro_lib(WRF_LIB_ROUTING_HYB   hydro_routing_reservoirs_hybrid)

# hydro_routing_reservoirs_rfc: RFC (River Forecast Center) reservoir method
find_wrfhydro_lib(WRF_LIB_ROUTING_RFC   hydro_routing_reservoirs_rfc)

# hydro_routing_diversions: Channel diversions
find_wrfhydro_lib(WRF_LIB_ROUTING_DIV   hydro_routing_diversions)

# --- Data and infrastructure libraries ---
# hydro_data_rec: Data record types (RT_FIELD -- holds ALL routing state vars)
find_wrfhydro_lib(WRF_LIB_DATA_REC      hydro_data_rec)

# hydro_orchestrator: I/O orchestration layer
find_wrfhydro_lib(WRF_LIB_ORCHESTRATOR  hydro_orchestrator)

# hydro_netcdf_layer: NetCDF I/O abstraction
find_wrfhydro_lib(WRF_LIB_NETCDF_LAYER  hydro_netcdf_layer)

# --- Utility libraries ---
# hydro_mpp: MPI parallelism wrappers (message passing, domain decomposition)
find_wrfhydro_lib(WRF_LIB_MPP           hydro_mpp)

# hydro_utils: General utility functions
find_wrfhydro_lib(WRF_LIB_UTILS         hydro_utils)

# hydro_debug_utils: Debug printing utilities
find_wrfhydro_lib(WRF_LIB_DEBUG         hydro_debug_utils)

# --- Noah-MP land surface model libraries ---
# noahmp_phys: Noah-MP physics (energy balance, soil, snow, vegetation)
find_wrfhydro_lib(WRF_LIB_NOAHMP_PHYS   noahmp_phys)

# noahmp_util: Noah-MP utility functions
find_wrfhydro_lib(WRF_LIB_NOAHMP_UTIL   noahmp_util)

# noahmp_data: Noah-MP parameter data
find_wrfhydro_lib(WRF_LIB_NOAHMP_DATA   noahmp_data)

# --- Snow model libraries ---
# snowcro: Crocus snow model (advanced snow physics)
find_wrfhydro_lib(WRF_LIB_SNOWCRO       snowcro)

# crocus_surfex: Surface exchange for Crocus
find_wrfhydro_lib(WRF_LIB_CROCUS        crocus_surfex)

# --- Misc libraries ---
# fortglob: Fortran glob (file pattern matching)
find_wrfhydro_lib(WRF_LIB_FORTGLOB      fortglob)

# Collect ALL WRF-Hydro libraries into a single list variable.
# ORDER MATTERS! Higher-level libs first, lower-level libs last.
# This order mirrors what WRF-Hydro's own CMakeLists.txt uses for the
# wrfhydro executable (see wrf_hydro_nwm_public/src/CMakeLists.txt line 111).
#
# If you get "undefined reference" linker errors, the fix is usually to
# reorder this list so the library providing the missing symbol comes LATER.
set(WRFHYDRO_LIBRARIES
  ${WRF_LIB_NOAHMP_CPL}          # Highest level: Noah-MP <-> Hydro coupling
  ${WRF_LIB_DRIVER}              # HYDRO_ini / HYDRO_exe / HYDRO_finish
  ${WRF_LIB_ROUTING}             # Channel routing (largest lib, 3.8MB)
  ${WRF_LIB_DATA_REC}            # RT_FIELD type definition
  ${WRF_LIB_ROUTING_OVR}         # Overland flow
  ${WRF_LIB_ROUTING_SUB}         # Subsurface flow
  ${WRF_LIB_ROUTING_RES}         # Reservoir base
  ${WRF_LIB_ROUTING_LP}          # Level-pool reservoirs
  ${WRF_LIB_ROUTING_HYB}         # Hybrid reservoirs
  ${WRF_LIB_ROUTING_RFC}         # RFC reservoirs
  ${WRF_LIB_ROUTING_DIV}         # Diversions
  ${WRF_LIB_ORCHESTRATOR}        # I/O orchestration
  ${WRF_LIB_NETCDF_LAYER}        # NetCDF abstraction
  ${WRF_LIB_NOAHMP_PHYS}         # Noah-MP physics
  ${WRF_LIB_NOAHMP_UTIL}         # Noah-MP utilities
  ${WRF_LIB_NOAHMP_DATA}         # Noah-MP data
  ${WRF_LIB_SNOWCRO}             # Crocus snow model
  ${WRF_LIB_CROCUS}              # Crocus surface exchange
  ${WRF_LIB_DEBUG}               # Debug utilities
  ${WRF_LIB_UTILS}               # General utilities
  ${WRF_LIB_MPP}                 # MPI wrappers (lowest level)
  ${WRF_LIB_FORTGLOB}            # File globbing
)


# ============================================================================
# SECTION 6: Compiler Flags
# ============================================================================
# Fortran compiler flags control how source code is compiled. Different
# compilers (gfortran, ifort, etc.) use different flag syntax.
#
# Key flags for our BMI wrapper:
#   -ffree-form              : Source code uses free-form layout (not 72-column)
#   -ffree-line-length-none  : No limit on line length (Fortran default is 132)
#   -fPIC                    : Position Independent Code (required for .so)
#   -cpp                     : Enable C preprocessor (#ifdef, #define, etc.)
#   -fallow-argument-mismatch: Needed for gfortran 10+ (relaxes type checking
#                              for old-style Fortran interfaces in WRF-Hydro)
#
# Preprocessor defines (-D flags):
#   -DWRF_HYDRO   : Enables WRF-Hydro code blocks (#ifdef WRF_HYDRO)
#   -DMPP_LAND    : Enables MPI land domain decomposition code
#   -DUSE_NWM_BMI : Our own flag for BMI-specific code blocks
#
# We do NOT set -DHYDRO_D here (that enables verbose debug printing in
# WRF-Hydro, which floods stdout). Set it only for Debug builds.
# ============================================================================

# These flags will be set per-target below (not globally) for cleanliness.
# We store them in variables first for readability.
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
  message(STATUS "Fortran compiler: gfortran ${CMAKE_Fortran_COMPILER_VERSION}")

  # Base flags for our BMI wrapper source files
  set(BMI_FORTRAN_FLAGS
    -ffree-form                # Free-form source layout (not fixed 72-column)
    -ffree-line-length-none    # Allow arbitrarily long lines
    -fPIC                      # Position Independent Code (needed for shared lib)
    -cpp                       # Enable C preprocessor for #ifdef directives
    -fconvert=big-endian       # Match WRF-Hydro's byte order for binary I/O
    -frecord-marker=4          # 4-byte record markers (matches WRF-Hydro)
  )

  # gfortran 10+ requires this flag because WRF-Hydro has some legacy
  # interfaces where argument types don't match exactly (common in MPI code).
  if(CMAKE_Fortran_COMPILER_VERSION VERSION_GREATER_EQUAL 10)
    list(APPEND BMI_FORTRAN_FLAGS -fallow-argument-mismatch)
  endif()

  # Preprocessor defines that match WRF-Hydro's build configuration
  set(BMI_PREPROCESSOR_DEFS
    -DWRF_HYDRO               # Enable WRF-Hydro code paths
    -DMPP_LAND                 # Enable MPI land parallelism code
    -DUSE_NWM_BMI              # Enable our BMI wrapper code blocks
  )

  # Optimization flags per build type
  set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
  set(CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g -fbacktrace -fcheck=all -Wall")

elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
  message(STATUS "Fortran compiler: ifort/ifx ${CMAKE_Fortran_COMPILER_VERSION}")
  set(BMI_FORTRAN_FLAGS -fpp -fPIC -FR -ftz -align all -fno-alias -fp-model precise)
  set(BMI_PREPROCESSOR_DEFS -DWRF_HYDRO -DMPP_LAND -DUSE_NWM_BMI)
  set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
  set(CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g -traceback -check all")

else()
  message(WARNING "Unknown Fortran compiler: ${CMAKE_Fortran_COMPILER_ID}. "
    "Using generic flags. You may need to adjust manually.")
  set(BMI_FORTRAN_FLAGS -cpp -fPIC)
  set(BMI_PREPROCESSOR_DEFS -DWRF_HYDRO -DMPP_LAND -DUSE_NWM_BMI)
endif()


# ============================================================================
# SECTION 7: BMI Wrapper Shared Library (libwrfhydro_bmi.so)
# ============================================================================
# This is the main output of this project: a shared library that implements
# the BMI interface for WRF-Hydro. Other programs (test driver, Python via
# babelizer, PyMT) will load this library to control WRF-Hydro.
#
# Shared library (.so) vs Static library (.a):
#   - .so can be loaded at runtime (needed for Python ctypes / babelizer)
#   - .a gets linked into the executable at compile time
#   We need .so because the babelizer (Phase 2) loads it from Python.
#
# ML analogy: The .so file is like a trained model checkpoint. Other programs
# load it and call its functions (predict/initialize/update) without knowing
# the internal implementation details.
# ============================================================================

# add_library: Creates a build target.
#   SHARED -> produce a .so file (shared library)
#   bmi_wrf_hydro.f90 -> the source file to compile
add_library(wrfhydro_bmi SHARED
  src/bmi_wrf_hydro.f90
)

# target_compile_options: Add compiler flags to THIS target only.
# PRIVATE means these flags apply only when compiling wrfhydro_bmi's own
# source files, not when other targets link against it.
target_compile_options(wrfhydro_bmi PRIVATE
  ${BMI_FORTRAN_FLAGS}
  ${BMI_PREPROCESSOR_DEFS}
)

# target_include_directories: Tell the compiler where to find .mod files.
# When bmi_wrf_hydro.f90 says "use module_hydro_drv", gfortran needs to find
# module_hydro_drv.mod. We provide three search paths:
#   1. BMI include dir        -> for bmif_2_0.mod (the BMI abstract interface)
#   2. WRF-Hydro mods dir    -> for all WRF-Hydro module files (86 .mod files)
#   3. Our own mod dir        -> for any modules WE create during the build
#   4. MPI include dirs       -> for mpi.mod / mpif.h
target_include_directories(wrfhydro_bmi PRIVATE
  ${BMIF_INCLUDE_DIRS}                   # bmif_2_0.mod from bmi-fortran
  ${WRFHYDRO_MOD_DIR}                    # All 86 WRF-Hydro .mod files
  ${CMAKE_Fortran_MODULE_DIRECTORY}      # Our own .mod files (_build/mod/)
  ${MPI_Fortran_INCLUDE_DIRS}            # MPI module files
)

# target_link_libraries: Specify what libraries to link against.
# When the linker creates libwrfhydro_bmi.so, it needs to resolve all the
# external symbols (function calls) that bmi_wrf_hydro.f90 makes.
#
# The link order is critical for static libraries (.a files):
#   - Our BMI lib calls WRF-Hydro functions -> WRF-Hydro libs come after
#   - WRF-Hydro calls NetCDF functions -> NetCDF comes after WRF-Hydro
#   - WRF-Hydro calls MPI functions -> MPI comes last
#
# We wrap WRF-Hydro libs in --start-group/--end-group to handle circular
# dependencies between the static libraries. This tells the linker to scan
# the group multiple times until all symbols are resolved.
target_link_libraries(wrfhydro_bmi
  ${BMIF_LINK_LIBRARIES}                 # libbmif.so (BMI abstract interface)
  -Wl,--start-group                      # BEGIN: resolve circular deps
  ${WRFHYDRO_LIBRARIES}                  # All 22 WRF-Hydro static libraries
  -Wl,--end-group                        # END: circular dep resolution
  ${NETCDFF_LIBRARY}                     # libnetcdff.so (NetCDF Fortran)
  ${NETCDF_LIBRARY}                      # libnetcdf.so (NetCDF C)
  MPI::MPI_Fortran                       # MPI libraries (via CMake target)
)

# Set the output name and properties for the shared library
# SOVERSION: The "API version" -- increment when the interface changes
# VERSION: The "release version" -- full version number
set_target_properties(wrfhydro_bmi PROPERTIES
  OUTPUT_NAME wrfhydro_bmi               # Produces libwrfhydro_bmi.so
  VERSION ${PROJECT_VERSION}             # libwrfhydro_bmi.so.1.0.0
  SOVERSION 1                            # libwrfhydro_bmi.so.1 (symlink)
  Fortran_MODULE_DIRECTORY ${CMAKE_Fortran_MODULE_DIRECTORY}
)


# ============================================================================
# SECTION 8: Test Executable (bmi_wrf_hydro_test)
# ============================================================================
# The test driver is a standalone Fortran program that:
#   1. Creates a bmi_wrf_hydro object
#   2. Calls all 41 BMI functions
#   3. Checks return values (BMI_SUCCESS = 0 or BMI_FAILURE = 1)
#   4. Reports pass/fail for each function
#
# It links against our libwrfhydro_bmi.so library, so it only needs to know
# about the BMI interface -- not WRF-Hydro's internals.
# ============================================================================

# add_executable: Creates a build target that produces an executable binary.
add_executable(bmi_wrf_hydro_test
  tests/bmi_wrf_hydro_test.f90
)

# The test driver needs to find:
#   - bmif_2_0.mod (BMI abstract type, for "use bmif_2_0")
#   - bmi_wrf_hydro.mod (our wrapper module, for "use bmi_wrf_hydro_module")
target_compile_options(bmi_wrf_hydro_test PRIVATE
  ${BMI_FORTRAN_FLAGS}
)

target_include_directories(bmi_wrf_hydro_test PRIVATE
  ${BMIF_INCLUDE_DIRS}                   # bmif_2_0.mod
  ${CMAKE_Fortran_MODULE_DIRECTORY}      # bmi_wrf_hydro.mod (built by us)
)

# The test executable links against our BMI wrapper library.
# Because wrfhydro_bmi is a SHARED library, it transitively brings in
# all of WRF-Hydro, NetCDF, and MPI -- so we don't need to list them again.
target_link_libraries(bmi_wrf_hydro_test
  wrfhydro_bmi                           # Our BMI wrapper (pulls in everything)
  ${BMIF_LINK_LIBRARIES}                 # libbmif.so
)


# ============================================================================
# SECTION 9: CTest Registration
# ============================================================================
# CTest is CMake's built-in test runner. After building, you can run:
#   ctest --test-dir _build
# and it will execute all registered tests and report pass/fail.
#
# The test must run from the WRF-Hydro run directory (where namelists,
# forcing data, and domain files live) because WRF-Hydro expects to find
# these files in the current working directory.
# ============================================================================

# enable_testing(): Turns on CTest support. Without this, add_test() does nothing.
enable_testing()

# add_test: Register our test executable with CTest.
#   NAME: The test name shown in CTest output
#   COMMAND: The executable to run
#   WORKING_DIRECTORY: cd to this directory before running the test.
#     WRF-Hydro needs namelists (namelist.hrldas, hydro.namelist) and input
#     files (DOMAIN/, FORCING/) in the current directory. These are set up
#     in WRF_Hydro_Run_Local/run/ for the Croton NY test case.
add_test(
  NAME bmi_wrf_hydro_all_tests
  COMMAND bmi_wrf_hydro_test
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/../WRF_Hydro_Run_Local/run"
)

# set_tests_properties: Configure test behavior.
#   TIMEOUT 300: Kill the test after 5 minutes (WRF-Hydro init can be slow)
#   ENVIRONMENT: Pass environment variables to the test process.
#     LD_LIBRARY_PATH ensures the test can find libwrfhydro_bmi.so at runtime.
set_tests_properties(bmi_wrf_hydro_all_tests PROPERTIES
  TIMEOUT 300
  ENVIRONMENT "LD_LIBRARY_PATH=${CMAKE_BINARY_DIR}:$ENV{CONDA_PREFIX}/lib:$ENV{LD_LIBRARY_PATH}"
)


# ============================================================================
# SECTION 10: Installation Rules
# ============================================================================
# "Installing" copies the built artifacts to a standard location so other
# projects can find them. With -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX, the
# library and module files go into the conda environment, making them
# available to the babelizer (Phase 2) and PyMT (Phase 3).
#
# After installation:
#   $CONDA_PREFIX/lib/libwrfhydro_bmi.so       <- shared library
#   $CONDA_PREFIX/include/bmi_wrf_hydro.mod    <- Fortran module file
#   $CONDA_PREFIX/bin/bmi_wrf_hydro_test       <- test executable
# ============================================================================

# install(TARGETS ...): Copy the built library to the install prefix.
#   LIBRARY DESTINATION -> for .so files (Linux shared libraries)
#   ARCHIVE DESTINATION -> for .a files (if we ever build a static version)
#   RUNTIME DESTINATION -> for .exe files (Windows DLLs go here too)
install(TARGETS wrfhydro_bmi
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install the test executable
install(TARGETS bmi_wrf_hydro_test
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install the Fortran module file so other Fortran projects can "use" our module.
# The .mod filename is determined by the module name in bmi_wrf_hydro.f90.
# We use a glob because the exact filename depends on the compiler
# (gfortran lowercases it, ifort preserves case).
install(
  DIRECTORY ${CMAKE_Fortran_MODULE_DIRECTORY}/
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
  FILES_MATCHING PATTERN "*.mod"
)


# ============================================================================
# SECTION 11: Build Summary
# ============================================================================
# Print a summary of all configuration to help users verify their setup.
# This appears at the end of the cmake configuration step.
# ============================================================================
message(STATUS "")
message(STATUS "=============================================================")
message(STATUS "  WRF-Hydro BMI Wrapper - Configuration Summary")
message(STATUS "=============================================================")
message(STATUS "  Project version:     ${PROJECT_VERSION}")
message(STATUS "  Build type:          ${CMAKE_BUILD_TYPE}")
message(STATUS "  Fortran compiler:    ${CMAKE_Fortran_COMPILER}")
message(STATUS "  Compiler ID:         ${CMAKE_Fortran_COMPILER_ID} ${CMAKE_Fortran_COMPILER_VERSION}")
message(STATUS "  Install prefix:      ${CMAKE_INSTALL_PREFIX}")
message(STATUS "  ---")
message(STATUS "  BMI Fortran:         ${BMIF_VERSION} (${BMIF_LINK_LIBRARIES})")
message(STATUS "  WRF-Hydro build:     ${WRFHYDRO_BUILD_DIR}")
message(STATUS "  WRF-Hydro libs:      22 static libraries in ${WRFHYDRO_LIB_DIR}")
message(STATUS "  WRF-Hydro mods:      ${WRFHYDRO_MOD_DIR} (86 .mod files)")
message(STATUS "  NetCDF-Fortran:      ${NETCDFF_LIBRARY}")
message(STATUS "  NetCDF-C:            ${NETCDF_LIBRARY}")
message(STATUS "  MPI:                 ${MPI_Fortran_COMPILER}")
message(STATUS "  ---")
message(STATUS "  Output library:      libwrfhydro_bmi.so")
message(STATUS "  Test executable:     bmi_wrf_hydro_test")
message(STATUS "  Test working dir:    ${CMAKE_SOURCE_DIR}/../WRF_Hydro_Run_Local/run")
message(STATUS "=============================================================")
message(STATUS "")
