# Nearby tower facade refinement

The 18 towers generated in the playable district now receive individual facade palettes and shallow architectural details through `godot/scripts/nearby_tower_facades.gd`. Their positions, heights, primary meshes, silhouettes, crowns, transit rings and collision envelopes are preserved. Distant skyline towers, the Civic Exchange, Observatory and headquarters keep their own materials.

Treatments:
- Helix: warm titanium on western towers and cool alloy on eastern towers, smoked glazing, quiet occupied-floor lighting, refined trim and core entry detailing. Ribbon geometry and halo decks are retained.
- Stepped imported buildings: graphite/champagne tint and less mirror-like surfaces, retaining supplied texture maps and mesh hierarchy.
- Inverted towers: champagne cladding, tapered mullions and thin floor rings following the existing flared body.
- Wave towers: teal cladding, cylindrical glazed bays, slender mullions and floor bands following each offset section.
- Fork towers: darker steel, tapered structural mullions and floor framing beneath the existing prongs.
- Disc towers: pale composite decks, inset perimeter trim and underside radial supports.
- Blade towers: bronze panels, dark glazed face strips, vertical framing and shallow horizontal joints.

Window, beacon and neon materials are restrained relative to the original generic district palette. Nearby details consume no city random numbers, so the seeded layout and existing occupancy choices stay reproducible. No new collider or accessible interior is added.

Material aliases resolve before kit batching and are scoped to a single tower construction call. Helix's custom box batching follows the same aliases. The visual optimizer also batches the known world-space panel shader; transparent glazing, local-coordinate dome materials and animated landmark subtrees remain independent.

## Verification

- Actual Godot Forward+ / Metal before/after captures use matching cameras.
- The complete collision count remains 677 and the collision-envelope digest matches the baseline exactly.
- Observatory moving geometry remains visible and its rotation still changes after static batching.
- Existing composition checks pass: both transit routes retain their approved layout and have zero visual intersections.
- Daylight captures use the existing offline lighting study; normal runtime blue-hour lighting is unchanged.
- Review scripts avoid the backend and production saves.

```sh
godot --path godot --script res://scripts/nearby_towers_review.gd -- --no-simulation
godot --headless --path godot --script res://scripts/composition_check.gd -- --no-simulation
```

`before/` holds the original seven camera views; `after/` includes the same views and four daylight captures. Verification details are in each folder's JSON report. These are in-engine captures, not generated concept images.
