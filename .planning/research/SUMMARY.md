# Project Research Summary

**Project:** WRF-Hydro BMI — Phase 2 (Babelizer & PyMT Integration)
**Domain:** Fortran BMI shared library babelization into PyMT Python package
**Researched:** 2026-02-24
**Confidence:** HIGH

## Executive Summary

This project babelizes an existing, fully-tested Fortran BMI shared library (`libbmiwrfhydrof.so`) into a Python package (`pymt_wrfhydro`) usable from PyMT. The foundation is complete: the BMI wrapper (41 functions, 151/151 tests passing), shared library (4.8 MB, installed), pkg-config discovery (`bmiwrfhydrof.pc`), and .mod files are all in place. Phase 2 is primarily an integration and packaging task, not core development. The recommended toolchain is: babelizer 0.3.9 (conda-forge) to generate the `pymt_wrfhydro` skeleton, followed by a manual Meson build migration (replacing the generated setuptools scaffolding), following the pattern established by the CSDMS team's own reference implementation `pymt_heatf`. Six new conda packages are required: `babelizer`, `meson-python`, `meson`, `ninja`, `cython`, and `python-build`.

The single most important operational rule is `pip install --no-build-isolation`. Default pip build isolation breaks Fortran-in-conda environments in three distinct ways: it cannot find the pkg-config file, it installs build tools from PyPI instead of conda-forge (causing compiler mismatches), and it does not inherit the conda environment's `$PKG_CONFIG_PATH`. This is documented in babelizer issue #73 and is the most likely first failure point. Every MPI-related pitfall flows from a single root cause: WRF-Hydro requires MPI, but neither babelizer nor PyMT initializes it. The solution is to add `mpi4py` as a package requirement in `babel.toml` and document that users must `from mpi4py import MPI` before importing `pymt_wrfhydro`.

The existing C binding layer (`bmi_wrf_hydro_c.f90`, compiled into `libbmiwrfhydrof.so`) will conflict with babelizer's auto-generated `bmi_interoperability.f90` because both define `bind(C, name="bmi_initialize")` with different signatures (the babelizer version takes a `model_index` integer; ours does not). This is a hard blocker that must be resolved before babelization: the shared library must be rebuilt without `bmi_wrf_hydro_c.o` in the link line. The C binding layer was test infrastructure only and is superseded by the babelizer's more complete 41-function interop layer.

## Key Findings

### Recommended Stack

The existing `wrfhydro-bmi` conda environment is missing exactly six packages for Phase 2: `babelizer`, `meson-python`, `meson`, `ninja`, `cython`, and `python-build`. PyMT (`pymt=1.3.2`) is needed only for the final validation phase and carries a large dependency tree (esmpy, landlab, scipy, shapely, xarray), so it should be installed in a separate step. All other required tools (gfortran 14.3.0, OpenMPI 5.0.8, NetCDF-Fortran 4.6.2, bmi-tester 0.5.9, numpy 2.2.6, pkg-config) are already present.

**Core technologies:**
- **babelizer 0.3.9** (conda-forge): Generates the `pymt_wrfhydro` package skeleton from `babel.toml` — only stable release; generates setuptools scaffolding but Meson migration is required for NumPy 2.x compatibility
- **meson-python 0.19.0**: PEP 517 build backend for the generated package — replaces deprecated `numpy.distutils`; used by the `pymt_heatf` reference implementation
- **meson 1.10.1 + ninja**: Build system that discovers `libbmiwrfhydrof.so` via pkg-config, compiles Fortran interop + Cython, links the Python extension — the CSDMS ecosystem standard
- **cython 3.2.4**: Compiles the babelizer-generated `.pyx` wrapper to a C extension — provides the Python-to-C bridge
- **mpi4py**: Loads MPI with `RTLD_GLOBAL` flags before the Cython extension imports `libbmiwrfhydrof.so` — prevents Open MPI plugin segfaults; must be added to `[package].requirements` in `babel.toml`
- **pymt 1.3.2** (validation phase only): PyMT framework for plugin registration and model registry (`from pymt.models import WrfHydroBmi`)

### Expected Features

