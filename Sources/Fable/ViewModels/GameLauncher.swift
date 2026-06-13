import Foundation

enum GameLaunchError: LocalizedError {
    case executableMissing(String)
    case runtimeConflict(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            "The game's executable is missing from the bottle (C:\\\(path.replacingOccurrences(of: "/", with: "\\")))."
        case .runtimeConflict(let bottle):
            "Another game in “\(bottle)” is running on a different Wine runtime. Stop it first — one bottle can't run two Wine versions at once."
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

    /// Called when a game starts (pid non-nil) and when it exits (pid
    /// nil). Used by RunningGameMetricsStore to drive its polling.
    var onProcessLifecycle: ((Game.ID, Int32?) -> Void)?

    func isRunning(_ gameID: Game.ID) -> Bool {
        running[gameID] != nil
    }

    /// Which Wine runtime each running game uses — one bottle must stay
    /// on one wineserver at a time.
    private var runningRuntime: [Game.ID: String] = [:]
    private var runningBottle: [Game.ID: Bottle.ID] = [:]

    func launch(
        _ game: Game,
        in bottle: Bottle,
        bottleManager: BottleManager,
        wineManager: WineManager,
        gptkManager: GPTKManager
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
        let baseOverrides = environment["WINEDLLOVERRIDES"] ?? ""

        // Per-game override wins over the bottle's default — lets a D3D9
        // and a D3D11 title share one bottle.
        let effectiveBackend = game.graphicsBackend ?? bottle.graphicsBackend

        // Pick the Wine binary and graphics routing per backend.
        let wine: URL
        let runtimeKey: String
        var releaseWineserver: URL?
        switch effectiveBackend {
        case .gptk:
            wine = try gptkManager.wineBinary()
            runtimeKey = "gptk"
            releaseWineserver = try? gptkManager.wineserverBinary()
            environment.merge(
                GPTKManager.launchEnvironment(baseOverrides: baseOverrides)
            ) { _, new in new }
            environment.merge(bottle.performance.gptkEnvironment()) { _, new in new }
        case .dxmt, .off:
            wine = try wineManager.wineBinary()
            runtimeKey = "wine"
            // Frame-rate cap rides on DXMT's config when the backend is DXMT.
            var dxmtConfig = bottle.dxmtConfig
            dxmtConfig.maxFrameRate = bottle.performance.frameRateCap
            environment.merge(DXMTManager.launchEnvironment(
                enabled: effectiveBackend == .dxmt,
                config: dxmtConfig,
                baseOverrides: baseOverrides,
                logFile: log
            )) { _, new in new }
        }
        environment.merge(bottle.performance.backendAgnosticEnvironment()) { _, new in new }

        // Version-mismatched wineservers can't share a prefix: refuse
        // to mix runtimes within one bottle while games are running.
        let conflicting = runningBottle.contains { gameID, bottleID in
            bottleID == bottle.id && runningRuntime[gameID] != runtimeKey
        }
        if conflicting {
            throw GameLaunchError.runtimeConflict(bottle.name)
        }

        // Per-game environment overrides win over everything.
        environment.merge(game.environment) { _, new in new }
        let process = try ProcessRunner.start(
            wine,
            arguments: [executable.path] + ArgumentTokenizer.tokenize(game.arguments),
            environment: environment,
            currentDirectory: executable.deletingLastPathComponent(),
            redirectingOutputTo: log
        )

        running[game.id] = process
        runningRuntime[game.id] = runtimeKey
        runningBottle[game.id] = bottle.id
        lastLog[game.id] = log
        lastExitCode[game.id] = nil
        onProcessLifecycle?(game.id, process.processIdentifier)

        let gameName = game.name
        let prefixPath = prefix.path
        Task { [weak self] in
            let code = await process.waitForExit()
            // Let an alternate runtime's wineserver release the prefix
            // before the bottle is considered free again.
            if let releaseWineserver {
                _ = try? await ProcessRunner.run(
                    releaseWineserver,
                    arguments: ["-w"],
                    environment: ["WINEPREFIX": prefixPath]
                )
            }
            self?.running[game.id] = nil
            self?.runningRuntime[game.id] = nil
            self?.runningBottle[game.id] = nil
            self?.lastExitCode[game.id] = code
            self?.onProcessLifecycle?(game.id, nil)
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
