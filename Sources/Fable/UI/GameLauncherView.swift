import SwiftUI

/// One game row: play/stop, status, and a debugging menu (logs, reveal,
/// remove).
struct GameLauncherView: View {
    let game: Game
    let bottle: Bottle

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var gameLauncher: GameLauncher

    @State private var launchError: String?

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
                Image(systemName: "gamecontroller")
                    .foregroundStyle(isRunning ? .green : .secondary)
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
                if let log = gameLauncher.lastLog[game.id] {
                    Button("Show Last Log") {
                        NSWorkspace.shared.activateFileViewerSelecting([log])
                    }
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
            Text("Running")
                .font(.caption)
                .foregroundStyle(.green)
        } else if let code = gameLauncher.lastExitCode[game.id], code != 0 {
            Text("Last run exited with code \(code)")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func launch() {
        do {
            try gameLauncher.launch(
                game,
                in: bottle,
                bottleManager: bottleManager,
                wineManager: wineManager
            )
        } catch {
            launchError = error.localizedDescription
        }
    }
}
