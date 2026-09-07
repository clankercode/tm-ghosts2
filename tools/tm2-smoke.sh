#!/usr/bin/env bash
# Ghosts2 smoke test against the live ManiaPlanet 4 game, through the tm-mp4-control socket and the
# ghosts2 command pack. Prints one PASS/FAIL line per check and exits non-zero if any check failed.
#
#   tools/tm2-smoke.sh              run the checks against whatever race is loaded
#   tools/tm2-smoke.sh --nav        also drive the game to a script race first (slow, ~2 min)
#   tools/tm2-smoke.sh --nav-map 'Campaigns\0\A02.Map.Gbx'
#
# The plugin and the pack must already be staged and loaded (./build.sh dev, mp4pack/build.sh dev).
# This restarts the local player's run several times and adds/removes ghosts: do not run it mid-attempt.
set -uo pipefail
CTL="${MP4_CONTROL_DIR:-$HOME/src/openplanet/my-plugins/tm-mp4-control}"
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
  call ghosts2.load_medal level=4 >/dev/null
  if wait_until 25 bash -c "[[ \$(timeout 20 python3 '$CTL/tools/mp4call.py' ghosts2.state 2>/dev/null | python3 -c \"import json,sys;print(json.load(sys.stdin)['data']['tracked'])\") -gt $before ]]"; then
    ok "medal ghost tracked (was $before)"
  else bad "medal ghost never appeared in the tracked list"; fi
  note "status: $(state "d['status']")"
  # the added ghost must get a playback record (ghostTime >= 0), i.e. the run restarted for it
  if wait_until 25 bash -c "timeout 20 python3 '$CTL/tools/mp4call.py' ghosts2.list 2>/dev/null | python3 -c \"
import json,sys
gs=json.load(sys.stdin)['data']
sys.exit(0 if gs and all(g['ghostTime']>=0 for g in gs) else 1)\""; then
    ok "every tracked ghost has a playback record (added ghosts actually start)"
  else
    bad "a tracked ghost still has no playback record"
    ghosts | python3 -c "
import json,sys
for g in json.load(sys.stdin)['data']: print('        ', g['instId'], g['nickname'][:20], 'ghostTime', g['ghostTime'])"
  fi

  head_ "playback control (pause / seek / speed, through the lock)"
  id="$(ghosts | jq_ "d[0]['instId']")"
  call ghosts2.pause instId="$id" paused=true >/dev/null; sleep 2
  a="$(ghosts | jq_ "d[0]['ghostTime']")"; sleep 2; b="$(ghosts | jq_ "d[0]['ghostTime']")"
  if [[ "$a" == "$b" ]]; then ok "paused ghost does not advance ($a ms held for 2 s)"; else bad "paused ghost advanced $a -> $b"; fi
  call ghosts2.seek instId="$id" ms=5000 >/dev/null; sleep 2
  s="$(ghosts | jq_ "d[0]['ghostTime']")"
  if [[ "$s" == "5000" ]]; then ok "seek lands exactly (5000 ms)"; else bad "seek landed at $s, expected 5000"; fi
  # every locked member must sit at the same time
  spread="$(ghosts | jq_ "max(g['ghostTime'] for g in d) - min(g['ghostTime'] for g in d)")"
  if [[ "${spread:-99}" -le 2 ]]; then ok "locked ghosts are in sync (spread ${spread} ms)"; else bad "locked ghosts drifted ${spread} ms apart"; fi
  call ghosts2.speed instId="$id" speed=2 >/dev/null
  call ghosts2.pause instId="$id" paused=false >/dev/null
  t0="$(ghosts | jq_ "d[0]['ghostTime']")"; sleep 4; t1="$(ghosts | jq_ "d[0]['ghostTime']")"
  rate=$(( (t1 - t0) / 4 ))
  if [[ "$rate" -gt 1700 && "$rate" -lt 2300 ]]; then ok "2x speed measured ${rate} ms/s"; else bad "2x speed measured ${rate} ms/s (want ~2000)"; fi
  call ghosts2.speed instId="$id" speed=1 >/dev/null
  call ghosts2.seek instId="$id" ms=2000 >/dev/null
  call ghosts2.pause instId="$id" paused=true >/dev/null

  head_ "spectate and stop"
  sleep 1
  if [[ "$(call ghosts2.spectate instId="$id" | jq_ "'ok' if r.get('ok') else 'no'")" == "ok" ]]; then
    sleep 3
    [[ "$(state "d['spectating']")" == "True" ]] && ok "spectating" || bad "spectate reported ok but state says not spectating"
    forced="$(state "hex(d['camForcedId'])")"; note "camera forced id $forced"
    call ghosts2.stop_spectating >/dev/null; sleep 5
    [[ "$(state "d['spectating']")" == "False" ]] && ok "stopped spectating" || bad "still spectating after stop"
    [[ "$(state "hex(d['camForcedId'])")" == "0xff00000" ]] && ok "camera forced target cleared" || bad "camera still forced at $(state "hex(d['camForcedId'])")"
  else
    bad "spectate refused: $(state "d['status']")"
  fi

  head_ "remove sticks"
  id2="$(ghosts | jq_ "d[0]['instId']")"
  n_before="$(ghosts | jq_ "len(d)")"
  call ghosts2.remove instId="$id2" >/dev/null; sleep 5
  still="$(ghosts | jq_ "sum(1 for g in d if g['instId']==$id2)")"
  n_after="$(ghosts | jq_ "len(d)")"
  if [[ "${still:-1}" == "0" ]]; then ok "removed ghost stays removed ($n_before -> $n_after tracked)"
  else bad "removed ghost came back (instId $id2 still listed)"; fi
fi

head_ "hooks are healthy"
[[ "$(state "d['timeCtlHook']")" == "True" ]] && ok "playback clock hook installed" || bad "playback clock hook missing"
[[ "$(state "d['camHook']")" == "True" ]] && ok "camera target hook installed" || bad "camera target hook missing"
err="$(state "d['timeCtlLastErr']")"; [[ -z "$err" ]] && ok "no time-control error" || bad "time control error: $err"
err="$(state "d['camLastErr']")"; [[ -z "$err" ]] && ok "no camera error" || bad "camera error: $err"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[[ "$fail" == "0" ]]
