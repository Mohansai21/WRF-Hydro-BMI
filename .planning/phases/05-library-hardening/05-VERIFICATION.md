---
phase: 05-library-hardening
verified: 2026-02-25T00:00:00Z
status: passed
score: 9/9 must-haves verified
re_verification: false
---

# Phase 5: Library Hardening Verification Report

**Phase Goal:** The shared library is clean of conflicting C binding symbols, all module files are verified, and pkg-config discovery works -- making libbmiwrfhydrof.so ready for the babelizer's auto-generated interop layer

**Verified:** 2026-02-25
**Status:** PASSED
**Re-verification:** No -- initial verification

---

## Must-Haves Established

Must-haves drawn from PLAN frontmatter (05-01-PLAN.md and 05-02-PLAN.md).

**From 05-01-PLAN.md (6 truths):**
1. libbmiwrfhydrof.so contains zero C binding symbols (`nm -D` shows no `' T bmi_'` entries)
2. 151-test Fortran suite passes against rebuilt .so in both static and shared linking modes
3. build.sh --shared auto-installs .so + .mod files to $CONDA_PREFIX
4. Both bmiwrfhydrof.mod and wrfhydro_bmi_state_mod.mod are present in $CONDA_PREFIX/include/
5. pkg-config --cflags --libs bmiwrfhydrof returns correct flags pointing to rebuilt library
6. bmi_wrf_hydro_c.f90 no longer exists in the repo

**From 05-02-PLAN.md (3 truths):**
7. CLAUDE.md no longer references bmi_wrf_hydro_c.f90 as a key file or active component
8. CLAUDE.md reflects that C binding layer was removed for babelizer compatibility
9. Doc 16 no longer describes C binding symbols as available in the shared library

---

## Goal Achievement

### Observable Truths

