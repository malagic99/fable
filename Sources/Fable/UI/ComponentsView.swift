import SwiftUI

/// Components tab: install state, versions, and updates for the runtime
/// pieces (Wine, DXMT).
struct ComponentsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var componentManager: ComponentManager
    @EnvironmentObject private var updateManager: UpdateManager
    @EnvironmentObject private var dxmtManager: DXMTManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var toastCenter: ToastCenter

    var body: some View {
        Form {
            Section {
                ComponentRow(
                    id: WineManager.componentID,
                    fallback: appState.versionCatalog.wine
                )
                ComponentRow(
                    id: DXMTManager.componentID,
                    fallback: appState.versionCatalog.dxmt
                )
            } header: {
                Text("Runtime Components")
            } footer: {
                if let lastChecked = updateManager.lastChecked {
                    Text("Last checked \(lastChecked.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = updateManager.lastError {
                Section {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await updateManager.checkForUpdates() }
                } label: {
                    if updateManager.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(updateManager.isChecking)
                .help("Check GitHub for newer component releases")
            }
        }
    }
}

/// One component's row: versions, live install state, install/update.
private struct ComponentRow: View {
    let id: String
    let fallback: VersionCatalog.Component?

    @EnvironmentObject private var componentManager: ComponentManager
    @EnvironmentObject private var updateManager: UpdateManager
    @EnvironmentObject private var dxmtManager: DXMTManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var toastCenter: ToastCenter

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(fallback?.name ?? id)
                    .font(.headline)
                subtitle
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var subtitle: some View {
        switch componentManager.state(of: id) {
        case .downloading(let progress):
            ProgressView(value: progress.fraction)
                .frame(maxWidth: 220)
        case .verifying:
            Text("Verifying download…").font(.caption).foregroundStyle(.secondary)
        case .extracting:
            Text("Extracting…").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
        case .installed, .notInstalled:
            Text(versionText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var versionText: String {
        if let installed = updateManager.installedVersion(of: id) {
            if let update = updateManager.available[id] {
                return "\(installed) installed — \(update.version) available"
            }
            return "\(installed) installed"
        }
        return "Not installed"
    }

    @ViewBuilder
    private var trailing: some View {
        switch componentManager.state(of: id) {
        case .downloading, .verifying, .extracting:
            EmptyView()
        default:
            if let update = updateManager.available[id] {
                Button("Update to \(update.version)") { install(update) }
                    .buttonStyle(.borderedProminent)
            } else if updateManager.installedVersion(of: id) == nil, let fallback {
                Button("Install \(fallback.version)") { install(fallback) }
            } else {
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            }
        }
    }

    private func install(_ component: VersionCatalog.Component) {
        Task {
            do {
                try await updateManager.install(component, id: id)
                // Updated DXMT DLLs must be re-copied into bottles that
                // have it enabled.
                if id == DXMTManager.componentID {
                    for bottle in bottleManager.bottles where bottle.dxmtEnabled {
                        try dxmtManager.enable(
                            in: bottle, bottleManager: bottleManager, wineManager: wineManager
                        )
                    }
                }
                toastCenter.success("\(component.name) \(component.version) installed")
            } catch {
                toastCenter.error(error.localizedDescription)
            }
        }
    }
}
