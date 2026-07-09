import Foundation

enum GameLaunchError: LocalizedError {
    case executableMissing(String)
    case runtimeConflict(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            "The game's executable is missing from the bottle (C:\\\(path.replacingOccurrences(of: "/", with: "\\")))."
        case .runtimeConflict(let bottle):
            "Another game in “\(bottle)” is running on a different Wine runtime. Stop it first — one bottle can't run two Wine versions at once."
        case .notConfigured:
            "Fable's launcher isn't ready yet — try again in a moment."
        }
    }
}

/// Resolves the wine/wineserver binaries for a backend family. The seam that
/// lets launch-plan composition be tested without real Wine installs on disk —
/// the app adapts its managers; tests provide fixed URLs.
@MainActor
protocol RuntimeResolving {
    func wineBinary(for backend: GraphicsBackend) throws -> URL
    /// Alternate-runtime wineserver to drain after exit; nil for the default
    /// runtime (whose wineserver needs no explicit drain).
    func wineserverBinary(for backend: GraphicsBackend) -> URL?
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

    /// Fired after a game has fully exited *and* its prefix's wineserver has
    /// drained — i.e. the prefix is idle and safe to touch. Used to auto-heal
    /// Steam installs left stuck on the WoW64 commit step (no-op otherwise).
    var onGameFullyExited: ((Bottle.ID) -> Void)?

    /// Fired after every exit with the backend used and the crash signature
    /// (nil = clean run or an uncorrelatable crash). Wired to GameStatsStore
    /// so the same-crash-on-two-backends verdict can be reached — the First
    /// Light rule (docs/ARCHITECTURE.md).
    var onCrashSignature: ((Game.ID, GraphicsBackend, String?) -> Void)?

    func isRunning(_ gameID: Game.ID) -> Bool {
        running[gameID] != nil
    }

    /// Which Wine runtime each running game uses — one bottle must stay
    /// on one wineserver at a time.
    private var runningRuntime: [Game.ID: String] = [:]
    private var runningBottle: [Game.ID: Bottle.ID] = [:]
    /// The effective backend each run launched with (for crash correlation).
    private var runningBackend: [Game.ID: GraphicsBackend] = [:]

    // MARK: Dependencies

    /// Everything the launch flow composes with, wired once at app startup so
    /// call sites don't thread five managers apiece (behavior added at call
    /// sites drifts — the per-game-trigger gap came from exactly that).
    struct Dependencies {
        let bottleManager: BottleManager
        let wineManager: WineManager
        let gptkManager: GPTKManager
        let crossOverManager: CrossOverManager
        let sikarugirManager: SikarugirManager
        let triggerController: DualSenseTriggerController
        let activityMonitor: ActivityMonitor
        let toastCenter: ToastCenter
    }

    private var deps: Dependencies?

    /// Wire the launcher's collaborators. Called once from the app root.
    func configure(_ dependencies: Dependencies) {
        deps = dependencies
    }

    /// Adapts the configured managers to the runtime-resolution seam.
    private struct ManagerRuntimeResolver: RuntimeResolving {
        let deps: Dependencies

        func wineBinary(for backend: GraphicsBackend) throws -> URL {
            switch backend {
            case .gptk: try deps.gptkManager.wineBinary()
            case .crossover: try deps.crossOverManager.wineBinary()
            case .sikarugir: try deps.sikarugirManager.wineBinary()
            case .off, .dxmt, .dxvk: try deps.wineManager.wineBinary()
            }
        }

        func wineserverBinary(for backend: GraphicsBackend) -> URL? {
            switch backend {
            case .gptk: try? deps.gptkManager.wineserverBinary()
            case .crossover: try? deps.crossOverManager.wineserverBinary()
            case .sikarugir: try? deps.sikarugirManager.wineserverBinary()
            case .off, .dxmt, .dxvk: nil
            }
        }
    }

    // MARK: Launch plan

