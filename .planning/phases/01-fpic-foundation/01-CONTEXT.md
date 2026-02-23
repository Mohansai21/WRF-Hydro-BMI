# Phase 1: fPIC Foundation - Context

**Gathered:** 2026-02-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Rebuild WRF-Hydro's 22 static libraries with position-independent code (`-fPIC`) so they can be linked into a shared object in Phase 2. The existing BMI 151-test suite must still pass against the rebuilt libraries (no regression). No WRF-Hydro source files are modified.

</domain>

<decisions>
## Implementation Decisions

### CMake modification policy
- Do NOT modify WRF-Hydro's CMakeLists.txt or any upstream files
- Create a wrapper script (`rebuild_fpic.sh`) in `bmi_wrf_hydro/` that invokes cmake with `-DCMAKE_POSITION_INDEPENDENT_CODE=ON`
- This preserves the "never modify WRF-Hydro source" rule — the wrapper passes flags externally

### Build output directory
- Rebuilt fPIC libraries go into a SEPARATE directory (`build_fpic/` under `wrf_hydro_nwm_public/`) — do NOT overwrite the existing `build/`
- Both versions coexist: original `build/` for reference, `build_fpic/` for shared library work

### Rebuild script design
- Script name: `rebuild_fpic.sh` (lives in `bmi_wrf_hydro/`)
- Full rebuild script: handles clean, cmake with -fPIC, build all 22 libs — one command, done
- Script also auto-runs the 151-test regression suite after building (build + verify in one step)

### build.sh update
- Add a `--fpic` flag to `build.sh` that links against `build_fpic/` libraries instead of `build/`
- Default behavior (no flag) still uses original `build/` libraries — backward compatible
- This gives flexibility to test with either library set

### Claude's Discretion
- Exact cmake invocation flags beyond -fPIC (optimization level, build type)
- readelf/objdump verification details
- Script error handling and output formatting
- Whether to use symlinks or absolute paths for library references

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. User wants clean separation between original and fPIC builds, with the wrapper script keeping WRF-Hydro upstream untouched.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-fpic-foundation*
*Context gathered: 2026-02-23*
