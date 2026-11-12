import SwiftUI

/// The outcome of one rung of the validation ladder. The vocabulary is
/// FRICL's, and the rule that goes with it: **skipped is never passed.**
enum CanaryStatus: String, Codable, Sendable {
    /// The test ran and met its condition.
    case passed
    /// The test ran and did not.
    case failed
    /// Not run, because an earlier rung stopped the run.
    case skipped
    /// This engine or backend can't be tested this way.
    case unsupported
    /// It ran, but the outcome can't be trusted either way.
    case inconclusive
}

/// One rung: what was asked, and what happened.
struct CanaryRung: Codable, Equatable, Hashable, Sendable {
    enum ID: String, Codable, CaseIterable, Sendable {
        /// Wine started, made a prefix, and ran a Windows program.
        case windowsProgram
        /// The Direct3D DLLs loaded.
        case rendererLoads
        /// A D3D12 device and command queue were created, cold.
        case direct3D12
        /// A graphics adapter was reported.
        case adapter
        /// A D3D11 device was created.
        case direct3D11
    }

    var id: ID
    var status: CanaryStatus
    /// The fact behind the status: an adapter name, an error code, the last
    /// thing the engine printed before it stopped.
    var detail: String?
}

/// What the canary found on one engine, kept as evidence. It says what the
/// engine can do on this Mac; it never says a game works.
struct CanaryResult: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var backend: GraphicsBackend
    /// ``BottleRuntime/engineKey(for:)`` of the engine tested.
    var engineKey: String?
    /// The engine's manifest id at the time, so a result can be tied to the
    /// exact files it was run on.
    var manifestID: String?
    var date: Date
    var durationSeconds: Double
    var rungs: [CanaryRung]
    var fableVersion: String?

    /// True when every rung passed. A skipped, unsupported or inconclusive
    /// rung keeps this false: nothing unproven counts.
    var allPassed: Bool { !rungs.isEmpty && rungs.allSatisfy { $0.status == .passed } }
    /// The first rung that did not pass.
    var firstProblem: CanaryRung? { rungs.first { $0.status != .passed } }
    var hasFailure: Bool { rungs.contains { $0.status == .failed } }
}

enum EngineCanary {
    /// How the canary process ended.
    enum Exit: Equatable, Sendable {
        case exited(Int32)
        case timedOut
        case couldNotStart(String)
    }

    /// Backends whose engine the canary can exercise as Fable launches it.
    /// DXMT and DXVK put their DLLs in the bottle, not the engine, so a
    /// throwaway prefix wouldn't test what a game gets; CrossOver is the
    /// user's own install. Those are reported unsupported, not passed.
    static func supports(_ backend: GraphicsBackend) -> Bool {
        switch backend {
        case .sikarugir, .sikarugir11, .gptk: true
        case .off, .dxmt, .dxvk, .crossover: false
        }
    }

    static let programName = "fable-canary64.exe"
    static let resultName = "result.txt"
    /// A cold run creates a prefix first, which is most of the time.
    static let timeoutSeconds: Double = 150

    /// The canary program shipped in the app's resources.
    static var program: URL? {
        Bundle.fableResources.url(forResource: "fable-canary64", withExtension: "exe", subdirectory: "canary")
    }

    static func unsupportedResult(backend: GraphicsBackend, engineKey: String?, at date: Date = .now) -> CanaryResult {
        CanaryResult(
            backend: backend, engineKey: engineKey, manifestID: nil, date: date, durationSeconds: 0,
            rungs: CanaryRung.ID.allCases.map { CanaryRung(id: $0, status: .unsupported, detail: nil) },
            fableVersion: appVersion)
    }

    static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    // MARK: Reading the program's output

    /// Turns what the canary wrote into rungs. Pure, so every way a run can
    /// end is tested without Wine.
    ///
    /// The program flushes a line per fact, so after a crash or a hang the
    /// lines stop at the rung that was in progress: that rung failed, and the
    /// ones after it were never reached — skipped, not passed.
    static func rungs(output: String, exit: Exit, errorTail: String) -> [CanaryRung] {
        var facts: [String: String] = [:]
        var crash: String?
        for line in output.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            if key == "crash" { crash = value } else { facts[key] = value }
        }
        let finished = output.split(whereSeparator: \.isNewline).contains { $0 == "done" }

