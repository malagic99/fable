import Foundation
import Testing
@testable import Fable

/// The offline anti-cheat quirk source — name matching, status→severity, and
/// finding synthesis.
@Suite struct AntiCheatDatabaseTests {

    private func db() -> AntiCheatDatabase {
        AntiCheatDatabase(entries: [
            .init(name: "Apex Legends", status: "Denied", anticheats: ["Easy Anti-Cheat"]),
            .init(name: "Halo: The Master Chief Collection", status: "Broken", anticheats: ["Easy Anti-Cheat", "BattlEye"]),
            .init(name: "Elden Ring", status: "Supported", anticheats: ["Easy Anti-Cheat"]),
            .init(name: "Some Game", status: "Configuration", anticheats: []),
            .init(name: "Mystery Title", status: "Unknown", anticheats: []),
        ])
    }

    @Test
    func matchesNamesIgnoringTrademarksAndPunctuation() {
        let db = db()
        // ™ and the colon shouldn't break the match.
        #expect(db.entry(forGameNamed: "Apex Legends™")?.status == "Denied")
        #expect(db.entry(forGameNamed: "halo  the master chief collection")?.status == "Broken")
        #expect(db.entry(forGameNamed: "Not In The List") == nil)
    }

    @Test
    func mapsStatusToSeverity() {
        #expect(AntiCheatDatabase.severity(for: "Denied") == .knownBlocker)
        #expect(AntiCheatDatabase.severity(for: "broken") == .knownBlocker)
        #expect(AntiCheatDatabase.severity(for: "Configuration") == .caveat)
        #expect(AntiCheatDatabase.severity(for: "Supported") == .info)
        #expect(AntiCheatDatabase.severity(for: "Unknown") == nil)   // no actionable signal
    }

    @Test
    func deniedGameBecomesABlockerFindingNamingTheAntiCheat() {
        let finding = db().finding(forGameNamed: "Apex Legends")
        #expect(finding?.severity == .knownBlocker)
        #expect(finding?.id == "anticheat-db")
        #expect(finding?.title.contains("Easy Anti-Cheat") == true)
        #expect(finding?.suggestion.isEmpty == false)
    }

    @Test
    func unknownStatusYieldsNoFinding() {
        #expect(db().finding(forGameNamed: "Mystery Title") == nil)
    }

    @Test
    func parsesAreWeAntiCheatYetShapedJSON() throws {
        let json = """
        [
          { "name": "Valorant", "status": "Denied", "anticheats": ["Riot Vanguard"], "storeIds": {} },
          { "name": "Bad Entry With No Status" },
          { "name": "Team Fortress 2", "status": "Supported", "anticheats": [] }
        ]
        """
        let dir = FileManager.default.temporaryDirectory.appending(path: "acy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "areweanticheatyet.json")
        try json.write(to: url, atomically: true, encoding: .utf8)

        let db = try #require(AntiCheatDatabase.load(from: url))
        #expect(db.count == 2)   // the status-less entry is skipped
        #expect(db.finding(forGameNamed: "Valorant")?.severity == .knownBlocker)
        #expect(db.entry(forGameNamed: "Team Fortress 2")?.status == "Supported")
    }
}
