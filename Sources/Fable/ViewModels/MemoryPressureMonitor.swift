import Foundation

/// Watches macOS memory pressure and warns *before* the out-of-memory crash —
/// the memory analogue of `ThermalMonitor`.
///
/// On Apple Silicon RAM and VRAM are one pool, so a texture-hungry AAA game
/// can walk the whole Mac into a wired-memory wall. Fable's Doctor only sees
/// `E_OUTOFMEMORY` *after* the crash, and the Memory Diet is a next-launch
/// fix; this is the *live* "close some apps / drop textures now" nudge that
/// lands first.
///
/// Uses the kernel's own memory-pressure signal (`DispatchSource`) — event-
/// driven and cheap, no polling. Edge-triggered like `ThermalMonitor`: fires
/// once on the normal→pressured onset, so the nudge never spams.
@MainActor
final class MemoryPressureMonitor: ObservableObject {
    @Published private(set) var isUnderPressure = false

    /// Fired when pressure escalates from normal into warning/critical. Wired
    /// in the app to nudge only while a game is actually running.
    var onPressureOnset: (() -> Void)?

    // Cancelled from the nonisolated deinit; DispatchSource cancel is
    // thread-safe, so unsafe isolation is fine.
    nonisolated(unsafe) private var source: DispatchSourceMemoryPressure?

    init(start: Bool = true) {
        guard start else { return }
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main
        )
        source = src
        src.setEventHandler { [weak self, weak src] in
            guard let data = src?.data else { return }
            Task { @MainActor in self?.handle(data) }
        }
        src.resume()
    }

    deinit { source?.cancel() }

    /// Applies a pressure event, firing `onPressureOnset` only on the
    /// normal→pressured edge. Exposed for the app wiring and for tests.
    func handle(_ event: DispatchSource.MemoryPressureEvent) {
        let pressured = event.contains(.warning) || event.contains(.critical)
        let escalated = pressured && !isUnderPressure
        isUnderPressure = pressured
        if escalated { onPressureOnset?() }
    }
}
