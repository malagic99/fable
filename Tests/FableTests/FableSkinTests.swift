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
        #expect(ids.contains("og-steam"))
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

    @Test
    func appearanceDecodesWithDefault() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.appearance == .system)
        #expect(decoded.activeThemeID == "default")
        #expect(decoded.customBackgroundPath == nil)
    }
}
