# Ghosts2

An Openplanet plugin for **ManiaPlanet 4 / TrackMania 2** that lists, loads, removes and
spectates race ghosts. It is a small clone of the TM2020 plugin
[Ghosts++](../tm-ghosts-plus-plus), rebuilt on the MP4 API (`CTrackManiaRaceRules.RaceGhost_*`)
rather than the TM2020 ghost-clip manager.

## What it does

- **Ghosts tab**
  - Lists every entry of `CTrackManiaRace.RaceGhosts`: nickname, race time, respawns, login,
    and — for ghosts this plugin added — the `MwId` returned by `RaceGhost_Add`.
  - Lists the ghosts Ghosts2 loaded, with per-row **remove**, **re-add**, **spectate** and
    **save**, plus **Remove all** (`RaceGhost_RemoveAll`).
  - Shows `PlayerBestGhost` / `PlayerRecordedGhost` and toggles for the free engine ghosts
    (`IsBestRaceGhostVisible`, `MedalGhost_ShowGold/Silver/Bronze`).
- **Load tab**
  - A folder browser over the game's `Replays` folder (`IO::FromUserGameFolder("Replays")`,
    overridable in settings) listing `*.Replay.Gbx` / `*.Ghost.Gbx`. Loading runs
    `DataFileMgr.Replay_Load` in a coroutine and adds every returned ghost to the race.
  - **Load my PB** via `ScoreMgr.Map_GetRecordGhost(localUser, mapUid, "")`.
  - **Load author/gold/silver/bronze ghost** via `ScoreMgr.Map_GetMultiAsyncLevelRecordGhost`
    (levels 4/3/2/1). Nadeo campaign maps only — TMX maps have no medal ghosts, so failures
    and null ghosts notify.
- **Spectate** — writes the ghost's instance `MwId` to `UIAll.SpectatorForcedTarget` (what
  Nadeo's `UISequences::SetReplayGhostFocus` does), optionally with `ForceSpectator` and
  `UISequence = EndRound`. Stopping restores the previous values.
