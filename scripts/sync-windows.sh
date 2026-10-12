#!/usr/bin/env bash
# Copy the project and toolkit to the Windows drive, where MSVC builds them.
# Building over \\wsl.localhost is slow and CMake mishandles the UNC path.
#
#   scripts/sync-windows.sh            # sources + toolkit
#   scripts/sync-windows.sh --game     # also copy the rip into game/ (2.2 GB, once)
#
# -rc without -t: content-compared and no timestamps carried over, so files
# whose text did not change keep their mtime and Ninja does not rebuild them.
# Then, from WSL:
#   cmd.exe /c 'C:\Code\Xbox\ssx3-recomp\tools\build.bat'
#   powershell.exe -ExecutionPolicy Bypass -File 'C:\Code\Xbox\ssx3-recomp\tools\run.ps1' -Seconds 45
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$(dirname "$HERE")"
DEST="${WIN_DEST:-/mnt/c/Code/Xbox}"

mkdir -p "$DEST/ssx3-recomp" "$DEST/xboxrecomp"
rsync -rc --itemize-changes --exclude .git --exclude .venv --exclude 'tools/*/output' \
    --exclude tools/ghidra_naming/work --exclude tools/ghidra_naming/export \
    "$PARENT/xboxrecomp/" "$DEST/xboxrecomp/" | grep -v '^\.d' || true
rsync -rc --itemize-changes --exclude .git --exclude decomp --exclude '*.log' \
    "$HERE/" "$DEST/ssx3-recomp/" | grep -v '^\.d' || true
if [ "${1:-}" = --game ]; then
    rsync -a "$PARENT/SSX3/" "$DEST/ssx3-recomp/game/"
fi
