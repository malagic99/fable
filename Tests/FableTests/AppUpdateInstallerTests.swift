import Foundation
import Testing

@testable import Fable

@Suite("In-app update")
struct AppUpdateInstallerTests {

    /// The release JSON must yield the attached build, not just the page link.
    /// Without an asset there is nothing to install, which is why the banner
    /// falls back to the browser rather than offering a button that can't work.
    @Test
    func releaseCarriesItsDownloadableAsset() throws {
        let json = Data("""
        [{"tag_name":"v1.0.1","name":"Fable v1.0.1","html_url":"https://example.com/r",
          "body":"notes","draft":false,"prerelease":false,
          "assets":[{"name":"Fable-1.0.1.zip",
                     "browser_download_url":"https://example.com/Fable-1.0.1.zip",
                     "size":17694720}]}]
        """.utf8)
        let release = try #require(try AppUpdateChecker.parseLatest(fromReleasesJSON: json))
        #expect(release.version == "1.0.1")
        #expect(release.assetURL?.lastPathComponent == "Fable-1.0.1.zip")
        #expect(release.assetBytes == 17694720)
    }

    /// GitHub attaches source tarballs to every release; picking one of those
    /// would download something that isn't an app.
    @Test
    func sourceArchivesAreNotMistakenForTheApp() throws {
        let json = Data("""
        [{"tag_name":"v1.0.1","html_url":"https://example.com/r","draft":false,"prerelease":false,
          "assets":[{"name":"Source code.zip","browser_download_url":"https://example.com/src.zip","size":1},
                    {"name":"Fable-1.0.1.zip","browser_download_url":"https://example.com/app.zip","size":2}]}]
        """.utf8)
        let release = try #require(try AppUpdateChecker.parseLatest(fromReleasesJSON: json))
        #expect(release.assetURL?.absoluteString == "https://example.com/app.zip")
    }

    /// A release published without a build must not look installable.
    @Test
    func releaseWithoutAnAssetHasNothingToInstall() throws {
        let json = Data("""
        [{"tag_name":"v1.0.1","html_url":"https://example.com/r","draft":false,"prerelease":false,"assets":[]}]
        """.utf8)
        let release = try #require(try AppUpdateChecker.parseLatest(fromReleasesJSON: json))
        #expect(release.assetURL == nil)
    }

    /// Verification must reject anything that isn't this app before the
    /// installed copy is touched — a swap that happens first and checks second
    /// is how an update leaves someone with no working app.
    @Test
    func unpackingRejectsAnArchiveWithNoApp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "fable-update-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let notAnApp = dir.appending(path: "readme.txt")
        try Data("nothing here".utf8).write(to: notAnApp)
        let archive = dir.appending(path: "bundle.zip")
        _ = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", notAnApp.path, archive.path])

        await #expect(throws: AppUpdateError.self) {
            _ = try await AppUpdateInstaller.unpackAndVerify(
                archive: archive, expectedVersion: "1.0.1")
        }
    }

    /// Self-updating is only offered where it can actually work; a test-runner
    /// binary is not an app bundle, so this must be false here.
    @Test
    func selfUpdateIsNotOfferedOutsideAnAppBundle() {
        #expect(AppUpdateInstaller.installedLocation == nil)
        #expect(!AppUpdateInstaller.canSelfUpdate())
    }
}
