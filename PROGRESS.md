# Brother Eye — durable project handoff

Updated **13 October 2026**, after Stage 6E. **Current checkpoint: the agreed Stage 1–6 plan is delivered within documented limits; no further stage is authorized/pending.** Read `docs/STAGE_6E.md` for the final 50/100-person acceptance, performance limits and MP4, `docs/STAGE_6D.md` for retention/retry semantics, and `docs/STAGE_6C.md` for rendering budgets. Production save/journal untouched.

**Fresh 6E acceptance:** 101 backend tests OK (22.960 s); native 50/100 write/read checks, all six broader regression suites, 14 obstacle and 26 navigation checks, five focused projected-arrival regression checks and clean import pass. The requested **57.50-second MP4** is `docs/previews/stage6e/Brother-Eye-Stage-6E.mp4` (1440×900, H.264, 24 FPS, silent, chaptered, fully decoded and sampled frames visually reviewed). 50 is recommended for 60 FPS headroom; 100 is opt-in and slower in skyline/control-room views. 100 control median/p95: **19.892/29.114 ms**. Evidence and exact commands: `docs/previews/stage6e/` and `docs/STAGE_6E.md`.

**Fresh 6D acceptance:** 97 backend tests, 8 focused retention tests, headless/native journal/retry/history/crash/relaunch checks, six broader regression harnesses and clean import pass. A disposable 50-person database stayed near 27.6 MB across 1,800 saves and compacted to ~22.4 MB. A synthetic 124 MB schema-7 save with 1,200 legacy snapshots upgraded in 1.404 s and compacted to 13.7 MB. These are storage/backend measurements, not gameplay or thermal guarantees. Evidence: `docs/previews/stage6d/`.

**Fresh 6C acceptance:** native paired 50-person A/B, near-image checks, live feed detail priority, 4D control-room and 5D physical-policy restart checks, 26 navigation checks, two-ring clearance plus obstruction negative control, and final import pass. **625 opaque surfaces → 110 LOD batches**; skyline draw calls **5,733 → 4,518**, primitives **2,109,202 → 1,336,242**, median **7.621 → 7.281 ms**, p95 **8.544 → 7.687 ms**. Paired rendering comparison is paused; the final feed sample runs simulation. Extra resident visual memory is a documented tradeoff. `docs/previews/stage6c/` has final logs/screens/JSON. Production save/journal untouched.

**Additional review, 13 October 2026:** `docs/previews/day-cycle/Brother-Eye-24-Hour-Cycle.mp4` shows a 06:00→next-day 06:00 lighting study (~60 s). `tools/record_day_cycle.py` / `day_cycle_review.gd` render offline without any backend, residents, save or journal. The normal game remains blue hour; new moon/star shader controls default to the original appearance. See `docs/DAY_CYCLE_REVIEW.md`. This video is separate from the live 100-resident acceptance video.

## Goal and approach

Build one persistent, explorable futuristic civilization. Ordinary people have local knowledge, needs, schedules, bounded memories and organic routines. Brother Eye inspects/evaluates and explicitly redirects travel. Four Exceptional Agents follow immutable ideologies through deterministic local decisions and voluntary interactions. Scale only to measured supported limits; 100 is a measured opt-in tier with skyline/control-room frame limits; 1,000 remains unverified.

Stack: Godot **4.7.2 / GDScript / Metal Forward+**, Python **3.12** (`.venv/bin/python`), SQLite WAL/FULL, websockets **15.0.1**, Blender **5.2.2** for assets. Machine: Apple M2 Pro, 16 GB; native review at 1440×900. Root: `/Users/ddi/Documents/ChatGPT/civilization_sim`.

Python owns the authoritative 20 Hz clock, needs and decisions; Godot owns actual collision/motion/poses and reports accepted progress. Snapshots ~4 Hz, checkpoints ~2 s; no offline advance. No LLM, council, Dyson structure or Unreal migration is implemented. Cinematic overhaul and external AI remain separately scoped/deferred.

## Completed checkpoints

