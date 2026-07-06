import SwiftUI

/// Grid of all bottles with creation entry point. Root of the Bottles section.
struct BottleListView: View {
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var toastCenter: ToastCenter
    @State private var isShowingCreateSheet = false
    @State private var isShowingSteamSheet = false
    @State private var isImporting = false

    private static let steamTemplate = BottleTemplateCatalog.all
        .first { $0.id == "steam-ready" } ?? BottleTemplateCatalog.default

    private var columns: [GridItem] {
        let min = TileMetrics.cardMin(settingsManager.settings.tileScale)
        return [GridItem(.adaptive(minimum: min, maximum: min * 1.3), spacing: 18)]
    }

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
                    // Same heading + inline resizer shape as the game wall.
                    HStack {
                        // "Your bottles", not "Bottles" — the classic face
                        // already titles the window "Bottles" right above it.
                        Text("Your bottles").font(.title.weight(.semibold))
                        Spacer()
                        TileSizeControl(scale: $settingsManager.settings.tileScale)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(bottleManager.bottles) { bottle in
                            BottleGridItem(bottle: bottle)
                        }
                        // The one creation entry point: a choice tile — plain or
                        // Steam bottle. (No toolbar "+", per the games-first flow.)
                        NewBottleCard(
                            createBottle: { isShowingCreateSheet = true },
                            createSteam: { isShowingSteamSheet = true },
                            importBottle: { importBottle() }
                        )
                    }
                    .padding([.horizontal, .bottom], 24)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
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

    /// The Friend Kit receiving end: pick a .fbottle, verify, adopt.
    private func importBottle() {
        guard !isImporting,
              let archive = FilePicker.chooseFile(extension: BottleArchive.pathExtension)
        else { return }
        isImporting = true
        toastCenter.success(L10n.string("toast.bottle.importing", archive.lastPathComponent))
        Task {
            defer { isImporting = false }
            do {
                let unpacked = try await BottleArchive.unpack(archive)
                let imported = try bottleManager.importBottle(unpacked)
                toastCenter.success(L10n.string("toast.bottle.imported", imported.name))
            } catch {
                toastCenter.error(error.localizedDescription)
            }
        }
    }
}

/// Dashed ghost tile that creates a new bottle — a menu offering a plain or a
/// Steam bottle. Matches the card footprint so the grid stays rhythmic.
private struct NewBottleCard: View {
    let createBottle: () -> Void
    let createSteam: () -> Void
    let importBottle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Menu {
            Button("New Bottle", systemImage: "wineglass") { createBottle() }
            Button("New Steam Bottle", systemImage: "gamecontroller") { createSteam() }
            Divider()
            Button("Import Bottle (.fbottle)…", systemImage: "square.and.arrow.down") { importBottle() }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                Text("New Bottle")
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                    .strokeBorder(
                        isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: FableTheme.cardRadius))
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { isHovering = $0 }
        .help("Create a new bottle")
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

            // Always visible for one-glance click-and-play; a subtle lift on
            // hover ties it to the card.
            BottleQuickLaunchButton(bottle: bottle)
                .padding(12)
                .scaleEffect(isHovering ? 1.08 : 1)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .onHover { isHovering = $0 }
    }
}

