import Foundation
import Testing
@testable import Fable

@Suite struct DownloadManagerTests {
    @Test
    func downloadsLocalFileWithProgress() async throws {
        let fm = FileManager.default
        let source = fm.temporaryDirectory.appending(path: "dl-src-\(UUID().uuidString).bin")
        let destination = fm.temporaryDirectory.appending(path: "dl-dst-\(UUID().uuidString).bin")
        defer {
            try? fm.removeItem(at: source)
            try? fm.removeItem(at: destination)
        }

        // 300 KB so multiple chunks are written.
        let payload = Data((0..<300_000).map { UInt8($0 % 251) })
        try payload.write(to: source)

        let observed = ProgressCollector()
        try await DownloadManager.download(from: source, to: destination) { progress in
            observed.record(progress)
        }

        #expect(try Data(contentsOf: destination) == payload)
        let final = observed.last
        #expect(final?.bytesReceived == Int64(payload.count))
    }
}

/// Thread-safe sink for progress callbacks emitted off the test's task.
final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [DownloadProgress] = []

    func record(_ value: DownloadProgress) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }

    var last: DownloadProgress? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }
}
