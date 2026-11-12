import Foundation
import Testing
@testable import Fable

@Suite("Rosetta check")
struct RosettaCheckTests {
    @Test
    func installedMeansTheRuntimeLibraryIsThere() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "fable-rosetta-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appending(path: "libRosettaRuntime")
        #expect(!Rosetta.isInstalled(marker: marker))
        try Data().write(to: marker)
        #expect(Rosetta.isInstalled(marker: marker))
    }

    @Test
    func theInstallerIsApplesAndNeedsNoTerminal() {
        #expect(Rosetta.installCommand.first == "/usr/sbin/softwareupdate")
        #expect(Rosetta.installCommand.contains("--install-rosetta"))
        // Without this flag the installer waits for a typed "A" that nobody
        // can give it; with it, the interface must say the licence is accepted.
        #expect(Rosetta.installCommand.contains("--agree-to-license"))
        #expect(!L10n.string("rosetta.setup.license").hasPrefix("rosetta."))
    }

    @Test
    func aFailedInstallReportsTheInstallersLastLine() {
        #expect(Rosetta.failureDetail(
            standardOutput: "Checking…\n", standardError: "Install of Rosetta 2 failed: no network\n\n")
            == "Install of Rosetta 2 failed: no network")
        #expect(Rosetta.failureDetail(standardOutput: "Checking…\nNothing to install\n", standardError: "")
            == "Nothing to install")
        #expect(Rosetta.failureDetail(
            standardOutput: "", standardError: "first\nInstall failed with Error: no network\n")
            == "Install failed with Error: no network")
        #expect(!Rosetta.failureDetail(standardOutput: "", standardError: "").isEmpty)
    }

    @Test
    func aLaunchWithoutRosettaNamesTheFix() {
        let message = GameLaunchError.rosettaMissing.errorDescription ?? ""
        #expect(message.contains("Rosetta"))
        #expect(!message.contains("softwareupdate"))
    }
}

@Suite("Build info")
struct BuildInfoTests {
    private func info(commit: String?, dirty: Bool?) -> BuildInfo {
        BuildInfo(version: "1.2.0", build: "40", commit: commit, dirty: dirty, builtAt: nil)
    }

    @Test
    func theVersionLabelCarriesTheCommit() {
        let clean = info(commit: "ee0adf6c0ffee0000000000000000000000000000", dirty: false)
        #expect(BuildInfo.versionLabel("1.2.0", info: clean) == "1.2.0 (ee0adf6)")
        // A build with local changes must not pass for the commit it names.
        let dirty = info(commit: "ee0adf6c0ffee0000000000000000000000000000", dirty: true)
        #expect(BuildInfo.versionLabel("1.2.0", info: dirty) == "1.2.0 (ee0adf6+)")
    }

    @Test
    func noRecordMeansJustTheVersion() {
        #expect(BuildInfo.versionLabel("1.2.0", info: nil) == "1.2.0")
        #expect(BuildInfo.versionLabel("1.2.0", info: info(commit: nil, dirty: nil)) == "1.2.0")
    }

    @Test
    func theRecordTheBuildScriptWritesDecodes() throws {
        // Extra fields (bundledTools, swift…) and nulls are tolerated.
        let json = """
        {"schemaVersion": 1, "version": "1.2.0", "build": "40",
         "commit": "ee0adf6c0ffee0000000000000000000000000000", "dirty": null,
         "builtAt": "2026-11-12T20:00:00Z", "swift": "Apple Swift 6",
         "bundledTools": {"cabextract": "abc"}, "componentCatalogSHA256": null}
        """
        let decoded = try #require(BuildInfo.load(from: Data(json.utf8)))
        #expect(decoded.shortCommit == "ee0adf6")
        #expect(BuildInfo.load(from: Data("not json".utf8)) == nil)
    }
}
