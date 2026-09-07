// Ghost playback time control — exact, via a hook on the engine's per-record clock update.
//
// Every ghost the engine plays has a 0x98-byte playback record (fields live on CTrackManiaRace, size 0x1278):
//   record: +0x00 CGameCtnGhost*, +0x10 StartTime, +0x14 started, +0x18 elapsed (ghost time, written every
//           frame), +0x28 GhostInstId, +0x40 flags, +0x48 vehicle-vis entry
//   race+0xde0/+0xde8   records of RaceGhost_Add instances (script modes), paired 1:1 with the add-entry array
//                       race+0xdd0/+0xdd8 (stride 0x18; +0x10 OffsetMs, +0x14 GhostInstId)
//   race+0x1080/+0x1088 records of the engine's RaceGhosts (classic campaign race; inst ids 0x0f00xxxx)
// Each frame the race UpdateFrame (0x140ebad00) rewrites record.StartTime from the player's race start and calls
//   RaceGhostRecord_TickPlayback(mgr, rec, nowMs) -> RaceGhostRecord_UpdatePlaybackTime(mgr, rec, nowNs)
//   which does  rec.elapsed = nowMs - rec.StartTime  and applies the ghost sample for that time to the vis.
// Writing StartTime/OffsetMs from Update() means predicting the engine's next integer-ms frame step, which is
// wrong by ±1-2 ms per frame and makes a paused car vibrate. So instead we hook UpdatePlaybackTime (RDX = record,
// R8 = nowNs, exact) and set rec.StartTime = nowMs - wantedMs right there: elapsed and the applied sample are
// exactly `wanted`, every tick, in both race types and whether or not the local player is racing.
// Evidence: research/mp4/2026-09-07-RaceGhost-Runtime.md.

const uint16 O_Race_AddEntries = 0xdd0;        // live copy, rebuilt from the script list at every (re)spawn
const uint16 O_Race_AddEntryCount = 0xdd8;
const uint16 O_Race_ScriptAddEntries = 0x1d0;  // script-facing list: RaceGhost_Add/Remove act here, applied at the next spawn
const uint16 O_Race_ScriptAddEntryCount = 0x1d8;
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
const uint64 O_Rec_Vis = 0x48;
const uint MaxGhostRecords = 256;

// RaceGhostRecord_UpdatePlaybackTime (ManiaPlanet.exe build 2019-11-19_18_50): image offset + prologue bytes.
const uint64 UpdatePlaybackTime_RVA = 0x848f20;
const string UpdatePlaybackTime_Prologue = "48 83 EC 58 8B 42 40";   // SUB RSP,0x58 ; MOV EAX,[RDX+0x40]  (7 bytes)

// diagnostics (State tab / ghosts2.state)
uint g_timeCtlUpdates = 0;
uint g_timeCtlWrites = 0;      // hook writes
string g_timeCtlLastErr = "";
Dev::HookInfo@ g_clockHook;

// --- the clock hook ---------------------------------------------------------

// One entry per record whose clock we own. Written from Update(), consumed inside the hook (same thread).
class ClockEntry {
    uint64 rec = 0;
    double wanted = 0;      // ms into the replay
    float speed = 1.0;
    bool paused = false;
    uint lastNowMs = 0;
}
array<ClockEntry@> g_clock;

ClockEntry@ Clock_Find(uint64 rec) {
    for (uint i = 0; i < g_clock.Length; i++) {
        if (g_clock[i].rec == rec) return g_clock[i];
    }
    return null;
}

// Hook callback: runs at the entry of RaceGhostRecord_UpdatePlaybackTime for every record, every frame.
void OnUpdatePlaybackTime(uint64 rdx, uint64 r8) {
    for (uint i = 0; i < g_clock.Length; i++) {
        auto e = g_clock[i];
        if (e.rec != rdx) continue;
        uint nowMs = uint(r8 / 1000000);
        if (e.lastNowMs != 0 && nowMs > e.lastNowMs && !e.paused) e.wanted += double(nowMs - e.lastNowMs) * e.speed;
        e.lastNowMs = nowMs;
        if (e.wanted < 0) e.wanted = 0;
        uint w = uint(e.wanted);
        if (w > nowMs) w = nowMs;
        Dev::Write(rdx + O_Rec_StartTime, uint(nowMs - w));
        g_timeCtlWrites++;
        return;
    }
}

bool TimeCtl_HookInstalled() { return g_clockHook !is null; }

bool TimeCtl_InstallHook() {
    if (g_clockHook !is null) return true;
#if TURBO
    // The MP4 hook site (RaceGhostRecord_UpdatePlaybackTime, 64-bit) has no Turbo counterpart yet: Turbo is
    // 32-bit, its playback records live on the race's ghost manager rather than on the race, and the engine
    // computes the elapsed time on demand instead of writing it per frame. Ghost time control is off on
    // Turbo until that is mapped (research/turbo/2026-09-08-Turbo-RaceGhost-RE.md).
    g_timeCtlLastErr = "ghost time control is not implemented on Trackmania Turbo yet";
    return false;
#else
    uint64 ptr = Dev::BaseAddress() + UpdatePlaybackTime_RVA;
    string bytes = "";
    try {
        for (uint i = 0; i < 7; i++) bytes += (i > 0 ? " " : "") + Text::Format("%02X", Dev::ReadUInt8(ptr + i));
    } catch { g_timeCtlLastErr = "hook site unreadable"; return false; }
    if (bytes != UpdatePlaybackTime_Prologue) {
        g_timeCtlLastErr = "hook site mismatch (" + bytes + "), time control disabled";
        warn("Ghosts2: " + g_timeCtlLastErr);
        return false;
    }
    @g_clockHook = Dev::Hook(ptr, 2, "OnUpdatePlaybackTime", Dev::PushRegisters::SSE);
    if (g_clockHook is null) { g_timeCtlLastErr = "Dev::Hook failed"; warn("Ghosts2: " + g_timeCtlLastErr); return false; }
    trace("Ghosts2: playback clock hook installed at " + Text::FormatPointer(ptr));
    return true;
#endif
}

