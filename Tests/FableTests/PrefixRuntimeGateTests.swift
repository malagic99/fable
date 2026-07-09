import Foundation
import Testing
@testable import Fable

/// The one-live-Wine-per-prefix gate — the fix for the 'version mismatch
/// NNN/NNN' class found in the VotV session.
@Suite struct PrefixRuntimeGateTests {
    private let fm = FileManager.default

    /// A fake wineserver: a script that appends its argv + WINEPREFIX to a
    /// journal file, so the test can assert exactly how it was driven.
    private func fakeWineserver(journal: URL) throws -> URL {
        let dir = fm.temporaryDirectory.appending(path: "gate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appending(path: "wineserver")
        try """
        #!/bin/sh
        echo "$WINEPREFIX $@" >> "\(journal.path)"
        """.write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    @Test
    func busyBottleRefusesInsteadOfKilling() async throws {
        let journal = fm.temporaryDirectory.appending(path: "journal-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: journal) }
        let ws = try fakeWineserver(journal: journal)

        await #expect(throws: PrefixRuntimeGate.BottleBusyError.self) {
            try await PrefixRuntimeGate.ensureExclusive(
                prefix: URL(filePath: "/tmp/prefix"),
                bottleName: "Steam Ready",
                foreignWineservers: [ws],
                hasLiveProcesses: true
            )
        }
        // Busy → nothing was drained.
        #expect(!fm.fileExists(atPath: journal.path))
    }

    @Test
    func idleBottleDrainsEveryForeignServerWithKillThenWait() async throws {
        let journal = fm.temporaryDirectory.appending(path: "journal-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: journal) }
        let wsA = try fakeWineserver(journal: journal)
        let wsB = try fakeWineserver(journal: journal)
        let prefix = URL(filePath: "/tmp/some prefix")

        try await PrefixRuntimeGate.ensureExclusive(
            prefix: prefix,
            bottleName: "Steam Ready",
            foreignWineservers: [wsA, wsB],
            hasLiveProcesses: false
        )

        let lines = try String(contentsOf: journal, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        // Each server: -k (kill) then -w (wait for exit), prefix threaded.
        #expect(lines == [
            "/tmp/some prefix -k", "/tmp/some prefix -w",
            "/tmp/some prefix -k", "/tmp/some prefix -w",
        ])
    }

    @Test
    func busyVerdictMatchesBottleTokenInCommands() {
        let id = UUID()
        let commands = [
            "/usr/bin/wine /x/bottles/\(id.uuidString.lowercased())/prefix/drive_c/game.exe",
        ]
        #expect(PrefixRuntimeGate.hasProcesses(commands: commands, bottleID: id))
        #expect(!PrefixRuntimeGate.hasProcesses(commands: commands, bottleID: UUID()))
        #expect(!PrefixRuntimeGate.hasProcesses(commands: [], bottleID: id))
    }
}
