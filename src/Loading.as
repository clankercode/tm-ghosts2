// Sourcing ghosts: local replay files via DataFileMgr.Replay_Load, and the personal best
// via ScoreMgr.Map_GetRecordGhost. Both are async task-result APIs, so both run as coroutines.
// Note: Nadeo documents CGamePlaygroundScript.DataFileMgr as "only available for local solo modes".

bool g_busy = false;
string g_status = "";

// Every load waits on the game - a data manager task, a ghost decoding - and the player can leave the map
// while it waits. The ghost that finally arrives then belongs to a track they are no longer on, and adding it
// drops a foreign racing line into the race: the same mistake "Allow ghosts from other maps" exists to refuse,
// arriving by a different door. So a load remembers the map it began on and abandons itself once that changes.
string g_loadForMapUid = "";

void LoadBegin() { g_busy = true; g_loadForMapUid = CurrentMapUid(); }
void LoadEnd() { g_busy = false; g_loadForMapUid = ""; }

// False once the player has left the map this load was started for.
bool LoadStillWanted() { return g_loadForMapUid.Length > 0 && CurrentMapUid() == g_loadForMapUid; }

void SetStatus(const string &in msg, bool notify = false, bool isError = false) {
    // A load nobody asked for reports through the status line and an ordinary log line (see AutoLoad_Update):
    // no notification, and not a warning either - "this map has no personal best yet" is unremarkable, and
    // warning about it on every map entry is exactly the kind of log noise the plugin should not add.
    if (g_quietLoad) { notify = false; isError = false; }
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

// --- which map is a replay file from? --------------------------------------
//
// The CGameGhostScript that Replay_Load hands back carries no map identity at all - only a nickname, a time
// and checkpoints - so a replay from another track used to load without a word and drive a racing line that
// had nothing to do with the map you were on. The game's own replay index does know: CGameCtnApp
// .ReplayRecordInfos has a row per catalogued replay with its MapUid (plus who drove it and their time,
// which is worth showing in the browser anyway). Its FileName is relative to the Replays folder and
// backslash-separated ("Autosaves\AutoSave_PersonalBest_B01.Replay.Gbx"), while the browser works in
// absolute paths, so match it as a path suffix.
//
// A file the index has never seen (a folder outside the Replays tree, a replay dropped in since the game
// last catalogued) returns null, which has to read as "unknown" and never as "wrong map".
#if !TURBO
CGameCtnReplayRecordInfo@ ReplayFileInfo(const string &in path) {
    auto app = App();
    if (app is null) return null;
    string want = path.Replace("\\", "/").ToLower();
    if (want.Length == 0) return null;
    for (uint i = 0; i < app.ReplayRecordInfos.Length; i++) {
        auto ri = app.ReplayRecordInfos[i];
        if (ri is null) continue;
        string rel = string(ri.FileName).Replace("\\", "/").ToLower();
        // Folder rows have an empty FileName; EndsWith("") is true, so they would match everything.
        if (rel.Length > 0 && want.EndsWith(rel)) return ri;
    }
    return null;
}

// "" when the file is not in the index (unknown), else the uid of the map it was driven on.
string ReplayFileMapUid(const string &in path) {
    auto ri = ReplayFileInfo(path);
    return ri is null ? "" : string(ri.MapUid);
}

// True only when we positively know the file belongs to a different map than the one loaded.
bool ReplayIsFromAnotherMap(const string &in path) {
    string fileUid = ReplayFileMapUid(path);
    string mapUid = CurrentMapUid();
    return fileUid.Length > 0 && mapUid.Length > 0 && fileUid != mapUid;
}
#endif

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
    g_browseDirNames.RemoveRange(0, g_browseDirNames.Length);
    g_browseFileNames.RemoveRange(0, g_browseFileNames.Length);
    auto entries = IO::IndexFolder(g_browseDir, false);
    for (uint i = 0; i < entries.Length; i++) {
        string e = entries[i].Replace("\\", "/");
        // IO::IndexFolder marks a directory with a trailing separator. Do NOT use IO::FolderExists here:
        // in Openplanet it is the same "does this path exist" predicate as IO::FileExists, so it answers
        // true for ordinary files too - which listed every replay as a folder, left the file list empty
        // (so nothing could be loaded), and turned a click into "Folder not found: <the file>/".
        if (e.EndsWith("/")) {
            g_browseDirs.InsertLast(e);
            g_browseDirNames.InsertLast(BaseName(e));
        } else if (!S_FilterGhostFiles || LooksLikeGhostFile(e)) {
            g_browseFiles.InsertLast(e);
            g_browseFileNames.InsertLast(BaseName(e));
        }
    }
    Browse_RefreshFileInfo();
}

