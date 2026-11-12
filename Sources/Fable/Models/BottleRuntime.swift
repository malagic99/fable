import Foundation

/// Which engine versions a bottle runs on — the first slice of the runtime
/// integrity work in docs/ROADMAP.md ("Long-term direction").
///
/// Before this existed every bottle used the newest installed version of its
/// backend's engine, so installing an engine update silently moved every
/// bottle onto it — including ones that worked. Wine upgrades a prefix one way
/// the first time a newer build touches it, so that move can't be undone.
///
/// A bottle is stamped with the versions it actually ran on at its first
/// launch, and keeps them until the user moves it (see `BottleManager
/// .moveToNewestEngines`). Pins are keyed by component id, so a bottle that
/// switches backend and back keeps both pins.
struct BottleRuntime: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    enum Policy: String, Codable, Sendable {
        /// Stay on the stamped versions until the user moves the bottle.
        case pinned
        /// Always run the newest installed version (the pre-pinning behavior).
        case followNewest
    }

    /// What one launch actually ran on — evidence, not a setting.
    struct Launch: Codable, Hashable, Sendable {
        var backend: GraphicsBackend
        /// Component id → version that was resolved for the launch.
        var versions: [String: String]
        var date: Date
    }

    /// Recorded as evidence but never pinned. Sikarugir's Wine 11 template
    /// (its D3DMetal renderer) is assembled *into* the engine folder, so a
    /// template update re-assembles that folder in place — a pin on it could
    /// not hold, and would only raise false "not installed" warnings.
    static let informationalComponentIDs: Set<String> = [Sikarugir11Manager.templateComponentID]

    var schemaVersion: Int
    var policy: Policy
    /// Component id → installed version folder, e.g.
    /// `"sikarugir": "WS12WineSikarugir10.0_4"`.
    var pins: [String: String]
    var lastLaunch: Launch?

    init(
        policy: Policy = .pinned,
        pins: [String: String] = [:],
        lastLaunch: Launch? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.policy = policy
        self.pins = pins
        self.lastLaunch = lastLaunch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        // An unknown policy from a newer Fable reads as pinned: the cautious one.
        let rawPolicy = try container.decodeIfPresent(String.self, forKey: .policy)
        policy = rawPolicy.flatMap(Policy.init(rawValue:)) ?? .pinned
        pins = try container.decodeIfPresent([String: String].self, forKey: .pins) ?? [:]
        lastLaunch = try? container.decodeIfPresent(Launch.self, forKey: .lastLaunch)
    }

    /// The pins to apply while resolving engines: none when following newest.
    var activePins: [String: String] {
        policy == .pinned ? pins : [:]
    }

    /// The record after a launch that resolved `versions` on `backend`.
    /// Pins the versions a pinned bottle hadn't pinned yet (its first launch,
    /// or the first on a newly chosen backend) and never moves an existing
    /// pin — a pinned version that was missing on disk stays pinned, so it is
    /// used again once it's back.
    func recordingLaunch(backend: GraphicsBackend, versions: [String: String], at date: Date = .now) -> BottleRuntime {
        var next = self
        if policy == .pinned {
            next.pins.merge(versions.filter { !Self.informationalComponentIDs.contains($0.key) }) { existing, _ in existing }
        }
        next.lastLaunch = Launch(backend: backend, versions: versions, date: date)
        return next
    }

    /// Pinned components whose pinned version differs from what a launch used —
    /// the pinned version wasn't on disk and the newest was used instead.
    func missingPins(resolved versions: [String: String]) -> [String: (pinned: String, used: String)] {
        var result: [String: (pinned: String, used: String)] = [:]
        for (id, used) in versions where !Self.informationalComponentIDs.contains(id) {
            if let pinned = activePins[id], pinned != used {
                result[id] = (pinned, used)
            }
        }
        return result
    }
}

/// The pins in effect while resolving engine directories. Task-local so the
/// managers' existing resolution (`ComponentManager.installedDirectory(for:)`)
/// honors a bottle's pins without threading a version through every call.
/// Set it with `EnginePins.$current.withValue(bottle.enginePins) { … }`.
enum EnginePins {
    @TaskLocal static var current: [String: String] = [:]

    /// The pins of the bottle that owns `prefix` (`Bottles/<id>/prefix`, with
    /// `bottle.json` beside it), read from disk. Lets every helper that runs
    /// Wine on a prefix — winecfg, winetricks, installers, registry writes —
    /// use the bottle's own engine without each caller passing it. Empty for a
    /// prefix with no readable bottle record (a brand-new bottle).
    static func forPrefix(_ prefix: URL) -> [String: String] {
        let record = prefix.deletingLastPathComponent().appending(path: "bottle.json")
        guard let data = try? Data(contentsOf: record),
              let bottle = try? JSONDecoder().decode(Bottle.self, from: data)
        else { return [:] }
        return bottle.enginePins
    }
}

extension Bottle {
    /// The pins to apply for this bottle; empty for an unstamped bottle or
    /// one that follows the newest engines.
    var enginePins: [String: String] {
        runtime?.activePins ?? [:]
    }
}

extension GraphicsBackend {
    /// The Fable-managed components a launch on this backend resolves.
    /// CrossOver is the user's own install and isn't Fable's to pin. DXMT is
    /// copied into the prefix when enabled, so its version lives there.
    var engineComponentIDs: [String] {
        switch self {
        case .off, .dxmt, .dxvk: [WineManager.componentID]
        case .gptk: [GPTKManager.componentID]
        case .sikarugir: [SikarugirManager.componentID]
        case .sikarugir11: [Sikarugir11Manager.engineComponentID]
        case .crossover: []
        }
    }
}
