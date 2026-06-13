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

    var body: some View {
        Form {
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
