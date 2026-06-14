import Foundation
import Testing
@testable import Fable

@Suite struct NewBackendsTests {
    @Test
    func allFiveBackendsAreCaseIterable() {
        let all = GraphicsBackend.allCases
        #expect(all.contains(.off))
        #expect(all.contains(.dxmt))
        #expect(all.contains(.gptk))
        #expect(all.contains(.dxvk))
        #expect(all.contains(.crossover))
        #expect(all.count == 5)
    }

    @Test
    func everyBackendHasDisplayNameAndShortName() {
        for backend in GraphicsBackend.allCases {
            #expect(!backend.displayName.isEmpty)
            #expect(!backend.shortName.isEmpty)
        }
    }

    @Test
    func dxvkAndCrossoverRoundTripThroughJSON() throws {
        for backend in [GraphicsBackend.dxvk, .crossover] {
            var bottle = Bottle(name: "Test")
            bottle.graphicsBackend = backend
            let data = try JSONEncoder().encode(bottle)
            let decoded = try JSONDecoder().decode(Bottle.self, from: data)
            #expect(decoded.graphicsBackend == backend)
        }
    }

    @Test
    func legacyBottleWithoutDxvkBackendStillDecodes() throws {
        // A bottle written by v0.3.0 (which only knew off/dxmt/gptk)
        // must still load on a v0.4.0 build.
        let legacyJSON = """
        {"id": "\(UUID().uuidString)", "name": "Legacy", "windowsVersion": "win10",
         "createdAt": 700000000, "status": "ready", "games": [],
         "graphicsBackend": "dxmt"}
        """
        let bottle = try JSONDecoder().decode(Bottle.self, from: Data(legacyJSON.utf8))
        #expect(bottle.graphicsBackend == .dxmt)
    }
}

@Suite struct DXVKManagerTests {
    @Test
    func launchEnvironmentRoutesAllD3DDllsAsNative() {
        let env = DXVKManager.launchEnvironment(
            baseOverrides: "mscoree,mshtml=",
            frameRateCap: nil,
            logFile: nil
        )
        let overrides = try? #require(env["WINEDLLOVERRIDES"])
        #expect(overrides?.contains("d3d10core") == true)
        #expect(overrides?.contains("d3d11") == true)
        #expect(overrides?.contains("d3d12") == true)
        #expect(overrides?.contains("dxgi") == true)
        // `=n` means native — DXVK's DLLs in the prefix system32 win.
        #expect(overrides?.contains("=n") == true)
    }

    @Test
    func launchEnvironmentRespectsFrameRateCap() {
        let env = DXVKManager.launchEnvironment(
            baseOverrides: "",
            frameRateCap: 60,
            logFile: nil
        )
        #expect(env["DXVK_FRAME_RATE"] == "60")
    }

    @Test
    func launchEnvironmentNoFrameCapMeansNoEnvVar() {
        let env = DXVKManager.launchEnvironment(
            baseOverrides: "",
            frameRateCap: nil,
            logFile: nil
        )
        #expect(env["DXVK_FRAME_RATE"] == nil)
    }
}

@MainActor
@Suite struct CrossOverManagerTests {
    @Test
    func reportsNotInstalledWhenAppMissing() {
        // CrossOver may or may not be on the test machine, so we can't
        // assert "isInstalled == false" unconditionally. What we CAN
        // assert: the field is consistent with the on-disk reality.
        let manager = CrossOverManager()
        let onDisk = FileManager.default.fileExists(atPath: CrossOverManager.installPath.path)
        #expect(manager.isInstalled == onDisk)
    }

    @Test
    func wineBinaryThrowsWhenNotInstalled() {
        let manager = CrossOverManager()
        if !manager.isInstalled {
            #expect(throws: CrossOverError.self) {
                _ = try manager.wineBinary()
            }
        }
    }

    @Test
    func launchEnvironmentPassesOnlyBaseOverridesWhenSet() {
        let env = CrossOverManager.launchEnvironment(baseOverrides: "mscoree,mshtml=")
        #expect(env["WINEDLLOVERRIDES"] == "mscoree,mshtml=")
    }

    @Test
    func launchEnvironmentIsEmptyWhenNoBaseOverrides() {
        let env = CrossOverManager.launchEnvironment(baseOverrides: "")
        #expect(env.isEmpty)
    }
}

@Suite struct SmartBottleRecommendationTests {
    /// Helper: a Finding with just the id we care about for routing.
    private func finding(id: String, severity: CompatibilityFinding.Severity = .caveat) -> CompatibilityFinding {
        CompatibilityFinding(
            id: id, severity: severity, title: id, detail: "", suggestion: ""
        )
    }

    @Test
    func knownBlockerSuppressesAnyRecommendation() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "anticheat-eac", severity: .knownBlocker)],
            crossOverAvailable: true
        )
        #expect(result == nil, "Anti-cheat means no Wine path works, regardless of CrossOver")
    }

    @Test
    func streamlineRecommendsDXVKWithoutCrossOver() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "streamline")],
            crossOverAvailable: false
        )
        #expect(result == .dxvk)
    }

    @Test
    func streamlineRecommendsCrossOverWhenAvailable() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "streamline")],
            crossOverAvailable: true
        )
        #expect(result == .crossover, "CrossOver beats DXVK when present — same SEH win plus D3DMetal")
    }

    @Test
    func directStorageRecommendsCrossOverWhenAvailable() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "directstorage")],
            crossOverAvailable: true
        )
        #expect(result == .crossover)
    }

    @Test
    func cleanInstallRecommendsGPTK() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [],
            crossOverAvailable: false
        )
        #expect(result == .gptk)
    }

    @Test
    func infoOnlyFindingsStillRecommendGPTK() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [finding(id: "repack-install", severity: .info)],
            crossOverAvailable: false
        )
        #expect(result == .gptk, "Repack tag alone shouldn't push off GPTK")
    }

    @Test
    func combinedRealisticFirstLightFindingsRouteToDXVK() {
        let result = CompatibilityScanner.recommendedBackend(
            for: [
                finding(id: "streamline"),
                finding(id: "directstorage"),
                finding(id: "goldberg-emu", severity: .info),
                finding(id: "goldberg-no-interfaces"),
                finding(id: "repack-install", severity: .info),
            ],
            crossOverAvailable: false
        )
        #expect(result == .dxvk, "Today's 007 First Light scenario without CrossOver → DXVK")
    }
}
