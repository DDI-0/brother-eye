#!/bin/zsh
set -eu
cd -- "$(dirname -- "$0")"
if [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  exec /Applications/Godot.app/Contents/MacOS/Godot --path "$PWD/godot" -- --intervention-review
elif command -v godot >/dev/null 2>&1; then
  exec godot --path "$PWD/godot" -- --intervention-review
else
  echo 'Godot 4 is required to open the intervention review.'
  read -r '?Press Return to close.'
fi
