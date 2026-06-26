import Foundation
import Testing
@testable import Fable

/// Pins the Steam-in-a-bottle layout. The literal strings here mirror what
/// SteamFastPathTests/SteamRedistInstallerTests plant on disk, so if the layout
/// drifts these and those fail together — an independent cross-check.
@Suite struct SteamPathsTests {

    @Test
    func relativePathsMatchTheRealLayout() {
        #expect(SteamPaths.clientDirRelative == "Program Files (x86)/Steam")
        #expect(SteamPaths.exeRelative == "Program Files (x86)/Steam/Steam.exe")
        #expect(SteamPaths.uiMarkerRelative == "Program Files (x86)/Steam/steamui.dll")
        #expect(SteamPaths.sharedRedistRelative
            == "Program Files (x86)/Steam/steamapps/common/Steamworks Shared/_CommonRedist")
    }

    @Test
    func urlHelpersComposeUnderDriveC() {
        let driveC = URL(filePath: "/bottles/x/prefix/drive_c")
        #expect(SteamPaths.clientRoot(inDriveC: driveC).path
            == "/bottles/x/prefix/drive_c/Program Files (x86)/Steam")
        #expect(SteamPaths.uiMarker(inDriveC: driveC).path
            == "/bottles/x/prefix/drive_c/Program Files (x86)/Steam/steamui.dll")
        // appsCommon resolves from a client root, not drive_c.
        let root = SteamPaths.clientRoot(inDriveC: driveC)
        #expect(SteamPaths.appsCommon(inClientRoot: root).path
            == "/bottles/x/prefix/drive_c/Program Files (x86)/Steam/steamapps/common")
    }
}
