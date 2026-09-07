// Ghosts2: ManiaPlanet 4 (TM2) port of the Ghosts++ ideas: list, load, remove and spectate ghosts.

const string PluginName = Meta::ExecutingPlugin().Name;
const string MenuTitle = "\\$dd5" + Icons::HandPointerO + "\\$z " + PluginName;

void Main() {
    trace("Ghosts2 loaded");
    g_lockAll = S_ScrubLockDefault;
#if DEV
    S_ShowWindow = true;  // dev builds: always start with the window open (agents cannot click the plugin menu)
#endif
}

void Update(float dt) {
    Ghosts_Update();
    TimeCtl_Update(dt);
    CamTarget_Update();
}

void OnDestroyed() { Cleanup(); }
void OnDisabled() { Cleanup(); }

void Cleanup() {
    Scrubber_Close();
    TimeCtl_RemoveHook();
    CamTarget_RemoveHook();
    // Leave the race as we found it: restore the UI config, drop our bookkeeping.
    Spectate_Stop();
    Ghosts_ForgetAll();
}

void RenderMenu() {
    if (UI::MenuItem(MenuTitle, "", S_ShowWindow)) {
        S_ShowWindow = !S_ShowWindow;
    }
}

// One-shot tab selection (export ShowWindow / pack `show_window tab=`), consumed by the next frame.
string g_selectTab = "";
int g_selectTabFrames = 0;   // hold the SetSelected flag for a few frames (a single frame was sometimes missed)
bool g_moveWindow = false;   // one-shot window move (pack `show_window x= y=`), for scripted screenshots
int2 g_moveWindowTo = int2(0, 0);
int TabFlags(const string &in name) { return g_selectTab == name ? UI::TabItemFlags::SetSelected : UI::TabItemFlags::None; }

// The scrubber draws from Render(), not RenderInterface(): it has to stay on screen while the Openplanet
// overlay is hidden (that is when you are actually driving). Its buttons only take clicks with the overlay up.
void Render() {
    DrawScrubberWindow();
}

void RenderInterface() {
    if (!S_ShowWindow) return;
    UI::SetNextWindowSize(720, 420, UI::Cond::FirstUseEver);
    // ImGui coordinates are game pixels / UI scale
    UI::SetNextWindowPos(int(float(Display::GetWidth()) / UI::GetScale()) - 740, 40, UI::Cond::FirstUseEver);
    if (g_moveWindow) { g_moveWindow = false; UI::SetNextWindowPos(g_moveWindowTo.x, g_moveWindowTo.y, UI::Cond::Always); }
    if (UI::Begin(MenuTitle, S_ShowWindow)) {
        // MP4 Openplanet: UI::BeginTabBar returns void (not bool as in TM2020)
        UI::BeginTabBar("g2-tabs");
        if (UI::BeginTabItem("Ghosts", TabFlags("ghosts"))) { DrawGhostsTab(); UI::EndTabItem(); }
        if (UI::BeginTabItem("Playback", TabFlags("playback"))) { DrawPlaybackTab(); UI::EndTabItem(); }
        if (UI::BeginTabItem("Load", TabFlags("load"))) { DrawLoadTab(); UI::EndTabItem(); }
        if (UI::BeginTabItem("State", TabFlags("state"))) { DrawStateTab(); UI::EndTabItem(); }
        UI::EndTabBar();
        if (g_selectTabFrames > 0 && --g_selectTabFrames == 0) g_selectTab = "";
    }
    UI::End();
}

void DrawStateTab() {
    auto app = App();
    UI::Text("PlaygroundScript: " + TypeName(app.PlaygroundScript));
    UI::Text("CurrentPlayground: " + TypeName(app.CurrentPlayground));
    auto map = CurrentMap();
    UI::Text("Map: " + (map is null ? "\\$888null" : Text::OpenplanetFormatCodes(string(map.MapName)) + "  \\$888" + CurrentMapUid()));
    auto rules = CurrentRules();
    UI::Text("DataFileMgr: " + (rules is null ? "\\$888n/a" : TypeName(rules.DataFileMgr)));
    UI::Text("ScoreMgr: " + (rules is null ? "\\$888n/a" : TypeName(rules.ScoreMgr)));
    UI::Text("UIAll: " + TypeName(UiAll()));
    UI::Text("Local login: " + GetLocalLogin() + "  \\$888user id " + LocalUserId().Value);
    UI::Separator();
    UI::Text("Spectating: " + (g_specActive ? "\\$8f8inst " + g_specInstId : "\\$888no"));
    UI::Text("Tracked map uid: \\$888" + g_trackedMapUid);
    UI::Text("Status: \\$888" + g_status);
    UI::Text("Time control: \\$888" + (g_clockHook is null ? "hook off" : "hook on") + ", " + g_timeCtlUpdates + " updates, " + g_timeCtlWrites + " hook writes, " + g_clock.Length + " owned clock(s)" + (g_timeCtlLastErr.Length > 0 ? ", last error: " + g_timeCtlLastErr : ""));
    UI::Text("Camera target: \\$888" + (g_camHook is null ? "hook off" : "hook on") + (g_camForcedId == CamId_None ? ", none" : ", forced id " + Text::Format("0x%08x", g_camForcedId)) + ", " + g_camHookWrites + " hook writes" + (g_camLastErr.Length > 0 ? ", last error: " + g_camLastErr : ""));
    UI::Separator();
    if (UI::Button("Open settings")) Meta::OpenSettings(Meta::ExecutingPlugin());
}
