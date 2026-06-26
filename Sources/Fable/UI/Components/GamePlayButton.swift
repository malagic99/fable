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

    @State private var launchError: String?

    private var isRunning: Bool { gameLauncher.isRunning(game.id) }

    var body: some View {
        Button {
            if isRunning { gameLauncher.stop(game.id) } else { launch() }
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
}
