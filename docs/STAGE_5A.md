# Stage 5A — Exceptional Agent behavior contract

Design checkpoint completed 12 October 2026. This defines the Stage 5 implementation; it does **not** add agents or change runtime behavior. The user requested 5A after the proposed five-step plan and destination-only authority recommendation. That recommendation is the working decision below. Status update: Stage 5B is now implemented and verified in `docs/STAGE_5B.md`; Stage 5C is now implemented and verified in `docs/STAGE_5C.md`; Stage 5D is implemented and verified in `docs/STAGE_5D.md`; 5E remains unimplemented. The sections below retain the original behavior contract and planned division of work.

## Goal and bounded scope

Add four persistent, visibly distinct people whose choices differ for understandable reasons. Reuse the astronaut, animation/navigation, authoritative Python simulation, inspection/evaluation, SQLite and intervention pipeline. Build one shared deterministic planner, complete the Arbiter first, then configure the other three. No model downloads, LLM calls, separate agent services or council are needed for Stage 5.

The first version demonstrates local observation, prioritised civic assistance, information gathering, coordination and self/companion care. It does not simulate criminal justice, coercion, combat, political control, an economy or a citywide institution. The broad ideologies motivate bounded decisions; this first version cannot enact their entire philosophical ambitions.

## Identity and immutable cores

Keep the established names and original designs; use the supplied astronaut base with restrained material/insignia variants, visible names and inspection explanations. Color alone must not identify an agent. Shared equipment confers no special ability.

| Stable profile key / name | Immutable core | Autonomous priority among feasible opportunities | Adaptable tactics |
|---|---|---|---|
| `arbiter_of_dawn` / Arbiter of Dawn | Justice applies consistently, regardless of friendship or status. | Address the most severe observed unmet assistance request; ties go to the oldest request, then stable ID. | Choose a reachable route, avoid repeated failed approaches, seek corroboration before an accusation. No criminal enforcement exists in this version. |
| `attendant_of_mysteries` / Attendant of Mysteries | Knowledge, strategy and influence are the route to power. | Inspect the most uncertain relevant local information; when that is exhausted, coordinate with the most useful known contact. | Prefer sources that proved reliable; avoid repetitive observations; learn which contacts accept coordination. No secret omniscience or mind control. |
| `martyr_of_providence` / Martyr of Providence | Personally bears responsibility for remaking society and sees their own plan as the necessary path. | Pursue a persistent civic project: identify a local cluster of unmet requests, seek voluntary coordination, then personally assist when coordination is unavailable. | Reorder project steps and change partners after outcomes. Does not acquire authority to force civilians to obey. |
| `sovereign_of_unbound_will` / Sovereign of Unbound Will | Own and inner-circle freedom comes first, even at outsiders' expense. This is not universal altruism. | Protect own urgent needs, then assist a known companion before a more severe stranger request; otherwise preserve autonomy or explore. | Change contacts/routes and maintain or withdraw trust from experience. Does not gain physical immunity or unlimited resources. |

Immutable fields: profile key/version and the canonical core/priorities it selects. Store profile references, validate against the server-owned catalogue, and reject attempts to mutate identity/core through commands or save validation. Migration may deliberately version a catalogue; ordinary decisions, learning and Brother Eye may not rewrite it. Names/biographies should be original; no borrowed fictional dialogue.

## Authority and precedence

1. Physical feasibility is mandatory: collision, route availability, pause and connection state remain binding. No teleport, fake arrival, remote global knowledge or supernatural action.
2. A valid explicit Brother Eye destination override takes precedence over autonomous needs, projects and tactics, including for Exceptional Agents. It changes the immediate destination only. It does **not** mean the agent agrees with Brother Eye, switches ideology or gains knowledge of other destinations.
3. Preserve Stage 4 semantics: own known-place key only, required reason, expected goal/override context, fresh goal identity, durable accepted/rejected receipt and audit, held override until explicit release, safe waiting when blocked. Completed remains held; there is no automatic expiry or needs fallback. Inspector must make this consequence clear.
4. While held, agents can retain observations and record the intervention/outcome; they cannot start a competing autonomous mission or let learning change the forced goal. Release resumes planning from current needs, observations and experience, rather than restarting their biography or restoring an obsolete goal.
5. Autonomous precedence: urgent physiological recovery (existing urgent hunger ≥90 or energy ≤10 thresholds), then profile priorities, then routine/exploration. Social need alone does not suppress every ideological choice. The Sovereign's companion preference applies after their own urgent recovery. Held override still wins over urgent needs.
6. Brother Eye has no action to edit core, memories, trust, relationships, motivation or project state. Any new authority requires a separate scoped decision. Extending destination validation to `exceptional` is explicit Stage 5 work; current code still accepts civilian/police only.

