// Ghosts2: ManiaPlanet 4 (TM2) port of the Ghosts++ ideas: list, load, unload, spectate and scrub ghosts.
// Early skeleton: state window only.

[Setting hidden]
bool S_ShowWindow = true;

const string PluginName = Meta::ExecutingPlugin().Name;
const string MenuTitle = "\\$dd5" + Icons::HandPointerO + "\\$z " + PluginName;

void Main() {
    trace("Ghosts2 loaded");
}

void RenderMenu() {
    if (UI::MenuItem(MenuTitle, "", S_ShowWindow)) {
        S_ShowWindow = !S_ShowWindow;
    }
}

void RenderInterface() {
    if (!S_ShowWindow) return;
    UI::SetNextWindowSize(560, 320, UI::Cond::FirstUseEver);
    if (UI::Begin(MenuTitle, S_ShowWindow)) {
        DrawStateWindow();
    }
    UI::End();
}

string TypeName(CMwNod@ nod) {
    if (nod is null) return "null";
    auto ty = Reflection::TypeOf(nod);
    return ty is null ? "?" : ty.Name;
}

void DrawStateWindow() {
    auto app = cast<CGameManiaPlanet>(GetApp());
    UI::Text("PlaygroundScript: " + TypeName(app.PlaygroundScript));
    UI::Text("CurrentPlayground: " + TypeName(app.CurrentPlayground));
    if (app.RootMap !is null) UI::Text("Map: " + string(app.RootMap.MapName) + " (" + app.RootMap.MapInfo.MapUid + ")");
    auto race = cast<CTrackManiaRace>(app.CurrentPlayground);
    if (race is null) {
        UI::Text("Not in a TrackMania race.");
        return;
    }
    UI::Separator();
    UI::Text("Race ghosts: " + race.RaceGhosts.Length);
    for (uint i = 0; i < race.RaceGhosts.Length; i++) {
        auto g = race.RaceGhosts[i];
        if (g is null) continue;
        UI::Text(Text::Format("%02d. ", i + 1) + string(g.GhostNickname) + "  " + Time::Format(g.RaceTime) + "  " + g.GhostLogin);
    }
    auto ctnPg = cast<CGameCtnPlayground>(app.CurrentPlayground);
    if (ctnPg !is null) {
        UI::Text("PlayerBestGhost: " + (ctnPg.PlayerBestGhost is null ? "null" : Time::Format(ctnPg.PlayerBestGhost.RaceTime)));
        UI::Text("PlayerRecordedGhost: " + (ctnPg.PlayerRecordedGhost is null ? "null" : Time::Format(ctnPg.PlayerRecordedGhost.RaceTime)));
    }
}
