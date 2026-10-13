# Additional review — 24-hour lighting time-lapse

13 October 2026. `docs/previews/day-cycle/Brother-Eye-24-Hour-Cycle.mp4` shows the existing city from **06:00 through the next 06:00**, condensed into approximately **60 seconds**. It is a silent, chaptered 1440×900 H.264 MP4 at 24 FPS.

This is an **offline lighting study**, clearly labeled in the video. No backend or residents are instantiated, no gameplay time advances, and no save/journal is opened. It supplements the original live 100-person review, which remains unchanged. The normal application still uses its established blue-hour atmosphere; a persistent gameplay day/night cycle has not been added.

`godot/scripts/day_cycle_review.gd` changes sky gradients, warm dawn/dusk, directional lighting, ambient light and haze across the day. Night brings the crescent and restrained stars forward. A southern lighting arc remains separate from Brother Eye's northwest position. The camera, city geometry, transit rings and satellite retain their existing layout. `city_sky.gdshader` adds moon/star visibility controls with defaults preserving the original appearance; star calculations are skipped when disabled.

Reproduce from the project root with:

```sh
.venv/bin/python tools/record_day_cycle.py
```

Requires Godot and FFmpeg/ffprobe. Godot MovieWriter renders fixed frames to a temporary AVI; the tool removes warmup frames, encodes standard limited-range H.264 with fast-start metadata and eight time chapters, then fully decodes the result. The original and closing 06:00 frames are included (1,441 frames, about 60.04 s). This is offline rendering, not a performance/FPS benchmark.

Evidence under `docs/previews/day-cycle/`: `render.log`, `capture.json`, `encode.log`, `verification.json`, three-hour screenshots and MP4 frame captures. Automated checks verify the complete 24-hour span, matching morning lighting endpoints, distinct daylight/night energy, output dimensions/format/duration and complete decoding. Morning/noon/sunset/midnight/closing views are visually reviewed. No unrelated backend regression rerun is claimed for this isolated visual change.

The video and relevant source/docs can be added to GitHub with the normal `git add`, `git commit` and `git push` workflow. It does not replace either the final acceptance video or the project's current save.
