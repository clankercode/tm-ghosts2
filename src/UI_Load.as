// Load tab: replay file browser + "load my PB".

void DrawLoadTab() {
    auto rules = CurrentRules();
    if (rules is null) UI::TextWrapped("\\$fc4No CTrackManiaRaceRules - loading needs a running TrackMania playground.");

    UI::BeginDisabled(rules is null || g_busy);
    if (UI::Button(Icons::Download + " Load my PB")) Load_PersonalBest();
    UI::EndDisabled();
    if (UI::IsItemHovered()) UI::SetTooltip("ScoreMgr.Map_GetRecordGhost(localUser, mapUid, \"\")");
    UI::SameLine();
    if (g_busy) UI::Text("\\$fc4working ...");
    else UI::Text("\\$888" + g_status);

    UI::Separator();

    if (!g_browseInit) Browse_Refresh();

    if (UI::Button(Icons::Refresh + "##refresh")) Browse_Refresh();
    UI::SameLine();
    UI::BeginDisabled(ParentDir(g_browseDir).Length == 0);
    if (UI::Button(Icons::LevelUp + " Up")) Browse_Goto(ParentDir(g_browseDir));
    UI::EndDisabled();
    UI::SameLine();
    if (UI::Button(Icons::Home + " Replays")) Browse_Goto(DefaultReplaysFolder());
    UI::SameLine();
    UI::SetNextItemWidth(UI::GetContentRegionAvail().x);
    bool changed = false;
    string typed = UI::InputText("##g2-dir", g_browseDir, changed);
    if (changed) Browse_Goto(typed);

    if (!UI::BeginChild("g2-browse", vec2(0, 0))) {
        UI::EndChild();
        return;
    }
    for (uint i = 0; i < g_browseDirs.Length; i++) {
        if (UI::Selectable(Icons::FolderOpen + " " + BaseName(g_browseDirs[i]) + "##d" + i, false)) {
            Browse_Goto(g_browseDirs[i]);
            break;
        }
    }
    UI::BeginDisabled(rules is null || g_busy);
    for (uint i = 0; i < g_browseFiles.Length; i++) {
        UI::PushID("f" + i);
        if (UI::Button(Icons::PlusCircle + "##load")) Load_ReplayFile(g_browseFiles[i]);
        if (UI::IsItemHovered()) UI::SetTooltip("DataFileMgr.Replay_Load(" + g_browseFiles[i] + ")");
        UI::SameLine();
        UI::AlignTextToFramePadding();
        UI::Text(BaseName(g_browseFiles[i]));
        UI::PopID();
    }
    UI::EndDisabled();
    if (g_browseDirs.Length == 0 && g_browseFiles.Length == 0) UI::TextDisabled("(nothing here)");
    UI::EndChild();
}