// Who drove each listed replay, what they got, and whether it is even this map - resolved once per listing
// rather than per frame (the row lookup is a scan of the whole replay index, and both lists are long).
// Display strings for the listing, built once when it is read rather than per row per frame: the Autosaves
// folder here holds 187 replays, and BaseName() on every one of them, every frame, is real cost in a
// callback that runs at frame rate.
array<string> g_browseFileNames;
array<string> g_browseDirNames;

array<string> g_browseFileWho;      // "nickname  0:12.34", or "" when the index does not know the file
array<bool> g_browseFileForeign;    // positively identified as belonging to a different map
string g_browseInfoMapUid = "";     // the map "foreign" was decided against; changes when you change map

// Recompute the per-file info if it was worked out for a different map than the one now loaded.
void Browse_RefreshFileInfoIfStale() {
    if (g_browseInfoMapUid != CurrentMapUid()) Browse_RefreshFileInfo();
}

void Browse_RefreshFileInfo() {
    g_browseFileWho.RemoveRange(0, g_browseFileWho.Length);
    g_browseFileForeign.RemoveRange(0, g_browseFileForeign.Length);
    string mapUid = CurrentMapUid();
    g_browseInfoMapUid = mapUid;
    for (uint i = 0; i < g_browseFiles.Length; i++) {
        string who = "";
        bool foreign = false;
#if !TURBO
        auto ri = ReplayFileInfo(g_browseFiles[i]);
        if (ri !is null) {
            who = Text::OpenplanetFormatCodes(string(ri.PlayerNickname));
            if (ri.BestTime > 0 && ri.BestTime != 0xffffffff) who += "  " + FormatTime(ri.BestTime);
            foreign = mapUid.Length > 0 && string(ri.MapUid).Length > 0 && string(ri.MapUid) != mapUid;
        }
#endif
        g_browseFileWho.InsertLast(who);
        g_browseFileForeign.InsertLast(foreign);
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
    LoadBegin();
    LoadReplayInner(path);
    LoadEnd();
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
    while (g.DataState == CGameGhostScript::EDataState::InProgress && Time::Now < deadline && LoadStillWanted()) yield();
    if (!LoadStillWanted()) { SetStatus("Load abandoned: you left the map before the ghost arrived."); return; }
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
    if (!S_AllowOtherMapGhosts && ReplayIsFromAnotherMap(path)) {
        SetStatus(BaseName(path) + " was driven on a different map, so its ghost would take a racing line "
                  "that does not fit this track. Loading → \"Allow ghosts from other maps\" loads it anyway.",
                  true, true);
        return;
    }
    SetStatus("Loading " + BaseName(path) + " ...");
    auto task = dfm.Replay_Load(wstring(path));
    if (task is null) {
        SetStatus("Replay_Load returned null for " + path, true, true);
        return;
    }
    while (task.IsProcessing && LoadStillWanted()) yield();
    if (!LoadStillWanted()) { SetStatus("Load abandoned: you left the map before the ghost arrived."); return; }

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
    LoadBegin();
    LoadPbInner();
    LoadEnd();
}

void Load_Medal(uint level) {
    if (g_busy || level < 1 || level > 4) return;
    startnew(CoroutineFuncUserdataString(Load_MedalCoro), "" + level);
}

void Load_MedalCoro(const string &in levelStr) {
    uint level = Text::ParseUInt(levelStr);
    LoadBegin();
    LoadMedalInner(level);
    LoadEnd();
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
    while (dm.LatestResult == CGameDataManagerScript::EResult::Running && Time::Now < deadline && LoadStillWanted()) yield();
    if (!LoadStillWanted()) { SetStatus("Load abandoned: you left the map before the ghost arrived."); return null; }
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
    while (g.DataState == CGameGhostScript::EDataState::InProgress && Time::Now < deadline && LoadStillWanted()) yield();
    if (!LoadStillWanted()) { SetStatus("Load abandoned: you left the map before the ghost arrived."); return null; }
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
    while (task.IsProcessing && LoadStillWanted()) yield();
    if (!LoadStillWanted()) { SetStatus("Load abandoned: you left the map before the ghost arrived."); return; }
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
    while (task.IsProcessing && LoadStillWanted()) yield();
    if (!LoadStillWanted()) { SetStatus("Load abandoned: you left the map before the ghost arrived."); return; }
    if (!task.HasSucceeded) {
        SetStatus("Campaign_GetMapRecordGhost failed: " + string(task.ErrorDescription), true, true);
        sm.ReleaseTaskResult(task.Id);
        return;
    }
    auto g = dm.GhostRetrieveFromTaskResult(task);
    sm.ReleaseTaskResult(task.Id);
    if (g is null) { SetStatus("No personal best ghost for this map.", true); return; }
    uint deadline = Time::Now + 20000;
    while (g.DataState == CGameGhostScript::EDataState::InProgress && Time::Now < deadline && LoadStillWanted()) yield();
    if (!LoadStillWanted()) { SetStatus("Load abandoned: you left the map before the ghost arrived."); return; }
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
    while (task.IsProcessing && LoadStillWanted()) yield();
    if (!LoadStillWanted()) { SetStatus("Load abandoned: you left the map before the ghost arrived."); return; }

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
    LoadBegin();
    SaveGhostInner();
    @g_saveGhost = null;
    LoadEnd();
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
    while (task.IsProcessing && LoadStillWanted()) yield();
    if (!LoadStillWanted()) { SetStatus("Load abandoned: you left the map before the ghost arrived."); return; }
    if (task.HasSucceeded) {
        SetStatus("Saved " + name, true);
    } else {
        SetStatus("Replay_Save failed: " + string(task.ErrorDescription), true, true);
    }
    dfm.TaskResult_Release(task.Id);
#endif
}


// --- loading something automatically when you arrive on a map ---------------
//
// Ghosts++ puts your own ghost on the track when you enter a map, and Ghosts2 not doing that was the single
// most confusing thing about it for a new user: the plugin looks inert until you find the Load tab, and a
// ghost you did load by hand is gone the moment you leave the map and come back (the retained list is
// dropped on a map change, deliberately - the ghosts belong to the map you loaded them for).
//
// This runs at most once per map, and stays quiet: no notification either way, because something that
// happens by itself on every map must not interrupt. The status line and the Ghosts tab still say what
// happened, and a failure here is genuinely unremarkable - plenty of maps have no personal best yet.

string g_autoLoadedFor = "";    // map uid the auto-load has already run for ("" = not yet on this map)
uint g_autoLoadAt = 0;          // Time::Now to fire at, 0 = nothing scheduled
bool g_quietLoad = false;       // suppress notifications for a load nobody asked for

// The race is usually not finished setting itself up on the frame the map uid appears, and a load fired into
// that window races the mode's own ghost handling and just gets rejected.
const uint AutoLoadDelayMs = 1500;

void AutoLoad_OnMapChanged() {
    g_autoLoadedFor = "";
    g_autoLoadAt = 0;
}

// Is one of the ghosts already in the race the local player's own? The campaign's challenge card loads it
// when you pick PERSONAL RECORD, and Ghosts2 adopts that - auto-loading on top would add it twice.
bool OwnGhostAlreadyPresent() {
    string me = LocalPlayerName();
    if (me.Length == 0) return false;
    for (uint i = 0; i < g_ghosts.Length; i++) {
        if (g_ghosts[i].nickname == me) return true;
    }
    for (uint i = 0; i < g_engineGhosts.Length; i++) {
        if (g_engineGhosts[i].nickname == me) return true;
    }
    return false;
}

void AutoLoad_Update() {
    if (!S_AutoLoadPB || g_busy) return;
    string uid = CurrentMapUid();
    if (uid.Length == 0 || uid == g_autoLoadedFor) return;
    // Not in a race that can take ghosts at all: the legacy solo playground refuses every RaceGhost_Add, so
    // firing here would only produce a guaranteed failure on every map entry.
    if (!Race_CanAddGhosts()) return;
    if (g_autoLoadAt == 0) { g_autoLoadAt = Time::Now + AutoLoadDelayMs; return; }
    if (Time::Now < g_autoLoadAt) return;
    // Claim the map before starting: this must not fire twice while the load is in flight.
    g_autoLoadedFor = uid;
    g_autoLoadAt = 0;
    if (OwnGhostAlreadyPresent()) {
        trace("Ghosts2: auto-load skipped, your own ghost is already in the race");
        return;
    }
    startnew(CoroutineFunc(AutoLoadPbCoro));
}

void AutoLoadPbCoro() {
    LoadBegin();
    g_quietLoad = true;
    LoadPbInner();
    g_quietLoad = false;
    LoadEnd();
}
