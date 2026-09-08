// Game shims. ManiaPlanet 4 and Trackmania Turbo are the same engine family, and - measured 2026-09-08 -
// Turbo really does run a mode script: launched through its campaign flow the playground is a
// CTrackManiaRaceNew with a live CTrackManiaRaceRules (mode TMC_CampaignSolo), carrying the whole
// RaceGhost_Add/Remove/GetStartTime surface, SpawnPlayer, UIManager, DataMgr and ScoreMgr.
//
// (An earlier note here claimed Turbo had no mode script at all. That reading came from the legacy
// CTrackManiaRace1P you get from PlayMap with an empty mode - which on MP4 is just as ruleless. The
// campaign flow is the real one; `research/turbo/2026-09-08-Turbo-Setup.md` records the measurement.)
//
// What genuinely differs is smaller, and all of it lives in this file:
//   * CGameDataFileManagerScript -> CGameDataManagerScript, and CGameGhostScript.Result -> .RaceResult
//   * no RaceGhost_IsVisible / RaceGhost_GetPosition (zero occurrences in TrackmaniaTurbo.exe)
//   * no CTmRaceRulesPlayer.IdleDuration (but Position is there, which is what idle really means)
//   * CGamePlaygroundUIConfig has no SpectatorForcedTarget / SpectatorForceCameraType, so spectating
//     goes through the camera set instead (see CameraTarget.as)

#if TURBO

// Turbo keeps DataMgr and ScoreMgr on the menus' title ManiaApp as well as on the rules nod. The rules
// copy is the one that matters in a race (it is the one holding the map's medal ghosts); the ManiaApp
// copy keeps the Load tab usable from the menus.
CGameManiaAppTitle@ TitleManiaApp() {
    auto app = App();
    auto mm = app is null ? null : app.MenuManager;
    return mm is null ? null : mm.MenuCustom_CurrentManiaApp;
}

CGameDataManagerScript@ DataMgr() {
    auto rules = CurrentRules();
    if (rules !is null && rules.DataMgr !is null) return rules.DataMgr;
    auto ta = TitleManiaApp();
    return ta is null ? null : ta.DataMgr;
}

CGameScoreAndLeaderBoardManagerScript@ ScoreMgr() {
    auto rules = CurrentRules();
    if (rules !is null && rules.ScoreMgr !is null) return rules.ScoreMgr;
    auto ta = TitleManiaApp();
    return ta is null ? null : ta.ScoreMgr;
}

CTmRaceResultNod@ GhostResult(CGameGhostScript@ g) { return g is null ? null : g.RaceResult; }

// Vanished-ghost detection runs on GetStartTime plus add-list membership instead.
bool RaceGhostVisible(CTrackManiaRaceRules@ rules, MwId id) { return false; }
const bool HasRaceGhostVisible = false;

// Turbo's UIConfig has no spectator fields at all, so Spectate.as drives the camera set directly.
const bool HasSpectatorForcedTarget = false;

const string ReplaysFolderHint =
    "Turbo has no Replays folder: this is <profile>/MapsGhosts, whose files are index stubs rather than "
    "ghost data. Use Map records, the medal buttons or Load my PB to get a ghost.";

// Turbo has no replay-file writer. The only way to keep a ghost is DataMgr.StoreRecordName, which writes it
// into this map's record table as yours - so it asks first.
const bool SaveNeedsConfirm = true;
string SaveHint(const string &in name) {
    return "Store this ghost in the map's record table as \"" + name + "\" (DataMgr.StoreRecordName). "
           "Turbo cannot write replay files.";
}
string SaveConfirmText(const string &in ghostName) {
    return "Store " + ghostName + " in this map's record table as your record?\n\n"
           "Turbo has no replay files, so this is the only way to keep a ghost - but it writes into the "
           "game's own records for this map, and there is no undo.";
}

#else

CGameDataFileManagerScript@ DataMgr() { auto r = CurrentRules(); return r is null ? null : r.DataFileMgr; }
CGameScoreAndLeaderBoardManagerScript@ ScoreMgr() { auto r = CurrentRules(); return r is null ? null : r.ScoreMgr; }
CTmRaceResultNod@ GhostResult(CGameGhostScript@ g) { return g is null ? null : g.Result; }
bool RaceGhostVisible(CTrackManiaRaceRules@ rules, MwId id) { return rules !is null && rules.RaceGhost_IsVisible(id); }
const bool HasRaceGhostVisible = true;
const bool HasSpectatorForcedTarget = true;

const string ReplaysFolderHint = "Jump to the game's Replays folder.";

const bool SaveNeedsConfirm = false;
string SaveHint(const string &in name) { return "Save as " + name + " (DataFileMgr.Replay_Save)"; }
string SaveConfirmText(const string &in ghostName) { return ""; }

#endif

// The ghosts the game has already loaded for this map. On both games this is where medal ghosts and the
// player's own records live once a race is up; on Turbo it is the *only* offline source of a ghost.
array<CGameGhostScript@> DataMgrGhosts() {
    array<CGameGhostScript@> ghosts;
    auto dm = DataMgr();
    if (dm is null) return ghosts;
    for (uint i = 0; i < dm.Ghosts.Length; i++) {
        if (dm.Ghosts[i] !is null) ghosts.InsertLast(dm.Ghosts[i]);
    }
    return ghosts;
}

// How long the local player has been sitting still, in ms. MP4 publishes this on the player nod; Turbo
// does not, so measure the thing the number is actually about - the car stopped moving.
#if TURBO
vec3 g_idlePos;
uint g_idleSince = 0;
bool g_idleSeen = false;

uint PlayerIdleDuration(CTmRaceRulesPlayer@ p) {
    if (p is null) return 0;
    vec3 pos = p.Position;
    uint now = Time::Now;
    if (!g_idleSeen || (pos - g_idlePos).LengthSquared() > 0.04) {   // 20 cm
        g_idlePos = pos;
        g_idleSince = now;
        g_idleSeen = true;
        return 0;
    }
    return now - g_idleSince;
}
#else
uint PlayerIdleDuration(CTmRaceRulesPlayer@ p) { return p is null ? 0 : p.IdleDuration; }
#endif

// One line to explain, in the UI and in the log, why the race we are in cannot take ghosts. Both games
// have the same failure: a playground with no mode driving it (Turbo's PlayMap with an empty mode, MP4's
// classic Campaigns menu) gives a CTrackManiaRace1P whose rules nod has no players to spawn.
const string NoModeHint =
    "this is the legacy solo race, which has no mode script driving it: its rules nod has an empty Players "
    "list, so RaceGhost_Add has nobody to attach a ghost to";
