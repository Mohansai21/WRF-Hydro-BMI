#!/bin/bash
# ============================================================================
# build.sh - Build script for WRF-Hydro BMI wrapper
# ============================================================================
# Compiles the BMI wrapper module and test executables, then links them
# against WRF-Hydro libraries.
#
# Directory layout:
#   src/    -> BMI wrapper source (bmi_wrf_hydro.f90)
#   tests/  -> Test programs (bmi_minimal_test.f90, bmi_wrf_hydro_test.f90)
#   build/  -> All compiled artifacts (.o, .mod, executables, .so)
#
# Usage:
#   ./build.sh              Build all (BMI module + minimal test + full test)
#   ./build.sh minimal      Build only BMI module + minimal test
#   ./build.sh full         Build only BMI module + full test
#   ./build.sh clean        Remove all build artifacts
#   ./build.sh --fpic       Build all using fPIC WRF-Hydro libraries
#   ./build.sh --fpic full  Build full test using fPIC libraries
#   ./build.sh --fpic clean Remove all build artifacts
#   ./build.sh --shared             Build .so + all tests linked against .so + run tests
#   ./build.sh --shared full        Build .so + full test linked against .so + run full test
#   ./build.sh --shared minimal     Build .so + minimal test linked against .so + run minimal test
#   ./build.sh --shared clean       Remove all build artifacts including .so
#
# Notes:
#   --shared auto-implies --fpic (uses build_fpic/ libraries).
#   --shared builds libbmiwrfhydrof.so, links tests against it, and auto-runs tests.
#
# After build, run from bmi_wrf_hydro/ directory:
#   mpirun --oversubscribe -np 1 ./build/bmi_minimal_test
#   mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test
# ============================================================================

set -e  # Exit on any error

# --- Parse flags (before BUILD_TARGET) ---
USE_FPIC="false"
USE_SHARED="false"
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --fpic) USE_FPIC="true" ;;
    --shared) USE_SHARED="true" ;;
    *) ARGS+=("$arg") ;;
  esac
done
BUILD_TARGET="${ARGS[0]:-all}"  # default: build all

# --shared auto-implies --fpic (shared library needs PIC objects)
if [ "$USE_SHARED" = "true" ]; then
  USE_FPIC="true"
fi

# --- Conda Environment ---
source ~/miniconda3/etc/profile.d/conda.sh
conda activate wrfhydro-bmi

# --- Directory Layout ---
BMI_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="${BMI_DIR}/src"
TEST_DIR="${BMI_DIR}/tests"
BUILD_DIR="${BMI_DIR}/build"

# --- External Paths ---
CONDA_P=/home/mohansai/miniconda3/envs/wrfhydro-bmi

if [ "$USE_FPIC" = "true" ]; then
  WRF_BUILD="${BMI_DIR}/../wrf_hydro_nwm_public/build_fpic"
  echo "*** Using fPIC libraries from build_fpic/ ***"
else
  WRF_BUILD="${BMI_DIR}/../wrf_hydro_nwm_public/build"
fi

# Verify build directory exists when --fpic is used
if [ "$USE_FPIC" = "true" ] && [ ! -d "$WRF_BUILD" ]; then
  echo "ERROR: ${WRF_BUILD} not found. Run rebuild_fpic.sh first."
  exit 1
fi

WRF_MODS="${WRF_BUILD}/mods"
WRF_LIB="${WRF_BUILD}/lib"
WRF_OBJ="${WRF_BUILD}/src/CMakeFiles/wrfhydro.dir/Land_models/NoahMP/IO_code"

# --- Compiler Flags ---
FC="gfortran"
FFLAGS="-c -cpp -DWRF_HYDRO -DMPP_LAND"
INCLUDES="-I${CONDA_P}/include -I${WRF_MODS} -I${BUILD_DIR}"
MOD_OUT="-J${BUILD_DIR}"

