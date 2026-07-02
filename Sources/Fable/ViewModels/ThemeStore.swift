import AppKit
import SwiftUI

/// The theme catalog: built-ins plus user themes imported as `.fableskin`
/// files (stored in Application Support/Themes). Also owns background images —
/// a theme's embedded one, or the user's own custom pick.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var skins: [FableSkin] = FableSkin.builtIns

    private let directory: URL
    private var imagesDirectory: URL {
        directory.appending(path: "images", directoryHint: .isDirectory)
    }

    init(directory: URL = AppPaths.themes) {
        self.directory = directory
        reload()
    }

    /// The active skin for an id (falls back to the default skin).
    func skin(id: String) -> FableSkin {
        skins.first { $0.id == id } ?? .standard
    }

    /// The effective background image: the user's custom pick wins over the
    /// theme's own.
    func backgroundImage(for skin: FableSkin, customPath: String?) -> NSImage? {
        if let customPath, let image = NSImage(contentsOfFile: customPath) { return image }
        guard let file = skin.backgroundImageFile else { return nil }
        return NSImage(contentsOf: imagesDirectory.appending(path: file))
    }

    // MARK: Import / export

    /// Imports a `.fableskin` file: stores its embedded background (if any),
    /// persists the skin, reloads, and returns it.
    @discardableResult
    func importSkin(from url: URL) throws -> FableSkin {
        let document = try JSONDecoder().decode(FableSkinDocument.self, from: Data(contentsOf: url))
        var skin = document.skin
        // Namespace imports so they can't shadow a built-in.
        if FableSkin.builtIns.contains(where: { $0.id == skin.id }) {
            skin.id = "user-\(skin.id)"
        }
        if let imageData = document.backgroundImageData {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            let filename = "\(skin.id).img"
            try imageData.write(to: imagesDirectory.appending(path: filename), options: .atomic)
            skin.backgroundImageFile = filename
        }
        try persist(skin)
        return skin
    }

    /// Encodes a skin as a shareable `.fableskin`, embedding its background
    /// image so the theme travels as one file.
    func exportData(for skin: FableSkin) throws -> Data {
        var document = FableSkinDocument(skin: skin)
        if let file = skin.backgroundImageFile {
            document.backgroundImageData = try? Data(contentsOf: imagesDirectory.appending(path: file))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// Copies a user-picked background image into the themes store and returns
    /// the stored path (so the original can move/unmount without breaking).
    func storeCustomBackground(from url: URL) throws -> String {
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        let destination = imagesDirectory.appending(path: "custom-background.img")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination.path
    }

    // MARK: Internals

    private func persist(_ skin: FableSkin) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(FableSkinDocument(skin: skin))
        try data.write(to: directory.appending(path: "\(skin.id).fableskin"), options: .atomic)
        reload()
    }

    private func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        let imported = files
            .filter { $0.pathExtension == "fableskin" }
            .compactMap { try? JSONDecoder().decode(FableSkinDocument.self, from: Data(contentsOf: $0)).skin }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        skins = FableSkin.builtIns + imported
    }
}
