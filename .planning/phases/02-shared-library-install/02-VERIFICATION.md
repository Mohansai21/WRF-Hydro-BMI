---
phase: 02-shared-library-install
verified: 2026-02-23T20:45:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Run ./build.sh --shared full from bmi_wrf_hydro/ and confirm 151/151 pass"
    expected: "libbmiwrfhydrof.so created in build/, all 151 tests pass when linked against it"
    why_human: "Test suite takes ~7 minutes and requires WRF-Hydro domain data; cannot run in verification pass"
  - test: "Run ctest --test-dir _build from bmi_wrf_hydro/ directory"
    expected: "1/1 CTest test passes (bmi_wrf_hydro_all_tests with 151 sub-tests)"
    why_human: "CTest requires WRF_Hydro_Run_Local/run/ data and MPI runtime; cannot run in verification pass"
---

# Phase 2: Shared Library + Install Verification Report

**Phase Goal:** `libwrfhydrobmi.so` builds, links all dependencies with no unresolved symbols, and installs to conda prefix with pkg-config discovery -- making the library babelizer-ready
**Verified:** 2026-02-23T20:45:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

All truths derived from the ROADMAP.md Phase 2 Success Criteria and plan frontmatter `must_haves`.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `cmake --build` produces `libbmiwrfhydrof.so` with zero unresolved symbols | VERIFIED | `_build/libbmiwrfhydrof.so.1.0.0` exists (4.9MB); `ldd` shows 0 "not found" entries |
| 2 | `build.sh --shared` flag produces `libbmiwrfhydrof.so` for fast dev iteration | VERIFIED | `build.sh` lines 148-199 implement full --shared path; commit 89b3ca8 confirmed working |
| 3 | `cmake --install` places .so, .mod files, and .pc in conda prefix | VERIFIED | `install_manifest.txt` confirms all 6 artifacts installed to `/home/mohansai/miniconda3/envs/wrfhydro-bmi/` |
| 4 | `pkg-config --libs bmiwrfhydrof` returns correct linker flags | VERIFIED | Returns `-L/home/mohansai/miniconda3/envs/wrfhydro-bmi/lib -lbmiwrfhydrof -lbmif` |
| 5 | `pkg-config --cflags bmiwrfhydrof` returns include path | VERIFIED | Returns `-I/home/mohansai/miniconda3/envs/wrfhydro-bmi/include` |
| 6 | `pkg-config --modversion bmiwrfhydrof` returns version | VERIFIED | Returns `1.0.0` |
| 7 | `--shared` auto-implies `--fpic` | VERIFIED | `build.sh` lines 51-53: `if [ "$USE_SHARED" = "true" ]; then USE_FPIC="true"; fi` |
| 8 | `--shared clean` removes the .so from `build/` | VERIFIED | `build.sh` line 96: `rm -f ... "${BUILD_DIR}"/libbmiwrfhydrof.so` |
| 9 | 62 BMI symbols exported from installed .so | VERIFIED | `nm -D libbmiwrfhydrof.so.1.0.0 \| grep -ci bmi` returns 62 |

**Score:** 9/9 truths verified

### Required Artifacts

#### Plan 02-01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `bmi_wrf_hydro/build.sh` | `--shared` flag for building `libbmiwrfhydrof.so` | VERIFIED | Contains `--shared` flag, `link_executable_shared()`, `gfortran -shared` with `--whole-archive` |
| `bmi_wrf_hydro/build/libbmiwrfhydrof.so` | Shared library in build/ | TRANSIENT | Not currently present (cleaned after CMake path completed); build.sh --shared produces it on demand; persistent deliverable is the conda-installed version |

Note on transient artifact: The CONTEXT decision explicitly states "build.sh does NOT install" and the persistent deliverable is the conda-installed `.so`. The `build/libbmiwrfhydrof.so` is produced by `./build.sh --shared` and consumed during the test run, then persists until cleaned. Its absence in the current snapshot does not indicate a failure -- it means the session ended with a clean state after the CMake install path was used.

