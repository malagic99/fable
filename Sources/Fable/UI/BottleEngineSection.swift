import SwiftUI

/// The bottle page's "Engine" section: which engine versions this bottle is
/// pinned to, and — when a newer one is installed — moving it there with a
/// backup copy, since Wine upgrades a prefix one way. See `BottleRuntime`.
struct BottleEngineSection: View {
    let bottle: Bottle
    /// True while a game runs in this bottle: moving then would clone a live prefix.
    let isBusy: Bool

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var componentManager: ComponentManager
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var isConfirmingMove = false
    @State private var isChecking = false
    /// One line per engine from the last check, nil before the first.
    @State private var checkResults: [RuntimeIntegrity.CheckLine]?

    private var runtime: BottleRuntime? { bottle.runtime }
    private var updates: [EngineInventory.Update] {
        EngineInventory.updates(for: bottle, componentManager: componentManager)
    }

    var body: some View {
        Section {
            if let runtime, !runtime.pins.isEmpty {
                ForEach(runtime.pins.keys.sorted(), id: \.self) { id in
                    LabeledContent(Self.displayName(for: id)) {
                        Text(Self.displayVersion(runtime.pins[id] ?? "", for: id))
                            .monospacedDigit()
                    }
                }
            } else {
                Text("Not recorded yet — the next launch records the engine this bottle runs on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Toggle("Always Use the Newest Engine", isOn: Binding(
                get: { runtime?.policy == .followNewest },
                set: { followNewest in
                    var next = runtime ?? BottleRuntime()
                    next.policy = followNewest ? .followNewest : .pinned
                    do {
                        try bottleManager.setRuntime(next, for: bottle.id)
                    } catch {
                        toastCenter.error(error.localizedDescription)
                    }
                }
            ))
            .help("Off keeps this bottle on the engine it was set up with until you move it. On moves it to every engine update automatically — the old behavior.")

            if !updates.isEmpty {
                ForEach(updates, id: \.self) { update in
                    Text(L10n.string(
                        "engine.update_available",
                        Self.displayName(for: update.componentID),
                        Self.displayVersion(update.pinned, for: update.componentID),
                        Self.displayVersion(update.newest, for: update.componentID)
                    ))
                    .font(.callout)
                }
                Button("Move to Newer Engine…") { isConfirmingMove = true }
                    .disabled(isBusy || bottle.status != .ready || isChecking)
            }

            HStack {
                Button("Check Engine Files") { check() }
                    .disabled(isChecking)
                    .help("Compares every file of this bottle's engine with the record Fable made when it set the engine up.")
                if isChecking { ProgressView().controlSize(.small) }
            }
            if let checkResults {
                ForEach(checkResults, id: \.self) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(line.summary, systemImage: line.symbol)
                            .foregroundStyle(line.isProblem ? .orange : .primary)
                        if let detail = line.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .font(.callout)
                }
            }
        } header: {
            Text("Engine")
        } footer: {
            Text("Engine updates don't change a bottle that already works. Moving keeps a copy of the bottle as it was, because Wine upgrades a bottle one way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            L10n.string("engine.move.title", bottle.name),
            isPresented: $isConfirmingMove
        ) {
            Button("Move and Keep a Copy") { move() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.string("engine.move.message", backupName))
        }
    }

    private var backupName: String {
        L10n.string("engine.backup_name", bottle.name)
    }

    /// The engine directories this bottle runs on, under its own pins.
    private func engineRoots() -> [(id: String, root: URL?)] {
        EnginePins.$current.withValue(bottle.enginePins) {
            bottle.graphicsBackend.engineComponentIDs.map { ($0, componentManager.installedDirectory(for: $0)) }
        }
    }

    private func check() {
        let targets = engineRoots()
        isChecking = true
        Task {
            let lines = await Task.detached(priority: .userInitiated) {
                targets.map { RuntimeIntegrity.checkLine(componentID: $0.id, root: $0.root) }
            }.value
            checkResults = lines
            isChecking = false
        }
    }

    /// Moves the bottle, after checking that the engines it would move to
    /// are intact. A damaged engine blocks the move — never a bottle that is
    /// already working where it is.
    private func move() {
        let targets = updates.map { ($0.componentID, componentManager.newestInstalledDirectory(for: $0.componentID)) }
        isChecking = true
        Task {
            let lines = await Task.detached(priority: .userInitiated) {
                targets.map { RuntimeIntegrity.checkLine(componentID: $0.0, root: $0.1) }
            }.value
            isChecking = false
            if lines.contains(where: \.isProblem) {
                checkResults = lines
                toastCenter.error(L10n.string("integrity.move_blocked"))
                return
            }
            do {
                let backup = try bottleManager.moveToNewestEngines(bottle.id, backupName: backupName)
                toastCenter.success(L10n.string("engine.moved", bottle.name, backup.name))
            } catch {
                toastCenter.error(error.localizedDescription)
            }
        }
    }

    // MARK: Labels

    static func displayName(for componentID: String) -> String {
        BottleRuntime.displayName(forComponent: componentID)
    }

    static func displayVersion(_ raw: String, for componentID: String) -> String {
        BottleRuntime.displayVersion(raw, forComponent: componentID)
    }
}

/// Components tab section: engine versions on disk that no bottle is pinned
/// to and that aren't current. Nothing is removed without the button.
struct UnusedEnginesSection: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var componentManager: ComponentManager
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var unused: [EngineInventory.Unused] = []
    @State private var totalBytes: Int64 = 0
    @State private var isConfirming = false

    var body: some View {
        Group {
            if !unused.isEmpty {
                Section {
                    ForEach(unused, id: \.self) { item in
                        LabeledContent(BottleEngineSection.displayName(for: item.componentID)) {
                            Text(BottleEngineSection.displayVersion(item.version, for: item.componentID))
                                .monospacedDigit()
                        }
                    }
                    Button("Remove Unused Engines…", role: .destructive) { isConfirming = true }
                } header: {
                    Text("Unused Engine Versions")
                } footer: {
                    Text(L10n.string(
                        "engine.unused.footer",
                        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .confirmationDialog(
                    L10n.string("engine.unused.confirm", unused.count as CVarArg),
                    isPresented: $isConfirming
                ) {
                    Button("Remove", role: .destructive) { remove() }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .task(id: bottleManager.bottles.map(\.runtime)) { await refresh() }
    }

    private var catalogVersions: [String: String] {
        appState.versionCatalog.components.mapValues(\.version)
    }

    private func refresh() async {
        let found = EngineInventory.unusedVersions(
            bottles: bottleManager.bottles,
            componentManager: componentManager,
            keep: catalogVersions
        )
        let dirs = found.map(\.directory)
        let bytes = await Task.detached {
            dirs.reduce(Int64(0)) { $0 + EngineInventory.diskSize(of: $1) }
        }.value
        unused = found
        totalBytes = bytes
    }

    private func remove() {
        // Recompute right before deleting: a bottle may have been stamped
        // or moved since the list was drawn.
        let current = EngineInventory.unusedVersions(
            bottles: bottleManager.bottles,
            componentManager: componentManager,
            keep: catalogVersions
        )
        var failed: [String] = []
        for item in current {
            do {
                try FileManager.default.removeItem(at: item.directory)
            } catch {
                failed.append(item.version)
            }
        }
        if failed.isEmpty {
            toastCenter.success(L10n.string("engine.unused.removed", current.count))
        } else {
            toastCenter.error(L10n.string("engine.unused.failed", failed.joined(separator: ", ")))
        }
        Task { await refresh() }
    }
}
