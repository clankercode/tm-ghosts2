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
    if (g_browseDir.Length == 0) g_browseDir = DefaultReplaysFolder();
    if (!IO::FolderExists(g_browseDir)) {
        // keep the previous listing on screen: an empty pane hides where you actually are
        SetStatus("Folder not found: " + g_browseDir, false, true);
        return;
    }
    g_browseDirs.RemoveRange(0, g_browseDirs.Length);
    g_browseFiles.RemoveRange(0, g_browseFiles.Length);
    auto entries = IO::IndexFolder(g_browseDir, false);
    for (uint i = 0; i < entries.Length; i++) {
        string e = entries[i].Replace("\\", "/");
        // IO::IndexFolder marks a directory with a trailing separator. Do NOT use IO::FolderExists here:
        // in Openplanet it is the same "does this path exist" predicate as IO::FileExists, so it answers
        // true for ordinary files too - which listed every replay as a folder, left the file list empty
        // (so nothing could be loaded), and turned a click into "Folder not found: <the file>/".
        if (e.EndsWith("/")) {
            g_browseDirs.InsertLast(e);
        } else if (!S_FilterGhostFiles || LooksLikeGhostFile(e)) {
            g_browseFiles.InsertLast(e);
        }
    }
}

void Browse_Goto(const string &in dir) {
    if (LooksLikeGhostFile(dir)) { Load_ReplayFile(dir); return; }   // a mis-click must not strand the browser
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
#if TURBO
    // Turbo has no DataFileMgr.Replay_Load. CGameDataManagerScript.GhostRetrieve(url) is the whole loader:
    // it resolves ":Medal:<name>", ":Url:<http...>" and a plain path, and hands back a CGameGhostScript.
    auto dm = DataMgr();
    if (dm is null) { SetStatus("No DataMgr.", true, true); return; }
    SetStatus("Loading " + BaseName(path) + " ...");
    auto g = dm.GhostRetrieve(path);
    if (g is null) { SetStatus("GhostRetrieve found nothing at " + path + " (" + tostring(dm.LatestResult) + ").", true, true); return; }
    uint deadline = Time::Now + 20000;
    while (g.DataState == CGameGhostScript::EDataState::InProgress && Time::Now < deadline) yield();
    if (g.DataState != CGameGhostScript::EDataState::Ready) {
        SetStatus("GhostRetrieve returned " + tostring(g.DataState) + " for " + BaseName(path) + ".", true, true);
        return;
    }
    if (Ghosts_Add(g, "replay") !is null) SetStatus("Added " + BaseName(path) + ".", true);
    else SetStatus("Could not add the ghost" + AddRejectedWhy(), true, true);
#else
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
#endif
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
#if TURBO
    // Turbo's ScoreMgr has no Map_GetMultiAsyncLevelRecordGhost. The medal ghosts are the 44 official
    // "Author Medal" replays in CGameCtnApp.ReplayRecordInfos, and DataMgr.GhostRetrieve(":Medal:<name>")
    // is meant to reach them - but that call hard-crashes Turbo in every state tested so far
    // (research/turbo/2026-09-08-Turbo-Setup.md), so it is not wired up until the crash is understood.
    SetStatus("Medal ghosts are not available on Turbo yet: the engine's :Medal: ghost loader crashes the "
              "game, and Turbo's ScoreMgr has no medal-ghost request. Level " + level + " not loaded.", true, true);
#else
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
#endif
}

void LoadPbInner() {
#if TURBO
    // Turbo: Campaign_GetMapRecordGhost gives a ghost *handle* task, which DataMgr turns into a ghost.
    auto sm = ScoreMgr();
    auto dm = DataMgr();
    if (sm is null || dm is null) { SetStatus("No ScoreMgr / DataMgr.", true, true); return; }
    string uid = CurrentMapUid();
    if (uid.Length == 0) { SetStatus("No map loaded.", true, true); return; }
    SetStatus("Requesting personal best ghost ...");
    auto task = sm.Campaign_GetMapRecordGhost(LocalUserId(), uid);
    if (task is null) { SetStatus("Campaign_GetMapRecordGhost returned null.", true, true); return; }
    while (task.IsProcessing) yield();
    if (!task.HasSucceeded) {
        SetStatus("Campaign_GetMapRecordGhost failed: " + string(task.ErrorDescription), true, true);
        sm.ReleaseTaskResult(task.Id);
        return;
    }
    auto g = dm.GhostRetrieveFromTaskResult(task);
    sm.ReleaseTaskResult(task.Id);
    if (g is null) { SetStatus("No personal best ghost for this map.", true); return; }
    uint deadline = Time::Now + 20000;
    while (g.DataState == CGameGhostScript::EDataState::InProgress && Time::Now < deadline) yield();
    if (g.DataState != CGameGhostScript::EDataState::Ready) { SetStatus("PB ghost came back " + tostring(g.DataState) + ".", true, true); return; }
    if (Ghosts_Add(g, "PB") !is null) SetStatus("Added personal best ghost.", true);
    else SetStatus("Could not add the personal best ghost" + AddRejectedWhy(), true, true);
#else
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
#endif
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
#if TURBO
    // Turbo: DataMgr.StoreRecordName writes the ghost into the user's records for this map; there is no
    // Replay_Save, so a ghost cannot be written out as a .Replay.Gbx.
    auto dm = DataMgr();
    if (dm is null) { SetStatus("Cannot save: no DataMgr.", true, true); return; }
    string uid = CurrentMapUid();
    if (uid.Length == 0) { SetStatus("Cannot save: no map.", true, true); return; }
    string name = g_saveName;
    if (name.Length == 0) name = "Ghosts2";
    dm.StoreRecordName(uid, LocalUserId(), g_saveGhost, name);
    SetStatus("Stored " + name + " in this map's records (Turbo has no replay file writer).", true);
#else
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
#endif
}
