// Sourcing ghosts: local replay files via DataFileMgr.Replay_Load, and the personal best
// via ScoreMgr.Map_GetRecordGhost. Both are async task-result APIs, so both run as coroutines.
// Note: Nadeo documents CGamePlaygroundScript.DataFileMgr as "only available for local solo modes".

bool g_busy = false;
string g_status = "";

void SetStatus(const string &in msg, bool notify = false, bool isError = false) {
    g_status = msg;
    if (isError) warn(msg); else trace(msg);
    if (notify) UI::ShowNotification("Ghosts2", msg, isError ? 6000 : 3000);
}

// --- replay folder browsing ------------------------------------------------

string g_browseDir = "";
array<string> g_browseDirs;
array<string> g_browseFiles;
bool g_browseInit = false;

string DefaultReplaysFolder() {
    if (S_ReplaysFolder.Length > 0) return NormalizeDir(S_ReplaysFolder);
    return NormalizeDir(IO::FromUserGameFolder("Replays"));
}

string NormalizeDir(const string &in path) {
    string p = path.Replace("\\", "/");
    if (p.Length > 0 && !p.EndsWith("/")) p += "/";
    return p;
}

string BaseName(const string &in path) {
    string p = path.Replace("\\", "/");
    while (p.EndsWith("/")) p = p.SubStr(0, p.Length - 1);
    int slash = p.LastIndexOf("/");
    return slash < 0 ? p : p.SubStr(uint(slash) + 1);
}

string ParentDir(const string &in path) {
    string p = path.Replace("\\", "/");
    while (p.EndsWith("/")) p = p.SubStr(0, p.Length - 1);
    int slash = p.LastIndexOf("/");
    if (slash <= 0) return "";
    return p.SubStr(0, uint(slash) + 1);
}

bool LooksLikeGhostFile(const string &in path) {
    string lower = path.ToLower();
    return lower.EndsWith(".replay.gbx") || lower.EndsWith(".ghost.gbx");
}

void Browse_Refresh() {
    g_browseInit = true;
    g_browseDirs.RemoveRange(0, g_browseDirs.Length);
    g_browseFiles.RemoveRange(0, g_browseFiles.Length);
    if (g_browseDir.Length == 0) g_browseDir = DefaultReplaysFolder();
    if (!IO::FolderExists(g_browseDir)) {
        SetStatus("Folder not found: " + g_browseDir, false, true);
        return;
    }
    auto entries = IO::IndexFolder(g_browseDir, false);
    for (uint i = 0; i < entries.Length; i++) {
        string e = entries[i].Replace("\\", "/");
        if (IO::FolderExists(e)) {
            g_browseDirs.InsertLast(NormalizeDir(e));
        } else if (!S_FilterGhostFiles || LooksLikeGhostFile(e)) {
            g_browseFiles.InsertLast(e);
        }
    }
}

void Browse_Goto(const string &in dir) {
    g_browseDir = NormalizeDir(dir);
    Browse_Refresh();
}

// --- loading ---------------------------------------------------------------

void Load_ReplayFile(const string &in path) {
    if (g_busy) return;
    startnew(CoroutineFuncUserdataString(Load_ReplayFileCoro), path);
}

void Load_ReplayFileCoro(const string &in path) {
    g_busy = true;
    LoadReplayInner(path);
    g_busy = false;
}

void LoadReplayInner(const string &in path) {
    auto rules = CurrentRules();
    if (rules is null) {
        SetStatus("Not in a TrackMania race (no CTrackManiaRaceRules).", true, true);
        return;
    }
    auto dfm = rules.DataFileMgr;
    if (dfm is null) {
        SetStatus("DataFileMgr is null (solo-only surface).", true, true);
        return;
    }
    SetStatus("Loading " + BaseName(path) + " ...");
    auto task = dfm.Replay_Load(wstring(path));
    if (task is null) {
        SetStatus("Replay_Load returned null for " + path, true, true);
        return;
    }
    while (task.IsProcessing) yield();

    if (task.HasSucceeded) {
        uint added = 0;
        for (uint i = 0; i < task.Ghosts.Length; i++) {
            auto g = task.Ghosts[i];
            if (g is null) continue;
            if (Ghosts_Add(g, BaseName(path)) !is null) added++;
        }
        SetStatus("Loaded " + added + "/" + task.Ghosts.Length + " ghost(s) from " + BaseName(path), true);
    } else {
        SetStatus("Replay_Load failed: " + string(task.ErrorDescription), true, true);
    }
    dfm.TaskResult_Release(task.Id);
}

void Load_PersonalBest() {
    if (g_busy) return;
    startnew(CoroutineFunc(Load_PersonalBestCoro));
}

void Load_PersonalBestCoro() {
    g_busy = true;
    LoadPbInner();
    g_busy = false;
}

