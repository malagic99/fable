import Foundation
import Testing
@testable import Fable

@Suite struct ArgumentTokenizerTests {
    @Test
    func tokenizesWithQuotes() {
        #expect(ArgumentTokenizer.tokenize("-windowed -skipintro") == ["-windowed", "-skipintro"])
        #expect(ArgumentTokenizer.tokenize("  -a   \"two words\" 'single quoted' ") ==
            ["-a", "two words", "single quoted"])
        #expect(ArgumentTokenizer.tokenize("--path=\"C:\\Games\\My Game\"") == ["--path=C:\\Games\\My Game"])
        #expect(ArgumentTokenizer.tokenize("") == [])
        #expect(ArgumentTokenizer.tokenize("\"\"") == [""])
    }

    @Test
    func environmentLinesRoundTrip() {
        let env = ArgumentTokenizer.environment(fromLines: """
        DXVK_HUD=fps
          WINEESYNC=1
        not a pair
        =alsobad
        EMPTY=
        """)
        #expect(env == ["DXVK_HUD": "fps", "WINEESYNC": "1", "EMPTY": ""])
        #expect(ArgumentTokenizer.lines(fromEnvironment: ["B": "2", "A": "1"]) == "A=1\nB=2")
    }
}

@Suite struct GameModelCompatibilityTests {
    @Test
    func oldGameJSONDecodesWithDefaults() throws {
        let json = """
        {"id": "\(UUID().uuidString)", "name": "Old", "executablePath": "Program Files/Old/old.exe"}
        """
        let game = try JSONDecoder().decode(Game.self, from: Data(json.utf8))
        #expect(game.arguments == "")
        #expect(game.environment.isEmpty)
    }
}

@Suite struct WinePrefixInspectorTests {
    @Test
    func mapsBuildNumbersToVersions() {
        #expect(WinePrefixInspector.version(forBuild: 22000) == .win11)
        #expect(WinePrefixInspector.version(forBuild: 26100) == .win11)
        #expect(WinePrefixInspector.version(forBuild: 19043) == .win10)
        #expect(WinePrefixInspector.version(forBuild: 10240) == .win10)
        #expect(WinePrefixInspector.version(forBuild: 7601) == .win7)
        #expect(WinePrefixInspector.version(forBuild: 2600) == nil)
    }

    @Test
    func parsesSystemReg() throws {
        let reg = """
        WINE REGISTRY Version 2

        [Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion] 1700000000
        "CurrentBuildNumber"="19043"
        "CurrentVersion"="10.0"
        """
        let prefix = FileManager.default.temporaryDirectory
            .appending(path: "RegTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: prefix) }
        try Data(reg.utf8).write(to: prefix.appending(path: "system.reg"))

        #expect(WinePrefixInspector.windowsVersion(ofPrefix: prefix) == .win10)
    }
}

@Suite struct ExeIconExtractorTests {
    @Test
    func garbageDataReturnsNil() {
        #expect(ExeIconExtractor.icoData(from: Data("not an exe".utf8)) == nil)
        #expect(ExeIconExtractor.icoData(from: Data()) == nil)
        // MZ but truncated.
        #expect(ExeIconExtractor.icoData(from: Data([0x4D, 0x5A, 0, 0])) == nil)
    }

    /// Real-exe check, gated: FABLE_ICON_EXE=/path/to/game.exe
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FABLE_ICON_EXE"] != nil))
    func extractsIconFromRealExe() throws {
        let path = try #require(ProcessInfo.processInfo.environment["FABLE_ICON_EXE"])
        let data = try Data(contentsOf: URL(filePath: path), options: .alwaysMapped)
        let ico = try #require(ExeIconExtractor.icoData(from: data), "no icon extracted")
        // ICO magic: reserved=0, type=1.
        #expect(ico[0] == 0 && ico[1] == 0 && ico[2] == 1 && ico[3] == 0)
        #expect(ExeIconExtractor.icon(forExecutable: URL(filePath: path)) != nil)
    }
}