Reaction is observable rather than resistance by stealth. Record accepted redirection and release exactly once; an agent may describe interruption in their decision explanation. Do not infer trust changes from free-text command reasons. Any trust adaptation requires a defined observed interaction outcome, not merely receiving/replaying an ACK. Replays/reconnects cannot duplicate memories, relationship changes or landmark effects.

## Shared minimal decision and interaction model

Use a small candidate set and explicit ordered priorities, not four separate planners or arbitrary per-frame random choices. Each choice records profile, local evidence IDs, candidates, selected action/target and reason. Stable IDs break remaining ties. A held action is not reselected every tick; replan on completion, new relevant local evidence, changed needs, release or a bounded retry/cooldown. Keep the existing authoritative clock; exact update budget is measured in 5C, not promised here.

Shared first-version actions:

- **Recover / travel:** existing known home/food/park destinations and collision-backed movement. Needs recovery requires confirmed arrival and matching activity.
- **Observe:** visit a known reachable point, then acquire bounded local observations. Initial sensing is proximity-based within 8 m on the same walking level (vertical difference ≤2 m); explicitly label it a simulation abstraction, not optical/line-of-sight surveillance. Merely choosing a target does not reveal it. Observations include subject, fact, observed time and source; they expire for decisions after 10 simulated minutes until re-observed. Persistent memory may remember the historical observation.
- **Assist:** respond to an observed, still-open request by travelling to the person's last observed position and verifying proximity again. Initial assistance is a brief voluntary social interaction: 5 simulated seconds while both participants are within 2 m on the same level, neither travelling nor paused/offline. Completion reduces the recipient's social need by at most 5 points, clamped at zero, once per request. It does not cure hunger or energy remotely. Recipient arrival/activity is not fabricated. If the recipient declines, leaves or the route fails, record that actual outcome and make no assistance effect. Use a per-pair 60 simulated-second cooldown.
- **Coordinate:** offer another locally known participant a shared assistance request. Accept/decline is deterministic from that participant's own authority, urgent needs and existing commitments; it does not force a destination. In this first version, autonomous coordinated task acceptance is limited to Exceptional Agents. Civilians may voluntarily receive assistance but keep their existing planner. A declined proposal must still allow the Martyr to carry out their project alone.

Requests are bounded records referring to a real recipient and unmet social need (>75), with created time, severity, claimant and terminal outcome. They are created only from local observation, refreshed against local evidence, and resolved atomically once. A request's presence is not a crime or permission to punish. Inspection can show global authoritative records to the user; the agent planner must receive only its locally observed subset. Isolated acceptance fixtures may initialise multiple valid requests, but normal simulation must produce them from actual conditions.

Keep durable state bounded: at most 16 current observations, 8 directed relationships and one active project per Exceptional Agent. Reuse the existing 16-entry recent-memory limit; preserve durable significant outcomes in the event log. Directed relationships contain known person ID, trust (−100…100) and an explicit companion flag. Seed one original civilian companion for the Sovereign without changing that civilian's identity, needs or routine; the directed bond does not imply reciprocal knowledge or trust. Other relationships can start neutral when encountered. Companion status stays fixed in Stage 5; social-group growth is deferred.

For learning, a completed cooperative interaction increments the participant's directed trust by 1; an explicit decline decrements it by 1, clamped. A blocked route is route experience, not moral betrayal; it records a cooldown, not a trust penalty. Deduplicate consequences by interaction ID. The Attendant can use trust as source/contact preference, the Martyr as partner preference, and the Sovereign within their known contacts. The Arbiter cannot use friendship/trust to bypass request severity and age. Confidence is evidence freshness/reliability, not invented probability of guilt.

Requests, claims, effects, project transitions, interaction outcomes and associated memories must use the existing atomic persistence boundary. One request cannot reward multiple helpers after completion. Stale/expired evidence may prompt observation, but cannot justify a remote effect. Future implementation may simplify presentation, not silently replace these physical/local/at-most-once guarantees with text-only decisions.

## Required observable scenarios

These are future acceptance criteria, **not tests run or behavior implemented in 5A**. Use isolated worlds and actual observable outcomes.

