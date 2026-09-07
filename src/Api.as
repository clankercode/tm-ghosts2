// Thin accessors over the ManiaPlanet 4 race API surface used by Ghosts2.
// Every member referenced here was checked against ~/Openplanet4/Openplanet.h.

CGameManiaPlanet@ App() {
    return cast<CGameManiaPlanet>(GetApp());
}

// CTrackManiaRace holds the live ghost list (RaceGhosts) and the PB toggle.
CTrackManiaRace@ CurrentRace() {
    auto app = App();
    if (app is null) return null;
    return cast<CTrackManiaRace>(app.CurrentPlayground);
}

// CTrackManiaRaceRules is the mode-script rules nod: RaceGhost_*, DataFileMgr, ScoreMgr, UIManager.
CTrackManiaRaceRules@ CurrentRules() {
    auto app = App();
    if (app is null) return null;
    return cast<CTrackManiaRaceRules>(app.PlaygroundScript);
}

CGameCtnChallenge@ CurrentMap() {
    auto rules = CurrentRules();
    if (rules !is null && rules.Map !is null) return rules.Map;
    auto app = App();
    if (app is null) return null;
#if TURBO
    return app.Challenge;   // Turbo dropped CGameManiaPlanet.RootMap; the same map is CGameCtnApp.Challenge
#else
    return app.RootMap;
#endif
}

string CurrentMapUid() {
    auto map = CurrentMap();
    if (map is null || map.MapInfo is null) return "";
    return map.MapInfo.MapUid;
}

// UIAll applies to every player's UI config at once; that is what Nadeo's UISequences lib walks.
CGamePlaygroundUIConfig@ UiAll() {
    auto rules = CurrentRules();
    if (rules is null || rules.UIManager is null) return null;
    return rules.UIManager.UIAll;
}

// The MwId used by ScoreMgr.Map_GetRecordGhost. UNVERIFIED in-game: Nadeo's own script
// reads a `declare Ident ... for User` instead, which has no reflected equivalent.
MwId LocalUserId() {
    auto rules = CurrentRules();
    if (rules is null) return MwId();
    string login = GetLocalLogin();
    for (uint i = 0; i < rules.Users.Length; i++) {
        auto u = rules.Users[i];
        if (u !is null && u.Login == login) return u.Id;
    }
    if (rules.Users.Length > 0 && rules.Users[0] !is null) return rules.Users[0].Id;
    return MwId();
}

// Raw address of a nod (temporarily stores the handle in a scratch nod's first slot and reads it back).
// Turbo is 32-bit (MANIA32), so the slot is 4 bytes there and a u64 read would drag in the next field.
uint64 NodPointer(CMwNod@ nod) {
    if (nod is null) return 0;
    auto tmpNod = CMwNod();
#if MANIA32
    uint saved = Dev::GetOffsetUint32(tmpNod, 0);
    Dev::SetOffset(tmpNod, 0, nod);
    uint64 ptr = uint64(Dev::GetOffsetUint32(tmpNod, 0));
    Dev::SetOffset(tmpNod, 0, saved);
#else
    uint64 saved = Dev::GetOffsetUint64(tmpNod, 0);
    Dev::SetOffset(tmpNod, 0, nod);
    uint64 ptr = Dev::GetOffsetUint64(tmpNod, 0);
    Dev::SetOffset(tmpNod, 0, saved);
#endif
    return ptr;
}

// Reverse of NodPointer: a nod handle for a raw address (only for real CMwNod-derived objects).
CMwNod@ NodFromPointer(uint64 ptr) {
    if (!LooksLikeNod(ptr)) return null;
    auto tmpNod = CMwNod();
#if MANIA32
    uint saved = Dev::GetOffsetUint32(tmpNod, 0);
    Dev::SetOffset(tmpNod, 0, uint(ptr));
    CMwNod@ nod = Dev::GetOffsetNod(tmpNod, 0);
    Dev::SetOffset(tmpNod, 0, saved);
#else
    uint64 saved = Dev::GetOffsetUint64(tmpNod, 0);
    Dev::SetOffset(tmpNod, 0, ptr);
    CMwNod@ nod = Dev::GetOffsetNod(tmpNod, 0);
    Dev::SetOffset(tmpNod, 0, saved);
#endif
    return nod;
}

// True while the game's own in-game menu (Escape) is open.
bool InGameMenuOpen() {
    auto app = App();
    if (app is null) return false;
#if TURBO
    // No CGamePlaygroundClientScriptAPI.IsInGameMenuDisplayed on Turbo; the menus script API has the
    // same flag one level up.
    auto mp = app.ManiaPlanetScriptAPI;
    return mp !is null && mp.ActiveContext_InGameMenuDisplayed;
#else
    if (app.Network is null) return false;
    auto pcs = app.Network.PlaygroundClientScriptAPI;
    return pcs !is null && pcs.IsInGameMenuDisplayed;
#endif
}

