import Foundation

/// Finds the Windows redistributable installers Steam unpacks into a game's
/// `_CommonRedist/` folder but — under Fable's experimental-WoW64 Steam —
/// never actually runs.
///
/// On Windows, after a depot finishes, Steam executes the game's bundled
/// vcredist / DirectX / OpenAL setups. Under our Steam the install step
/// silently no-ops (the same dead-service gap that stalls commits, see
/// `SteamInstallCommitter`), so a big multi-depot game lands on disk and then
/// crashes on first launch for a missing `vcruntime140.dll`. We discover those
/// installers and hand them to `RedistInstaller` to run ourselves — once.
enum SteamRedistInstaller {
    /// Marker written next to Steam listing the redist relative-paths already
    /// run in this prefix, so we never re-run them — and a cloned bottle that
    /// inherits the marker (via `cp -c`) skips them entirely.
    static let markerName = ".fable_installed_redists"

    struct PendingRedist: Equatable, Sendable {
        let url: URL
        /// Path relative to the Steam root — the stable idempotency key.
        let key: String
        let kind: RedistInstaller.Kind
    }

    /// Recognized redist installers under `steamapps/common/<game>/_CommonRedist/`
    /// not yet recorded in the marker. Deliberately limited to installers Fable
    /// knows how to drive silently (vcredist / DirectX / OpenAL) — a generic
    /// `.exe` with the wrong silent flag would pop a GUI and hang the prefix.
    static func pendingRedists(
        steamRoot: URL,
        fileManager fm: FileManager = .default
    ) -> [PendingRedist] {
        let common = steamRoot.appending(path: "steamapps/common", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: common.path),
              let games = try? fm.contentsOfDirectory(
                at: common,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }

        let installed = installedKeys(steamRoot: steamRoot, fileManager: fm)
        var found: [PendingRedist] = []
        var seen = Set<String>()

        // Only descend into each game's `_CommonRedist` subtree — never the
        // multi-GB game body — so this stays a cheap walk even on huge installs.
        for game in games {
            let redistDir = game.appending(path: "_CommonRedist", directoryHint: .isDirectory)
            guard fm.fileExists(atPath: redistDir.path),
                  let walker = fm.enumerator(
                    at: redistDir,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                  )
            else { continue }

            for case let url as URL in walker {
                guard url.pathExtension.lowercased() == "exe" else { continue }
                let kind = RedistInstaller.classify(url)
                guard kind != .generic else { continue }  // only known-silent installers
                let key = relativeKey(of: url, under: steamRoot)
                guard !installed.contains(key), seen.insert(key).inserted else { continue }
                found.append(PendingRedist(url: url, key: key, kind: kind))
            }
        }

        // Stable, sensible order: vcredist first (almost every game needs it),
        // then DirectX, then OpenAL; alpha within a kind for determinism.
        return found.sorted { ($0.kind.installRank, $0.key) < ($1.kind.installRank, $1.key) }
    }

    /// Record these redist keys as done, appending to any existing marker.
    static func markInstalled(
        _ keys: [String],
        steamRoot: URL,
        fileManager fm: FileManager = .default
    ) {
        guard !keys.isEmpty else { return }
        let merged = installedKeys(steamRoot: steamRoot, fileManager: fm).union(keys)
        let text = merged.sorted().joined(separator: "\n") + "\n"
        try? Data(text.utf8).write(to: marker(steamRoot: steamRoot), options: .atomic)
    }

    // MARK: Internals

    private static func marker(steamRoot: URL) -> URL {
        steamRoot.appending(path: markerName)
    }

    private static func installedKeys(steamRoot: URL, fileManager fm: FileManager) -> Set<String> {
        guard let text = try? String(contentsOf: marker(steamRoot: steamRoot), encoding: .utf8) else {
            return []
        }
        return Set(text.split(whereSeparator: \.isNewline).map(String.init))
    }

    /// Lowercased path of `url` relative to `steamRoot` (symlink-normalized so
    /// `/var` vs `/private/var` doesn't split keys).
    private static func relativeKey(of url: URL, under steamRoot: URL) -> String {
        let root = steamRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let abs = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard abs.hasPrefix(root) else { return abs.lowercased() }
        return String(abs.dropFirst(root.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