**Must have (table stakes):**
- `babel.toml` configuration file — single input to `babelize init`; defines `library = "bmiwrfhydrof"`, `entry_point = "bmi_wrf_hydro"`, `package.name = "pymt_wrfhydro"`
- `pymt_wrfhydro` package builds with `pip install --no-build-isolation .` — gatekeeper for everything downstream
- `from pymt_wrfhydro import WrfHydroBmi` imports without error — proves shared library loads from Python
- `initialize/update/finalize` cycle works end-to-end from Python with Croton NY data — core IRF validation
- `get_value` returns numpy float64 arrays for all 8 output variables — data pipeline integrity
- `set_value` accepts numpy arrays for all 4 input variables — forcing injection
- All grid metadata queries work for all 3 grid types (LSM 1km, routing 250m, channel vector)
- `bmi-tester` passes Stage 1 (info/time) and Stage 2 (variable info) — official CSDMS compliance

**Should have (differentiators):**
- `bmi-tester` Stage 3 passes (grids + values) — includes vector grid coordinate validation for grid 2
- Croton NY reference validation — Python output matches Fortran reference values
- PyMT metadata files (`meta/WrfHydroBmi/` with `info.yaml`, `api.yaml`, `parameters.yaml`, `run.yaml`) — enables `from pymt.models import WrfHydroBmi`
- MPI guard in `pymt_wrfhydro/__init__.py` that auto-loads `libmpi.so` with `RTLD_GLOBAL` — user experience hardening
- Example Jupyter notebook showing the full IRF cycle with Croton NY data

**Defer (v2+):**
- SCHISM babelization — different pathway (NextGen, not PyMT); out of scope
- `parameters.yaml` covering all 200+ WRF-Hydro namelist options — start with 5-10 essential parameters (timestep, duration, output frequency)
- conda-forge recipe submission — premature; use `pip install` locally for now
- MPI parallel execution (np > 1) — serial-first; babelizer does not handle MPI process management
- Automated CI/CD — WRF-Hydro's 22-library build is too complex for generic CI infrastructure

### Architecture Approach

The babelizer generates a 4-layer call stack: Python user code calls the Cython extension (`wrfhydrof.cpython-3xx.so`), which calls the babelizer-generated Fortran C-interop layer (`bmi_interoperability.f90`, ~818 lines, box/handle pattern with 2048 instance slots), which calls our BMI module (`bmiwrfhydrof`), which calls WRF-Hydro internals (22 static libs baked into `libbmiwrfhydrof.so`). The babelizer does NOT use our existing C binding layer (`bmi_wrf_hydro_c.f90`); it generates its own complete interop layer. The two C binding definitions must not coexist in the shared library.

**Major components:**
1. **`babel.toml`** (we write, 1 file) — declares `library`, `entry_point`, `package.name`; the naming chain drives all auto-generated code and must be exact
2. **`bmi_interoperability.f90`** (auto-generated, ~818 lines) — multi-instance box pattern wrapping all 41 BMI functions with ISO_C_BINDING; compiled into Cython extension, links against `libbmiwrfhydrof.so`
3. **`wrfhydrof.pyx`** (auto-generated) — Cython wrapper; dispatches `get_value`/`set_value` by type (our `get_var_type` returns `"double precision"`, so only `bmi_get_value_double` is called)
4. **`meson.build`** (auto-generated) — discovers `libbmiwrfhydrof.so` via `dependency('bmiwrfhydrof', method: 'pkg-config')`; drives Fortran + Cython compilation
5. **`meta/WrfHydroBmi/`** (we write) — PyMT model metadata YAML files; enables PyMT model registry integration
6. **`libbmiwrfhydrof.so`** (pre-existing, Phase 1.5 artifact) — must be rebuilt WITHOUT `bmi_wrf_hydro_c.o` before babelization to remove conflicting C symbols

### Critical Pitfalls

1. **C binding symbol conflict** — `bmi_wrf_hydro_c.f90` compiled into `libbmiwrfhydrof.so` defines `bind(C, name="bmi_initialize")` which collides with babelizer's generated interop (same name, different signature). Must rebuild `.so` without `bmi_wrf_hydro_c.o` BEFORE running `babelize init`. Verify with: `nm -D libbmiwrfhydrof.so | grep " T bmi_"` — should return nothing.

