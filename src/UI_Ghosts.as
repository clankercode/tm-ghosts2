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
    UI::Text("\\$888" + race.RaceGhosts.Length + " in race, " + g_ghosts.Length + " ours");

    UI::Separator();
    DrawRaceGhostsTable(race, rules);
    UI::Separator();
    DrawPluginGhostsTable(rules);
    UI::Separator();
    DrawPlaybackControls();
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
        UI::TableNextColumn(); UI::Text("" + (i + 1));
        UI::TableNextColumn(); UI::Text(string(g.GhostNickname));
        UI::TableNextColumn(); UI::Text(FormatTime(g.RaceTime));
        UI::TableNextColumn(); UI::Text("" + g.NbRespawns);
        UI::TableNextColumn(); UI::Text("\\$888" + g.GhostLogin);
        UI::TableNextColumn();
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
            if (UI::IsItemHovered()) UI::SetTooltip("RaceGhost_Remove");
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
        UI::TableNextColumn(); UI::Text(pg.nickname);
        UI::TableNextColumn(); UI::Text(FormatTime(pg.raceTime));
        UI::TableNextColumn(); UI::Text("" + pg.instId);
        UI::TableNextColumn();
        if (pg.gaveUp) UI::Text("\\$f44gave up");
        else if (pg.inRace) UI::Text("\\$8f8in race");
        else UI::Text("\\$fc4missing");
        UI::TableNextColumn(); UI::Text("\\$888" + pg.source);
        UI::TableNextColumn();
        UI::BeginDisabled(rules is null);
        bool isSpec = g_specActive && g_specInstId == pg.instId && pg.instId != 0;
        if (UI::Button(isSpec ? Icons::Eye + "##spec" : Icons::EyeSlash + "##spec")) {
            if (isSpec) Spectate_Stop(); else Spectate_Start(pg.instId);
        }
        if (UI::IsItemHovered()) UI::SetTooltip(isSpec ? "Stop spectating" : "Spectate (SpectatorForcedTarget)");
        UI::SameLine();
        if (UI::Button(Icons::Refresh + "##readd")) {
            pg.gaveUp = false;
            pg.failedReAdds = 0;
            Ghosts_PushToRace(pg);
        }
        if (UI::IsItemHovered()) UI::SetTooltip("Re-add now (RaceGhost_Add)");
        UI::SameLine();
        UI::BeginDisabled(g_busy);
        if (UI::Button(Icons::FloppyO + "##save")) Save_Ghost(pg.ghost, SuggestedSaveName(pg));
        UI::EndDisabled();
        if (UI::IsItemHovered()) UI::SetTooltip("Save as " + SuggestedSaveName(pg) + " (DataFileMgr.Replay_Save)");
        UI::SameLine();
        if (UI::Button(Icons::Times + "##rm")) @toRemove = pg;
        if (UI::IsItemHovered()) UI::SetTooltip("Remove from race and stop tracking");
        UI::EndDisabled();
        UI::PopID();
    }
    UI::EndTable();
    if (toRemove !is null) Ghosts_Remove(toRemove);
}

void DrawPlaybackControls() {
    if (!TimeCtl_Available()) {
        if (g_ghosts.Length > 0 || g_engineGhosts.Length > 0) UI::TextDisabled("Playback control needs a TrackMania race" + (S_TimeControl ? "" : " and the Time control setting"));
        return;
    }
    UI::SeparatorText("Playback");
    DrawPlaybackRows(g_ghosts, "pb");
    DrawPlaybackRows(g_engineGhosts, "pe");
}

void DrawPlaybackRows(array<PluginGhost@>@ list, const string &in idPrefix) {
    for (uint i = 0; i < list.Length; i++) {
        auto pg = list[i];
        if (!pg.engine && pg.instId == 0) continue;
        UI::PushID(idPrefix + i);
        int t = TimeCtl_GhostTime(pg);
        UI::AlignTextToFramePadding();
        UI::Text(pg.nickname);
        UI::SameLine();
        UI::BeginDisabled(t < 0);
        bool scrubOpen = g_scrubGhost is pg;
        if (UI::Button((scrubOpen ? "\\$8f8" : "") + Icons::Sliders + "##scrub")) {
            if (scrubOpen) Scrubber_Close(); else Scrubber_Open(pg);
        }
        if (UI::IsItemHovered()) UI::SetTooltip(scrubOpen ? "Close the scrubber" : "Open the scrubber (seek / step / speed)");
        UI::SameLine();
        if (UI::Button(pg.paused ? Icons::Play + "##pp" : Icons::Pause + "##pp")) TimeCtl_SetPaused(pg, !pg.paused);
        if (UI::IsItemHovered()) UI::SetTooltip(pg.paused ? "Resume" : "Pause");
        UI::SameLine();
        if (UI::Button(SpeedLabel(pg.speed) + "##spd", vec2(46, 0))) TimeCtl_SetSpeed(pg, NextSpeed(pg.speed));
        if (UI::IsItemHovered()) UI::SetTooltip("Playback speed (click to cycle)");
        UI::SameLine();
        UI::BeginDisabled(!pg.Controlled());
        if (UI::Button(Icons::Undo + "##sync")) TimeCtl_Release(pg);
        if (UI::IsItemHovered()) UI::SetTooltip("Give the clock back to the game");
        UI::EndDisabled();
        UI::EndDisabled();
        UI::SameLine();
        UI::AlignTextToFramePadding();
        UI::Text("\\$888" + (t < 0 ? "not started" : FormatTime(uint(t))) + (pg.Controlled() ? "  \\$8f8" + Icons::Clock : ""));
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
