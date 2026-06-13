import Foundation
import Testing
@testable import Fable

@Suite struct BottleDiskUsageTests {
    private func makePrefix() throws -> (URL, () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "DiskUsageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )
        return (root, { try? FileManager.default.removeItem(at: root) })
    }

    private func writeFile(at url: URL, byteCount: Int) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0, count: byteCount).write(to: url)
    }

    @Test
    func sizeSumsFilesRecursively() throws {
        let (prefix, cleanup) = try makePrefix()
        defer { cleanup() }

        try writeFile(at: prefix.appending(path: "drive_c/Program Files/Game/game.exe"), byteCount: 1024)
        try writeFile(at: prefix.appending(path: "drive_c/windows/system32/dxgi.dll"), byteCount: 2048)

        let size = try BottleDiskUsage.size(of: prefix)
        // Allocated size rounds up to filesystem block size, so don't
        // assert equality — assert it's at least the byte count.
        #expect(size >= 1024 + 2048)
    }

    @Test
    func sizeReturnsZeroForMissingDirectory() throws {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "absent-\(UUID().uuidString)", directoryHint: .isDirectory)
        #expect(try BottleDiskUsage.size(of: missing) == 0)
    }

    @Test
    func tempPathsCoverWindowsAndAllUsers() throws {
        let (prefix, cleanup) = try makePrefix()
        defer { cleanup() }

        let users = prefix.appending(path: "drive_c/users")
        for user in ["fable", "Public"] {
            try FileManager.default.createDirectory(
                at: users.appending(path: user), withIntermediateDirectories: true
            )
        }

        let paths = BottleDiskUsage.tempPaths(in: prefix).map(\.path)
        #expect(paths.contains { $0.hasSuffix("drive_c/windows/Temp") })
        #expect(paths.contains { $0.hasSuffix("drive_c/users/fable/Temp") })
        #expect(paths.contains { $0.hasSuffix("drive_c/users/Public/AppData/Local/Temp") })
    }

    @Test
    func cleanTempFilesRemovesContentsAndReportsBytesFreed() throws {
        let (prefix, cleanup) = try makePrefix()
        defer { cleanup() }

        let windowsTemp = prefix.appending(path: "drive_c/windows/Temp")
        try FileManager.default.createDirectory(
            at: windowsTemp, withIntermediateDirectories: true
        )
        try writeFile(at: windowsTemp.appending(path: "scratch.dat"), byteCount: 4096)

        let usersTemp = prefix.appending(path: "drive_c/users/fable/Temp")
        try FileManager.default.createDirectory(
            at: usersTemp, withIntermediateDirectories: true
        )
        try writeFile(at: usersTemp.appending(path: "log.txt"), byteCount: 256)

        let freed = try BottleDiskUsage.cleanTempFiles(in: prefix)
        #expect(freed > 0)

        // Directories should still exist (Wine needs them); contents gone.
        #expect(FileManager.default.fileExists(atPath: windowsTemp.path))
        #expect(!FileManager.default.fileExists(
            atPath: windowsTemp.appending(path: "scratch.dat").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: usersTemp.appending(path: "log.txt").path
        ))
    }

    @Test
    func cleanTempFilesIsNoOpOnEmptyPrefix() throws {
        let (prefix, cleanup) = try makePrefix()
        defer { cleanup() }
        #expect(try BottleDiskUsage.cleanTempFiles(in: prefix) == 0)
    }

    @Test
    func formattedRendersHumanReadable() {
        // 0 bytes localizes as "Zero KB" / "Zero bytes" / "0 byte" depending
        // on locale — assert only that the unit suffix is present.
        let zero = BottleDiskUsage.formatted(0).lowercased()
        #expect(zero.contains("b") || zero.contains("0"))
        let oneMegabyte = BottleDiskUsage.formatted(1_048_576)
        #expect(oneMegabyte.contains("MB") || oneMegabyte.contains("M"))
    }
}
