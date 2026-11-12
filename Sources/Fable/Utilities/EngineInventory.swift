import Foundation

/// What engine versions are on disk relative to what bottles are pinned to:
/// updates a pinned bottle could move to, and versions nothing uses any more.
/// Pure over a `ComponentManager` and the bottle list, so it's unit-tested
/// against a temp directory.
@MainActor
enum EngineInventory {
    /// Components a bottle can be pinned to (see `GraphicsBackend.engineComponentIDs`).
    static let pinnableComponentIDs = [
        WineManager.componentID,
        GPTKManager.componentID,
        SikarugirManager.componentID,
        Sikarugir11Manager.engineComponentID,
        Sikarugir11Manager.templateComponentID,
    ]

    struct Update: Hashable, Sendable {
        let componentID: String
        let pinned: String
        let newest: String
    }

    struct Unused: Hashable, Sendable {
        let componentID: String
        let version: String
        let directory: URL
    }

    /// Pinned components of `bottle` with a newer version installed.
    static func updates(for bottle: Bottle, componentManager: ComponentManager) -> [Update] {
        guard let runtime = bottle.runtime, runtime.policy == .pinned else { return [] }
        return runtime.pins.keys.sorted().compactMap { id in
            guard pinnableComponentIDs.contains(id),
                  let pinned = runtime.pins[id],
                  let newest = componentManager.newestInstalledDirectory(for: id)?.lastPathComponent,
                  VersionCompare.isNewer(newest, than: pinned)
            else { return nil }
            return Update(componentID: id, pinned: pinned, newest: newest)
        }
    }

    /// Installed versions no bottle is pinned to or last ran on, that aren't
    /// the newest and aren't what this Fable's catalog names (`keep`). Pins
    /// count whatever a bottle's policy, so switching a bottle back to pinned
    /// never finds its engine gone; last launches count because a running
    /// game may be on a version nothing pins (a bottle that follows the
    /// newest, or a launch that fell back from a missing pin). Only the
    /// pinnable engines are considered.
    static func unusedVersions(
        bottles: [Bottle],
        componentManager: ComponentManager,
        keep: [String: String]
    ) -> [Unused] {
        var result: [Unused] = []
        for id in pinnableComponentIDs {
            let versions = componentManager.installedVersions(for: id)
            guard let newest = componentManager.newestInstalledDirectory(for: id)?.lastPathComponent else { continue }
            let inUse = Set(bottles.flatMap { bottle in
                [bottle.runtime?.pins[id], bottle.runtime?.lastLaunch?.versions[id]].compactMap { $0 }
            })
            for version in versions.sorted()
            where version != newest && version != keep[id] && !inUse.contains(version) {
                guard let dir = componentManager.installedDirectory(for: id, version: version) else { continue }
                result.append(Unused(componentID: id, version: version, directory: dir))
            }
        }
        return result
    }

    /// Bytes on disk under `directory` (allocated size, so APFS clones and
    /// sparse files count what they really take).
    nonisolated static func diskSize(of directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: Array(keys)
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
