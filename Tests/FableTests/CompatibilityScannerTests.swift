import Foundation
import Testing
@testable import Fable

@Suite struct CompatibilityScannerTests {
    /// Build a fixture install directory with the given relative file
    /// paths created as empty placeholder files. The caller passes a
    /// `subdir` to influence the install path (e.g. "voices38").
    private func makeFixture(
        subdir: String = "Game",
        files: [String]
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let gameDir = root.appending(path: subdir, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        for relative in files {
            let url = gameDir.appending(path: relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: url)
        }
        return gameDir
    }

    @Test
    func emptyDirectoryProducesNoFindings() throws {
        let dir = try makeFixture(files: [])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        #expect(CompatibilityScanner.scan(gameDirectory: dir).isEmpty)
    }

    @Test
    func nonexistentDirectoryProducesNoFindings() {
        let dir = URL(filePath: "/tmp/absolutely-does-not-exist-\(UUID().uuidString)")
        #expect(CompatibilityScanner.scan(gameDirectory: dir).isEmpty)
    }

    @Test
    func streamlinePluginsTriggerCaveat() throws {
        let dir = try makeFixture(files: [
            "sl.interposer.dll",
            "sl.dlss.dll",
            "sl.reflex.dll",
        ])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let findings = CompatibilityScanner.scan(gameDirectory: dir)
        let streamline = try #require(findings.first { $0.id == "streamline" })
        #expect(streamline.severity == .caveat)
        #expect(streamline.suggestion.contains("Wine built-in") ||
                streamline.suggestion.contains("Off"))
    }

    @Test
    func directStorageTriggersCaveat() throws {
        let dir = try makeFixture(files: ["dstorage.dll", "dstoragecore.dll"])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let findings = CompatibilityScanner.scan(gameDirectory: dir)
        #expect(findings.contains { $0.id == "directstorage" && $0.severity == .caveat })
    }

    @Test
    func easyAntiCheatTriggersKnownBlocker() throws {
        let dir = try makeFixture(files: ["EasyAntiCheat/EasyAntiCheat_x64.dll"])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let findings = CompatibilityScanner.scan(gameDirectory: dir)
        let eac = try #require(findings.first { $0.id.hasPrefix("anticheat-") })
        #expect(eac.severity == .knownBlocker)
    }

    @Test
    func battleEyeTriggersKnownBlocker() throws {
        let dir = try makeFixture(files: ["BattlEye/BEService.exe"])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let findings = CompatibilityScanner.scan(gameDirectory: dir)
        #expect(findings.contains { $0.id.contains("battleye") && $0.severity == .knownBlocker })
    }

    @Test
    func vanguardTriggersKnownBlocker() throws {
        let dir = try makeFixture(files: ["vgc.exe"])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let findings = CompatibilityScanner.scan(gameDirectory: dir)
        #expect(findings.contains { $0.id.contains("vanguard") && $0.severity == .knownBlocker })
    }

    @Test
    func goldbergWithoutInterfacesGetsCaveatPlusInfo() throws {
        let dir = try makeFixture(files: [
            "steam_settings/configs.app.ini",
            "steam_settings/configs.user.ini",
        ])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let findings = CompatibilityScanner.scan(gameDirectory: dir)
        #expect(findings.contains { $0.id == "goldberg-emu" && $0.severity == .info })
        let caveat = try #require(findings.first { $0.id == "goldberg-no-interfaces" })
        #expect(caveat.severity == .caveat)
        #expect(caveat.suggestion.contains("steam_interfaces.txt"))
    }

    @Test
    func goldbergWithInterfacesSkipsTheCaveat() throws {
        let dir = try makeFixture(files: [
            "steam_settings/configs.app.ini",
            "steam_settings/steam_interfaces.txt",
        ])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let findings = CompatibilityScanner.scan(gameDirectory: dir)
        #expect(findings.contains { $0.id == "goldberg-emu" })
        #expect(!findings.contains { $0.id == "goldberg-no-interfaces" })
    }

    @Test
    func repackPathTriggersInfo() throws {
        let dir = try makeFixture(subdir: "voices38/MyGame", files: ["game.exe"])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let findings = CompatibilityScanner.scan(gameDirectory: dir)
        #expect(findings.contains { $0.id == "repack-install" && $0.severity == .info })
    }

    @Test
    func cleanInstallProducesNoFindings() throws {
        let dir = try makeFixture(files: [
            "Game.exe",
            "Engine.dll",
            "Resources/textures.pak",
        ])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        #expect(CompatibilityScanner.scan(gameDirectory: dir).isEmpty)
    }

    @Test
    func compositeRealisticInstallShowsMultipleFindings() throws {
        // Mirrors the actual 007 First Light install — combination of
        // signals we saw in production. Each rule fires once.
        let dir = try makeFixture(subdir: "voices38/007FirstLight/Retail", files: [
            "sl.interposer.dll",
            "sl.dlss.dll",
            "sl.reflex.dll",
            "dstorage.dll",
            "dstoragecore.dll",
            "steam_settings/configs.app.ini",
            "steam_settings/configs.user.ini",
        ])
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let findings = CompatibilityScanner.scan(gameDirectory: dir)
        let ids = Set(findings.map(\.id))
        #expect(ids.contains("streamline"))
        #expect(ids.contains("directstorage"))
        #expect(ids.contains("goldberg-emu"))
        #expect(ids.contains("goldberg-no-interfaces"))
        #expect(ids.contains("repack-install"))
    }
}
