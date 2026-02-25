# Phase 5: Library Hardening - Context

**Gathered:** 2026-02-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Rebuild `libbmiwrfhydrof.so` without conflicting C binding symbols, verify all .mod files are installed, and confirm pkg-config discovery works — making the shared library ready for the babelizer's auto-generated interop layer. No BMI wrapper logic changes. No new features.

</domain>

<decisions>
## Implementation Decisions

### C Binding Removal
- Delete `bmi_wrf_hydro_c.f90` entirely from the repo (not just exclude from link line)
- Delete the Python ctypes test (`tests/test_bmi_ctypes.py`) — it depends on C symbols being removed; Phase 7 will have Python tests via the babelized package
- Keep `hydro_stop_shim.f90` in the .so — it's needed by the BMI wrapper's finalize(), unrelated to C bindings
- Update CLAUDE.md and Doc 16 references to `bmi_wrf_hydro_c.f90` during this phase (don't defer to Phase 9)

### Build System Scope
- Update both `build.sh` and `CMakeLists.txt` to remove C binding compilation/linking
- Remove C binding from ALL build modes (static, --fpic, --shared), not just --shared
- `./build.sh --shared` should auto-install the rebuilt .so to `$CONDA_PREFIX/lib/` (overwriting old one)
- Do NOT add singleton guard to `bmi_wrf_hydro.f90` in this phase — defer to Phase 8 if bmi-tester needs it

### Regression Strategy
- Run all three checks: 151-test suite + minimal smoke test + manual `nm -D` symbol check
- Test in both modes: static linking (default build) AND dynamic linking (--shared build)
- If `nm` shows unexpected `bmi_` symbols in the .so, block and fix — do not proceed
- Interactive validation during execution (no persistent log files needed)

### Install Verification
- Verify both .mod files present: `ls $CONDA_PREFIX/include/bmiwrfhydrof.mod` and `wrfhydro_bmi_state_mod.mod`
- Verify pkg-config flags are correct (not just that it returns something) — check -L and -l paths
- Keep version at 1.0.0 (ABI didn't change, we only removed symbols)
- Run a final composite "babelizer readiness check" as the Phase 5 exit gate: nm (no bmi_ symbols), .mod files present, pkg-config correct, ldd clean

### Claude's Discretion
- Exact ordering of build script modifications
- Whether to consolidate build.sh cleanup into one edit or multiple
- How to structure the composite readiness check (inline script vs separate function)

</decisions>

<specifics>
## Specific Ideas

- The composite readiness check at the end should verify all 4 babelizer prerequisites in one block: `nm -D` (no conflicting symbols), `.mod` files (both present), `pkg-config` (correct flags), `ldd` (no missing deps)
- Research SUMMARY.md identifies the C binding conflict as the #1 blocker — this phase resolves it

</specifics>

<deferred>
## Deferred Ideas

- Singleton guard (`active_instance_count` in `bmi_wrf_hydro.f90`) — defer to Phase 8 if bmi-tester needs it
- Comprehensive Doc 18 — Phase 9 (PYMT-04)

</deferred>

---

*Phase: 05-library-hardening*
*Context gathered: 2026-02-24*
