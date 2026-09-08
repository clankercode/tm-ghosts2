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

#if TURBO
// Turbo (32-bit) has the same shape at different offsets. Nothing there rewrites a record's StartTime per
// frame, so Ghosts2 holds it from Update() instead of hooking - but it holds it against the engine's own
// clock, recovered from the record, not against rules.Now. Driving it from rules.Now is what made Turbo
// playback stutter through 0.6.0; TimeCtl_WriteClocks carries the measurement and the reasoning.
const uint16 O_Race_ScriptAddEntries = 0x0c4;   // RaceGhost_Add/Remove act here
const uint16 O_Race_ScriptAddEntryCount = 0x0c8;
const uint16 O_Race_AddEntries = 0x3ac;         // live copy, rebuilt at every (re)spawn
const uint16 O_Race_AddEntryCount = 0x3b0;
const uint16 O_Race_ScriptRecords = 0x3b8;
const uint16 O_Race_ScriptRecordCount = 0x3bc;
const uint16 O_Race_EngineRecords = 0x59c;      // wrappers for CTrackManiaRace.RaceGhosts
const uint16 O_Race_EngineRecordCount = 0x5a0;
const uint64 O_Entry_Ghost = 0x4;
const uint64 O_Rec_Ghost = 0x4;
const uint64 O_Rec_StartTime = 0x0c;
const uint64 O_Rec_Started = 0x10;
const uint64 O_Rec_InstId = 0x24;
const uint64 O_Rec_EngineElapsed = 0x14;   // engine-written playback time (see TimeCtl_ReadRecord)
const bool ClockNeedsHook = false;   // the Update path works without one; the hook below is an upgrade, not a requirement

// Turbo's playback tick: TickPlayback(ECX = record, [ESP+4] = nowMs) at 0x009116f0 turns ms into ns and
// calls the record writer at 0x00910c40 (which reads rec+0x04 ghost and rec+0x10 started, so the shape is
// confirmed). Hooking the MOV EDX,1000000 at +0x0d is the one instruction where both values this plugin
// needs are already in registers - ECX is still the record and EAX is still nowMs, on both branches above
// it - and it is five bytes of MOV with no relative operand, so it relocates with no padding.
//
// Why bother, when Update() already holds the clock: writing from Update() means predicting the engine's
// next tick, and Turbo ticks ghosts at about 30 Hz. Measured paused at a steady frame rate, the prediction
// left a rolling hold error of -9..+16 ms - roughly 0.6 m of position wobble - which is the stutter that
// survived 0.7.0. Inside the tick there is nothing to predict: nowMs is the value the engine is about to
// use, so StartTime = nowMs - wanted is exact.
const uint64 TurboTick_RVA = 0x5116fd;
const string TurboTick_Prologue = "BA 40 42 0F 00";   // MOV EDX, 0x000F4240
#else
const uint16 O_Race_AddEntries = 0xdd0;        // live copy, rebuilt from the script list at every (re)spawn
const uint16 O_Race_AddEntryCount = 0xdd8;
const uint16 O_Race_ScriptAddEntries = 0x1d0;  // script-facing list: RaceGhost_Add/Remove act here, applied at the next spawn
const uint16 O_Race_ScriptAddEntryCount = 0x1d8;
const uint16 O_Race_ScriptRecords = 0xde0;
const uint16 O_Race_ScriptRecordCount = 0xde8;
const uint16 O_Race_EngineRecords = 0x1080;
const uint16 O_Race_EngineRecordCount = 0x1088;
const uint64 O_Entry_Ghost = 0x0;
const uint64 O_Rec_Ghost = 0x0;
const uint64 O_Rec_StartTime = 0x10;
const uint64 O_Rec_Started = 0x14;
const uint64 O_Rec_GhostTime = 0x18;           // engine-written elapsed; Turbo computes it on demand instead
const uint64 O_Rec_InstId = 0x28;
const uint64 O_Rec_Vis = 0x48;
const bool ClockNeedsHook = true;
#endif

