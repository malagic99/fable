import SwiftUI

@main
struct FableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var bottleManager: BottleManager
    @StateObject private var componentManager: ComponentManager
    @StateObject private var wineManager: WineManager
    @StateObject private var dxmtManager: DXMTManager
    @StateObject private var gptkManager: GPTKManager
    @StateObject private var crossOverManager = CrossOverManager()
    @StateObject private var sikarugirManager: SikarugirManager
    @StateObject private var winetricksManager: WinetricksManager
    @StateObject private var updateManager: UpdateManager
    @StateObject private var appUpdateChecker = AppUpdateChecker()
    @StateObject private var diskUsageStore = BottleDiskUsageStore()
    @StateObject private var metricsStore = RunningGameMetricsStore()
    @StateObject private var onboardingState = OnboardingState()
    @StateObject private var gameLauncher = GameLauncher()
    @StateObject private var toastCenter = ToastCenter()
    @StateObject private var settingsManager = SettingsManager()

    init() {
        let appState = AppState()
        let componentManager = ComponentManager()
        _appState = StateObject(wrappedValue: appState)
        _bottleManager = StateObject(wrappedValue: BottleManager())
        _componentManager = StateObject(wrappedValue: componentManager)
        _wineManager = StateObject(wrappedValue: WineManager(
            componentManager: componentManager,
            catalog: appState.versionCatalog
        ))
        _dxmtManager = StateObject(wrappedValue: DXMTManager(
            componentManager: componentManager,
            catalog: appState.versionCatalog
        ))
        _gptkManager = StateObject(wrappedValue: GPTKManager(
            componentManager: componentManager,
            catalog: appState.versionCatalog
        ))
        _sikarugirManager = StateObject(wrappedValue: SikarugirManager(
            componentManager: componentManager
        ))
        _winetricksManager = StateObject(wrappedValue: WinetricksManager(
            componentManager: componentManager,
            catalog: appState.versionCatalog
        ))
        _updateManager = StateObject(wrappedValue: UpdateManager(
            componentManager: componentManager,
            catalog: appState.versionCatalog
        ))
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .onAppear {
                    gameLauncher.onAbnormalExit = { [weak toastCenter] message in
                        toastCenter?.error(message)
                    }
                    gameLauncher.onProcessLifecycle = { [weak metricsStore] id, pid in
                        if let pid {
                            metricsStore?.startTracking(id, rootPID: pid)
                        } else {
                            metricsStore?.stopTracking(id)
                        }
                    }
                    // Quitting Steam is the moment to finish any install stuck
                    // on the WoW64 commit step — no-op for non-Steam bottles.
                    gameLauncher.onGameFullyExited = { [weak bottleManager, weak toastCenter] bottleID in
                        guard let bottleManager, let bottle = bottleManager.bottle(with: bottleID) else { return }
                        Task {
                            let committed = await bottleManager.commitStuckSteamInstalls(in: bottle)
                            if !committed.isEmpty {
                                toastCenter?.success("Finished installing: \(committed.joined(separator: ", "))")
                            }
                        }
                    }
                    Task { await appUpdateChecker.checkIfDue() }
                }
                .environmentObject(appState)
                .environmentObject(bottleManager)
                .environmentObject(componentManager)
                .environmentObject(wineManager)
                .environmentObject(dxmtManager)
                .environmentObject(gptkManager)
                .environmentObject(crossOverManager)
                .environmentObject(sikarugirManager)
                .environmentObject(winetricksManager)
                .environmentObject(updateManager)
                .environmentObject(appUpdateChecker)
                .environmentObject(diskUsageStore)
                .environmentObject(metricsStore)
                .environmentObject(onboardingState)
                .environmentObject(gameLauncher)
                .environmentObject(toastCenter)
                .environmentObject(settingsManager)
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var onboardingState: OnboardingState

    var body: some View {
        VStack(spacing: 0) {
            AppUpdateBanner()
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            } detail: {
                MainContentView()
            }
        }
        .toastOverlay()
        .frame(minWidth: 800, minHeight: 520)
        .navigationTitle(appState.selectedSection.title)
        .sheet(isPresented: Binding(
            get: { onboardingState.isShowingWizard },
            set: { newValue in
                if !newValue { onboardingState.hasCompleted = true }
            }
        )) {
            OnboardingView()
        }
    }
}
