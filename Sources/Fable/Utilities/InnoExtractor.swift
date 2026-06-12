import Foundation

enum InnoExtractError: LocalizedError {
    case toolMissing
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolMissing:
            "innoextract isn't installed. Install it with Homebrew: brew install innoextract"
        case .extractionFailed(let detail):
            "Couldn't extract the installer: \(detail)"
        }
    }
}

/// Unpacks Inno Setup installers (GOG offline backups) directly, without
/// running them under Wine. Old GOG installers crash Wine's WoW64 layer,
/// so direct extraction is the reliable path.
enum InnoExtractor {
    /// Locates innoextract: bundled with the app, or Homebrew/MacPorts.
    static func find() -> URL? {
        var candidates = [
            URL(filePath: "/opt/homebrew/bin/innoextract"),
            URL(filePath: "/usr/local/bin/innoextract"),
            URL(filePath: "/opt/local/bin/innoextract"),
        ]
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "innoextract") {
            candidates.insert(bundled, at: 0)
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// True if the file is an Inno Setup installer innoextract can read.
    static func isInnoSetup(_ installer: URL) async -> Bool {
        guard let tool = find() else { return false }
        let result = try? await ProcessRunner.run(
            tool,
            arguments: ["--info", "--silent", installer.path]
        )
        return result?.succeeded ?? false
    }

    /// The game title embedded in the installer ("System Shock 2"), if any.
    static func gameTitle(of installer: URL) async -> String? {
        guard let tool = find() else { return nil }
        guard let result = try? await ProcessRunner.run(
            tool,
            arguments: ["--info", installer.path]
        ), result.succeeded else { return nil }

        // First line: Inspecting "System Shock 2" - setup data version 5.5.0
        for line in result.standardOutput.split(separator: "\n") {
            if let start = line.firstIndex(of: "\""),
               let end = line[line.index(after: start)...].firstIndex(of: "\"") {
                let title = String(line[line.index(after: start)..<end])
                if !title.isEmpty { return title }
            }
        }
        return nil
    }

    /// Extracts the installer into `destination`. GOG payloads put game
    /// files under app/; that subfolder's contents become `destination`.
    static func extract(_ installer: URL, to destination: URL) async throws {
        guard let tool = find() else { throw InnoExtractError.toolMissing }
        let fm = FileManager.default

        let staging = destination.deletingLastPathComponent()
            .appending(path: ".extracting-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let result = try await ProcessRunner.run(
            tool,
            arguments: ["--extract", "--silent", "--output-dir", staging.path, installer.path]
        )
        guard result.succeeded else {
            throw InnoExtractError.extractionFailed(
                result.standardError.isEmpty ? "innoextract exited with \(result.exitCode)" : result.standardError
            )
        }

        // GOG layout: game files in app/, redistributables (OpenAL,
        // VC++, DirectX) in tmp/. Other Inno installers may extract
        // straight to the root.
        let appDir = staging.appending(path: "app", directoryHint: .isDirectory)
        let payload = fm.fileExists(atPath: appDir.path) ? appDir : staging

        // Keep bundled redist installers — games often need them (the
        // real installer would have run these as post-install steps).
        let redistSources = ["tmp", "commonappdata", "__redist"]
            .map { staging.appending(path: $0, directoryHint: .isDirectory) }
        var redists: [URL] = []
        for dir in redistSources {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                continue
            }
            redists += files.filter { $0.pathExtension.lowercased() == "exe" }
        }
        if !redists.isEmpty {
            let redistDir = payload.appending(path: "_redist", directoryHint: .isDirectory)
            try fm.createDirectory(at: redistDir, withIntermediateDirectories: true)
            for redist in redists {
                try? fm.moveItem(at: redist, to: redistDir.appending(path: redist.lastPathComponent))
            }
        }

        try? fm.removeItem(at: destination)
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fm.moveItem(at: payload, to: destination)
    }

    /// Companion data parts of a multi-file GOG backup
    /// (setup_game-1.bin, setup_game-2.bin, …) sitting next to the exe.
    /// innoextract picks them up automatically — this is for showing the
    /// user what was detected, and warning when parts look missing.
    static func companionParts(of installer: URL) -> [URL] {
        let base = installer.deletingPathExtension().lastPathComponent.lowercased()
        let directory = installer.deletingLastPathComponent()
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return siblings
            .filter {
                $0.pathExtension.lowercased() == "bin"
                    && $0.deletingPathExtension().lastPathComponent.lowercased().hasPrefix(base)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Redist installers preserved from extraction, if any.
    static func bundledRedists(in gameDirectory: URL) -> [URL] {
        let redistDir = gameDirectory.appending(path: "_redist", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: redistDir, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "exe" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
