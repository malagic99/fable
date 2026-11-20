import Foundation
import Testing
@testable import Fable

/// Security scan 2026-11-20, findings 1 and 3: values in Steam's files inside
/// a bottle are untrusted — any Windows program can write them, and they
/// arrive in shared bottles. Opening a bottle runs the stuck-install
/// committer, so these must hold without launching anything.
@Suite("Steam file safety")
struct SteamFileSafetyTests {

    /// A fake bottle: Steam with one fully downloaded, uncommitted app, and a
    /// file outside Steam standing in for something in the user's home folder.
    private struct Fixture {
        let root: URL
        let steamRoot: URL
        let steamapps: URL
        let appDir: URL
        let outsideFile: URL

        init(installdir: String) throws {
            let fm = FileManager.default
            root = fm.temporaryDirectory.appending(path: "fable-steamsafety-\(UUID().uuidString)", directoryHint: .isDirectory)
            steamRoot = root.appending(path: "bottle/drive_c/Steam", directoryHint: .isDirectory)
            steamapps = steamRoot.appending(path: "steamapps", directoryHint: .isDirectory)
            appDir = steamapps.appending(path: "downloading/123", directoryHint: .isDirectory)
            try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: steamapps.appending(path: "common"), withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 65_536).write(to: appDir.appending(path: "victim.txt"))
            let outside = root.appending(path: "outside", directoryHint: .isDirectory)
            try fm.createDirectory(at: outside, withIntermediateDirectories: true)
            outsideFile = outside.appending(path: "victim.txt")
            try Data("ORIGINAL".utf8).write(to: outsideFile)
            try manifest(installdir: installdir).write(
                to: steamapps.appending(path: "appmanifest_123.acf"), atomically: true, encoding: .utf8)
        }

        func manifest(installdir: String) -> String {
            let escaped = installdir.replacingOccurrences(of: "\\", with: "\\\\")
            return "\"AppState\"\n{\n\t\"appid\"\t\t\"123\"\n\t\"name\"\t\t\"Game\"\n\t\"installdir\"\t\t\"\(escaped)\"\n\t\"StateFlags\"\t\t\"1026\"\n\t\"BytesToStage\"\t\t\"1\"\n}\n"
        }

        func commit() -> String? {
            SteamInstallCommitter.commitApp(appid: "123", appDir: appDir, steamapps: steamapps, steamRoot: steamRoot)
        }

        var outsideUntouched: Bool {
            (try? Data(contentsOf: outsideFile)) == Data("ORIGINAL".utf8)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    @Test(arguments: [
        "../../../../outside",      // climbs out to the fake home folder
        "..\\..\\..\\..\\outside",  // Windows-style separators
        "..",
        ".",
        "/absolute",
        "",
    ])
    func aFolderNameThatLeavesSteamIsRefused(_ installdir: String) throws {
        let fixture = try Fixture(installdir: installdir)
        defer { fixture.cleanUp() }
        #expect(fixture.commit() == nil)
        #expect(fixture.outsideUntouched)
        // The download is left where it was, for Steam to deal with.
        #expect(FileManager.default.fileExists(atPath: fixture.appDir.appending(path: "victim.txt").path))
    }

    @Test
    func aSymlinkedGameFolderLeadingOutIsRefused() throws {
        let fixture = try Fixture(installdir: "Game")
        defer { fixture.cleanUp() }
        try FileManager.default.createSymbolicLink(
            at: fixture.steamapps.appending(path: "common/Game"),
            withDestinationURL: fixture.outsideFile.deletingLastPathComponent())
        #expect(fixture.commit() == nil)
        #expect(fixture.outsideUntouched)
    }

    @Test
    func aSymlinkedCommonFolderLeadingOutIsRefused() throws {
        let fixture = try Fixture(installdir: "outside")
        defer { fixture.cleanUp() }
        let common = fixture.steamapps.appending(path: "common")
        try FileManager.default.removeItem(at: common)
        try FileManager.default.createSymbolicLink(at: common, withDestinationURL: fixture.root)
        #expect(fixture.commit() == nil)
        #expect(fixture.outsideUntouched)
    }

    @Test
    func anOrdinaryStuckInstallIsStillCommitted() throws {
        let fixture = try Fixture(installdir: "Game")
        defer { fixture.cleanUp() }
        #expect(fixture.commit() == "Game")
        #expect(FileManager.default.fileExists(
            atPath: fixture.steamapps.appending(path: "common/Game/victim.txt").path))
        #expect(fixture.outsideUntouched)
    }

    @Test
    func anOversizedManifestIsNotRead() throws {
        let fixture = try Fixture(installdir: "Game")
        defer { fixture.cleanUp() }
        let padded = fixture.manifest(installdir: "Game")
            + String(repeating: "/", count: SteamInstallCommitter.maxManifestBytes)
        try padded.write(to: fixture.steamapps.appending(path: "appmanifest_123.acf"), atomically: true, encoding: .utf8)
        #expect(fixture.commit() == nil)
    }

    @Test
    func folderNameRule() {
        #expect(SteamPaths.isSafeFolderName("CONTROL Resonant"))
        #expect(SteamPaths.isSafeFolderName("..hidden but fine"))
        for bad in ["", ".", "..", "a/b", "a\\b", "../x", "x\u{0}y"] {
            #expect(!SteamPaths.isSafeFolderName(bad), "\(bad)")
        }
    }

    // MARK: Parser depth

    private func nested(_ depth: Int) -> String {
        "\"AppState\"\n" + String(repeating: "{\"a\"", count: depth) + "\"x\"" + String(repeating: "}", count: depth)
    }

    @Test
    func nestingBeyondTheLimitIsRefusedNotParsed() {
        #expect(SteamKeyValues.parse(nested(SteamKeyValues.maxDepth - 1)) != nil)
        #expect(SteamKeyValues.parse(nested(SteamKeyValues.maxDepth + 5)) == nil)
    }

    /// The crash itself: a background task has a 512 KB stack, and 20,000
    /// nested blocks used to overflow it and kill Fable.
    @Test
    func deeplyNestedFileDoesNotCrashOnASmallStack() async {
        let text = nested(20_000)
        let finished: Bool = await withCheckedContinuation { continuation in
            let thread = Thread {
                _ = SteamKeyValues.parse(text)
                continuation.resume(returning: true)
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
        #expect(finished)
    }
}
