import SwiftUI

/// Sheet that babysits a Windows installer running under Wine, then lets
/// the user register the freshly installed game.
struct GameInstallerView: View {
    let bottle: Bottle
    let installerExe: URL

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var wineManager: WineManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var installer = GameInstaller()

    private enum Phase: Equatable {
        case running
        case finished(exitCode: Int32)
        case failed(String)
    }

    @State private var phase: Phase = .running
    @State private var registrationError: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            switch phase {
            case .running:
                ProgressView()
                Text("Installer Running")
                    .font(.headline)
                Text("Complete the “\(installerExe.lastPathComponent)” installer in its own window. Fable will continue when it finishes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

            case .finished(let exitCode):
                Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(exitCode == 0 ? .green : .yellow)
                Text(exitCode == 0 ? "Installer Finished" : "Installer Failed (exit code \(exitCode))")
                    .font(.headline)
                Text(exitCode == 0
                    ? "Pick the installed game's .exe (usually in C:\\Program Files) to add it to this bottle."
                    : "The installer crashed or was stopped before finishing. Check the log for details — and if this is a GOG offline installer, use Extract Directly instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
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
                Text("Couldn't Run Installer")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            HStack {
                switch phase {
                case .running:
                    Button("Stop Installer", role: .destructive) {
                        installer.cancelInstaller()
                    }
                    Spacer()
                case .finished(let exitCode):
                    if let log = installer.installerLog {
                        Button("Show Log") {
                            NSWorkspace.shared.activateFileViewerSelecting([log])
                        }
                    }
                    Spacer()
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    if exitCode == 0 {
                        Button("Add Installed Game…") { addInstalledGame() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        // Some installers exit non-zero even on success.
                        Button("Add Game Anyway…") { addInstalledGame() }
                    }
                case .failed:
                    if let log = installer.installerLog {
                        Button("Show Log") {
                            NSWorkspace.shared.activateFileViewerSelecting([log])
                        }
                    }
                    Spacer()
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(16)
        }
        .frame(width: 420, height: 240)
        .interactiveDismissDisabled(phase == .running)
        .task { await runInstaller() }
    }

    private func runInstaller() async {
        do {
            let exitCode = try await installer.runInstaller(
                installerExe,
                bottle: bottle,
                bottleManager: bottleManager,
                wineManager: wineManager
            )
            phase = .finished(exitCode: exitCode)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func addInstalledGame() {
        let driveC = bottleManager.driveCDirectory(for: bottle)
        guard let exe = FilePicker.chooseExecutable(
            title: "Choose the installed game's .exe",
            startingAt: driveC.appending(path: "Program Files", directoryHint: .isDirectory)
        ) else { return }

        let installer = GameInstaller()
        do {
            try installer.registerGame(
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

/// Sheet for importing a portable game from outside the bottle: choose
/// what to copy, watch progress, done.
struct ImportGameView: View {
    let bottle: Bottle
    let executable: URL

    @EnvironmentObject private var bottleManager: BottleManager
    @Environment(\.dismiss) private var dismiss

    @StateObject private var installer = GameInstaller()

    @State private var mode: GameInstaller.ImportMode = .wholeFolder
    @State private var isCopying = false
    @State private var errorMessage: String?
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if isCopying {
                copyProgressContent
            } else {
                optionsContent
            }
        }
        .frame(width: 440, height: 280)
        .interactiveDismissDisabled(isCopying)
    }

    private var optionsContent: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent("Game", value: executable.lastPathComponent)
                LabeledContent("From") {
                    Text(executable.deletingLastPathComponent().path)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }

                Picker("Copy into bottle", selection: $mode) {
                    Text("Entire folder “\(executable.deletingLastPathComponent().lastPathComponent)” (recommended)")
                        .tag(GameInstaller.ImportMode.wholeFolder)
                    Text("Just \(executable.lastPathComponent)")
                        .tag(GameInstaller.ImportMode.executableOnly)
                }
                .pickerStyle(.radioGroup)

                Text("The game is copied into C:\\Program Files inside this bottle. Most games need their whole folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Import") { startImport() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    private var copyProgressContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: installer.copyProgress ?? 0)
                .frame(width: 300)
            Text("Copying into bottle…")
                .font(.headline)
            Spacer()
            HStack {
                Button("Cancel", role: .cancel) {
                    importTask?.cancel()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(16)
        }
    }

    private func startImport() {
        isCopying = true
        errorMessage = nil
        importTask = Task {
            do {
                try await installer.importGame(
                    executable: executable,
                    mode: mode,
                    bottle: bottle,
                    bottleManager: bottleManager
                )
                dismiss()
            } catch is CancellationError {
                dismiss()
            } catch {
                isCopying = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
