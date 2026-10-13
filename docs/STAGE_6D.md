# Stage 6D — retention and long-term persistence

Completed 13 October 2026. SQL schema **8**, protocol **1**, life version **1**. All verification used disposable databases/journals; production `runtime/world.sqlite3` and its journal were untouched. Stage 6E has not started.

## Storage and retry contract

`backend/retention.py` prunes within the same transaction as state, event and receipt commits, every 32 commits and on startup. Keep the newest **128 full receipts**, the newest **512 events**, and independently the newest **512 significant events** containing intervention or agent outcomes. Creation/migration events are pinned. Between pruning passes, at most 31 additional commits accumulate: up to 159 full receipts and 1,024 events plus pinned records and 31 new events. Windows count records, not elapsed days. Current authoritative world state, active claims/projects, memories, overrides and the clock are preserved.

New Godot mutations, including shutdown, carry a contiguous durable command serial. A SHA-256-derived UUID binds world identity to serial; the backend atomically advances the watermark with the command result. Recent retries return the exact stored ACK. Older consumed serials receive `receipt_retired` with current authoritative state and cannot execute again, even after detailed receipts disappear. Invalid gaps, serials and reused IDs reject without mutation. Canonical request hashes distinguish boolean and numeric payloads while accepting equivalent JSON integer/float representations.

The pending journal persists its serial counter and ordered immutable sent requests. On reconnect, it reconciles retired commands against the matching world/watermark, without inventing an original acceptance or replaying a visual pulse. Unsent coalescing retains its ID/serial. Legacy journals remain readable. Replayed historical shutdowns do not stop a new service; a new shutdown is journaled and its ACK clears the journal before exit.

Schema-7 migration is atomic and preserves old UUID retry identities. Old unsequenced receipts compact into `legacy_receipts`: request hash and original small response/result metadata, without full snapshots. An old retry returns that recorded metadata with the current snapshot and a retired flag; it never repeats its effect. **This compatibility ledger grows if an external legacy client continues issuing new unsequenced commands.** Normal updated Godot traffic uses serials and needs no growing per-command tombstone ledger. No hard byte cap is claimed for arbitrary state/payload sizes or legacy traffic.

`receipts.committed_seq` provides stable receipt chronology across VACUUM. Legacy snapshot compaction processes 16 records at a time to bound migration memory. `retention` stores pruning counters; read-only audit paging preserves original event cursors and reports pruning metadata. The control room displays “Older audit entries were pruned; showing retained history.” only after actual audit entries disappear. Historical full-detail audit is intentionally finite.

## File space and maintenance

SQLite reuses freed pages; pruning alone need not shrink an existing file. WAL uses a 4 MiB journal-size limit and 256-page autocheckpoint. `tools/compact_database.py --db PATH` uses the application's exclusive lock, prunes, checkpoints, VACUUMs and verifies unchanged current state and SQLite integrity. Close Brother Eye before choosing an existing database for this offline operation. It may perform the normal schema migration on an old save. No per-frame or per-commit VACUUM runs, and no production compaction was performed.

## Verified evidence

Evidence: `docs/previews/stage6d/`; native retention notice: `retention-notice.png` (visually reviewed).

| Command | Actual result |
|---|---|
| `.venv/bin/python -m unittest discover -s backend/tests -v` | **97 tests OK**, 18.464 s; `backend.log`. |
| `.venv/bin/python -m unittest backend.tests.test_retention -v` | **8 tests OK**, 8.438 s; `retention-tests.log`. Includes atomic pruning/migration rollback, ancient/recent retries, immutable typed payloads, restart watermarks, read-only paging and caps. |
| `.venv/bin/python tools/check_stage6d.py` | **write/read failures=0** and long-run check passes; `headless.log`, `retention-headless.json`. |
| `.venv/bin/python tools/check_stage6d.py --native` | **write/read failures=0** and long-run check passes on Metal Forward+; `native.log`, `retention-native.json`. Real pending journal, fresh/replayed commands, audit notice, backend crash, app relaunch and shutdown. |
| `.venv/bin/python tools/check_stage5e_regressions.py --evidence-dir docs/previews/stage6d/regressions` | **All six pass**: foundation, Arbiter, policies, control, population and lifecycle; `regressions.log` and child logs. |
| `godot --headless --path godot --editor --quit` | Clean exit 0; `import.log`. |
| `.venv/bin/python tools/measure_retention_migration.py` | Synthetic 50-person schema-7 save with **1,200 legacy receipt snapshots** upgrades in **1,403.94 ms**; 128 full + 1,072 compact records, old/recent retry and state preservation verified. **124,051,456 → 13,660,160 bytes** after offline compaction; `legacy-migration.json`/log. |

Long-run scenario: 50 residents, paused clock, 600 prior intervention commands followed by 1,800 sequenced saves. Headless file size remained **27,623,424 bytes** at 600/1,200/1,800 saves, then compacted to **22,351,872**. Native size remained **27,627,520**, then compacted to **22,355,968**. Full receipts were 152/144/136 and events 1,049/1,041/1,033 at sample boundaries; exactly one legacy compatibility record remained. No state/clock/identity loss or repeated effect occurred.

Backend command latency: headless median/p95/max **10.341/14.745/99.601 ms**; native **10.822/13.994/42.452 ms**. These are SQLite/backend command timings, not gameplay frame times or a thermal guarantee. Later bounded migration batching and typed-hash refinements were covered by the final 97-test suite, focused tests, headless acceptance and legacy migration measurement; the earlier native run verifies presentation/reconnect behavior.

## Next checkpoint

6E: deliberately add the 100-person tier and safe existing-save migration; measure native frame/physics/backend/navigation/save cost and memory with active residents, verify collision, autonomy, retained-history/retry behavior and restart, capture fresh views and document measured supported limits. Preserve the 6C rendering/collision budgets and all identity/authority contracts. Await the user's 6E request.
