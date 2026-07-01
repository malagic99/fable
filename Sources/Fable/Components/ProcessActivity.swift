import Foundation

/// Detects which games are *actually* running by scanning the process table —
/// not just what Fable itself launched. Fixes two real gaps: a game started
/// from inside Steam (Fable never launched it, so it wouldn't show as running)
/// and a process that lingers after its window closes (so Stop/Play state was
/// stale).
enum ProcessActivity {

    /// Lowercased command lines of every running process (`ps -axww -o command=`).
    static func runningCommands() -> [String] {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/ps")
        process.arguments = ["-axww", "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.lowercased() }
    }

    /// True when a game is running: some command references BOTH the bottle
    /// (its prefix token — the bottle UUID, which appears in the exe's unix
    /// path) AND the game's exe basename. Requiring *both* avoids matching an
    /// unrelated process that merely names the bottle directory (e.g. a tool's
    /// `--dir` argument that mentions the bottle but not the exe).
    static func isRunning(commands: [String], prefixToken: String, exeBasename: String) -> Bool {
        let token = prefixToken.lowercased()
        let exe = exeBasename.lowercased()
        guard !token.isEmpty, !exe.isEmpty else { return false }
        return commands.contains { $0.contains(token) && $0.contains(exe) }
    }
}
