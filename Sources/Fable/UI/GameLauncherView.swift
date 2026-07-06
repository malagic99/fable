import SwiftUI

/// One game row: play/stop, status, and a debugging menu (logs, reveal,
/// remove).
struct GameLauncherView: View {
    let game: Game
    let bottle: Bottle

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var metricsStore: RunningGameMetricsStore
    @EnvironmentObject private var activityMonitor: ActivityMonitor
    @EnvironmentObject private var gameStats: GameStatsStore

    @State private var launchError: String?
    @State private var isShowingSettings = false
    @State private var logToView: PickedExecutable?
    @State private var isShowingDoctor = false
    @State private var doctorFindings: [CompatibilityFinding] = []
    @State private var icon: NSImage?

    private var isRunning: Bool {
        gameLauncher.isRunning(game, in: bottle, activity: activityMonitor)
    }

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name)
                    statusText
                }
            } icon: {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "gamecontroller")
                        .foregroundStyle(isRunning ? .green : .secondary)
                        .frame(width: 26, height: 26)
                }
            }

            Spacer()

            if isRunning {
                Button {
                    stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop \(game.name)")
            } else {
                Button {
                    launch()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .help("Launch \(game.name)")
                .disabled(bottle.status != .ready)
            }

            Menu {
                Button("Game Settings…") { isShowingSettings = true }
                Button("Create Desktop Shortcut") { createShortcut() }
                    .help("A double-clickable app on your Desktop that launches this game directly")
                if let log = gameLauncher.lastLog[game.id] {
                    Button("View Last Log") { logToView = PickedExecutable(url: log) }
                    Button("Diagnose Last Run…") {
                        doctorFindings = GameDoctor.diagnose(logFile: log)
                        // The strongest diagnosis first: identical crash on
                        // two backends means it's the game, not the setup.
                        if let cross = gameStats.crossBackendCrash(game.id) {
                            doctorFindings.insert(
                                GameDoctor.crossBackendFinding(
                                    signature: cross.signature,
                                    backends: cross.backends.map { GraphicsBackend(rawValue: $0)?.shortName ?? $0 }
                                ),
                                at: 0
                            )
                        }
                        isShowingDoctor = true
                    }
                        .help("Fable Doctor reads the log and explains what went wrong")
                }
                Button("Reveal in Finder") {
                    let exe = bottleManager.driveCDirectory(for: bottle)
                        .appending(path: game.executablePath)
                    NSWorkspace.shared.activateFileViewerSelecting([exe])
                }
                Divider()
                Button("Remove from Bottle", role: .destructive) {
                    try? bottleManager.removeGame(game.id, from: bottle.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !isRunning && bottle.status == .ready {
                launch()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            GameSettingsView(game: game, bottle: bottle)
        }
        .sheet(item: $logToView) { log in
            LogViewerView(logURL: log.url)
        }
        .sheet(isPresented: $isShowingDoctor) {
            DoctorSheet(gameName: game.name, findings: doctorFindings)
        }
        .task(id: game.executablePath) {
            let exe = bottleManager.driveCDirectory(for: bottle)
                .appending(path: game.executablePath)
            let icoData = await Task.detached(priority: .utility) { () -> Data? in
                guard let data = try? Data(contentsOf: exe, options: .alwaysMapped) else {
                    return nil
                }
                return ExeIconExtractor.icoData(from: data)
            }.value
            icon = icoData.flatMap { NSImage(data: $0) }
        }
        .alert("Couldn't Launch Game", isPresented: .init(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchError ?? "")
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if isRunning {
            HStack(spacing: 6) {
                Text("Running")
                    .foregroundStyle(.green)
                if let metric = metricsStore.metrics[game.id], metric.residentBytes > 0 {
                    Text("·").foregroundStyle(.tertiary)
                    Text(formattedMetric(metric))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        } else if let code = gameLauncher.lastExitCode[game.id], code != 0 {
            Text(L10n.string("game.last_exit_code", String(code)))
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let override = game.graphicsBackend, override != bottle.graphicsBackend {
            Text(L10n.string("game.backend_override", override.shortName))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedMetric(_ metric: ProcessMetrics) -> String {
        let mem = ByteCountFormatter.string(
            fromByteCount: metric.residentBytes, countStyle: .memory
        )
        let cpu = String(format: "%.0f%%", metric.cpuPercent)
        return "\(mem) · \(cpu) CPU"
    }

    private func stop() {
        gameLauncher.stopSmart(game, in: bottle)
    }

    private func launch() {
        Task {
            do {
                try await gameLauncher.launchSmart(game, in: bottle)
            } catch {
                launchError = error.localizedDescription
            }
        }
    }

    private func createShortcut() {
        do {
            let plan = try gameLauncher.makeLaunchPlan(game, in: bottle)
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop")
            let app = try ShortcutGenerator.createApp(named: game.name, plan: plan, in: desktop)
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            launchError = error.localizedDescription
        }
    }
}