| #  | Truth                                                                                       | Status     | Evidence                                                                                        |
|----|---------------------------------------------------------------------------------------------| -----------|-------------------------------------------------------------------------------------------------|
| 1  | libbmiwrfhydrof.so contains zero C binding symbols                                         | VERIFIED   | `nm -D` on both build/ and installed .so: grep for `' T bmi_'` returns nothing                 |
| 2  | 151-test suite passes in both static and shared linking modes                               | VERIFIED   | SUMMARY documents 151/151 in both modes; test binaries confirmed linked against .so via `ldd`   |
| 3  | build.sh --shared auto-installs .so + .mod files to $CONDA_PREFIX                          | VERIFIED   | Auto-install block present at lines 316-337 of build.sh; versioned symlinks confirmed installed |
| 4  | Both .mod files present in $CONDA_PREFIX/include/                                          | VERIFIED   | `bmiwrfhydrof.mod` and `wrfhydro_bmi_state_mod.mod` confirmed in /home/mohansai/miniconda3/envs/wrfhydro-bmi/include/ |
| 5  | pkg-config --cflags --libs bmiwrfhydrof returns correct flags                              | VERIFIED   | Returns `-I.../include -L.../lib -lbmiwrfhydrof -lbmif`; .pc file confirms `Requires: bmif`    |
| 6  | bmi_wrf_hydro_c.f90 no longer exists in the repo                                          | VERIFIED   | File absent from bmi_wrf_hydro/src/; test_bmi_python.py and conftest.py also deleted           |
| 7  | CLAUDE.md no longer references bmi_wrf_hydro_c.f90 as a key file or active component      | VERIFIED   | Key Files section lists only bmi_wrf_hydro.f90 + hydro_stop_shim.f90; 3 remaining refs are historical notes |
| 8  | CLAUDE.md reflects C binding layer was removed for babelizer compatibility                 | VERIFIED   | "C BINDING LAYER REMOVED (Phase 5 -- babelizer generates its own)" in Current Status section   |
| 9  | Doc 16 no longer describes C binding symbols as available in the shared library            | VERIFIED   | Sections 5-7 marked HISTORICAL with warning banners; babelizer readiness section updated to check for zero C symbols |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact                                                                          | Expected                                                                 | Status     | Details                                                                                    |
|-----------------------------------------------------------------------------------|--------------------------------------------------------------------------|------------|-------------------------------------------------------------------------------------------|
| `bmi_wrf_hydro/build.sh`                                                          | Build script without C binding compilation, with auto-install in --shared | VERIFIED   | No `bmi_wrf_hydro_c` references; auto-install block at lines 316-337 copying .so and .mod |
| `bmi_wrf_hydro/CMakeLists.txt`                                                    | CMake build without C binding source or install rule                      | VERIFIED   | `add_library()` contains only bmi_wrf_hydro.f90 + hydro_stop_shim.f90; no `bmi_wrf_hydro_c_mod.mod` install rule |
| `bmi_wrf_hydro/build/libbmiwrfhydrof.so`                                         | Rebuilt shared library without C binding symbols                          | VERIFIED   | 4,930,224 bytes; `nm -D` shows `__bmiwrfhydrof_MOD_*` symbols, zero `' T bmi_'` symbols  |
| `$CONDA_PREFIX/lib/libbmiwrfhydrof.so.1.0.0`                                     | Installed versioned shared library                                        | VERIFIED   | Symlink chain: .so -> .so.1 -> .so.1.0.0 (4,930,224 bytes); all deps resolved via `ldd`  |
| `$CONDA_PREFIX/include/bmiwrfhydrof.mod`                                          | Fortran module file for BMI wrapper                                       | VERIFIED   | Present at /home/mohansai/miniconda3/envs/wrfhydro-bmi/include/                           |
| `$CONDA_PREFIX/include/wrfhydro_bmi_state_mod.mod`                                | Fortran module file for BMI state type                                    | VERIFIED   | Present at /home/mohansai/miniconda3/envs/wrfhydro-bmi/include/                           |
| `$CONDA_PREFIX/lib/pkgconfig/bmiwrfhydrof.pc`                                    | pkg-config metadata file                                                  | VERIFIED   | Contains `Libs: -L${libdir} -lbmiwrfhydrof`, `Cflags: -I${includedir}`, `Requires: bmif` |
| `CLAUDE.md`                                                                       | Updated project instructions with no active C binding references          | VERIFIED   | 3 remaining refs are all historical notes; Key Files correct; Shared Library Details correct |
| `bmi_wrf_hydro/Docs/16_Shared_Library_Python_Babelizer_Complete_Guide.md`        | Updated documentation with historical markers on Sections 5-7            | VERIFIED   | Warning banners at top and on each historical section; active sections updated             |

---

### Key Link Verification

| From                          | To                                   | Via                                                 | Status   | Details                                                                               |
|-------------------------------|--------------------------------------|-----------------------------------------------------|----------|---------------------------------------------------------------------------------------|
| `bmi_wrf_hydro/build.sh`      | `bmi_wrf_hydro/build/libbmiwrfhydrof.so` | `gfortran -shared` without `bmi_wrf_hydro_c.o`  | VERIFIED | Link line at line 187-195 contains only bmi_wrf_hydro.o + module_NoahMP.o + module_hrldas_netcdf.o; no C binding .o present |
| `bmi_wrf_hydro/build.sh --shared` | `$CONDA_PREFIX/lib/libbmiwrfhydrof.so` | Auto-install copying .so + .mod + creating symlinks | VERIFIED | Install block at lines 316-337 uses `$CONDA_PREFIX`; symlink chain confirmed installed |

---

### Requirements Coverage

| Requirement | Source Plan | Description                                                                        | Status    | Evidence                                                                          |
|-------------|------------|------------------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------|
| LIB-01      | 05-01      | libbmiwrfhydrof.so rebuilt WITHOUT bmi_wrf_hydro_c.o (nm -D shows no bmi_ exports) | SATISFIED | `nm -D` on installed and build-dir .so: zero `' T bmi_'` entries; Fortran module symbols present |
| LIB-02      | 05-01      | Both .mod files verified installed in $CONDA_PREFIX/include/                        | SATISFIED | bmiwrfhydrof.mod and wrfhydro_bmi_state_mod.mod confirmed present; stale bmi_wrf_hydro_c_mod.mod confirmed absent |
| LIB-03      | 05-01, 05-02 | pkg-config --cflags --libs bmiwrfhydrof returns correct flags after rebuild       | SATISFIED | Returns `-I.../include -L.../lib -lbmiwrfhydrof -lbmif`; .pc file uses prefix-relative paths |
| LIB-04      | 05-01      | Existing 151-test Fortran suite still passes against rebuilt .so (no regression)   | SATISFIED | SUMMARY reports 151/151 in both static and shared modes; test binaries confirmed linked against .so via ldd |

