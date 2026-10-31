import Foundation
import Testing
@testable import Fable

/// Per-bottle "PlayStation pads as XInput" (winebus `DisableHidraw`).
/// Defaults OFF — Wine's raw pass-through is what games with native
/// PlayStation support want; XInput-only games need it on.
@Suite struct PlayStationPadsAsXInputTests {

    @Test
    func defaultsToOff() {
        #expect(Bottle(name: "B").playStationPadsAsXInput == false)
    }

    @Test
    func readsDisableHidrawFromSystemRegWinebusKeyOnly() throws {
        let fm = FileManager.default
        let prefix = fm.temporaryDirectory.appending(path: "pfx-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: prefix) }
        let systemReg = prefix.appending(path: "system.reg")
        let winebus = "[System\\\\ControlSet001\\\\Services\\\\winebus] 1790688034\n#time=1dd50154f09ffe0\n"

        // Value absent → nil.
        try (winebus + "\"Start\"=dword:00000003\n").write(to: systemReg, atomically: true, encoding: .utf8)
        #expect(WineManager.currentPlayStationPadsAsXInput(at: prefix) == nil)

        // On / off read back, the way `wine reg add` writes them.
        try (winebus + "\"DisableHidraw\"=dword:00000001\n").write(to: systemReg, atomically: true, encoding: .utf8)
        #expect(WineManager.currentPlayStationPadsAsXInput(at: prefix) == true)
        try (winebus + "\"DisableHidraw\"=dword:00000000\n").write(to: systemReg, atomically: true, encoding: .utf8)
        #expect(WineManager.currentPlayStationPadsAsXInput(at: prefix) == false)

        // The same value name under another key is not ours.
        let other = "[System\\\\ControlSet001\\\\Services\\\\winehid] 1\n\"DisableHidraw\"=dword:00000001\n"
        try (other + winebus + "\"Start\"=dword:00000003\n").write(to: systemReg, atomically: true, encoding: .utf8)
        #expect(WineManager.currentPlayStationPadsAsXInput(at: prefix) == nil)
    }

    @Test
    func roundTripsAndLegacyBottlesDecodeToOff() throws {
        var bottle = Bottle(name: "B")
        bottle.playStationPadsAsXInput = true
        let decoded = try JSONDecoder().decode(Bottle.self, from: try JSONEncoder().encode(bottle))
        #expect(decoded.playStationPadsAsXInput == true)

        let legacyJSON = """
        {"id": "\(UUID().uuidString)", "name": "Old", "windowsVersion": "win10",
         "createdAt": 700000000, "status": "ready", "games": [],
         "graphicsBackend": "off"}
        """
        let legacy = try JSONDecoder().decode(Bottle.self, from: Data(legacyJSON.utf8))
        #expect(legacy.playStationPadsAsXInput == false)
    }
}
