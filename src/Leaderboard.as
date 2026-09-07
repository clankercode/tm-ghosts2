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
    string name;
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

string Lb_Zone() { return S_LeaderboardZone.Length == 0 ? "World" : S_LeaderboardZone; }

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
            e.name = string(info.DisplayName);
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
    auto e = Lb_FindByRank(rank);
    if (e is null) { SetStatus("Leaderboard entry #" + rank + " is not in the fetched list.", true, true); return; }
    auto rules = CurrentRules();
    if (rules is null || rules.DataFileMgr is null) { SetStatus("No DataFileMgr (solo-only surface).", true, true); return; }
    string label = "#" + e.rank + " " + e.name;
    SetStatus("Downloading ghost " + label + " ...");
    auto task = rules.DataFileMgr.Ghost_Download(wstring(e.fileName), e.url);
    if (task is null) { SetStatus("Ghost_Download returned null for " + label, true, true); return; }
    while (task.IsProcessing) yield();
    if (task.HasSucceeded && task.Ghost !is null) {
        if (Ghosts_Add(task.Ghost, "LB " + label) !is null) SetStatus("Added leaderboard ghost " + label + " (" + FormatTime(e.score) + ").", true);
        else SetStatus("RaceGhost_Add rejected the ghost " + label, true, true);
    } else if (task.HasSucceeded) {
        SetStatus("Ghost_Download returned no ghost for " + label, true, true);
    } else {
        SetStatus("Ghost_Download failed for " + label + ": " + string(task.ErrorDescription), true, true);
    }
    rules.DataFileMgr.TaskResult_Release(task.Id);
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
        eo["rank"] = e.rank; eo["login"] = e.login; eo["name"] = e.name; eo["score"] = e.score;
        eo["fileName"] = e.fileName; eo["url"] = e.url;
        arr.Add(eo);
    }
    o["entries"] = arr;
    return o;
}
