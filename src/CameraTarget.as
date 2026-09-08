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

// Follow-spectate sub-camera: the spectator path writes cam id 0x12 into camsys+0x180 every frame before
// CameraSystem_UpdateFrame reads it; the resolver hook runs in between, so writing our own id here wins.
const uint64 O_CamSys_CamId = 0x180;
uint g_camForcedCamId = 0;        // 0 = leave the engine's choice

#if TURBO
// Turbo has neither CGamePlaygroundUIConfig.SpectatorForcedTarget nor a CGameCameraSystem on the script
// surface, so there is nothing to hook and nothing to force through the UI config. What it does have is the
// terminal's camera set - CGameTerminal.CameraSet.CamsMaster - whose managed cameras each expose a writable
// FollowedGameMobilId, in the same id space the race hands out to ghost instances (0x0fe0xxxx). So the
// Turbo camera is a plain script write, re-applied each frame because the engine re-evaluates the target.
CGameControlCameraMaster@ TurboCamsMaster() {
    auto pg = App().CurrentPlayground;
    if (pg is null || pg.GameTerminals.Length == 0) return null;
    auto term = pg.GameTerminals[0];
    if (term is null || term.CameraSet is null) return null;
    return term.CameraSet.CamsMaster;
}

// A race ghost's instance id is NOT a GameMobilId, which is what cost 0.6.0 its Turbo spectating: the
// earlier attempt wrote the instance id straight into FollowedGameMobilId, every camera read it back
// happily, and the view never moved. The scene keeps both numbers on the ghost's own mobil - ReplicaId is
// the race instance id, GameMobilId is the dense id the cameras follow (0 = the local player's car) - so the
// translation is a walk of CGameCtnPlayground.GameScene.GameMobils. Verified 2026-09-08.
uint TurboGhostMobilId(uint instId) {
    if (instId == 0 || instId == CamId_None) return 0;
    auto cp = cast<CGameCtnPlayground>(App().CurrentPlayground);
    if (cp is null || cp.GameScene is null) return 0;
    auto scene = cp.GameScene;
    for (uint i = 0; i < scene.GameMobils.Length; i++) {
        auto m = scene.GameMobils[i];
        if (m !is null && m.ReplicaId == instId) return m.GameMobilId;
    }
    return 0;
}

// Which camera a managed slot is, by type rather than by position: the order of ManagedCams is not
// documented, and EGameCam is a *kind* of camera, not an index into that array. Reflection answers it
// directly, so the setting can name a camera the player recognises and still find it whatever the order.
string TurboCamKind(CGameControlCamera@ cam) {
    if (cam is null) return "";
    auto t = Reflection::TypeOf(cam);
    if (t is null) return "";
    string n = t.Name;
    if (!n.StartsWith("CGameControlCamera")) return n;
    // The plain base class is a real entry in ManagedCams; stripping the prefix would leave it nameless.
    n = n.SubStr(18);
    return n.Length == 0 ? "Camera" : n;
}

// Aim the managed cameras at `instId`, or back at the local vehicle when it is CamId_None. The engine
// re-evaluates the target, so this is re-applied every frame from CamTarget_Update.
bool CamTarget_ApplyTurbo(uint instId) {
    auto master = TurboCamsMaster();
    if (master is null) { g_camLastErr = "no camera set on the terminal"; return false; }
    uint id = 0;
    if (instId != CamId_None) {
        id = TurboGhostMobilId(instId);
        if (id == 0) {
            // The ghost is in the race but the scene has not built its mobil (or it has been torn down at
            // the end of its replay). Say so rather than silently aiming at the local car.
            g_camLastErr = "that ghost has no vehicle in the scene to follow";
            return false;
        }
    }
    g_camLastErr = "";
    for (uint i = 0; i < master.ManagedCams.Length; i++) {
        auto cam = master.ManagedCams[i];
        if (cam is null || cam.FollowedGameMobilId == id) continue;
        cam.FollowedGameMobilId = id;
        g_camHookWrites++;
    }
    return true;
}

// Switch the active camera by kind (see TurboCamKind). Empty name = leave the engine's choice alone.
bool CamTarget_SetTurboCamKind(const string &in kind) {
    if (kind.Length == 0) return true;
    auto master = TurboCamsMaster();
    if (master is null) return false;
    int idx = CamTarget_TurboCamIndex(kind);
    if (idx < 0) return false;
    if (master.CurrentCam != uint(idx)) master.CurrentCam = uint(idx);
    return true;
}

// The camera kinds this playground actually offers, in ManagedCams order, for the settings UI and for the
// state export - guessing from the EGameCam enum would list cameras that are not there.
// Measured 2026-09-08 on campaign 003: TrackManiaRace3, TrackManiaRace3, VehicleInternal, VehicleInternal,
// TrackManiaRace, Camera, Free - so the kind alone does not identify a slot. Repeats get a "#2", "#3" suffix
// so a saved setting always names exactly one camera, and the first of a kind keeps the plain readable name.
array<string> CamTarget_TurboCamKinds() {
    array<string> kinds;
    auto master = TurboCamsMaster();
    if (master is null) return kinds;
    for (uint i = 0; i < master.ManagedCams.Length; i++) {
        string kind = TurboCamKind(master.ManagedCams[i]);
        if (kind.Length == 0) { kinds.InsertLast(""); continue; }
        uint seen = 0;
        for (uint j = 0; j < kinds.Length; j++) if (kinds[j] == kind || kinds[j].StartsWith(kind + "#")) seen++;
        kinds.InsertLast(seen == 0 ? kind : kind + "#" + (seen + 1));
    }
    return kinds;
}

