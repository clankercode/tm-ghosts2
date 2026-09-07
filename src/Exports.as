// Ghosts2 public API (consumers: add `dependencies = ["tm-ghosts2"]` and import these).
// Implementations live in Exports_Impl.as (compiled as part of the plugin module).
namespace Ghosts2 {
    import Json::Value@ ListGhosts() from "Ghosts2";
    import bool LoadReplay(const string &in path) from "Ghosts2";
    import bool LoadPB() from "Ghosts2";
    import bool LoadMedal(uint level) from "Ghosts2";
    import bool LeaderboardFetch(uint offset) from "Ghosts2";
    import Json::Value@ Leaderboard() from "Ghosts2";
    import bool LoadLeaderboard(uint rank) from "Ghosts2";
    import void SetLockAll(bool on) from "Ghosts2";
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
    // Hands the clock back to the game (ghost snaps to the player's race time).
    import bool Resync(uint instId) from "Ghosts2";
    // Opens (visible=true) or closes the scrubber strip for a ghost.
    import bool ShowScrubber(uint instId, bool visible) from "Ghosts2";
}