# --- Handle clean target ---
if [ "$BUILD_TARGET" = "clean" ]; then
  echo "=== Cleaning build artifacts ==="
  rm -f "${BUILD_DIR}"/*.o "${BUILD_DIR}"/*.mod \
        "${BUILD_DIR}"/bmi_minimal_test "${BUILD_DIR}"/bmi_wrf_hydro_test \
        "${BUILD_DIR}"/libbmiwrfhydrof.so
  echo "    -> build/ cleaned"
  exit 0
fi

# --- WRF-Hydro library list ---
# NOTE: We do NOT include main_hrldas_driver.F.o because it has program main()
#       which would conflict with our test driver's main program.

# Library names (used for both -l flags and full-path expansion)
WRF_LIB_NAMES="\
  hydro_driver \
  hydro_noahmp_cpl \
  hydro_orchestrator \
  noahmp_data \
  noahmp_phys \
  noahmp_util \
  hydro_routing \
  hydro_routing_overland \
  hydro_routing_subsurface \
  hydro_routing_reservoirs \
  hydro_routing_reservoirs_hybrid \
  hydro_routing_reservoirs_levelpool \
  hydro_routing_reservoirs_rfc \
  hydro_routing_diversions \
  hydro_data_rec \
  hydro_mpp \
  hydro_netcdf_layer \
  hydro_debug_utils \
  hydro_utils \
  fortglob \
  crocus_surfex \
  snowcro"

# Build -l flags string (repeated 3x for circular dependencies)
# NOTE: Libraries are repeated 3x instead of using --start-group/--end-group
# because mpif90 wrapper doesn't pass those linker flags correctly.
WRF_LIBS_SINGLE=""
for libname in ${WRF_LIB_NAMES}; do
  WRF_LIBS_SINGLE="${WRF_LIBS_SINGLE} -l${libname}"
done

# ========== Step 1: Compile the BMI wrapper module ==========
echo "=== Step 1: Compile src/bmi_wrf_hydro.f90 (BMI wrapper module) ==="
EXTRA_FFLAGS=""
if [ "$USE_SHARED" = "true" ]; then
  EXTRA_FFLAGS="-fPIC"
  echo "    (with -fPIC for shared library)"
fi
${FC} ${FFLAGS} ${EXTRA_FFLAGS} ${INCLUDES} ${MOD_OUT} "${SRC_DIR}/bmi_wrf_hydro.f90" -o "${BUILD_DIR}/bmi_wrf_hydro.o"
echo "    -> build/bmi_wrf_hydro.o created"

# ========== Step 2 (shared mode): Build libbmiwrfhydrof.so ==========
if [ "$USE_SHARED" = "true" ]; then
  echo ""
  echo "=== Step 2a: Recompile extra .o files with -fPIC ==="
  # The two extra .o files (module_NoahMP_hrldas_driver.F.o, module_hrldas_netcdf_io.F.o)
  # are from WRF-Hydro's executable target which uses -fPIE (not -fPIC).
  # -fPIE is insufficient for shared libraries. We recompile with -fPIC into build/.
  WRF_SRC="${BMI_DIR}/../wrf_hydro_nwm_public/src"
  WRF_IO_SRC="${WRF_SRC}/Land_models/NoahMP/IO_code"
  WRF_FFLAGS="-c -cpp -DWRF_HYDRO -DMPP_LAND -fPIC -w -ffree-form -ffree-line-length-none -fconvert=big-endian -frecord-marker=4 -fallow-argument-mismatch -O2"
  WRF_INCLUDES="-I${WRF_MODS} -I${WRF_SRC}/Data_Rec -I${CONDA_P}/include"
  WRF_MOD_OUT="-J${BUILD_DIR}"

  ${FC} ${WRF_FFLAGS} ${WRF_INCLUDES} ${WRF_MOD_OUT} \
    "${WRF_IO_SRC}/module_hrldas_netcdf_io.F" \
    -o "${BUILD_DIR}/module_hrldas_netcdf_io.F.o"
  echo "    -> build/module_hrldas_netcdf_io.F.o recompiled with -fPIC"

  ${FC} ${WRF_FFLAGS} ${WRF_INCLUDES} ${WRF_MOD_OUT} \
    "${WRF_IO_SRC}/module_NoahMP_hrldas_driver.F" \
    -o "${BUILD_DIR}/module_NoahMP_hrldas_driver.F.o"
  echo "    -> build/module_NoahMP_hrldas_driver.F.o recompiled with -fPIC"

  echo ""
  echo "=== Step 2b: Link shared library libbmiwrfhydrof.so ==="

  # Build full paths for --whole-archive (needs absolute paths, not -l flags)
  WRF_STATIC_LIBS_FULL=""
  for libname in ${WRF_LIB_NAMES}; do
    WRF_STATIC_LIBS_FULL="${WRF_STATIC_LIBS_FULL} ${WRF_LIB}/lib${libname}.a"
  done

  # Extract MPI linker flags from mpif90 (don't use mpif90 as driver for -shared)
  MPI_LINK_FLAGS="$(mpif90 --showme:link)"

  # Use gfortran -shared (NOT mpif90 -shared) to create the .so
  # --whole-archive forces ALL symbols from static libs into the .so
  # (downstream users may need any symbol; shared libs must be self-contained)
  # NOTE: Uses our -fPIC recompiled .o files from build/, NOT the originals
  gfortran -shared -o "${BUILD_DIR}/libbmiwrfhydrof.so" \
    "${BUILD_DIR}/bmi_wrf_hydro.o" \
    "${BUILD_DIR}/module_NoahMP_hrldas_driver.F.o" \
    "${BUILD_DIR}/module_hrldas_netcdf_io.F.o" \
    -Wl,--whole-archive ${WRF_STATIC_LIBS_FULL} -Wl,--no-whole-archive \
    -L"${CONDA_P}/lib" -lbmif \
    -lnetcdff \
    -lnetcdf \
    ${MPI_LINK_FLAGS}

  echo "    -> build/libbmiwrfhydrof.so created"
  ls -lh "${BUILD_DIR}/libbmiwrfhydrof.so"
fi

# ========== Helper function to link an executable (static mode) ==========
# Args: $1=output_name $2=object_file
link_executable() {
  local OUT_NAME="$1"
  local OBJ_FILE="$2"
  echo "    Linking ${OUT_NAME} (static)..."
  mpif90 -o "${BUILD_DIR}/${OUT_NAME}" \
    "${BUILD_DIR}/bmi_wrf_hydro.o" \
    "${OBJ_FILE}" \
    "${WRF_OBJ}/module_NoahMP_hrldas_driver.F.o" \
    "${WRF_OBJ}/module_hrldas_netcdf_io.F.o" \
    -L"${CONDA_P}/lib" -lbmif \
    -L"${WRF_LIB}" \
    ${WRF_LIBS_SINGLE} \
    ${WRF_LIBS_SINGLE} \
    ${WRF_LIBS_SINGLE} \
    -lnetcdff \
    -lnetcdf
  echo "    -> build/${OUT_NAME} created"
}

# ========== Helper function to link an executable (shared mode) ==========
# Args: $1=output_name $2=object_file
# Links against libbmiwrfhydrof.so instead of static objects.
link_executable_shared() {
  local OUT_NAME="$1"
  local OBJ_FILE="$2"
  echo "    Linking ${OUT_NAME} (against libbmiwrfhydrof.so)..."
  mpif90 -o "${BUILD_DIR}/${OUT_NAME}" \
    "${OBJ_FILE}" \
    -L"${BUILD_DIR}" -lbmiwrfhydrof \
    -Wl,-rpath,"${BUILD_DIR}" \
    -L"${CONDA_P}/lib" -lbmif
  echo "    -> build/${OUT_NAME} created"
}

# ========== Step 3: Build minimal test ==========
if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "minimal" ]; then
  echo ""
  echo "=== Step 3a: Compile tests/bmi_minimal_test.f90 ==="
  ${FC} ${FFLAGS} ${EXTRA_FFLAGS} ${INCLUDES} ${MOD_OUT} "${TEST_DIR}/bmi_minimal_test.f90" -o "${BUILD_DIR}/bmi_minimal_test.o"
  echo "    -> build/bmi_minimal_test.o created"

  echo "=== Step 3b: Link bmi_minimal_test ==="
  if [ "$USE_SHARED" = "true" ]; then
    link_executable_shared "bmi_minimal_test" "${BUILD_DIR}/bmi_minimal_test.o"
  else
    link_executable "bmi_minimal_test" "${BUILD_DIR}/bmi_minimal_test.o"
  fi
fi

# ========== Step 4: Build full test ==========
if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "full" ]; then
  echo ""
  echo "=== Step 4a: Compile tests/bmi_wrf_hydro_test.f90 ==="
  ${FC} ${FFLAGS} ${EXTRA_FFLAGS} ${INCLUDES} ${MOD_OUT} "${TEST_DIR}/bmi_wrf_hydro_test.f90" -o "${BUILD_DIR}/bmi_wrf_hydro_test.o"
  echo "    -> build/bmi_wrf_hydro_test.o created"

  echo "=== Step 4b: Link bmi_wrf_hydro_test ==="
  if [ "$USE_SHARED" = "true" ]; then
    link_executable_shared "bmi_wrf_hydro_test" "${BUILD_DIR}/bmi_wrf_hydro_test.o"
  else
    link_executable "bmi_wrf_hydro_test" "${BUILD_DIR}/bmi_wrf_hydro_test.o"
  fi
fi

echo ""
echo "=== BUILD SUCCESSFUL ==="

# ========== Auto-run tests in shared mode ==========
if [ "$USE_SHARED" = "true" ]; then
  echo ""
  echo "=== AUTO-RUNNING TESTS (shared library mode) ==="
  # Tests must run from bmi_wrf_hydro/ directory because the test program writes
  # bmi_config.nml with wrfhydro_run_dir = "../WRF_Hydro_Run_Local/run/" (relative
  # to the bmi_wrf_hydro/ directory where the test is designed to be invoked from).
  TESTS_PASSED=0
  TESTS_FAILED=0

  if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "minimal" ]; then
    echo ""
    echo "--- Running bmi_minimal_test ---"
    if (cd "${BMI_DIR}" && mpirun --oversubscribe -np 1 "${BUILD_DIR}/bmi_minimal_test"); then
      echo ">>> bmi_minimal_test: PASSED"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo ">>> bmi_minimal_test: FAILED"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  fi

  if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "full" ]; then
    echo ""
    echo "--- Running bmi_wrf_hydro_test (151-test suite) ---"
    if (cd "${BMI_DIR}" && mpirun --oversubscribe -np 1 "${BUILD_DIR}/bmi_wrf_hydro_test"); then
      echo ">>> bmi_wrf_hydro_test: PASSED"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      echo ">>> bmi_wrf_hydro_test: FAILED"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  fi

  echo ""
  echo "=== TEST SUMMARY ==="
  echo "    Passed: ${TESTS_PASSED}"
  echo "    Failed: ${TESTS_FAILED}"

  if [ "$TESTS_FAILED" -gt 0 ]; then
    echo "*** SOME TESTS FAILED ***"
    exit 1
  else
    echo "*** ALL TESTS PASSED ***"
  fi
else
  echo "Run from bmi_wrf_hydro/ directory:"
  if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "minimal" ]; then
    echo "  mpirun --oversubscribe -np 1 ./build/bmi_minimal_test"
  fi
  if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "full" ]; then
    echo "  mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test"
  fi
fi
