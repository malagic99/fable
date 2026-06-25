import SwiftUI

/// Bottle tile for the grid: icon, name, status, and quick facts, with
/// a hover lift.
struct BottleCard: View {
    let bottle: Bottle
    /// Driven by the parent grid item so the card's lift and the
    /// quick-launch button's reveal share one hover state.
    var isHovering: Bool = false

    @EnvironmentObject private var diskUsageStore: BottleDiskUsageStore
    @EnvironmentObject private var bottleManager: BottleManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "wineglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                Spacer()
                statusBadge
            }

            Text(bottle.name)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 10) {
                Label("\(bottle.games.count)", systemImage: "gamecontroller")
                    .help("\(bottle.games.count) game(s)")
                Text(bottle.windowsVersion.displayName)
                if let bytes = diskUsageStore.size(for: bottle.id) {
                    Label(BottleDiskUsage.formatted(bytes), systemImage: "internaldrive")
                        .help("Prefix size on disk")
                } else {
                    Text(bottle.createdAt, format: .dateTime.day().month())
                }
                // Keep the bottom-right corner clear for the quick-launch
                // button that overlays the card in the grid.
                Spacer(minLength: 46)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(14)
        .background(.quaternary.opacity(isHovering ? 0.8 : 0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(isHovering ? 0.15 : 0.06),
            radius: isHovering ? 8 : 3,
            y: 2
        )
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(.spring(duration: 0.2), value: isHovering)
        .task {
            // First-visit scan. The store coalesces concurrent requests,
            // and the walk runs at utility priority off the main actor.
            if diskUsageStore.size(for: bottle.id) == nil {
                diskUsageStore.scan(bottle, manager: bottleManager)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch bottle.status {
        case .provisioning:
            StatusBadge(text: "Setting up", color: .orange)
        case .broken:
            StatusBadge(text: "Needs repair", color: .red)
        case .ready:
            switch bottle.graphicsBackend {
            case .dxmt:
                StatusBadge(text: "DXMT", color: .blue)
            case .gptk:
                StatusBadge(text: "GPTK", color: .purple)
            case .dxvk:
                StatusBadge(text: "DXVK", color: .teal)
            case .crossover:
                StatusBadge(text: "CrossOver", color: .green)
            case .sikarugir:
                StatusBadge(text: "Sikarugir", color: .pink)
            case .off:
                EmptyView()
            }
        }
    }
}
