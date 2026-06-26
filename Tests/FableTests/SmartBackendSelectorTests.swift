import Foundation
import Testing
@testable import Fable

/// The conservative auto-pick rules: act only on strong signal (a validated
/// recipe or modern-D3D markers) and only on an untouched bottle.
@Suite struct SmartBackendSelectorTests {

    private func finding(_ id: String) -> CompatibilityFinding {
        CompatibilityFinding(id: id, severity: .caveat, title: id, detail: "", suggestion: "")
    }

    // MARK: Recipe fast path

    @Test
    func recipeBackendPicksValidatedBackendForUntouchedBottle() {
        // Balatro is seeded → Sikarugir, and Sikarugir needs no install.
        let game = Game(name: "Balatro", executablePath: "Balatro.exe")
        #expect(SmartBackendSelector.recipeBackend(game: game, bottleBackend: .off) == .sikarugir)
    }

    @Test
    func recipeBackendIgnoresExplicitPerGameOverride() {
        let game = Game(name: "Balatro", executablePath: "Balatro.exe", graphicsBackend: .gptk)
        #expect(SmartBackendSelector.recipeBackend(game: game, bottleBackend: .off) == nil)
    }

    @Test
    func recipeBackendIgnoresAlreadyConfiguredBottle() {
        let game = Game(name: "Balatro", executablePath: "Balatro.exe")
        // Bottle already on a deliberate backend → leave it alone.
        #expect(SmartBackendSelector.recipeBackend(game: game, bottleBackend: .sikarugir) == nil)
        #expect(SmartBackendSelector.recipeBackend(game: game, bottleBackend: .dxmt) == nil)
    }

    @Test
    func recipeBackendExcludesDXVKRecipes() {
        // System Shock 2 is seeded → DXVK, which needs a per-bottle install, so
        // it's deliberately left to the banner's explicit flow, not auto-picked.
        let game = Game(name: "System Shock 2", executablePath: "SS2.exe")
        #expect(GameRecipeCatalog.recipe(forExecutablePath: "SS2.exe")?.backend == .dxvk)
        #expect(SmartBackendSelector.recipeBackend(game: game, bottleBackend: .off) == nil)
    }

    @Test
    func recipeBackendNilForUnknownGame() {
        let game = Game(name: "Mystery", executablePath: "mystery.exe")
        #expect(SmartBackendSelector.recipeBackend(game: game, bottleBackend: .off) == nil)
    }

    // MARK: Marker path

    @Test
    func markerBackendPicksSikarugirForStreamlineWhenAvailable() {
        let game = Game(name: "Modern", executablePath: "modern.exe")
        let backend = SmartBackendSelector.markerBackend(
            game: game, bottleBackend: .off, findings: [finding("streamline")],
            crossOverAvailable: false, sikarugirAvailable: true
        )
        #expect(backend == .sikarugir)
    }

    @Test
    func markerBackendNilWhenOnlyDXVKWouldDo() {
        // Streamline + neither Sikarugir nor CrossOver → recommendation is DXVK,
        // which we don't silently auto-install, so auto-pick stands down.
        let game = Game(name: "Modern", executablePath: "modern.exe")
        let backend = SmartBackendSelector.markerBackend(
            game: game, bottleBackend: .off, findings: [finding("streamline")],
            crossOverAvailable: false, sikarugirAvailable: false
        )
        #expect(backend == nil)
    }

    @Test
    func markerBackendNilForCleanInstall() {
        // No markers → ambiguous; leave the default and let the banner suggest.
        let game = Game(name: "Clean", executablePath: "clean.exe")
        let backend = SmartBackendSelector.markerBackend(
            game: game, bottleBackend: .off, findings: [],
            crossOverAvailable: true, sikarugirAvailable: true
        )
        #expect(backend == nil)
    }

    @Test
    func markerBackendIgnoresConfiguredBottle() {
        let game = Game(name: "Modern", executablePath: "modern.exe")
        let backend = SmartBackendSelector.markerBackend(
            game: game, bottleBackend: .sikarugir, findings: [finding("directstorage")],
            crossOverAvailable: true, sikarugirAvailable: true
        )
        #expect(backend == nil)
    }

    @Test
    func canAutoPickGuards() {
        let plain = Game(name: "A", executablePath: "a.exe")
        let overridden = Game(name: "B", executablePath: "b.exe", graphicsBackend: .dxmt)
        #expect(SmartBackendSelector.canAutoPick(game: plain, bottleBackend: .off))
        #expect(!SmartBackendSelector.canAutoPick(game: plain, bottleBackend: .gptk))
        #expect(!SmartBackendSelector.canAutoPick(game: overridden, bottleBackend: .off))
    }
}
