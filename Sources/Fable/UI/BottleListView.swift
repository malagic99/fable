import SwiftUI

/// Grid of all bottles with creation entry point. Root of the Bottles section.
struct BottleListView: View {
    @EnvironmentObject private var bottleManager: BottleManager
    @State private var isShowingCreateSheet = false
    @State private var isShowingSteamSheet = false

    private static let steamTemplate = BottleTemplateCatalog.all
        .first { $0.id == "steam-ready" } ?? BottleTemplateCatalog.default

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)]

    var body: some View {
        Group {
            if bottleManager.bottles.isEmpty {
                ContentUnavailableView {
                    Label("No Bottles Yet", systemImage: "wineglass")
                } description: {
                    Text("Create a bottle to install and run Windows games.")
                } actions: {
                    VStack(spacing: 8) {
                        Button("Create Bottle") { isShowingCreateSheet = true }
                            .buttonStyle(.borderedProminent)
                        Button("New Steam Bottle…") { isShowingSteamSheet = true }
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(bottleManager.bottles) { bottle in
                            NavigationLink(value: bottle.id) {
                                BottleCard(bottle: bottle)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Bottle…") { isShowingCreateSheet = true }
                    Button("New Steam Bottle…") { isShowingSteamSheet = true }
                } label: {
                    Label("Create Bottle", systemImage: "plus")
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

