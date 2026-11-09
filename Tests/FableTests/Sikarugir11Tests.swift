import Foundation
import Testing
@testable import Fable

@Suite struct Sikarugir11Tests {
    private let fm = FileManager.default

    @Test
    func backendRoundTripsAndCountsAsD3DMetal() throws {
        var bottle = Bottle(name: "Test")
        bottle.graphicsBackend = .sikarugir11
        let decoded = try JSONDecoder().decode(Bottle.self, from: JSONEncoder().encode(bottle))
        #expect(decoded.graphicsBackend == .sikarugir11)
        #expect(GraphicsBackend.sikarugir11.usesD3DMetal)
        #expect(GraphicsBackend.sikarugir11.shortName == "Sikarugir 11")
        #expect(GraphicsBackend.sikarugir11.displayName.contains("Wine 11"))
        // Same D3DMetal tuning as the Wine 10 path.
        #expect(PerformanceOptions.rockSolid(for: .sikarugir11).metalFXUpscaling)
    }

    @Test
    func environmentCarriesTheEngineSwitchAndNoD3DOverrides() {
        let env = Sikarugir11Manager.launchEnvironment(baseOverrides: "mscoree,mshtml=", bundleRoot: nil)
        #expect(env["SikarugirAppWine11"] != nil)
        #expect(env["WINEMSYNC"] == "1")
        #expect(env["WINEDLLOVERRIDES"] == "mscoree,mshtml=")
    }

