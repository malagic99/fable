import Foundation
import Testing
@testable import Fable

/// Full run-an-installer-in-Wine pass through the app's own code path,
/// including 32-bit routing via a discovered compatibility runtime and
/// the wineserver handoff back to the main Wine. Uses the machine's
/// real component store; opt-in:
///
///   FABLE_GOG_INSTALLER=~/Downloads/setup_somegame.exe \
///     swift test --filter InstallerCompatIntegrationTests
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FABLE_GOG_INSTALLER"] != nil
    && CompatibilityRuntime.discover() != nil))
struct InstallerCompatIntegrationTests {
    @Test(.timeLimit(.minutes(10)))
    func runsCrashingInstallerViaCompatRuntime() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["FABLE_GOG_INSTALLER"])
        let installer = URL(filePath: (path as NSString).expandingTildeInPath)
        try #require(PEInfo.architecture(of: installer) == .pe32)

        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appending(path: "CompatIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // Real components (Wine 11), scratch bottle.
        let componentManager = ComponentManager()
        let catalog = try VersionCatalog.loadBundled()
        let wineManager = WineManager(componentManager: componentManager, catalog: catalog)
        let bottleManager = BottleManager(bottlesDirectory: dir)
        let bottle = try bottleManager.createBottle(name: "Compat Test")
        try await wineManager.createPrefix(
            at: bottleManager.prefixDirectory(for: bottle),
            windowsVersion: .win10
        )

        let gameInstaller = GameInstaller()
        let exitCode = try await gameInstaller.runInstaller(
            installer,
            arguments: ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/DIR=C:\\compat-test"],
            bottle: bottle,
            bottleManager: bottleManager,
            wineManager: wineManager
        )
        #expect(exitCode == 0)
        #expect(gameInstaller.compatibilityRuntimeName != nil)

        let installed = bottleManager.driveCDirectory(for: bottle).appending(path: "compat-test")
        let exes = try fm.contentsOfDirectory(at: installed, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "exe" }
        #expect(!exes.isEmpty, "installer produced no exes in \(installed.path)")

        // Main Wine must be able to use the prefix again immediately.
        let check = try await ProcessRunner.run(
            try wineManager.wineBinary(),
            arguments: ["cmd", "/c", "echo PREFIX_OK"],
            environment: wineManager.environment(forPrefix: bottleManager.prefixDirectory(for: bottle))
        )
        #expect(check.succeeded)
        #expect(check.standardOutput.contains("PREFIX_OK"))
    }
}
