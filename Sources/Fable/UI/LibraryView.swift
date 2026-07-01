import SwiftUI

/// Cross-bottle Library: every game across every bottle in one searchable
/// grid, each launchable with one click. Root of the Library section.
struct LibraryView: View {
    @EnvironmentObject private var bottleManager: BottleManager
    @State private var searchText = ""
    @State private var isShowingHeroicImport = false

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 18)]

    private var allEntries: [LibraryEntry] {
        LibraryIndex.entries(from: bottleManager.bottles)
    }

    private var filteredEntries: [LibraryEntry] {
        LibraryIndex.entries(from: bottleManager.bottles, query: searchText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if allEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No Games Yet", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Add games to a bottle and they'll appear here, ready to launch.")
                    } actions: {
                        Button("Import from Heroic…") { isShowingHeroicImport = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(filteredEntries) { entry in
                                LibraryGameItem(entry: entry)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search games")
            .navigationDestination(for: Bottle.ID.self) { id in
                BottleDetailView(bottleID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingHeroicImport = true
                    } label: {
                        Label("Import from Heroic…", systemImage: "square.and.arrow.down")
                    }
                    .help("Import installed games from the Heroic Games Launcher")
                }
            }
            .sheet(isPresented: $isShowingHeroicImport) {
                HeroicImportView()
            }
        }
    }
}

/// One Library tile: the card opens the game's bottle on tap; the play button
/// (sibling overlay, not nested in the link) launches it.
private struct LibraryGameItem: View {
    let entry: LibraryEntry
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationLink(value: entry.bottle.id) {
                LibraryGameCard(entry: entry, isHovering: isHovering)
            }
            .buttonStyle(.plain)

            GamePlayButton(game: entry.game, bottle: entry.bottle)
                .padding(12)
                .scaleEffect(isHovering ? 1.08 : 1)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .onHover { isHovering = $0 }
    }
}

private struct LibraryGameCard: View {
    let entry: LibraryEntry
    var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ExeIconView(bottle: entry.bottle, game: entry.game,
                            size: 52, fallbackSymbol: "gamecontroller.fill")
                Spacer()
                BackendBadge(backend: entry.effectiveBackend)
            }

            Spacer(minLength: 2)

            Text(entry.game.name)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            Label(entry.bottle.name, systemImage: "wineglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // Keep the bottom-right corner clear for the play button.
                .padding(.trailing, 42)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .fableCard(isHovering: isHovering)
    }
}
