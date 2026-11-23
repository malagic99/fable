import Foundation
import Testing
@testable import Fable

@Suite struct VersionCompareTests {
    @Test
    func comparesComponentVersions() {
        #expect(VersionCompare.isNewer("11.10", than: "11.0_1"))
        #expect(VersionCompare.isNewer("11.0_2", than: "11.0_1"))
        #expect(VersionCompare.isNewer("0.81", than: "0.80"))
        #expect(VersionCompare.isNewer("1.0.1", than: "1.0"))
        #expect(!VersionCompare.isNewer("11.0_1", than: "11.0_1"))
        #expect(!VersionCompare.isNewer("11.0_1", than: "11.10"))
        #expect(!VersionCompare.isNewer("0.80", than: "0.80"))
        // Tag prefixes and release-candidate suffixes.
        #expect(VersionCompare.isNewer("v0.81", than: "0.80"))
        #expect(VersionCompare.isNewer("11.0", than: "11.0-rc1"))
    }
}

@Suite struct UpdateManagerParsingTests {
    private static let shaA = String(repeating: "a", count: 64)
    private static let shaB = String(repeating: "b", count: 64)
    private static let shaC = String(repeating: "c", count: 64)

    private let fixture = """
    [
      {
        "prerelease": false, "draft": false, "published_at": "2026-01-01T00:00:00Z", "tag_name": "11.10",
        "assets": [
          {"name": "wine-devel-11.10-osx64.tar.xz",
           "browser_download_url": "https://github.com/o/r/releases/download/t/devel.tar.xz",
           "digest": "sha256:\(shaA)"},
          {"name": "wine-staging-11.10-osx64.tar.xz",
           "browser_download_url": "https://github.com/o/r/releases/download/t/staging.tar.xz",
           "digest": "sha256:\(shaB)"}
        ]
      },
      {
        "prerelease": false, "draft": false, "published_at": "2026-01-01T00:00:00Z", "tag_name": "11.0_2",
        "assets": [
          {"name": "wine-stable-11.0_2-osx64.tar.xz",
           "browser_download_url": "https://github.com/o/r/releases/download/t/stable.tar.xz",
           "digest": "sha256:\(shaC)"}
        ]
      }
    ]
    """

    @Test
    func picksNewestReleaseWithMatchingAsset() throws {
        let component = try UpdateManager.component(
            fromReleasesJSON: Data(fixture.utf8), repo: "o/r",
            assetPrefix: "wine-stable-",
            assetSuffix: "-osx64.tar.xz",
            displayName: "Wine Stable"
        )
        // 11.10 has no stable asset, so 11.0_2 wins.
        #expect(component?.version == "11.0_2")
        #expect(component?.sha256 == Self.shaC)
        #expect(component?.url.absoluteString == "https://github.com/o/r/releases/download/t/stable.tar.xz")
    }

    /// One release per entry, newest first: (tag, prerelease, draft, published, url).
    private func releases(_ entries: [(String, Bool?, Bool?, String?, String)]) -> Data {
        let items = entries.map { tag, pre, draft, published, url in
            var fields = [#""tag_name": "\#(tag)""#]
            if let pre { fields.append(#""prerelease": \#(pre)"#) }
            if let draft { fields.append(#""draft": \#(draft)"#) }
            if let published { fields.append(#""published_at": "\#(published)""#) }
            fields.append(#""assets": [{"name": "dxmt-\#(tag)-builtin.tar.gz", "browser_download_url": "\#(url)", "digest": "sha256:\#(Self.shaA)"}]"#)
            return "{" + fields.joined(separator: ", ") + "}"
        }
        return Data(("[" + items.joined(separator: ",") + "]").utf8)
    }

    private func pick(_ data: Data, now: Date = ISO8601DateFormatter().date(from: "2026-11-23T12:00:00Z")!) throws -> String? {
        try UpdateManager.component(fromReleasesJSON: data, repo: "3Shain/dxmt", assetPrefix: "dxmt-v",
                                    assetSuffix: "-builtin.tar.gz", displayName: "DXMT", now: now)?.version
    }

    private let own = "https://github.com/3Shain/dxmt/releases/download/x/f.tar.gz"
    private let old = "2026-10-01T00:00:00Z"

    @Test
    func preReleasesAndDraftsAreNeverOffered() throws {
        #expect(try pick(releases([
            ("v0.83", true, false, old, own),
            ("v0.82", false, true, old, own),
            ("v0.81", nil, false, old, own),   // flag missing: treated as a pre-release
            ("v0.80", false, false, old, own),
        ])) == "0.80")
    }

    @Test
    func aReleaseIsOfferedOnlyAfterAWeek() throws {
        let data = releases([
            ("v0.82", false, false, "2026-11-20T12:00:00Z", own), // 3 days old
            ("v0.81", false, false, "2026-11-16T11:00:00Z", own), // 7 days, 1 hour
            ("v0.80", false, false, old, own),
        ])
        #expect(try pick(data) == "0.81")
        // A week later the newest is old enough too.
        #expect(try pick(data, now: ISO8601DateFormatter().date(from: "2026-11-28T00:00:00Z")!) == "0.82")
        // A release with no publication date has no known age.
        #expect(try pick(releases([("v0.82", false, false, nil, own)])) == nil)
    }

    @Test
    func onlyTheProjectsOwnReleaseFilesAreOffered() throws {
        #expect(try pick(releases([
            ("v0.83", false, false, old, "https://example.com/3Shain/dxmt/releases/download/x/f.tar.gz"),
            ("v0.82", false, false, old, "https://github.com/someone-else/dxmt/releases/download/x/f.tar.gz"),
            ("v0.81", false, false, old, "http://github.com/3Shain/dxmt/releases/download/x/f.tar.gz"),
            ("v0.80", false, false, old, "https://github.com/3Shain/dxmt/releases/download/v0.80/f.tar.gz"),
        ])) == "0.80")
    }

