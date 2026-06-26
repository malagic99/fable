import Foundation
import Testing
@testable import Fable

/// Locks the centralized Wine environment quirks so a refactor or an upgrade
/// can't silently drop a hard-won fix.
@MainActor
@Suite struct WineEnvTests {

    @Test
    func baseCarriesEveryAlwaysOnFix() {
        let env = WineEnv.base(prefix: URL(filePath: "/tmp/prefix"))
        #expect(env[WineEnv.prefix] == "/tmp/prefix")
        #expect(env[WineEnv.debug] == WineEnv.debugSilent)          // silent during setup
        #expect(env[WineEnv.dllOverrides] == "mscoree,mshtml=")     // skip mono/gecko dialogs
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")                // AVX int3 fix
        #expect(env["SDL_JOYSTICK_HIDAPI_PS4"] == "1")              // PlayStation pads
        #expect(env["SDL_JOYSTICK_HIDAPI_PS5"] == "1")
    }

    @Test
    func diagnosticDebugKeepsErrorsButSilencesMsyncFlood() {
        // The exact value matters: real errors stay, the per-frame msync
        // channel is off (the 25 GB-log fix).
        #expect(WineEnv.debugDiagnostic == "fixme-all,-msync")

        let flipped = WineEnv.withDiagnosticDebug(WineEnv.base(prefix: URL(filePath: "/tmp/p")))
        #expect(flipped[WineEnv.debug] == WineEnv.debugDiagnostic)
        // Only the debug profile changes — every other base fix survives.
        #expect(flipped["ROSETTA_ADVERTISE_AVX"] == "1")
        #expect(flipped[WineEnv.prefix] == "/tmp/p")
    }

    @Test
    func wineManagerEnvironmentMatchesTheBase() {
        // The manager is now just a thin wrapper over WineEnv.base — keep it so.
        let prefix = URL(filePath: "/tmp/bottle/prefix")
        let manager = WineManager(componentManager: ComponentManager(), catalog: VersionCatalog(components: [:]))
        #expect(manager.environment(forPrefix: prefix) == WineEnv.base(prefix: prefix))
    }
}
