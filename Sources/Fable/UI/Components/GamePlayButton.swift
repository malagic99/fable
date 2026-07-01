import SwiftUI

/// Play/Stop control for any game in any bottle, running the one launch flow
/// (`GameLauncher.launchSmart`). Used by the Library so a game launches with
/// one click from anywhere.
struct GamePlayButton: View {
    let game: Game
    let bottle: Bottle
    var size: CGFloat = 30

    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var activityMonitor: ActivityMonitor

    @State private var launchError: String?

    /// Running if Fable launched it OR a live process for it is detected
    /// (e.g. started from inside Steam, or lingering after its window closed).
    private var isRunning: Bool {
        gameLauncher.isRunning(game.id) || activityMonitor.isRunning(game, in: bottle)
    }

    var body: some View {
        Button {
            if isRunning {
                gameLauncher.stopSmart(game, in: bottle)
            } else {
                launch()
            }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .font(.system(size: size * 0.43, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(isRunning ? Color.red : Color.accentColor))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(bottle.status != .ready)
        .help(isRunning ? "Stop \(game.name)" : "Launch \(game.name)")
        .alert("Couldn't Launch", isPresented: .init(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchError ?? "")
        }
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
}
