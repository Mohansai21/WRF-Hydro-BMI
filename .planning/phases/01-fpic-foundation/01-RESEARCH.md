# Phase 1: fPIC Foundation - Research

**Researched:** 2026-02-23
**Domain:** CMake build configuration, position-independent code, Fortran static library compilation
**Confidence:** HIGH

## Summary

Phase 1 requires rebuilding WRF-Hydro's 22 static libraries with `-fPIC` so they can later be linked into a shared object (`libwrfhydrobmi.so`) in Phase 2. The research investigated the current WRF-Hydro build system (CMake-based, 22 `STATIC` library targets across ~30 sub-CMakeLists), the compiler's default PIC behavior, and the exact mechanism by which `CMAKE_POSITION_INDEPENDENT_CODE=ON` injects `-fPIC` into the build.

**Critical discovery:** The existing WRF-Hydro `.a` libraries already contain position-independent code. Both the system gfortran 13.3.0 (used for the original build) and the conda gfortran 14.3.0 are configured with `--enable-default-pie`, which injects `-fPIC` via compiler specs unless explicitly disabled with `-fno-PIC`. Zero `R_X86_64_32S` relocations were found across all 22 libraries. However, this is an implicit default -- it is correct and important to rebuild with explicit `-fPIC` via `CMAKE_POSITION_INDEPENDENT_CODE=ON` to make the requirement explicit and portable across compilers/environments.

**Primary recommendation:** Create `rebuild_fpic.sh` in `bmi_wrf_hydro/` that invokes cmake on the WRF-Hydro source with `-DCMAKE_POSITION_INDEPENDENT_CODE=ON` outputting to `wrf_hydro_nwm_public/build_fpic/`. Add `--fpic` flag to `build.sh` to link against the new library set. The rebuild is a straightforward cmake invocation with no source modifications.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Do NOT modify WRF-Hydro's CMakeLists.txt or any upstream files
- Create a wrapper script (`rebuild_fpic.sh`) in `bmi_wrf_hydro/` that invokes cmake with `-DCMAKE_POSITION_INDEPENDENT_CODE=ON`
- This preserves the "never modify WRF-Hydro source" rule -- the wrapper passes flags externally
- Rebuilt fPIC libraries go into a SEPARATE directory (`build_fpic/` under `wrf_hydro_nwm_public/`) -- do NOT overwrite the existing `build/`
- Both versions coexist: original `build/` for reference, `build_fpic/` for shared library work
- Script name: `rebuild_fpic.sh` (lives in `bmi_wrf_hydro/`)
- Full rebuild script: handles clean, cmake with -fPIC, build all 22 libs -- one command, done
- Script also auto-runs the 151-test regression suite after building (build + verify in one step)
- Add a `--fpic` flag to `build.sh` that links against `build_fpic/` libraries instead of `build/`
- Default behavior (no flag) still uses original `build/` libraries -- backward compatible

