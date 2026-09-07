// Ghosts++-style scrubber: a small always-on-top strip at the bottom of the screen for one ghost.

PluginGhost@ g_scrubGhost;
bool g_scrubDragging = false;     // slider held: the clock is frozen at the slider value until release
bool g_scrubWasPaused = false;
int g_scrubDragValue = -1;
uint g_scrubLastHover = 0;          // Time::Now when the mouse was last over the strip
vec2 g_scrubLastSize = vec2(0, 0);  // last drawn window size (hover test while the strip is hidden)

void Scrubber_Open(PluginGhost@ pg) {
    @g_scrubGhost = pg;
    g_scrubLastHover = Time::Now;
}

// A loaded ghost gets the scrubber by default (Ghosts++: it shows up during the countdown and hides once you drive).
void Scrubber_AutoOpen(PluginGhost@ pg) {
    if (g_scrubGhost is null) Scrubber_Open(pg);
}

bool Scrubber_InCountdown() {
    auto rules = CurrentRules();
    if (rules is null) return false;
    string login = GetLocalLogin();
    for (uint i = 0; i < rules.Players.Length; i++) {
        auto p = rules.Players[i];
        if (p is null || p.User is null || string(p.User.Login) != login) continue;
        return int(p.RaceStartTime) > int(rules.Now);
    }
    return false;
}

// Ghosts++ visibility rules: always while spectating or dragging, during the race countdown, and for
// S_ScrubHideDelayMs after the mouse was last over the strip (hovering the hidden strip's area brings it back).
bool Scrubber_ShouldShow(float w) {
    if (!S_ScrubAutoHide || g_scrubDragging || g_specActive) return true;
    if (S_ScrubShowBeforeStart && Scrubber_InCountdown()) return true;
    vec2 m = UI::GetMousePos();
    vec2 p0 = vec2((Display::GetWidth() - w) / 2, Display::GetHeight() - 120);
    float h = g_scrubLastSize.y > 0 ? g_scrubLastSize.y : 64.0f;
    if (m.x >= p0.x && m.x <= p0.x + w && m.y >= p0.y && m.y <= p0.y + h) g_scrubLastHover = Time::Now;
    return Time::Now - g_scrubLastHover < S_ScrubHideDelayMs;
}

void Scrubber_Close() {
    Scrubber_EndDrag();
    @g_scrubGhost = null;
}

void Scrubber_EndDrag() {
    if (!g_scrubDragging) return;
    g_scrubDragging = false;
    g_scrubDragValue = -1;
    if (g_scrubGhost !is null && !g_scrubWasPaused) Ctl_SetPaused(g_scrubGhost, false);
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
    if (speed < 0.1) return 0.1;
    if (speed < 0.25) return 0.25;
    if (speed < 0.5) return 0.5;
    if (speed < 1.0) return 1.0;
    if (speed < 2.0) return 2.0;
    if (speed < 4.0) return 4.0;
    return 0.01;
}

float PrevSpeed(float speed) {
    if (speed > 4.0) return 4.0;
    if (speed > 2.0) return 2.0;
    if (speed > 1.0) return 1.0;
    if (speed > 0.5) return 0.5;
    if (speed > 0.25) return 0.25;
    if (speed > 0.1) return 0.1;
    return 4.0;
}

void DrawSpectateMenuRows(array<PluginGhost@>@ list, bool &out any) {
    for (uint i = 0; i < list.Length; i++) {
        auto g = list[i];
        if (g is null || g.instId == 0) continue;
        any = true;
        bool cur = g_specActive && g_specInstId == g.instId;
        bool live = CamTarget_GhostHasVis(g);
        string label = (live ? "" : "\\$666") + g.DisplayName() + "  \\$888" + FormatTime(g.raceTime) + "##spec" + g.instId;
        if (UI::MenuItem(label, "", cur)) {
            if (cur) Spectate_Stop(); else Spectate_Start(g.instId);
        }
        if (!live && UI::IsItemHovered()) UI::SetTooltip("No playback right now (not started or finished)");
    }
}

