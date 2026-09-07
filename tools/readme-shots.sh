#!/usr/bin/env bash
# Capture README screenshots from the running game via the tm-mp4-control pack (moves the Ghosts2 window to a known
# spot, selects tabs, spectates one ghost for the scrubber shot, then puts the window back).
#   tools/readme-shots.sh [instId-to-spectate] [restore-x restore-y]
set -euo pipefail
cd "$(dirname "$0")/.."
M="../tm-mp4-control/tools/mp4call.py"
SHOT="../tm-mp4-control/tools/mp-screenshot.sh"
inst="${1:-}"; rx="${2:-1350}"; ry="${3:-0}"
tmp="$(mktemp -d)"
if [[ -n "$inst" ]]; then
  # a finished ghost has no playback: park the group mid-run first (the lock applies this to every ghost)
  python3 "$M" ghosts2.pause instId="$inst" paused=true >/dev/null
  python3 "$M" ghosts2.seek instId="$inst" ms="${SEEK_MS:-8000}" >/dev/null; sleep 0.3
fi
python3 "$M" ghosts2.show_window visible=true tab=playback x=700 y=40 >/dev/null; sleep 0.7
"$SHOT" "$tmp/playback.png" >/dev/null 2>&1
magick "$tmp/playback.png" -crop 820x470+690+30 docs/img/playback-tab.png
python3 "$M" ghosts2.show_window visible=true tab=ghosts >/dev/null; sleep 0.7
"$SHOT" "$tmp/ghosts.png" >/dev/null 2>&1
magick "$tmp/ghosts.png" -crop 820x470+690+30 docs/img/ghosts-tab.png
if [[ -n "$inst" ]]; then
  python3 "$M" ghosts2.show_window visible=false >/dev/null
  python3 "$M" ghosts2.spectate instId="$inst" >/dev/null; sleep 2.5
  "$SHOT" "$tmp/spec.png" >/dev/null 2>&1
  magick "$tmp/spec.png" -crop 1000x160+300+740 docs/img/scrubber.png
  magick "$tmp/spec.png" -resize 50% docs/img/spectate.png
  python3 "$M" ghosts2.stop_spectating >/dev/null
  python3 "$M" ghosts2.show_window visible=true tab=ghosts >/dev/null
fi
python3 "$M" ghosts2.show_window visible=true x="$rx" y="$ry" >/dev/null
rm -rf "$tmp"; ls -la docs/img
