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

/// Runs external executables (wine, wineserver, tar, …) asynchronously,
/// capturing output. The workhorse behind WineManager and GameLauncher.
enum ProcessRunner {
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
