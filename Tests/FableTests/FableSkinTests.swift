import SwiftUI
import Testing
@testable import Fable

/// Themes: hex parsing, built-ins, the .fableskin document, and import rules.
@MainActor
@Suite struct FableSkinTests {
    private let fm = FileManager.default

    @Test
    func hexColorsParse() {
        #expect(Color(hex: "#C4B550") != nil)
        #expect(Color(hex: "3F4637") != nil)     // leading # optional
        #expect(Color(hex: "nope") == nil)
        #expect(Color(hex: "#FFF") == nil)       // shorthand not supported
    }

    @Test
    func builtInsAreDistinctAndComplete() {
        let ids = FableSkin.builtIns.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("default"))
        #expect(ids.contains("midnight"))
        #expect(ids.contains("pitch-black"))
        #expect(ids.contains("og-steam"))
        // Pitch Black is a true-black OLED theme: near-opaque #000000 wash.
        #expect(FableSkin.pitchBlack.windowTintHex == "#000000")
        #expect(FableSkin.pitchBlack.windowTintOpacity >= 0.95)
        // Every built-in's colors must actually parse.
        for skin in FableSkin.builtIns {
            #expect(Color(hex: skin.gradientStartHex) != nil, Comment(rawValue: skin.name))
            #expect(Color(hex: skin.gradientEndHex) != nil, Comment(rawValue: skin.name))
        }
        // The OG Steam skin is dark and gold — the 2004 look.
        #expect(FableSkin.ogSteam.suggestedAppearance == .dark)
        #expect(FableSkin.ogSteam.accentHex == "#C4B550")
    }

    @Test
    func skinDocumentRoundTripsThroughAFile() throws {
        let dir = fm.temporaryDirectory.appending(path: "skins-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let store = ThemeStore(directory: dir)

        var custom = FableSkin.midnight
        custom.id = "my-night"
        custom.name = "My Night"
        let file = dir.appending(path: "share.fableskin")
        try JSONEncoder().encode(FableSkinDocument(skin: custom)).write(to: file)

        let imported = try store.importSkin(from: file)
        #expect(imported.name == "My Night")
        #expect(store.skins.contains { $0.id == imported.id })

        // Export produces a decodable document again.
        let exported = try store.exportData(for: imported)
        let decoded = try JSONDecoder().decode(FableSkinDocument.self, from: exported)
        #expect(decoded.skin.name == "My Night")
    }

    @Test
    func importsCannotShadowBuiltIns() throws {
        let dir = fm.temporaryDirectory.appending(path: "skins-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let store = ThemeStore(directory: dir)

        // A malicious/clashing theme claiming the built-in "default" id gets
        // namespaced instead of replacing the stock look.
        let impostor = FableSkinDocument(skin: {
            var skin = FableSkin.ogSteam
            skin.id = "default"
            return skin
        }())
        let file = dir.appending(path: "impostor.fableskin")
        try JSONEncoder().encode(impostor).write(to: file)

        let imported = try store.importSkin(from: file)
        #expect(imported.id == "user-default")
        #expect(store.skin(id: "default").name == FableSkin.standard.name)
    }

    @Test
    func embeddedBackgroundTravelsWithTheFile() throws {
        let dir = fm.temporaryDirectory.appending(path: "skins-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let store = ThemeStore(directory: dir)

        var skin = FableSkin.standard
        skin.id = "artful"
        skin.name = "Artful"
        var document = FableSkinDocument(skin: skin)
        document.backgroundImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // fake JPEG header
        let file = dir.appending(path: "artful.fableskin")
        try JSONEncoder().encode(document).write(to: file)

        let imported = try store.importSkin(from: file)
        #expect(imported.backgroundImageFile != nil)
        let stored = dir.appending(path: "images/\(imported.backgroundImageFile!)")
        #expect(fm.fileExists(atPath: stored.path))
        // And the export embeds it back.
        let exported = try store.exportData(for: imported)
        let decoded = try JSONDecoder().decode(FableSkinDocument.self, from: exported)
        #expect(decoded.backgroundImageData == document.backgroundImageData)
    }

    // MARK: Crafted .fableskin files (path traversal)

    /// A themes folder nested two levels inside a sandbox, so a `../..`
    /// escape lands somewhere the test can see and clean up. `images/` exists
    /// up front: a `../` path only resolves through a real directory, and
    /// without it the escape tests would pass against unfixed code.
    private func nestedThemesDirectory() throws -> (sandbox: URL, themes: URL) {
        let sandbox = fm.temporaryDirectory.appending(path: "skins-\(UUID().uuidString)", directoryHint: .isDirectory)
        let themes = sandbox.appending(path: "a/themes", directoryHint: .isDirectory)
        try fm.createDirectory(at: themes.appending(path: "images"), withIntermediateDirectories: true)
        return (sandbox, themes)
    }

    @Test
    func safeFileStemRules() {
        #expect(FableSkin.isSafeFileStem("my-night"))
        #expect(FableSkin.isSafeFileStem("user-default"))
        #expect(FableSkin.isSafeFileStem("Night_2"))
        #expect(!FableSkin.isSafeFileStem(""))
        #expect(!FableSkin.isSafeFileStem(".."))
        #expect(!FableSkin.isSafeFileStem("../../escape"))
        #expect(!FableSkin.isSafeFileStem("a/b"))
        #expect(!FableSkin.isSafeFileStem(".hidden"))
        #expect(!FableSkin.isSafeFileStem("night\u{0}"))
        #expect(!FableSkin.isSafeFileStem(String(repeating: "x", count: 65)))
    }

    @Test
    func traversalIDCannotWriteOutsideTheThemesFolder() throws {
        let (sandbox, themes) = try nestedThemesDirectory()
        defer { try? fm.removeItem(at: sandbox) }
        let store = ThemeStore(directory: themes)

        var skin = FableSkin.midnight
        skin.id = "../../escape"
        var document = FableSkinDocument(skin: skin)
        document.backgroundImageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let file = sandbox.appending(path: "crafted.fableskin")
        try JSONEncoder().encode(document).write(to: file)

        let imported = try store.importSkin(from: file)

        #expect(FableSkin.isSafeFileStem(imported.id))
        #expect(!fm.fileExists(atPath: sandbox.appending(path: "escape.fableskin").path))
        #expect(!fm.fileExists(atPath: sandbox.appending(path: "a/escape.img").path))
        // The theme still imports — it just lives under a safe name.
        #expect(fm.fileExists(atPath: themes.appending(path: "\(imported.id).fableskin").path))
        #expect(store.skins.contains { $0.id == imported.id && $0.name == "Midnight" })
    }

    @Test
    func importedThemeCannotPointAtAFileItDidNotCarry() throws {
        let (sandbox, themes) = try nestedThemesDirectory()
        defer { try? fm.removeItem(at: sandbox) }
        let secret = sandbox.appending(path: "secret.txt")
        try Data("private".utf8).write(to: secret)
        let store = ThemeStore(directory: themes)

        // No embedded image, but a background "file" aimed out of images/ at
        // the sandbox's secret — re-exporting would embed it in a shareable file.
        var skin = FableSkin.standard
        skin.id = "borrower"
        skin.backgroundImageFile = "../../../secret.txt"
        let file = sandbox.appending(path: "borrower.fableskin")
        try JSONEncoder().encode(FableSkinDocument(skin: skin)).write(to: file)

        let imported = try store.importSkin(from: file)
        #expect(imported.backgroundImageFile == nil)
        let exported = try JSONDecoder().decode(
            FableSkinDocument.self, from: try store.exportData(for: imported))
        #expect(exported.backgroundImageData == nil)
    }

    @Test
    func storedThemeWithAnEscapingImageNameIsNotRead() throws {
        let (sandbox, themes) = try nestedThemesDirectory()
        defer { try? fm.removeItem(at: sandbox) }
        let secret = sandbox.appending(path: "secret.txt")
        try Data("private".utf8).write(to: secret)

        // A theme already on disk (e.g. imported by an older build) whose
        // image name escapes the images folder.
        var skin = FableSkin.standard
        skin.id = "legacy"
        skin.backgroundImageFile = "../../../secret.txt"
        try JSONEncoder().encode(FableSkinDocument(skin: skin))
            .write(to: themes.appending(path: "legacy.fableskin"))

        let store = ThemeStore(directory: themes)
        let loaded = store.skin(id: "legacy")
        #expect(loaded.name == FableSkin.standard.name)
        let exported = try JSONDecoder().decode(
            FableSkinDocument.self, from: try store.exportData(for: loaded))
        #expect(exported.backgroundImageData == nil)
    }

    @Test
    func appearanceDecodesWithDefault() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.appearance == .system)
        #expect(decoded.activeThemeID == "default")
        #expect(decoded.customBackgroundPath == nil)
    }
}
