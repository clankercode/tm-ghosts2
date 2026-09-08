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

    uint64 clockRec = 0;    // engine record whose clock we own (0 = engine drives it)

    // Per-frame memo for TimeCtl_Resolve (see TimeControl.as). Resolving walks the race's entry and record
    // arrays with guarded Dev reads, and one frame asks for the same ghost four to six times.
    uint resolveFrame = 0;
    bool resolveOk = false;
    GhostSlot@ resolveSlot;

    // engine ghosts (CTrackManiaRace.RaceGhosts, classic race): no CGameGhostScript, identified by nod address
    bool engine = false;
    CGameCtnGhost@ ctn;
    uint64 ctnPtr = 0;

    // script instance found in the race that we did not add (plugin reload, the game's own leaderboard dialog, ...)
    bool adopted = false;

    bool Controlled() { return clockRec != 0; }

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

    PluginGhost(CGameCtnGhost@ g, uint id, const string &in src) {
        adopted = true;
        @ctn = g;
        ctnPtr = NodPointer(g);
        instId = id;
        source = src;
        nickname = g is null ? "?" : string(g.GhostNickname);
        raceTime = g is null ? 0 : g.RaceTime;
        key = GhostKey(nickname, raceTime);
        inRace = true;
    }

    MwId InstMwId() { return MwId(instId); }
    // nickname with the game's $-format codes converted for Openplanet's UI (raw one kept for matching)
    string DisplayName() { return Text::OpenplanetFormatCodes(nickname); }
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

// Script modes: every RaceGhost_Add'ed instance lives in the race's add-entry array (race+0xdd0, stride 0x18:
// +0x0 CGameCtnGhost, +0x8 displayAsPlayerBest, +0x10 OffsetMs, +0x14 GhostInstId). Instances we do not track
// (added before a plugin reload, or by the game's own leaderboard dialog) are adopted so they get the same
// spectate / time control / remove actions. The CGameGhostScript handle is recovered from DataFileMgr.Ghosts by
// nickname + time when possible (needed for re-adding after the mode wipes ghosts).
// Two lists: the script-facing add list (race+0x1d0: RaceGhost_Add lands here immediately) and the live copy
// (race+0xdd0) the engine rebuilds from it at every (re)spawn. A ghost added since the last spawn is only in the
// first, one removed since the last spawn only in the second (still visible until the next spawn); read both.
// Returns every GhostInstId the race currently holds (both lists), or null if the race could not be read.
// An instance in neither list is gone from the engine, whether or not it ever started.
array<uint>@ Ghosts_AdoptRaceInstances(CTrackManiaRaceRules@ rules) {
    auto race = CurrentRace();
    if (race is null) return null;
    array<uint> ids;
    if (!Ghosts_AdoptList(rules, race, O_Race_ScriptAddEntries, O_Race_ScriptAddEntryCount, ids)) return null;
    if (!Ghosts_AdoptList(rules, race, O_Race_AddEntries, O_Race_AddEntryCount, ids)) return null;
    for (int i = int(g_removedInstIds.Length) - 1; i >= 0; i--) {
        if (ids.Find(g_removedInstIds[i]) < 0) g_removedInstIds.RemoveAt(uint(i));
    }
    for (int i = int(g_ignoredInstIds.Length) - 1; i >= 0; i--) {
        if (ids.Find(g_ignoredInstIds[i]) < 0) g_ignoredInstIds.RemoveAt(uint(i));
    }
    return ids;
}

