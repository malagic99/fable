import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct GameInstallerTests {
    /// Bottle manager in a temp dir with one bottle whose drive_c exists.
    private func makeBottle() throws -> (BottleManager, Bottle, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "GameInstallerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manager = BottleManager(bottlesDirectory: dir)
        let bottle = try manager.createBottle(name: "Test")
        try FileManager.default.createDirectory(
            at: manager.driveCDirectory(for: bottle),
            withIntermediateDirectories: true
        )
        return (manager, bottle, dir)
    }

    @Test
    func pathInDriveCComputesRelativePaths() {
        let driveC = URL(filePath: "/tmp/bottle/prefix/drive_c")
        #expect(GameInstaller.pathInDriveC(
            of: URL(filePath: "/tmp/bottle/prefix/drive_c/Program Files/Game/game.exe"),
            driveC: driveC
        ) == "Program Files/Game/game.exe")
        #expect(GameInstaller.pathInDriveC(
            of: URL(filePath: "/Users/someone/Downloads/game.exe"),
            driveC: driveC
        ) == nil)
        // Prefix-string lookalike must not match.
        #expect(GameInstaller.pathInDriveC(
            of: URL(filePath: "/tmp/bottle/prefix/drive_c_other/game.exe"),
            driveC: driveC
        ) == nil)
    }

    @Test
    func registerGameInsideBottlePersists() throws {
        let (manager, bottle, dir) = try makeBottle()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exe = manager.driveCDirectory(for: bottle)
            .appending(path: "Program Files/Cool Game/cool.exe")
        try FileManager.default.createDirectory(
            at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: exe)

        let game = try GameInstaller().registerGame(
            executable: exe, bottle: bottle, bottleManager: manager)

        #expect(game.name == "cool")
        #expect(game.executablePath == "Program Files/Cool Game/cool.exe")
        let reloaded = BottleManager(bottlesDirectory: dir)
        #expect(reloaded.bottle(with: bottle.id)?.games.first?.executablePath
            == "Program Files/Cool Game/cool.exe")
    }

    @Test
    func registerRejectsNonExeAndOutsideFiles() throws {
        let (manager, bottle, dir) = try makeBottle()
        defer { try? FileManager.default.removeItem(at: dir) }

        let outside = FileManager.default.temporaryDirectory.appending(path: "out-\(UUID()).exe")
        try Data("MZ".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }

        #expect(throws: GameInstallError.self) {
            try GameInstaller().registerGame(executable: outside, bottle: bottle, bottleManager: manager)
        }

        let notExe = manager.driveCDirectory(for: bottle).appending(path: "readme.txt")
        try Data("hi".utf8).write(to: notExe)
        #expect(throws: GameInstallError.self) {
            try GameInstaller().registerGame(executable: notExe, bottle: bottle, bottleManager: manager)
        }
    }

    @Test
    func importCopiesWholeFolderIntoProgramFiles() async throws {
        let (manager, bottle, dir) = try makeBottle()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Portable game folder outside the bottle.
        let gameDir = FileManager.default.temporaryDirectory
            .appending(path: "PortableGame-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: gameDir.appending(path: "data"), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: gameDir.appending(path: "run.exe"))
        try Data("assets".utf8).write(to: gameDir.appending(path: "data/assets.pak"))
        defer { try? FileManager.default.removeItem(at: gameDir) }

        let game = try await GameInstaller().importGame(
            executable: gameDir.appending(path: "run.exe"),
            mode: .wholeFolder,
            bottle: bottle,
            bottleManager: manager
        )

        let installedRoot = manager.driveCDirectory(for: bottle)
            .appending(path: "Program Files/\(gameDir.lastPathComponent)")
        #expect(FileManager.default.fileExists(atPath: installedRoot.appending(path: "run.exe").path))
        #expect(FileManager.default.fileExists(atPath: installedRoot.appending(path: "data/assets.pak").path))
        #expect(game.executablePath == "Program Files/\(gameDir.lastPathComponent)/run.exe")
        #expect(manager.bottle(with: bottle.id)?.games.count == 1)
    }

    @Test
    func importExecutableOnlyCopiesJustTheExe() async throws {
        let (manager, bottle, dir) = try makeBottle()
        defer { try? FileManager.default.removeItem(at: dir) }

        let gameDir = FileManager.default.temporaryDirectory
            .appending(path: "SoloExe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: gameDir.appending(path: "tool.exe"))
        try Data("junk".utf8).write(to: gameDir.appending(path: "unrelated.txt"))
        defer { try? FileManager.default.removeItem(at: gameDir) }

        let game = try await GameInstaller().importGame(
            executable: gameDir.appending(path: "tool.exe"),
            mode: .executableOnly,
            bottle: bottle,
            bottleManager: manager
        )

        let installedRoot = manager.driveCDirectory(for: bottle).appending(path: "Program Files/tool")
        #expect(FileManager.default.fileExists(atPath: installedRoot.appending(path: "tool.exe").path))
        #expect(!FileManager.default.fileExists(atPath: installedRoot.appending(path: "unrelated.txt").path))
        #expect(game.executablePath == "Program Files/tool/tool.exe")
    }
}
