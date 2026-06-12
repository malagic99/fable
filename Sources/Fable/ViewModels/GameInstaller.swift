import Foundation

enum GameInstallError: LocalizedError {
    case notAnExecutable(String)
    case outsideBottle(String)
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAnExecutable(let name):
            "\(name) isn't a Windows executable (.exe)."
        case .outsideBottle(let name):
            "\(name) isn't inside this bottle's C: drive."
        case .copyFailed(let detail):
            "Couldn't copy the game into the bottle: \(detail)"
        }
    }
}

/// Installs games into a bottle: runs Windows installers under Wine, or
/// imports portable games by copying them into the C: drive.
@MainActor
final class GameInstaller: ObservableObject {
    /// The currently running Windows installer, if any.
    @Published private(set) var installerProcess: LaunchedProcess?
    /// 0…1 while importing a portable game into the bottle.
    @Published private(set) var copyProgress: Double?
    /// Log of the last installer run (debugging fallback).
    @Published private(set) var installerLog: URL?

    /// How much to copy when importing an executable from outside the bottle.
    enum ImportMode {
        /// Just the .exe — fine for single-file programs.
        case executableOnly
        /// The .exe's entire enclosing folder — what most games need.
        case wholeFolder
    }

    // MARK: Running Windows installers

    /// Runs an installer .exe under Wine and waits for it to finish.
    /// The installer shows its own windows; we babysit the process.
    func runInstaller(
        _ installerExe: URL,
        bottle: Bottle,
        bottleManager: BottleManager,
        wineManager: WineManager
    ) async throws -> Int32 {
        let prefix = bottleManager.prefixDirectory(for: bottle)
        var environment = wineManager.environment(forPrefix: prefix)
        environment["WINEDEBUG"] = "fixme-all"

        let log = AppPaths.logs.appending(
            path: "installer-\(bottle.name)-\(Self.timestamp()).log"
        )
        let process = try ProcessRunner.start(
            try wineManager.wineBinary(),
            arguments: [installerExe.path],
            environment: environment,
            currentDirectory: installerExe.deletingLastPathComponent(),
            redirectingOutputTo: log
        )
        installerProcess = process
        installerLog = log
        defer { installerProcess = nil }
        return await process.waitForExit()
    }

    func cancelInstaller() {
        installerProcess?.terminate()
    }

    // MARK: GOG / Inno Setup direct extraction

    /// Unpacks a GOG offline installer straight into C:\Program Files,
    /// bypassing Wine entirely. Returns the installed game directory.
    func extractInnoInstaller(
        _ installer: URL,
        bottle: Bottle,
        bottleManager: BottleManager
    ) async throws -> URL {
        let title = await InnoExtractor.gameTitle(of: installer)
            ?? installer.deletingPathExtension().lastPathComponent
        let destination = bottleManager.driveCDirectory(for: bottle)
            .appending(path: "Program Files", directoryHint: .isDirectory)
            .appending(path: title, directoryHint: .isDirectory)
        try await InnoExtractor.extract(installer, to: destination)
        return destination
    }

    // MARK: Registering and importing games

    /// Path of `executable` relative to the bottle's C: drive, or nil if
    /// it lives outside the bottle.
    nonisolated static func pathInDriveC(of executable: URL, driveC: URL) -> String? {
        let exePath = executable.standardizedFileURL.path
        let drivePath = driveC.standardizedFileURL.path + "/"
        guard exePath.hasPrefix(drivePath) else { return nil }
        return String(exePath.dropFirst(drivePath.count))
    }

    /// Registers an executable that is already inside the bottle.
    @discardableResult
    func registerGame(
        executable: URL,
        name: String? = nil,
        bottle: Bottle,
        bottleManager: BottleManager
    ) throws -> Game {
        guard executable.pathExtension.lowercased() == "exe" else {
            throw GameInstallError.notAnExecutable(executable.lastPathComponent)
        }
        guard let relative = Self.pathInDriveC(
            of: executable,
            driveC: bottleManager.driveCDirectory(for: bottle)
        ) else {
            throw GameInstallError.outsideBottle(executable.lastPathComponent)
        }

        let game = Game(
            name: name ?? executable.deletingPathExtension().lastPathComponent,
            executablePath: relative
        )
        try bottleManager.addGame(game, to: bottle.id)
        return game
    }

    /// Copies an external executable (or its whole folder) into
    /// C:\Program Files\<name>\ with progress, then registers it.
    @discardableResult
    func importGame(
        executable: URL,
        mode: ImportMode,
        bottle: Bottle,
        bottleManager: BottleManager
    ) async throws -> Game {
        guard executable.pathExtension.lowercased() == "exe" else {
            throw GameInstallError.notAnExecutable(executable.lastPathComponent)
        }

        let driveC = bottleManager.driveCDirectory(for: bottle)
        let programFiles = driveC.appending(path: "Program Files", directoryHint: .isDirectory)

        let source: URL
        let destinationName: String
        switch mode {
        case .executableOnly:
            source = executable
            destinationName = executable.deletingPathExtension().lastPathComponent
        case .wholeFolder:
            source = executable.deletingLastPathComponent()
            destinationName = source.lastPathComponent
        }
        let destination = programFiles.appending(path: destinationName, directoryHint: .isDirectory)

        copyProgress = 0
        defer { copyProgress = nil }
        do {
            try await DirectoryCopier.copy(source, to: destination) { [weak self] fraction in
                Task { @MainActor in self?.copyProgress = fraction }
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw GameInstallError.copyFailed(error.localizedDescription)
        }

        let installedExe: URL
        switch mode {
        case .executableOnly:
            installedExe = destination.appending(path: executable.lastPathComponent)
        case .wholeFolder:
            installedExe = destination.appending(path: executable.lastPathComponent)
        }
        return try registerGame(
            executable: installedExe,
            name: executable.deletingPathExtension().lastPathComponent,
            bottle: bottle,
            bottleManager: bottleManager
        )
    }

    nonisolated static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }
}
