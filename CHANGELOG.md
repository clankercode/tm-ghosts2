# Changelog

Newest first. One line per change; details live in README.md / TASKS.md.

## 0.6.0 - "Bring Your Own Ghost"

Everything here comes from a player's report against 0.2.0 (thanks, Juesto) - four of the five things they
hit were still real on 0.5.1.

- 2026-09-08: **Your own ghost is on the track when you get there.** Setting *Loading -> Load my PB when I
  enter a map* (on by default) loads your personal best once per map, which is what Ghosts++ does and what
  made Ghosts2 look inert until you found the Load tab. It skips itself when your ghost is already in the
  race (the campaign challenge card's PERSONAL RECORD loads it too, and adding on top of that would give you
  two of you), and in the legacy solo playground, which refuses added ghosts anyway. It never notifies and
  never warns: something that happens by itself on every map must not interrupt, and "this map has no
  personal best yet" is unremarkable rather than an error. This also answers "it doesn't survive restarts" -
  the retained list is still dropped on a map change (those ghosts belong to the map you loaded them for),
  but your own ghost now comes back by itself when you return.
- 2026-09-08: **A replay from another map is refused instead of silently driving through the scenery.** The
  `CGameGhostScript` that `Replay_Load` returns carries no map identity at all - only a nickname, a time and
  checkpoints - so there was nothing to check against. The game's own replay index has it:
  `CGameCtnApp.ReplayRecordInfos` holds a row per catalogued replay with its `MapUid`, and its `FileName` is
  relative to the Replays folder, so it matches as a suffix of the absolute path the browser uses. A file the
  index has never seen still loads: Ghosts2 only refuses a map it can positively identify as the wrong one.
  *Loading -> Allow ghosts from other maps* turns the refusal off, because watching a ghost drive a line from
  somewhere else is genuinely funny.
- 2026-09-08: **The replay browser says who drove each file and what they got**, from the same index, and
  greys out the ones belonging to another map with an `[another map]` tag - so the wrong file is visible
  before you click it, not after. Resolved once per listing and re-resolved when you change map, never per
  frame.
- 2026-09-08: **A log line that repeated about once a second.** The "ignoring race ghost with no finished
  time and no script handle" trace sat in the adoption scan, which revisits the race's add lists every scan,
  and the branch `continue`d without recording anything - so unlike every other adoption path (which dedups
  by inserting into the tracked list) it had nothing to stop it firing again a second later, for as long as
  that entry was in the race. It is now said once per instance id. Note this is a sibling of, not the same
  bug as, the "giving up re-adding" burst that 0.3.0 fixed.
- 2026-09-08: The scrubber's Respawn tooltip still promised "unspawn + respawn the local player", and a
  comment in `Spectate.as` still said to unspawn first. 0.5.0 established that the unspawn is exactly the
  thing that must never happen (it costs you the car and the challenge card in `CampaignSolo`); both now say
  what the code actually does.
- 2026-09-08: The update check is verified on Trackmania Turbo as well (it fetched `v0.5.1`, reported up to
  date, and left the daily gate closed).

## 0.5.1 - "Once a Day Keeps the Rate Limit Away"

- 2026-09-08: **Ghosts2 tells you when there is a new version.** It asks the GitHub releases API at most
  once every 24 hours and shows a line at the top of the window, with *Open releases page* / *Copy link*,
  while a newer release exists. Setting *Updates → Check GitHub for a new release* (on by default) turns it
  off; *State → Check for updates now* asks immediately. The whole design is about the shared
  unauthenticated GitHub budget of 60 requests an hour per IP: the daily gate is a **persisted wall-clock
  timestamp**, so restarting the game or reloading the plugin buys no extra request; the timestamp is
  written **before** the request goes out, so a timeout, an error or a crash mid-flight still consumes the
  day instead of becoming a retry loop; a clock that has moved backwards counts as "never checked" rather
  than locking the check out; and the notification fires once per newly discovered version, so an update
  you chose not to install does not nag you again tomorrow. Between checks, `Update()` costs one integer
  compare per frame and one clock read per minute.
- 2026-09-08: **`Meta::ExecutingPlugin()` inside an export returns the *caller's* plugin, not yours.** The
  first cut of the update check compared the latest release against `Meta::ExecutingPlugin().Version` and
  so reported "update available" to any plugin that called `Ghosts2::State()` - the command pack's own
  0.1.0 was being compared against Ghosts2's releases. The version is now captured once at module init
  (`PluginVersion` in `Main.as`), like `PluginName` already was. Same trap as `Dev::Hook` from an export.
