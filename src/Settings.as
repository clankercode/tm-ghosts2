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

[Setting hidden]
bool S_ScrubLockAll = false;

[Setting category="Spectate" name="Set ForceSpectator" description="Puts the local player into spectator so the forced target is actually followed."]
bool S_SpectateForceSpectator = true;

[Setting category="Spectate" name="Camera hook (classic race)" description="Hook the camera target resolver so the chase cam follows the spectated ghost in the classic campaign race too (the engine ignores SpectatorForcedTarget there)."]
bool S_CameraHook = true;

[Setting category="Spectate" name="Camera type" min=0 max=2 description="SpectatorForceCameraType; Nadeo's replay cam loop cycles 0/1/2."]
uint S_SpectateCameraType = 0;

[Setting category="Spectate" name="Also set UISequence = EndRound" description="Mirrors Nadeo's StartReplaySequence(). May fight the running mode script; off by default."]
bool S_SpectateEndRoundSequence = false;
