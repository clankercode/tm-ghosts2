# Changelog

Newest first. One line per change; details live in README.md / TASKS.md.

- 2026-09-08: Leaderboard ghosts (Load tab, exports, pack `lb_fetch/lb_list/load_lb`) via `MapLeaderBoard_GetPlayerList` → `Ghost_Download` → `RaceGhost_Add`; the argument convention, the per-entry `FileName`/`ReplayUrl` and `Ghost_Download` usage are FortTM's research (see README Credits).
- 2026-09-08: Spectate only forces the camera while the ghost has live playback; refuses ghosts with no playback; scrubber Respawn button (script modes) when the ghost has not started.
- 2026-09-08: Classic-race spectate fixed with a hook on the camera target resolver (`CameraTarget.as`, setting Spectate → Camera hook).
- 2026-09-08: Speed cycle 0.01x..4x with right-click cycling backwards; scrubber steps scale with speed (grok helper).
- 2026-09-08: Scrubber: hold the clock while dragging, right-click toggles pause; hidden while the game menu is open.
- 2026-09-08: Smooth pause/seek/speed via a hook on the engine's playback clock (`TimeControl.as`).