| Stage | Delivered; detailed reference |
|---|---|
| 0–1 / atmosphere | Tools/provenance, dense district, helix/command towers, Brother Eye satellite, transit rings and clearance, sky design. `docs/BUILD_PLAN.md`, `docs/SKY_DESIGN.md`, `docs/ASSETS.md`. |
| 2 | Owned backend, one writer/world, save/restore, clock, atomic UUID receipts, pending journal, reconnect/replay. `docs/STAGE_2.md`. |
| 3A–3B | Supplied human/astronaut rigs; idle/walk/run/sit-down/seated-idle/stand-up; feet/hands/glove/run fixes. `docs/STAGE_3B.md`. |
| 3C–3E | Physical stepping/stairs/skywalk, routines/needs/recovery, 25 civilians+5 police, shared navigation/avoidance, atomic movement batches. `docs/STAGE_3E.md`, `docs/OBSTACLE_FIX.md`. |
| 4A–4E | Inspection, source-exact deterministic evaluation, explicit destination authority, physical blocked recovery, real-scene camera feed, SQL intervention audit, ACK-only landmark pulse, persistence integration. `docs/STAGE_4A.md` through `STAGE_4E.md`. |
| 5A–5E | Four canonical Exceptional Agents, local sensing/claims/assistance/trust, information, civic projects and voluntary coordination; combined conflicts/replay/rollback/persistence and measured 34-person baseline. `docs/STAGE_5A.md` through `STAGE_5E.md`. |
| 6A | Independent Exceptional quarters/cycles/dwell, organic venue spots/facing, staggered shifts/minute offsets, short strolls and bench poses. Physical sit→stand→walk and retained-activity strolling verified after corrections. `docs/PRE_6C_FIXES.md`. |
| 6E | Safe 100-resident expansion, final native 50/100 benchmarks/RSS/backend/save measurements, corrected projected arrival, physical/restore/regression acceptance and final MP4. `docs/STAGE_6E.md`. |
| 6D | Transactional event/receipt retention, durable sequenced retries, legacy compatibility, atomic schema-8 migration, audit pruning notice and offline compaction. `docs/STAGE_6D.md`. |
| 6C | Opaque spatial batching with regenerated mesh LODs, shorter decorative draw range, main/feed camera-aware actor detail; controlled native image/performance comparison. `docs/STAGE_6C.md`. |
| 6B | 50-person tier (41 civilian, 5 police, 4 exceptional), atomic existing-save expansion preserving original state, dynamic demographics, interactive cap and measured native baseline. Basic real animation/query budgets and mesh cutoff now implemented. `docs/STAGE_6B.md`, `docs/PRE_6C_FIXES.md`. |

Stage 5 policy: Arbiter severity/age/ID fairness irrespective of friendship; Attendant uncertain local information then useful trusted contacts; Martyr persistent self-owned civic project/voluntary helpers/solo fallback; Sovereign urgent own needs then fixed companion Mira. Learning changes tactics, never identity/core. No crime enforcement, political economy or general intelligence is claimed.

Shared interaction contract: sensing radius 8 m, vertical ≤2 m, observations expire after 600 simulated seconds; proximity, not optical sight. Claims and terminal effects are atomic. Actual ARRIVED/proximity/fresh reports and 5-second dwell gate one social−5 effect. Contact meetings use perpendicular 1.2 m offsets so an organiser leaves helper departure clearance. Busy/directed/urgent people may decline. Decline changes directed trust; blocked/departed/interrupted outcomes grant no aid. Pair cooldown 60 s. Project tasks expire if unclaimed and their need resolves or local evidence is lost; helpers' claims remain protected. Bounds: 16 observations/facts/memories, 8 relationships, one project ≤16 tasks, 64 live requests/history. Full audit/receipts now have finite windows; older unsequenced UUIDs retain compact compatibility metadata (see 6D).

## Architecture and decisions

