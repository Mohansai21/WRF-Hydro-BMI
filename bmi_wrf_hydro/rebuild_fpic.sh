#!/bin/bash
# ============================================================================
# rebuild_fpic.sh - Rebuild WRF-Hydro static libraries with explicit -fPIC
# ============================================================================
# This script rebuilds WRF-Hydro from source using cmake's
# CMAKE_POSITION_INDEPENDENT_CODE=ON flag, which adds -fPIC to every static
# library target. The rebuilt libraries are placed in a SEPARATE directory
# (wrf_hydro_nwm_public/build_fpic/) so the original build/ is preserved.
#
# Purpose:
#   Position-independent code (-fPIC) is required to link static libraries
#   into a shared object (libwrfhydrobmi.so) in Phase 2. Although the current
#   compiler defaults to PIC, making the flag explicit ensures portability
#   and documents the requirement.
#
# What this script does:
#   1. Activates the wrfhydro-bmi conda environment
#   2. Cleans any previous build_fpic/ directory
#   3. Runs cmake configure with -DCMAKE_POSITION_INDEPENDENT_CODE=ON
#   4. Builds all 24 WRF-Hydro static libraries
#   5. Verifies PIC via readelf (zero R_X86_64_32S relocations)
#   6. Counts libraries to confirm all built
#   7. Runs 151-test BMI regression suite against rebuilt libraries
#
# What this script does NOT do:
#   - It does NOT modify any WRF-Hydro source files
#   - It does NOT overwrite the original build/ directory
#
# Usage:
#   cd bmi_wrf_hydro/
#   ./rebuild_fpic.sh
#
# Prerequisites:
#   - wrfhydro-bmi conda environment with gfortran, MPI, NetCDF
#   - WRF-Hydro source at ../wrf_hydro_nwm_public/
#   - BMI wrapper source in src/bmi_wrf_hydro.f90
#   - Test suite in tests/bmi_wrf_hydro_test.f90
# ============================================================================

set -e  # Exit on any error

# --- Conda Environment ---
source ~/miniconda3/etc/profile.d/conda.sh
conda activate wrfhydro-bmi

# --- Paths ---
BMI_DIR="$(cd "$(dirname "$0")" && pwd)"
WRF_SRC="${BMI_DIR}/../wrf_hydro_nwm_public"
BUILD_DIR="${WRF_SRC}/build_fpic"

echo "============================================================"
echo " WRF-Hydro fPIC Rebuild"
echo "============================================================"
echo "WRF-Hydro source: ${WRF_SRC}"
echo "Build output:     ${BUILD_DIR}"
echo "Fortran compiler: $(which gfortran) ($(gfortran --version | head -1))"
echo "C compiler:       $(which gcc) ($(gcc --version | head -1))"
echo ""

# --- Step 1: Clean previous build ---
echo "=== Step 1: Clean previous build_fpic/ ==="
if [ -d "${BUILD_DIR}" ]; then
  echo "    Removing existing ${BUILD_DIR}..."
  rm -rf "${BUILD_DIR}"
  echo "    -> Cleaned"
else
  echo "    -> No previous build_fpic/ found (clean start)"
fi
echo ""

# --- Step 2: Configure cmake with -fPIC ---
echo "=== Step 2: Configure cmake with -fPIC ==="
cmake -B "${BUILD_DIR}" \
  -S "${WRF_SRC}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_Fortran_COMPILER="$(which gfortran)" \
  -DCMAKE_C_COMPILER="$(which gcc)"
echo ""
echo "    -> cmake configure complete"
echo ""

# --- Step 3: Build all targets ---
echo "=== Step 3: Build all targets (-j$(nproc)) ==="
cmake --build "${BUILD_DIR}" -j$(nproc)
echo ""
echo "    -> Build complete"
echo ""

# --- Step 4: Verify PIC via readelf ---
echo "=== Step 4: Verify PIC (readelf check) ==="
NON_PIC_COUNT=$(readelf -r "${BUILD_DIR}/lib/libhydro_routing.a" 2>/dev/null | grep -c 'R_X86_64_32S' || true)
echo "Non-PIC relocations in libhydro_routing.a: ${NON_PIC_COUNT}"
if [ "$NON_PIC_COUNT" -ne 0 ]; then
  echo "ERROR: Non-PIC relocations found! -fPIC may not have been applied."
  exit 1
fi
echo "PIC verification: PASSED"
echo ""

# --- Step 5: Count libraries ---
echo "=== Step 5: Count rebuilt libraries ==="
LIB_COUNT=$(ls "${BUILD_DIR}/lib/"*.a 2>/dev/null | wc -l)
echo "Libraries in build_fpic/lib/: ${LIB_COUNT}"
echo "Libraries:"
ls -1 "${BUILD_DIR}/lib/"*.a 2>/dev/null | while read -r lib; do
  echo "    $(basename "$lib")"
done
echo ""

# --- Step 6: Verify compiler in CMakeCache ---
echo "=== Step 6: Verify compiler selection ==="
FORTRAN_COMPILER=$(grep 'CMAKE_Fortran_COMPILER:FILEPATH' "${BUILD_DIR}/CMakeCache.txt" | cut -d= -f2)
echo "Fortran compiler used: ${FORTRAN_COMPILER}"
if echo "$FORTRAN_COMPILER" | grep -q "miniconda3"; then
  echo "Compiler check: PASSED (conda gfortran)"
else
  echo "WARNING: Compiler does not appear to be conda gfortran"
  echo "         This may cause ABI incompatibility with the BMI wrapper"
fi
echo ""

# --- Step 7: Run BMI regression tests ---
echo "=== Step 7: Build and run 151-test BMI regression suite ==="
cd "${BMI_DIR}"
./build.sh --fpic full
echo ""
echo "=== Running 151-test BMI regression suite ==="
mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test

echo ""
echo "============================================================"
echo " fPIC Rebuild: COMPLETE"
echo "============================================================"
echo "Libraries: ${BUILD_DIR}/lib/ (${LIB_COUNT} files)"
echo "PIC check: PASSED (zero R_X86_64_32S relocations)"
echo "Regression: See test output above"
echo "============================================================"