        /// Why the run stopped, for the rung it stopped in.
        let stopReason: String = {
            if let crash { return "crashed (\(crash.split(separator: " ").first ?? ""))" }
            let tail = errorTail.trimmingCharacters(in: .whitespacesAndNewlines)
            switch exit {
            case .timedOut: return tail.isEmpty ? "stopped responding" : "stopped responding: \(tail)"
            case .couldNotStart(let reason): return reason
            case .exited(let code): return tail.isEmpty ? "exited with code \(code)" : tail
            }
        }()

        var result: [CanaryRung] = []
        var stopped = false

        /// Appends a rung from the facts it needs. `keys` are in the order
        /// the program writes them; the first one missing is where it stopped.
        func rung(_ id: CanaryRung.ID, keys: [String], detail: (([String: String]) -> String?)? = nil) {
            if stopped {
                result.append(CanaryRung(id: id, status: .skipped, detail: nil))
                return
            }
            for key in keys {
                guard let value = facts[key] else {
                    // Not written: the run ended here, unless it ran to the end
                    // and simply never reported this (a program/runner mismatch).
                    result.append(CanaryRung(
                        id: id, status: finished ? .inconclusive : .failed,
                        detail: finished ? "no result reported" : stopReason))
                    stopped = !finished
                    return
                }
                if value.hasPrefix("skipped") {
                    result.append(CanaryRung(id: id, status: .skipped, detail: nil))
                    return
                }
                guard value.hasPrefix("ok") else {
                    result.append(CanaryRung(id: id, status: .failed, detail: failureDetail(key: key, value: value)))
                    return
                }
            }
            result.append(CanaryRung(id: id, status: .passed, detail: detail?(facts)))
        }

        rung(.windowsProgram, keys: ["pe"])
        rung(.rendererLoads, keys: ["dll.d3d12", "dll.dxgi", "dll.d3d11"])
        rung(.direct3D12, keys: ["d3d12.device", "d3d12.queue"])
        rung(.adapter, keys: ["adapter"]) { facts in
            // "ok vendor=… device=… vram_mb=… name=AMD Compatibility Mode"
            facts["adapter"]?.range(of: "name=").map { String(facts["adapter"]![$0.upperBound...]) }
        }
        rung(.direct3D11, keys: ["d3d11.device"])
        return result
    }

    /// "d3d12.device=failed hr=0x887a0004" → "D3D12 device: error 0x887a0004".
    static func failureDetail(key: String, value: String) -> String {
        let code = value.split(separator: " ").first { $0.hasPrefix("hr=") || $0.hasPrefix("error=") }
            .map { String($0.split(separator: "=").last ?? "") }
        let what: String = switch key {
        case "dll.d3d12": "d3d12.dll did not load"
        case "dll.dxgi": "dxgi.dll did not load"
        case "dll.d3d11": "d3d11.dll did not load"
        case "d3d12.device": "no D3D12 device"
        case "d3d12.queue": "no D3D12 command queue"
        case "d3d11.device": "no D3D11 device"
        case "adapter": "no graphics adapter"
        default: key
        }
        return code.map { "\(what) (error \($0))" } ?? what
    }

    /// The last line of the engine's own output worth showing: assertion and
    /// error lines first, since the tail is often a graphics banner.
    static func errorTail(of standardError: String) -> String {
        let lines = standardError.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let telling = lines.last { line in
            ["Assertion failed", "dyld", "Library not loaded", "err:", "abort", "Bad CPU"].contains { line.contains($0) }
        }
        return String((telling ?? lines.last ?? "").prefix(240))
    }

    // MARK: Running

    struct Invocation: Sendable {
        var wine: URL
        var arguments: [String]
        var environment: [String: String]
        var workingDirectory: URL
        var resultFile: URL
        var wineserver: URL
    }

    /// Runs the canary and reports how it ended, with what it wrote. Always
    /// stops the throwaway prefix's wineserver afterwards — a hung canary
    /// must not leave Wine processes behind.
    static func execute(_ invocation: Invocation, timeout: Double = timeoutSeconds) async -> (exit: Exit, output: String, errorTail: String) {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let errorFile = invocation.resultFile.deletingLastPathComponent().appending(path: "stderr.txt")
            fm.createFile(atPath: errorFile.path, contents: nil)
            let process = Process()
            process.executableURL = invocation.wine
            process.arguments = invocation.arguments
            process.environment = invocation.environment
            process.currentDirectoryURL = invocation.workingDirectory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = try? FileHandle(forWritingTo: errorFile)

            var exit: Exit
            do {
                try process.run()
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning, Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                if process.isRunning {
                    process.terminate()
                    exit = .timedOut
                } else {
                    exit = .exited(process.terminationStatus)
                }
            } catch {
                exit = .couldNotStart(error.localizedDescription)
            }

            // Stop everything in the throwaway prefix, then wait for it.
            let prefixEnvironment = invocation.environment
            for flag in ["-k", "-w"] {
                let server = Process()
                server.executableURL = invocation.wineserver
                server.arguments = [flag]
                server.environment = prefixEnvironment
                server.standardOutput = FileHandle.nullDevice
                server.standardError = FileHandle.nullDevice
                if (try? server.run()) != nil {
                    let stop = Date().addingTimeInterval(15)
                    while server.isRunning, Date() < stop { try? await Task.sleep(for: .milliseconds(100)) }
                    if server.isRunning { server.terminate() }
                }
            }

            let output = (try? String(contentsOf: invocation.resultFile, encoding: .utf8)) ?? ""
            let standardError = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
            return (exit, output, errorTail(of: standardError))
        }.value
    }
}

