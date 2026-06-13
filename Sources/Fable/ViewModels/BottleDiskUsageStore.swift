import Foundation

/// App-wide cache of per-bottle prefix sizes. Scans are async and
/// cancellable. UI reads the cached value if available; views that
/// care (BottleDetailView) trigger a scan on appear.
@MainActor
final class BottleDiskUsageStore: ObservableObject {
    /// Cached size in bytes per bottle id. Absent = not yet scanned.
    @Published private(set) var sizes: [Bottle.ID: Int64] = [:]
    /// Bottle ids currently being scanned.
    @Published private(set) var scanning: Set<Bottle.ID> = []

    private var tasks: [Bottle.ID: Task<Void, Never>] = [:]

    func size(for id: Bottle.ID) -> Int64? { sizes[id] }
    func isScanning(_ id: Bottle.ID) -> Bool { scanning.contains(id) }

    /// Recomputes the cached size. Coalesces concurrent requests so the
    /// same prefix isn't enumerated twice.
    func scan(_ bottle: Bottle, manager: BottleManager) {
        if scanning.contains(bottle.id) { return }
        scanning.insert(bottle.id)

        let prefix = manager.prefixDirectory(for: bottle)
        let id = bottle.id
        tasks[id] = Task.detached(priority: .utility) { [weak self] in
            let bytes = (try? BottleDiskUsage.size(of: prefix)) ?? 0
            await self?.applyResult(id: id, bytes: bytes)
        }
    }

    /// Cleans temp files in the bottle's prefix and refreshes the
    /// cached size from the post-clean state. Returns bytes freed.
    @discardableResult
    func cleanTempFiles(in bottle: Bottle, manager: BottleManager) async throws -> Int64 {
        let prefix = manager.prefixDirectory(for: bottle)
        let id = bottle.id
        let freed = try await Task.detached(priority: .utility) {
            try BottleDiskUsage.cleanTempFiles(in: prefix)
        }.value
        if let current = sizes[id] {
            sizes[id] = max(0, current - freed)
        }
        // Trigger a fresh scan to reconcile in case other writes happened.
        scan(bottle, manager: manager)
        return freed
    }

    private func applyResult(id: Bottle.ID, bytes: Int64) {
        sizes[id] = bytes
        scanning.remove(id)
        tasks[id] = nil
    }
}
