import SwiftUI

/// THE cover tile — one implementation for both worlds (Wine and native).
/// Cover art or a caller-supplied fallback, a health badge, the "Playing"
/// chip, selection ring, hover spring, and a caller-supplied context menu.
/// The wine/native wrappers in GameWallView only decide what to feed it.
///
/// Health reads as glyph + label under the cover rather than as a coloured
/// dot on it. The dot put the whole verdict in hue — on a green/amber/red
/// scale, which is the combination red-green colour deficiency collapses —
/// and carried nothing for VoiceOver but a tooltip.
struct CoverCard<Fallback: View, Menu: View>: View {
    let artwork: NSImage?
    let name: String
    /// What the badge under the cover reports. `.native` carries its own
    /// glyph, so native games no longer need a separate marker.
    let health: Health
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
                .overlay(alignment: .topLeading) {
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

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HealthBadge(health: health)
            }
            .padding(.horizontal, 3)
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
        .contextMenu { menu }
    }
}
