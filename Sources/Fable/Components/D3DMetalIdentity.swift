import Foundation

/// Identifies a D3DMetal framework by what it exports, rather than by the
/// version label of whatever is carrying it.
///
/// The label can't be trusted. Fable can overlay a newer D3DMetal onto an
/// installed Game Porting Toolkit, so a component directory named for its Wine
/// build (`3.0-3`) routinely holds a much newer renderer — and both managers
/// need to answer "which generation is this really?" to decide what it can be
/// paired with.
enum D3DMetalIdentity {

    /// Generation of a D3DMetal framework binary.
    enum Generation: Equatable {
        /// GPTK 4 and later — exports the extra `IUnknownIface` interface.
        case gptk4OrNewer
        /// Anything older, including the framework Sikarugir bundles.
        case legacy
    }

    /// Symbol GPTK 4 adds to `GFXTOSInterface` and earlier builds lack. Chosen
    /// as the tell because it is part of the exported dispatch surface, so its
    /// presence is what actually determines whether a modern Wine's dispatch
    /// can link against the framework.
    private static let gptk4Marker = Data("IUnknownIface".utf8)

    /// Reads the generation of the framework binary at `url`.
    ///
    /// Searches the Mach-O's bytes for the mangled symbol rather than shelling
    /// out to `nm`: exported names live in the string table, so the substring
    /// is present exactly when the symbol is, and this stays synchronous.
    /// Memory-mapped — these binaries are 5–8 MB.
    static func generation(of url: URL) -> Generation? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return data.range(of: gptk4Marker) != nil ? .gptk4OrNewer : .legacy
    }

    /// Convenience for a `.framework` bundle rather than its binary.
    static func generation(ofFramework framework: URL) -> Generation? {
        generation(of: framework.appending(path: "Versions/A/D3DMetal"))
    }
}
