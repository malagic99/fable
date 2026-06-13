import Foundation
import Testing
@testable import Fable

@Suite struct WinetricksCatalogTests {
    /// Mirrors the upstream `w_metadata` shape: header line with slug +
    /// category, then continuation lines with title.
    private let sampleScript = """
        #!/bin/sh
        # winetricks fixture

        w_metadata amstream dlls \\
            title="MS amstream.dll" \\
            publisher="Microsoft" \\
            year="2011"

        w_metadata corefonts fonts \\
            title="MS Arial, Times New Roman, ..." \\
            publisher="Microsoft" \\
            year="2008"

        load_corefonts() { :; }

        w_metadata dotnet48 dlls \\
            title=".NET Framework 4.8" \\
            publisher="Microsoft" \\
            year="2019" \\
            media="download"

        # A bare w_metadata() function definition isn't a verb.
        w_metadata()
        {
            :
        }

        w_metadata 3dmark11 benchmarks \\
            title="3DMark 11"

        """

    @Test
    func parsesVerbsWithCategoryAndTitle() {
        let verbs = WinetricksCatalog.verbs(fromScript: sampleScript)
        #expect(verbs.map(\.id) == ["amstream", "corefonts", "dotnet48", "3dmark11"])

        let dotnet = try? #require(verbs.first { $0.id == "dotnet48" })
        #expect(dotnet?.category == .dlls)
        #expect(dotnet?.title == ".NET Framework 4.8")
    }

    @Test
    func ignoresFunctionDefinitionForm() {
        let verbs = WinetricksCatalog.verbs(fromScript: sampleScript)
        // The `w_metadata()` block has no slug — must not be parsed as a verb.
        #expect(!verbs.contains { $0.id.isEmpty })
        #expect(verbs.allSatisfy { !$0.id.contains("(") })
    }

    @Test
    func searchTextLowercasesIdAndTitle() {
        let verbs = WinetricksCatalog.verbs(fromScript: sampleScript)
        let dotnet = try? #require(verbs.first { $0.id == "dotnet48" })
        #expect(dotnet?.searchText.contains("dotnet48") == true)
        #expect(dotnet?.searchText.contains(".net framework 4.8") == true)
    }

    @Test
    func categoryPickerCoversAllRawValues() {
        // If upstream adds a new category, parsing it should fail silently
        // (returns nil) rather than crash — that's by design.
        let unknown = """
            w_metadata foo galaxy \\
                title="From the Future"
            """
        let verbs = WinetricksCatalog.verbs(fromScript: unknown)
        #expect(verbs.isEmpty)
    }

    @Test
    func bottleRoundTripsInstalledVerbs() throws {
        var bottle = Bottle(name: "B")
        bottle.installedWinetricksVerbs = ["corefonts", "dotnet48"]
        let data = try JSONEncoder().encode(bottle)
        let decoded = try JSONDecoder().decode(Bottle.self, from: data)
        #expect(decoded.installedWinetricksVerbs == ["corefonts", "dotnet48"])
    }

    @Test
    func legacyBottleWithoutVerbsDecodesToEmptySet() throws {
        let legacyJSON = """
        {"id": "\(UUID().uuidString)", "name": "Old", "windowsVersion": "win10",
         "createdAt": 700000000, "status": "ready", "games": [],
         "graphicsBackend": "off"}
        """
        let bottle = try JSONDecoder().decode(Bottle.self, from: Data(legacyJSON.utf8))
        #expect(bottle.installedWinetricksVerbs.isEmpty)
    }
}
