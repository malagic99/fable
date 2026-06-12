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
    @State private var errorMessage: String?

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
        }
    }

    private func save() {
        var updated = game
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.arguments = arguments
        updated.environment = ArgumentTokenizer.environment(fromLines: environmentText)
        do {
            try bottleManager.updateGame(updated, in: bottle.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
