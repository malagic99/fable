import SwiftUI

/// Bottle tile for the grid: cover art, name, status, and quick facts, with
/// a hover lift. Surface + badge styling come from FableTheme.
struct BottleCard: View {
    let bottle: Bottle
    /// Driven by the parent grid item so the card's lift and the
    /// quick-launch button's reveal share one hover state.
    var isHovering: Bool = false

    @EnvironmentObject private var diskUsageStore: BottleDiskUsageStore
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var gameLauncher: GameLauncher

    /// The bottle's first game — its icon becomes the card's cover art.
    private var primaryGame: Game? { bottle.games.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ExeIconView(bottle: bottle, game: primaryGame, size: 52)
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
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
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
    }

    private var dot: some View {
        Text("·").foregroundStyle(.tertiary)
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
