// Retained ghost state: what Ghosts2 put into the race, and putting it back when the mode wipes it.

class PluginGhost {
    CGameGhostScript@ ghost;
    string nickname;
    string source;          // where it came from (file path / "PB" / ...)
    uint raceTime = 0;
    string key;             // GhostKey(nickname, raceTime)

    uint instId = 0;        // MwId.Value returned by RaceGhost_Add; 0 == not added
    bool displayAsPlayerBest = false;
    uint offsetMs = 0;

    bool inRace = false;    // seen in CTrackManiaRace.RaceGhosts on the last scan
    uint failedReAdds = 0;
    bool gaveUp = false;

    PluginGhost(CGameGhostScript@ g, const string &in src) {
        @ghost = g;
        source = src;
        nickname = g is null ? "?" : string(g.Nickname);
        raceTime = ScriptGhostTime(g);
        key = GhostKey(nickname, raceTime);
    }

    MwId InstMwId() { return MwId(instId); }
}

array<PluginGhost@> g_ghosts;
string g_trackedMapUid = "";
uint g_lastScan = 0;

// --- mutations -------------------------------------------------------------

// Adds `g` to the race and starts tracking it. Returns null if the add failed.
PluginGhost@ Ghosts_Add(CGameGhostScript@ g, const string &in source, bool displayAsPlayerBest = false, uint offsetMs = 0) {
    if (g is null) return null;
    auto pg = PluginGhost(g, source);
    pg.displayAsPlayerBest = displayAsPlayerBest;
    pg.offsetMs = offsetMs;
    if (!Ghosts_PushToRace(pg)) {
        warn("RaceGhost_Add failed for " + pg.nickname);
        return null;
    }
    g_ghosts.InsertLast(pg);
    g_trackedMapUid = CurrentMapUid();
    return pg;
}

// (Re-)adds a tracked ghost to the race. Does not touch g_ghosts.
bool Ghosts_PushToRace(PluginGhost@ pg) {
    auto rules = CurrentRules();
    if (rules is null || pg is null || pg.ghost is null) return false;
    if (pg.offsetMs > 0) {
        pg.instId = rules.RaceGhost_AddWithOffset(pg.ghost, pg.offsetMs).Value;
    } else {
        pg.instId = rules.RaceGhost_Add(pg.ghost, pg.displayAsPlayerBest).Value;
    }
    return pg.instId != 0;
}

void Ghosts_Remove(PluginGhost@ pg) {
    if (pg is null) return;
    auto rules = CurrentRules();
    if (rules !is null && pg.instId != 0) rules.RaceGhost_Remove(pg.InstMwId());
    Spectate_ForgetGhost(pg.instId);
    int idx = g_ghosts.FindByRef(pg);
    if (idx >= 0) g_ghosts.RemoveAt(idx);
}

void Ghosts_RemoveAll() {
    auto rules = CurrentRules();
    if (rules !is null) rules.RaceGhost_RemoveAll();
    Spectate_Stop();
    g_ghosts.RemoveRange(0, g_ghosts.Length);
}

// Drop our bookkeeping without touching the race (used on map change).
void Ghosts_ForgetAll() {
    Spectate_Reset();
    g_ghosts.RemoveRange(0, g_ghosts.Length);
}

// --- tracking --------------------------------------------------------------

void Ghosts_Update() {
    string uid = CurrentMapUid();
    if (uid != g_trackedMapUid) {
        if (g_ghosts.Length > 0) trace("map changed (" + g_trackedMapUid + " -> " + uid + "); dropping " + g_ghosts.Length + " retained ghost(s)");
        g_trackedMapUid = uid;
        Ghosts_ForgetAll();
        return;
    }
    if (g_ghosts.Length == 0) return;

    uint now = Time::Now;
    if (now - g_lastScan < S_ScanIntervalMs) return;
    g_lastScan = now;

    auto race = CurrentRace();
    auto rules = CurrentRules();
    if (race is null || rules is null) return;

    // Match our ghosts against the live list. Consume matches so duplicates line up 1:1.
    array<string> present;
    for (uint i = 0; i < race.RaceGhosts.Length; i++) {
        auto g = race.RaceGhosts[i];
        if (g is null) continue;
        present.InsertLast(GhostKey(string(g.GhostNickname), g.RaceTime));
    }
    for (uint i = 0; i < g_ghosts.Length; i++) {
        auto pg = g_ghosts[i];
        int idx = present.Find(pg.key);
        if (idx >= 0) {
            present.RemoveAt(idx);
            pg.inRace = true;
            pg.failedReAdds = 0;
            pg.gaveUp = false;
        } else {
            pg.inRace = false;
        }
    }

    if (!S_AutoReAdd) return;
    for (uint i = 0; i < g_ghosts.Length; i++) {
        auto pg = g_ghosts[i];
        if (pg.inRace || pg.gaveUp) continue;
        pg.failedReAdds++;
        if (pg.failedReAdds > S_MaxReAddAttempts) {
            pg.gaveUp = true;
            warn("giving up re-adding ghost '" + pg.nickname + "' after " + S_MaxReAddAttempts + " attempts");
            continue;
        }
        if (Ghosts_PushToRace(pg)) trace("re-added ghost '" + pg.nickname + "' (inst " + pg.instId + ")");
    }
}

// Finds the tracked ghost matching a CGameCtnGhost row, or null.
PluginGhost@ Ghosts_FindByCtn(CGameCtnGhost@ g) {
    if (g is null) return null;
    string key = GhostKey(string(g.GhostNickname), g.RaceTime);
    for (uint i = 0; i < g_ghosts.Length; i++) {
        if (g_ghosts[i].key == key) return g_ghosts[i];
    }
    return null;
}
