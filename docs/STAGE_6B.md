# Stage 6B — 50-resident tier and verified budgeting

Updated 13 October 2026 after the pre-6C review and corrections. See [verified corrections and commands](PRE_6C_FIXES.md) for current evidence, implementation boundaries and sustained benchmark results. The original forty-frame measurements and thermal guarantees are superseded.

Delivered: 41 civilians, 5 police and 4 Exceptional Agents; deliberate atomic existing-save expansion via `Launch 50 Residents.command`; preservation of original resident state/claims/receipts; real animation/step-probe budgets; a pedestrian draw-distance limit; interactive 60 FPS cap/V-Sync; dynamic demographics.

Full collision physics, navigation and crowd avoidance continue at their normal rate. Temperature/fans/throttling were not measured. The 100-person tier is not implemented; it remains planned for 6E. Remaining visual LOD and draw-call tuning belongs to 6C.

Current checks: **89 backend tests pass**, six integration regression suites pass, native physical bench/stroll/budgeting acceptance passes, and obstacle/navigation/import QA pass. Evidence: `docs/previews/pre6c-fixes/`.

## Current native baseline (50 residents, 1440×900 Metal Forward+)

| View | Median ms | p95 ms | p99 ms | Physics p95 ms | Draw-call snapshot |
|---|---:|---:|---:|---:|---:|
| street | 9.882 | 11.151 | 11.797 | 2.954 | 2544 |
| plaza | 9.559 | 11.077 | 11.354 | 3.045 | 1818 |
| skyline | 10.532 | 12.854 | 15.033 | 3.103 | 7498 |

Each sample covers ten seconds after a two-second warmup. Measurements are view-specific; no causal savings or worst-case scaling guarantee is inferred. Renderer memory and real LOD counters are included in `previews/pre6c-fixes/performance.json`.
