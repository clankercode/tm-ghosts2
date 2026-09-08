#!/usr/bin/env bash
# Ghosts2 smoke test against the live game, through the tm-mp4-control socket and the ghosts2 command pack.
# Prints one PASS/FAIL line per check and exits non-zero if any check failed.
#
#   tools/tm2-smoke.sh              run the checks against whatever race is loaded (ManiaPlanet 4)
#   GAME=turbo tools/tm2-smoke.sh   same checks against Trackmania Turbo
#   tools/tm2-smoke.sh --nav        also drive the game to a script race first (MP4 only, slow, ~2 min)
#   tools/tm2-smoke.sh --nav-map 'Campaigns\0\A02.Map.Gbx'
#
# The plugin and the pack must already be staged and loaded (./build.sh dev, mp4pack/build.sh dev).
# This restarts the local player's run several times and adds/removes ghosts: do not run it mid-attempt.
# Turbo pauses whenever its window loses focus, so give it the focus before running this there.
set -uo pipefail
CTL="${MP4_CONTROL_DIR:-$HOME/src/openplanet/my-plugins/tm-mp4-control}"
GAME="${GAME:-mp4}"
case "$GAME" in
  mp4)   PORT=34531; MEDAL=4; MEDAL_NAME="author" ;;
  turbo) PORT=34532; MEDAL=4; MEDAL_NAME="author" ;;
  *) echo "unknown GAME=$GAME (mp4|turbo)" >&2; exit 2 ;;
esac
export MP4_CONTROL_PORT="$PORT"
call() { timeout 30 python3 "$CTL/tools/mp4call.py" "$@" 2>&1; }
NAV=0; NAV_MAP='Campaigns\0\A02.Map.Gbx'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --nav) NAV=1; shift ;;
    --nav-map) NAV=1; NAV_MAP="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

