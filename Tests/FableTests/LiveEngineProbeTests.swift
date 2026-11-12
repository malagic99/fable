import Foundation
import Testing
@testable import Fable

/// Opt-in: runs the canary (and, for `+bench`, the benchmark) on this Mac's
/// real engines through the launcher's own code path, with the real managers.
/// Nothing here runs in CI — it needs installed engines, Rosetta and a GPU.
///
///     FABLE_LIVE_PROBE=sikarugir+bench swift test --filter LiveEngineProbe
///     FABLE_LIVE_PROBE=sikarugir11,gptk swift test --filter LiveEngineProbe
///
/// Results are real measurements and are stored like any other run.
@Suite("Live engine probe", .enabled(if: ProcessInfo.processInfo.environment["FABLE_LIVE_PROBE"] != nil))
struct LiveEngineProbeTests {
    @Test @MainActor
    func theLauncherRunsTheProbesOnRealEngines() async throws {
        let catalog = try VersionCatalog.loadBundled()
        let components = ComponentManager()
        let launcher = GameLauncher()
        launcher.configure(.init(
            bottleManager: BottleManager(),
            componentManager: components,
            wineManager: WineManager(componentManager: components, catalog: catalog),
            gptkManager: GPTKManager(componentManager: components, catalog: catalog),
            crossOverManager: CrossOverManager(),
            sikarugirManager: SikarugirManager(componentManager: components, catalog: catalog),
            sikarugir11Manager: Sikarugir11Manager(componentManager: components, catalog: catalog),
            triggerController: DualSenseTriggerController(),
            activityMonitor: ActivityMonitor(),
            toastCenter: ToastCenter()))

        for request in ProcessInfo.processInfo.environment["FABLE_LIVE_PROBE"]!.split(separator: ",") {
            let parts = request.split(separator: "+")
            let backend = try #require(GraphicsBackend(rawValue: String(parts[0])), "unknown backend \(parts[0])")

            let canary = await launcher.runCanary(backend: backend, pins: [:])
            print("LIVE canary \(backend.rawValue) engine=\(canary.engineKey ?? "-") \(String(format: "%.1f", canary.durationSeconds))s")
            for rung in canary.rungs {
                print("LIVE   \(rung.id.rawValue)=\(rung.status.rawValue) \(rung.detail ?? "")")
            }
            #expect(canary.allPassed, "canary on \(backend.rawValue): \(canary.firstProblem.map { "\($0.id.rawValue) \($0.detail ?? "")" } ?? "")")

            if parts.contains("bench") {
                let bench = await launcher.runBenchmark(backend: backend, pins: [:])
                print("LIVE bench \(backend.rawValue) \(String(format: "%.1f", bench.durationSeconds))s presented=\(bench.framePresented.rawValue) failure=\(bench.failure ?? "-")")
                for phase in bench.phases {
                    print("LIVE   \(phase.id.rawValue) median=\(phase.medianMs) p99=\(phase.p99Ms) frames=\(phase.frames)")
                }
                #expect(bench.isComplete)
                #expect(bench.framePresented == .passed)
            }
        }
        // Nothing left behind.
        let leftovers = (try? FileManager.default.contentsOfDirectory(
            atPath: AppPaths.applicationSupport.appending(path: "Canary").path)) ?? []
        #expect(leftovers.isEmpty)
    }
}
