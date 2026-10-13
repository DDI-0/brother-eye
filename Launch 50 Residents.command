#!/bin/zsh
set -eu
cd -- "$(dirname -- "$0")"
if [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  exec /Applications/Godot.app/Contents/MacOS/Godot --path "$PWD/godot" -- --population-tier=1
elif command -v godot >/dev/null 2>&1; then
  exec godot --path "$PWD/godot" -- --population-tier=1
else
  echo 'Godot 4 is required. See docs/SETUP.md.'
  read -r '?Press Return to close.'
fi
