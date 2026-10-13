# Stage 4E — combined acceptance checkpoint

Completed 2026-10-12. Stage 4's implemented control scope is verified end to end. This checkpoint adds repeatable acceptance tooling and durable evidence; it adds no new authority, AI provider, production geometry or save migration. Schema 4 / protocol 1 remain unchanged. Stage 5 has not begun.

## Combined scenario

`tools/check_stage4e.py` creates a disposable paused city with 30 residents and a hungry Alex near the market. `godot/scripts/stage4e_check.gd` drives the real city, backend, inspector, intervention controls, follow camera and control room across two launches:

1. Observe urgent 92% hunger in a source-bound evaluation; reject a stale assessment as current evidence.
2. Issue a known-market override through the UI with a reason. Pending emits no pulse; acknowledged acceptance emits one. Pause preserves needs and position.
3. Submit a conflicting stale-context command; confirm durable rejection without changing the held override or freezing the service.
4. Enclose the actor with temporary physical walls and rebuild navigation. Resume: physical routing reports waiting, evaluation includes route evidence, and neither arrival nor eating is fabricated.
5. Detach the temporary walls before rebaking. The actor walks more than 2 m, physically arrives, completes the task and starts eating; authoritative hunger decreases and evaluation reports recovery.
6. Browse accepted, rejected, waiting, travelling and completed audit entries in the actual control-room UI. Confirm the camera's paused-world tick and offline retained-evidence labels.
7. Kill only the disposable backend, recover the same completed override without historical feedback, close gracefully, then relaunch. Verify resident identity, needs, position, goal, held override and clock; no offline time or duplicate pulse.
8. Inspect SQLite: integrity OK, one created world, 30 residents, exactly two intervention receipts and accepted/rejected/wait/completion audit evidence.

Graceful shutdown intentionally submits a final movement report. The restore comparison excludes only its advancing `motion_seq`; physical state and all other resident fields must match. Native fixture deletion must detach walls from the scene before parsing collision geometry; `queue_free()` alone can still leave them present at rebake time. Both details were corrected in the harness and final native/headless runs pass.

The real `runtime/world.sqlite3` is never opened by these tests. Temporary test geometry exists only in the disposable acceptance scene. JSON traces retain audit IDs, reasons, outcomes and before/after context, not the disposable database itself.

## Fresh verification

All commands run from the project root; logs below are in `docs/previews/stage4e/`. Every final run exited successfully.

| Command | Actual result | Evidence |
|---|---|---|
| `.venv/bin/python -m unittest discover -s backend/tests -v` | 41 tests OK, 3.198 s; includes transaction rollback, authority, migration, waits, immutable retry IDs and crash/replay | `backend.log` |
| `.venv/bin/python tools/check_stage4e.py` | write/read failures=0, SQL trace/integrity/owned shutdown pass | `check.log`, `trace-headless.json` |
| Same with `--native` | write/read failures=0; Metal Forward+, 1440×900; two screenshots visually inspected | `native.log`, `trace-native.json`, `blocked-follow.png`, `completed-audit.png` |
| `.venv/bin/python tools/check_stage4a.py` | two-launch inspection/follow/modal/read-only/restore pass | `inspection.log` |
| `.venv/bin/python tools/check_stage4b.py` | source-bound evaluation and confirmed physical recovery pass | `evaluation.log` |
| `.venv/bin/python tools/check_stage4c.py` | four-phase intervention/release/conflict/backend restart/frontend journal recovery pass; exactly one replay receipt/effect | `interventions.log` |
| `.venv/bin/python tools/check_stage4d.py` | two-launch paging/filter/details/read-only/offline/render suspension/ACK feedback/replay/recovery pass | `control-room.log` |
| `.venv/bin/python tools/check_stage3e.py` | four-phase population migration/persistence/journal pass; 30 moved, 30 arrived; sampled minimum travel gap 2.081 m | `population.log` |
| `.venv/bin/python tools/check_stage2.py` | five-phase lifecycle/replay pass, one world, SQLite integrity, owned service shutdown | `lifecycle.log` |
| `godot --headless --path godot --fixed-fps 60 --script res://scripts/check_obstacles.gd -- --no-simulation` | 14 obstacle checks, failures=0 | `obstacles.log` |
| `godot --headless --path godot --editor --quit` | clean script import | `import.log` |

No new performance claim is made. Stage 4D's measured camera overhead and Stage 3E's population measurements remain the applicable historical samples.

## Supported scope and remaining limits

Brother Eye can inspect globally, derive deterministic need/navigation findings, explicitly assign or replace a resident's known destination, release that override, follow physical consequences, browse committed intervention history and view fixed simulated cameras. Ordinary residents retain their local known places. Completed overrides remain held until released; blocked overrides wait, with no automatic fallback or fake arrival. Evaluation does not issue commands.

Memory/motivation/ideology editing, arbitrary world-condition changes, automated policing, LLM reasoning, recording/rewind and camera PTZ are unsupported. Work/eating/rest/social activities remain abstract outdoor idles. Starting locations are distributed across three areas, but shared corridors and similar schedules can produce clustered, same-direction crowds; more varied routines and social behavior remain polish work. Agent scaling and long-term receipt/history growth remain unbenchmarked. Preserve the user's city composition, satellite, sky, licenses, character fixes and touchpad-friendly camera.

Next: agree Stage 5's ideology versus Brother Eye authority precedence and social/relationship scope, then deliberately migrate the exact-30-person contract for four Exceptional Agents. Do not change those semantics silently. `PROGRESS.md` retains the plan through Stage 6.

Evidence provenance update at Stage 5B: the headless `trace-headless.json` was regenerated by the 34-person/schema-5 regression. Original Stage 4E logs and native trace retain their 30-person milestone provenance. The same updated trace is saved as `stage5b/control-trace.json`; future regression runs can use `tools/check_stage4e.py --evidence-dir docs/previews/stage5b` to keep their traces separate.