| Files | Responsibilities |
|---|---|
| `backend/store.py` | **SQL schema 8, protocol 1, life_version 1**; checkpoint/events/receipts, durable command_serial, locking, validation, atomic migrations and pruning. Life migration commits revision+state+event before serving the upgraded world. Existing goal IDs/coordinates, physical state, overrides and actions survive; current legacy goal coordinates become bounded venue spots. Rollback and repeated reopen verified. |
| `backend/retention.py`, `tools/compact_database.py` | 128 full receipts; 512 recent + 512 significant events plus pinned migrations, pruning every 32 commits/startup. Stable receipt ordering; compact legacy retry ledger; offline locked VACUUM. |
| `backend/citizens.py`, `city_life.py` | Supported saved populations **34, 50 or 100**; deterministic identities, places/spots/postures, personal schedules, needs, goal planning, strolling and recovery. Shared append-only expansion adds 16 for tier 1 and 50 for tier 2, dispersing only newcomers and clearing old physical positions. Tier-2 newcomers have two spots per venue and additional existing promenade market space. Original residents remain verbatim. |
| `backend/service.py` | Authenticated localhost service, owned lifecycle, detached clock steps, atomic significant outcomes, command validation/rollback. `--population-tier=1/2` opts into 50/100 creation or atomic existing-save expansion; default preserves saved tier and smaller-tier launches never downgrade it. |
| `backend/exceptional.py`, `agent_behavior.py`, `agent_policies.py` | Canonical immutable profiles/cores, local sensing, decisions, voluntary willingness, claims/actions/learning, information/project transitions. |
| `backend/interventions.py`, `evaluation.py`, `history.py` | Destination-only held authority, pure snapshot evaluation, cursor-paged read-only intervention audit. |
| `godot/scripts/simulation_bridge.gd` | Owned Python process, snapshot/assessment consistency, sequenced UUID journal/ACK/replay and retired-command reconciliation, correlated history queries, population-tier flag forwarding. |
| `persistent_population.gd` | One body per durable ID; backend-goal application and physical batch reports. Starts movement from navigation state, including strolls retaining venue activity. Restored seated pose requires actual ARRIVED. |
| `pedestrian.gd`, `pedestrian_navigation.gd` | Full collision/avoidance/nav, flat-foot support and 25 cm steps, stall recovery, motion-driven animations, sitting transitions, follow/orbit camera. Arrival checks the original destination within 0.75 m rather than its projected navigation endpoint; backend still enforces 0.95 m. Stops residual horizontal velocity. Stand-up reports TRAVELLING and completes before pending travel. |
| `inspection_*`, `evaluation_view.gd`, `intervention_controls.gd`, `control_room.gd`, `command_feedback.gd` | Inspection/follow/evaluation/control UI, one actual-scene camera viewport, paged audit and deduplicated current ACK feedback. |
| `visual_budget.gd` | 48 m spatial cells, material/format/shadow/range-safe opaque batching; regenerated screen-error mesh LODs. Transparent/custom/dynamic landmarks remain separate. Reference sources retain zero render layers for QA/A-B. |
| `city.gd`, `geometry.gd`, `city_composition.gd`, `helix_tower.gd` | Existing city scene/geometry/landmarks. `godot/scenes/city.tscn` main scene. |
| `tools/check_pre6c_fixes.py`, `pre6c_fixes_check.gd`, `backend/tests/test_life_upgrades.py` | New disposable physical/sustained acceptance and six upgrade safety tests. Standard 6A/6B Python checks now use this stronger shared acceptance. |

Current distance budget: ≤35 m full animation updates, 35–65 m ~20 Hz, >65 m ~10 Hz; sit/stand transitions stay full rate. Step probes every 1/2/4 ticks. **Gravity, collision body motion, crowd avoidance, navigation and physical reports stay at normal physics rate.** Pedestrian mesh cutoff 140 m. Main/live-feed camera animation priorities and generated static mesh LODs are verified in 6C; 100-person acceptance passes with the frame limits in `docs/STAGE_6E.md`; it is not a constant 60 FPS guarantee. No data-pad animation asset is supplied; standing has a small gradual facing variation.

