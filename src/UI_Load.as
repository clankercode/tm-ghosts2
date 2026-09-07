// Load tab: replay file browser + "load my PB".

void DrawLoadTab() {
    auto rules = CurrentRules();
    if (rules is null) UI::TextWrapped("\\$fc4No CTrackManiaRaceRules - loading needs a running TrackMania playground.");
    bool canAdd = Race_CanAddGhosts();
    if (rules !is null && !canAdd) UI::TextWrapped("\\$fc4Ghosts cannot be added here: " + ClassicRaceHint + ".");

    UI::BeginDisabled(!canAdd || g_busy);
    if (UI::Button(Icons::Download + " Load my PB")) Load_PersonalBest();
    UI::EndDisabled();
    AddSimpleTooltip("ScoreMgr.Map_GetRecordGhost(localUser, mapUid, \"\")");
    UI::SameLine();
    if (g_busy) UI::Text("\\$fc4working ...");
    else UI::Text("\\$888" + g_status);

    // Medal ghosts (Nadeo campaign maps; TMX maps have none - failures notify via SetStatus).
    UI::BeginDisabled(!canAdd || g_busy);
    if (UI::Button(Icons::Trophy + " Load author ghost")) Load_Medal(4);
    UI::SameLine();
    if (UI::Button("Gold")) Load_Medal(3);
    UI::SameLine();
    if (UI::Button("Silver")) Load_Medal(2);
    UI::SameLine();
    if (UI::Button("Bronze")) Load_Medal(1);
    UI::EndDisabled();
    AddSimpleTooltip("ScoreMgr.Map_GetMultiAsyncLevelRecordGhost(mapUid, \\\"\\\", level 4/3/2/1 = author/gold/silver/bronze)");

    UI::Separator();
    DrawLeaderboardSection(rules);
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
    string typed = UI::InputText("##g2-dir", g_browseDir, changed, UI::InputTextFlags::EnterReturnsTrue);
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
    UI::BeginDisabled(!canAdd || g_busy);
    for (uint i = 0; i < g_browseFiles.Length; i++) {
        UI::PushID("f" + i);
        if (UI::Button(Icons::PlusCircle + "##load")) Load_ReplayFile(g_browseFiles[i]);
        AddSimpleTooltip("DataFileMgr.Replay_Load(" + g_browseFiles[i] + ")");
        UI::SameLine();
        UI::AlignTextToFramePadding();
        UI::Text(BaseName(g_browseFiles[i]));
        UI::PopID();
    }
    UI::EndDisabled();
    if (g_browseDirs.Length == 0 && g_browseFiles.Length == 0) UI::TextDisabled("(nothing here)");
    UI::EndChild();
}

// Leaderboard records -> ghost download -> RaceGhost_Add (flow credited to FortTM, see Leaderboard.as).
void DrawLeaderboardSection(CTrackManiaRaceRules@ rules) {
    // First draws for this map: fetch its board by itself (the cache was dropped on the map change).
    if (rules !is null && CurrentMapUid().Length > 0 && Lb_WantAutoFetch()) Lb_AutoFetch();
    UI::AlignTextToFramePadding();
    UI::Text("Leaderboard (" + Lb_Zone() + ")");
    UI::SameLine();
    UI::BeginDisabled(rules is null || g_lbBusy);
    if (UI::Button(Icons::Globe + " Fetch")) Lb_Fetch(0);
    AddSimpleTooltip("ScoreMgr.MapLeaderBoard_GetPlayerList(MwId(0), mapUid, \"\", zone, offset, count)");
    UI::SameLine();
    uint count = Math::Clamp(S_LeaderboardCount, 1, 100);
    UI::BeginDisabled(g_lbOffset == 0 || g_lbEntries.Length == 0);
    if (UI::Button(Icons::ChevronLeft + "##lb-prev")) Lb_Fetch(g_lbOffset >= count ? g_lbOffset - count : 0);
    UI::EndDisabled();
    UI::SameLine();
    UI::BeginDisabled(g_lbEntries.Length < count);
    if (UI::Button(Icons::ChevronRight + "##lb-next")) Lb_Fetch(g_lbOffset + count);
    UI::EndDisabled();
    UI::EndDisabled();
    UI::SameLine();
    UI::Text("\\$888" + (g_lbBusy ? "fetching ..." : g_lbStatus));

    if (g_lbEntries.Length == 0) return;
    bool canAdd = Race_CanAddGhosts();
    bool stale = g_lbMapUid != CurrentMapUid();
    if (stale) UI::Text("\\$fc4Fetched for another map - fetch again.");
    if (UI::BeginTable("g2-lb", 4, UI::TableFlags::SizingFixedFit | UI::TableFlags::RowBg)) {
        UI::TableSetupColumn("#", UI::TableColumnFlags::WidthFixed, 40);
        UI::TableSetupColumn("Name", UI::TableColumnFlags::WidthFixed, 200);
        UI::TableSetupColumn("Time", UI::TableColumnFlags::WidthFixed, 80);
        UI::TableSetupColumn("", UI::TableColumnFlags::WidthFixed, 40);
        UI::TableHeadersRow();
        for (uint i = 0; i < g_lbEntries.Length; i++) {
            auto e = g_lbEntries[i];
            UI::TableNextRow();
            UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text("" + e.rank);
            UI::TableNextColumn(); UI::Text(e.name.Length > 0 ? e.name : e.login);
            UI::TableNextColumn(); UI::Text(FormatTime(e.score));
            UI::TableNextColumn();
            UI::BeginDisabled(stale || g_busy || !canAdd || e.url.Length == 0);
            if (UI::Button(Icons::PlusCircle + "##lb" + i)) Lb_Load(e.rank);
            UI::EndDisabled();
            AddSimpleTooltip("DataFileMgr.Ghost_Download(FileName, ReplayUrl) then RaceGhost_Add");
        }
        UI::EndTable();
    }
}

