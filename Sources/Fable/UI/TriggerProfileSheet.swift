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
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text("A constant trigger feel you set — like Steam Input. A Wine game's own contextual trigger effects can't cross the Wine boundary, so these are static, not game-driven.")
                    .font(.caption).foregroundStyle(.secondary)
                    // Wrap to the sheet width instead of forcing it wider (which
                    // clipped the header at both edges).
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        // Fixed width so text wraps and nothing overflows; height grows to the
        // content (2 sliders in Feedback, 3 in Weapon/Vibration) so there's no
        // dead space and no clipping.
        .frame(width: 640)
    }
}
