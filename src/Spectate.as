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

    g_specActive = true;
    g_specInstId = instId;
    return true;
}

void Spectate_Stop() {
    auto ui = UiAll();
    if (ui !is null && g_specSaved) {
        ui.SpectatorForcedTarget = MwId(g_specPrevTarget);
        ui.SpectatorForceCameraType = g_specPrevCamType;
        ui.ForceSpectator = g_specPrevForceSpectator;
        if (S_SpectateEndRoundSequence) ui.UISequence = g_specPrevSequence;
    }
    Spectate_Reset();
}

// Forget the saved state without writing to the game (map change / plugin unload paths).
void Spectate_Reset() {
    g_specActive = false;
    g_specInstId = 0;
    g_specSaved = false;
}

void Spectate_ForgetGhost(uint instId) {
    if (g_specActive && g_specInstId == instId) Spectate_Stop();
}

