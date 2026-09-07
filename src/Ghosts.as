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

    bool inRace = false;    // instance currently believed to be in the race
    bool everStarted = false; // has reported startTime>0 at least once
    uint failedReAdds = 0;
    bool gaveUp = false;

    // time control (TimeControl.as)
    bool paused = false;
    float speed = 1.0;
    float heldTime = 0.0;   // ms into the replay while paused / at non-1x speed

    bool wasControlled = false;

    // engine ghosts (CTrackManiaRace.RaceGhosts, classic race): no CGameGhostScript, identified by nod address
    bool engine = false;
    CGameCtnGhost@ ctn;
    uint64 ctnPtr = 0;

    bool Controlled() { return paused || speed != 1.0; }

    PluginGhost(CGameGhostScript@ g, const string &in src) {
        @ghost = g;
        source = src;
        nickname = g is null ? "?" : string(g.Nickname);
        raceTime = ScriptGhostTime(g);
        key = GhostKey(nickname, raceTime);
    }

    PluginGhost(CGameCtnGhost@ g) {
        engine = true;
        @ctn = g;
        ctnPtr = NodPointer(g);
        source = "engine";
        nickname = g is null ? "?" : string(g.GhostNickname);
        raceTime = g is null ? 0 : g.RaceTime;
        key = GhostKey(nickname, raceTime);
        inRace = true;
    }

    MwId InstMwId() { return MwId(instId); }
}

// Engine ghosts currently in CTrackManiaRace.RaceGhosts, one PluginGhost per nod (state survives rescans).
array<PluginGhost@> g_engineGhosts;

void Ghosts_SyncEngine() {
    auto race = CurrentRace();
    if (race is null) {
        g_engineGhosts.RemoveRange(0, g_engineGhosts.Length);
        return;
    }
    array<PluginGhost@> next;
    for (uint i = 0; i < race.RaceGhosts.Length; i++) {
        auto g = race.RaceGhosts[i];
        if (g is null) continue;
        uint64 ptr = NodPointer(g);
        PluginGhost@ found = null;
        for (uint j = 0; j < g_engineGhosts.Length; j++) {
            if (g_engineGhosts[j].ctnPtr == ptr) { @found = g_engineGhosts[j]; break; }
        }
        if (found is null) @found = PluginGhost(g);
        next.InsertLast(found);
    }
    g_engineGhosts = next;
    // learn each engine ghost's GhostInstId from its playback record (needed for the exports / pack)
    for (uint i = 0; i < g_engineGhosts.Length; i++) {
        if (g_engineGhosts[i].instId == 0) { GhostSlot slot; TimeCtl_Resolve(g_engineGhosts[i], slot); }
    }
}

PluginGhost@ Ghosts_FindEngineByCtn(CGameCtnGhost@ g) {
    if (g is null) return null;
    uint64 ptr = NodPointer(g);
    for (uint i = 0; i < g_engineGhosts.Length; i++) {
        if (g_engineGhosts[i].ctnPtr == ptr) return g_engineGhosts[i];
    }
    return null;
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
    pg.inRace = true;
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
    if (pg.instId != 0) {
        pg.everStarted = false;  // fresh instance: not started until the player (re)spawns
        return true;
    }
    return false;
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
    g_engineGhosts.RemoveRange(0, g_engineGhosts.Length);
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

    uint now = Time::Now;
    if (now - g_lastScan < S_ScanIntervalMs) return;
    g_lastScan = now;
    Ghosts_SyncEngine();
    if (g_ghosts.Length == 0) return;

    auto rules = CurrentRules();
    if (rules is null) return;

    // RaceGhosts is empty in script-driven modes. Query each tracked instance directly.
    // A freshly added ghost reports startTime==0 && !visible until the player (re)starts,
    // so only an instance that previously reported startTime>0 counts as removed.
    for (uint i = 0; i < g_ghosts.Length; i++) {
        auto pg = g_ghosts[i];
        if (pg.instId == 0) {
            pg.inRace = false;
            continue;
        }
        bool visible = rules.RaceGhost_IsVisible(pg.InstMwId());
        uint startTime = rules.RaceGhost_GetStartTime(pg.InstMwId());
        if (visible || startTime > 0) {
            if (startTime > 0) pg.everStarted = true;
            pg.inRace = true;
        } else {
            pg.inRace = !pg.everStarted;
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
