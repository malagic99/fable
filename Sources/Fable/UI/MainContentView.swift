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
            SettingsView()
        }
    }
}
