import Foundation

extension Bundle {
    /// The package's resource bundle, located the way Fable actually ships.
    ///
    /// SwiftPM's generated `Bundle.module` checks exactly two places: beside
    /// the executable (`Bundle.main.bundleURL/Fable_Fable.bundle`) and an
    /// absolute path inside the `.build` directory of the machine that
    /// compiled it. Neither describes an app bundle, where resources belong in
    /// `Contents/Resources` — so `Bundle.module` misses, falls through to the
    /// build directory, and traps with `fatalError` when that isn't there
    /// either.
    ///
    /// The failure mode is the nasty part: on the build machine the `.build`
    /// path exists, so every launch works and the bug is invisible. On any
    /// other Mac the app dies before its first window with a `SIGTRAP`, which
    /// is what shipped in v0.23.3 and, unnoticed, in the releases before it.
    ///
    /// Checked in shipping order, `Bundle.module` last so development and
    /// `swift test` keep working.
    static let fableResources: Bundle = {
        let name = "Fable_Fable.bundle"
        let candidates = [
            Bundle.main.resourceURL,    // Contents/Resources — how the .app ships
            Bundle.main.bundleURL,      // beside the executable — `swift run`
        ]
        for base in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: base.appending(path: name)) { return bundle }
        }
        return .module
    }()
}
