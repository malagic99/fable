import Foundation
import Testing
@testable import Fable

/// Games Steam installs in a bottle are added to the wall on their own.
/// These lock the two things that can go wrong: picking the wrong program,
/// and adding something the user didn't want (back).
@Suite("Steam library sync")
struct SteamLibrarySyncTests {

    // MARK: Building a binary app cache

    /// Writes a current-layout `appinfo.vdf` (string-table keys) holding the
    /// given apps, the way Steam does.
    private func appCache(_ apps: [(id: Int, tree: VDFValue)], magic: UInt32 = 0x0756_4429) -> Data {
        var strings: [String] = []
        func index(_ key: String) -> UInt32 {
            if let found = strings.firstIndex(of: key) { return UInt32(found) }
            strings.append(key)
            return UInt32(strings.count - 1)
        }
        func u32(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8((value >> (8 * UInt32($0))) & 0xFF) } }
        let inline = magic == 0x0756_4428
        func key(_ name: String) -> [UInt8] { inline ? Array(name.utf8) + [0] : u32(index(name)) }
        func encode(_ value: VDFValue) -> [UInt8] {
            guard case .object(let pairs) = value else { return [] }
            var bytes: [UInt8] = []
            for pair in pairs {
                switch pair.value {
                case .string(let text):
                    bytes += [0x01] + key(pair.key) + Array(text.utf8) + [0]
                case .object:
                    bytes += [0x00] + key(pair.key) + encode(pair.value)
                }
            }
            return bytes + [0x08]
        }

        var records: [UInt8] = []
        for app in apps {
            let tree = encode(.object([("appinfo", app.tree)]))
            let header = [UInt8](repeating: 0, count: 4 + 4 + 8 + 20 + 4 + 20)
            records += u32(UInt32(app.id)) + u32(UInt32(header.count + tree.count)) + header + tree
        }
        records += u32(0)

