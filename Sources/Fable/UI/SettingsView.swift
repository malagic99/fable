import SwiftUI

/// Settings section: General (new-bottle defaults, folders),
/// Performance (DXMT defaults), About.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            PerformanceSettingsTab()
                .tabItem { Label("Performance", systemImage: "speedometer") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var userRecipeStore: UserRecipeStore
    @EnvironmentObject private var toastCenter: ToastCenter

    var body: some View {
        Form {
            Section {
                Toggle("Advanced Mode", isOn: $settingsManager.settings.advancedMode)
            } header: {
                Text("Interface")
            } footer: {
                Text("Off: a clean click-and-play view of each bottle's games. On: the full graphics backend, performance, dependency, storage, and troubleshooting panels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                Text("Off by default. When on, Fable sends a game's Steam app ID to ProtonDB to fetch its community rating, shown in the compatibility banner. The offline anti-cheat database always works regardless of this setting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("New Bottle Defaults") {
                Picker("Windows Version", selection: $settingsManager.settings.defaultWindowsVersion) {
                    ForEach(WindowsVersion.allCases) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                Toggle("Enable DXMT (DirectX 11 via Metal)", isOn: $settingsManager.settings.defaultDXMTEnabled)
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
        }
        .formStyle(.grouped)
    }

    private func open(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func importRecipe() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["fablerecipe"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let recipe = try userRecipeStore.importRecipe(from: url)
            toastCenter.success("Imported recipe: \(recipe.name)")
        } catch {
            toastCenter.error("Couldn't import that recipe file.")
        }
    }
}

private struct PerformanceSettingsTab: View {
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        Form {
            Section {
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
                Text("DXMT Defaults for New Bottles")
            } footer: {
                Text("Existing bottles keep their own Graphics settings — change those on the bottle's page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutTab: View {
    @EnvironmentObject private var updateManager: UpdateManager
    @EnvironmentObject private var appUpdateChecker: AppUpdateChecker
    @EnvironmentObject private var onboardingState: OnboardingState
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
                LabeledContent("Wine", value: updateManager.installedVersion(of: WineManager.componentID) ?? "not installed")
                LabeledContent("DXMT", value: updateManager.installedVersion(of: DXMTManager.componentID) ?? "not installed")
            } header: {
                Text("Versions")
            }

            Section {
                Button("settings.reset_onboarding") {
                    onboardingState.reset()
                }
                .help("Show the first-launch wizard again next time the app opens")
            } header: {
                Text("Onboarding")
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
    }
}
