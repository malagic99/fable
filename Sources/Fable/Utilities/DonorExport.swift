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

    // MARK: The owner's Mac user name

    /// The Windows profile name a donor export carries instead of the
    /// owner's. Wine names the profile after the Mac user, and writes that
    /// name — and the Mac home folder — into the registry dozens of times
    /// (external review 2026-11-23). On import it becomes the importer's.
    static let profilePlaceholder = "fable-donor"

    /// The registry files that name the profile and the Mac home folder.
    static let registryFiles = ["user.reg", "system.reg", "userdef.reg"]

    /// `text` with `user` replaced where it is a profile or home folder name:
    /// `\\users\\<user>` as the registry file writes it (`C:\users\…`,
    /// `Z:\Users\…` and `HOMEPATH`; the file doubles every backslash) and
    /// `/Users/<user>`, followed by a separator, a closing quote or the end
    /// of the line. The name alone is never replaced, so a user called
    /// "wine" or "steam" doesn't damage anything else.
    static func replacingProfileName(_ text: String, user: String, with replacement: String) -> String {
        guard !user.isEmpty, user != replacement else { return text }
        // `\\\\` in a pattern matches the file's `\\`.
        let pattern = #"(\\\\users\\\\|/users/)"# + NSRegularExpression.escapedPattern(for: user) + #"(?=\\\\|/|"|$)"#
        // And the one place the name stands alone: `HKCU\Volatile
        // Environment`'s USERNAME, which Wine sets from the Mac user.
        let variable = #"^("USERNAME"=")"# + NSRegularExpression.escapedPattern(for: user) + #"(?="$)"#
        var result = text
        for pattern in [pattern, variable] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
            else { return text }
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1" + NSRegularExpression.escapedTemplate(for: replacement))
        }
        return result
    }

    /// Makes a donor's prefix (a throwaway clone) stop naming its owner:
    ///
    /// - Every link in `drive_c` that points outside the bottle. Wine links
    ///   each profile's Desktop, Documents, Downloads, Music, Pictures,
    ///   Movies and Templates into the Mac user's home — in every profile,
    ///   including the `crossover` one CrossOver-made templates carry — and a
    ///   game can be linked in from anywhere. They name the owner and would
    ///   dangle on another Mac anyway. A link to a folder (or to nothing)
    ///   becomes an empty folder, so Windows programs still find one; a link
    ///   to a file is removed.
    /// - `drive_c/users/<user>` becomes ``profilePlaceholder``, and its
    ///   `AppData/Local/Temp`, where installers leave logs, is emptied.
    /// - Finder's `.DS_Store` files, which list folder names.
    /// - `dosdevices` keeps only `c:` and `z:`. The rest are the volumes that
    ///   happened to be mounted (disk images, USB drives, by name); Wine adds
    ///   the importer's own on first launch.
    ///
    /// Returns whether the profile folder was renamed. The registry is
    /// handled separately, with the other account data.
    @discardableResult
    static func anonymizeProfile(prefix: URL, user: String) throws -> Bool {
        let fm = FileManager.default
        let users = prefix.appending(path: "drive_c/users", directoryHint: .isDirectory)

        // One walk of drive_c. The enumerator doesn't follow links, so a
        // link to the owner's home is seen, never entered.
        var outwardLinks: [URL] = []
        let driveC = prefix.appending(path: "drive_c", directoryHint: .isDirectory)
        if let walker = fm.enumerator(at: driveC, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let item as URL in walker {
                if item.lastPathComponent == ".DS_Store" {
                    try? fm.removeItem(at: item)
                } else if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true,
                          let target = try? fm.destinationOfSymbolicLink(atPath: item.path),
                          target.hasPrefix("/") || target.split(separator: "/").contains("..") {
                    outwardLinks.append(item)
                }
            }
        }
        for link in outwardLinks {
            let wasFile = (try? link.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]))?
                .isRegularFile == true
            try fm.removeItem(at: link)
            if !wasFile { try fm.createDirectory(at: link, withIntermediateDirectories: false) }
        }

        let dosdevices = prefix.appending(path: "dosdevices", directoryHint: .isDirectory)
        for name in (try? fm.contentsOfDirectory(atPath: dosdevices.path)) ?? []
        where !["c:", "z:"].contains(name.lowercased()) {
            try fm.removeItem(at: dosdevices.appending(path: name))
        }

        let profile = users.appending(path: user, directoryHint: .isDirectory)
        let placeholder = users.appending(path: profilePlaceholder, directoryHint: .isDirectory)
        guard !user.isEmpty, user != profilePlaceholder, SteamPaths.isSafeFolderName(user),
              isDirectory(profile, fm: fm), !fm.fileExists(atPath: placeholder.path)
        else { return false }

        let temp = profile.appending(path: "AppData/Local/Temp", directoryHint: .isDirectory)
        if isDirectory(temp, fm: fm) {
            try fm.removeItem(at: temp)
            try fm.createDirectory(at: temp, withIntermediateDirectories: false)
        }
        try fm.moveItem(at: profile, to: placeholder)
        return true
    }

    /// `excluding` with the owner's profile folder renamed, so exclusions
    /// for games kept inside the profile still match after
    /// ``anonymizeProfile(prefix:user:)``.
    static func renamingProfile(in excluding: [String], user: String, prefixEntry: String) -> [String] {
        let from = "\(prefixEntry)/drive_c/users/\(literalPattern(user))/"
        let to = "\(prefixEntry)/drive_c/users/\(profilePlaceholder)/"
        return excluding.map { $0.hasPrefix(from) ? to + $0.dropFirst(from.count) : $0 }
    }

    /// On import, gives a donor's profile the importer's name: the folder,
    /// and every registry path naming it. Left as ``profilePlaceholder``
    /// (which works just as well) when a folder with the importer's name is
    /// already there.
    static func restoreProfile(prefix: URL, user: String) {
        let fm = FileManager.default
        guard !user.isEmpty, user != profilePlaceholder, SteamPaths.isSafeFolderName(user) else { return }
        let users = prefix.appending(path: "drive_c/users", directoryHint: .isDirectory)
        let placeholder = users.appending(path: profilePlaceholder, directoryHint: .isDirectory)
        let profile = users.appending(path: user, directoryHint: .isDirectory)
        guard !fm.fileExists(atPath: profile.path) else { return }
        if fm.fileExists(atPath: placeholder.path) {
            guard (try? fm.moveItem(at: placeholder, to: profile)) != nil else { return }
        }
        for name in registryFiles {
            let file = prefix.appending(path: name)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let restored = replacingProfileName(text, user: profilePlaceholder, with: user)
            if restored != text { try? restored.write(to: file, atomically: true, encoding: .utf8) }
        }
    }

    private static func isDirectory(_ url: URL, fm: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
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
