import Foundation
import Testing
@testable import Fable

@Suite struct LaunchedProcessTests {
    @Test
    func startTerminateAndWait() async throws {
        let process = try ProcessRunner.start(
            URL(filePath: "/bin/sleep"),
            arguments: ["30"]
        )
        #expect(process.isRunning)
        process.terminate()
        let code = await process.waitForExit()
        #expect(code != 0)  // SIGTERM
        #expect(!process.isRunning)
    }

    @Test
    func redirectsOutputToLogFile() async throws {
        let log = FileManager.default.temporaryDirectory
            .appending(path: "logs-\(UUID().uuidString)")
            .appending(path: "run.log")
        defer { try? FileManager.default.removeItem(at: log.deletingLastPathComponent()) }

        let process = try ProcessRunner.start(
            URL(filePath: "/bin/sh"),
            arguments: ["-c", "echo out; echo err 1>&2"],
            redirectingOutputTo: log
        )
        let code = await process.waitForExit()
        #expect(code == 0)

        let contents = try String(contentsOf: log, encoding: .utf8)
        #expect(contents.contains("out"))
        #expect(contents.contains("err"))
    }

    @Test
    func waitAfterExitReturnsBufferedCode() async throws {
        let process = try ProcessRunner.start(URL(filePath: "/usr/bin/true"))
        // Give it time to exit before we start waiting.
        try await Task.sleep(for: .milliseconds(200))
        let code = await process.waitForExit()
        #expect(code == 0)
    }
}
