import Foundation
import Testing
@testable import Fable

@Suite struct ProcessRunnerTests {
    @Test
    func capturesStandardOutputAndExitCode() async throws {
        let result = try await ProcessRunner.run(
            URL(filePath: "/bin/echo"),
            arguments: ["hello"]
        )
        #expect(result.exitCode == 0)
        #expect(result.succeeded)
        #expect(result.standardOutput == "hello\n")
        #expect(result.standardError.isEmpty)
    }

    @Test
    func capturesStandardErrorAndNonZeroExit() async throws {
        let result = try await ProcessRunner.run(
            URL(filePath: "/bin/sh"),
            arguments: ["-c", "echo oops 1>&2; exit 3"]
        )
        #expect(result.exitCode == 3)
        #expect(!result.succeeded)
        #expect(result.standardError == "oops\n")
    }

    @Test
    func passesEnvironmentAndWorkingDirectory() async throws {
        let result = try await ProcessRunner.run(
            URL(filePath: "/bin/sh"),
            arguments: ["-c", "echo $FABLE_TEST_VAR; pwd"],
            environment: ["FABLE_TEST_VAR": "wine"],
            currentDirectory: URL(filePath: "/private/tmp")
        )
        let lines = result.standardOutput.split(separator: "\n")
        #expect(lines.first == "wine")
        #expect(lines.last == "/private/tmp")
    }

    @Test
    func throwsForMissingExecutable() async {
        await #expect(throws: ProcessRunnerError.self) {
            try await ProcessRunner.run(URL(filePath: "/no/such/binary"))
        }
    }

    @Test
    func handlesLargeOutputWithoutDeadlock() async throws {
        // Larger than the 64 KiB pipe buffer to prove pipes are drained
        // while the process runs.
        let result = try await ProcessRunner.run(
            URL(filePath: "/bin/sh"),
            arguments: ["-c", "head -c 1000000 /dev/zero | tr '\\0' 'x'"]
        )
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.count == 1_000_000)
    }
}
