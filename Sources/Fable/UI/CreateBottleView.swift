import SwiftUI

/// Modal sheet for creating a new bottle: validates the name, then
/// provisions it (downloading Wine on first use and initializing the prefix).
struct CreateBottleView: View {
    /// Locks the picker to this template if non-nil — used by the
    /// dedicated "New Steam Bottle…" entry point.
    let initialTemplate: BottleTemplate?
    let titleOverride: String?

    init(initialTemplate: BottleTemplate? = nil, title: String? = nil) {
        self.initialTemplate = initialTemplate
        self.titleOverride = title
    }

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var componentManager: ComponentManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var dxmtManager: DXMTManager
    @EnvironmentObject private var gptkManager: GPTKManager
    @EnvironmentObject private var winetricksManager: WinetricksManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case form
        case installingWine
        case creatingPrefix
        case installingDependencies(String)
        case failed(String)
    }

    @State private var name = ""
    @State private var windowsVersion: WindowsVersion = .win10
    @State private var template: BottleTemplate = BottleTemplateCatalog.default
    @State private var errorMessage: String?
    @State private var phase: Phase = .form
    /// Non-essential winetricks verbs that failed during setup (e.g. a font
    /// pack when its mirror was down) — surfaced as a warning, not a hard fail.
    @State private var verbFailures: [String] = []
    @State private var provisionTask: Task<Void, Never>?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isWorking: Bool {
        switch phase {
        case .installingWine, .creatingPrefix, .installingDependencies: true
        default: false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .form:
                formContent
            case .installingWine, .creatingPrefix, .installingDependencies:
                progressContent
            case .failed(let message):
                failureContent(message)
            }
        }
        .frame(width: 440, height: 340)
        .interactiveDismissDisabled(isWorking)
        .onAppear {
            windowsVersion = settingsManager.settings.defaultWindowsVersion
            if let initialTemplate {
                template = initialTemplate
                if name.isEmpty { name = initialTemplate.name }
            }
        }
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

                if initialTemplate == nil {
                    Picker("Template", selection: $template) {
                        ForEach(BottleTemplateCatalog.all) { tmpl in
                            Text(tmpl.name).tag(tmpl)
                        }
                    }
                } else {
                    LabeledContent("Template", value: template.name)
                }
                Text(template.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
                SheetStatusView(
                    systemImage: nil,
                    title: "Creating Wine prefix…",
                    message: "Setting up “\(trimmedName)” — this takes a minute."
                )
            case .installingDependencies(let label):
                SheetStatusView(
                    systemImage: nil,
                    title: "Installing \(label)…",
                    message: "Applying the “\(template.name)” template to “\(trimmedName)”."
                )
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
            SheetStatusView(
                systemImage: "exclamationmark.triangle",
                tint: .yellow,
                title: "Couldn't Create Bottle",
                message: message
            )
            Spacer()
            SheetActionBar {
                Button("Close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Try Again") { phase = .form }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
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
        let chosenTemplate = template
        provisionTask = Task {
            do {
                try await wineManager.ensureWineInstalled()
                phase = .creatingPrefix
                try await wineManager.createPrefix(
                    at: bottleManager.prefixDirectory(for: bottle),
                    windowsVersion: windowsVersion
                )

                try await applyTemplate(chosenTemplate, to: bottle)

                try bottleManager.setStatus(.ready, for: bottle.id)
                if !verbFailures.isEmpty {
                    toastCenter.error("Bottle ready, but some optional setup didn't finish (a download mirror was likely down): \(verbFailures.joined(separator: ", ")). Retry it from the bottle's Winetricks button.")
                }
                dismiss()
            } catch is CancellationError {
                try? bottleManager.deleteBottle(bottle.id)
            } catch {
                try? bottleManager.deleteBottle(bottle.id)
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Backend + dependencies + winetricks verbs, run sequentially with
    /// progress updates. The template's backend wins over the global
    /// DXMT default since the user picked it deliberately.
    private func applyTemplate(_ template: BottleTemplate, to bottle: Bottle) async throws {
        // Fast path: a Steam template clones an existing known-good Steam
        // bottle instead of re-running the slow chain (vcredist + corefonts +
        // the ~hundreds-of-MB Steam download + first-run self-update, which is
        // slow under Rosetta and prone to hang on a dead corefonts mirror).
        // The clone is near-instant (APFS clonefile) and inherits the donor's
        // working graphics backend, so the new Steam bottle just works.
        if template.installsSteam,
           let donor = bottleManager.steamDonorBottle(excluding: bottle.id) {
            phase = .installingDependencies("Cloning Steam from “\(donor.name)”")
            try await bottleManager.seedPrefix(into: bottle.id, fromBottle: donor.id)
            bottleManager.applyRecommendedPerformanceIfDefault(for: bottle.id)
            registerTemplateGames(template, in: bottle)
            return
        }

        switch template.graphicsBackend {
        case .dxmt:
            try await dxmtManager.ensureInstalled()
            try dxmtManager.enable(
                in: bottle, bottleManager: bottleManager, wineManager: wineManager
            )
            try bottleManager.setGraphics(
                backend: .dxmt,
                config: settingsManager.settings.defaultDXMTConfig,
                for: bottle.id
            )
        case .gptk:
            try await gptkManager.ensureInstalled()
            try bottleManager.setGraphics(backend: .gptk, for: bottle.id)
        case .dxvk, .crossover, .sikarugir:
            // Templates can request these but the per-game setup
            // (DXVK install; CrossOver/Sikarugir discovery) happens on
            // first launch. Just persist the choice here.
            try bottleManager.setGraphics(backend: template.graphicsBackend, for: bottle.id)
        case .off:
            // Vanilla / classic preset honors the global default if user
            // had defaultDXMTEnabled on. Otherwise keep .off.
            let defaults = settingsManager.settings
            if template.isVanilla && defaults.defaultDXMTEnabled {
                try await dxmtManager.ensureInstalled()
                try dxmtManager.enable(
                    in: bottle, bottleManager: bottleManager, wineManager: wineManager
                )
                try bottleManager.setGraphics(
                    backend: .dxmt, config: defaults.defaultDXMTConfig, for: bottle.id
                )
            }
        }

        let installer = DependencyInstaller()
        for depID in template.dependencyIDs {
            guard let dep = DependencyCatalog.all.first(where: { $0.id == depID }) else { continue }
            phase = .installingDependencies(dep.name)
            try await installer.install(
                dep, bottle: bottle, bottleManager: bottleManager, wineManager: wineManager
            )
        }

        if !template.winetricksVerbs.isEmpty {
            try await winetricksManager.ensureInstalled()
            let updated = bottleManager.bottle(with: bottle.id) ?? bottle
            for slug in template.winetricksVerbs {
                guard let verb = winetricksManager.verbs.first(where: { $0.id == slug }) else { continue }
                phase = .installingDependencies("Winetricks \(verb.id)")
                do {
                    try await winetricksManager.install(
                        verb: verb, in: updated,
                        bottleManager: bottleManager, wineManager: wineManager
                    )
                } catch is CancellationError {
                    throw CancellationError()   // user cancelled → abort + clean up
                } catch {
                    // A single verb failing (e.g. corefonts when a SourceForge
                    // mirror is down) must NOT destroy the whole bottle. Record
                    // it, keep going, and surface it so the user can retry from
                    // the bottle's Winetricks button.
                    verbFailures.append(verb.id)
                }
            }
        }

        bottleManager.applyRecommendedPerformanceIfDefault(for: bottle.id)
        registerTemplateGames(template, in: bottle)
    }

    /// Walks `gamesToRegister` and adds each one whose executable
    /// actually landed in drive_c. A missing exe is not an error — some
    /// installers (Steam) silently skip themselves on existing installs.
    private func registerTemplateGames(_ template: BottleTemplate, in bottle: Bottle) {
        guard !template.gamesToRegister.isEmpty else { return }
        let driveC = bottleManager.driveCDirectory(for: bottle)
        for registration in template.gamesToRegister {
            let exe = driveC.appending(path: registration.executablePath)
            guard FileManager.default.fileExists(atPath: exe.path) else { continue }
            let game = Game(
                name: registration.name,
                executablePath: registration.executablePath,
                arguments: registration.arguments
            )
            try? bottleManager.addGame(game, to: bottle.id)
        }
    }

    private func cancelProvisioning() {
        provisionTask?.cancel()
        provisionTask = nil
        dismiss()
    }
}
