import Foundation

/// Which dispatch directories a Wine build uses, and whether its host side is
/// translated. The one place that knows Wine's architecture shape.
///
/// Wine splits every module into a **PE side** (the Windows guest DLL) and a
/// **Unix side** (the native `.so` that talks to the host OS), and finds them
/// through architecture-named directories: `lib/wine/x86_64-windows` and
/// `lib/wine/x86_64-unix`. Every Wine build Fable ships today is an x86_64
/// macOS binary run under Rosetta 2, so those names lived as bare string
/// literals in three different managers.
///
/// A native-ARM64 Wine keeps the PE side at `x86_64-windows` — the *guest* is
/// still Windows x86-64 code, emulated — but its Unix side becomes
/// `aarch64-unix`. Holding that in one value is what makes supporting such a
/// build a config change instead of a rewrite.
///
/// Same rule as `WineEnv` and `SteamPaths`: if a magic string shows up in two
/// files, it belongs here. See docs/FEX-MIGRATION.md.
struct WineLayout: Equatable, Sendable {
    /// Host-side dispatch directory — `x86_64-unix` or `aarch64-unix`.
    let unixDirectory: String
    /// 64-bit guest dispatch directory. Identical in both worlds: the guest
    /// stays Windows x86-64 whether it's translated by Rosetta or emulated.
    let peDirectory: String
    /// 32-bit guest dispatch directory.
    let pe32Directory: String
    /// True when the host side is x86_64 and therefore runs under Rosetta 2 on
    /// Apple Silicon. Gates the Rosetta-only env vars in ``WineEnv``.
    let isTranslatedHost: Bool

    /// Today's shape, and every shipping backend: x86_64 Wine under Rosetta 2.
    static let rosetta = WineLayout(
        unixDirectory: "x86_64-unix",
        peDirectory: "x86_64-windows",
        pe32Directory: "i386-windows",
        isTranslatedHost: true
    )

    /// Native-ARM64 Wine: the Unix half runs natively, x86 guest code is
    /// emulated. Nothing ships in this shape yet — it exists so the managers
    /// can be written against a value instead of a literal.
    static let nativeARM64 = WineLayout(
        unixDirectory: "aarch64-unix",
        peDirectory: "x86_64-windows",
        pe32Directory: "i386-windows",
        isTranslatedHost: false
    )

    /// Reads the layout off a real Wine binary's Mach-O header.
    ///
    /// Unknown or unreadable falls back to ``rosetta`` deliberately: that's
    /// every build shipping today, and guessing "native" for a binary we
    /// couldn't parse would break a working install by looking for
    /// directories that aren't there.
    static func detect(wineBinary: URL) -> WineLayout {
        guard let arch = MachOInfo.architecture(of: wineBinary) else { return .rosetta }
        return arch.needsRosetta ? .rosetta : .nativeARM64
    }

    /// One line for diagnostics and bug reports — which world a log came from.
    var diagnosticSummary: String {
        isTranslatedHost ? "Wine x86_64 (Rosetta 2)" : "Wine arm64 (native)"
    }
}
