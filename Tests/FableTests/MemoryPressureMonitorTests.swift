import Foundation
import Testing
@testable import Fable

/// The memory-pressure nudge — edge-triggered so it never spams, matching
/// ThermalMonitor's contract.
@MainActor
@Suite struct MemoryPressureMonitorTests {

    private func monitor() -> MemoryPressureMonitor {
        MemoryPressureMonitor(start: false)  // no live DispatchSource in tests
    }

    @Test
    func firesOnceOnTheNormalToPressuredEdge() {
        let m = monitor()
        var fires = 0
        m.onPressureOnset = { fires += 1 }

        m.handle(.warning)
        #expect(m.isUnderPressure)
        #expect(fires == 1)

        // Staying pressured (critical after warning) must NOT re-fire.
        m.handle(.critical)
        #expect(fires == 1)
    }

    @Test
    func reArmsAfterReturningToNormal() {
        let m = monitor()
        var fires = 0
        m.onPressureOnset = { fires += 1 }

        m.handle(.warning)     // fire
        m.handle(.normal)      // reset
        #expect(!m.isUnderPressure)
        #expect(fires == 1)
        m.handle(.critical)    // fire again — a fresh episode
        #expect(fires == 2)
    }

    @Test
    func normalAloneNeverFires() {
        let m = monitor()
        var fires = 0
        m.onPressureOnset = { fires += 1 }
        m.handle(.normal)
        #expect(!m.isUnderPressure)
        #expect(fires == 0)
    }
}
