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
    return app.RootMap;
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
    if (g is null || g.Result is null) return 0;
    int t = g.Result.Time;
    return t < 0 ? 0 : uint(t);
}
