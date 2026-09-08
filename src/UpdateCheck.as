// Once-a-day "is there a newer Ghosts2?" check against the GitHub releases API.
//
// The whole design is about not spamming GitHub. Unauthenticated api.github.com allows 60 requests an hour
// per IP, shared with every other plugin and tool on the machine, so this makes at most **one** request per
// 24 hours per install, and the daily gate is a persisted wall-clock timestamp rather than anything tied to
// a session: restarting the game, reloading the plugin, or a crash mid-request all leave the gate closed.
// The timestamp is written *before* the request goes out, so a failing or hanging request cannot turn into
// a retry loop either - a bad day simply means no update news until tomorrow, which is the right trade for
// a cosmetic feature.

const string UpdateApiUrl = "https://api.github.com/repos/clankercode/tm-ghosts2/releases/latest";
const string UpdateReleasesUrl = "https://github.com/clankercode/tm-ghosts2/releases/latest";
const int64 UpdateIntervalSec = 24 * 60 * 60;

bool g_updBusy = false;         // a request is in flight (also stops a second one being started)
uint g_updNextPoll = 0;         // Time::Now: when to next look at the clock at all (not when to fetch)
string g_updLastError = "";
bool g_updCheckedThisSession = false;

int64 UpdateLastCheck() {
    int64 v = 0;
    // Stored as a string: Openplanet settings have no int64 type, and seconds-since-epoch does not fit an int.
    if (!Text::TryParseInt64(S_UpdateLastCheck, v)) return 0;
    return v;
}

bool UpdateCheck_Due() {
    int64 last = UpdateLastCheck();
    int64 now = Time::Stamp;
    // A clock that has moved backwards (timezone change, a bad RTC) would otherwise lock the check out for
    // as long as the skew lasts, so treat a future timestamp as "never checked".
    if (last > now) return true;
    return now - last >= UpdateIntervalSec;
}

// True when the fetched version is strictly newer than the running one.
bool UpdateAvailable() {
    return S_UpdateLatestVersion.Length > 0
        && VersionIsNewer(S_UpdateLatestVersion, PluginVersion);
}

// Numeric, component-wise. Anything that is not a digit ends a component, so "0.5.0", "v0.5.0" and
// "0.5.0-rc1" all read as 0.5.0 - deliberately conservative: a version this cannot parse compares equal
// rather than "newer", so a malformed tag never nags.
array<int> VersionParts(const string &in v) {
    array<int> parts;
    int cur = 0;
    bool inNumber = false;
    for (int i = 0; i < int(v.Length); i++) {
        uint8 c = v[i];
        if (c >= 0x30 && c <= 0x39) {
            cur = cur * 10 + int(c) - 0x30;
            inNumber = true;
        } else if (inNumber) {
            parts.InsertLast(cur);
            cur = 0;
            inNumber = false;
            if (c != 0x2e) break;   // '.' continues the version, anything else ends it ("0.5.0-rc1")
        } else if (c != 0x76 && c != 0x56 && c != 0x2e) {
            break;                  // leading 'v'/'V'/'.' are skipped, any other prefix is not a version
        }
    }
    if (inNumber) parts.InsertLast(cur);
    return parts;
}

bool VersionIsNewer(const string &in candidate, const string &in current) {
    auto a = VersionParts(candidate);
    auto b = VersionParts(current);
    if (a.Length == 0) return false;
    uint n = Math::Max(a.Length, b.Length);
    for (uint i = 0; i < n; i++) {
        int av = i < a.Length ? a[i] : 0;
        int bv = i < b.Length ? b[i] : 0;
        if (av != bv) return av > bv;
    }
    return false;
}

// Called from Update(): an integer compare most frames, a clock read once a minute, a request once a day.
void UpdateCheck_Update() {
    if (!S_CheckForUpdates || g_updBusy) return;
    uint now = Time::Now;
    if (now < g_updNextPoll) return;
    g_updNextPoll = now + 60000;
    if (!UpdateCheck_Due()) return;
    startnew(UpdateCheck_Coro);
}

// The State tab's button. A person asking explicitly is not spam, but it still goes through the same
// single-request-at-a-time guard and still records the attempt, so it cannot be leaned on.
void UpdateCheck_Force() {
    if (g_updBusy) return;
    startnew(UpdateCheck_Coro);
}

