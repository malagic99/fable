import Foundation
import Testing
@testable import Fable

/// Security scan 2026-11-20, findings 2, 4 and 5: what a donor export must
/// leave out beyond whole folders.
@Suite("Donor export")
struct DonorExportTests {

    @Test
    func theAccountNameAndPerAccountKeysAreRemovedAndNothingElse() {
        let registry = #"""
        WINE REGISTRY Version 2
        ;; All keys relative to \\User\\S-1-5-21

        [Software\\Valve\\Steam] 1794875685
        #time=1dd762d0bc63e54
        "AlreadyRetriedOfflineMode"=dword:00000000
        "AutoLoginUser"="owneraccount"
        "Language"="english"
        "LastGameNameUsed"="Owner Persona"
        "RememberPassword"=dword:00000001

        [Software\\Valve\\Steam\\ActiveProcess] 1794875676
        #time=1dd762b6c24f986
        "ActiveUser"=dword:0badf00d
        "pid"=dword:00000020

        [Software\\Valve\\Steam\\Apps\\1812620] 1794528673
        "Installed"=dword:00000001
        "Name"="DSX"

        [Software\\Valve\\Steamsteamglobal] 1790688230
        "language"="english"

        [Software\\Wine\\DllOverrides] 1794876356
        "d3d12"="builtin"
        """#
        let out = DonorExport.sanitizedUserRegistry(registry)
        for gone in ["owneraccount", "Owner Persona", "RememberPassword", "ActiveProcess", "0badf00d", "\"DSX\""] {
            #expect(!out.contains(gone), "\(gone) should be gone")
        }
        // Other Steam settings, a key that only starts the same, and Wine's
        // own settings are kept exactly.
        #expect(out.contains(#""AlreadyRetriedOfflineMode"=dword:00000000"#))
        #expect(out.contains(#""Language"="english""#))
        #expect(out.contains(#"[Software\\Valve\\Steamsteamglobal] 1790688230"#))
        #expect(out.contains(#"[Software\\Wine\\DllOverrides] 1794876356"#))
        #expect(out.hasPrefix("WINE REGISTRY Version 2"))
    }

    @Test
    func aValueSpreadOverSeveralLinesIsRemovedWhole() {
        let registry = "[Software\\\\Valve\\\\Steam] 1\n\"AutoLoginUser\"=hex(2):6f,00,77,\\\n  6e,00,65,00,\\\n  72,00\n\"Language\"=\"english\"\n"
        let out = DonorExport.sanitizedUserRegistry(registry)
        #expect(!out.contains("6f,00"))
        #expect(!out.contains("72,00"))
        #expect(out.contains(#""Language"="english""#))
    }

    @Test
    func aRegistryWithoutSteamIsUnchanged() {
        let registry = "WINE REGISTRY Version 2\n\n[Software\\\\Wine] 1\n\"Version\"=\"win10\"\n"
        #expect(DonorExport.sanitizedUserRegistry(registry) == registry)
    }

    @Test
    func gameFoldersCoverEveryGameButNeverWindowsOrSteamItself() {
        var bottle = Bottle(name: "B")
        bottle.games = [
            Game(name: "Steam", executablePath: SteamPaths.exeRelative),
            Game(name: "In Steam", executablePath: "\(SteamPaths.clientDirRelative)/steamapps/common/G/g.exe"),
            Game(name: "Undertale", executablePath: "Program Files/Undertale.v31.08.2017/UNDERTALE.exe"),
            Game(name: "007", executablePath: "Games/007 First Light/Retail/007FirstLight.exe"),
            Game(name: "GOG", executablePath: "GOG Games\\System Shock 2\\shock2.exe"),
            Game(name: "Desktop", executablePath: "users/me/Desktop/Tool/tool.exe"),
            Game(name: "cmd", executablePath: "windows/system32/cmd.exe"),
            Game(name: "Loose", executablePath: "Program Files/loose.exe"),
            Game(name: "Escape", executablePath: "Program Files/../windows/x.exe"),
        ]
        #expect(DonorExport.gameFolders(of: bottle) == [
            "GOG Games/System Shock 2",
            "Games/007 First Light",
            "Program Files/Undertale.v31.08.2017",
            "SteamBridge",
            "users/me/Desktop/Tool",
        ])
    }

    @Test
    func folderNamesAreMatchedLiterally() {
        #expect(DonorExport.literalPattern("Games/Doom [1993]*?") == #"Games/Doom \[1993\]\*\?"#)
    }
}
