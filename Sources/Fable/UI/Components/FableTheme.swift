import SwiftUI

/// Fable's design language in one place: the brand gradient, card surface,
/// backend tints, and the shared exe-icon view. Every grid card and hero uses
/// these so the app reads as one hand, not thirty feature branches.
enum FableTheme {
    /// The identity: the wineglass purple→indigo from onboarding, carried
    /// through the whole app. Themes override it via `\.fableGradient`.
    static let accentGradient = LinearGradient(
        colors: [.purple, .indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Shape scale — exactly two radii, everywhere.
    /// Containers: cards, inspectors, tiles, selection rings.
    static let cardRadius: CGFloat = 12
    /// Elements inside a container: cover art, chips, small marks.
    static let innerRadius: CGFloat = 8

    // MARK: Surface scale — three semantic tones instead of ad-hoc
    // `.quaternary.opacity(…)` values scattered per view.
    /// A resting panel (inspector, sidebar-ish blocks).
    static let surface = AnyShapeStyle(.quaternary.opacity(0.4))
    /// A raised element on a surface (cover placeholder, chips, search field).
    static let surfaceRaised = AnyShapeStyle(.quaternary.opacity(0.6))
    /// The selected/active state of a raised element.
    static let surfaceSelected = AnyShapeStyle(.quaternary.opacity(0.75))

    /// One tint per backend — quiet, informative colors (never alarm-red;
    /// red is reserved for actual problems).
    static func tint(for backend: GraphicsBackend) -> Color {
        switch backend {
        case .dxmt: .blue
        case .gptk: .purple
        case .dxvk: .teal
        case .crossover: .green
        case .sikarugir: .indigo
        case .off: .secondary
        }
    }

    /// Delegates to the model's one compact label — two switch statements for
    /// the same concept is how the "Wine"/"Built-in" drift happened.
    static func label(for backend: GraphicsBackend) -> String { backend.shortName }
}

/// Tile sizing driven by `AppSettings.tileScale`, so the same slider grows both
/// the portrait cover wall (Gamer) and the wider bottle cards (Classic) —
/// laptop-tight to couch-distance.
enum TileMetrics {
    static let range: ClosedRange<Double> = 0.7...1.8
    static func clamp(_ v: Double) -> Double { min(max(v, range.lowerBound), range.upperBound) }

    /// Adaptive minimum for a portrait game cover.
    static func coverMin(_ scale: Double) -> CGFloat { 132 * clamp(scale) }
    /// Adaptive minimum for a wide bottle card.
    static func cardMin(_ scale: Double) -> CGFloat { 224 * clamp(scale) }
}

/// The Finder-style tile resizer: two glyphs bracketing a slider. Bound to the
/// scale so both grids resize live.
struct TileSizeControl: View {
    @Binding var scale: Double

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.grid.3x3").font(.caption2).foregroundStyle(.secondary)
            Slider(value: $scale, in: TileMetrics.range)
                .frame(width: 96)
            Image(systemName: "square.grid.2x2").font(.footnote).foregroundStyle(.secondary)
        }
        .help("Resize tiles")
    }
}

/// The one capsule for "which backend renders this" — replaces the two
/// hand-rolled switch statements that had drifted (and the alarm-pink).
struct BackendBadge: View {
    let backend: GraphicsBackend

    var body: some View {
        StatusBadge(text: FableTheme.label(for: backend), color: FableTheme.tint(for: backend))
    }
}

/// Shared card surface: soft material fill, hairline border, hover lift with
/// a faint brand-tinted glow. Both grids and any future tiles use this.
struct FableCard: ViewModifier {
    var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                .quaternary.opacity(isHovering ? 0.75 : 0.5),
                in: RoundedRectangle(cornerRadius: FableTheme.cardRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                    .strokeBorder(
                        isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: .black.opacity(isHovering ? 0.18 : 0.07),
                radius: isHovering ? 10 : 4,
                y: isHovering ? 4 : 2
            )
            .scaleEffect(isHovering ? 1.015 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.25), value: isHovering)
    }
}

extension View {
    func fableCard(isHovering: Bool = false) -> some View {
        modifier(FableCard(isHovering: isHovering))
    }
}

/// The active theme's identity gradient, injected at the app root so every
/// brand mark and fallback cover re-skins together.
private struct FableGradientKey: EnvironmentKey {
    static let defaultValue = FableTheme.accentGradient
}

/// True when the active theme paints a window wash (Midnight, OG Steam, Pitch
/// Black, or a custom background). Grouped forms/lists read this to drop their
/// own opaque backing so the wash — e.g. Pitch Black's pure #000000 — shows
/// through instead of being covered by a lighter panel.
private struct FableWindowTintedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var fableGradient: LinearGradient {
        get { self[FableGradientKey.self] }
        set { self[FableGradientKey.self] = newValue }
    }

    var fableWindowTinted: Bool {
        get { self[FableWindowTintedKey.self] }
        set { self[FableWindowTintedKey.self] = newValue }
    }
}

private struct ThemedFormBackground: ViewModifier {
    @Environment(\.fableWindowTinted) private var tinted
    func body(content: Content) -> some View {
        if tinted {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

extension View {
    /// Lets the themed window wash show through a grouped `Form`/`List` when a
    /// tinted theme is active; a no-op otherwise, so the default look is
    /// unchanged. Apply after `.formStyle(.grouped)` / `.listStyle(...)`.
    func fableThemedFormBackground() -> some View { modifier(ThemedFormBackground()) }
}

/// The one exe-icon view: loads a game's icon from its exe (off the main
/// actor), falling back to a symbol on the brand gradient. Replaces the three
/// copy-pasted loaders in BottleCard / LibraryGameCard / GameLauncherView.
struct ExeIconView: View {
    let bottle: Bottle
    let game: Game?
    var size: CGFloat = 44
    var fallbackSymbol: String = "wineglass"

    @EnvironmentObject private var bottleManager: BottleManager
    @Environment(\.fableGradient) private var gradient
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(
                        gradient,
                        in: RoundedRectangle(cornerRadius: size * 0.22)
                    )
            }
        }
        .task(id: game?.executablePath) {
            guard let game else { icon = nil; return }
            let exe = bottleManager.driveCDirectory(for: bottle).appending(path: game.executablePath)
            let data = await Task.detached(priority: .utility) { () -> Data? in
                guard let bytes = try? Data(contentsOf: exe, options: .alwaysMapped) else { return nil }
                return ExeIconExtractor.icoData(from: bytes)
            }.value
            icon = data.flatMap { NSImage(data: $0) }
        }
    }
}
