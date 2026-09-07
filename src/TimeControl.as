// Ghost playback time control (script-mode races only).
//
// The engine keeps one 0x98-byte record per RaceGhost_Add instance: CTrackManiaRaceNew+0xde0 is an array of
// record pointers, +0xde8 the count. record+0x10 (StartTime, what RaceGhost_GetStartTime returns) is the only
// input to the ghost's clock: ghost time = race Now - StartTime, recomputed every frame into record+0x18.
// Nothing rewrites StartTime per frame, so seek = one write, pause/speed = one write per frame.
// Evidence: research/mp4/2026-09-07-RaceGhost-Runtime.md ("Ghost time control").

const uint16 O_RaceNew_GhostRecords = 0xde0;
const uint16 O_RaceNew_GhostRecordCount = 0xde8;
const uint64 O_Rec_StartTime = 0x10;
const uint64 O_Rec_GhostTime = 0x18;
const uint64 O_Rec_InstId = 0x28;
const uint MaxGhostRecords = 256;

// Records only exist for the script-mode playground; the classic race keeps its ghosts elsewhere.
CTrackManiaRaceNew@ ScriptRace() {
    auto app = App();
    if (app is null || app.CurrentPlayground is null) return null;
    if (TypeName(app.CurrentPlayground) != "CTrackManiaRaceNew") return null;
    return cast<CTrackManiaRaceNew>(app.CurrentPlayground);
}

// Reads the u32 GhostInstId stored at record+0x28 (the u64 there is {instId, 4}); 0 when unreadable.
uint TimeCtl_RecordInstId(uint64 rec) {
    if (rec == 0) return 0;
    uint64 v = 0;
    try { v = Dev::SafeReadUInt64(rec + O_Rec_InstId); } catch { return 0; }
    return uint(v & 0xffffffff);
}

// Finds the engine record for a RaceGhost instance, or 0.
uint64 TimeCtl_FindRecord(uint instId) {
    if (instId == 0) return 0;
    auto race = ScriptRace();
    if (race is null) return 0;
    uint64 arr = Dev::GetOffsetUint64(race, O_RaceNew_GhostRecords);
    uint n = uint(Dev::GetOffsetUint64(race, O_RaceNew_GhostRecordCount) & 0xffffffff);
    if (arr == 0 || n == 0 || n > MaxGhostRecords) return 0;
    for (uint i = 0; i < n; i++) {
        uint64 rec = 0;
        try { rec = Dev::SafeReadUInt64(arr + 8 * i); } catch { return 0; }
        if (TimeCtl_RecordInstId(rec) == instId) return rec;
    }
    return 0;
}

// Cached record pointer for a tracked ghost, re-resolved when the instance changed or the record moved.
uint64 TimeCtl_Record(PluginGhost@ pg) {
    if (pg is null || pg.instId == 0) return 0;
    if (pg.rec != 0 && TimeCtl_RecordInstId(pg.rec) == pg.instId) return pg.rec;
    pg.rec = TimeCtl_FindRecord(pg.instId);
    return pg.rec;
}

bool TimeCtl_Available() {
    return S_TimeControl && ScriptRace() !is null && CurrentRules() !is null;
}

// Current time into the replay (ms) as the engine computed it this frame; -1 when unknown.
int TimeCtl_GhostTime(PluginGhost@ pg) {
    uint64 rec = TimeCtl_Record(pg);
    if (rec == 0) return -1;
    uint64 v = 0;
    try { v = Dev::SafeReadUInt64(rec + O_Rec_StartTime); } catch { return -1; }
    // +0x10 StartTime, +0x14 started flag; a not-yet-started ghost has no meaningful time
    if ((v >> 32) == 0) return -1;
    try { v = Dev::SafeReadUInt64(rec + O_Rec_GhostTime); } catch { return -1; }
    return int(v & 0xffffffff);
}

uint TimeCtl_Now() {
    auto rules = CurrentRules();
    return rules is null ? 0 : uint(rules.Now);
}

// Writes StartTime so that the ghost is `ghostTimeMs` into its replay right now.
bool TimeCtl_WriteGhostTime(PluginGhost@ pg, uint ghostTimeMs) {
    uint64 rec = TimeCtl_Record(pg);
    if (rec == 0) return false;
    uint now = TimeCtl_Now();
    if (now == 0) return false;
    if (ghostTimeMs > now) ghostTimeMs = now;
    Dev::Write(rec + O_Rec_StartTime, uint(now - ghostTimeMs));
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
// simply stops writing; the ghost continues from wherever it is at normal speed.
void TimeCtl_Update(float dt) {
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