bool Ghosts_AdoptList(CTrackManiaRaceRules@ rules, CTrackManiaRace@ race, uint16 listOff, uint16 countOff, array<uint>@ ids) {
    uint64 entries = Dev::GetOffsetUint64(race, listOff);
    uint nEntries = uint(Dev::GetOffsetUint64(race, countOff) & 0xffffffff);
    if (nEntries > MaxGhostRecords) return false;
    if (entries == 0 || nEntries == 0) return true;
    for (uint i = 0; i < nEntries; i++) {
        uint64 e = entries + AddEntryStride * i;
        uint64 v, ghostPtr, flags;
        try { v = SafeU64(e + O_Entry_OffsetMs); ghostPtr = SafeU64(e); flags = SafeU64(e + 8); } catch { return false; }
        uint instId = uint(v >> 32);
        if (instId == 0) continue;
        if (ids.Find(instId) < 0) ids.InsertLast(instId);
        if (Ghosts_WasRemoved(instId)) continue;
        if (Ghosts_FindByInstId(instId) !is null) continue;
        auto ctn = cast<CGameCtnGhost>(NodFromPointer(ghostPtr));
        auto pg = PluginGhost(ctn, instId, "race");
        pg.offsetMs = uint(v & 0xffffffff);
        pg.displayAsPlayerBest = (flags & 0xffffffff) != 0;
        auto dfm = DataMgr();
        if (dfm !is null) {
            for (uint j = 0; j < dfm.Ghosts.Length; j++) {
                auto gs = dfm.Ghosts[j];
                if (gs is null || string(gs.Nickname) != pg.nickname || ScriptGhostTime(gs) != pg.raceTime) continue;
                @pg.ghost = gs;
                pg.source = "race (DataMgr)";
                break;
            }
        }
        // The solo mode scripts put the local player's own live recording in the race (RaceGhost_Add with
        // DisplayAsPlayerBest). It has no finished time, so no CGameGhostScript can be recovered for it and
        // it can never be re-added - adopting it just produced a dead row plus five "giving up re-adding"
        // warnings every time the mode rebuilt its ghosts with a fresh instance id.
        if (Ghosts_WasRemovedKey(pg.key)) continue;   // you removed this ghost; the mode re-added it under a new id
        if (pg.ghost is null && (pg.raceTime == 0 || pg.raceTime == 0xffffffff)) {
            // Say so once per instance, not once per scan: this entry stays in the race's add list for the
            // whole run, and adoption revisits it every time.
            if (g_ignoredInstIds.Find(instId) < 0) {
                g_ignoredInstIds.InsertLast(instId);
                trace("Ghosts2: ignoring race ghost with no finished time and no script handle: " + pg.DisplayName() + " inst " + Text::Format("0x%08x", instId));
            }
            continue;
        }
        g_ghosts.InsertLast(pg);
        Scrubber_AutoOpen(pg);
        trace("Ghosts2: adopted race ghost " + pg.DisplayName() + " (" + FormatTime(pg.raceTime) + ") inst " + Text::Format("0x%08x", instId) + (pg.ghost is null ? ", no script handle" : ""));
    }
    return true;
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

PluginGhost@ Ghosts_FindByInstId(uint instId) {
    if (instId == 0) return null;
    for (uint i = 0; i < g_ghosts.Length; i++) if (g_ghosts[i].instId == instId) return g_ghosts[i];
    for (uint i = 0; i < g_engineGhosts.Length; i++) if (g_engineGhosts[i].instId == instId) return g_engineGhosts[i];
    return null;
}
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
    Ghosts_RequestSpawnForAdd();
    g_trackedMapUid = CurrentMapUid();
    Scrubber_AutoOpen(pg);
    return pg;
}

// A ghost handed to RaceGhost_Add only lands in the race's pending add list (race+0x1d0); the engine builds its
// playback record when the local player next spawns, so a ghost added mid-run never starts. Adds therefore ask
// for a restart, coalesced over a short window so loading a page of leaderboard ghosts restarts the run once.
// The restart is a real cost mid-lap - it throws the attempt away - so by default it only happens while you
// are still on the start line; otherwise the pending restart is parked and offered as a button.
uint g_spawnForAddAt = 0;    // Time::Now deadline, 0 = nothing pending
bool g_restartOffered = false;   // an add is waiting for a restart the user has to ask for
bool g_restartHeld = false;      // pending restart waiting for a run to exist (say it once, not every pump)
const uint SpawnForAddCoalesceMs = 400;

void Ghosts_RequestSpawnForAdd() {
    if (S_RespawnOnAdd == RespawnOnAdd::Never) return;
    g_spawnForAddAt = Time::Now + SpawnForAddCoalesceMs;
}

void Ghosts_CancelSpawnForAdd() { g_spawnForAddAt = 0; g_restartHeld = false; }

// "Mid-lap" = a lap worth protecting: spawned, at least one checkpoint crossed, and still being driven.
// Neither half is enough on its own. The race clock is not a test - in solo it runs from the end of the
// countdown whether or not the car moved, so timing on it would suppress the restart in exactly the case it
// is needed (adding ghosts at the line). And CurRace keeps the previous run's checkpoints, so the
// checkpoint count alone reports mid-lap while the car sits on the start line - hence the idle check.
const uint MidLapIdleMs = 1500;
bool Race_MidLap() {
    auto p = LocalPlayer();
    if (p is null) return false;
    if (!p.IsSpawned || p.CurRace is null || p.CurRace.Checkpoints.Length == 0) return false;
    return PlayerIdleDuration(p) < MidLapIdleMs;
}

