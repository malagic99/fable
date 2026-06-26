import Foundation

/// The "rubber mat" — Fable's performance-stability policy in one documented
/// place. The goal isn't peak FPS; it's a *steady* frame rate, by removing the
/// jitter Fable itself can cause and making macOS treat the game as what it is:
/// the one workload that matters.
///
/// Two levers live here (claim the cores; get out of the way). The frame-pacing
/// and thermal levers live with the things they configure — `PerformanceOptions`
/// (Rock Solid preset) and `ThermalMonitor`. See `docs/wine-quirks.md`.
enum Stability {

    /// Games launch at the top interactive QoS so macOS schedules them on the
    /// performance cores ahead of Fable's own background work and other apps.
    /// Fable is a game launcher — the game IS the foreground workload, even
    /// while Fable sits in the background.
    static let gameQoS: QualityOfService = .userInteractive

    /// How often a running game's CPU/mem readout is sampled. 3 s is plenty for
    /// a glanceable indicator and a third less `ps` churn than the old 2 s.
    static let metricsInterval: Duration = .seconds(3)

    /// We only need fresh metrics when the readout is actually on screen — i.e.
    /// when Fable is frontmost. While you're *in* the game (Fable in the
    /// background) we skip the per-interval `ps` shell-out entirely, so Fable
    /// stops forking a process next to the game every few seconds.
    static func shouldSampleMetrics(fableActive: Bool) -> Bool {
        fableActive
    }

    /// Heavy background work (disk-usage tree walks over multi-GB bottles, etc.)
    /// stands down while a game is running, so it never contends for I/O or CPU
    /// mid-session. It runs on next visit once the game exits.
    static func mayRunHeavyBackgroundWork(gameRunning: Bool) -> Bool {
        !gameRunning
    }
}
