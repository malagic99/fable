import Foundation
import Testing
@testable import Fable

/// Opt-in: a real donor export of a real bottle, written to a scratch file and
/// read back. `FABLE_LIVE_DONOR_BOTTLE=<bottle id> FABLE_LIVE_DONOR_OUT=<file>`.
@Suite("Live donor export", .enabled(if: ProcessInfo.processInfo.environment["FABLE_LIVE_DONOR_BOTTLE"] != nil))
struct LiveDonorExportTests {
    @Test @MainActor
    func exportsARealBottle() async throws {
        let env = ProcessInfo.processInfo.environment
        let manager = BottleManager()
        let id = try #require(UUID(uuidString: env["FABLE_LIVE_DONOR_BOTTLE"]!))
        let bottle = try #require(manager.bottle(with: id))
        let out = URL(filePath: env["FABLE_LIVE_DONOR_OUT"]!)
        let started = Date()
        try await BottleArchive.pack(
            BottleArchive.donorBottle(bottle), bottleManager: manager,
            catalog: try VersionCatalog.loadBundled(), to: out,
            excluding: BottleArchive.donorExclusions(for: bottle),
            sanitizeRegistry: env["FABLE_LIVE_DONOR_NO_SANITIZE"] == nil)
        print("LIVE packed in \(Int(Date().timeIntervalSince(started)))s")
        print("LIVE excluded game folders: \(DonorExport.gameFolders(of: bottle))")
        // What an importing friend's Fable does first: re-checksum.
        // As a friend with another Mac user name would.
        let unpacked = try await BottleArchive.unpack(out, importerUserName: "livefriend")
        defer { try? FileManager.default.removeItem(at: unpacked.workingDirectory) }
        print("LIVE import checksum verified; games: \(unpacked.bottle.games.map(\.name))")
        let prefix = unpacked.prefixDirectory
        let fm = FileManager.default
        print("LIVE users: \((try? fm.contentsOfDirectory(atPath: prefix.appending(path: "drive_c/users").path).sorted()) ?? [])")
        print("LIVE dosdevices: \((try? fm.contentsOfDirectory(atPath: prefix.appending(path: "dosdevices").path).sorted()) ?? [])")
        // Every file that still names the exporting user, contents or name.
        let grep = Process()
        grep.executableURL = URL(filePath: "/usr/bin/grep")
        grep.arguments = ["-rlI", "--", NSUserName(), prefix.path]
        let pipe = Pipe()
        grep.standardOutput = pipe
        try grep.run()
        let hits = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        grep.waitUntilExit()
        let files = hits.split(separator: "\n").map { $0.replacingOccurrences(of: prefix.path + "/", with: "") }
        print("LIVE files naming the owner: \(files.count)")
        for file in files.prefix(40) { print("LIVE   \(file)") }
    }
}
