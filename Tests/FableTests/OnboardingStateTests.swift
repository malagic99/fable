import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct OnboardingStateTests {
    /// Fresh @AppStorage between tests by giving each its own UserDefaults
    /// suite name. The state's @AppStorage uses standard defaults — so
    /// every test resets it explicitly to keep them independent.
    private func freshState() -> OnboardingState {
        let state = OnboardingState()
        state.reset()
        return state
    }

    @Test
    func advancesThroughEveryStepInOrder() {
        let state = freshState()
        #expect(state.currentStep == .welcome)
        state.advance()
        #expect(state.currentStep == .graphics)
        state.advance()
        #expect(state.currentStep == .source)
        state.advance()
        #expect(state.currentStep == .firstBottle)
        state.advance()
        #expect(state.currentStep == .done)
    }

    @Test
    func advanceStopsAtDone() {
        let state = freshState()
        for _ in 0..<10 { state.advance() }
        #expect(state.currentStep == .done)
    }

    @Test
    func goBackMovesOneStepAtATime() {
        let state = freshState()
        state.advance()
        state.advance()
        #expect(state.currentStep == .source)
        state.goBack()
        #expect(state.currentStep == .graphics)
        state.goBack()
        #expect(state.currentStep == .welcome)
        state.goBack()
        #expect(state.currentStep == .welcome, "goBack from welcome is a no-op")
    }

    @Test
    func reachingDoneDoesNotAutoComplete() {
        // Bug from the first build: advance() to .done flipped
        // hasCompleted, which dismissed the sheet before the user saw
        // the "You're all set" confirmation. The Start Playing button
        // is now the sole place that completes the flow.
        let state = freshState()
        #expect(!state.hasCompleted)
        state.advance(); state.advance(); state.advance(); state.advance()
        #expect(state.currentStep == .done)
        #expect(!state.hasCompleted, "Reaching .done must not auto-complete")
        #expect(state.isShowingWizard, "Wizard must remain visible on .done")

        // Simulate the Start Playing button.
        state.hasCompleted = true
        #expect(!state.isShowingWizard)
    }

    @Test
    func skipCompletesWithoutVisitingMiddleSteps() {
        let state = freshState()
        state.skip()
        #expect(state.hasCompleted)
        #expect(state.currentStep == .done)
    }

    @Test
    func sourcePersistsAcrossInstances() {
        let state = freshState()
        state.source = .steam
        #expect(state.source == .steam)
        // A new instance reads the same @AppStorage backing.
        let reloaded = OnboardingState()
        #expect(reloaded.source == .steam)
        reloaded.reset()
    }

    @Test
    func resetReturnsToInitialState() {
        let state = freshState()
        state.source = .heroic
        state.advance(); state.advance(); state.advance(); state.advance()
        #expect(state.currentStep == .done)
        state.hasCompleted = true  // simulate Start Playing
        #expect(!state.isShowingWizard)

        state.reset()
        #expect(state.currentStep == .welcome)
        #expect(!state.hasCompleted)
        #expect(state.source == nil)
        #expect(state.isShowingWizard)
    }

    @Test
    func sourceMapsToExpectedTemplate() {
        #expect(OnboardingState.GameSource.steam.preferredTemplateID == "steam-ready")
        #expect(OnboardingState.GameSource.heroic.preferredTemplateID == "modern-dxmt")
        #expect(OnboardingState.GameSource.manual.preferredTemplateID == "vanilla")
    }

    @Test
    func everyPreferredTemplateExistsInCatalog() {
        let knownIDs = Set(BottleTemplateCatalog.all.map(\.id))
        for source in OnboardingState.GameSource.allCases {
            #expect(knownIDs.contains(source.preferredTemplateID),
                    "Source \(source.rawValue) points at missing template \(source.preferredTemplateID)")
        }
    }
}
