import Foundation
import Testing
@testable import Fable

/// Shareable recipes: export capture, file round-trip, import, and override.
@MainActor
@Suite struct UserRecipeStoreTests {
    private let fm = FileManager.default

    private func makeStore() -> (UserRecipeStore, URL) {
        let dir = fm.temporaryDirectory.appending(path: "recipes-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (UserRecipeStore(directory: dir), dir)
    }

    @Test
    func capturesAGamesEffectiveConfig() {
        var bottle = Bottle(name: "B", graphicsBackend: .sikarugir)
        bottle.performance = PerformanceOptions(metalHUD: false, metalFXUpscaling: true, frameRateCap: 60)
        let game = Game(name: "My Game", executablePath: "Game/MyGame.exe")   // inherits bottle backend

        let recipe = UserRecipeStore.recipe(from: game, in: bottle)
        #expect(recipe.name == "My Game")
        #expect(recipe.executables == ["mygame.exe"])
        #expect(recipe.backend == .sikarugir)       // inherited from the bottle
        #expect(recipe.metalFX == true)
        #expect(recipe.frameRateCap == 60)
    }

    @Test
    func perGameOverrideWinsWhenCapturing() {
        let bottle = Bottle(name: "B", graphicsBackend: .off)
        let game = Game(name: "G", executablePath: "g.exe", graphicsBackend: .dxvk)
        #expect(UserRecipeStore.recipe(from: game, in: bottle).backend == .dxvk)
    }

    @Test
    func persistReloadAndLookUp() throws {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        let recipe = GameRecipe(name: "Balatro", executables: ["balatro.exe"], backend: .sikarugir,
                                metalFX: false, frameRateCap: nil, note: "x")
        try store.persist(recipe)

        #expect(store.recipes.count == 1)
        #expect(store.recipe(forExecutablePath: "Steam/Balatro.exe")?.backend == .sikarugir)

        // A fresh store over the same directory sees the persisted recipe.
        let reopened = UserRecipeStore(directory: dir)
        #expect(reopened.recipe(forExecutablePath: "balatro.exe") != nil)
    }

    @Test
    func exportedFileImportsBackIdentically() throws {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        let recipe = GameRecipe(name: "DEATHLOOP", executables: ["deathloop.exe"], backend: .sikarugir,
                                metalFX: true, frameRateCap: 60, note: "AAA")
        let file = dir.appending(path: "shared.fablerecipe")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try UserRecipeStore.encoded(recipe).write(to: file)

        let imported = try store.importRecipe(from: file)
        #expect(imported == recipe)
        #expect(store.recipe(forExecutablePath: "deathloop.exe") == recipe)
    }

    @Test
    func malformedImportThrows() throws {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let junk = dir.appending(path: "junk.fablerecipe")
        try Data("not json".utf8).write(to: junk)
        #expect(throws: (any Error).self) { try store.importRecipe(from: junk) }
    }
}
