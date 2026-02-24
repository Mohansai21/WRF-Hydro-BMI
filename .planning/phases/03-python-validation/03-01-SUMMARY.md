---
phase: 03-python-validation
plan: 01
subsystem: build-infra
tags: [iso_c_binding, bind-c, c-interop, shared-library, fortran, ctypes, singleton]

# Dependency graph
requires:
  - phase: 02-shared-library-install
    provides: libbmiwrfhydrof.so shared library installed to $CONDA_PREFIX with pkg-config discovery
provides:
  - bmi_wrf_hydro_c.f90 C binding module exposing 10 BMI functions as flat C symbols
  - Updated build systems (CMake + build.sh) compiling C binding into libbmiwrfhydrof.so
  - bmi_wrf_hydro_c_mod.mod installed to $CONDA_PREFIX/include/
affects: [03-02-python-test, babelizer]

# Tech tracking
tech-stack:
  added: [ISO_C_BINDING bind(C), c_to_f_string/f_to_c_string helpers]
  patterns: [singleton C binding pattern (module-level bmi_wrf_hydro + is_registered guard), string marshalling between C/Fortran via character-by-character copy]

key-files:
  created:
    - bmi_wrf_hydro/src/bmi_wrf_hydro_c.f90
  modified:
    - bmi_wrf_hydro/CMakeLists.txt
    - bmi_wrf_hydro/build.sh

key-decisions:
  - "Singleton pattern (module-level the_model + is_registered flag) instead of box/opaque-handle pattern -- WRF-Hydro cannot support multiple instances"
  - "f_to_c_string as subroutine with buffer length parameter (not function returning array) to prevent stack overflow with large strings"
  - "Character-by-character copy in c_to_f_string instead of transfer() to avoid compiler-specific issues"
  - "bmi_get_component_name takes buffer size n as integer(c_int), value parameter for C calling convention"

patterns-established:
  - "Singleton C binding: module-level type(bmi_wrf_hydro), save :: the_model with logical guard, all bind(C) functions delegate to the_model%method()"
  - "String marshalling: c_to_f_string scans for c_null_char then allocates and copies; f_to_c_string copies trimmed content and appends c_null_char"
  - "C symbol naming: bmi_register, bmi_initialize, bmi_update, bmi_finalize, bmi_get_* -- flat underscore-separated names for ctypes"

requirements-completed: [CBIND-01, CBIND-03, CBIND-04]

# Metrics
duration: 5min
completed: 2026-02-24
---

# Phase 3 Plan 1: C Binding Layer Summary

**Minimal ISO_C_BINDING module (bmi_wrf_hydro_c.f90, 335 lines) exposing 10 BMI functions as flat C symbols in libbmiwrfhydrof.so, with singleton guard and string marshalling helpers**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-24T01:08:46Z
- **Completed:** 2026-02-24T01:14:11Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created bmi_wrf_hydro_c.f90 (335 lines) with 10 bind(C) functions, 2 string helpers, and singleton guard pattern
- Updated both build systems (CMake and build.sh) to compile C binding into libbmiwrfhydrof.so
- All 10 bmi_* C symbols exported and verified via nm -D on both local and installed .so
- 151/151 Fortran BMI tests still pass (zero regression from adding C binding source)
- Installed bmi_wrf_hydro_c_mod.mod to $CONDA_PREFIX/include/ for downstream consumers
- Zero unresolved symbols in installed .so (verified via ldd)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create bmi_wrf_hydro_c.f90 with bind(C) wrappers and string helpers** - `7249c94` (feat)
2. **Task 2: Update build systems and verify C symbols in .so** - `66b371d` (feat)

**Plan metadata:** (pending)

## Files Created/Modified
- `bmi_wrf_hydro/src/bmi_wrf_hydro_c.f90` - Minimal C binding module: 10 bind(C) functions (register, initialize, update, finalize, get_component_name, get_current_time, get_var_grid, get_grid_size, get_var_nbytes, get_value_double) + 2 string helpers (c_to_f_string, f_to_c_string) + singleton guard
- `bmi_wrf_hydro/CMakeLists.txt` - Added bmi_wrf_hydro_c.f90 to SHARED library source list and bmi_wrf_hydro_c_mod.mod to install targets
- `bmi_wrf_hydro/build.sh` - Added Step 1b compilation of C binding layer, included .o in shared library link and static executable link steps

## Decisions Made
- Used singleton pattern (module-level `the_model` with `is_registered` guard) instead of box/opaque-handle pattern, matching WRF-Hydro's inability to support multiple instances
- Implemented `f_to_c_string` as a subroutine with explicit buffer length parameter rather than a function returning an array, to prevent stack overflow risks and give the caller control over buffer size
- Used character-by-character copy in `c_to_f_string` instead of `transfer()` intrinsic, avoiding compiler-specific issues with character array transfer
- `bmi_get_component_name` takes buffer size `n` as `integer(c_int), value` to follow C calling convention for scalar parameters

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- WSL2 clock skew warnings during CMake build ("Clock skew detected") -- harmless, known WSL2/NTFS issue documented in CLAUDE.md
- CMake install initially failed due to empty `$CONDA_PREFIX` when `conda activate` didn't persist across bash tool calls -- resolved by running configure+build+install in a single bash shell invocation

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- **Python test unblocked:** 10 flat C symbols (bmi_register through bmi_get_value_double) are now callable via Python ctypes
- **Library installed:** libbmiwrfhydrof.so with C symbols at $CONDA_PREFIX/lib/, .mod files at $CONDA_PREFIX/include/
- **No blockers:** All prerequisites for Plan 03-02 (Python pytest test) are satisfied

## Self-Check: PASSED

- FOUND: bmi_wrf_hydro/src/bmi_wrf_hydro_c.f90
- FOUND: bmi_wrf_hydro/CMakeLists.txt
- FOUND: bmi_wrf_hydro/build.sh
- FOUND: $CONDA_PREFIX/lib/libbmiwrfhydrof.so
- FOUND: $CONDA_PREFIX/include/bmi_wrf_hydro_c_mod.mod
- FOUND: 7249c94 (Task 1 commit)
- FOUND: 66b371d (Task 2 commit)

---
*Phase: 03-python-validation*
*Completed: 2026-02-24*