void UpdateCheck_Coro() {
    if (g_updBusy) return;
    g_updBusy = true;
    // Record the attempt before the request leaves, not after it succeeds: a timeout, an error, or the game
    // being closed mid-flight must all still consume today's check.
    S_UpdateLastCheck = "" + Time::Stamp;
    UpdateCheckInner();
    g_updCheckedThisSession = true;
    g_updBusy = false;
}

void UpdateCheckInner() {
    g_updLastError = "";
    auto req = Net::HttpGet(UpdateApiUrl);
    if (req is null) { g_updLastError = "HttpGet returned null"; return; }
    uint deadline = Time::Now + 20000;
    while (!req.Finished() && Time::Now < deadline) yield();
    if (!req.Finished()) {
        req.Cancel();
        g_updLastError = "timed out";
        trace("Ghosts2: update check timed out");
        return;
    }
    int code = req.ResponseCode();
    if (code != 200) {
        // 403 here is almost always the shared unauthenticated rate limit, which is exactly what the daily
        // gate exists to stay clear of - so say which it is rather than just "failed".
        g_updLastError = "HTTP " + code + (code == 403 ? " (GitHub rate limit)" : "") + " " + req.Error();
        trace("Ghosts2: update check failed: " + g_updLastError);
        return;
    }
    auto js = req.Json();
    if (js is null || js.GetType() != Json::Type::Object || !js.HasKey("tag_name")) {
        g_updLastError = "unexpected response";
        trace("Ghosts2: update check got an unexpected response");
        return;
    }
    string tag = js["tag_name"];
    S_UpdateLatestVersion = tag;
    S_UpdateLatestUrl = js.HasKey("html_url") ? string(js["html_url"]) : UpdateReleasesUrl;
    string mine = PluginVersion;
    if (!UpdateAvailable()) {
        trace("Ghosts2: up to date (running " + mine + ", latest " + tag + ")");
        return;
    }
    trace("Ghosts2: update available: " + tag + " (running " + mine + ")");
    // One toast per version discovered, not one per check: an update the user has already been told about
    // and chosen not to install must not nag them again tomorrow. The window line below stays either way.
    if (S_UpdateNotifiedVersion != tag) {
        S_UpdateNotifiedVersion = tag;
        UI::ShowNotification(PluginName, "Ghosts2 " + tag + " is out (you have " + mine + ").", 10000);
    }
}

// One line under the tab bar while a newer release exists. Deliberately not a popup: it is information,
// not an interruption.
void DrawUpdateBanner() {
    if (!UpdateAvailable()) return;
    UI::AlignTextToFramePadding();
    UI::Text("\\$fd4" + Icons::Download + " " + PluginName + " " + S_UpdateLatestVersion + " is available"
             + " \\$888(you have " + PluginVersion + ")");
    UI::SameLine();
    if (UI::Button("Open releases page##g2-upd")) OpenBrowserURL(S_UpdateLatestUrl);
    UI::SameLine();
    if (UI::Button("Copy link##g2-upd")) IO::SetClipboard(S_UpdateLatestUrl);
    AddSimpleTooltip(S_UpdateLatestUrl);
    UI::Separator();
}

void DrawUpdateStatus() {
    if (!S_CheckForUpdates) { UI::Text("Update check: \\$888off"); return; }
    int64 last = UpdateLastCheck();
    string when = last <= 0 ? "never" : Time::FormatString("%Y-%m-%d %H:%M", last);
    string latest = S_UpdateLatestVersion.Length > 0 ? S_UpdateLatestVersion : "unknown";
    UI::Text("Update check: \\$888last " + when + ", latest seen " + latest
             + (g_updBusy ? ", \\$fc4checking ..." : "")
             + (g_updLastError.Length > 0 ? ", \\$fc4last error: " + g_updLastError : ""));
    UI::BeginDisabled(g_updBusy);
    if (UI::Button("Check for updates now")) UpdateCheck_Force();
    UI::EndDisabled();
    AddSimpleTooltip("Asks GitHub once. The automatic check runs at most once every 24 hours.");
}
