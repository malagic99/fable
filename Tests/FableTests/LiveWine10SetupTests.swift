import Foundation
import Testing
@testable import Fable

/// Opt-in: sets up the Wine 10 engine from the catalog into an empty folder,
/// the shared way or (FABLE_LIVE_ENGINE_LEGACY=1) the legacy way, then runs
/// the engine test and the benchmark on that fresh engine.
/// `FABLE_LIVE_W10_DIR=/empty/dir swift test --filter LiveWine10Setup`
@Suite("Live Wine 10 setup", .enabled(if: ProcessInfo.processInfo.environment["FABLE_LIVE_W10_DIR"] != nil))
struct LiveWine10SetupTests {
    @Test @MainActor
    func setUpAndProbeAFreshEngine() async throws {
        let env = ProcessInfo.processInfo.environment
        let root = URL(filePath: env["FABLE_LIVE_W10_DIR"]!)
        let componentsDir = root.appending(path: "Components", directoryHint: .isDirectory)
        let downloadsDir = root.appending(path: "Downloads", directoryHint: .isDirectory)
        for dir in [componentsDir, downloadsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let catalog = try VersionCatalog.loadBundled()
        let components = ComponentManager(componentsDirectory: componentsDir, downloadsDirectory: downloadsDir)
        let sikarugir = SikarugirManager(componentManager: components, catalog: catalog)
        sikarugir.useLegacySetup = env["FABLE_LIVE_ENGINE_LEGACY"] != nil
        try await sikarugir.ensureInstalled()
        let engine = try #require(components.installedDirectory(for: SikarugirManager.componentID))
        print("LIVE setup=\(sikarugir.useLegacySetup ? "legacy" : "shared") engine=\(engine.path)")

        let launcher = GameLauncher()
        launcher.configure(.init(
            bottleManager: BottleManager(), componentManager: components,
            wineManager: WineManager(componentManager: components, catalog: catalog),
            gptkManager: GPTKManager(componentManager: components, catalog: catalog),
            crossOverManager: CrossOverManager(), sikarugirManager: sikarugir,
            sikarugir11Manager: Sikarugir11Manager(componentManager: components, catalog: catalog),
            triggerController: DualSenseTriggerController(), activityMonitor: ActivityMonitor(),
            toastCenter: ToastCenter()))
        let canary = await launcher.runCanary(backend: .sikarugir, pins: [:])
        print("LIVE canary \(canary.rungs.map { "\($0.id.rawValue)=\($0.status.rawValue)" }.joined(separator: " "))")
        let bench = await launcher.runBenchmark(backend: .sikarugir, pins: [:])
        print("LIVE bench presented=\(bench.framePresented.rawValue) " + bench.phases.map { "\($0.id.rawValue)=\($0.medianMs)ms" }.joined(separator: " ") + " failure=\(bench.failure ?? "-")")
        #expect(canary.allPassed)
        #expect(bench.isComplete)
    }
}