#### Plan 02-02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `bmi_wrf_hydro/CMakeLists.txt` | CMake project building `libbmiwrfhydrof.so` with `add_library(bmiwrfhydrof SHARED` | VERIFIED | Line 274: `add_library(${bmi_name} SHARED` where `bmi_name=bmiwrfhydrof`; substantive 440-line implementation |
| `bmi_wrf_hydro/bmiwrfhydrof.pc.cmake` | pkg-config template with `Requires: bmif` | VERIFIED | Line 9: `Requires: bmif`; 11-line template following bmi-example-fortran pattern |
| `bmi_wrf_hydro/src/hydro_stop_shim.f90` | Bare external `hydro_stop` shim for `--whole-archive` symbol resolution | VERIFIED | 27-line implementation delegating to `module_hydro_stop` |
| `$CONDA_PREFIX/lib/libbmiwrfhydrof.so` | Installed shared library | VERIFIED | Symlink chain: `.so -> .so.1 -> .so.1.0.0` (4.9MB); all deps resolve |
| `$CONDA_PREFIX/include/bmiwrfhydrof.mod` | Installed BMI wrapper Fortran module | VERIFIED | 11,129 bytes at `/home/mohansai/miniconda3/envs/wrfhydro-bmi/include/bmiwrfhydrof.mod` |
| `$CONDA_PREFIX/include/wrfhydro_bmi_state_mod.mod` | Installed BMI state module | VERIFIED | 1,373 bytes at `/home/mohansai/miniconda3/envs/wrfhydro-bmi/include/wrfhydro_bmi_state_mod.mod` |
| `$CONDA_PREFIX/lib/pkgconfig/bmiwrfhydrof.pc` | Installed pkg-config file | VERIFIED | 285 bytes; correct `prefix`, `Libs`, `Cflags`, `Requires: bmif` |

### Key Link Verification

#### Plan 02-01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `build.sh (--shared)` | `wrf_hydro_nwm_public/build_fpic/lib/*.a` | `-Wl,--whole-archive ... -Wl,--no-whole-archive` | WIRED | Lines 191-194: full `--whole-archive` + `${WRF_STATIC_LIBS_FULL}` pattern present |
| `build/bmi_wrf_hydro_test` | `build/libbmiwrfhydrof.so` | `-L./build -lbmiwrfhydrof` with `-Wl,-rpath` | WIRED | `link_executable_shared()` at lines 225-235: `-L"${BUILD_DIR}" -lbmiwrfhydrof -Wl,-rpath,"${BUILD_DIR}"` |

#### Plan 02-02 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `bmi_wrf_hydro/CMakeLists.txt` | `bmi-fortran conda package` | `pkg_check_modules(BMIF REQUIRED IMPORTED_TARGET bmif)` | WIRED | Line 108: exact match for required pattern |
| `bmi_wrf_hydro/CMakeLists.txt` | `wrf_hydro_nwm_public/build_fpic/lib/*.a` | `target_link_libraries` with `--whole-archive` | WIRED | Lines 301-303: `-Wl,--whole-archive ${WRF_STATIC_LIBS} -Wl,--no-whole-archive` |
| `bmi_wrf_hydro/bmiwrfhydrof.pc.cmake` | babelizer Meson build | `Requires: bmif` pattern | WIRED | Line 9: `Requires: bmif`; installed `.pc` verified via `pkg-config --libs` returning `-lbmiwrfhydrof -lbmif` |

### Requirements Coverage

All 4 requirement IDs declared across the two plans for this phase are cross-referenced against REQUIREMENTS.md.

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BUILD-02 | 02-02-PLAN.md | `libwrfhydrobmi.so` builds via CMake, linking all 22 WRF-Hydro static libs + BMI + NetCDF + MPI with no unresolved symbols | SATISFIED | `_build/libbmiwrfhydrof.so.1.0.0` (4.9MB); `ldd` shows 0 "not found"; 22 static libs linked via `--whole-archive`; `nm -D` shows 62 BMI symbols |
| BUILD-03 | 02-01-PLAN.md | `build.sh` updated with shared library target (`-shared` flag) for fast dev iteration | SATISFIED | `build.sh` lines 21-24, 51-53, 141-199: `--shared` flag parses, auto-implies `--fpic`, recompiles 2 driver .o files, links via `gfortran -shared --whole-archive` |
| BUILD-04 | 02-02-PLAN.md | `cmake --install` places `.so`, `.mod` files, and `.pc` in `$CONDA_PREFIX/{lib,include,lib/pkgconfig}` | SATISFIED | `install_manifest.txt` confirms: `.so.1.0.0` + 2 symlinks in `lib/`, 2 `.mod` files in `include/`, `.pc` in `lib/pkgconfig/` |
| BUILD-05 | 02-02-PLAN.md | pkg-config `.pc` file generated by CMake enabling babelizer discovery via `pkg-config bmiwrfhydrof` | SATISFIED | `pkg-config --libs bmiwrfhydrof` returns `-L.../lib -lbmiwrfhydrof -lbmif`; `--cflags` returns `-I.../include`; `--modversion` returns `1.0.0` |

