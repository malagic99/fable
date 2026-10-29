import Foundation
import SwiftUI
import Testing

@testable import Fable

@Suite("Health")
struct HealthTests {

    // MARK: Priority order (Spec 1.1)

    /// Native wins outright: nothing about Wine compatibility applies to a
    /// game that never touches Wine.
    @Test
    func nativeOutranksEverything() {
        #expect(Health.resolve(confidence: .blocked, isNative: true, crashedLastRun: true) == .native)
        #expect(Health.resolve(confidence: .verified, isNative: true) == .native)
    }

    /// A kernel anti-cheat that won't load is the only thing worth saying, so
    /// it outranks a local crash and any catalog verdict.
    @Test
    func blockedOutranksCrashAndCatalog() {
        #expect(Health.resolve(confidence: .blocked, crashedLastRun: true) == .blocked)
        #expect(Health.resolve(confidence: .blocked) == .blocked)
    }

    /// The deliberate call: a crash on *this* Mac is more actionable than a
    /// catalog saying it works elsewhere. Callers keep showing the catalog
    /// verdict beside it, so the verified signal isn't lost.
    @Test
    func crashOutranksVerified() {
        #expect(Health.resolve(confidence: .verified, crashedLastRun: true) == .crashed)
        #expect(Health.resolve(confidence: .caveat, crashedLastRun: true) == .crashed)
        #expect(Health.resolve(confidence: .played, crashedLastRun: true) == .crashed)
    }

    @Test
    func catalogVerdictsMapThroughWhenNothingLocalApplies() {
        #expect(Health.resolve(confidence: .verified) == .verified)
        #expect(Health.resolve(confidence: .caveat) == .tweaks)
        #expect(Health.resolve(confidence: .played) == .played)
        #expect(Health.resolve(confidence: .unknown) == .untested)
    }

    // MARK: Crash clearing

    /// `crashed` reports an event, not a property, so it has to expire —
    /// otherwise one bad exit marks a game forever.
    @Test
    func aCleanExitClearsTheCrashBadge() {
        #expect(Health.clearsCrash(exitCode: 0, sessionSeconds: 2))
    }

    /// A long session the user ended themselves is real play, whatever the
    /// process returned — games exit non-zero for all sorts of reasons.
    @Test
    func aLongSessionClearsItEvenOnANonZeroExit() {
        #expect(Health.clearsCrash(exitCode: 1, sessionSeconds: Health.cleanSessionSeconds))
        #expect(Health.clearsCrash(exitCode: nil, sessionSeconds: 600))
    }

    /// A quick non-zero exit is exactly the thing the badge exists to report.
    @Test
    func aShortNonZeroExitDoesNotClearIt() {
        #expect(!Health.clearsCrash(exitCode: 134, sessionSeconds: 3))
    }

    // MARK: Presentation invariants

    /// The reason this type exists: every state must carry a glyph and a
    /// label, so nothing is ever communicated by colour alone.
    @Test
    func everyStateHasAGlyphAndALabel() {
        for health in Health.allCases {
            #expect(!health.symbol.isEmpty, "\(health) has no glyph")
            #expect(!health.label.isEmpty, "\(health) has no label")
            #expect(health.label != health.labelKey, "\(health) label is an untranslated key")
        }
    }

    /// Two states sharing a hue is what made the old dot ambiguous. Played was
    /// blue and so was native; played is cyan now.
    @Test
    func playedAndNativeAreVisuallyDistinct() {
        #expect(Health.played.tint != Health.native.tint)
        #expect(Health.played.tint == .cyan)
        #expect(Health.native.tint == .blue)
    }

    /// Crashed and tweaks intentionally share orange, so the glyph and label
    /// are the only thing telling them apart — they must differ.
    @Test
    func statesSharingAColourDifferInLabel() {
        #expect(Health.crashed.tint == Health.tweaks.tint)
        #expect(Health.crashed.label != Health.tweaks.label)
    }

    /// Only `crashed` describes something observed here rather than a catalog
    /// verdict; that's what tells the inspector to keep showing both.
    @Test
    func onlyCrashedIsALocalObservation() {
        for health in Health.allCases where health != .crashed {
            #expect(!health.isLocalObservation, "\(health) should not be local")
        }
        #expect(Health.crashed.isLocalObservation)
    }
}

@Suite("Backend tints")
struct BackendTintTests {

    /// GPTK was purple, which read as a sibling of the brand gradient rather
    /// than the legacy fallback it is.
    @Test
    func legacyBackendsAreNoLongerColoured() {
        #expect(FableTheme.tint(for: .gptk) == .secondary)
        #expect(FableTheme.tint(for: .off) == .secondary)
    }

    @Test
    func theFlagshipBackendTakesTheAccent() {
        #expect(FableTheme.tint(for: .sikarugir) == .accentColor)
    }
}
