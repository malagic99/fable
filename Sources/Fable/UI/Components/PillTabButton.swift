import SwiftUI

/// THE horizontal tab pill — one look for every tab strip (Gamer top bar,
/// Settings sections). Icon + label, capsule highlight when active.
struct PillTabButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                Text(title)
            }
            .font(.callout.weight(isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isActive ? AnyShapeStyle(.quaternary.opacity(0.8)) : AnyShapeStyle(.clear),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
