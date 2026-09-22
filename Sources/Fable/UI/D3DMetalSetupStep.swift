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
    @State private var installStep: String?

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
            if case .missing = status, SikarugirInstaller.isHomebrewInstalled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fable will run:").font(.caption).foregroundStyle(.secondary)
                    ForEach(installCommands, id: \.self) { command in
                        Text(verbatim: command)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(maxWidth: 460, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
                .padding(.top, 4)
            }
            if let installStep {
                Text(installStep)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if isWorking { ProgressView().controlSize(.small).padding(.top, 4) }
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal, 40) }
            Spacer()
            footer.padding(24)
        }
        // Setup happens in another app, so the moment it finishes is invisible
        // from here. Poll while this step is on screen: the user comes back
        // from Sikarugir to a step that has already moved on, instead of
        // staring at a stale message hunting for a re-check button.
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
            "Sikarugir \(SikarugirManager.displayVersion(available)) found. Set it up so Fable can render Steam and D3D12 games."
        case .incomplete:
            "Sikarugir is installed but hasn't downloaded its graphics engine yet — it does that the first time you open it. Open Sikarugir, wait for it to finish, and this step will continue on its own."
        case .missing:
            SikarugirInstaller.isHomebrewInstalled
                ? "To run Steam and modern games, Fable needs a graphics engine that comes from Sikarugir. Fable can install it for you — it takes a few minutes and Fable handles the rest. Older DirectX 9 games work without it."
                : "To run Steam and modern games, Fable needs a graphics engine that comes from Sikarugir, which is distributed through Homebrew. Install Homebrew from brew.sh first, then come back and Fable will do the rest. Older DirectX 9 games work without it."
        }
    }

    /// Shown before anything runs. This installs third-party software
    /// system-wide, so the commands are on screen rather than hidden behind a
    /// spinner — and they're the same ones Sikarugir's own README gives.
    private var installCommands: [String] { SikarugirInstaller.commands }

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
            case .incomplete:
                Button("Continue without it") { onboardingState.advance() }
                if let app = SikarugirManager.appLocation {
                    Button("Open Sikarugir") { NSWorkspace.shared.open(app) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Re-check") { refresh() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            case .missing:
                Button("Continue without it") { onboardingState.advance() }
                if SikarugirInstaller.isHomebrewInstalled {
                    Button("Install Sikarugir") { installSikarugir() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)
                        .keyboardShortcut(.defaultAction)
                } else {
                    // Sikarugir ships only as a Homebrew cask — it publishes no
                    // releases and no app to download — so without Homebrew
                    // there is nothing for Fable to install from.
                    Button("Get Homebrew") {
                        NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    // MARK: Actions

    private func refresh() {
        sikarugirManager.refresh()
        status = sikarugirManager.d3dMetalStatus()
    }

    /// Runs the cask install, then continues straight into extracting the
    /// engine — from the user's side this is one action, not two.
    private func installSikarugir() {
        isWorking = true
        errorText = nil
        Task {
            defer { isWorking = false; installStep = nil }
            do {
                try await SikarugirInstaller.install { installStep = $0 }
                // Sikarugir fetches its engine on first launch, so opening it
                // is part of installing it, not a separate chore for the user.
                if let app = SikarugirManager.appLocation {
                    NSWorkspace.shared.open(app)
                }
            } catch {
                errorText = error.localizedDescription
            }
            refresh()
        }
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
