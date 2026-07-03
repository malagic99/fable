import SwiftUI

/// The Gamer interface: games first, Big-Picture style. One horizontal bar
/// across the top carries the identity and all navigation — no sidebar at all —
/// and the content below runs full-bleed: the shared game wall (GameWallView),
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
    @Environment(\.fableGradient) private var gradient

    @State private var tab: Tab = .play

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
                GameWallView(openBottles: {
                    tab = .bottles
                    appState.selectedSection = .bottles
                })
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
                .help("Now playing — jump to the wall")
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
}
