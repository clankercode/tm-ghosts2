// Ghost playback time control.
//
// Every ghost the engine plays has a 0x98-byte playback record (fields live on CTrackManiaRace, size 0x1278):
//   record: +0x00 CGameCtnGhost*, +0x10 StartTime, +0x14 started, +0x18 elapsed (ghost time, written every
//           frame), +0x28 GhostInstId, +0x40 flags, +0x48 vehicle-vis entry
//   race+0xde0/+0xde8  records of RaceGhost_Add instances (script modes), paired 1:1 with the add-entry array
//                      race+0xdd0/+0xdd8 (stride 0x18; +0x10 OffsetMs, +0x14 GhostInstId)
//   race+0x1080/+0x1088 records of the engine's RaceGhosts (classic campaign race; inst ids 0x0f00xxxx)
// The race UpdateFrame (0x140ebad00) does, every frame, for every record in both lists:
//   if (local player racing) record.StartTime = playerRaceStart - ghost->+0x40        // ghost+0x40 is -1 by default
//   record.elapsed = max(0, now [+ entry.OffsetMs, script list only] - record.StartTime)
// Levers: script instances -> entry.OffsetMs (signed, re-read every frame; independent of the player state).
//         engine ghosts     -> CGameCtnGhost+0x40 while the player races, record.StartTime otherwise (both are
//                              written; whichever the engine honours wins). Restored to -1 on release.
// Evidence: research/mp4/2026-09-07-RaceGhost-Runtime.md ("Ghost time control", "Classic race").

const uint16 O_Race_AddEntries = 0xdd0;
const uint16 O_Race_AddEntryCount = 0xdd8;
const uint16 O_Race_ScriptRecords = 0xde0;
const uint16 O_Race_ScriptRecordCount = 0xde8;
const uint16 O_Race_EngineRecords = 0x1080;
const uint16 O_Race_EngineRecordCount = 0x1088;
const uint64 AddEntryStride = 0x18;
const uint64 O_Entry_OffsetMs = 0x10;   // u64 at +0x10 = {OffsetMs, GhostInstId}
const uint64 O_Rec_Ghost = 0x0;
const uint64 O_Rec_StartTime = 0x10;    // u64 at +0x10 = {StartTime, started}
const uint64 O_Rec_GhostTime = 0x18;
const uint64 O_Rec_InstId = 0x28;
const uint64 O_Ghost_StartOffset = 0x40; // CGameCtnGhost: int, StartTime = playerRaceStart - this
const uint MaxGhostRecords = 256;

// diagnostics (State tab / ghosts2.state)
uint g_timeCtlUpdates = 0;
uint g_timeCtlWrites = 0;
string g_timeCtlLastErr = "";

uint64 SafeU64(uint64 addr) {
    try { return Dev::SafeReadUInt64(addr); } catch { return 0; }
}

// Resolved engine objects for one ghost this frame.
class GhostSlot {
    uint64 entry = 0;   // add entry (script instances only)
    uint64 rec = 0;
    uint64 ghostNod = 0;
    uint instId = 0;
    uint startTime = 0;
    bool started = false;
    int offsetMs = 0;
    int ghostTime = -1;
}

bool TimeCtl_ReadRecord(uint64 r, GhostSlot@ slot) {
    if (r == 0) return false;
    slot.rec = r;
    slot.ghostNod = SafeU64(r + O_Rec_Ghost);
    slot.instId = uint(SafeU64(r + O_Rec_InstId) & 0xffffffff);
    uint64 st = SafeU64(r + O_Rec_StartTime);
    slot.startTime = uint(st & 0xffffffff);
    slot.started = uint(st >> 32) != 0;
    slot.ghostTime = slot.started ? int(uint(SafeU64(r + O_Rec_GhostTime) & 0xffffffff)) : -1;
    return true;
}

// Script-mode instance: find the add entry and record by GhostInstId.
bool TimeCtl_ResolveScript(CTrackManiaRace@ race, uint instId, GhostSlot@ slot) {
    uint64 entries = Dev::GetOffsetUint64(race, O_Race_AddEntries);
    uint nEntries = uint(Dev::GetOffsetUint64(race, O_Race_AddEntryCount) & 0xffffffff);
    uint64 recs = Dev::GetOffsetUint64(race, O_Race_ScriptRecords);
    uint nRecs = uint(Dev::GetOffsetUint64(race, O_Race_ScriptRecordCount) & 0xffffffff);
    if (entries == 0 || recs == 0 || nEntries == 0 || nEntries > MaxGhostRecords || nRecs > MaxGhostRecords) return false;
    slot.entry = 0;
    for (uint i = 0; i < nEntries; i++) {
        uint64 e = entries + AddEntryStride * i;
        uint64 v = SafeU64(e + O_Entry_OffsetMs);
        if (uint(v >> 32) == instId) {
            slot.entry = e;
            slot.offsetMs = int(uint(v & 0xffffffff));
            break;
        }
    }
    if (slot.entry == 0) return false;
    for (uint i = 0; i < nRecs; i++) {
        uint64 r = SafeU64(recs + 8 * i);
        if (r != 0 && uint(SafeU64(r + O_Rec_InstId) & 0xffffffff) == instId) return TimeCtl_ReadRecord(r, slot);
    }
    return false;
}

// Engine ghost (classic race): find the record whose +0x0 is this CGameCtnGhost.
bool TimeCtl_ResolveEngine(CTrackManiaRace@ race, uint64 ghostNod, GhostSlot@ slot) {
    if (ghostNod == 0) return false;
    uint64 recs = Dev::GetOffsetUint64(race, O_Race_EngineRecords);
    uint nRecs = uint(Dev::GetOffsetUint64(race, O_Race_EngineRecordCount) & 0xffffffff);
    if (recs == 0 || nRecs == 0 || nRecs > MaxGhostRecords) return false;
    slot.entry = 0;
    for (uint i = 0; i < nRecs; i++) {
        uint64 r = SafeU64(recs + 8 * i);
        if (r != 0 && SafeU64(r + O_Rec_Ghost) == ghostNod) return TimeCtl_ReadRecord(r, slot);
    }
    return false;
}

