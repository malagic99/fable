import Foundation
import Testing
@testable import Fable

/// Detecting a running game from process command lines — matching the bottle
/// AND the exe, so unrelated processes that merely name the bottle dir don't
/// count.
@Suite struct ProcessActivityTests {
    private let uuid = "C10BEAF8-71F9-4B39-B2DD-0911F8C58D9E"

    @Test
    func detectsAGameRunningInItsBottle() {
        let cmds = [
            "/some/other/process --flag",
            "/users/x/library/application support/fable/bottles/\(uuid.lowercased())/prefix/drive_c/program files (x86)/steam/steamapps/common/deathloop/deathloop.exe",
        ]
        #expect(ProcessActivity.isRunning(commands: cmds, prefixToken: uuid, exeBasename: "DEATHLOOP.exe"))
        #expect(!ProcessActivity.isRunning(commands: cmds, prefixToken: uuid, exeBasename: "notthere.exe"))
    }

    @Test
    func ignoresProcessesThatNameTheBottleButNotTheExe() {
        // A tool (like a dev agent) whose args mention the bottle dir but not a
        // running game exe must NOT count as the game running.
        let cmds = [
            "claude --add-dir /users/x/.../fable/bottles/\(uuid.lowercased())/prefix/drive_c/program files/system shock 2 --model opus",
        ]
        #expect(!ProcessActivity.isRunning(commands: cmds, prefixToken: uuid, exeBasename: "ss2.exe"))
    }

    @Test
    func scopesToTheRightBottle() {
        let other = "AAAAAAAA-0000-0000-0000-000000000000"
        let cmds = ["/…/bottles/\(other.lowercased())/…/game.exe"]
        // Same exe name, different bottle → not running in ours.
        #expect(!ProcessActivity.isRunning(commands: cmds, prefixToken: uuid, exeBasename: "game.exe"))
        #expect(ProcessActivity.isRunning(commands: cmds, prefixToken: other, exeBasename: "game.exe"))
    }

    @Test
    func emptyInputsAreNotRunning() {
        #expect(!ProcessActivity.isRunning(commands: [], prefixToken: uuid, exeBasename: "game.exe"))
        #expect(!ProcessActivity.isRunning(commands: ["x"], prefixToken: "", exeBasename: "game.exe"))
        #expect(!ProcessActivity.isRunning(commands: ["x"], prefixToken: uuid, exeBasename: ""))
    }

    @Test
    func liveScanReturnsSomething() {
        // Sanity: ps runs and yields at least this test process's own command.
        #expect(!ProcessActivity.runningCommands().isEmpty)
    }
}
