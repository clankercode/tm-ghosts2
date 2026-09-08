// Ghosts2 public API (consumers: add `dependencies = ["tm-ghosts2"]` and import these).
// Implementations live in Exports_Impl.as (compiled as part of the plugin module).
namespace Ghosts2 {
    import Json::Value@ ListGhosts() from "Ghosts2";
    import Json::Value@ Browse(const string &in dir) from "Ghosts2";   // replay browser listing; dir "" = current
    import bool LoadReplay(const string &in path) from "Ghosts2";
    import bool LoadPB() from "Ghosts2";
    import bool LoadMedal(uint level) from "Ghosts2";
    import bool LeaderboardFetch(uint offset) from "Ghosts2";
    import Json::Value@ Leaderboard() from "Ghosts2";
    import bool LoadLeaderboard(uint rank) from "Ghosts2";
    import void SetLockAll(bool on) from "Ghosts2";
    import void SetCameraType(uint camType) from "Ghosts2";
    import bool SetTurboSpectateCam(const string &in kind) from "Ghosts2";
    import void SetFollowCam(uint cam) from "Ghosts2";        // 1 behind far, 2 behind close, 3 internal (Follow camera)
    import bool Remove(uint instId) from "Ghosts2";
    import void RemoveAll() from "Ghosts2";
    import bool Spectate(uint instId) from "Ghosts2";
    import void StopSpectating() from "Ghosts2";
    import void StopSpectatingEx(bool respawn) from "Ghosts2";   // respawn=false: release the spectator clip instead
    import bool ResetCamera() from "Ghosts2";   // camera system auto target -> local vehicle (true if it changed)
    import Json::Value@ State() from "Ghosts2";
    import Json::Value@ RaceEntries() from "Ghosts2";   // diagnostic: raw race ghost add lists + what each entry resolves to
    import Json::Value@ NodProbe() from "Ghosts2";      // diagnostic: nod vtable signature (for LooksLikeNod on 32-bit)
    import void ShowWindow(bool visible) from "Ghosts2";
    import void SelectTab(const string &in tab) from "Ghosts2";   // "ghosts" | "playback" | "load" | "state"
    import void MoveWindow(int x, int y) from "Ghosts2";          // one-shot, ImGui coordinates
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
