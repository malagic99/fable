import Foundation
import Testing
@testable import Fable

/// Per-bottle Retina (HiDPI) mode persistence. Defaults OFF — Retina crisps
/// launcher/CEF UI but breaks non-HiDPI games (the Balatro corner-render).
@Suite struct BottleRetinaModeTests {

    @Test
    func defaultsToOff() {
        #expect(Bottle(name: "B").retinaMode == false)
    }

    @Test
    func roundTripsWhenEnabled() throws {
        var bottle = Bottle(name: "B")
        bottle.retinaMode = true
        let data = try JSONEncoder().encode(bottle)
        let decoded = try JSONDecoder().decode(Bottle.self, from: data)
        #expect(decoded.retinaMode == true)
    }

    @Test
    func legacyBottleWithoutFieldDecodesToOff() throws {
        // A bottle.json written before the field existed must still load,
        // defaulting Retina off (the safe, game-friendly default).
        let legacyJSON = """
        {"id": "\(UUID().uuidString)", "name": "Old", "windowsVersion": "win10",
         "createdAt": 700000000, "status": "ready", "games": [],
         "graphicsBackend": "off"}
        """
        let bottle = try JSONDecoder().decode(Bottle.self, from: Data(legacyJSON.utf8))
        #expect(bottle.retinaMode == false)
    }
}