## Launching and controls

- `Launch Brother Eye.command` opens/preserves the saved tier. **`Launch 50 Residents.command`** opts into a durable 34→50 expansion once. This launcher was tested only against disposable saves; using it normally upgrades the user's city.
- **`Launch 100 Residents.command`** opts into durable 34/50→100 expansion. 50 remains recommended for 60 FPS headroom; 100 is slower in broad skyline/control-room views. No launcher was used on the real save during acceptance.
- Normal save `runtime/world.sqlite3`; journal `runtime/world.sqlite3.pending.json`; ready files `runtime/session-*.json`. **Never edit/delete these for a test or fix.** Tests use temporary directories and `--world-db=…`.
- Review launchers share the real save; `Review Exceptional Agents.command` opens that filter. F2 clock/save, F3 follow, F4 details, F5 inspector, F6 evaluation, F7 control room, [ / ] previous/next person. Selecting a character does not itself command travel.
- Follow is unlocked: WASD/EQ, Shift, click-drag/two-finger orbit, R reset. Inspector suspends camera input, not simulation time. Held destination overrides must be released before autonomy resumes.

## Fresh verified evidence — current corrected checkpoint

Current 6E evidence and exact commands/results: `docs/STAGE_6E.md`, `docs/previews/stage6e/`. **101 backend tests OK**, native 50/100 write/read passes, all six regressions pass, 14 obstacles/26 navigation/five focused arrival checks and clean import pass. 94/100 bodies moved over 1 m during acceptance; 983 venue routes connect. Video fully decoded and reviewed.

Earlier 6D evidence and exact commands/results: `docs/STAGE_6D.md`, `docs/previews/stage6d/`. Final backend suite: **97 OK (18.464 s)**; focused retention: **8 OK**; write/read headless and native checks: **failures=0**; all six broader regression harnesses pass. Final headless/full-suite runs cover the later bounded migration batching and typed request-hash refinements; the native run covers presentation/reconnect behavior.

The following pre-6C evidence remains historical: `docs/previews/pre6c-fixes/`; it is not a new 6D performance rerun claim.

| Command | Actual result |
|---|---|
| `.venv/bin/python -m unittest discover -s backend/tests -v` | **89 OK, 10.610 s**; `backend-tests.log`. Upgrade durability/idempotence, rollback, original residents/overrides/receipts/claims preserved. |
| `.venv/bin/python tools/check_pre6c_fixes.py` | **PRE6C_FIXES failures=0**; physical bench arrival/sitting/standing/departure, venue stroll, real budget counters, service launch-time 34→50 expansion, SQL integrity and owned shutdown. `native.log`, PNGs and JSON. |
| `.venv/bin/python tools/check_stage5e_regressions.py --evidence-dir docs/previews/pre6c-fixes/regressions` | **All six pass**: foundation, Arbiter, policies, control/interventions, population, lifecycle. `regressions.log` and subdirectory logs. |
| `godot --headless --path godot --fixed-fps 60 --script res://scripts/check_obstacles.gd -- --no-simulation` | **14 checks, failures=0**, `obstacles.log`. |
| `godot --headless --path godot --fixed-fps 60 --script res://scripts/check_navigation.gd -- --navigation-review --no-simulation` | **26 checks, passed=true**, `navigation.log`. |
| `godot --headless --path godot --editor --quit` | Exit 0, clean import; `import.log`. Later native scripts also load/execute successfully. |

Native 50-person, 1440×900, Metal Forward+: three ten-second samples after two-second warmups. Street **9.882 ms median / 11.151 p95**, plaza **9.559 / 11.077**, skyline **10.532 / 12.854**. Physics p95 **2.954 / 3.045 / 3.103 ms**; draw-call snapshots **2,544 / 1,818 / 7,498**. Video-memory counter **504,823,808 bytes**, engine static ~149–151 MB (not total process/unified memory). Actual 1.2 s budget counts: animation **72 near / 11 far**, step probes **72 / 18**. Bench screenshot reviewed. See `performance.json` for frames/p99/max/per-view LOD counts.