    /// Everything needed to start a game: the resolved Wine binary, full
    /// argument vector, merged environment, and working directory. The
    /// single source of truth for *how* a game launches — used both by
    /// `launch()` and by `ShortcutGenerator` so a desktop shortcut runs the
    /// exact same command the app does.
    struct LaunchPlan {
        let wine: URL
        let executable: URL
        /// Tokenized per-game arguments (appended after the executable).
        let arguments: [String]
        let environment: [String: String]
        let workingDirectory: URL
        let logFile: URL
        /// Identifies the wineserver family, for the one-runtime-per-bottle check.
        let runtimeKey: String
        /// Alternate-runtime wineserver to drain after exit (nil for the default).
        let releaseWineserver: URL?

        /// Full argv passed to `wine`: the executable path then its arguments.
        var wineArguments: [String] { [executable.path] + arguments }
    }

    /// The routing + environment-composition core: backend → wine binary,
    /// runtime key, and the layered environment. Pure except for the
    /// executable-exists check and CrossOver's bottle-config write, so tests
    /// lock the whole table with a stub resolver and a temp prefix.
    ///
    /// Environment precedence (later wins): base (WineEnv + prefix) →
    /// backend-specific → performance backend-agnostic → per-game overrides.
    static func composeLaunchPlan(
        game: Game,
        bottle: Bottle,
        prefix: URL,
        driveC: URL,
        baseEnvironment: [String: String],
        logFile: URL,
        runtime: any RuntimeResolving
    ) throws -> LaunchPlan {
        let executable = driveC.appending(path: game.executablePath)
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw GameLaunchError.executableMissing(game.executablePath)
        }

        // Keep real errors for crash diagnosis but silence the msync flood —
        // see WineEnv.debugDiagnostic for the why.
        var environment = WineEnv.withDiagnosticDebug(baseEnvironment)
        let baseOverrides = environment["WINEDLLOVERRIDES"] ?? ""

        // Per-game override wins over the bottle's default — lets a D3D9
        // and a D3D11 title share one bottle.
        let effectiveBackend = game.graphicsBackend ?? bottle.graphicsBackend

        let wine = try runtime.wineBinary(for: effectiveBackend)
        let runtimeKey: String
        switch effectiveBackend {
        case .gptk:
            runtimeKey = "gptk"
            environment.merge(
                GPTKManager.launchEnvironment(baseOverrides: baseOverrides)
            ) { _, new in new }
            environment.merge(bottle.performance.gptkEnvironment()) { _, new in new }
        case .dxvk:
            // DXVK runs on the modern wine — same binary as .off/.dxmt but
            // with d3d11/d3d12/dxgi routed to native so DXVK's prefix DLLs
            // win over Wine's stubs.
            runtimeKey = "wine"
            environment.merge(DXVKManager.launchEnvironment(
                baseOverrides: baseOverrides,
                frameRateCap: bottle.performance.frameRateCap,
                logFile: logFile
            )) { _, new in new }
        case .crossover:
            // CrossOver provides its own version-matched wine + D3DMetal.
            // Its wine wrapper resolves the bottle from CX_BOTTLE inside
            // CX_BOTTLE_PATH and requires cxbottle.conf at that path.
            try CrossOverManager.ensureBottleConfig(at: prefix)
            runtimeKey = "crossover"
            environment.merge(
                CrossOverManager.launchEnvironment(prefix: prefix, baseOverrides: baseOverrides)
            ) { _, new in new }
        case .sikarugir:
            // Sikarugir's wine-10.0 + D3DMetal recompiled against it.
            // Forces the D3DMetal builtins so prefix natives don't shadow,
            // and points D3DMetal at its framework (the env that makes CEF
            // composite instead of black-squaring).
            runtimeKey = "sikarugir"
            let sikBundle = wine.deletingLastPathComponent().deletingLastPathComponent()
            environment.merge(
                SikarugirManager.launchEnvironment(baseOverrides: baseOverrides, bundleRoot: sikBundle)
            ) { _, new in new }
            environment.merge(bottle.performance.gptkEnvironment()) { _, new in new }
        case .dxmt, .off:
            runtimeKey = "wine"
            // Frame-rate cap rides on DXMT's config when the backend is DXMT.
            var dxmtConfig = bottle.dxmtConfig
            dxmtConfig.maxFrameRate = bottle.performance.frameRateCap
            environment.merge(DXMTManager.launchEnvironment(
                enabled: effectiveBackend == .dxmt,
                config: dxmtConfig,
                baseOverrides: baseOverrides,
                logFile: logFile
            )) { _, new in new }
        }
        environment.merge(bottle.performance.backendAgnosticEnvironment()) { _, new in new }
        // Per-game environment overrides win over everything.
        environment.merge(game.environment) { _, new in new }

