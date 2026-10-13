# Stage 6C — Distance budgeting and static visual LOD

Implementation checkpoint, 13 October 2026. Final acceptance results and measured values are recorded below. Stage 6D retention and 6E 100-person scaling remain separate work.

## Implementation

- `visual_budget.gd` consolidates compatible single-surface opaque meshes by material, vertex format, shadow setting, original visibility range and 48 m three-dimensional spatial cells. Transparent glass, custom shaders/holograms, skinned meshes, the rotating satellite and Brother Eye command axis remain independent.
- Batching preserves source transforms/materials. Generated meshes regenerate Godot screen-error LOD indices with `ImporterMesh.generate_lods`; this avoids forcing every original high-detail triangle into distant views. The first prototype reduced calls but worsened frame time, so it was replaced by the smaller-cell/mesh-LOD implementation.
- `geometry.gd` / `city_composition.gd` separate small non-colliding decorations (<4 m maximum dimension) from structural boxes. Detail batches stop rendering at 220 m with a 20 m hysteresis margin. Structural silhouettes, facades, transit rings, sky and satellite retain their existing ranges/composition. A margin is hysteresis, not alpha fading.
- Animation/query budgets from the corrected 6B checkpoint remain: near/full physics-tick animation, medium ~20 Hz, far ~10 Hz; step probes every 1/2/4 ticks; sit/stand transitions full rate. Pedestrian visual cutoff remains 140 m. Full collision/gravity/navigation/avoidance/reporting continue.
- `control_room.gd` publishes the currently live feed camera position; actors use the nearer of the main and live feed cameras for animation/probe detail. Closing/offlining the feed removes its priority, preserving hidden feed suspension.

No schema, backend decision, population, authority or asset download changes. The 50-person test world is disposable. Source meshes remain resident with zero render layers for controlled A/B and exact original-bound QA. This trades additional visual memory/startup processing for fewer draw submissions; it is not a memory optimization. Source render layers are restored by the test-only toggle. Production enables the budget by default.

## Acceptance design

`tools/check_stage6c.py` / `stage6c_check.gd` create a temporary 50-person world and compare three identical paused camera views with budgeting disabled/enabled. Each sample is eight seconds after a two-second warmup; draw calls and primitives are sampled across frames rather than inferred from one snapshot. The harness records frame median/p95/p99/max, physics p95 and engine memory counters.

The near views also have sampled PNG intensity-difference checks and visual review. The test asserts all 657 collision shapes remain, paused time does not advance, signal meshes remain independent, skyline draw calls decrease, all four cores remain unchanged and a nearby control-room feed retains full actor detail while the main camera is far. A final control-room sample runs the simulation. Reopen validates durable state/SQLite integrity and service ownership shutdown.

`composition_check.gd` excludes the newly merged visual batch bounds and inspects the retained individual source bounds; it continues to verify the actual two approved transit ellipses and obstruction clearance. Aggregate batch AABBs must not be mistaken for solid buildings. Physical route and control-room regressions remain required.

## Limits

This checkpoint verifies 50 residents, not 100. A draw-call reduction does not imply an equal FPS increase: V-Sync, GPU triangles, lighting and physics can dominate. A/B uses the same paused geometry, while the separate control-room sample includes running behavior; do not compare its physics numbers as feed-only overhead. The retained reference meshes affect memory counters. No temperature, fan, GPU-duty or throttling telemetry is collected. No worst-case population/long-soak/export guarantee is claimed.

The retained exact source nodes support bounds/debug QA; frame-visible geometry is the generated LOD batches. Small distant decorations can disappear while primary architecture remains. Compare the provided near/far screenshots when adjusting thresholds in future.


## Verified results — final corrected implementation

Native Apple M2 Pro / Metal Forward+, 1440×900, same paused 50-person world for paired views. Source **625 surfaces → 110 spatial batches**. Original physics and all **657 collision shapes** remain. Final image sampled mean differences were street **0.072/255**, plaza **0.046/255**, skyline **0.134/255**; street baseline/optimized and skyline screenshots were visually reviewed. The sample checks are a coarse regression guard, not proof of pixel identity at every view.

| View | Median ms, original → budget | p95 ms | Median draw calls | Render primitives |
|---|---:|---:|---:|---:|
| street | 7.565 → 7.519 | 7.843 → 7.840 | 3741 → 3241 | 1053618 → 911774 |
| plaza | 7.111 → 7.121 | 7.390 → 7.384 | 2666 → 2307 | 871941 → 903191 |
| skyline | 7.621 → 7.281 | 8.544 → 7.687 | 5733 → 4518 | 2109202 → 1336242 |

Skyline: ~21% fewer draw calls, ~37% fewer rendered primitives, ~4.5% lower median interval and ~10% lower p95 in this paired sample. Plaza rendered primitives increased slightly despite fewer calls; measure both counters when tuning. These observations are sample-specific, not a promised FPS gain everywhere. The separate optimized running control-room sample is in the JSON, including physics cost; no feed-only overhead inference.

Renderer memory includes both retained reference meshes and generated LODs: final feed-open video-memory counter **659,357,696 bytes**. Memory is a tradeoff, not a reduction claim. The street/plaza/skyline samples are paused rendering comparisons, not a replacement for the earlier running-crowd benchmark or Stage 6E's 100-person test.

| Command | Actual result / evidence |
|---|---|
| `.venv/bin/python tools/check_stage6c.py` | **STAGE6C_CHECK failures=0**; native A/B/image/range/immutable-core/control-room-priority/integrity/shutdown assertions. `native.log`, `performance.json`, paired PNGs and `control-room.png`. |
| `.venv/bin/python tools/check_stage4d.py` | Write/read **failures=0**; live/closed/offline feed behavior, paged audit, ACK/replay and app restoration; `control.log`. |
| `.venv/bin/python tools/check_stage5d.py` | Write/read **failures=0**; actual information/companion/coordination/helper travel, unique aid, backend crash and app restore; `policies.log`. |
| Godot `check_navigation.gd -- --navigation-review --no-simulation` | **26 checks, passed=true**; `navigation.log`. |
| Godot `composition_check.gd -- --no-simulation` | **Two approved transit rings, 21,678 individual bounds, zero intersections**, `composition.log`. |
| Godot `composition_check.gd -- --no-simulation --inject-ring-obstruction` | Expected nonzero exit and `passed=false`: injected physical/rendered obstruction still detected. `clearance-negative.log`. |
| `godot --headless --path godot --editor --quit` | Exit 0, clean final import; `import.log`. |

Evidence root: `docs/previews/stage6c/`. Backend was not changed in 6C; the prior **89 passing tests** remain historical evidence, not a fresh rerun claim. Early prototypes failed with a primitive-mesh API mismatch and later a frame-time regression; final retained logs correspond to the corrected passing implementation. No production save or pending journal was opened.

**Stage 6C is complete for the implemented 50-person visual-budget scope.** Next is Stage 6D retention, then Stage 6E 100-person/scaling acceptance. Do not begin those automatically.
