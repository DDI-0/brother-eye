# Brother Eye headquarters refinement

Implemented in `godot/scripts/brother_eye_tower.gd`, called from `city.gd`. The original core, angular blades, buttresses, footprint and collision shapes are retained. New details include recessed observation bays, mullions, floor ledges, structural belts, service louvers, rooftop mechanical equipment, paneled podium, entrance jambs, canopy, double doors, handles and facade-mounted lettering. The entrance remains a closed exterior; this change does not introduce an accessible interior.

Dedicated graphite, metal-frame and podium materials use `command_facade.gdshader` with world-space panel seams, restrained panel variation, runoff shading and roughness variation. Window occupancy varies deterministically. The central cyan signal is narrower with lower baseline emission, and remains a separate StandardMaterial3D mesh compatible with live command acknowledgement feedback. City lighting and surrounding architecture are not changed.

Verification:
- Godot 4.7.2 Forward+ / Metal native render: four views captured without script/shader errors.
- Entrance collision ray hits original podium at z=-76; collision shape count remains 657.
- Command signal remains emissive StandardMaterial3D for command-feedback duplication.
- Existing composition QA passes: two transit routes, zero intersections, 22,096 visual bounds checked.
- `git diff --check` passes.

`before/` and `after/` contain matching tower, facade and entrance viewpoints. `after/skyline.png` adds a wider view showing the complete crown. These are actual in-engine captures using the normal city lighting, rather than generated concept images.

Reproduce captures and checks:

```sh
godot --path godot --script res://scripts/brother_eye_review.gd -- --no-simulation
godot --headless --path godot --script res://scripts/composition_check.gd -- --no-simulation
```

Both review runs avoid the simulation backend and world saves.
