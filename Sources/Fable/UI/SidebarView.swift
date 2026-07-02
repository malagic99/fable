import SwiftUI

/// Sidebar navigation between the app's top-level sections, headed by the
/// Fable mark so the app carries its identity beyond onboarding.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.fableGradient) private var gradient

    var body: some View {
        List(selection: $appState.selectedSection) {
            Section {
                ForEach(AppSection.allCases) { section in
                    Label(section.titleKey, systemImage: section.systemImage)
                        .padding(.vertical, 2)
                        .tag(section)
                }
            } header: {
                HStack(spacing: 10) {
                    Image(systemName: "wineglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(gradient, in: RoundedRectangle(cornerRadius: 8))
                    Text("Fable")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                }
                .padding(.vertical, 8)
            }
        }
        .listStyle(.sidebar)
    }
}