Interactive mode has a 60 FPS cap/V-Sync. Benchmark scripts bypass the cap. **Temperature, fan noise, GPU duty and thermal throttling were not measured; no thermal guarantee exists.** Different camera/timing samples cannot prove causal draw-call savings. Historical 6A/6B screenshot scripts did not establish seated behavior; current stronger acceptance supersedes them.

## Requirements and remaining limits

Preserve one authoritative world/clock; no offline advance/teleport/fake arrival/recovery. Keep immutable UUID retries, atomic receipt/state/event/watermark commits, pending journal order, stale goal/sequence rejection and revision protection against historical ACK snapshots. Exact original ACKs are guaranteed within the retained receipt window; older consumed serials reconcile current state without re-execution or invented original outcomes. Legacy UUIDs retain compact request hashes/result metadata. New mutations must keep contiguous serials and world-bound deterministic IDs; never simply delete legacy retry identities. Coalesce only unsent compatible movement/view updates; never change a sent command ID's payload.

Brother Eye destination-only authority persists until release, including after arrival, outranking autonomous needs. Urgent physiology precedes ideological work. Core/identity/companion membership remains immutable; no memory/core-edit command. Local knowledge must remain local and bounded.

Preserve city composition/ring clearance, sky/satellite prominence, supplied models and licenses, character fixes and touchpad camera. Keep 25 cm physical/nav step contract, flat-foot support and larger-obstacle detours; no guarantee against all dense-crowd deadlocks. No dedicated step animation or foot IK is claimed; sliding/deformation polish remains.

Control room is one 640×360 actual-scene feed, four fixed cameras, ≤10 updates/s while open/connected. No recording/rewind/PTZ. Evaluation covers validated needs/reported waits, not crime or prolonged-stall inference; automatic intervention is absent. Detailed audit is finite and explicitly labeled after pruning. Standard sequenced traffic has bounded hot history; external clients issuing new legacy unsequenced commands can grow the compact compatibility ledger. SQLite reuses freed pages; an already-large file needs the optional offline compactor to shrink. No absolute byte cap or unlimited-play performance guarantee is claimed.

Project files are still untracked; no committed baseline was verified. Preserve unrelated edits; no destructive Git cleanup. No applicable AGENTS.md found. Use `rg`. No external AI/council, engine migration, asset rebuild, worldbuilding addition or distribution/export acceptance has been authorized by this repair task.

## Remaining scope / next action

The agreed stages are complete within measured limits. **Do not automatically begin more work or upgrade the user's saved city.** Deliver the MP4 and final review, then await the user's next direction.

- Recommended tier: 50 for measured 60 FPS headroom. 100 is deliberately opt-in, with skyline/control-room samples exceeding a 16.67 ms frame budget; no 1,000-person or universal crowd-deadlock/thermal guarantee.
- Reproduce final native acceptance with `.venv/bin/python tools/check_stage6e.py` (100) or `--tier 1` (50). Both use disposable saves, real bodies, UI interventions, sitting, active samples and app relaunch. `tools/measure_stage6e_backend.py` isolates backend cost; `tools/record_stage6e.py` records a separate disposable review. `tools/verify_stage6e_video.py` checks the MP4. Recording is excluded from benchmarks.
- The first live capture supplies the delivered MP4; a later low-rate retry was rejected before replacement. Final normalized file, stream/decode evidence and reviewed frame captures are in `docs/previews/stage6e/`. Raw frames were temporary; this adds no in-app recording/rewind feature.
- Further institutions, interactions, graphics/material/lighting/audio/foot-placement polish, larger-population optimization, optional LLM/council, Dyson worldbuilding or renderer migration require separately scoped direction. Export packaging/backend/assets/attribution remain unverified unless distribution is requested.
- Preserve one world/clock, immutable identities/cores, physical outcomes and held authority, safe journal/serial/retention contracts, original city/rings/satellite/sky and supplied assets. Never use or compact production saves for tests.
