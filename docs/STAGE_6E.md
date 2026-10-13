# Stage 6E — population benchmark and final review

13 October 2026. **Completed within the measured limits below.** Native 50/100-person acceptance, final regression checks and the requested MP4 review passed. All checks use disposable saves/journals. Production `runtime/world.sqlite3` and its journal were untouched.

## Delivered implementation

- Saved tiers are now **34 / 50 / 100** (25 / 41 / 91 civilians, always five police and four Exceptional Agents). SQL schema **8**, protocol **1**, life version **1** remain: the existing representation already supports these records.
- `backend/citizens.py` shares deterministic append-only tier expansion. `Store(..., tier=2)` atomically expands an existing 34- or 50-person city; default/older-tier launches never shrink a saved population. Existing residents, motion sequences, goals, overrides, claims, cores, receipts and command watermark survive verbatim. Failure rolls back both 34→50→100 steps together.
- New residents use the existing walkable promenade between z=14 and z=40 as additional market space. No city geometry changes. New tier-2 residents receive two dispersed spots per main venue, preserving short strolls while respecting district capacity; existing spots remain unchanged. Spacing stays 1.35 m. Upgrade placement also clears the preserved residents' actual mid-commute positions.
- **`Launch 100 Residents.command`** explicitly opts into durable expansion. Normal and 50-person launchers preserve an already saved 100-person city. Choose 100 deliberately; the normal launcher was not used to upgrade the production save.
- The longer native review exposed a real arrival mismatch: navigation can finish at a projected endpoint outside the backend's assigned-goal tolerance. `pedestrian.gd` now checks the original destination within 0.75 m, completes the final safe approach or reports a route wait, and stops residual horizontal motion. Backend arrival validation remains 0.95 m; it was not weakened. No teleport/fake arrival was introduced.

## Native measurements and supported limits

Apple M2 Pro / Metal Forward+, 1440×900. Each tier has four active eight-second samples after two-second view warmups. Scripted runs bypass the normal 60 FPS cap; recording is disabled during measurements. Every sample asserts the authoritative clock continues advancing and the bridge stays connected. Different disposable world identities produce different organic positions, so this is a per-tier sample, not a geometry-identical causal A/B comparison.

| View | 50 median / p95 ms | 100 median / p95 ms | 100 physics p95 ms | 100 median draw calls |
|---|---:|---:|---:|---:|
| Street | 7.652 / 10.054 | 11.478 / 13.496 | 4.909 | 4,069 |
| Plaza | 7.271 / 9.712 | 11.478 / 12.525 | 5.048 | 1,754 |
| Skyline | 9.917 / 10.830 | 14.276 / 20.981 | 4.977 | 9,034 |
| Control room | 10.561 / 14.123 | 19.892 / 29.114 | 5.735 | 10,393 |

**50 remains the recommended tier for 60 FPS headroom in these views.** 100 is a verified opt-in tier with a material cost: skyline and especially control-room views exceed the 16.67 ms budget. The 100-person control sample corresponds to roughly 50 FPS at its median and 34 FPS at its p95, not a constant 60 FPS guarantee. Individual larger stalls, dense-crowd waits, longer sessions and arbitrary camera angles remain possible; see JSON for p99/max/state distributions. No 1,000-person, thermal, fan-noise or unlimited-session claim is made.

At least one metre of physical displacement was observed for **49/50** and **94/100** residents during acceptance. Stationary residents may be resting or waiting; forcing everyone to move continuously would defeat their routines. All **583 / 983** venue spots had nearby connected navigation, and all **657 city collision shapes** remained. These route checks do not prove every simultaneous crowd configuration is deadlock-free.

Sampled peak Godot process RSS: **656,080,896 / 573,259,776 bytes** (50/100); backend **37,797,888 / 46,874,624**. These are 0.5-second OS RSS samples including startup, not complete/unique unified-memory usage; the lower 100-person RSS is not evidence that 100 costs less memory. Engine static/video counters and per-view LOD/state distributions are in `performance-1.json` and `performance-2.json`; do not add allocator/GPU/RSS counters as if disjoint.

After native shutdown/relaunch, 200 backend saves retained bounded full receipts and unchanged paused residents/clock. File sizes **22,036,480 / 39,628,800 bytes**; save median/p95 **9.644/11.728 ms** (50) and **17.585/20.112 ms** (100). These are offline backend costs, not gameplay frames or long-run plateau measurements. Stage 6D separately proves long-run pruning and retry reconciliation.

