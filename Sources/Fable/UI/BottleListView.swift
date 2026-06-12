import SwiftUI

/// Grid of all bottles with creation entry point. Root of the Bottles section.
struct BottleListView: View {
    @EnvironmentObject private var bottleManager: BottleManager
    @State private var isShowingCreateSheet = false

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)]

    var body: some View {
        Group {
            if bottleManager.bottles.isEmpty {
                ContentUnavailableView {
                    Label("No Bottles Yet", systemImage: "wineglass")
                } description: {
                    Text("Create a bottle to install and run Windows games.")
                } actions: {
                    Button("Create Bottle") { isShowingCreateSheet = true }
                        .buttonStyle(.borderedProminent)
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
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Label("Create Bottle", systemImage: "plus")
                }
                .help("Create a new bottle")
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateBottleView()
        }
        .navigationDestination(for: Bottle.ID.self) { id in
            BottleDetailView(bottleID: id)
        }
    }
}

