import Foundation
import Testing
@testable import Fable

/// v1.3: the validation ladder. These lock how a run's output becomes rungs —
/// above all that nothing unproven is ever reported as passed.
@Suite("Engine canary")
struct EngineCanaryTests {

    /// What the program wrote on a real Sikarugir Wine 10 engine (M4 Pro).
    private let healthy = """
    fable-canary 1
    pe=ok bits=64
    dll.d3d12=ok path=C:\\windows\\system32\\d3d12.dll
    d3d12.device=ok
    d3d12.queue=ok
    dll.dxgi=ok path=C:\\windows\\system32\\dxgi.dll
    adapter=ok vendor=0x1002 device=0x66af vram_mb=18186 name=AMD Compatibility Mode
    dll.d3d11=ok path=C:\\windows\\system32\\d3d11.dll
    d3d11.device=ok level=0xb000
    done
    """

    private func statuses(_ rungs: [CanaryRung]) -> [CanaryStatus] { rungs.map(\.status) }

    @Test
    func aHealthyEnginePassesEveryRung() {
        let rungs = EngineCanary.rungs(output: healthy, exit: .exited(0), errorTail: "")
        #expect(rungs.map(\.id) == CanaryRung.ID.allCases)
        #expect(statuses(rungs) == [.passed, .passed, .passed, .passed, .passed])
        #expect(rungs.first { $0.id == .adapter }?.detail == "AMD Compatibility Mode")
    }

    /// The real failure seen with the renderer removed: the engine asserted
    /// and hung while loading d3d12.dll, after writing only the first lines.
    @Test
    func aHangStopsAtTheRungInProgressAndSkipsTheRest() {
        let partial = "fable-canary 1\npe=ok bits=64\n"
        let rungs = EngineCanary.rungs(
            output: partial, exit: .timedOut,
            errorTail: "Assertion failed: (GFXTHandle && \"Failed to dlopen D3DMetal\")")
        #expect(statuses(rungs) == [.passed, .failed, .skipped, .skipped, .skipped])
        #expect(rungs[1].detail?.contains("Failed to dlopen D3DMetal") == true)
    }

