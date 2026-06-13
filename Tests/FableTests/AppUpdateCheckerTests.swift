import Foundation
import Testing
@testable import Fable

@Suite struct AppUpdateCheckerTests {
    private let releaseJSON = """
    [
      {
        "tag_name": "v0.3.0",
        "name": "Fable 0.3.0",
        "html_url": "https://github.com/markoalagic/fable/releases/tag/v0.3.0",
        "body": "GPTK 4 support.",
        "draft": false,
        "prerelease": false
      },
      {
        "tag_name": "v0.2.0",
        "name": "Fable 0.2.0",
        "html_url": "https://github.com/markoalagic/fable/releases/tag/v0.2.0",
        "body": "DXMT 0.80.",
        "draft": false,
        "prerelease": false
      }
    ]
    """

    @Test
    func parsesNewestNonPrereleaseAsLatest() throws {
        let data = Data(releaseJSON.utf8)
        let release = try #require(try AppUpdateChecker.parseLatest(fromReleasesJSON: data))
        #expect(release.tagName == "v0.3.0")
        #expect(release.version == "0.3.0")
        #expect(release.url.absoluteString.hasSuffix("v0.3.0"))
        #expect(release.body.contains("GPTK"))
    }

    @Test
    func skipsDraftAndPrereleaseEntries() throws {
        let json = """
        [
          {"tag_name": "v0.4.0-beta", "name": "Beta", "html_url": "https://example.com/a", "draft": false, "prerelease": true},
          {"tag_name": "v0.3.5-draft", "name": "Draft", "html_url": "https://example.com/b", "draft": true, "prerelease": false},
          {"tag_name": "v0.3.0", "name": "Stable", "html_url": "https://example.com/c", "draft": false, "prerelease": false}
        ]
        """
        let release = try #require(try AppUpdateChecker.parseLatest(
            fromReleasesJSON: Data(json.utf8)
        ))
        #expect(release.tagName == "v0.3.0")
    }

    @Test
    func returnsNilForEmptyResponse() throws {
        let release = try AppUpdateChecker.parseLatest(fromReleasesJSON: Data("[]".utf8))
        #expect(release == nil)
    }

    @Test
    func returnsNilWhenOnlyDraftsAndPrereleases() throws {
        let json = """
        [
          {"tag_name": "v0.4.0-beta", "name": "Beta", "html_url": "https://example.com/a", "draft": false, "prerelease": true},
          {"tag_name": "v0.3.5-draft", "name": "Draft", "html_url": "https://example.com/b", "draft": true, "prerelease": false}
        ]
        """
        let release = try AppUpdateChecker.parseLatest(fromReleasesJSON: Data(json.utf8))
        #expect(release == nil)
    }

    @Test
    func stripsLeadingVFromTag() throws {
        let json = """
        [{"tag_name": "1.2.3", "name": "Plain", "html_url": "https://example.com/", "draft": false, "prerelease": false}]
        """
        let release = try #require(try AppUpdateChecker.parseLatest(
            fromReleasesJSON: Data(json.utf8)
        ))
        #expect(release.version == "1.2.3")
        #expect(release.tagName == "1.2.3")
    }

    @Test
    func versionComparatorRecognizesNewerReleases() {
        // Pinned baseline avoids depending on Bundle.main, which in the
        // test runner is the swift-testing harness, not Fable.app.
        let baseline = "0.1.0"
        #expect(VersionCompare.isNewer("0.2.0", than: baseline))
        #expect(VersionCompare.isNewer("0.1.1", than: baseline))
        #expect(!VersionCompare.isNewer("0.0.9", than: baseline))
        #expect(!VersionCompare.isNewer("0.1.0", than: baseline))
    }

    @Test
    func currentVersionFallsBackToZeroOutsideAppBundle() {
        // Under the test runner there's no CFBundleShortVersionString —
        // we expect the documented "0" fallback so update checks still
        // show banners in dev builds.
        #expect(AppUpdateChecker.currentVersion == "0")
    }
}
