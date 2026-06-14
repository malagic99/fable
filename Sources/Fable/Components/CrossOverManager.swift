import Foundation

enum CrossOverError: LocalizedError {
    case notInstalled
    case binaryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "CrossOver isn't installed. Get it from codeweavers.com, then this backend will work without further setup."
        case .binaryNotFound(let searched):
            "CrossOver is installed but no wine binary was found under \(searched). Try re-installing CrossOver."
        }
    }
}

/// Detects CrossOver's app bundle and exposes its wine binary for use
/// as a Fable graphics backend. CrossOver bundles wine 9+ AND Apple's
/// licensed D3DMetal in a version-matched pair — modern SEH for games
/// that fail under GPTK's wine 7.7, plus the D3DMetal optimization
/// layer. The trade-off is CrossOver is paid ($74/yr); we can't ship
/// it, only use it when the user has it installed.
@MainActor
final class CrossOverManager: ObservableObject {
    /// Canonical install location. `/usr/local` style installs aren't
    /// supported — CrossOver always lives in /Applications.
    nonisolated static let installPath = URL(filePath: "/Applications/CrossOver.app", directoryHint: .isDirectory)

    @Published private(set) var isInstalled: Bool = false

    init() {
        refresh()
    }

    func refresh() {
        isInstalled = FileManager.default.fileExists(atPath: Self.installPath.path)
    }

    /// Locates CrossOver's wine binary. CrossOver ships it inside the
    /// app bundle's SharedSupport/CrossOver hierarchy, not in standard
    /// /Contents/MacOS — different from GPTK + Whisky.
    func wineBinary() throws -> URL {
        guard isInstalled else { throw CrossOverError.notInstalled }
        let fm = FileManager.default

        // Known relative paths for CrossOver 23/24/25. Search in
        // order — newer first.
        let candidates = [
            "Contents/SharedSupport/CrossOver/CrossOver-Hosted Application/wine",
            "Contents/SharedSupport/CrossOver/bin/wine64",
            "Contents/SharedSupport/CrossOver/bin/wine",
        ]
        for relative in candidates {
            let url = Self.installPath.appending(path: relative)
            if fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        throw CrossOverError.binaryNotFound(Self.installPath.path)
    }

    /// wineserver sits next to wine in CrossOver's hosted app dir.
    func wineserverBinary() throws -> URL {
        let wine = try wineBinary()
        let candidate = wine.deletingLastPathComponent().appending(path: "wineserver")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw CrossOverError.binaryNotFound(candidate.path)
    }

    /// Environment fragment for launching a game on the CrossOver
    /// backend. CrossOver's wine handles its own DLL routing — we
    /// don't need WINEDLLOVERRIDES tweaks, just pass the prefix path.
    nonisolated static func launchEnvironment(baseOverrides: String) -> [String: String] {
        var env: [String: String] = [:]
        if !baseOverrides.isEmpty {
            env["WINEDLLOVERRIDES"] = baseOverrides
        }
        return env
    }
}
