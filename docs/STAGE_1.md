# Stage 1 — Explorable neighborhood

## Run

Double-click `Launch Brother Eye.command` in the project folder, or open `godot/project.godot` in Godot and press F5.

The launcher uses the installed Godot executable. This checkpoint is a local development build, not an exported standalone app. Blender and Python are not needed while exploring Stage 1.

## Controls

| Action | Control |
| --- | --- |
| Begin walking | Enter streets button |
| Capture mouse / look | Click the city, then move mouse |
| Move | W / A / S / D |
| Move faster | Shift |
| Jump on foot | Space |
| Fly up / down | E / Q |
| Change free-flight speed | Mouse wheel |
| Switch ground / observer | Ctrl+Shift+B |
| Skyline / plaza / skywalk views | 1 / 2 / 3 |
| Controls and mode-key rebinding | F1 |
| Release mouse / menu | Escape |
| Fullscreen | F11 |

Mode switching restores the previous ground position. Landmark shortcuts intentionally relocate the character. Ground mode starts on the central boulevard; follow it north toward the command tower. Stairs at X=±24, Z=64 ascend to the 12m skywalk. Walk sideways along the skywalk to reach the Civic Exchange and Observatory terraces.

Controls default to `godot/config/controls.cfg`. The controls panel can rebind the mode shortcut; overrides are saved in Godot's `user://controls.cfg` under this application's user-data folder. This is settings persistence, not world save/load.

## Implemented

- Deterministic procedural neighborhood and surrounding scenic skyline: blade crowns, stepped towers, ribbed facades, window banks, rooftop machinery, tanks, masts, and domes.
- Street grid, sidewalks, crossings, storefront facades, civic terminals, benches, lamps, surveillance fixtures, and a central plaza with an animated holographic material.
- Brother Eye command structure plus a distant satellite representation with restrained motion.
- Collision-backed pedestrian exploration, curb handling, jump, observer flight, and mode switching.
- Two stair routes, bridge, guarded edges, and accessible rooftop terraces.
- Panel/roughness shaders, navy/steel palette, blue and cyan emission, atmospheric haze, ambient occlusion, and glow.
- HUD with controls, landmarks, live FPS, and mode/altitude indication.
- Repeated geometry grouped into MultiMesh batches by material and spatial cell. Simple collision is separate from visual geometry. Render range is bounded.

## Validation

Automated checks use the actual scene and CharacterBody3D physics:

1. Spawn settles on the road.
2. Walking advances at the expected speed.
3. Observer camera activates.
4. Free-flight ascent works.
5. Switching back preserves the character's location.
6. A building facade blocks movement.
7. The full stair route reaches the skywalk without jumping.
8. The skywalk opens onto a rooftop terrace.
9. The bridge supports crossing above the boulevard.
10. Its north railing prevents walking off the central span.
11. Jump rises above the ground.
12. Jump returns to the ground.
13. Rebinding the mode action activates the new shortcut.

All 13 passed at the original Stage 1 checkpoint. The current Helix revision results are recorded below. Run again with:

```sh
godot --headless --path godot -- --qa
```

The native graphical renderer was exercised on Apple M2 Pro using Metal / Forward+, at 1440×900, with 4× MSAA. Captured views were visually inspected. The final 240-frame opening-view sample measured a median frame interval of 8.30ms (about 120 FPS), with a 95th-percentile interval of 10.29ms. It used approximately 340 MiB of reported render memory and 700 draw calls. See `previews/final/performance.json` for the raw measurements; they are a short local sample after warm-up, not a guarantee across all views or hardware. Engine memory counters do not represent total process memory.

```sh
godot --path godot -- --capture --capture-dir=/absolute/path/to/previews
```

## Scope and limitations

This is an architectural blockout with procedural surface detail. It does not match the supplied concept images' final asset fidelity. Storefronts and building entrances are exterior facades; interiors and opening doors are not implemented. Only the civic terraces are connected for on-foot rooftop exploration; other roofs can be inspected in observer mode. The distant skyline and satellite establish visual scale; no orbital physics or planet-scale simulation is present.

No citizens, traffic simulation, Brother Eye decision logic, active surveillance feeds, Python backend, world save/load, or baked navigation mesh are implemented in this stage. The collision geometry and documented route dimensions prepare for future navigation. The source character/animation downloads have not been imported into the runtime and their retargeting remains Stage 3 work.

Stage 2 is the authoritative Python service, world clock, WebSocket connection, and SQLite persistence. Review Stage 1 before advancing.

## Helix Spire refinement — October 11, 2026

The Helix variant now uses smooth continuous titanium ribbons around a tapered glazed core, with floor slabs, mullions, interior partitions, desks, and restrained ceiling lighting. Two annular crown decks have machined edges, radial members, inclined supports, rail posts, and thin cyan light strips. Three landing platforms use structural cantilevers, approach markings, and arrival displays. A stepped foundation and slender aerial complete the silhouette. This is a real-time interpretation of the supplied tower reference, not a photorealistic reconstruction.

Implementation is isolated in `godot/scripts/helix_tower.gd`, called by `city.gd`. The original downloaded Helix asset and shader remain available on disk. Other tower variants and global scene lighting are unchanged. Curved geometry uses higher resolution nearby and fewer segments in the distant skyline. Angled Helix members scale along their local axes, preserving their shape. Transparent glazing is specific to this tower. Floors and core interiors are visual detail, not accessible rooms.

Collision covers the service core, ribbon structure, podium, and landing platforms, without the previous oversized solid cylinder around the halo footprint. Focused checks passed for core collision, clear space beside the building, podium support, and outward ribbon normals. The facade check now probes the current wave tower at X=48, Z=64, walks long enough to reach its narrower footprint, and verifies the player stops at capsule clearance from the measured wall and remains stopped under continued input. The full movement suite passes all 13 checks. In the verified run, the wall was at Z=70.354 and the player stopped at Z=70.674.

Native Metal / Forward+ captures at 1440×900 were visually inspected at skyline and close-up distances. The final 240-frame skyline sample measured median 8.333ms (~120 FPS), p95 9.958ms, 2,077 draw calls, and 461.2 MiB reported render memory. These are short local measurements on the M2 Pro. Screenshots and raw metrics are in `previews/helix-refinement/`.
