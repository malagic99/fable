import Foundation
import Testing
@testable import Fable

/// Engine pinning (FRICL slice 1): a bottle keeps the engine versions it was
/// stamped with until the user moves it.
@Suite struct BottleRuntimeTests {
    @Test
    func firstLaunchStampsAndLaterLaunchesNeverMovePins() {
        var runtime = BottleRuntime()
        runtime = runtime.recordingLaunch(backend: .sikarugir, versions: ["sikarugir": "WS12WineSikarugir10.0_4"])
        #expect(runtime.pins == ["sikarugir": "WS12WineSikarugir10.0_4"])

        // The pinned version was missing and the newest ran instead: the pin
        // stays, so it's used again once the version is back.
        runtime = runtime.recordingLaunch(backend: .sikarugir, versions: ["sikarugir": "WS12WineSikarugir10.0_5"])
        #expect(runtime.pins["sikarugir"] == "WS12WineSikarugir10.0_4")
        #expect(runtime.lastLaunch?.versions["sikarugir"] == "WS12WineSikarugir10.0_5")

        // A newly used backend adds its pins next to the existing ones.
        runtime = runtime.recordingLaunch(backend: .dxvk, versions: ["wine": "11.10_1"])
        #expect(runtime.pins == ["sikarugir": "WS12WineSikarugir10.0_4", "wine": "11.10_1"])
    }

    @Test
    func theWine11TemplateIsEvidenceNeverAPin() {
        let runtime = BottleRuntime().recordingLaunch(
            backend: .sikarugir11, versions: ["sikarugir11": "11.0_1", "sikarugir-template": "1.0.27"])
        #expect(runtime.pins == ["sikarugir11": "11.0_1"])
        #expect(runtime.lastLaunch?.versions["sikarugir-template"] == "1.0.27")
        // A template that moved on is not reported as a missing pin.
        var withStaleTemplatePin = runtime
        withStaleTemplatePin.pins["sikarugir-template"] = "1.0.20"
        #expect(withStaleTemplatePin.missingPins(resolved: ["sikarugir11": "11.0_1", "sikarugir-template": "1.0.27"]).isEmpty)
    }

    @Test
    func pinsAreReadFromTheBottleRecordBesideAPrefix() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "PrefixPins-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dir) }
        let prefix = dir.appending(path: "prefix", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        #expect(EnginePins.forPrefix(prefix).isEmpty)

        var bottle = Bottle(name: "P")
        bottle.runtime = BottleRuntime(pins: ["wine": "11.9_1"])
        try JSONEncoder().encode(bottle).write(to: dir.appending(path: "bottle.json"))
        #expect(EnginePins.forPrefix(prefix) == ["wine": "11.9_1"])

        bottle.runtime?.policy = .followNewest
        try JSONEncoder().encode(bottle).write(to: dir.appending(path: "bottle.json"))
        #expect(EnginePins.forPrefix(prefix).isEmpty)
    }

    @Test
    func followNewestRecordsEvidenceButPinsNothing() {
        let runtime = BottleRuntime(policy: .followNewest)
            .recordingLaunch(backend: .off, versions: ["wine": "11.10_1"])
        #expect(runtime.pins.isEmpty)
        #expect(runtime.activePins.isEmpty)
        #expect(runtime.lastLaunch?.backend == .off)
    }

    @Test
    func missingPinsComparesPinnedWithResolved() {
        let runtime = BottleRuntime(pins: ["wine": "11.9_1", "gptk": "3.0-3"])
        let missing = runtime.missingPins(resolved: ["wine": "11.10_1", "gptk": "3.0-3"])
        #expect(missing.count == 1)
        #expect(missing["wine"]?.pinned == "11.9_1")
        #expect(missing["wine"]?.used == "11.10_1")
    }

    @Test
    func olderBottleJSONDecodesWithoutARuntime() throws {
        let original = Bottle(name: "Old")
        var json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        json.removeValue(forKey: "runtime")
        let decoded = try JSONDecoder().decode(Bottle.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.runtime == nil)
        #expect(decoded.enginePins.isEmpty)
    }

    @Test
    func runtimeRoundTripsAndUnknownPolicyReadsAsPinned() throws {
        var bottle = Bottle(name: "Pinned")
        bottle.runtime = BottleRuntime(pins: ["wine": "11.10_1"])
        let decoded = try JSONDecoder().decode(Bottle.self, from: JSONEncoder().encode(bottle))
        #expect(decoded.runtime == bottle.runtime)
        #expect(decoded.enginePins == ["wine": "11.10_1"])

        let future = #"{"schemaVersion": 7, "policy": "somethingNew", "pins": {"wine": "12.0"}}"#
        let runtime = try JSONDecoder().decode(BottleRuntime.self, from: Data(future.utf8))
        #expect(runtime.policy == .pinned)
        #expect(runtime.pins == ["wine": "12.0"])
    }

