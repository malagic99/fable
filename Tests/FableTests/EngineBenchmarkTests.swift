import Foundation
import Testing
@testable import Fable

/// The engine benchmark: a fixed scene, timed. These lock how its output
/// becomes a result, and when two results may be compared at all.
@Suite("Engine benchmark")
struct EngineBenchmarkTests {

    /// What the program wrote on a real Sikarugir Wine 10 engine (M4 Pro).
    private let healthy = """
    fable-bench 1
    scene=ok width=2560 height=1440 draws=20000 steps=256 seconds=3
    libraries=ok
    device=ok
    window=ok
    swapchain=ok
    shaders=ok
    pipeline=ok
    present=ok first_ms=9.988
    phase.draws=ok frames=407 wall_ms=3003 avg_ms=7.368 median_ms=7.000 p99_ms=10.248
    phase.shade=ok frames=795 wall_ms=3002 avg_ms=3.771 median_ms=3.761 p99_ms=4.039
    done
    """

    private func result(
        _ output: String, exit: EngineCanary.Exit = .exited(0), errorTail: String = "",
        engineKey: String? = "sikarugir=A", supported: Bool = true, hardware: String? = "Apple M4 Pro"
    ) -> BenchmarkResult {
        EngineBenchmark.result(
            backend: .sikarugir, engineKey: engineKey, manifestID: nil,
            date: Date(timeIntervalSince1970: 1_800_000_000), durationSeconds: 14,
            supported: supported, output: output, exit: exit, errorTail: errorTail, hardware: hardware)
    }

    @Test
    func aHealthyRunYieldsBothPhasesAndAPresentedFrame() {
        let r = result(healthy)
        #expect(r.isComplete)
        #expect(r.failure == nil)
        #expect(r.framePresented == .passed)
        #expect(r.phase(.draws)?.medianMs == 7.0)
        #expect(r.phase(.draws)?.frames == 407)
        #expect(r.phase(.shade)?.p99Ms == 4.039)
        #expect(r.scene == "width=2560 height=1440 draws=20000 steps=256 seconds=3")
    }

    @Test
    func aStepThatFailsExplainsWhyThereAreNoNumbers() {
        let output = "fable-bench 1\nscene=ok width=2560\nlibraries=ok\ndevice=ok\nwindow=ok\nswapchain=ok\nshaders=failed hr=0x80004005\ndone\n"
        let r = result(output, exit: .exited(2))
        #expect(!r.isComplete)
        #expect(r.phases.isEmpty)
        #expect(r.failure == "compiling the shaders failed (error 0x80004005)")
        // No frame was reached: skipped, never passed.
        #expect(r.framePresented == .skipped)
    }

    /// Seen on a real GPTK engine whose renderer is newer than its Wine.
    @Test
    func aLibraryThatWillNotLoadIsNamed() {
        let output = "fable-bench 1\nscene=ok width=2560\nlibraries=failed error=1114 dll=d3d12.dll\ndone\n"
        let r = result(output, exit: .exited(2))
        #expect(r.failure == "loading the Direct3D libraries failed (d3d12.dll, error 1114)")
        #expect(r.framePresented == .skipped)
    }

    @Test
    func aHangIsReportedAtTheStepItStoppedIn() {
        let output = "fable-bench 1\nscene=ok width=2560\nlibraries=ok\n"
        let r = result(output, exit: .timedOut, errorTail: "Assertion failed: Failed to dlopen D3DMetal")
        #expect(r.failure == "stopped responding while creating a D3D12 device: Assertion failed: Failed to dlopen D3DMetal")
        #expect(r.phases.isEmpty)
    }

    @Test
    func aFailedPresentIsAFailedRungAndStopsThere() {
        let output = healthy.components(separatedBy: "present=ok")[0] + "present=failed reason=gpu-timeout\ndone\n"
        let r = result(output, exit: .exited(2))
        #expect(r.framePresented == .failed)
        #expect(r.failure == "no frame could be presented (gpu-timeout)")
    }

    @Test
    func aPhaseThatFailsKeepsTheOneBeforeIt() {
        let output = healthy.replacingOccurrences(
            of: "phase.shade=ok frames=795 wall_ms=3002 avg_ms=3.771 median_ms=3.761 p99_ms=4.039",
            with: "phase.shade=failed reason=gpu-timeout frames=12")
        let r = result(output)
        #expect(r.phases.map(\.id) == [.draws])
        #expect(!r.isComplete)
        #expect(r.failure?.contains("shade phase failed") == true)
    }

    @Test
    func aCrashMidPhaseIsNamed() {
        let output = healthy.components(separatedBy: "phase.draws")[0] + "crash=0xc0000005 stage=draws\n"
        let r = result(output, exit: .exited(3))
        #expect(r.failure == "crashed while the draws phase (0xc0000005)")
        #expect(r.framePresented == .passed)
    }

    @Test
    func anEngineThatCannotBeBenchmarkedClaimsNothing() {
        let r = result("", supported: false)
        #expect(r.framePresented == .unsupported)
        #expect(!r.isComplete)
        #expect(r.displayLines.count == 1)
    }

