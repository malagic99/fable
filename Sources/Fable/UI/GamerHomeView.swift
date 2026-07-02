import SwiftUI

/// The Gamer interface: games first, Big-Picture style. One horizontal bar
/// across the top carries the identity and all navigation — no sidebar at all —
/// and the content below runs full-bleed: the cover wall with its inspector,
/// or the workshop sections.
struct GamerHomeView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case play, bottles, components, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .play: "Play"
            case .bottles: "Bottles"
            case .components: "Components"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .play: "play.fill"
            case .bottles: "square.stack.3d.up"
            case .components: "shippingbox"
            case .settings: "gearshape"
            }
        }

        var appSection: AppSection? {
            switch self {
            case .play: nil
            case .bottles: .bottles
            case .components: .components
            case .settings: .settings
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var activityMonitor: ActivityMonitor
    @EnvironmentObject private var settingsManager: SettingsManager
    @Environment(\.fableGradient) private var gradient

    @EnvironmentObject private var nativeGames: NativeGamesStore

    /// The wall holds both worlds; selection distinguishes them.
    private enum Selection: Hashable {
        case wine(LibraryEntry.ID)
        case native(NativeGame.ID)
    }

    @State private var tab: Tab = .play
    @State private var searchText = ""
    @State private var selection: Selection?
    @State private var isShowingSteamImport = false

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

    private var nowPlaying: LibraryEntry? {
        LibraryIndex.entries(from: bottleManager.bottles).first { isRunning($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if tab == .play {
                playSurface
            } else {
                MainContentView()
            }
        }
    }

    // MARK: Top bar — the one navigation, horizontal

    private var topBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "wineglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(gradient, in: RoundedRectangle(cornerRadius: 7))
                Text("Fable").font(.headline.weight(.bold))
            }

            HStack(spacing: 4) {
                ForEach(Tab.allCases) { item in
                    tabButton(item)
                }
            }

            Spacer()

            if let nowPlaying {
                Button {
                    tab = .play
                    selection = .wine(nowPlaying.id)
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        Text(nowPlaying.game.name)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Now playing — jump to it")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.background.secondary)
    }

    private func tabButton(_ item: Tab) -> some View {
        let active = tab == item
        return Button {
            tab = item
            if let section = item.appSection { appState.selectedSection = section }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(item.title)
            }
            .font(.callout.weight(active ? .semibold : .regular))
            .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                active ? AnyShapeStyle(.quaternary.opacity(0.8)) : AnyShapeStyle(.clear),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Play surface (cover wall + inspector)

    private var playSurface: some View {
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
                    .background(.quaternary.opacity(0.5), in: Capsule())
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
                                addApp: { pickApp() },
                                openBottles: {
                                    tab = .bottles
                                    appState.selectedSection = .bottles
                                }
                            )
                        }
                        .padding(.vertical, 4)
                    }
                    HStack(spacing: 14) {
                        legendDot(.green, "verified")
                        legendDot(.orange, "works with tweaks")
                        legendDot(.red, "won't run")
                        legendDot(Color.secondary.opacity(0.6), "untested")
                        legendDot(.blue, "native mac")
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 20)

            if let selectedNative {
                NativeInspector(game: selectedNative, isRunning: nativeGames.isRunning(selectedNative))
                    .frame(width: 235)
                    .padding([.trailing, .vertical], 14)
            } else if let selectedWine {
                GameInspector(entry: selectedWine, isRunning: isRunning(selectedWine))
                    .frame(width: 235)
                    .padding([.trailing, .vertical], 14)
            }
        }
        .sheet(isPresented: $isShowingSteamImport) {
            NativeSteamImportView()
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
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.6))
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
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
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
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
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.6))
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)
                        .padding(4)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                        .help("Native macOS — no Wine involved")
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

            Text(game.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The wall's add tile: native Steam import, a plain .app, or the Bottles
/// section for Windows games.
private struct AddGameTile: View {
    let hasNativeSteam: Bool
    let importSteam: () -> Void
    let addApp: () -> Void
    let openBottles: () -> Void
    @State private var isHovering = false

    var body: some View {
        Menu {
            if hasNativeSteam {
                Button("Import from native Steam…", systemImage: "arrow.down.circle") { importSteam() }
            }
            Button("Add Mac App…", systemImage: "applelogo") { addApp() }
            Button("Windows games → Bottles", systemImage: "wineglass") { openBottles() }
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
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isHovering ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
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
