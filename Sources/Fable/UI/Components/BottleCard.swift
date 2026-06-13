import SwiftUI

/// Bottle tile for the grid: icon, name, status, and quick facts, with
/// a hover lift.
struct BottleCard: View {
    let bottle: Bottle

    @EnvironmentObject private var diskUsageStore: BottleDiskUsageStore
    @EnvironmentObject private var bottleManager: BottleManager
    @State private var isHovering = false

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
                Spacer()
                if let bytes = diskUsageStore.size(for: bottle.id) {
                    Label(BottleDiskUsage.formatted(bytes), systemImage: "internaldrive")
                        .help("Prefix size on disk")
                } else {
                    Text(bottle.createdAt, format: .dateTime.day().month())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
        .onHover { isHovering = $0 }
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
            case .off:
                EmptyView()
            }
        }
    }
}