        return LaunchPlan(
            wine: wine,
            executable: executable,
            arguments: ArgumentTokenizer.tokenize(game.arguments),
            environment: environment,
            workingDirectory: executable.deletingLastPathComponent(),
            logFile: logFile,
            runtimeKey: runtimeKey,
            releaseWineserver: runtime.wineserverBinary(for: effectiveBackend)
        )
    }

    /// Resolves the backend, Wine binary, and environment for a game using the
    /// configured managers. Throws if the executable is missing.
    func makeLaunchPlan(_ game: Game, in bottle: Bottle) throws -> LaunchPlan {
        guard let deps else {
            assertionFailure("GameLauncher used before configure(_:)")
            throw GameLaunchError.notConfigured
        }
        let prefix = deps.bottleManager.prefixDirectory(for: bottle)
        return try Self.composeLaunchPlan(
            game: game,
            bottle: bottle,
            prefix: prefix,
            driveC: deps.bottleManager.driveCDirectory(for: bottle),
            baseEnvironment: deps.wineManager.environment(forPrefix: prefix),
            logFile: AppPaths.logs.appending(path: GameInstaller.logName(bottle.name, game.name)),
            runtime: ManagerRuntimeResolver(deps: deps)
        )
    }

    // MARK: The one launch flow

    /// True for a Steam game (under steamapps/common) that isn't Steam itself —
    /// those need the Steam client already running to launch directly.
    static func needsSteamRunning(_ game: Game) -> Bool {
        let path = game.executablePath.lowercased().replacingOccurrences(of: "\\", with: "/")
        return path.contains("steamapps/common") && !path.hasSuffix("steam.exe")
    }

    /// The one-stop launch every Play control uses: Steam-prerequisite nudge,
    /// Smart Bottle backend pick, launch, then trigger-profile application —
    /// centralized so behavior can't drift between call sites.
    func launchSmart(_ game: Game, in bottle: Bottle) async throws {
        guard let deps else {
            assertionFailure("GameLauncher used before configure(_:)")
            throw GameLaunchError.notConfigured
        }

        // Steam games need the client up first — surface that instead of
        // letting the raw exe fail cryptically. (Steam counts as running if
        // Fable launched it, even before the next activity scan sees it.)
        if Self.needsSteamRunning(game) {
            let steamTracked = bottle.games.contains {
                $0.executablePath.lowercased().hasSuffix("steam.exe") && isRunning($0.id)
            }
            if !steamTracked && !deps.activityMonitor.isSteamRunning(in: bottle) {
                deps.toastCenter.error("“\(game.name)” is a Steam game — start Steam in this bottle first, then launch it from your Steam library.")
            }
        }

        // Smart Bottle auto-picks a backend for an untouched bottle before
        // launch (no-op once configured), then we launch with the fresh config.
        let prepared = await deps.bottleManager.prepareSmartBackend(
            for: game, in: bottle,
            crossOverAvailable: deps.crossOverManager.isInstalled,
            sikarugirAvailable: deps.sikarugirManager.isDiscovered
        )
        let fresh = deps.bottleManager.bottle(with: bottle.id) ?? bottle

        // A helper (winetricks, an installer, winecfg) may have left the
        // DEFAULT wine's server on this prefix — a different build's server
        // makes this launch fail with 'version mismatch'. Idle bottle →
        // drain it first; busy bottle → leave it, same-runtime launches
        // coexist and launch() refuses mixed ones.
        await drainForeignServersIfIdle(
            for: fresh, runtime: prepared.graphicsBackend ?? fresh.graphicsBackend
        )

        try launch(prepared, in: fresh)
        refreshTriggers()
    }

    /// Keeps the DualSense adaptive-trigger profile matched to whatever's
    /// actually running — Fable-launched OR detected (a game started from inside
    /// Steam). Fable drives the trigger *resistance* as a hardware state through
    /// GameController, independent of whether the game supports triggers, so it
    /// "stacks on top of" the game's own input: even a game with zero native
    /// support gets the bottle's resistive triggers. Applies the running game's
    /// effective profile (its per-game override when resolvable, else the bottle
    /// default — the global-per-bottle baseline); clears when nothing runs.
    func refreshTriggers() {
        guard let deps else { return }
        for bottle in deps.bottleManager.bottles {
            for game in bottle.games
            where isRunning(game.id) || deps.activityMonitor.isRunning(game, in: bottle) {
                deps.triggerController.apply(
                    game.effectiveTriggerProfile(bottleDefault: bottle.triggerProfile)
                )
                return
            }
        }
        deps.triggerController.reset()
    }

    // MARK: One runtime per prefix (the version-mismatch gate)

    /// Prepares `bottle`'s prefix for work on `runtime`'s Wine build by
    /// draining every OTHER runtime's wineserver. Throws
    /// `PrefixRuntimeGate.BottleBusyError` while games run — surface it,
    /// never force. Helpers that spawn the default Wine (winetricks,
    /// installers, winecfg/regedit) MUST call this with `.off` first;
    /// `launch()` calls it with the game's effective backend. See
    /// docs/wine-quirks.md "mixed wineservers".
    func prepareExclusivePrefix(for bottle: Bottle, runtime: GraphicsBackend) async throws {
        guard let deps else { throw GameLaunchError.notConfigured }

        let fableLaunched = bottle.games.contains { isRunning($0.id) }
        let detected = PrefixRuntimeGate.hasProcesses(
            commands: ProcessActivity.runningCommands(), bottleID: bottle.id
        )

        // Every runtime family's wineserver except the one about to run.
        // A missing/uninstalled runtime just drops out of the list.
        var foreign: [URL] = []
        if runtimeFamily(of: runtime) != "wine" { foreign.append(contentsOf: [try? deps.wineManager.wineserverBinary()].compactMap { $0 }) }
        if runtimeFamily(of: runtime) != "gptk" { foreign.append(contentsOf: [try? deps.gptkManager.wineserverBinary()].compactMap { $0 }) }
        if runtimeFamily(of: runtime) != "crossover" { foreign.append(contentsOf: [try? deps.crossOverManager.wineserverBinary()].compactMap { $0 }) }
        if runtimeFamily(of: runtime) != "sikarugir" { foreign.append(contentsOf: [try? deps.sikarugirManager.wineserverBinary()].compactMap { $0 }) }

        try await PrefixRuntimeGate.ensureExclusive(
            prefix: deps.bottleManager.prefixDirectory(for: bottle),
            bottleName: bottle.name,
            foreignWineservers: foreign,
            hasLiveProcesses: fableLaunched || detected
        )
    }

    /// Launch-side variant: drains foreign servers only when the bottle is
    /// idle. A busy bottle is left alone — launching alongside a running
    /// game is legal on the same runtime, and the runtime-conflict check
    /// in launch() refuses the mixed case.
    func drainForeignServersIfIdle(for bottle: Bottle, runtime: GraphicsBackend) async {
        try? await prepareExclusivePrefix(for: bottle, runtime: runtime)
    }

    /// The wineserver family a backend runs on — mirrors composeLaunchPlan's
    /// runtimeKey exactly (off/dxmt/dxvk share the default wine).
    private func runtimeFamily(of backend: GraphicsBackend) -> String {
        switch backend {
        case .gptk: "gptk"
        case .crossover: "crossover"
        case .sikarugir: "sikarugir"
        case .off, .dxmt, .dxvk: "wine"
        }
    }

    /// Stop what Fable launched; for a game that's only *detected* (started
    /// externally or lingering after close), kill the bottle's wine tree.
    func stopSmart(_ game: Game, in bottle: Bottle) {
        if isRunning(game.id) {
            stop(game.id)
        } else if let deps {
            Task {
                try? await deps.wineManager.forceKillPrefix(
                    deps.bottleManager.prefixDirectory(for: bottle)
                )
            }
        }
    }

    func launch(_ game: Game, in bottle: Bottle) throws {
        guard let deps else {
            assertionFailure("GameLauncher used before configure(_:)")
            throw GameLaunchError.notConfigured
        }
        guard running[game.id] == nil else { return }

        // Self-heal the standard drive mappings (esp. Z: → /) before launch, so
        // an exe anywhere outside C: resolves. Cheap + idempotent.
        deps.wineManager.reconcileDrives(at: deps.bottleManager.prefixDirectory(for: bottle))

        let plan = try makeLaunchPlan(game, in: bottle)

        // Version-mismatched wineservers can't share a prefix: refuse
        // to mix runtimes within one bottle while games are running.
        let conflicting = runningBottle.contains { gameID, bottleID in
            bottleID == bottle.id && runningRuntime[gameID] != plan.runtimeKey
        }
        if conflicting {
            throw GameLaunchError.runtimeConflict(bottle.name)
        }

        let process = try ProcessRunner.start(
            plan.wine,
            arguments: plan.wineArguments,
            environment: plan.environment,
            currentDirectory: plan.workingDirectory,
            redirectingOutputTo: plan.logFile,
            // Claim the performance cores — the game is the foreground workload.
            qualityOfService: Stability.gameQoS
        )

        running[game.id] = process
        runningRuntime[game.id] = plan.runtimeKey
        runningBottle[game.id] = bottle.id
        // Same rule as composeLaunchPlan: per-game override wins.
        runningBackend[game.id] = game.graphicsBackend ?? bottle.graphicsBackend
        lastLog[game.id] = plan.logFile
        lastExitCode[game.id] = nil
        onProcessLifecycle?(game.id, process.processIdentifier)

        let gameName = game.name
        let bottleID = bottle.id
        let prefixPath = deps.bottleManager.prefixDirectory(for: bottle).path
        let releaseWineserver = plan.releaseWineserver
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
            let backend = self?.runningBackend[game.id]
            self?.running[game.id] = nil
            self?.runningRuntime[game.id] = nil
            self?.runningBottle[game.id] = nil
            self?.runningBackend[game.id] = nil
            self?.lastExitCode[game.id] = code
            self?.onProcessLifecycle?(game.id, nil)
            // SIGTERM (user pressed Stop) isn't a crash worth announcing.
            if code != 0 && code != 15 {
                self?.onAbnormalExit?("“\(gameName)” exited with code \(code) — check its log")
            }
            // Crash correlation: classify this run for the backend it used.
            // Clean runs report nil, which CLEARS a stale record — the game
            // evidently works on this backend now.
            if let backend {
                let signature = (code != 0 && code != 15)
                    ? GameDoctor.crashSignature(exitCode: code, logTail: Self.logTail(of: plan.logFile))
                    : nil
                self?.onCrashSignature?(game.id, backend, signature)
            }
            // Prefix is idle now — a Steam quit is the natural moment to
            // finish any install stuck on the WoW64 commit step.
            self?.onGameFullyExited?(bottleID)
        }
    }

    func stop(_ gameID: Game.ID) {
        running[gameID]?.terminate()
    }

    /// Last ~64 KB of a log — enough for the crash tail without reading a
    /// multi-GB Wine log into memory.
    nonisolated static func logTail(of url: URL, maxBytes: Int = 1 << 16) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

extension GameLauncher {
    /// THE running check: Fable-launched OR detected in the process table
    /// (Steam-launched, lingering). Every Play/Stop indicator goes through
    /// this so the rule can't drift between call sites.
    func isRunning(_ game: Game, in bottle: Bottle, activity: ActivityMonitor) -> Bool {
        isRunning(game.id) || activity.isRunning(game, in: bottle)
    }
}
