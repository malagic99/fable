import SwiftUI

/// THE game library — one wall for both faces. Wine games and native macOS
/// games side by side, cover art, confidence dots, an inspector, and a single
/// unified Add flow (native Steam, Heroic, Mac apps, Windows installers).
/// The Gamer face embeds it under the top bar; the Classic face shows it as
/// the Library section. There is deliberately no second library surface.
struct GameWallView: View {
    /// Navigates to the Bottles section (Windows games are set up there);
    /// each face supplies its own jump.
    let openBottles: () -> Void

    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var activityMonitor: ActivityMonitor
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var nativeGames: NativeGamesStore

    /// The wall holds both worlds; selection distinguishes them.
    private enum Selection: Hashable {
        case wine(LibraryEntry.ID)
        case native(NativeGame.ID)
    }

    @State private var searchText = ""
    @State private var selection: Selection?
    @State private var isShowingSteamImport = false
    @State private var isShowingHeroicImport = false
    @State private var isShowingLegend = false

    private var entries: [LibraryEntry] {
        LibraryIndex.entries(from: bottleManager.bottles, query: searchText)
    }

    private var nativeEntries: [NativeGame] {
        nativeGames.entries(query: searchText)
    }

    private var selectedWine: LibraryEntry? {
        if case .wine(let id) = selection, let entry = entries.first(where: { $0.id == id }) {
            return entry
        }
        // Default focus: the first wine game when nothing valid is selected.
        if case .native = selection { return nil }
        return entries.first
    }

    private var selectedNative: NativeGame? {
        guard case .native(let id) = selection else { return nil }
        return nativeEntries.first { $0.id == id }
    }

    private func isRunning(_ entry: LibraryEntry) -> Bool {
        gameLauncher.isRunning(entry.game.id) || activityMonitor.isRunning(entry.game, in: entry.bottle)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Text("Your games").font(.title.weight(.semibold))
                    Spacer()
                    TileSizeControl(scale: $settingsManager.settings.tileScale)
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 130)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(FableTheme.surfaceRaised, in: Capsule())
                    // Learn-once info lives behind "?", not in a permanent row.
                    Button {
                        isShowingLegend = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("What the dots mean")
                    .popover(isPresented: $isShowingLegend, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Health dots").font(.caption.weight(.semibold))
                            legendDot(.green, "verified — a tested recipe exists")
                            legendDot(.orange, "works with tweaks")
                            legendDot(.red, "won't run")
                            legendDot(Color.secondary.opacity(0.6), "untested")
                            Divider()
                            HStack(spacing: 5) {
                                Image(systemName: "applelogo").font(.caption2).foregroundStyle(.secondary)
                                Text("native Mac game — no Wine, it just runs")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                    }
                }
                .padding(.top, 16)

                if entries.isEmpty && nativeEntries.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        let coverMin = TileMetrics.coverMin(settingsManager.settings.tileScale)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: coverMin, maximum: coverMin * 1.25), spacing: 16)],
                                  spacing: 16) {
                            ForEach(entries) { entry in
                                GameCoverCard(
                                    entry: entry,
                                    isSelected: selection == .wine(entry.id) || (selection == nil && entry.id == selectedWine?.id),
                                    isRunning: isRunning(entry)
                                )
                                .onTapGesture(count: 2) {
                                    Task { try? await gameLauncher.launchSmart(entry.game, in: entry.bottle) }
                                }
                                .onTapGesture { selection = .wine(entry.id) }
                            }
                            ForEach(nativeEntries) { game in
                                NativeCoverCard(
                                    game: game,
                                    isSelected: selection == .native(game.id),
                                    isRunning: nativeGames.isRunning(game)
                                )
                                .onTapGesture(count: 2) { nativeGames.launch(game) }
                                .onTapGesture { selection = .native(game.id) }
                            }
                            AddGameTile(
                                hasNativeSteam: SteamAppManifest.nativeSteamRoot() != nil,
                                importSteam: { isShowingSteamImport = true },
                                importHeroic: { isShowingHeroicImport = true },
                                addApp: { pickApp() },
                                openBottles: openBottles
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 20)

            if let selectedNative {
                NativeInspector(game: selectedNative, isRunning: nativeGames.isRunning(selectedNative))
                    .frame(width: 264)
                    .padding([.trailing, .vertical], 14)
            } else if let selectedWine {
                GameInspector(entry: selectedWine, isRunning: isRunning(selectedWine))
                    .frame(width: 264)
                    .padding([.trailing, .vertical], 14)
            }
        }
        .sheet(isPresented: $isShowingSteamImport) {
            NativeSteamImportView()
        }
        .sheet(isPresented: $isShowingHeroicImport) {
            HeroicImportView()
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { nativeGames.addApp(at: url) }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Cover card

/// One game on the wall: cover art (fetched artwork when available, else the
/// exe icon on the brand-dark surface), confidence dot, playing chip, name.
private struct GameCoverCard: View {
    let entry: LibraryEntry
    let isSelected: Bool
    let isRunning: Bool

    @EnvironmentObject private var quirkService: QuirkService
    @EnvironmentObject private var userRecipeStore: UserRecipeStore
    @EnvironmentObject private var artworkStore: ArtworkStore
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var isHovering = false

    private var confidence: GameConfidence {
        let hasRecipe = userRecipeStore.recipe(forExecutablePath: entry.game.executablePath) != nil
            || GameRecipeCatalog.recipe(forExecutablePath: entry.game.executablePath) != nil
        return .assess(hasRecipe: hasRecipe,
                       findings: quirkService.findings(forGameNamed: entry.game.name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: FableTheme.innerRadius)
                .fill(FableTheme.surfaceRaised)
                .overlay {
                    if let art = artworkStore.image(for: entry.game) {
                        Image(nsImage: art)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ExeIconView(bottle: entry.bottle, game: entry.game,
                                    size: 64, fallbackSymbol: "gamecontroller.fill")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: FableTheme.innerRadius))
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(confidence.tint)
                        .frame(width: 10, height: 10)
                        .padding(4)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                        .help(confidence.label)
                }
                .overlay(alignment: .bottomLeading) {
                    if isRunning {
                        Label("Playing", systemImage: "play.fill")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.green)
                            .padding(6)
                    }
                }

            Text(entry.game.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                .fill(isSelected ? FableTheme.surfaceSelected : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.25), value: isHovering)
        .onHover { isHovering = $0 }
        .help("Click to inspect · double-click to play")
        .contextMenu {
            Button("Set Custom Cover…") { pickCustomCover() }
            Button("Refresh Cover") {
                Task {
                    await artworkStore.refreshArt(
                        for: entry.game, bottle: entry.bottle,
                        bottleManager: bottleManager, settings: settingsManager.settings
                    )
                }
            }
        }
        .task(id: entry.id) {
            await artworkStore.fetchIfNeeded(
                game: entry.game, bottle: entry.bottle,
                bottleManager: bottleManager, settings: settingsManager.settings
            )
        }
    }

    private func pickCustomCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        artworkStore.setCustomArt(for: entry.game, from: url)
    }
}

