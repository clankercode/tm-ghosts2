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

void RenderInterface() {
    DrawScrubberWindow();
    if (!S_ShowWindow) return;
    UI::SetNextWindowSize(640, 420, UI::Cond::FirstUseEver);
    UI::SetNextWindowPos(int(Display::GetWidth() - 660), 40, UI::Cond::FirstUseEver);
    if (UI::Begin(MenuTitle, S_ShowWindow)) {
        // MP4 Openplanet: UI::BeginTabBar returns void (not bool as in TM2020)
        UI::BeginTabBar("g2-tabs");
        if (UI::BeginTabItem("Ghosts")) { DrawGhostsTab(); UI::EndTabItem(); }
        if (UI::BeginTabItem("Load")) { DrawLoadTab(); UI::EndTabItem(); }
        if (UI::BeginTabItem("State")) { DrawStateTab(); UI::EndTabItem(); }
        UI::EndTabBar();
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