- 2026-09-08: `ghosts2.state` reports `updateCheckEnabled`, `updateLastCheck`, `updateCheckDue`,
  `updateLatestVersion`, `updateAvailable` and `updateLastError`, and `tools/tm2-smoke.sh` asserts that the
  daily gate is actually holding - a broken gate would be invisible except as GitHub rate-limit errors
  much later.

## 0.5.0 - "Turbo Had a Script All Along"

- 2026-09-08: **Correction to 0.4.0: Turbo does have a mode script.** The "no mode script at all" reading
  came from the legacy `CTrackManiaRace1P` playground, which is equally ruleless on ManiaPlanet 4. Enter a
  map through the campaign flow and the playground is a `CTrackManiaRaceNew` driven by a real
  `CTrackManiaRaceRules` (`ServerModeName` `TMC_CampaignSolo`) with the whole `RaceGhost_*` surface,
  `SpawnPlayer`, `UIManager`, `DataMgr` and `ScoreMgr`. Everything built on that assumption is now
  rebuilt on the real thing: **adding ghosts, restarting to start them, playback control, the lock, the
  scrubber, removal, re-add and saving all work on Turbo.** Live smoke test: 19/19.
- 2026-09-08: **Playback control on Turbo needs no hook.** Nothing there rewrites a ghost record's start
  time per frame, so Ghosts2 holds `record + 0x0c = rules.Now - wanted` from its own `Update()`. Measured
  on campaign 003: a paused ghost holds its millisecond over 3 s, seeks land exactly, 2x measures 2.1x.
  A ghost whose clock Ghosts2 owns now also *reports* the time it is being held at rather than
  recomputing it from a race clock that has moved on since the last write - that lag alone made a held
  ghost look like it was creeping forward by tens of milliseconds.