// MARK: - Inspector

/// How the selected game runs: Play and Tune sit up top, then health, backend,
/// performance, and triggers.
private struct GameInspector: View {
    let entry: LibraryEntry
    let isRunning: Bool

    @EnvironmentObject private var quirkService: QuirkService
    @EnvironmentObject private var userRecipeStore: UserRecipeStore
    @State private var isShowingTune = false

    private var confidence: GameConfidence {
        let hasRecipe = userRecipeStore.recipe(forExecutablePath: entry.game.executablePath) != nil
            || GameRecipeCatalog.recipe(forExecutablePath: entry.game.executablePath) != nil
        return .assess(hasRecipe: hasRecipe,
                       findings: quirkService.findings(forGameNamed: entry.game.name))
    }

    private var triggers: TriggerProfile {
        entry.game.effectiveTriggerProfile(bottleDefault: entry.bottle.triggerProfile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.game.name)
                    .font(.headline)
                    .lineLimit(2)
                Label(entry.bottle.name, systemImage: "wineglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                GamePlayButton(game: entry.game, bottle: entry.bottle, size: 42)
                Button {
                    isShowingTune = true
                } label: {
                    Label("Tune", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            Divider()

            Text("How it runs")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 9) {
                fact("Health") {
                    HStack(spacing: 5) {
                        Circle().fill(confidence.tint).frame(width: 7, height: 7)
                        Text(confidence.label).foregroundStyle(confidence.tint)
                    }
                }
                fact("Backend") { BackendBadge(backend: entry.effectiveBackend) }
                fact("Frame cap") {
                    Text(entry.bottle.performance.frameRateCap.map { "\($0) fps" } ?? "Uncapped")
                }
                fact("MetalFX") {
                    Image(systemName: entry.bottle.performance.metalFXUpscaling ? "checkmark" : "minus")
                        .foregroundStyle(entry.bottle.performance.metalFXUpscaling ? .green : .secondary)
                }
            }
            .font(.callout)

            if triggers.isActive {
                Divider()
                Text("Adaptive triggers")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    triggerChip("L2", mode: triggers.left.mode)
                    triggerChip("R2", mode: triggers.right.mode)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(FableTheme.surface, in: RoundedRectangle(cornerRadius: FableTheme.cardRadius))
        .sheet(isPresented: $isShowingTune) {
            GameSettingsView(game: entry.game, bottle: entry.bottle)
        }
    }

    private func fact(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            value()
        }
        .font(.callout)
    }

    private func triggerChip(_ name: String, mode: TriggerMode) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.caption.weight(.semibold))
            Text(mode.label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(FableTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: FableTheme.innerRadius))
    }
}

// MARK: - Native games

