import Foundation

/// A shareable `.fablerecipe` document — a recipe plus a schema version so old
/// files keep importing as the format evolves.
struct RecipeDocument: Codable, Sendable {
    static let currentSchema = 1
    var schemaVersion: Int = RecipeDocument.currentSchema
    var recipe: GameRecipe
}

/// User-imported game recipes — the "shareable recipes" half of the catalog.
/// A user recipe for a given exe overrides the built-in `GameRecipeCatalog`, so
/// someone can drop in a community setup and have it take effect immediately.
@MainActor
final class UserRecipeStore: ObservableObject {
    @Published private(set) var recipes: [GameRecipe] = []
    let directory: URL

    init(directory: URL = AppPaths.recipes) {
        self.directory = directory
        reload()
    }

    /// The user recipe matching an executable path (basename), if any. Robust
    /// to `/` and `\` separators, like the built-in catalog.
    func recipe(forExecutablePath path: String) -> GameRecipe? {
        let exe = (path.replacingOccurrences(of: "\\", with: "/") as NSString)
            .lastPathComponent.lowercased()
        guard !exe.isEmpty else { return nil }
        return recipes.first { $0.executables.contains(exe) }
    }

    /// Imports a `.fablerecipe` file into the user store and returns it.
    @discardableResult
    func importRecipe(from url: URL) throws -> GameRecipe {
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(RecipeDocument.self, from: data)
        try persist(document.recipe)
        return document.recipe
    }

    /// Saves a recipe into the user store (one file per recipe).
    func persist(_ recipe: GameRecipe) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoded(recipe).write(to: fileURL(for: recipe), options: .atomic)
        reload()
    }

    func remove(_ recipe: GameRecipe) {
        try? FileManager.default.removeItem(at: fileURL(for: recipe))
        reload()
    }

    /// Encodes a recipe as a shareable document — for the export save panel.
    static func encoded(_ recipe: GameRecipe) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(RecipeDocument(recipe: recipe))
    }

    /// Builds a recipe from a game's current, in-effect configuration — what
    /// "Export as Recipe" captures.
    static func recipe(from game: Game, in bottle: Bottle) -> GameRecipe {
        let exe = (game.executablePath.replacingOccurrences(of: "\\", with: "/") as NSString)
            .lastPathComponent.lowercased()
        return GameRecipe(
            name: game.name,
            executables: [exe],
            backend: game.graphicsBackend ?? bottle.graphicsBackend,
            metalFX: bottle.performance.metalFXUpscaling,
            frameRateCap: bottle.performance.frameRateCap,
            note: "Shared Fable recipe for \(game.name)."
        )
    }

    private func reload() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { recipes = []; return }
        recipes = files
            .filter { $0.pathExtension == "fablerecipe" }
            .compactMap { try? JSONDecoder().decode(RecipeDocument.self, from: Data(contentsOf: $0)).recipe }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func fileURL(for recipe: GameRecipe) -> URL {
        let slug = recipe.executables.first ?? recipe.name.lowercased()
        let safe = slug.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return directory.appending(path: "\(safe).fablerecipe")
    }
}