        var file = u32(magic) + u32(1)
        if !inline {
            let tableOffset = UInt64(file.count + 8 + records.count)
            file += u32(UInt32(tableOffset & 0xFFFF_FFFF)) + u32(UInt32(tableOffset >> 32))
        }
        file += records
        if !inline {
            file += u32(UInt32(strings.count))
            for string in strings { file += Array(string.utf8) + [0] }
        }
        return Data(file)
    }

    private func app(name: String, type: String = "Game", launch: [(exe: String, config: [(String, String)], type: String?, args: String?)]) -> VDFValue {
        .object([
            ("common", .object([("name", .string(name)), ("type", .string(type))])),
            ("config", .object([("launch", .object(launch.enumerated().map { index, entry in
                var fields: [(key: String, value: VDFValue)] = [("executable", .string(entry.exe))]
                if let args = entry.args { fields.append(("arguments", .string(args))) }
                if let type = entry.type { fields.append(("type", .string(type))) }
                if !entry.config.isEmpty {
                    fields.append(("config", .object(entry.config.map { ($0.0, VDFValue.string($0.1)) })))
                }
                return (String(index), VDFValue.object(fields))
            }))])),
        ])
    }

    // MARK: The cache reader

    @Test
    func readsRequestedAppsFromBothLayouts() throws {
        let wingman = app(name: "Project Wingman", launch: [("ProjectWingman.exe", [("oslist", "windows")], "default", "-nohmd")])
        let other = app(name: "Other", launch: [("Other.exe", [], nil, nil)])
        for magic in [UInt32(0x0756_4429), 0x0756_4428] {
            let data = appCache([(895870, wingman), (42, other)], magic: magic)
            let found = try #require(SteamAppInfoCache.entries(for: [895870], in: data))
            #expect(found.count == 1)
            #expect(found[895870]?["common"]?.string("name") == "Project Wingman")
            #expect(found[895870]?["config"]?["launch"]?["0"]?.string("arguments") == "-nohmd")
        }
    }

    @Test
    func damagedOrUnknownFilesNeverCrashAndNeverInventData() {
        let good = appCache([(7, app(name: "X", launch: [("x.exe", [], nil, nil)]))])
        // Every truncation of a valid file: nil or a smaller answer, no trap.
        for length in stride(from: 0, to: good.count, by: 3) {
            let result = SteamAppInfoCache.entries(for: [7], in: good.prefix(length))
            #expect(result == nil || result?[7] == nil || result?[7]?["common"]?.string("name") == "X")
        }
        #expect(SteamAppInfoCache.entries(for: [7], in: Data("not a cache at all, just text".utf8)) == nil)
        // An older layout Fable doesn't read is refused, not guessed at.
        var old = good
        old[old.startIndex] = 0x27
        #expect(SteamAppInfoCache.entries(for: [7], in: old) == nil)
    }

    // MARK: Choosing the program

    /// Control Resonant's real shape: 25 entries, the first a developer
    /// profiling build on a private branch. Only the shipped program exists.
    @Test
    func theProgramThatIsActuallyInstalledWinsOverTheFirstListed() {
        let info = app(name: "CONTROL Resonant", launch: [
            ("profile/Game_x64_prof.exe", [("BetaKey", "milestone")], nil, nil),
            ("development/Game_x64_dev.exe", [("BetaKey", "development")], nil, nil),
            ("CONTROLResonant.exe", [("BetaKey", "test")], nil, nil),
            ("CONTROLResonant.exe", [("BetaKey", "main_shipping")], nil, nil),
        ])
        let entry = SteamLibrarySync.launchEntry(appInfo: info, betaKey: nil) { $0 == "CONTROLResonant.exe" }
        #expect(entry?.executable == "CONTROLResonant.exe")
        // Nothing on disk yet (still downloading): nothing is added.
        #expect(SteamLibrarySync.launchEntry(appInfo: info, betaKey: nil) { _ in false } == nil)
    }

    @Test
    func theInstalledBranchsEntryIsPreferredThenBranchlessOnes() {
        let info = app(name: "G", launch: [
            ("beta.exe", [("BetaKey", "beta")], nil, nil),
            ("game.exe", [], nil, "-fast"),
        ])
        let all: (String) -> Bool = { _ in true }
        #expect(SteamLibrarySync.launchEntry(appInfo: info, betaKey: nil, exists: all)?.executable == "game.exe")
        #expect(SteamLibrarySync.launchEntry(appInfo: info, betaKey: nil, exists: all)?.arguments == "-fast")
        #expect(SteamLibrarySync.launchEntry(appInfo: info, betaKey: "beta", exists: all)?.executable == "beta.exe")
    }

    @Test
    func nonWindowsVRAndEscapingEntriesAreNeverChosen() {
        let info = app(name: "G", launch: [
            ("AppRun", [("oslist", "linux")], "default", nil),
            ("Game.app", [("oslist", "macos")], "default", nil),
            ("vr.exe", [("oslist", "windows")], "vr", nil),
            ("..\\\\..\\\\windows\\\\system32\\\\cmd.exe", [], nil, nil),
            ("bin\\\\game.exe", [("oslist", "windows")], "default", nil),
        ])
        let entry = SteamLibrarySync.launchEntry(appInfo: info, betaKey: nil) { _ in true }
        #expect(entry?.executable == "bin/game.exe")
        #expect(SteamLibrarySync.isContained("bin/game.exe"))
        #expect(!SteamLibrarySync.isContained("../game.exe"))
        #expect(!SteamLibrarySync.isContained("/abs/game.exe"))
    }

    // MARK: Manifests

    @Test
    func manifestsSayWhenAGameIsFullyInstalled() {
        func manifest(flags: Int, dir: String = "DSX") -> String {
            "\"AppState\"\n{\n\t\"appid\"\t\t\"1812620\"\n\t\"name\"\t\t\"DSX\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n\t\"installdir\"\t\t\"\(dir)\"\n}\n"
        }
        #expect(SteamLibrarySync.Manifest.parse(manifest(flags: 4))?.isFullyInstalled == true)
        // Update pending but installed: still launchable.
        #expect(SteamLibrarySync.Manifest.parse(manifest(flags: 6))?.isFullyInstalled == true)
        // Control Resonant mid-download.
        #expect(SteamLibrarySync.Manifest.parse(manifest(flags: 1026))?.isFullyInstalled == false)
        // A folder name that would climb out of the library is refused.
        #expect(SteamLibrarySync.Manifest.parse(manifest(flags: 4, dir: "..")) == nil)
        #expect(SteamLibrarySync.Manifest.parse(manifest(flags: 4, dir: "a/b")) == nil)
    }

    // MARK: End to end on a fake library

    private func makeLibrary() throws -> (driveC: URL, steamRoot: URL) {
        let fm = FileManager.default
        let driveC = fm.temporaryDirectory.appending(path: "fable-steam-\(UUID().uuidString)/drive_c", directoryHint: .isDirectory)
        let steamRoot = SteamPaths.clientRoot(inDriveC: driveC)
        let steamapps = steamRoot.appending(path: "steamapps", directoryHint: .isDirectory)
        try fm.createDirectory(at: steamapps.appending(path: "common"), withIntermediateDirectories: true)
        try fm.createDirectory(at: steamRoot.appending(path: "appcache"), withIntermediateDirectories: true)

        func install(_ id: Int, _ name: String, dir: String, flags: Int, files: [String]) throws {
            let text = "\"AppState\"\n{\n\t\"appid\"\t\t\"\(id)\"\n\t\"name\"\t\t\"\(name)\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n\t\"installdir\"\t\t\"\(dir)\"\n}\n"
            try text.write(to: steamapps.appending(path: "appmanifest_\(id).acf"), atomically: true, encoding: .utf8)
            for file in files {
                let url = steamapps.appending(path: "common/\(dir)/\(file)")
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("MZ".utf8).write(to: url)
            }
        }
        try install(895870, "Project Wingman", dir: "Project Wingman", flags: 4, files: ["ProjectWingman.exe"])
        try install(3669870, "CONTROL Resonant", dir: "CONTROL Resonant", flags: 1026, files: [])
        try install(228980, "Steamworks Common Redistributables", dir: "Steamworks Shared", flags: 4, files: ["x.exe"])
        try install(502500, "ACE COMBAT 7", dir: "ACE COMBAT 7", flags: 4, files: [])   // stale manifest, no files
        try install(5503090, "Pure Skill Demo", dir: "Pure Skill Demo", flags: 4, files: ["PureSkill.exe"])

        let cache = appCache([
            (895870, app(name: "Project Wingman", launch: [
                ("ProjectWingman.exe", [("oslist", "windows")], "default", "-nohmd"),
                ("ProjectWingman.exe", [("oslist", "windows")], "vr", "-vr"),
            ])),
            (3669870, app(name: "CONTROL Resonant", launch: [("CONTROLResonant.exe", [], nil, nil)])),
            (228980, app(name: "Steamworks Common Redistributables", type: "Tool", launch: [("x.exe", [], nil, nil)])),
            (502500, app(name: "ACE COMBAT 7", launch: [("Ace7Game.exe", [("oslist", "windows")], "default", nil)])),
            (5503090, app(name: "Pure Skill Demo", type: "Demo", launch: [("PureSkill.exe", [("oslist", "windows")], "default", nil)])),
        ])
        try cache.write(to: steamRoot.appending(path: "appcache/appinfo.vdf"))
        return (driveC, steamRoot)
    }

    @Test @MainActor
    func discoveryFindsOnlyInstalledLaunchableGames() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.driveC.deletingLastPathComponent()) }
        let games = SteamLibrarySync.discover(steamRoot: library.steamRoot, driveC: library.driveC)

        // Not the download in progress, not the tool, not the manifest with no files.
        #expect(games.map(\.name) == ["Project Wingman", "Pure Skill Demo"])
        let wingman = try #require(games.first)
        #expect(wingman.executablePath == "Program Files (x86)/Steam/steamapps/common/Project Wingman/ProjectWingman.exe")
        #expect(wingman.arguments == "-nohmd")
        // The path is one the launcher accepts: inside drive_c, and present.
        #expect(FileManager.default.fileExists(atPath: library.driveC.appending(path: wingman.executablePath).path))
        #expect(GameLauncher.needsSteamRunning(Game(name: wingman.name, executablePath: wingman.executablePath)))
    }

    @Test
    func aGameIsAddedOnceAndStaysRemovedWhenRemoved() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.driveC.deletingLastPathComponent()) }
        let games = SteamLibrarySync.discover(steamRoot: library.steamRoot, driveC: library.driveC)
        var bottle = Bottle(name: "Steam Ready")

        let first = SteamLibrarySync.newGames(games, bottle: bottle, known: [])
        #expect(first.count == 2)
        // The user removes them; they were recorded as known.
        bottle.games = []
        #expect(SteamLibrarySync.newGames(games, bottle: bottle, known: Set(games.map(\.appID))).isEmpty)
    }

    @Test
    func aGameTheUserAlreadyAddedByHandIsLeftAlone() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.driveC.deletingLastPathComponent()) }
        let games = SteamLibrarySync.discover(steamRoot: library.steamRoot, driveC: library.driveC)
        // By hand, and deliberately a different program in the same folder.
        var bottle = Bottle(name: "Steam Ready")
        bottle.games = [Game(
            name: "Wingman (my launcher)",
            executablePath: "Program Files (x86)/Steam/steamapps/common/project wingman/Launcher.exe")]
        #expect(SteamLibrarySync.newGames(games, bottle: bottle, known: []).map(\.name) == ["Pure Skill Demo"])
    }

    @Test
    func theFingerprintChangesWhenTheLibraryDoes() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.driveC.deletingLastPathComponent()) }
        let before = SteamLibrarySync.fingerprint(steamRoot: library.steamRoot)
        #expect(before == SteamLibrarySync.fingerprint(steamRoot: library.steamRoot))
        let manifest = library.steamRoot.appending(path: "steamapps/appmanifest_3669870.acf")
        let finished = try String(contentsOf: manifest, encoding: .utf8).replacingOccurrences(of: "1026", with: "4")
        try (finished + "\n").write(to: manifest, atomically: true, encoding: .utf8)
        #expect(before != SteamLibrarySync.fingerprint(steamRoot: library.steamRoot))
    }

    @Test
    func aBottleFromBeforeThisFeatureDecodesAndTheRecordRoundTrips() throws {
        var bottle = Bottle(name: "Old")
        let old = try JSONEncoder().encode(bottle)
        #expect(try JSONDecoder().decode(Bottle.self, from: old).steamSyncedAppIDs == nil)
        bottle.steamSyncedAppIDs = [895870, 5503090]
        let roundTripped = try JSONDecoder().decode(Bottle.self, from: JSONEncoder().encode(bottle))
        #expect(roundTripped.steamSyncedAppIDs == [895870, 5503090])
    }
}

/// Opt-in, read-only: what would be found in a real bottle's Steam library.
/// `FABLE_STEAM_DRIVE_C=/path/to/drive_c swift test --filter LiveSteamLibrary`
@Suite("Live Steam library", .enabled(if: ProcessInfo.processInfo.environment["FABLE_STEAM_DRIVE_C"] != nil))
struct LiveSteamLibraryTests {
    @Test
    func printsWhatDiscoveryFinds() {
        let driveC = URL(filePath: ProcessInfo.processInfo.environment["FABLE_STEAM_DRIVE_C"]!)
        let games = SteamLibrarySync.discover(steamRoot: SteamPaths.clientRoot(inDriveC: driveC), driveC: driveC)
        for game in games {
            print("LIVE \(game.appID) | \(game.name) | \(game.executablePath) | args: \(game.arguments)")
        }
        print("LIVE found \(games.count)")
    }
}