bool TimeCtl_Resolve(PluginGhost@ pg, GhostSlot@ slot) {
    if (pg is null || slot is null) return false;
    auto race = CurrentRace();
    if (race is null) return false;
    if (pg.engine) {
        if (!TimeCtl_ResolveEngine(race, pg.ctnPtr, slot)) return false;
        pg.instId = slot.instId;
        return true;
    }
    return pg.instId != 0 && TimeCtl_ResolveScript(race, pg.instId, slot);
}

bool TimeCtl_Available() {
    return S_TimeControl && CurrentRace() !is null;
}

// Current time into the replay (ms) as the engine computed it this frame; -1 when unknown / not started.
int TimeCtl_GhostTime(PluginGhost@ pg) {
    GhostSlot slot;
    if (!TimeCtl_Resolve(pg, slot)) return -1;
    return slot.ghostTime;
}

int TimeCtl_ReadGhostStartOffset(uint64 ghostNod) {
    return int(uint(SafeU64(ghostNod + O_Ghost_StartOffset) & 0xffffffff));
}

// Makes the ghost be `ghostTimeMs` into its replay on the next frame. `dtMs` = the frame step the engine will
// add before that frame (0 for a one-shot seek).
bool TimeCtl_WriteGhostTime(PluginGhost@ pg, uint ghostTimeMs, float dtMs) {
    GhostSlot slot;
    if (!TimeCtl_Resolve(pg, slot)) { g_timeCtlLastErr = "no engine record for " + pg.nickname; return false; }
    if (!slot.started) { g_timeCtlLastErr = pg.nickname + " not started"; return false; }
    if (slot.entry != 0) {
        auto rules = CurrentRules();
        uint now = rules is null ? 0 : uint(rules.Now);
        if (now == 0) { g_timeCtlLastErr = "rules.Now == 0"; return false; }
        int offset = int(ghostTimeMs) - (int(now) - int(slot.startTime));
        Dev::Write(slot.entry + O_Entry_OffsetMs, uint(offset));
    } else {
        // now (as of the last tick) == StartTime + elapsed; the engine adds dtMs before recomputing elapsed.
        int delta = int(ghostTimeMs) - slot.ghostTime - int(dtMs);
        int startOffset = TimeCtl_ReadGhostStartOffset(slot.ghostNod);
        Dev::Write(slot.ghostNod + O_Ghost_StartOffset, uint(startOffset + delta));   // honoured while the player races
        Dev::Write(slot.rec + O_Rec_StartTime, uint(int(slot.startTime) - delta));      // honoured otherwise
    }
    g_timeCtlWrites++;
    return true;
}

// Engine ghosts: put CGameCtnGhost+0x40 back to its default so the next respawn starts the ghost normally.
void TimeCtl_Release(PluginGhost@ pg) {
    if (pg is null || !pg.engine) return;
    GhostSlot slot;
    if (TimeCtl_Resolve(pg, slot) && slot.ghostNod != 0) Dev::Write(slot.ghostNod + O_Ghost_StartOffset, uint(0xffffffff));
}

bool TimeCtl_Seek(PluginGhost@ pg, uint ghostTimeMs) {
    if (!TimeCtl_Available() || pg is null) return false;
    pg.heldTime = float(ghostTimeMs);
    return TimeCtl_WriteGhostTime(pg, ghostTimeMs, 0.0);
}

bool TimeCtl_SetPaused(PluginGhost@ pg, bool paused) {
    if (!TimeCtl_Available() || pg is null) return false;
    if (paused == pg.paused) return true;
    if (paused && !pg.Controlled()) {
        int t = TimeCtl_GhostTime(pg);
        if (t < 0) return false;
        pg.heldTime = float(t);
    }
    pg.paused = paused;
    return true;
}

bool TimeCtl_SetSpeed(PluginGhost@ pg, float speed) {
    if (!TimeCtl_Available() || pg is null) return false;
    if (speed < 0.0 || speed > 16.0) return false;
    if (speed != 1.0 && !pg.Controlled()) {
        int t = TimeCtl_GhostTime(pg);
        if (t < 0) return false;
        pg.heldTime = float(t);
    }
    pg.speed = speed;
    return true;
}

void TimeCtl_UpdateList(array<PluginGhost@>@ list, float dt) {
    for (uint i = 0; i < list.Length; i++) {
        auto pg = list[i];
        bool controlled = pg.Controlled();
        if (!controlled) {
            if (pg.wasControlled) TimeCtl_Release(pg);
            pg.wasControlled = false;
            continue;
        }
        pg.wasControlled = true;
        if (!pg.paused) {
            pg.heldTime += dt * pg.speed;
            if (pg.heldTime < 0.0) pg.heldTime = 0.0;
        }
        TimeCtl_WriteGhostTime(pg, uint(pg.heldTime), dt);
    }
}

// Per frame: hold or advance the clock of every controlled ghost. Releasing control (not paused, speed 1)
// stops writing; the ghost continues from wherever it is at normal speed.
void TimeCtl_Update(float dt) {
    g_timeCtlUpdates++;
    if (!S_TimeControl) return;
    if (g_ghosts.Length > 0) TimeCtl_UpdateList(g_ghosts, dt);
    if (g_engineGhosts.Length > 0) TimeCtl_UpdateList(g_engineGhosts, dt);
}
