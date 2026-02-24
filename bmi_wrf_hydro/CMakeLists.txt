# ============================================================================
# CMakeLists.txt -- WRF-Hydro BMI Wrapper Build Configuration
# ============================================================================
#
# PURPOSE:
#   This file tells CMake how to compile two things:
#     1. libbmiwrfhydrof.so  -- The BMI wrapper shared library
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
#   2. WRF-Hydro must be compiled with -fPIC at ../wrf_hydro_nwm_public/build_fpic/
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
# HOW TO INSTALL (puts library into conda env for babelizer discovery):
#   cmake --install _build
#
# NAMING CONVENTION:
#   Library name: bmiwrfhydrof (following bmi-example-fortran: bmi{model}f)
#   This produces: libbmiwrfhydrof.so
#   pkg-config:    bmiwrfhydrof.pc
#   The babelizer uses: pkg-config --libs bmiwrfhydrof
# ============================================================================


# ============================================================================
# SECTION 1: Project Setup
# ============================================================================
# cmake_minimum_required: Sets the oldest CMake version that can process this
# file. Version 3.12 is needed for pkg_check_modules IMPORTED_TARGET support.
cmake_minimum_required(VERSION 3.12)

# project(): Declares the project name, version, and language.
#   - VERSION 1.0.0 sets PROJECT_VERSION and related variables
#   - LANGUAGES Fortran tells CMake we only need a Fortran compiler
#
# NOTE: Project name "bmi-wrf-hydro" follows bmi-example-fortran convention
# (project is "bmi-example-fortran", library is "bmiheatf").
project(bmi-wrf-hydro
  VERSION 1.0.0
  LANGUAGES Fortran
)

# include(GNUInstallDirs): Provides standard installation directory variables
# like CMAKE_INSTALL_LIBDIR (usually "lib"), CMAKE_INSTALL_INCLUDEDIR
# (usually "include"), etc. This ensures our install paths follow conventions.
include(GNUInstallDirs)

# bmi_name: The library target name. Following the bmi-example-fortran pattern
# where set(bmi_name bmiheatf), we use bmiwrfhydrof.
# This produces: libbmiwrfhydrof.so, bmiwrfhydrof.pc, bmiwrfhydrof.mod
set(bmi_name bmiwrfhydrof)

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
include_directories(${BMIF_INCLUDE_DIRS})

# CMAKE_Fortran_MODULE_DIRECTORY: When gfortran compiles a Fortran module,
# it produces a .mod file. This setting puts ALL .mod files into _build/mod/
# so they are easy to find.
set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod)


# ============================================================================
# SECTION 3: Find MPI (Message Passing Interface)
# ============================================================================
# WRF-Hydro is an MPI-parallel application. Even though our BMI wrapper
# starts in serial mode, the WRF-Hydro libraries were compiled with MPI,
# so we must link against MPI to resolve symbols like MPI_Init, MPI_Comm_rank.
# ============================================================================
find_package(MPI REQUIRED COMPONENTS Fortran)
message(STATUS "MPI Fortran compiler: ${MPI_Fortran_COMPILER}")
message(STATUS "MPI Fortran include: ${MPI_Fortran_INCLUDE_DIRS}")


# ============================================================================
# SECTION 4: Find WRF-Hydro fPIC Libraries
# ============================================================================
# WRF-Hydro was compiled with -fPIC into static libraries (.a files)
# at ../wrf_hydro_nwm_public/build_fpic/lib/. We need ALL 22 of them
# because our BMI wrapper calls WRF-Hydro subroutines (HYDRO_ini, HYDRO_exe,
# land_driver_ini, land_driver_exe, etc.) which depend on the full model.
#
# We also need two specific .o object files that contain the main driver
# subroutines that our BMI wrapper calls directly.
#
# The fPIC libraries are produced by rebuild_fpic.sh (Phase 1).
# ============================================================================

