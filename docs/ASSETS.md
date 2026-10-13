# Supplied assets

Original files have been copied into `assets/source/`. Their checksums, author metadata, and animation names are in `asset_inventory.json`. Source downloads are not automatically runtime-ready or distributed with the application.

| Source | Intended use | Inspection result | Included license metadata |
| --- | --- | --- | --- |
| human.glb | Everyday civilians, workers, police | Static mesh; one gray material; no skin, animation, or images | aaron.kalvin; CC-BY-4.0 |
| space_engineers_astronaut.zip | Shared appearance for four Exceptional Agents | Five meshes; no skin, animation, or images | Keen Software House; CC-BY-4.0 |
| walk_cycle_animation.zip | Walk motion source | One animation, approximately 2.8 seconds; 68-joint skin | jlwande2; CC-BY-4.0 |
| standing__sitting_animation.zip | Sitting/standing motion source | Main clip approximately 3.875 seconds, auxiliary clip approximately 0.042 seconds; 222-joint skin | abysmaljess; CC-BY-4.0 |
| run.zip | Run motion reference/source | One animation, approximately 0.633 seconds; 23-joint skin | mega3d; CC-BY-NC-4.0 (noncommercial) |

Full supplied notices are preserved under `docs/licenses/`. Carry credits forward when producing distributable assets. Do not assume retargeting removes the run source's noncommercial restriction.

These findings are structural inspection, not confirmation of visual quality or successful retargeting. Both original character appearances are unrigged. Motion sources use different skeletons; the Stage 3B derivatives below now provide rigs and motion transfer. No dedicated idle loop has been confirmed; a simple idle may be authored.

## Architectural references

`references/city/` contains eleven supplied images: tower and facade modules, rooftop equipment, antennas, domes, arches/rings, low-rise mechanical structures, beams/ladders/panels, and assembled city views. Reconstruct approximate original geometry from visible forms; infer unseen sides and street-level features. The pictures are references, not 3D assets.

`references/mood/` contains five earlier city images establishing dark monumental architecture and blue/cyan lighting. Preserve dark areas and human-scale legibility; avoid applying emission to every surface.

`references/Brother_Eye_Master_Project_Specification.docx` is the original planning baseline. User instructions in the conversation govern scope and later design decisions.

## Stage 3A derivative

`godot/models/civilian/civilian.glb` is the enhanced static civilian appearance derived from the supplied Human. The original remains untouched. Editable Blender source is in `assets/working/civilian/`; author/license attribution ships beside the GLB. It has no skin or animation yet. See [Stage 3A review](STAGE_3A.md).

## Stage 3B animated derivatives

`godot/models/animated/` contains separate rigged civilian and astronaut GLBs, each with six baked clips. Walk and sit motion are transferred from the supplied CC BY sources; idle and run are authored for the project. No noncommercial run asset is incorporated. Original downloads and the static 3A appearance remain preserved. See [Stage 3B review](STAGE_3B.md) and the attribution beside the animated assets.
