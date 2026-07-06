import SwiftUI
import GameController

/// Shows the game controllers macOS currently sees, plus guidance for the
/// best experience under Wine. Detection only — actual in-game input flows
/// through Wine's HID → DirectInput/XInput path (and Steam Input when used).
struct ControllerStatusView: View {
    let bottle: Bottle
    @State private var controllers: [String] = []

    private var isSteamBottle: Bool {
        bottle.games.contains { $0.executablePath.lowercased().hasSuffix("steam.exe") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text(controllers.isEmpty
                         ? L10n.string("controller.none")
                         : controllers.joined(separator: ", "))
                } icon: {
                    Image(systemName: "gamecontroller")
                        .foregroundStyle(controllers.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
                }
                .foregroundStyle(controllers.isEmpty ? .secondary : .primary)
                Spacer()
                Button("Refresh") { refresh() }
                    .controlSize(.small)
            }
            Text(guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { refresh() }
    }

    /// Honest guidance: pads pass through automatically; Steam Input is the
    /// best path for a DualSense / DualShock 4.
    private var guidance: String {
        L10n.string(isSteamBottle ? "controller.guidance.steam" : "controller.guidance.generic")
    }

    private func refresh() {
        controllers = GCController.controllers().map { $0.vendorName ?? $0.productCategory }
    }
}
