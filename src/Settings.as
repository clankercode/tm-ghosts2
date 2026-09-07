[Setting hidden]
bool S_ShowWindow = true;

[Setting category="Loading" name="Replays folder" description="Blank = the game's own Replays folder (IO::FromUserGameFolder(\"Replays\"))."]
string S_ReplaysFolder = "";

[Setting category="Leaderboard" name="Zone" description="Leaderboard zone passed to MapLeaderBoard_GetPlayerList, e.g. World or a zone path"]
string S_LeaderboardZone = "World";

[Setting category="Leaderboard" name="Records per page" min=1 max=100]
uint S_LeaderboardCount = 10;

[Setting category="Loading" name="Show only .Replay.Gbx / .Ghost.Gbx" description="Uncheck to list every file in the folder."]
bool S_FilterGhostFiles = true;

[Setting category="Auto re-add" name="Re-add ghosts the mode removes" description="LocalTimeAttackBase2 calls RaceGhost_RemoveAll() on phase changes; this puts our ghosts back."]
bool S_AutoReAdd = true;

[Setting category="Auto re-add" name="Scan interval (ms)" min=250 max=10000]
uint S_ScanIntervalMs = 1000;

[Setting category="Auto re-add" name="Give up after N failed re-adds" min=1 max=20 description="Stops an add/remove fight if the ghost never shows up in RaceGhosts."]
uint S_MaxReAddAttempts = 5;

[Setting category="Time control" name="Enable pause / seek / speed" description="Writes the ghost's StartTime in the engine's race-ghost record (script modes only). Turn off if a game update moves the structure."]
bool S_TimeControl = true;

[Setting category="Time control" name="Scrubber step (ms)" min=10 max=5000 description="Step size of the scrubber's back/forward buttons at 1x speed; scales with playback speed (min 1 ms)."]
uint S_ScrubStepMs = 100;

[Setting category="Scrubber" name="Lock all ghosts by default" description="Start with the padlock on: the scrubber drives every ghost together and keeps them in sync (toggle on the scrubber)."]
bool S_ScrubLockDefault = true;

[Setting category="Scrubber" name="Show during the race countdown" description="Ghosts++ behaviour: the scrubber is visible while a ghost is loaded and the race has not started yet, hides once you start driving."]
bool S_ScrubShowBeforeStart = true;

[Setting category="Scrubber" name="Auto-hide" description="Hide the scrubber while driving; it comes back while spectating or when the mouse hovers its area (and stays for the hide delay)."]
bool S_ScrubAutoHide = true;

[Setting category="Scrubber" name="Hide delay (ms)" min=0 max=10000 description="How long the scrubber stays visible after the mouse leaves it."]
uint S_ScrubHideDelayMs = 1500;

[Setting category="Spectate" name="Set ForceSpectator" description="Puts the local player into spectator so the forced target is actually followed."]
bool S_SpectateForceSpectator = true;

[Setting category="Spectate" name="Restart when you stop spectating" description="On: stopping restarts you and the ghosts together (same as Ghosts++). Off: Ghosts2 releases the engine's spectator camera clip itself and you carry on from where you are (no restart)."]
bool S_SpectateRespawnOnStop = true;

[Setting category="Spectate" name="Respawn delay (ms)" min=0 max=5000 description="Countdown before your car starts again after 'Stop spectating'."]
uint S_SpectateRespawnDelayMs = 1500;

[Setting category="Spectate" name="Camera hook (classic race)" description="Hook the camera target resolver so the chase cam follows the spectated ghost in the classic campaign race too (the engine ignores SpectatorForcedTarget there)."]
bool S_CameraHook = true;

[Setting category="Spectate" name="Camera type" min=0 max=15 description="SpectatorForceCameraType: 0 replay (engine camera clip), 1 follow (chase cam), 2 free cam, 15 none (the game's own spectator camera controls apply). The scrubber's camera button cycles these."]
uint S_SpectateCameraType = 0;

[Setting category="Spectate" name="Follow camera" min=1 max=3 description="Vehicle camera used by the Follow spectator camera: 1 behind (far), 2 behind (close), 3 internal. The scrubber's Cam button cycles these."]
uint S_SpectateFollowCam = 1;

[Setting category="Spectate" name="Also set UISequence = EndRound" description="Mirrors Nadeo's StartReplaySequence(). May fight the running mode script; off by default."]
bool S_SpectateEndRoundSequence = false;
