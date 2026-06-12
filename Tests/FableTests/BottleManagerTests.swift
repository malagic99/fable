import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct BottleManagerTests {
    private func makeTempManager() throws -> (BottleManager, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "FableTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (BottleManager(bottlesDirectory: dir), dir)
    }

    @Test
    func createBottleAppearsInListAndOnDisk() throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bottle = try manager.createBottle(name: "Steam", windowsVersion: .win11)

        #expect(manager.bottles.count == 1)
        #expect(manager.bottles.first?.name == "Steam")
        #expect(bottle.windowsVersion == .win11)

        let metadata = manager.directory(for: bottle).appending(path: "bottle.json")
        #expect(FileManager.default.fileExists(atPath: metadata.path))
    }

    @Test
    func createRejectsEmptyAndDuplicateNames() throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: BottleError.emptyName) {
            try manager.createBottle(name: "   ")
        }

        try manager.createBottle(name: "Games")
        #expect(throws: BottleError.duplicateName("games")) {
            try manager.createBottle(name: "games")
        }
        #expect(manager.bottles.count == 1)
    }

    @Test
    func renameUpdatesListAndDisk() throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bottle = try manager.createBottle(name: "Old Name")
        try manager.renameBottle(bottle.id, to: "New Name")

        #expect(manager.bottle(with: bottle.id)?.name == "New Name")

        // A fresh manager reading the same directory sees the rename.
        let reloaded = BottleManager(bottlesDirectory: dir)
        #expect(reloaded.bottle(with: bottle.id)?.name == "New Name")
    }

    @Test
    func renameRejectsNameOfOtherBottle() throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(at: dir) }

        try manager.createBottle(name: "First")
        let second = try manager.createBottle(name: "Second")

        #expect(throws: BottleError.duplicateName("First")) {
            try manager.renameBottle(second.id, to: "First")
        }
        // Renaming to its own name (case change) is allowed.
        try manager.renameBottle(second.id, to: "SECOND")
        #expect(manager.bottle(with: second.id)?.name == "SECOND")
    }

    @Test
    func deleteRemovesListEntryAndDirectory() throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bottle = try manager.createBottle(name: "Doomed")
        let bottleDir = manager.directory(for: bottle)

        try manager.deleteBottle(bottle.id)

        #expect(manager.bottles.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: bottleDir.path))
        #expect(throws: BottleError.notFound) {
            try manager.deleteBottle(bottle.id)
        }
    }

    @Test
    func loadBottlesRoundTripsAcrossInstances() throws {
        let (manager, dir) = try makeTempManager()
        defer { try? FileManager.default.removeItem(at: dir) }

        try manager.createBottle(name: "A", windowsVersion: .win7)
        try manager.createBottle(name: "B")

        let reloaded = BottleManager(bottlesDirectory: dir)
        #expect(reloaded.bottles.map(\.name).sorted() == ["A", "B"])
        #expect(reloaded.bottles.first { $0.name == "A" }?.windowsVersion == .win7)
    }
}
