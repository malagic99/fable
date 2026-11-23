import Foundation

/// A game Steam has finished installing in a bottle, with the executable
/// Steam itself would start.
struct SteamLibraryGame: Equatable, Sendable {
    let appID: Int
    let name: String
    /// Relative to the bottle's `drive_c`.
    let executablePath: String
    let arguments: String
    /// The folder under `steamapps/common`.
    let installDir: String
}

/// Finds the games installed through a bottle's Steam and decides which are
/// new to Fable, so they can be put on the wall without the user hunting for
/// an .exe. Everything here is pure or read-only; adding is ``BottleManager``'s.
enum SteamLibrarySync {
    /// Steam's `StateFlags` bit for "fully installed".
    static let fullyInstalledFlag = 4

    /// App types that belong on a game wall. Tools (the shared
    /// redistributables, dedicated servers), configs, DLC, music and video
    /// are Steam's own bookkeeping or have nothing to launch.
    static let addableTypes: Set<String> = ["game", "demo", "application", "beta"]

    /// Launch types that are not the ordinary way to start the game.
    private static let skippedLaunchTypes: Set<String> = ["vr", "othervr", "openxr", "osvr", "config", "server", "editor", "manual"]

    /// What one `appmanifest_*.acf` says.
    struct Manifest: Equatable, Sendable {
        let appID: Int
        let name: String
        let installDir: String
        let stateFlags: Int
        /// The branch installed, when it isn't the public one.
        let betaKey: String?

        var isFullyInstalled: Bool { stateFlags & SteamLibrarySync.fullyInstalledFlag != 0 }

        static func parse(_ text: String) -> Manifest? {
            guard let appID = SteamAppManifest.value(of: "appid", in: text).flatMap(Int.init),
                  let name = SteamAppManifest.value(of: "name", in: text), !name.isEmpty,
                  let installDir = SteamAppManifest.value(of: "installdir", in: text),
                  // The folder name becomes part of a path: nothing that climbs out.
                  SteamPaths.isSafeFolderName(installDir)
            else { return nil }
            let flags = SteamAppManifest.value(of: "StateFlags", in: text).flatMap(Int.init) ?? 0
            let beta = SteamAppManifest.value(of: "BetaKey", in: text).flatMap { $0.isEmpty ? nil : $0 }
            return Manifest(appID: appID, name: name, installDir: installDir, stateFlags: flags, betaKey: beta)
        }
    }

    // MARK: Choosing the executable

