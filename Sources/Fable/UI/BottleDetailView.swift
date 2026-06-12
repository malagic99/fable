import SwiftUI

/// Detail page for a single bottle: info, game list, rename/delete actions.
struct BottleDetailView: View {
    let bottleID: Bottle.ID

    @EnvironmentObject private var bottleManager: BottleManager
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingRename = false
    @State private var renameText = ""
    @State private var isShowingDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        if let bottle = bottleManager.bottle(with: bottleID) {
            detailContent(for: bottle)
        } else {
            // Deleted while visible (or stale link) — nothing to show.
            ContentUnavailableView("Bottle Not Found", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder
    private func detailContent(for bottle: Bottle) -> some View {
        Form {
            Section("Bottle") {
                LabeledContent("Name", value: bottle.name)
                LabeledContent("Windows Version", value: bottle.windowsVersion.displayName)
                LabeledContent("Status") {
                    switch bottle.status {
                    case .ready:
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .provisioning:
                        Label("Setting up", systemImage: "clock")
                            .foregroundStyle(.orange)
                    }
                }
                LabeledContent("Created") {
                    Text(bottle.createdAt, format: .dateTime.day().month().year())
                }
                LabeledContent("Location") {
                    HStack {
                        Text(bottleManager.directory(for: bottle).path)
                            .truncationMode(.middle)
                            .lineLimit(1)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [bottleManager.directory(for: bottle)]
                            )
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("Games") {
                if bottle.games.isEmpty {
                    Text("No games installed. Game installation arrives with Wine integration.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bottle.games) { game in
                        Label(game.name, systemImage: "gamecontroller")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(bottle.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    renameText = bottle.name
                    isShowingRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .help("Rename this bottle")

                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this bottle")
            }
        }
        .alert("Rename Bottle", isPresented: $isShowingRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                do {
                    try bottleManager.renameBottle(bottle.id, to: renameText)
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "Delete “\(bottle.name)”?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete Bottle", role: .destructive) {
                do {
                    try bottleManager.deleteBottle(bottle.id)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("This permanently removes the bottle and everything installed in it.")
        }
    }
}
