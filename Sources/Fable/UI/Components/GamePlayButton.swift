import SwiftUI

/// Play/Stop control for any game in any bottle, running the same Smart Bottle
/// auto-pick + launch path as the grid quick-launch. Used by the Library so a
/// game launches with one click from anywhere.
struct GamePlayButton: View {
    let game: Game
    let bottle: Bottle
    var size: CGFloat = 30

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var gptkManager: GPTKManager
    @EnvironmentObject private var crossOverManager: CrossOverManager
    @EnvironmentObject private var sikarugirManager: SikarugirManager
    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var activityMonitor: ActivityMonitor
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var launchError: String?

    /// Running if Fable launched it OR a live process for it is detected
    /// (e.g. started from inside Steam, or lingering after its window closed).
    private var isRunning: Bool {
        gameLauncher.isRunning(game.id) || activityMonitor.isRunning(game, in: bottle)
    }

    /// A Steam game (under steamapps/common) that isn't Steam itself needs the
    /// Steam client already running to launch.
    private var needsSteamRunning: Bool {
        let path = game.executablePath.lowercased().replacingOccurrences(of: "\\", with: "/")
        return path.contains("steamapps/common") && !path.hasSuffix("steam.exe")
    }

    var body: some View {
        Button {
            if isRunning { stop() } else { launch() }
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
        // Steam games need the Steam client up first — surface that instead of
        // letting the raw exe fail cryptically.
        if needsSteamRunning && !activityMonitor.isSteamRunning(in: bottle) {
            toastCenter.error("“\(game.name)” is a Steam game — start Steam in this bottle first, then launch it from your Steam library.")
        }
        Task {
            let prepared = await bottleManager.prepareSmartBackend(
                for: game, in: bottle,
                crossOverAvailable: crossOverManager.isInstalled,
                sikarugirAvailable: sikarugirManager.isDiscovered
            )
            let fresh = bottleManager.bottle(with: bottle.id) ?? bottle
            do {
                try gameLauncher.launch(
                    prepared, in: fresh,
                    bottleManager: bottleManager, wineManager: wineManager,
                    gptkManager: gptkManager, crossOverManager: crossOverManager,
                    sikarugirManager: sikarugirManager
                )
            } catch {
                launchError = error.localizedDescription
            }
        }
    }

    /// Stop what Fable launched; if the game is only *detected* (started
    /// externally or lingering), fall back to killing the bottle's wine tree.
    private func stop() {
        if gameLauncher.isRunning(game.id) {
            gameLauncher.stop(game.id)
        } else {
            Task {
                try? await wineManager.forceKillPrefix(bottleManager.prefixDirectory(for: bottle))
            }
        }
    }
}
