import Foundation
import Testing
@testable import Fable

/// The log-directory pruner that stops wine debug spam from eating the disk.
@Suite struct LogPrunerTests {
    private let fm = FileManager.default

    private func makeDir() throws -> URL {
        let dir = fm.temporaryDirectory.appending(path: "logs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeLog(_ name: String, bytes: Int, ageSeconds: TimeInterval, in dir: URL) throws -> URL {
        let url = dir.appending(path: name)
        try Data(count: bytes).write(to: url)
        let date = Date().addingTimeInterval(-ageSeconds)
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    @Test
    func deletesRunawayLogOverPerFileCap() throws {
        let dir = try makeDir()
        defer { try? fm.removeItem(at: dir) }
        let runaway = try writeLog("huge.log", bytes: 2_000, ageSeconds: 600, in: dir)
        let small = try writeLog("small.log", bytes: 100, ageSeconds: 600, in: dir)

        LogPruner.prune(directory: dir, maxFileBytes: 1_000, maxTotalBytes: 1_000_000)

        #expect(!fm.fileExists(atPath: runaway.path))   // over the per-file cap → gone
        #expect(fm.fileExists(atPath: small.path))       // under it → kept
    }

    @Test
    func trimsTotalToBudgetOldestFirst() throws {
        let dir = try makeDir()
        defer { try? fm.removeItem(at: dir) }
        let oldest = try writeLog("a.log", bytes: 400, ageSeconds: 9000, in: dir)
        let middle = try writeLog("b.log", bytes: 400, ageSeconds: 6000, in: dir)
        let newest = try writeLog("c.log", bytes: 400, ageSeconds: 3000, in: dir)

        // Budget 1000, total 1200 → must drop the oldest (400) to fit.
        LogPruner.prune(directory: dir, maxFileBytes: 1_000_000, maxTotalBytes: 1_000)

        #expect(!fm.fileExists(atPath: oldest.path))
        #expect(fm.fileExists(atPath: middle.path))
        #expect(fm.fileExists(atPath: newest.path))
    }

    @Test
    func neverTouchesActivelyWrittenLogs() throws {
        let dir = try makeDir()
        defer { try? fm.removeItem(at: dir) }
        // A huge, brand-new log (a game writing right now) must be left alone.
        let active = try writeLog("active.log", bytes: 5_000, ageSeconds: 10, in: dir)

        LogPruner.prune(directory: dir, maxFileBytes: 1_000, maxTotalBytes: 1_000, activeWindow: 300)

        #expect(fm.fileExists(atPath: active.path))
    }
}
