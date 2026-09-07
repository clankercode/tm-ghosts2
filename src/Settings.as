[Setting hidden]
bool S_ShowWindow = true;

[Setting category="Loading" name="Replays folder" description="Blank = the game's own Replays folder (IO::FromUserGameFolder(\"Replays\"))."]
string S_ReplaysFolder = "";

[Setting category="Loading" name="Show only .Replay.Gbx / .Ghost.Gbx" description="Uncheck to list every file in the folder."]
bool S_FilterGhostFiles = true;

[Setting category="Auto re-add" name="Re-add ghosts the mode removes" description="LocalTimeAttackBase2 calls RaceGhost_RemoveAll() on phase changes; this puts our ghosts back."]
bool S_AutoReAdd = true;

[Setting category="Auto re-add" name="Scan interval (ms)" min=250 max=10000]
uint S_ScanIntervalMs = 1000;

[Setting category="Auto re-add" name="Give up after N failed re-adds" min=1 max=20 description="Stops an add/remove fight if the ghost never shows up in RaceGhosts."]
uint S_MaxReAddAttempts = 5;

[Setting category="Spectate" name="Set ForceSpectator" description="Puts the local player into spectator so the forced target is actually followed."]
bool S_SpectateForceSpectator = true;

[Setting category="Spectate" name="Camera type" min=0 max=2 description="SpectatorForceCameraType; Nadeo's replay cam loop cycles 0/1/2."]
uint S_SpectateCameraType = 0;

[Setting category="Spectate" name="Also set UISequence = EndRound" description="Mirrors Nadeo's StartReplaySequence(). May fight the running mode script; off by default."]
bool S_SpectateEndRoundSequence = false;
