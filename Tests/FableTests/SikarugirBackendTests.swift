import Foundation
import Testing
@testable import Fable

@Suite struct SikarugirBackendTests {
    @Test
    func sikarugirIsACaseInTheBackendEnum() {
        #expect(GraphicsBackend.allCases.contains(.sikarugir))
        #expect(GraphicsBackend.allCases.count == 6)
    }

    @Test
    func sikarugirHasDisplayAndShortName() {
        #expect(GraphicsBackend.sikarugir.shortName == "Sikarugir")
        // Display name leads with the modern flagship's headline use cases.
        let display = GraphicsBackend.sikarugir.displayName
        #expect(display.contains("Sikarugir"))
        #expect(display.contains("DirectX 12"))
        #expect(display.contains("Steam"))
    }

    @Test
    func sikarugirRoundTripsThroughBottleJSON() throws {
        var bottle = Bottle(name: "Test")
        bottle.graphicsBackend = .sikarugir
        let data = try JSONEncoder().encode(bottle)
        let decoded = try JSONDecoder().decode(Bottle.self, from: data)
        #expect(decoded.graphicsBackend == .sikarugir)
    }

    @Test
    func launchEnvironmentForcesD3DMetalBuiltins() {
        let env = SikarugirManager.launchEnvironment(baseOverrides: "mscoree,mshtml=", bundleRoot: nil)
        let overrides = env["WINEDLLOVERRIDES"] ?? ""
        // D3DMetal-backed DLLs must be builtin so prefix natives don't win.
        #expect(overrides.contains("d3d11"))
        #expect(overrides.contains("d3d12"))
        #expect(overrides.contains("dxgi"))
        #expect(overrides.contains("=b"))
        // msync, not esync: esync spin-polls IOCP under Rosetta and stalls
        // Steam downloads (411%→32% CPU when switched). msync blocks via Mach.
        #expect(env["WINEMSYNC"] == "1")
        #expect(env["WINEESYNC"] == nil)
    }

    @Test
    func launchEnvironmentWiresD3DMetalFrameworkWhenPresent() throws {
        // Build a fake bundle with lib/external/D3DMetal.framework + libd3dshared.
        let tmp = URL(filePath: "/tmp/FableSikTest-\(UUID().uuidString)")
        let external = tmp.appending(path: "lib/external")
        let fwDir = external.appending(path: "D3DMetal.framework/Versions/A")
        try FileManager.default.createDirectory(at: fwDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("x".utf8).write(to: fwDir.appending(path: "D3DMetal"))
        try Data("x".utf8).write(to: external.appending(path: "libd3dshared.dylib"))

        let env = SikarugirManager.launchEnvironment(baseOverrides: "", bundleRoot: tmp)
        // The load-bearing env: without D3DMETAL_FRAMEWORK_PATH the d3dmetal
        // dispatch can't dlopen D3DMetal → no Metal surface → black square.
        #expect(env["D3DMETAL_FRAMEWORK_PATH"] == fwDir.appending(path: "D3DMetal").path)
        #expect(env["CX_APPLEGPTK_LIBD3DSHARED_PATH"] == external.appending(path: "libd3dshared.dylib").path)
    }

    @Test
    func launchEnvironmentOmitsD3DMetalPathsWhenBundleMissing() {
        // No bundle root → no framework env (graceful, e.g. unit tests).
        let env = SikarugirManager.launchEnvironment(baseOverrides: "", bundleRoot: nil)
        #expect(env["D3DMETAL_FRAMEWORK_PATH"] == nil)
        #expect(env["CX_APPLEGPTK_LIBD3DSHARED_PATH"] == nil)
    }

    @Test
    func builtinDLLsCoverTheD3DMetalSet() {
        let set = Set(SikarugirManager.builtinDLLs)
        #expect(set.contains("d3d11"))
        #expect(set.contains("d3d12"))
        #expect(set.contains("dxgi"))
    }
}

@Suite struct SikarugirRecommendationTests {
    private func finding(id: String, severity: CompatibilityFinding.Severity = .caveat) -> CompatibilityFinding {
        CompatibilityFinding(id: id, severity: severity, title: id, detail: "", suggestion: "")
    }

    @Test
    func streamlinePrefersSikarugirOverCrossOverWhenBothAvailable() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "streamline")],
            crossOverAvailable: true,
            sikarugirAvailable: true
        )
        #expect(result == .sikarugir, "Sikarugir is free with the same capability — wins over paid CrossOver")
    }

    @Test
    func streamlineFallsToCrossOverWhenNoSikarugir() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "streamline")],
            crossOverAvailable: true,
            sikarugirAvailable: false
        )
        #expect(result == .crossover)
    }

    @Test
    func streamlineFallsToDXVKWhenNeitherD3DMetalStackPresent() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "streamline")],
            crossOverAvailable: false,
            sikarugirAvailable: false
        )
        #expect(result == .dxvk)
    }

    @Test
    func directStorageAlsoRoutesToSikarugirWhenAvailable() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "directstorage")],
            crossOverAvailable: false,
            sikarugirAvailable: true
        )
        #expect(result == .sikarugir)
    }

    @Test
    func knownBlockerStillSuppressesEvenWithSikarugir() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "anticheat-eac", severity: .knownBlocker)],
            crossOverAvailable: true,
            sikarugirAvailable: true
        )
        #expect(result == nil)
    }

    @Test
    func cleanInstallStillRecommendsGPTKRegardlessOfSikarugir() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [],
            crossOverAvailable: true,
            sikarugirAvailable: true
        )
        #expect(result == .gptk, "No D3D12 markers → GPTK default; Sikarugir reserved for the hard cases")
    }

    @Test
    func realFirstLightScenarioRoutesToSikarugir() {
        // The actual 007 First Light fingerprint, with Sikarugir present.
        let result = CompatibilityScanner.recommendedBackend(
            for: [
                finding(id: "streamline"),
                finding(id: "directstorage"),
                finding(id: "goldberg-emu", severity: .info),
                finding(id: "goldberg-no-interfaces"),
                finding(id: "repack-install", severity: .info),
            ],
            crossOverAvailable: true,
            sikarugirAvailable: true
        )
        #expect(result == .sikarugir, "The whole saga's resolution: First Light → Sikarugir")
    }
}
