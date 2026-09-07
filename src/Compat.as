// Game shims. ManiaPlanet 4 and Trackmania Turbo are the same engine family, but Turbo is the classic,
// non-scripted branch of it: `GetApp().PlaygroundScript` is null for the whole life of a solo race, so
// there is no CTrackManiaRaceRules and none of RaceGhost_Add / SpawnPlayer / UIManager / rules.DataMgr.
// Everything that still exists has been moved or renamed. This file is the one place that knows which.
//
// Measured, not assumed: research/turbo/2026-09-08-Turbo-Setup.md, "Turbo has no mode script".

#if TURBO

// Turbo's DataMgr and ScoreMgr hang off the menus' title ManiaApp, which stays alive during a race,
// rather than off the (nonexistent) rules nod.
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

// CGameGhostScript.Result was renamed RaceResult; the nod behind it is the same CTmRaceResultNod.
CTmRaceResultNod@ GhostResult(CGameGhostScript@ g) { return g is null ? null : g.RaceResult; }

// Turbo's CTrackManiaRaceRules has neither RaceGhost_IsVisible nor RaceGhost_GetPosition (zero occurrences
// in the binary). Vanished-ghost detection runs on GetStartTime plus add-list membership instead.
bool RaceGhostVisible(CTrackManiaRaceRules@ rules, MwId id) { return false; }
const bool HasRaceGhostVisible = false;

#else

CGameDataFileManagerScript@ DataMgr() { auto r = CurrentRules(); return r is null ? null : r.DataFileMgr; }
CGameScoreAndLeaderBoardManagerScript@ ScoreMgr() { auto r = CurrentRules(); return r is null ? null : r.ScoreMgr; }
CTmRaceResultNod@ GhostResult(CGameGhostScript@ g) { return g is null ? null : g.Result; }
bool RaceGhostVisible(CTrackManiaRaceRules@ rules, MwId id) { return rules !is null && rules.RaceGhost_IsVisible(id); }
const bool HasRaceGhostVisible = true;

#endif

// One line to explain, in the UI and in the log, why a Turbo build cannot do something.
const string TurboNoRulesHint =
#if TURBO
    "Trackmania Turbo has no mode script: GetApp().PlaygroundScript is null for the whole race, so the "
    "RaceGhost_* script API this needs does not exist on Turbo";
#else
    "";
#endif
