import Foundation

/// Watches the Mac's thermal state — the "slips after an hour" culprit on a
/// sustained session is usually the SoC throttling, not the game.
///
/// A running Wine game reads its frame cap from the environment at launch, so
/// Fable can't lower it on a live process. The honest move is therefore to
/// *detect* sustained throttling and nudge the user toward Rock Solid (and a
/// lower cap next launch) rather than silently re-cap something we can't.
///
/// `onThrottleOnset` is edge-triggered — it fires once when the state escalates
/// into throttling, not repeatedly — so the nudge never spams.
@MainActor
final class ThermalMonitor: ObservableObject {
    @Published private(set) var state: ProcessInfo.ThermalState

    /// Fired when the thermal state escalates into throttling (serious or
    /// critical) from a cooler state. Wired in the app to nudge toward Rock
    /// Solid when a game is actually running.
    var onThrottleOnset: (() -> Void)?

    private let notificationCenter: NotificationCenter
    // Touched from the nonisolated deinit; NotificationCenter removal is
    // thread-safe, so unsafe isolation is fine here.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = .default,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.notificationCenter = notificationCenter
        state = processInfo.thermalState
        observer = notificationCenter.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            let current = ProcessInfo.processInfo.thermalState
            Task { @MainActor in self?.update(to: current) }
        }
    }

    deinit {
        if let observer { notificationCenter.removeObserver(observer) }
    }

    /// Applies a new thermal state, firing `onThrottleOnset` only on the
    /// cool→throttling edge. Exposed for the app wiring and for tests.
    func update(to newState: ProcessInfo.ThermalState) {
        let escalated = Self.isThrottling(newState) && !Self.isThrottling(state)
        state = newState
        if escalated { onThrottleOnset?() }
    }

    /// Serious or critical means the CPU/GPU is actively being throttled.
    static func isThrottling(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }
}
