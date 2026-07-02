import SwiftUI

/// Onboarding step: pick the app's face. Two live-sketched previews — the
/// Classic utility (bottles and tools first) and the Gamer cover wall (games
/// first). The choice writes straight to settings and is switchable any time
/// in Settings → Interface.
struct InterfaceStyleStep: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var settingsManager: SettingsManager

    private var selection: InterfaceStyle {
        settingsManager.settings.interfaceStyle
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("How should Fable feel?")
                    .font(.largeTitle.weight(.semibold))
                Text("Pick a default — you can switch any time in Settings → Interface.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                StyleChoiceCard(
                    style: .gamer,
                    isSelected: selection == .gamer,
                    preview: { GamerPreviewSketch() }
                ) { settingsManager.settings.interfaceStyle = .gamer }

                StyleChoiceCard(
                    style: .classic,
                    isSelected: selection == .classic,
                    preview: { ClassicPreviewSketch() }
                ) { settingsManager.settings.interfaceStyle = .classic }
            }
            .padding(.horizontal, 40)

            Spacer()

            HStack {
                Button("Back") { onboardingState.goBack() }
                Spacer()
                Button("Continue") { onboardingState.advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
    }
}

/// One selectable style: a sketch preview above the name + blurb.
private struct StyleChoiceCard<Preview: View>: View {
    let style: InterfaceStyle
    let isSelected: Bool
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                preview()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(style.displayName)
                            .font(.headline)
                        Text(style.blurb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: 300)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: FableTheme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: FableTheme.cardRadius))
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

/// Miniature of the Gamer face: rail + cover wall with confidence dots.
private struct GamerPreviewSketch: View {
    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(FableTheme.accentGradient).frame(width: 12, height: 12)
                RoundedRectangle(cornerRadius: 2).fill(.tertiary).frame(width: 26, height: 5)
                RoundedRectangle(cornerRadius: 2).fill(.quaternary).frame(width: 22, height: 5)
                Spacer()
            }
            .frame(width: 34)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill([Color.green, .green, .orange, .green, .red, .secondary][index])
                                .frame(width: 4, height: 4)
                                .padding(3)
                        }
                }
            }
        }
        .padding(10)
    }
}

/// Miniature of the Classic face: sidebar + settings rows.
private struct ClassicPreviewSketch: View {
    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(FableTheme.accentGradient).frame(width: 12, height: 12)
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index == 0 ? AnyShapeStyle(Color.accentColor.opacity(0.6)) : AnyShapeStyle(.quaternary))
                        .frame(width: 28, height: 6)
                }
                Spacer()
            }
            .frame(width: 38)

            VStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { _ in
                    HStack {
                        RoundedRectangle(cornerRadius: 2).fill(.tertiary).frame(width: 40, height: 5)
                        Spacer()
                        RoundedRectangle(cornerRadius: 2).fill(.quaternary).frame(width: 24, height: 5)
                    }
                }
                Spacer()
            }
        }
        .padding(10)
    }
}
