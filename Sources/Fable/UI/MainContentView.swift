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
            ComponentsView()
        case .settings:
            SettingsPlaceholderView()
        }
    }
}

// MARK: - Section placeholders
// Replaced by the real views as they land: SettingsView (Day 7).

struct SettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape",
            description: Text("Global configuration arrives on Day 7.")
        )
    }
}
