# Scene entry point

`city.tscn` loads `scripts/city.gd`, which deterministically assembles the first neighborhood from `scripts/geometry.gd`.

The procedural kit keeps simple collision separate from batched visual geometry. Imported building assets can replace the tower visuals while retaining their footprints and collision contracts. Keep street-level assets in meters, Y-up, with origin at the base; orient the front toward +Z. Runtime-ready imported models should be under `res://assets/`, with attribution retained under the repository's `docs/licenses/`.

The bridge walking surface is at Y=12. Its ramps are 4.8m wide and rise 12m over 40m; step meshes use an independent continuous collision slope. Sidewalk curbs are 0.12m above the road and the controller allows a 0.26m curb step. These dimensions and simple colliders are suitable inputs to future navigation baking. Stage 1 does not yet contain a baked navigation mesh or pathfinding.

Ground mode uses a 1.8m capsule, radius 0.32m. Observer flight preserves the ground character's last position. Shortcut views intentionally move the character to a landmark.
