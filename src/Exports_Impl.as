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
            // "queued" = accepted by RaceGhost_Add but the engine has not built its playback record yet
            // (that happens at the next spawn), which is very different from "missing".
            row["status"] = pg.gaveUp ? "gave_up" : (pg.inRace ? (TimeCtl_GhostTime(pg) >= 0 ? "in_race" : "queued") : "missing");
            row["startTime"] = rules is null || pg.instId == 0 ? 0 : rules.RaceGhost_GetStartTime(pg.InstMwId());
            row["visible"] = RaceGhostVisible(rules, pg.InstMwId());
            row["replayOver"] = rules !is null && pg.instId != 0 && rules.RaceGhost_IsReplayOver(pg.InstMwId());
            row["ghostTime"] = TimeCtl_GhostTime(pg);
            // What the engine renders, and how far that is from where we are holding it (see TimeCtl_HoldError).
            row["engineGhostTime"] = TimeCtl_EngineGhostTime(pg);
            row["holdError"] = TimeCtl_HoldError(pg);
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

    // The Load tab's replay browser as data, so it can be driven and checked from a script:
    // `dir` non-empty navigates there first (a directory - to load a file use LoadReplay).
    Json::Value@ Browse(const string &in dir) {
        if (dir.Length > 0) Browse_Goto(dir);
        else if (!g_browseInit) Browse_Refresh();
        auto o = Json::Object();
        o["dir"] = g_browseDir;
        auto ds = Json::Array();
        for (uint i = 0; i < g_browseDirs.Length; i++) ds.Add(Json::Value(g_browseDirs[i]));
        auto fs = Json::Array();
        for (uint i = 0; i < g_browseFiles.Length; i++) fs.Add(Json::Value(g_browseFiles[i]));
        o["dirs"] = ds;
        o["files"] = fs;
        o["status"] = g_status;
        return o;
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
        // Ghosts_FindByInstId, not a g_ghosts scan: the engine's own race ghosts live in their own list and
        // were silently unreachable from here (the pack's `remove` just returned false for them).
        auto pg = Ghosts_FindByInstId(instId);
        if (pg is null) return false;
        Ghosts_Remove(pg);
        return true;
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
        // Turbo needs no clock hook at all (nothing there rewrites a ghost record's start time per frame), so
        // "is the hook object there" is the wrong question for a caller: this is the one that travels.
        o["timeCtlReady"] = TimeCtl_HookInstalled();
        o["timeCtlOwned"] = g_clock.Length;
        auto ents = Json::Array();
        for (uint i = 0; i < g_clock.Length; i++) {
            auto e = Json::Object();
            e["rec"] = Text::Format("%llx", g_clock[i].rec);
            e["wanted"] = g_clock[i].wanted;
            e["paused"] = g_clock[i].paused;
            e["speed"] = g_clock[i].speed;
            e["lastNowMs"] = g_clock[i].lastNowMs;
#if TURBO
            // How well the ghost is actually being held, in the engine's own terms: holdErr is the last
            // tick's (rendered time - asked-for time), and the min/max pair is that error over a rolling
            // 600-tick window. A held ghost that reads 0 is not stuttering; anything wide is.
            e["engineNow"] = g_clock[i].engineNow;
            e["tickEst"] = g_clock[i].tickEst;
            e["holdErr"] = g_clock[i].holdErr;
            e["holdErrMin"] = g_clock[i].holdErrMin;
            e["holdErrMax"] = g_clock[i].holdErrMax;
#endif
            ents.Add(e);
        }
        o["timeCtlEntries"] = ents;
        o["timeCtlLastErr"] = g_timeCtlLastErr;
        o["lockAll"] = Lock_Enabled();
        o["camResets"] = g_camResets;
        o["clipDrops"] = g_clipDrops;
        o["clipDropLastErr"] = g_clipDropLastErr;
        o["camHook"] = g_camHook !is null;
        o["camReady"] = CamTarget_Ready();
        o["camForcedId"] = g_camForcedId;
        o["camHookWrites"] = g_camHookWrites;
        o["camLastErr"] = g_camLastErr;
#if TURBO
        // The cameras this playground offers, in ManagedCams order, so a caller (and the settings UI) can see
        // what "Spectator camera" can actually be set to on this map rather than guessing from EGameCam.
        auto cams = Json::Array();
        auto kinds = CamTarget_TurboCamKinds();
        for (uint i = 0; i < kinds.Length; i++) cams.Add(Json::Value(kinds[i]));
        o["turboCams"] = cams;
        o["turboCam"] = S_TurboSpectateCam;
        o["turboSpecMobilId"] = g_specActive ? TurboGhostMobilId(g_specInstId) : 0;
#endif
        // Why a pending restart has or has not fired yet: the difference between "the add is waiting" and
        // "the add was parked to save your lap" is invisible from the ghost list alone.
        o["modeName"] = CurrentModeName();
        o["playerSpawned"] = LocalPlayerSpawned();
        o["runStarted"] = Race_RunStarted();
        o["midLap"] = Race_MidLap();
        o["restartOffered"] = g_restartOffered;
        o["restartHeld"] = g_restartHeld;
        o["spawnForAddIn"] = g_spawnForAddAt == 0 ? -1 : int(g_spawnForAddAt) - int(Time::Now);
        // Update check: `updateCheckDue` is the thing worth asserting - it must be false right after a
        // check, or the daily gate is not holding and the plugin would hammer the GitHub API.
        o["updateCheckEnabled"] = S_CheckForUpdates;
        o["updateLastCheck"] = S_UpdateLastCheck;
        o["updateCheckDue"] = UpdateCheck_Due();
        o["updateLatestVersion"] = S_UpdateLatestVersion;
        o["updateAvailable"] = UpdateAvailable();
        o["updateLastError"] = g_updLastError;
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
