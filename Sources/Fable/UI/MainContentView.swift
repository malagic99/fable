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
        case .library:
            // The one game surface — same wall as the Gamer face.
            GameWallView(openBottles: { appState.selectedSection = .bottles })
        case .components:
            ComponentsView()
        case .settings:
            SettingsView()
        }
    }
}
