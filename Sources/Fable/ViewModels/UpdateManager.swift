import Foundation

enum UpdateError: LocalizedError {
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let detail):
            "Couldn't check for updates: \(detail)"
        }
    }
}

/// Checks GitHub for newer component releases and installs them.
/// Checksums come from GitHub's own asset digests, so updates stay
/// verified even though they're newer than the pinned versions.json.
@MainActor
final class UpdateManager: ObservableObject {
    /// Newer-than-installed components found by the last check.
    @Published private(set) var available: [String: VersionCatalog.Component] = [:]
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?

    let componentManager: ComponentManager
    let catalog: VersionCatalog

    init(componentManager: ComponentManager, catalog: VersionCatalog) {
        self.componentManager = componentManager
        self.catalog = catalog
    }

    /// The version currently on disk for a component, if any.
    func installedVersion(of id: String) -> String? {
        componentManager.installedDirectory(for: id)?.lastPathComponent
    }

    // MARK: Checking

    func checkForUpdates() async {
        isChecking = true
        lastError = nil
        defer {
            isChecking = false
            lastChecked = .now
        }

        do {
            async let wine = Self.latestRelease(
                repo: "Gcenx/macOS_Wine_builds",
                assetPrefix: "wine-stable-",
                assetSuffix: "-osx64.tar.xz",
                displayName: "Wine Stable"
            )
            async let dxmt = Self.latestRelease(
                repo: "3Shain/dxmt",
                assetPrefix: "dxmt-v",
                assetSuffix: "-builtin.tar.gz",
                displayName: "DXMT"
            )

            var found: [String: VersionCatalog.Component] = [:]
            if let wine = try await wine, isUpdate(wine, for: WineManager.componentID) {
                found[WineManager.componentID] = wine
            }
            if let dxmt = try await dxmt, isUpdate(dxmt, for: DXMTManager.componentID) {
                found[DXMTManager.componentID] = dxmt
            }
            available = found
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func isUpdate(_ component: VersionCatalog.Component, for id: String) -> Bool {
        let current = installedVersion(of: id)
            ?? catalog.components[id]?.version
            ?? "0"
        return VersionCompare.isNewer(component.version, than: current)
    }

    /// Installs an available update (or anything else) through the
    /// component manager.
    func install(_ component: VersionCatalog.Component, id: String) async throws {
        try await componentManager.install(id: id, component: component)
        available[id] = nil
    }

    // MARK: GitHub

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let digest: String?
        }
        let tag_name: String
        let assets: [Asset]
    }

    /// Finds the newest release in `repo` carrying an asset that matches
    /// prefix/suffix, returning it as a catalog component.
    nonisolated private static func latestRelease(
        repo: String,
        assetPrefix: String,
        assetSuffix: String,
        displayName: String
    ) async throws -> VersionCatalog.Component? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=20")!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.badResponse("GitHub returned HTTP \(http.statusCode) for \(repo)")
        }
        return try component(
            fromReleasesJSON: data,
            assetPrefix: assetPrefix,
            assetSuffix: assetSuffix,
            displayName: displayName
        )
    }

    /// Pure parsing step, separated for testability.
    nonisolated static func component(
        fromReleasesJSON data: Data,
        assetPrefix: String,
        assetSuffix: String,
        displayName: String
    ) throws -> VersionCatalog.Component? {
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        for release in releases {
            guard let asset = release.assets.first(where: {
                $0.name.hasPrefix(assetPrefix) && $0.name.hasSuffix(assetSuffix)
            }) else { continue }

            let version = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst())
                : release.tag_name
            let sha256 = asset.digest?.replacingOccurrences(of: "sha256:", with: "") ?? ""
            return VersionCatalog.Component(
                name: displayName,
                version: version,
                url: asset.browser_download_url,
                sha256: sha256
            )
        }
        return nil
    }
}
