import Foundation

/// What kind of Windows installer a file is — which decides how Wine has to be
/// invoked.
///
/// A `.exe` is a program: Wine executes it directly. An MSI package is *data* —
/// a Windows Installer database — so `wine package.msi` fails the same way
/// running a `.zip` would. It installs only through Windows Installer, which
/// Wine ships as the built-in `msiexec`.
///
/// Detection mirrors ``PEInfo``: one small header read, no external tools. The
/// bias is deliberately conservative — anything not positively identified as an
/// MSI keeps today's "just run it" path, so a header we can't parse can never
/// stop an install that used to work.
enum InstallerKind: Equatable, Sendable {
    /// A program Wine executes directly.
    case executable
    /// A Windows Installer database — must go through `msiexec /i`.
    case msiPackage

    /// OLE2 compound-document signature. MSI databases are OLE2 containers,
    /// which is what separates them from PE binaries on disk.
    private static let oleSignature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]

    static func detect(_ url: URL) -> InstallerKind {
        let head: Data
        if let handle = try? FileHandle(forReadingFrom: url) {
            head = (try? handle.read(upToCount: 0x1000)) ?? Data()
            try? handle.close()
        } else {
            head = Data()
        }
        return detect(head: head, pathExtension: url.pathExtension)
    }

    /// Pure form, so classification is testable without touching disk.
    ///
    /// The `.msi` extension is trusted even when the signature is missing: a
    /// truncated or corrupt package is better answered by msiexec's own "this
    /// installation package could not be opened" than by Wine failing to exec
    /// it. The signature check then catches the rarer case of an MSI wearing
    /// someone else's extension.
    static func detect(head: Data, pathExtension: String) -> InstallerKind {
        if pathExtension.lowercased() == "msi" { return .msiPackage }
        if hasOLESignature(head), PEInfo.architecture(of: head) == nil { return .msiPackage }
        return .executable
    }

    private static func hasOLESignature(_ data: Data) -> Bool {
        guard data.count >= oleSignature.count else { return false }
        return !oleSignature.enumerated().contains { data[data.startIndex + $0.offset] != $0.element }
    }

    /// Plain-language meaning for the documented Windows Installer exit codes.
    ///
    /// msiexec reports failures through its exit status rather than the log,
    /// so without this an MSI failure reads as a bare number. Only the codes
    /// Microsoft documents as stable are mapped; anything else returns nil and
    /// falls back to the generic advice.
    static func msiExitMeaning(_ code: Int32) -> String? {
        switch code {
        case 1602:
            "You cancelled the installer before it finished."
        case 1603:
            "The installer hit a fatal error partway through. This is the usual "
                + "MSI failure under Wine — the log names the step that failed."
        case 1618:
            "Another installation is already running in this bottle. Wait for it "
                + "to finish, or close any leftover installer window and retry."
        case 1619, 1620:
            "Windows Installer couldn't open the package — it may be corrupt, or "
                + "an incomplete download."
        case 1633:
            "The package refuses to install on this architecture."
        case 3010:
            "Installed successfully — the package wants a reboot, which a bottle "
                + "doesn't need. Treat this as success."
        default:
            nil
        }
    }
}