void TimeCtl_RemoveHook() {
    if (g_clockHook !is null) {
        Dev::Unhook(g_clockHook);
        @g_clockHook = null;
    }
    g_clock.RemoveRange(0, g_clock.Length);
}

// --- record lookup ----------------------------------------------------------

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
    return S_TimeControl && g_clockHook !is null && CurrentRace() !is null;
}

// Current time into the replay (ms) as the engine computed it this frame; -1 when unknown / not started.
int TimeCtl_GhostTime(PluginGhost@ pg) {
    GhostSlot slot;
    if (!TimeCtl_Resolve(pg, slot)) return -1;
    return slot.ghostTime;
}

// --- control ----------------------------------------------------------------

// Takes ownership of the ghost's clock (idempotent). Returns the entry or null when the record is unknown.
ClockEntry@ TimeCtl_Own(PluginGhost@ pg) {
    if (!TimeCtl_Available() || pg is null) return null;
    GhostSlot slot;
    if (!TimeCtl_Resolve(pg, slot) || !slot.started) return null;
    auto e = Clock_Find(slot.rec);
    if (e is null) {
        @e = ClockEntry();
        e.rec = slot.rec;
        e.wanted = double(slot.ghostTime < 0 ? 0 : slot.ghostTime);
        g_clock.InsertLast(e);
    }
    pg.clockRec = slot.rec;
    e.speed = pg.speed;
    e.paused = pg.paused;
    return e;
}

// Gives the clock back to the engine (the ghost snaps to the player's race time, as the engine intends).
// Drop every owned clock (map change / forget-all): a stale entry would hijack whatever record the engine later
// allocates at the same address.
void TimeCtl_ReleaseAll() {
    g_clock.RemoveRange(0, g_clock.Length);
}

// Garbage-collect entries that no tracked ghost owns any more (ghost dropped without Release).
void TimeCtl_CollectOrphans() {
    for (int i = int(g_clock.Length) - 1; i >= 0; i--) {
        uint64 rec = g_clock[i].rec;
        bool owned = false;
        for (uint j = 0; j < g_ghosts.Length && !owned; j++) owned = g_ghosts[j].clockRec == rec;
        for (uint j = 0; j < g_engineGhosts.Length && !owned; j++) owned = g_engineGhosts[j].clockRec == rec;
        if (!owned) g_clock.RemoveAt(uint(i));
    }
}

void TimeCtl_Release(PluginGhost@ pg) {
    if (pg is null) return;
    pg.paused = false;
    pg.speed = 1.0;
    for (uint i = 0; i < g_clock.Length; i++) {
        if (g_clock[i].rec == pg.clockRec) { g_clock.RemoveAt(i); break; }
    }
    pg.clockRec = 0;
}

bool TimeCtl_Seek(PluginGhost@ pg, uint ghostTimeMs) {
    auto e = TimeCtl_Own(pg);
    if (e is null) return false;
    e.wanted = double(ghostTimeMs);
    pg.heldTime = float(ghostTimeMs);
    return true;
}

bool TimeCtl_SetPaused(PluginGhost@ pg, bool paused) {
    if (pg is null) return false;
    pg.paused = paused;
    return TimeCtl_Own(pg) !is null;
}

bool TimeCtl_SetSpeed(PluginGhost@ pg, float speed) {
    if (pg is null || speed < 0.0 || speed > 16.0) return false;
    pg.speed = speed;
    return TimeCtl_Own(pg) !is null;
}

// Per frame: keep entries in sync with the ghosts (records move when the engine rebuilds them on respawn; an
// owned clock whose record vanished is dropped, i.e. the ghost restarts with the player like the engine wants).
void TimeCtl_UpdateList(array<PluginGhost@>@ list) {
    for (uint i = 0; i < list.Length; i++) {
        auto pg = list[i];
        if (pg.clockRec == 0) continue;
        GhostSlot slot;
        if (!TimeCtl_Resolve(pg, slot) || slot.rec != pg.clockRec) {
            TimeCtl_Release(pg);
            continue;
        }
        auto e = Clock_Find(pg.clockRec);
        if (e is null) { pg.clockRec = 0; continue; }
        e.speed = pg.speed;
        e.paused = pg.paused;
        pg.heldTime = float(e.wanted);
    }
}

void TimeCtl_Update(float dt) {
    g_timeCtlUpdates++;
    if (!S_TimeControl) {
        if (g_clockHook !is null) TimeCtl_RemoveHook();
        return;
    }
    if (g_clockHook is null && g_timeCtlLastErr.Length == 0) TimeCtl_InstallHook();
    if (g_clockHook is null) return;
    if (g_ghosts.Length > 0) TimeCtl_UpdateList(g_ghosts);
    if (g_engineGhosts.Length > 0) TimeCtl_UpdateList(g_engineGhosts);
    Lock_Update();
    if (g_clock.Length > 0) TimeCtl_CollectOrphans();
}
