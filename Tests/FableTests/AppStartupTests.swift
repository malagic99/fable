import Testing
@testable import Fable

@Suite("App start-up")
struct AppStartupTests {
    /// File → New Window ran the whole start-up again, starting another
    /// never-ending Steam scan per window (code-quality check 2026-11-20).
    @Test @MainActor
    func startUpIsClaimedOncePerRun() {
        // Another test, or the test host, may already have claimed it; what
        // matters is that a second claim is always refused.
        _ = FableApp.AppStartup.claim()
        #expect(!FableApp.AppStartup.claim())
        #expect(!FableApp.AppStartup.claim())
    }
}