/// A native macOS game on the wall — same cover language, a blue "native" dot
/// instead of a Wine confidence verdict (it just runs).
private struct NativeCoverCard: View {
    let game: NativeGame
    let isSelected: Bool
    let isRunning: Bool

    @EnvironmentObject private var artworkStore: ArtworkStore
    @EnvironmentObject private var nativeGames: NativeGamesStore
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RoundedRectangle(cornerRadius: FableTheme.innerRadius)
                .fill(FableTheme.surfaceRaised)
                .overlay {
                    if let art = artworkStore.image(named: game.name) {
                        Image(nsImage: art)
                            .resizable()
                            .scaledToFill()
                    } else if let path = game.appPath {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 64, height: 64)
                    } else {
                        Image(systemName: "applelogo")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: FableTheme.innerRadius))
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(alignment: .bottomLeading) {
                    if isRunning {
                        Label("Playing", systemImage: "play.fill")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.green)
                            .padding(6)
                    }
                }

            HStack(spacing: 4) {
                Image(systemName: "applelogo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Native macOS — no Wine involved")
                Text(game.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                .fill(isSelected ? FableTheme.surfaceSelected : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .scaleEffect(isHovering ? 1.02 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.25), value: isHovering)
        .onHover { isHovering = $0 }
        .help("Click to inspect · double-click to play")
        .contextMenu {
            Button("Set Custom Cover…") { pickCustomCover() }
            Button("Remove from Library", role: .destructive) { nativeGames.remove(game) }
        }
        .task(id: game.id) {
            await artworkStore.fetchIfNeeded(native: game, settings: settingsManager.settings)
        }
    }

    private func pickCustomCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        artworkStore.setCustomArt(named: game.name, from: url)
    }
}

/// Inspector for a native game — honest and short: it runs natively, no
/// backend, no bottle, no tuning.
private struct NativeInspector: View {
    let game: NativeGame
    let isRunning: Bool

    @EnvironmentObject private var nativeGames: NativeGamesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(2)
                Label(game.sourceLabel, systemImage: "applelogo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                nativeGames.launch(game)
            } label: {
                Label(isRunning ? "Running" : "Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Divider()

            Text("How it runs")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)

            HStack {
                Text("Runtime").foregroundStyle(.secondary)
                Spacer()
                StatusBadge(text: "Native macOS", color: .blue)
            }
            .font(.callout)

            Text(game.steamAppID != nil
                 ? "Launches through the native Steam client — login, DRM, and cloud saves are Steam's."
                 : "A regular Mac app — Fable just launches it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(14)
        .background(FableTheme.surface, in: RoundedRectangle(cornerRadius: FableTheme.cardRadius))
    }
}

/// The wall's ONE add flow — every way a game can enter the library, in a
/// single menu: native Steam import, Heroic import, a plain Mac app, or
/// setting up a Windows game in a bottle.
private struct AddGameTile: View {
    let hasNativeSteam: Bool
    let importSteam: () -> Void
    let importHeroic: () -> Void
    let addApp: () -> Void
    let openBottles: () -> Void
    @State private var isHovering = false

    var body: some View {
        Menu {
            Section("Import") {
                if hasNativeSteam {
                    Button("From native Steam…", systemImage: "arrow.down.circle") { importSteam() }
                }
                Button("From Heroic (Epic/GOG)…", systemImage: "square.and.arrow.down") { importHeroic() }
                Button("A Mac App…", systemImage: "applelogo") { addApp() }
            }
            Section("Windows games") {
                Button("Set Up in a Bottle…", systemImage: "wineglass") { openBottles() }
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                Text("Add game")
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .aspectRatio(3 / 4, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: FableTheme.cardRadius)
                    .strokeBorder(
                        isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: FableTheme.cardRadius))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { isHovering = $0 }
        .help("Add a game to the wall")
    }
}

/// Multi-select import of installed native Steam games.
private struct NativeSteamImportView: View {
    @EnvironmentObject private var nativeGames: NativeGamesStore
    @Environment(\.dismiss) private var dismiss
    @State private var available: [(appID: Int, name: String)] = []
    @State private var selected: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from native Steam").font(.headline)
                    Text("Installed games from the macOS Steam client — they launch through Steam.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select All") { selected = Set(available.map(\.appID)) }
                    .controlSize(.small)
            }
            .padding(16)
            Divider()

            if available.isEmpty {
                ContentUnavailableView(
                    "Nothing to import",
                    systemImage: "checkmark.circle",
                    description: Text("Every installed native Steam game is already in the library.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(available, id: \.appID) { app in
                        Toggle(isOn: Binding(
                            get: { selected.contains(app.appID) },
                            set: { on in
                                if on { selected.insert(app.appID) } else { selected.remove(app.appID) }
                            }
                        )) {
                            Text(app.name)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            SheetActionBar {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            } trailing: {
                Button("Import") {
                    nativeGames.importNativeSteamGames(available.filter { selected.contains($0.appID) })
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .frame(width: 440, height: 420)
        .onAppear { available = nativeGames.availableNativeSteamGames() }
    }
}
