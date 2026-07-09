import SwiftUI

/// "Dependencies" section of the bottle detail page: one-click installs
/// of common runtimes games expect.
struct DependenciesSection: View {
    let bottle: Bottle

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var wineManager: WineManager
    @EnvironmentObject private var toastCenter: ToastCenter
    @EnvironmentObject private var gameLauncher: GameLauncher

    @StateObject private var installer = DependencyInstaller()
    @State private var isShowingWinetricks = false

    var body: some View {
        Section {
            ForEach(DependencyCatalog.all) { dependency in
                row(for: dependency)
            }
            HStack {
                Label("More from Winetricks…", systemImage: "wrench.and.screwdriver")
                Spacer()
                Text(L10n.string("winetricks.installed_count", String(bottle.installedWinetricksVerbs.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Browse") { isShowingWinetricks = true }
                    .controlSize(.small)
                    .disabled(bottle.status != .ready)
            }
        } header: {
            Text("Dependencies")
        } footer: {
            Text("Runtimes many games expect. Install what a game's requirements mention — its log will name anything missing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isShowingWinetricks) {
            WinetricksSheetView(bottle: bottle)
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
                // Dependency installs run the DEFAULT wine — one runtime
                // per prefix at a time.
                try await gameLauncher.prepareExclusivePrefix(for: bottle, runtime: .off)
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
