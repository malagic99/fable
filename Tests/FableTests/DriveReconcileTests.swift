import Foundation
import Testing
@testable import Fable

/// The DOS-drive self-heal that keeps Wine able to resolve exes outside C:
/// (the "can't find the Z: drive" symptom).
@MainActor
@Suite struct DriveReconcileTests {
    private let fm = FileManager.default

    private func makeManager() -> WineManager {
        WineManager(componentManager: ComponentManager(), catalog: VersionCatalog(components: [:]))
    }

    private func tempPrefix() throws -> URL {
        let url = fm.temporaryDirectory.appending(path: "prefix-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func createsMissingCAndZDrives() throws {
        let prefix = try tempPrefix()
        defer { try? fm.removeItem(at: prefix) }

        makeManager().reconcileDrives(at: prefix)

        let dosdevices = prefix.appending(path: "dosdevices")
        #expect(try fm.destinationOfSymbolicLink(atPath: dosdevices.appending(path: "c:").path) == "../drive_c")
        #expect(try fm.destinationOfSymbolicLink(atPath: dosdevices.appending(path: "z:").path) == "/")
    }

    @Test
    func repairsAWrongZTarget() throws {
        let prefix = try tempPrefix()
        defer { try? fm.removeItem(at: prefix) }
        let dosdevices = prefix.appending(path: "dosdevices")
        try fm.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        // A bogus z: pointing somewhere wrong.
        try fm.createSymbolicLink(atPath: dosdevices.appending(path: "z:").path, withDestinationPath: "/nonsense")

        makeManager().reconcileDrives(at: prefix)
        #expect(try fm.destinationOfSymbolicLink(atPath: dosdevices.appending(path: "z:").path) == "/")
    }

    @Test
    func leavesACorrectDriveAloneAndNeverDeletesARealDir() throws {
        let prefix = try tempPrefix()
        defer { try? fm.removeItem(at: prefix) }
        let dosdevices = prefix.appending(path: "dosdevices")
        try fm.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        // A real directory sitting where a drive link would be — must be preserved.
        let realDir = dosdevices.appending(path: "d:")
        try fm.createDirectory(at: realDir, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: realDir.appending(path: "important.txt"))

        makeManager().reconcileDrives(at: prefix)

        #expect(fm.fileExists(atPath: realDir.appending(path: "important.txt").path))
        // And the standard pair still gets created alongside it.
        #expect((try? fm.destinationOfSymbolicLink(atPath: dosdevices.appending(path: "z:").path)) == "/")
    }
}
