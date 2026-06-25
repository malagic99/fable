import Foundation
import Testing
@testable import Fable

/// The desktop-shortcut generator: a `.app` bundle whose launch script
/// reproduces a game's resolved Wine command + environment.
@Suite struct ShortcutGeneratorTests {

    private func samplePlan(
        env: [String: String] = ["WINEPREFIX": "/tmp/pfx", "WINEESYNC": "1"]
    ) -> GameLauncher.LaunchPlan {
        GameLauncher.LaunchPlan(
            wine: URL(filePath: "/opt/wine/bin/wine64"),
            executable: URL(filePath: "/tmp/pfx/drive_c/Game/Game.exe"),
            arguments: ["-windowed", "two words"],
            environment: env,
            workingDirectory: URL(filePath: "/tmp/pfx/drive_c/Game"),
            logFile: URL(filePath: "/tmp/logs/game.log"),
            runtimeKey: "wine",
            releaseWineserver: nil
        )
    }

    @Test
    func shellQuoteEscapesSingleQuotes() {
        #expect(ShortcutGenerator.shellQuote("plain") == "'plain'")
        // An embedded single quote becomes '\'' inside the quoted run.
        #expect(ShortcutGenerator.shellQuote("it's") == #"'it'\''s'"#)
    }

    @Test
    func sanitizedFileNameStripsPathSeparatorsAndColons() {
        #expect(ShortcutGenerator.sanitizedFileName("Half-Life 2") == "Half-Life 2")
        #expect(!ShortcutGenerator.sanitizedFileName("foo/bar:baz").contains("/"))
        #expect(!ShortcutGenerator.sanitizedFileName("foo/bar:baz").contains(":"))
        // Falls back when nothing usable survives.
        #expect(ShortcutGenerator.sanitizedFileName("///") == "Fable Game")
    }

    @Test
    func launchScriptExportsEnvAndExecsWine() {
        let script = ShortcutGenerator.launchScript(plan: samplePlan())
        #expect(script.hasPrefix("#!/bin/sh"))
        // Every env var is exported, sorted and quoted.
        #expect(script.contains("export WINEPREFIX='/tmp/pfx'"))
        #expect(script.contains("export WINEESYNC='1'"))
        // cd into the working dir, then exec the wine + exe + args, logging.
        #expect(script.contains("cd '/tmp/pfx/drive_c/Game'"))
        #expect(script.contains("exec '/opt/wine/bin/wine64' '/tmp/pfx/drive_c/Game/Game.exe' '-windowed' 'two words'"))
        #expect(script.contains(">> '/tmp/logs/game.log' 2>&1"))
    }

    @Test
    func argumentWithSingleQuoteSurvivesQuoting() {
        let plan = samplePlan(env: ["A": "x'y"])
        let script = ShortcutGenerator.launchScript(plan: plan)
        #expect(script.contains(#"export A='x'\''y'"#))
    }

    @Test
    func createAppWritesRunnableBundle() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "shortcut-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let app = try ShortcutGenerator.createApp(named: "My Game", plan: samplePlan(), in: dir)

        #expect(app.lastPathComponent == "My Game.app")
        let exec = app.appending(path: "Contents/MacOS/launch")
        let plist = app.appending(path: "Contents/Info.plist")
        #expect(fm.fileExists(atPath: plist.path))
        #expect(fm.isExecutableFile(atPath: exec.path))
        // Info.plist names the script as the bundle executable.
        let plistBody = try String(contentsOf: plist, encoding: .utf8)
        #expect(plistBody.contains("<key>CFBundleExecutable</key><string>launch</string>"))

        // Re-creating with the same name replaces, doesn't throw.
        let again = try ShortcutGenerator.createApp(named: "My Game", plan: samplePlan(), in: dir)
        #expect(again == app)
    }
}
