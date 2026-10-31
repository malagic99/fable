import Foundation
import Testing
@testable import Fable

@Suite struct VersionCatalogTests {
    @Test
    func bundledCatalogDecodesAndPinsWineAndDXMT() throws {
        let catalog = try VersionCatalog.loadBundled()

        let wine = try #require(catalog.wine)
        #expect(wine.version == "11.10_1")
        #expect(!wine.sha256.isEmpty, "Wine checksum must be pinned")

        let dxmt = try #require(catalog.dxmt)
        #expect(dxmt.version == "0.80")
        #expect(!dxmt.sha256.isEmpty, "DXMT checksum must be pinned")
    }

    @Test
    func everyBundledComponentCarriesARealSHA256() throws {
        // Installs refuse anything else, so a bad pin here would break a
        // first-run download rather than skip its check.
        for (id, component) in try VersionCatalog.loadBundled().components {
            #expect(ChecksumVerifier.isPinned(component.sha256), Comment(rawValue: id))
        }
    }

    @Test
    func decodingFromData() throws {
        let json = """
        {
            "components": {
                "wine": {
                    "name": "Wine",
                    "version": "11.0",
                    "url": "https://example.com/wine.tar.xz",
                    "sha256": "abc123"
                }
            }
        }
        """
        let catalog = try VersionCatalog.load(from: Data(json.utf8))
        #expect(catalog.wine?.sha256 == "abc123")
        #expect(catalog.dxmt == nil)
    }
}
