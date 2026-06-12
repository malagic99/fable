import Foundation

enum GameLaunchError: LocalizedError {
    case executableMissing(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            "The game's executable is missing from the bottle (C:\\\(path.replacingOccurrences(of: "/", with: "\\")))."
        }
    }
}

/// Launches and stops games. App-wide so games keep running while you
/// navigate around.
@MainActor
final class GameLauncher: ObservableObject {
    @Published private(set) var running: [Game.ID: LaunchedProcess] = [:]
    /// Exit code of each game's most recent run.
    @Published private(set) var lastExitCode: [Game.ID: Int32] = [:]
    /// Wine log of each game's most recent run (debugging fallback).
    @Published private(set) var lastLog: [Game.ID: URL] = [:]

    /// Hook for surfacing crashes after the user has navigated away
    /// (wired to ToastCenter at app startup).
    var onAbnormalExit: ((String) -> Void)?

    func isRunning(_ gameID: Game.ID) -> Bool {
        running[gameID] != nil
    }

    func launch(
        _ game: Game,
        in bottle: Bottle,
        bottleManager: BottleManager,
        wineManager: WineManager
    ) throws {
        guard running[game.id] == nil else { return }

        let prefix = bottleManager.prefixDirectory(for: bottle)
        let executable = bottleManager.driveCDirectory(for: bottle)
            .appending(path: game.executablePath)
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw GameLaunchError.executableMissing(game.executablePath)
        }

        var environment = wineManager.environment(forPrefix: prefix)
        // Keep real errors in the log without drowning it in fixmes.
        environment["WINEDEBUG"] = "fixme-all"

        let log = AppPaths.logs.appending(path: GameInstaller.logName(bottle.name, game.name))

        // DXMT: route d3d11/dxgi to Metal when the bottle has it enabled,
        // and explicitly back to Wine's builtins when it doesn't.
        environment.merge(DXMTManager.launchEnvironment(
            enabled: bottle.dxmtEnabled,
            config: bottle.dxmtConfig,
            baseOverrides: environment["WINEDLLOVERRIDES"] ?? "",
            logFile: log
        )) { _, new in new }

        // Per-game environment overrides win over everything.
        environment.merge(game.environment) { _, new in new }
        let process = try ProcessRunner.start(
            try wineManager.wineBinary(),
            arguments: [executable.path] + ArgumentTokenizer.tokenize(game.arguments),
            environment: environment,
            currentDirectory: executable.deletingLastPathComponent(),
            redirectingOutputTo: log
        )

        running[game.id] = process
        lastLog[game.id] = log
        lastExitCode[game.id] = nil

        let gameName = game.name
        Task { [weak self] in
            let code = await process.waitForExit()
            self?.running[game.id] = nil
            self?.lastExitCode[game.id] = code
            // SIGTERM (user pressed Stop) isn't a crash worth announcing.
            if code != 0 && code != 15 {
                self?.onAbnormalExit?("“\(gameName)” exited with code \(code) — check its log")
            }
        }
    }

    func stop(_ gameID: Game.ID) {
        running[gameID]?.terminate()
    }
}
