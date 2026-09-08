// Spectating a race ghost = writing its RaceGhost_Add MwId into CGamePlaygroundUIConfig.
// Nadeo's UISequences::SetReplayGhostFocus does exactly this (plus camera type / UISequence).

bool g_specActive = false;
uint g_specInstId = 0;

// Saved UI config so "Stop spectating" is reversible.
bool g_specSaved = false;
uint g_specPrevTarget = 0;
uint g_specPrevCamType = 0;
bool g_specPrevForceSpectator = false;
CGamePlaygroundUIConfig::EUISequence g_specPrevSequence = CGamePlaygroundUIConfig::EUISequence::None;
#if TURBO
// Turbo picks the active camera by index into the terminal's ManagedCams, so leaving a ghost has to put the
// player's camera back where it was - nothing else restores it.
bool g_specPrevTurboCamSaved = false;
uint g_specPrevTurboCam = 0;
#endif


bool Spectate_Start(uint instId) {
    if (instId == 0) return false;
    string camWhy = CamTarget_WhyNotReady();
    if (camWhy.Length > 0) {
        g_status = camWhy + ".";
        warn("Ghosts2: " + g_status);
        return false;
    }
    auto ui = UiAll();
    if (ui is null) return false;
    auto pg = Ghosts_FindByInstId(instId);
    if (!CamTarget_GhostHasVis(pg)) {
        g_status = pg !is null && TimeCtl_GhostTime(pg) >= 0
            ? "Ghost has finished: seek it back (or respawn) before spectating."
            : "Ghost has no playback yet: respawn (start the race) so it is spawned, then spectate.";
        warn("Ghosts2: " + g_status);
        return false;
    }

    if (!g_specSaved) {
#if !TURBO
        g_specPrevTarget = ui.SpectatorForcedTarget.Value;
        g_specPrevCamType = ui.SpectatorForceCameraType;
        g_specPrevForceSpectator = ui.ForceSpectator;
#endif
        g_specPrevSequence = ui.UISequence;
        g_specSaved = true;
#if TURBO
        auto master = TurboCamsMaster();
        if (master !is null) { g_specPrevTurboCam = master.CurrentCam; g_specPrevTurboCamSaved = true; }
#endif
    }

#if !TURBO
    ui.SpectatorForcedTarget = MwId(instId);
    ui.SpectatorForceCameraType = S_SpectateCameraType;
    if (S_SpectateForceSpectator) ui.ForceSpectator = true;
#endif
    if (S_SpectateEndRoundSequence) ui.UISequence = CGamePlaygroundUIConfig::EUISequence::EndRound;

    // Classic race, and all of Turbo: the UI config target is ignored by (or absent from) the camera, so the
    // camera override is what actually aims it.
    CamTarget_Set(instId);

    g_specActive = true;
    g_specInstId = instId;
    // The scrubber follows the ghost you are watching. Spectating and scrubbing are the same intent - "look
    // at this run" - and leaving them pointed at different ghosts meant the strip on screen while you watched
    // one ghost was driving another, or nothing at all. Same effect as the sliders button on the ghost's row,
    // and it also makes this ghost the lock leader, so a seek moves what you can see.
    Scrubber_Open(pg);
    return true;
}

// Camera while spectating (SpectatorForceCameraType, 4 bits): 0 replay = the engine's camera clip, 1 follow = chase cam
// (cam type 0xe -> camsys cam 0x12), 2 = free cam (cam type 2 with the target zeroed; the terminal enum calls it Free;
// fly with the game's ButFreeCam action map), 3..14 clamp to 1, 15 = none: the terminal's own SpectatorCameraType and
// the game's spectator camera controls apply. Verified 2026-09-08 (camsys+0x180 per value; Spectate_ComputeCamParams).
const array<uint> SpecCamTypes = {0, 1, 2, 15};

string Spectate_CameraLabel(uint t) {
    if (t == 0) return "Replay";
    if (t == 1) return "Follow";
    if (t == 2) return "FreeCam";
    if (t == 15) return "Game";
    return "Cam " + t;
}

void Spectate_SetCameraType(uint t) {
    S_SpectateCameraType = t;
    auto ui = UiAll();
    if (g_specActive && ui !is null) ui.SpectatorForceCameraType = t;
}

void Spectate_CycleCameraType(bool backwards) {
    int idx = SpecCamTypes.Find(S_SpectateCameraType);
    if (idx < 0) idx = 0;
    else idx = (idx + (backwards ? int(SpecCamTypes.Length) - 1 : 1)) % int(SpecCamTypes.Length);
    Spectate_SetCameraType(SpecCamTypes[idx]);
}

