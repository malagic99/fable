import SwiftUI

/// Mandatory onboarding step: detect Apple's D3DMetal (sourced from the free
/// Sikarugir) — the engine behind Fable's flagship backend that renders Steam
/// and D3D12 games — show its version, and offer set-up / update, or guide
/// installing Sikarugir. An informed "continue without" escape keeps the app
/// usable for someone who only wants old D3D9 games (which don't need it).
struct D3DMetalSetupStep: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var sikarugirManager: SikarugirManager

    @State private var status: SikarugirManager.D3DMetalStatus = .missing
    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
            VStack(spacing: 8) {
                Text("Graphics engine").font(.largeTitle.weight(.semibold))
                Text(headline)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 44)
            }
            if isWorking { ProgressView().controlSize(.small).padding(.top, 4) }
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal, 40) }
            Spacer()
            footer.padding(24)
        }
        .task { refresh() }
    }

    // MARK: State-driven presentation

    private var icon: String {
        switch status {
        case .ready: "checkmark.seal.fill"
        case .updateAvailable: "arrow.up.circle.fill"
        case .notInstalled: "arrow.down.circle"
        case .missing: "exclamationmark.triangle.fill"
        }
    }
    private var tint: Color {
        switch status {
        case .ready: .green
        case .updateAvailable: .blue
        case .notInstalled: .accentColor
        case .missing: .orange
        }
    }
    private var headline: String {
        switch status {
        case .ready(let v):
            "D3DMetal \(SikarugirManager.displayVersion(v)) is ready. Steam and D3D12 games will use the fast Metal path."
        case .updateAvailable(let installed, let available):
            "D3DMetal \(SikarugirManager.displayVersion(installed)) is set up — a newer \(SikarugirManager.displayVersion(available)) is available."
        case .notInstalled(let available):
            "Sikarugir \(SikarugirManager.displayVersion(available)) found. Set it up so Fable can render Steam and D3D12 games."
        case .missing:
            "Fable uses Apple's D3DMetal (via the free Sikarugir) to render Steam and modern games. Install Sikarugir, then come back — or continue with just the built-in backends for older games."
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("Back") { onboardingState.goBack() }
            Spacer()
            switch status {
            case .ready:
                Button("Continue") { onboardingState.advance() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            case .notInstalled:
                Button("Continue without it") { onboardingState.advance() }
                Button("Set Up D3DMetal") { setUp() }
                    .buttonStyle(.borderedProminent).disabled(isWorking).keyboardShortcut(.defaultAction)
            case .updateAvailable:
                Button("Update") { setUp() }.disabled(isWorking)
                Button("Continue") { onboardingState.advance() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            case .missing:
                Button("Re-check") { refresh() }
                Button("Continue without it") { onboardingState.advance() }
                Button("Get Sikarugir") { NSWorkspace.shared.open(URL(string: "https://sikarugir.app")!) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Actions

    private func refresh() {
        sikarugirManager.refresh()
        status = sikarugirManager.d3dMetalStatus()
    }

    private func setUp() {
        isWorking = true
        errorText = nil
        Task {
            do { try await sikarugirManager.ensureInstalled() }
            catch { errorText = error.localizedDescription }
            isWorking = false
            refresh()
        }
    }
}