# WRF_HYDRO_BUILD_DIR: Path to the WRF-Hydro fPIC build directory.
# Default: ../wrf_hydro_nwm_public/build_fpic (the fPIC-compiled libraries)
set(WRF_HYDRO_BUILD_DIR
  "${CMAKE_CURRENT_SOURCE_DIR}/../wrf_hydro_nwm_public/build_fpic"
  CACHE PATH "Path to WRF-Hydro fPIC build directory")

# Verify the directory exists (fail early with a clear message)
if(NOT EXISTS "${WRF_HYDRO_BUILD_DIR}")
  message(FATAL_ERROR
    "WRF-Hydro fPIC build directory not found at: ${WRF_HYDRO_BUILD_DIR}\n"
    "Please run rebuild_fpic.sh first to compile WRF-Hydro with -fPIC:\n"
    "  cd bmi_wrf_hydro && ./rebuild_fpic.sh\n"
    "Or set -DWRF_HYDRO_BUILD_DIR=/path/to/build_fpic when running cmake.")
endif()

# Define key directories within the fPIC build
set(WRF_LIB_DIR "${WRF_HYDRO_BUILD_DIR}/lib")
set(WRF_MOD_DIR "${WRF_HYDRO_BUILD_DIR}/mods")

# WRF-Hydro source directory (for recompiling driver .o files with -fPIC)
# The land_driver_ini/exe subroutines live in module_NoahMP_hrldas_driver.F
# which is compiled as part of the wrfhydro executable target (not a library).
# CMake's POSITION_INDEPENDENT_CODE only applies to library targets, so the
# executable .o files were compiled with -fPIE (not -fPIC). We must recompile
# them from source with -fPIC to include in our shared library.
set(WRF_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../wrf_hydro_nwm_public/src")
set(WRF_IO_SRC_DIR "${WRF_SRC_DIR}/Land_models/NoahMP/IO_code")

# Verify subdirectories exist
if(NOT EXISTS "${WRF_LIB_DIR}")
  message(FATAL_ERROR "WRF-Hydro lib directory not found at: ${WRF_LIB_DIR}")
endif()
if(NOT EXISTS "${WRF_MOD_DIR}")
  message(FATAL_ERROR "WRF-Hydro module directory not found at: ${WRF_MOD_DIR}")
endif()

# Make WRF-Hydro .mod files visible for 'use' statements
include_directories(${WRF_MOD_DIR})

message(STATUS "WRF-Hydro fPIC build: ${WRF_HYDRO_BUILD_DIR}")
message(STATUS "WRF-Hydro lib dir: ${WRF_LIB_DIR}")
message(STATUS "WRF-Hydro mod dir: ${WRF_MOD_DIR}")

# Collect all WRF-Hydro static libraries
file(GLOB WRF_STATIC_LIBS "${WRF_LIB_DIR}/*.a")
list(LENGTH WRF_STATIC_LIBS wrf_lib_count)
message(STATUS "Found ${wrf_lib_count} WRF-Hydro static libraries")

# Verify we found the expected count
if(wrf_lib_count LESS 20)
  message(WARNING "Expected ~22 WRF-Hydro libraries but found ${wrf_lib_count}. "
    "Build may fail with unresolved symbols.")
endif()


# ============================================================================
# SECTION 5: Preprocessor Definitions
# ============================================================================
# These CPP flags match what WRF-Hydro uses during its own build:
#   -DWRF_HYDRO   : Enables WRF-Hydro code blocks (#ifdef WRF_HYDRO)
#   -DMPP_LAND    : Enables MPI land domain decomposition code
# ============================================================================
add_definitions(-DWRF_HYDRO -DMPP_LAND)


# ============================================================================
# SECTION 6: Compiler Flags (per-compiler)
# ============================================================================
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
  message(STATUS "Fortran compiler: gfortran ${CMAKE_Fortran_COMPILER_VERSION}")

  set(BMI_FORTRAN_FLAGS
    -ffree-form
    -ffree-line-length-none
    -fPIC
    -cpp
    -fconvert=big-endian
    -frecord-marker=4
  )

  if(CMAKE_Fortran_COMPILER_VERSION VERSION_GREATER_EQUAL 10)
    list(APPEND BMI_FORTRAN_FLAGS -fallow-argument-mismatch)
  endif()

  set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
  set(CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g -fbacktrace -fcheck=all -Wall")

elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
  message(STATUS "Fortran compiler: ifort/ifx ${CMAKE_Fortran_COMPILER_VERSION}")
  set(BMI_FORTRAN_FLAGS -fpp -fPIC -FR -ftz -align all -fno-alias -fp-model precise)
  set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
  set(CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g -traceback -check all")

else()
  message(WARNING "Unknown Fortran compiler: ${CMAKE_Fortran_COMPILER_ID}. "
    "Using generic flags.")
  set(BMI_FORTRAN_FLAGS -cpp -fPIC)
endif()


# ============================================================================
# SECTION 7: BMI Wrapper Shared Library (libbmiwrfhydrof.so)
# ============================================================================
# This is the main output: a shared library implementing the BMI interface
# for WRF-Hydro. The babelizer (Phase 2) uses pkg-config to find this library.
#
# Naming follows bmi-example-fortran: bmi{model}f -> bmiwrfhydrof
# ============================================================================

# Create shared library from our BMI wrapper source AND the two WRF-Hydro
# driver source files that contain land_driver_ini/exe subroutines.
#
# These two files (module_NoahMP_hrldas_driver.F and module_hrldas_netcdf_io.F)
# are part of WRF-Hydro's executable target, not a library target. CMake's
# POSITION_INDEPENDENT_CODE=ON only applies to library targets, so the .o files
# in build_fpic/src/ were compiled with -fPIE (not -fPIC). We recompile from
# source with -fPIC by including them in our SHARED library target.
#
# We also include src/hydro_stop_shim.f90 which provides a bare external
# `hydro_stop` subroutine. WRF-Hydro has one call site (nwmCheck in
# module_reservoir_routing.F90) that calls hydro_stop without `use module_hydro_stop`,
# generating a reference to the bare symbol `hydro_stop_`. This is dead code in
# normal WRF-Hydro builds, but --whole-archive pulls it into our .so. The shim
# delegates to the module version to resolve the linker error.
add_library(${bmi_name} SHARED
  src/bmi_wrf_hydro.f90
  src/hydro_stop_shim.f90
  ${WRF_IO_SRC_DIR}/module_NoahMP_hrldas_driver.F
  ${WRF_IO_SRC_DIR}/module_hrldas_netcdf_io.F
)

# Compiler flags for all sources in this target (including the WRF-Hydro files)
target_compile_options(${bmi_name} PRIVATE
  ${BMI_FORTRAN_FLAGS}
  -w    # Suppress warnings from WRF-Hydro source files (not our code)
)

# Include directories for module file resolution
target_include_directories(${bmi_name} PRIVATE
  ${BMIF_INCLUDE_DIRS}
  ${WRF_MOD_DIR}
  ${CMAKE_Fortran_MODULE_DIRECTORY}
  ${MPI_Fortran_INCLUDE_DIRS}
)

# Link dependencies:
#   1. All 22 WRF-Hydro static libs wrapped in --whole-archive to pull ALL symbols
#   2. BMI Fortran library (libbmif.so)
#   3. MPI Fortran libraries
#   4. NetCDF libraries
target_link_libraries(${bmi_name}
  -Wl,--whole-archive
  ${WRF_STATIC_LIBS}
  -Wl,--no-whole-archive
  ${BMIF_LINK_LIBRARIES}
  MPI::MPI_Fortran
  -lnetcdff
  -lnetcdf
)

# Library properties
set_target_properties(${bmi_name} PROPERTIES
  VERSION ${PROJECT_VERSION}
  SOVERSION 1
  Fortran_MODULE_DIRECTORY ${CMAKE_Fortran_MODULE_DIRECTORY}
)


# ============================================================================
# SECTION 8: Test Executable (bmi_wrf_hydro_test)
# ============================================================================
# The test driver calls all 41 BMI functions and checks return values.
# It links against our libbmiwrfhydrof.so library.
# ============================================================================

add_executable(bmi_wrf_hydro_test tests/bmi_wrf_hydro_test.f90)

target_compile_options(bmi_wrf_hydro_test PRIVATE ${BMI_FORTRAN_FLAGS})

target_include_directories(bmi_wrf_hydro_test PRIVATE
  ${BMIF_INCLUDE_DIRS}
  ${CMAKE_Fortran_MODULE_DIRECTORY}
)

target_link_libraries(bmi_wrf_hydro_test
  ${bmi_name}
  ${BMIF_LINK_LIBRARIES}
)


# ============================================================================
# SECTION 9: CTest Registration
# ============================================================================
# After building, run: ctest --test-dir _build
# The test must run from the WRF-Hydro run directory (where namelists,
# forcing data, and domain files live).
# ============================================================================
enable_testing()

add_test(
  NAME bmi_wrf_hydro_all_tests
  COMMAND bmi_wrf_hydro_test
  WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/../WRF_Hydro_Run_Local/run"
)

set_tests_properties(bmi_wrf_hydro_all_tests PROPERTIES
  TIMEOUT 300
  ENVIRONMENT "LD_LIBRARY_PATH=${CMAKE_BINARY_DIR}:$ENV{CONDA_PREFIX}/lib:$ENV{LD_LIBRARY_PATH}"
)


# ============================================================================
# SECTION 10: Installation Rules
# ============================================================================
# "Installing" copies built artifacts to $CONDA_PREFIX so the babelizer
# can discover them via pkg-config.
#
# After installation:
#   $CONDA_PREFIX/lib/libbmiwrfhydrof.so           <- shared library
#   $CONDA_PREFIX/include/bmiwrfhydrof.mod          <- BMI wrapper module
#   $CONDA_PREFIX/include/wrfhydro_bmi_state_mod.mod <- BMI state module
#   $CONDA_PREFIX/lib/pkgconfig/bmiwrfhydrof.pc     <- pkg-config file
# ============================================================================

# Install the shared library
install(TARGETS ${bmi_name}
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install the BMI wrapper .mod file
install(
  FILES ${CMAKE_Fortran_MODULE_DIRECTORY}/${bmi_name}.mod
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Install the BMI state module .mod file
install(
  FILES ${CMAKE_Fortran_MODULE_DIRECTORY}/wrfhydro_bmi_state_mod.mod
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# Install the pkg-config file
install(
  FILES ${CMAKE_CURRENT_BINARY_DIR}/${bmi_name}.pc
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig
)


# ============================================================================
# SECTION 11: pkg-config File Generation
# ============================================================================
# The babelizer's Meson build uses pkg-config to find our library:
#   pkg-config --libs bmiwrfhydrof  -> -L.../lib -lbmiwrfhydrof
#   pkg-config --cflags bmiwrfhydrof -> -I.../include
#
# We generate the .pc file from a template, substituting CMake variables.
# ============================================================================
configure_file(
  ${CMAKE_CURRENT_SOURCE_DIR}/${bmi_name}.pc.cmake
  ${CMAKE_CURRENT_BINARY_DIR}/${bmi_name}.pc
  @ONLY
)


# ============================================================================
# SECTION 12: Build Summary
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
message(STATUS "  WRF-Hydro fPIC:      ${WRF_HYDRO_BUILD_DIR}")
message(STATUS "  WRF-Hydro libs:      ${wrf_lib_count} static libraries")
message(STATUS "  WRF-Hydro mods:      ${WRF_MOD_DIR}")
message(STATUS "  MPI:                 ${MPI_Fortran_COMPILER}")
message(STATUS "  ---")
message(STATUS "  Output library:      lib${bmi_name}.so")
message(STATUS "  pkg-config:          ${bmi_name}.pc")
message(STATUS "  Test executable:     bmi_wrf_hydro_test")
message(STATUS "=============================================================")
message(STATUS "")
