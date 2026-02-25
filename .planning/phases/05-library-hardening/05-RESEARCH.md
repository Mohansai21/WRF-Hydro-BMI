# Phase 5: Library Hardening - Research

**Researched:** 2026-02-24
**Domain:** Fortran shared library symbol management, pkg-config discovery, build system cleanup
**Confidence:** HIGH

## Summary

Phase 5 is a surgical cleanup phase: remove the C binding layer (`bmi_wrf_hydro_c.f90`) from the repository, rebuild `libbmiwrfhydrof.so` without it, verify all install artifacts, and confirm nothing regressed. The work is well-understood because the conflict was identified during v2.0 research (PITFALLS.md, Pitfall 8) and the exact symbols to remove are known (10 `bmi_*` C-callable symbols currently exported via `nm -D`). The build system has two paths -- `build.sh --shared` for fast iteration and `CMakeLists.txt` via `cmake` for production install -- and both must be updated.

The current state is verified: both the installed `.so` at `$CONDA_PREFIX/lib/` and the build-dir `.so` at `bmi_wrf_hydro/build/` export 10 conflicting `bmi_*` symbols (bmi_initialize, bmi_update, bmi_finalize, bmi_register, bmi_get_component_name, bmi_get_current_time, bmi_get_var_grid, bmi_get_grid_size, bmi_get_var_nbytes, bmi_get_value_double). Both `.mod` files are already installed (`bmiwrfhydrof.mod` + `wrfhydro_bmi_state_mod.mod`), plus the now-unneeded `bmi_wrf_hydro_c_mod.mod`. The pkg-config file is working and returns correct flags. The 151-test suite was passing against the `.so` as of v1.0.

