import Foundation

/// What this copy of Fable was built from, written into the app by
/// `scripts/build-info.py` at build time. Absent under `swift run` and in
/// tests, so everything here is optional.
struct BuildInfo: Codable, Equatable, Sendable {
    let version: String?
    let build: String?
    let commit: String?
    /// True when the source tree had uncommitted changes at build time: the
    /// commit then names the nearest source, not the exact one.
    let dirty: Bool?
    let builtAt: String?

    static let current: BuildInfo? = Bundle.main
        .url(forResource: "build-info", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap(load(from:))

    static func load(from data: Data) -> BuildInfo? {
        try? JSONDecoder().decode(BuildInfo.self, from: data)
    }

    /// "ee0adf6", or "ee0adf6+" for a build with uncommitted changes.
    var shortCommit: String? {
        guard let commit, commit.count >= 7 else { return nil }
        return String(commit.prefix(7)) + (dirty == true ? "+" : "")
    }

    /// "1.2.0 (ee0adf6)" — the version with its source, when known.
    static func versionLabel(_ version: String, info: BuildInfo? = current) -> String {
        guard let short = info?.shortCommit else { return version }
        return "\(version) (\(short))"
    }
}
