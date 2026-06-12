import SwiftUI

/// Sheet for Inno Setup / GOG offline installers: extract directly into
/// the bottle (reliable), or run the installer under Wine (old GOG
/// installers crash there).
struct GOGInstallView: View {
    let bottle: Bottle
    let installer: URL
    /// Invoked if the user prefers running the installer under Wine.
    let onRunInWine: (URL) -> Void

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var wineManager: WineManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var gameInstaller = GameInstaller()
    @StateObject private var redistInstaller = RedistInstaller()

    private enum Phase: Equatable {
        case choice
        case extracting
        case redists(gameDir: URL, redists: [URL])
        case installingRedists
        case done(URL)
        case failed(String)
    }

    @State private var phase: Phase = .choice
    @State private var registrationError: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            content
            Spacer()
            buttons
                .padding(16)
        }
        .frame(width: 460, height: 320)
        .interactiveDismissDisabled(phase == .extracting)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .choice:
            SheetStatusView(
                systemImage: "shippingbox.and.arrow.backward",
                title: "GOG / Inno Setup Installer Detected",
                message: "“\(installer.lastPathComponent)” can be unpacked directly into the bottle — faster and more reliable than running the installer, which crashes under Wine for older GOG releases."
            )

        case .extracting:
            SheetStatusView(
                systemImage: nil,
                title: "Extracting…",
                message: "Unpacking the game into C:\\Program Files."
            )

        case .redists(_, let redists):
            SheetStatusView(
                systemImage: "puzzlepiece.extension",
                title: "Bundled Dependencies Found",
                message: "This game ships runtimes it expects to be installed:"
            )
            VStack(alignment: .leading, spacing: 4) {
                ForEach(redists, id: \.absoluteString) { redist in
                    Label(
                        RedistInstaller.classify(redist) == .generic
                            ? redist.lastPathComponent
                            : RedistInstaller.classify(redist).displayName,
                        systemImage: "shippingbox"
                    )
                    .font(.callout)
                }
            }

        case .installingRedists:
            SheetStatusView(
                systemImage: nil,
                title: "Installing Dependencies…",
                message: redistInstaller.currentInstall
            )

        case .done:
            SheetStatusView(
                systemImage: "checkmark.circle.fill",
                tint: .green,
                title: "Extracted",
                message: "Pick the game's .exe to add it to this bottle."
            )
            if let registrationError {
                Text(registrationError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

        case .failed(let message):
            SheetStatusView(
                systemImage: "exclamationmark.triangle",
                tint: .yellow,
                title: "Extraction Failed",
                message: message
            )
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch phase {
        case .choice:
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Run Installer in Wine") {
                    dismiss()
                    onRunInWine(installer)
                }
                Button("Extract Directly") { startExtraction() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .extracting, .installingRedists:
            HStack { Spacer() }
        case .redists(let gameDir, let redists):
            HStack {
                Button("Skip") { phase = .done(gameDir) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Install Dependencies") {
                    installRedists(redists, thenContinueTo: gameDir)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        case .done(let directory):
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Game…") { addGame(from: directory) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .failed:
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func startExtraction() {
        phase = .extracting
        Task {
            do {
                let directory = try await gameInstaller.extractInnoInstaller(
                    installer,
                    bottle: bottle,
                    bottleManager: bottleManager
                )
                let redists = InnoExtractor.bundledRedists(in: directory)
                phase = redists.isEmpty
                    ? .done(directory)
                    : .redists(gameDir: directory, redists: redists)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func installRedists(_ redists: [URL], thenContinueTo gameDir: URL) {
        phase = .installingRedists
        Task {
            do {
                try await redistInstaller.install(
                    redists,
                    bottle: bottle,
                    bottleManager: bottleManager,
                    wineManager: wineManager
                )
                phase = .done(gameDir)
            } catch {
                // The game is extracted and playable; dependencies can
                // be retried later. Report but continue.
                registrationError = "Some dependencies failed: \(error.localizedDescription)"
                phase = .done(gameDir)
            }
        }
    }

    private func addGame(from directory: URL) {
        guard let exe = FilePicker.chooseExecutable(
            title: "Choose the game's .exe",
            startingAt: directory
        ) else { return }
        do {
            try gameInstaller.registerGame(
                executable: exe,
                bottle: bottle,
                bottleManager: bottleManager
            )
            dismiss()
        } catch {
            registrationError = error.localizedDescription
        }
    }
}
