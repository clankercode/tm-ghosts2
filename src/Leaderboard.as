// Leaderboard ghosts (world / zone records) for the current map.
//
// Flow credited to FortTM (2026-09-08), who traced what the game does when you add an opponent from the
// leaderboard dialog: ScoreMgr.MapLeaderBoard_GetPlayerList -> DataFileMgr.Ghost_Download -> RaceGhost_Add.
// New to us from that research: GetPlayerList takes (MwId(0) [behaves like the local user id], mapUid,
// context "" [what the game passes], zone e.g. "World", fromIndex, count), and each returned
// CGameNaturalLeaderBoardInfoScript carries FileName + ReplayUrl that Ghost_Download accepts as-is.

class LbEntry {
    uint rank;
    string login;
    string name;       // display name, Openplanet UI format codes
    string plainName;  // format codes stripped (source strings, logs, JSON)
    uint score;        // race time in ms
    string fileName;
    string url;
}

array<LbEntry@> g_lbEntries;
string g_lbMapUid = "";
string g_lbZone = "";
uint g_lbOffset = 0;
bool g_lbBusy = false;
string g_lbStatus = "";
// Automatic fetch for a new map, from the Load tab. Right after a map load the game answers
// "Unable to update leaderboard" for a good ten seconds (measured on A03: fetches at +0 / +4 / +8 s all
// failed, one at ~+16 s succeeded), so this retries over about half a minute before giving up; the Fetch
// button is always there, and it never runs more than LbAutoMaxTries times per map.
uint g_lbAutoTries = 0;
uint g_lbAutoNextAt = 0;
const uint LbAutoMaxTries = 6;
const uint LbAutoRetryMs = 6000;

bool Lb_WantAutoFetch() {
    return !g_lbBusy && g_lbEntries.Length == 0 && g_lbAutoTries < LbAutoMaxTries && Time::Now >= g_lbAutoNextAt;
}

void Lb_AutoFetch() {
    g_lbAutoTries++;
    g_lbAutoNextAt = Time::Now + LbAutoRetryMs;
    Lb_Fetch(0);
}

// The cached list belongs to one map. Dropped as soon as the map changes so a stale board is never shown
// (and never loadable); the Load tab fetches the new map's board by itself the next time it is drawn.
void Lb_OnMapChanged() {
    g_lbEntries.RemoveRange(0, g_lbEntries.Length);
    g_lbMapUid = "";
    g_lbOffset = 0;
    g_lbStatus = "";
    g_lbAutoTries = 0;
    g_lbAutoNextAt = 0;
}

#if TURBO
// Turbo's board is the map's own record table (medals + your record), read locally - there is no zone to
// pick and no second page, so naming a zone here would be a lie the UI then repeats.
const bool LbIsZoned = false;
string Lb_Zone() { return "this map"; }
#else
const bool LbIsZoned = true;
string Lb_Zone() { return S_LeaderboardZone.Length == 0 ? "World" : S_LeaderboardZone; }
#endif

void Lb_Fetch(uint offset) {
    if (g_lbBusy) return;
    startnew(CoroutineFuncUserdataString(Lb_FetchCoro), "" + offset);
}

void Lb_FetchCoro(const string &in offsetStr) {
    g_lbBusy = true;
    LbFetchInner(Text::ParseUInt(offsetStr));
    g_lbBusy = false;
}

