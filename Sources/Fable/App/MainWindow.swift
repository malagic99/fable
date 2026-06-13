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
    @StateObject private var winetricksManager: WinetricksManager
    @StateObject private var updateManager: UpdateManager
    @StateObject private var appUpdateChecker = AppUpdateChecker()
    @StateObject private var diskUsageStore = BottleDiskUsageStore()
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
                    Task { await appUpdateChecker.checkIfDue() }
                }
                .environmentObject(appState)
                .environmentObject(bottleManager)
                .environmentObject(componentManager)
                .environmentObject(wineManager)
                .environmentObject(dxmtManager)
                .environmentObject(gptkManager)
                .environmentObject(winetricksManager)
                .environmentObject(updateManager)
                .environmentObject(appUpdateChecker)
                .environmentObject(diskUsageStore)
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
    }
}
