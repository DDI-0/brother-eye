# Neon Providence — Observatory

The eastern Observatory at x=46 is now built by `godot/scripts/observatory.gd`. The Civic Exchange, surrounding towers and normal city lighting are unchanged.

The original support footprint and roof level are retained. The building now has recessed instrument-floor windows, projecting metal ribs, paneled cladding, service louvers, a framed entrance and restrained task/status lights. The rooftop includes a raised dome drum, two open shutter sectors with curved tracks, a visible telescope on a fork mount, a small telemetry dish, weather mast, service cabinets, cooling louvers, conduit runs and calibration markings.

The dome, instruments and research entrance are exterior scenery. The equipment does not yet collect simulated observations, track real celestial objects or transmit telemetry. The ground-floor doors remain closed; no interior is added. Solid equipment and the instrument enclosure have collision. The inner rooftop aisle and original skywalk opening remain clear.

Review:

```sh
godot --path godot --script res://scripts/observatory_review.gd -- --no-simulation
godot --headless --path godot --script res://scripts/composition_check.gd -- --no-simulation
```

The native review saves six actual in-engine captures: entrance, terrace and dome in normal blue-hour lighting, plus temporary 10:00 daylight versions. It walks the real player controller through the eastern skywalk opening and north along the roof aisle, then ray-checks the closed entrance, service equipment and dome drum. Review input is refreshed each physics frame so desktop focus changes cannot interrupt the test. It does not open the simulation backend or production save.

Composition QA passes with two transit routes and zero intersections. The machine-readable native access/collision result is in `verification.json`.

## Daily dome rotation

`observatory_tracking.gd` turns the dome, shutter tracks and telescope together once per saved simulated day. The telescope also varies elevation between 25 and 65 degrees. The fixed drum, dish, service plant, facade and collision enclosure do not rotate. Moving meshes are excluded from the static visual optimizer using the `animated_landmark` subtree marker; dome panel shading uses local coordinates so panel seams rotate with the shell.

The controller uses the same 08:00 offset as the city HUD and reads authoritative `clock_seconds` from connected/restored simulation snapshots. It accumulates no independent wall-clock time, so pause, simulation speed and restored clock values retain their meaning. Disconnection holds the last pose. Offline scene previews start at 08:00; `day_cycle_review.gd` explicitly supplies the selected hour. This is an artistic daily tracking cycle, not an astronomical ephemeris or new telemetry simulation.

`observatory_rotation_review.gd` checks four daily poses, day closure, changing telescope elevation, paused/disconnected stability, restored absolute time, midnight continuity, and the visibility of all moving mesh descendants after static optimization. All checks pass; see `rotation/verification.json`. Transit clearance continues to pass with zero intersections. The optional eight-second movie mode compresses a full day and lighting cycle into 192 frames at 24 fps:

```sh
godot --path godot --script res://scripts/observatory_rotation_review.gd -- --no-simulation
godot --path godot --script res://scripts/observatory_rotation_review.gd --write-movie /tmp/neon-observatory-day.avi --fixed-fps 24 --disable-vsync -- --no-simulation --rotation-movie
```
