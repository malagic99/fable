import AppKit

/// Polls the process table so Play/Stop state reflects what's *actually*
/// running — including games launched from inside Steam, and Steam itself as a
/// prerequisite. Complements `GameLauncher`'s own launch tracking.
@MainActor
final class ActivityMonitor: ObservableObject {
    @Published private(set) var commands: [String] = []
    private var task: Task<Void, Never>?

    /// Begins polling. Idempotent.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                // Only scan while Fable is frontmost — the running indicators are
                // only visible then, and this keeps us out of the game's way
                // mid-session (same policy as the metrics poll).
                if Stability.shouldSampleMetrics(fableActive: NSApplication.shared.isActive) {
                    let scanned = await Task.detached(priority: .utility) {
                        ProcessActivity.runningCommands()
                    }.value
                    self?.commands = scanned
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Whether a game is running anywhere (Fable-launched, Steam-launched, or a
    /// lingering process), by scanning for its exe under this bottle.
    func isRunning(_ game: Game, in bottle: Bottle) -> Bool {
        ProcessActivity.isRunning(
            commands: commands,
            prefixToken: bottle.id.uuidString,
            exeBasename: (game.executablePath as NSString).lastPathComponent,
            // Matches the Windows-style command line a Steam-launched copy
            // runs with (no unix bottle path in it).
            windowsPath: ProcessActivity.windowsPath(fromExecutablePath: game.executablePath)
        )
    }

    /// Whether Steam itself is up in this bottle — the prerequisite for
    /// launching Steam games directly.
    func isSteamRunning(in bottle: Bottle) -> Bool {
        ProcessActivity.isRunning(
            commands: commands, prefixToken: bottle.id.uuidString, exeBasename: "steam.exe"
        )
    }
}
