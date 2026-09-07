// tm-ghosts2-mp4pack: exposes Ghosts2's exported API as a tm-mp4-control command pack.
// Socket usage: tm-mp4-control/tools/mp4call.py ghosts2.list (also: state, load_replay,
// load_pb, load_medal, remove, remove_all, spectate, stop_spectating, show_window).

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
            Ghosts2::StopSpectating();
            return OkTrue();
        }
        if (cmd == "show_window") {
            Ghosts2::ShowWindow(bool(args.Get("visible", true)));
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
