import SwiftUI

/// Play/Stop control for a bottle's primary game (`games.first`), so a
/// bottle can be launched straight from the grid without opening its
/// detail page. No-op when the bottle has no games or isn't ready.
struct BottleQuickLaunchButton: View {
    let bottle: Bottle

    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var activityMonitor: ActivityMonitor

    @State private var launchError: String?

    /// The game a one-click launch runs — the first registered game
    /// (Steam, for a Steam bottle; the single game otherwise).
    private var primaryGame: Game? { bottle.games.first }

    private var isRunning: Bool {
        guard let primaryGame else { return false }
        return gameLauncher.isRunning(primaryGame, in: bottle, activity: activityMonitor)
    }

    var body: some View {
        if let primaryGame {
            Button {
                if isRunning {
                    gameLauncher.stopSmart(primaryGame, in: bottle)
                } else {
                    launch(primaryGame)
                }
            } label: {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(isRunning ? Color.red : Color.accentColor)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(bottle.status != .ready)
            .help(L10n.string(isRunning ? "game.action.stop_named" : "game.action.launch_named", primaryGame.name))
            .contextMenu {
                Button("Create Desktop Shortcut") { createShortcut(primaryGame) }
            }
            .alert("Couldn't Launch", isPresented: .init(
                get: { launchError != nil },
                set: { if !$0 { launchError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(launchError ?? "")
            }
        }
    }

    private func launch(_ game: Game) {
        Task {
            do {
                try await gameLauncher.launchSmart(game, in: bottle)
            } catch {
                launchError = error.localizedDescription
            }
        }
    }

    private func createShortcut(_ game: Game) {
        do {
            let plan = try gameLauncher.makeLaunchPlan(game, in: bottle)
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop")
            let app = try ShortcutGenerator.createApp(named: "\(bottle.name) — \(game.name)", plan: plan, in: desktop)
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            launchError = error.localizedDescription
        }
    }
}
