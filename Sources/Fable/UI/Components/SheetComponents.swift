import SwiftUI

/// Shared layout for sheet status states: spinner-or-icon, headline,
/// optional message. Keeps every flow's sheets visually identical.
struct SheetStatusView: View {
    /// nil shows an indeterminate spinner instead of an icon.
    let systemImage: String?
    var tint: Color = .accentColor
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(tint)
            } else {
                ProgressView()
            }
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
}

/// Bottom action bar with standard padding: leading (dismissive) and
/// trailing (primary) controls.
struct SheetActionBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            leading
            Spacer()
            trailing
        }
        .padding(16)
    }
}

/// Colored capsule tag ("Setting up", "Needs repair", "DXMT").
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.22), in: Capsule())
            .foregroundStyle(color)
    }
}
