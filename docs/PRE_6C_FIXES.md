# Stage 6A/6B corrections — verified 13 October 2026

All findings in `PRE_6C_REVIEW.md` have been addressed within the scope below. Production `runtime/world.sqlite3` and its journal were not opened or modified. Stage 6C's remaining tuning and Stage 6D/6E are not declared complete.

## Migration and expansion safety

SQL schema remains 7; `life_version=1` versions the city-life extension. Existing schema-7 saves now receive the life upgrade, revision increase, state checkpoint and migration event in one transaction before the upgraded world is exposed. Existing goals, IDs, physical state, overrides and Exceptional actions are preserved. A current legacy goal coordinate is retained as one bounded venue spot, allowing in-flight physical reports/journaled commands to keep valid context. Failed migration rolls back state and event together; subsequent reopen does not regenerate goals. Historical receipts remain byte-for-byte stored and replayable, and their earlier revision cannot replace the upgraded snapshot.

`Store(path, tier=1)` now also upgrades an existing 34-person city once. Expansion preserves every original resident dictionary, active assistance claims, history and receipts; only the 16 new residents receive new spots/routines. Previously expansion regenerated all residents' destinations. Invalid population tiers are rejected. An existing 50-person save remains at 50 when opened normally.

`Launch 50 Residents.command` explicitly requests the upgrade through the Godot bridge and service's `--population-tier=1` option. Launching it changes the user's saved city to 50; this was only exercised on disposable saves during verification. The ordinary launcher preserves the existing tier.

## Physical life and distance budgets

Fixed two frontend bugs found by the new physical test: a stroll retains its venue activity but still needs physical travel, so navigation now starts from navigation state; a departing seated actor now reports TRAVELLING during stand-up rather than claiming arrival at a distant new goal. Stand-up completion switches to idle before starting the pending route, preventing a completed transition from blocking later animation choices.

Native acceptance requires actual travel to a bench, sit-down finishing in seated idle, stand-up after an acknowledged destination command and another metre of walking. It also verifies a real stroll with retained socializing activity. The seated screenshot was visually reviewed. Standing idles now include a small gradual facing variation; no separate data-pad animation asset is claimed.

Distance levels now budget actual work: root-camera distances ≤35 m advance animation every physics tick, 35–65 m about 20 Hz, >65 m about 10 Hz. Sit/stand transitions continue every tick. Step-probe calls run every 1/2/4 ticks. Torso/foot collision, gravity, crowd avoidance, navigation and physical reporting continue at the normal physics rate. Pedestrian meshes have a 140 m visibility cutoff. This deliberately does **not** decimate collision bodies or guarantee large-population performance; multi-camera animation priorities and geometry LOD tuning remain 6C work.

A 1.2-second native sample recorded **72 near vs 11 far animation evaluations**, and **72 near vs 18 far step probes**, with collision and crowd avoidance still enabled. `check_stage6a.py` and `check_stage6b.py` now call the stronger shared physical/sustained acceptance rather than treating three-second screenshots or forty-frame counters as proof of behavior.

## Actual evidence

| Command | Result |
|---|---|
| `.venv/bin/python -m unittest discover -s backend/tests -v` | **89 tests OK, 10.610 s**. Includes six new upgrade tests for rollback, idempotence, overrides/receipts and active-claim preservation. `backend-tests.log`. |
| `.venv/bin/python tools/check_pre6c_fixes.py` | **PRE6C_FIXES failures=0**. Launch-time existing 34→50 upgrade, physical seating/departure/stroll, real distance-budget counters, SQLite integrity and owned shutdown. `native.log`/PNGs/`performance.json`. |
| `.venv/bin/python tools/check_stage5e_regressions.py --evidence-dir docs/previews/pre6c-fixes/regressions` | **All six pass**: foundation, Arbiter, remaining policies, control/interventions, population, lifecycle. `regressions.log` and `regressions/`. |
| Godot `check_obstacles.gd -- --no-simulation` | **14 checks, failures=0**; `obstacles.log`. |
| Godot `check_navigation.gd -- --navigation-review --no-simulation` | **26 checks, passed=true**; `navigation.log`. |
| `godot --headless --path godot --editor --quit` | Clean import, exit 0; `import.log`. |

Evidence directory: `docs/previews/pre6c-fixes/`. Earlier failed native attempts exposed the seated departure bug; the retained final native log is the passing corrected run. Original review evidence remains historical. No claims of a fresh 100-person, export, temperature, fan or thermal-throttling test.

## Sustained native sample

Apple M2 Pro, Metal Forward+, 1440×900, 50 residents, running simulation. Three ten-second samples after two-second per-view warmups. Benchmarks bypass the interactive 60 FPS limit; V-Sync settings remain configured. Snapshot draw calls are not a controlled causal comparison with previous camera views.

| View | Median ms | p95 ms | p99 ms | Physics p95 ms | Draw-call snapshot |
|---|---:|---:|---:|---:|---:|
| street | 9.882 | 11.151 | 11.797 | 2.954 | 2544 |
| plaza | 9.559 | 11.077 | 11.354 | 3.045 | 1818 |
| skyline | 10.532 | 12.854 | 15.033 | 3.103 | 7498 |

Renderer video memory: 504,823,808 bytes. Engine static-memory snapshots: roughly 149–151 MB; these are not total process memory. Per-view LOD counts, frame counts and maximum intervals are in the JSON. The cap reduces unnecessary rendering demand, but temperature, fan noise, GPU duty cycle and thermal throttling were not measured. The former “cool/silent/zero throttling” guarantees are withdrawn. Skyline geometry remains a draw-call bottleneck to examine in 6C.

## Next checkpoint

Proceed to the remaining Stage 6C profiling/visual LOD work using this measured 50-person baseline. Retention (6D) must preserve command deduplication and pending replay. Tier 2/100-person work and final native benchmark/handoff remain 6E. Do not claim 100-person support or finished Stage 6 based on this repair checkpoint.
