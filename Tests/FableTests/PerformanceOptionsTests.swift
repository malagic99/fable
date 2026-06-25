import Foundation
import Testing
@testable import Fable

@Suite struct PerformanceOptionsTests {
    @Test
    func defaultsAreAllOff() {
        let perf = PerformanceOptions()
        #expect(!perf.metalHUD)
        #expect(!perf.metalFXUpscaling)
        #expect(perf.frameRateCap == nil)
        #expect(perf.backendAgnosticEnvironment().isEmpty)
        #expect(perf.gptkEnvironment().isEmpty)
    }

    @Test
    func metalHUDProducesEnvVar() {
        var perf = PerformanceOptions()
        perf.metalHUD = true
        #expect(perf.backendAgnosticEnvironment()["MTL_HUD_ENABLED"] == "1")
    }

    @Test
    func gptkEnvironmentRoutesUpscalerAndFrameRate() {
        var perf = PerformanceOptions()
        perf.metalFXUpscaling = true
        perf.frameRateCap = 60
        let env = perf.gptkEnvironment()
        #expect(env["D3DM_USE_METALFX_UPSCALER"] == "1")
        #expect(env["D3DM_FRAME_RATE_LIMIT"] == "60")
    }

    @Test
    func recommendedDefaultsPerBackend() {
        // Heavy D3DMetal path: cap + upscale so AAA titles hold steady FPS.
        for backend in [GraphicsBackend.sikarugir, .gptk] {
            let rec = PerformanceOptions.recommended(for: backend)
            #expect(rec.frameRateCap == 60)
            #expect(rec.metalFXUpscaling)
        }
        // Translation backends: cap only (MetalFX is D3DMetal-only).
        for backend in [GraphicsBackend.dxmt, .dxvk] {
            let rec = PerformanceOptions.recommended(for: backend)
            #expect(rec.frameRateCap == 60)
            #expect(!rec.metalFXUpscaling)
        }
        // Bare backends keep defaults.
        #expect(PerformanceOptions.recommended(for: .off) == PerformanceOptions())
        #expect(PerformanceOptions.recommended(for: .crossover) == PerformanceOptions())
    }

    @Test
    func legacyBottleWithoutPerformanceMigratesFrameRateCap() throws {
        let legacyJSON = """
        {"id": "\(UUID().uuidString)", "name": "Old", "windowsVersion": "win10",
         "createdAt": 700000000, "status": "ready", "games": [],
         "graphicsBackend": "dxmt",
         "dxmtConfig": {"maxFrameRate": 90, "logLevel": "error"}}
        """
        let bottle = try JSONDecoder().decode(Bottle.self, from: Data(legacyJSON.utf8))
        #expect(bottle.performance.frameRateCap == 90)
        #expect(!bottle.performance.metalHUD)
        #expect(!bottle.performance.metalFXUpscaling)
    }
}
