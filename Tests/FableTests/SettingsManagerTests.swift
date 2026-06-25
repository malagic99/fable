import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct SettingsManagerTests {
    private func tempConfig() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "SettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "config.json")
    }

    @Test
    func startsWithDefaultsWhenFileMissing() {
        let url = tempConfig()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let manager = SettingsManager(configURL: url)
        #expect(manager.settings == AppSettings())
        #expect(manager.settings.defaultWindowsVersion == .win10)
        #expect(!manager.settings.defaultDXMTEnabled)
    }

    @Test
    func changesPersistAcrossInstances() {
        let url = tempConfig()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let manager = SettingsManager(configURL: url)
        manager.settings.defaultWindowsVersion = .win7
        manager.settings.defaultDXMTEnabled = true
        manager.settings.defaultDXMTConfig.maxFrameRate = 60

        let reloaded = SettingsManager(configURL: url)
        #expect(reloaded.settings.defaultWindowsVersion == .win7)
        #expect(reloaded.settings.defaultDXMTEnabled)
        #expect(reloaded.settings.defaultDXMTConfig.maxFrameRate == 60)
    }

    @Test
    func advancedModeDefaultsOffAndPersists() {
        let url = tempConfig()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let manager = SettingsManager(configURL: url)
        #expect(!manager.settings.advancedMode)   // simple, click-and-play by default

        manager.settings.advancedMode = true
        let reloaded = SettingsManager(configURL: url)
        #expect(reloaded.settings.advancedMode)
    }

    @Test
    func legacyConfigWithoutAdvancedModeDecodesOff() throws {
        // A config.json written before the field existed must still load.
        let json = #"{"defaultWindowsVersion": "win10"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(!settings.advancedMode)
    }

    @Test
    func corruptedFileFallsBackToDefaults() throws {
        let url = tempConfig()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json]".utf8).write(to: url)

        let manager = SettingsManager(configURL: url)
        #expect(manager.settings == AppSettings())
    }

    @Test
    func unknownKeysAreToleratedOnDecode() throws {
        let json = """
        {"defaultWindowsVersion": "win11", "someFutureSetting": 42}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.defaultWindowsVersion == .win11)
        #expect(settings.defaultDXMTConfig == DXMTConfig())
    }
}
