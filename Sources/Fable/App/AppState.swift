import SwiftUI

/// Top-level sections reachable from the sidebar.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case bottles
    case components
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottles: "Bottles"
        case .components: "Components"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .bottles: "wineglass"
        case .components: "shippingbox"
        case .settings: "gearshape"
        }
    }
}

/// Global application state shared through the environment.
@MainActor
final class AppState: ObservableObject {
    @Published var selectedSection: AppSection = .bottles

    /// Pinned component versions shipped with the app (Resources/versions.json).
    let versionCatalog: VersionCatalog

    init() {
        do {
            versionCatalog = try VersionCatalog.loadBundled()
        } catch {
            assertionFailure("versions.json is bundled with the app and must decode: \(error)")
            versionCatalog = VersionCatalog(components: [:])
        }
    }
}