void Load_Medal(uint level) {
    if (g_busy || level < 1 || level > 4) return;
    startnew(CoroutineFuncUserdataString(Load_MedalCoro), "" + level);
}

void Load_MedalCoro(const string &in levelStr) {
    uint level = Text::ParseUInt(levelStr);
    g_busy = true;
    LoadMedalInner(level);
    g_busy = false;
}

void LoadMedalInner(uint level) {
    auto rules = CurrentRules();
    if (rules is null || rules.ScoreMgr is null) {
        SetStatus("Cannot load medal: no ScoreMgr.", true, true);
        return;
    }
    string uid = CurrentMapUid();
    if (uid.Length == 0) {
        SetStatus("No map loaded.", true, true);
        return;
    }
    SetStatus("Requesting medal ghost (level " + level + ") ...");
    auto task = rules.ScoreMgr.Map_GetMultiAsyncLevelRecordGhost(uid, "", level);
    if (task is null) {
        SetStatus("Map_GetMultiAsyncLevelRecordGhost returned null.", true, true);
        return;
    }
    while (task.IsProcessing) yield();
    if (task.HasSucceeded && task.Ghost !is null) {
        if (Ghosts_Add(task.Ghost, "Medal " + level) !is null) SetStatus("Added medal ghost (level " + level + ").", true);
        else SetStatus("RaceGhost_Add rejected the medal ghost" + AddRejectedWhy(), true, true);
    } else if (task.HasSucceeded) {
        SetStatus("No medal ghost for level " + level + ".", true);
    } else {
        SetStatus("Medal ghost request failed: " + string(task.ErrorDescription), true, true);
    }
    rules.ScoreMgr.TaskResult_Release(task.Id);
}

void LoadPbInner() {
    auto rules = CurrentRules();
    if (rules is null) {
        SetStatus("Not in a TrackMania race (no CTrackManiaRaceRules).", true, true);
        return;
    }
    auto sm = rules.ScoreMgr;
    if (sm is null) {
        SetStatus("ScoreMgr is null.", true, true);
        return;
    }
    string uid = CurrentMapUid();
    if (uid.Length == 0) {
        SetStatus("No map loaded.", true, true);
        return;
    }
    SetStatus("Requesting personal best ghost ...");
    auto task = sm.Map_GetRecordGhost(LocalUserId(), uid, "");
    if (task is null) {
        SetStatus("Map_GetRecordGhost returned null.", true, true);
        return;
    }
    while (task.IsProcessing) yield();

    if (task.HasSucceeded) {
        if (task.Ghost is null) {
            SetStatus("No personal best ghost for this map.", true);
        } else if (Ghosts_Add(task.Ghost, "PB") !is null) {
            SetStatus("Added personal best ghost.", true);
        } else {
            SetStatus("RaceGhost_Add rejected the personal best ghost" + AddRejectedWhy(), true, true);
        }
    } else {
        SetStatus("Map_GetRecordGhost failed: " + string(task.ErrorDescription), true, true);
    }
    sm.TaskResult_Release(task.Id);
}

// --- saving ----------------------------------------------------------------

CGameGhostScript@ g_saveGhost;
string g_saveName = "";

// DataFileMgr.Replay_Save(wstring Path, CGameCtnChallenge@ Map, CGameGhostScript@ Ghost).
// Nadeo passes a bare name here, so the engine resolves it inside the Replays folder.
void Save_Ghost(CGameGhostScript@ ghost, const string &in name) {
    if (g_busy || ghost is null) return;
    @g_saveGhost = ghost;
    g_saveName = name;
    startnew(CoroutineFunc(Save_GhostCoro));
}

void Save_GhostCoro() {
    g_busy = true;
    SaveGhostInner();
    @g_saveGhost = null;
    g_busy = false;
}

void SaveGhostInner() {
    auto rules = CurrentRules();
    if (rules is null || rules.DataFileMgr is null) {
        SetStatus("Cannot save: no DataFileMgr.", true, true);
        return;
    }
    auto map = CurrentMap();
    if (map is null) {
        SetStatus("Cannot save: no map.", true, true);
        return;
    }
    string name = g_saveName;
    if (name.Length == 0) name = "Ghosts2";
    if (!name.ToLower().EndsWith(".replay.gbx")) name += ".Replay.Gbx";

    auto dfm = rules.DataFileMgr;
    auto task = dfm.Replay_Save(wstring(name), map, g_saveGhost);
    if (task is null) {
        SetStatus("Replay_Save returned null.", true, true);
        return;
    }
    while (task.IsProcessing) yield();
    if (task.HasSucceeded) {
        SetStatus("Saved " + name, true);
    } else {
        SetStatus("Replay_Save failed: " + string(task.ErrorDescription), true, true);
    }
    dfm.TaskResult_Release(task.Id);
}
