import Foundation

/// What a "Donor for a Friend" export leaves out, beyond the folders in
/// ``BottleArchive/donorExclusions(for:)``.
///
/// Security scan 2026-11-20 found three things that still travelled:
/// - the Steam **account name** (`AutoLoginUser`) and per-account state, kept
///   in the Windows registry file `user.reg`, which the folder exclusions
///   can't reach without dropping the whole registry;
/// - games outside `steamapps` — Steam-bridge downloads and games installed
///   by hand — whose files and wall entries shipped in a "no games" export;
/// - the list of Steam apps the owner has installed (`steamSyncedAppIDs`).
enum DonorExport {
    /// Values under `HKCU\Software\Valve\Steam` that identify the owner.
    static let steamAccountValues: Set<String> = [
        "AutoLoginUser", "LastGameNameUsed", "RememberPassword", "PersonaName",
    ]

    /// Registry keys under `HKCU\Software\Valve\Steam` dropped whole: the
    /// signed-in account (`ActiveProcess` holds its id) and every installed
    /// app's name. Steam rebuilds both on first launch.
    static let steamAccountKeyPrefixes = [
        #"Software\\Valve\\Steam\\ActiveProcess"#,
        #"Software\\Valve\\Steam\\Apps\\"#,
    ]

    /// `user.reg` with the owner's Steam account data removed and everything
    /// else byte-for-byte as it was. Wine's registry format: a `[key] stamp`
    /// line, then value lines until the next key; a value may continue over
    /// several lines, each ending in a backslash.
    static func sanitizedUserRegistry(_ text: String) -> String {
        var output: [Substring] = []
        var inSteamKey = false
        var droppingKey = false
        var droppingValue = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if droppingValue {
                // The continuation of a value being removed.
                droppingValue = line.hasSuffix("\\")
                continue
            }
            if line.hasPrefix("[") {
                let name = keyName(line)
                inSteamKey = name == #"Software\\Valve\\Steam"#
                droppingKey = steamAccountKeyPrefixes.contains { name.hasPrefix($0) || name == $0 }
                if droppingKey { continue }
                output.append(line)
                continue
            }
            if droppingKey { continue }
            if inSteamKey, let value = valueName(line), steamAccountValues.contains(value) {
                droppingValue = line.hasSuffix("\\")
                continue
            }
            output.append(line)
        }
        return output.joined(separator: "\n")
    }

    /// `[Software\\Valve\\Steam] 1794875685` → `Software\\Valve\\Steam`
    /// (backslashes kept doubled, as the file has them).
    private static func keyName(_ line: Substring) -> String {
        guard let close = line.lastIndex(of: "]") else { return String(line.dropFirst()) }
        return String(line[line.index(after: line.startIndex)..<close])
    }

    /// `"AutoLoginUser"="…"` → `AutoLoginUser`.
    private static func valueName(_ line: Substring) -> String? {
        guard line.first == "\"", let end = line.dropFirst().firstIndex(of: "\"") else { return nil }
        return String(line[line.index(after: line.startIndex)..<end])
    }

    // MARK: Games

    /// Folders, relative to `drive_c`, holding the files of games that
    /// aren't Steam's own — dropped from a donor export like `steamapps` is.
    /// A game's folder is the first path component below the usual
    /// containers (`Program Files`, `Games`, …); a program in `windows`
    /// is part of Windows and is never dropped.
    static func gameFolders(of bottle: Bottle) -> [String] {
        var folders: Set<String> = [SteamCmd.installRoot]
        for game in bottle.games where !isSteamClient(game) {
            let parts = game.executablePath.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/").map(String.init)
            guard parts.count >= 2, parts[0].lowercased() != "windows",
                  !parts.contains(where: { $0 == ".." || $0 == "." })
            else { continue }
            if parts[0].lowercased() == "users" {
                // users/<name>/…/Game/game.exe → the game's own folder.
                guard parts.count >= 4 else { continue }
                folders.insert(parts.dropLast().joined(separator: "/"))
                continue
            }
            var index = 0
            while index < parts.count - 2, containers.contains(parts[index].lowercased()) { index += 1 }
            let folder = parts[0...index].joined(separator: "/")
            // Never a container itself, and never Steam (handled by name).
            guard !containers.contains(parts[index].lowercased()),
                  !folder.lowercased().hasPrefix(SteamPaths.clientDirRelative.lowercased())
            else { continue }
            folders.insert(folder)
        }
        return folders.sorted()
    }

    private static let containers: Set<String> = [
        "program files", "program files (x86)", "games", "gog games", "programdata",
    ]

    static func isSteamClient(_ game: Game) -> Bool {
        game.executablePath.replacingOccurrences(of: "\\", with: "/")
            .caseInsensitiveCompare(SteamPaths.exeRelative) == .orderedSame
    }

    /// A tar `--exclude` pattern matching `path` literally: bsdtar reads
    /// these as globs, and game folder names can contain `[`, `*` or `?`.
    static func literalPattern(_ path: String) -> String {
        var escaped = ""
        for character in path {
            if "*?[]\\".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
