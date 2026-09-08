// tm-ghosts2-mp4pack: exposes Ghosts2's exported API as a tm-mp4-control command pack.
// Socket usage: tm-mp4-control/tools/mp4call.py ghosts2.list (also: state, load_replay,
// load_pb, load_medal, remove, remove_all, spectate, stop_spectating, show_window,
// ghost_time, seek ms=, pause paused=, speed speed=).

// Imports come from the dependencies' `exports` files (Mp4Control/Exports.as, Ghosts2/Exports.as);
// Openplanet compiles those into this module, so re-declaring them here is a duplicate-function error.

namespace Ghosts2Mp4Pack {
    Json::Value@ Ok(Json::Value@ data) {
        auto o = Json::Object();
        o["ok"] = true;
        o["data"] = data;
        return o;
    }

    Json::Value@ OkTrue() {
        auto o = Json::Object();
        o["ok"] = true;
        return o;
    }

    Json::Value@ Err(const string &in msg) {
        auto o = Json::Object();
        o["ok"] = false;
        o["error"] = msg;
        return o;
    }

    // PackDispatch callback: `cmd` is the part after "ghosts2.".
    Json::Value@ Dispatch(const string &in cmd, Json::Value@ args) {
        if (cmd == "list") return Ok(Ghosts2::ListGhosts());
        if (cmd == "state") return Ok(Ghosts2::State());
        if (cmd == "race_entries") return Ok(Ghosts2::RaceEntries());
        if (cmd == "nod_probe") return Ok(Ghosts2::NodProbe());
        if (cmd == "read_words") return Ok(Ghosts2::ReadWords(string(args.Get("addr", "0")), uint(args.Get("count", 64))));
        if (cmd == "browse") return Ok(Ghosts2::Browse(string(args.Get("dir", ""))));
        if (cmd == "load_replay") {
            string path = string(args.Get("path", ""));
            if (path.Length == 0) return Err("load_replay needs path");
            return Ghosts2::LoadReplay(path) ? OkTrue() : Err("load rejected (busy or empty path)");
        }
        if (cmd == "load_pb") {
            return Ghosts2::LoadPB() ? OkTrue() : Err("load rejected (busy)");
        }
        if (cmd == "load_medal") {
            uint level = uint(args.Get("level", 4));
            return Ghosts2::LoadMedal(level) ? OkTrue() : Err("load rejected (busy or level not 1..4)");
        }
        if (cmd == "follow_cam") {
            Ghosts2::SetFollowCam(uint(args.Get("cam", 1)));
            return OkTrue();
        }
        if (cmd == "cam") {
            Ghosts2::SetCameraType(uint(args.Get("type", 0)));
            return OkTrue();
        }
        if (cmd == "turbo_cam") {
            string kind = string(args.Get("kind", ""));
            return Ghosts2::SetTurboSpectateCam(kind) ? OkTrue() : Err("no camera named '" + kind + "' in this playground (see state.turboCams)");
        }
        if (cmd == "lock") {
            Ghosts2::SetLockAll(bool(args.Get("all", true)));
            return OkTrue();
        }
        if (cmd == "lb_fetch") {
            uint offset = uint(args.Get("offset", 0));
            return Ghosts2::LeaderboardFetch(offset) ? OkTrue() : Err("fetch rejected (busy)");
        }
        if (cmd == "lb_list") return Ok(Ghosts2::Leaderboard());
        if (cmd == "load_lb") {
            uint rank = uint(args.Get("rank", 0));
            if (rank == 0) return Err("load_lb needs rank (from lb_list)");
            return Ghosts2::LoadLeaderboard(rank) ? OkTrue() : Err("load rejected (busy, unknown rank, or no replay url)");
        }
        if (cmd == "remove") {
            uint instId = uint(args.Get("instId", 0));
            if (instId == 0) return Err("remove needs instId");
            return Ghosts2::Remove(instId) ? OkTrue() : Err("unknown instId");
        }
        if (cmd == "remove_all") {
            Ghosts2::RemoveAll();
            return OkTrue();
        }
        if (cmd == "spectate") {
            uint instId = uint(args.Get("instId", 0));
            if (instId == 0) return Err("spectate needs instId");
            return Ghosts2::Spectate(instId) ? OkTrue() : Err("spectate failed (no UI config?)");
        }
        if (cmd == "stop_spectating") {
            if (args.HasKey("respawn")) Ghosts2::StopSpectatingEx(bool(args["respawn"]));
            else Ghosts2::StopSpectating();
            return OkTrue();
        }
        if (cmd == "cam_reset") {
            auto o = Json::Object();
            o["changed"] = Ghosts2::ResetCamera();
            return Ok(o);
        }
        if (cmd == "ghost_time") {
            uint instId = uint(args.Get("instId", 0));
            auto o = Json::Object(); o["ok"] = true; o["data"] = Ghosts2::GetGhostTime(instId);
            return o;
        }
        if (cmd == "seek") {
            uint instId = uint(args.Get("instId", 0));
            return Ghosts2::Seek(instId, uint(args.Get("ms", 0))) ? OkTrue() : Err("seek failed (unknown instId, not started, or not a script-mode race)");
        }
        if (cmd == "pause") {
            uint instId = uint(args.Get("instId", 0));
            return Ghosts2::SetPaused(instId, bool(args.Get("paused", true))) ? OkTrue() : Err("pause failed (unknown instId or not started)");
        }
        if (cmd == "speed") {
            uint instId = uint(args.Get("instId", 0));
            return Ghosts2::SetSpeed(instId, float(double(args.Get("speed", 1.0)))) ? OkTrue() : Err("speed failed (unknown instId, not started, or speed outside 0..16)");
        }
        if (cmd == "scrubber") {
            uint instId = uint(args.Get("instId", 0));
            return Ghosts2::ShowScrubber(instId, bool(args.Get("visible", true))) ? OkTrue() : Err("unknown instId");
        }
        if (cmd == "resync") {
            uint instId = uint(args.Get("instId", 0));
            return Ghosts2::Resync(instId) ? OkTrue() : Err("unknown instId");
        }
        if (cmd == "show_window") {
            Ghosts2::ShowWindow(bool(args.Get("visible", true)));
            if (args.HasKey("tab")) Ghosts2::SelectTab(string(args["tab"]));
            if (args.HasKey("x") && args.HasKey("y")) Ghosts2::MoveWindow(int(args["x"]), int(args["y"]));
            return OkTrue();
        }
        return Err("unknown ghosts2 cmd: " + cmd);
    }
}

void Main() {
    if (!Mp4Control::RegisterPack("ghosts2", Ghosts2Mp4Pack::Dispatch)) {
        warn("tm-ghosts2-mp4pack: RegisterPack('ghosts2') failed");
    }
}

void OnDestroyed() { Mp4Control::UnregisterPack("ghosts2"); }
void OnDisabled() { Mp4Control::UnregisterPack("ghosts2"); }
