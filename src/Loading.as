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
#if TURBO
    // Turbo has no Replays folder. It saves a lap as <user folder>/<profile guid>/MapsGhosts/<n>.Ghost.Gbx,
    // so open the first MapsGhosts we can find and fall back to the user folder itself - never a path that
    // does not exist, which just showed "Folder not found" with an empty browser.
    string root = NormalizeDir(IO::FromUserGameFolder(""));
    auto entries = IO::IndexFolder(root, false);
    for (uint i = 0; i < entries.Length; i++) {
        string e = NormalizeDir(entries[i]);
        if (!e.EndsWith("/")) continue;
        string cand = e + "MapsGhosts/";
        if (IO::FolderExists(cand)) return cand;
    }
    return root;
#else
    return NormalizeDir(IO::FromUserGameFolder("Replays"));
#endif
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
    if (g is null) {
        // Every ghost file under a Turbo profile's MapsGhosts/ is a ~20-byte index stub, not ghost data, and
        // GhostRetrieve takes urls rather than file paths - so this is expected for those, and saying only
        // "found nothing" would send someone hunting for a bug that is not there.
        SetStatus("Turbo will not load " + BaseName(path) + " (" + tostring(dm.LatestResult) + "). Its "
                  "MapsGhosts files are index stubs, not ghost data - use Map records, the medal buttons or "
                  "Load my PB instead.", true, true);
        return;
    }
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

string MedalName(uint level) {
    if (level >= 4) return "author";
    if (level == 3) return "gold";
    if (level == 2) return "silver";
    return "bronze";
}

#if TURBO
// Find the medal ghost the engine loaded with the map. Match on the medal time first (the nicknames are
// localised, the times are not), then fall back to the nickname for a map with no medal times set.
CGameGhostScript@ Turbo_FindMedalGhost(uint level) {
    auto map = CurrentMap();
    int wanted = -1;
    if (map !is null) {
        if (level >= 4) wanted = int(map.TMObjective_AuthorTime);
        else if (level == 3) wanted = int(map.TMObjective_GoldTime);
        else if (level == 2) wanted = int(map.TMObjective_SilverTime);
        else wanted = int(map.TMObjective_BronzeTime);
    }
    auto ghosts = DataMgrGhosts();
    if (wanted > 0) {
        for (uint i = 0; i < ghosts.Length; i++) {
            auto r = GhostResult(ghosts[i]);
            if (r !is null && int(r.Time) == wanted) return ghosts[i];
        }
    }
    string needle = MedalName(level);
    for (uint i = 0; i < ghosts.Length; i++) {
        if (Text::StripFormatCodes(string(ghosts[i].Nickname)).ToLower().Contains(needle)) return ghosts[i];
    }
    return null;
}

// The medal time this map asks for, or -1 when the map does not set one.
int Turbo_MedalTime(uint level) {
    auto map = CurrentMap();
    if (map is null) return -1;
    if (level >= 4) return int(map.TMObjective_AuthorTime);
    if (level == 3) return int(map.TMObjective_GoldTime);
    if (level == 2) return int(map.TMObjective_SilverTime);
    return int(map.TMObjective_BronzeTime);
}

