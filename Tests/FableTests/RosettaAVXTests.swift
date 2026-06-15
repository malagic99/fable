import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct RosettaAVXTests {
    private func makeWineManager() -> WineManager {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "AVXTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let cm = ComponentManager(
            componentsDirectory: root.appending(path: "Components"),
            downloadsDirectory: root.appending(path: "Downloads")
        )
        return WineManager(componentManager: cm, catalog: VersionCatalog(components: [:]))
    }

    @Test
    func prefixEnvironmentAdvertisesAVXToRosetta() {
        let wine = makeWineManager()
        let env = wine.environment(forPrefix: URL(filePath: "/tmp/prefix"))
        // The single free knob that unblocks AVX-gated games under
        // Rosetta — must be present on the base env every launch path
        // (game, installer, prefix-create) builds on.
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")
    }

    @Test
    func avxFlagSurvivesIntoGptkLaunchEnvironment() {
        // GPTK/Sikarugir/CrossOver merge their overrides ON TOP of the
        // base prefix env, so the AVX flag must still be there after the
        // merge. Simulate the merge the launcher does.
        let wine = makeWineManager()
        var env = wine.environment(forPrefix: URL(filePath: "/tmp/prefix"))
        env.merge(GPTKManager.launchEnvironment(baseOverrides: "mscoree=")) { _, new in new }
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1", "GPTK merge must not drop the AVX flag")
    }

    @Test
    func avxFlagSurvivesIntoSikarugirLaunchEnvironment() {
        let wine = makeWineManager()
        var env = wine.environment(forPrefix: URL(filePath: "/tmp/prefix"))
        env.merge(SikarugirManager.launchEnvironment(baseOverrides: "mscoree=")) { _, new in new }
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")
    }
}
