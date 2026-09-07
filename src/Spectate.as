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

bool Spectate_Start(uint instId) {
    if (instId == 0) return false;
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
        g_specPrevTarget = ui.SpectatorForcedTarget.Value;
        g_specPrevCamType = ui.SpectatorForceCameraType;
        g_specPrevForceSpectator = ui.ForceSpectator;
        g_specPrevSequence = ui.UISequence;
        g_specSaved = true;
    }

    ui.SpectatorForcedTarget = MwId(instId);
    ui.SpectatorForceCameraType = S_SpectateCameraType;
    if (S_SpectateForceSpectator) ui.ForceSpectator = true;
    if (S_SpectateEndRoundSequence) ui.UISequence = CGamePlaygroundUIConfig::EUISequence::EndRound;

    // Classic race: the UI config target is ignored by the camera; the hook forces it (no-op if disabled).
    CamTarget_Set(instId);

    g_specActive = true;
    g_specInstId = instId;
    return true;
}

void Spectate_Stop() {
    auto ui = UiAll();
    bool wasForced = g_specActive && g_specSaved && S_SpectateForceSpectator;
    if (ui !is null && g_specSaved) {
        ui.SpectatorForcedTarget = MwId(g_specPrevTarget);
        ui.SpectatorForceCameraType = g_specPrevCamType;
        ui.ForceSpectator = g_specPrevForceSpectator;
        if (S_SpectateEndRoundSequence) ui.UISequence = g_specPrevSequence;
    }
    Spectate_Reset();
    // Forcing the spectator made the terminal's CGameCtnMediaClipPlayer play a spectator camera clip aimed at the
    // ghost. Clearing ForceSpectator/SpectatorForcedTarget does not stop that clip (it keeps pushing a forced
    // camera block every frame: camera stuck on the ghost). Only a (re)spawn of the local player ends it, which
    // is also what Ghosts++ does when leaving a ghost. Unspawn first so the ghosts restart with the player.
    if (wasForced && S_SpectateRespawnOnStop) {
        if (!Race_SpawnLocal(S_SpectateRespawnDelayMs, true)) warn("Ghosts2: could not respawn the local player after spectating; the camera may stay on the ghost");
    }
}

// Forget the saved state without writing to the game (map change / plugin unload paths).
void Spectate_Reset() {
    CamTarget_Clear();
    g_specActive = false;
    g_specInstId = 0;
    g_specSaved = false;
}

void Spectate_ForgetGhost(uint instId) {
    if (g_specActive && g_specInstId == instId) Spectate_Stop();
}

