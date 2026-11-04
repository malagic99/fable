import Foundation
import Testing
@testable import Fable

/// Registering a game downloaded for the native Steam bridge.
@MainActor
@Suite struct SteamBridgeRegisterTests {
    private let fm = FileManager.default
    private let info = SteamAppInfo(appID: 1168880, name: "MOLEK-SYNTEZ",
                                    windowsExecutable: "MOLEK-SYNTEZ.exe", windowsArguments: "-skipintro")

    private func makeBottle() throws -> (BottleManager, Bottle, URL) {
        let root = fm.temporaryDirectory.appending(path: "BridgeRegister-\(UUID().uuidString)", directoryHint: .isDirectory)
        let manager = BottleManager(bottlesDirectory: root.appending(path: "Bottles"))
        let bottle = try manager.createBottle(name: "Library")
        try manager.setStatus(.ready, for: bottle.id)
        return (manager, manager.bottle(with: bottle.id)!, root)
    }

    private func download(_ info: SteamAppInfo, into bottle: Bottle, _ manager: BottleManager) throws {
        let exe = manager.driveCDirectory(for: bottle)
            .appending(path: "\(SteamCmd.installFolder(appID: info.appID))/\(info.windowsExecutable!)")
        try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)
    }

    @Test
    func registersTheDownloadedGameOnSikarugir() throws {
        let (manager, bottle, root) = try makeBottle()
        defer { try? fm.removeItem(at: root) }
        try download(info, into: bottle, manager)

        let game = try manager.addSteamBridgeGame(info, to: bottle.id)

        #expect(game.executablePath == "SteamBridge/1168880/MOLEK-SYNTEZ.exe")
        #expect(game.steamAppID == 1168880)
        #expect(game.graphicsBackend == .sikarugir)     // whatever the bottle's default
        #expect(game.arguments == "-skipintro")
        #expect(manager.bottle(with: bottle.id)?.games.map(\.id) == [game.id])
    }

    @Test
    func addingTheSameAppAgainUpdatesInsteadOfDuplicating() throws {
        let (manager, bottle, root) = try makeBottle()
        defer { try? fm.removeItem(at: root) }
        try download(info, into: bottle, manager)
        let first = try manager.addSteamBridgeGame(info, to: bottle.id)

        let updated = SteamAppInfo(appID: 1168880, name: "MOLEK-SYNTEZ",
                                   windowsExecutable: "MOLEK-SYNTEZ.exe", windowsArguments: "")
        let second = try manager.addSteamBridgeGame(updated, to: bottle.id)

        #expect(second.id == first.id)
        #expect(second.arguments == "")
        #expect(manager.bottle(with: bottle.id)?.games.count == 1)
    }

    @Test
    func refusesAGameThatIsntDownloaded() throws {
        let (manager, bottle, root) = try makeBottle()
        defer { try? fm.removeItem(at: root) }
        do {
            try manager.addSteamBridgeGame(info, to: bottle.id)
            Issue.record("registered a game with no files")
        } catch SteamCmdError.notDownloaded {
        } catch {
            Issue.record("expected .notDownloaded, got \(error)")
        }
        #expect(manager.bottle(with: bottle.id)?.games.isEmpty == true)
    }
}
