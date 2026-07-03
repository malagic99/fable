import SwiftUI

/// THE cover tile — one implementation for both worlds (Wine and native).
/// Cover art or a caller-supplied fallback, an optional health dot, the
/// "Playing" chip, selection ring, hover spring, and a caller-supplied
/// context menu. The wine/native wrappers in GameWallView only decide what
/// to feed it.
struct CoverCard<Fallback: View, Menu: View>: View {
    let artwork: NSImage?
    let name: String
    /// Health verdict dot (tint + tooltip); nil = no dot (native games).
    let healthDot: (tint: Color, label: String)?
    /// Shows the  glyph next to the name (native games).
    let isNative: Bool
    let isSelected: Bool
    let isRunning: Bool
    @ViewBuilder let fallback: Fallback
    @ViewBuilder let menu: Menu

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: FableTheme.innerRadius)
                .fill(FableTheme.surfaceRaised)
                .overlay {
                    if let artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else {
                        fallback
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: FableTheme.innerRadius))
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if let healthDot {
                        Circle()
                            .fill(healthDot.tint)
                            .frame(width: 10, height: 10)
                            .padding(4)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(6)
                            .help(healthDot.label)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isRunning {
                        Label("Playing", systemImage: "play.fill")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.green)
                            .padding(6)
                    }
                }

            HStack(spacing: 4) {
                if isNative {
                    Image(systemName: "applelogo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Native macOS — no Wine involved")
                }
                Text(name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                .fill(isSelected ? FableTheme.surfaceSelected : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.25), value: isHovering)
        .onHover { isHovering = $0 }
        .help("Click to inspect · double-click to play")
        .contextMenu { menu }
    }
}
