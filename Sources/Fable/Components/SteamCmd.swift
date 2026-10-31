import Foundation

/// What Fable needs from a Steam app's public info to add it as a native
/// Steam bridge game.
struct SteamAppInfo: Equatable, Sendable {
    let appID: Int
    let name: String
    /// The Windows launch entry: executable relative to the install folder
    /// (always `/`-separated here) and its default arguments. nil when the
    /// app has no Windows build.
    let windowsExecutable: String?
    let windowsArguments: String

    /// An app id from what someone pastes: the number itself, or a Steam
    /// store / SteamDB link (`…/app/1168880/MOLEKSYNTEZ/`).
    static func appID(fromInput input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed), id > 0 { return id }
        guard let range = trimmed.range(of: #"/app/(\d+)"#, options: .regularExpression) else { return nil }
        return Int(trimmed[range].dropFirst("/app/".count))
    }

    /// Parses `steamcmd +app_info_print <appID>` output: noise lines, then a
    /// `"<appID>" { … }` KeyValues block.
    static func parse(appID: Int, steamcmdOutput output: String) -> SteamAppInfo? {
        guard let start = output.range(of: "\"\(appID)\"") else { return nil }
        // Bind the parsed pair whole, as SteamInstallCommitter does: Swift 6.2
        // (CI) reports a circular reference when this optional tuple of the
        // recursive VDFValue is destructured in a `guard let`.
        guard let parsed = SteamKeyValues.parse(String(output[start.lowerBound...])),
              parsed.key == String(appID),
              let name = parsed.value["common"]?.string("name")
        else { return nil }
        let root: VDFValue = parsed.value

        var executable: String?
        var arguments = ""
        if let launch = root["config"]?["launch"], case .object(let entries) = launch {
            // Launch entries are keyed "0", "1", … in order; take the first
            // Windows one (no oslist means every platform).
            for pair in entries {
                let entry: VDFValue = pair.value
                guard let exe = entry.string("executable"), exe.lowercased().hasSuffix(".exe") else { continue }
                let oslist = entry["config"]?.string("oslist") ?? ""
                guard oslist.isEmpty || oslist.split(separator: ",").contains("windows") else { continue }
                executable = exe.replacingOccurrences(of: "\\", with: "/")
                arguments = entry.string("arguments") ?? ""
                break
            }
        }
        return SteamAppInfo(appID: appID, name: name, windowsExecutable: executable, windowsArguments: arguments)
    }
}

enum SteamCmdError: LocalizedError {
    case lookupFailed(Int, String)
    case noWindowsBuild(String)
    case notDownloaded(String)

    var errorDescription: String? {
        switch self {
        case .notDownloaded(let name):
            "“\(name)” isn't downloaded into that bottle yet — its Windows executable is missing."
        case .lookupFailed(let appID, let detail):
            "Couldn't look up Steam app \(appID)\(detail.isEmpty ? "" : ": \(detail)")."
        case .noWindowsBuild(let name):
            "“\(name)” has no Windows build on Steam, so there's nothing for the bridge to run."
        }
    }
}

/// Valve's `steamcmd`, which downloads a game's **Windows** build for the
/// native Steam bridge. Lives in `Components/steamcmd` and updates itself on
/// first run. Fable never sees your Steam password: downloads run in
/// Terminal, where you sign in to steamcmd yourself.
enum SteamCmd {
    static let tarballURL = URL(string: "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz")!
    /// Pinned like every other download (an unverified one is refused).
    static let tarballSHA256 = "8ecc17c8988e5acadcc78e631c48490f76150f2dfaa6cf8d7b4b67b097bd753b"

    static var directory: URL {
        AppPaths.components.appending(path: "steamcmd", directoryHint: .isDirectory)
    }
    static var script: URL { directory.appending(path: "steamcmd.sh") }
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: script.path) }

    /// Downloads, verifies and unpacks steamcmd (no-op when present).
    static func installIfNeeded() async throws {
        guard !isInstalled else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: AppPaths.downloads, withIntermediateDirectories: true)
        let tarball = AppPaths.downloads.appending(path: "steamcmd_osx.tar.gz")
        defer { try? fm.removeItem(at: tarball) }
        try await DownloadManager.download(from: tarballURL, to: tarball)
        try ChecksumVerifier.verify(tarball, sha256: tarballSHA256)

        let staging = AppPaths.downloads.appending(path: "steamcmd-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"), arguments: ["-xzf", tarball.path, "-C", staging.path])
        guard result.succeeded else { throw ComponentError.extractionFailed(result.standardError) }
        try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: directory)
        try fm.moveItem(at: staging, to: directory)
    }

    /// Public app info, fetched anonymously — no account needed.
    static func appInfo(_ appID: Int) async throws -> SteamAppInfo {
        try await installIfNeeded()
        let result = try await ProcessRunner.run(
            script,
            arguments: ["+login", "anonymous", "+app_info_update", "1",
                        "+app_info_print", String(appID), "+quit"],
            currentDirectory: directory
        )
        guard let info = SteamAppInfo.parse(appID: appID, steamcmdOutput: result.standardOutput) else {
            throw SteamCmdError.lookupFailed(appID, result.succeeded ? "" : "steamcmd exited with \(result.exitCode)")
        }
        guard info.windowsExecutable != nil else { throw SteamCmdError.noWindowsBuild(info.name) }
        return info
    }

    // MARK: Download (in Terminal)

    /// Where a bridge game's files go inside a bottle (drive_c-relative).
    static func installFolder(appID: Int) -> String { "SteamBridge/\(appID)" }

    /// A `.command` script Terminal runs: asks for the Steam account name,
    /// lets steamcmd ask for the password and Steam Guard code itself,
    /// downloads the Windows build, and writes steamcmd's exit code to
    /// `marker` so Fable knows when it's done.
    static func downloadCommand(info: SteamAppInfo, installDir: URL, marker: URL, steamcmd: URL = script) -> String {
        func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let title = info.name.filter { !$0.isNewline }
        return """
        #!/bin/sh
        # Fable: download the Windows build of \(title) (Steam app \(info.appID))
        # for the native Steam bridge. steamcmd asks for your password and
        # Steam Guard code itself; Fable never sees them.
        rm -f \(quote(marker.path))
        echo 'Downloading the Windows build of '\(quote(title))' for Fable.'
        printf 'Steam account name: '
        read -r STEAM_USER
        \(quote(steamcmd.path)) \\
            +@sSteamCmdForcePlatformType windows \\
            +force_install_dir \(quote(installDir.path)) \\
            +login "$STEAM_USER" \\
            +app_update \(info.appID) validate \\
            +quit
        code=$?
        echo "$code" > \(quote(marker.path))
        if [ "$code" -eq 0 ]; then echo 'Done. Go back to Fable; you can close this window.'
        else echo "steamcmd failed (exit $code). Go back to Fable to try again."; fi

        """
    }
}
