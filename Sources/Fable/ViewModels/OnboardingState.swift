import Foundation
import SwiftUI

/// Drives the first-launch wizard. Persists the completion flag and
/// the user's "where are your games?" choice so the rest of the app
/// can tailor defaults (e.g. CreateBottleView pre-picking a template).
@MainActor
final class OnboardingState: ObservableObject {
    /// Linear step machine. Adding a step = bump the next/previous logic.
    enum Step: Int, CaseIterable {
        case welcome
        case interface      // pick the app's face: Classic or Gamer
        case graphics       // detect / set up D3DMetal (the flagship backend's source)
        case source
        case firstBottle
        case done
    }

    /// What the user picked on the "where are your games?" step. Drives
    /// which BottleTemplate is pre-selected on the firstBottle step.
    enum GameSource: String, Codable, CaseIterable, Identifiable, Sendable {
        case steam
        case heroic
        case manual

        var id: String { rawValue }

        /// Resolved title for the card. Goes through L10n (Bundle.module)
        /// rather than LocalizedStringKey — SwiftUI's Text(LocalizedStringKey)
        /// only auto-resolves string LITERALS reliably; a runtime-built
        /// key like "onboarding.source.\(rawValue).title" renders raw.
        var title: String { L10n.string("onboarding.source.\(rawValue).title") }
        var subtitle: String { L10n.string("onboarding.source.\(rawValue).subtitle") }

        var systemImage: String {
            switch self {
            case .steam: "gamecontroller.fill"
            case .heroic: "shippingbox.fill"
            case .manual: "doc.on.doc.fill"
            }
        }

        /// Which Day-14 template should be pre-selected for this source.
        var preferredTemplateID: String {
            switch self {
            case .steam: "steam-ready"
            case .heroic: "modern-dxmt"
            case .manual: "vanilla"
            }
        }
    }

    /// Persists across launches. When true, the wizard never shows.
    @AppStorage("onboarding.hasCompleted") private var hasCompletedStorage = false
    /// Persists across launches so the rest of the app can read it.
    @AppStorage("onboarding.source") private var sourceRaw: String = ""

    @Published var currentStep: Step = .welcome

    var hasCompleted: Bool {
        get { hasCompletedStorage }
        set { hasCompletedStorage = newValue }
    }

    /// Nil when the user hasn't picked yet.
    var source: GameSource? {
        get { GameSource(rawValue: sourceRaw) }
        set { sourceRaw = newValue?.rawValue ?? "" }
    }

    var isShowingWizard: Bool { !hasCompleted }

    // MARK: Navigation

    func advance() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
        // NOTE: do NOT flip hasCompleted here. The sheet's isShowingWizard
        // binding watches hasCompleted, so flipping it on entry to .done
        // would dismiss the sheet before the user ever sees the "You're
        // all set" confirmation. DoneStep's "Start Playing" button is
        // the only place that completes the flow.
    }

    func goBack() {
        guard let previous = Step(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
    }

    /// Skip the wizard entirely — e.g. user closes the sheet. The
    /// hasCompleted flag still flips so we don't pester them next launch.
    func skip() {
        currentStep = .done
        hasCompleted = true
    }

    /// "Reset onboarding" action from Settings — useful for development
    /// and for users who want to re-run the wizard.
    func reset() {
        hasCompleted = false
        sourceRaw = ""
        currentStep = .welcome
    }
}
