// Camera target override for engine (classic-race) ghosts.
//
// The chase camera's target is an entity id on CGameCameraSystem (app.GameScene.MgrCamera.CamSystems[i]):
//   +0x48 default id (0 = the local vehicle), +0x4c forced id (0x0ff00000 = none), +0x50 current id.
// Every frame the engine clears +0x4c (FUN_140b446e0) and later the camera update resolves it
// (FUN_140b44740 -> Scene_ResolveEntityById -> vehicle-vis list lookup by GhostInstId). Script modes
// refill +0x4c from CGamePlaygroundUIConfig.SpectatorForcedTarget in between; the classic race never
// does, which is why SpectatorForcedTarget alone leaves the camera on the player's car there.
// Fix: hook the resolver and write the wanted id into +0x4c right before it is read.

const uint64 CamResolveTarget_RVA = 0xb44740;
const string CamResolveTarget_Prologue = "48 89 5C 24 08 48 89 6C 24 10";
const uint CamId_None = 0x0ff00000;
const uint64 O_CamSys_ForcedId = 0x4c;

Dev::HookInfo@ g_camHook;
uint g_camWantId = CamId_None;    // what Spectate asked for
uint g_camForcedId = CamId_None;  // what the hook writes this frame (none while the ghost has no live playback)
uint g_camHookWrites = 0;
string g_camLastErr = "";

void OnCameraResolveTarget(uint64 rcx) {
    if (g_camForcedId == CamId_None || rcx == 0) return;
    Dev::Write(rcx + O_CamSys_ForcedId, g_camForcedId);
    g_camHookWrites++;
}

bool CamTarget_InstallHook() {
    if (g_camHook !is null) return true;
    if (g_camLastErr.Length > 0) return false;
    uint64 ptr = Dev::BaseAddress() + CamResolveTarget_RVA;
    string bytes = "";
    try {
        for (uint i = 0; i < 10; i++) bytes += (i > 0 ? " " : "") + Text::Format("%02X", Dev::ReadUInt8(ptr + i));
    } catch { g_camLastErr = "camera hook site unreadable"; return false; }
    if (bytes != CamResolveTarget_Prologue) {
        g_camLastErr = "camera hook site mismatch (" + bytes + ")";
        warn("Ghosts2: " + g_camLastErr);
        return false;
    }
    @g_camHook = Dev::Hook(ptr, 0, "OnCameraResolveTarget", Dev::PushRegisters::SSE);
    if (g_camHook is null) { g_camLastErr = "Dev::Hook (camera) failed"; warn("Ghosts2: " + g_camLastErr); return false; }
    trace("Ghosts2: camera target hook installed at " + Text::FormatPointer(ptr));
    return true;
}

void CamTarget_RemoveHook() {
    g_camWantId = CamId_None;
    g_camForcedId = CamId_None;
    if (g_camHook !is null) {
        Dev::Unhook(g_camHook);
        @g_camHook = null;
    }
}

// Point the chase camera at a ghost instance id (0x0f00xxxx engine ghosts, 0x0fe0xxxx script instances).
bool CamTarget_Set(uint instId) {
    if (!S_CameraHook) return false;
    g_camWantId = instId;
    return g_camHook !is null;
}

// The camera can only follow a ghost whose playback record is started and not past its end (otherwise the
// vehicle-vis entry does not exist and the camera is left with no target: an empty, drifting view).
bool CamTarget_GhostHasVis(PluginGhost@ pg) {
    if (pg is null) return false;
    int t = TimeCtl_GhostTime(pg);
    if (t < 0) return false;
    return pg.raceTime == 0 || uint(t) <= pg.raceTime + 500;
}

// Called from the plugin's own Update(): Dev::Hook resolves the callback in the *calling* module, so the
// hook must be installed from here, not from an export invoked by another plugin (that raised
// "Unable to find a function with the given name in the current module").
void CamTarget_Update() {
    if (!S_CameraHook) { if (g_camHook !is null) CamTarget_RemoveHook(); return; }
    if (g_camHook is null) CamTarget_InstallHook();
    uint id = CamId_None;
    if (g_camWantId != CamId_None && CamTarget_GhostHasVis(Ghosts_FindByInstId(g_camWantId))) id = g_camWantId;
    g_camForcedId = id;
}

void CamTarget_Clear() {
    g_camWantId = CamId_None;
    g_camForcedId = CamId_None;
}

bool CamTarget_Active() { return g_camHook !is null && g_camForcedId != CamId_None; }

