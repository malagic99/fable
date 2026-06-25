import Foundation
import Testing
@testable import Fable

/// The data-driven per-game recipe catalog — the seed of Fable's
/// compatibility knowledge base.
@Suite struct GameRecipeCatalogTests {

    @Test
    func matchesByExecutableBasenameCaseInsensitively() {
        // Full Windows path, mixed case — matches on the basename.
        let r = GameRecipeCatalog.recipe(forExecutablePath: #"Program Files (x86)\Steam\steamapps\common\Balatro\Balatro.exe"#)
        #expect(r?.name == "Balatro")
        #expect(r?.backend == .sikarugir)
    }

    @Test
    func deathloopRecipePrescribesCapAndMetalFX() {
        let r = try? #require(GameRecipeCatalog.recipe(forExecutablePath: "DEATHLOOP.exe"))
        #expect(r?.backend == .sikarugir)
        #expect(r?.performance.frameRateCap == 60)
        #expect(r?.performance.metalFXUpscaling == true)
    }

    @Test
    func unknownGameHasNoRecipe() {
        #expect(GameRecipeCatalog.recipe(forExecutablePath: "SomeRandomGame.exe") == nil)
        #expect(GameRecipeCatalog.recipe(forExecutablePath: "") == nil)
    }

    @Test
    func recipeSurfacesAsAnInfoFindingWithConfigSummary() {
        let r = try? #require(GameRecipeCatalog.recipe(forExecutablePath: "ss2.exe"))
        #expect(r?.backend == .dxvk)
        let finding = try? #require(r?.finding)
        #expect(finding?.severity == .info)
        #expect(finding?.title.contains("System Shock 2") == true)
        #expect(finding?.suggestion.contains("DXVK") == true)
    }

    @Test
    func everyRecipeHasUniqueExecutablesAndANote() {
        var seen = Set<String>()
        for recipe in GameRecipeCatalog.all {
            #expect(!recipe.note.isEmpty)
            #expect(!recipe.executables.isEmpty)
            for exe in recipe.executables {
                #expect(exe == exe.lowercased())   // stored lowercased for matching
                #expect(seen.insert(exe).inserted)  // no two recipes claim one exe
            }
        }
    }
}
