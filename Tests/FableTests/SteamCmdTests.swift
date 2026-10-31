import Foundation
import Testing
@testable import Fable

/// steamcmd app info parsing and the Terminal download script for the native
/// Steam bridge.
@Suite struct SteamCmdTests {
    /// Shape of real `steamcmd +app_info_print 1168880` output (MOLEK-SYNTEZ,
    /// 2026-10-31), trimmed: login noise, then the KeyValues block.
    private let molek = """
    Redirecting stderr to '/Users/x/Library/Application Support/Steam/logs/stderr.txt'
    Logging in user 'anonymous' to Steam Public...OK
    Waiting for user info...OK
    AppID : 1168880, change number : 31234567/0, last change : Fri Oct 14 2022
    "1168880"
    {
    \t"common"
    \t{
    \t\t"name"\t\t"MOLEK-SYNTEZ"
    \t\t"oslist"\t\t"windows,macos,linux"
    \t}
    \t"config"
    \t{
    \t\t"launch"
    \t\t{
    \t\t\t"0"
    \t\t\t{
    \t\t\t\t"executable"\t\t"MOLEK-SYNTEZ.exe"
    \t\t\t\t"type"\t\t"default"
    \t\t\t\t"config"
    \t\t\t\t{
    \t\t\t\t\t"oslist"\t\t"windows"
    \t\t\t\t}
    \t\t\t}
    \t\t\t"1"
    \t\t\t{
    \t\t\t\t"executable"\t\t"MOLEK-SYNTEZ.app/Contents/MacOS/MOLEK-SYNTEZ"
    \t\t\t\t"config"
    \t\t\t\t{
    \t\t\t\t\t"oslist"\t\t"macos"
    \t\t\t\t}
    \t\t\t}
    \t\t}
    \t}
    }
    Unloading Steam API...OK
    """

    @Test
    func parsesNameAndTheWindowsLaunchEntry() {
        let info = SteamAppInfo.parse(appID: 1168880, steamcmdOutput: molek)
        #expect(info == SteamAppInfo(appID: 1168880, name: "MOLEK-SYNTEZ",
                                     windowsExecutable: "MOLEK-SYNTEZ.exe", windowsArguments: ""))
    }

    @Test
    func windowsPathsAreNormalisedAndArgumentsKept() {
        let output = """
        "42"
        {
        \t"common" { "name" "Game" }
        \t"config" { "launch" {
        \t\t"0" { "executable" "Game\\\\Binaries\\\\Win64\\\\Game-Win64-Shipping.exe" "arguments" "-dx11" }
        \t} }
        }
        """
        let info = SteamAppInfo.parse(appID: 42, steamcmdOutput: output)
        // No oslist means every platform, Windows included.
        #expect(info?.windowsExecutable == "Game/Binaries/Win64/Game-Win64-Shipping.exe")
        #expect(info?.windowsArguments == "-dx11")
    }

    @Test
    func anAppWithoutAWindowsBuildHasNoExecutable() {
        let macOnly = molek.replacingOccurrences(of: "\"MOLEK-SYNTEZ.exe\"", with: "\"MOLEK-SYNTEZ.sh\"")
        let info = SteamAppInfo.parse(appID: 1168880, steamcmdOutput: macOnly)
        #expect(info?.name == "MOLEK-SYNTEZ")
        #expect(info?.windowsExecutable == nil)
    }

    @Test
    func unrelatedOrEmptyOutputParsesToNil() {
        #expect(SteamAppInfo.parse(appID: 1168880, steamcmdOutput: "") == nil)
        #expect(SteamAppInfo.parse(appID: 999, steamcmdOutput: molek) == nil)
    }

    @Test
    func downloadScriptIsValidShellAndQuotesItsPaths() async throws {
        let info = SteamAppInfo(appID: 1168880, name: "It's \"MOLEK\"\nSYNTEZ",
                                windowsExecutable: "MOLEK-SYNTEZ.exe", windowsArguments: "")
        let script = SteamCmd.downloadCommand(
            info: info,
            installDir: URL(filePath: "/Users/x/Library/Application Support/Fable/Bottles/B/prefix/drive_c/SteamBridge/1168880"),
            marker: URL(filePath: "/tmp/fable marker/1168880.done"),
            steamcmd: URL(filePath: "/Users/x/Library/Application Support/Fable/Components/steamcmd/steamcmd.sh")
        )
        #expect(script.contains("+@sSteamCmdForcePlatformType windows"))
        #expect(script.contains("+app_update 1168880 validate"))
        #expect(script.contains("'/Users/x/Library/Application Support/Fable/Bottles/B/prefix/drive_c/SteamBridge/1168880'"))
        #expect(!script.contains("\nSYNTEZ"), "a newline in the name must not break the comment line")

        let file = FileManager.default.temporaryDirectory.appending(path: "steamcmd-\(UUID().uuidString).command")
        defer { try? FileManager.default.removeItem(at: file) }
        try script.write(to: file, atomically: true, encoding: .utf8)
        let check = try await ProcessRunner.run(URL(filePath: "/bin/sh"), arguments: ["-n", file.path])
        #expect(check.succeeded, "sh -n: \(check.standardError)")
    }

    @Test
    func appIDFromWhatPeoplePaste() {
        #expect(SteamAppInfo.appID(fromInput: "1168880") == 1168880)
        #expect(SteamAppInfo.appID(fromInput: "  1168880\n") == 1168880)
        #expect(SteamAppInfo.appID(fromInput: "https://store.steampowered.com/app/1168880/MOLEKSYNTEZ/") == 1168880)
        #expect(SteamAppInfo.appID(fromInput: "steamdb.info/app/895870/") == 895870)
        #expect(SteamAppInfo.appID(fromInput: "MOLEK-SYNTEZ") == nil)
        #expect(SteamAppInfo.appID(fromInput: "0") == nil)
        #expect(SteamAppInfo.appID(fromInput: "") == nil)
    }

    @Test
    func bridgeGamesInstallIntoTheirOwnFolder() {
        #expect(SteamCmd.installFolder(appID: 1168880) == "SteamBridge/1168880")
    }
}
