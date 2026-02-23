# Phase 2: Shared Library + Install - Context

**Gathered:** 2026-02-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Build `libwrfhydrobmi.so` from the fPIC-rebuilt WRF-Hydro libraries (Phase 1 output), install it to the conda prefix with pkg-config discovery, and verify the babelizer can find it. Two build paths: CMake (for install/packaging) and build.sh (for fast dev iteration). The 151-test BMI suite must pass when linked against the shared library.

</domain>

<decisions>
## Implementation Decisions

### build.sh integration
- New `--shared` flag: `./build.sh --shared full` produces `libwrfhydrobmi.so`
- `--shared` auto-implies `--fpic` (uses build_fpic/ libraries automatically)
- Shared library output goes to `bmi_wrf_hydro/build/` (same directory as existing .o and test executables)
- `--shared` auto-runs the 151-test suite linked against the .so after building (build + verify in one command)

### CMake project structure
- CMakeLists.txt lives in `bmi_wrf_hydro/CMakeLists.txt` (alongside build.sh and rebuild_fpic.sh)
- Follow bmi-example-fortran's cmake pattern closely (maximize babelizer compatibility)
- CMake depends on pre-built fPIC libraries (user runs rebuild_fpic.sh first, then cmake)
- Separate cmake build directory: `bmi_wrf_hydro/_build/` (follows bmi-example-fortran convention, keeps cmake artifacts separate from build.sh artifacts)

### Install mechanism
- `cmake --install` is the ONLY install path (build.sh does NOT install)
- cmake defaults to `$CONDA_PREFIX` as install prefix (detects active conda env)
- Post-install auto-verification: checks pkg-config works and ldd shows no missing deps
- pkg-config library name: `bmiwrfhydrof` (matches bmi-example-fortran's `bmiheatf` pattern for babelizer compatibility)

### Claude's Discretion
- Exact CMakeLists.txt structure and cmake variables
- pkg-config .pc file template details
- How to link the 22 static libraries into the .so (link order, circular dep handling)
- Post-install verification script implementation
- .gitignore updates for _build/

</decisions>

<specifics>
## Specific Ideas

- Follow bmi-example-fortran's pattern as closely as possible — it's the known-working babelizer reference
- Two build paths serve different purposes: build.sh for fast dev iteration, cmake for install/packaging
- rebuild_fpic.sh → build.sh --shared → cmake --install is the full pipeline

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-shared-library-install*
*Context gathered: 2026-02-23*
