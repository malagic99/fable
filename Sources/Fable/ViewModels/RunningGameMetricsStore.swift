import Foundation

/// Polls ProcessMetrics for each running game and republishes the
/// latest sample. Wired to GameLauncher via a closure callback so the
/// launcher doesn't grow a metrics dependency.
@MainActor
final class RunningGameMetricsStore: ObservableObject {
    /// Latest sample per running game. Cleared on exit.
    @Published private(set) var metrics: [Game.ID: ProcessMetrics] = [:]

    /// How often each running game's process tree is sampled. ps takes
    /// ~5–10 ms on a typical system; 2 s is invisible in the UI.
    static let pollInterval: Duration = .seconds(2)

    private var tasks: [Game.ID: Task<Void, Never>] = [:]

    /// Starts polling `pid` and writes samples into `metrics[id]`.
    /// Calling with the same id replaces any in-flight polling task.
    func startTracking(_ id: Game.ID, rootPID: Int32) {
        tasks[id]?.cancel()
        metrics[id] = .zero
        let interval = Self.pollInterval
        tasks[id] = Task { [weak self] in
            while !Task.isCancelled {
                let sample = (try? await ProcessMetricsSampler.sample(root: rootPID)) ?? .zero
                self?.metrics[id] = sample
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopTracking(_ id: Game.ID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        metrics[id] = nil
    }
}
