import Foundation
import Testing
@testable import Fable

@Suite("Wine 10 shared setup")
struct Wine10SharedSetupTests {
    /// Template 1.0.10's renderer, in miniature: its `i386-windows` is a link
    /// to cnc-ddraw's DirectDraw wrapper, not D3DMetal.
    private func makeTemplate() throws -> (app: URL, renderer: URL, root: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "fable-w10-\(UUID().uuidString)", directoryHint: .isDirectory)
        let app = root.appending(path: "Template-1.0.10.app", directoryHint: .isDirectory)
        let rendererRoot = app.appending(path: "Contents/Frameworks/renderer", directoryHint: .isDirectory)
        let renderer = rendererRoot.appending(path: "d3dmetal", directoryHint: .isDirectory)
        for dir in ["wine/x86_64-windows", "wine/x86_64-unix", "external"] {
            try fm.createDirectory(at: renderer.appending(path: dir), withIntermediateDirectories: true)
        }
        try Data("pe".utf8).write(to: renderer.appending(path: "wine/x86_64-windows/d3d12.dll"))
        try Data("so".utf8).write(to: renderer.appending(path: "wine/x86_64-unix/libd3dshared.dylib"))
        try fm.createSymbolicLink(atPath: renderer.appending(path: "wine/x86_64-unix/d3d12.so").path,
                                  withDestinationPath: "libd3dshared.dylib")
        let ddraw = rendererRoot.appending(path: "cnc-ddraw/wine/i386-windows", directoryHint: .isDirectory)
        try fm.createDirectory(at: ddraw, withIntermediateDirectories: true)
        try Data("ddraw".utf8).write(to: ddraw.appending(path: "ddraw.dll"))
        try fm.createSymbolicLink(atPath: renderer.appending(path: "wine/i386-windows").path,
                                  withDestinationPath: "../../cnc-ddraw/wine/i386-windows")
        let frameworks = app.appending(path: "Contents/Frameworks", directoryHint: .isDirectory)
        try Data("lib".utf8).write(to: frameworks.appending(path: "libinotify.0.dylib"))
        try fm.createSymbolicLink(atPath: frameworks.appending(path: "libinotify.dylib").path,
                                  withDestinationPath: "libinotify.0.dylib")
        return (app, renderer, root)
    }

    @Test
    func wine10DoesNotGetTheDirectDrawWrapper() throws {
        let template = try makeTemplate()
        defer { try? FileManager.default.removeItem(at: template.root) }
        let lib = template.root.appending(path: "engine/wswine.bundle/lib", directoryHint: .isDirectory)
        try Sikarugir11Manager.overlay(renderer: template.renderer, intoLib: lib, includeI386: false)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: lib.appending(path: "wine/x86_64-windows/d3d12.dll").path))
        #expect(!fm.fileExists(atPath: lib.appending(path: "wine/i386-windows").path))
        // The renderer's libraries stay links to one image.
        #expect(try fm.destinationOfSymbolicLink(atPath: lib.appending(path: "wine/x86_64-unix/d3d12.so").path)
            == "libd3dshared.dylib")
    }

    @Test
    func supportLibrariesComeFromTheTemplatesFrameworksWithLinksKept() throws {
        let template = try makeTemplate()
        defer { try? FileManager.default.removeItem(at: template.root) }
        let lib = template.root.appending(path: "engine/wswine.bundle/lib", directoryHint: .isDirectory)
        // A dangling link already there is replaced, not an error.
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: lib.appending(path: "libinotify.dylib").path,
                                                   withDestinationPath: "gone.dylib")
        try SikarugirManager.copyTemplateSupportLibs(templateApp: template.app, intoLib: lib)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: lib.appending(path: "libinotify.0.dylib").path))
        #expect(try fm.destinationOfSymbolicLink(atPath: lib.appending(path: "libinotify.dylib").path)
            == "libinotify.0.dylib")
    }

    @Test
    func theLegacySettingIsOffByDefaultAndSurvivesOldConfigs() throws {
        #expect(AppSettings().legacyWine10EngineSetup == false)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.legacyWine10EngineSetup == false)
    }
}
