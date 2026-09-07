// Group lock: the scrubber (and the playback rows) drive every ghost with live playback at once and keep
// them in sync. The leader is the scrubber's ghost (else the first member); every frame the other members'
// clocks mirror the leader's wanted time / pause / speed, so ghosts that start later join at the group time.

bool Lock_Enabled() { return S_ScrubLockAll; }

bool Lock_IsMember(PluginGhost@ pg) { return pg !is null && TimeCtl_GhostTime(pg) >= 0; }

array<PluginGhost@>@ Lock_Members() {
    array<PluginGhost@> members;
    for (uint i = 0; i < g_ghosts.Length; i++) if (Lock_IsMember(g_ghosts[i])) members.InsertLast(g_ghosts[i]);
    for (uint i = 0; i < g_engineGhosts.Length; i++) if (Lock_IsMember(g_engineGhosts[i])) members.InsertLast(g_engineGhosts[i]);
    return members;
}

PluginGhost@ Lock_Leader() {
    if (g_scrubGhost !is null && Lock_IsMember(g_scrubGhost)) return g_scrubGhost;
    auto m = Lock_Members();
    return m.Length > 0 ? m[0] : null;
}

// Turn the lock on (snapping every member to the leader's time / state) or off (members keep their clocks).
void Lock_Set(bool on) {
    S_ScrubLockAll = on;
    if (!on) return;
    auto leader = Lock_Leader();
    if (leader is null) return;
    int t = TimeCtl_GhostTime(leader);
    if (t < 0) return;
    TimeCtl_Own(leader);
    auto members = Lock_Members();
    for (uint i = 0; i < members.Length; i++) {
        auto m = members[i];
        if (m is leader) continue;
        TimeCtl_Seek(m, uint(t));
        TimeCtl_SetPaused(m, leader.paused);
        TimeCtl_SetSpeed(m, leader.speed);
    }
}

// Per frame (from TimeCtl_Update): mirror the leader while it is under our control.
void Lock_Update() {
    if (!Lock_Enabled() || !TimeCtl_Available()) return;
    auto leader = Lock_Leader();
    if (leader is null) return;
    ClockEntry@ le = leader.Controlled() ? Clock_Find(leader.clockRec) : null;
    auto members = Lock_Members();
    for (uint i = 0; i < members.Length; i++) {
        auto m = members[i];
        if (m is leader) continue;
        if (le is null) {
            // leader handed back to the game: the group follows the engine too
            if (m.Controlled()) TimeCtl_Release(m);
            continue;
        }
        auto e = TimeCtl_Own(m);
        if (e is null) continue;
        if (Math::Abs(float(e.wanted - le.wanted)) > 1.0f) e.wanted = le.wanted;
        e.paused = le.paused;
        e.speed = le.speed;
        m.paused = leader.paused;
        m.speed = leader.speed;
        m.heldTime = float(e.wanted);
    }
}

// --- control wrappers used by the scrubber and the playback rows -------------

void Ctl_SetPaused(PluginGhost@ pg, bool paused) {
    if (!Lock_Enabled()) { TimeCtl_SetPaused(pg, paused); return; }
    auto members = Lock_Members();
    for (uint i = 0; i < members.Length; i++) TimeCtl_SetPaused(members[i], paused);
    if (!Lock_IsMember(pg)) TimeCtl_SetPaused(pg, paused);
}

void Ctl_Seek(PluginGhost@ pg, uint ms) {
    if (!Lock_Enabled()) { TimeCtl_Seek(pg, ms); return; }
    auto members = Lock_Members();
    for (uint i = 0; i < members.Length; i++) TimeCtl_Seek(members[i], ms);
    if (!Lock_IsMember(pg)) TimeCtl_Seek(pg, ms);
}

void Ctl_SetSpeed(PluginGhost@ pg, float speed) {
    if (!Lock_Enabled()) { TimeCtl_SetSpeed(pg, speed); return; }
    auto members = Lock_Members();
    for (uint i = 0; i < members.Length; i++) TimeCtl_SetSpeed(members[i], speed);
    if (!Lock_IsMember(pg)) TimeCtl_SetSpeed(pg, speed);
}

void Ctl_Release(PluginGhost@ pg) {
    if (!Lock_Enabled()) { TimeCtl_Release(pg); return; }
    auto members = Lock_Members();
    for (uint i = 0; i < members.Length; i++) TimeCtl_Release(members[i]);
    TimeCtl_Release(pg);
}
