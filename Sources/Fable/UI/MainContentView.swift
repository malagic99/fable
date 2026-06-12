import SwiftUI

/// Routes the detail pane to the view for the selected sidebar section.
struct MainContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch appState.selectedSection {
        case .bottles:
            BottlesPlaceholderView()
        case .components:
            ComponentsPlaceholderView()
        case .settings:
            SettingsPlaceholderView()
        }
    }
}

// MARK: - Section placeholders
// Replaced by the real views as they land: BottleListView (Day 2),
// ComponentsView (Day 6), SettingsView (Day 7).

struct BottlesPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "No Bottles Yet",
            systemImage: "wineglass",
            description: Text("Create a bottle to install and run Windows games.")
        )
    }
}

struct ComponentsPlaceholderView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section("Pinned Versions") {
                ForEach(appState.versionCatalog.components.sorted(by: { $0.key < $1.key }), id: \.key) { _, component in
                    LabeledContent(component.name, value: component.version)
                }
            }
        }
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape",
            description: Text("Global configuration arrives on Day 7.")
        )
    }
}
