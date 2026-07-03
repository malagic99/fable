import Foundation
import Testing
@testable import Fable

/// Native macOS games in the library: model, manifest enumeration, tooling
/// filter, and store persistence.
@MainActor
@Suite struct NativeGamesTests {
    private let fm = FileManager.default

    @Test
    func modelRoundTripsBothSources() throws {
        let games = [
            NativeGame(name: "Control", source: .steam(appID: 870780)),
            NativeGame(name: "Prism Launcher", source: .app(path: "/Applications/Prism Launcher.app")),
        ]
        let decoded = try JSONDecoder().decode([NativeGame].self, from: JSONEncoder().encode(games))
        #expect(decoded[0].steamAppID == 870780)
        #expect(decoded[0].appPath == nil)
        #expect(decoded[1].appPath == "/Applications/Prism Launcher.app")
        #expect(decoded[1].steamAppID == nil)
    }

    @Test
    func installedAppsEnumeratesManifests() throws {
        let root = fm.temporaryDirectory.appending(path: "nsteam-\(UUID().uuidString)", directoryHint: .isDirectory)
        let steamapps = root.appending(path: "steamapps", directoryHint: .isDirectory)
        try fm.createDirectory(at: steamapps, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try #"""
        "AppState" { "appid" "870780"  "name" "Control Ultimate Edition"  "installdir" "Control" }
        """#.write(to: steamapps.appending(path: "appmanifest_870780.acf"), atomically: true, encoding: .utf8)
        try #"""
        "AppState" { "appid" "264710"  "name" "Subnautica" }
        """#.write(to: steamapps.appending(path: "appmanifest_264710.acf"), atomically: true, encoding: .utf8)

        let apps = SteamAppManifest.installedApps(steamRoot: root)
        #expect(apps.count == 2)
        #expect(apps.first?.name == "Control Ultimate Edition")   // sorted
        #expect(apps.first?.installDir == "Control")
        #expect(apps.map(\.appID).contains(264710))
    }

    @Test
    func staleManifestsWithoutGameFilesAreDetected() throws {
        // A manifest can claim "installed" while common/<installdir> is a husk
        // (observed live: Balatro's dir held only a .DS_Store while the acf
        // said 85 MB) — hasGameFiles must reject those and accept real ones.
        let root = fm.temporaryDirectory.appending(path: "nsteam-\(UUID().uuidString)", directoryHint: .isDirectory)
        let common = root.appending(path: "steamapps/common", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: root) }

        // Husk: directory with a token file, far under the threshold.
        let husk = common.appending(path: "Husk", directoryHint: .isDirectory)
        try fm.createDirectory(at: husk, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: husk.appending(path: ".DS_Store"))

        // Real install: content past the threshold.
        let real = common.appending(path: "RealGame", directoryHint: .isDirectory)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try Data(count: 6_000_000).write(to: real.appending(path: "game.bin"))

        #expect(!SteamAppManifest.hasGameFiles(installDir: "Husk", steamRoot: root))
        #expect(SteamAppManifest.hasGameFiles(installDir: "RealGame", steamRoot: root))
        #expect(!SteamAppManifest.hasGameFiles(installDir: "Nonexistent", steamRoot: root))
        #expect(!SteamAppManifest.hasGameFiles(installDir: nil, steamRoot: root))
    }

    @Test
    func steamToolingIsFilteredFromImports() {
        #expect(NativeGamesStore.isSteamTooling("Steamworks Common Redistributables"))
        #expect(NativeGamesStore.isSteamTooling("SteamVR"))
        #expect(NativeGamesStore.isSteamTooling("Steam Controller Configs"))
        #expect(!NativeGamesStore.isSteamTooling("Control"))
        #expect(!NativeGamesStore.isSteamTooling("Subnautica"))
    }

    @Test
    func storePersistsAcrossInstances() throws {
        let file = fm.temporaryDirectory.appending(path: "native-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: file) }

        let store = NativeGamesStore(fileURL: file)
        store.importNativeSteamGames([(appID: 264710, name: "Subnautica")])
        store.addApp(at: URL(filePath: "/Applications/Chess.app"))
        #expect(store.games.count == 2)

        // Duplicates are ignored.
        store.importNativeSteamGames([(appID: 264710, name: "Subnautica")])
        store.addApp(at: URL(filePath: "/Applications/Chess.app"))
        #expect(store.games.count == 2)

        let reopened = NativeGamesStore(fileURL: file)
        #expect(reopened.games.count == 2)
        #expect(reopened.games.contains { $0.steamAppID == 264710 })

        reopened.remove(reopened.games[0])
        #expect(NativeGamesStore(fileURL: file).games.count == 1)
    }

    @Test
    func searchFiltersByName() {
        let file = fm.temporaryDirectory.appending(path: "native-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: file) }
        let store = NativeGamesStore(fileURL: file)
        store.importNativeSteamGames([(appID: 1, name: "Control"), (appID: 2, name: "Subnautica")])
        #expect(store.entries(query: "sub").map(\.name) == ["Subnautica"])
        #expect(store.entries().count == 2)
    }
}
