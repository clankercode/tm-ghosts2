// Implementations of the exports declared in Exports.as.

namespace Ghosts2 {
    Json::Value@ ListGhosts() {
        auto arr = Json::Array();
        auto rules = CurrentRules();
        for (uint i = 0; i < g_ghosts.Length; i++) {
            auto pg = g_ghosts[i];
            auto row = Json::Object();
            row["instId"] = pg.instId;
            row["nickname"] = pg.nickname;
            row["time"] = pg.raceTime;
            row["source"] = pg.source;
            row["status"] = pg.gaveUp ? "gave_up" : (pg.inRace ? "in_race" : "missing");
            row["startTime"] = rules is null || pg.instId == 0 ? 0 : rules.RaceGhost_GetStartTime(pg.InstMwId());
            row["visible"] = rules !is null && pg.instId != 0 && rules.RaceGhost_IsVisible(pg.InstMwId());
            row["replayOver"] = rules !is null && pg.instId != 0 && rules.RaceGhost_IsReplayOver(pg.InstMwId());
            row["ghostTime"] = TimeCtl_GhostTime(pg);
            row["paused"] = pg.paused;
            row["speed"] = pg.speed;
            arr.Add(row);
        }
        // Classic mode: the engine ghosts live here (script-mode RaceGhosts stays empty).
        auto race = CurrentRace();
        if (race !is null) {
            for (uint i = 0; i < race.RaceGhosts.Length; i++) {
                auto g = race.RaceGhosts[i];
                if (g is null) continue;
                auto eg = Ghosts_FindEngineByCtn(g);
                int egTime = eg is null ? -1 : TimeCtl_GhostTime(eg);   // also refreshes eg.instId
                auto row = Json::Object();
                row["instId"] = eg is null ? 0 : eg.instId;
                row["nickname"] = string(g.GhostNickname);
                row["time"] = g.RaceTime;
                row["source"] = "engine";
                row["status"] = "in_race";
                row["startTime"] = 0;
                row["visible"] = true;
                row["replayOver"] = false;
                row["ghostTime"] = egTime;
                row["paused"] = eg !is null && eg.paused;
                row["speed"] = eg is null ? 1.0 : eg.speed;
                arr.Add(row);
            }
        }
        return arr;
    }

    // The Load* wrappers return "accepted" only; the async task reports through State()/ListGhosts().
    bool LoadReplay(const string &in path) {
        if (g_busy || path.Length == 0) return false;
        Load_ReplayFile(path);
        return true;
    }

    bool LoadPB() {
        if (g_busy) return false;
        Load_PersonalBest();
        return true;
    }

    bool LoadMedal(uint level) {
        if (g_busy || level < 1 || level > 4) return false;
        Load_Medal(level);
        return true;
    }

    // Leaderboard: fetch a page (async; poll Leaderboard() until busy is false), then load by rank.
    bool LeaderboardFetch(uint offset) {
        if (g_lbBusy) return false;
        Lb_Fetch(offset);
        return true;
    }

    Json::Value@ Leaderboard() { return Lb_ToJson(); }

    bool LoadLeaderboard(uint rank) { return Lb_Load(rank); }

    void SetLockAll(bool on) { Lock_Set(on); }
    void SetCameraType(uint camType) { Spectate_SetCameraType(camType); }
    void SetFollowCam(uint cam) { S_SpectateFollowCam = Math::Clamp(cam, 1, 3); }   // Follow spectator camera: 1 far, 2 close, 3 internal

    bool Remove(uint instId) {
        for (uint i = 0; i < g_ghosts.Length; i++) {
            if (g_ghosts[i].instId == instId) {
                Ghosts_Remove(g_ghosts[i]);
                return true;
            }
        }
        return false;
    }

    void RemoveAll() { Ghosts_RemoveAll(); }
    bool Spectate(uint instId) { return Spectate_Start(instId); }
    void StopSpectating() { Spectate_Stop(); }
    void StopSpectatingEx(bool respawn) { Spectate_StopEx(respawn); }
    bool ResetCamera() { return CamTarget_ResetToLocal(); }

    Json::Value@ State() {
        auto o = Json::Object();
        o["busy"] = g_busy;
        o["status"] = g_status;
        o["mapUid"] = CurrentMapUid();
        o["tracked"] = g_ghosts.Length;
        o["spectating"] = g_specActive;
        o["spectateInstId"] = g_specInstId;
        o["timeCtlUpdates"] = g_timeCtlUpdates;
        o["timeCtlWrites"] = g_timeCtlWrites;
        o["timeCtlHook"] = g_clockHook !is null;
        o["timeCtlOwned"] = g_clock.Length;
        auto ents = Json::Array();
        for (uint i = 0; i < g_clock.Length; i++) {
            auto e = Json::Object();
            e["rec"] = Text::Format("%llx", g_clock[i].rec);
            e["wanted"] = g_clock[i].wanted;
            e["paused"] = g_clock[i].paused;
            e["speed"] = g_clock[i].speed;
            e["lastNowMs"] = g_clock[i].lastNowMs;
            ents.Add(e);
        }
        o["timeCtlEntries"] = ents;
        o["timeCtlLastErr"] = g_timeCtlLastErr;
        o["lockAll"] = Lock_Enabled();
        o["camResets"] = g_camResets;
        o["clipDrops"] = g_clipDrops;
        o["clipDropLastErr"] = g_clipDropLastErr;
        o["camHook"] = g_camHook !is null;
        o["camForcedId"] = g_camForcedId;
        o["camHookWrites"] = g_camHookWrites;
        o["camLastErr"] = g_camLastErr;
        return o;
    }

    void ShowWindow(bool visible) { S_ShowWindow = visible; }
    void SelectTab(const string &in tab) { g_selectTab = tab.ToLower(); g_selectTabFrames = 3; }
    void MoveWindow(int x, int y) { g_moveWindow = true; g_moveWindowTo = int2(x, y); }

    PluginGhost@ FindTracked(uint instId) { return Ghosts_FindByInstId(instId); }

    int GetGhostTime(uint instId) { return TimeCtl_GhostTime(FindTracked(instId)); }
    bool Seek(uint instId, uint ghostTimeMs) { auto pg = FindTracked(instId); if (pg is null || TimeCtl_GhostTime(pg) < 0) return false; Ctl_Seek(pg, ghostTimeMs); return true; }
    bool SetPaused(uint instId, bool paused) { auto pg = FindTracked(instId); if (pg is null || TimeCtl_GhostTime(pg) < 0) return false; Ctl_SetPaused(pg, paused); return true; }
    bool SetSpeed(uint instId, float speed) { auto pg = FindTracked(instId); if (pg is null || speed < 0.0 || speed > 16.0) return false; Ctl_SetSpeed(pg, speed); return true; }

    bool ShowScrubber(uint instId, bool visible) { auto pg = FindTracked(instId); if (pg is null) return false; if (visible) Scrubber_Open(pg); else Scrubber_Close(); return true; }
    bool Resync(uint instId) { auto pg = FindTracked(instId); if (pg is null) return false; Ctl_Release(pg); return true; }
}
