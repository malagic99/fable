import Foundation
import Testing
@testable import Fable

@Suite struct PerGameBackendOverrideTests {
    @Test
    func newGameDefaultsToInheritingBottle() {
        let game = Game(name: "TestGame", executablePath: "Game.exe")
        #expect(game.graphicsBackend == nil)
    }

    @Test
    func backendOverrideRoundTripsThroughJSON() throws {
        let original = Game(
            name: "Classic",
            executablePath: "C:/old.exe",
            graphicsBackend: .off
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Game.self, from: data)
        #expect(decoded.graphicsBackend == .off)
    }

    @Test
    func legacyGameJSONDecodesWithoutBackend() throws {
        // Games written before Day 17 had no `graphicsBackend` key.
        let legacyJSON = """
        {"id": "\(UUID().uuidString)", "name": "Legacy", "executablePath": "old.exe"}
        """
        let game = try JSONDecoder().decode(Game.self, from: Data(legacyJSON.utf8))
        #expect(game.graphicsBackend == nil)
        #expect(game.arguments == "")
    }

    @Test
    func bottleRoundTripsGameOverride() throws {
        var bottle = Bottle(name: "Shared", graphicsBackend: .dxmt)
        bottle.games = [
            Game(name: "D3D9", executablePath: "old.exe", graphicsBackend: .off),
            Game(name: "D3D11", executablePath: "new.exe"),
        ]
        let data = try JSONEncoder().encode(bottle)
        let decoded = try JSONDecoder().decode(Bottle.self, from: data)
        #expect(decoded.games.first(where: { $0.name == "D3D9" })?.graphicsBackend == .off)
        #expect(decoded.games.first(where: { $0.name == "D3D11" })?.graphicsBackend == nil)
    }

    @Test
    func shortNamesAreCompact() {
        #expect(GraphicsBackend.off.shortName == "Wine")
        #expect(GraphicsBackend.dxmt.shortName == "DXMT")
        #expect(GraphicsBackend.gptk.shortName == "GPTK")
    }
}
