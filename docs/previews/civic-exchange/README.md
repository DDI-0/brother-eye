# Neon Providence — Civic Exchange

The western Civic Exchange at (-46, 7) is now built by `civic_exchange.gd`. The Observatory remains unchanged. The building retains its original podium, roof height and skywalk connection. Added details include pale stone facade framing, inset glass bays and mullions, side service louvers, a lit closed entrance with canopy and signs, a framed rooftop skylight, stone planters with shrubs, timber benches, a shade pergola, and deck inlays. Props have collision where they can impede walking. This is an exterior upgrade; no accessible indoor lobby is implemented.

The project title, HUD, satellite identity, headquarters sign, inspection/control screens and new backend authority records use Neon Providence. Historical audit records and media/resource filenames are retained. The new launcher is `Launch Neon Providence.command`; the original launcher also opens the renamed game. The authoritative simulation database remains in `runtime/`, independent of the display name. Saved key bindings fall back to the former Godot user folder until changed.

Validation:
- Native Godot Forward+ / Metal: five captures in normal blue-hour and temporary daylight study lighting; runtime lighting is unchanged.
- The real player controller crosses the western skywalk opening and walks north into the terrace aisle, finishing at approximately (-30.76, 12.00, 11.77).
- Composition QA passes: two transit routes, zero intersections.
- All 101 backend tests pass, including temporary local service tests outside the sandbox.
- `git diff --check` passes.

Reproduce offline visual and access checks:

```sh
godot --path godot --script res://scripts/civic_exchange_review.gd -- --no-simulation
```

The review uses no backend or production save. `entrance.png`, `terrace.png`, and `headquarters.png` use normal lighting; the two `day-` captures use temporary 10:00 lighting from the existing day-cycle study.
