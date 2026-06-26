import Foundation

/// One installed Windows game discovered in a Heroic Games Launcher library.
struct HeroicGame: Identifiable, Hashable, Sendable {
    let appName: String
    let title: String
    /// Heroic's store backend: "gog", "legendary" (Epic), "nile" (Amazon).
    let runner: String
    /// Absolute macOS path of the game's install directory.
    let installPath: URL
    /// Executable relative to `installPath`.
    let executable: String
    let platform: String?
    /// Heroic's on-disk folder name for the install (for the bottle symlink).
    let folderName: String?

    var id: String { "\(runner):\(appName)" }

    /// Human store name for the badge.
    var sourceLabel: String {
        switch runner {
        case "gog": "GOG"
        case "legendary": "Epic"
        case "nile": "Amazon"
        default: runner.capitalized
        }
    }
}

/// Reads the Heroic Games Launcher's library caches and returns the installed
/// Windows games, so Fable can import them into a bottle. Heroic stores one
/// JSON cache per store under `store_cache/`; each lists every game with an
/// `install` block (`install_path` + `executable`) once it's installed.
///
/// Schema verified against a real Heroic install (2026-06): GOG games live
/// under the `games` key, Epic/Amazon under `library`.
enum HeroicLibrary {
    /// Heroic's config root, if present. macOS is case-insensitive, so the
    /// lowercase path resolves whichever case Heroic actually created.
    static func defaultRoot(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager fm: FileManager = .default
    ) -> URL? {
        let root = home.appending(path: "Library/Application Support/heroic", directoryHint: .isDirectory)
        return fm.fileExists(atPath: root.path) ? root : nil
    }

    /// Every installed Windows game across all three stores, de-duplicated and
    /// sorted by title. Safe on a missing/partial Heroic install (returns []).
    static func installedGames(root: URL, fileManager fm: FileManager = .default) -> [HeroicGame] {
        let sources: [(file: String, key: String)] = [
            ("store_cache/gog_library.json", "games"),
            ("store_cache/legendary_library.json", "library"),
            ("store_cache/nile_library.json", "library"),
        ]
        var seen = Set<String>()
        var games: [HeroicGame] = []
        for source in sources {
            for game in parse(file: source.file, arrayKey: source.key, root: root, fm: fm)
            where seen.insert(game.id).inserted {
                games.append(game)
            }
        }
        return games.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: Parsing

    private static func parse(file: String, arrayKey: String, root: URL, fm: FileManager) -> [HeroicGame] {
        let url = root.appending(path: file)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = obj[arrayKey] as? [[String: Any]]
        else { return [] }
        return array.compactMap(game(from:))
    }

    private static func game(from dict: [String: Any]) -> HeroicGame? {
        // Only installed games carry a usable install block.
        guard dict["is_installed"] as? Bool == true,
              let install = dict["install"] as? [String: Any],
              let installPath = install["install_path"] as? String, !installPath.isEmpty,
              let executable = install["executable"] as? String, !executable.isEmpty,
              // Fable runs Wine — Windows executables only, never mac-native builds.
              executable.lowercased().hasSuffix(".exe")
        else { return nil }

        let appName = dict["app_name"] as? String ?? installPath
        let title = dict["title"] as? String ?? appName
        // Skip store redistributables (e.g. GOG's "Galaxy Common Redistributables").
        guard !appName.lowercased().contains("redist"),
              !title.lowercased().contains("redistributable") else { return nil }

        return HeroicGame(
            appName: appName,
            title: title,
            runner: dict["runner"] as? String ?? "unknown",
            installPath: URL(fileURLWithPath: installPath),
            executable: executable,
            platform: install["platform"] as? String,
            folderName: dict["folder_name"] as? String
        )
    }
}