    @Test
    func returnsNilWhenNothingMatches() throws {
        let component = try UpdateManager.component(
            fromReleasesJSON: Data(fixture.utf8), repo: "o/r",
            assetPrefix: "dxmt-v",
            assetSuffix: ".tar.gz",
            displayName: "DXMT"
        )
        #expect(component == nil)
    }

    @Test
    func stripsTagVPrefix() throws {
        let json = """
        [{"prerelease": false, "draft": false, "published_at": "2026-01-01T00:00:00Z", "tag_name": "v0.81", "assets": [
          {"name": "dxmt-v0.81-builtin.tar.gz",
           "browser_download_url": "https://github.com/o/r/releases/download/t/dxmt.tar.gz",
           "digest": "sha256:\(Self.shaA)"}
        ]}]
        """
        let component = try UpdateManager.component(
            fromReleasesJSON: Data(json.utf8), repo: "o/r",
            assetPrefix: "dxmt-v",
            assetSuffix: "-builtin.tar.gz",
            displayName: "DXMT"
        )
        #expect(component?.version == "0.81")
        #expect(component?.sha256 == Self.shaA)
    }

    @Test
    func skipsReleasesWithoutAUsableDigest() throws {
        // Newest first: no digest, then a non-SHA-256 one, then a truncated
        // one — none can be verified, so the update offered is v0.80.
        let json = """
        [{"prerelease": false, "draft": false, "published_at": "2026-01-01T00:00:00Z", "tag_name": "v0.83", "assets": [
           {"name": "dxmt-v0.83-builtin.tar.gz",
            "browser_download_url": "https://github.com/o/r/releases/download/t/83.tar.gz", "digest": null}]},
         {"prerelease": false, "draft": false, "published_at": "2026-01-01T00:00:00Z", "tag_name": "v0.82", "assets": [
           {"name": "dxmt-v0.82-builtin.tar.gz",
            "browser_download_url": "https://github.com/o/r/releases/download/t/82.tar.gz",
            "digest": "sha512:\(Self.shaA)"}]},
         {"prerelease": false, "draft": false, "published_at": "2026-01-01T00:00:00Z", "tag_name": "v0.81", "assets": [
           {"name": "dxmt-v0.81-builtin.tar.gz",
            "browser_download_url": "https://github.com/o/r/releases/download/t/81.tar.gz", "digest": "sha256:abcd"}]},
         {"prerelease": false, "draft": false, "published_at": "2026-01-01T00:00:00Z", "tag_name": "v0.80", "assets": [
           {"name": "dxmt-v0.80-builtin.tar.gz",
            "browser_download_url": "https://github.com/o/r/releases/download/t/80.tar.gz",
            "digest": "sha256:\(Self.shaB)"}]}]
        """
        let component = try UpdateManager.component(
            fromReleasesJSON: Data(json.utf8), repo: "o/r",
            assetPrefix: "dxmt-v",
            assetSuffix: "-builtin.tar.gz",
            displayName: "DXMT"
        )
        #expect(component?.version == "0.80")
        #expect(component?.sha256 == Self.shaB)

        // And when no release can be verified, nothing is offered at all.
        let unverifiable = """
        [{"prerelease": false, "draft": false, "published_at": "2026-01-01T00:00:00Z", "tag_name": "v0.83", "assets": [
           {"name": "dxmt-v0.83-builtin.tar.gz",
            "browser_download_url": "https://github.com/o/r/releases/download/t/83.tar.gz"}]}]
        """
        #expect(try UpdateManager.component(
            fromReleasesJSON: Data(unverifiable.utf8), repo: "o/r",
            assetPrefix: "dxmt-v",
            assetSuffix: "-builtin.tar.gz",
            displayName: "DXMT"
        ) == nil)
    }
}

@Suite struct DependencyCatalogTests {
    @Test
    func catalogEntriesAreWellFormed() {
        #expect(!DependencyCatalog.all.isEmpty)
        for dependency in DependencyCatalog.all {
            #expect(dependency.url.scheme == "https")
            #expect(!dependency.detectionPath.isEmpty)
            #expect(!dependency.name.isEmpty)
        }
        // ids unique
        let ids = DependencyCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
