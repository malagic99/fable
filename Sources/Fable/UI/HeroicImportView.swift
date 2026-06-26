import SwiftUI

/// Imports installed games from the Heroic Games Launcher (Epic / GOG / Amazon)
/// into a Fable bottle — pick games, pick a target bottle, import. The game
/// files are symlinked in, so nothing is copied.
struct HeroicImportView: View {
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var toastCenter: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var games: [HeroicGame] = []
    @State private var selection: Set<HeroicGame.ID> = []
    @State private var targetBottle: Bottle.ID?
    @State private var isLoading = true
    @State private var heroicFound = true

    private var readyBottles: [Bottle] {
        bottleManager.bottles.filter { $0.status == .ready }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 480, height: 540)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import from Heroic").font(.headline)
                Text("Installed games from Epic, GOG, and Amazon")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !games.isEmpty {
                Button(selection.count == games.count ? "Deselect All" : "Select All") {
                    selection = selection.count == games.count ? [] : Set(games.map(\.id))
                }
                .font(.caption)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !heroicFound {
            ContentUnavailableView {
                Label("Heroic Not Found", systemImage: "questionmark.folder")
            } description: {
                Text("Install the Heroic Games Launcher and install some games in it, then come back.")
            }
        } else if games.isEmpty {
            ContentUnavailableView {
                Label("No Installed Games", systemImage: "tray")
            } description: {
                Text("Heroic has no installed Windows games to import. Install one in Heroic first.")
            }
        } else {
            List {
                ForEach(games) { game in
                    row(game)
                }
            }
            .listStyle(.inset)
        }
    }

    private func row(_ game: HeroicGame) -> some View {
        Button {
            if selection.contains(game.id) { selection.remove(game.id) } else { selection.insert(game.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection.contains(game.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.contains(game.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(game.title).lineLimit(1)
                    Text(game.executable).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                StatusBadge(text: game.sourceLabel, color: sourceColor(game.runner))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if readyBottles.isEmpty {
                Label("Create a bottle first", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Into", selection: $targetBottle) {
                    ForEach(readyBottles) { bottle in
                        Text(bottle.name).tag(Optional(bottle.id))
                    }
                }
                .frame(maxWidth: 220)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Import \(selection.isEmpty ? "" : "(\(selection.count))")") { runImport() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty || targetBottle == nil)
        }
        .padding(16)
    }

    private func sourceColor(_ runner: String) -> Color {
        switch runner {
        case "gog": .purple
        case "legendary": .blue
        case "nile": .orange
        default: .secondary
        }
    }

    private func load() async {
        guard let root = HeroicLibrary.defaultRoot() else {
            heroicFound = false
            isLoading = false
            return
        }
        let found = await Task.detached(priority: .userInitiated) {
            HeroicLibrary.installedGames(root: root)
        }.value
        games = found
        targetBottle = readyBottles.first?.id
        isLoading = false
    }

    private func runImport() {
        guard let target = targetBottle else { return }
        let chosen = games.filter { selection.contains($0.id) }
        do {
            let imported = try bottleManager.importHeroicGames(chosen, into: target)
            if imported.isEmpty {
                toastCenter.success("Those games were already imported.")
            } else {
                toastCenter.success("Imported \(imported.count) game\(imported.count == 1 ? "" : "s") from Heroic.")
            }
            dismiss()
        } catch {
            toastCenter.error(error.localizedDescription)
        }
    }
}
