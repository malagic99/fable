import Foundation

/// What the engine benchmark measured on one engine. A fixed, synthetic D3D12
/// scene: it compares engines on this Mac and catches a slowdown after an
/// engine or macOS update. It never says how a game will run.
struct BenchmarkResult: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct Phase: Codable, Equatable, Hashable, Sendable {
        enum ID: String, Codable, CaseIterable, Sendable {
            /// Thousands of small draw calls: bound by Wine and the renderer
            /// translating D3D12 on the CPU. Where engines differ.
            case draws
            /// One heavy full-screen shader: bound by the GPU.
            case shade
        }

        var id: ID
        var frames: Int
        /// Milliseconds per frame, start of recording to the GPU finishing.
        var medianMs: Double
        var averageMs: Double
        var p99Ms: Double
    }

    var schemaVersion = currentSchemaVersion
    var backend: GraphicsBackend
    var engineKey: String?
    var manifestID: String?
    var date: Date
    var durationSeconds: Double
    /// The scene's parameters as the program reported them. Two results are
    /// only comparable when these match.
    var scene: String?
    var phases: [Phase]
    /// The ladder's sixth rung: a frame was presented to a real window.
    var framePresented: CanaryStatus
    /// Why the run stopped early, when it did.
    var failure: String?
    /// The Mac it ran on, so a number is never read without its hardware.
    var hardware: String?
    var fableVersion: String?

    func phase(_ id: Phase.ID) -> Phase? { phases.first { $0.id == id } }
    /// True when both phases were measured.
    var isComplete: Bool { phases.count == Phase.ID.allCases.count && failure == nil }
}

enum EngineBenchmark {
    static let programName = "fable-bench64.exe"
    /// Prefix creation, two 3-second phases with warm-up, and slack.
    static let timeoutSeconds: Double = 180

    static var program: URL? {
        Bundle.fableResources.url(forResource: "fable-bench64", withExtension: "exe", subdirectory: "canary")
    }

    /// How far two medians may differ before it means anything. Measured on
    /// an M4 Pro over repeated runs: shading repeats within 1%, the
    /// CPU-bound draw phase within about 10% (other programs running shift
    /// it). Differences inside these margins are reported as "about the same".
    static func noiseMargin(for phase: BenchmarkResult.Phase.ID) -> Double {
        switch phase {
        case .draws: 0.15
        case .shade: 0.05
        }
    }

    // MARK: Reading the program's output

    /// Builds a result from what the benchmark wrote. Pure.
    static func result(
        backend: GraphicsBackend, engineKey: String?, manifestID: String?, date: Date,
        durationSeconds: Double, supported: Bool, output: String, exit: EngineCanary.Exit,
        errorTail: String, hardware: String? = HardwareProfile.current.summary
    ) -> BenchmarkResult {
        var result = BenchmarkResult(
            backend: backend, engineKey: engineKey, manifestID: manifestID, date: date,
            durationSeconds: durationSeconds, scene: nil, phases: [],
            framePresented: supported ? .skipped : .unsupported, failure: nil,
            hardware: hardware, fableVersion: EngineCanary.appVersion)
        guard supported else { return result }

        var facts: [String: String] = [:]
        var order: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            facts[key] = String(line[line.index(after: equals)...])
            order.append(key)
        }
        let finished = output.split(whereSeparator: \.isNewline).contains { $0 == "done" }
        result.scene = facts["scene"].map { $0.replacingOccurrences(of: "ok ", with: "") }

        // The steps before the first frame, in the order the program does
        // them. The first one that isn't "ok" is why there are no numbers.
        let setup = ["libraries", "device", "window", "swapchain", "shaders", "pipeline"]
        for step in setup {
            guard let value = facts[step] else {
                result.failure = stopDescription(step: step, facts: facts, exit: exit, errorTail: errorTail)
                return result
            }
            if !value.hasPrefix("ok") {
                result.failure = "\(stepName(step)) failed (\(detail(of: value)))"
                return result
            }
        }

