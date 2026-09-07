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
                auto row = Json::Object();
                row["instId"] = 0;
                row["nickname"] = string(g.GhostNickname);
                row["time"] = g.RaceTime;
                row["source"] = "engine";
                row["status"] = "in_race";
                row["startTime"] = 0;
                row["visible"] = true;
                row["replayOver"] = false;
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
        o["timeCtlLastErr"] = g_timeCtlLastErr;
        return o;
    }

    void ShowWindow(bool visible) { S_ShowWindow = visible; }

    PluginGhost@ FindTracked(uint instId) {
        for (uint i = 0; i < g_ghosts.Length; i++) {
            if (g_ghosts[i].instId == instId && instId != 0) return g_ghosts[i];
        }
        return null;
    }

    int GetGhostTime(uint instId) { return TimeCtl_GhostTime(FindTracked(instId)); }
    bool Seek(uint instId, uint ghostTimeMs) { return TimeCtl_Seek(FindTracked(instId), ghostTimeMs); }
    bool SetPaused(uint instId, bool paused) { return TimeCtl_SetPaused(FindTracked(instId), paused); }
    bool SetSpeed(uint instId, float speed) { return TimeCtl_SetSpeed(FindTracked(instId), speed); }
}
