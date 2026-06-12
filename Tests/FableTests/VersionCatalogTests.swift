import Foundation
import Testing
@testable import Fable

@Suite struct VersionCatalogTests {
    @Test
    func bundledCatalogDecodesAndPinsWineAndDXMT() throws {
        let catalog = try VersionCatalog.loadBundled()

        let wine = try #require(catalog.wine)
        #expect(wine.version == "11.0")

        let dxmt = try #require(catalog.dxmt)
        #expect(dxmt.version == "0.80")
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