// Restart now, whatever the setting says (the Ghosts tab button and the scrubber's Respawn).
bool Ghosts_RestartForAdds() {
    g_spawnForAddAt = 0;
    g_restartOffered = false;
    g_restartHeld = false;
    if (Race_SpawnLocal(S_RespawnOnAddDelayMs)) { SetStatus("Restarting the run so the new ghost(s) start."); return true; }
    if (!Race_RunStarted()) {
        // Nothing to restart yet, and asking anyway costs the player the screen they are on (see
        // Race_RunStarted), so hold it instead of spending their state on a spawn the mode will discard.
        g_restartHeld = true;
        g_spawnForAddAt = Time::Now + SpawnForAddCoalesceMs;
        SetStatus("Ghost added. It starts when you start your run.", true);
        return false;
    }
    SetStatus("The run could not be restarted - press Respawn to start the new ghost(s).", true, true);
    return false;
}

// The offer is stale as soon as every tracked ghost has a playback record (any spawn does that).
void Ghosts_ExpireRestartOffer() {
    if (!g_restartOffered) return;
    for (uint i = 0; i < g_ghosts.Length; i++) {
        auto pg = g_ghosts[i];
        if (pg.inRace && !pg.gaveUp && TimeCtl_GhostTime(pg) < 0) return;
    }
    g_restartOffered = false;
}

