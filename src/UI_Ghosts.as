// Ghost list panel: what the race is showing, and what Ghosts2 put there.

void DrawGhostsTab() {
    auto race = CurrentRace();
    auto rules = CurrentRules();
    if (race is null) {
        UI::TextWrapped("Not in a TrackMania race (CurrentPlayground is " + TypeName(App().CurrentPlayground) + ").");
        return;
    }

    UI::BeginDisabled(rules is null);
    if (UI::Button(Icons::Trash + " Remove all")) Ghosts_RemoveAll();
    UI::EndDisabled();
    UI::SameLine();
    if (g_specActive) {
        if (UI::Button(Icons::StopCircle + " Stop spectating")) Spectate_Stop();
    } else {
        UI::BeginDisabled(true);
        UI::Button(Icons::StopCircle + " Stop spectating");
        UI::EndDisabled();
    }
    UI::SameLine();
    if (UI::Button(Icons::VideoCamera + " Reset camera")) CamTarget_ResetToLocal();
    AddSimpleTooltip("Point the camera back at your car if it is still following a ghost");
    UI::SameLine();
    UI::Text("\\$888" + race.RaceGhosts.Length + " in race, " + g_ghosts.Length + " ours");

    UI::Separator();
    DrawRaceGhostsTable(race, rules);
    UI::Separator();
    DrawPluginGhostsTable(rules);
    UI::Separator();
    DrawEngineGhosts();
}

void DrawRaceGhostsTable(CTrackManiaRace@ race, CTrackManiaRaceRules@ rules) {
    UI::SeparatorText("CTrackManiaRace.RaceGhosts");
    if (race.RaceGhosts.Length == 0) {
        UI::TextDisabled("(empty)");
        return;
    }
    if (!UI::BeginTable("g2-race-ghosts", 6, UI::TableFlags::SizingStretchProp | UI::TableFlags::RowBg)) return;
    UI::TableSetupColumn("#", UI::TableColumnFlags::WidthFixed, 26);
    UI::TableSetupColumn("Nickname");
    UI::TableSetupColumn("Time", UI::TableColumnFlags::WidthFixed, 84);
    UI::TableSetupColumn("Resp.", UI::TableColumnFlags::WidthFixed, 42);
    UI::TableSetupColumn("Login");
    UI::TableSetupColumn("Ours / inst", UI::TableColumnFlags::WidthFixed, 150);
    UI::TableHeadersRow();

    for (uint i = 0; i < race.RaceGhosts.Length; i++) {
        auto g = race.RaceGhosts[i];
        if (g is null) continue;
        auto pg = Ghosts_FindByCtn(g);
        UI::PushID("rg" + i);
        UI::TableNextRow();
        UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text("" + (i + 1));
        UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text(string(g.GhostNickname));
        UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text(FormatTime(g.RaceTime));
        UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text("" + g.NbRespawns);
        UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text("\\$888" + g.GhostLogin);
        UI::TableNextColumn(); UI::AlignTextToFramePadding();
        if (pg is null) {
            auto eg = Ghosts_FindEngineByCtn(g);
            if (eg is null || eg.instId == 0) UI::TextDisabled("engine");
            else UI::Text("\\$888engine " + Text::Format("0x%08x", eg.instId));
        } else {
            UI::Text("\\$8f8" + pg.instId);
            UI::SameLine();
            UI::BeginDisabled(rules is null);
            if (UI::Button(Icons::Times + "##rm")) Ghosts_Remove(pg);
            UI::EndDisabled();
            AddSimpleTooltip("RaceGhost_Remove");
        }
        UI::PopID();
    }
    UI::EndTable();
}