// The ManagedCams index a (possibly suffixed) kind names, or -1.
int CamTarget_TurboCamIndex(const string &in kind) {
    if (kind.Length == 0) return -1;
    auto kinds = CamTarget_TurboCamKinds();
    for (uint i = 0; i < kinds.Length; i++) if (kinds[i] == kind) return int(i);
    return -1;
}
#endif

void OnCameraResolveTarget(uint64 rcx) {
    if (rcx == 0) return;
    if (g_camForcedCamId != 0) Dev::Write(rcx + O_CamSys_CamId, g_camForcedCamId);
    if (g_camForcedId == CamId_None) return;
    Dev::Write(rcx + O_CamSys_ForcedId, g_camForcedId);
    g_camHookWrites++;
}

bool CamTarget_InstallHook() {
    if (g_camHook !is null) return true;
    if (g_camLastErr.Length > 0) return false;
#if TURBO
    return true;   // nothing to hook: see CamTarget_ApplyTurbo
#else
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
#endif
}

// Whether the camera override can run at all. MP4 needs its resolver hook; Turbo needs only a camera set.
// A plain question, with no side effect: it is asked once per frame by the UI and by State().
bool CamTarget_Ready() {
#if TURBO
    return TurboCamsMaster() !is null;
#else
    return g_camHook !is null;
#endif
}

// Why CamTarget_Ready() said no, for a caller that is about to refuse something. Empty when it said yes.
string CamTarget_WhyNotReady() {
    if (CamTarget_Ready()) return "";
#if TURBO
    return g_camLastErr.Length > 0 ? g_camLastErr : "this playground has no camera set";
#else
    return g_camLastErr.Length > 0 ? g_camLastErr : "the camera target hook is not installed";
#endif
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
    return CamTarget_Ready();
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
// Engine vehicle cam ids (verified 2026-09-08 by forcing camsys+0x180 while Follow-spectating): 0x12 behind far,
// 0x13 behind close, 0x14 internal (0x15 internal facing back; 8 / 9 close-chase variants). The forced Follow
// spectator camera (SpectatorForceCameraType 1 -> cam type 0xe) hard-codes 0x12 in the per-terminal cam compute
// (FUN_140e462a0); the terminal's own Follow honours the player's key choice at CGameTerminal+0x44.
const array<uint> FollowCamIds = {0x12, 0x13, 0x14};

uint Spectate_FollowCamId() {
    uint n = Math::Clamp(S_SpectateFollowCam, 1, FollowCamIds.Length);
    return FollowCamIds[n - 1];
}

void Spectate_CycleFollowCam(bool backwards) {
    uint n = Math::Clamp(S_SpectateFollowCam, 1, FollowCamIds.Length);
    S_SpectateFollowCam = backwards ? (n == 1 ? FollowCamIds.Length : n - 1) : (n % FollowCamIds.Length) + 1;
}

void CamTarget_Update() {
    if (!S_CameraHook) {
        if (g_camHook !is null) CamTarget_RemoveHook();
#if TURBO
        if (g_camForcedId != CamId_None) { CamTarget_ApplyTurbo(CamId_None); g_camForcedId = CamId_None; }
#endif
        return;
    }
    if (!CamTarget_Ready()) CamTarget_InstallHook();
    uint id = CamId_None;
    if (g_camWantId != CamId_None && CamTarget_GhostHasVis(Ghosts_FindByInstId(g_camWantId))) id = g_camWantId;
    g_camForcedId = id;
    // Follow spectate: pick the vehicle cam (the engine would always use 0x12)
    g_camForcedCamId = (g_specActive && S_SpectateCameraType == 1) ? Spectate_FollowCamId() : 0;
#if TURBO
    CamTarget_ApplyTurbo(id);
    // The camera kind has to be re-asserted too: leaving the spectated car re-selects the race camera.
    if (id != CamId_None) CamTarget_SetTurboCamKind(S_TurboSpectateCam);
#endif
}

void CamTarget_Clear() {
    g_camWantId = CamId_None;
    g_camForcedId = CamId_None;
    g_camForcedCamId = 0;
}

bool CamTarget_Active() { return CamTarget_Ready() && g_camForcedId != CamId_None; }

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

// Stop-spectate without respawn: the UI config restore only reaches the engine on a later frame, and until then
// the picker re-assigns the clip (it did so within the same frame in testing). So wait a few frames, drop, then keep
// dropping for a short while if the slot refills; every refill added a reference, so each drop stays balanced.
void Spectate_DropClipLater() {
    for (uint i = 0; i < 3; i++) yield();
    uint dropped = 0;
    uint until = Time::Now + 1500;
    while (Time::Now < until) {
        if (g_specActive) return;
        if (Spectate_DropClip()) dropped++;
        else if (g_clipDropLastErr.Length > 0) { warn("Ghosts2: could not release the spectator clip (" + g_clipDropLastErr + "); the camera may stay on the ghost"); return; }
        if (dropped >= 8) { warn("Ghosts2: spectator clip keeps getting re-picked; use Restart when you stop spectating"); return; }
        yield();
    }
}

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
#if TURBO
    // The engine's auto-target lives on the same managed cameras, so putting them back on the local
    // vehicle is the whole reset. Always safe to run, even when targeting is not resolved: it clears any
    // id we may have written.
    if (!CamTarget_ApplyTurbo(CamId_None)) return false;
    g_camResets++;
    return true;
#else
    uint64 cs = CamSys_Ptr();
    if (cs == 0) return false;
    uint cur = Dev::ReadUInt32(cs + O_CamSys_AutoId);
    if (cur == 0) return false;
    Dev::Write(cs + O_CamSys_AutoId, uint(0));
    g_camResets++;
    return true;
#endif
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
