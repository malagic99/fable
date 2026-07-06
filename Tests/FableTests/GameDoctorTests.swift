import Foundation
import Testing
@testable import Fable

/// Fable Doctor's log-signature matching.
@Suite struct GameDoctorTests {

    private func ids(_ findings: [CompatibilityFinding]) -> Set<String> {
        Set(findings.map(\.id))
    }

    @Test
    func cleanLogYieldsNothing() {
        #expect(GameDoctor.diagnose(log: "fixme:everything is fine\ninfo:loaded ok").isEmpty)
    }

    @Test
    func missingVCRuntimeIsCaught() {
        let log = "err:module:import_dll Library MSVCP140.dll not found"
        let findings = GameDoctor.diagnose(log: log)
        // Two rules fire here (the specific vcredist one + the generic missing-dll).
        #expect(ids(findings).contains("doctor-vcredist"))
        #expect(findings.first(where: { $0.id == "doctor-vcredist" })?.severity == .caveat)
    }

    @Test
    func anticheatIsAHardBlocker() {
        let log = "Loading EasyAntiCheat_x64.dll ... blocked"
        let finding = GameDoctor.diagnose(log: log).first { $0.id == "doctor-anticheat" }
        #expect(finding?.severity == .knownBlocker)
    }

    @Test
    func matchingIsCaseInsensitive() {
        #expect(!GameDoctor.diagnose(log: "FAILED TO CREATE D3D12 DEVICE").isEmpty)
    }

    @Test
    func d3d12FailureSuggestsSikarugir() {
        let finding = GameDoctor.diagnose(log: "vkd3d: device removed").first { $0.id == "doctor-d3d12-device" }
        #expect(finding?.suggestion.contains("Sikarugir") == true)
    }

    // ——— The 2026-06 investigation signatures (docs/ARCHITECTURE.md) ———

    @Test
    func realLogLinesMatchTheInvestigationRules() {
        // Each pair: a line as it actually appears in the wild → the rule id.
        let cases: [(String, String)] = [
            ("Assertion failed: (GFXTHandle), Failed to dlopen D3DMetal", "doctor-d3dmetal-dlopen"),
            ("wine: could not load kernel32.dll, status c0000142", "doctor-abi-mismatch"),
            ("dlopen: library load disallowed by system policy", "doctor-quarantine"),
            ("Wine cannot find the FreeType font library.", "doctor-freetype"),
            ("err:secur32:schan_imp_init Failed to load libgnutls, secure connections will not be available.", "doctor-gnutls"),
            ("[service] Failed to create Service pipe (GLE 2)", "doctor-steamservice"),
            ("Execution of the command buffer was aborted due to an error during execution", "doctor-gpu-hang"),
            ("CreateTexture2D returned E_OUTOFMEMORY", "doctor-out-of-memory"),
            ("Denuvo Anti-Tamper: integrity check", "doctor-denuvo"),
            ("err:module:import_dll Library XAudio2_7.dll not found", "doctor-xaudio"),
            ("PhysXLoader.dll failed to initialize", "doctor-physx"),
        ]
        for (line, ruleID) in cases {
            #expect(ids(GameDoctor.diagnose(log: line)).contains(ruleID),
                    "expected \(ruleID) to match: \(line)")
        }
    }

    @Test
    func denuvoIsABlockerAndPointsAtStreaming() {
        let finding = GameDoctor.diagnose(log: "denuvo").first { $0.id == "doctor-denuvo" }
        #expect(finding?.severity == .knownBlocker)
        #expect(finding?.suggestion.contains("streaming") == true)
    }

    @Test
    func steamServiceFailurePointsAtTheCommitter() {
        let finding = GameDoctor.diagnose(log: "BOpenService failed (GLE 1060)")
            .first { $0.id == "doctor-steamservice" }
        #expect(finding?.suggestion.contains("Finish Stuck Steam Downloads") == true)
    }

    @Test
    func rulesHaveUniqueIDsAndNonEmptyGuidance() {
        // The database is data — lock its invariants so a bulk edit can't
        // ship a duplicate id or an empty suggestion.
        let ids = GameDoctor.rules.map(\.id)
        #expect(Set(ids).count == ids.count)
        for rule in GameDoctor.rules {
            #expect(!rule.needles.isEmpty)
            #expect(!rule.suggestion.isEmpty)
            // Needles must be lowercase — matching lowercases the haystack only.
            for needle in rule.needles {
                #expect(needle == needle.lowercased(), "needle not lowercase: \(needle)")
            }
        }
    }

    @Test
    func diagnosesFromAFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "doc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "run.log")
        try "wine: mscoree not found".write(to: url, atomically: true, encoding: .utf8)
        #expect(GameDoctor.diagnose(logFile: url).contains { $0.id == "doctor-dotnet" })
        // Missing file → empty, never throws.
        #expect(GameDoctor.diagnose(logFile: dir.appending(path: "nope.log")).isEmpty)
    }
}
