#!/usr/bin/env bash
# Showcase screenshots for the README, staged through the tm-mp4-control pack. Needs a race with the plugin's
# ghosts loaded (9 leaderboard ghosts on A01 when this was written). Writes docs/img/*.png (menu bar cropped off).
#   tools/showcase-shots.sh <slowest-ghost-instId> [mid-pack-instId] [restore-x restore-y]
set -euo pipefail
cd "$(dirname "$0")/.."
M="../tm-mp4-control/tools/mp4call.py"
SHOT="../tm-mp4-control/tools/mp-screenshot.sh"
slow="${1:?instId of the slowest ghost (the pack is ahead of it)}"; mid="${2:-$slow}"; rx="${3:-1350}"; ry="${4:-0}"
tmp="$(mktemp -d)"; mkdir -p docs/img
c() { python3 "$M" "$@" >/dev/null; }
shot() { "$SHOT" "$tmp/$1.png" >/dev/null 2>&1; magick "$tmp/$1.png" -crop 1600x878+0+22 "docs/img/$1.png"; }

c ghosts2.show_window visible=false
c ghosts2.lb_fetch offset=0   # async; the Load tab shot below needs the table filled
c ghosts2.lock all=true
if [[ "${SHOTS:-all}" != "ui" ]]; then
c ghosts2.pause instId="$slow" paused=true; c ghosts2.seek instId="$slow" ms=16000; sleep 0.3
# 1. hero: Follow cam 1 on the slowest ghost, the pack ahead, scrubber visible (spectate first so the chase cam
#    has settled behind the car, then seek to the start straight)
c ghosts2.cam type=1; c ghosts2.follow_cam cam=1; c ghosts2.spectate instId="$slow"; sleep 1.5
c ghosts2.seek instId="$slow" ms=4500; sleep 1.6
shot hero
# 2. Follow cam 2 (close) on the banked turn
c ghosts2.follow_cam cam=2; c ghosts2.seek instId="$slow" ms=16000; sleep 1.6; shot follow-cam2
# 3. internal cam over the jump
c ghosts2.follow_cam cam=3; c ghosts2.seek instId="$slow" ms=7000; sleep 1.6; shot internal
# 4. Replay (engine clip) camera on the turn
c ghosts2.cam type=0; c ghosts2.seek instId="$slow" ms=16000; sleep 1.8; shot replay-cam
c ghosts2.cam type=1; c ghosts2.follow_cam cam=1
c ghosts2.stop_spectating respawn=false; sleep 0.5
fi

# 5. Playback tab with varied states: lock off, mixed speeds, one paused, one spectated
c ghosts2.lock all=false
i=0; for id in $(python3 "$M" ghosts2.list | python3 -c "import sys,json; print(' '.join(str(g['instId']) for g in json.load(sys.stdin)['data'] if g['instId']))"); do
  case $i in 0) c ghosts2.speed instId=$id speed=2;; 1) c ghosts2.speed instId=$id speed=0.25;; 2) c ghosts2.pause instId=$id paused=true;; *) c ghosts2.pause instId=$id paused=false;; esac
  i=$((i+1))
done
c ghosts2.spectate instId="$mid"; sleep 1.5
c ghosts2.seek instId="$mid" ms=16000; sleep 0.8
c ghosts2.show_window visible=true tab=playback x=60 y=60; sleep 1.6; shot playback-tab
# 6. Load tab (leaderboard fetched beforehand), 7. Ghosts tab
c ghosts2.show_window visible=true tab=load; sleep 1.6; shot load-tab
c ghosts2.show_window visible=true tab=ghosts; sleep 1.6; shot ghosts-tab
c ghosts2.stop_spectating respawn=false
c ghosts2.lock all=true; c ghosts2.pause instId="$slow" paused=true
c ghosts2.show_window visible=true x="$rx" y="$ry"
rm -rf "$tmp"; ls -la docs/img
