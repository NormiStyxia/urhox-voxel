# Night FX code review — 2026-11-15

Scope: Fireflies.lua, NightBraziers.lua, exact SkyAtmosphere/GameSettings wiring and two new SurfaceShaders/material XML pairs.

Reviewed: asynchronous callback lifetime/ownership; independent legacy flame fallback; no default-white material binding; single firefly geometry section; CPU bounds cover shader motion; real Terrain safety probes and height envelope; quality rebuild/disposal; per-frame clock before the sky 5Hz gate; point-light color reuse and phase synchronization; log/probe closed path; untouched legacy shader/material.

No blocking code findings remain. Corrected the offline flight test to use each particle's actual packed phase rather than the first particle's phase; reran the complete check successfully. Zero native GPU validation is claimed.

Verification receipts:
- python3 validation/night-fx/check.py: PASS, check.log.
- python3 validation/night-fx/lsp_check.py: PASS, 4 files Error=0, lsp.log. Uses already installed maker-lua-lsp EmmyLua stdio binary.
- git diff --check: PASS, diff-check.log.
- Official generate_resource_meta: all 5 requested resource sidecars generated.
- Start/end git status --short inspected; final full output status-final.log. Existing and concurrent changes outside task preserved.

Remaining integration risks: Web GPU compilation/visible brightness/Bloom, whole-patch recycling breath during movement, first-load and patch replacement frame cost, native Variant marshaling allocations, exact draw calls across engine views/passes. Low-frequency whole-patch reconstruction is the explicit ground-safety tradeoff; normal frames do not update per-particle vertices. Shader compilation errors that occur after a successful Material callback are not detectable through the verified Lua API.
