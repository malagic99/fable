import SwiftUI

/// Sheet for editing a DualSense trigger profile (a bottle default or a
/// per-game override), with live preview via `TriggerConfigView`.
struct TriggerProfileSheet: View {
    let title: String
    @State private var profile: TriggerProfile
    private let onSave: (TriggerProfile) -> Void

    @Environment(\.dismiss) private var dismiss

    init(title: String, profile: TriggerProfile, onSave: @escaping (TriggerProfile) -> Void) {
        self.title = title
        _profile = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text("A constant trigger feel you set — like Steam Input. A Wine game's own contextual trigger effects can't cross the Wine boundary, so these are static, not game-driven.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()

            TriggerConfigView(profile: $profile)
                .padding(16)

            Divider()
            SheetActionBar {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Save") { onSave(profile); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 560, height: 470)
    }
}