Independent backend cost sample (`backend-cost.json`): 400 synchronous 0.05-second steps, median/p95 **4.286/6.606 ms** (50) and **7.088/7.996 ms** (100). These separate worlds have no Godot reports/networking, so this isolates planner/state cost rather than measuring full active gameplay.

## Reproduction and evidence

Evidence directory: `docs/previews/stage6e/`. Use the project's `.venv` and Godot executable; no production DB argument.

| Command | Verified result |
|---|---|
| `.venv/bin/python -m unittest discover -s backend/tests -v` | **101 tests OK**, 22.960 s; `backend.log`. Four new tier-2 tests cover capacity/spacing, original work/receipt preservation, rollback and active claims. |
| `.venv/bin/python tools/check_stage5e_regressions.py --evidence-dir docs/previews/stage6e/regressions` | **All six pass**: foundation, Arbiter, policies, control, population and lifecycle. |
| `godot --headless --path godot --fixed-fps 60 --script res://scripts/check_obstacles.gd -- --no-simulation` | **14 checks, OBSTACLE_QA failures=0**. |
| `godot --headless --path godot --fixed-fps 60 --script res://scripts/check_navigation.gd -- --navigation-review --no-simulation` | **26 checks, NAVIGATION_QA passed=true**. |
| `godot --headless --path godot --editor --quit` | Clean import, exit 0; `import.log`. |
| `.venv/bin/python tools/measure_stage6e_backend.py` | Independent 50/100 planner/save cost recorded in `backend-cost.json`. |
| `.venv/bin/python tools/verify_stage6e_video.py` | **57.50 s**, 1440×900 H.264/yuv420p, 24 FPS, silent; full decode passes. |
| `.venv/bin/python tools/check_stage6e.py --tier 1` | Native **write/read failures=0**, 50 bodies, real UI command/physical arrival, bench sitting, active samples, audit/feed, exact paused relaunch, unchanged cores and SQLite integrity. |
| `.venv/bin/python tools/check_stage6e.py` | Same native acceptance at 100; **write/read failures=0**. |
| `godot --headless --path godot --fixed-fps 60 --script res://scripts/check_arrival.gd -- --no-simulation` | **ARRIVAL_QA failures=0**, five focused checks including the previously false projected arrival and real recovery. |

Initial test-harness issues were corrected: headless runs skip framebuffer captures, and restart probes serialize full floating-point precision rather than rounding the clock. The invalid disconnected native sample was rejected, diagnosed and superseded by the arrival fix and fresh passing active runs. Do not use earlier interrupted measurements as performance evidence.

## Final review recording

`tools/record_stage6e.py` runs a separate disposable 100-person scene through existing intervention controls. It captures live rendered frames with wall-clock timestamps and encodes a silent, chaptered H.264 MP4 at 1440×900, 24 FPS, with fast-start metadata. It shows the city/satellite, command acceptance, real body travel, committed audit/live feed, explicit release, city life, bench rest and Exceptional Agent inspection. The opening is explicitly paused; subsequent simulation runs at 1×. Initial close-range command and bench positions are declared acceptance-fixture placements before launch, not runtime teleports or the user's save.

Recording overhead is excluded from the native benchmark. MP4 timestamps preserve real elapsed capture timing rather than speeding up slow frames. The supplied **`Brother-Eye-Stage-6E.mp4`** is **57.50 seconds**, 1,380 encoded frames, with chapter markers. Full decoding and stream checks passed; sampled frames at 2/9/16/24/29/31/39/47/55 seconds were visually reviewed for the skyline/satellite, command acceptance, travel, live audit/feed, release, seating and inspection. `video-verification.json` records the final file. The first live capture was retained and normalized from JPEG full-range metadata to standard limited-range H.264 without changing duration/content. A later low-frame-count retry was discarded before replacing it (`discarded-recording-retry.log`); the recorder now retains capture metadata and rejects rates below 15 frames/s while preserving an existing MP4. Raw frames were temporary. Use `tools/verify_stage6e_video.py` to independently check the delivered file. This is an external review artifact, not a new in-app recording/rewind feature.

## Milestone handoff

Preserve one authoritative world/clock, no offline advance, physical arrival/assistance, immutable ideologies, local knowledge, held destination authority, serial/receipt/journal contracts, retention boundaries, city/ring/sky/satellite and supplied assets. Current rendering budgets and real collision/avoidance remain. This is a persistent deterministic simulation, not an LLM/council or a finished cinematic game.

The agreed Stage 1–6 implementation plan is delivered within the measured limits above. Further graphics/animation/audio polish, additional institutions or interactions, large-population optimization, external AI, renderer migration and distribution require separately scoped direction. Do not silently raise the population or rebuild assets to chase aspirational numbers.
