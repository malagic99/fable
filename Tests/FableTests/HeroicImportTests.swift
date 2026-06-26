import Foundation
import Testing
@testable import Fable

/// Importing Heroic games into a bottle: symlink the install dir in, register
/// the exe, stay idempotent.
@MainActor
@Suite struct HeroicImportTests {
    private let fm = FileManager.default

    private func makeManager() -> (BottleManager, URL) {
        let root = fm.temporaryDirectory.appending(path: "HeroicImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (BottleManager(bottlesDirectory: root.appending(path: "Bottles")), root)
    }

    /// A fake Heroic install on disk: a folder with a real .exe inside.
    private func makeInstall(in root: URL, folder: String, exe: String) throws -> HeroicGame {
        let dir = root.appending(path: "HeroicGames/\(folder)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: dir.appending(path: exe))
        return HeroicGame(
            appName: folder, title: folder, runner: "legendary",
            installPath: dir, executable: exe, platform: "Windows", folderName: folder
        )
    }

    @Test
    func importSymlinksInstallDirAndRegistersExe() async throws {
        let (manager, root) = makeManager()
        defer { try? fm.removeItem(at: root) }

        let bottle = try manager.createBottle(name: "Library")
        try manager.setStatus(.ready, for: bottle.id)
        let game = try makeInstall(in: root, folder: "AbsoluteDrift", exe: "absolutedrift.exe")

        let imported = try manager.importHeroicGames([game], into: bottle.id)
        #expect(imported == ["AbsoluteDrift"])

        // Registered with a drive_c-relative path.
        let registered = manager.bottle(with: bottle.id)?.games.first
        #expect(registered?.name == "AbsoluteDrift")
        #expect(registered?.executablePath == "Heroic/AbsoluteDrift/absolutedrift.exe")

        // The exe resolves through the symlink under drive_c.
        let exe = manager.driveCDirectory(for: manager.bottle(with: bottle.id)!)
            .appending(path: registered!.executablePath)
        #expect(fm.fileExists(atPath: exe.path))
    }

    @Test
    func reimportingIsIdempotent() async throws {
        let (manager, root) = makeManager()
        defer { try? fm.removeItem(at: root) }

        let bottle = try manager.createBottle(name: "Library")
        try manager.setStatus(.ready, for: bottle.id)
        let game = try makeInstall(in: root, folder: "Doom", exe: "doom.exe")

        #expect(try manager.importHeroicGames([game], into: bottle.id).count == 1)
        // Second pass: nothing new, and no duplicate registration.
        #expect(try manager.importHeroicGames([game], into: bottle.id).isEmpty)
        #expect(manager.bottle(with: bottle.id)?.games.count == 1)
    }
}
