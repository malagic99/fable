import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool { exitCode == 0 }
}

enum ProcessRunnerError: LocalizedError {
    case launchFailed(executable: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let executable, let underlying):
            "Couldn't launch \(executable): \(underlying)"
        }
    }
}

/// A started, possibly long-lived process (a running game or installer).
/// Output goes to a log file rather than memory.
final class LaunchedProcess: @unchecked Sendable {
    private let process: Process
    private let exitCodes: AsyncStream<Int32>

    fileprivate init(process: Process, exitCodes: AsyncStream<Int32>) {
        self.process = process
        self.exitCodes = exitCodes
    }

    var isRunning: Bool { process.isRunning }

    /// PID of the launched root process. Children (wineserver, the game
    /// itself) live under this PID — discoverable via ProcessMetrics.
    var processIdentifier: Int32 { process.processIdentifier }

    func terminate() {
        process.terminate()
    }

    /// Waits for the process to exit. Single consumer; the exit code is
    /// buffered, so calling after exit returns immediately.
    func waitForExit() async -> Int32 {
        var code: Int32 = -1
        for await value in exitCodes { code = value }
        return code
    }
}

/// Runs external executables (wine, wineserver, tar, …) asynchronously,
/// capturing output. The workhorse behind WineManager and GameLauncher.
enum ProcessRunner {
    /// Starts a process without waiting for it, redirecting stdout/stderr
    /// to `logFile` (created, parent directories included).
    static func start(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        redirectingOutputTo logFile: URL? = nil,
        qualityOfService: QualityOfService = .default
    ) throws -> LaunchedProcess {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Bias the scheduler: a game launches at .userInteractive (P-cores),
        // installers/tools keep the default. See Stability.gameQoS.
        process.qualityOfService = qualityOfService
        if let environment {
            process.environment = ProcessInfo.processInfo.environment
                .merging(environment) { _, override in override }
        }
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let logHandle: FileHandle? = try logFile.map { logFile in
            try FileManager.default.createDirectory(
                at: logFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            return try FileHandle(forWritingTo: logFile)
        }
        if let logHandle {
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        let exitCodes = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                try? logHandle?.close()
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            try? logHandle?.close()
            throw ProcessRunnerError.launchFailed(
                executable: executable.lastPathComponent,
                underlying: error.localizedDescription
            )
        }

        return LaunchedProcess(process: process, exitCodes: exitCodes)
    }

    static func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            // Merge over the inherited environment so PATH etc. survive.
            process.environment = ProcessInfo.processInfo.environment
                .merging(environment) { _, override in override }
        }
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Install the termination handler before run(); a fast-exiting
        // process can otherwise terminate before the handler is attached.
        let exitCodes = AsyncStream<Int32> { continuation in
            process.terminationHandler = {
                continuation.yield($0.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(
                executable: executable.lastPathComponent,
                underlying: error.localizedDescription
            )
        }

        // Drain both pipes while the process runs; waiting for exit
        // first can deadlock once a pipe buffer fills.
        async let stdoutData = read(stdoutPipe)
        async let stderrData = read(stderrPipe)

        var exitCode: Int32 = -1
        for await code in exitCodes { exitCode = code }

        return await ProcessResult(
            exitCode: exitCode,
            standardOutput: String(decoding: stdoutData, as: UTF8.self),
            standardError: String(decoding: stderrData, as: UTF8.self)
        )
    }

    private static func read(_ pipe: Pipe) async -> Data {
        await Task.detached {
            (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        }.value
    }
}
