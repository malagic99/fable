import SwiftUI

/// Grid of all bottles with creation entry point. Root of the Bottles section.
struct BottleListView: View {
    @EnvironmentObject private var bottleManager: BottleManager
    @State private var isShowingCreateSheet = false
    @State private var isShowingSteamSheet = false

    private static let steamTemplate = BottleTemplateCatalog.all
        .first { $0.id == "steam-ready" } ?? BottleTemplateCatalog.default

    private let columns = [GridItem(.adaptive(minimum: 248, maximum: 320), spacing: 18)]

    var body: some View {
        Group {
            if bottleManager.bottles.isEmpty {
                ContentUnavailableView {
                    Label("bottle.list.empty.title", systemImage: "wineglass")
                } description: {
                    Text("bottle.list.empty.description")
                } actions: {
                    VStack(spacing: 8) {
                        Button("bottle.list.create") { isShowingCreateSheet = true }
                            .buttonStyle(.borderedProminent)
                        Button("bottle.list.new_steam") { isShowingSteamSheet = true }
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(bottleManager.bottles) { bottle in
                            BottleGridItem(bottle: bottle)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("bottle.list.new") { isShowingCreateSheet = true }
                    Button("bottle.list.new_steam") { isShowingSteamSheet = true }
                } label: {
                    Label("bottle.list.create", systemImage: "plus")
                }
                .help("Create a new bottle")
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateBottleView()
        }
        .sheet(isPresented: $isShowingSteamSheet) {
            CreateBottleView(
                initialTemplate: Self.steamTemplate,
                title: "New Steam Bottle"
            )
        }
        .navigationDestination(for: Bottle.ID.self) { id in
            BottleDetailView(bottleID: id)
        }
    }
}

/// One bottle in the grid: the card navigates to detail on tap, and a
/// quick-launch button reveals on hover (a sibling overlay, not nested in
/// the link, so its taps launch the game instead of opening the detail).
/// Owns the hover state shared by the card's lift and the button's reveal.
private struct BottleGridItem: View {
    let bottle: Bottle
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationLink(value: bottle.id) {
                BottleCard(bottle: bottle, isHovering: isHovering)
            }
            .buttonStyle(.plain)

            BottleQuickLaunchButton(bottle: bottle)
                .padding(12)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .onHover { isHovering = $0 }
    }
}

