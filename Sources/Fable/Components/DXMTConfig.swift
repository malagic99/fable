import Foundation

/// Per-bottle DXMT settings, persisted in bottle.json.
struct DXMTConfig: Codable, Hashable, Sendable {
    enum LogLevel: String, Codable, CaseIterable, Identifiable, Sendable {
        case none
        case error
        case warn
        case info
        case debug

        var id: String { rawValue }
    }

    /// Cap the game's frame rate (nil = uncapped).
    var maxFrameRate: Int?
    var logLevel: LogLevel = .error

    /// Environment variables understood by DXMT's d3d11/dxgi.
    func environment(logFile: URL?) -> [String: String] {
        var env: [String: String] = [:]
        var config: [String] = []
        if let maxFrameRate, maxFrameRate > 0 {
            config.append("dxgi.maxFrameRate=\(maxFrameRate);")
        }
        if !config.isEmpty {
            env["DXMT_CONFIG"] = config.joined()
        }
        env["DXMT_LOG_LEVEL"] = logLevel.rawValue
        if let logFile, logLevel != .none {
            env["DXMT_LOG_PATH"] = logFile.deletingLastPathComponent().path
        }
        return env
    }
}
