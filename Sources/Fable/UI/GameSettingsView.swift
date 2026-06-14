import SwiftUI

/// Per-game settings sheet: rename, launch arguments, environment
/// overrides.
struct GameSettingsView: View {
    let game: Game
    let bottle: Bottle

    @EnvironmentObject private var bottleManager: BottleManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var arguments = ""
    @State private var environmentText = ""
    @State private var backendOverride: GraphicsBackend? = nil
    @State private var errorMessage: String?

    /// Tag used by the "inherit" row in the picker. None of the real
    /// GraphicsBackend cases can be nil, so this stand-in is safe.
    private enum BackendChoice: Hashable {
        case inherit
        case override(GraphicsBackend)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name)

                Section {
                    TextField("Arguments", text: $arguments, prompt: Text("-windowed -skipintro"))
                        .font(.body.monospaced())
                } footer: {
                    Text("Passed to the game's .exe. Quote values containing spaces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Graphics Backend", selection: Binding(
                        get: { backendOverride.map(BackendChoice.override) ?? .inherit },
                        set: {
                            switch $0 {
                            case .inherit: backendOverride = nil
                            case .override(let backend): backendOverride = backend
                            }
                        }
                    )) {
                        Text("Bottle default (\(bottle.graphicsBackend.displayName))")
                            .tag(BackendChoice.inherit)
                        Divider()
                        ForEach(GraphicsBackend.allCases) { backend in
                            Text(backend.displayName)
                                .tag(BackendChoice.override(backend))
                        }
                    }
                } footer: {
                    Text(backendFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $environmentText)
                        .font(.body.monospaced())
                        .frame(height: 80)
                } header: {
                    Text("Environment Variables")
                } footer: {
                    Text("One KEY=VALUE per line. Applied on top of the bottle's launch environment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            SheetActionBar {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(width: 460, height: 360)
        .onAppear {
            name = game.name
            arguments = game.arguments
            environmentText = ArgumentTokenizer.lines(fromEnvironment: game.environment)
            backendOverride = game.graphicsBackend
        }
    }

    private var backendFooter: String {
        guard let backendOverride else {
            return "Inheriting the bottle's backend. Override to share one bottle between a D3D9 and a D3D11 game."
        }
        switch backendOverride {
        case .off:
            return "Wine's built-in graphics — safest for D3D9-era games."
        case .dxmt:
            return "DXMT routing forced on. Needs DXMT enabled on the bottle (install it once from the Graphics section)."
        case .gptk:
            return "Game Porting Toolkit Wine forced on. The other backends in this bottle won't run while this one is open."
        case .dxvk:
            return "DXVK routing forced on. Needs `winetricks dxvk` run in the bottle once."
        case .crossover:
            return "Routes through your installed CrossOver. Different wineserver — can't share the bottle with other backends running."
        case .sikarugir:
            return "Routes through Sikarugir's wine-10.0 + D3DMetal. The free D3D12 path for modern games."
        }
    }

    private func save() {
        var updated = game
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.arguments = arguments
        updated.environment = ArgumentTokenizer.environment(fromLines: environmentText)
        updated.graphicsBackend = backendOverride
        do {
            try bottleManager.updateGame(updated, in: bottle.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
