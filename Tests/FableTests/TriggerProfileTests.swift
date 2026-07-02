import Foundation
import Testing
@testable import Fable

/// The DualSense trigger profile model: presets, effective resolution, and
/// Codable round-trip with tolerant decode.
@Suite struct TriggerProfileTests {

    @Test
    func offProfileIsInactive() {
        #expect(!TriggerProfile.off.isActive)
        #expect(TriggerProfile.shooter.isActive)
    }

    @Test
    func presetsAreDistinctAndSane() {
        #expect(TriggerProfile.shooter.right.mode == .weapon)
        #expect(TriggerProfile.shooter.right.end > TriggerProfile.shooter.right.start)
        #expect(TriggerProfile.heavy.left.mode == .feedback)
        #expect(TriggerProfile.presets.first?.name == "Off")
    }

    @Test
    func effectiveProfilePrefersGameOverride() {
        let bottleDefault = TriggerProfile.shooter
        let inheriting = Game(name: "A", executablePath: "a.exe")
        #expect(inheriting.effectiveTriggerProfile(bottleDefault: bottleDefault) == bottleDefault)

        let overridden = Game(name: "B", executablePath: "b.exe", triggerProfile: .racing)
        #expect(overridden.effectiveTriggerProfile(bottleDefault: bottleDefault) == .racing)
    }

    @Test
    @MainActor
    func keepAliveRunsOnlyForAnActiveProfileOnADualSense() {
        // The re-assert timer that keeps resistance alive after a game clears
        // the triggers must not spin with nothing to write or no pad present.
        #expect(DualSenseTriggerController.shouldKeepAlive(profileActive: true, isDualSense: true))
        #expect(!DualSenseTriggerController.shouldKeepAlive(profileActive: false, isDualSense: true))
        #expect(!DualSenseTriggerController.shouldKeepAlive(profileActive: true, isDualSense: false))
        #expect(!DualSenseTriggerController.shouldKeepAlive(profileActive: false, isDualSense: false))
    }

    @Test
    func bottleAndGameProfilesSurviveACodableRoundTrip() throws {
        var bottle = Bottle(name: "B")
        bottle.triggerProfile = .shooter
        bottle.games = [Game(name: "G", executablePath: "g.exe", triggerProfile: .heavy)]

        let data = try JSONEncoder().encode(bottle)
        let decoded = try JSONDecoder().decode(Bottle.self, from: data)
        #expect(decoded.triggerProfile == .shooter)
        #expect(decoded.games.first?.triggerProfile == .heavy)
    }

    @Test
    func olderBottlesWithoutTriggerFieldDefaultToOff() throws {
        // A bottle JSON that predates the trigger field must decode with .off.
        // Minimal older-shape bottle: the optional sub-configs are absent, so
        // they (and the new triggerProfile) fall back to defaults.
        let json = """
        {"id":"\(UUID().uuidString)","name":"Legacy","windowsVersion":"win10",
         "createdAt":0,"status":"ready","games":[],"graphicsBackend":"off",
         "installedWinetricksVerbs":[]}
        """
        let decoded = try JSONDecoder().decode(Bottle.self, from: Data(json.utf8))
        #expect(decoded.triggerProfile == .off)
        #expect(decoded.games.isEmpty)
    }
}
