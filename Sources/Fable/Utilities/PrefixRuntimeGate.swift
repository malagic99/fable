import Foundation

/// One live Wine build per prefix — THE invariant behind every
/// `wine client error: version mismatch NNN/NNN` failure. A prefix happily
/// alternates between Wine builds over time (games on Sikarugir's wine-10,
/// installers on the default 11.x), but two builds can't talk to one
/// wineserver concurrently: the second client fails, installs stall, and
/// the errors point everywhere except the real cause.
///
/// The gate serializes the switch: refuse while the bottle has live Wine
/// processes (killing them would eat someone's session), otherwise drain
/// every *other* runtime's wineserver so the caller starts fresh. Draining
/// a runtime with no server is a cheap no-op, so callers pass all of them.
enum PrefixRuntimeGate {
    struct BottleBusyError: LocalizedError {
        let bottleName: String
        var errorDescription: String? {
            L10n.string("gate.bottle_busy", bottleName)
        }
    }

    /// Ensures the caller's runtime can own `prefix`. `foreignWineservers`
    /// is every runtime's wineserver EXCEPT the caller's; `hasLiveProcesses`
    /// is the caller's ps-informed verdict (games running → we never kill).
    static func ensureExclusive(
        prefix: URL,
        bottleName: String,
        foreignWineservers: [URL],
        hasLiveProcesses: Bool
    ) async throws {
        guard !hasLiveProcesses else {
            throw BottleBusyError(bottleName: bottleName)
        }
        for wineserver in foreignWineservers {
            // -k kills the prefix's server if this build owns one; -w waits
            // for it to fully exit so the successor can't race the socket.
            // Both no-op fast when this runtime has no server here.
            _ = try? await ProcessRunner.run(
                wineserver, arguments: ["-k"],
                environment: ["WINEPREFIX": prefix.path]
            )
            _ = try? await ProcessRunner.run(
                wineserver, arguments: ["-w"],
                environment: ["WINEPREFIX": prefix.path]
            )
        }
    }

    /// The busy verdict used with the gate: any process whose command line
    /// carries the bottle's identity. (Steam-launched children don't carry
    /// it — but their Steam does, and Fable-launched games are checked by
    /// the caller against its own running table.)
    static func hasProcesses(commands: [String], bottleID: UUID) -> Bool {
        let token = bottleID.uuidString.lowercased()
        return commands.contains { $0.lowercased().contains(token) }
    }
}