    @Test
    func unreadableRuntimeDoesNotStopTheBottleLoading() throws {
        let original = Bottle(name: "Odd")
        var json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any]
        )
        json["runtime"] = "not an object"
        let decoded = try JSONDecoder().decode(Bottle.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.name == "Odd")
        #expect(decoded.runtime == nil)
    }

    @Test
    func backendsMapToTheirEngineComponents() {
        #expect(GraphicsBackend.dxvk.engineComponentIDs == ["wine"])
        #expect(GraphicsBackend.sikarugir11.engineComponentIDs == ["sikarugir11"])
        #expect(GraphicsBackend.crossover.engineComponentIDs.isEmpty)
    }
}

@MainActor
@Suite struct EngineResolutionTests {
    private let fm = FileManager.default

    /// A component manager over a temp directory with the given versions on disk.
    private func makeManager(_ versions: [String: [String]]) throws -> (ComponentManager, URL) {
        let root = fm.temporaryDirectory.appending(path: "Pins-\(UUID().uuidString)", directoryHint: .isDirectory)
        let manager = ComponentManager(
            componentsDirectory: root.appending(path: "Components", directoryHint: .isDirectory),
            downloadsDirectory: root.appending(path: "Downloads", directoryHint: .isDirectory)
        )
        for (id, list) in versions {
            for version in list {
                try fm.createDirectory(
                    at: manager.componentsDirectory.appending(path: "\(id)/\(version)", directoryHint: .isDirectory),
                    withIntermediateDirectories: true
                )
            }
        }
        return (manager, root)
    }

    @Test
    func pinnedVersionWinsWhenInstalled() throws {
        let (manager, root) = try makeManager(["wine": ["11.9_1", "11.10_1"]])
        defer { try? fm.removeItem(at: root) }

        #expect(manager.installedDirectory(for: "wine")?.lastPathComponent == "11.10_1")
        EnginePins.$current.withValue(["wine": "11.9_1"]) {
            #expect(manager.installedDirectory(for: "wine")?.lastPathComponent == "11.9_1")
            // Installs and update checks are about the app, not a bottle.
            #expect(manager.newestInstalledDirectory(for: "wine")?.lastPathComponent == "11.10_1")
        }
    }

    @Test
    func missingPinFallsBackToNewest() throws {
        let (manager, root) = try makeManager(["wine": ["11.10_1"]])
        defer { try? fm.removeItem(at: root) }

        EnginePins.$current.withValue(["wine": "11.2_1"]) {
            #expect(manager.installedDirectory(for: "wine")?.lastPathComponent == "11.10_1")
        }
    }

    @Test
    func strayFilesAreNotVersions() throws {
        let (manager, root) = try makeManager(["wine": ["11.10_1"]])
        defer { try? fm.removeItem(at: root) }
        try Data().write(to: manager.componentsDirectory.appending(path: "wine/notes.txt"))
        #expect(manager.installedVersions(for: "wine") == ["11.10_1"])
    }

    @Test
    func sikarugir11HonorsAPinnedAssembledPair() throws {
        let (manager, root) = try makeManager(["sikarugir11": ["11.0_1", "11.0_2"]])
        defer { try? fm.removeItem(at: root) }
        for (engine, template) in [("11.0_1", "1.0.27"), ("11.0_2", "1.0.28")] {
            let engineRoot = manager.componentsDirectory.appending(path: "sikarugir11/\(engine)", directoryHint: .isDirectory)
            let bin = engineRoot.appending(path: "wswine.bundle/bin", directoryHint: .isDirectory)
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            try Data().write(to: bin.appending(path: "wine"))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.appending(path: "wine").path)
            try Data(template.utf8).write(to: engineRoot.appending(path: Sikarugir11Manager.assembledMarker))
        }
        let url = URL(string: "https://example.invalid/x.tar.xz")!
        let catalog = VersionCatalog(components: [
            "sikarugir11": .init(name: "E", version: "11.0_2", url: url, sha256: ""),
            "sikarugir-template": .init(name: "T", version: "1.0.28", url: url, sha256: ""),
        ])
        let sikarugir11 = Sikarugir11Manager(componentManager: manager, catalog: catalog)

