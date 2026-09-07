// Ghost playback time control (script-mode races only).
//
// Per RaceGhost_Add instance the engine keeps, on CTrackManiaRaceNew:
//   +0xdd0/+0xdd8  add-entry array (stride 0x18): +0x00 CGameCtnGhost*, +0x08 displayAsPlayerBest, +0x0c modelId,
//                  +0x10 OffsetMs (u32), +0x14 GhostInstId
//   +0xde0/+0xde8  array of pointers to 0x98-byte playback records: +0x10 StartTime, +0x14 started,
//                  +0x18 elapsed (ghost time, written every frame), +0x28 GhostInstId
// CTrackManiaRaceNew_UpdateFrame (0x140ebad00) does, every frame and for every record i:
//   if (player racing) record.StartTime = playerRaceStart + 1;          // so StartTime cannot be overridden
//   record.elapsed = max(0, (now + entry[i].OffsetMs) - record.StartTime) // OffsetMs is re-read every frame
// So the lever is entry.OffsetMs (as a signed int): OffsetMs = wantedGhostTime - (now - StartTime).
// Both arrays are rebuilt (and shuffled) on respawn, so everything is re-resolved by GhostInstId each frame.
// Evidence: research/mp4/2026-09-07-RaceGhost-Runtime.md ("Ghost time control").

const uint16 O_RaceNew_AddEntries = 0xdd0;
const uint16 O_RaceNew_AddEntryCount = 0xdd8;
const uint16 O_RaceNew_GhostRecords = 0xde0;
const uint16 O_RaceNew_GhostRecordCount = 0xde8;
const uint64 AddEntryStride = 0x18;
const uint64 O_Entry_OffsetMs = 0x10;   // u64 at +0x10 = {OffsetMs, GhostInstId}
const uint64 O_Rec_StartTime = 0x10;    // u64 at +0x10 = {StartTime, started}
const uint64 O_Rec_GhostTime = 0x18;
const uint64 O_Rec_InstId = 0x28;
const uint MaxGhostRecords = 256;

// diagnostics (State tab / ghosts2.state)
uint g_timeCtlUpdates = 0;
uint g_timeCtlWrites = 0;
string g_timeCtlLastErr = "";

// Records only exist for the script-mode playground; the classic race keeps its ghosts elsewhere.
CTrackManiaRaceNew@ ScriptRace() {
    auto app = App();
    if (app is null || app.CurrentPlayground is null) return null;
    if (TypeName(app.CurrentPlayground) != "CTrackManiaRaceNew") return null;
    return cast<CTrackManiaRaceNew>(app.CurrentPlayground);
}

uint64 SafeU64(uint64 addr) {
    try { return Dev::SafeReadUInt64(addr); } catch { return 0; }
}

// Resolved engine objects for one instance this frame.
class GhostSlot {
    uint64 entry = 0;   // add entry (OffsetMs at +0x10)
    uint64 rec = 0;     // playback record
    uint startTime = 0;
    bool started = false;
    int offsetMs = 0;
    int ghostTime = -1;
}

bool TimeCtl_Resolve(uint instId, GhostSlot@ slot) {
    if (instId == 0 || slot is null) return false;
    auto race = ScriptRace();
    if (race is null) return false;
    uint64 entries = Dev::GetOffsetUint64(race, O_RaceNew_AddEntries);
    uint nEntries = uint(Dev::GetOffsetUint64(race, O_RaceNew_AddEntryCount) & 0xffffffff);
    uint64 recs = Dev::GetOffsetUint64(race, O_RaceNew_GhostRecords);
    uint nRecs = uint(Dev::GetOffsetUint64(race, O_RaceNew_GhostRecordCount) & 0xffffffff);
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

    slot.rec = 0;
    for (uint i = 0; i < nRecs; i++) {
        uint64 r = SafeU64(recs + 8 * i);
        if (r != 0 && uint(SafeU64(r + O_Rec_InstId) & 0xffffffff) == instId) {
            slot.rec = r;
            break;
        }
    }
    if (slot.rec == 0) return false;
    uint64 st = SafeU64(slot.rec + O_Rec_StartTime);
    slot.startTime = uint(st & 0xffffffff);
    slot.started = uint(st >> 32) != 0;
    slot.ghostTime = slot.started ? int(uint(SafeU64(slot.rec + O_Rec_GhostTime) & 0xffffffff)) : -1;
    return true;
}

bool TimeCtl_Available() {
    return S_TimeControl && ScriptRace() !is null && CurrentRules() !is null;
}

// Current time into the replay (ms) as the engine computed it this frame; -1 when unknown / not started.
int TimeCtl_GhostTime(PluginGhost@ pg) {
    if (pg is null) return -1;
    GhostSlot slot;
    if (!TimeCtl_Resolve(pg.instId, slot)) return -1;
    return slot.ghostTime;
}

uint TimeCtl_Now() {
    auto rules = CurrentRules();
    return rules is null ? 0 : uint(rules.Now);
}

// Writes the entry's OffsetMs so that the ghost is `ghostTimeMs` into its replay on the next frame.
bool TimeCtl_WriteGhostTime(PluginGhost@ pg, uint ghostTimeMs) {
    GhostSlot slot;
    if (!TimeCtl_Resolve(pg.instId, slot)) { g_timeCtlLastErr = "no engine record for inst " + pg.instId; return false; }
    if (!slot.started) { g_timeCtlLastErr = "inst " + pg.instId + " not started"; return false; }
    uint now = TimeCtl_Now();
    if (now == 0) { g_timeCtlLastErr = "rules.Now == 0"; return false; }
    int offset = int(ghostTimeMs) - (int(now) - int(slot.startTime));
    Dev::Write(slot.entry + O_Entry_OffsetMs, uint(offset));
    g_timeCtlWrites++;
    return true;
}

bool TimeCtl_Seek(PluginGhost@ pg, uint ghostTimeMs) {
    if (!TimeCtl_Available() || pg is null) return false;
    pg.heldTime = float(ghostTimeMs);
    return TimeCtl_WriteGhostTime(pg, ghostTimeMs);
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

// Per frame: hold or advance the clock of every controlled ghost. Releasing control (not paused, speed 1)
// simply stops writing; the ghost continues from wherever it is at normal speed (OffsetMs persists until the
// engine rebuilds its records at the next respawn).
void TimeCtl_Update(float dt) {
    g_timeCtlUpdates++;
    if (g_ghosts.Length == 0 || !S_TimeControl) return;
    for (uint i = 0; i < g_ghosts.Length; i++) {
        auto pg = g_ghosts[i];
        if (!pg.Controlled() || pg.instId == 0) continue;
        if (!pg.paused) {
            pg.heldTime += dt * pg.speed;
            if (pg.heldTime < 0.0) pg.heldTime = 0.0;
        }
        TimeCtl_WriteGhostTime(pg, uint(pg.heldTime));
    }
}
