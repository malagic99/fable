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