        if let present = facts["present"] {
            result.framePresented = present.hasPrefix("ok") ? .passed : .failed
            if !present.hasPrefix("ok") {
                result.failure = "no frame could be presented (\(detail(of: present)))"
                return result
            }
        } else {
            result.framePresented = .failed
            result.failure = stopDescription(step: "present", facts: facts, exit: exit, errorTail: errorTail)
            return result
        }

        for id in BenchmarkResult.Phase.ID.allCases {
            guard let value = facts["phase.\(id.rawValue)"] else {
                if !finished {
                    result.failure = stopDescription(
                        step: "phase.\(id.rawValue)", facts: facts, exit: exit, errorTail: errorTail)
                    return result
                }
                continue
            }
            guard value.hasPrefix("ok"), let phase = phase(id, from: value) else {
                result.failure = "the \(id.rawValue) phase failed (\(detail(of: value)))"
                return result
            }
            result.phases.append(phase)
        }
        if result.phases.count < BenchmarkResult.Phase.ID.allCases.count, result.failure == nil {
            result.failure = "the benchmark finished without reporting every phase"
        }
        return result
    }

    /// "ok frames=407 wall_ms=3003 avg_ms=7.368 median_ms=7.000 p99_ms=10.248"
    static func phase(_ id: BenchmarkResult.Phase.ID, from value: String) -> BenchmarkResult.Phase? {
        var numbers: [String: Double] = [:]
        for field in value.split(separator: " ") {
            let pair = field.split(separator: "=", maxSplits: 1)
            if pair.count == 2, let number = Double(pair[1]) { numbers[String(pair[0])] = number }
        }
        guard let frames = numbers["frames"], let median = numbers["median_ms"],
              let average = numbers["avg_ms"], let p99 = numbers["p99_ms"],
              frames >= 10, median > 0
        else { return nil }
        return .init(id: id, frames: Int(frames), medianMs: median, averageMs: average, p99Ms: p99)
    }

    private static func detail(of value: String) -> String {
        // "failed error=1114 dll=d3d12.dll" → "d3d12.dll, error 1114"
        let fields = value.split(separator: " ").dropFirst().map(String.init)
        let dll = fields.first { $0.hasPrefix("dll=") }.map { String($0.dropFirst(4)) }
        let rest = fields.filter { !$0.hasPrefix("dll=") }.joined(separator: " ")
            .replacingOccurrences(of: "hr=", with: "error ")
            .replacingOccurrences(of: "error=", with: "error ")
            .replacingOccurrences(of: "reason=", with: "")
        return [dll, rest.isEmpty ? nil : rest].compactMap { $0 }.joined(separator: ", ")
    }

    private static func stepName(_ step: String) -> String {
        switch step {
        case "libraries": "loading the Direct3D libraries"
        case "device": "creating a D3D12 device"
        case "window": "opening a window"
        case "swapchain": "creating the swap chain"
        case "shaders": "compiling the shaders"
        case "pipeline": "building the pipeline"
        case "present": "presenting a frame"
        default: step
        }
    }

    /// Why nothing was written for `step`: the run ended there.
    private static func stopDescription(
        step: String, facts: [String: String], exit: EngineCanary.Exit, errorTail: String
    ) -> String {
        let name = step.hasPrefix("phase.") ? "the \(step.dropFirst(6)) phase" : stepName(step)
        if let crash = facts["crash"] {
            return "crashed while \(name) (\(crash.split(separator: " ").first ?? ""))"
        }
        let tail = errorTail.trimmingCharacters(in: .whitespacesAndNewlines)
        switch exit {
        case .timedOut:
            return tail.isEmpty ? "stopped responding while \(name)" : "stopped responding while \(name): \(tail)"
        case .couldNotStart(let reason):
            return reason.isEmpty ? "the benchmark could not start" : reason
        case .exited(let code):
            return tail.isEmpty ? "ended while \(name) (exit code \(code))" : "ended while \(name): \(tail)"
        }
    }

    // MARK: Comparing engines

    enum Verdict: Equatable, Sendable {
        /// Within the noise margin.
        case same
        /// `fraction` of the other's time saved (0.2 = 20% less time per frame).
        case faster(Double)
        /// `fraction` more time per frame than the other.
        case slower(Double)
    }

    /// How `result` compares with `other` on one phase, or nil when they
    /// can't be compared: different scenes, different Macs, or a phase missing.
    static func compare(
        _ result: BenchmarkResult, to other: BenchmarkResult, phase id: BenchmarkResult.Phase.ID
    ) -> Verdict? {
        guard result.scene != nil, result.scene == other.scene, result.hardware == other.hardware,
              let mine = result.phase(id), let theirs = other.phase(id), theirs.medianMs > 0
        else { return nil }
        let change = (mine.medianMs - theirs.medianMs) / theirs.medianMs
        if abs(change) <= noiseMargin(for: id) { return .same }
        return change < 0 ? .faster(-change) : .slower(change)
    }
}

