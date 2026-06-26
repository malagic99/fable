import Foundation
import Testing
@testable import Fable

/// Parsing real-shaped Heroic library caches into importable Windows games.
@Suite struct HeroicLibraryTests {
    private let fm = FileManager.default

    /// Builds a Heroic config root with the given store-cache JSON files.
    private func makeRoot(_ files: [String: String]) throws -> URL {
        let root = fm.temporaryDirectory.appending(path: "heroic-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cache = root.appending(path: "store_cache", directoryHint: .isDirectory)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        for (name, json) in files {
            try json.write(to: cache.appending(path: name), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test
    func parsesInstalledWindowsGamesAcrossStores() throws {
        let gog = """
        { "games": [
          { "app_name": "g1", "runner": "gog", "title": "Witcher 3", "is_installed": true, "folder_name": "Witcher3",
            "install": { "executable": "bin/witcher3.exe", "install_path": "/Games/Witcher3", "platform": "windows" } }
        ] }
        """
        let epic = """
        { "library": [
          { "app_name": "e1", "runner": "legendary", "title": "Absolute Drift", "is_installed": true, "folder_name": "AbsoluteDrift",
            "install": { "executable": "absolutedrift.exe", "install_path": "/Games/AbsoluteDrift", "platform": "Windows" } }
        ] }
        """
        let root = try makeRoot(["gog_library.json": gog, "legendary_library.json": epic])
        defer { try? fm.removeItem(at: root) }

        let games = HeroicLibrary.installedGames(root: root)
        // Sorted by title: "Absolute Drift" before "Witcher 3".
        #expect(games.map(\.title) == ["Absolute Drift", "Witcher 3"])
        #expect(games[0].runner == "legendary")
        #expect(games[0].sourceLabel == "Epic")
        #expect(games[1].executable == "bin/witcher3.exe")
        #expect(games[1].folderName == "Witcher3")
        #expect(games[1].installPath.path == "/Games/Witcher3")
    }

    @Test
    func skipsUninstalledMacNativeAndRedistEntries() throws {
        let gog = """
        { "games": [
          { "app_name": "not-installed", "runner": "gog", "title": "Owned Not Installed", "is_installed": false,
            "install": {} },
          { "app_name": "gog-redist", "runner": "gog", "title": "Galaxy Common Redistributables", "is_installed": true,
            "install": { "executable": "redist.exe", "install_path": "/Games/Redist", "platform": "windows" } },
          { "app_name": "mac-game", "runner": "gog", "title": "Mac Only", "is_installed": true,
            "install": { "executable": "MacGame.app", "install_path": "/Games/MacGame", "platform": "osx" } },
          { "app_name": "good", "runner": "gog", "title": "Real Game", "is_installed": true,
            "install": { "executable": "game.exe", "install_path": "/Games/Real", "platform": "windows" } }
        ] }
        """
        let root = try makeRoot(["gog_library.json": gog])
        defer { try? fm.removeItem(at: root) }

        let games = HeroicLibrary.installedGames(root: root)
        #expect(games.map(\.title) == ["Real Game"])   // the other three are filtered
    }

    @Test
    func deduplicatesByRunnerAndAppName() throws {
        let dup = """
        { "library": [
          { "app_name": "x", "runner": "legendary", "title": "Dupe", "is_installed": true,
            "install": { "executable": "x.exe", "install_path": "/Games/X", "platform": "Windows" } },
          { "app_name": "x", "runner": "legendary", "title": "Dupe", "is_installed": true,
            "install": { "executable": "x.exe", "install_path": "/Games/X", "platform": "Windows" } }
        ] }
        """
        let root = try makeRoot(["legendary_library.json": dup])
        defer { try? fm.removeItem(at: root) }
        #expect(HeroicLibrary.installedGames(root: root).count == 1)
    }

    @Test
    func emptyWhenNoHeroicData() throws {
        let root = try makeRoot([:])
        defer { try? fm.removeItem(at: root) }
        #expect(HeroicLibrary.installedGames(root: root).isEmpty)
    }
}
