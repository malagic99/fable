import SwiftUI

/// Settings, grouped by intent (UI review P2):
/// Appearance (how Fable looks) · Library (how games are described) ·
/// Defaults (what new bottles get) · Advanced (storage + escape hatches) ·
/// About (version + update).
struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            LibrarySettingsTab()
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            DefaultsSettingsTab()
                .tabItem { Label("Defaults", systemImage: "slider.horizontal.3") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var toastCenter: ToastCenter

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: $settingsManager.settings.interfaceStyle) {
                    ForEach(InterfaceStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Advanced Mode", isOn: $settingsManager.settings.advancedMode)
            } header: {
                Text("Interface")
            } footer: {
                Text("Gamer puts your games up front as a cover wall; Classic is the bottles-first utility. Advanced Mode reveals the backend, performance, storage, and troubleshooting panels on bottle pages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Appearance", selection: $settingsManager.settings.appearance) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Theme", selection: Binding(
                    get: { settingsManager.settings.activeThemeID },
                    set: { applyTheme(id: $0) }
                )) {
                    ForEach(themeStore.skins) { skin in
                        Text(skin.name).tag(skin.id)
                    }
                }

                LabeledContent("Theme Files") {
                    HStack(spacing: 8) {
                        Button("Import…") { importTheme() }
                            .controlSize(.small)
                        Button("Export Current…") { exportTheme() }
                            .controlSize(.small)
                    }
                }

                LabeledContent("Background") {
                    HStack(spacing: 8) {
                        if settingsManager.settings.customBackgroundPath != nil {
                            Button("Clear") { settingsManager.settings.customBackgroundPath = nil }
                                .controlSize(.small)
                        }
                        Button("Choose Image…") { pickBackground() }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Themes")
            } footer: {
                Text("Themes recolor Fable's accent, gradient, and window wash, and travel as .fableskin files you can share. A custom background image sits behind the whole window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fableThemedFormBackground()
    }

    private func applyTheme(id: String) {
        settingsManager.settings.activeThemeID = id
        // A theme carries a suggested appearance — apply it (still overridable).
        if let suggested = themeStore.skin(id: id).suggestedAppearance {
            settingsManager.settings.appearance = suggested
        }
    }

    private func importTheme() {
        guard let url = FilePicker.chooseFile(extension: "fableskin") else { return }
        do {
            let skin = try themeStore.importSkin(from: url)
            applyTheme(id: skin.id)
            toastCenter.success("Theme imported: \(skin.name)")
        } catch {
            toastCenter.error("Couldn't import that theme file.")
        }
    }

    private func exportTheme() {
        let skin = themeStore.skin(id: settingsManager.settings.activeThemeID)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(skin.name).fableskin"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try themeStore.exportData(for: skin).write(to: url, options: .atomic)
        } catch {
            toastCenter.error("Couldn't export the theme.")
        }
    }

    private func pickBackground() {
        guard let url = FilePicker.chooseImage() else { return }
        do {
            settingsManager.settings.customBackgroundPath = try themeStore.storeCustomBackground(from: url)
        } catch {
            toastCenter.error("Couldn't use that image.")
        }
    }
}

// MARK: - Library

