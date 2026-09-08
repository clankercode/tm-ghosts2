# Ghosts2 task list (MP4 / TM2 Ghosts++ clone)

Legend: [ ] todo · [~] in progress · [x] done · (who) owner. "pfi" items get appended here.

## Plugin features
- [x] List race ghosts (engine `RaceGhosts` for classic mode; plugin-tracked instances for script modes) (opus subagent, v0)
- [x] Load ghosts from replay files (`Replay_Load` → `RaceGhost_Add`) — API verified in-game via tm-mp4-control (`race_ghost_add source=replay path=Ghosts2/test-silver.Replay.Gbx`, path relative to Replays/); Ghosts2 path verified 2026-09-07 via `ghosts2.load_replay path=Ghosts2/test-silver.Replay.Gbx` (1/1 ghost, starts on respawn)
- [x] Load personal best (`ScoreMgr.Map_GetRecordGhost`) — verified in-game 2026-09-07 via `ghosts2.load_pb` (PB 23.277 by xertrov; `LocalUserId()` via `rules.Users[i].Id` is correct)
- [x] Load author/gold/silver/bronze medal ghost buttons (`Map_GetMultiAsyncLevelRecordGhost`, level 4..1) (grok helper) — user request 2026-09-07
- [x] Spectate a ghost via `UIAll.SpectatorForcedTarget` (+ restore) — verified in-game via tm-mp4-control `spectate`
- [x] **Classic-race spectate** (user bug 2026-09-08 "spectate ghost button does nothing"): the classic race never copies `SpectatorForcedTarget` into the camera. The camera target id lives on `CGameCameraSystem` (`MgrCamera.CamSystems[0]`): +0x48 default (0 = local car), +0x4c forced (0x0ff00000 = none, cleared every frame by `CameraSystem_ClearForcedTarget` 0x140b446e0, which also zeroes +0x6c/+0x188/+0x300), +0x50 current (rewritten from +0xb4 at end of `CameraSystem_UpdateFrame` 0x140b45640); `CameraSystem_ResolveTarget` 0x140b44740 resolves it through `Scene_ResolveEntityById` → vehicle-vis list lookup by GhostInstId. `CameraSystem_SetTarget` 0x140b445e0 (id EDX, forced R8D) is the engine setter — no engine caller refills +0x4c from UIConfig per frame; classic ghost ids (0x0f000000) resolve through the same VehicleVisImpl list as players, so there is no registration divergence. Fix: `CameraTarget.as` hooks the resolver and writes the spectated id into +0x4c (setting `S_CameraHook`). Verified 2026-09-08: chase cam follows the paused silver ghost, stop restores the player cam. Note: `Dev::Hook` must be called from the plugin's own Update (from an export it looks the callback up in the caller's module)
- [x] Auto re-add after the mode's `RaceGhost_RemoveAll` — detection fixed: per-instance `RaceGhost_GetStartTime/IsVisible` queries; only "removed" after the instance previously reported startTime>0 (grok helper)
- [x] **What works in the legacy solo race** (`CTrackManiaRace1P` — the classic Campaigns menu, and `play_campaign_map` without a mode script): the engine's own opponent ghosts are listed, scrubbed, paused, sped up, locked together, spectated and camera-reset exactly as in a script race (14/14 checks of `tools/tm2-smoke.sh` pass there). What does **not** work is *adding* a ghost: its `CTrackManiaRaceRules` nod has an empty `Players` list, `RaceGhost_Add` returns MwId 0 and `SpawnPlayer` has nobody to spawn (measured on A01, A02 and A05, minutes after the race went live). A script-driven race (`CTrackManiaRaceNew`, e.g. `CampaignSolo` or PlayMap with a mode script) takes ghosts normally. The Load tab warns about this but no longer disables anything
- [x] Classic campaign race (`CTrackManiaRace1P`): engine RaceGhosts records found at `race+0x1080` (same 0x98 layout, inst ids 0x0f00xxxx); time control via `CGameCtnGhost+0x40` verified 2026-09-07 (pause ±1 ms, 2x/0.5x rates 2049/512); spectating by that id works. Engine ghosts now get inst ids, playback rows and `ghosts2.*` commands. Still no engine-level add/remove for classic mode (the menu's ghost-opponent dialog does that)
- [x] Ghost time control (pause / seek / speed) — done 2026-09-07 for script modes: Ghosts2 writes the add entry's OffsetMs (`CTrackManiaRaceNew+0xdd0[i]+0x10`, re-read every frame by `CTrackManiaRaceNew_UpdateFrame`; the record's StartTime is rewritten every frame while the player races, so it is not a lever). Verified via pack: pause holds ±2 ms, seek lands within 1 frame, 2x/0.25x rates measured 2055/258 ms per s, works driving and spectating. Exports `GetGhostTime/Seek/SetPaused/SetSpeed`, pack cmds `ghost_time/seek/pause/speed`, Playback UI row
- [x] Adopt untracked race instances (user bug 2026-09-08 "says no ghosts loaded, but there are"): after a plugin reload the RaceGhost_Add'ed instances stayed in the race while the bookkeeping was gone. `Ghosts_AdoptRaceInstances` reads `race+0xdd0[+0xdd8]` (stride 0x18: CGameCtnGhost, displayAsPB, OffsetMs, instId), adopts unknown ids, recovers the CGameGhostScript from `DataFileMgr.Ghosts`. Verified 2026-09-08 (author ghost survives a reload with time control intact)
- [x] Leaderboard ghosts (2026-09-08): `MapLeaderBoard_GetPlayerList` → `Ghost_Download(FileName, ReplayUrl)` → `RaceGhost_Add`; Load-tab section with paging, exports `LeaderboardFetch/Leaderboard/LoadLeaderboard`, pack `lb_fetch/lb_list/load_lb`. Flow credited to FortTM (README Credits, CHANGELOG)
- [x] (superseded by the playback clock hook, which seeks both ways) Ghost offset (forward seek) via remove + `RaceGhost_AddWithOffset(ghost, ms)` + `SpawnPlayer` (verified: offset = seek into the replay, same startTime) — cheap partial scrubber for script modes
- [x] Spectate camera choice (user request 2026-09-08): scrubber camera button cycles `SpectatorForceCameraType` 0 / 1 / 2 / 15. Verified against `camsys+0x180` (live cam id): 0 → cam 3 + forced clip block (the engine's replay camera clip), 1 / 3 / 4 / 5 / 6 → cam 0x12 (chase), 2 → cam 2 (track cameras, `+0x4c` none), 15 → none: the terminal's own `SpectatorCameraType` (`CGameTerminal+0x12c`, enum Replay 0 → cam 3, Follow 1 → cam 0x12, Free 2 → cam 2) and the game's spectator camera controls apply
- [x] Free-fly spectator camera: value 2 (terminal "Free" = cam 2) is the free camera; button label renamed FreeCam 2026-09-08 per user. Static confirmation (grok, research ef9bd27): `Spectate_ComputeCamParams` maps 0 → cam type 0, 1 → 0xe, 2 → cam type 2 with the target zeroed (free-fly), 3..14 clamp to 0xe, 15 → terminal `SpectatorCameraType`; free-cam controls are the `ButFreeCam` / MoveFaster / MoveSlower / ResetDir / ResetRoll action map. grok was asked 2026-09-08 for the static mapping of `Spectate_ComputeCamParams` 0x140a45f10 / `FUN_140e46540` (cam ids 0x12/0x13, 8/9, 2)
- [x] Save ghost: `DataFileMgr.Replay_Save("Ghosts2/x.Replay.Gbx", RootMap, ghostScript)` verified in-game (writes under Replays/); no `Ghost_Save` in MP4
- [x] **Playback smoothness** (user report 2026-09-08): root cause was predicting the engine's next integer-ms frame step from `Update()` (±1-2 ms → ±16 cm wobble). Fixed with `Dev::Hook` on `RaceGhostRecord_UpdatePlaybackTime` (0x140848f20): StartTime is set from the exact tick time inside the hook; paused ghosts are pixel-still, seeks land exactly, speeds integrate engine tick deltas. User confirmed "not stuttering" 2026-09-08; script-mode (TimeAttack) re-test under both hooks 2026-09-08 01:45: paused drift 0, seek exact, 2x = 2087 ms/s, 0.25x = 257 ms/s, spectate/stop OK
- [x] Playback UI (user request 2026-09-08): rows use `AlignTextToFramePadding`, time readout moved after the buttons, Ghosts++-style scrubber strip (`Scrubber.as`: step ±100 ms, play/pause, speed cycle, resync, spectate, slider) opened per ghost
- [x] Playback tab (user request 2026-09-08): own tab, table layout (controls | name | time | state), group row (lock, pause/resume all, release all); screenshot-verified via `show_window tab=playback x= y=`
- [x] Ghost lock (user request 2026-09-08 "lock all ghosts together so the scrubber controls all of them and keeps them in sync"): `ScrubLock.as`, padlock button on the scrubber, `S_ScrubLockAll` (hidden setting), verified with two author ghosts (snap on lock, pause/seek/speed propagate, times identical)
- [x] **Stop spectating leaves the camera stuck** (user bug 2026-09-08, second report): the forced-spectator spectate makes the terminal's `CGameCtnMediaClipPlayer` (`CTrackManiaGameTerminal+0x70`) play a spectator camera clip on the ghost; `CGameCtnPlayground_UpdateCamsAll` pushes its camera block into `camsys+0x190` every frame (`+0x18c = 1`). Clearing `ForceSpectator`/target sets the terminal's target to none but the wanted clip (`Terminal_ComputeWantedSpectateClip`: `+0xd4 != 6 ? +0xd8 : +0xc0 ? : +0xa8`) still equals the current one (`+0x100`), so `Terminal_StopSpectateClip` never runs. Verified with hw watchpoints: a `SpawnPlayer` (respawn) is what stops it (`FUN_140d7f700` → `FUN_140d7e440` → `ClipPlayer_Stop 0x140b52830`). Fix: `Spectate_Stop` restarts the local player (unspawn + spawn, setting `S_SpectateRespawnOnStop`), like Ghosts++ does. Verified 2026-09-08 via pack: clip `+0x2b0` → 0, `camsys+0x18c` → 0, `+0x48` → 0 within 1 s; ghosts restart with the player
- [x] Scrubber visibility like Ghosts++ (user request 2026-09-08): countdown / spectating / dragging / hover with 1.5 s hide delay; auto-open on first ghost; right-click pause only on the time bar; lock-aware eye; lock on by default (`S_ScrubLockDefault`); exports/pack routed through `Ctl_*`
- [x] Leaderboard ghosts lost on reload (user bug 2026-09-08): `RaceGhost_Add` lands in the script-facing list `race+0x1d0` and only reaches the live list `race+0xdd0` at the next (re)spawn; adoption now reads both. Verified: a pending LB ghost survives a reload as "not started", starts on restart
- [x] **Camera stuck on the ghost after stop with Follow / FreeCam** (user report 2026-09-08, third camera bug): with `SpectatorForceCameraType` 1 / 2 / 15 the spectator code sets the camera system's *auto* target (`camsys+0x48`) to the ghost id; clearing the UI config and the respawn leave it there (the Replay clip path re-targets the local vehicle when the clip stops, which is why type 0 worked). Fix: `CamTarget_ResetAfterStop` writes `+0x48 = 0` (local vehicle) at stop and polls through the respawn window (`CamSys_Ptr`: playground `+0xa00` terminals → terminal `+0x30`). Verified via pack: Follow spectate → stop: `+0x48` 0x0fe00002 → 0 within 0.3 s, stays 0 after the respawn, camera on the car
- [x] Non-respawn stop-spectate (2026-09-08): `Spectate_DropClipLater` releases `terminal+0xa8` (guard: nod, refcount 2..64; `nod+0x10` per grok's research 6a12f69) then zeroes the slot, **3 frames after** the UI config restore — a same-frame drop was re-picked by `Playground_PickTerminalCamClip` via the spectator path (refcount back to 3) because the script setters reach the engine a frame later. Verified via pack (`stop_spectating respawn=false`): Replay clip: `+0xa8/+0x100` → 0, clip player `+0x2b0` → 0, camsys `+0x18c` → 0, cam 0x12, RaceStartTime unchanged; Follow: no clip, auto target reset only. Setting "Restart when you stop spectating" off selects it (default stays on)
- [x] Follow camera Cam 1/2/3 (user request 2026-09-08): vehicle cam ids 0x12 / 0x13 / 0x14 (0x15 internal facing back, 8 / 9 chase variants) verified by forcing `camsys+0x180` while Follow-spectating; forced Follow (`cam type 0xe`) hard-codes 0x12 in `FUN_140e462a0`, the terminal's own Follow reads the key choice at `CGameTerminal+0x44`. Override written from the resolver hook (runs before `CameraSystem_UpdateFrame` reads `+0x180`). Scrubber 20% wider
- [x] **Added ghosts never start** (user bug 2026-09-08): `RaceGhost_Add` only queues the ghost in the race's pending add list (`race+0x1d0`); the engine builds its playback record in `RaceGhost_RebuildRecords_ClassicAndScript` at the next spawn, so a ghost added mid-run stayed invisible with `ghostTime = -1` forever, and the `inRace = !everStarted` rule meant the auto re-add never touched it either. Fix: `Ghosts_RequestSpawnForAdd` / `Ghosts_PumpSpawnForAdd` restart the run 400 ms after the last user-initiated add (setting Loading -> Restart the run when a ghost is added, default on; the mode-driven auto re-add deliberately does not request one), and an instance found in neither add list is now marked `inRace = false` so it gets re-added. Verified live 2026-09-08: `ghosts2.load_lb rank=4` -> status "Restarting the run so the new ghost(s) start", new instance gets a record and plays
- [x] Scrubber hidden with the Openplanet overlay (user bug 2026-09-08): it drew from `RenderInterface()`; moved to `Render()` so it stays up while driving
- [x] **Replay browser listed every file as a folder** (user bug 2026-09-08, Juesto: "why are the ghosts saved as folders … so basically i cant load gbx files"): `Browse_Refresh` classified entries with `IO::FolderExists`, which in Openplanet is the same "does this path exist" predicate as `IO::FileExists` and returns true for files, so `g_browseFiles` was always empty (the `+` load button is only drawn for it) and a click navigated to `<file>/` → "Folder not found". Fixed by classifying on the trailing separator `IO::IndexFolder` puts on directories — verified live via the new `ghosts2.browse` export: `Replays/` → 5 folders / 0 files, `Replays/Ghosts2/` → 0 folders / 1 file
- [x] **Player's own ghost adopted and re-added forever** (Juesto's log: `adopted race ghost <player> (--:--.---) … no script handle` then `giving up re-adding … after 5 attempts`, repeating with a new instance id each mode phase change): the solo mode scripts `RaceGhost_Add` the local player's live recording. Adoption now skips a candidate with no finished time and no recoverable script handle, and the re-add loop gives up at the first attempt for a handle-less ghost instead of the fifth
- [x] **Removing a ghost the game owns** (Juesto: "if i remove a ghost loaded by the game that is active it gets readded"): two mechanisms. Ghosts the mode re-adds under a fresh instance id are now suppressed by identity (`GhostKey` nickname+time), not just by id. The engine's own race ghosts genuinely cannot be removed — `RaceGhost_Remove` is a no-op for them and `Ghosts_SyncEngine` reads them back out of `CTrackManiaRace.RaceGhosts` — so Ghosts2 checks whether the removal landed and says so instead of pretending. Also fixed `Ghosts2::Remove` only searching `g_ghosts`, which made engine ghosts unreachable from the exports/pack
- [x] Status word `queued` for a ghost added but not yet given a playback record (was reported as "missing", which read as "the ghost is broken"); tooltips on every status word
- [ ] **Race HUD stays on screen while spectating, showing a frozen chrono** (Juesto: "ui also doesnt disappear, shows frozen game time"). Attempted and reverted 2026-09-08: setting `OverlayHideChrono` / `OverlayHideSpeedAndDist` / … on `rules.UIManager.UIAll` **does not work** — the writes stick (read back true seconds later) but the chrono and speed gauge stay on screen, and even `OverlayHideAll` changes nothing. So the solo HUD is not driven by that config. Next probe: the client-side `CGamePlaygroundClientScriptAPI.UI` (`clientManiaAppPlayground` was false in this solo context) or the title pack's own manialink
- [ ] Scrubber polish: keyboard shortcuts, remember position (step size setting and the camera button are done)
- [ ] Ghost list extras: distance/delta to player, per-ghost visibility toggle (`RaceGhost_IsVisible` is read-only?), colours
- [x] Exports (`Ghosts2::*`) + tm-mp4-control command pack `ghosts2.*` (grok helper) — user request 2026-09-07; smoke-tested in-game 2026-09-07 (`packs` → ghosts2, `ghosts2.load_medal level=4`, list/state/spectate OK; pack must not re-declare dependency imports)
- [x] README screenshots (`tools/readme-shots.sh` → `docs/img/`), release build `tm-ghosts2-0.2.0.op`, version 0.2.0 — 2026-09-08
- [ ] Ghosts tab: `CTrackManiaRace.RaceGhosts` reads empty in script modes while the adopted ghosts are in the race (the script API array only mirrors the classic race list?) — show the adopted list count instead

## Trackmania Turbo support (started 2026-09-08)

Code that diverges uses `#if MP4` / `#if TURBO` (Openplanet's own defines; Turbo also defines `MANIA32`).
Setup, hashes and API findings: `research/turbo/2026-09-08-Turbo-Setup.md`.

- [x] Turbo binary identified: `TrackmaniaTurbo.exe`, **PE32 i386 (32-bit)**, Ubisoft build in the TM2020 prefix
- [x] Ghidra headless analysis on x-alpha (project `~/re/turbo`, unit `ghidra-turbo-analyze`); MCP scripts
      `research/turbo/tools/ghidra-turbo.sh` + `ghidra_api.sh` on port **18744** (18743 is ManiaPlanet.exe),
      tunnel unit `ghidra-turbo-tunnel.service`
- [x] Openplanet for Turbo 1.29.14 downloaded; installer helper `~/.local/bin/tm-turbo-openplanet {install|remove|status}`
- [x] Turbo API docs mirrored to `~/.llm-general/website-archives/openplanet/turbo-raw/`
- [x] Turbo has the same RaceGhost script API: `CTrackManiaRaceRules.RaceGhost_Add/AddWithOffset/AddModel/Remove/RemoveAll/GetStartTime/GetCurCheckpoint/GetCheckpointTime/IsReplayOver`, plus `CTrackManiaRace.RaceGhosts` and `CTrackManiaRace1PGhosts.MedalGhosts`
- [x] Confirm whether Turbo has `RaceGhost_IsVisible` / `RaceGhost_GetPosition` (grok, binary strings 2026-09-08, research 1f62d45): **both absent** (zero occurrences in TrackmaniaTurbo.exe); full RaceGhost API = Add/AddModel/AddWithOffset/GetCheckpointTime/GetCurCheckpoint/GetStartTime/IsReplayOver/Remove/RemoveAll — use GetStartTime/IsReplayOver for the re-add detection
- [x] Turbo launching and playable under Proton (grok-word-chart-v5rk), Openplanet 1.29.14 installed and **running**, `OpenplanetTurbo.json` dumped. The gate was `UPLAY_ARGUMENTS`: Turbo's dinput8 shim returns from `DllMain` before it opens its own log if that variable is absent (Uplay sets it when it relaunches the game; the R1 stub does not). With it, plus `WINEDLLOVERRIDES=…;dinput8=n,b`, Openplanet loads — both are now defaults in `tm-turbo-launch-uplay`
- [x] Turbo dev loop: RemoteBuild loads and listens on **port 30002**, DeveloperMode set, `research/turbo/tools/{turbo-restart,turbo-set-devmode,turbo-screenshot}.sh`, `openplanet-lsp check --game-target TURBO` finds the typedb by itself
- [x] Port surface measured: `openplanet-lsp --game-target TURBO` on the unmodified MP4 sources gives **20 errors / 8 distinct missing members**. The whole `RaceGhost_*` core survives; the cost is that `CGameDataFileManagerScript` does not exist in Turbo at all and Turbo's `ScoreMgr` has no record/leaderboard/ghost functions (table in `research/turbo/2026-09-08-Turbo-Setup.md`)
- [x] `CGameCtnGhost` → `CGameGhostScript`: no manual wrap needed (grok, research 683d7b0). Turbo's DataFileMgr equivalent is `CGameDataManagerScript` with `GhostRetrieve(url)`, `GhostRetrieveFromPlayer`, `GhostRetrieveFromTaskResult`, `GhostDestroy`, `Ghosts`, `StoreRecord(Name)`
- [x] Turbo control plugin: **`tm-mp4-control` itself now builds for Turbo** (`GAME=turbo ./build.sh dev`, socket **34532**, client `tools/turbocall.py`; MP4-only commands answer "not on Turbo" instead of failing to compile). New commands `maps`, `records`, `replays`, `race_set`, `turbo_probe`, `ghost_retrieve`, `menu_call`, `fid_copy`, `ghost_push`. `PlayMap` works through `ManiaTitleFlowScriptAPI` (Turbo's name for MP4's `ManiaTitleControlScriptAPI`)
- [x] Ghosts2 compiles, loads and runs on Turbo (`src/Compat.as` shim layer; `GAME=turbo ./build.sh dev`; verified live through the `ghosts2.*` pack on 34532), with the loading and leaderboard paths rewritten against Turbo's `DataMgr` / `ScoreMgr`

### Turbo does have a mode script (the 0.4.0 "blocker" was a misreading)

**Corrected 2026-09-08.** The earlier "`PlaygroundScript` is null for the whole life of a Turbo solo race"
measurement was taken in the legacy `CTrackManiaRace1P` playground - which is equally ruleless on
ManiaPlanet 4, so it said nothing about Turbo. Enter a map through the campaign flow (INSERT COIN →
CAMPAIGN → SOLO CAMPAIGN → series → map; scripted in `research/turbo/tools/turbo-enter-campaign.sh`) and
the playground is a `CTrackManiaRaceNew` driven by a real `CTrackManiaRaceRules`, `ServerModeName`
`TMC_CampaignSolo`, with the whole `RaceGhost_*` surface, `SpawnPlayer`, `UIManager`, `DataMgr` and
`ScoreMgr`.

- [x] Turbo ghost loading: gold/silver/bronze from `DataMgr.Ghosts` (preloaded with the campaign map,
      offline, instant), author from `DataMgr.Records[i].GhostUrl` via `GhostRetrieve`, PB from the same
      record table (falling back to `Campaign_GetMapRecordGhost`)
- [x] Turbo leaderboard: `DataMgr.RetrieveRecords(MapInfo, UserId)` → `DataMgr.Records`, presented as
      **Map records** (local, no zone, single page)
- [x] Turbo add + restart: `RaceGhost_Add` then `SpawnPlayer`. **Never `UnspawnPlayer`** - it drops the
      playground to the arcade attract mode and never returns
- [x] Turbo playback clock with no hook: hold `record+0x0c = rules.Now - wanted` from `Update()`. Measured
      on campaign 003: pause holds the millisecond over 3 s, seek exact, 2x = 2.1x. Record layout in
      `research/turbo/2026-09-08-Turbo-Setup.md` and `src/TimeControl.as`
- [x] Turbo smoke test: `GAME=turbo tools/tm2-smoke.sh`, **19/19**
- [x] Turbo screenshots in `docs/img/turbo-*.png`, README section rewritten
- [x] `DataMgr.GhostRetrieve(":Medal:<name>")` is still a hard crash and is not used; the medal ghosts come
      from `DataMgr.Ghosts` and the record table instead, which needs no such url
- [x] The "no ghosts to test with" blocker is gone: the campaign flow preloads the medal ghosts locally and
      `RetrieveRecords` returns the map's five rows offline, Max's own PB included
- [~] **Turbo spectating — target solved, camera not.** A race ghost's instance id is not a `GameMobilId`;
      the ghost's mobil carries the instance id in `CGameMobil.ReplicaId` and the cameras follow
      `CGameMobil.GameMobilId`, so `CGameCtnPlayground.GameScene.GameMobils` is the translation. Measured on
      campaign 001: `instId 0x0FE0000A` → `GameMobilId 11`, written to all seven managed cameras, and it
      sticks
- [ ] **Turbo spectate view-lock — mechanism now known, fix not written.** Per grok's static read of
      `CGameControlCameraTrackManiaRace3_Update` (`0x00d8f890`, Turbo; *their* analysis, not verified here):
      the camera *does* read `FollowedGameMobilId` and resolve it with `FindSceneMobilByGameMobilId`, then
      refuses to follow unless `this+0xA4 != 0`, `SceneMobil+0x0C != 0`, **and the vis is a
      `CSceneMgrVehicleVis` (`IsKindOf 0xA037000`)**. A ghost's SceneMobil fails that last check, which is
      exactly why the id sticks on all seven cameras and the view never moves - the write was never the
      problem. Two routes worth trying, cheapest first: (a) the **Free camera** (`ManagedCams` index 6) is
      reported not to have that gate, so it may follow a ghost as-is - but the engine overwrites a scripted
      `CurrentCam` every frame, so something has to make Free the active camera; (b) hook the gate the way
      MP4 hooks `CameraSystem_ResolveTarget` (`0x140b44740`). Nothing here is verified in game yet
- [ ] ~~What does `CGameControlCameraTrackManiaRace3` read for its target?~~ Answered above. It ignores
      `FollowedGameMobilId` in *effect*, not by not reading it. Ruled out from the script surface: `CamsMaster.CurrentCam` is an index into
      `ManagedCams` (it always matches the `IsActive` entry) but the engine overwrites it every frame even
      when re-asserted from `Update()`; `CGameTerminal.SpectatorCameraType` changes nothing;
      `CGamePlayerCameraSet.DefaultCam` accepts a new `EGameCam` without changing the active camera; and
      `CGamePlaygroundSpectating` has no script fields. Turbo needs MP4's approach - a hook on the camera's
      target resolver (MP4's is `CamResolveTarget` at RVA `0xb44740`, `src/CameraTarget.as`)
- [ ] Turbo engine race ghosts (the game's own medal opponents) list with `instId 0` and no resolvable
      playback record. MP4 resolves them from `race+0x1080/0x1088`; on Turbo `race+0x59c/0x5a0` are
      *wrappers* rather than records, so the record pointer is probably one indirection away
- [ ] Turbo `.Ghost.Gbx` loading is not possible: a profile's `MapsGhosts/*.Ghost.Gbx` are ~20-byte index
      stubs, `GhostRetrieve` takes urls not paths, and `Fids::GetUser` will not resolve them. The browser
      says so rather than failing silently
- [ ] Ways to hang or kill Turbo, all costing a restart, all recorded in the research note: a generic
      Reflection sweep over Turbo nods (hangs the script engine - walk `MwClassInfo.GetMember(name)` by
      name instead), `CTrackManiaMenus.MenuCampaignChallenges_Solo()` (same hang),
      `DataMgr.GhostRetrieve(":Medal:...")`, and reading `CGameCtnReplayRecordInfo.ChallengeId.GetName()` /
      `.Fid.FullFileName`. `DialogQuickChooseGhostOpponents()` kills the process on **ManiaPlanet** too -
      that one is not Turbo-specific
- [ ] Turbo pauses whenever its window loses focus (arcade-port behaviour). Any timing measurement needs
      the window focused, or you measure a stopped clock

### ManiaPlanet 4 findings from the same pass

- [x] **`UnspawnPlayer` is never needed and is harmful.** `SpawnPlayer` on an already-spawned player is
      what makes the engine rebuild the ghost playback records, in TimeAttack and `CampaignSolo` alike.
      Unspawning in `CampaignSolo` takes the car away, drops the map's challenge card back over the track,
      and every later `SpawnPlayer` is discarded on the same frame
- [x] **`CampaignSolo` parks the car behind the challenge card** with `IsSpawned` true and
      `RaceStartTime` 0. That is not a run: a spawn request there costs the player that screen. Ghosts2
      gates the restart on `Race_RunStarted()` and holds a pending restart until a run exists
- [x] `GetLocalLogin()` returns `""` on this install even though authenticated web calls succeed, so the
      local-player lookup falls back to the only player in a solo race

## Update check

- [x] Once-a-day GitHub releases check (`src/UpdateCheck.as`, 2026-09-08, Max's request): at most one
      request per 24 h per install, gated on a **persisted** wall-clock timestamp written *before* the
      request so failures cannot retry; notification once per newly discovered version; banner + link in
      the window; `State → Check for updates now` for a manual ask; state exposed to the pack and asserted
      by the smoke test
- [x] Trap found doing it: `Meta::ExecutingPlugin()` called inside an export resolves to the **caller's**
      plugin. Capture anything about "this plugin" at module init (`PluginVersion` in `Main.as`)

## Turbo playback stutter (fixed, 2026-09-08)

- [x] Root cause: `rules.Now` is not the engine's playback clock. Measured over 90 samples with a ghost held
      at 8000, `EngineNow - RaceNow` ran −88…−39 ms and the rendered elapsed wandered 8017–8123
- [x] Fix without a hook: recover the engine's clock from the record itself
      (`EngineNow = writtenStart + elapsed` at `rec+0x14`), integrate `wanted` with the engine's tick delta,
      and aim the write one tick ahead. Rendered spread 106 ms → 56–62 ms at ~17 fps
- [x] `holdErr` / `holdErrMin` / `holdErrMax` / `tickEst` exported per owned clock, so the error is
      measurable rather than self-confirming
- [x] The residual *was* visible: Max reported "pausing still stutters" against 0.7.0. Turbo ticks ghosts at
      about 30 Hz, so predicting the next tick from `Update()` left a rolling hold error of −9…+16 ms (~0.6 m
      of wobble). Fixed by hooking `TickPlayback` (`0x009116F0`) at the `MOV EDX,0xF4240` five bytes in
      (`0x009116FD`, RVA `0x5116fd`), where ECX is still the record and EAX still `nowMs` — five bytes, no
      relative operand, padding 0. Inside the tick `StartTime = nowMs − wanted` is exact, so the prediction is
      gone. Measured paused at 9000 over a rolling 600-tick window: `holdErr` 0, min 0, max 0. Playback and
      speed re-checked (1x/2x/0.5x = 3110/6200/1550 ms per 3 s); locked ghosts sit at spread 0. The prologue
      is byte-checked before patching and a mismatch falls back to the `Update()` path
- [x] ...and that was still not it (user report 2026-09-08, "still stuttery when paused"). The hook site was
      right; the callback was wrong. Two of the wrapper's three callers (`Physics_Step 0x00e7f4aa`, and
      `UpdateAsync 0x00e828f0` / `0x00e82916`) run every frame off clocks a few ms apart, so `nowMs` is not
      monotonic in the callback. 0.7.1 returned on a backwards step, skipping the StartTime write, so the
      lagging caller rendered from a StartTime one tick stale. Fixed by writing on every call and only
      integrating forward steps
- [x] The metric was the real problem: `holdError` reads 0 by construction on the corrected path (the hook
      derives StartTime from the same `nowMs` the engine subtracts). Ground truth is the rendered pose -
      `rec+0x04` mobil -> `+0x14` scene mobil -> `+0x84` vis entry -> Iso4 at `+0x86c`, position `+0x890`.
      Paused at 49.825 that was oscillating **0.67 m**; after the fix **0.00000 m**. Exported as `pos` on
      each Turbo ghost row and asserted in the smoke suite

## Turbo spectate: grok's static read, not verified in game (2026-09-08)

Reported over c2c from the Ghidra side (research `b45f457`). **None of this is tested; treat as leads.**

- [ ] Cheaper target path: after `SetStartTimeAndActivate`, `rec+0x4` is a `CGameMobil*`, and
      `RegisterGameMobil` writes a dense `GameMobilId` at `mobil+0x0C` (ctor leaves -1). Spectating that id
      needs no instance id and no `ReplicaId` walk
- [ ] `FindGameMobilById`'s "none" is **-1, not 0** — 0 is the local car. `TurboGhostMobilId` returning 0 on a
      miss therefore *follows the player* if written to `FollowedGameMobilId`. Worth hardening even though
      `CamTarget_ApplyTurbo` already refuses 0
- [ ] Engine medal ghosts: `Race_RebuildGhostWrappers` `0x00ed8df0` calls `CreateFromGhost(..., instId = -1)`
      into `race+0x59c` / count `+0x5a0`. The auto-inst free list is `mgr+0x400` (not `+0x24`). Slot 0 gives
      `rec+0x24` instId 0, which *is* a valid `ReplicaId` (only `0x0FF00000` means none) — so `Spectate_Start`
      and `TurboGhostMobilId` refusing 0 means those ghosts can never be spectated
- [ ] `Activate` also runs `AttachMobil` / `FillFollowBox`, so a *started* engine ghost should have
      `SceneMobil+0x84` populated and be Helico-safe — possibly the way past the
      `CSceneMgrVehicleVis` gate recorded above

## Turbo ghosts missing from the list (fixed, 2026-09-08)

- [x] Root cause (user report: "shows my ghost but not the bronze ghost that is also loaded"): two stacked
      faults meant *no* ghost Ghosts2 had not added itself could ever be adopted on Turbo. (a) The add entry's
      ghost handle is at `O_Entry_Ghost` = `+4` on Turbo (32-bit pointer behind a sentinel word) and `+0` on
      MP4 — the constant existed but adoption read a full 64 bits from a fixed `+0`. (b) `LooksLikeNod`
      returned `false` unconditionally on Turbo, so even a correct pointer resolved to nothing and the ghost
      was dropped as "no finished time and no script handle"
- [x] The 32-bit nod signature is now measured, not guessed: the first vtable slot is one shared function for
      every `CMwNod` subclass, at image offset `0x55ce50` on Turbo (`0x141dc0` on MP4). Agreed across App, the
      race, the rules, the map, `DataMgr` and three `CGameCtnGhost`s — and across the unknown add-list
      pointers, which is how we know they were real nods all along
- [x] Side effect cured: because adoption always failed, every plugin reload added a *fresh* copy of your PB
      instead of adopting the one already in the race. Seven had stacked up in one session. A reload now logs
      `adopted race ghost` and auto-load skips
- [x] `Ghosts2::RaceEntries()` / `Ghosts2::NodProbe()` (pack: `ghosts2.race_entries`, `ghosts2.nod_probe`)
      dump the add lists and re-measure the vtable signature — the failure was invisible from script, and the
      offset will move when the game is patched

## Player feedback (Juesto, against 0.2.0)

- [x] **Your own ghost is missing / you have to re-add it by hand / it does not survive restarts** - one
      cause: there was no auto-load. Entering a map now loads your PB once (`S_AutoLoadPB`, on by default),
      skipping when your ghost is already in the race or when the playground refuses adds. Verified on A01
      (loaded and restarted the run so it plays), A02 (no PB - quiet, no retry) and A01 `CampaignSolo`
      (skipped, the challenge card had already loaded it).
- [x] **You can load ghosts from other challenges** - refused now, from `CGameCtnApp.ReplayRecordInfos`
      (`S_AllowOtherMapGhosts` allows it back). Verified both ways live: a B01 replay refused on A01, an A01
      replay still loaded.
- [x] **Log spam** - the "ignoring race ghost" trace re-fired every adoption scan; deduped per instance id.
      Structural fix; the branch did not fire on A01/`CampaignSolo`, so this one is **not** confirmed live.
      Juesto's actual screenshot is unread, and their spam was more likely the "giving up re-adding" burst
      that 0.3.0 already fixed.
- [ ] **"the almost hidden button in the scrubber about the ghosts"** - unresolved: cannot tell which
      control they meant without the screenshot. Most likely the scrubber's **Respawn** button (the only
      scrubber control "about the ghosts" that gates them starting), whose need 0.5.0 largely removed by
      restarting automatically on add. Ask before redesigning anything.
- [ ] Campaign entered through the game's own ghost-opponents dialog is `CTrackManiaRace1P` with a rules
      script that has no players, so adds are refused there; entered with an explicit mode script it is
      `CTrackManiaRaceNew` + `CampaignSolo` and everything works. This is almost certainly Juesto's "campaign
      on stadium immediately worked" vs. not. Worth making the refusal message name the fix more loudly.

## Conventions

- Every release gets a funny/jovial code name alongside the version number (Max, 2026-09-08).

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