// Pull a medal ghost out of the map's record table (DataMgr.Records) - the only route to the author ghost on
// Turbo, since the engine never preloads one. Matches the record's time against the map's medal time, then
// falls back to the row's name. Blocks on the fetch and on the download, so call it from a coroutine.
CGameGhostScript@ Turbo_RetrieveMedalFromRecords(uint level) {
    auto dm = DataMgr();
    auto map = CurrentMap();
    if (dm is null || map is null || map.MapInfo is null) return null;
    int wanted = Turbo_MedalTime(level);
    string needle = MedalName(level);
    SetStatus("Looking for the " + needle + " ghost in this map's records ...");
    dm.RetrieveRecords(map.MapInfo, LocalUserId());
    uint deadline = Time::Now + 20000;
    while (dm.LatestResult == CGameDataManagerScript::EResult::Running && Time::Now < deadline) yield();
    if (dm.LatestResult != CGameDataManagerScript::EResult::Finished_Ok) return null;
    string url;
    for (uint i = 0; i < dm.Records.Length; i++) {
        auto r = dm.Records[i];
        if (r is null || string(r.GhostUrl).Length == 0) continue;
        bool hit = (wanted > 0 && int(r.Time) == wanted)
                   || Text::StripFormatCodes(string(r.Name)).ToLower().Contains(needle);
        if (hit) { url = r.GhostUrl; break; }
    }
    if (url.Length == 0) return null;
    auto g = dm.GhostRetrieve(url);
    if (g is null) return null;
    deadline = Time::Now + 20000;
    while (g.DataState == CGameGhostScript::EDataState::InProgress && Time::Now < deadline) yield();
    return g.DataState == CGameGhostScript::EDataState::Ready ? g : null;
}
#endif

#if TURBO
// The player's own record ghost, as the engine loaded it with the map: the one whose nickname is the
// local player's, and which is not one of the map's medal ghosts.
CGameGhostScript@ Turbo_FindOwnGhost() {
    string me = Text::StripFormatCodes(LocalPlayerName()).ToLower();
    if (me.Length == 0) return null;
    auto ghosts = DataMgrGhosts();
    for (uint i = 0; i < ghosts.Length; i++) {
        if (Text::StripFormatCodes(string(ghosts[i].Nickname)).ToLower() == me) return ghosts[i];
    }
    return null;
}
#endif

void LoadMedalInner(uint level) {
#if TURBO
    // Turbo's ScoreMgr has no Map_GetMultiAsyncLevelRecordGhost, and DataMgr.GhostRetrieve(":Medal:<name>")
    // hard-crashes the game (research/turbo/2026-09-08-Turbo-Setup.md). Neither is needed: in a campaign
    // race the engine has already loaded the map's Gold / Silver / Bronze ghosts into DataMgr.Ghosts, so
    // the medal is right there - offline, instantly, no web task at all. The author medal is the one
    // exception; Turbo never ships an author ghost with the map.
    auto g = Turbo_FindMedalGhost(level);
    if (g !is null) {
        if (Ghosts_Add(g, "Medal " + level) !is null) SetStatus("Added the " + MedalName(level) + " ghost.", true);
        else SetStatus("Could not add the " + MedalName(level) + " ghost" + AddRejectedWhy(), true, true);
        return;
    }
    // The author medal is never among the ghosts loaded with the map, but the map's record table has an
    // Author row whose GhostUrl GhostRetrieve accepts - so the author ghost is reachable after all, it just
    // costs a records fetch. Same route for any other medal the map did not preload.
    auto viaRecords = Turbo_RetrieveMedalFromRecords(level);
    if (viaRecords !is null) {
        if (Ghosts_Add(viaRecords, "Medal " + level) !is null) SetStatus("Added the " + MedalName(level) + " ghost.", true);
        else SetStatus("Could not add the " + MedalName(level) + " ghost" + AddRejectedWhy(), true, true);
        return;
    }
    SetStatus("No " + MedalName(level) + " ghost for this map: it is not among the ghosts loaded with the "
              "map, and the map's record table has no matching row.", true);
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
    // The engine loads the player's own record for the map alongside the medal ghosts, so try that first:
    // it is instant and it is the record the game itself shows. Only fall back to the web task (which is
    // what Campaign_GetMapRecordGhost is) when there is no local copy.
    auto local = Turbo_FindOwnGhost();
    if (local !is null) {
        if (Ghosts_Add(local, "PB") !is null) SetStatus("Added your personal best ghost.", true);
        else SetStatus("Could not add your personal best ghost" + AddRejectedWhy(), true, true);
        return;
    }
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
