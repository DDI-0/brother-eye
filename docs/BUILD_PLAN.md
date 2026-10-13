# Staged build plan

Each stage ends with a demonstrable result and an explicit report of verified behavior and remaining limitations. Present that checkpoint before starting the next stage so the user can steer the work.

## 0 — Toolchain and source preparation (complete)

- Inspect the local hardware and available tools.
- Install standard Godot 4 and Apple Silicon Blender; use existing Python 3.12 in a project virtual environment.
- Preserve source downloads, reference images, provenance, and license notices.
- Verify tool execution and Python's SQLite support.
- Establish folders and record exact installed versions.

Acceptance: tools execute, the isolated Python environment works, supplied assets have an inventory, and no application features are represented as already implemented.

## 1 — Explorable city (complete; ready for user review)

- Build a compact neighborhood from reusable geometry informed by the supplied tower, machinery, antenna, dome, arch, and truss references.
- Infer street-level entrances, shops, alleys, utilities, sidewalks, stairs, railings, and pedestrian connections.
- Apply midnight navy (#071525), steel blue (#12375B), electric blue (#007BFF), cyan (#00D9FF), and ice white (#C9F4FF), with restrained emissive areas.
- Include a Brother Eye command tower and an original orbital satellite silhouette with a recessed blue eye.
- Provide ground movement, collision, free-fly observation, and configurable mode switching (initially Ctrl+Shift+B).
- Select the renderer using a local visual/performance check; measure frame rate on the M2 Pro rather than promising a megacity performance target.

Acceptance: a runnable neighborhood, coherent pedestrian scale, working camera modes, no required external downloads, and a visual review checkpoint. This stage contains no claim of autonomous citizen simulation.

Delivered checkpoint: `docs/STAGE_1.md`, final preview images, and a double-click launcher. All 13 automated controller/collision checks pass. Native Metal / Forward+ rendering was exercised and captured at 1440×900 on the M2 Pro. The result is a procedural architectural blockout; detailed imported art and interiors remain future work.

## 1B — City composition (implemented; ready for visual review)

Dense blocks and perimeter development now surround the existing landmarks, with an extended skyline, varied crowns, two elevated transit loops and two tower skybridges. Ring routes reserve clearance from buildings and rooftop structures. The original walking-route checks pass, and a separate geometry check reports zero building intersections with the transit loops. See `docs/STAGE_1B.md` and `docs/previews/stage1b/` for scope, validation and previews.

## 2 — Persistent application and simulation foundation (complete; ready for review)

- Python authoritative world clock and state, versioned WebSocket messages, SQLite migrations and save/load.
- Application-owned backend lifecycle: run only while the application is open, save on exit, recover from interruptions, resume on launch.
- Log events and handle reconnects without duplicate worlds or clocks.

Acceptance: move/change state, close, relaunch, and verify restoration; verify backend shutdown and reconnect behavior.

Delivered checkpoint: `docs/STAGE_2.md`. Ten backend tests and five isolated Godot launches verify atomic persistence, camera/clock restoration, no offline advancement, reconnect, backend crash recovery, pending journal replay after frontend interruption, one durable world and app-owned service shutdown. Existing 13 movement/collision checks still pass. Population begins in Stage 3.

## 3 — Animated population (split into reviewable steps)

### 3A — Civilian appearance (implemented; ready for visual review)

Prepare one supplied human for the city: scale/origin, a civilian outfit, skin/hair/materials and restrained civic details. Export an editable Blender source and a Godot GLB, and review front, back, close-up and in-city appearance. See `docs/STAGE_3A.md` and the isolated `civilian_review.tscn` scene. This is a static appearance checkpoint, with no rigging or animation claim.

### 3B — Rigging and animation (implemented; ready for motion review)

One civilian and one supplied astronaut have biped rigs and six baked clips, with transferred walk/sit motion, original idle/run, floor adjustments and a separate interactive review. Playback/transition and exported geometry checks pass. See `docs/STAGE_3B.md` for measured limits, previews and remaining deformation polish. The noncommercial supplied run is excluded. Foot sliding against actual travel must be checked with navigation in 3C.

### 3C — Navigation (implemented; ready for city motion review)

One civilian traverses the promenade, both stair ramps, skywalk, terrace and street crossing in the existing city review. Collision-backed routes recover around an unexpected obstruction; unreachable destinations wait safely. Movement drives animation cadence, and the run stance is corrected for actual travel. Open `Review Navigation.command`. Full-route, entry-point, turning and stride checks pass; see `docs/STAGE_3C.md` for evidence and remaining foot/crowd polish.

### 3D — Persistent behavior (implemented; ready for behavior review)

Add durable identities, needs, schedules, limited knowledge and saved routines. Verify behavior and restoration across app restarts using the Stage 2 service.

Delivered checkpoint: one persistent civilian in the normal city, backend-owned needs and daily decisions, four known destinations, bounded memories and collision-backed travel. Schema 2 migrates existing saves without replacing their world. Backend checks and four Godot launches verify recovery, arrival, routines, pause, restoration and replay; Stage 2’s five-launch checks still pass. Open `Review Behavior.command`; see `docs/STAGE_3D.md` for evidence and scope.

### 3E — Population (implemented; ready for population review)

Expand to 25 civilians and 5 police with appropriate appearance variants, shared animation resources and measured performance. Review the populated city before proceeding.

Acceptance: a small population performs persistent routines and navigation with usable animation; each step receives its own review checkpoint. The supplied human is the shared civilian/worker/police base, and the supplied astronaut remains the Exceptional Agent base.

Delivered checkpoint: 25 civilians and 5 police, eight civilian palettes and one police uniform, shared meshes/animations, crowd avoidance and physical collision, one navigation map, local patrol stops, durable routines and atomic population movement batches. Schema 3 preserves the existing world and Alex while adding 29 residents once. Open `Review Population.command`; use [ / ] to select residents. See `docs/STAGE_3E.md` for validation, native performance and scope. Stage 4 remains a separate checkpoint.

## 4 — Brother Eye control

- Deterministic inspect/evaluate/intervene controller with a stable API.
- Inspectable city/agent state, events, simulated cameras, commands, and logged overrides.
- Tie restrained satellite/tower effects to actual intervention events.

Acceptance: interventions visibly affect authoritative simulation state and have traceable logs; ordinary agents retain local knowledge.

### 4A — Inspection (implemented; ready for review)

Searchable roster, civilian/police filters, identity-stable selection, needs and current goal, saved versus local character position, each resident's known places, daily schedule, and timestamped memories with a decision filter. A versioned read-only snapshot projection supplies the interface. Camera controls suspend while inspecting; following and city time remain accessible. Two native Godot launches verify inspection, read-only behavior and restoration, and the population and follow-camera regressions pass. Open `Review Inspection.command` or press F5; see `docs/STAGE_4A.md`.

### 4B — Evaluation (implemented; ready for review)

Assess actual city/resident conditions and explain conclusions. Establish a reasoning interface before choosing whether to use deterministic rules, a local model or a hosted model. AI integration remains a future choice.

Delivered checkpoint: authoritative deterministic assessments accompany the exact source snapshot. City totals, flagged residents, need thresholds, route versus crowd waits, recovery context, evidence and suggested review steps appear in the city evaluation and each resident's Assessment tab. No automatic intervention is issued. Open `Review Evaluation.command` or press F6. See `docs/STAGE_4B.md` for rules, validation and limits.

### 4C — Intervention (implemented; ready for review)

Validated known-destination override/replacement and release for civilians/police, required reasons, optimistic goal/override context, persistent held authority, atomic accepted/rejected receipts and audit, and physical travel/wait/completion. Schema 4 preserves existing saves. Inspector Interventions tab and `Review Interventions.command` provide explicit actions; evaluation never commands automatically. 38 backend tests, four-launch headless/native intervention acceptance and inspection/evaluation/lifecycle/obstacle regressions pass. See `docs/STAGE_4C.md`. Memory/motivation/world-condition authority remains unsupported; Exceptional Agent ideology precedence remains a Stage 5 decision.

### 4D — Presentation and verification (implemented; ready for review)

F7/control-room launcher, four fixed real-scene simulated cameras using one throttled viewport, read-only full intervention-audit paging/filter/details, and acknowledgement-only satellite/tower/interface feedback. Pending/rejected/replayed results are distinct; historical welcome and receipt replay cannot duplicate pulses. 41 backend tests, two-launch headless/native acceptance, physical-intervention/inspection/lifecycle regressions and native overhead measurement pass. See `docs/STAGE_4D.md`. Stage 4E below closes the combined acceptance checkpoint. No new authority or AI provider is added.

### 4E — Combined acceptance (complete)

The real UI/service/navigation/control-room sequence passes in native and headless launches: urgent evaluation, explicit command, conflict rejection, physically blocked override, wait audit, clearance, physical arrival and need recovery, history review, backend restart and app relaunch. Backend rollback/replay and inspection/evaluation/intervention/control-room/population/obstacle/lifecycle regressions pass. Evidence and supported authority limits: `docs/STAGE_4E.md`. Stage 5A/5B are complete below; current schema is 8, protocol remains 1.

## 5 — Exceptional Agents

### 5A — Behavior and authority contract (complete; design only)

Four immutable ideological profiles with adaptable tactics, explicit destination-only Brother Eye precedence, bounded local evidence/relationships/projects and a small deterministic action set. Define observable contrasting choices before implementation. `docs/STAGE_5A.md` is the current contract. No runtime behavior or save changes are delivered by this step.

### 5B — Shared foundation (implemented and verified)

Schema 5 appends four stable identities and distinguishable shared astronaut variants while preserving all original 30 records/world/receipts. Bounded foundation state, immutable core validation, inspection/filter/follow/evaluation, 2 m collision/navigation headroom and destination-only authority are integrated. 46 backend tests, headless/native acceptance and relevant population/control/inspection/obstacle regressions pass. Basic routines remain explicitly labelled; see `docs/STAGE_5B.md`.

### 5C — One complete agent (implemented and verified)

Shared local observations, bounded request claims/actions, candidate evidence, physical voluntary assistance, trust/memories and atomic outcomes now support the Arbiter's fair severity/age/ID policy. Schema 6 preserves existing records/receipts; native/headless movement→dwell→effect→backend/app restore and rollback/refusal/block/authority tests pass. Other three and project/coordination producers remain 5D. See `docs/STAGE_5C.md`.

### 5D — Remaining three policies (implemented and verified)

Shared policies now implement Attendant information/contact strategy, Martyr persistent project/voluntary coordination and Sovereign self/companion priorities. Schema 7 preserves ongoing state. Seventy backend tests, headless/native physical coordination and restart acceptance, and focused Arbiter regression pass. Side-offset contact meetings clear the helper departure path. See `STAGE_5D.md` for evidence and limits.

### 5E — Combined acceptance (verified; current 6A/6B fixes also regress this checkpoint)

Review all four interacting; verify locality, immutable cores, claims/effects, atomic rollback/replay, interventions and persistence. Run broader relevant regressions once here and measure the 34-person native scene. Deliver Stage 6 handoff and actual limitations.

Acceptance: observable decisions follow each ideology, persist through restarts, and respond to experience without supernatural abilities. Focused checks at 5B–5D; avoid unrelated asset rebuilds, AI services and repeated full-suite runs. `PROGRESS.md` records the current stop point.

## 6 — Scaling and polish

- Measure progression toward 100–1,000 agents using simulation detail levels, instancing, geometry detail levels, and bounded draw distances.
- Expand the city only as measured performance permits.
- Add more interactions, institutions, material detail, and visual variety.
- Optional LLM planning remains a later extension behind the controller API.

Acceptance: documented frame-time/memory/simulation measurements at each population tier and explicit supported settings.


Current Stage 6 checkpoint: 6A organic routines and 6B 50-resident tier are implemented with verified corrections. See `PRE_6C_FIXES.md`. Basic animation/query/draw budgeting now works; 6C visual LOD and 6D retention are now verified below; 6E 100-person benchmark/handoff is complete below. Interactive frame cap is not a thermal guarantee.


**Stage 6C complete (13 October 2026):** opaque spatial batching with regenerated mesh LODs, decorative distance cutoff and live-feed character detail priorities. Controlled 50-person native comparison, image/clearance/navigation/control/persistence checks pass. Scope and memory tradeoff: `STAGE_6C.md`. Retention is complete below; 6E acceptance is complete below.


**Stage 6D complete (13 October 2026):** schema-8 transactional retention, sequenced command watermarks and safe retired retries, compact legacy compatibility records, audit pruning notice and locked offline compaction. 97 backend tests, native/headless acceptance, six regression suites and synthetic large-save migration pass. `STAGE_6D.md` records actual file-size/latency evidence and legacy-ledger limits. Production save/journal untouched. 6E acceptance follows below.


**Stage 6E complete (13 October 2026):** safe optional 100-resident expansion and final native 50/100 measurements, original-goal arrival correction, persistence/control/behavior/navigation regressions and the requested verified 57.50-second MP4. `STAGE_6E.md` records actual limits: 50 recommended for 60 FPS headroom; 100 is slower in skyline/control-room views. 101 backend tests and all six broader regressions pass. Production save/journal untouched. The agreed milestone plan is delivered; further scope awaits user direction.
