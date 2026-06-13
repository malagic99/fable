import SwiftUI

/// Sidebar navigation between the app's top-level sections.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $appState.selectedSection) {
            ForEach(AppSection.allCases) { section in
                Label(section.titleKey, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
    }
}