void DrawPluginGhostsTable(CTrackManiaRaceRules@ rules) {
    UI::SeparatorText("Loaded by Ghosts2");
    if (g_ghosts.Length == 0) {
        UI::TextDisabled("(none - use the Load tab)");
        return;
    }
    if (!UI::BeginTable("g2-plugin-ghosts", 6, UI::TableFlags::SizingStretchProp | UI::TableFlags::RowBg)) return;
    UI::TableSetupColumn("Nickname");
    UI::TableSetupColumn("Time", UI::TableColumnFlags::WidthFixed, 84);
    UI::TableSetupColumn("Inst", UI::TableColumnFlags::WidthFixed, 70);
    UI::TableSetupColumn("Status", UI::TableColumnFlags::WidthFixed, 80);
    UI::TableSetupColumn("Source");
    UI::TableSetupColumn("Actions", UI::TableColumnFlags::WidthFixed, 190);
    UI::TableHeadersRow();

    PluginGhost@ toRemove = null;
    for (uint i = 0; i < g_ghosts.Length; i++) {
        auto pg = g_ghosts[i];
        UI::PushID("pg" + i);
        UI::TableNextRow();
        UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text(pg.DisplayName());
        UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text(FormatTime(pg.raceTime));
        UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text("" + pg.instId);
        UI::TableNextColumn(); UI::AlignTextToFramePadding();
        if (pg.gaveUp) UI::Text("\\$f44gave up");
        else if (pg.inRace) UI::Text("\\$8f8in race");
        else UI::Text("\\$fc4missing");
        UI::TableNextColumn(); UI::AlignTextToFramePadding(); UI::Text("\\$888" + pg.source);
        UI::TableNextColumn();
        UI::BeginDisabled(rules is null);
        bool isSpec = g_specActive && g_specInstId == pg.instId && pg.instId != 0;
        if (UI::Button(isSpec ? Icons::Eye + "##spec" : Icons::EyeSlash + "##spec")) {
            if (isSpec) Spectate_Stop(); else Spectate_Start(pg.instId);
        }
        AddSimpleTooltip(isSpec ? "Stop spectating" : "Spectate (SpectatorForcedTarget)");
        UI::SameLine();
        if (UI::Button(Icons::Refresh + "##readd")) {
            pg.gaveUp = false;
            pg.failedReAdds = 0;
            Ghosts_PushToRace(pg);
        }
        AddSimpleTooltip("Re-add now (RaceGhost_Add)");
        UI::SameLine();
        UI::BeginDisabled(g_busy);
        UI::BeginDisabled(pg.ghost is null);
        if (UI::Button(Icons::FloppyO + "##save")) Save_Ghost(pg.ghost, SuggestedSaveName(pg));
        UI::EndDisabled();
        UI::EndDisabled();
        AddSimpleTooltip("Save as " + SuggestedSaveName(pg) + " (DataFileMgr.Replay_Save)");
        UI::SameLine();
        if (UI::Button(Icons::Times + "##rm")) @toRemove = pg;
        AddSimpleTooltip("Remove from race and stop tracking");
        UI::EndDisabled();
        UI::PopID();
    }
    UI::EndTable();
    if (toRemove !is null) Ghosts_Remove(toRemove);
}

void DrawPlaybackTab() {
    if (!TimeCtl_Available()) {
        UI::TextDisabled("Playback control needs a TrackMania race" + (S_TimeControl ? "" : " and the Time control setting") + ".");
        return;
    }
    auto members = Lock_Members();
    bool locked = Lock_Enabled();
    bool anyPlaying = false;
    for (uint i = 0; i < members.Length; i++) if (!members[i].paused) anyPlaying = true;

    if (UI::Button((locked ? "\\$8f8" + Icons::Lock + " Locked" : Icons::Unlock + " Unlocked") + "##lockall", vec2(100, 0))) Lock_Set(!locked);
    AddSimpleTooltip(locked ? "Every started ghost is driven together and kept in sync. Click to control ghosts individually." : "Ghosts are controlled individually. Click to lock them together.");
    UI::SameLine();
    UI::BeginDisabled(members.Length == 0);
    if (UI::Button((anyPlaying ? Icons::Pause + " Pause all" : Icons::Play + " Resume all") + "##allpp", vec2(110, 0))) {
        for (uint i = 0; i < members.Length; i++) TimeCtl_SetPaused(members[i], anyPlaying);
    }
    UI::SameLine();
    if (UI::Button(Icons::Undo + " Release all##allsync")) {
        for (uint i = 0; i < members.Length; i++) TimeCtl_Release(members[i]);
    }
    AddSimpleTooltip("Give every clock back to the game");
    UI::EndDisabled();
    UI::SameLine();
    UI::AlignTextToFramePadding();
    UI::Text("\\$888" + members.Length + " started");

    UI::Separator();
    if (g_ghosts.Length == 0 && g_engineGhosts.Length == 0) {
        UI::TextDisabled("(no ghosts - use the Load tab)");
        return;
    }
    if (!UI::BeginTable("g2-playback", 4, UI::TableFlags::SizingStretchProp | UI::TableFlags::RowBg)) return;
    UI::TableSetupColumn("Controls", UI::TableColumnFlags::WidthFixed, 212);
    UI::TableSetupColumn("Ghost");
    UI::TableSetupColumn("Time", UI::TableColumnFlags::WidthFixed, 136);
    UI::TableSetupColumn("State", UI::TableColumnFlags::WidthFixed, 60);
    UI::TableHeadersRow();
    DrawPlaybackRows(g_ghosts, "pb");
    DrawPlaybackRows(g_engineGhosts, "pe");
    UI::EndTable();
}

// Right-align text inside the current table cell.
void CellTextRight(const string &in text) {
    float w = UI::MeasureString(text).x;
    float avail = UI::GetContentRegionAvail().x;
    if (avail > w) UI::SetCursorPosX(UI::GetCursorPos().x + avail - w);
    UI::AlignTextToFramePadding();
    UI::Text(text);
}

