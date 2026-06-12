import SwiftUI

/// Routes the detail pane to the view for the selected sidebar section.
struct MainContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch appState.selectedSection {
        case .bottles:
            NavigationStack {
                BottleListView()
            }
        case .components:
            ComponentsPlaceholderView()
        case .settings:
            SettingsPlaceholderView()
        }
    }
}

// MARK: - Section placeholders
// Replaced by the real views as they land: ComponentsView (Day 6),
// SettingsView (Day 7).

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