    @Test
    func environmentPointsAtTheBundledGStreamerAndD3DMetal() throws {
        let bundle = fm.temporaryDirectory.appending(path: "sik11-\(UUID().uuidString)/wswine.bundle")
        defer { try? fm.removeItem(at: bundle.deletingLastPathComponent()) }
        let external = bundle.appending(path: "lib/external")
        try fm.createDirectory(
            at: external.appending(path: "D3DMetal.framework/Versions/A"), withIntermediateDirectories: true)
        fm.createFile(atPath: external.appending(path: "D3DMetal.framework/Versions/A/D3DMetal").path, contents: Data())
        fm.createFile(atPath: external.appending(path: "libd3dshared.dylib").path, contents: Data())

        let env = Sikarugir11Manager.launchEnvironment(baseOverrides: "", bundleRoot: bundle)
        let lib = bundle.appending(path: "lib").path
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]?.hasPrefix(lib + ":") == true)
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]?.contains("GStreamer.framework/Libraries") == true)
        #expect(env["GST_PLUGIN_PATH"] == lib + "/GStreamer.framework/Libraries/gstreamer-1.0")
        #expect(env["D3DMETAL_FRAMEWORK_PATH"]?.hasSuffix("D3DMetal.framework/Versions/A/D3DMetal") == true)
        #expect(env["CX_APPLEGPTK_LIBD3DSHARED_PATH"]?.hasSuffix("external/libd3dshared.dylib") == true)
    }

    // MARK: Registry

    private static let configuredUserReg = #"""
    WINE REGISTRY Version 2

    [Software\\Wine\\AppDefaults\\steamwebhelper.exe\\DllOverrides] 1731110000
    #time=1db32a0c0a0b2c4
    "d3d11"=""
    "d3d12"=""
    "d3d12core"=""
    "dxgi"=""
    "nvapi64"=""

    [Software\\Wine\\DllOverrides] 1731110000
    #time=1db32a0c0a0b2c4
    "d3d11"="builtin"
    "d3d12"="builtin"
    "d3d12core"="builtin"
    "dxgi"="builtin"
    "nvapi64"="builtin"
    "winemenubuilder.exe"=""
    """#

    @Test
    func registryCheckAcceptsAConfiguredPrefix() {
        #expect(!Sikarugir11Manager.needsRegistryOverrides(userReg: Self.configuredUserReg))
    }

    @Test
    func registryCheckCatchesEachMissingPiece() {
        #expect(Sikarugir11Manager.needsRegistryOverrides(userReg: ""))
        // A DXMT bottle's native override must be replaced.
        let native = Self.configuredUserReg.replacingOccurrences(
            of: #""dxgi"="builtin""#, with: #""dxgi"="native""#)
        #expect(Sikarugir11Manager.needsRegistryOverrides(userReg: native))
        // The web helper section missing one DLL.
        let partial = Self.configuredUserReg.replacingOccurrences(of: "\"d3d12core\"=\"\"\n", with: "")
        #expect(Sikarugir11Manager.needsRegistryOverrides(userReg: partial))
        // A value belonging to a later section doesn't count.
        let misplaced = """
        [Software\\\\Wine\\\\AppDefaults\\\\steamwebhelper.exe\\\\DllOverrides] 1
        [Other] 1
        "d3d11"=""
        """
        #expect(Sikarugir11Manager.needsRegistryOverrides(userReg: misplaced))
    }

    @Test
    func registryCommandsWriteBothKeys() {
        let commands = Sikarugir11Manager.registryCommands()
        #expect(commands.count == Sikarugir11Manager.builtinDLLs.count * 2)
        #expect(commands.contains(
            ["reg", "add", #"HKCU\Software\Wine\DllOverrides"#, "/v", "d3d12core", "/t", "REG_SZ", "/d", "builtin", "/f"]))
        #expect(commands.contains(
            ["reg", "add", #"HKCU\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides"#,
             "/v", "dxgi", "/t", "REG_SZ", "/d", "", "/f"]))
    }

    // MARK: Assembly

    @Test
    func overlayKeepsTheRendererLibrariesAsLinks() throws {
        let root = fm.temporaryDirectory.appending(path: "sik11-overlay-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let renderer = root.appending(path: "renderer/d3dmetal")
        let unix = renderer.appending(path: "wine/x86_64-unix")
        try fm.createDirectory(at: unix, withIntermediateDirectories: true)
        try fm.createDirectory(at: renderer.appending(path: "external"), withIntermediateDirectories: true)
        fm.createFile(atPath: renderer.appending(path: "external/libd3dshared.dylib").path, contents: Data("x".utf8))
        for name in ["d3d12.so", "dxgi.so"] {
            try fm.createSymbolicLink(
                atPath: unix.appending(path: name).path, withDestinationPath: "../../external/libd3dshared.dylib")
        }
        let lib = root.appending(path: "engine/lib")
        try fm.createDirectory(at: lib.appending(path: "wine/x86_64-unix"), withIntermediateDirectories: true)
        // An old regular file in the way gets replaced, not followed.
        fm.createFile(atPath: lib.appending(path: "wine/x86_64-unix/d3d12.so").path, contents: Data("old".utf8))

        try Sikarugir11Manager.overlay(renderer: renderer, intoLib: lib)

        for name in ["d3d12.so", "dxgi.so"] {
            let path = lib.appending(path: "wine/x86_64-unix/\(name)").path
            #expect(try fm.destinationOfSymbolicLink(atPath: path) == "../../external/libd3dshared.dylib")
        }
        #expect(fm.fileExists(atPath: lib.appending(path: "external/libd3dshared.dylib").path))
    }

    @Test
    func rendererIsFoundInNewAndOldTemplateLayouts() throws {
        let root = fm.temporaryDirectory.appending(path: "sik11-tpl-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let new = root.appending(path: "New.app")
        try fm.createDirectory(at: new.appending(path: "Contents/SharedSupport/renderer/d3dmetal"),
                               withIntermediateDirectories: true)
        let old = root.appending(path: "Old.app")
        try fm.createDirectory(at: old.appending(path: "Contents/Frameworks/renderer/d3dmetal"),
                               withIntermediateDirectories: true)
        #expect(Sikarugir11Manager.renderer(in: new)?.path.contains("SharedSupport") == true)
        #expect(Sikarugir11Manager.renderer(in: old)?.path.contains("Frameworks") == true)
        #expect(Sikarugir11Manager.renderer(in: root.appending(path: "None.app")) == nil)
    }

    @Test
    func assemblyMarkerMatchesTheTemplateVersion() throws {
        let root = fm.temporaryDirectory.appending(path: "sik11-marker-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(!Sikarugir11Manager.isAssembled(engineRoot: root, templateVersion: "1.0.27"))
        try Data("1.0.27\n".utf8).write(to: root.appending(path: Sikarugir11Manager.assembledMarker))
        #expect(Sikarugir11Manager.isAssembled(engineRoot: root, templateVersion: "1.0.27"))
        // A template bump re-assembles.
        #expect(!Sikarugir11Manager.isAssembled(engineRoot: root, templateVersion: "1.0.28"))
    }

    @Test
    func bundledCatalogPinsBothDownloads() throws {
        let catalog = try VersionCatalog.loadBundled()
        for id in [Sikarugir11Manager.engineComponentID, Sikarugir11Manager.templateComponentID] {
            let component = try #require(catalog.components[id])
            #expect(ChecksumVerifier.isPinned(component.sha256), "\(id) pinned")
            #expect(component.url.host() == "github.com", "\(id) from GitHub")
            #expect(component.url.path().hasPrefix("/Sikarugir-App/"), "\(id) from Sikarugir's org")
        }
    }

    @Test
    func aceCombat8RecipeUsesWine11() {
        let recipe = GameRecipeCatalog.recipe(
            forExecutablePath: "Program Files (x86)/Steam/steamapps/common/ACE COMBAT 8/Game/Binaries/Win64/AceCombat8.exe")
        #expect(recipe?.backend == .sikarugir11)
    }
}