- 2026-09-08: **Never unspawn to restart a run.** `SpawnPlayer` on an already-spawned player is enough to
  make the engine rebuild the ghost playback records, in every mode tried on both games - the older claim
  that the unspawn was required was wrong. And the unspawn is actively harmful: in `CampaignSolo` (the
  mode behind the game's own SOLO campaign) it takes the car away, drops the map's challenge card back
  over the track and discards every later `SpawnPlayer` on the same frame; on Turbo it drops the
  playground to the arcade attract mode and never comes back.
- 2026-09-08: **An add made before your run has started is held, not dropped.** `CampaignSolo` parks the
  car on the track behind the map's challenge card with `IsSpawned` true but `RaceStartTime` 0; asking for
  a spawn from there costs you that screen and starts nothing. Ghosts2 now checks whether there is a run
  to restart at all, holds the restart while there is not, and fires it the moment you begin - so a ghost
  loaded at the card starts with you. This was the last failing check in the MP4 smoke test.
- 2026-09-08: **`Load author ghost` works on Turbo.** Turbo never preloads an author ghost with the map,
  but the map's record table has an Author row whose `GhostUrl` `GhostRetrieve` accepts, so Ghosts2 falls
  back to a records fetch for any medal the map did not preload.
- 2026-09-08: The Turbo Load tab tells the truth about what it is showing: **Map records** instead of
  "Leaderboard (World)" (there is no zone and no second page), your own record row is labelled with your
  name instead of coming back blank, and the paging buttons are gone.
- 2026-09-08: **Saving on Turbo asks first.** There is no replay-file writer, so a save is
  `DataMgr.StoreRecordName` - which writes the ghost into the map's own record table as *your* record.
  That is not something to do on a stray click, so it now takes a confirmation.
- 2026-09-08: Turbo's ghost folder browser explains itself: a profile's `MapsGhosts/` files are ~20-byte
  index stubs rather than ghost data and `GhostRetrieve` takes urls, not paths - so a click on one says
  that instead of "found nothing".
- 2026-09-08: **Controls that cannot do anything are gone rather than dead.** Where the camera cannot be
  pointed at a ghost (Turbo), the spectate eye, *Stop spectating*, *Reset camera* and the scrubber's whole
  camera group are hidden or disabled with the reason, and the Ghosts tab carries one line saying why. The
  ghost counter reads "N engine, M ours" instead of the ambiguous "N in race".
- 2026-09-08: `ghosts2.state` reports `modeName`, `playerSpawned`, `runStarted`, `midLap`, `restartHeld`,
  `restartOffered`, `spawnForAddIn`, `timeCtlReady` and `camReady` - the difference between "the add is
  waiting" and "the add was parked to save your lap" was invisible from the ghost list alone, and it cost
  an hour to work out from the outside.
- 2026-09-08: `tools/tm2-smoke.sh` takes `GAME=turbo`, asserts the right thing in each state instead of
  one shape everywhere (a started run must give every added ghost a playback record; at a challenge card
  the car must still be there afterwards and the restart must be held; where spectating is unavailable it
  must be refused rather than silently no-op), scopes the record and sync checks to ghosts Ghosts2 loaded,
  and clears the ghost list first so leftovers from an earlier run cannot fail it.
- 2026-09-08: `tools/showcase-shots.sh` and `tools/readme-shots.sh` take `GAME=turbo`, crop to whatever
  size the game window actually is, and skip the spectator-camera shots where spectating is unavailable.
- 2026-09-08: README rewritten around what is actually true of Turbo, with Turbo screenshots, the Turbo
  API delta table, the measured record layout, and the four ways to hang or kill the game found today.

## 0.4.0 - "Scriptless in Turbo"

- 2026-09-08: **Ghosts2 builds, loads and runs on Trackmania Turbo** (`GAME=turbo ./build.sh dev`). A new `src/Compat.as` holds every place the two games differ, and the loading and leaderboard paths are rewritten against Turbo's own managers: `CGameDataManagerScript.GhostRetrieve` for replay files, `ScoreMgr.Campaign_GetMapRecordGhost` + `GhostRetrieveFromTaskResult` for the personal best, `DataMgr.RetrieveRecords` -> `Records[i].GhostUrl` for the map's record table (Turbo's leaderboard), `DataMgr.StoreRecordName` for saving. Both managers are reached off the menus' title ManiaApp, because - see below - Turbo has no rules script to hang them on.
- 2026-09-08: ~~**The Turbo headline: Turbo has no mode script at all.**~~ **This was wrong - see 0.5.0.**
  Turbo does have a mode script; the reading below came from the legacy `CTrackManiaRace1P` playground.
  The original entry is kept for the record: `GetApp().PlaygroundScript` is null for the whole life of a solo race (measured 14/14 across a full map load), and the game ships no `*.Script.txt` modes. So Turbo has no `CTrackManiaRaceRules`: no `RaceGhost_Add`, no `SpawnPlayer`, no `CGamePlaygroundUIConfig` spectator controls. The two memory features - the playback clock and the camera-target hook - now say "not implemented on Trackmania Turbo yet" instead of poking 64-bit ManiaPlanet addresses at a 32-bit game, and `LooksLikeNod` refuses every raw pointer there rather than hand an unverified address to Reflection. What replaces the script API is mapped out in `research/turbo/2026-09-08-Turbo-Setup.md` and TASKS.md; adding ghosts will go through `CTrackManiaRace.RaceGhosts`, which the engine copies into its active list at race init with no validation at all (grok's RE).
- 2026-09-08: **Adding a ghost no longer eats the lap you are driving.** The restart that makes a queued ghost start is now skipped while you are actually mid-lap (spawned, past a checkpoint, and not idle); the Ghosts tab offers a "Restart now" button instead, and the status line says the lap was left alone. Setting Loading -> Restart the run when a ghost is added is now Never / Unless mid-lap (default) / Always. The race clock is deliberately not the test: in solo it runs from the end of the countdown whether or not the car moved, so timing on it would suppress the restart exactly when it is wanted.
- 2026-09-08: **Stop spectating leaves a lap alone too**, on the same rule: mid-lap it releases the engine's spectator camera clip instead of restarting you (Spectate -> Restart when you stop spectating is now the same three-way setting).
- 2026-09-08: `./build.sh dev` reloads the `tm-ghosts2-mp4pack` command pack as well - reloading the plugin unloads anything that depends on it, which silently broke the smoke test on every dev cycle.
- 2026-09-08: `tools/tm2-smoke.sh` no longer depends on where the replay browser was left by a previous run.

## 0.3.0

- 2026-09-08: **The replay browser lists files again.** It classified entries with `IO::FolderExists`, which in Openplanet is the same "does this path exist" predicate as `IO::FileExists` and answers true for ordinary files - so every `.Replay.Gbx` was drawn as a folder, the file list was always empty (nothing could be loaded at all), and clicking one asked for `<the file>/` and reported "Folder not found". Entries are now classified by the trailing separator that `IO::IndexFolder` puts on directories; a click on a ghost file loads it instead of stranding the browser, and a failed navigation keeps the previous listing on screen. Reported by Juesto.
- 2026-09-08: Ghosts2 no longer adopts the local player's own live recording. The solo mode scripts put it in the race with `RaceGhost_Add`, it has no finished time so no script handle can ever be recovered for it, and every mode phase change re-added it under a new instance id - producing a dead row plus five "giving up re-adding" warnings each time, an ever-growing ghost list and 30-50 ms frame hangs. A ghost with no script handle now also gives up re-adding at the first attempt instead of the fifth, with one trace instead of five warnings.
- 2026-09-08: Removing a ghost is remembered by identity (nickname + time), not only by instance id, so a ghost the mode re-adds under a fresh id after a phase change stays removed. The game's own race ghosts cannot be taken out of the race at all: Ghosts2 now checks whether the removal actually landed and says so plainly instead of dropping the row and letting it reappear. `Ghosts2::Remove` (and the pack's `remove`) reach engine ghosts at all now - they were silently unreachable.
- 2026-09-08: New export `Ghosts2::Browse(dir)` / pack `ghosts2.browse dir=`: the replay browser's listing as data, so it can be driven and checked from a script.
- 2026-09-08: A ghost that has been added but has no playback record yet reads **queued**, not "missing" - the engine only builds that record when you (re)spawn. Every status word now has a tooltip explaining it.
- 2026-09-08: The scrubber stays on screen while playback is being held (paused, or at anything other than 1x) instead of relying on a mouse-over test that cannot run while the Openplanet overlay is hidden.
- 2026-09-08: The load buttons are never disabled by the legacy-race heuristic any more - it only prints a warning, so a race it misjudges can still load ghosts. The camera tooltip says that only the "Game" camera leaves your own spectator keys working.
- 2026-09-08: `tools/tm2-smoke.sh` - a repeatable live smoke test (21 checks) covering adds starting, the replay browser, the leaderboard round trip, playback and the lock, spectate/stop and the camera reset, removal, and hook health; it also runs in the legacy solo race, where it checks the engine-ghost paths instead.
- 2026-09-08: `build.sh` takes `GAME=turbo` (stage into `~/OpenplanetTurbo`, `--game-target TURBO`, RemoteBuild on the Turbo port) - groundwork for Trackmania Turbo support.

- 2026-09-08: The leaderboard cache belongs to one map: it is dropped when the map changes and the Load tab fetches the new map's board by itself (up to 6 tries, 6 s apart - right after a map load the game answers "Unable to update leaderboard" for a good ten seconds). The status line clears on a map change too.
- 2026-09-08: Removing a ghost sticks. `RaceGhost_Remove` only takes it out of the script-facing list; the live copy keeps playing it until the next spawn, and adoption read it straight back in. Removed instance ids are now skipped until the engine really drops them, and the status says the ghost stops driving at your next restart.
- 2026-09-08: A rejected add explains itself: in the classic campaign race (`CTrackManiaRace1P`) the `CTrackManiaRaceRules` nod is not the one driving the race (its `Players` list is empty), so `RaceGhost_Add` returns MwId 0 and there is nobody to respawn. The Load tab now says so up front instead of failing per click (a warning only - the buttons stay live, see the later entry).
- 2026-09-08: Adding a ghost restarts your run so it actually plays (setting Loading -> Restart the run when a ghost is added, default on; Restart countdown (ms)). `RaceGhost_Add` only queues the ghost in the race's pending add list and the engine builds its playback record at the next spawn, so a ghost added mid-run used to sit there invisible with no clock forever. Restarts are coalesced over 400 ms, so loading a page of leaderboard ghosts restarts once; the mode-driven auto re-add never triggers one.
- 2026-09-08: A tracked instance that is in neither of the race's add lists is now treated as gone, so it gets re-added instead of lingering: a ghost that never started kept `inRace` set forever and the auto re-add skipped it.
- 2026-09-08: The scrubber draws from `Render()` instead of `RenderInterface()`, so it stays on screen while the Openplanet overlay is hidden (its buttons still need the overlay up to take clicks).
- 2026-09-08: Follow spectator camera can use Cam 1 / 2 / 3 (behind far / behind close / internal): scrubber "Cam N" button next to Follow (click next, right click previous), setting Spectate → Follow camera, export `SetFollowCam`, pack `ghosts2.follow_cam cam=`. The engine hard-codes cam 1 for the forced Follow camera, so the camera-target hook writes the chosen vehicle cam id (`camsys+0x180`) each frame while spectating. Scrubber strip 20% wider.
- 2026-09-08: Stop spectating without a restart (setting Spectate → Restart when you stop spectating = off): Ghosts2 releases the terminal's spectator clip slot itself (`Spectate_DropClipLater`, ref-counted, a few frames after the UI config restore); export `StopSpectatingEx(respawn)`, pack `stop_spectating respawn=false`. Reset camera button also on the Playback tab.
- 2026-09-08: Version 0.2.0; README screenshots (`tools/readme-shots.sh`); Ghosts tab "Reset camera" button.
- 2026-09-08: Stop spectating also resets the camera system's auto target (`camsys+0x48`) to the local vehicle: with the Follow / FreeCam / Game cameras the spectator code aims that id at the ghost and neither clearing the UI config nor the respawn puts it back, so the camera kept following the ghost. Ghosts tab "Reset camera" button, export `ResetCamera`, pack `ghosts2.cam_reset` as a manual escape hatch.
- 2026-09-08: Tooltips go through `AddSimpleTooltip` (`UI_Helpers.as`: wrapped text, explicit window width ≤ 400 px, snug for short messages); the camera tooltip lists one camera per line.
- 2026-09-08: Playback rows have a spectate toggle (eye) too. Camera value 2 is labelled FreeCam (was Track).
- 2026-09-08: Playback moved to its own tab as a table (controls left, name, time right-aligned, state icons) with a lock / pause-all / resume-all / release-all row; pack `show_window tab= x= y=` (exports `SelectTab`, `MoveWindow`) select a tab / move the window for scripted screenshots. First-use window position now accounts for the UI scale.
- 2026-09-08: Ghost and map names render through `Text::OpenplanetFormatCodes` (colours/bold instead of raw `$` codes) in the ghost list, scrubber, leaderboard and State tab; save filenames and log/source strings use the stripped name.
- 2026-09-08: Right-click on the scrubber's eye opens a ghost picker (every loaded ghost, greyed when it has no playback right now, plus Stop spectating).
- 2026-09-08: Spectator camera button on the scrubber (pack `ghosts2.cam type=`, export `SetCameraType`): Replay (0, the engine's camera clip), Follow (1, chase cam), Track (2, track cameras), Game (15, the game's own spectator camera controls). Mapping verified against the live camera-system id; a free-fly camera is still being looked for.
- 2026-09-08: Stop spectating restarts you and the ghosts (setting Spectate → Restart when you stop spectating, default on). Root cause of the stuck camera: forcing the spectator makes the terminal's `CGameCtnMediaClipPlayer` play a spectator camera clip on the ghost, and clearing `ForceSpectator`/`SpectatorForcedTarget` never stops it; only a (re)spawn does (same as Ghosts++). Spectating a finished ghost is refused with a clearer message.
- 2026-09-08: Scrubber shows/hides like Ghosts++ (settings Scrubber → Show during the race countdown / Auto-hide / Hide delay): visible while spectating, dragging, or during the countdown, otherwise for 1.5 s after the mouse was over its area (hovering the hidden strip brings it back); opens by itself for the first loaded ghost. Right-click toggles pause only on the time bar. With the lock on, the eye reflects whichever ghost is spectated.
- 2026-09-08: Ghost lock is on by default (setting Scrubber → Lock all ghosts by default; the padlock is runtime state). Exports / pack `pause`, `seek`, `speed`, `resync` go through the lock too (a member's pause was being undone by the leader every frame).
- 2026-09-08: Adoption also reads the script-facing add list (`race+0x1d0`): a ghost added since the last (re)spawn only lives there until the engine rebuilds the live list, so it was lost on a plugin reload until the next restart.
- 2026-09-08: Ghost lock (scrubber padlock, pack `ghosts2.lock all=`): the scrubber and playback rows drive every started ghost together and keep them in sync (members mirror the leader's time / pause / speed every frame; late starters join at the group time).
- 2026-09-08: Ghosts already in the race but not tracked (plugin reload, the game's own leaderboard dialog) are adopted from the engine's add-entry array and get spectate / time control / remove; script handle recovered from DataFileMgr by nickname+time. Nod pointers are vtable-checked before any Reflection call (a bad `TypeOf` crashed the game).
- 2026-09-08: Leaderboard ghosts (Load tab, exports, pack `lb_fetch/lb_list/load_lb`) via `MapLeaderBoard_GetPlayerList` → `Ghost_Download` → `RaceGhost_Add`; the argument convention, the per-entry `FileName`/`ReplayUrl` and `Ghost_Download` usage are FortTM's research (see README Credits).
- 2026-09-08: Spectate only forces the camera while the ghost has live playback; refuses ghosts with no playback; scrubber Respawn button (script modes) when the ghost has not started.
- 2026-09-08: Classic-race spectate fixed with a hook on the camera target resolver (`CameraTarget.as`, setting Spectate → Camera hook).
- 2026-09-08: Speed cycle 0.01x..4x with right-click cycling backwards; scrubber steps scale with speed (grok helper).
- 2026-09-08: Scrubber: hold the clock while dragging, right-click toggles pause; hidden while the game menu is open.
- 2026-09-08: Smooth pause/seek/speed via a hook on the engine's playback clock (`TimeControl.as`).
