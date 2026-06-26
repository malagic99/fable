import SwiftUI

/// Top-level sections reachable from the sidebar.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case bottles
    case library
    case components
    case settings

    var id: String { rawValue }

    /// Localization key for the section's display name. Lives in
    /// Localizable.strings as `sidebar.<rawValue>`.
    var localizationKey: String { "sidebar.\(rawValue)" }

    /// Localized display name as a plain String — for navigationTitle
    /// and other String-typed APIs that don't take LocalizedStringKey.
    var title: String {
        L10n.string(localizationKey)
    }

    /// Localized display name as a LocalizedStringKey — for Label/Text
    /// which auto-resolve through the locale-aware key path.
    var titleKey: LocalizedStringKey {
        LocalizedStringKey(localizationKey)
    }

    var systemImage: String {
        switch self {
        case .bottles: "wineglass"
        case .library: "square.grid.2x2"
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
