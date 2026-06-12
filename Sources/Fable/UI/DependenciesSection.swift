import SwiftUI

/// "Dependencies" section of the bottle detail page: one-click installs
/// of common runtimes games expect.
struct DependenciesSection: View {
    let bottle: Bottle

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var toastCenter: ToastCenter

    @StateObject private var installer = DependencyInstaller()

    var body: some View {
        Section {
            ForEach(DependencyCatalog.all) { dependency in
                row(for: dependency)
            }
        } header: {
            Text("Dependencies")
        } footer: {
            Text("Runtimes many games expect. Install what a game's requirements mention — its log will name anything missing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(for dependency: Dependency) -> some View {
        HStack {
            Label(dependency.name, systemImage: "puzzlepiece.extension")
            Spacer()
            if installer.installing.contains(dependency.id) {
                ProgressView()
                    .controlSize(.small)
            } else if installer.isInstalled(dependency, bottle: bottle, bottleManager: bottleManager) {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Button("Install") { install(dependency) }
                    .controlSize(.small)
                    .disabled(bottle.status != .ready)
            }
        }
    }

    private func install(_ dependency: Dependency) {
        Task {
            do {
                try await installer.install(
                    dependency,
                    bottle: bottle,
                    bottleManager: bottleManager,
                    wineManager: wineManager
                )
                toastCenter.success("\(dependency.name) installed")
            } catch {
                toastCenter.error("\(dependency.name): \(error.localizedDescription)")
            }
        }
    }
}
