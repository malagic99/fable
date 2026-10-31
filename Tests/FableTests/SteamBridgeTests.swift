import Foundation
import Testing
@testable import Fable

/// The native Steam bridge's install check, prefix staging and launch inputs.
@Suite struct SteamBridgeTests {
    private let fm = FileManager.default

    /// A fake bridge build: every required file with distinct content, plus a
    /// manifest of their real SHA-256s (what build.sh writes).
    private func makeBridge(version: Int = SteamBridge.version) throws -> URL {
        let dir = fm.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString)", directoryHint: .isDirectory)
        var files: [String: String] = [:]
        for path in SteamBridge.requiredFiles {
            let url = dir.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("contents of \(path)".utf8).write(to: url)
            files[path] = try ChecksumVerifier.sha256(of: url)
        }
        let manifest: [String: Any] = [
            "bridgeVersion": version, "wine": "10.0",
            "protonCommit": "e91ca2be0df2cef4c230cbbc0b86604d73a0bbf6", "files": files,
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: dir.appending(path: "manifest.json"))
        return dir
    }

    @Test
    func aCompleteBuildIsReady() throws {
        let dir = try makeBridge()
        defer { try? fm.removeItem(at: dir) }
        guard case .ready(let manifest) = SteamBridge.status(at: dir) else {
            Issue.record("expected .ready, got \(SteamBridge.status(at: dir))")
            return
        }
        #expect(manifest.wine == "10.0")
        #expect(manifest.files.count == SteamBridge.requiredFiles.count)
    }

    @Test
    func noManifestMeansNotBuilt() {
        let empty = fm.temporaryDirectory.appending(path: "bridge-none-\(UUID().uuidString)")
        #expect(SteamBridge.status(at: empty) == .notBuilt)
    }

    @Test
    func aChangedOrMissingFileIsDamaged() throws {
        let dir = try makeBridge()
        defer { try? fm.removeItem(at: dir) }
        try Data("tampered".utf8).write(to: dir.appending(path: "x86_64-unix/steamclient64.so"))
        #expect(SteamBridge.status(at: dir) == .damaged(reason: "x86_64-unix/steamclient64.so doesn't match its checksum"))

        try fm.removeItem(at: dir.appending(path: "steam.exe"))
        guard case .damaged = SteamBridge.status(at: dir) else {
            Issue.record("a missing file must not read as ready")
            return
        }
    }

    @Test
    func aBuildForAnotherVersionIsDamaged() throws {
        let dir = try makeBridge(version: SteamBridge.version + 1)
        defer { try? fm.removeItem(at: dir) }
        guard case .damaged(let reason) = SteamBridge.status(at: dir) else {
            Issue.record("expected .damaged")
            return
        }
        #expect(reason.contains("bridge version"))
    }

    @Test
    func stagingCopiesTheStandInAndClientsIntoItsOwnFolder() throws {
        let bridge = try makeBridge()
        let driveC = fm.temporaryDirectory.appending(path: "drivec-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: bridge); try? fm.removeItem(at: driveC) }
        // A real Windows Steam in the same bottle must not be touched.
        let windowsSteam = driveC.appending(path: "Program Files (x86)/Steam/steam.exe")
        try fm.createDirectory(at: windowsSteam.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("valve steam".utf8).write(to: windowsSteam)

        let shim = try SteamBridge.stage(driveC: driveC, bridge: bridge)

        #expect(shim == driveC.appending(path: "\(SteamBridge.prefixFolder)/steam.exe"))
        let folder = shim.deletingLastPathComponent()
        #expect(try String(contentsOf: folder.appending(path: "steamclient64.dll"), encoding: .utf8)
                == "contents of x86_64-windows/steamclient64.dll")
        #expect(try String(contentsOf: folder.appending(path: "steamclient.dll"), encoding: .utf8)
                == "contents of i386-windows/steamclient.dll")
        #expect(try String(contentsOf: windowsSteam, encoding: .utf8) == "valve steam")

        // Staging again after a rebuild refreshes the copy.
        try Data("rebuilt".utf8).write(to: bridge.appending(path: "steam.exe"))
        try SteamBridge.stage(driveC: driveC, bridge: bridge)
        #expect(try String(contentsOf: shim, encoding: .utf8) == "rebuilt")
    }

    @Test
    func launchInputs() {
        #expect(SteamBridge.windowsPath(forExecutablePath: "Games/MOLEK-SYNTEZ/MOLEK-SYNTEZ.exe")
                == #"C:\Games\MOLEK-SYNTEZ\MOLEK-SYNTEZ.exe"#)
        let env = SteamBridge.launchEnvironment(
            appID: 1168880, bridge: URL(filePath: "/b"), macSteamClient: URL(filePath: "/s"))
        #expect(env == ["WINEDLLPATH": "/b", "STEAM_COMPAT_CLIENT_INSTALL_PATH": "/s",
                        "SteamAppId": "1168880", "SteamGameId": "1168880"])
        #expect(SteamBridge.isMacSteamRunning(commands: [
            "/usr/sbin/cfprefsd agent",
            "/Users/x/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steam_osx",
        ]))
        #expect(!SteamBridge.isMacSteamRunning(commands: [
            "/Users/x/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/ipcserver",
        ]))
    }
}
