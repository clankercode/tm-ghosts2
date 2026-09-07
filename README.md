# Ghosts2

Load, scrub, lock, spectate and save race ghosts in **ManiaPlanet 4 / TrackMania 2**, from an
[Openplanet](https://openplanet.dev) plugin. A clone of the TM2020 plugin
[Ghosts++](https://openplanet.dev/plugin/ghostspp) rebuilt on the MP4 engine.

> ## 📦 Download
> **Grab the `.op` file from the [Releases page](https://github.com/clankercode/tm-ghosts2/releases/latest)**
> and drop it into your `Openplanet4/Plugins` folder (Documents › ManiaPlanet › Openplanet4 › Plugins on
> Windows). Reload plugins from the Openplanet menu, or restart the game.

![Following the pack: Follow camera behind the slowest ghost, scrubber at the bottom](docs/img/hero.png)

## Features

- **Load ghosts from anywhere** — your PB, the author / gold / silver / bronze medal ghosts, any
  `.Replay.Gbx` / `.Ghost.Gbx` from a folder browser over your Replays folder, and any entry of the
  map's world / zone **leaderboard** (paged, one click per record).
- **Scrub every ghost like a video** — pause, step, seek on a time bar, speeds from ¼x to 4x, and a
  resync that hands the clock back to the game. A paused car is perfectly still and seeks land on
  the exact millisecond: Ghosts2 hooks the engine's per-record clock instead of restarting ghosts.
- **Ghost lock** — one padlock drives every started ghost together and keeps them in sync, so a
  whole leaderboard pack replays as one and late starters join at the group time.
- **Spectate with the camera you want** — Replay (the engine's cinematic clip), Follow with
  **Cam 1 / 2 / 3** (behind far, behind close, internal), the free-fly camera, or the game's own
  spectator controls. Right-click the eye for a picker of every loaded ghost.
- **Stop spectating cleanly** — either restart together with the ghosts (like Ghosts++), or carry on
  from where you are: Ghosts2 knows how to end the engine's spectator camera clip without a respawn.
- **Save** any loaded ghost back to a replay file, remove ghosts one by one or all at once, and keep
  ghosts alive across the mode script's periodic `RaceGhost_RemoveAll` and plugin reloads.
- **Scriptable** — exports for other plugins and a command pack for scripted control.

| Follow camera, Cam 2 | Internal camera (Cam 3) |
|---|---|
| ![Follow camera, close](docs/img/follow-cam2.png) | ![Internal camera over the jump](docs/img/internal.png) |

| Replay camera (engine clip) | Playback tab |
|---|---|
| ![Replay camera on the banked turn](docs/img/replay-cam.png) | ![Playback tab: mixed speeds, one paused, one spectated](docs/img/playback-tab.png) |

| Load tab: medals, leaderboard, replay files | Ghosts tab |
|---|---|
| ![Load tab with the world leaderboard](docs/img/load-tab.png) | ![Ghosts tab](docs/img/ghosts-tab.png) |

## Using it

Open the window from the Openplanet **Plugins › Ghosts2** menu. Four tabs:

- **Load** — *Load my PB*, *Load author ghost* (Gold / Silver / Bronze), the leaderboard table
  (*Fetch*, then **+** on a record), and the replay folder browser (**+** on a file).
- **Playback** — one row per started ghost: spectate / scrubber / pause / speed / resync buttons,
  the name, the ghost's time over its race time, and state icons (eye = spectated, clock = clock
  owned by Ghosts2, padlock = in the lock group). The top row toggles the lock, pauses, resumes or
  releases every started ghost at once, and resets the camera.
- **Ghosts** — what the race holds and what Ghosts2 loaded, with per-row remove, re-add, spectate and
  save, plus *Remove all* and the engine's own medal/PB ghost toggles.
- **State** — the current playground, map and hook status.

### Scrubber

The strip at the bottom of the screen opens by itself for the first ghost you load and follows the
Ghosts++ rules: visible during the race countdown, while you spectate and while you drag it; otherwise
it hides 1.5 s after the mouse leaves it, and hovering the (invisible) strip area brings it back
(settings *Scrubber → Show during the race countdown / Auto-hide / Hide delay*).

Buttons: step back / play-pause / step forward (step scales with the speed), speed (click faster,
right-click slower), resync, **eye** (spectate this ghost; right-click for a picker of every ghost;
with the lock on it shows whichever ghost is spectated), **camera** (Replay / Follow / FreeCam / Game,
right-click cycles backwards; in Follow a **Cam 1/2/3** button appears), and the **padlock**.
Right-click on the time bar toggles pause.

### Ghost lock

On by default (*Scrubber → Lock all ghosts by default*). With the lock on, the scrubber, the Playback
rows and the exports drive every started ghost: pause, seek, step and speed apply to all of them, and
each frame the others mirror the scrubber ghost's clock.

### Spectating

The eye writes the ghost's instance id into the game's `SpectatorForcedTarget` and forces you into
spectator mode (what Nadeo's own replay-focus UI does). The camera button picks the spectator camera:

| Camera | What you get |
|---|---|
| **Replay** | the engine's cinematic camera clip |
| **Follow** | chase cam on the ghost; **Cam 1** behind far, **Cam 2** behind close, **Cam 3** internal |
| **FreeCam** | the free-fly camera (cam 7 in TM2020 terms), moved with the game's own free-cam keys |
| **Game** | no override: the game's spectator camera controls apply |

Stopping either **restarts you and the ghosts together** (setting *Spectate → Restart when you stop
spectating*, on by default, same as Ghosts++) or, with that setting off, ends the spectator camera clip
in place so you carry on without a restart. *Reset camera* on the Ghosts / Playback tabs points the
camera back at your car if anything ever leaves it on a ghost.

## Settings

All under **Openplanet › Settings › Ghosts2**: replay folder, auto re-add, time control on/off,
scrubber visibility and step size, lock default, spectate options (force spectator, restart on stop,
respawn delay, camera type, Follow camera, classic-race camera hook), leaderboard zone.

## Exports and command pack

Ghosts2 exports `Ghosts2::ListGhosts`, `LoadReplay`, `LoadPB`, `LoadMedal`, `Remove`, `RemoveAll`,
`Spectate`, `StopSpectating`, `StopSpectatingEx(respawn)`, `State`, `ShowWindow`, `SelectTab`,
`MoveWindow`, `GetGhostTime`, `Seek`, `SetPaused`, `SetSpeed`, `Resync`, `ShowScrubber`, `SetLockAll`,
`SetCameraType`, `SetFollowCam`, `ResetCamera` and the leaderboard calls for other Openplanet scripts
(see `src/Exports.as`). The optional pack in `mp4pack/` (plugin id `tm-ghosts2-mp4pack`) exposes the same
operations to the `tm-mp4-control` plugin as `ghosts2.*` commands
(`list`, `state`, `load_replay`, `load_pb`, `load_medal`, `lb_fetch`, `lb_list`, `load_lb`, `remove`,
`remove_all`, `spectate`, `stop_spectating [respawn=]`, `cam type=`, `follow_cam cam=`, `cam_reset`,
`lock all=`, `ghost_time`, `seek`, `pause`, `speed`, `resync`, `scrubber`, `show_window`). The pack must
not re-declare the imports: Openplanet compiles a dependency's `exports` files into the dependent module.

## Building from source

```
SKIP_RELOAD=1 ./build.sh dev     # lint (openplanet-lsp, MP4 type db) + stage to ~/Openplanet4/Plugins
./build.sh dev                   # same, plus hot-reload via tm-remote-build
./build.sh release               # produce tm-ghosts2-<version>.op
```

`build.sh` runs `openplanet-lsp check --game-target MP4` first and refuses to stage on errors.
`tools/showcase-shots.sh` and `tools/readme-shots.sh` regenerate the screenshots through the command pack.

## How it works (engine notes)

- **Playback control** hooks the engine's per-record clock update (`RaceGhostRecord_UpdatePlaybackTime`,
  `Dev::Hook`) and sets each record's StartTime from the exact tick time, so paused cars do not
  vibrate and seeks land exactly. Resync hands the clock back; a respawn rebuilds the records, which
  releases any owned clock. The setting *Time control* turns the hook off.
- **Auto re-add** — the stock solo mode calls `RaceGhost_RemoveAll()` on every phase transition.
  Ghosts2 keeps the `CGameGhostScript@` handles and puts them back, rate limited, giving up after a
  few failed attempts so it never fights the mode script. `RaceGhost_Add` takes effect at the next
  (re)spawn: the engine keeps a script-facing add list and a live copy rebuilt when the player spawns,
  and Ghosts2 tracks (and, after a reload, adopts) ghosts from both.
- **Stop spectating** — forcing the spectator makes the engine play a spectator camera clip on the
  ghost (`CGameCtnMediaClipPlayer` on the game terminal) that clearing the UI config never stops; only
  a (re)spawn does, or a ref-counted release of the terminal's clip slot a few frames after the UI
  config restore has reached the engine (the no-restart mode). With the Follow / FreeCam / Game cameras
  the camera system's auto target also stays on the ghost, so stopping writes it back to your car.
- **Follow Cam 1/2/3** — the engine hard-codes the far chase cam for the forced Follow spectator
  camera; Ghosts2 writes the chosen vehicle cam id into the camera system from its camera-target hook,
  which runs right before the camera update reads it.
- **Classic race camera hook** — in the campaign race (`CTrackManiaRace1P`) the engine never copies
  `SpectatorForcedTarget` into the camera, so Ghosts2 hooks the camera target resolver and writes the
  ghost's id into the forced-target slot right before it is read (setting *Camera hook (classic race)*).
  All hooks are removed on unload.

The research behind these lives in the `openplanet/research/mp4/` notes (Ghidra decompiles and runtime
notes; engine build `2019-11-19_18_50`, Openplanet 1.29.14).

## Known limitations

- **The hooks target engine build 2019-11-19_18_50.** Prologue bytes are checked before hooking and each
  feature disables itself on a mismatch; the script API alone only offers the forward-only
  `RaceGhost_AddWithOffset`.
- **Ghost identity is a heuristic** for engine-loaded ghosts (`CGameCtnGhost.Id` is `0xffffffff`), so
  they are matched by stripped nickname + race time.
- **`DataFileMgr` is documented as "only available for local solo modes"**, so replay loading and saving
  are expected to be unavailable online.
- **Saving writes `.Replay.Gbx`** (MP4 has no `Ghost_Save`), under `Replays/Ghosts2/`.
- Only ghosts loaded by Ghosts2 (or adopted from the race) can be removed individually, spectated or
  saved; the engine's own medal/PB ghosts have no instance id.

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
| `CGameDataFileManagerScript.Ghost_Download` | `CWebServicesTaskResult_GhostScript@ (string FileName, string Url)` — leaderboard entries carry both |
| `CGameDataFileManagerScript.TaskResult_Release` | `void (MwId TaskId)` — also on `ScoreMgr` |
| `CGameScoreAndLeaderBoardManagerScript.Map_GetRecordGhost` | `CWebServicesTaskResult_GhostScript@ (MwId UserId, string MapUid, string Context)`, `.Ghost` |
| `CGameScoreAndLeaderBoardManagerScript.MapLeaderBoard_GetPlayerList` | `(MwId(0), mapUid, "", zone, offset, count)` → `CGameNaturalLeaderBoardInfoScript` entries |
| `CWebServicesTaskResult` | `Id`, `IsProcessing`, `HasSucceeded`, `HasFailed`, `IsCanceled`, `ErrorType/Code/Description` |
| `CGamePlaygroundUIConfig` | `SpectatorForcedTarget`, `SpectatorAutoTarget`, `ForceSpectator`, `SpectatorForceCameraType`, `UISequence` (all writable) |
| `CGameGhostScript` | only `Id`, `Result` (`CTmRaceResultNod`, `.Time` is `int`), `Nickname` |
| `CGameCtnGhost` | `GhostLogin`, `GhostNickname`, `RaceTime`, `NbRespawns`, `EventsDuration`, `Validate_*` |
| `MwId` | value type with `MwId()`, `MwId(uint)`, `opEquals`, `GetName/SetName`, `.Value` |
| `CMwNod.Id` | every nod has an `MwId Id`, which is how the local user id is obtained from `rules.Users[i]` |

**Does not exist in MP4** (present in TM2020 / Ghosts++, do not port):

- `NGameGhostClips_SMgr`, `CGameGhostMgrScript` — no ghost-clip manager at all.
- `CGamePlaygroundUIConfig.Spectator_SetForcedTarget_Ghost` — write the plain `SpectatorForcedTarget` field instead.
- `CSmArenaRulesMode.Ghosts_SetStartTime` — no start-time setter (Ghosts2 hooks the clock instead).
- `DataFileMgr.Ghost_Save` — only `Replay_Save`.
- `CGamePlaygroundScript.ModeName` — detect the mode by `app.PlaygroundScript` being a `CTrackManiaRaceRules`.
- MLHook and any `SendCustomEvent` event bus — drive `CTrackManiaRaceRules` methods directly.

**Verified in-game (TimeAttack on A01, and the classic campaign race):**

1. `LocalUserId()` (`rules.Users[i].Id` matched by `GetLocalLogin()`) is the id `Map_GetRecordGhost` wants.
2. `SpectatorForcedTarget` written from Openplanet sticks; the camera follows the ghost until the values are restored.
3. In script modes `RaceGhosts` stays empty, so plugin ghosts are tracked per instance with
   `RaceGhost_GetStartTime` / `IsVisible`; the nickname+time match is only used for the classic race list.
4. `Replay_Save` accepts a bare filename and writes under the game's `Replays` folder; `Replay_Load` reads it back.
5. Releasing a task result while holding its `CGameGhostScript@` keeps the ghost usable.

## Credits

- [Ghosts++](https://openplanet.dev/plugin/ghostspp) (TM2020) for the feature set and UI this plugin imitates.
- **FortTM** for the leaderboard ghost flow (`MapLeaderBoard_GetPlayerList` with `MwId(0)`, an empty context
  and a zone name; `FileName`/`ReplayUrl` on each entry; `Ghost_Download` taking them directly).
- Created by [Max Kaye (XertroV)](https://xk.io) + AI.

## License

Dual-licensed under the [Unlicense](https://unlicense.org) and
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/), at your option. See `LICENSE`.