| Scenario | Required evidence |
|---|---|
| Same local opportunities, different priorities | With no urgent self-need: Arbiter selects the most severe stranger request even when a friend waits; Attendant selects the uncertain information target; Martyr selects the shared project/coordination step; Sovereign selects the known companion over the stranger. Reasons cite local facts and profile rules. |
| No global oracle | An unobserved distant request or changed need cannot enter the planner's evidence. Inspection may reveal it to the user. Visiting/observing changes the agent's available choices. |
| Real assistance | Actor arrives, proximity/dwell/recipient consent gates pass, one bounded social effect and one completion occur. Departure, refusal, pause, disconnect and blockage produce no fabricated effect. |
| Adaptive tactics, stable core | An observed cooperation/decline changes partner/source preference where applicable; blocked travel changes route retry behavior. Canonical core is identical before/after and after restart. Arbiter fairness survives friendship changes. |
| Brother Eye interruption | Assign during an autonomous action, preserve core/project evidence, wait/complete physically, remain held, release to a fresh feasible ideological choice. Stale movement cannot finish the interrupted task. |
| Shared task conflicts | Two helpers/coordination offers cannot double-claim or double-apply a request effect; replays and transaction failures leave no partial relationship/memory/reward. |
| Save migration and restoration | Add exactly four once to the existing 25 civilians +5 police; retain old world/clock/person IDs/needs/memories/places/goals/held overrides and pending receipt/journal compatibility. Relaunch and backend crash retain each new agent's identity/core/experience; no offline advancement. |
| Runtime review | Four distinguishable astronaut agents appear in roster/follow/evaluation/control-room flows; existing civilian/police filters still work. Explain planned, travelling, waiting, interacting and completed states without confusing decisions with actual effects. |

## Implementation order and efficient validation

- **5A — complete:** this behavior/authority contract, scoped scenarios and updated durable plan. Documentation review only; no new runtime test claim.
- **5B — shared foundation:** introduce catalogue/identity validation and deliberate schema migration to 34 total (25 civilians, 5 police, 4 Exceptional Agents). Add bounded state containers and four shared-asset variants; adapt population, inspector and evaluation counts/types. Existing overrides and historical receipts must remain restorable. Agents can use clearly labelled basic routines until 5C/5D. Extend destination-only authority and test immutable cores. Focus on migration, model/animation integration, controls and restore; do not build four brains yet.
- **5C — one complete vertical slice:** implement shared local sensing, request lifecycle, planner/action execution, bounded relationships/learning/project primitives and Arbiter policy. Verify movement → observation → choice → voluntary assist → effect → memory/audit → save/relaunch, plus interruption and blocked/declined cases. Use fixtures for other policy candidates, without claiming the other agents are complete.
- **5D — three remaining policies:** add Attendant information/contact strategy, Martyr project/coordination loop and Sovereign companion/autonomy priorities using that shared foundation. Verify contrasting choices and adaptation. Implement voluntary Exceptional Agent coordination here; keep the Arbiter's solo assistance path useful without it.
- **5E — combined acceptance:** four-agent interaction/conflict scenario, immutable-core tests, local-knowledge isolation, failed-transaction/replay recovery, native review and measured 34-person sample. Run the broader relevant regression suite once here. Update supported scope and Stage 6 handoff.

For 5B–5D, run focused unit/integration checks after changes; broaden only when a cross-cutting change justifies it. Reuse models/materials/clips instead of rebuilding Blender assets for planner changes. Update `PROGRESS.md` at every step with actual commands/results and limitations. No Stage 6 scaling, unrelated crowd reset, renderer migration, AI/council, expanded city geometry or additional authority is included.

## Verified current implementation and immediate 5B work

Inspected `backend/citizens.py` (exact 30 and 25/5 validation, 16 memories, local places and needs), `backend/interventions.py` (civilian/police-only destination authority), `godot/scripts/pedestrian.gd` (currently hardcodes civilian GLB), existing build plan and Stage 4E handoff. These are actual constraints; the contract above is future work.

Validation for this documentation checkpoint: local Markdown links and basic document structure checked successfully for this contract, `docs/BUILD_PLAN.md`, `PROGRESS.md` and `README.md`. No runtime tests were rerun; Stage 4E evidence remains unchanged.

Before editing 5B, map `backend/store.py` migration and old receipt restoration, `backend/service.py` state/command validation, `godot/scripts/persistent_population.gd`, `population_appearance.gd`, `inspection_model.gd`, `inspection_panel.gd`, `intervention_controls.gd` and evaluation totals/filters. Confirm the processed astronaut GLB path and material/animation layout. Make a disposable schema-4 fixture containing an active override and receipts; migrate twice and assert original 30 records/world survive and only four identities are added. Never run migration experiments on `runtime/world.sqlite3`. Preserve license/credits and the supplied-run exclusion.
