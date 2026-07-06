import Foundation
import Testing
@testable import Fable

/// The self-healing Steam committer: finishes installs that downloaded +
/// extracted but stalled on the (dead-service) commit step under WoW64.
@Suite struct SteamInstallCommitterTests {
    private let fm = FileManager.default

    /// Builds a fake Steam tree with one app extracted into `downloading/`.
    /// `extractedBytes` controls whether it looks fully extracted.
    private func makeSteam(
        appid: String = "999",
        installdir: String = "My Game",
        bytesToStage: Int,
        extractedBytes: Int,
        depot: String = "111",
        manifest: String = "222333"
    ) throws -> URL {
        let root = fm.temporaryDirectory.appending(path: "Steam-\(UUID().uuidString)", directoryHint: .isDirectory)
        let steamapps = root.appending(path: "steamapps", directoryHint: .isDirectory)
        let downloading = steamapps.appending(path: "downloading", directoryHint: .isDirectory)
        let appDir = downloading.appending(path: appid, directoryHint: .isDirectory)
        let depotcache = root.appending(path: "depotcache", directoryHint: .isDirectory)
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: depotcache, withIntermediateDirectories: true)

        // The extracted payload (one file of the requested size).
        try Data(count: extractedBytes).write(to: appDir.appending(path: "game.bin"))
        // Per-depot state file (names the depot) + a depotcache manifest.
        try Data("x".utf8).write(to: downloading.appending(path: "state_\(appid)_\(depot).patch"))
        try Data("m".utf8).write(to: depotcache.appending(path: "\(depot)_\(manifest).manifest"))

        let acf = """
        "AppState"
        {
        	"appid"		"\(appid)"
        	"name"		"\(installdir)"
        	"installdir"		"\(installdir)"
        	"StateFlags"		"1026"
        	"BytesToDownload"		"\(bytesToStage)"
        	"BytesToStage"		"\(bytesToStage)"
        	"TargetBuildID"		"5"
        	"InstalledDepots"
        	{
        	}
        }
        """
        try acf.write(to: steamapps.appending(path: "appmanifest_\(appid).acf"), atomically: true, encoding: .utf8)
        return root
    }

    @Test
    func directorySizeSumsRegularFiles() throws {
        let root = try makeSteam(bytesToStage: 100, extractedBytes: 100)
        defer { try? fm.removeItem(at: root) }
        let appDir = root.appending(path: "steamapps/downloading/999")
        #expect(SteamInstallCommitter.directorySize(appDir) == 100)
    }

    @Test
    func parsesDepotAndManifestIDs() throws {
        let root = try makeSteam(bytesToStage: 100, extractedBytes: 100, depot: "111", manifest: "987654")
        defer { try? fm.removeItem(at: root) }
        let downloading = root.appending(path: "steamapps/downloading")
        #expect(SteamInstallCommitter.depotIDs(forApp: "999", in: downloading) == ["111"])
        #expect(SteamInstallCommitter.manifestID(forDepot: "111", steamRoot: root) == "987654")
    }

    @Test
    func commitsFullyExtractedApp() throws {
        let root = try makeSteam(bytesToStage: 1000, extractedBytes: 1000)
        defer { try? fm.removeItem(at: root) }

        let committed = SteamInstallCommitter.commitStuckInstalls(steamRoot: root)
        #expect(committed == ["My Game"])

        // Payload moved into common/<installdir>.
        let installed = root.appending(path: "steamapps/common/My Game/game.bin")
        #expect(fm.fileExists(atPath: installed.path))
        // Download scratch + state files cleaned.
        #expect(!fm.fileExists(atPath: root.appending(path: "steamapps/downloading/999").path))
        #expect(!fm.fileExists(atPath: root.appending(path: "steamapps/downloading/state_999_111.patch").path))

        // Manifest marked installed with the depot's manifest id.
        let acf = try String(contentsOf: root.appending(path: "steamapps/appmanifest_999.acf"), encoding: .utf8)
        let app = try #require(SteamKeyValues.parse(acf)).value
        #expect(app.int("StateFlags") == 4)
        #expect(app.string("FullValidateAfterNextUpdate") == "0")
        #expect(app["InstalledDepots"]?["111"]?.string("manifest") == "222333")
    }

    @Test
    func skipsPartiallyExtractedApp() throws {
        // Extracted is short of BytesToStage → not ready, leave it alone.
        let root = try makeSteam(bytesToStage: 1000, extractedBytes: 400)
        defer { try? fm.removeItem(at: root) }

        let committed = SteamInstallCommitter.commitStuckInstalls(steamRoot: root)
        #expect(committed.isEmpty)
        // Still in downloading, not committed.
        #expect(fm.fileExists(atPath: root.appending(path: "steamapps/downloading/999/game.bin").path))
        #expect(!fm.fileExists(atPath: root.appending(path: "steamapps/common/My Game").path))
    }

    @Test
    func sparsePreallocatedDownloadIsNotCommitted() throws {
        // Steam PRE-ALLOCATES depot files sparsely while downloading: logical
        // size looks complete long before the bytes exist. Committing then
        // would move a half-download into common/ and mark it installed —
        // the allocated-size check is what stands in the way.
        let root = try makeSteam(bytesToStage: 1_000_000, extractedBytes: 0)
        defer { try? fm.removeItem(at: root) }
        let appDir = root.appending(path: "steamapps/downloading/999")
        try fm.removeItem(at: appDir.appending(path: "game.bin"))
        let sparse = appDir.appending(path: "depot.resources")
        #expect(fm.createFile(atPath: sparse.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: 1_000_000)
        try handle.close()

        let sizes = SteamInstallCommitter.directorySizes(appDir)
        #expect(sizes.logical >= 1_000_000)     // looks complete…
        #expect(sizes.allocated < 1_000_000)    // …but isn't — the tell

        #expect(SteamInstallCommitter.commitStuckInstalls(steamRoot: root).isEmpty)
        // Left exactly where it was, still downloading.
        #expect(fm.fileExists(atPath: sparse.path))
        #expect(!fm.fileExists(atPath: root.appending(path: "steamapps/common/My Game").path))
    }

    @Test
    func mergesOverAStubInstallDir() throws {
        // A prior failed attempt left an empty common/<installdir> — commit
        // must merge the real files in, not choke on the existing dir.
        let root = try makeSteam(bytesToStage: 500, extractedBytes: 500)
        defer { try? fm.removeItem(at: root) }
        let dest = root.appending(path: "steamapps/common/My Game", directoryHint: .isDirectory)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: dest.appending(path: "leftover.txt"))

        let committed = SteamInstallCommitter.commitStuckInstalls(steamRoot: root)
        #expect(committed == ["My Game"])
        #expect(fm.fileExists(atPath: dest.appending(path: "game.bin").path))
    }
}