**Orphaned requirements check:** REQUIREMENTS.md Traceability table maps BUILD-02, BUILD-03, BUILD-04, BUILD-05 to Phase 2 -- all 4 are claimed by the plans and verified. No orphaned requirements.

**REQUIREMENTS.md vs ROADMAP naming note:** REQUIREMENTS.md uses `libwrfhydrobmi.so` in descriptions while the actual library is named `libbmiwrfhydrof.so`. The naming follows the bmi-example-fortran `bmi{model}f` convention adopted by the plans. This is a documentation inconsistency in REQUIREMENTS.md, not a goal gap -- the intent (shared library + pkg-config) is fully met by `libbmiwrfhydrof.so`.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None | - | No TODOs, FIXMEs, placeholders, or stub implementations found | - | None |

Scanned files: `bmi_wrf_hydro/CMakeLists.txt`, `bmi_wrf_hydro/bmiwrfhydrof.pc.cmake`, `bmi_wrf_hydro/src/hydro_stop_shim.f90`, `bmi_wrf_hydro/build.sh`. All clean.

### Notable Observations (Not Blockers)

1. **ROADMAP.md stale checkbox:** `[ ] 02-02-PLAN.md` in ROADMAP.md was never updated to `[x]` after plan completion. The progress table also still shows `1/2 plans complete`. This is a documentation gap only -- the goal is fully achieved.

2. **Transient build artifact:** `bmi_wrf_hydro/build/libbmiwrfhydrof.so` is absent in the current snapshot. This is expected -- the CONTEXT decision states "build.sh does NOT install" and `build/` is the scratch output directory for the `--shared` dev iteration path. The persistent deliverable is the conda-installed version at `$CONDA_PREFIX/lib/libbmiwrfhydrof.so`.

3. **Library naming:** The final library is `libbmiwrfhydrof.so` (following `bmi{model}f` babelizer convention), not `libwrfhydrobmi.so` as the phase goal statement suggests. Both REQUIREMENTS.md and ROADMAP.md use the older name in prose, but the plans and implementation correctly use `bmiwrfhydrof`.

### Human Verification Required

#### 1. build.sh --shared Test Suite Run

**Test:** From `bmi_wrf_hydro/` directory, run `./build.sh --shared full`
**Expected:** `build/libbmiwrfhydrof.so` is created, `bmi_wrf_hydro_test` is linked against it (not against static .o files), and 151/151 BMI tests pass
**Why human:** Test suite takes ~7 minutes and requires WRF-Hydro Croton NY domain data at `WRF_Hydro_Run_Local/run/`; cannot run in automated verification pass

#### 2. CMake CTest Run

**Test:** From `bmi_wrf_hydro/` directory, run `cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX && cmake --build _build && ctest --test-dir _build`
**Expected:** 1/1 CTest tests pass (`bmi_wrf_hydro_all_tests`)
**Why human:** CTest requires WRF_Hydro_Run_Local/run/ domain data and MPI runtime; cannot run in verification pass. Note: `_build/bmi_wrf_hydro_test` already exists (4.4MB), confirming the build was performed

---

## Summary

Phase 2 goal is **ACHIEVED**. All 9 observable truths are verified, all 4 requirement IDs (BUILD-02, BUILD-03, BUILD-04, BUILD-05) are satisfied, and the library is babelizer-ready:

- `libbmiwrfhydrof.so` is installed at `$CONDA_PREFIX/lib/` with proper symlink chain
- `pkg-config --libs bmiwrfhydrof` returns valid flags (`-lbmiwrfhydrof -lbmif`)
- Zero unresolved symbols (`ldd` verified)
- 62 BMI symbols exported (`nm -D` verified)
- 2 `.mod` files installed to `$CONDA_PREFIX/include/`
- `.pc` file installed to `$CONDA_PREFIX/lib/pkgconfig/`
- `build.sh --shared` flag fully implemented with `--whole-archive` linking, rpath support, and auto-test execution
- `CMakeLists.txt` follows bmi-example-fortran pattern for babelizer compatibility
- `hydro_stop_shim.f90` resolves the bare `hydro_stop_` symbol from `--whole-archive` dead code

The single non-blocking gap is a stale `[ ]` checkbox in ROADMAP.md for plan 02-02.

---

_Verified: 2026-02-23T20:45:00Z_
_Verifier: Claude (gsd-verifier)_
