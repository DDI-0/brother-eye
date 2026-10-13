"""Read-only diagnostics for the local Brother Eye development toolchain."""

import json
from pathlib import Path
import platform
import shutil
import sqlite3
import subprocess
import sys


def tool_version(command, fallback):
    executable = shutil.which(command)
    if executable is None and Path(fallback).is_file():
        executable = fallback
    if executable is None:
        return {"available": False}
    try:
        result = subprocess.run(
            [executable, "--version"], capture_output=True, text=True, timeout=30
        )
        return {
            "available": result.returncode == 0,
            "executable": executable,
            "version": (result.stdout or result.stderr).strip().splitlines()[:1],
            "returncode": result.returncode,
        }
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"available": False, "error": str(error)}


def main():
    report = {
        "platform": platform.system(),
        "architecture": platform.machine(),
        "python": {"version": platform.python_version(), "executable": sys.executable},
        "sqlite": sqlite3.sqlite_version,
        "godot": tool_version("godot", "/Applications/Godot.app/Contents/MacOS/Godot"),
        "blender": tool_version("blender", "/Applications/Blender.app/Contents/MacOS/Blender"),
    }
    with sqlite3.connect(":memory:") as connection:
        connection.execute("CREATE TABLE setup_check (value INTEGER)")
        connection.execute("INSERT INTO setup_check VALUES (1)")
        report["sqlite_read_write"] = connection.execute(
            "SELECT value FROM setup_check"
        ).fetchone() == (1,)
    print(json.dumps(report, indent=2))
    return 0 if (
        sys.version_info >= (3, 12)
        and report["godot"]["available"]
        and report["blender"]["available"]
        and report["sqlite_read_write"]
    ) else 1


if __name__ == "__main__":
    raise SystemExit(main())
