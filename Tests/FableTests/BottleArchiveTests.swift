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