### Claude's Discretion
- Exact cmake invocation flags beyond -fPIC (optimization level, build type)
- readelf/objdump verification details
- Script error handling and output formatting
- Whether to use symlinks or absolute paths for library references

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BUILD-01 | WRF-Hydro 22 static libraries recompiled with `-fPIC` (`CMAKE_POSITION_INDEPENDENT_CODE=ON`) so they can be linked into a shared library | Full cmake mechanism verified: `-DCMAKE_POSITION_INDEPENDENT_CODE=ON` adds `-fPIC` to each STATIC library target, even when WRF-Hydro's CMakeLists.txt overrides `CMAKE_Fortran_FLAGS`. Tested on this exact compiler toolchain. All 22 sub-CMakeLists use `add_library(... STATIC ...)` which respects this property. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| cmake | 3.31.1 | Build system orchestrator | WRF-Hydro's native build system; `-DCMAKE_POSITION_INDEPENDENT_CODE=ON` is the standard cmake mechanism for adding `-fPIC` to all targets |
| gfortran (conda) | 14.3.0 | Fortran compiler | conda-forge `gcc_compilers_1770248565660`; should be used for fPIC rebuild to match BMI wrapper compiler (currently original build used system gfortran 13.3.0) |
| make | system | Build executor | cmake generates Unix Makefiles by default |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| readelf | system | Verify PIC relocations | Use `readelf -r` on `.o` files to confirm absence of `R_X86_64_32S` relocations (non-PIC indicator on x86_64) |
| mpif90 (conda) | OpenMPI 5.0.8 | MPI Fortran wrapper | Used internally by cmake via `find_package(MPI REQUIRED)` for compilation and linking |
| mpirun | OpenMPI 5.0.8 | Test executor | `mpirun --oversubscribe -np 1` to run BMI test suite against rebuilt libraries |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `CMAKE_POSITION_INDEPENDENT_CODE=ON` | Appending `-fPIC` to `CMAKE_Fortran_FLAGS` | `POSITION_INDEPENDENT_CODE` is the cmake-native mechanism; manual flag appending is fragile (WRF-Hydro's CMakeLists overrides `CMAKE_Fortran_FLAGS` with `set()`, which would erase appended flags) |
| Separate `build_fpic/` directory | Overwriting `build/` in place | User locked decision: keep both for reference |
| Rebuilding from scratch | Patching existing `.a` files | Not possible to retroactively add PIC to compiled objects; full recompile is required even though existing objects happen to already be PIC (compiler default) |

## Architecture Patterns

### WRF-Hydro CMake Build Structure
```
wrf_hydro_nwm_public/
  CMakeLists.txt           # Top-level: project def, MPI, NetCDF, compiler flags, subdirs
  src/
    CMakeLists.txt         # Sub-projects: 22 library targets + wrfhydro executable
    MPP/CMakeLists.txt     # add_library(hydro_mpp STATIC ...)
    HYDRO_drv/CMakeLists.txt  # add_library(hydro_driver STATIC ...)
    Routing/CMakeLists.txt    # add_library(hydro_routing STATIC ...) -- largest lib (3.8MB)
    ...                    # ~30 sub-CMakeLists total
  build/                   # Original build output (lib/, mods/, src/CMakeFiles/)
  build_fpic/              # [NEW] fPIC rebuild output (same structure)
```

### Pattern 1: cmake Wrapper Script (rebuild_fpic.sh)
**What:** A bash script that invokes cmake on WRF-Hydro sources with `-DCMAKE_POSITION_INDEPENDENT_CODE=ON`, builds all 22 libraries, and runs the 151-test suite for verification.
**When to use:** Whenever fPIC libraries need to be rebuilt from clean.
**Key cmake invocation:**
```bash
# Source: verified by running cmake with verbose build on this system
cmake -B "${WRF_SRC}/build_fpic" \
  -S "${WRF_SRC}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_Fortran_COMPILER="$(which gfortran)" \
  -DCMAKE_C_COMPILER="$(which gcc)"

cmake --build "${WRF_SRC}/build_fpic" -j$(nproc)
```

### Pattern 2: build.sh --fpic Flag
**What:** A flag for the existing `build.sh` that switches library paths from `build/` to `build_fpic/`.
**When to use:** When compiling and linking BMI wrapper + tests against fPIC libraries.
**Key changes to build.sh:**
```bash
# Current:
WRF_BUILD="${BMI_DIR}/../wrf_hydro_nwm_public/build"

# With --fpic:
if [ "$USE_FPIC" = "true" ]; then
  WRF_BUILD="${BMI_DIR}/../wrf_hydro_nwm_public/build_fpic"
fi
```
Three paths derived from WRF_BUILD must all switch: `WRF_MODS`, `WRF_LIB`, `WRF_OBJ`.

### Anti-Patterns to Avoid
- **Modifying WRF-Hydro's CMakeLists.txt files:** This violates the "never modify WRF-Hydro source" rule. The wrapper script passes flags externally via cmake command-line args.
- **Overwriting the original `build/` directory:** User decision requires both builds to coexist.
- **Relying on compiler-default PIC without explicit flag:** Although both gfortran 13.3.0 and 14.3.0 default to PIC on this system, this is environment-specific. Explicit `-DCMAKE_POSITION_INDEPENDENT_CODE=ON` makes the requirement portable and documented.
- **Skipping the conda environment activation:** The rebuild should use the conda gfortran (14.3.0) to match the BMI wrapper compiler, not the system `/usr/bin/f95` (13.3.0) that the original build used.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Adding -fPIC to STATIC targets | Manual flag injection into `CMAKE_Fortran_FLAGS` | `CMAKE_POSITION_INDEPENDENT_CODE=ON` | cmake's native mechanism; works through target property, survives WRF-Hydro's `set(CMAKE_Fortran_FLAGS ...)` override |
| PIC verification | Manual `objdump` parsing | `readelf -r \| grep R_X86_64_32S` | Standard method: `R_X86_64_32S` is the definitive non-PIC relocation type on x86_64; zero occurrences = confirmed PIC |
| Library enumeration | Hardcoded list of 22 names | `ls build_fpic/lib/*.a` | The build_fpic/ output mirrors build/, so glob is reliable |

**Key insight:** The entire fPIC rebuild is handled by a single cmake flag. There is no custom build logic needed -- cmake's `POSITION_INDEPENDENT_CODE` property propagates to every STATIC library target automatically.

## Common Pitfalls

### Pitfall 1: Wrong Fortran Compiler Selection
**What goes wrong:** cmake picks up `/usr/bin/f95` (system gfortran 13.3.0) instead of conda gfortran 14.3.0, causing potential ABI incompatibility with the BMI wrapper compiled by conda gfortran.
**Why it happens:** cmake's `find_package` searches system paths before conda paths. The original WRF-Hydro build used `/usr/bin/f95` as confirmed in `CMakeCache.txt`.
**How to avoid:** Explicitly pass `-DCMAKE_Fortran_COMPILER=$(which gfortran)` and `-DCMAKE_C_COMPILER=$(which gcc)` to cmake after activating the conda environment. This ensures the conda compilers are used.
**Warning signs:** `CMakeCache.txt` in `build_fpic/` shows `CMAKE_Fortran_COMPILER:FILEPATH=/usr/bin/f95` instead of the conda path.

### Pitfall 2: Stale CMake Cache
**What goes wrong:** A partial or failed build leaves a `CMakeCache.txt` in `build_fpic/` that locks in wrong settings. Subsequent cmake runs use cached values instead of new command-line arguments.
**Why it happens:** cmake caches compiler paths, build type, and flags on first configure. Re-running cmake with different flags doesn't always override cached values.
**How to avoid:** The rebuild script should remove `build_fpic/` entirely before running cmake (clean rebuild). Use `rm -rf build_fpic && cmake -B build_fpic ...`.
**Warning signs:** cmake output says "Using cached" or the build type doesn't match expectations.

### Pitfall 3: Missing MPI/NetCDF at Configure Time
**What goes wrong:** cmake fails at `find_package(MPI REQUIRED)` or `find_package(NetCDF REQUIRED)` because the conda environment isn't activated.
**Why it happens:** The rebuild script must be run inside the `wrfhydro-bmi` conda environment where MPI and NetCDF are installed.
**How to avoid:** The script should activate the conda environment at the top: `source ~/miniconda3/etc/profile.d/conda.sh && conda activate wrfhydro-bmi`.
**Warning signs:** cmake error "Could not find MPI" or "Could not find NetCDF".

### Pitfall 4: build.sh Object File Path Changes
**What goes wrong:** The `build.sh` link step references specific `.o` files at paths like `${WRF_OBJ}/module_NoahMP_hrldas_driver.F.o`. The path structure inside `build_fpic/` must match `build/`.
**Why it happens:** cmake generates object files under `build_fpic/src/CMakeFiles/wrfhydro.dir/Land_models/NoahMP/IO_code/` -- same relative structure as `build/`. But if cmake version or generator changes, the path could differ.
**How to avoid:** After rebuild, verify the `.o` file paths exist at the expected location under `build_fpic/`. The script should check for the required files.
**Warning signs:** Linker error "No such file or directory" when build.sh tries to link with `--fpic`.

### Pitfall 5: Executable Build Creates File Conflicts
**What goes wrong:** WRF-Hydro's CMakeLists.txt builds the `wrfhydro` executable and runs `POST_BUILD` commands that copy it to a `Run/` directory. If the original `build/Run/wrf_hydro` and the new `build_fpic/Run/wrf_hydro` both exist, there's no conflict -- but the `WRF_Hydro_Run_Local/run/` test directory may have symlinks to the original.
**Why it happens:** The cmake `POST_BUILD` command copies the built executable to `${CMAKE_BINARY_DIR}/Run/` which is `build_fpic/Run/`.
**How to avoid:** The fPIC rebuild creates its own self-contained output. The test suite (BMI 151 tests) should be run from `bmi_wrf_hydro/` using `build.sh --fpic` which links against `build_fpic/lib/`, not the executable.
**Warning signs:** None likely -- this is a non-issue as long as test execution uses build.sh, not the WRF-Hydro executable directly.

### Pitfall 6: WSL2 Clock Skew During Build
**What goes wrong:** cmake reports "file has modification time in the future" warnings during build on WSL2.
**Why it happens:** WSL2's NTFS filesystem layer has clock synchronization issues.
**How to avoid:** Ignore the warnings -- they're harmless. Documented in CLAUDE.md.
**Warning signs:** Warning messages during build, no actual build failures.

## Code Examples

### Example 1: rebuild_fpic.sh Core Logic
```bash
# Source: verified on this system (cmake 3.31.1, gfortran 14.3.0, WRF-Hydro v5.4.0)
#!/bin/bash
set -e

# Activate conda environment
source ~/miniconda3/etc/profile.d/conda.sh
conda activate wrfhydro-bmi

# Paths
BMI_DIR="$(cd "$(dirname "$0")" && pwd)"
WRF_SRC="${BMI_DIR}/../wrf_hydro_nwm_public"
BUILD_DIR="${WRF_SRC}/build_fpic"

# Clean previous build
rm -rf "${BUILD_DIR}"

# Configure with fPIC
cmake -B "${BUILD_DIR}" \
  -S "${WRF_SRC}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_Fortran_COMPILER="$(which gfortran)" \
  -DCMAKE_C_COMPILER="$(which gcc)"

# Build all targets
cmake --build "${BUILD_DIR}" -j$(nproc)
```

### Example 2: PIC Verification Command
```bash
# Source: readelf manual + verified on this system
# Check a sample library for non-PIC relocations
# R_X86_64_32S = absolute 32-bit signed relocation (NON-PIC indicator on x86_64)
# Zero matches = confirmed PIC
readelf -r build_fpic/lib/libhydro_routing.a 2>/dev/null | grep -c 'R_X86_64_32S'
# Expected output: 0
```

### Example 3: build.sh --fpic Flag Addition
```bash
# Source: pattern from existing build.sh
# Parse --fpic flag
USE_FPIC="false"
for arg in "$@"; do
  case "$arg" in
    --fpic) USE_FPIC="true" ;;
  esac
done

# Select library set
if [ "$USE_FPIC" = "true" ]; then
  WRF_BUILD="${BMI_DIR}/../wrf_hydro_nwm_public/build_fpic"
else
  WRF_BUILD="${BMI_DIR}/../wrf_hydro_nwm_public/build"
fi
WRF_MODS="${WRF_BUILD}/mods"
WRF_LIB="${WRF_BUILD}/lib"
WRF_OBJ="${WRF_BUILD}/src/CMakeFiles/wrfhydro.dir/Land_models/NoahMP/IO_code"
```

### Example 4: Regression Test Execution
```bash
# Source: existing test commands from CLAUDE.md
cd "${BMI_DIR}"
./build.sh --fpic full
mpirun --oversubscribe -np 1 ./build/bmi_wrf_hydro_test
# Expected: 151/151 tests pass
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual `-fPIC` in `CMAKE_Fortran_FLAGS` | `CMAKE_POSITION_INDEPENDENT_CODE=ON` target property | cmake 2.8.12+ (2013) | Works per-target, survives flag overrides, standard mechanism |
| System gfortran for all builds | conda-forge gfortran for reproducibility | conda-forge practice | Ensures ABI compatibility between model and wrapper |
| Compiler-default PIC (implicit) | Explicit `-fPIC` via cmake property | Best practice for shared library chains | Makes dependency explicit, portable across compilers |

**Deprecated/outdated:**
- Manual `-fPIC` flag appending to `CMAKE_C_FLAGS`/`CMAKE_Fortran_FLAGS`: Superseded by `POSITION_INDEPENDENT_CODE` property. The manual approach breaks when CMakeLists.txt overrides flags with `set()`.

## Key Findings from Code Investigation

### Finding 1: Existing Libraries Already Contain PIC (HIGH confidence)
All 22 WRF-Hydro `.a` libraries plus 2 additional `.o` files have zero `R_X86_64_32S` relocations. This was verified with `readelf -r` on every library. Both the system gfortran 13.3.0 (which built the originals) and the conda gfortran 14.3.0 inject `-fPIC` by default via compiler specs (`--enable-default-pie` in the GCC configure). This means the rebuild with explicit `-fPIC` will produce functionally identical object code -- the primary value is making the requirement explicit and portable.

### Finding 2: Compiler Mismatch Between Original Build and BMI Wrapper (HIGH confidence)
The original WRF-Hydro build used `/usr/bin/f95` (system gfortran 13.3.0). The BMI wrapper (`build.sh`) uses the conda gfortran 14.3.0. The fPIC rebuild provides an opportunity to align both to the conda compiler, improving ABI consistency.

### Finding 3: CMAKE_POSITION_INDEPENDENT_CODE Survives Flag Overrides (HIGH confidence)
WRF-Hydro's top-level CMakeLists.txt calls `set(CMAKE_Fortran_FLAGS "-cpp -w -ffree-form ...")` which overrides any user-appended flags. However, `CMAKE_POSITION_INDEPENDENT_CODE=ON` works through the target property mechanism, not through `CMAKE_Fortran_FLAGS`. Verified: cmake adds `-fPIC` as a separate flag even after the `set()` override. The verbose build output shows: `gfortran -cpp -w -ffree-form ... -fPIC -c ...`.

### Finding 4: All Library Targets Use STATIC (HIGH confidence)
Every sub-CMakeLists.txt in the WRF-Hydro source tree defines its library with `add_library(name STATIC ...)`. The `POSITION_INDEPENDENT_CODE` property applies to STATIC targets via `CMAKE_POSITION_INDEPENDENT_CODE`. No special per-target configuration is needed.

### Finding 5: Build Time Estimate (MEDIUM confidence)
The WRF-Hydro build output is ~25MB across 22 libraries + object files + modules. With 16 cores available and `-j$(nproc)`, the cmake configure + build should take approximately 2-10 minutes on WSL2 (WSL2 filesystem I/O on NTFS is slower than native Linux).

### Finding 6: build_fpic/ Output Structure Mirrors build/ (HIGH confidence)
cmake generates the same directory structure regardless of build flags: `build_fpic/lib/` for static libraries, `build_fpic/mods/` for module files, `build_fpic/src/CMakeFiles/wrfhydro.dir/` for object files. The `build.sh --fpic` flag only needs to change the base `WRF_BUILD` path; the three derived paths (`WRF_MODS`, `WRF_LIB`, `WRF_OBJ`) maintain the same relative structure.

### Finding 7: 24 Libraries, Not 22 (HIGH confidence)
The `build/lib/` directory contains 24 `.a` files (22 listed in build.sh + `libcrocus_surfex.a` + `libsnowcro.a`). All 24 are already in the build.sh `WRF_LIBS_SINGLE` variable. The "22 libraries" count from CLAUDE.md is slightly inaccurate but functionally correct since all are handled by the same cmake mechanism.

## Open Questions

1. **Build time on WSL2/NTFS**
   - What we know: 25MB total output, 16 cores available, cmake parallel build
   - What's unclear: Actual wall-clock time on this specific WSL2 instance with NTFS overhead
   - Recommendation: Time the first rebuild and document for future reference. Estimate 2-10 minutes.

2. **Compiler version alignment**
   - What we know: Original build used system gfortran 13.3.0, BMI wrapper uses conda 14.3.0. Both produce compatible object code (verified by existing 151 tests passing).
   - What's unclear: Whether switching the WRF-Hydro build to conda gfortran changes any behavior or performance characteristics.
   - Recommendation: Use conda gfortran for the fPIC rebuild to align with BMI wrapper. If any test failures occur (unlikely), fall back to system gfortran. Differences between 13.3 and 14.3 are minor for this codebase.

## Sources

### Primary (HIGH confidence)
- WRF-Hydro CMakeLists.txt (`wrf_hydro_nwm_public/CMakeLists.txt`) -- all compiler flags, library targets, build structure verified by direct reading
- WRF-Hydro sub-CMakeLists (30 files in `src/`) -- confirmed all use `add_library(... STATIC ...)`
- `build/CMakeCache.txt` -- confirmed original build used `/usr/bin/f95`, Release mode, no explicit PIC
- `build/src/HYDRO_drv/CMakeFiles/hydro_driver.dir/flags.make` -- confirmed actual compilation flags (no -fPIC, but PIC via compiler default)
- `readelf -r` on all 24 `.a` files -- confirmed zero `R_X86_64_32S` relocations across all libraries
- gfortran specs (`-dumpspecs`) -- confirmed both system and conda gfortran inject `-fPIC` by default
- cmake verbose build test -- confirmed `CMAKE_POSITION_INDEPENDENT_CODE=ON` adds `-fPIC` even when `CMAKE_Fortran_FLAGS` is overridden
- `bmi_wrf_hydro/build.sh` -- confirmed library list, linker flags, path structure
- [CMAKE_POSITION_INDEPENDENT_CODE documentation](https://cmake.org/cmake/help/latest/variable/CMAKE_POSITION_INDEPENDENT_CODE.html) -- confirmed mechanism for STATIC targets

### Secondary (MEDIUM confidence)
- [CMake POSITION_INDEPENDENT_CODE target property](https://cmake.org/cmake/help/latest/prop_tgt/POSITION_INDEPENDENT_CODE.html) -- confirmed True by default for SHARED/MODULE, initialized by variable for others

### Tertiary (LOW confidence)
- Build time estimate (2-10 minutes) -- based on output size and core count, not measured

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- cmake mechanism verified by direct testing on this system
- Architecture: HIGH -- build.sh modification is a simple path switch; rebuild_fpic.sh is a standard cmake invocation
- Pitfalls: HIGH -- compiler selection and flag override issues verified empirically; WSL2 issues documented from project experience

**Research date:** 2026-02-23
**Valid until:** Indefinite (cmake mechanism and compiler behavior are stable; only changes if conda environment or WRF-Hydro version changes)