const uint64 AddEntryStride = 0x18;
const uint64 O_Entry_OffsetMs = 0x10;
const uint64 O_Entry_InstId = 0x14;
#if MANIA32
const uint64 RecordPtrSize = 4;
#else
const uint64 RecordPtrSize = 8;
#endif
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
#if TURBO
    // The engine's own playback clock, recovered from the record rather than read from a second clock that
    // does not agree with it. See TimeCtl_WriteClocks.
    bool synced = false;        // false until the first write gives us a StartTime to recover EngineNow from
    bool seedPending = false;   // the next delta spans a seed write, not one engine tick: do not integrate it
    uint engineNow = 0;         // engine clock as of its last tick
    uint writtenStart = 0;      // the StartTime we last wrote (EngineNow = writtenStart + elapsed)
    double wantedAtWrite = 0;   // what that write asked for, so the hold error is measurable
    double tickEst = 0;         // smoothed engine tick interval, ms
    int holdErr = 0;            // engine elapsed - wantedAtWrite, last tick
    int holdErrMin = 0;
    int holdErrMax = 0;
    uint holdErrFrames = 0;
#endif
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

#if TURBO
// Ticks this hook has actually driven. Until it is non-zero the register mapping is unproven, so Update()
// keeps holding the clocks the old way: a hook whose arguments arrive in unexpected registers then costs
// nothing instead of flinging ghosts across the map on a garbage StartTime.
uint g_turboHookTicks = 0;

void OnTurboTickPlayback(uint64 ecx, uint64 eax) {
    uint nowMs = uint(eax & 0xffffffff);
    if (nowMs == 0) return;
    for (uint i = 0; i < g_clock.Length; i++) {
        auto e = g_clock[i];
        if (e.rec != ecx) continue;
        // Refuse a clock that cannot be the one we have been following. This is the guard that makes a
        // wrong register mapping harmless rather than destructive.
        if (e.lastNowMs != 0) {
            int64 step = int64(nowMs) - int64(e.lastNowMs);
            if (step < 0 || step > 5000) return;
        }
        if (e.lastNowMs != 0 && nowMs > e.lastNowMs && !e.paused) e.wanted += double(nowMs - e.lastNowMs) * e.speed;
        e.lastNowMs = nowMs;
        if (e.wanted < 0) e.wanted = 0;
        uint w = uint(e.wanted);
        if (w > nowMs) w = nowMs;
        Dev::Write(e.rec + O_Rec_StartTime, uint(nowMs - w));
        e.wantedAtWrite = double(w);
        g_timeCtlWrites++;
        g_turboHookTicks++;
        return;
    }
}
#endif

bool TimeCtl_HookInstalled() { return !ClockNeedsHook || g_clockHook !is null; }

bool TimeCtl_InstallHook() {
    if (g_clockHook !is null) return true;
#if TURBO
    // Best effort: the Update() path is a working fallback, so a refused hook is not an error.
    uint64 tptr = Dev::BaseAddress() + TurboTick_RVA;
    string tbytes = "";
    try {
        for (uint i = 0; i < 5; i++) tbytes += (i > 0 ? " " : "") + Text::Format("%02X", Dev::ReadUInt8(tptr + i));
    } catch { g_timeCtlLastErr = "playback tick site unreadable; holding the clock from Update() instead"; return true; }
    if (tbytes != TurboTick_Prologue) {
        g_timeCtlLastErr = "playback tick site mismatch (" + tbytes + "); holding the clock from Update() instead";
        warn("Ghosts2: " + g_timeCtlLastErr);
        return true;
    }
    // EAX carries nowMs here, so it must not be the hook's scratch register; EBX is untouched by this
    // function. Padding 0: the relocated instruction is exactly the five bytes the jump needs.
    @g_clockHook = Dev::Hook(tptr, 0, "OnTurboTickPlayback", Dev::PushRegisters::SSE, Dev::FreeRegister::Rbx);
    if (g_clockHook is null) {
        g_timeCtlLastErr = "Dev::Hook (playback tick) failed; holding the clock from Update() instead";
        warn("Ghosts2: " + g_timeCtlLastErr);
        return true;
    }
    trace("Ghosts2: playback tick hook installed at " + Text::FormatPointer(tptr));
    return true;
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

uint SafeU32(uint64 addr) {
    try { return Dev::SafeReadUInt32(addr); } catch { return 0; }
}

// One pointer as the process stores it (Turbo is 32-bit).
uint64 SafePtr(uint64 addr) {
#if MANIA32
    return uint64(SafeU32(addr));
#else
    return SafeU64(addr);
#endif
}

// Where the engine's clock is measured from, i.e. the value RaceGhost_ComputeElapsed subtracts StartTime from.
uint RaceNow() {
    auto rules = CurrentRules();
    return rules is null ? 0 : rules.Now;
}

// A pointer / a count stored on the race nod, at the process's word size.
uint64 RaceField(CTrackManiaRace@ race, uint16 off) {
#if MANIA32
    return uint64(Dev::GetOffsetUint32(race, off));
#else
    return Dev::GetOffsetUint64(race, off);
#endif
}

uint RaceCount(CTrackManiaRace@ race, uint16 off) { return Dev::GetOffsetUint32(race, off); }

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
    // What the *engine* thinks the ghost's time is, as opposed to what Ghosts2 is asking for. On a record
    // this plugin drives these two disagree by the frame-phase error, and that disagreement is the whole
    // stutter - so it has to be observable, or a measurement can only ever confirm our own intention.
    int engineGhostTime = -1;

    void CopyFrom(GhostSlot@ o) {
        entry = o.entry; rec = o.rec; ghostNod = o.ghostNod; instId = o.instId;
        startTime = o.startTime; started = o.started; offsetMs = o.offsetMs;
        ghostTime = o.ghostTime; engineGhostTime = o.engineGhostTime;
    }
}