pass=0; fail=0
ok()   { printf '  PASS  %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$*"; fail=$((fail+1)); }
note() { printf '        %s\n' "$*"; }
head_() { printf '\n== %s\n' "$*"; }

# jq-free field access: jq_ '<python expr over d>' <<< '<json>'
jq_() { python3 -c "
import json,sys
r=json.load(sys.stdin)
d=r.get('data')
try: print($1)
except Exception as e: print('')
"; }

state()  { call ghosts2.state | jq_ "$1"; }
ghosts() { call ghosts2.list; }

# wait_until <seconds> <shell test command...>   - polls once a second
wait_until() {
  local n="$1"; shift
  for _ in $(seq 1 "$n"); do "$@" && return 0; sleep 1; done
  return 1
}

if [[ "$NAV" == "1" && "$GAME" != "mp4" ]]; then
  echo "--nav only knows how to drive ManiaPlanet 4; start the Turbo race yourself" >&2; exit 2
fi
if [[ "$NAV" == "1" ]]; then
  head_ "navigating to a script race ($NAV_MAP)"
  timeout 240 "$CTL/tools/mp-play-map-script.sh" "$NAV_MAP" >/dev/null 2>&1 \
    && ok "script race loaded" || bad "could not load $NAV_MAP"
  sleep 5
fi

head_ "plugin is alive"
if [[ "$(state "'ok' if r.get('ok') else 'no'")" == "ok" ]]; then ok "ghosts2.state responds"; else
  bad "ghosts2.state did not respond - is the plugin (and mp4pack) loaded?"; echo; echo "$pass passed, $fail failed"; exit 1
fi
uid="$(state "d['mapUid']")"; note "map $uid"
# Start from an empty list. Ghosts left by an earlier run make the sync and record checks read leftovers
# rather than what this run did, which shows up as a flaky failure rather than an obvious stale-state one.
call ghosts2.remove_all >/dev/null; sleep 3

head_ "the race accepts ghosts"
mode="$(call race | jq_ "d['currentPlayground']")"
players="$(call race | jq_ "d['nbPlayers']")"
note "playground $mode, rules.Players $players"
can_add=0
[[ "${players:-0}" -gt 0 ]] && can_add=1
if [[ "$can_add" == "1" ]]; then ok "script race: RaceGhost_Add is usable"
else note "classic race (rules.Players empty): add/restart checks skipped by design"; fi

head_ "leaderboard cache belongs to this map"
lb_uid="$(call ghosts2.lb_list | jq_ "d['mapUid']")"
if [[ -z "$lb_uid" || "$lb_uid" == "$uid" ]]; then ok "leaderboard cache is empty or for the current map ('$lb_uid')"
else bad "leaderboard cache is for another map: '$lb_uid' != '$uid'"; fi

if [[ "$can_add" == "1" ]]; then
  head_ "adding a ghost starts it"
  before="$(state "d['tracked']")"
  call ghosts2.load_medal level="$MEDAL" >/dev/null
  if wait_until 25 bash -c "[[ \$(timeout 20 python3 '$CTL/tools/mp4call.py' ghosts2.state 2>/dev/null | python3 -c \"import json,sys;print(json.load(sys.stdin)['data']['tracked'])\") -gt $before ]]"; then
    ok "$MEDAL_NAME medal ghost tracked (was $before)"
  else bad "$MEDAL_NAME medal ghost never appeared in the tracked list"; fi
  note "status: $(state "d['status']")"
  started="$(state "d['runStarted']")"
  note "mode $(state "d['modeName']"), run started $started"
  if [[ "$started" == "True" ]]; then
    # the added ghost must get a playback record (ghostTime >= 0), i.e. the run restarted for it
    # Only the ghosts Ghosts2 loaded: an engine ghost the game put in the race can be listed with no
    # resolvable playback record, and that is the game's business, not a failure of the add.
    if wait_until 25 bash -c "timeout 20 python3 '$CTL/tools/mp4call.py' ghosts2.list 2>/dev/null | python3 -c \"
import json,sys
gs=[g for g in json.load(sys.stdin)['data'] if g['source'] != 'engine']
sys.exit(0 if gs and all(g['ghostTime']>=0 for g in gs) else 1)\""; then
      ok "every tracked ghost has a playback record (added ghosts actually start)"
    else
      bad "a tracked ghost still has no playback record"
      ghosts | python3 -c "
import json,sys
for g in json.load(sys.stdin)['data']: print('        ', g['instId'], g['nickname'][:20], 'ghostTime', g['ghostTime'])"
    fi
  else
    # No run to restart (CampaignSolo parks the car behind the map's challenge card). The ghost must be
    # queued for the player's own start, and - the regression this guards - the car must still be there:
    # asking for a spawn from that screen takes it away and leaves the card up.
    sleep 3
    if [[ "$(state "d['playerSpawned']")" == "True" ]]; then ok "no run to restart: the car was left alone"
    else bad "the car was unspawned by an add while no run was started"; fi
    if [[ "$(state "d['status']")" == *"starts when you start your run"* ]]; then ok "the add says it starts with the run"
    else bad "unexpected status while parked: $(state "d['status']")"; fi
    if [[ "$(state "d['restartHeld']")" == "True" ]]; then ok "the restart is held, not dropped"
    else bad "the restart was not held (it will never fire)"; fi
  fi

fi

# Playback / spectate / remove run against whatever is in the race - in the legacy solo playground that is the
# engine's own opponent ghosts, which Ghosts2 drives even though it cannot add to them.
n_ghosts="$(ghosts | jq_ "sum(1 for g in d if g['ghostTime'] >= 0)")"
if [[ "${n_ghosts:-0}" -lt 1 ]]; then
  note "no ghost with a playback record: playback / spectate / remove checks skipped"
else
  head_ "the replay browser lists files as files"
  # The browser remembers where it was left, including by a previous run of this script, so walk up to a
  # folder that actually has subfolders before judging it.
  b="$(call ghosts2.browse)"
  for _ in 1 2 3; do
    [[ "$(printf '%s' "$b" | jq_ "len(d['dirs'])")" != "0" ]] && break
    parent="$(printf '%s' "$b" | jq_ "d['dir'].rstrip('/').rsplit('/',1)[0] + '/'")"
    [[ -z "$parent" || "$parent" == "/" ]] && break
    b="$(call ghosts2.browse dir="$parent")"
  done
  root_dirs="$(printf '%s' "$b" | jq_ "len(d['dirs'])")"
  if [[ "${root_dirs:-0}" -gt 0 ]]; then ok "replay folder lists $root_dirs subfolder(s)"; else bad "replay folder listed no subfolders"; fi
  sub="$(printf '%s' "$b" | jq_ "next((x for x in d['dirs'] if x.rstrip('/').endswith('Ghosts2')), d['dirs'][0] if d['dirs'] else '')")"
  if [[ -n "$sub" ]]; then
    b2="$(call ghosts2.browse dir="$sub")"
    nf="$(printf '%s' "$b2" | jq_ "len(d['files'])")"
    nd="$(printf '%s' "$b2" | jq_ "len(d['dirs'])")"
    if [[ "${nf:-0}" -gt 0 ]]; then ok "$sub lists $nf file(s) as files (and $nd folders)"
    else bad "$sub listed 0 files - are replays being classified as folders again?"; fi
  fi

  head_ "playback control (pause / seek / speed, through the lock)"
  id="$(ghosts | jq_ "next(g['instId'] for g in d if g['ghostTime'] >= 0 and g['instId'])")"
  # seek first so the pause check holds a non-zero time (a ghost paused at its start would pass trivially)
  call ghosts2.pause instId="$id" paused=true >/dev/null; sleep 1
  call ghosts2.seek instId="$id" ms=5000 >/dev/null; sleep 2
  s="$(ghosts | jq_ "next(g['ghostTime'] for g in d if g['instId'] == $id)")"
  if [[ "$s" == "5000" ]]; then ok "seek lands exactly (5000 ms)"; else bad "seek landed at $s, expected 5000"; fi
  a="$(ghosts | jq_ "next(g['ghostTime'] for g in d if g['instId'] == $id)")"; sleep 3; b="$(ghosts | jq_ "next(g['ghostTime'] for g in d if g['instId'] == $id)")"
  if [[ "$a" == "$b" && "${a:-0}" -gt 0 ]]; then ok "paused ghost does not advance ($a ms held for 3 s)"
  elif [[ "$a" == "$b" ]]; then bad "pause check was trivial: ghost sat at ${a} ms"
  else bad "paused ghost advanced $a -> $b"; fi
  # The clock reading "held" is not the same as the car standing still, and believing it twice is how the
  # Turbo stutter survived two releases. On Turbo, check where the ghost actually is on track.
  if [[ "$GAME" == "turbo" ]]; then
    p0="$(ghosts | jq_ "next(g.get('pos') for g in d if g['instId'] == $id)")"
    sleep 2
    p1="$(ghosts | jq_ "next(g.get('pos') for g in d if g['instId'] == $id)")"
    if [[ -z "$p0" || "$p0" == "None" ]]; then bad "no rendered position for the paused ghost (pose chain broken?)"
    elif [[ "$p0" == "$p1" ]]; then ok "paused ghost does not move on track (held at $p0 for 2 s)"
    else bad "paused ghost moved on track: $p0 -> $p1"; fi
  fi
  # every locked member must sit at the same time
  spread="$(ghosts | jq_ "max(g['ghostTime'] for g in d if g['ghostTime'] >= 0) - min(g['ghostTime'] for g in d if g['ghostTime'] >= 0)")"
  if [[ "${spread:-99}" -le 2 ]]; then ok "locked ghosts are in sync (spread ${spread} ms)"; else bad "locked ghosts drifted ${spread} ms apart"; fi
  call ghosts2.speed instId="$id" speed=2 >/dev/null
  call ghosts2.pause instId="$id" paused=false >/dev/null
  t0="$(ghosts | jq_ "next(g['ghostTime'] for g in d if g['instId'] == $id)")"; sleep 4; t1="$(ghosts | jq_ "next(g['ghostTime'] for g in d if g['instId'] == $id)")"
  rate=$(( (t1 - t0) / 4 ))
  if [[ "$rate" -gt 1700 && "$rate" -lt 2300 ]]; then ok "2x speed measured ${rate} ms/s"; else bad "2x speed measured ${rate} ms/s (want ~2000)"; fi
  call ghosts2.speed instId="$id" speed=1 >/dev/null
  call ghosts2.seek instId="$id" ms=2000 >/dev/null
  call ghosts2.pause instId="$id" paused=true >/dev/null

  head_ "leaderboard fetch and load"
  call ghosts2.lb_fetch >/dev/null
  if wait_until 30 bash -c "timeout 20 python3 '$CTL/tools/mp4call.py' ghosts2.lb_list 2>/dev/null | python3 -c \"
import json,sys
sys.exit(0 if len(json.load(sys.stdin)['data']['entries'])>0 else 1)\""; then
    ok "leaderboard fetched ($(call ghosts2.lb_list | jq_ "len(d['entries'])") records)"
    lb_before="$(ghosts | jq_ "len(d)")"
    call ghosts2.load_lb rank=1 >/dev/null
    if wait_until 30 bash -c "[[ \$(timeout 20 python3 '$CTL/tools/mp4call.py' ghosts2.list 2>/dev/null | python3 -c \"import json,sys;print(len(json.load(sys.stdin)['data']))\") -gt $lb_before ]]"; then
      ok "leaderboard ghost downloaded and added"
    else bad "leaderboard ghost never arrived: $(state "d['status']")"; fi
  else
    note "leaderboard did not answer for this map: $(call ghosts2.lb_list | jq_ "d['status']")"
  fi

  head_ "spectate and stop"
  sleep 1
  if [[ "$(state "d['camReady']")" != "True" ]]; then
    # Turbo: the camera follows a GameMobilId and a race ghost's instance id is not one. The plugin has to
    # say so and leave the camera alone, rather than write an id nothing follows.
    st="$(call ghosts2.spectate instId="$id" >/dev/null; state "d['status']")"
    if [[ "$(state "d['spectating']")" == "False" ]]; then ok "spectating is refused where the camera cannot follow a ghost"
    else bad "spectate started even though the camera is not ready"; fi
    if [[ -n "$st" ]]; then note "refusal: $st"; fi
  elif [[ "$(call ghosts2.spectate instId="$id" | jq_ "'ok' if r.get('ok') else 'no'")" == "ok" ]]; then
    sleep 3
    [[ "$(state "d['spectating']")" == "True" ]] && ok "spectating" || bad "spectate reported ok but state says not spectating"
    forced="$(state "hex(d['camForcedId'])")"; note "camera forced id $forced"
    call ghosts2.stop_spectating >/dev/null; sleep 5
    [[ "$(state "d['spectating']")" == "False" ]] && ok "stopped spectating" || bad "still spectating after stop"
    [[ "$(state "hex(d['camForcedId'])")" == "0xff00000" ]] && ok "camera forced target cleared" || bad "camera still forced at $(state "hex(d['camForcedId'])")"
  else
    bad "spectate refused: $(state "d['status']")"
  fi

  head_ "remove"
  # prefer a ghost Ghosts2 added: the game's own race ghosts cannot be taken out of the race at all, and the
  # plugin is expected to say so rather than to pretend the row went away.
  id2="$(ghosts | jq_ "next((g['instId'] for g in d if g['source'] != 'engine'), d[0]['instId'])")"
  src2="$(ghosts | jq_ "next((g['source'] for g in d if g['instId'] == $id2), '?')")"
  n_before="$(ghosts | jq_ "len(d)")"
  call ghosts2.remove instId="$id2" >/dev/null; sleep 5
  still="$(ghosts | jq_ "sum(1 for g in d if g['instId']==$id2)")"
  n_after="$(ghosts | jq_ "len(d)")"
  if [[ "$src2" == "engine" ]]; then
    st="$(state "d['status']")"
    if [[ "${still:-0}" == "1" && "$st" == *"game's own race ghosts"* ]]; then ok "engine ghost cannot be removed and says so"
    else bad "engine ghost removal: still=$still status='$st'"; fi
  elif [[ "${still:-1}" == "0" ]]; then ok "removed ghost stays removed ($n_before -> $n_after tracked)"
  else bad "removed ghost came back (instId $id2 still listed)"; fi
fi

head_ "the update check stays inside its daily budget"
# The one thing that can go wrong here is the daily gate not holding: that would mean a request to the
# GitHub API on every load or every frame, and a shared unauthenticated rate limit is easy to exhaust.
if [[ "$(state "d['updateCheckEnabled']")" != "True" ]]; then
  note "update check is turned off"
else
  last="$(state "d['updateLastCheck']")"
  due="$(state "d['updateCheckDue']")"
  if [[ "$last" == "0" ]]; then
    note "no check has run yet in this install (it runs within a minute of load)"
  elif [[ "$due" == "False" ]]; then ok "a check has run and the next one is not due (last stamp $last)"
  else bad "a check has run but another is already due - the daily gate is not holding"; fi
  err="$(state "d['updateLastError']")"; [[ -z "$err" ]] && ok "no update-check error" || note "update check last error: $err"
fi

head_ "hooks are healthy"
# Turbo needs no clock hook (nothing there rewrites a record's start time per frame) and has no camera
# override yet, so what must hold is "the clock is drivable", not "a hook object exists".
[[ "$(state "d['timeCtlReady']")" == "True" ]] && ok "playback clock is drivable" || bad "playback clock is not drivable"
if [[ "$GAME" == "mp4" ]]; then
  [[ "$(state "d['camHook']")" == "True" ]] && ok "camera target hook installed" || bad "camera target hook missing"
else
  [[ "$(state "d['camReady']")" == "False" ]] && ok "camera override reports itself unavailable (Turbo)" || ok "camera override is ready"
fi
err="$(state "d['timeCtlLastErr']")"; [[ -z "$err" ]] && ok "no time-control error" || bad "time control error: $err"
err="$(state "d['camLastErr']")"; [[ -z "$err" ]] && ok "no camera error" || bad "camera error: $err"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[[ "$fail" == "0" ]]
