// Ghosts2 public API (consumers: add `dependencies = ["tm-ghosts2"]` and import these).
// Implementations live in Exports_Impl.as (compiled as part of the plugin module).
namespace Ghosts2 {
    import Json::Value@ ListGhosts() from "Ghosts2";
    import bool LoadReplay(const string &in path) from "Ghosts2";
    import bool LoadPB() from "Ghosts2";
    import bool LoadMedal(uint level) from "Ghosts2";
    import bool Remove(uint instId) from "Ghosts2";
    import void RemoveAll() from "Ghosts2";
    import bool Spectate(uint instId) from "Ghosts2";
    import void StopSpectating() from "Ghosts2";
    import Json::Value@ State() from "Ghosts2";
    import void ShowWindow(bool visible) from "Ghosts2";
    // Time control (script modes only): ghost time in ms, or -1 when not started / unavailable.
    import int GetGhostTime(uint instId) from "Ghosts2";
    import bool Seek(uint instId, uint ghostTimeMs) from "Ghosts2";
    import bool SetPaused(uint instId, bool paused) from "Ghosts2";
    import bool SetSpeed(uint instId, float speed) from "Ghosts2";
}