bool TimeCtl_ReadRecord(uint64 r, GhostSlot@ slot) {
    if (r == 0) return false;
    slot.rec = r;
    slot.ghostNod = SafePtr(r + O_Rec_Ghost);
    slot.instId = SafeU32(r + O_Rec_InstId);
    slot.startTime = SafeU32(r + O_Rec_StartTime);
    slot.started = SafeU32(r + O_Rec_Started) != 0 && slot.startTime != 0xffffffff;
#if TURBO
    // No engine-written elapsed field on Turbo: the same subtraction the engine does on demand. For a record
    // this plugin drives, answer with the time it is being held at instead - the record's start time is
    // rewritten once per Update to mean exactly that, so subtracting a race clock that has moved on since
    // that write only measures the lag between the write and this read (tens of ms, and it made a held
    // ghost look like it was creeping forward).
    // Turbo DOES keep an engine-written elapsed, at rec+0x14 - the earlier "no such field on Turbo" note
    // was wrong. It is the ghost's real playback time: measured 2026-09-08, a ghost held at wanted=8000
    // read 8033..8074 here across a 6.5 s window while our StartTime writes landed perfectly every frame.
    slot.engineGhostTime = slot.started ? int(SafeU32(r + O_Rec_EngineElapsed)) : -1;
    auto owned = Clock_Find(r);
    if (owned !is null) {
        slot.ghostTime = slot.started ? int(owned.wanted) : -1;
    } else {
        uint now = RaceNow();
        slot.ghostTime = slot.started && now >= slot.startTime ? int(now - slot.startTime) : -1;
    }
#else
    slot.ghostTime = slot.started ? int(uint(SafeU64(r + O_Rec_GhostTime) & 0xffffffff)) : -1;
    slot.engineGhostTime = slot.ghostTime;   // MP4 drives this field from inside the engine's own tick
#endif
    return true;
}

// Script-mode instance: find the add entry and record by GhostInstId.
bool TimeCtl_ResolveScript(CTrackManiaRace@ race, uint instId, GhostSlot@ slot) {
    uint64 entries = RaceField(race, O_Race_AddEntries);
    uint nEntries = RaceCount(race, O_Race_AddEntryCount);
    uint64 recs = RaceField(race, O_Race_ScriptRecords);
    uint nRecs = RaceCount(race, O_Race_ScriptRecordCount);
    if (entries == 0 || recs == 0 || nEntries == 0 || nEntries > MaxGhostRecords || nRecs > MaxGhostRecords) return false;
    slot.entry = 0;
    for (uint i = 0; i < nEntries; i++) {
        uint64 e = entries + AddEntryStride * i;
        if (SafeU32(e + O_Entry_InstId) == instId) {
            slot.entry = e;
            slot.offsetMs = int(SafeU32(e + O_Entry_OffsetMs));
            break;
        }
    }
    if (slot.entry == 0) return false;
    for (uint i = 0; i < nRecs; i++) {
        uint64 r = SafePtr(recs + RecordPtrSize * i);
        if (r != 0 && SafeU32(r + O_Rec_InstId) == instId) return TimeCtl_ReadRecord(r, slot);
    }
    return false;
}

