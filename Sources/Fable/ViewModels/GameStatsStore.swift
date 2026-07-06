import Foundation

/// Per-game history: accumulated playtime, when it was last played, and the
/// user's freeform notes. Keyed by the game's stable UUID (wine games and
/// native games alike), persisted as one JSON file.
///
/// Honesty note: playtime accumulates for sessions Fable itself launched and
/// tracked (launch → exit). A game started from inside Steam still gets its
/// "last played" touched when detected, but its duration isn't guessed.
@MainActor
final class GameStatsStore: ObservableObject {
    struct Stats: Codable, Equatable {
        var totalSeconds: Double = 0
        var lastPlayedAt: Date?
        var notes: String = ""
        /// Crash signature per backend tried (backend rawValue → signature,
        /// e.g. "sikarugir" → "int3"). Optional so pre-existing stats files
        /// decode unchanged. Feeds the cross-backend "it's the game, not the
        /// backend" verdict — see GameDoctor.crossBackendFinding.
        var crashSignatures: [String: String]?
    }

    @Published private(set) var stats: [UUID: Stats] = [:]
    private var activeSessions: [UUID: Date] = [:]
    private let fileURL: URL

    init(fileURL: URL = AppPaths.applicationSupport.appending(path: "game-stats.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([UUID: Stats].self, from: data) {
            stats = loaded
        }
    }

    // MARK: Sessions

    /// A Fable-launched game started running.
    func sessionStarted(_ id: UUID, at date: Date = .now) {
        activeSessions[id] = date
        stats[id, default: Stats()].lastPlayedAt = date
        save()
    }

    /// It exited — fold the session into the total.
    func sessionEnded(_ id: UUID, at date: Date = .now) {
        guard let started = activeSessions.removeValue(forKey: id) else { return }
        let seconds = max(0, date.timeIntervalSince(started))
        stats[id, default: Stats()].totalSeconds += seconds
        stats[id]?.lastPlayedAt = date
        save()
    }

    /// Marks "played now" without a duration — native launches hand off to
    /// the platform (Steam/LaunchServices), so only the moment is known.
    func touch(_ id: UUID, at date: Date = .now) {
        stats[id, default: Stats()].lastPlayedAt = date
        save()
    }

    // MARK: Crash correlation

    /// Records that this game crashed with `signature` on `backend`.
    /// A later clean exit on that backend clears it (the game evidently
    /// runs now — config or game update fixed it).
    func recordCrash(_ id: UUID, backend: String, signature: String?) {
        var signatures = stats[id]?.crashSignatures ?? [:]
        if let signature {
            signatures[backend] = signature
        } else {
            signatures[backend] = nil
        }
        stats[id, default: Stats()].crashSignatures = signatures.isEmpty ? nil : signatures
        save()
    }

    /// The signature seen on two or more DIFFERENT backends, if any —
    /// the tell that the crash is the game's own doing.
    func crossBackendCrash(_ id: UUID) -> (signature: String, backends: [String])? {
        guard let signatures = stats[id]?.crashSignatures else { return nil }
        let bySignature = Dictionary(grouping: signatures.keys, by: { signatures[$0]! })
        guard let (signature, backends) = bySignature.first(where: { $0.value.count >= 2 }) else {
            return nil
        }
        return (signature, backends.sorted())
    }

    // MARK: Notes

    func setNotes(_ notes: String, for id: UUID) {
        stats[id, default: Stats()].notes = notes
        save()
    }

    func notes(for id: UUID) -> String {
        stats[id]?.notes ?? ""
    }

    // MARK: Display

    /// "12 min", "3.5 h", "26 h" — playtime at the precision that matters.
    nonisolated static func formattedPlaytime(seconds: Double) -> String? {
        guard seconds >= 60 else { return nil }  // under a minute isn't playtime
        let minutes = seconds / 60
        if minutes < 60 { return "\(Int(minutes)) min" }
        let hours = minutes / 60
        if hours < 10 { return String(format: "%.1f h", hours) }
        return "\(Int(hours)) h"
    }

    // MARK: Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(stats) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
