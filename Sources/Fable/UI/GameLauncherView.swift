import SwiftUI

/// One game row: play/stop, status, and a debugging menu (logs, reveal,
/// remove).
struct GameLauncherView: View {
    let game: Game
    let bottle: Bottle

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var gptkManager: GPTKManager
    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var metricsStore: RunningGameMetricsStore

    @State private var launchError: String?
    @State private var isShowingSettings = false
    @State private var logToView: URL?
    @State private var icon: NSImage?

    private var isRunning: Bool {
        gameLauncher.isRunning(game.id)
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
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "gamecontroller")
                        .foregroundStyle(isRunning ? .green : .secondary)
                }
            }

            Spacer()

            if isRunning {
                Button {
                    gameLauncher.stop(game.id)
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
                if let log = gameLauncher.lastLog[game.id] {
                    Button("View Last Log") { logToView = log }
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
            LogViewerView(logURL: log)
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
            Text("Last run exited with code \(code)")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if let override = game.graphicsBackend, override != bottle.graphicsBackend {
            Text("Backend override: \(override.shortName)")
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

    private func launch() {
        do {
            try gameLauncher.launch(
                game,
                in: bottle,
                bottleManager: bottleManager,
                wineManager: wineManager,
                gptkManager: gptkManager
            )
        } catch {
            launchError = error.localizedDescription
        }
    }
}
