# Stage 5D — Local policies and voluntary coordination

Implemented and verified 12 October 2026. Stage 5E combined acceptance and performance measurement remain unstarted.

## Behavior

- **Attendant of Mysteries:** verifies uncertain locally observed social-need information (unverified, then oldest verification, then learned trust). When information is current, offers a useful observed request to a trusted known Exceptional Agent. Verification produces a bounded fact and relationship learning, not an assistance reward.
- **Martyr of Providence:** groups nearby observed requests into one persistent civic project, offers work to a locally observed Exceptional Agent, and falls back to personal assistance after refusal/cooldown. Actual recorded task outcomes update the project; failed tasks are not described as successful aid.
- **Sovereign of Unbound Will:** handles urgent personal recovery first, then assists fixed companion Mira ahead of more severe strangers. Refuses offers inconsistent with those priorities.
- **Arbiter of Dawn:** retains severity/age/stable-ID fairness. A voluntary offer can be refused when a better locally known request takes priority.

Helpers also refuse when directed by Brother Eye, urgently recovering, already committed, cooling down or pursuing incompatible information/project priorities. Offers do not control civilians or rewrite ideology. A recipient can decline or depart; there is no effect until physical completion.

## Collision fix and physical contract

The Martyr previously approached in front of the helper and occupied the departure route. Contact goals now use a perpendicular 1.2 m meeting offset. Assistance retains its existing approach logic. The native acceptance verifies actual movement from the meeting to the recipient and successful assistance after a backend crash, with collision enabled throughout.

Meeting acceptance requires actual ARRIVED state, proximity within 2 m, fresh physical reports and five live simulated seconds. Coordination shares only the offered evidence, retaining its original observation time; it atomically claims the request for a willing helper. It does not instantly reward the recipient. The helper must then physically arrive and complete the common five-second assistance, producing social need −5 exactly once. No teleport, need reset or synthetic arrival is used.

Observation visits pause for up to 15 simulated seconds after arrival, allowing voluntary meetings before resuming exploration. This can delay selection of new ideological requests by that bounded interval; urgent physiology and held destination overrides still take precedence. Pair cooldown is 60 simulated seconds.

## Architecture and persistence

- `backend/agent_policies.py`: ordered policy choices, information, project transitions, partner willingness and contact execution.
- `backend/agent_behavior.py`: shared sensing, physical gates, assistance, learning, audit and validation. Decisions use each actor's observations, not remote need scans.
- `backend/store.py` / `exceptional.py` / `citizens.py`: schema **7**, protocol **1**; migration activates canonical policy stages and information state while preserving ongoing Arbiter actions, evidence, receipts and identities. One revision increment covers the upgrade.
- `Service.advance()` keeps significant consequences atomic with world/event state and rolls back failures. UUID receipts and stale-motion rejection remain intact.
- Inspector/follow/Interventions show active policies, facts, project/partner, choices and outcomes; held destination authority still wins until release.
- Bounds: 16 observations, 16 verified facts, 8 relationships, 16 memories, one project with at most 16 tasks; 64 live request/history caches. Full significant events remain in SQLite. Observation radius 8 m, vertical tolerance 2 m, evidence expiry 600 simulated seconds. This is proximity sensing, not optical line of sight.

Canonical cores/identities, fixed companion membership, ordinary 25 civilian/5 police routines, city layout, rings, satellite, sky, character assets and camera controls remain unchanged. No LLM, council, new authority or asset rebuild.

## Verified evidence

All commands run from project root. Evidence lives in `docs/previews/stage5d/`.

| Command | Actual result / evidence |
|---|---|
| `.venv/bin/python -m unittest discover -s backend/tests -v` | **70 tests OK, 3.802 s**; `backend-tests.log`. Includes contrast, adaptation/refusal, self-target prevention, authority, migration, partial-state preservation and atomic rollback. |
| `.venv/bin/python tools/check_stage5d.py` | Write/read **failures=0**, schema 7 and SQLite integrity; `policies-headless.log`, `trace.json`. |
| `.venv/bin/python tools/check_stage5d.py --native` | Metal Forward+ write/read **failures=0**; `policies-native.log`, `native-trace.json`. Actual information gathering, companion aid, delegation, helper departure/arrival, backend crash and app restore pass without duplicate effects. |
| `.venv/bin/python tools/check_stage5c.py --evidence-dir docs/previews/stage5d/arbiter-regression` | Write/read **failures=0**; `arbiter-regression.log` and `arbiter-regression/trace.json`. Arbiter physical assistance, partial-dwell restore and unique outcome remain valid. |
| `godot --headless --path godot --editor --quit` | Exit 0, no script errors; `import.log`. |