void LbFetchInner(uint offset) {
#if TURBO
    // Turbo has no MapLeaderBoard_GetPlayerList. DataMgr.RetrieveRecords(MapInfo, UserId) fills
    // DataMgr.Records - the map's record table, medals included - and every row carries a GhostUrl that
    // GhostRetrieve accepts, so this is Turbo's leaderboard. It is one page, so `offset` is ignored.
    auto dm = DataMgr();
    if (dm is null) { g_lbStatus = "No DataMgr."; return; }
    auto map = CurrentMap();
    if (map is null || map.MapInfo is null) { g_lbStatus = "No map loaded."; return; }
    string uid = CurrentMapUid();
    g_lbStatus = "Fetching this map's records ...";
    dm.RetrieveRecords(map.MapInfo, LocalUserId());
    uint deadline = Time::Now + 20000;
    while (dm.LatestResult == CGameDataManagerScript::EResult::Running && Time::Now < deadline) yield();
    if (dm.LatestResult != CGameDataManagerScript::EResult::Finished_Ok) {
        g_lbStatus = "RetrieveRecords: " + tostring(dm.LatestResult);
        return;
    }
    g_lbEntries.RemoveRange(0, g_lbEntries.Length);
    for (uint i = 0; i < dm.Records.Length; i++) {
        auto r = dm.Records[i];
        if (r is null) continue;
        LbEntry e;
        e.rank = r.Rank > 0 ? r.Rank : i + 1;
        e.login = "";
        // Your own record comes back with an empty name; an unlabelled row reads as a broken entry.
        string rn = string(r.Name);
        if (Text::StripFormatCodes(rn).Length == 0) rn = LocalPlayerName();
        if (rn.Length == 0) rn = "(your record)";
        e.name = Text::OpenplanetFormatCodes(rn);
        e.plainName = Text::StripFormatCodes(rn);
        e.score = r.Time;
        e.fileName = r.GhostName;
        e.url = r.GhostUrl;
        g_lbEntries.InsertLast(e);
    }
    g_lbMapUid = uid;
    g_lbZone = "map";
    g_lbOffset = 0;
    g_lbStatus = "" + g_lbEntries.Length + " record(s) for this map";
#else
    auto rules = CurrentRules();
    if (rules is null || rules.ScoreMgr is null) { g_lbStatus = "No ScoreMgr (not in a race)."; return; }
    string uid = CurrentMapUid();
    if (uid.Length == 0) { g_lbStatus = "No map loaded."; return; }
    string zone = Lb_Zone();
    uint count = Math::Clamp(S_LeaderboardCount, 1, 100);
    g_lbStatus = "Fetching " + zone + " records " + (offset + 1) + ".." + (offset + count) + " ...";
    auto task = rules.ScoreMgr.MapLeaderBoard_GetPlayerList(MwId(0), uid, "", wstring(zone), offset, count);
    if (task is null) { g_lbStatus = "MapLeaderBoard_GetPlayerList returned null."; return; }
    while (task.IsProcessing) yield();
    if (task.HasSucceeded) {
        g_lbEntries.RemoveRange(0, g_lbEntries.Length);
        for (uint i = 0; i < task.LeaderBoardInfo.Length; i++) {
            auto info = task.LeaderBoardInfo[i];
            if (info is null) continue;
            LbEntry e;
            e.rank = info.Rank;
            e.login = info.Login;
            e.name = Text::OpenplanetFormatCodes(string(info.DisplayName));
            e.plainName = Text::StripFormatCodes(string(info.DisplayName));
            e.score = info.Score;
            e.fileName = string(info.FileName);
            e.url = info.ReplayUrl;
            g_lbEntries.InsertLast(e);
        }
        g_lbMapUid = uid;
        g_lbZone = zone;
        g_lbOffset = offset;
        g_lbStatus = "" + g_lbEntries.Length + " " + zone + " record(s) from #" + (offset + 1);
    } else {
        g_lbStatus = "Leaderboard request failed: " + string(task.ErrorDescription);
        warn("Ghosts2: " + g_lbStatus);
    }
    rules.ScoreMgr.TaskResult_Release(task.Id);
#endif
}

LbEntry@ Lb_FindByRank(uint rank) {
    for (uint i = 0; i < g_lbEntries.Length; i++) if (g_lbEntries[i].rank == rank) return g_lbEntries[i];
    return null;
}

