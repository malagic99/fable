import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct BottleArchiveTests {
    /// Standard fixture: a BottleManager with one bottle that has a
    /// real on-disk prefix containing a known file. Tests assert on
    /// the round-trip preserving that file.
    private func makeFixture() throws -> (BottleManager, Bottle, VersionCatalog, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bottlesDir = root.appending(path: "Bottles", directoryHint: .isDirectory)
        let bottleManager = BottleManager(bottlesDirectory: bottlesDir)
        var bottle = try bottleManager.createBottle(name: "Archived")
        try bottleManager.setStatus(.ready, for: bottle.id)

        // Plant a known file inside the prefix so we can verify the
        // archive really carries the prefix tree.
        let prefix = bottleManager.prefixDirectory(for: bottle)
        let driveC = prefix.appending(path: "drive_c")
        try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
        try Data("hello-archive".utf8).write(to: driveC.appending(path: "marker.txt"))

        bottle = try #require(bottleManager.bottle(with: bottle.id))

        let catalog = VersionCatalog(components: [
            "wine": .init(name: "Wine", version: "11.10", url: URL(string: "https://x")!, sha256: ""),
            "dxmt": .init(name: "DXMT", version: "0.80", url: URL(string: "https://x")!, sha256: ""),
        ])
        return (bottleManager, bottle, catalog, root)
    }

    @Test
    func roundTripPackAndUnpackPreservesPrefixContents() async throws {
        let (manager, bottle, catalog, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = root.appending(path: "Archived.fbottle")
        try await BottleArchive.pack(bottle, bottleManager: manager,
                                     catalog: catalog, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))

        let unpacked = try await BottleArchive.unpack(archive)
        defer { try? FileManager.default.removeItem(at: unpacked.workingDirectory) }

        let marker = unpacked.prefixDirectory.appending(path: "drive_c/marker.txt")
        let bytes = try Data(contentsOf: marker)
        #expect(String(decoding: bytes, as: UTF8.self) == "hello-archive")
        #expect(unpacked.bottle.name == "Archived")
    }

    @Test
    func importAdoptsTheBottleWithFreshIdentityAndDedupedName() async throws {
        // The Friend Kit receiving end: pack on machine A, import on
        // machine B (a second, empty BottleManager here).
        let (manager, bottle, catalog, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appending(path: "Archived.fbottle")
        try await BottleArchive.pack(bottle, bottleManager: manager, catalog: catalog, to: archive)

        let receiver = BottleManager(
            bottlesDirectory: root.appending(path: "FriendBottles", directoryHint: .isDirectory)
        )
        let first = try receiver.importBottle(try await BottleArchive.unpack(archive))
        #expect(first.name == "Archived")
        #expect(first.id != bottle.id)          // fresh identity, never reused
        #expect(first.status == .ready)
        // Prefix landed in the receiver's tree, contents intact.
        let marker = receiver.prefixDirectory(for: first).appending(path: "drive_c/marker.txt")
        #expect(FileManager.default.fileExists(atPath: marker.path))
        // Games survive (their paths are C:-relative).
        #expect(first.games.map(\.name) == bottle.games.map(\.name))

        // Importing the same archive again dedups the name.
        let second = try receiver.importBottle(try await BottleArchive.unpack(archive))
        #expect(second.name == "Archived 2")
        #expect(receiver.bottles.count == 2)
    }

    @Test
    func donorExportStripsGamesAndLoginButKeepsTheClient() async throws {
        // The legal/privacy guard: a donor .fbottle must NOT carry installed
        // games (licensed content) or the owner's Steam session — but the
        // client itself travels. Checksum must verify on import, which is
        // only true if the SAME exclusions fed both tars.
        let (manager, bottle, catalog, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let steam = manager.prefixDirectory(for: bottle)
            .appending(path: "drive_c/\(SteamPaths.clientDirRelative)", directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: steam.appending(path: "steamapps/common/Game"), withIntermediateDirectories: true)
        try fm.createDirectory(at: steam.appending(path: "config"), withIntermediateDirectories: true)
        try Data("exe".utf8).write(to: steam.appending(path: "Steam.exe"))
        try Data("48GB of game".utf8).write(to: steam.appending(path: "steamapps/common/Game/game.bin"))
        try Data("account tokens".utf8).write(to: steam.appending(path: "config/loginusers.vdf"))
        try Data("sentry".utf8).write(to: steam.appending(path: "ssfn1234567890"))
        // Login state the client keeps outside its own folder, in the Wine
        // user's local AppData — the saved-login cache and the web cookies.
        let users = manager.prefixDirectory(for: bottle).appending(path: "drive_c/users", directoryHint: .isDirectory)
        let localSteam = users.appending(path: "donor/AppData/Local/Steam", directoryHint: .isDirectory)
        try fm.createDirectory(at: localSteam.appending(path: "htmlcache/Default/Network"), withIntermediateDirectories: true)
        try Data("ConnectCache".utf8).write(to: localSteam.appending(path: "local.vdf"))
        try Data("steamLoginSecure".utf8).write(to: localSteam.appending(path: "htmlcache/Default/Network/Cookies"))
        // Other AppData of that user is not login state and still travels.
        try fm.createDirectory(at: users.appending(path: "donor/AppData/Local/Other"), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: users.appending(path: "donor/AppData/Local/Other/settings.ini"))
        // The Steam account name lives in the registry (security scan
        // 2026-11-20), and games can live outside steamapps.
        let prefix = manager.prefixDirectory(for: bottle)
        let registry = #"""
        WINE REGISTRY Version 2

        [Software\\Valve\\Steam] 1794875685
        #time=1dd762d0bc63e54
        "AutoLoginUser"="owneraccount"
        "Language"="english"
        "SteamExe"="c:/program files (x86)/steam/steam.exe"

        [Software\\Valve\\Steam\\ActiveProcess] 1794875676
        "ActiveUser"=dword:0badf00d

        [Software\\Valve\\Steam\\Apps\\3669870] 1794875685
        "Name"="CONTROL Resonant"

        [Software\\Wine\\DllOverrides] 1794876356
        "d3d12"="builtin"
        """#
        try registry.write(to: prefix.appending(path: "user.reg"), atomically: true, encoding: .utf8)
        let driveC = prefix.appending(path: "drive_c", directoryHint: .isDirectory)
        for file in ["SteamBridge/1168880/MOLEKSYNTEZ.exe", "Program Files/Undertale/UNDERTALE.exe",
                     "windows/system32/cmd.exe"] {
            try fm.createDirectory(at: driveC.appending(path: file).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("MZ".utf8).write(to: driveC.appending(path: file))
        }

        // Metadata side: the steamapps game entry is stripped, Steam stays.
        var withGames = bottle
        withGames.games = [
            Game(name: "Steam", executablePath: "\(SteamPaths.exeRelative)"),
            Game(name: "Big Game", executablePath: "\(SteamPaths.clientDirRelative)/steamapps/common/Game/game.bin"),
            Game(name: "MOLEK-SYNTEZ", executablePath: "SteamBridge/1168880/MOLEKSYNTEZ.exe"),
            Game(name: "UNDERTALE", executablePath: "Program Files/Undertale/UNDERTALE.exe"),
            Game(name: "cmd", executablePath: "windows/system32/cmd.exe"),
        ]
        withGames.steamSyncedAppIDs = [3669870]
        let donor = BottleArchive.donorBottle(withGames)
        #expect(donor.games.map(\.name) == ["Steam"])
        #expect(donor.steamSyncedAppIDs == nil)

        let archive = root.appending(path: "Donor.fbottle")
        try await BottleArchive.pack(donor, bottleManager: manager, catalog: catalog,
                                     to: archive, excluding: BottleArchive.donorExclusions(for: withGames),
                                     sanitizeRegistry: true)
        // The original bottle is untouched, and the export's copy is gone.
        #expect(try String(contentsOf: prefix.appending(path: "user.reg"), encoding: .utf8).contains("owneraccount"))
        #expect(try fm.contentsOfDirectory(atPath: manager.directory(for: bottle).path)
            .allSatisfy { !$0.hasPrefix(".donor-export") })

        // Import verifies the checksum — the moment of truth for exclusion
        // symmetry — then the stripped files must be gone, the client not.
        let unpacked = try await BottleArchive.unpack(archive)
        defer { try? FileManager.default.removeItem(at: unpacked.workingDirectory) }
        let outSteam = unpacked.prefixDirectory.appending(path: "drive_c/\(SteamPaths.clientDirRelative)")
        #expect(fm.fileExists(atPath: outSteam.appending(path: "Steam.exe").path))
        #expect(!fm.fileExists(atPath: outSteam.appending(path: "steamapps").path))
        #expect(!fm.fileExists(atPath: outSteam.appending(path: "config").path))
        #expect(!fm.fileExists(atPath: outSteam.appending(path: "ssfn1234567890").path))
        let outUsers = unpacked.prefixDirectory.appending(path: "drive_c/users/donor/AppData/Local")
        #expect(!fm.fileExists(atPath: outUsers.appending(path: "Steam/local.vdf").path))
        #expect(!fm.fileExists(atPath: outUsers.appending(path: "Steam/htmlcache").path))
        #expect(fm.fileExists(atPath: outUsers.appending(path: "Other/settings.ini").path))
        // No account name, no installed-app list, the rest of the registry intact.
        let outRegistry = try String(contentsOf: unpacked.prefixDirectory.appending(path: "user.reg"), encoding: .utf8)
        #expect(!outRegistry.contains("owneraccount"))
        #expect(!outRegistry.contains("AutoLoginUser"))
        #expect(!outRegistry.contains("ActiveProcess"))
        #expect(!outRegistry.contains("CONTROL Resonant"))
        #expect(outRegistry.contains(#""Language"="english""#))
        #expect(outRegistry.contains(#""d3d12"="builtin""#))
        // Games outside steamapps don't travel; Windows' own programs do.
        let outDriveC = unpacked.prefixDirectory.appending(path: "drive_c")
        #expect(!fm.fileExists(atPath: outDriveC.appending(path: "SteamBridge").path))
        #expect(!fm.fileExists(atPath: outDriveC.appending(path: "Program Files/Undertale").path))
        #expect(fm.fileExists(atPath: outDriveC.appending(path: "windows/system32/cmd.exe").path))
        #expect(unpacked.bottle.steamSyncedAppIDs == nil)
        // The keeper from the fixture still travels.
        #expect(fm.fileExists(atPath: unpacked.prefixDirectory.appending(path: "drive_c/marker.txt").path))
    }

    /// Real bottles never imported: copying drops group-write bits and adds
    /// extended attributes, so the old raw-stream checksum never matched.
    @Test
    func aBottleWithGroupWritableFoldersAndAttributesImports() async throws {
        let (manager, bottle, catalog, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let folder = manager.prefixDirectory(for: bottle).appending(path: "drive_c/Shared", directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "file.txt"))
        try fm.setAttributes([.posixPermissions: 0o775], ofItemAtPath: folder.path)
        _ = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/xattr"), arguments: ["-w", "user.DOSATTRIB", "0x20", folder.appending(path: "file.txt").path])

        let archive = root.appending(path: "Real.fbottle")
        try await BottleArchive.pack(bottle, bottleManager: manager, catalog: catalog, to: archive)
        #expect(try await BottleArchive.inspect(archive).checksumFormat == BottleArchive.ChecksumFormat.normalized.rawValue)
        let unpacked = try await BottleArchive.unpack(archive)
        defer { try? fm.removeItem(at: unpacked.workingDirectory) }
        let mode = try fm.attributesOfItem(atPath: unpacked.prefixDirectory.appending(path: "drive_c/Shared").path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o775)
    }

    @Test
    func archivesFromBeforeTheFormatFieldUseTheRawChecksum() throws {
        let json = #"{"schemaVersion":1,"fableVersion":"1.3.0","exportedAt":"2026-11-01T00:00:00Z","originalBottleID":"102CC732-6BC7-479E-ACD2-771AF7D7912C","originalBottleName":"B","components":{},"prefixChecksum":"sha256:00"}"#
        let manifest = try JSONDecoder.fable().decode(BottleArchive.Manifest.self, from: Data(json.utf8))
        #expect(manifest.checksumFormat == nil)
    }

    @Test
    func manifestCarriesComponentVersionsAndOriginalIdentity() async throws {
        let (manager, bottle, catalog, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = root.appending(path: "Archived.fbottle")
        try await BottleArchive.pack(bottle, bottleManager: manager,
                                     catalog: catalog, to: archive)

        let manifest = try await BottleArchive.inspect(archive)
        #expect(manifest.schemaVersion == BottleArchive.Manifest.currentSchemaVersion)
        #expect(manifest.originalBottleID == bottle.id)
        #expect(manifest.originalBottleName == "Archived")
        #expect(manifest.components.wine == "11.10")
        #expect(manifest.components.dxmt == "0.80")
        #expect(manifest.components.gptk == nil, "Catalog had no GPTK entry, manifest should reflect that")
        #expect(manifest.prefixChecksum.hasPrefix("sha256:"))
    }

    @Test
    func packMissingBottleDirectoryThrows() async throws {
        let (manager, bottle, catalog, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        // Yank the bottle dir behind the manager's back to simulate
        // a race where another process deleted the bottle.
        try FileManager.default.removeItem(at: manager.directory(for: bottle))
        let archive = root.appending(path: "Archived.fbottle")
        await #expect(throws: ArchiveError.self) {
            _ = try await BottleArchive.pack(
                bottle, bottleManager: manager,
                catalog: catalog, to: archive
            )
        }
    }

    @Test
    func corruptArchiveRejectedAtUnpack() async throws {
        let (manager, bottle, catalog, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = root.appending(path: "Archived.fbottle")
        try await BottleArchive.pack(bottle, bottleManager: manager,
                                     catalog: catalog, to: archive)

        // Overwrite the middle of the archive with garbage.
        let handle = try FileHandle(forUpdating: archive)
        try handle.seek(toOffset: 64)
        try handle.write(contentsOf: Data(repeating: 0xFF, count: 256))
        try handle.close()

        await #expect(throws: ArchiveError.self) {
            _ = try await BottleArchive.unpack(archive)
        }
    }

    @Test
    func unsupportedSchemaIsRejected() async throws {
        let (manager, bottle, catalog, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        // Pack normally, then patch the manifest inside the archive to
        // a future schema version. This is the path users hit when an
        // older Fable opens a newer archive.
        let archive = root.appending(path: "Archived.fbottle")
        try await BottleArchive.pack(bottle, bottleManager: manager,
                                     catalog: catalog, to: archive)

        let temp = FileManager.default.temporaryDirectory
            .appending(path: "schema-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // Extract, patch manifest, repack.
        let extractResult = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: ["--zstd", "-xf", archive.path, "-C", temp.path]
        )
        try #require(extractResult.succeeded)

        let manifestPath = temp.appending(path: BottleArchive.manifestEntryName)
        var manifest = try JSONDecoder.fable().decode(
            BottleArchive.Manifest.self,
            from: Data(contentsOf: manifestPath)
        )
        // Reach in by replacing the file rather than mutating (Manifest's
        // schemaVersion is let). Encode a doctored version manually.
        let future = """
        {
            "schemaVersion": \(manifest.schemaVersion + 99),
            "fableVersion": "\(manifest.fableVersion)",
            "exportedAt": "\(ISO8601DateFormatter().string(from: manifest.exportedAt))",
            "originalBottleID": "\(manifest.originalBottleID.uuidString)",
            "originalBottleName": "\(manifest.originalBottleName)",
            "components": {},
            "prefixChecksum": "\(manifest.prefixChecksum)"
        }
        """
        try Data(future.utf8).write(to: manifestPath)
        _ = manifest // silence unused

        try FileManager.default.removeItem(at: archive)
        let repackResult = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: [
                "--zstd", "-cf", archive.path, "-C", temp.path,
                BottleArchive.manifestEntryName,
                BottleArchive.bottleEntryName,
                BottleArchive.prefixEntryName,
            ]
        )
        try #require(repackResult.succeeded)

        await #expect(throws: ArchiveError.self) {
            _ = try await BottleArchive.unpack(archive)
        }
    }

    @Test
    func archivedBottleSettingsSurviveTheRoundTrip() async throws {
        let (manager, originalBottle, catalog, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        // Spice up the bottle with non-default settings the archive
        // must preserve through round-trip.
        var perf = PerformanceOptions()
        perf.metalHUD = true
        perf.frameRateCap = 60
        try manager.setPerformance(perf, for: originalBottle.id)
        try manager.setWinetricksVerbInstalled("dotnet48", for: originalBottle.id)
        let updated = try #require(manager.bottle(with: originalBottle.id))

        let archive = root.appending(path: "Configured.fbottle")
        try await BottleArchive.pack(updated, bottleManager: manager,
                                     catalog: catalog, to: archive)
        let unpacked = try await BottleArchive.unpack(archive)
        defer { try? FileManager.default.removeItem(at: unpacked.workingDirectory) }

        #expect(unpacked.bottle.performance.metalHUD == true)
        #expect(unpacked.bottle.performance.frameRateCap == 60)
        #expect(unpacked.bottle.installedWinetricksVerbs == ["dotnet48"])
    }
}

/// External review 2026-11-23, N1 and N2.
@MainActor
@Suite struct BottleArchiveHardeningTests {
    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// An archive from someone else can carry file flags and ACLs. Import
    /// must not restore them: an immutable file can't be deleted, and an
    /// ACL can let other users on the Mac write to it.
    @Test
    func importDoesNotRestoreFileFlagsOrACLs() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "ArchiveFlags-\(UUID().uuidString)", directoryHint: .isDirectory)
        let source = root.appending(path: "source", directoryHint: .isDirectory)
        let out = root.appending(path: "out", directoryHint: .isDirectory)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        defer {
            _ = try? run("/usr/bin/chflags", ["-R", "nouchg", root.path])
            try? fm.removeItem(at: root)
        }
        let file = source.appending(path: "locked.txt")
        try Data("x".utf8).write(to: file)
        _ = try run("/bin/chmod", ["775", file.path])
        _ = try run("/bin/chmod", ["+a", "everyone allow write", file.path])
        _ = try run("/usr/bin/chflags", ["uchg", file.path])

        let archive = root.appending(path: "crafted.tar.zst")
        _ = try run("/usr/bin/tar", ["--zstd", "-cf", archive.path, "-C", source.path, "locked.txt"])
        _ = try run("/usr/bin/chflags", ["nouchg", file.path])
        // The crafted archive really carries both, or this test proves nothing.
        let listing = try run("/usr/bin/tar", ["--zstd", "-xpf", archive.path, "-C", out.path])
        #expect(listing.isEmpty)
        let unprotected = out.appending(path: "locked.txt")
        #expect((try fm.attributesOfItem(atPath: unprotected.path)[.immutable] as? Bool) == true)
        #expect(try run("/bin/ls", ["-le", unprotected.path]).contains("everyone allow write"))
        _ = try run("/usr/bin/chflags", ["nouchg", unprotected.path])
        try fm.removeItem(at: unprotected)

        _ = try run("/usr/bin/tar", BottleArchive.extractArguments(archive: archive, into: out))
        let extracted = out.appending(path: "locked.txt")
        #expect(fm.fileExists(atPath: extracted.path))
        #expect((try fm.attributesOfItem(atPath: extracted.path)[.immutable] as? Bool) != true)
        #expect(!(try run("/bin/ls", ["-le", extracted.path]).contains("everyone allow write")))
        // What -p is there for still happens: the permission bits as archived.
        #expect((try fm.attributesOfItem(atPath: extracted.path)[.posixPermissions] as? Int) == 0o775)
    }

    /// A registry that can't be read as text must stop a donor export, not
    /// travel with the owner's account name in it.
    @Test
    func aDonorExportStopsWhenTheRegistryCantBeRead() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "ArchiveReg-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: root) }
        let manager = BottleManager(bottlesDirectory: root.appending(path: "Bottles", directoryHint: .isDirectory))
        var bottle = try manager.createBottle(name: "Donor")
        try manager.setStatus(.ready, for: bottle.id)
        bottle = try #require(manager.bottle(with: bottle.id))
        let prefix = manager.prefixDirectory(for: bottle)
        try fm.createDirectory(at: prefix.appending(path: "drive_c"), withIntermediateDirectories: true)
        // "owneraccount" in Latin-1 around a byte that is never valid UTF-8.
        try Data("\"AutoLoginUser\"=\"owneraccount\"\u{00FF}".data(using: .isoLatin1)!)
            .write(to: prefix.appending(path: "user.reg"))
        let catalog = VersionCatalog(components: [
            "wine": .init(name: "Wine", version: "11.10", url: URL(string: "https://x")!, sha256: ""),
        ])

        let archive = root.appending(path: "Donor.fbottle")
        await #expect(throws: ArchiveError.registryUnreadable) {
            _ = try await BottleArchive.pack(bottle, bottleManager: manager, catalog: catalog,
                                             to: archive, sanitizeRegistry: true)
        }
        #expect(!fm.fileExists(atPath: archive.path))
        #expect(try fm.contentsOfDirectory(atPath: manager.directory(for: bottle).path)
            .allSatisfy { !$0.hasPrefix(".donor-export") })
    }
}

/// External review 2026-11-23: a donor export carried the owner's Mac user
/// name — the profile folder, its links into their home, the registry, and
/// installer logs — and the names of their mounted volumes.
@MainActor
@Suite struct DonorUserNameTests {
    @Test
    func onlyProfileAndHomePathsAreRenamed() {
        let text = #"""
        "TEMP"="C:\\users\\owner\\AppData\\Local\\Temp"
        "HOMEPATH"="\\users\\owner"
        "ProfileImagePath"="C:\\users\\owner"
        "Marlett (TrueType)"="Z:\\Users\\owner\\Library\\Fable\\marlett.ttf"
        "DesktopFile"="\\\\?\\Z:\\Users\\owner\\.local\\x.desktop"
        "Unix"="/Users/owner/Desktop"
        "Other"="C:\\users\\owners\\x"
        "Name"="owner"
        "Engine"="Z:\\Users\\someone\\owner.app"
        "USERNAME"="owner"
        "USERNAME"="owner2"
        """#
        let out = DonorExport.replacingProfileName(text, user: "owner", with: "fable-donor")
        #expect(out == #"""
        "TEMP"="C:\\users\\fable-donor\\AppData\\Local\\Temp"
        "HOMEPATH"="\\users\\fable-donor"
        "ProfileImagePath"="C:\\users\\fable-donor"
        "Marlett (TrueType)"="Z:\\Users\\fable-donor\\Library\\Fable\\marlett.ttf"
        "DesktopFile"="\\\\?\\Z:\\Users\\fable-donor\\.local\\x.desktop"
        "Unix"="/Users/fable-donor/Desktop"
        "Other"="C:\\users\\owners\\x"
        "Name"="owner"
        "Engine"="Z:\\Users\\someone\\owner.app"
        "USERNAME"="fable-donor"
        "USERNAME"="owner2"
        """#)
        // A user named after something else in the registry damages nothing.
        let wine = #""Source"="Z:\\Users\\wine\\Wine Devel.app\\wine""#
        #expect(DonorExport.replacingProfileName(wine, user: "wine", with: "x")
            == #""Source"="Z:\\Users\\x\\Wine Devel.app\\wine""#)
    }

    private func everyMention(of name: String, under root: URL) throws -> [String] {
        let fm = FileManager.default
        var hits: [String] = []
        let walker = try #require(fm.enumerator(atPath: root.path))
        while let relative = walker.nextObject() as? String {
            let path = root.appending(path: relative).path
            if relative.contains(name) { hits.append("name: \(relative)") }
            if let target = try? fm.destinationOfSymbolicLink(atPath: path) {
                if target.contains(name) { hits.append("link: \(relative) -> \(target)") }
                continue
            }
            if let data = fm.contents(atPath: path), data.range(of: Data(name.utf8)) != nil {
                hits.append("contents: \(relative)")
            }
        }
        return hits
    }

    @Test
    func aDonorExportNamesNobodyAndImportUsesTheImportersName() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "DonorName-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: root) }
        let manager = BottleManager(bottlesDirectory: root.appending(path: "Bottles", directoryHint: .isDirectory))
        var bottle = try manager.createBottle(name: "Donor")
        try manager.setStatus(.ready, for: bottle.id)
        bottle = try #require(manager.bottle(with: bottle.id))
        let prefix = manager.prefixDirectory(for: bottle)
        let users = prefix.appending(path: "drive_c/users", directoryHint: .isDirectory)
        let profile = users.appending(path: "zowner", directoryHint: .isDirectory)

        // The profile as Wine makes it.
        for folder in ["AppData/Local/Temp", "AppData/Roaming/Game", "Saved Games", "Games/Hand Game"] {
            try fm.createDirectory(at: profile.appending(path: folder), withIntermediateDirectories: true)
        }
        for (link, target) in [("Desktop", "/Users/zowner/Desktop"), ("Documents", "/Users/zowner/Documents")] {
            try fm.createSymbolicLink(atPath: profile.appending(path: link).path, withDestinationPath: target)
        }
        try Data("C:\\users\\zowner\\AppData".utf8).write(to: profile.appending(path: "AppData/Local/Temp/dd_vcredist.log"))
        // Links Wine and the owner made elsewhere: another profile, deep in
        // AppData, a game linked in from a download folder, a linked file —
        // and an ordinary link inside the bottle, which stays.
        let other = users.appending(path: "crossover", directoryHint: .isDirectory)
        try fm.createDirectory(at: other.appending(path: "AppData/Roaming/Microsoft/Windows"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: other.appending(path: "Music").path, withDestinationPath: "/Users/zowner/Music")
        try fm.createSymbolicLink(
            atPath: other.appending(path: "AppData/Roaming/Microsoft/Windows/Templates").path,
            withDestinationPath: "/Users/zowner/Templates")
        let programs = prefix.appending(path: "drive_c/Program Files", directoryHint: .isDirectory)
        try fm.createDirectory(at: programs.appending(path: "Tool/data"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: programs.appending(path: "Linked Game").path, withDestinationPath: "/Users/zowner/Downloads/Linked Game")
        let realFile = root.appending(path: "zowner-notes.txt")
        try Data("x".utf8).write(to: realFile)
        try fm.createSymbolicLink(atPath: programs.appending(path: "Tool/notes.txt").path, withDestinationPath: realFile.path)
        try fm.createSymbolicLink(atPath: programs.appending(path: "Tool/current").path, withDestinationPath: "data")
        try Data("keep".utf8).write(to: profile.appending(path: "AppData/Roaming/Game/settings.ini"))
        try Data("MZ".utf8).write(to: profile.appending(path: "Games/Hand Game/game.exe"))
        try Data("zowner".utf8).write(to: users.appending(path: ".DS_Store"))
        let logs = prefix.appending(path: "drive_c/ProgramData/Launcher/logs", directoryHint: .isDirectory)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("Z:\\Users\\zowner".utf8).write(to: logs.appending(path: "bootstrap.log"))
        try fm.createDirectory(at: users.appending(path: "Public"), withIntermediateDirectories: true)

        let dosdevices = prefix.appending(path: "dosdevices", directoryHint: .isDirectory)
        try fm.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: dosdevices.appending(path: "c:").path, withDestinationPath: "../drive_c")
        try fm.createSymbolicLink(atPath: dosdevices.appending(path: "z:").path, withDestinationPath: "/")
        try fm.createSymbolicLink(atPath: dosdevices.appending(path: "f:").path, withDestinationPath: "/Volumes/Private Project")
        try fm.createSymbolicLink(atPath: dosdevices.appending(path: "f::").path, withDestinationPath: "/dev/rdisk14")

        try #"""
        [Environment] 1
        "TEMP"="C:\\users\\zowner\\AppData\\Local\\Temp"
        [Volatile Environment] 1
        "USERNAME"="zowner"
        [Software\\Wine\\Fonts] 1
        "Marlett"="Z:\\Users\\zowner\\Library\\Application Support\\Fable\\marlett.ttf"
        """#.write(to: prefix.appending(path: "user.reg"), atomically: true, encoding: .utf8)
        try #"""
        [Software\\Microsoft\\Windows NT\\CurrentVersion\\ProfileList\\S-1-5-21] 1
        "ProfileImagePath"="C:\\users\\zowner"
        """#.write(to: prefix.appending(path: "system.reg"), atomically: true, encoding: .utf8)
        try #""Desktop"="C:\\users\\zowner\\Desktop""#
            .write(to: prefix.appending(path: "userdef.reg"), atomically: true, encoding: .utf8)

        var withGame = bottle
        withGame.games = [Game(name: "Hand Game", executablePath: "users/zowner/Games/Hand Game/game.exe")]
        let catalog = VersionCatalog(components: [
            "wine": .init(name: "Wine", version: "11.10", url: URL(string: "https://x")!, sha256: ""),
        ])
        let archive = root.appending(path: "Donor.fbottle")
        _ = try await BottleArchive.pack(
            BottleArchive.donorBottle(withGame), bottleManager: manager, catalog: catalog, to: archive,
            excluding: BottleArchive.donorExclusions(for: withGame), sanitizeRegistry: true,
            ownerUserName: "zowner")
        // The owner's own bottle is as it was.
        #expect(fm.fileExists(atPath: profile.appending(path: "Games/Hand Game/game.exe").path))
        #expect((try? fm.destinationOfSymbolicLink(atPath: profile.appending(path: "Desktop").path)) == "/Users/zowner/Desktop")
        #expect(fm.fileExists(atPath: dosdevices.appending(path: "f:").path) || (try? fm.destinationOfSymbolicLink(atPath: dosdevices.appending(path: "f:").path)) != nil)

        // Nothing in the archive names the owner or their volumes.
        let raw = root.appending(path: "raw", directoryHint: .isDirectory)
        try fm.createDirectory(at: raw, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["--zstd", "-xf", archive.path, "-C", raw.path]
        try tar.run()
        tar.waitUntilExit()
        #expect(try everyMention(of: "zowner", under: raw).isEmpty)
        #expect(try everyMention(of: "Private Project", under: raw).isEmpty)
        let rawPrefix = raw.appending(path: "prefix")
        #expect(try fm.contentsOfDirectory(atPath: rawPrefix.appending(path: "dosdevices").path).sorted() == ["c:", "z:"])

        // Import: the profile takes the importer's name and still works.
        let unpacked = try await BottleArchive.unpack(archive, importerUserName: "friend")
        defer { try? fm.removeItem(at: unpacked.workingDirectory) }
        #expect(unpacked.manifest.profilePlaceholder == DonorExport.profilePlaceholder)
        let theirs = unpacked.prefixDirectory.appending(path: "drive_c/users/friend", directoryHint: .isDirectory)
        #expect(try fm.contentsOfDirectory(atPath: theirs.deletingLastPathComponent().path).sorted() == ["Public", "crossover", "friend"])
        var isDirectory: ObjCBool = false
        #expect(fm.fileExists(atPath: theirs.appending(path: "Desktop").path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect((try? fm.destinationOfSymbolicLink(atPath: theirs.appending(path: "Desktop").path)) == nil)
        #expect(try fm.contentsOfDirectory(atPath: theirs.appending(path: "AppData/Local/Temp").path).isEmpty)
        #expect(fm.fileExists(atPath: theirs.appending(path: "AppData/Roaming/Game/settings.ini").path))
        #expect(fm.fileExists(atPath: theirs.appending(path: "Saved Games").path))
        // The game kept in the profile was still left out after the rename.
        #expect(!fm.fileExists(atPath: theirs.appending(path: "Games/Hand Game").path))
        let userReg = try String(contentsOf: unpacked.prefixDirectory.appending(path: "user.reg"), encoding: .utf8)
        #expect(userReg.contains(#""TEMP"="C:\\users\\friend\\AppData\\Local\\Temp""#))
        #expect(userReg.contains(#""USERNAME"="friend""#))
        #expect(userReg.contains(#"Z:\\Users\\friend\\Library\\Application Support\\Fable\\marlett.ttf"#))
        let systemReg = try String(contentsOf: unpacked.prefixDirectory.appending(path: "system.reg"), encoding: .utf8)
        #expect(systemReg.contains(#""ProfileImagePath"="C:\\users\\friend""#))
        #expect(try everyMention(of: "fable-donor", under: unpacked.prefixDirectory).isEmpty)
        let out = unpacked.prefixDirectory.appending(path: "drive_c")
        for folder in ["users/crossover/Music", "users/crossover/AppData/Roaming/Microsoft/Windows/Templates",
                       "Program Files/Linked Game"] {
            var isFolder: ObjCBool = false
            #expect(fm.fileExists(atPath: out.appending(path: folder).path, isDirectory: &isFolder) && isFolder.boolValue, "\(folder)")
            #expect((try? fm.destinationOfSymbolicLink(atPath: out.appending(path: folder).path)) == nil, "\(folder)")
        }
        #expect((try? fm.destinationOfSymbolicLink(atPath: out.appending(path: "Program Files/Tool/notes.txt").path)) == nil)
        #expect(!fm.fileExists(atPath: out.appending(path: "Program Files/Tool/notes.txt").path))
        #expect((try? fm.destinationOfSymbolicLink(atPath: out.appending(path: "Program Files/Tool/current").path)) == "data")
    }

    /// A plain (non-donor) export is a backup: it keeps everything.
    @Test
    func aPlainExportKeepsTheProfileAsItIs() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "PlainName-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: root) }
        let manager = BottleManager(bottlesDirectory: root.appending(path: "Bottles", directoryHint: .isDirectory))
        var bottle = try manager.createBottle(name: "Backup")
        try manager.setStatus(.ready, for: bottle.id)
        bottle = try #require(manager.bottle(with: bottle.id))
        let profile = manager.prefixDirectory(for: bottle).appending(path: "drive_c/users/zowner", directoryHint: .isDirectory)
        try fm.createDirectory(at: profile, withIntermediateDirectories: true)
        let catalog = VersionCatalog(components: [
            "wine": .init(name: "Wine", version: "11.10", url: URL(string: "https://x")!, sha256: ""),
        ])
        let archive = root.appending(path: "Backup.fbottle")
        _ = try await BottleArchive.pack(bottle, bottleManager: manager, catalog: catalog, to: archive, ownerUserName: "zowner")
        let unpacked = try await BottleArchive.unpack(archive, importerUserName: "friend")
        defer { try? fm.removeItem(at: unpacked.workingDirectory) }
        #expect(unpacked.manifest.profilePlaceholder == nil)
        #expect(fm.fileExists(atPath: unpacked.prefixDirectory.appending(path: "drive_c/users/zowner").path))
    }
}