    @Test
    func skippedIsNeverPassed() {
        let partial = "fable-canary 1\npe=ok bits=64\n"
        let result = CanaryResult(
            backend: .sikarugir, engineKey: nil, manifestID: nil, date: .now, durationSeconds: 1,
            rungs: EngineCanary.rungs(output: partial, exit: .timedOut, errorTail: ""), fableVersion: nil)
        #expect(!result.allPassed)
        #expect(result.hasFailure)
        #expect(result.firstProblem?.id == .rendererLoads)
        // An engine that can't be tested claims nothing either.
        let unsupported = EngineCanary.unsupportedResult(backend: .dxmt, engineKey: nil)
        #expect(!unsupported.allPassed)
        #expect(!unsupported.hasFailure)
        #expect(CanaryResult(backend: .sikarugir, engineKey: nil, manifestID: nil, date: .now,
                             durationSeconds: 0, rungs: [], fableVersion: nil).allPassed == false)
    }

    @Test
    func aFailedDeviceIsReportedWithItsErrorAndLaterRungsStillRun() {
        let output = healthy
            .replacingOccurrences(of: "d3d12.device=ok", with: "d3d12.device=failed hr=0x887a0004")
            .replacingOccurrences(of: "d3d12.queue=ok", with: "d3d12.queue=skipped")
        let rungs = EngineCanary.rungs(output: output, exit: .exited(0), errorTail: "")
        #expect(statuses(rungs) == [.passed, .passed, .failed, .passed, .passed])
        #expect(rungs[2].detail == "no D3D12 device (error 0x887a0004)")
    }

    @Test
    func aMissingDLLFailsLoadingAndItsDeviceRungIsSkipped() {
        let output = """
        fable-canary 1
        pe=ok bits=64
        dll.d3d12=failed error=126
        d3d12.device=skipped
        d3d12.queue=skipped
        dll.dxgi=ok path=C:\\windows\\system32\\dxgi.dll
        adapter=ok vendor=0x1 device=0x2 vram_mb=1 name=Some Adapter
        dll.d3d11=ok path=x
        d3d11.device=ok level=0xb000
        done
        """
        let rungs = EngineCanary.rungs(output: output, exit: .exited(0), errorTail: "")
        #expect(statuses(rungs) == [.passed, .failed, .skipped, .passed, .passed])
        #expect(rungs[1].detail == "d3d12.dll did not load (error 126)")
    }

    @Test
    func aCrashNamesItselfAndNothingAfterItCounts() {
        let output = "fable-canary 1\npe=ok bits=64\ndll.d3d12=ok path=x\ncrash=0xc0000005 stage=d3d12.device\n"
        let rungs = EngineCanary.rungs(output: output, exit: .exited(3), errorTail: "")
        #expect(statuses(rungs) == [.passed, .failed, .skipped, .skipped, .skipped])
        // dll.dxgi was never reached, so loading didn't finish: that is where it stopped.
        #expect(rungs[1].detail == "crashed (0xc0000005)")
    }

    @Test
    func wineNotStartingFailsTheFirstRung() {
        let rungs = EngineCanary.rungs(output: "", exit: .exited(1), errorTail: "dyld: Library not loaded: @rpath/libinotify.0.dylib")
        #expect(statuses(rungs) == [.failed, .skipped, .skipped, .skipped, .skipped])
        #expect(rungs[0].detail?.contains("libinotify") == true)
        let noStart = EngineCanary.rungs(output: "", exit: .couldNotStart("Bad CPU type in executable"), errorTail: "")
        #expect(noStart[0].detail == "Bad CPU type in executable")
    }

    @Test
    func aRunThatFinishedWithoutReportingARungIsInconclusiveNotPassed() {
        let output = "fable-canary 1\npe=ok bits=64\ndone\n"
        let rungs = EngineCanary.rungs(output: output, exit: .exited(0), errorTail: "")
        #expect(statuses(rungs) == [.passed, .inconclusive, .inconclusive, .inconclusive, .inconclusive])
    }

    @Test
    func theErrorTailPrefersTheTellingLine() {
        let stderr = """
        Assertion failed: (GFXTHandle && "Failed to dlopen D3DMetal"), function D3DRMDispatch_Init_block_invoke
        [mvk-info] Created VkInstance for Vulkan version 1.0.334
        \tVK_KHR_get_physical_device_properties2 v2
        """
        #expect(EngineCanary.errorTail(of: stderr).hasPrefix("Assertion failed"))
        #expect(EngineCanary.errorTail(of: "one\ntwo\n") == "two")
        #expect(EngineCanary.errorTail(of: "") == "")
    }

    @Test
    func onlyEnginesFableCanExerciseAreTested() {
        #expect(EngineCanary.supports(.sikarugir))
        #expect(EngineCanary.supports(.sikarugir11))
        #expect(EngineCanary.supports(.gptk))
        // Their Direct3D lives in the bottle, or in someone else's install.
        #expect(!EngineCanary.supports(.dxmt))
        #expect(!EngineCanary.supports(.dxvk))
        #expect(!EngineCanary.supports(.crossover))
        #expect(!EngineCanary.supports(.off))
    }

    @Test
    func resultsAreStoredPerEngineAndBackend() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "fable-canary-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        func result(_ key: String, passed: Bool) -> CanaryResult {
            CanaryResult(
                backend: .sikarugir, engineKey: key, manifestID: "abc",
                date: Date(timeIntervalSince1970: 1_800_000_000), durationSeconds: 8,
                rungs: [CanaryRung(id: .windowsProgram, status: passed ? .passed : .failed, detail: nil)],
                fableVersion: "1.3.0")
        }
        CanaryStore.save(result("sikarugir=A", passed: true), to: file)
        CanaryStore.save(result("sikarugir=B", passed: false), to: file)
        #expect(CanaryStore.latest(backend: .sikarugir, engineKey: "sikarugir=A", from: file)?.allPassed == true)
        #expect(CanaryStore.latest(backend: .sikarugir, engineKey: "sikarugir=B", from: file)?.hasFailure == true)
        // A result for one engine says nothing about another, or another backend.
        #expect(CanaryStore.latest(backend: .sikarugir, engineKey: "sikarugir=C", from: file) == nil)
        #expect(CanaryStore.latest(backend: .sikarugir11, engineKey: "sikarugir=A", from: file) == nil)
        // A newer run replaces the older one for the same engine.
        CanaryStore.save(result("sikarugir=A", passed: false), to: file)
        #expect(CanaryStore.latest(backend: .sikarugir, engineKey: "sikarugir=A", from: file)?.hasFailure == true)
    }

    @Test
    func everyStatusAndRungHasWording() {
        for status in [CanaryStatus.passed, .failed, .skipped, .unsupported, .inconclusive] {
            #expect(!status.label.hasPrefix("canary."))
        }
        for id in CanaryRung.ID.allCases {
            #expect(!CanaryRung(id: id, status: .passed, detail: nil).lineText.hasPrefix("canary."))
        }
        let passed = CanaryResult(
            backend: .sikarugir, engineKey: nil, manifestID: nil, date: .now, durationSeconds: 8,
            rungs: EngineCanary.rungs(output: healthy, exit: .exited(0), errorTail: ""), fableVersion: nil)
        #expect(!passed.summaryText.contains("%"))
        #expect(!EngineCanary.unsupportedResult(backend: .dxmt, engineKey: nil).summaryText.contains("%"))
    }

    /// The canary programs are committed binaries. They may only change
    /// together with canary/SHA256SUMS, which `scripts/build-canary.sh`
    /// prints — so a changed program is always visible beside its source.
    @Test
    func theShippedProgramsMatchTheirRecordedChecksums() throws {
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sums = try String(contentsOf: repo.appending(path: "canary/SHA256SUMS"), encoding: .utf8)
        var checked = 0
        for line in sums.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let file = repo.appending(path: "Sources/Fable/Resources/canary/\(parts[1])")
            #expect(try RuntimeIntegrity.sha256(ofFileAt: file.path) == String(parts[0]), "\(parts[1]) changed without SHA256SUMS")
            checked += 1
        }
        #expect(checked == 2)
        #expect(EngineCanary.program != nil)
    }
}