// --- camera target reset after spectating ---------------------------------------------------------
//
// Chase / free spectator cameras (SpectatorForceCameraType 1 / 2, or the game's own controls) point the camera
// system's *auto* target id (+0x48) at the ghost. Nothing writes it back when ForceSpectator / the forced target are
// cleared, and a respawn does not touch it either, so the camera keeps following the ghost (the Replay clip camera
// is different: stopping the clip re-targets the local vehicle). 0 = the local vehicle.

const uint64 O_Playground_Terminals = 0xa00;      // CGameCtnPlayground: CGameTerminal* array (+0xa08 count)
const uint64 O_Terminal_CamSys = 0x30;            // CGameTerminal: its CGameCameraSystem
const uint64 O_CamSys_AutoId = 0x48;
uint g_camResets = 0;

uint64 Terminal_Ptr() {
    auto pg = cast<CGameCtnPlayground>(App().CurrentPlayground);
    if (pg is null) return 0;
    uint64 terms = Dev::GetOffsetUint64(pg, uint16(O_Playground_Terminals));
    uint nTerms = Dev::GetOffsetUint32(pg, uint16(O_Playground_Terminals + 8));
    if (terms == 0 || nTerms == 0) return 0;
    uint64 term = Dev::ReadUInt64(terms);
    return LooksLikeNod(term) ? term : 0;
}

uint64 CamSys_Ptr() {
    uint64 term = Terminal_Ptr();
    if (term == 0) return 0;
    uint64 cs = Dev::ReadUInt64(term + O_Terminal_CamSys);
    return LooksLikeNod(cs) ? cs : 0;
}

// --- spectator clip drop (stop spectating without a respawn) ---------------------------------------
//
// While the spectator is forced, Playground_PickTerminalCamClip (0x140d7dc80) assigns the spectator camera clip
// to terminal+0xa8 (ref-counted); the clip player keeps playing it while that slot still holds the clip, and
// the respawn path (Terminal_ClearSpectateWant 0x140d7db30) is what releases the slot. Releasing it ourselves
// (MwNod_ReleaseRef 0x1402818a0 is a plain decrement of nod+0x10) makes Playground_SyncSpectateClips stop the
// clip on the next frame. The clip is also referenced from the terminal's clip list and the clip player, so the
// refcount must stay >= 1 after the drop (terminal+0x100 is a weak reference). Research: 2026-09-07-RaceGhost-Runtime.md.

const uint64 O_Terminal_SpectateClip = 0xa8;
const uint64 O_Nod_RefCount = 0x10;
uint g_clipDrops = 0;
string g_clipDropLastErr = "";

bool Spectate_DropClip() {
    uint64 term = Terminal_Ptr();
    if (term == 0) { g_clipDropLastErr = "no terminal"; return false; }
    uint64 clip = Dev::ReadUInt64(term + O_Terminal_SpectateClip);
    if (clip == 0) { g_clipDropLastErr = ""; return false; }
    if (!LooksLikeNod(clip)) { g_clipDropLastErr = "clip slot is not a nod"; return false; }
    uint rc = Dev::ReadUInt32(clip + O_Nod_RefCount);
    if (rc < 2 || rc > 64) { g_clipDropLastErr = "clip refcount " + rc + " (expected 2..64)"; return false; }
    Dev::Write(clip + O_Nod_RefCount, rc - 1);
    Dev::Write(term + O_Terminal_SpectateClip, uint64(0));
    g_clipDrops++;
    g_clipDropLastErr = "";
    return true;
}

// Put the camera back on the local vehicle if it is still aimed at something else. Returns true when it wrote.
bool CamTarget_ResetToLocal() {
    uint64 cs = CamSys_Ptr();
    if (cs == 0) return false;
    uint cur = Dev::ReadUInt32(cs + O_CamSys_AutoId);
    if (cur == 0) return false;
    Dev::Write(cs + O_CamSys_AutoId, uint(0));
    g_camResets++;
    return true;
}

// Stop-spectate path: reset now, then keep checking through the respawn window (the spawn rebuilds the terminal's
// state and could re-apply the ghost id).
void CamTarget_ResetAfterStop() {
    CamTarget_ResetToLocal();
    uint until = Time::Now + S_SpectateRespawnDelayMs + 2500;
    while (Time::Now < until) {
        sleep(100);
        if (g_specActive) return;  // spectating again: leave it alone
        CamTarget_ResetToLocal();
    }
}
