import SwiftUI
import GameController

/// Shows the game controllers macOS currently sees, plus guidance for the
/// best experience under Wine. Detection only — actual in-game input flows
/// through Wine's HID → DirectInput/XInput path (and Steam Input when used).
struct ControllerStatusView: View {
    let bottle: Bottle
    @State private var controllers: [String] = []
    /// Pads macOS sees as HID devices but does not classify as game
    /// controllers, so they never reach GCController — or Wine.
    @State private var unroutedPads: [HIDControllerScanner.Device] = []

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
            // A pad that's plainly connected but reports itself as something
            // else would otherwise show as "No controller detected", which
            // reads as Fable being broken rather than the pad being in the
            // wrong mode.
            ForEach(unroutedPads) { pad in
                Label {
                    Text(L10n.string("controller.not_routed", pad.name))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
            Text(guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { refresh() }
        // Without these the list is a snapshot from whenever the page opened:
        // plugging a pad in afterwards changes nothing until someone finds the
        // Refresh button, which reads as "Fable can't see my controller".
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            refresh()
        }
    }

    /// Honest guidance: pads pass through automatically; Steam Input is the
    /// best path for a DualSense / DualShock 4.
    private var guidance: String {
        L10n.string(isSteamBottle ? "controller.guidance.steam" : "controller.guidance.generic")
    }

    private func refresh() {
        controllers = GCController.controllers().map { $0.vendorName ?? $0.productCategory }
        // Only those macOS won't route — a pad already in GCController needs
        // no warning.
        unroutedPads = HIDControllerScanner.scan().filter { !$0.presentsAsGamepad }
    }
}
