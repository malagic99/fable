import CryptoKit
import Foundation

/// The native Steam bridge: a Windows game in a Sikarugir bottle talks to the
/// **Mac** Steam client you're logged into, with no Windows Steam involved.
///
/// The bridge is Valve's Proton `lsteamclient`, built on this Mac by
/// `scripts/steam-bridge/build.sh` (Steamworks SDK licence: Fable ships the
/// script, never the code or the built files). The build lands in
/// `Components/steam-bridge/<version>` with a `manifest.json` of SHA-256s.
///
/// A bridge launch puts that folder on `WINEDLLPATH` — so Sikarugir itself is
/// never modified and nothing changes for ordinary launches — and starts the
/// game through the bridge's `steam.exe` stand-in, staged into the bottle's
/// own folder (never a real Windows Steam install). Plan and spike evidence:
/// docs/NATIVE-STEAM-BRIDGE.md.
enum SteamBridge {
    /// Bumped whenever build.sh's output changes shape; Fable looks for this
    /// version's folder only.
    static let version = 1

    static var directory: URL {
        AppPaths.components
            .appending(path: "steam-bridge", directoryHint: .isDirectory)
            .appending(path: "\(version)", directoryHint: .isDirectory)
    }

    /// Files a usable build must contain (manifest-relative paths). steam_api
    /// asks for `steamclient64`/`steamclient`, and Wine finds a builtin's Unix
    /// half by the DLL's own name — hence the duplicate names.
    static let requiredFiles = [
        "x86_64-windows/lsteamclient.dll",
        "x86_64-windows/steamclient64.dll",
        "i386-windows/lsteamclient.dll",
        "i386-windows/steamclient.dll",
        "x86_64-unix/lsteamclient.so",
        "x86_64-unix/steamclient64.so",
        "x86_64-unix/steamclient.so",
        "steam.exe",
    ]

    struct Manifest: Decodable, Equatable {
        let bridgeVersion: Int
        let wine: String
        let protonCommit: String
        let files: [String: String]
    }

    enum Status: Equatable {
        /// No build for this version (run build.sh).
        case notBuilt
        case ready(Manifest)
        /// A build exists but doesn't match its own manifest — rebuild.
        case damaged(reason: String)
    }

    /// Checks a build folder against its manifest: version, every required
    /// file present, every listed file's SHA-256.
    static func status(at directory: URL = directory) -> Status {
        let manifestURL = directory.appending(path: "manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else { return .notBuilt }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return .damaged(reason: "manifest.json is unreadable")
        }
        guard manifest.bridgeVersion == version else {
            return .damaged(reason: "built for bridge version \(manifest.bridgeVersion), Fable needs \(version)")
        }
        if let missing = requiredFiles.first(where: { manifest.files[$0] == nil }) {
            return .damaged(reason: "manifest doesn't list \(missing)")
        }
        for (path, expected) in manifest.files.sorted(by: { $0.key < $1.key }) {
            let file = directory.appending(path: path)
            guard let actual = try? ChecksumVerifier.sha256(of: file) else {
                return .damaged(reason: "\(path) is missing")
            }
            guard actual == expected.lowercased() else {
                return .damaged(reason: "\(path) doesn't match its checksum")
            }
        }
        return .ready(manifest)
    }

    // MARK: Mac Steam

    /// Where the Mac Steam client keeps `steamclient.dylib`; the bridge's Unix
    /// half loads it from `STEAM_COMPAT_CLIENT_INSTALL_PATH`.
    static func macSteamClientDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS",
                       directoryHint: .isDirectory)
    }

    /// True when the native Steam client is among `commands` (a process
    /// list) — the bridge needs it running and logged in.
    static func isMacSteamRunning(commands: [String]) -> Bool {
        commands.contains { $0.contains("Steam.AppBundle/Steam/Contents/MacOS/steam_osx") }
    }

    // MARK: Launching

    /// drive_c-relative folder the stand-in and its steamclient DLLs live in.
    /// Its own folder, so a bottle that also has Windows Steam keeps working.
    static let prefixFolder = "Program Files (x86)/Fable Steam Bridge"

    /// Copies `steam.exe` and the two steamclient DLLs into the bottle (the
    /// registry points steam_api at them; Wine loads the builtins from
    /// `WINEDLLPATH` by name). Re-copies only what changed. Returns the
    /// stand-in's path.
    @discardableResult
    static func stage(driveC: URL, bridge: URL = directory) throws -> URL {
        let fm = FileManager.default
        let folder = driveC.appending(path: prefixFolder, directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let copies = [
            ("steam.exe", "steam.exe"),
            ("x86_64-windows/steamclient64.dll", "steamclient64.dll"),
            ("i386-windows/steamclient.dll", "steamclient.dll"),
        ]
        for (source, name) in copies {
            let from = bridge.appending(path: source)
            let to = folder.appending(path: name)
            if fm.fileExists(atPath: to.path),
               (try? ChecksumVerifier.sha256(of: to)) == (try? ChecksumVerifier.sha256(of: from)) {
                continue
            }
            try? fm.removeItem(at: to)
            try fm.copyItem(at: from, to: to)
        }
        return folder.appending(path: "steam.exe")
    }

    /// The game as the stand-in's first argument: a Windows path on C:.
    static func windowsPath(forExecutablePath path: String) -> String {
        "C:\\" + path.replacingOccurrences(of: "/", with: "\\")
    }

    /// Environment a bridge launch adds on top of the Sikarugir layer.
    static func launchEnvironment(appID: Int, bridge: URL, macSteamClient: URL) -> [String: String] {
        [
            "WINEDLLPATH": bridge.path,
            "STEAM_COMPAT_CLIENT_INSTALL_PATH": macSteamClient.path,
            "SteamAppId": String(appID),
            "SteamGameId": String(appID),
        ]
    }
}
