# Review before Stage 6C — 13 October 2026

Reviewed the current project files and saved evidence at the user's request. Stage 6C was not begun; production saves/journals and implementation code were not changed. Fresh backend suite: **83 tests OK (9.812 s)**, evidence `previews/pre6c-review/backend-tests.log`. The findings below remain unresolved despite that passing suite.

**Resolution — 13 October 2026:** The findings below are historical and have now been corrected/qualified. See `PRE_6C_FIXES.md` for implementation, fresh evidence and remaining scope.

## Findings

1. **High — City-life migration is not durable before serving the upgraded world.** `backend/store.py` runs `migrate_city_life()` for an existing save without `life_version=1`, but the subsequent transaction only runs for SQL versions below 7. Existing schema-7 saves therefore receive new place/goal state in memory without an immediate checkpoint or revision increment. A disposable schema-7 fixture reproduced: memory life_version=1, disk marker absent, revision unchanged, goal IDs different on the next reopen. A crash before the ordinary checkpoint repeats the migration. An unchanged revision also fails to establish a newer snapshot than historical receipts. Fix with a deliberate atomic migration/revision boundary and crash/replay tests before relying on upgrades.

2. **High — Distance LOD currently classifies, but does not budget work.** `pedestrian.gd` computes `lod_level` at 35/65 m and assigns `lod_phase`; neither controls animation processing, physics scheduling, avoidance neighbors or obstacle probes. All actors still run the same physics/animation code. No pedestrian mesh draw-distance cutoff is present. Saved 6B metrics show `far_avoidance_throttled_actors=0`. Implement actual budgeting in 6C, with collision and authoritative physical-report invariants tested; remove the claim that 6B already delivers it.

3. **Medium — Population tier 1 is a new-world benchmark option, not an existing-save upgrade.** `Store(..., tier=1)` creates a 50-resident world only when no world row exists. The normal service/launcher does not request that tier. `expand_tier1()` is available as a helper, but calls `disperse/stagger/retarget` on every resident, changing all 34 original residents' destinations/goals. A disposable fixture confirmed all 34 changed. Preserved positions/identities should not be described as preserved full state. Define an explicit supported expansion path that preserves active overrides/claims and pending replay; test a real 34→50 upgrade. Current 100-resident work is explicitly deferred to 6E in the handoff.

4. **Medium — Native seating acceptance does not assert seating.** Both 6A/6B scripts count seated actors but print failures=0 without requiring a seated actor or validating a sit→stand→walk sequence. Both saved metrics report zero seated actors. `bench_seated.png` visually shows an empty bench. Code for seats and animation transitions exists; the supplied evidence does not verify the complete interaction. Add a controlled physical seating/departure scenario. Strolling and facing are implemented; distinct looking-around/data-pad idle actions are absent.

5. **Medium — Performance and thermal claims exceed saved evidence.** The 6B harness samples only 40 frames per view, stores no physics timing or memory, records LOD counts once after the final camera view, and stores p95 only for street. Saved metrics currently read street 7.881/p95 10.644 ms/3,550 draw calls, plaza 7.264 ms/2,297 calls, skyline 10.466 ms/7,623 calls. Those differ from the handoff's cited 7.81/9.82/10.76 values. Comparing street draw calls with an earlier different view cannot establish LOD-caused savings. A frame cap and V-Sync exist, but temperature, fan noise, GPU duty and zero thermal throttling were not measured. Use sustained per-view measurements, relevant counters and precise scope; avoid thermal guarantees.

6. **Low — Handoff contains stale architecture details.** `PROGRESS.md` still says exactly 34 residents and describes schema 7 only, although current validation accepts 34/50 and life_version=1 extends the state. `city_life.py` calls its change 'Schema 8' while SQL schema remains 7. Saved 5E performance JSON also differs from its headline summary. Prefer current files and evidence over summary claims until corrected.

## Verified implementation

Distinct Exceptional Agent venue regions/cycles/dwell rates, deterministic venue spots and conversation-facing headings, staggered ordinary shifts/minute offsets, in-venue strolls, sitting animation integration, a 50-person seeded tier and dynamic demographic UI are present. Six existing regression logs end in passing results; these are inspected historical results, not fresh reruns of all harnesses during this review. The 83-test backend suite was freshly rerun with local socket permission and passed.

## Recommended order

First repair and test migration/replay and an explicit expansion contract. Then validate bench seating/departure. Correct status/performance claims. Proceed to 6C with actual scheduling/draw budgeting and repeat sustained native measurements; retention and the 100-person acceptance remain later work. This review does not mark 6A/6B fully verified or certify thermal behavior.
