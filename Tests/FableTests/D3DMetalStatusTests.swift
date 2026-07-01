import Foundation
import Testing
@testable import Fable

/// The onboarding step's D3DMetal status decision (pure) + version display.
@MainActor
@Suite struct D3DMetalStatusTests {

    @Test
    func missingWhenSikarugirNotDiscovered() {
        #expect(SikarugirManager.status(discovered: false, available: nil, installed: nil) == .missing)
        #expect(SikarugirManager.status(discovered: false, available: "v1", installed: "v1") == .missing)
    }

    @Test
    func notInstalledWhenFoundButNotExtracted() {
        #expect(SikarugirManager.status(discovered: true, available: "v1", installed: nil)
                == .notInstalled(available: "v1"))
    }

    @Test
    func readyWhenVersionsMatch() {
        #expect(SikarugirManager.status(discovered: true, available: "v1", installed: "v1")
                == .ready(version: "v1"))
    }

    @Test
    func updateAvailableWhenInstalledIsOlder() {
        #expect(SikarugirManager.status(discovered: true, available: "v2", installed: "v1")
                == .updateAvailable(installed: "v1", available: "v2"))
    }

    @Test
    func displayVersionStripsTheSikarugirPrefix() {
        #expect(SikarugirManager.displayVersion("WS12WineSikarugir10.0_4") == "10.0_4")
        #expect(SikarugirManager.displayVersion("unexpected") == "unexpected")
    }
}
