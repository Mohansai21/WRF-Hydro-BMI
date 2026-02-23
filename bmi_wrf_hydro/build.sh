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
#   build/  -> All compiled artifacts (.o, .mod, executables)
#
# Usage:
#   ./build.sh          Build all (BMI module + minimal test + full test)
#   ./build.sh minimal  Build only BMI module + minimal test
#   ./build.sh full     Build only BMI module + full test
#   ./build.sh clean    Remove all build artifacts
#
# After build, run from bmi_wrf_hydro/ directory:
#   mpirun --oversubscribe -np 1 ./build/bmi_minimal_test
#   mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test
# ============================================================================

set -e  # Exit on any error

BUILD_TARGET="${1:-all}"  # default: build all

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
WRF_BUILD="${BMI_DIR}/../wrf_hydro_nwm_public/build"
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
  rm -f "${BUILD_DIR}"/*.o "${BUILD_DIR}"/*.mod "${BUILD_DIR}"/bmi_minimal_test "${BUILD_DIR}"/bmi_wrf_hydro_test
  echo "    -> build/ cleaned"
  exit 0
fi

# --- WRF-Hydro library list (repeated 3x for circular dependencies) ---
# NOTE: Libraries are repeated 3x instead of using --start-group/--end-group
# because mpif90 wrapper doesn't pass those linker flags correctly.
# NOTE: We do NOT include main_hrldas_driver.F.o because it has program main()
#       which would conflict with our test driver's main program.
WRF_LIBS_SINGLE="\
  -lhydro_driver \
  -lhydro_noahmp_cpl \
  -lhydro_orchestrator \
  -lnoahmp_data \
  -lnoahmp_phys \
  -lnoahmp_util \
  -lhydro_routing \
  -lhydro_routing_overland \
  -lhydro_routing_subsurface \
  -lhydro_routing_reservoirs \
  -lhydro_routing_reservoirs_hybrid \
  -lhydro_routing_reservoirs_levelpool \
  -lhydro_routing_reservoirs_rfc \
  -lhydro_routing_diversions \
  -lhydro_data_rec \
  -lhydro_mpp \
  -lhydro_netcdf_layer \
  -lhydro_debug_utils \
  -lhydro_utils \
  -lfortglob \
  -lcrocus_surfex \
  -lsnowcro"

# ========== Step 1: Always compile the BMI wrapper module ==========
echo "=== Step 1: Compile src/bmi_wrf_hydro.f90 (BMI wrapper module) ==="
${FC} ${FFLAGS} ${INCLUDES} ${MOD_OUT} "${SRC_DIR}/bmi_wrf_hydro.f90" -o "${BUILD_DIR}/bmi_wrf_hydro.o"
echo "    -> build/bmi_wrf_hydro.o created"

# ========== Helper function to link an executable ==========
# Args: $1=output_name $2=object_file
link_executable() {
  local OUT_NAME="$1"
  local OBJ_FILE="$2"
  echo "    Linking ${OUT_NAME}..."
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

# ========== Step 2: Build minimal test ==========
if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "minimal" ]; then
  echo ""
  echo "=== Step 2a: Compile tests/bmi_minimal_test.f90 ==="
  ${FC} ${FFLAGS} ${INCLUDES} ${MOD_OUT} "${TEST_DIR}/bmi_minimal_test.f90" -o "${BUILD_DIR}/bmi_minimal_test.o"
  echo "    -> build/bmi_minimal_test.o created"

  echo "=== Step 2b: Link bmi_minimal_test ==="
  link_executable "bmi_minimal_test" "${BUILD_DIR}/bmi_minimal_test.o"
fi

# ========== Step 3: Build full test ==========
if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "full" ]; then
  echo ""
  echo "=== Step 3a: Compile tests/bmi_wrf_hydro_test.f90 ==="
  ${FC} ${FFLAGS} ${INCLUDES} ${MOD_OUT} "${TEST_DIR}/bmi_wrf_hydro_test.f90" -o "${BUILD_DIR}/bmi_wrf_hydro_test.o"
  echo "    -> build/bmi_wrf_hydro_test.o created"

  echo "=== Step 3b: Link bmi_wrf_hydro_test ==="
  link_executable "bmi_wrf_hydro_test" "${BUILD_DIR}/bmi_wrf_hydro_test.o"
fi

echo ""
echo "=== BUILD SUCCESSFUL ==="
echo "Run from bmi_wrf_hydro/ directory:"
if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "minimal" ]; then
  echo "  mpirun --oversubscribe -np 1 ./build/bmi_minimal_test"
fi
if [ "$BUILD_TARGET" = "all" ] || [ "$BUILD_TARGET" = "full" ]; then
  echo "  mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test"
fi