// A restart is the sure way to end the spectator clip, but it also throws away a lap. Mid-lap, take the
// clip-release path instead - same setting shape as the restart-on-add one, and the same reasoning.
void Spectate_Stop() {
    Spectate_StopEx(S_SpectateRespawnOnStop == RespawnOnAdd::Always
                    || (S_SpectateRespawnOnStop == RespawnOnAdd::UnlessMidLap && !Race_MidLap()));
}

// `async` is false on the unload path: a coroutine started from OnDestroyed/OnDisabled outlives the module
// that owns its callback and keeps writing to the game after the plugin is gone.
void Spectate_StopEx(bool respawn, bool async = true) {
    bool wasSpectating = g_specActive;
    auto ui = UiAll();
    // Turbo never forces the spectator (no such field), so it never grows the spectator camera clip either.
    bool wasForced = HasSpectatorForcedTarget && g_specActive && g_specSaved && S_SpectateForceSpectator;
    if (ui !is null && g_specSaved) {
#if !TURBO
        ui.SpectatorForcedTarget = MwId(g_specPrevTarget);
        ui.SpectatorForceCameraType = g_specPrevCamType;
        ui.ForceSpectator = g_specPrevForceSpectator;
#endif
        if (S_SpectateEndRoundSequence) ui.UISequence = g_specPrevSequence;
    }
#if TURBO
    auto master = TurboCamsMaster();
    if (master !is null && g_specPrevTurboCamSaved) master.CurrentCam = g_specPrevTurboCam;
    g_specPrevTurboCamSaved = false;
#endif
    Spectate_Reset();
    // Forcing the spectator made the terminal's CGameCtnMediaClipPlayer play a spectator camera clip aimed at the
    // ghost. Clearing ForceSpectator/SpectatorForcedTarget does not stop that clip (it keeps pushing a forced
    // camera block every frame: camera stuck on the ghost). Only a (re)spawn of the local player ends it, which
    // is also what Ghosts++ does when leaving a ghost. Spawn only - never unspawn first (see Race_SpawnLocal:
    // in CampaignSolo the unspawn takes the car away and drops the challenge card back over the track).
    if (wasForced) {
        if (respawn) {
            if (!Race_SpawnLocal(S_SpectateRespawnDelayMs)) warn("Ghosts2: could not respawn the local player after spectating; the camera may stay on the ghost");
        } else if (async) {
            // No restart: release the terminal's spectator clip slot ourselves (see Spectate_DropClipLater).
            startnew(Spectate_DropClipLater);
        }
    }
    // Chase / free cameras leave the camera system's auto target on the ghost even after the respawn - but
    // only chase that when we were actually spectating: Cleanup() calls this on every unload, and a stop that
    // did nothing has nothing to undo.
    if (wasSpectating) {
        CamTarget_ResetToLocal();
        if (async) startnew(CamTarget_ResetAfterStop);
    }
}

// Plugin unload: put the game back synchronously, leaving nothing running behind us.
void Spectate_StopForUnload() { Spectate_StopEx(false, false); }

// Forget the saved state without writing to the game (map change / plugin unload paths).
void Spectate_Reset() {
    CamTarget_Clear();
#if TURBO
    g_specPrevTurboCamSaved = false;
#endif
    g_specActive = false;
    g_specInstId = 0;
    g_specSaved = false;
}

#if TURBO
// Turbo's camera button cycles the playground's own managed cameras, which is a different - and richer - list
// than MP4's four SpectatorForceCameraType values: it includes the free camera as a real camera rather than a
// forced camera type. The list is read from the game, so a playground that has no free camera never offers one.
void Spectate_CycleTurboCam(bool backwards) {
    auto kinds = CamTarget_TurboCamKinds();
    if (kinds.Length == 0) return;
    int idx = kinds.Find(S_TurboSpectateCam);
    if (idx < 0) idx = backwards ? int(kinds.Length) - 1 : 0;
    else idx = (idx + (backwards ? int(kinds.Length) - 1 : 1)) % int(kinds.Length);
    S_TurboSpectateCam = kinds[idx];
    CamTarget_SetTurboCamKind(S_TurboSpectateCam);
}

string Spectate_TurboCamLabel() {
    return S_TurboSpectateCam.Length == 0 ? "Game" : S_TurboSpectateCam;
}
#endif

void Spectate_ForgetGhost(uint instId) {
    if (g_specActive && g_specInstId == instId) Spectate_Stop();
}