2. **pip build isolation breaks pkg-config and compilers** — Default `pip install .` creates an isolated env where `$CONDA_PREFIX/lib/pkgconfig` is invisible and build tools come from PyPI. Always use `pip install --no-build-isolation .` with all build deps pre-installed via conda. Documented in babelizer issue #73.

3. **MPI RTLD_GLOBAL segfault** — Loading `libbmiwrfhydrof.so` from Python without first loading `libmpi.so` with `RTLD_GLOBAL` causes Open MPI's MCA plugin system to fail with a segfault. Solution: add `from mpi4py import MPI` as the first import, or add an auto-load guard in `pymt_wrfhydro/__init__.py`. Add `mpi4py` to `[package].requirements` in `babel.toml`.

4. **Missing `wrfhydro_bmi_state_mod.mod`** — `bmi_wrf_hydro.f90` defines two modules in one file; both `.mod` files must be installed to `$CONDA_PREFIX/include/` before babelization or the interop layer fails to compile with "Cannot read module file" errors.

5. **Working directory chaos** — WRF-Hydro reads namelists from the current working directory; bmi-tester and PyMT also manipulate `cwd`. Use absolute paths in all BMI config files and test with bmi-tester's `--root-dir` flag from the start.

## Implications for Roadmap

Based on combined research, the natural phase structure follows the dependency chain: resolve the C binding conflict (prerequisite), write `babel.toml` and generate the skeleton, build the package, validate, then add PyMT metadata.

### Phase 1: Pre-Babelization Library Hardening

**Rationale:** The C binding conflict and missing .mod files are hard blockers that must be resolved before `babelize init` produces a usable package. This phase costs roughly 1-2 hours but prevents costly debugging later. The singleton instance guard should also be added here to prevent confusing behavior if bmi-tester creates multiple model objects.

**Delivers:** A clean `libbmiwrfhydrof.so` with no conflicting C symbols; all .mod files verified in `$CONDA_PREFIX/include/`; singleton instance guard added to `bmi_wrf_hydro.f90`; pkg-config discovery verified

**Addresses:** Foundational prerequisite — all downstream phases depend on this

**Avoids:** C binding conflict (P8), missing .mod (P13), singleton crash (P2)

**Actions:**
- Remove `bmi_wrf_hydro_c.o` from the link line in `build.sh --shared` and rebuild
- Verify `nm -D libbmiwrfhydrof.so | grep " T bmi_"` returns nothing
- Confirm `wrfhydro_bmi_state_mod.mod` installed alongside `bmiwrfhydrof.mod`
- Add `active_instance_count` guard to `bmi_wrf_hydro.f90` (returns BMI_FAILURE on second `initialize()`)
- Verify `pkg-config --cflags --libs bmiwrfhydrof` returns correct flags

### Phase 2: Environment Setup + babel.toml + babelize init

**Rationale:** Install the 6 missing conda packages, write `babel.toml`, and run `babelize init`. Writing `babel.toml` correctly is critical — the naming chain (`library`, `entry_point`, `package.name`) drives all auto-generated code. The values must exactly match the Fortran module name and derived type name in `bmi_wrf_hydro.f90`.

**Delivers:** `pymt_wrfhydro/` directory with all auto-generated files; `babel.toml` committed to repo

**Uses:** babelizer 0.3.9, meson-python 0.19.0, meson 1.10.1, ninja, cython 3.2.4

**Avoids:** Wrong babelizer version (P5), missing mpi4py requirement (P10)

**Key decision:** `library = "bmiwrfhydrof"`, `entry_point = "bmi_wrf_hydro"` (exact Fortran module and type names). Add `mpi4py` to `[package].requirements`.

### Phase 3: Build pymt_wrfhydro Package

**Rationale:** The Meson build is the most likely failure point. All environment conditions must hold simultaneously: correct gfortran, correct pkg-config path, no build isolation. Isolating this as its own phase means failure here is easy to diagnose and retry without touching other work.

**Delivers:** `pymt_wrfhydro` installed in conda site-packages; `from pymt_wrfhydro import WrfHydroBmi` works

