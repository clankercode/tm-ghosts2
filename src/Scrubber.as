// Ghosts++-style scrubber: a small always-on-top strip at the bottom of the screen for one ghost.

PluginGhost@ g_scrubGhost;

void Scrubber_Open(PluginGhost@ pg) {
    @g_scrubGhost = pg;
}

void Scrubber_Close() {
    @g_scrubGhost = null;
}

// Drop the scrubber if its ghost disappeared from our lists.
bool Scrubber_GhostAlive() {
    if (g_scrubGhost is null) return false;
    if (g_ghosts.FindByRef(g_scrubGhost) >= 0) return true;
    if (g_engineGhosts.FindByRef(g_scrubGhost) >= 0) return true;
    return false;
}

string SpeedLabel(float speed) {
    if (speed == 0.25) return "¼x";
    if (speed == 0.5) return "½x";
    return Text::Format("%.2gx", speed);
}

float NextSpeed(float speed) {
    if (speed < 0.5) return 0.5;
    if (speed < 1.0) return 1.0;
    if (speed < 2.0) return 2.0;
    if (speed < 4.0) return 4.0;
    return 0.25;
}

void DrawScrubberWindow() {
    if (!Scrubber_GhostAlive()) { @g_scrubGhost = null; return; }
    auto pg = g_scrubGhost;
    bool avail = TimeCtl_Available();
    int t = TimeCtl_GhostTime(pg);
    int maxT = int(pg.raceTime > 0 ? pg.raceTime : 60000);
    if (t > maxT) maxT = t;

    float w = Math::Min(760.0f, Display::GetWidth() * 0.6f);
    UI::SetNextWindowSize(int(w), 0, UI::Cond::Always);
    UI::SetNextWindowPos(int((Display::GetWidth() - w) / 2), int(Display::GetHeight() - 120), UI::Cond::Always);
    int flags = UI::WindowFlags::NoTitleBar | UI::WindowFlags::NoResize | UI::WindowFlags::NoCollapse
        | UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoDocking;
    if (!UI::Begin("Ghosts2 scrubber##g2-scrubber", flags)) { UI::End(); return; }

    UI::BeginDisabled(!avail || t < 0);
    vec2 btn = vec2(34, 0);
    if (UI::Button(Icons::StepBackward + "##sb", btn)) TimeCtl_Seek(pg, uint(Math::Max(0, t - 100)));
    if (UI::IsItemHovered()) UI::SetTooltip("Back 100 ms");
    UI::SameLine();
    if (UI::Button((pg.paused ? Icons::Play : Icons::Pause) + "##pp", btn)) TimeCtl_SetPaused(pg, !pg.paused);
    if (UI::IsItemHovered()) UI::SetTooltip(pg.paused ? "Resume" : "Pause");
    UI::SameLine();
    if (UI::Button(Icons::StepForward + "##sf", btn)) TimeCtl_Seek(pg, uint(t + 100));
    if (UI::IsItemHovered()) UI::SetTooltip("Forward 100 ms");
    UI::SameLine();
    if (UI::Button(SpeedLabel(pg.speed) + "##spd", vec2(46, 0))) TimeCtl_SetSpeed(pg, NextSpeed(pg.speed));
    if (UI::IsItemHovered()) UI::SetTooltip("Playback speed (click to cycle)");
    UI::SameLine();
    UI::BeginDisabled(!pg.Controlled());
    if (UI::Button(Icons::Undo + "##sync", btn)) TimeCtl_Release(pg);
    if (UI::IsItemHovered()) UI::SetTooltip("Give the clock back to the game (ghost snaps to the player's race time)");
    UI::EndDisabled();
    UI::EndDisabled();
    UI::SameLine();
    bool isSpec = g_specActive && g_specInstId == pg.instId && pg.instId != 0;
    if (UI::Button((isSpec ? Icons::Eye : Icons::EyeSlash) + "##spec", btn)) {
        if (isSpec) Spectate_Stop(); else Spectate_Start(pg.instId);
    }
    if (UI::IsItemHovered()) UI::SetTooltip(isSpec ? "Stop spectating" : "Spectate this ghost");
    UI::SameLine();
    UI::AlignTextToFramePadding();
    UI::Text(pg.nickname + "  \\$888" + (t < 0 ? "not started" : FormatTime(uint(t))) + " / " + FormatTime(pg.raceTime));
    UI::SameLine(w - 44);
    if (UI::Button(Icons::Times + "##close", btn)) Scrubber_Close();

    UI::BeginDisabled(!avail || t < 0);
    UI::SetNextItemWidth(-1);
    string fmt = t < 0 ? "-" : FormatTime(uint(t));
    float v = UI::SliderFloat("##g2-scrub-slider", float(t < 0 ? 0 : t), 0.0f, float(maxT), fmt, UI::SliderFlags::NoInput);
    if (UI::IsItemActive() && int(v) != t) TimeCtl_Seek(pg, uint(Math::Max(0.0f, v)));
    UI::EndDisabled();
    UI::End();
}
