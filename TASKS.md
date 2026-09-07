# Ghosts2 task list (MP4 / TM2 Ghosts++ clone)

Legend: [ ] todo · [~] in progress · [x] done · (who) owner. "pfi" items get appended here.

## Plugin features
- [x] List race ghosts (engine `RaceGhosts` for classic mode; plugin-tracked instances for script modes) (opus subagent, v0)
- [x] Load ghosts from replay files (`Replay_Load` → `RaceGhost_Add`) — API verified in-game via tm-mp4-control (`race_ghost_add source=replay path=Ghosts2/test-silver.Replay.Gbx`, path relative to Replays/); Ghosts2 path verified 2026-09-07 via `ghosts2.load_replay path=Ghosts2/test-silver.Replay.Gbx` (1/1 ghost, starts on respawn)
- [x] Load personal best (`ScoreMgr.Map_GetRecordGhost`) — verified in-game 2026-09-07 via `ghosts2.load_pb` (PB 23.277 by xertrov; `LocalUserId()` via `rules.Users[i].Id` is correct)
- [x] Load author/gold/silver/bronze medal ghost buttons (`Map_GetMultiAsyncLevelRecordGhost`, level 4..1) (grok helper) — user request 2026-09-07
- [x] Spectate a ghost via `UIAll.SpectatorForcedTarget` (+ restore) — verified in-game via tm-mp4-control `spectate`
- [x] Auto re-add after the mode's `RaceGhost_RemoveAll` — detection fixed: per-instance `RaceGhost_GetStartTime/IsVisible` queries; only "removed" after the instance previously reported startTime>0 (grok helper)
- [x] Classic campaign race (`CTrackManiaRace1P`): engine RaceGhosts records found at `race+0x1080` (same 0x98 layout, inst ids 0x0f00xxxx); time control via `CGameCtnGhost+0x40` verified 2026-09-07 (pause ±1 ms, 2x/0.5x rates 2049/512); spectating by that id works. Engine ghosts now get inst ids, playback rows and `ghosts2.*` commands. Still no engine-level add/remove for classic mode (the menu's ghost-opponent dialog does that)
- [x] Ghost time control (pause / seek / speed) — done 2026-09-07 for script modes: Ghosts2 writes the add entry's OffsetMs (`CTrackManiaRaceNew+0xdd0[i]+0x10`, re-read every frame by `CTrackManiaRaceNew_UpdateFrame`; the record's StartTime is rewritten every frame while the player races, so it is not a lever). Verified via pack: pause holds ±2 ms, seek lands within 1 frame, 2x/0.25x rates measured 2055/258 ms per s, works driving and spectating. Exports `GetGhostTime/Seek/SetPaused/SetSpeed`, pack cmds `ghost_time/seek/pause/speed`, Playback UI row
- [ ] Ghost offset (forward seek) via remove + `RaceGhost_AddWithOffset(ghost, ms)` + `SpawnPlayer` (verified: offset = seek into the replay, same startTime) — cheap partial scrubber for script modes
- [ ] Spectate camera choice: `SpectatorForceCameraType` 0 close chase, 1 behind car, 2/3 track cam (verified)
- [x] Save ghost: `DataFileMgr.Replay_Save("Ghosts2/x.Replay.Gbx", RootMap, ghostScript)` verified in-game (writes under Replays/); no `Ghost_Save` in MP4
- [ ] Ghost list extras: distance/delta to player, per-ghost visibility toggle (`RaceGhost_IsVisible` is read-only?), colours
- [x] Exports (`Ghosts2::*`) + tm-mp4-control command pack `ghosts2.*` (grok helper) — user request 2026-09-07; smoke-tested in-game 2026-09-07 (`packs` → ghosts2, `ghosts2.load_medal level=4`, list/state/spectate OK; pack must not re-declare dependency imports)
- [ ] Settings polish, window layout, README screenshots; release build + version bump

## Tooling / infra
- [x] tm-mp4-control: socket control plugin (menus, click, titles, play_map, campaigns, race, ghosts, mem, findu32(deep), race_ghost_add/remove/query, spectate)
- [x] tools: mp4call.py, memdump.py, structdump.py, typedb.py, mp-restart/screenshot/log/set-devmode, mp-play-campaign-map.sh
- [x] Ghidra: analysis done on x-alpha (upstream 12.1.3, ~/re/mp4u), GhidraMCP tunnelled to :18743, `research/mp4/tools/ghidra-mp4.sh`, `ghidra-mp4-progress.sh`, `ghidra_api.sh`; RaceGhost_* + Physics_Step named (see research/mp4/Ghidra.md)
- [x] Ghidra: RaceGhost_Add (0x140efe470), Remove/RemoveAll internals, record allocator, per-frame writer `RaceGhostRecord_UpdatePlaybackTime` (0x140848f20) + `CTrackManiaRaceNew_UpdateFrame` (0x140ebad00) — opus subagent 2026-09-07, research commit 4f53cf9
- [x] Classic race ghost records — solved at runtime (memscan); helper's static pass in research 7eefe80/41e1327 (1P ctor/vtable, 0xf0 id allocator)
- [x] tools: `mp-gdb-watch.sh` (hardware watchpoints on the live game), `memscan.py`/`memdiff.py`/`rawscan.py`, `poke`
- [x] tm-mp4-control: pack registry (`Packs.as`) + shared funcdef (grok helper)
- [x] Log LSP gaps: void `UI::BeginTabBar` in `if`; duplicate imports vs injected dependency `exports` (both logged 2026-09-07)
- [ ] typedb needs `OpenplanetNext.json` name for MP4

## Research notes to write (research/mp4/)
- [x] RaceGhost runtime (2026-09-07-RaceGhost-Runtime.md; keep appending): script-mode vs classic-mode findings, GhostInstId format (0x0fe0xxxx), holder structs at CTrackManiaRaceNew+0x1d0, remove/query semantics
- [x] GppApiMapping-TM2020-vs-MP4.md (helper), TM2-SoloGhostScripts.md (opus subagent)
