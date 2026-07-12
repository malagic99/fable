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
        base: [String: String] = ["WINEDLLOVERRIDES": "mscoree,mshtml="]
    ) throws -> GameLauncher.LaunchPlan {
        try GameLauncher.composeLaunchPlan(
            game: game, bottle: bottle, prefix: prefix, driveC: driveC,
            baseEnvironment: base,
            logFile: fm.temporaryDirectory.appending(path: "plan-test.log"),
            runtime: StubRuntime()
        )
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
