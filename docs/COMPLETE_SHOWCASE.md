# Complete city showcase

13 October 2026. Final artifact: `docs/previews/showcase/Brother-Eye-Complete-Showcase.mp4`, approximately **5 minutes 37 seconds**, 1440×900, H.264/yuv420p, 24 FPS, silent, with seven chapters and embedded result captions.

## Contents and provenance

1. **City and civilian life:** new live 50-resident recording covering skyline, Brother Eye satellite, authority/helix towers, transit rings, streets (camera follows the moving civilian crowd), elevated terraces, bench rest, patrol and city assessment. 47 residents moved over one metre during the capture.
2. **Arbiter:** staged local needs; actual physical approach, five-second assistance and a committed five-point social-need effect.
3. **Attendant:** physical local information verification, a saved sourced fact, and inspection of the agent's knowledge.
4. **Martyr:** a voluntary offer and delegated request, followed by the Arbiter helper's real travel/completion and the project's recorded outcome. The coordinated and completed events share the same request ID.
5. **Sovereign:** actual companion assistance ahead of the more severe nearby stranger; recorded physical completion and a five-point effect.
6. **Brother Eye:** the existing verified 100-resident review: explicit destination control, physical travel, live camera/audit, release to autonomy, city life, sitting and inspection.
7. **Day/night:** the existing separately labeled offline lighting study, 06:00→next-day 06:00. Gameplay time/population do not advance in this segment.

This is an edited compilation of **separate disposable review worlds**, not one continuous 100-resident session. Exceptional Agent chapters use the established 34-person acceptance scenarios, seeded before launch so each policy can be demonstrated clearly. The Python backend and actual Godot bodies produce all decisions, travel, claims, dwell, knowledge and effects. No runtime teleport or manually awarded result is used. Outcome captions derive from the captured authoritative events, rather than from fictional narration.

The normal application, city layout, models, policies and save format are unchanged. Production save/journal and both earlier MP4s were untouched. There is no automatic repository push. Existing interactions are physical approach/dwell plus recorded needs/knowledge/project changes; dialogue, handshake gestures and voice acting are not implemented.

## Recording and verification

```sh
.venv/bin/python tools/record_showcase.py
```

Requires Godot, the project's Python dependencies, FFmpeg with `drawtext`, and ffprobe. The current caption font is macOS Arial (`/System/Library/Fonts/Supplemental/Arial.ttf`). `--mode arbiter|attendant|martyr|sovereign|city` records one chapter; `--mode assemble` rebuilds the compilation from locally retained chapters plus the two earlier review videos.

`godot/scripts/showcase_capture.gd` orchestrates cameras, headings and existing inspection controls. Captured frame timestamps preserve real elapsed timing; live frames were sampled at approximately **18 FPS**, encoded into a 24 FPS MP4. This is not a performance benchmark. Frames are duplicated where necessary to maintain real elapsed playback rather than speeding up slow captures. Pauses for inspecting completed outcomes are labeled.

Per-chapter checks require a healthy bridge, actual expected policy outcomes, unchanged canonical cores, valid persisted state/SQLite integrity and owned backend shutdown. Arbiter assistance requires over two metres of actual body displacement. Final assembly checks sourced verified information, shared delegation/completion request IDs, exact five-point assistance effects, format/duration and a full-file decode. The final video is kept below 95 MiB for a regular GitHub upload; no LFS is needed for this artifact.

Evidence in `docs/previews/showcase/`: native capture logs, per-mode JSON with authoritative histories/agents, `verification.json` with chapter timing/result captions, and reviewed chapter frames. Scratch JPEG sequences are temporary; intermediate chapter MP4s stay local and are Git-ignored. The final compilation, evidence and source scripts are included in Git candidates. This isolated recording work does not claim a fresh rerun of unrelated backend/regression suites.