private struct LibrarySettingsTab: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var userRecipeStore: UserRecipeStore
    @EnvironmentObject private var toastCenter: ToastCenter

    var body: some View {
        Form {
            Section {
                Toggle("Look Up Compatibility Online (ProtonDB)", isOn: $settingsManager.settings.onlineCompatibilityLookups)
                LabeledContent("Shared Recipes") {
                    HStack(spacing: 8) {
                        if !userRecipeStore.recipes.isEmpty {
                            Text("\(userRecipeStore.recipes.count) imported")
                                .foregroundStyle(.secondary)
                        }
                        Button("Import Recipe…") { importRecipe() }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Compatibility")
            } footer: {
                Text("Off by default. When on, Fable sends a game's Steam app ID to ProtonDB for its community rating. The offline anti-cheat database always works regardless.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Fetch Cover Art Online", isOn: $settingsManager.settings.onlineArtwork)
                TextField("SteamGridDB API Key (optional)", text: $settingsManager.settings.steamGridDBKey)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Artwork")
            } footer: {
                Text("Covers come from Steam's public CDN, cached after one fetch. Add a free SteamGridDB key for titles Steam doesn't carry. Off keeps Fable fully offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fableThemedFormBackground()
    }

    private func importRecipe() {
        guard let url = FilePicker.chooseFile(extension: "fablerecipe") else { return }
        do {
            let recipe = try userRecipeStore.importRecipe(from: url)
            toastCenter.success("Imported recipe: \(recipe.name)")
        } catch {
            toastCenter.error("Couldn't import that recipe file.")
        }
    }
}

// MARK: - Defaults (everything a NEW bottle starts with — one home)

private struct DefaultsSettingsTab: View {
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        Form {
            Section {
                Picker("Windows Version", selection: $settingsManager.settings.defaultWindowsVersion) {
                    ForEach(WindowsVersion.allCases) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                Toggle("Enable DXMT (DirectX 11 via Metal)", isOn: $settingsManager.settings.defaultDXMTEnabled)

                Picker("Frame Rate Cap", selection: Binding(
                    get: { settingsManager.settings.defaultDXMTConfig.maxFrameRate ?? 0 },
                    set: { settingsManager.settings.defaultDXMTConfig.maxFrameRate = $0 == 0 ? nil : $0 }
                )) {
                    Text("Uncapped").tag(0)
                    Text("120 fps").tag(120)
                    Text("60 fps").tag(60)
                    Text("30 fps").tag(30)
                }

                Picker("DXMT Log Level", selection: $settingsManager.settings.defaultDXMTConfig.logLevel) {
                    ForEach(DXMTConfig.LogLevel.allCases) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
            } header: {
                Text("New Bottle Defaults")
            } footer: {
                Text("Applied when a bottle is created. Existing bottles keep their own settings — change those on the bottle's page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fableThemedFormBackground()
    }
}

// MARK: - Advanced

private struct AdvancedSettingsTab: View {
    @EnvironmentObject private var shaderCacheStore: ShaderCacheStore
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var toastCenter: ToastCenter

    var body: some View {
        Form {
            Section {
                LabeledContent("Saved Shaders",
                               value: shaderCacheStore.localBytes > 0 ? BottleDiskUsage.formatted(shaderCacheStore.localBytes) : "—")
                if let external = shaderCacheStore.externalLocation {
                    LabeledContent("Offloaded To") {
                        Text(external.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    }
                    Button("Bring Shaders Back to Mac") {
                        Task { await shaderCacheStore.bringBack(); toastCenter.success("Shaders restored to this Mac.") }
                    }
                    .disabled(shaderCacheStore.isWorking)
                } else {
                    Button("Back Up Shaders to External…") { backUpShaders() }
                        .disabled(shaderCacheStore.isWorking || (shaderCacheStore.localBytes == 0 && shaderCacheStore.liveBytes == 0))
                }
            } header: {
                Text("Shader Cache")
            } footer: {
                Text("Fable keeps a durable copy of D3DMetal's compiled shaders so they survive a reboot, and restores it automatically at startup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Folders") {
                LabeledContent("Bottles") {
                    Button("Open Bottles Folder") { open(AppPaths.bottles) }
                        .controlSize(.small)
                }
                LabeledContent("Components") {
                    Button("Open Components Folder") { open(AppPaths.components) }
                        .controlSize(.small)
                }
                LabeledContent("Logs") {
                    Button("Open Logs Folder") { open(AppPaths.logs) }
                        .controlSize(.small)
                }
            }

            Section {
                Button("settings.reset_onboarding") {
                    onboardingState.reset()
                }
                .help("Show the first-launch wizard again next time the app opens")
            } header: {
                Text("Onboarding")
            }
        }
        .formStyle(.grouped)
        .fableThemedFormBackground()
    }

    private func open(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func backUpShaders() {
        guard let dir = FilePicker.chooseFolder(prompt: "Back Up Here") else { return }
        Task {
            await shaderCacheStore.snapshot()       // capture the latest warmed shaders first
            await shaderCacheStore.offload(to: dir)
            toastCenter.success("Shaders backed up to \(dir.lastPathComponent).")
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    @EnvironmentObject private var appUpdateChecker: AppUpdateChecker
    @EnvironmentObject private var appState: AppState

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    LabeledContent("Fable", value: appVersion)
                    Spacer()
                    if appUpdateChecker.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check for Updates") {
                            Task { await appUpdateChecker.checkIfDue(force: true) }
                        }
                        .controlSize(.small)
                    }
                }
                if let release = appUpdateChecker.available {
                    HStack {
                        Label("Fable \(release.version) is available", systemImage: "arrow.up.circle")
                            .foregroundStyle(.tint)
                        Spacer()
                        Button("Open Release Page") { appUpdateChecker.openInBrowser() }
                            .controlSize(.small)
                    }
                } else if let lastChecked = appUpdateChecker.lastChecked, appUpdateChecker.lastError == nil {
                    Text("Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened)) — up to date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let lastError = appUpdateChecker.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Version")
            } footer: {
                // Runtime versions live in ONE place — Components (was
                // duplicated here).
                Text("Wine, DXMT, and the other runtime pieces are managed in the Components section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Link("Wine builds — Gcenx/macOS_Wine_builds",
                     destination: URL(string: "https://github.com/Gcenx/macOS_Wine_builds")!)
                Link("DXMT — 3Shain/dxmt",
                     destination: URL(string: "https://github.com/3Shain/dxmt")!)
                Link("innoextract",
                     destination: URL(string: "https://constexpr.org/innoextract/")!)
            } header: {
                Text("Built On")
            } footer: {
                Text("Fable runs Windows games through Wine with DirectX-to-Metal translation. Wine runs under Rosetta 2 — Windows games are x86, and that's fine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fableThemedFormBackground()
    }
}
