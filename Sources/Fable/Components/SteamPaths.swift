import Foundation

/// The on-disk layout of a Steam install inside a bottle — the magic
/// `Program Files (x86)/Steam/…` subpaths that were hardcoded across
/// BottleManager, the bottle templates, and the redist scanner. Centralized so
/// the layout is stated once and a path change (or a Steam relocation) is a
/// one-file edit.
enum SteamPaths {
    /// Steam client directory, relative to a bottle's `drive_c`.
    static let clientDirRelative = "Program Files (x86)/Steam"
    /// The Steam launcher, relative to `drive_c` — a Steam bottle's registered exe.
    static let exeRelative = "\(clientDirRelative)/Steam.exe"
    /// Presence of this CEF UI dll proves Steam finished installing.
    static let uiMarkerRelative = "\(clientDirRelative)/steamui.dll"
    /// Installed-games tree, relative to the Steam client root.
    static let appsCommonRelative = "steamapps/common"
    /// Shared "Steamworks Common Redistributables" dir, relative to `drive_c`.
    static let sharedRedistRelative = "\(clientDirRelative)/\(appsCommonRelative)/Steamworks Shared/_CommonRedist"

    // MARK: URL helpers (from a bottle's drive_c)

    static func clientRoot(inDriveC driveC: URL) -> URL {
        driveC.appending(path: clientDirRelative, directoryHint: .isDirectory)
    }
    static func uiMarker(inDriveC driveC: URL) -> URL {
        driveC.appending(path: uiMarkerRelative)
    }
    static func sharedRedist(inDriveC driveC: URL) -> URL {
        driveC.appending(path: sharedRedistRelative, directoryHint: .isDirectory)
    }

    // MARK: URL helpers (from a resolved Steam client root)

    static func appsCommon(inClientRoot root: URL) -> URL {
        root.appending(path: appsCommonRelative, directoryHint: .isDirectory)
    }
}