// Engine ghost (classic race): find the record whose +0x0 is this CGameCtnGhost.
bool TimeCtl_ResolveEngine(CTrackManiaRace@ race, uint64 ghostNod, GhostSlot@ slot) {
    if (ghostNod == 0) return false;
    uint64 recs = RaceField(race, O_Race_EngineRecords);
    uint nRecs = RaceCount(race, O_Race_EngineRecordCount);
    if (recs == 0 || nRecs == 0 || nRecs > MaxGhostRecords) return false;
    slot.entry = 0;
    for (uint i = 0; i < nRecs; i++) {
        uint64 r = SafePtr(recs + RecordPtrSize * i);
        if (r != 0 && SafePtr(r + O_Rec_Ghost) == ghostNod) return TimeCtl_ReadRecord(r, slot);
    }
    return false;
}

// Bumped once per TimeCtl_Update, so Update, Render and RenderInterface of the same frame share one answer.
// Never 0: that is the "not resolved yet" value on a fresh PluginGhost.
uint g_resolveFrame = 1;

bool TimeCtl_ResolveUncached(PluginGhost@ pg, GhostSlot@ slot) {
    auto race = CurrentRace();
    if (race is null) return false;
    if (pg.engine) {
        if (!TimeCtl_ResolveEngine(race, pg.ctnPtr, slot)) return false;
        pg.instId = slot.instId;
        return true;
    }
    return pg.instId != 0 && TimeCtl_ResolveScript(race, pg.instId, slot);
}

// Each resolve is O(entries + records) guarded Dev reads - every SafeU32/SafePtr is a try/catch'd read - and
// a frame asks for the same ghost four to six times over: both TimeCtl_UpdateList passes, Lock_Update's walk
// of the members, TimeCtl_Own per member, and a row per open tab. With ten ghosts that was over a thousand
// guarded reads a frame, which is most of what Update() was costing. The answer cannot change inside a frame
// - the engine rebuilds records at a spawn, between frames - so resolve once per ghost per frame.
bool TimeCtl_Resolve(PluginGhost@ pg, GhostSlot@ slot) {
    if (pg is null || slot is null) return false;
    if (pg.resolveFrame == g_resolveFrame) {
        if (!pg.resolveOk || pg.resolveSlot is null) return false;
        slot.CopyFrom(pg.resolveSlot);
        return true;
    }
    bool ok = TimeCtl_ResolveUncached(pg, slot);
    pg.resolveFrame = g_resolveFrame;
    pg.resolveOk = ok;
    if (ok) {
        if (pg.resolveSlot is null) @pg.resolveSlot = GhostSlot();
        pg.resolveSlot.CopyFrom(slot);
    }
    return ok;
}

bool TimeCtl_Available() {
    return S_TimeControl && TimeCtl_HookInstalled() && CurrentRace() !is null;
}

// Current time into the replay (ms) as the engine computed it this frame; -1 when unknown / not started.
int TimeCtl_GhostTime(PluginGhost@ pg) {
    GhostSlot slot;
    if (!TimeCtl_Resolve(pg, slot)) return -1;
    return slot.ghostTime;
}

// The engine's own playback time for this ghost, which is what you actually see on screen. On a record
// Ghosts2 drives, TimeCtl_GhostTime answers with the time we are *asking* for; comparing the two is the
// only way to tell whether the ghost is really being held where we think it is.
int TimeCtl_EngineGhostTime(PluginGhost@ pg) {
    GhostSlot slot;
    if (!TimeCtl_Resolve(pg, slot)) return -1;
    return slot.engineGhostTime;
}

