import Foundation
import Testing
@testable import Fable

/// Playtime/notes store + the Steam-launched running detection.
@MainActor
@Suite struct GameStatsTests {
    private let fm = FileManager.default

    private func tempFile() -> URL {
        fm.temporaryDirectory.appending(path: "stats-\(UUID().uuidString).json")
    }

    @Test
    func crashRecordsCorrelateAcrossBackendsAndClearOnCleanRun() throws {
        let file = tempFile()
        defer { try? fm.removeItem(at: file) }
        let id = UUID()
        let store = GameStatsStore(fileURL: file)

        // One backend crashing is just a crash — could be config.
        store.recordCrash(id, backend: "gptk", signature: "int3")
        #expect(store.crossBackendCrash(id) == nil)

        // The SAME signature on a second backend is the First Light tell.
        store.recordCrash(id, backend: "sikarugir", signature: "int3")
        let cross = try #require(store.crossBackendCrash(id))
        #expect(cross.signature == "int3")
        #expect(cross.backends == ["gptk", "sikarugir"])

        // Verdict survives a reload (backend roulette spans days).
        #expect(GameStatsStore(fileURL: file).crossBackendCrash(id) != nil)

        // A clean run on one backend clears its record — game works now.
        store.recordCrash(id, backend: "sikarugir", signature: nil)
        #expect(store.crossBackendCrash(id) == nil)
    }

    @Test
    func statsFileWithoutCrashFieldStillDecodes() throws {
        // Pre-0.20 stats files have no crashSignatures key. (Swift encodes
        // [UUID: Stats] as an alternating key/value ARRAY, not an object —
        // matches the real game-stats.json on disk.)
        let file = tempFile()
        defer { try? fm.removeItem(at: file) }
        let id = UUID()
        try Data("""
        ["\(id.uuidString)", {"totalSeconds": 120, "notes": "old"}]
        """.utf8).write(to: file)

        let store = GameStatsStore(fileURL: file)
        #expect(store.stats[id]?.totalSeconds == 120)
        #expect(store.crossBackendCrash(id) == nil)
    }

    @Test
    func sessionsAccumulateAndPersist() throws {
        let file = tempFile()
        defer { try? fm.removeItem(at: file) }
        let id = UUID()
        let store = GameStatsStore(fileURL: file)

        let start = Date(timeIntervalSince1970: 1_000)
        store.sessionStarted(id, at: start)
        store.sessionEnded(id, at: start.addingTimeInterval(90 * 60))
        // A second session adds on top.
        store.sessionStarted(id, at: start.addingTimeInterval(10_000))
        store.sessionEnded(id, at: start.addingTimeInterval(10_000 + 30 * 60))

        #expect(store.stats[id]?.totalSeconds == 7_200.0)
        #expect(store.stats[id]?.lastPlayedAt == start.addingTimeInterval(10_000 + 30 * 60))

        // Survives a reload.
        let reopened = GameStatsStore(fileURL: file)
        #expect(reopened.stats[id]?.totalSeconds == 7_200.0)
    }

    @Test
    func endWithoutStartIsIgnoredAndTouchOnlySetsLastPlayed() {
        let file = tempFile()
        defer { try? fm.removeItem(at: file) }
        let id = UUID()
        let store = GameStatsStore(fileURL: file)

        store.sessionEnded(id)  // no session running — must not invent time
        #expect(store.stats[id] == nil)

        store.touch(id)
        #expect(store.stats[id]?.lastPlayedAt != nil)
        #expect(store.stats[id]?.totalSeconds == 0)
    }

    @Test
    func notesRoundTrip() {
        let file = tempFile()
        defer { try? fm.removeItem(at: file) }
        let id = UUID()
        let store = GameStatsStore(fileURL: file)
        store.setNotes("EF mod installed; use -windowed", for: id)
        #expect(GameStatsStore(fileURL: file).notes(for: id) == "EF mod installed; use -windowed")
    }

    @Test
    func playtimeFormatsAtTheRightPrecision() {
        #expect(GameStatsStore.formattedPlaytime(seconds: 30) == nil)      // not playtime yet
        #expect(GameStatsStore.formattedPlaytime(seconds: 12 * 60) == "12 min")
        #expect(GameStatsStore.formattedPlaytime(seconds: 3.5 * 3600) == "3.5 h")
        #expect(GameStatsStore.formattedPlaytime(seconds: 26 * 3600) == "26 h")
    }

    // MARK: Steam-launched detection

    @Test
    func windowsPathDerivesFromDriveC() {
        let unix = "/Users/me/Bottles/ABC/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Ready Or Not/ReadyOrNot.exe"
        #expect(ProcessActivity.windowsPath(fromExecutablePath: unix)
                == #"c:\Program Files (x86)\Steam\steamapps\common\Ready Or Not\ReadyOrNot.exe"#)
        #expect(ProcessActivity.windowsPath(fromExecutablePath: "/Applications/Game.app/exe") == nil)
    }

    @Test
    func steamLaunchedGameMatchesByWindowsPath() {
        // A Steam-launched game's command line is Windows-style — it names the
        // exe but NOT the bottle's unix path, so the UUID+basename rule alone
        // missed it (the "game shows as just Steam running" report).
        let bottleID = "6E1AA1FD-0000-0000-0000-000000000000"
        let winPath = #"c:\Program Files (x86)\Steam\steamapps\common\Ready Or Not\ReadyOrNot.exe"#
        let commands = [
            #"z:\usr\wine\bin\wine c:\program files (x86)\steam\steamapps\common\ready or not\readyornot.exe -silent"#,
        ]
        // Old rule alone: no match (no bottle token in the command).
        #expect(!ProcessActivity.isRunning(
            commands: commands, prefixToken: bottleID, exeBasename: "ReadyOrNot.exe"
        ))
        // With the windows path: match.
        #expect(ProcessActivity.isRunning(
            commands: commands, prefixToken: bottleID, exeBasename: "ReadyOrNot.exe",
            windowsPath: winPath
        ))
        // Forward-slash variant (wine sometimes normalizes) also matches.
        let slashCommands = [#"wine c:/program files (x86)/steam/steamapps/common/ready or not/readyornot.exe"#]
        #expect(ProcessActivity.isRunning(
            commands: slashCommands, prefixToken: bottleID, exeBasename: "ReadyOrNot.exe",
            windowsPath: winPath
        ))
        // An unrelated game does not.
        #expect(!ProcessActivity.isRunning(
            commands: commands, prefixToken: bottleID, exeBasename: "Deathloop.exe",
            windowsPath: #"c:\Program Files (x86)\Steam\steamapps\common\DEATHLOOP\Deathloop.exe"#
        ))
    }

    @Test
    func fableLaunchedGameStillMatchesByUnixPath() {
        let bottleID = "6E1AA1FD-0000-0000-0000-000000000000"
        let commands = [
            "/usr/wine/bin/wine64 /users/me/bottles/6e1aa1fd-0000-0000-0000-000000000000/prefix/drive_c/games/balatro.exe",
        ]
        #expect(ProcessActivity.isRunning(
            commands: commands, prefixToken: bottleID, exeBasename: "Balatro.exe"
        ))
    }
}
