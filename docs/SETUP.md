# Toolchain checkpoint — 11 October 2026

## Verified environment

- Apple M2 Pro, 16 GB unified memory, macOS 15.7.4, ARM64.
- Godot 4.7.2 stable (`4.7.2.stable.official.ed1daf0bf`), installed through Homebrew at `/Applications/Godot.app`.
- Blender 5.2.2 LTS, installed through Homebrew at `/Applications/Blender.app`.
- Existing Python 3.12.0 selected explicitly from `/Library/Frameworks/Python.framework/Versions/3.12/bin/python3`.
- Project virtual environment: `.venv/`; SQLite 3.42.0 available through Python.

The shell's default `python3` points to an older Python 3.8 installation. Use `.venv/bin/python` for this project; system defaults were not changed.

## Checks completed

1. Godot and Blender version commands returned successfully.
2. Godot initialized and imported the project shell in headless editor mode and exited successfully. No main scene exists yet.
3. Blender started with factory settings in background mode, executed a Python expression, and exited successfully.
4. Python created an in-memory SQLite table, inserted a value, and read it back successfully.
5. All five supplied model/animation sources were copied locally and hashed. Sixteen reference images and the specification were preserved.

Initial sandboxed startup checks could not initialize Godot's user Library directories, and Blender crashed in that restricted environment. Approved runs outside the sandbox succeeded. Godot emitted macOS camera API deprecation warnings, without initialization failure. Graphical rendering and performance have not yet been tested; those belong to Stage 1.

## Repeat basic diagnostics

From the project directory:

```sh
.venv/bin/python tools/check_setup.py
```

Open `godot/project.godot` in Godot for the project shell. This is not a playable build yet.

## Deferred downloads

Install and pin the Python WebSocket dependency when Stage 2 implements the service. SQLite needs no separate installation. Godot export templates are needed when producing standalone builds, not for the first editor-run neighborhood. No paid software or additional model downloads are required to start Stage 1.

Tool sources: [Godot for macOS](https://godotengine.org/download/macos/) and [Blender](https://www.blender.org/download/).