string TypeName(CMwNod@ nod) {
    if (nod is null) return "null";
    auto ty = Reflection::TypeOf(nod);
    return ty is null ? "?" : ty.Name;
}

string FormatTime(uint ms) {
    if (ms == 0 || ms == uint(-1)) return "--:--.---";
    return Time::Format(uint64(ms));
}

// Identity we can compare between a CGameGhostScript we hold and a CGameCtnGhost in RaceGhosts.
// CGameCtnGhost.Id is 0xffffffff for engine-loaded ghosts, so name+time is the only usable key.
string GhostKey(const string &in nickname, uint raceTime) {
    return Text::StripFormatCodes(nickname) + "|" + raceTime;
}

uint ScriptGhostTime(CGameGhostScript@ g) {
    auto res = GhostResult(g);
    if (res is null) return 0;
    int t = res.Time;
    return t < 0 ? 0 : uint(t);
}

// The legacy solo race (CTrackManiaRace1P - what the classic Campaigns menu and `play_campaign_map` without a
// mode script give you) does expose a CTrackManiaRaceRules nod, but it is not the one driving the race: its
// Players list is empty while the playground has the player, RaceGhost_Add returns MwId 0, and SpawnPlayer has
// nobody to spawn. Measured on A01 and A05, minutes after the race went live. A script-driven race
// (CTrackManiaRaceNew - PlayMap with a mode script, or a campaign whose mode script runs, e.g. CampaignSolo)
// has Players populated and takes ghosts normally.
// This is a hint for the UI only: it never disables a load, because a proxy that is wrong in some state
// would take away a feature that works.
bool Race_CanAddGhosts() {
    auto rules = CurrentRules();
    return rules !is null && rules.Players.Length > 0;
}

// Turbo never has a rules script, so the whole RaceGhost_* surface is missing rather than merely refusing.
bool HasRulesScript() { return CurrentRules() !is null; }

// Suffix for a rejected add: name the usual cause instead of leaving the user with a bare rejection.
string AddRejectedWhy() {
#if TURBO
    if (CurrentRules() is null) return " - " + TurboNoRulesHint + ".";
#endif
    return Race_CanAddGhosts() ? "." : " - " + ClassicRaceHint + ".";
}

const string ClassicRaceHint = "this race is the legacy solo playground (CTrackManiaRace1P), whose rules script has no players - RaceGhost_Add is refused there and only the ghosts picked in the game's own opponent dialog play. Start the map through a mode script (the title pack's Solo/Play flow) to load ghosts into it";

// Script modes only: unspawn + respawn the local player (a RaceGhost_Add'ed ghost only starts on the next spawn).
bool Race_RespawnLocal(uint delayMs = 1500) { return Race_SpawnLocal(delayMs, true); }

// (Re)spawn the local player. `unspawn` first = a clean restart (ghosts restart with the spawn); without it the
// engine treats it as a respawn of the current vehicle, which is enough to end the spectator camera clip.
bool Race_SpawnLocal(uint delayMs, bool unspawn) {
    auto rules = CurrentRules();
    if (rules is null) return false;
    string login = GetLocalLogin();
    for (uint i = 0; i < rules.Players.Length; i++) {
        auto p = rules.Players[i];
        if (p is null || p.User is null || string(p.User.Login) != login) continue;
        if (unspawn) rules.UnspawnPlayer(p);
        rules.SpawnPlayer(p, 0, int(rules.Now) + int(delayMs));
        return true;
    }
    return false;
}

// Vtable sanity check before treating an address as a nod (Reflection on a non-nod crashes the game):
// the vtable must be in the exe image and its first entry the shared CMwNod base slot (image offset 0x141dc0).
bool LooksLikeNod(uint64 ptr) {
#if TURBO
    // The base-slot signature below is the 64-bit MP4 one. Until the 32-bit equivalent is measured, refuse
    // every raw pointer on Turbo rather than hand an unverified address to Reflection (that crashes the game).
    return false;
#else
    if (ptr == 0 || (ptr & 7) != 0) return false;
    uint64 base = Dev::BaseAddress();
    try {
        uint64 vt = Dev::SafeReadUInt64(ptr);
        if (vt < base || vt >= base + 0x2000000 || (vt & 7) != 0) return false;
        return Dev::SafeReadUInt64(vt) == base + 0x141dc0;
    } catch { return false; }
#endif
}