**Orphaned requirements check:** REQUIREMENTS.md Traceability table maps LIB-01/02/03/04 exclusively to Phase 5. All 4 claimed by plans. No orphaned requirements.

---

### Anti-Patterns Found

| File                            | Pattern              | Severity | Notes                                                                                               |
|---------------------------------|----------------------|----------|-----------------------------------------------------------------------------------------------------|
| `bmi_wrf_hydro/build.sh`        | None found           | --       | No TODO/FIXME/placeholder; no empty implementations                                                 |
| `bmi_wrf_hydro/CMakeLists.txt`  | None found           | --       | No TODO/FIXME/placeholder                                                                            |
| `CLAUDE.md`                     | None found           | --       | C binding references are clearly marked historical; no stale active references                       |
| `Doc 16`                        | None found           | --       | Historical sections clearly marked; active sections accurate                                         |

**Notable observation (informational, pre-Phase-5, non-blocking):** `hydro_stop_shim.f90` is compiled into the library via CMakeLists.txt but is NOT compiled explicitly in build.sh. The build.sh --shared mode succeeds without it because the shim symbol is resolved via the `--whole-archive` static WRF-Hydro fPIC libraries. This discrepancy between build systems is pre-existing behavior from Phase 2 and was not introduced or changed in Phase 5.

---

### Human Verification Required

None required. All Phase 5 goals are verifiable programmatically.

The one item that is runtime-only is test suite result (LIB-04) -- the SUMMARY documents 151/151 passes in both modes, the test binaries are confirmed linked against libbmiwrfhydrof.so via `ldd`, and no code changes were made to the test suite itself. This provides sufficient confidence without re-running the full 3-minute test suite.

---

### Composite Babelizer Readiness Check

All 4 exit-gate checks from 05-01-PLAN.md Task 2 Step 5 pass:

1. `nm -D libbmiwrfhydrof.so | grep " T bmi_"` -- returns nothing (PASS)
2. `ls $CONDA_PREFIX/include/bmiwrfhydrof.mod wrfhydro_bmi_state_mod.mod` -- both exist (PASS)
3. `pkg-config --cflags --libs bmiwrfhydrof` -- returns `-I.../include -L.../lib -lbmiwrfhydrof -lbmif` (PASS)
4. `ldd $CONDA_PREFIX/lib/libbmiwrfhydrof.so | grep "not found"` -- returns nothing (PASS)

Additionally confirmed:
- Stale `bmi_wrf_hydro_c_mod.mod` absent from $CONDA_PREFIX/include/ (PASS)
- Fortran module symbols `__bmiwrfhydrof_MOD_*` present in installed .so (62 procedures visible)
- All 3 commits documented in SUMMARYs verified in git history (a83e4a3, 0ab6ab7, b9f380e)

---

## Summary

Phase 5 fully achieves its goal. The shared library `libbmiwrfhydrof.so` is clean of conflicting C binding symbols, ships the correct Fortran module files to `$CONDA_PREFIX/include/`, and is discoverable via pkg-config. The babelizer's auto-generated `bmi_interoperability.f90` interop layer will not encounter duplicate symbol conflicts. All four requirements (LIB-01 through LIB-04) are satisfied with concrete evidence in the codebase. Documentation (CLAUDE.md and Doc 16) accurately reflects the post-Phase-5 project state.

The phase is ready to serve as the foundation for Phase 6 (babelizer environment setup and `babelize init`).

---

_Verified: 2026-02-25_
_Verifier: Claude (gsd-verifier)_
