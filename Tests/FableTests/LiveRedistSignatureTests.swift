import Foundation
import Testing
@testable import Fable

/// Opt-in, network: downloads every catalog dependency the way the app does
/// and runs its check. `FABLE_LIVE_REDIST=1`.
@Suite("Live redistributable checks", .enabled(if: ProcessInfo.processInfo.environment["FABLE_LIVE_REDIST"] != nil))
struct LiveRedistSignatureTests {
    @Test(arguments: DependencyCatalog.all.map(\.id))
    func theRealDownloadPassesItsCheck(_ id: String) async throws {
        let dependency = try #require(DependencyCatalog.all.first { $0.id == id })
        let folder = FileManager.default.temporaryDirectory.appending(path: "live-redist-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: dependency.url.lastPathComponent)
        try await DownloadManager.download(from: dependency.url, to: file)
        try dependency.check.verify(file)

        // And the same file with one byte changed doesn't.
        var data = try Data(contentsOf: file)
        data[data.count / 2] ^= 0x01
        try data.write(to: file)
        #expect(throws: (any Error).self) { try dependency.check.verify(file) }
        print("LIVE \(id): \(data.count) bytes verified; tampered copy refused")
    }
}
