import SwiftUI

/// First-launch wizard. Four steps: welcome → source → first bottle →
/// done. Shown as a sheet over MainWindow when
/// `OnboardingState.isShowingWizard` is true.
struct OnboardingView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var bottleManager: BottleManager
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingCreateSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(
                value: Double(onboardingState.currentStep.rawValue),
                total: Double(OnboardingState.Step.allCases.count - 1)
            )
            .progressViewStyle(.linear)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Group {
                switch onboardingState.currentStep {
                case .welcome:
                    WelcomeStep()
                case .graphics:
                    D3DMetalSetupStep()
                case .source:
                    SourceStep()
                case .firstBottle:
                    FirstBottleStep(isShowingCreateSheet: $isShowingCreateSheet)
                case .done:
                    DoneStep()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 460)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $isShowingCreateSheet, onDismiss: {
            // CreateBottleView only dismisses on success — once it
            // does, we know a bottle exists and can advance.
            if !bottleManager.bottles.isEmpty {
                onboardingState.advance()
            }
        }) {
            CreateBottleView(
                initialTemplate: BottleTemplateCatalog.all.first {
                    $0.id == onboardingState.source?.preferredTemplateID
                }
            )
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    @EnvironmentObject private var onboardingState: OnboardingState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "wineglass")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("onboarding.welcome.title")
                    .font(.largeTitle.weight(.semibold))
                Text("onboarding.welcome.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()

            HStack {
                Button("onboarding.skip") { onboardingState.skip() }
                Spacer()
                Button("onboarding.get_started") { onboardingState.advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
    }
}

// MARK: - Step 2: Source picker

private struct SourceStep: View {
    @EnvironmentObject private var onboardingState: OnboardingState

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("onboarding.source.title")
                    .font(.title2.weight(.semibold))
                Text("onboarding.source.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            VStack(spacing: 12) {
                ForEach(OnboardingState.GameSource.allCases) { source in
                    SourceCard(
                        source: source,
                        isSelected: onboardingState.source == source,
                        onTap: { onboardingState.source = source }
                    )
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack {
                Button("onboarding.back") { onboardingState.goBack() }
                Spacer()
                Button("onboarding.continue") { onboardingState.advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(onboardingState.source == nil)
            }
            .padding(24)
        }
    }
}

private struct SourceCard: View {
    let source: OnboardingState.GameSource
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: source.systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: source.title)
                        .font(.headline)
                    Text(verbatim: source.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 3: First bottle

private struct FirstBottleStep: View {
    @Binding var isShowingCreateSheet: Bool

    @EnvironmentObject private var onboardingState: OnboardingState

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("onboarding.first_bottle.title")
                    .font(.title2.weight(.semibold))
                Text(subtitleKey)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 24)

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: onboardingState.source?.systemImage ?? "wineglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                if let template = matchedTemplate {
                    Text(template.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            Spacer()

            HStack {
                Button("onboarding.back") { onboardingState.goBack() }
                Spacer()
                Button("onboarding.skip_for_now") { onboardingState.advance() }
                Button("onboarding.create_bottle") {
                    isShowingCreateSheet = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
    }

    private var matchedTemplate: BottleTemplate? {
        BottleTemplateCatalog.all.first {
            $0.id == onboardingState.source?.preferredTemplateID
        }
    }

    private var subtitleKey: LocalizedStringKey {
        switch onboardingState.source {
        case .steam: "onboarding.first_bottle.subtitle.steam"
        case .heroic: "onboarding.first_bottle.subtitle.heroic"
        case .manual, .none: "onboarding.first_bottle.subtitle.manual"
        }
    }
}

// MARK: - Step 4: Done

private struct DoneStep: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("onboarding.done.title")
                    .font(.largeTitle.weight(.semibold))
                Text("onboarding.done.subtitle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            HStack {
                Spacer()
                Button("onboarding.done.start") {
                    onboardingState.hasCompleted = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
    }
}