**Avoids:** pkg-config not found (P1), PyPI build deps (P4), gfortran version mismatch (P9), editable install failure (P14)

**Commands:**
```bash
export PKG_CONFIG_PATH=$CONDA_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH
export FC=$CONDA_PREFIX/bin/gfortran
cd pymt_wrfhydro
pip install --no-build-isolation .
python -c "from mpi4py import MPI; from pymt_wrfhydro import WrfHydroBmi; print('OK')"
```

### Phase 4: BMI Compliance Validation (bmi-tester)

**Rationale:** Official CSDMS validation of the Python-side BMI interface. Runs 3 stages: info/time, variable info, grids/values. Some failures are expected by design (`get_value_ptr` returns `BMI_FAILURE`; grid topology functions not applicable for our grid types). Must distinguish expected non-implementation from genuine bugs.

**Delivers:** bmi-tester results documented; genuine failures fixed; expected non-implementations documented with justification

**Avoids:** MPI RTLD_GLOBAL (P3 — solved by mpi4py import), working directory chaos (P7 — use absolute paths)

**Research flag:** Stage 3 behavior for the vector grid (grid 2, channel network) is unverified. `get_grid_node_count`, `get_grid_x`, `get_grid_y` for vector grids need live verification against bmi-tester Stage 3 test code. Also verify that `get_grid_edge_count` returning 0 vs BMI_FAILURE for rectilinear grids matches bmi-tester expectations.

### Phase 5: PyMT Metadata + Full Integration

**Rationale:** Adding the `meta/WrfHydroBmi/` YAML files enables `from pymt.models import WrfHydroBmi` — the final step toward PyMT coupling readiness. Install PyMT separately from the babelizer toolchain to isolate its large dependency tree. Start `parameters.yaml` with 5-10 essential parameters only.

**Delivers:** `meta/WrfHydroBmi/` with 4 YAML files + template config; `from pymt.models import WrfHydroBmi` works; Croton NY validation from Python matches Fortran reference output; example Jupyter notebook; Documentation (Doc 18)

**Uses:** pymt 1.3.2, bmipy 2.0.1

**Avoids:** Library conflicts (P15 — install pymt with conda, not pip)

**Research flag:** PyMT's esmpy dependency requires ESMF compiled against MPI. Whether conda-forge's esmpy is compiled against OpenMPI 5.0.8 is unknown. Run `conda install --dry-run pymt=1.3.2` before committing to this phase.

### Phase Ordering Rationale

- Phase 1 before everything: The C binding conflict is a hard blocker; attempting babelization with it present wastes all downstream work
- Phase 2 before Phase 3: `babelize init` must run before `pip install` (it generates the files that Meson compiles)
- Phase 3 before Phase 4: bmi-tester requires an installed, importable package
- Phase 5 last: PyMT metadata is purely additive; the core value (Python-callable BMI) is delivered in Phases 3-4
- PyMT installed after babelizer toolchain: Large dependency tree should be isolated to avoid conflicts with Meson build tools

### Research Flags

Phases likely needing deeper research during planning:

- **Phase 3 (Meson build):** The `--no-build-isolation` + conda flag interaction with meson-python 0.19.0 has not been tested on this exact environment. If Meson cannot find gfortran despite `FC` being set, additional `native-file` configuration may be needed.
- **Phase 4 (bmi-tester vector grid):** bmi-tester Stage 3 unstructured grid tests for our grid 2 (channel vector network) have not been run. The test expectations for vector grids may differ from what our wrapper returns for CHLON/CHLAT coordinates.
- **Phase 5 (PyMT + MPI):** PyMT pulls in `mpi4py` transitively (via esmpy). There may be MPI version conflicts between `mpi4py`'s expected MPI ABI and OpenMPI 5.0.8. Test with `conda install --dry-run pymt` first.

Phases with standard patterns (skip research-phase):

