import Foundation
import Testing
@testable import Fable

@Suite struct InnoExtractorTests {
    @Test
    func nonInnoFileIsRejected() async {
        // Only meaningful when innoextract is installed.
        guard InnoExtractor.find() != nil else { return }
        #expect(await !InnoExtractor.isInnoSetup(URL(filePath: "/bin/ls")))
    }
}

/// End-to-end extraction against a real GOG installer. Runs only when
/// FABLE_GOG_INSTALLER points at one:
///
///   FABLE_GOG_INSTALLER=~/Downloads/setup_system_shock2_2.3.0.11.exe \
///     swift test --filter GOGExtractionIntegrationTests
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FABLE_GOG_INSTALLER"] != nil
    && InnoExtractor.find() != nil))
struct GOGExtractionIntegrationTests {
    @Test(.timeLimit(.minutes(10)))
    func extractsRealInstallerIntoBottle() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["FABLE_GOG_INSTALLER"])
        let installer = URL(filePath: (path as NSString).expandingTildeInPath)

        let dir = FileManager.default.temporaryDirectory
            .appending(path: "GOGIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = BottleManager(bottlesDirectory: dir)
        let bottle = try manager.createBottle(name: "GOG Test")
        try FileManager.default.createDirectory(
            at: manager.driveCDirectory(for: bottle),
            withIntermediateDirectories: true
        )

        #expect(await InnoExtractor.isInnoSetup(installer))

        let installed = try await GameInstaller().extractInnoInstaller(
            installer, bottle: bottle, bottleManager: manager
        )

        // The payload must contain at least one executable.
        let exes = try FileManager.default.contentsOfDirectory(
            at: installed, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "exe" }
        #expect(!exes.isEmpty, "no .exe found in \(installed.path)")
    }
}
