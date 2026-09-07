# Changelog

Newest first. One line per change; details live in README.md / TASKS.md.

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