    /// The launch entry Steam would use, as (executable, arguments) with the
    /// executable `/`-separated and relative to the install folder.
    ///
    /// The first Windows entry is not good enough. Control Resonant lists 25
    /// entries and the first is a developer profiling build that only exists
    /// on a private branch. So entries are ranked — the installed branch's
    /// first, then branch-less ones, then the rest — and the first whose file
    /// is actually on disk wins. `exists` answers that for a relative path.
    static func launchEntry(
        appInfo: VDFValue, betaKey: String?, exists: (String) -> Bool
    ) -> (executable: String, arguments: String)? {
        guard let launch = appInfo["config"]?["launch"], case .object(let entries) = launch else { return nil }

        struct Candidate { let executable: String; let arguments: String; let rank: Int }
        var candidates: [Candidate] = []
        for pair in entries {
            let entry: VDFValue = pair.value
            guard let raw = entry.string("executable") else { continue }
            // Steam writes either slash, sometimes doubled; one form from here on.
            let executable = raw.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
            guard executable.lowercased().hasSuffix(".exe"), isContained(executable) else { continue }
            if let type = entry.string("type")?.lowercased(), skippedLaunchTypes.contains(type) { continue }

            let config = entry["config"]
            let oslist = config?.string("oslist") ?? ""
            guard oslist.isEmpty || oslist.split(separator: ",").contains("windows") else { continue }

            // Steam writes this key as "BetaKey" in the cache and "betakey"
            // in app_info_print.
            let entryBeta = (config?.string("BetaKey") ?? config?.string("betakey")).flatMap { $0.isEmpty ? nil : $0 }
            let rank: Int
            if entryBeta == betaKey { rank = 0 }        // this branch (or both public)
            else if entryBeta == nil { rank = 1 }       // meant for every branch
            else { rank = 2 }                            // another branch's
            candidates.append(.init(executable: executable, arguments: entry.string("arguments") ?? "", rank: rank))
        }
        // Stable: within a rank, Steam's own order stands.
        let ordered = candidates.enumerated().sorted {
            ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset)
        }.map(\.element)
        return ordered.first { exists($0.executable) }.map { ($0.executable, $0.arguments) }
    }

    /// A relative path with no component that climbs out of its folder.
    static func isContained(_ relativePath: String) -> Bool {
        !relativePath.isEmpty && !relativePath.hasPrefix("/")
            && !relativePath.split(separator: "/").contains { $0 == ".." || $0 == "." }
    }

    // MARK: Discovering

    /// Every fully installed, launchable game in the bottle's Steam library.
    /// Reads the manifests and Steam's app cache; touches nothing.
    static func discover(steamRoot: URL, driveC: URL) -> [SteamLibraryGame] {
        let fm = FileManager.default
        let steamapps = steamRoot.appending(path: "steamapps", directoryHint: .isDirectory)
        let manifests: [Manifest] = ((try? fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }
            .compactMap { SteamAppManifest.readText(at: $0).flatMap(Manifest.parse) }
            .filter(\.isFullyInstalled)
        guard !manifests.isEmpty,
              let cache = SteamAppInfoCache.entries(for: Set(manifests.map(\.appID)), steamRoot: steamRoot)
        else { return [] }

        let relativeRoot = relativePath(of: steamapps, from: driveC)
        var games: [SteamLibraryGame] = []
        for manifest in manifests {
            guard let info = cache[manifest.appID], let relativeRoot,
                  let type = info["common"]?.string("type")?.lowercased(), addableTypes.contains(type)
            else { continue }
            let folder = steamapps.appending(path: "common", directoryHint: .isDirectory)
                .appending(path: manifest.installDir, directoryHint: .isDirectory)
            guard let entry = launchEntry(appInfo: info, betaKey: manifest.betaKey, exists: { relative in
                fm.fileExists(atPath: folder.appending(path: relative).path)
            }) else { continue }
            games.append(SteamLibraryGame(
                appID: manifest.appID,
                name: info["common"]?.string("name") ?? manifest.name,
                executablePath: "\(relativeRoot)/common/\(manifest.installDir)/\(entry.executable)",
                arguments: entry.arguments,
                installDir: manifest.installDir))
        }
        return games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `url` relative to `base`, or nil when it isn't inside it.
    static func relativePath(of url: URL, from base: URL) -> String? {
        let path = url.standardizedFileURL.path
        let root = base.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        return String(path.dropFirst(root.count + 1))
    }

    // MARK: Deciding what is new

    /// The discovered games Fable should add to `bottle` now.
    ///
    /// Left out: a game already added once (`known`) — so removing a game
    /// from the wall keeps it removed — and a game whose install folder
    /// already holds something on the wall, which the user put there by hand
    /// and may have pointed at a different .exe on purpose.
    static func newGames(_ discovered: [SteamLibraryGame], bottle: Bottle, known: Set<Int>) -> [SteamLibraryGame] {
        let takenFolders = Set(bottle.games.compactMap {
            SteamAppManifest.installDir(fromExecutablePath: $0.executablePath)?.lowercased()
        })
        return discovered.filter { game in
            !known.contains(game.appID) && !takenFolders.contains(game.installDir.lowercased())
        }
    }

    /// ``discover(steamRoot:driveC:)``, but only when the library changed
    /// since `previousFingerprint`: nil means "unchanged, nothing read".
    /// The fingerprint is taken first and is a few file stats, so an idle
    /// library costs almost nothing however often this runs. (It used to be
    /// taken alongside a full scan, so every check paid for the scan —
    /// security scan 2026-11-20, finding 6.)
    static func discoverIfChanged(
        steamRoot: URL, driveC: URL, previousFingerprint: String?
    ) -> (fingerprint: String, games: [SteamLibraryGame])? {
        let fingerprint = fingerprint(steamRoot: steamRoot)
        guard fingerprint != previousFingerprint else { return nil }
        return (fingerprint, discover(steamRoot: steamRoot, driveC: driveC))
    }

    /// A cheap fingerprint of what ``discover(steamRoot:driveC:)`` reads:
    /// the manifests' names and change times, and the cache's. Unchanged
    /// fingerprint, unchanged answer — so a periodic check can skip the work.
    static func fingerprint(steamRoot: URL) -> String {
        let fm = FileManager.default
        let steamapps = steamRoot.appending(path: "steamapps", directoryHint: .isDirectory)
        var parts: [String] = []
        let files = ((try? fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("appmanifest_") }
            + [steamRoot.appending(path: "appcache/appinfo.vdf")]
        for file in files.sorted(by: { $0.path < $1.path }) {
            let attributes = try? fm.attributesOfItem(atPath: file.path)
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            parts.append("\(file.lastPathComponent):\(modified):\(size)")
        }
        return parts.joined(separator: "|")
    }
}
