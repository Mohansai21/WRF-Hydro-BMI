# Phase 4: Documentation - Context

**Gathered:** 2026-02-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Write Doc 16 in `bmi_wrf_hydro/Docs/` — a comprehensive reference document covering the shared library architecture, babelizer readiness, minimal C binding rationale, and Python usage. This is a single markdown document following the project's established documentation style (Docs 1-15).

</domain>

<decisions>
## Implementation Decisions

### Document structure
- Follow the same numbered section pattern as existing docs (e.g., Doc 14 has 27 sections)
- Build-first flow: start with how to build the .so (CMake + build.sh), then architecture, then Python usage, then babelizer
- No quickstart/TL;DR at the top — dive straight into detailed sections
- Dedicated troubleshooting section (not inline) covering common errors, MPI issues, linker problems

### Audience & tone
- Dual audience: future self returning after months + new team member picking up the project
- Self-contained: include enough BMI context that someone can understand without reading other docs
- Continue the ML analogy style from existing docs (e.g., .so as a pre-trained model, pkg-config as model registry)
- Include rationale for key decisions (why minimal C bindings, why --whole-archive, why singleton) — helps readers understand trade-offs

### Diagrams & visuals
- Include all 4 diagram types:
  1. 5-layer architecture (WRF-Hydro → BMI wrapper → C bindings → shared library → Python/babelizer)
  2. Build pipeline flow (rebuild_fpic.sh → build.sh --shared → cmake → install → pkg-config)
  3. Data flow (Python → Fortran): how a Python get_value call travels through ctypes → bind(C) → BMI wrapper → WRF-Hydro state
  4. What we deliver vs babelizer: our deliverables (.so, .pc, .mod) vs auto-generated (bmi_interoperability.f90, Python package)
- Mix of ASCII art and Mermaid: ASCII for simple layouts, Mermaid for complex flows
- Include a full table of all 10 bind(C) functions with their signatures (C name, Fortran equivalent, parameters, return type)

### Babelizer readiness
- Describe what babel.toml would contain (conceptual), not a ready-to-use file
- Conceptual overview of what we deliver vs what babelizer generates (not a detailed side-by-side table)
- Include a babelizer readiness checklist (numbered pass/fail items: pkg-config works, .so has symbols, .mod files installed, etc.)
- Detailed SCHISM comparison section: our babelizer path vs SCHISM's NextGen path (full C bindings), side-by-side comparison of approaches

### Claude's Discretion
- Whether to include file tree diagrams (Claude decides if it adds clarity)
- Exact section ordering within the build-first flow
- How many ML analogies and where to place them
- Depth of each section (match existing doc patterns)
- Mermaid vs ASCII choice for each specific diagram

</decisions>

<specifics>
## Specific Ideas

- The doc follows the established style of Docs 7-15: emojis/icons throughout, ASCII/Mermaid diagrams, detailed explanations, ML analogies
- SCHISM comparison is important — readers need to understand why we took a different path than the only other Fortran BMI implementation they might find
- The babelizer readiness checklist should be actionable — someone should be able to run the checks themselves

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-documentation*
*Context gathered: 2026-02-24*
