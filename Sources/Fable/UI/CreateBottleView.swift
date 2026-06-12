import SwiftUI

/// Modal sheet for creating a new bottle: validates the name, then
/// provisions it (downloading Wine on first use and initializing the prefix).
struct CreateBottleView: View {
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var componentManager: ComponentManager
    @EnvironmentObject private var wineManager: WineManager
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case form
        case installingWine
        case creatingPrefix
        case failed(String)
    }

    @State private var name = ""
    @State private var windowsVersion: WindowsVersion = .win10
    @State private var errorMessage: String?
    @State private var phase: Phase = .form
    @State private var provisionTask: Task<Void, Never>?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isWorking: Bool {
        phase == .installingWine || phase == .creatingPrefix
    }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .form:
                formContent
            case .installingWine, .creatingPrefix:
                progressContent
            case .failed(let message):
                failureContent(message)
            }
        }
        .frame(width: 400, height: 260)
        .interactiveDismissDisabled(isWorking)
    }

    // MARK: Form

    private var formContent: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text("My Bottle"))
                    .onSubmit(create)

                Picker("Windows Version", selection: $windowsVersion) {
                    ForEach(WindowsVersion.allCases) { version in
                        Text(version.displayName).tag(version)
                    }
                }

                if !wineManager.isWineInstalled {
                    Text("Wine isn't installed yet — it will be downloaded (~190 MB) when you create your first bottle.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

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
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(16)
        }
    }

    // MARK: Progress

    private var progressContent: some View {
        VStack(spacing: 16) {
            Spacer()

            switch phase {
            case .installingWine:
                wineInstallProgress
            case .creatingPrefix:
                ProgressView()
                Text("Creating Wine prefix…")
                    .font(.headline)
                Text("Setting up “\(trimmedName)” — this takes a minute.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }

            Spacer()

            HStack {
                Button("Cancel", role: .cancel) { cancelProvisioning() }
                    .keyboardShortcut(.cancelAction)
                    // The prefix bootstrap can't be safely interrupted.
                    .disabled(phase == .creatingPrefix)
                Spacer()
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var wineInstallProgress: some View {
        switch componentManager.state(of: WineManager.componentID) {
        case .downloading(let progress):
            ProgressView(value: progress.fraction)
                .frame(width: 280)
            Text("Downloading Wine…")
                .font(.headline)
            Text(downloadDetail(progress))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case .verifying:
            ProgressView()
            Text("Verifying download…").font(.headline)
        case .extracting:
            ProgressView()
            Text("Extracting Wine…").font(.headline)
        default:
            ProgressView()
            Text("Preparing…").font(.headline)
        }
    }

    private func downloadDetail(_ progress: DownloadProgress) -> String {
        let received = ByteCountFormatter.string(fromByteCount: progress.bytesReceived, countStyle: .file)
        guard let total = progress.totalBytes else { return received }
        return "\(received) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    }

    // MARK: Failure

    private func failureContent(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
            Text("Couldn't Create Bottle")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            HStack {
                Button("Close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Try Again") { phase = .form }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    // MARK: Actions

    private func create() {
        guard !trimmedName.isEmpty else { return }

        let bottle: Bottle
        do {
            bottle = try bottleManager.createBottle(name: trimmedName, windowsVersion: windowsVersion)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        phase = .installingWine
        provisionTask = Task {
            do {
                try await wineManager.ensureWineInstalled()
                phase = .creatingPrefix
                try await wineManager.createPrefix(
                    at: bottleManager.prefixDirectory(for: bottle),
                    windowsVersion: windowsVersion
                )
                try bottleManager.setStatus(.ready, for: bottle.id)
                dismiss()
            } catch is CancellationError {
                try? bottleManager.deleteBottle(bottle.id)
            } catch {
                try? bottleManager.deleteBottle(bottle.id)
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelProvisioning() {
        provisionTask?.cancel()
        provisionTask = nil
        dismiss()
    }
}
