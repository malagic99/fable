import SwiftUI

/// The Gamer interface: games first. A cover wall of every game across every
/// bottle, a confidence dot on each cover (will it run?), and an inspector
/// showing how the selected game runs. The rail is the app's ONE navigation —
/// Play plus the workshop destinations — so there's no second sidebar to wade
/// through.
struct GamerHomeView: View {
    private enum Section: Hashable { case play, bottles, components, settings }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var bottleManager: BottleManager
    @EnvironmentObject private var gameLauncher: GameLauncher
    @EnvironmentObject private var activityMonitor: ActivityMonitor
    @EnvironmentObject private var settingsManager: SettingsManager

    @State private var section: Section = .play
    @State private var searchText = ""
    @State private var selectedID: LibraryEntry.ID?

    private var entries: [LibraryEntry] {
        LibraryIndex.entries(from: bottleManager.bottles, query: searchText)
    }

    private var selected: LibraryEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    private func isRunning(_ entry: LibraryEntry) -> Bool {
        gameLauncher.isRunning(entry.game.id) || activityMonitor.isRunning(entry.game, in: entry.bottle)
    }

    private var nowPlaying: LibraryEntry? {
        LibraryIndex.entries(from: bottleManager.bottles).first { isRunning($0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            if section == .play {
                playSurface
            } else {
                MainContentView()
            }
        }
    }

    // MARK: Rail — the one navigation

    private var rail: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                Image(systemName: "wineglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(FableTheme.accentGradient, in: RoundedRectangle(cornerRadius: 7))
                Text("Fable").font(.title3.weight(.bold))
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 14)

            railButton("Play", symbol: "play.fill", active: section == .play) { section = .play }
            if let nowPlaying {
                railButton(nowPlaying.game.name, symbol: "waveform", active: false) {
                    section = .play
                    selectedID = nowPlaying.id
                }
                .overlay(alignment: .trailing) {
                    Circle().fill(.green).frame(width: 7, height: 7).padding(.trailing, 14)
                }
            }

            Divider().padding(.vertical, 8).padding(.horizontal, 12)

            railButton("Bottles", symbol: "square.stack.3d.up", active: section == .bottles) { go(.bottles, .bottles) }
            railButton("Components", symbol: "shippingbox", active: section == .components) { go(.components, .components) }
            railButton("Settings", symbol: "gearshape", active: section == .settings) { go(.settings, .settings) }

            Spacer()
        }
        .frame(width: 178)
        .background(.background.secondary)
    }

    private func go(_ section: Section, _ appSection: AppSection) {
        self.section = section
        appState.selectedSection = appSection
    }

    private func railButton(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.callout.weight(active ? .semibold : .regular))
            .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                active ? AnyShapeStyle(.quaternary.opacity(0.8)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
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
                .padding(.top, 18)

                if entries.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "No games yet" : "No matches", systemImage: "square.grid.2x2")
                    } description: {
                        Text(searchText.isEmpty
                             ? "Add games in Bottles and they'll appear here as covers."
                             : "Nothing matches “\(searchText)”.")
                    } actions: {
                        if searchText.isEmpty {
                            Button("Open Bottles") { go(.bottles, .bottles) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        let coverMin = TileMetrics.coverMin(settingsManager.settings.tileScale)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: coverMin, maximum: coverMin * 1.25), spacing: 16)],
                                  spacing: 16) {
                            ForEach(entries) { entry in
                                GameCoverCard(
                                    entry: entry,
                                    isSelected: entry.id == selected?.id,
                                    isRunning: isRunning(entry)
                                )
                                .onTapGesture(count: 2) {
                                    Task { try? await gameLauncher.launchSmart(entry.game, in: entry.bottle) }
                                }
                                .onTapGesture { selectedID = entry.id }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    HStack(spacing: 14) {
                        legendDot(.green, "verified")
                        legendDot(.orange, "works with tweaks")
                        legendDot(.red, "won't run")
                        legendDot(Color.secondary.opacity(0.6), "untested")
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 20)

            if let selected {
                GameInspector(entry: selected, isRunning: isRunning(selected))
                    .frame(width: 235)
                    .padding([.trailing, .vertical], 14)
            }
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Cover card

/// One game on the wall: cover art (exe icon on the brand-dark surface),
/// confidence dot, playing chip, name.
private struct GameCoverCard: View {
    let entry: LibraryEntry
    let isSelected: Bool
    let isRunning: Bool

    @EnvironmentObject private var quirkService: QuirkService
    @EnvironmentObject private var userRecipeStore: UserRecipeStore
    @State private var isHovering = false

    private var confidence: GameConfidence {
        let hasRecipe = userRecipeStore.recipe(forExecutablePath: entry.game.executablePath) != nil
            || GameRecipeCatalog.recipe(forExecutablePath: entry.game.executablePath) != nil
        return .assess(hasRecipe: hasRecipe,
                       findings: quirkService.findings(forGameNamed: entry.game.name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary.opacity(0.6))
                ExeIconView(bottle: entry.bottle, game: entry.game,
                            size: 64, fallbackSymbol: "gamecontroller.fill")
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(confidence.tint)
                    .frame(width: 10, height: 10)
                    .padding(4)
                    .background(.background.opacity(0.6), in: Circle())
                    .padding(6)
                    .help(confidence.label)
            }
            .overlay(alignment: .bottomLeading) {
                if isRunning {
                    Label("Playing", systemImage: "play.fill")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.25), in: Capsule())
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