void DrawSpectateMenu() {
    UI::Text("\\$888Spectate");
    bool any = false;
    DrawSpectateMenuRows(g_ghosts, any);
    DrawSpectateMenuRows(g_engineGhosts, any);
    if (!any) UI::Text("\\$888no ghosts loaded");
    if (g_specActive) {
        UI::Separator();
        if (UI::MenuItem(Icons::EyeSlash + " Stop spectating##specmenu-stop")) Spectate_Stop();
    }
}

void DrawScrubberWindow() {
    if (!Scrubber_GhostAlive()) { @g_scrubGhost = null; return; }
    if (InGameMenuOpen()) return;
    auto pg = g_scrubGhost;
    bool avail = TimeCtl_Available();
    int t = TimeCtl_GhostTime(pg);
    int maxT = int(pg.raceTime > 0 ? pg.raceTime : 60000);
    if (t > maxT) maxT = t;

    float w = Math::Min(760.0f, Display::GetWidth() * 0.6f);
    if (!Scrubber_ShouldShow(w)) return;
    UI::SetNextWindowSize(int(w), 0, UI::Cond::Always);
    UI::SetNextWindowPos(int((Display::GetWidth() - w) / 2), int(Display::GetHeight() - 120), UI::Cond::Always);
    int flags = UI::WindowFlags::NoTitleBar | UI::WindowFlags::NoResize | UI::WindowFlags::NoCollapse
        | UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoScrollbar | UI::WindowFlags::NoDocking;
    if (!UI::Begin("Ghosts2 scrubber##g2-scrubber", flags)) { UI::End(); return; }

    UI::BeginDisabled(!avail || t < 0);
    vec2 btn = vec2(34, 0);
    // Step scales with playback speed: ¼x → 25 ms, 1x → 100 ms, 2x → 200 ms; min 1 ms.
    int step = Math::Max(1, int(float(S_ScrubStepMs) * pg.speed + 0.5f));
    if (UI::Button(Icons::StepBackward + "##sb", btn)) Ctl_Seek(pg, uint(Math::Max(0, t - step)));
    if (UI::IsItemHovered()) UI::SetTooltip("Back " + step + " ms");
    UI::SameLine();
    if (UI::Button((pg.paused ? Icons::Play : Icons::Pause) + "##pp", btn)) Ctl_SetPaused(pg, !pg.paused);
    if (UI::IsItemHovered()) UI::SetTooltip(pg.paused ? "Resume" : "Pause");
    UI::SameLine();
    if (UI::Button(Icons::StepForward + "##sf", btn)) Ctl_Seek(pg, uint(t + step));
    if (UI::IsItemHovered()) UI::SetTooltip("Forward " + step + " ms");
    UI::SameLine();
    if (UI::Button(SpeedLabel(pg.speed) + "##spd", vec2(46, 0))) Ctl_SetSpeed(pg, NextSpeed(pg.speed));
    if (UI::IsItemHovered()) {
        UI::SetTooltip("Playback speed (click = faster, right click = slower)");
        if (UI::IsMouseClicked(UI::MouseButton::Right)) Ctl_SetSpeed(pg, PrevSpeed(pg.speed));
    }
    UI::SameLine();
    UI::BeginDisabled(!pg.Controlled());
    if (UI::Button(Icons::Undo + "##sync", btn)) Ctl_Release(pg);
    if (UI::IsItemHovered()) UI::SetTooltip("Give the clock back to the game (ghost snaps to the player's race time)");
    UI::EndDisabled();
    UI::EndDisabled();
    UI::SameLine();
    bool locked = Lock_Enabled();
    // Locked: the strip drives the whole group, so the eye reflects whichever ghost is being spectated.
    bool anySpec = g_specActive && g_specInstId != 0;
    bool isSpec = anySpec && (locked || g_specInstId == pg.instId);
    if (UI::Button((isSpec ? Icons::Eye : Icons::EyeSlash) + "##spec", btn)) {
        if (isSpec) Spectate_Stop(); else Spectate_Start(pg.instId);
    }
    if (UI::IsItemHovered()) {
        string specName = "";
        if (isSpec && g_specInstId != pg.instId) { auto sp = Ghosts_FindByInstId(g_specInstId); if (sp !is null) specName = " (" + sp.DisplayName() + ")"; }
        UI::SetTooltip((isSpec ? "Stop spectating" + specName : "Spectate this ghost") + "\\nright click to change");
    }
    // right click on the eye: pick any ghost to spectate
    if (UI::BeginPopupContextItem("g2-spec-menu")) {
        DrawSpectateMenu();
        UI::EndPopup();
    }
    UI::SameLine();
    if (UI::Button(Icons::VideoCamera + " " + Spectate_CameraLabel(S_SpectateCameraType) + "##cam", vec2(96, 0))) Spectate_CycleCameraType(false);
    if (UI::IsItemHovered()) {
        UI::SetTooltip("Spectator camera (click = next, right click = previous): Replay = engine camera clip, Follow = chase cam, FreeCam = free camera (cam 7 in TM2020 terms), Game = the game's own spectator camera controls");
        if (UI::IsMouseClicked(UI::MouseButton::Right)) Spectate_CycleCameraType(true);
    }
    UI::SameLine();
    uint nMembers = locked ? Lock_Members().Length : 0;
    if (UI::Button((locked ? "\\$8f8" + Icons::Lock : Icons::Unlock) + "##lock", btn)) Lock_Set(!locked);
    if (UI::IsItemHovered()) UI::SetTooltip(locked ? "Unlock: control ghosts individually again" : "Lock all ghosts: this scrubber drives every ghost and keeps them in sync");
    UI::SameLine();
    UI::AlignTextToFramePadding();
    UI::Text(pg.DisplayName() + (locked ? "  \\$8f8" + Icons::Lock + " " + nMembers : "") + "  \\$888" + (t < 0 ? "not started" : FormatTime(uint(t))) + " / " + FormatTime(pg.raceTime));
    if (t < 0) {
        UI::SameLine();
        if (CurrentRules() !is null) {
            if (UI::Button(Icons::Play + " Respawn##g2-respawn", btn)) Race_RespawnLocal();
            if (UI::IsItemHovered()) UI::SetTooltip("Ghosts start playing on your next spawn: unspawn + respawn the local player");
        } else {
            UI::Text("\\$888(starts when you respawn)");
        }
    }
    UI::SameLine(w - 44);
    if (UI::Button(Icons::Times + "##close", btn)) Scrubber_Close();

    UI::BeginDisabled(!avail || t < 0);
    UI::SetNextItemWidth(-1);
    string fmt = t < 0 ? "-" : FormatTime(uint(t));
    float shown = g_scrubDragging && g_scrubDragValue >= 0 ? float(g_scrubDragValue) : float(t < 0 ? 0 : t);
    float v = UI::SliderFloat("##g2-scrub-slider", shown, 0.0f, float(maxT), fmt, UI::SliderFlags::NoInput);
    bool sliderHovered = UI::IsItemHovered();
    if (UI::IsItemActive()) {
        // Hold the clock while the slider is held, otherwise the engine advances it between our seeks and the
        // ghost flips between the slider value and one tick ahead.
        if (!g_scrubDragging) {
            g_scrubDragging = true;
            g_scrubWasPaused = pg.paused;
            Ctl_SetPaused(pg, true);
        }
        int target = int(Math::Max(0.0f, v));
        if (target != g_scrubDragValue) {
            g_scrubDragValue = target;
            Ctl_Seek(pg, uint(target));
        }
    } else if (g_scrubDragging) {
        Scrubber_EndDrag();
    }
    UI::EndDisabled();
    // right click on the time bar toggles pause (the buttons keep their own right-click meanings)
    if (avail && t >= 0 && sliderHovered && !g_scrubDragging && UI::IsMouseClicked(UI::MouseButton::Right)) Ctl_SetPaused(pg, !pg.paused);
    // remember the drawn rect for the hover test while hidden, and keep the strip up while the mouse is on it
    {
        vec2 m = UI::GetMousePos();
        vec2 p0 = UI::GetWindowPos();
        g_scrubLastSize = UI::GetWindowSize();
        if (m.x >= p0.x && m.y >= p0.y && m.x <= p0.x + g_scrubLastSize.x && m.y <= p0.y + g_scrubLastSize.y) g_scrubLastHover = Time::Now;
    }
    UI::End();
}
