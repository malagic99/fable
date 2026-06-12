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
    @Environment(\.dismiss) private var dismiss

    @StateObject private var gameInstaller = GameInstaller()

    private enum Phase: Equatable {
        case choice
        case extracting
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
        .frame(width: 460, height: 280)
        .interactiveDismissDisabled(phase == .extracting)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .choice:
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
            Text("GOG / Inno Setup Installer Detected")
                .font(.headline)
            Text("“\(installer.lastPathComponent)” can be unpacked directly into the bottle — faster and more reliable than running the installer, which crashes under Wine for older GOG releases.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

        case .extracting:
            ProgressView()
            Text("Extracting…")
                .font(.headline)
            Text("Unpacking the game into C:\\Program Files.")
                .font(.callout)
                .foregroundStyle(.secondary)

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("Extracted")
                .font(.headline)
            Text("Pick the game's .exe to add it to this bottle.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let registrationError {
                Text(registrationError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

        case .failed(let message):
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
            Text("Extraction Failed")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
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
        case .extracting:
            HStack { Spacer() }
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
                phase = .done(directory)
            } catch {
                phase = .failed(error.localizedDescription)
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
