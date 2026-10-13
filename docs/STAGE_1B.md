# Stage 1B — City composition

The supplied connected-city concept guides the elevated network and landmark hierarchy. The other city references guide density, vertical streets, blue/cyan lighting, and a skyline that continues beyond the playable neighborhood.

## Delivered

- 4,266 generated building groups: inhabited podiums, mid-rise infill, perimeter blocks, outer districts, and 28 tall asymmetric skyline anchors. Outer districts are scenic, not additional simulated neighborhoods.
- Street frontages, canopy details, rooftop services, antennas, setbacks, and varied lit-window facades. Windows use a shader rather than thousands of separate light objects.
- Two elevated transit loops and two tower skybridges. The transit loops preserve the original elliptical paths, heights, dimensions, station canopies, supports, and thin light strips. Affected existing towers are set back from the paths, while nearby generated roofs and antennas stay beneath reserved clearance envelopes. Imported building collisions follow their stepped mesh parts instead of an oversized full-height cylinder.
- Darker road/foundation materials, extended city foundations and observer range, and atmospheric depth. The original exposed rectangular platform no longer defines the skyline.
- Original command tower, Helix Spires, plaza, stair routes, bridge and civic terraces retained.

## Validation

All 13 controller/physics checks pass in the final layout, including facade blocking, stairs, bridge crossing, terrace access, jump and camera switching.

The dedicated ring-clearance check examines actual rendered mesh bounds and building instances against both route envelopes: 21,678 visual bounds checked, zero building intersections. The check also verifies that all route points remain on the approved original ellipses. A negative control inserts an actual box into a route and correctly fails with one intersection.

```sh
godot --headless --path godot -- --qa
godot --headless --path godot --script res://scripts/composition_check.gd
godot --headless --path godot --script res://scripts/composition_check.gd -- --inject-ring-obstruction
```

The third command intentionally exits with failure to verify obstruction detection.

Native Metal / Forward+ rendering at 1440×900 on the M2 Pro was captured and visually inspected at the skyline, plaza, skywalk, aerial, and neighborhood street views. Final opening-view sample: median 8.341ms (~120 FPS), p95 9.329ms, 2,391 draw calls, about 456.5 MiB reported render memory. These are local short-run measurements, not performance guarantees for future population simulation. Images and raw metrics are in `previews/stage1b/`.

## Scope

This pass establishes composition and urban density using procedural geometry. It is not the final art fidelity of the reference illustrations. Distant buildings are decorative and inaccessible. New transit loops are scenic infrastructure; trains, vehicles, route operation, and pedestrian access to these elevated decks are not implemented. Existing Stage 1 walking routes remain accessible. Generated building interiors are represented by facades; the Helix core has separate visual floor detail. No civilian simulation or backend has been added.

Implementation: `godot/scripts/city_composition.gd` and `godot/shaders/city_facade.gdshader`, integrated through `city.gd`. The new composition reference is preserved in `references/city/composition-connected-city.jpg`.
