import SwiftUI

/// Mandatory onboarding step: set up the engine behind Fable's flagship
/// backend — Sikarugir's Wine 10 with Apple's D3DMetal, which renders Steam
/// and D3D12 games. Fable downloads it itself (checksum-pinned, from
/// Sikarugir's GitHub releases), so nothing here needs Homebrew, Terminal or
/// another app. An informed "continue without" escape keeps the app usable
/// for someone who only wants old D3D9 games (which don't need it).
struct D3DMetalSetupStep: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var sikarugirManager: SikarugirManager

    @State private var status: SikarugirManager.D3DMetalStatus = .missing
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var installStep: String?
    @State private var rosettaInstalled = Rosetta.isInstalled()

    var body: some View {
        // The engine is an Intel program: without Rosetta, downloading it
        // gets someone no closer to a game. Ask for that first.
        if rosettaInstalled {
            engineBody
        } else {
            RosettaSetupStep { rosettaInstalled = true }
        }
    }

    private var engineBody: some View {
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
            if let installStep {
                Text(installStep)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isWorking { ProgressView().controlSize(.small).padding(.top, 4) }
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal, 40) }
            Spacer()
            footer.padding(24)
        }
        // The engine can also be set up from a bottle page while this step is
        // on screen, so poll rather than trusting the state read on appear.
        .task {
            refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                if case .ready = status { break }
                refresh()
            }
        }
    }

    // MARK: State-driven presentation

    private var icon: String {
        switch status {
        case .ready: "checkmark.seal.fill"
        case .updateAvailable: "arrow.up.circle.fill"
        case .notInstalled: "arrow.down.circle"
        case .incomplete: "hourglass"
        case .missing: "arrow.down.circle.fill"
        }
    }
    private var tint: Color {
        switch status {
        case .ready: .green
        case .updateAvailable: .blue
        case .notInstalled: .accentColor
        case .incomplete: .orange
        case .missing: .accentColor
        }
    }
    private var headline: String {
        switch status {
        case .ready(let v):
            "D3DMetal \(SikarugirManager.displayVersion(v)) is ready. Steam and D3D12 games will use the fast Metal path."
        case .updateAvailable(let installed, let available):
            "D3DMetal \(SikarugirManager.displayVersion(installed)) is set up — a newer \(SikarugirManager.displayVersion(available)) is available."
        case .notInstalled(let available):
            "To run Steam and modern games, Fable downloads a graphics engine: Sikarugir's Wine \(SikarugirManager.displayVersion(available)) with Apple's D3DMetal, about 270 MB. It stays inside Fable's own folder. Older DirectX 9 games work without it."
        case .incomplete, .missing:
            // Only reachable when the version catalog has no engine entry.
            "This copy of Fable has no graphics engine to download. Older DirectX 9 games still work; update Fable to run Steam and modern games."
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
                Button("Download Engine") { setUp() }
                    .buttonStyle(.borderedProminent).disabled(isWorking).keyboardShortcut(.defaultAction)
            case .updateAvailable:
                Button("Update") { setUp() }.disabled(isWorking)
                Button("Continue") { onboardingState.advance() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            case .incomplete, .missing:
                Button("Re-check") { refresh() }
                Button("Continue without it") { onboardingState.advance() }
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
        installStep = L10n.string("engine.setup.downloading")
        Task {
            do { try await sikarugirManager.ensureInstalled() }
            catch { errorText = error.localizedDescription }
            isWorking = false
            installStep = nil
            refresh()
        }
    }
}

/// Shown in place of the engine step on a Mac without Rosetta 2. Installs it
/// with Apple's own installer, so nobody is sent to Terminal for it.
struct RosettaSetupStep: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    let onInstalled: () -> Void

    @State private var isWorking = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text("Rosetta").font(.largeTitle.weight(.semibold))
                Text(L10n.string("rosetta.setup.headline"))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 44)
                Text(L10n.string("rosetta.setup.license"))
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 44)
            }
            if isWorking {
                ProgressView().controlSize(.small)
                Text(L10n.string("rosetta.setup.installing")).font(.caption).foregroundStyle(.secondary)
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal, 40)
            }
            Spacer()
            HStack {
                Button("Back") { onboardingState.goBack() }
                Spacer()
                Button("Continue without it") { onboardingState.advance() }
                Button("Install Rosetta") { install() }
                    .buttonStyle(.borderedProminent).disabled(isWorking).keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        // Rosetta can also arrive another way while this is on screen (macOS
        // offers it when any Intel app is opened).
        .task {
            while !Task.isCancelled {
                if Rosetta.isInstalled() { onInstalled(); break }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func install() {
        isWorking = true
        errorText = nil
        Task {
            do {
                try await Rosetta.install()
                onInstalled()
            } catch {
                errorText = error.localizedDescription
            }
            isWorking = false
        }
    }
}
