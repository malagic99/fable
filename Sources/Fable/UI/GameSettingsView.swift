import SwiftUI

/// Per-game settings sheet: rename, launch arguments, environment
/// overrides.
struct GameSettingsView: View {
    let game: Game
    let bottle: Bottle

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var gameStats: GameStatsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var arguments = ""
    @State private var environmentText = ""
    @State private var backendOverride: GraphicsBackend? = nil
    @State private var triggerOverride: TriggerProfile? = nil
    @State private var performance = PerformanceOptions()
    @State private var notes = ""
    @State private var isShowingTriggers = false
    @State private var errorMessage: String?

    /// Whether the effective backend can drive MetalFX (a D3DMetal feature).
    private var effectiveBackend: GraphicsBackend { backendOverride ?? bottle.graphicsBackend }

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
                        Text(L10n.string("game.backend.bottle_default", bottle.graphicsBackend.displayName))
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

                // The inspector shows Frame cap + MetalFX; Tune must be able to
                // change them (UI review P3 — no more "facts you can't touch").
                // These live on the bottle, and the section says so honestly.
                Section {
                    Picker("Frame Rate Cap", selection: Binding(
                        get: { performance.frameRateCap ?? 0 },
                        set: { performance.frameRateCap = $0 == 0 ? nil : $0 }
                    )) {
                        Text("Uncapped").tag(0)
                        Text("120 fps").tag(120)
                        Text("60 fps").tag(60)
                        Text("30 fps").tag(30)
                    }
                    .disabled(effectiveBackend == .off)

                    if effectiveBackend == .gptk || effectiveBackend == .sikarugir {
                        Toggle("MetalFX Upscaling", isOn: $performance.metalFXUpscaling)
                    }
                } header: {
                    Text("Performance")
                } footer: {
                    Text(L10n.string("game.perf.shared_footer", bottle.name))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Override bottle's DualSense triggers", isOn: Binding(
                        get: { triggerOverride != nil },
                        set: { triggerOverride = $0 ? (triggerOverride ?? bottle.triggerProfile) : nil }
                    ))
                    if triggerOverride != nil {
                        Button("Configure This Game's Triggers…") { isShowingTriggers = true }
                    }
                } header: {
                    Text("Adaptive Triggers")
                } footer: {
                    Text(L10n.string(triggerOverride == nil
                         ? "game.triggers.footer_default"
                         : "game.triggers.footer_override"))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(height: 60)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("Yours alone — mod setup, launch quirks, where you left off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        exportRecipe()
                    } label: {
                        Label("Export as Recipe…", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("Saves this game's backend + performance as a shareable .fablerecipe file. Anyone can import it so the setup auto-applies for them.")
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
            .fableThemedFormBackground()

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
        .frame(width: 460, height: 520)
        .onAppear {
            name = game.name
            arguments = game.arguments
            environmentText = ArgumentTokenizer.lines(fromEnvironment: game.environment)
            backendOverride = game.graphicsBackend
            triggerOverride = game.triggerProfile
            performance = bottle.performance
            notes = gameStats.notes(for: game.id)
        }
        .sheet(isPresented: $isShowingTriggers) {
            TriggerProfileSheet(title: "DualSense Triggers — \(game.name)",
                                profile: triggerOverride ?? bottle.triggerProfile) { profile in
                triggerOverride = profile
            }
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
        updated.triggerProfile = triggerOverride
        do {
            try bottleManager.updateGame(updated, in: bottle.id)
            if performance != bottle.performance {
                try bottleManager.setPerformance(performance, for: bottle.id)
            }
            if notes != gameStats.notes(for: game.id) {
                gameStats.setNotes(notes, for: game.id)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportRecipe() {
        // Capture the in-effect override the user may have just picked here.
        var staged = game
        staged.graphicsBackend = backendOverride
        let recipe = UserRecipeStore.recipe(from: staged, in: bottle)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(game.name).fablerecipe"
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try UserRecipeStore.encoded(recipe).write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
