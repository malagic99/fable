import AppKit

/// Polls ProcessMetrics for each running game and republishes the
/// latest sample. Wired to GameLauncher via a closure callback so the
/// launcher doesn't grow a metrics dependency.
@MainActor
final class RunningGameMetricsStore: ObservableObject {
    /// Latest sample per running game. Cleared on exit.
    @Published private(set) var metrics: [Game.ID: ProcessMetrics] = [:]

    private var tasks: [Game.ID: Task<Void, Never>] = [:]

    /// Starts polling `pid` and writes samples into `metrics[id]`.
    /// Calling with the same id replaces any in-flight polling task.
    func startTracking(_ id: Game.ID, rootPID: Int32) {
        tasks[id]?.cancel()
        metrics[id] = .zero
        tasks[id] = Task { [weak self] in
            while !Task.isCancelled {
                // Skip the `ps` shell-out while you're in the game (Fable in the
                // background) — the readout isn't on screen, and forking a
                // process beside the game every few seconds is a needless hitch.
                if Stability.shouldSampleMetrics(fableActive: NSApplication.shared.isActive) {
                    let sample = (try? await ProcessMetricsSampler.sample(root: rootPID)) ?? .zero
                    self?.metrics[id] = sample
                }
                try? await Task.sleep(for: Stability.metricsInterval)
            }
        }
    }

    func stopTracking(_ id: Game.ID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        metrics[id] = nil
    }
}
