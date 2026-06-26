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
