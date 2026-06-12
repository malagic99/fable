import SwiftUI

@main
struct FableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var bottleManager: BottleManager
    @StateObject private var componentManager: ComponentManager
    @StateObject private var wineManager: WineManager
    @StateObject private var dxmtManager: DXMTManager
    @StateObject private var gameLauncher = GameLauncher()

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
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .environmentObject(bottleManager)
                .environmentObject(componentManager)
                .environmentObject(wineManager)
                .environmentObject(dxmtManager)
                .environmentObject(gameLauncher)
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
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            MainContentView()
        }
        .frame(minWidth: 800, minHeight: 520)
        .navigationTitle(appState.selectedSection.title)
    }
}