/// The latest benchmark per engine, kept in Application Support beside the
/// canary results.
enum BenchmarkStore {
    static var fileURL: URL { AppPaths.applicationSupport.appending(path: "benchmark-results.json") }

    static func load(from file: URL = fileURL) -> [String: BenchmarkResult] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file),
              let results = try? decoder.decode([String: BenchmarkResult].self, from: data)
        else { return [:] }
        return results
    }

    static func save(_ result: BenchmarkResult, to file: URL = fileURL) {
        var all = load(from: file)
        all[CanaryStore.key(backend: result.backend, engineKey: result.engineKey)] = result
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(all).write(to: file, options: .atomic)
    }

    static func latest(backend: GraphicsBackend, engineKey: String?, from file: URL = fileURL) -> BenchmarkResult? {
        load(from: file)[CanaryStore.key(backend: backend, engineKey: engineKey)]
    }

    /// Complete results for other engines of the same backend — what a new
    /// result can be compared with.
    static func others(than result: BenchmarkResult, from file: URL = fileURL) -> [BenchmarkResult] {
        load(from: file).values
            .filter { $0.backend == result.backend && $0.engineKey != result.engineKey && $0.isComplete }
            .sorted { $0.date > $1.date }
    }
}

// MARK: - Presentation

extension BenchmarkResult {
    /// The lines shown under "Benchmark Engine".
    var displayLines: [String] {
        if framePresented == .unsupported {
            return [L10n.string("bench.unsupported", backend.shortName)]
        }
        var lines: [String] = []
        if let failure {
            lines.append(L10n.string("bench.failed", failure))
        }
        for phase in phases {
            lines.append(L10n.string(
                "bench.phase.\(phase.id.rawValue)",
                String(format: "%.1f", phase.medianMs), String(format: "%.1f", phase.p99Ms)))
        }
        if framePresented == .passed {
            lines.append(L10n.string("bench.presented"))
        }
        return lines
    }

    /// One line per other engine this can be compared with.
    func comparisonLines(with others: [BenchmarkResult]) -> [String] {
        others.compactMap { other in
            guard let key = other.engineKey else { return nil }
            let parts: [String] = Phase.ID.allCases.compactMap { id in
                guard let verdict = EngineBenchmark.compare(self, to: other, phase: id) else { return nil }
                let name = L10n.string("bench.phase_name.\(id.rawValue)")
                switch verdict {
                case .same: return L10n.string("bench.compare.same", name)
                case .faster(let f): return L10n.string("bench.compare.faster", name, String(Int((f * 100).rounded())))
                case .slower(let f): return L10n.string("bench.compare.slower", name, String(Int((f * 100).rounded())))
                }
            }
            guard !parts.isEmpty else { return nil }
            return L10n.string(
                "bench.compare.line", BottleRuntime.displayName(forEngineKey: key), parts.joined(separator: ", "))
        }
    }
}