/// The latest canary result per engine, kept in Application Support — the
/// start of the evidence record that labels and the Doctor will read.
enum CanaryStore {
    static var fileURL: URL { AppPaths.applicationSupport.appending(path: "canary-results.json") }

    static func key(backend: GraphicsBackend, engineKey: String?) -> String {
        "\(backend.rawValue)|\(engineKey ?? "unrecorded")"
    }

    static func load(from file: URL = fileURL) -> [String: CanaryResult] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file),
              let results = try? decoder.decode([String: CanaryResult].self, from: data)
        else { return [:] }
        return results
    }

    static func save(_ result: CanaryResult, to file: URL = fileURL) {
        var all = load(from: file)
        all[key(backend: result.backend, engineKey: result.engineKey)] = result
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(all).write(to: file, options: .atomic)
    }

    static func latest(backend: GraphicsBackend, engineKey: String?, from file: URL = fileURL) -> CanaryResult? {
        load(from: file)[key(backend: backend, engineKey: engineKey)]
    }
}

// MARK: - Presentation

extension CanaryStatus {
    var symbol: String {
        switch self {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "minus.circle"
        case .unsupported: "slash.circle"
        case .inconclusive: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .passed: .green
        case .failed: .orange
        case .skipped, .unsupported, .inconclusive: .secondary
        }
    }

    var label: String { L10n.string("canary.status.\(rawValue)") }
}

extension CanaryRung {
    /// "A DirectX 12 device is created — passed", with the fact behind it.
    var lineText: String {
        let base = "\(L10n.string("canary.rung.\(id.rawValue)")) — \(status.label)"
        guard let detail, !detail.isEmpty else { return base }
        return "\(base): \(detail)"
    }
}

extension CanaryResult {
    /// One sentence saying what the run showed and, always, what it didn't.
    var summaryText: String {
        let when = date.formatted(date: .abbreviated, time: .shortened)
        if rungs.allSatisfy({ $0.status == .unsupported }) {
            return L10n.string("canary.summary.unsupported", backend.shortName)
        }
        if allPassed {
            return L10n.string("canary.summary.passed", String(rungs.count), when)
        }
        let problem = firstProblem.map { L10n.string("canary.rung.\($0.id.rawValue)") } ?? ""
        return L10n.string(hasFailure ? "canary.summary.failed" : "canary.summary.incomplete", when, problem)
    }
}