- **Playback control** — per ghost (plugin-loaded instances in script modes, and the engine's own
  medal/PB ghosts in the classic campaign race): pause/resume, speed (¼x … 4x), step ±100 ms, seek,
  plus a Ghosts++-style scrubber strip at the bottom of the screen. Ghosts2 hooks the engine's
  per-record clock update (`RaceGhostRecord_UpdatePlaybackTime`, `Dev::Hook`) and sets the record's
  StartTime from the exact tick time, so a paused car is perfectly still and seeks land exactly;
  "resync" hands the clock back to the game (the ghost snaps to the player's race time). A respawn
  rebuilds the engine's records, which releases any owned clock. Setting `Time control` turns the
  hook off.
- **Auto re-add** (on by default) — the stock solo mode calls `RaceGhost_RemoveAll()` on every
  phase transition, silently wiping plugin ghosts. Ghosts2 keeps the `CGameGhostScript@`
  handles and puts them back, rate limited, giving up after a few failed attempts so it can
  never end up in an add/remove fight with the mode script. The retained list is cleared on
  map change. Removal detection queries each tracked instance (`RaceGhost_GetStartTime` /
  `IsVisible`) — `RaceGhosts` is empty in script modes — and only treats an instance as
  removed once it previously reported `startTime > 0` (a fresh add reports 0 until the
  player starts).

## Exports and MP4 command pack

Ghosts2 exports `Ghosts2::ListGhosts`, `LoadReplay`, `LoadPB`, `LoadMedal`, `Remove`,
`RemoveAll`, `Spectate`, `StopSpectating`, `State`, `ShowWindow`, `GetGhostTime`, `Seek`,
`SetPaused`, `SetSpeed`, `Resync` and `ShowScrubber` for other Openplanet scripts. The optional `ghosts2` pack (`mp4pack/`, plugin id `tm-ghosts2-mp4pack`,
build with `mp4pack/build.sh`) exposes the same operations through
`tm-mp4-control/tools/mp4call.py ghosts2.list` (subcommands: `state`, `load_replay`,
`load_pb`, `load_medal`, `remove`, `remove_all`, `spectate`, `stop_spectating`,
`show_window`, `ghost_time instId=`, `seek instId= ms=`, `pause instId= paused=`,
`speed instId= speed=`, `resync instId=`, `scrubber instId= visible=`). The pack must not re-declare the imports: Openplanet compiles a
dependency's `exports` files into the dependent module.

## Build

```
SKIP_RELOAD=1 ./build.sh dev     # lint (openplanet-lsp, MP4 type db) + stage to ~/Openplanet4/Plugins
./build.sh dev                   # same, plus hot-reload via tm-remote-build
./build.sh release               # produce tm-ghosts2-<version>.op
```

`build.sh` runs `openplanet-lsp check --game-target MP4` first and refuses to stage on errors.

## Known limitations

- **Playback control hooks engine build 2019-11-19_18_50** (`RaceGhostRecord_UpdatePlaybackTime` at
  image offset 0x848f20; the prologue bytes are checked before hooking and the feature disables
  itself on a mismatch). The script API itself only offers the forward-only `uint OffsetMs` of
  `RaceGhost_AddWithOffset`.
- **Ghost identity is a heuristic.** `CGameCtnGhost.Id` is `0xffffffff` for engine-loaded
  ghosts, so plugin ghosts are matched to `RaceGhosts` rows by stripped nickname + race time.
  Two identical runs by the same name are matched 1:1 by count, but cannot be told apart.
- **`DataFileMgr` is documented by Nadeo as "only available for local solo modes"**, so
  replay loading and saving are expected to be unavailable online.
- **Saving writes `.Replay.Gbx`, not `.Ghost.Gbx`.** MP4 has no `Ghost_Save`; only
  `Replay_Save(Path, Map, Ghost)`. It is passed a bare filename, which the engine resolves
  inside the Replays folder (that is how Nadeo's own save-ghost UI calls it).
- Only ghosts loaded *by this plugin* can be removed individually, spectated or saved —
  engine ghosts have no instance id and no `CGameGhostScript` handle we can reach.

## Notes for agents

Verified against `~/Openplanet4/Openplanet.h` + `Openplanet4.json` (engine build
`2019-11-20 04:50:52`, Openplanet 1.29.14) and the research notes under
`~/src/openplanet/research/mp4/`.

**Exists and is used:**

| API | Signature |
|---|---|
| `CTrackManiaRaceRules.RaceGhost_Add` | `MwId (CGameGhostScript@ Ghost, bool DisplayAsPlayerBest)` |
| `CTrackManiaRaceRules.RaceGhost_AddWithOffset` | `MwId (CGameGhostScript@, uint OffsetMs)` — offset is **unsigned**, forward-only |
| `CTrackManiaRaceRules.RaceGhost_Remove` / `_RemoveAll` | `void (MwId)` / `void ()` |
| `CGameDataFileManagerScript.Replay_Load` | `CWebServicesTaskResult_GhostListScript@ (wstring Path)`, `.Ghosts` is `MwFastBuffer<CGameGhostScript@>` |
| `CGameDataFileManagerScript.Replay_Save` | `CWebServicesTaskResult@ (wstring Path, CGameCtnChallenge@ Map, CGameGhostScript@ Ghost)` |
| `CGameDataFileManagerScript.TaskResult_Release` | `void (MwId TaskId)` — also on `ScoreMgr` |
| `CGameScoreAndLeaderBoardManagerScript.Map_GetRecordGhost` | `CWebServicesTaskResult_GhostScript@ (MwId UserId, string MapUid, string Context)`, `.Ghost` |
| `CWebServicesTaskResult` | `Id`, `IsProcessing`, `HasSucceeded`, `HasFailed`, `IsCanceled`, `ErrorType/Code/Description` |
| `CGamePlaygroundUIConfig` | `SpectatorForcedTarget`, `SpectatorAutoTarget`, `ForceSpectator`, `SpectatorForceCameraType`, `UISequence` (all writable) |
| `CGameGhostScript` | only `Id`, `Result` (`CTmRaceResultNod`, `.Time` is `int`), `Nickname` |
| `CGameCtnGhost` | `GhostLogin`, `GhostNickname`, `RaceTime`, `NbRespawns`, `EventsDuration`, `Validate_*` |
| `MwId` | value type with `MwId()`, `MwId(uint)`, `opEquals`, `GetName/SetName`, `.Value` |
| `CMwNod.Id` | every nod has an `MwId Id`, which is how the local user id is obtained from `rules.Users[i]` |

**Does not exist in MP4** (present in TM2020 / Ghosts++, do not port):

- `NGameGhostClips_SMgr`, `CGameGhostMgrScript` — no ghost-clip manager at all.
- `CGamePlaygroundUIConfig.Spectator_SetForcedTarget_Ghost` — write the plain
  `SpectatorForcedTarget` field instead.
- `CSmArenaRulesMode.Ghosts_SetStartTime` — no start-time setter; remove and re-add with an
  offset.
- `DataFileMgr.Ghost_Save` — only `Replay_Save`.
- `CGamePlaygroundScript.ModeName` — there is no mode-name string. Detect the mode by
  `app.PlaygroundScript` being a `CTrackManiaRaceRules`; `ServerModeName` is empty offline.
- MLHook and any `SendCustomEvent` event bus — the solo mode chain has none; drive
  `CTrackManiaRaceRules` methods directly.

**Verified in-game (2026-09-07, TimeAttack on A01):**

1. `LocalUserId()` (`rules.Users[i].Id` matched by `GetLocalLogin()`) is the id
   `Map_GetRecordGhost` wants: `Load my PB` returns the local record ghost.
2. `SpectatorForcedTarget` written from Openplanet sticks; the camera follows the ghost until
   `Stop spectating` restores the saved values.
3. In script modes `RaceGhosts` stays empty, so plugin ghosts are tracked per instance with
   `RaceGhost_GetStartTime` / `IsVisible`; the nickname+time match is only used for the
   classic race list.
4. `Replay_Save` accepts a bare filename and writes under the game's `Replays` folder
   (`Replays/Ghosts2/<name>.Replay.Gbx`); `Replay_Load` reads it back.
5. Releasing a task result while holding its `CGameGhostScript@` keeps the ghost usable
   (medal/PB ghosts are added after `TaskResult_Release`).