        #expect(try sikarugir11.engineRoot().lastPathComponent == "11.0_2")
        let pinned = try EnginePins.$current.withValue(["sikarugir11": "11.0_1", "sikarugir-template": "1.0.27"]) {
            try sikarugir11.engineRoot()
        }
        #expect(pinned.lastPathComponent == "11.0_1")
        // A pinned engine that was never assembled falls back to the catalog pair.
        try fm.removeItem(at: manager.componentsDirectory.appending(
            path: "sikarugir11/11.0_1/\(Sikarugir11Manager.assembledMarker)"))
        let unassembled = try EnginePins.$current.withValue(["sikarugir11": "11.0_1"]) {
            try sikarugir11.engineRoot()
        }
        #expect(unassembled.lastPathComponent == "11.0_2")
    }

    // MARK: Inventory

    @Test
    func updatesListOnlyNewerVersionsOfPinnedComponents() throws {
        let (manager, root) = try makeManager([
            "sikarugir": ["WS12WineSikarugir10.0_4", "WS12WineSikarugir10.0_5"],
            "wine": ["11.10_1"],
        ])
        defer { try? fm.removeItem(at: root) }

        var bottle = Bottle(name: "B")
        bottle.runtime = BottleRuntime(pins: ["sikarugir": "WS12WineSikarugir10.0_4", "wine": "11.10_1"])
        let updates = EngineInventory.updates(for: bottle, componentManager: manager)
        #expect(updates == [.init(componentID: "sikarugir", pinned: "WS12WineSikarugir10.0_4", newest: "WS12WineSikarugir10.0_5")])

        bottle.runtime?.policy = .followNewest
        #expect(EngineInventory.updates(for: bottle, componentManager: manager).isEmpty)
    }

    @Test
    func unusedKeepsPinnedNewestAndCatalogVersions() throws {
        let (manager, root) = try makeManager([
            "wine": ["11.2_1", "11.9_1", "11.10_1", "11.12_1"],
            "dxmt": ["0.70", "0.80"],   // not pinnable — never listed
        ])
        defer { try? fm.removeItem(at: root) }

        var pinned = Bottle(name: "Pinned")
        pinned.runtime = BottleRuntime(pins: ["wine": "11.2_1"])
        var follower = Bottle(name: "Follower")
        follower.runtime = BottleRuntime(policy: .followNewest, pins: ["wine": "11.9_1"])

        let unused = EngineInventory.unusedVersions(
            bottles: [pinned, follower, Bottle(name: "Unstamped")],
            componentManager: manager,
            keep: ["wine": "11.10_1"]
        )
        // 11.2 pinned, 11.9 pinned (policy aside), 11.10 catalog, 11.12 newest.
        #expect(unused.isEmpty)

        // A version a bottle last ran on is kept even when nothing pins it —
        // its game may still be running there.
        var running = Bottle(name: "Running")
        running.runtime = BottleRuntime(policy: .followNewest)
            .recordingLaunch(backend: .off, versions: ["wine": "11.2_1"])
        let keptByLaunch = EngineInventory.unusedVersions(
            bottles: [running], componentManager: manager, keep: [:])
        #expect(keptByLaunch.map(\.version) == ["11.10_1", "11.9_1"])

        let none = EngineInventory.unusedVersions(bottles: [], componentManager: manager, keep: [:])
        #expect(none.map(\.version) == ["11.10_1", "11.2_1", "11.9_1"])
    }
}

@MainActor
@Suite struct EngineMoveTests {
    @Test
    func moveKeepsABackupOnTheOldPinsAndClearsTheBottlesPins() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "FableTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = BottleManager(bottlesDirectory: dir)

        let bottle = try manager.createBottle(name: "AAA")
        let pins = ["sikarugir": "WS12WineSikarugir10.0_4"]
        try manager.setRuntime(BottleRuntime(pins: pins), for: bottle.id)

        let backup = try manager.moveToNewestEngines(bottle.id, backupName: "AAA (before engine update)")
        #expect(backup.name == "AAA (before engine update)")
        #expect(manager.bottle(with: backup.id)?.runtime?.pins == pins)
        #expect(manager.bottle(with: bottle.id)?.runtime?.pins.isEmpty == true)
        #expect(manager.bottle(with: bottle.id)?.runtime?.policy == .pinned)

        // A second move picks a free backup name rather than failing.
        try manager.setRuntime(BottleRuntime(pins: pins), for: bottle.id)
        let second = try manager.moveToNewestEngines(bottle.id, backupName: "AAA (before engine update)")
        #expect(second.name == "AAA (before engine update) 2")

        // And the pins survive a reload from disk.
        let reloaded = BottleManager(bottlesDirectory: dir)
        #expect(reloaded.bottle(with: backup.id)?.runtime?.pins == pins)
    }
}

@Suite struct LaunchHeaderEngineTests {
    @Test
    func headerNamesEnginesAndMissingPins() {
        var plan = GameLauncher.LaunchPlan(
            wine: URL(filePath: "/x/wine"),
            executable: URL(filePath: "/x/game.exe"),
            arguments: [],
            environment: [:],
            workingDirectory: URL(filePath: "/x"),
            logFile: URL(filePath: "/x/log"),
            runtimeKey: "sikarugir",
            releaseWineserver: nil
        )
        plan.engineVersions = ["sikarugir": "WS12WineSikarugir10.0_4", "wine": "11.10_1"]
        plan.enginesPinned = true
        plan.missingPins = ["wine": (pinned: "11.9_1", used: "11.10_1")]
        let header = plan.launchDetails
        #expect(header.contains("fable: engine sikarugir WS12WineSikarugir10.0_4 (pinned)"))
        #expect(header.contains("fable: engine wine 11.10_1 (pinned 11.9_1 is not installed — used the newest)"))
        #expect(header.hasSuffix(GameDoctor.launchHeaderEnd + "\n"))
    }
}