Native `project.png`, `information.png` and `helper.png` were visually inspected: policy headers/state are legible and the helper is beside the recipient with clear separation. Structured native checks also verify the scrollable fact/project content.

Tests use disposable worlds only. Unrelated fixture residents rest at their own homes to isolate comparable opportunities; production saves and journals were not edited. Earlier `failed-trace.json` is diagnostic evidence from a failed fixture before the successful final runs, not a passing result. Older milestone logs were not overwritten. The 5C harness now supports an alternate evidence directory and records actual schema 7.

## Limits and next step

This implements small deterministic social-need projects and information/contact tactics, not general intelligence or political institutions. Partners may refuse and projects may record failures. The side offset solves the demonstrated obstruction; it is not a proof against every dense-crowd deadlock. Historical event/receipt growth still needs retention planning.

Stage **5E** should combine all four policies with competing claims, refusal, authority and interrupted/replayed effects; run relevant broader regressions and measure the native 34-person scene. The native checks here are functional acceptance, not a new performance benchmark. Stage 6 remains measured scaling and scoped polish, as detailed in `PROGRESS.md`.


### Inspector-close regression follow-up

The user reproduced two inspector assertion failures while the physical behavior checks passed. The harness assumed the inspector remained open; `inspection_panel.refresh()` intentionally returns while hidden. Stage 5D acceptance now explicitly closes/reopens the Exceptional overview and selects the required resident before each UI assertion, covering a viewer closing the panel to watch movement. Production inspector behavior and agent policies are unchanged. The exact native command was rerun: write/read **failures=0**, including both new reopen/selection assertions and all existing physical/crash/relaunch checks. Updated evidence: `docs/previews/stage5d/policies-native.log` and `native-trace.json`. No backend tests were rerun for this harness-only change. `failed-trace.json` may contain the user's intervening failed run; it remains diagnostic only.


### Additional bug review — project lifecycle

Fixed two project stalls in existing 5D behavior: an unclaimed social request now expires when local observation confirms the need has resolved; unclaimed project tasks expire when the owner no longer has valid local evidence (600-second expiry or bounded-cache eviction). Previously those tasks could remain open indefinitely and prevent the Martyr from completing the project or beginning a new one. Cleanup records `expired`, applies no assistance reward/trust effect, and never cancels a helper's active claim. Newly observed needs can create fresh requests. No schema or authority change.

Added two regression tests in `backend/tests/test_agent_policies.py` covering resolved needs, expired evidence, project completion without reward, and preservation of delegated claims. Validation of the disposable test fixture caught an invalid ARRIVED position; that fixture was corrected to TRAVELLING. Initial sandbox socket failures were rerun with loopback permission.

Fresh results after fixes:
- `.venv/bin/python -m unittest discover -s backend/tests -v`: **72 tests OK (3.743 s)**; `docs/previews/stage5d/audit-backend-tests.log`.
- `.venv/bin/python tools/check_stage5d.py --native`: write/read **failures=0**, including inspector reopen, physical helper departure/arrival and backend/app restoration; updated `policies-native.log`/`native-trace.json`.
- `.venv/bin/python tools/check_stage5c.py --evidence-dir docs/previews/stage5d/arbiter-regression`: write/read **failures=0**; updated `arbiter-regression.log`/trace.
- `.venv/bin/python tools/check_stage4e.py --evidence-dir docs/previews/stage5d/control-regression`: write/read **failures=0**, authority, blocked-route recovery, replay/restoration, exactly two intervention receipts and 34 residents; `control-regression.log` and subdirectory trace.

These checks cover the reviewed behavior paths; they do not establish that every possible crowd/layout interaction is bug-free. Stage 5E combined acceptance/performance remains unstarted. Production save and pending journal were not touched.
