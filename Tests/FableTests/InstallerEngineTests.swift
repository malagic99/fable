import Foundation
import Testing
@testable import Fable

@Suite struct InstallerEngineTests {
    private let fm = FileManager.default

    private func makeTemp() throws -> URL {
        let dir = fm.temporaryDirectory.appending(path: "installer-engine-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A fake Wine at `root/<relative>` that passes the executable check.
    private func makeWine(_ root: URL, _ relative: String) throws {
        let wine = root.appending(path: relative)
        try fm.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: wine)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
    }

    private func makeEngine(in components: URL, version: String = "24.0.7_7", assembled: Bool) throws {
        let root = components.appending(path: "installer-engine/\(version)")
        try makeWine(root, "wswine.bundle/bin/wine")
        if assembled {
            try Data("1.0.27".utf8).write(to: root.appending(path: InstallerEngineManager.assembledMarker))
        }
    }

    // MARK: Discovery order

    @Test
    func fablesEngineWinsOverEverythingElse() throws {
        let temp = try makeTemp()
        defer { try? fm.removeItem(at: temp) }
        let components = temp.appending(path: "Components"), home = temp.appending(path: "home")
        try makeEngine(in: components, assembled: true)
        try makeWine(components, "gptk/3.0-3/bin/wine64")
        try makeWine(home, "Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64")

        let runtime = try #require(CompatibilityRuntime.discover(componentsDirectory: components, home: home, applications: temp))
        #expect(runtime.name == InstallerEngineManager.runtimeName)
        #expect(runtime.wineBinary.path.hasSuffix("installer-engine/24.0.7_7/wswine.bundle/bin/wine"))
        // Its dylibs live in its own lib/, for wine and for a bare wineserver.
        // (Compared by suffix: the temp directory resolves through /private.)
        let libraryPath = runtime.environment["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
        #expect(libraryPath.split(separator: ":").first?
            .hasSuffix("installer-engine/24.0.7_7/wswine.bundle/lib") == true)
        #expect(libraryPath.contains(":/usr/lib"))
        #expect(runtime.wineserverBinary.lastPathComponent == "wineserver")
    }

    @Test
    func halfInstalledEngineIsNotUsed() throws {
        let temp = try makeTemp()
        defer { try? fm.removeItem(at: temp) }
        let components = temp.appending(path: "Components"), home = temp.appending(path: "home")
        try makeEngine(in: components, assembled: false)
        #expect(InstallerEngineManager.installedRuntime(componentsDirectory: components) == nil)
        #expect(CompatibilityRuntime.discover(componentsDirectory: components, home: home, applications: temp) == nil)
    }

    @Test
    func fablesOwnGPTKComesBeforeOtherAppsLeftovers() throws {
        let temp = try makeTemp()
        defer { try? fm.removeItem(at: temp) }
        let components = temp.appending(path: "Components"), home = temp.appending(path: "home")
        try makeWine(components, "gptk/3.0-3/bin/wine64")
        try makeWine(home, "Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64")
        try makeWine(home, "Library/Application Support/heroic/tools/game-porting-toolkit/x/bin/wine64")

        let runtime = try #require(CompatibilityRuntime.discover(componentsDirectory: components, home: home, applications: temp))
        #expect(runtime.name == "Game Porting Toolkit")
        #expect(runtime.environment.isEmpty)

        // With only the leftovers, Heroic's maintained toolkit beats Whisky's.
        try fm.removeItem(at: components.appending(path: "gptk"))
        let fallback = try #require(CompatibilityRuntime.discover(componentsDirectory: components, home: home, applications: temp))
        #expect(fallback.name == "Heroic Game Porting Toolkit")
    }

    @Test
    func drainTimeoutStopsALingeringServer() async throws {
        let temp = try makeTemp()
        defer { try? fm.removeItem(at: temp) }
        // A stand-in wineserver: `-w` waits until `-k` removes its flag file,
        // like the real one waiting on a helper that never exits.
        let bin = temp.appending(path: "bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let flag = temp.appending(path: "running").path
        let script = """
        #!/bin/sh
        case "$1" in
          -w) touch '\(flag)'; n=0; while [ -e '\(flag)' ] && [ $n -lt 300 ]; do sleep 0.1; n=$((n+1)); done;;
          -k) rm -f '\(flag)';;
        esac
        """
        for name in ["wine", "wineserver"] {
            let url = bin.appending(path: name)
            try Data(script.utf8).write(to: url)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let runtime = CompatibilityRuntime(name: "stub", wineBinary: bin.appending(path: "wine"))
        let start = ContinuousClock.now
        await GameInstaller.releasePrefix(from: runtime, prefix: temp, timeout: .seconds(1))
        let elapsed = ContinuousClock.now - start
        // Without the fix this returns only when the 30 s stand-in gives up.
        #expect(elapsed < .seconds(10), "returned after \(elapsed)")
        #expect(!fm.fileExists(atPath: flag))
    }

    // MARK: 16-bit detection

    private func header(signature: String, at offset: Int = 0x80) -> Data {
        var data = Data(count: 0x200)
        data[0] = 0x4D; data[1] = 0x5A
        data[0x3C] = UInt8(offset)
        for (i, byte) in signature.utf8.enumerated() { data[offset + i] = byte }
        return data
    }

    @Test
    func sixteenBitProgramsAreRecognised() {
        #expect(PEInfo.isSixteenBit(header(signature: "NE")))
        #expect(!PEInfo.isSixteenBit(header(signature: "PE\0\0")))
        #expect(!PEInfo.isSixteenBit(Data("MZ".utf8)))
        #expect(!PEInfo.isSixteenBit(Data()))
        // A plain DOS program: MZ with no new-style header.
        var dos = Data(count: 0x200); dos[0] = 0x4D; dos[1] = 0x5A
        #expect(!PEInfo.isSixteenBit(dos))
    }

    @Test @MainActor
    func sixteenBitInstallerIsRefusedBeforeWineStarts() async throws {
        let temp = try makeTemp()
        defer { try? fm.removeItem(at: temp) }
        let setup = temp.appending(path: "SETUP.EXE")
        try header(signature: "NE").write(to: setup)
        let bottles = BottleManager(bottlesDirectory: temp.appending(path: "Bottles"))
        let wine = WineManager(
            componentManager: ComponentManager(componentsDirectory: temp, downloadsDirectory: temp),
            catalog: VersionCatalog(components: [:]))
        do {
            _ = try await GameInstaller().runInstaller(
                setup, bottle: Bottle(name: "B"), bottleManager: bottles, wineManager: wine)
            Issue.record("a 16-bit installer was launched")
        } catch GameInstallError.sixteenBitInstaller(let name) {
            #expect(name == "SETUP.EXE")
        }
    }

    // MARK: Catalog and Doctor

    @Test
    func bundledCatalogPinsTheEngine() throws {
        let engine = try #require(try VersionCatalog.loadBundled().components[InstallerEngineManager.componentID])
        #expect(ChecksumVerifier.isPinned(engine.sha256))
        #expect(engine.url.host() == "github.com")
        #expect(engine.url.path().hasPrefix("/Sikarugir-App/Engines/"))
    }

    @Test
    func doctorNamesTheWine11ExceptionStorm() throws {
        let temp = try makeTemp()
        defer { try? fm.removeItem(at: temp) }
        let log = temp.appending(path: "installer.log")
        try Data("01b0:err:seh:dispatch_user_callback ignoring exception c0000005\n".utf8).write(to: log)
        let finding = GameDoctor.installerBlocker(fableLog: log, driveC: temp, since: Date())
        #expect(finding?.id == "doctor-wow64-callback-exception-storm")
    }
}

@Suite struct BundledAntiCheatTests {
    @Test
    func snapshotShipsAndLoadsWithoutHeroic() throws {
        let url = try #require(AntiCheatDatabase.bundledSnapshot)
        let db = try #require(AntiCheatDatabase.load(from: url))
        #expect(db.count > 1000)
        // A home with no Heroic still gets a database.
        let empty = FileManager.default.temporaryDirectory.appending(path: "no-heroic-\(UUID().uuidString)")
        #expect(AntiCheatDatabase.loadFromDefaultLocations(home: empty) != nil)
    }

    @Test
    func linuxOnlySupportIsACaveatOnMac() {
        // "Supported" means Proton's Linux anti-cheat runtime — not a Mac thing.
        #expect(AntiCheatDatabase.severity(for: "Supported") == .caveat)
        #expect(AntiCheatDatabase.severity(for: "Running") == .info)
        #expect(AntiCheatDatabase.severity(for: "Denied") == .knownBlocker)
        let db = AntiCheatDatabase(entries: [.init(name: "Elden Ring", status: "Supported", anticheats: ["Easy Anti-Cheat"])])
        let finding = db.finding(forGameNamed: "ELDEN RING™")
        #expect(finding?.title.contains("not on Mac") == true)
    }
}

@Suite struct LaunchTransparencyTests {
    @Test
    func gameDLLOverridesAddToFablesInsteadOfReplacingThem() {
        let base = "mscoree,mshtml=;winemenubuilder.exe=d;d3d11,d3d12,dxgi,nvapi64=b"
        let merged = WineEnv.mergingDLLOverrides("dxgi=n;xinput1_3=n,b", into: base)
        // Fable's entries survive…
        #expect(merged.contains("mscoree,mshtml="))
        #expect(merged.contains("winemenubuilder.exe=d"))
        #expect(merged.contains("d3d11,d3d12,nvapi64=b"))
        // …and the game's choice for dxgi replaces Fable's rather than competing with it.
        #expect(merged.contains("dxgi=n"))
        #expect(!merged.contains("dxgi,") && !merged.contains(",dxgi="))
        #expect(merged.hasSuffix("dxgi=n;xinput1_3=n,b"))
        #expect(WineEnv.mergingDLLOverrides("a=n", into: nil) == "a=n")
        #expect(WineEnv.mergingDLLOverrides("A=n", into: "a,b=b") == "b=b;A=n")
        // A stray "=mode" entry isn't a DLL, and modes are trimmed.
        #expect(WineEnv.mergingDLLOverrides("=n; d3d11 = n ", into: nil) == "d3d11=n")
    }

    @Test
    func doctorIgnoresTheLaunchHeader() {
        let header = """
        fable: launch 2026-11-11T17:00:00Z
        fable: environment (Wine and renderer variables):
        fable:   WINEDLLOVERRIDES=mscoree,mshtml=;d3d12=b
        fable:   VKD3D_CONFIG=dxr
        fable: ---- Wine output ----
        0024:fixme:keyboard:NtUserActivateKeyboardLayout Changing user locale is not supported
        """
        #expect(GameDoctor.diagnose(log: header).isEmpty)
        // Read from partway through the header: the first line no longer
        // starts with "fable:", but it's still before the end marker.
        let tail = String(header.drop(while: { $0 != "W" }))
        #expect(GameDoctor.diagnose(log: tail).isEmpty)
        #expect(!GameDoctor.diagnose(log: header + "\nerr:module:import_dll Library mscoree.dll not found").isEmpty)
    }
}

@Suite struct LaunchNoticeTests {
    private let steamGame = Game(name: "STALKER 2", executablePath:
        "Program Files (x86)/Steam/steamapps/common/S.T.A.L.K.E.R. 2/Stalker2.exe")

    @Test
    func firstD3DMetalLaunchGetsTheShaderNoticeOnce() {
        #expect(GameLauncher.firstLaunchNotice(game: steamGame, backend: .sikarugir, playedBefore: false)?
            .contains("compiles its shaders") == true)
        #expect(GameLauncher.firstLaunchNotice(game: steamGame, backend: .sikarugir, playedBefore: true) == nil)
        #expect(GameLauncher.firstLaunchNotice(game: steamGame, backend: .dxmt, playedBefore: false) == nil)
        let steam = Game(name: "Steam", executablePath: "Program Files (x86)/Steam/steam.exe")
        #expect(GameLauncher.firstLaunchNotice(game: steam, backend: .sikarugir, playedBefore: false) == nil)
    }

    @Test
    func smartBottleSaysWhatItChanged() {
        var picked = steamGame
        picked.graphicsBackend = .sikarugir
        let notice = GameLauncher.smartBottleNotice(
            game: steamGame, prepared: picked, performanceChanged: true, bottleName: "Steam Ready")
        #expect(notice?.contains("Sikarugir") == true)
        #expect(notice?.contains("known setup") == true)       // STALKER 2 has a recipe
        #expect(notice?.contains("whole “Steam Ready” bottle") == true)
        // Nothing changed, or the user had already chosen: no toast.
        #expect(GameLauncher.smartBottleNotice(game: steamGame, prepared: steamGame,
                                               performanceChanged: false, bottleName: "B") == nil)
        #expect(GameLauncher.smartBottleNotice(game: picked, prepared: picked,
                                               performanceChanged: false, bottleName: "B") == nil)
    }
}
