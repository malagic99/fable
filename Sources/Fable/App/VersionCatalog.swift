import Foundation

/// The set of runtime components Fable knows how to download, keyed by
/// identifier ("wine", "dxmt"). Backed by Resources/versions.json.
struct VersionCatalog: Codable, Equatable, Sendable {
    struct Component: Codable, Equatable, Sendable {
        let name: String
        let version: String
        let url: URL
        /// SHA-256 of the download. Empty until pinned (Day 3).
        let sha256: String
    }

    let components: [String: Component]

    var wine: Component? { components["wine"] }
    var dxmt: Component? { components["dxmt"] }

    static func loadBundled() throws -> VersionCatalog {
        guard let url = Bundle.module.url(forResource: "versions", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try load(from: Data(contentsOf: url))
    }

    static func load(from data: Data) throws -> VersionCatalog {
        try JSONDecoder().decode(VersionCatalog.self, from: data)
    }
}
