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
                                BottleCardView(bottle: bottle)
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

/// Compact bottle card for the grid. (Promoted to a richer reusable
/// component during the Day 9 polish pass.)
struct BottleCardView: View {
    let bottle: Bottle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "wineglass")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)

            HStack(spacing: 6) {
                Text(bottle.name)
                    .font(.headline)
                    .lineLimit(1)
                if bottle.status == .provisioning {
                    Text("Setting up")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.25), in: Capsule())
                }
            }

            HStack {
                Text(bottle.windowsVersion.displayName)
                Spacer()
                Text(bottle.createdAt, format: .dateTime.day().month())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