**Primary recommendation:** Delete `bmi_wrf_hydro_c.f90` from `src/`, remove it from both build systems, delete the Python ctypes tests that depend on the C symbols, rebuild and reinstall, then verify all 4 success criteria in a single composite check.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Delete `bmi_wrf_hydro_c.f90` entirely from the repo (not just exclude from link line)
- Delete the Python ctypes test (`tests/test_bmi_ctypes.py`) -- it depends on C symbols being removed; Phase 7 will have Python tests via the babelized package
- Keep `hydro_stop_shim.f90` in the .so -- it's needed by the BMI wrapper's finalize(), unrelated to C bindings
- Update CLAUDE.md and Doc 16 references to `bmi_wrf_hydro_c.f90` during this phase (don't defer to Phase 9)
- Update both `build.sh` and `CMakeLists.txt` to remove C binding compilation/linking
- Remove C binding from ALL build modes (static, --fpic, --shared), not just --shared
- `./build.sh --shared` should auto-install the rebuilt .so to `$CONDA_PREFIX/lib/` (overwriting old one)
- Do NOT add singleton guard to `bmi_wrf_hydro.f90` in this phase -- defer to Phase 8 if bmi-tester needs it
- Run all three checks: 151-test suite + minimal smoke test + manual `nm -D` symbol check
- Test in both modes: static linking (default build) AND dynamic linking (--shared build)
- If `nm` shows unexpected `bmi_` symbols in the .so, block and fix -- do not proceed
- Interactive validation during execution (no persistent log files needed)
- Verify both .mod files present: `ls $CONDA_PREFIX/include/bmiwrfhydrof.mod` and `wrfhydro_bmi_state_mod.mod`
- Verify pkg-config flags are correct (not just that it returns something) -- check -L and -l paths
- Keep version at 1.0.0 (ABI didn't change, we only removed symbols)
- Run a final composite "babelizer readiness check" as the Phase 5 exit gate

### Claude's Discretion
- Exact ordering of build script modifications
- Whether to consolidate build.sh cleanup into one edit or multiple
- How to structure the composite readiness check (inline script vs separate function)

### Deferred Ideas (OUT OF SCOPE)
- Singleton guard (`active_instance_count` in `bmi_wrf_hydro.f90`) -- defer to Phase 8 if bmi-tester needs it
- Comprehensive Doc 18 -- Phase 9 (PYMT-04)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LIB-01 | `libbmiwrfhydrof.so` rebuilt WITHOUT `bmi_wrf_hydro_c.o` to remove conflicting C binding symbols (`nm -D` shows no `bmi_` exports) | Verified: current .so exports 10 `bmi_*` symbols from bmi_wrf_hydro_c_mod. Removing `bmi_wrf_hydro_c.f90` from both build paths (build.sh lines 148-154, 197-198, 218-219; CMakeLists.txt line 276) eliminates them. The Fortran module symbols (`__bmiwrfhydrof_MOD_*`) remain but do NOT conflict because they are mangled. |
| LIB-02 | Both `.mod` files (`bmiwrfhydrof.mod` + `wrfhydro_bmi_state_mod.mod`) verified installed in `$CONDA_PREFIX/include/` | Verified: both currently installed. CMake install_manifest.txt confirms. Must also REMOVE `bmi_wrf_hydro_c_mod.mod` from install (CMakeLists.txt lines 394-398) and from `$CONDA_PREFIX/include/` since the source file is being deleted. |
| LIB-03 | `pkg-config --cflags --libs bmiwrfhydrof` returns correct flags after rebuild | Verified: currently returns `-I.../include -L.../lib -lbmiwrfhydrof -lbmif`. The pkg-config file (`bmiwrfhydrof.pc`) does not reference `bmi_wrf_hydro_c` anywhere -- no changes needed to the `.pc` file or template. Rebuild + reinstall preserves correct flags. |
| LIB-04 | Existing 151-test Fortran suite still passes against rebuilt `.so` (no regression) | The 151-test suite (`bmi_wrf_hydro_test.f90`) does NOT use any C binding functions. It only `use`s `bmiwrfhydrof` module and calls type-bound procedures. Removing C bindings has zero impact on Fortran test functionality. Must verify in both static and dynamic linking modes. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| gfortran | 14.3.0 | Compiles Fortran sources, produces .mod and .o files | Already in conda env, same compiler used for all prior phases |
| build.sh | N/A | Fast dev iteration: compile + link + test | Project's shell-based build system for --shared mode |
| CMakeLists.txt | cmake 3.31.1 | Production build: .so versioning, .mod install, .pc generation | Project's CMake-based install system |
| nm | GNU binutils | Inspect exported symbols in .so | Standard ELF symbol inspection tool |
| pkg-config | system | Verify library discovery flags | Babelizer uses this to find our library |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| ldd | GNU binutils | Verify no missing shared library dependencies | Final readiness check |
| mpif90 | OpenMPI 5.0.8 | Fortran MPI compiler wrapper for linking tests | Used by build.sh for test executables |
| mpirun | OpenMPI 5.0.8 | Run tests with MPI singleton process | Test execution |

### Alternatives Considered

None -- this phase uses only existing tools already in the project. No new dependencies needed.

## Architecture Patterns

### Current File Layout (Before Phase 5)
```
bmi_wrf_hydro/
  src/
    bmi_wrf_hydro.f90         # BMI wrapper (1919 lines) -- KEEP
    bmi_wrf_hydro_c.f90       # C binding layer (335 lines) -- DELETE
    hydro_stop_shim.f90       # Linker shim (27 lines) -- KEEP
  tests/
    bmi_wrf_hydro_test.f90    # 151-test suite -- KEEP (no C binding deps)
    bmi_minimal_test.f90      # Minimal smoke test -- KEEP (no C binding deps)
    conftest.py               # Python ctypes fixtures -- DELETE
    test_bmi_python.py        # Python ctypes tests -- DELETE
  build/
    bmi_wrf_hydro.o           # Compiled BMI wrapper
    bmi_wrf_hydro_c.o         # Compiled C bindings -- will stop being created
    libbmiwrfhydrof.so        # Shared library (with conflicting symbols)
    bmiwrfhydrof.mod          # Module file
    bmi_wrf_hydro_c_mod.mod   # C binding module file -- will stop being created
    wrfhydro_bmi_state_mod.mod # State module file
  CMakeLists.txt              # CMake build -- update
  bmiwrfhydrof.pc.cmake       # pkg-config template -- NO CHANGE
  build.sh                    # Shell build -- update
```

### Target File Layout (After Phase 5)
```
bmi_wrf_hydro/
  src/
    bmi_wrf_hydro.f90         # BMI wrapper (unchanged)
    hydro_stop_shim.f90       # Linker shim (unchanged)
  tests/
    bmi_wrf_hydro_test.f90    # 151-test suite (unchanged)
    bmi_minimal_test.f90      # Minimal smoke test (unchanged)
  build/
    bmi_wrf_hydro.o           # Compiled BMI wrapper
    libbmiwrfhydrof.so        # Rebuilt shared library (NO bmi_* C symbols)
    bmiwrfhydrof.mod          # Module file
    wrfhydro_bmi_state_mod.mod # State module file
  CMakeLists.txt              # Updated (C binding sources removed)
  bmiwrfhydrof.pc.cmake       # Unchanged
  build.sh                    # Updated (C binding compile/link removed)
```

### Pattern 1: Symbol Verification via nm
**What:** Use `nm -D` to check the dynamic symbol table of a shared library for unexpected exports.
**When to use:** After every rebuild of the .so during this phase.
**Example:**
```bash
# Should return NOTHING after rebuild (exit code 1 from grep means "no match" = success)
nm -D libbmiwrfhydrof.so | grep " T bmi_"

# Fortran module symbols should still be present (these don't conflict):
nm -D libbmiwrfhydrof.so | grep "__bmiwrfhydrof_MOD_" | head -5
# Expected: __bmiwrfhydrof_MOD_wrfhydro_initialize, etc.
```
Source: v2.0 research PITFALLS.md, Pitfall 8 -- verified against current library state.

### Pattern 2: Build-Then-Install Flow
**What:** Rebuild the .so via build.sh, then install to conda prefix via CMake.
**When to use:** After modifying both build systems.
**Example:**
```bash
# Fast rebuild via build.sh
./build.sh --shared          # Builds .so + links tests + runs tests

# Production install via CMake
cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX
cmake --build _build
cmake --install _build       # Installs .so, .mod, .pc to conda prefix
```
Source: Project build.sh and CMakeLists.txt (existing patterns).

### Pattern 3: Auto-Install in build.sh --shared
**What:** After building the .so, copy it + .mod files to $CONDA_PREFIX (user decision).
**When to use:** build.sh --shared mode only.
**Example:**
```bash
# After building libbmiwrfhydrof.so in build/:
cp build/libbmiwrfhydrof.so $CONDA_PREFIX/lib/libbmiwrfhydrof.so.1.0.0
# Recreate symlinks
ln -sf libbmiwrfhydrof.so.1.0.0 $CONDA_PREFIX/lib/libbmiwrfhydrof.so.1
ln -sf libbmiwrfhydrof.so.1 $CONDA_PREFIX/lib/libbmiwrfhydrof.so
# Install .mod files
cp build/bmiwrfhydrof.mod $CONDA_PREFIX/include/
cp build/wrfhydro_bmi_state_mod.mod $CONDA_PREFIX/include/
```
Note: Must match the versioning pattern already established (1.0.0 with .so.1 SONAME link).

### Anti-Patterns to Avoid
- **Partial cleanup:** Removing from build.sh but forgetting CMakeLists.txt (or vice versa). BOTH build systems must be updated simultaneously.
- **Leaving stale .mod files:** After deleting `bmi_wrf_hydro_c.f90`, the old `bmi_wrf_hydro_c_mod.mod` remains in `$CONDA_PREFIX/include/` and `build/`. Must explicitly remove it.
- **Forgetting static build mode:** The C binding is compiled in ALL modes (not just --shared). Lines 148-154 in build.sh compile it unconditionally.
- **Testing only shared mode:** User decision requires testing both static and dynamic linking modes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Symbol inspection | Custom scripts parsing objdump | `nm -D lib.so \| grep pattern` | nm is the standard tool; grep provides exact pattern matching |
| pkg-config validation | Manual flag string comparison | `pkg-config --cflags --libs bmiwrfhydrof` then check output contains expected substrings | pkg-config is the authoritative source; babelizer uses it directly |
| Library dependency check | Manual ldd parsing | `ldd lib.so \| grep "not found"` | ldd is the standard dynamic linker diagnostics tool |

**Key insight:** This phase requires no new tools or libraries. Everything needed is already in the build environment. The work is purely editorial (delete files, update build scripts, verify).

## Common Pitfalls

### Pitfall 1: Stale Objects in build/ Directory
**What goes wrong:** After removing `bmi_wrf_hydro_c.f90` from the source tree, old `bmi_wrf_hydro_c.o` and `bmi_wrf_hydro_c_mod.mod` files remain in `build/`. If the linker picks them up, the rebuilt .so still has the C symbols.
**Why it happens:** `build.sh` creates objects in `build/` but only the `clean` target removes them. The default build target does not clean first.
**How to avoid:** Run `./build.sh clean` before rebuilding. Verify the .o and .mod files are gone after clean.
**Warning signs:** `nm -D` still shows `bmi_*` symbols after rebuild.

### Pitfall 2: CMake Cache Retains Deleted Source Files
**What goes wrong:** CMake caches the source file list. After removing `bmi_wrf_hydro_c.f90` from `CMakeLists.txt`, a rebuild without cleaning the cache may still compile the old file (if the cache remembers it).
**Why it happens:** CMake's incremental build system caches dependency graphs. Removing a source from `add_library()` may not trigger a full reconfigure.
**How to avoid:** Delete the `_build/` directory entirely and reconfigure from scratch: `rm -rf _build && cmake -B _build -DCMAKE_INSTALL_PREFIX=$CONDA_PREFIX`.
**Warning signs:** Build succeeds but `bmi_wrf_hydro_c.o` still appears in the build tree.

### Pitfall 3: Installed .so Is Stale (Not Overwritten)
**What goes wrong:** After rebuilding the .so, the installed copy at `$CONDA_PREFIX/lib/` is not updated. Tests linked against the build dir pass, but the babelizer (which uses the installed copy) still sees the old symbols.
**Why it happens:** `build.sh --shared` does not currently install to $CONDA_PREFIX. Only `cmake --install _build` does. User decision requires build.sh --shared to auto-install.
**How to avoid:** Add install steps to build.sh --shared. Always verify the INSTALLED .so (not just the build dir copy) with `nm -D`.
**Warning signs:** `nm -D $CONDA_PREFIX/lib/libbmiwrfhydrof.so | grep " T bmi_"` returns hits even after clean rebuild.

### Pitfall 4: Python ctypes Tests Left Behind
**What goes wrong:** After deleting C binding symbols, the Python ctypes tests (`test_bmi_python.py` + `conftest.py`) remain in the repo. They reference `lib.bmi_register()`, `lib.bmi_initialize()`, etc. which no longer exist in the .so. Running them would produce `AttributeError` or segfault.
**Why it happens:** Forgetting to delete all dependent files, not just the source.
**How to avoid:** Delete both `tests/test_bmi_python.py` and `tests/conftest.py`. Note: CONTEXT.md mentions `test_bmi_ctypes.py` but the actual file names are `test_bmi_python.py` and `conftest.py` (from Phase 3 Plan 2).
**Warning signs:** `pytest` discovers and fails on the old test files.

### Pitfall 5: CLAUDE.md References Become Stale
**What goes wrong:** CLAUDE.md still lists `bmi_wrf_hydro_c.f90` as a key file, mentions C binding layer as complete, and lists `bmi_wrf_hydro_c_mod.mod` in installed modules. This misleads future sessions.
**Why it happens:** Documentation not updated when code changes.
**How to avoid:** Update all CLAUDE.md sections that reference the C binding layer: Key Files, Phase 1.5 status, Current Status, Shared Library Details, src/ description.

## Code Examples

### Example 1: build.sh Before/After (Step 1b Removal)

**Before (lines 148-154):**
```bash
echo "=== Step 1b: Compile src/bmi_wrf_hydro_c.f90 (C binding layer) ==="
${FC} ${FFLAGS} ${EXTRA_FFLAGS} \
  -ffree-form -ffree-line-length-none -fconvert=big-endian -frecord-marker=4 \
  -fallow-argument-mismatch \
  ${INCLUDES} ${MOD_OUT} \
  "${SRC_DIR}/bmi_wrf_hydro_c.f90" -o "${BUILD_DIR}/bmi_wrf_hydro_c.o"
echo "    -> build/bmi_wrf_hydro_c.o created"
```

**After:** Delete entire block (lines 148-154).

### Example 2: build.sh Shared Library Link (Remove .o from Link Line)

**Before (line 197):**
```bash
  gfortran -shared -o "${BUILD_DIR}/libbmiwrfhydrof.so" \
    "${BUILD_DIR}/bmi_wrf_hydro.o" \
    "${BUILD_DIR}/bmi_wrf_hydro_c.o" \         # <-- REMOVE THIS LINE
    "${BUILD_DIR}/module_NoahMP_hrldas_driver.F.o" \
```

**After:**
```bash
  gfortran -shared -o "${BUILD_DIR}/libbmiwrfhydrof.so" \
    "${BUILD_DIR}/bmi_wrf_hydro.o" \
    "${BUILD_DIR}/module_NoahMP_hrldas_driver.F.o" \
```

### Example 3: build.sh Static Link Helper (Remove .o from Link)

**Before (lines 217-219):**
```bash
link_executable() {
  ...
  mpif90 -o "${BUILD_DIR}/${OUT_NAME}" \
    "${BUILD_DIR}/bmi_wrf_hydro.o" \
    "${BUILD_DIR}/bmi_wrf_hydro_c.o" \    # <-- REMOVE THIS LINE
    "${OBJ_FILE}" \
```

**After:**
```bash
link_executable() {
  ...
  mpif90 -o "${BUILD_DIR}/${OUT_NAME}" \
    "${BUILD_DIR}/bmi_wrf_hydro.o" \
    "${OBJ_FILE}" \
```

### Example 4: CMakeLists.txt Library Source Removal

**Before (lines 274-280):**
```cmake
add_library(${bmi_name} SHARED
  src/bmi_wrf_hydro.f90
  src/bmi_wrf_hydro_c.f90           # <-- REMOVE THIS LINE
  src/hydro_stop_shim.f90
  ${WRF_IO_SRC_DIR}/module_NoahMP_hrldas_driver.F
  ${WRF_IO_SRC_DIR}/module_hrldas_netcdf_io.F
)
```

**After:**
```cmake
add_library(${bmi_name} SHARED
  src/bmi_wrf_hydro.f90
  src/hydro_stop_shim.f90
  ${WRF_IO_SRC_DIR}/module_NoahMP_hrldas_driver.F
  ${WRF_IO_SRC_DIR}/module_hrldas_netcdf_io.F
)
```

### Example 5: CMakeLists.txt Install Section Cleanup

**Before (lines 394-398):**
```cmake
# Install the C binding module .mod file
install(
  FILES ${CMAKE_Fortran_MODULE_DIRECTORY}/bmi_wrf_hydro_c_mod.mod
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)
```

**After:** Delete entire block.

### Example 6: build.sh --shared Auto-Install Addition

```bash
# After building .so and running tests successfully:
echo "=== Installing to $CONDA_PREFIX ==="
CONDA_P=/home/mohansai/miniconda3/envs/wrfhydro-bmi

cp "${BUILD_DIR}/libbmiwrfhydrof.so" "${CONDA_P}/lib/libbmiwrfhydrof.so.1.0.0"
ln -sf libbmiwrfhydrof.so.1.0.0 "${CONDA_P}/lib/libbmiwrfhydrof.so.1"
ln -sf libbmiwrfhydrof.so.1 "${CONDA_P}/lib/libbmiwrfhydrof.so"
cp "${BUILD_DIR}/bmiwrfhydrof.mod" "${CONDA_P}/include/"
cp "${BUILD_DIR}/wrfhydro_bmi_state_mod.mod" "${CONDA_P}/include/"
echo "    -> Installed to $CONDA_P"
```

### Example 7: Composite Babelizer Readiness Check

```bash
echo "=== BABELIZER READINESS CHECK ==="
PASS=0
FAIL=0

# Check 1: No conflicting C binding symbols
if nm -D "$CONDA_P/lib/libbmiwrfhydrof.so" | grep -q " T bmi_"; then
  echo "  FAIL: Conflicting bmi_* C symbols found"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: No conflicting bmi_* C symbols"
  PASS=$((PASS + 1))
fi

# Check 2: Both .mod files present
if [ -f "$CONDA_P/include/bmiwrfhydrof.mod" ] && \
   [ -f "$CONDA_P/include/wrfhydro_bmi_state_mod.mod" ]; then
  echo "  PASS: Both .mod files present"
  PASS=$((PASS + 1))
else
  echo "  FAIL: Missing .mod files"
  FAIL=$((FAIL + 1))
fi

# Check 3: pkg-config returns correct flags
PC_OUT=$(pkg-config --cflags --libs bmiwrfhydrof 2>&1)
if echo "$PC_OUT" | grep -q "\-lbmiwrfhydrof" && \
   echo "$PC_OUT" | grep -q "\-I.*include"; then
  echo "  PASS: pkg-config returns correct flags"
  PASS=$((PASS + 1))
else
  echo "  FAIL: pkg-config output incorrect: $PC_OUT"
  FAIL=$((FAIL + 1))
fi

# Check 4: ldd shows no missing deps
if ldd "$CONDA_P/lib/libbmiwrfhydrof.so" | grep -q "not found"; then
  echo "  FAIL: Missing shared library dependencies"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: All shared library dependencies resolved"
  PASS=$((PASS + 1))
fi

echo "  Result: $PASS/4 passed, $FAIL/4 failed"
```

### Example 8: build.sh Clean Target Update

**Before (lines 94-96):**
```bash
rm -f "${BUILD_DIR}"/*.o "${BUILD_DIR}"/*.mod \
      "${BUILD_DIR}"/bmi_minimal_test "${BUILD_DIR}"/bmi_wrf_hydro_test \
      "${BUILD_DIR}"/libbmiwrfhydrof.so
```

**After (same -- no change needed):** The wildcard `*.o` and `*.mod` already covers all files. No C-binding-specific cleanup is needed because the wildcards handle it.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-written C bindings for ctypes testing (Phase 1.5) | Babelizer auto-generates 818-line interop layer | Phase 2 research (2026-02-24) | Our C bindings are now test infrastructure that must be removed before babelization |
| C bindings compiled into .so (Phase 3) | .so should only contain pure Fortran module symbols | Phase 5 (this phase) | Prevents duplicate symbol errors when babelizer's meson.build links against our .so |

**Deprecated/outdated:**
- `bmi_wrf_hydro_c.f90`: Was test infrastructure for validating shared library from Python via ctypes. Superseded by babelizer's auto-generated interop layer. Must be deleted.
- `test_bmi_python.py` + `conftest.py`: Python ctypes tests that depend on C binding symbols. Phase 7 will have proper Python tests via the babelized package. Must be deleted.
- `bmi_wrf_hydro_c_mod.mod`: Module file from C bindings. Must be removed from both build directories and $CONDA_PREFIX/include/.

## Specific File Changes Required

### Files to DELETE
1. `bmi_wrf_hydro/src/bmi_wrf_hydro_c.f90` -- C binding source (335 lines)
2. `bmi_wrf_hydro/tests/test_bmi_python.py` -- Python ctypes test (312 lines)
3. `bmi_wrf_hydro/tests/conftest.py` -- Python ctypes fixtures (181 lines)
4. `$CONDA_PREFIX/include/bmi_wrf_hydro_c_mod.mod` -- Installed module file (stale)
5. `bmi_wrf_hydro/build/bmi_wrf_hydro_c.o` -- Compiled object (stale, if present)
6. `bmi_wrf_hydro/build/bmi_wrf_hydro_c_mod.mod` -- Build-dir module file (stale)

### Files to MODIFY
1. `bmi_wrf_hydro/build.sh` -- Remove C binding compile step (Step 1b), remove .o from all link commands (shared + static), add auto-install to --shared mode
2. `bmi_wrf_hydro/CMakeLists.txt` -- Remove `src/bmi_wrf_hydro_c.f90` from `add_library()`, remove `bmi_wrf_hydro_c_mod.mod` install rule
3. `CLAUDE.md` -- Update Key Files, src/ description, Phase 1.5 status, Current Status, Shared Library Details sections
4. `bmi_wrf_hydro/Docs/16_Shared_Library_Python_Babelizer_Complete_Guide.md` -- Update references to C binding layer (16 occurrences)

### Files UNCHANGED
1. `bmi_wrf_hydro/src/bmi_wrf_hydro.f90` -- No changes (user decision: no singleton guard)
2. `bmi_wrf_hydro/src/hydro_stop_shim.f90` -- Kept in .so (user decision)
3. `bmi_wrf_hydro/tests/bmi_wrf_hydro_test.f90` -- No C binding deps
4. `bmi_wrf_hydro/tests/bmi_minimal_test.f90` -- No C binding deps
5. `bmi_wrf_hydro/bmiwrfhydrof.pc.cmake` -- Does not reference C bindings

## build.sh Edit Points (Line Numbers)

Based on the current file (334 lines), these are the exact edit locations:

| Line(s) | Current Content | Action |
|----------|----------------|--------|
| 9 | `#   src/    -> BMI wrapper source (bmi_wrf_hydro.f90)` | Already correct (only mentions bmi_wrf_hydro.f90) |
| 148-154 | Step 1b: Compile bmi_wrf_hydro_c.f90 | DELETE entire block |
| 195-198 | Shared link: includes `bmi_wrf_hydro_c.o` on line 197 | REMOVE line 197 |
| 216-219 | Static link_executable: includes `bmi_wrf_hydro_c.o` on line 219 | REMOVE line 219 |
| After test block (~line 324) | End of file | ADD install + readiness check block |

## CMakeLists.txt Edit Points (Line Numbers)

Based on the current file (447 lines):

| Line(s) | Current Content | Action |
|----------|----------------|--------|
| 276 | `src/bmi_wrf_hydro_c.f90` in add_library() | REMOVE this line |
| 394-398 | Install bmi_wrf_hydro_c_mod.mod | DELETE entire block |

## Open Questions

1. **Should build.sh clean target also remove stale installed .mod files?**
   - What we know: `./build.sh clean` currently only cleans `build/` directory, not `$CONDA_PREFIX/include/`
   - What's unclear: Whether clean should also uninstall from conda prefix
   - Recommendation: Keep clean scoped to build/ only. Add explicit `rm $CONDA_PREFIX/include/bmi_wrf_hydro_c_mod.mod` as a one-time cleanup in the install step.

2. **CMake _build/ directory: clean rebuild or incremental?**
   - What we know: CMake caches source file lists. Removing a source from CMakeLists.txt may not trigger full reconfigure.
   - What's unclear: Whether cmake --build will detect the CMakeLists.txt change and reconfigure automatically.
   - Recommendation: Delete `_build/` entirely and reconfigure from scratch to be safe. This takes ~30 seconds.

## Sources

### Primary (HIGH confidence)
- `bmi_wrf_hydro/build.sh` -- Direct examination of all build modes and link commands
- `bmi_wrf_hydro/CMakeLists.txt` -- Direct examination of library target and install rules
- `bmi_wrf_hydro/src/bmi_wrf_hydro_c.f90` -- Direct examination of C binding symbols (10 functions with `bind(C, name="bmi_*")`)
- `nm -D libbmiwrfhydrof.so` -- Live verification of 10 exported `bmi_*` symbols in both installed and build-dir copies
- `$CONDA_PREFIX/lib/pkgconfig/bmiwrfhydrof.pc` -- Live verification of pkg-config content
- `cmake --install _build` install manifest -- Confirms 7 installed files (3 symlinks, 3 .mod, 1 .pc)
- `.planning/research/PITFALLS.md` (Pitfall 8) -- C binding conflict analysis with babelizer's bmi_interoperability.f90
- `.planning/research/ARCHITECTURE.md` -- Relationship diagram between our C bindings and babelizer's interop layer

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY.md` -- Project research summary confirming C binding conflict as #1 blocker
- `.planning/phases/03-python-validation/03-02-SUMMARY.md` -- Phase 3 Plan 2 confirming actual Python test file names (test_bmi_python.py + conftest.py, NOT test_bmi_ctypes.py)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools are already installed and verified in the project
- Architecture: HIGH -- exact file changes, line numbers, and symbol lists verified by direct inspection
- Pitfalls: HIGH -- all pitfalls identified from actual project state (stale objects, CMake cache, install paths)

**Research date:** 2026-02-24
**Valid until:** Indefinite (build system patterns are stable; no external dependency changes expected)
