import SwiftUI

/// A game's health as glyph + label + colour.
///
/// Replaces the bare coloured dot `CoverCard` used to draw, which encoded the
/// whole verdict in hue and told a screen reader nothing. The glyph is knocked
/// out of a filled circle so it stays legible on cover art of any brightness.
struct HealthBadge: View {
    let health: Health
    /// `.compact` sits under a cover; `.regular` in the inspector.
    var size: Size = .compact
    /// Drops the text, for rows that print the label themselves. The glyph and
    /// the accessibility label stay — this never degrades to colour alone.
    var showsLabel: Bool = true

    enum Size { case compact, regular }

    private var diameter: CGFloat { size == .compact ? 13 : 14 }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: health.symbol)
                .font(.system(size: diameter * 0.62, weight: .heavy))
                // Knocked out of the circle rather than tinted, so the glyph
                // reads against every health colour.
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(health.tint))
            if showsLabel {
                Text(health.label)
                    .font(size == .compact ? .caption : .body)
                    .foregroundStyle(health.tint)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(health.label)
    }
}
