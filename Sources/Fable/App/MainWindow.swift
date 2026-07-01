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
    @StateObject private var redistInstaller = RedistInstaller()
    @StateObject private var thermalMonitor = ThermalMonitor()
    @StateObject private var quirkService = QuirkService()
    @StateObject private var userRecipeStore = UserRecipeStore()
    @StateObject private var shaderCacheStore = ShaderCacheStore()
    @StateObject private var activityMonitor = ActivityMonitor()
    @StateObject private var triggerController = DualSenseTriggerController()

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
                    // Wire the launcher's collaborators once — every Play
                    // control then runs the same launchSmart/stopSmart flow.
                    gameLauncher.configure(.init(
                        bottleManager: bottleManager,
                        wineManager: wineManager,
                        gptkManager: gptkManager,
                        crossOverManager: crossOverManager,
                        sikarugirManager: sikarugirManager,
                        triggerController: triggerController,
                        activityMonitor: activityMonitor,
                        toastCenter: toastCenter
                    ))
                    gameLauncher.onAbnormalExit = { [weak toastCenter] message in
                        toastCenter?.error(message)
                    }
                    gameLauncher.onProcessLifecycle = { [weak metricsStore, weak triggerController] id, pid in
                        if let pid {
                            metricsStore?.startTracking(id, rootPID: pid)
                        } else {
                            metricsStore?.stopTracking(id)
                            // Clear any adaptive-trigger effect when the game exits.
                            triggerController?.reset()
                        }
                    }
                    // Quitting Steam is the moment to finish any install stuck
                    // on the WoW64 commit step, then run the runtimes Steam
                    // unpacked but never executed — both no-ops for non-Steam
                    // bottles and idempotent once done.
                    gameLauncher.onGameFullyExited = { [weak bottleManager, weak toastCenter, weak wineManager, weak redistInstaller] bottleID in
                        guard let bottleManager, let bottle = bottleManager.bottle(with: bottleID) else { return }
                        Task {
                            let committed = await bottleManager.commitStuckSteamInstalls(in: bottle)
                            if !committed.isEmpty {
                                toastCenter?.success("Finished installing: \(committed.joined(separator: ", "))")
                            }
                            // Run any bundled VC++/DirectX redists the install left behind.
                            if let wineManager, let redistInstaller {
                                let runtimes = await bottleManager.installPendingSteamRedists(
                                    in: bottle, redistInstaller: redistInstaller, wineManager: wineManager
                                )
                                if !runtimes.isEmpty {
                                    toastCenter?.success("Installed game runtimes: \(runtimes.joined(separator: ", "))")
                                }
                            }
                            // Persist the shaders this session warmed, so a macOS
                            // purge of the volatile darwin cache can't lose them.
                            await shaderCacheStore.snapshot()
                        }
                    }
                    // When the Mac starts thermal-throttling mid-session (the
                    // "great for an hour, then it slips" cause), nudge toward
                    // Rock Solid — only if a game is actually running.
                    thermalMonitor.onThrottleOnset = { [weak gameLauncher, weak toastCenter] in
                        guard let gameLauncher, !gameLauncher.running.isEmpty else { return }
                        toastCenter?.error("Your Mac is thermal-throttling. Open the bottle's Performance section and tap Rock Solid to hold a steadier frame rate.")
                    }
                    Task { await appUpdateChecker.checkIfDue() }
                    // Restore warmed shaders if macOS purged the volatile darwin
                    // cache since last run (e.g. across a reboot) — once at start.
                    Task { await shaderCacheStore.restoreLiveIfPurged() }
                    // Reflect games actually running (incl. Steam-launched ones).
                    activityMonitor.start()
                    // Keep wine launch logs from eating the disk (a single
                    // spammy channel can balloon one log to tens of GB).
                    Task.detached(priority: .utility) { LogPruner.prune() }
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
                .environmentObject(thermalMonitor)
                .environmentObject(quirkService)
                .environmentObject(userRecipeStore)
                .environmentObject(shaderCacheStore)
                .environmentObject(activityMonitor)
                .environmentObject(triggerController)
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