    @Test
    func garbageNumbersAreNotAResult() {
        #expect(EngineBenchmark.phase(.draws, from: "ok frames=3 avg_ms=1 median_ms=1 p99_ms=1") == nil)
        #expect(EngineBenchmark.phase(.draws, from: "ok frames=400 avg_ms=1 median_ms=0 p99_ms=1") == nil)
        #expect(EngineBenchmark.phase(.draws, from: "ok frames=400") == nil)
    }

    // MARK: Comparing

    private func withMedians(draws: Double, shade: Double, key: String, scene: String? = nil,
                             hardware: String? = "Apple M4 Pro") -> BenchmarkResult {
        var r = result(healthy, engineKey: key, hardware: hardware)
        r.phases = [
            .init(id: .draws, frames: 400, medianMs: draws, averageMs: draws, p99Ms: draws),
            .init(id: .shade, frames: 800, medianMs: shade, averageMs: shade, p99Ms: shade),
        ]
        if let scene { r.scene = scene }
        return r
    }

    @Test
    func differencesInsideTheNoiseAreTheSame() {
        let old = withMedians(draws: 7.0, shade: 3.76, key: "sikarugir=A")
        // 10% on draws was seen between runs of one engine: not a difference.
        let noisy = withMedians(draws: 7.7, shade: 3.80, key: "sikarugir=B")
        #expect(EngineBenchmark.compare(noisy, to: old, phase: .draws) == .same)
        #expect(EngineBenchmark.compare(noisy, to: old, phase: .shade) == .same)
    }

    @Test
    func realDifferencesAreReportedWithTheirSize() {
        let old = withMedians(draws: 8.0, shade: 4.0, key: "sikarugir=A")
        let slower = withMedians(draws: 10.0, shade: 4.4, key: "sikarugir=B")
        #expect(EngineBenchmark.compare(slower, to: old, phase: .draws) == .slower(0.25))
        if case .slower(let f) = EngineBenchmark.compare(slower, to: old, phase: .shade) {
            #expect(abs(f - 0.1) < 0.0001)
        } else {
            Issue.record("a 10% shading slowdown is outside the 5% margin")
        }
        let faster = withMedians(draws: 6.0, shade: 4.0, key: "sikarugir=C")
        #expect(EngineBenchmark.compare(faster, to: old, phase: .draws) == .faster(0.25))
    }

    @Test
    func resultsFromAnotherSceneOrAnotherMacAreNotCompared() {
        let old = withMedians(draws: 8.0, shade: 4.0, key: "sikarugir=A")
        let otherScene = withMedians(draws: 4.0, shade: 2.0, key: "sikarugir=B", scene: "width=1280 height=720")
        #expect(EngineBenchmark.compare(otherScene, to: old, phase: .draws) == nil)
        let otherMac = withMedians(draws: 4.0, shade: 2.0, key: "sikarugir=B", hardware: "Apple M1")
        #expect(EngineBenchmark.compare(otherMac, to: old, phase: .draws) == nil)
        var incomplete = old
        incomplete.phases.removeLast()
        #expect(EngineBenchmark.compare(incomplete, to: old, phase: .shade) == nil)
        #expect(otherMac.comparisonLines(with: [old]).isEmpty)
    }

    @Test
    func theStoreOffersOnlyOtherCompleteEnginesOfTheSameBackend() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "fable-bench-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let current = withMedians(draws: 8, shade: 4, key: "sikarugir=A")
        BenchmarkStore.save(current, to: file)
        BenchmarkStore.save(withMedians(draws: 9, shade: 4, key: "sikarugir=B"), to: file)
        var broken = withMedians(draws: 9, shade: 4, key: "sikarugir=C")
        broken.failure = "stopped"
        BenchmarkStore.save(broken, to: file)
        var otherBackend = withMedians(draws: 9, shade: 4, key: "sikarugir11=X")
        otherBackend.backend = .sikarugir11
        BenchmarkStore.save(otherBackend, to: file)

        #expect(BenchmarkStore.others(than: current, from: file).map(\.engineKey) == ["sikarugir=B"])
        #expect(BenchmarkStore.latest(backend: .sikarugir, engineKey: "sikarugir=A", from: file) == current)
    }

    @Test
    func theWordingCarriesTheNumbersAndNoRawPlaceholders() {
        let r = result(healthy)
        let lines = r.displayLines
        #expect(lines.count == 3)
        #expect(lines[0].contains("7.0"))
        #expect(lines[1].contains("3.8"))
        #expect(lines.allSatisfy { !$0.contains("%@") && !$0.hasPrefix("bench.") })
        let other = withMedians(draws: 5.0, shade: 3.76, key: "sikarugir=WS12WineSikarugir10.0_8")
        let compared = r.comparisonLines(with: [other])
        #expect(compared.count == 1)
        #expect(compared[0].contains("40"))
        #expect(compared[0].contains("10.0_8"))
        #expect(!compared[0].contains("%@"))
    }
}