- **Phase 1 (library rebuild):** Rebuild command is well-understood; just remove `bmi_wrf_hydro_c.o` from the link line in `build.sh --shared`. No new patterns needed.
- **Phase 2 (babel.toml):** Template is verified and documented in FEATURES.md; naming chain is confirmed correct against `bmi_wrf_hydro.f90`. Mechanical transcription, not research.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All packages verified against conda-forge metadata and pymt_heatf reference; version compatibility matrix confirmed for Python 3.10 + NumPy 2.2.6 |
| Features | HIGH | Babelizer workflow verified against babelizer source templates and pymt_heatf; bmi-tester stages verified against actual test source code |
| Architecture | HIGH | Verified against pymt_heatf (meson.build, bmi_interoperability.f90, Cython pyx); 4-layer data flow confirmed; C binding conflict identified from direct source inspection |
| Pitfalls | HIGH (critical), MEDIUM (minor) | Critical pitfalls (C conflict, pkg-config, MPI) sourced from official docs and filed issues; minor pitfalls (WSL2 paths, editable install) inferred from known patterns |

**Overall confidence:** HIGH

### Gaps to Address

- **bmi-tester vector grid behavior:** Stage 3 grid tests for the channel vector network (grid 2) have not been run live against our wrapper. The `get_grid_edge_count` and `get_grid_face_count` return values (0 vs BMI_FAILURE) for rectilinear grids also need live verification.
- **PyMT + OpenMPI 5.0.8 compatibility:** Whether conda-forge's esmpy (a PyMT dependency) is compiled against OpenMPI 5.0.8 is unknown. Run `conda install --dry-run pymt=1.3.2` before Phase 5.
- **Singleton guard side effects:** Adding `active_instance_count` to `bmi_wrf_hydro.f90` means any test that leaks without calling `finalize()` would block subsequent tests. The counter reset in `finalize()` is essential and must be verified against the existing 151-test suite.
- **Meson native-file configuration:** If the conda gfortran is not found automatically by Meson, a `native-file` may be required. This is undocumented in the pymt_heatf reference (which assumes gfortran is on PATH).

## Sources

### Primary (HIGH confidence)

- csdms/babelizer (develop branch, cloned 2026-02-24) — template source, meson.build template, v0.3.10.dev0 vs v0.3.9 differences; confirmed Meson migration path
- pymt-lab/pymt_heatf (cloned 2026-02-24) — reference Fortran babelized package; verified meson.build, bmi_interoperability.f90, heatmodelf.pyx, pyproject.toml
- conda-forge package metadata (queried 2026-02-24) — babelizer 0.3.9, pymt 1.3.2, meson-python 0.19.0, bmi-tester 0.5.9 dependency graphs and compatibility
- csdms/bmi-tester (cloned 2026-02-24) — stage_1, stage_2, stage_3 test source code; confirmed which BMI functions are tested at each stage
- Babelizer issue #73 — PyPI vs conda compiler conflict; canonical `--no-build-isolation` fix
- Open MPI docs Section 11.4 + issue #3705 — RTLD_GLOBAL requirement for dynamic loading from Python
- Local: `bmi_wrf_hydro/src/bmi_wrf_hydro_c.f90` — confirmed conflicting bind(C) symbol names
- Local: verified `pkg-config --cflags --libs bmiwrfhydrof` returns correct flags (2026-02-24)
- Local: `.planning/research/CSDMS_BABELIZER_OFFICIAL.md` — babelizer architecture

### Secondary (MEDIUM confidence)

- babelizer.readthedocs.io — babel.toml format, Fortran example workflow
- meson-python.readthedocs.io — editable install limitations for Fortran extensions
- numpy.org distutils migration guide — numpy.distutils deprecation timeline and removal for Python 3.12+
- mpi4py.readthedocs.io — MPI initialization and RTLD_GLOBAL handling patterns
- CSDMS discussion #26 — BMI start time convention (start time = 0.0)
- Meson issue #14461 — PKG_CONFIG_LIBDIR discarded in some Meson scenarios

### Tertiary (LOW confidence)

- WSL2 + Meson long-path truncation — inferred from known Fortran character(len=80) limits; no specific Meson/WSL2 reports found
- Singleton model_array behavior with second WrfHydroBmi() instance — inferred from template code and WRF-Hydro module global pattern; no live test of double-init scenario documented

---
*Research completed: 2026-02-24*
*Ready for roadmap: yes*
