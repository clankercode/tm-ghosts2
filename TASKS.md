# Ghosts2 task list (MP4 / TM2 Ghosts++ clone)

Legend: [ ] todo · [~] in progress · [x] done · (who) owner. "pfi" items get appended here.

## Plugin features
- [x] List race ghosts (engine `RaceGhosts` for classic mode; plugin-tracked instances for script modes) (opus subagent, v0)
- [x] Load ghosts from replay files (`Replay_Load` → `RaceGhost_Add`) — API verified in-game via tm-mp4-control (`race_ghost_add source=replay path=Ghosts2/test-silver.Replay.Gbx`, path relative to Replays/); Ghosts2 UI path still to test
- [x] Load personal best (`ScoreMgr.Map_GetRecordGhost`) — needs in-game test (opus subagent)
- [~] Load author/gold/silver/bronze medal ghost buttons (`Map_GetMultiAsyncLevelRecordGhost`, level 4..1) (grok helper) — user request 2026-09-07
- [x] Spectate a ghost via `UIAll.SpectatorForcedTarget` (+ restore) — verified in-game via tm-mp4-control `spectate`
- [~] Auto re-add after the mode's `RaceGhost_RemoveAll` — fix detection: `RaceGhosts` is empty in script modes; use per-instance `RaceGhost_GetStartTime/IsVisible` (started before, now 0 ⇒ removed) (grok helper)
- [ ] Classic campaign race (`CTrackManiaRace1P`): script API is inactive there; needs engine-level add/remove (Ghidra)
- [ ] Ghost time control (pause / seek / speed) — find per-instance playback state (start time) in engine memory; Ghidra RE of `RaceGhost_GetStartTime`
- [x] Save ghost: `DataFileMgr.Replay_Save("Ghosts2/x.Replay.Gbx", RootMap, ghostScript)` verified in-game (writes under Replays/); no `Ghost_Save` in MP4
- [ ] Ghost list extras: distance/delta to player, per-ghost visibility toggle (`RaceGhost_IsVisible` is read-only?), colours
- [~] Exports (`Ghosts2::*`) + tm-mp4-control command pack `ghosts2.*` (grok helper) — user request 2026-09-07
- [ ] Settings polish, window layout, README screenshots; release build + version bump

## Tooling / infra
- [x] tm-mp4-control: socket control plugin (menus, click, titles, play_map, campaigns, race, ghosts, mem, findu32(deep), race_ghost_add/remove/query, spectate)
- [x] tools: mp4call.py, memdump.py, structdump.py, typedb.py, mp-restart/screenshot/log/set-devmode, mp-play-campaign-map.sh
- [~] Ghidra headless analysis of ManiaPlanet.exe: local runs OOM-killed even at 24G (game holds the RAM) → x-alpha only (grok helper, 32G heap) → GhidraMCP :18743 via ssh tunnel → research/mp4/Ghidra.md
- [ ] tm-mp4-control: pack registry (`Packs.as`) + shared funcdef (grok helper)
- [ ] Log LSP gaps: void `UI::BeginTabBar` in `if` (logged 2026-09-07); typedb needs `OpenplanetNext.json` name for MP4

## Research notes to write (research/mp4/)
- [x] RaceGhost runtime (2026-09-07-RaceGhost-Runtime.md; keep appending): script-mode vs classic-mode findings, GhostInstId format (0x0fe0xxxx), holder structs at CTrackManiaRaceNew+0x1d0, remove/query semantics
- [x] GppApiMapping-TM2020-vs-MP4.md (helper), TM2-SoloGhostScripts.md (opus subagent)