void Ghosts_PumpSpawnForAdd() {
    if (g_spawnForAddAt == 0 || Time::Now < g_spawnForAddAt) return;
    if (!Race_RunStarted()) {
        // Sitting behind a mode's pre-run screen (CampaignSolo parks the car on the track behind the map's
        // challenge card). A spawn request from there takes the car away and leaves the card up, and the
        // ghost would not start anyway - so hold the restart until there is a run to restart. It fires on
        // the first pump after the player starts, while they are still on the line and it costs nothing.
        if (!g_restartHeld) {
            g_restartHeld = true;
            SetStatus("Ghost added. It starts when you start your run.", true);
        }
        g_spawnForAddAt = Time::Now + SpawnForAddCoalesceMs;
        return;
    }
    g_restartHeld = false;
    if (S_RespawnOnAdd == RespawnOnAdd::UnlessMidLap && Race_MidLap()) {
        // Parking the restart is the whole point here: taking a lap away to start a ghost is worse than the
        // ghost waiting for the next respawn.
        g_spawnForAddAt = 0;
        g_restartOffered = true;
        SetStatus("Ghost added. It starts at your next restart - the lap you are driving was left alone.", true);
        return;
    }
    Ghosts_RestartForAdds();
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

// RaceGhost_Remove only takes the instance out of the script-facing list; the live copy (race+0xdd0) keeps
// it, and keeps playing it, until the engine rebuilds at the next spawn. Adoption reads that live copy, so
// without this set a removed ghost was re-adopted on the very next scan. Ids are dropped again once the
// engine has actually forgotten them.
array<uint> g_removedInstIds;
// ...and by identity (nickname + time), because the mode re-adds its ghosts under a *new* instance id after
// every phase change: an id-only filter let a ghost you removed walk straight back into the list.
array<string> g_removedKeys;
// Instances deliberately not adopted (the local player's own live recording, see Ghosts_AdoptList). Adoption
// runs every scan and these never enter g_ghosts, so without remembering them the "ignoring race ghost" line
// was written to the log once per scan - about once a second, for as long as the run lasted.
array<uint> g_ignoredInstIds;

bool Ghosts_WasRemoved(uint instId) { return g_removedInstIds.Find(instId) >= 0; }
bool Ghosts_WasRemovedKey(const string &in key) { return key.Length > 0 && g_removedKeys.Find(key) >= 0; }

void Ghosts_Remove(PluginGhost@ pg) {
    if (pg is null) return;
    auto rules = CurrentRules();
    bool isEngine = g_engineGhosts.FindByRef(pg) >= 0;
    if (rules !is null && pg.instId != 0) rules.RaceGhost_Remove(pg.InstMwId());
    // The game's own race ghosts (the opponents you picked in its dialog) are not ours to take out: in the
    // legacy solo playground RaceGhost_Remove is a no-op, and Ghosts_SyncEngine reads them straight back out
    // of CTrackManiaRace.RaceGhosts. Check whether the removal actually landed instead of pretending it did.
    if (isEngine) {
        auto race = CurrentRace();
        if (race !is null) {
            for (uint i = 0; i < race.RaceGhosts.Length; i++) {
                if (NodPointer(race.RaceGhosts[i]) != pg.ctnPtr) continue;
                SetStatus(pg.DisplayName() + " is one of the game's own race ghosts and stays in the race - pick opponents in the game's own dialog to change them.", true, true);
                return;
            }
        }
    }
    if (pg.instId != 0 && !Ghosts_WasRemoved(pg.instId)) g_removedInstIds.InsertLast(pg.instId);
    if (!Ghosts_WasRemovedKey(pg.key)) g_removedKeys.InsertLast(pg.key);
    Spectate_ForgetGhost(pg.instId);
    int idx = g_ghosts.FindByRef(pg);
    if (idx >= 0) g_ghosts.RemoveAt(idx);
    else {
        // engine ghosts (classic race) live in their own list; without this they stayed on screen
        idx = g_engineGhosts.FindByRef(pg);
        if (idx >= 0) g_engineGhosts.RemoveAt(idx);
    }
    SetStatus("Removed " + pg.DisplayName() + " - it stops driving at your next restart.");
}

void Ghosts_RemoveAll() {
    auto rules = CurrentRules();
    if (rules !is null) rules.RaceGhost_RemoveAll();
    Spectate_Stop();
    for (uint i = 0; i < g_ghosts.Length; i++) {
        uint id = g_ghosts[i].instId;
        if (id != 0 && !Ghosts_WasRemoved(id)) g_removedInstIds.InsertLast(id);
        if (!Ghosts_WasRemovedKey(g_ghosts[i].key)) g_removedKeys.InsertLast(g_ghosts[i].key);
    }
    g_ghosts.RemoveRange(0, g_ghosts.Length);
}

// Drop our bookkeeping without touching the race (used on map change).
void Ghosts_ForgetAll() {
    g_removedInstIds.RemoveRange(0, g_removedInstIds.Length);
    g_removedKeys.RemoveRange(0, g_removedKeys.Length);
    g_ignoredInstIds.RemoveRange(0, g_ignoredInstIds.Length);
    Spectate_Reset();
    TimeCtl_ReleaseAll();
    g_ghosts.RemoveRange(0, g_ghosts.Length);
    g_engineGhosts.RemoveRange(0, g_engineGhosts.Length);
}

// --- tracking --------------------------------------------------------------

void Ghosts_Update() {
    string uid = CurrentMapUid();
    if (uid != g_trackedMapUid) {
        if (g_ghosts.Length > 0) trace("map changed (" + g_trackedMapUid + " -> " + uid + "); dropping " + g_ghosts.Length + " retained ghost(s)");
        g_trackedMapUid = uid;
        Spectate_Reset();
        Ghosts_ForgetAll();
        Ghosts_CancelSpawnForAdd();
        Lb_OnMapChanged();
        AutoLoad_OnMapChanged();
        SetStatus("");
        return;
    }

    Ghosts_PumpSpawnForAdd();
    Ghosts_ExpireRestartOffer();

    uint now = Time::Now;
    if (now - g_lastScan < S_ScanIntervalMs) return;
    g_lastScan = now;
    Ghosts_SyncEngine();
    auto rules = CurrentRules();
    array<uint>@ raceInstIds = rules is null ? null : Ghosts_AdoptRaceInstances(rules);
    if (g_ghosts.Length == 0 || rules is null) return;

    // RaceGhosts is empty in script-driven modes. Query each tracked instance directly.
    // A freshly added ghost reports startTime==0 && !visible until the player (re)starts,
    // so only an instance that previously reported startTime>0 counts as removed.
    for (uint i = 0; i < g_ghosts.Length; i++) {
        auto pg = g_ghosts[i];
        if (pg.instId == 0) {
            pg.inRace = false;
            continue;
        }
        bool visible = RaceGhostVisible(rules, pg.InstMwId());
        uint startTime = rules.RaceGhost_GetStartTime(pg.InstMwId());
        if (visible || startTime > 0) {
            if (startTime > 0) pg.everStarted = true;
            pg.inRace = true;
        } else if (raceInstIds !is null && raceInstIds.Find(pg.instId) < 0) {
            // Neither add list holds this instance any more, so it is gone whether or not it ever started.
            // Without this a ghost that never started (added mid-run, then dropped by a rebuild) stayed
            // inRace forever: invisible, no playback record, and never re-added.
            pg.inRace = false;
        } else {
            pg.inRace = !pg.everStarted;
        }
    }

    if (!S_AutoReAdd) return;
    for (uint i = 0; i < g_ghosts.Length; i++) {
        auto pg = g_ghosts[i];
        if (pg.inRace || pg.gaveUp) continue;
        if (pg.ghost is null) {
            // Ghosts_PushToRace needs a CGameGhostScript; without one every attempt fails identically,
            // so stop at the first instead of counting to S_MaxReAddAttempts and warning each time.
            pg.gaveUp = true;
            trace("cannot re-add ghost '" + pg.nickname + "': no script handle");
            continue;
        }
        pg.failedReAdds++;
        if (pg.failedReAdds > S_MaxReAddAttempts) {
            pg.gaveUp = true;
            warn("giving up re-adding ghost '" + pg.nickname + "' after " + S_MaxReAddAttempts + " attempts");
            continue;
        }
        // no Ghosts_RequestSpawnForAdd() here: this fires when the mode wiped our ghosts, and its own
        // phase change respawns the player anyway - restarting from here would fight the mode script.
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
