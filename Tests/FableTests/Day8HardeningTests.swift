import Foundation
import Testing
@testable import Fable

@Suite struct LogNameTests {
    @Test
    func sanitizesPathSeparatorsAndColons() {
        let name = GameInstaller.logName("My/Bottle", "Game: Redux\\2")
        #expect(!name.contains("/"))
        #expect(!name.contains("\\"))
        #expect(!name.contains(":"))
        #expect(name.hasSuffix(".log"))
        #expect(name.contains("My-Bottle"))
        #expect(name.contains("Game- Redux-2"))
    }
}

@MainActor
@Suite struct BrokenBottleRecoveryTests {
    @Test
    func orphanedProvisioningBottleBecomesBrokenOnLoad() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "BrokenTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Simulate an app quit mid-provision: bottle persisted as
        // provisioning, then a fresh manager loads the directory.
        let first = BottleManager(bottlesDirectory: dir)
        let bottle = try first.createBottle(name: "Interrupted")
        #expect(bottle.status == .provisioning)

        let reloaded = BottleManager(bottlesDirectory: dir)
        #expect(reloaded.bottle(with: bottle.id)?.status == .broken)

        // And the migration is persisted, not just in memory.
        let again = BottleManager(bottlesDirectory: dir)
        #expect(again.bottle(with: bottle.id)?.status == .broken)

        // Repair path: marking ready persists.
        try again.setStatus(.ready, for: bottle.id)
        let final = BottleManager(bottlesDirectory: dir)
        #expect(final.bottle(with: bottle.id)?.status == .ready)
    }
}