// How far the rendered ghost is from where Ghosts2 is holding it, in ms (-1 = not measurable). A held ghost
// should read 0; anything that moves frame to frame is visible as a vibrating car.
int TimeCtl_HoldError(PluginGhost@ pg) {
    GhostSlot slot;
    if (!TimeCtl_Resolve(pg, slot)) return -1;
    if (slot.ghostTime < 0 || slot.engineGhostTime < 0) return -1;
    return slot.engineGhostTime - slot.ghostTime;
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

#if TURBO
// Turbo's half of the clock hook - without a hook, by borrowing the engine's own clock.
//
// The obvious implementation (StartTime = RaceNow - wanted, once per Update) is wrong, and was the stutter.
// The engine's playback clock is NOT rules.Now: measured 2026-09-08 over 90 samples on campaign 003, with a
// ghost held at wanted = 8000, EngineNow - RaceNow ran -88..-39 ms and the rendered elapsed wandered over
// 8017..8123. A StartTime computed from RaceNow therefore lands somewhere different every frame, and 106 ms
// of playback wander is about a metre of position wobble at racing speed: a vibrating car.
//
// So do not involve a second clock at all. The engine wrote elapsed = EngineNow - StartTime at its last tick,
// and StartTime is a value this plugin put there, so
//     EngineNow = writtenStart + elapsed
// hands its clock back exactly, in its own phase. Everything below is expressed in that clock: `wanted` is
// integrated with the engine's tick delta (so playback speed is exact too), and the write aims one tick
// ahead, because the value written now is consumed by the engine's *next* tick. What is left over is only
// the variation in tick length instead of the whole inter-clock offset.
void TimeCtl_WriteClocks() {
    // The hook drives every owned record once it has driven any of them, and it is exact where this is only
    // a prediction, so stand down rather than fight it for the same field.
    if (g_turboHookTicks > 0) return;
    for (uint i = 0; i < g_clock.Length; i++) {
        auto e = g_clock[i];
        if (e.rec == 0) continue;
        uint el = SafeU32(e.rec + O_Rec_EngineElapsed);
        uint engineNow = e.writtenStart + el;
        int64 delta = e.synced ? int64(engineNow) - int64(e.engineNow) : 0;

        if (!e.synced || delta < 0 || delta > 2000) {
            // Nothing to follow yet, or the record was rebuilt under us (respawn) and the recovered clock is
            // nonsense. Seed from RaceNow for this one frame; it is only ever a seed, never the time base.
            uint raceNow = RaceNow();
            if (raceNow == 0) continue;
            engineNow = raceNow;
            e.tickEst = 0;
            e.synced = true;
            e.seedPending = true;
        } else if (delta == 0) {
            continue;   // the engine has not ticked since our last write: there is nothing new to correct
        } else if (e.seedPending) {
            // This delta spans the seed write rather than one engine tick, so it must not move `wanted` and
            // must not seed the tick estimate. One frame at 60 Hz is close enough until a real tick lands.
            e.seedPending = false;
            e.tickEst = 16.0;
        } else {
            if (!e.paused) e.wanted += double(delta) * e.speed;
            e.tickEst = e.tickEst * 0.75 + double(delta) * 0.25;
            e.holdErr = int(el) - int(e.wantedAtWrite);
            if (e.holdErrFrames == 0) { e.holdErrMin = e.holdErr; e.holdErrMax = e.holdErr; }
            else {
                if (e.holdErr < e.holdErrMin) e.holdErrMin = e.holdErr;
                if (e.holdErr > e.holdErrMax) e.holdErrMax = e.holdErr;
            }
            if (++e.holdErrFrames >= 600) e.holdErrFrames = 0;   // rolling window: a stale spike ages out
        }

        e.engineNow = engineNow;
        e.lastNowMs = engineNow;
        if (e.wanted < 0) e.wanted = 0;
        uint target = engineNow + uint(e.tickEst + 0.5);
        double w = e.wanted;
        if (w > double(target)) w = double(target);
        uint start = target - uint(w);
        Dev::Write(e.rec + O_Rec_StartTime, start);
        e.writtenStart = start;
        e.wantedAtWrite = w;
        g_timeCtlWrites++;
    }
}
#endif

void TimeCtl_Update(float dt) {
    g_timeCtlUpdates++;
    // New frame: everything resolved for the last one is stale. Bumped before any early return, so a frame
    // that skips time control does not leave the previous frame's answers looking current.
    if (++g_resolveFrame == 0) g_resolveFrame = 1;
    if (!S_TimeControl) {
        if (g_clockHook !is null) TimeCtl_RemoveHook();
        return;
    }
    // Try once, on both games. TimeCtl_HookInstalled() answers "can time control run", which on Turbo is
    // true with or without the hook - asking it here meant the Turbo hook was never even attempted.
    if (g_clockHook is null && g_timeCtlLastErr.Length == 0) TimeCtl_InstallHook();
    if (!TimeCtl_HookInstalled()) return;
    if (g_ghosts.Length > 0) TimeCtl_UpdateList(g_ghosts);
    if (g_engineGhosts.Length > 0) TimeCtl_UpdateList(g_engineGhosts);
    Lock_Update();
    if (g_clock.Length > 0) TimeCtl_CollectOrphans();
#if TURBO
    TimeCtl_WriteClocks();
#endif
}
