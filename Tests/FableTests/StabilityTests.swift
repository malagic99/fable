import Foundation
import Testing
@testable import Fable

/// The rubber-mat policy: claim the cores, sample metrics only when visible,
/// and defer heavy background work while a game runs.
@Suite struct StabilityTests {

    @Test
    func gamesClaimThePerformanceCores() {
        #expect(Stability.gameQoS == .userInteractive)
    }

    @Test
    func metricsSampleOnlyWhenFableIsFrontmost() {
        #expect(Stability.shouldSampleMetrics(fableActive: true))
        #expect(!Stability.shouldSampleMetrics(fableActive: false))   // in-game → skip the ps fork
    }

    @Test
    func heavyBackgroundWorkDefersDuringGameplay() {
        #expect(Stability.mayRunHeavyBackgroundWork(gameRunning: false))
        #expect(!Stability.mayRunHeavyBackgroundWork(gameRunning: true))
    }
}

/// The Rock Solid one-click preset.
@Suite struct RockSolidPresetTests {

    @Test
    func d3dMetalBackendsGetCapPlusMetalFX() {
        for backend in [GraphicsBackend.sikarugir, .gptk] {
            let perf = PerformanceOptions.rockSolid(for: backend)
            #expect(perf.frameRateCap == 60)
            #expect(perf.metalFXUpscaling == true)
            #expect(perf.metalHUD == false)
        }
    }

    @Test
    func otherBackendsGetTheCapButNoMetalFX() {
        for backend in [GraphicsBackend.dxmt, .dxvk, .off, .crossover] {
            let perf = PerformanceOptions.rockSolid(for: backend)
            #expect(perf.frameRateCap == 60)
            #expect(perf.metalFXUpscaling == false)   // D3DMetal-only feature
        }
    }
}

/// Thermal throttling detection — edge-triggered so the nudge never spams.
@MainActor
@Suite struct ThermalMonitorTests {

    @Test
    func throttlingMeansSeriousOrCritical() {
        #expect(!ThermalMonitor.isThrottling(.nominal))
        #expect(!ThermalMonitor.isThrottling(.fair))
        #expect(ThermalMonitor.isThrottling(.serious))
        #expect(ThermalMonitor.isThrottling(.critical))
    }

    @Test
    func nudgeFiresOnceOnTheCoolToThrottlingEdge() {
        let monitor = ThermalMonitor()
        var fires = 0
        monitor.onThrottleOnset = { fires += 1 }

        monitor.update(to: .fair)        // still cool
        #expect(fires == 0)
        monitor.update(to: .serious)     // crossed into throttling → nudge
        #expect(fires == 1)
        monitor.update(to: .critical)    // already throttling → no repeat
        #expect(fires == 1)
        monitor.update(to: .nominal)     // cooled off
        monitor.update(to: .serious)     // throttled again → nudge again
        #expect(fires == 2)
    }
}
