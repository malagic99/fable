import Foundation
import Testing

@testable import Fable

@Suite("D3DMetal source selection")
struct D3DMetalSourceTests {

    /// GPTK 4's framework exports `GFXTOSInterface::IUnknownIface`; Sikarugir's
    /// bundled one doesn't. That single symbol is how Fable tells a framework
    /// new enough to pair with modern Wine from one that isn't — the component
    /// directory name can't be trusted, since a directory labelled `3.0-3` can
    /// already hold GPTK 4's framework after a hand-injection.
    @Test
    func detectsGPTK4ByItsExtraExport() throws {
        let dir = URL.temporaryTestDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let gptk4 = dir.appending(path: "gptk4-D3DMetal")
        try Data("...__ZN15GFXTOSInterface13IUnknownIfaceE...".utf8).write(to: gptk4)
        #expect(SikarugirManager.exportsGPTK4Marker(gptk4))

        let older = dir.appending(path: "sikarugir-D3DMetal")
        try Data("...__ZN15GFXTOSInterface7AdapterE...".utf8).write(to: older)
        #expect(!SikarugirManager.exportsGPTK4Marker(older))
    }

    @Test
    func missingFrameworkIsNotMistakenForGPTK4() {
        let absent = URL(filePath: "/nonexistent/D3DMetal")
        #expect(!SikarugirManager.exportsGPTK4Marker(absent))
    }

    @Test
    func sourceRoundTripsThroughItsMarkerValue() {
        #expect(SikarugirManager.D3DMetalSource(rawValue: "gptk4") == .gptk4)
        #expect(SikarugirManager.D3DMetalSource(rawValue: "sikarugir") == .sikarugir)
        // An unrecognised marker must not read as the experimental pairing.
        #expect(SikarugirManager.D3DMetalSource(rawValue: "something-else") == nil)
    }

    /// The experimental pairing has to be opt-in: a fresh install must run the
    /// combination Sikarugir actually tests.
    @Test
    func defaultSettingIsTheTestedPairing() {
        #expect(AppSettings().sikarugirUsesGPTK4D3DMetal == false)
    }

    @Test
    func settingSurvivesAnEncodeDecodeRoundTrip() throws {
        var settings = AppSettings()
        settings.sikarugirUsesGPTK4D3DMetal = true
        let restored = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.sikarugirUsesGPTK4D3DMetal)
    }

    /// Configs written before this option existed must decode, and must decode
    /// to the safe default rather than failing or enabling the swap.
    @Test
    func olderConfigWithoutTheKeyDecodesToOff() throws {
        let json = Data(#"{"advancedMode":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(settings.sikarugirUsesGPTK4D3DMetal == false)
        #expect(settings.advancedMode)
    }
}

private extension URL {
    static func temporaryTestDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "fable-d3dmetal-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