void DrawPlaybackRows(array<PluginGhost@>@ list, const string &in idPrefix) {
    bool locked = Lock_Enabled();
    for (uint i = 0; i < list.Length; i++) {
        auto pg = list[i];
        if (!pg.engine && pg.instId == 0) continue;
        UI::PushID(idPrefix + i);
        int t = TimeCtl_GhostTime(pg);
        UI::TableNextRow();

        UI::TableNextColumn();
        bool isSpec = g_specActive && g_specInstId != 0 && g_specInstId == pg.instId;
        UI::BeginDisabled(pg.instId == 0 || (!isSpec && !CamTarget_GhostHasVis(pg)));
        if (UI::Button((isSpec ? "\\$8f8" + Icons::Eye : Icons::EyeSlash) + "##spec")) {
            if (isSpec) Spectate_Stop(); else Spectate_Start(pg.instId);
        }
        UI::EndDisabled();
        AddSimpleTooltip(isSpec ? "Stop spectating" : (CamTarget_GhostHasVis(pg) ? "Spectate this ghost" : "No playback right now (seek it back or restart)"));
        UI::SameLine();
        UI::BeginDisabled(t < 0);
        bool scrubOpen = g_scrubGhost is pg;
        if (UI::Button((scrubOpen ? "\\$8f8" : "") + Icons::Sliders + "##scrub")) {
            if (scrubOpen) Scrubber_Close(); else Scrubber_Open(pg);
        }
        AddSimpleTooltip(scrubOpen ? "Close the scrubber" : "Open the scrubber (seek / step / speed)");
        UI::SameLine();
        if (UI::Button(pg.paused ? Icons::Play + "##pp" : Icons::Pause + "##pp")) Ctl_SetPaused(pg, !pg.paused);
        AddSimpleTooltip(pg.paused ? "Resume" : "Pause");
        UI::SameLine();
        if (UI::Button(SpeedLabel(pg.speed) + "##spd", vec2(46, 0))) Ctl_SetSpeed(pg, NextSpeed(pg.speed));
        if (UI::IsItemHovered()) {
            AddSimpleTooltip("Playback speed (click = faster, right click = slower)");
            if (UI::IsMouseClicked(UI::MouseButton::Right)) Ctl_SetSpeed(pg, PrevSpeed(pg.speed));
        }
        UI::SameLine();
        UI::BeginDisabled(!pg.Controlled());
        if (UI::Button(Icons::Undo + "##sync")) Ctl_Release(pg);
        AddSimpleTooltip("Give the clock back to the game");
        UI::EndDisabled();
        UI::EndDisabled();

        UI::TableNextColumn();
        UI::AlignTextToFramePadding();
        UI::Text(pg.DisplayName());
        if (pg.engine) { UI::SameLine(); UI::Text("\\$888engine"); }

        UI::TableNextColumn();
        CellTextRight(t < 0 ? "\\$888not started" : FormatTime(uint(t)) + " \\$888/ " + FormatTime(pg.raceTime));

        UI::TableNextColumn();
        string state = (isSpec ? "\\$8f8" + Icons::Eye + " " : "") + (pg.Controlled() ? "\\$8f8" + Icons::Clock + " " : "") + (locked && t >= 0 ? "\\$aaa" + Icons::Lock : "");
        if (state.Length > 0) {
            CellTextRight(state);
            AddSimpleTooltip((isSpec ? "Spectating\n" : "") + (pg.Controlled() ? "Clock owned by Ghosts2\n" : "") + (locked && t >= 0 ? "In the lock group" : ""));
        }
        UI::PopID();
    }
}

string SuggestedSaveName(PluginGhost@ pg) {
    string nick = Text::StripFormatCodes(pg.nickname);
    nick = nick.Replace("/", "_").Replace("\\", "_").Replace(":", "_");
    if (nick.Length == 0) nick = "ghost";
    return "Ghosts2_" + nick + "_" + pg.raceTime + ".Replay.Gbx";
}

void DrawEngineGhosts() {
    UI::SeparatorText("Engine ghosts");
    auto pg = cast<CGameCtnPlayground>(App().CurrentPlayground);
    if (pg is null) {
        UI::TextDisabled("(no CGameCtnPlayground)");
        return;
    }
    UI::Text("PlayerBestGhost: " + (pg.PlayerBestGhost is null ? "\\$888null" : FormatTime(pg.PlayerBestGhost.RaceTime) + "  " + string(pg.PlayerBestGhost.GhostNickname)));
    UI::Text("PlayerRecordedGhost: " + (pg.PlayerRecordedGhost is null ? "\\$888null" : FormatTime(pg.PlayerRecordedGhost.RaceTime) + "  " + string(pg.PlayerRecordedGhost.GhostNickname)));
    auto race = CurrentRace();
    if (race !is null) {
        bool vis = race.IsBestRaceGhostVisible;
        if (UI::Checkbox("IsBestRaceGhostVisible", vis)) race.IsBestRaceGhostVisible = vis;
    }
    auto rules = CurrentRules();
    if (rules !is null) {
        bool gold = rules.MedalGhost_ShowGold;
        if (UI::Checkbox("MedalGhost_ShowGold", gold)) rules.MedalGhost_ShowGold = gold;
        UI::SameLine();
        bool silver = rules.MedalGhost_ShowSilver;
        if (UI::Checkbox("Silver", silver)) rules.MedalGhost_ShowSilver = silver;
        UI::SameLine();
        bool bronze = rules.MedalGhost_ShowBronze;
        if (UI::Checkbox("Bronze", bronze)) rules.MedalGhost_ShowBronze = bronze;
    }
}
