import Foundation

/// Finds an Unreal Engine game's user `Engine.ini` inside a bottle's
/// `drive_c`, and decides whether a game is even Unreal. Kept separate from
/// `MemoryDiet` (pure string ops) and takes plain URLs so it tests against a
/// temp directory with no bottle machinery.
///
/// Layout it relies on (verified against real Steam UE installs):
///   <install>/<Project>/Binaries/Win64/<X>-Win64-Shipping.exe   ← UE marker
///   drive_c/users/<user>/AppData/Local/<Project>/Saved/Config/
///       {Windows,WindowsNoEditor}/Engine.ini                    ← the file
enum MemoryDietLocator {
    private static let configPlatforms = ["Windows", "WindowsNoEditor"]  // UE5, UE4

    /// The UE project name (the directory holding `Binaries/Win64/*-Win64-
    /// Shipping.exe`), or nil if this doesn't look like an Unreal game.
    static func unrealProjectName(driveC: URL, executablePath: String) -> String? {
        let exe = driveC.appending(path: normalizedPath(executablePath))
        // Search the install root — the exe may be a launcher at the top, or
        // the shipping exe itself deeper in. Cap the walk so a huge install
        // never turns this into a disk crawl.
        let installRoot = installRoot(forExe: exe)
        guard let enumerator = FileManager.default.enumerator(
            at: installRoot, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var scanned = 0
        for case let url as URL in enumerator {
            scanned += 1
            if scanned > 6000 { break }  // shipping exe lives near the top
            guard url.lastPathComponent.hasSuffix("-Win64-Shipping.exe") else { continue }
            // …/<Project>/Binaries/Win64/<X>-Win64-Shipping.exe
            let win64 = url.deletingLastPathComponent()          // Win64
            let binaries = win64.deletingLastPathComponent()     // Binaries
            guard binaries.lastPathComponent == "Binaries" else { continue }
            let project = binaries.deletingLastPathComponent()   // <Project>
            return project.lastPathComponent
        }
        return nil
    }

    /// The game's user `Engine.ini`: the existing file if present, else the
    /// path to create (parent `AppData/Local/<Project>` must already exist,
    /// i.e. the game has run once). Returns nil for non-UE games or when no
    /// matching config location is found.
    static func engineINI(driveC: URL, executablePath: String) -> URL? {
        guard let project = unrealProjectName(driveC: driveC, executablePath: executablePath) else {
            return nil
        }
        let usersDir = driveC.appending(path: "users", directoryHint: .isDirectory)
        let users = ((try? FileManager.default.contentsOfDirectory(at: usersDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.hasDirectoryPath && $0.lastPathComponent != "Public" }

        // Exact project match: prefer an existing file; else the create-path
        // if the game's LocalAppData folder exists.
        var createPath: URL?
        for user in users {
            let localApp = user.appending(path: "AppData/Local/\(project)", directoryHint: .isDirectory)
            for platform in configPlatforms {
                let ini = localApp.appending(path: "Saved/Config/\(platform)/Engine.ini")
                if FileManager.default.fileExists(atPath: ini.path) { return ini }
            }
            if createPath == nil, FileManager.default.fileExists(atPath: localApp.path) {
                createPath = localApp.appending(path: "Saved/Config/Windows/Engine.ini")
            }
        }
        if let createPath { return createPath }

        // Fallback: the LocalAppData folder name occasionally differs from the
        // project dir (internal UE ProjectName). If exactly one UE config
        // exists across users, and it isn't clearly some other game, use it.
        let allConfigs = users.flatMap { engineINIs(underUser: $0) }
        return allConfigs.count == 1 ? allConfigs.first : nil
    }

    // MARK: Helpers

    private static func installRoot(forExe exe: URL) -> URL {
        // If the exe is the shipping exe itself (…/Binaries/Win64/…), the
        // install root is three levels up; otherwise it's the exe's folder.
        let parent = exe.deletingLastPathComponent()
        if parent.lastPathComponent == "Win64",
           parent.deletingLastPathComponent().lastPathComponent == "Binaries" {
            return parent.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        }
        return parent
    }

    private static func engineINIs(underUser user: URL) -> [URL] {
        let local = user.appending(path: "AppData/Local", directoryHint: .isDirectory)
        let projects = (try? FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: nil)) ?? []
        return projects.flatMap { proj -> [URL] in
            configPlatforms.compactMap {
                let ini = proj.appending(path: "Saved/Config/\($0)/Engine.ini")
                return FileManager.default.fileExists(atPath: ini.path) ? ini : nil
            }
        }
    }

    /// Windows `\` → `/` so `appending(path:)` builds a real URL.
    private static func normalizedPath(_ p: String) -> String {
        p.replacingOccurrences(of: "\\", with: "/")
    }
}

// MARK: - Disk state (read / toggle)

extension MemoryDietLocator {
    /// The Memory Diet state for a game: whether it's even applicable (a UE
    /// `Engine.ini` was located) and, if so, the pool cap currently applied.
    struct Status: Equatable {
        /// The resolved `Engine.ini` (existing or create-path); nil = not a
        /// UE game / no config location. `isApplicable` keys the UI off this.
        let iniURL: URL?
        /// The pool cap Fable's block currently writes, or nil if not applied.
        let appliedPoolMB: Int?

        var isApplicable: Bool { iniURL != nil }
        var isApplied: Bool { appliedPoolMB != nil }
    }

    static func status(driveC: URL, executablePath: String) -> Status {
        guard let ini = engineINI(driveC: driveC, executablePath: executablePath) else {
            return Status(iniURL: nil, appliedPoolMB: nil)
        }
        let content = (try? String(contentsOf: ini, encoding: .utf8)) ?? ""
        return Status(iniURL: ini, appliedPoolMB: MemoryDiet.appliedPoolMB(content))
    }

    /// Applies (or removes) the diet by editing the game's `Engine.ini`,
    /// creating the file + parent dirs if needed. Throws if the config
    /// location couldn't be found (non-UE game).
    static func setEnabled(_ on: Bool, driveC: URL, executablePath: String, poolMB: Int) throws {
        guard let ini = engineINI(driveC: driveC, executablePath: executablePath) else {
            throw MemoryDietError.notUnreal
        }
        let existing = (try? String(contentsOf: ini, encoding: .utf8)) ?? ""
        let updated = on ? MemoryDiet.apply(to: existing, poolMB: poolMB)
                         : MemoryDiet.remove(from: existing)
        try FileManager.default.createDirectory(
            at: ini.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try updated.write(to: ini, atomically: true, encoding: .utf8)
    }
}

enum MemoryDietError: LocalizedError {
    case notUnreal
    var errorDescription: String? {
        L10n.string("memdiet.error.not_unreal")
    }
}
