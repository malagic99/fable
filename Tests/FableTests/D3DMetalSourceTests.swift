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

@Suite("D3DMetal identity")
struct D3DMetalIdentityTests {

    private func write(_ contents: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "d3dmetal-\(UUID().uuidString)")
        try? Data(contents.utf8).write(to: url)
        return url
    }

    /// The version label on the enclosing directory says nothing about the
    /// framework inside — Fable can overlay a newer renderer onto an installed
    /// toolkit, so generation has to come from the binary itself.
    @Test
    func generationComesFromExportsNotTheLabel() {
        let modern = write("...__ZN15GFXTOSInterface13IUnknownIfaceE...")
        let older = write("...__ZN15GFXTOSInterface7AdapterE...")
        defer {
            try? FileManager.default.removeItem(at: modern)
            try? FileManager.default.removeItem(at: older)
        }
        #expect(D3DMetalIdentity.generation(of: modern) == .gptk4OrNewer)
        #expect(D3DMetalIdentity.generation(of: older) == .legacy)
    }

    /// Absent is distinct from legacy: a caller deciding whether to offer a
    /// pairing must not treat "no framework" as "an old framework".
    @Test
    func missingBinaryReportsNoGeneration() {
        #expect(D3DMetalIdentity.generation(of: URL(filePath: "/nope/D3DMetal")) == nil)
    }
}

@Suite("Sikarugir setup status")
struct SikarugirSetupStatusTests {

    /// The state that used to be invisible: Sikarugir on the Mac but its
    /// engine not downloaded yet, because it fetches that on first launch.
    /// This previously read as `.missing`, sending someone off to re-download
    /// an app they already had instead of telling them to open it.
    @Test
    func installedButNeverOpenedIsItsOwnState() {
        let status = SikarugirManager.status(
            discovered: false, available: nil, installed: nil, sikarugirPresent: true)
        #expect(status == .incomplete)
    }

    @Test
    func nothingOnTheMacIsStillMissing() {
        let status = SikarugirManager.status(
            discovered: false, available: nil, installed: nil, sikarugirPresent: false)
        #expect(status == .missing)
    }

    @Test
    func discoveredButNotSetUpOffersSetup() {
        let status = SikarugirManager.status(
            discovered: true, available: "WS12WineSikarugir10.0_4", installed: nil,
            sikarugirPresent: true)
        #expect(status == .notInstalled(available: "WS12WineSikarugir10.0_4"))
    }

    @Test
    func matchingVersionsAreReady() {
        let v = "WS12WineSikarugir10.0_4"
        #expect(SikarugirManager.status(
            discovered: true, available: v, installed: v, sikarugirPresent: true)
            == .ready(version: v))
    }

    /// Sikarugir publishes no releases and no downloadable app — it exists
    /// only as a Homebrew cask behind a `brew trust` for its tap. Pointing a
    /// non-technical user at its GitHub page lands them on an empty Releases
    /// tab, which is what shipped in v0.23.5.
    @Test
    func installUsesTheHomebrewCaskSikarugirActuallyShips() {
        let commands = SikarugirInstaller.commands
        #expect(commands.count == 2)
        // The tap has to be trusted before its cask will install.
        #expect(commands[0].contains("trust"))
        #expect(commands[1].contains("--cask"))
        #expect(commands.allSatisfy { $0.hasPrefix("brew ") })
        #expect(commands.contains { $0.contains("Sikarugir-App/sikarugir") })
    }

    /// Without Homebrew there is nothing to install from, so the flow has to
    /// say so rather than offering an action that cannot work.
    @Test
    func homebrewDetectionDrivesWhatIsOffered() {
        #expect(SikarugirInstaller.isHomebrewInstalled == (SikarugirInstaller.homebrew != nil))
    }
}
