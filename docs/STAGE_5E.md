# Stage 5E — Combined acceptance and measured baseline

Stage 5E verifies the existing four-agent implementation; no new authority, city geometry, models, schema or external AI is introduced. Schema 7 / protocol 1 remains current. See `PROGRESS.md` for the current completion status.

## Combined behavior coverage

Two additional tests in `backend/tests/test_agent_policies.py` place all four agents in one opportunity/conflict scenario. The Arbiter and Sovereign claim distinct recipients, the Attendant inspects, and the Martyr offers coordination. An override interrupts an existing claim; held authority, every core and all four states survive checkpoint/reopen and receipt replay without duplicate consequences. A competing claim made during the Martyr's meeting cannot be stolen, cannot share its evidence, and cannot earn cooperation trust.

The full suite also covers local-only knowledge and expiry, urgent personal recovery, unwilling/busy/held helpers, project cleanup, bounded learning, immutable cores, atomic rollback, migration and receipt deduplication. Scripted backend fixtures verify decisions; actual collision-backed motion is verified separately by the Godot integration harnesses, not inferred from backend fixtures.

## Reproducible checks

Run from the project root with `.venv/bin/python`:

- `-m unittest discover -s backend/tests -v`: 74 tests, OK (3.711 s); `previews/stage5e/backend-tests.log`.
- `tools/check_stage5e_regressions.py`: invokes existing 5B foundation/migration, 5C Arbiter, 5D all-policy coordination, 4E control/intervention, 3E population and Stage 2 lifecycle harnesses. Each uses disposable saves. Individual logs are in `previews/stage5e/`; the 5D child also refreshes its existing headless trace, copied into Stage 5E evidence.
- `tools/check_stage5e.py`: native 34-person running-world measurement and validation, schema/integrity/core preservation and owned-service shutdown. `native.log`, `native-state.json`, `performance.json`, `street.png`, `control-room.png`.
- `godot --headless --path godot --fixed-fps 60 --script res://scripts/check_obstacles.gd -- --no-simulation`: obstacle QA, failures=0; `obstacles.log`.
- `godot --headless --path godot --editor --quit`: import check; `import.log`.
- `tools/measure_agent_step.py`: 1,000 backend steps, four active policies, no renderer/websocket/physical-report cost; `backend-step-cost.json`.

The preceding Stage 5D native physical delegation and inspector-close checks remain applicable: `previews/stage5d/policies-native.log`. Stage 5E introduces acceptance tooling/tests only; the new native run additionally reviews the ordinary running scene. No production save or pending journal is edited. Initial backend sandbox socket denials were rerun with local socket permission.

## Measured baseline

Apple M2 Pro, Godot 4.7.2 Metal Forward+, 1440×900, 34 residents, time scale 1. Three eight-second samples, each after a two-second warmup; about 30 simulated seconds total.

| View | Median frame ms | p95 ms | p99 ms | Physics p95 ms | Draw-call snapshot |
|---|---:|---:|---:|---:|---:|
| Street | 9.128 | 10.382 | 11.263 | 2.331 | 5,368 |
| Skyline | 9.548 | 10.908 | 12.725 | 1.634 | 5,588 |
| Control room open | 10.055 | 13.373 | 13.937 | 2.354 | 6,138 |

Renderer video memory was approximately 500 MB in the main views and 543 MB with the feed open (decimal units). Engine static memory snapshots were approximately 142–145 MB; these counters are not total process/unified-memory consumption. Maximum frame interval across samples was 23.209 ms. Backend-only steps: median 1.396 / p95 1.653 / p99 3.136 / max 5.256 ms, zero over the 50 ms step budget. This small seeded benchmark excludes physical reporting and rendering; it is not a guarantee for busy social interactions.

Native screenshots were inspected: residents, city and live control-room feed render correctly. Default same-area starts, shared character silhouettes, and the welcome overlay remain intentional/current presentation. The samples are different views at different times, not a controlled measurement of feed-only overhead, GPU time, a long soak or a guarantee for 100–1,000 residents.

## Stage 6 handoff

1. Define supported performance targets, then measure explicit population tiers. Existing validation assumes exactly 34 residents; deliberately generalize identity/population migration and test it before increasing counts. Do not mutate the user's save for benchmarking.
2. Use profiling to select work: current scene has roughly 5,000–6,000 draw calls, so test geometry/material batching, detail/draw-distance budgets and animation/navigation scheduling. Preserve clock, local knowledge, authority, collision and persistence through detail changes.
3. Measure large-save load/migration and introduce event/receipt retention without breaking durable command replay.
4. Scope art/interaction polish, character variation, crowd distribution, foot placement, sound and lighting within measured budgets. Broader institutions, AI/council and renderer migration remain separate decisions.
5. Finish with native/regression acceptance and documented supported settings. Export/packaged-backend verification is required if distribution is requested.

Known limits: deterministic social-need behavior rather than general intelligence; proximity rather than optical sensing; no guarantee against every dense-crowd deadlock; bounded live caches but unbounded durable audit/receipt history; no large-population or distribution acceptance yet. No Stage 6 implementation is included in this checkpoint.
