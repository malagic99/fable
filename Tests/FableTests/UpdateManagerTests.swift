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
    private let fixture = """
    [
      {
        "tag_name": "11.10",
        "assets": [
          {"name": "wine-devel-11.10-osx64.tar.xz",
           "browser_download_url": "https://example.com/devel.tar.xz",
           "digest": "sha256:aaaa"},
          {"name": "wine-staging-11.10-osx64.tar.xz",
           "browser_download_url": "https://example.com/staging.tar.xz",
           "digest": "sha256:bbbb"}
        ]
      },
      {
        "tag_name": "11.0_2",
        "assets": [
          {"name": "wine-stable-11.0_2-osx64.tar.xz",
           "browser_download_url": "https://example.com/stable.tar.xz",
           "digest": "sha256:cccc"}
        ]
      }
    ]
    """

    @Test
    func picksNewestReleaseWithMatchingAsset() throws {
        let component = try UpdateManager.component(
            fromReleasesJSON: Data(fixture.utf8),
            assetPrefix: "wine-stable-",
            assetSuffix: "-osx64.tar.xz",
            displayName: "Wine Stable"
        )
        // 11.10 has no stable asset, so 11.0_2 wins.
        #expect(component?.version == "11.0_2")
        #expect(component?.sha256 == "cccc")
        #expect(component?.url.absoluteString == "https://example.com/stable.tar.xz")
    }

    @Test
    func returnsNilWhenNothingMatches() throws {
        let component = try UpdateManager.component(
            fromReleasesJSON: Data(fixture.utf8),
            assetPrefix: "dxmt-v",
            assetSuffix: ".tar.gz",
            displayName: "DXMT"
        )
        #expect(component == nil)
    }

    @Test
    func stripsTagVPrefix() throws {
        let json = """
        [{"tag_name": "v0.81", "assets": [
          {"name": "dxmt-v0.81-builtin.tar.gz",
           "browser_download_url": "https://example.com/dxmt.tar.gz",
           "digest": null}
        ]}]
        """
        let component = try UpdateManager.component(
            fromReleasesJSON: Data(json.utf8),
            assetPrefix: "dxmt-v",
            assetSuffix: "-builtin.tar.gz",
            displayName: "DXMT"
        )
        #expect(component?.version == "0.81")
        #expect(component?.sha256 == "")
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