// Download the entry's ghost and add it to the race.
bool Lb_Load(uint rank) {
    if (g_busy) return false;
    auto e = Lb_FindByRank(rank);
    if (e is null || e.url.Length == 0) return false;
    startnew(CoroutineFuncUserdataString(Lb_LoadCoro), "" + rank);
    return true;
}

void Lb_LoadCoro(const string &in rankStr) {
    g_busy = true;
    LbLoadInner(Text::ParseUInt(rankStr));
    g_busy = false;
}

void LbLoadInner(uint rank) {
#if TURBO
    auto e = Lb_FindByRank(rank);
    if (e is null) { SetStatus("Leaderboard entry #" + rank + " is not in the fetched list.", true, true); return; }
    auto dm = DataMgr();
    if (dm is null) { SetStatus("No DataMgr.", true, true); return; }
    if (e.url.Length == 0) { SetStatus("That record has no ghost url.", true, true); return; }
    string label = "#" + e.rank + " " + (e.plainName.Length > 0 ? e.plainName : e.login);
    SetStatus("Fetching ghost " + label + " ...");
    auto g = dm.GhostRetrieve(e.url);
    if (g is null) { SetStatus("GhostRetrieve returned nothing for " + label + " (" + tostring(dm.LatestResult) + ").", true, true); return; }
    uint deadline = Time::Now + 20000;
    while (g.DataState == CGameGhostScript::EDataState::InProgress && Time::Now < deadline) yield();
    if (g.DataState != CGameGhostScript::EDataState::Ready) { SetStatus("Ghost " + label + " came back " + tostring(g.DataState) + ".", true, true); return; }
    if (Ghosts_Add(g, "LB " + label) !is null) SetStatus("Added leaderboard ghost " + label + " (" + FormatTime(e.score) + ").", true);
    else SetStatus("Could not add the ghost " + label + AddRejectedWhy(), true, true);
#else
    auto e = Lb_FindByRank(rank);
    if (e is null) { SetStatus("Leaderboard entry #" + rank + " is not in the fetched list.", true, true); return; }
    auto rules = CurrentRules();
    if (rules is null || rules.DataFileMgr is null) { SetStatus("No DataFileMgr (solo-only surface).", true, true); return; }
    string label = "#" + e.rank + " " + (e.plainName.Length > 0 ? e.plainName : e.login);
    SetStatus("Downloading ghost " + label + " ...");
    auto task = rules.DataFileMgr.Ghost_Download(wstring(e.fileName), e.url);
    if (task is null) { SetStatus("Ghost_Download returned null for " + label, true, true); return; }
    while (task.IsProcessing) yield();
    if (task.HasSucceeded && task.Ghost !is null) {
        if (Ghosts_Add(task.Ghost, "LB " + label) !is null) SetStatus("Added leaderboard ghost " + label + " (" + FormatTime(e.score) + ").", true);
        else SetStatus("RaceGhost_Add rejected the ghost " + label + AddRejectedWhy(), true, true);
    } else if (task.HasSucceeded) {
        SetStatus("Ghost_Download returned no ghost for " + label, true, true);
    } else {
        SetStatus("Ghost_Download failed for " + label + ": " + string(task.ErrorDescription), true, true);
    }
    rules.DataFileMgr.TaskResult_Release(task.Id);
#endif
}

Json::Value@ Lb_ToJson() {
    auto o = Json::Object();
    o["mapUid"] = g_lbMapUid;
    o["zone"] = g_lbZone;
    o["offset"] = g_lbOffset;
    o["busy"] = g_lbBusy;
    o["status"] = g_lbStatus;
    auto arr = Json::Array();
    for (uint i = 0; i < g_lbEntries.Length; i++) {
        auto e = g_lbEntries[i];
        auto eo = Json::Object();
        eo["rank"] = e.rank; eo["login"] = e.login; eo["name"] = e.plainName; eo["score"] = e.score;
        eo["fileName"] = e.fileName; eo["url"] = e.url;
        arr.Add(eo);
    }
    o["entries"] = arr;
    return o;
}
