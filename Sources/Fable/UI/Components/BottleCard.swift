import SwiftUI

/// Bottle tile for the grid: cover art (fetched artwork when available, else
/// the exe icon), name, status, and quick facts, with a hover lift. When art
/// is present it fills the card behind a dark scrim so text and badges stay
/// legible at any tile size.
struct BottleCard: View {
    let bottle: Bottle
    /// Driven by the parent grid item so the card's lift and the
    /// quick-launch button's reveal share one hover state.
    var isHovering: Bool = false

    @EnvironmentObject private var diskUsageStore: BottleDiskUsageStore
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var artworkStore: ArtworkStore
    @EnvironmentObject private var settingsManager: SettingsManager

    /// The bottle's first game — its artwork/icon becomes the card's cover.
    private var primaryGame: Game? { bottle.games.first }

    private var artwork: NSImage? {
        primaryGame.flatMap { artworkStore.image(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                if artwork == nil {
                    ExeIconView(bottle: bottle, game: primaryGame, size: 52)
                }
                Spacer()
                statusBadge
            }

            Spacer(minLength: 2)

            Text(bottle.name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 5) {
                Text("\(bottle.games.count) \(bottle.games.count == 1 ? "game" : "games")")
                dot
                Text(bottle.windowsVersion.displayName)
                if let bytes = diskUsageStore.size(for: bottle.id) {
                    dot
                    Text(BottleDiskUsage.formatted(bytes))
                }
                // Keep the bottom-right corner clear for the quick-launch
                // button that overlays the card in the grid.
                Spacer(minLength: 42)
            }
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(artwork != nil ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        }
        .foregroundStyle(artwork != nil ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .background {
            if let artwork {
                ZStack {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                    // Bottom-heavy scrim keeps name + facts legible on any art.
                    LinearGradient(
                        colors: [.black.opacity(0.78), .black.opacity(0.25)],
                        startPoint: .bottom, endPoint: .top
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FableTheme.cardRadius))
        .fableCard(isHovering: isHovering)
        .task {
            // First-visit scan. The store coalesces concurrent requests, and
            // the walk runs at utility priority off the main actor — but it
            // still defers entirely while a game is running so a multi-GB tree
            // walk never contends with the session.
            if diskUsageStore.size(for: bottle.id) == nil,
               Stability.mayRunHeavyBackgroundWork(gameRunning: !gameLauncher.running.isEmpty) {
                diskUsageStore.scan(bottle, manager: bottleManager)
            }
        }
        .task(id: primaryGame?.executablePath) {
            guard let primaryGame else { return }
            await artworkStore.fetchIfNeeded(
                game: primaryGame, bottle: bottle,
                bottleManager: bottleManager, settings: settingsManager.settings
            )
        }
    }

    private var dot: some View {
        Text("·").opacity(0.6)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch bottle.status {
        case .provisioning:
            StatusBadge(text: "Setting up", color: .orange)
        case .broken:
            StatusBadge(text: "Needs repair", color: .red)
        case .ready:
            if bottle.graphicsBackend != .off {
                BackendBadge(backend: bottle.graphicsBackend)
            }
        }
    }
}
