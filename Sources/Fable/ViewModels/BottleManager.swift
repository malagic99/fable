import Foundation

enum BottleError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case notFound
    case seedFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Bottle name can't be empty."
        case .duplicateName(let name):
            "A bottle named “\(name)” already exists."
        case .notFound:
            "This bottle no longer exists."
        case .seedFailed(let detail):
            "Couldn't clone the Steam install: \(detail)"
        }
    }
}

/// Owns the list of bottles and their on-disk representation.
/// Each bottle is a directory Bottles/<id>/ containing bottle.json;
/// the Wine prefix is created at Bottles/<id>/prefix on Day 3.
@MainActor
final class BottleManager: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []

    let bottlesDirectory: URL

    private static let metadataFilename = "bottle.json"

    init(bottlesDirectory: URL = AppPaths.bottles) {
        self.bottlesDirectory = bottlesDirectory
        loadBottles()
    }

    // MARK: Paths

    func directory(for bottle: Bottle) -> URL {
        bottlesDirectory.appending(path: bottle.id.uuidString, directoryHint: .isDirectory)
    }

    func prefixDirectory(for bottle: Bottle) -> URL {
        directory(for: bottle).appending(path: "prefix", directoryHint: .isDirectory)
    }

    // MARK: Loading

    func loadBottles() {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: bottlesDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        bottles = contents
            .compactMap { dir -> Bottle? in
                let metadata = dir.appending(path: Self.metadataFilename)
                guard let data = try? Data(contentsOf: metadata) else { return nil }
                return try? JSONDecoder().decode(Bottle.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }

        // A bottle still marked "provisioning" at load time was orphaned
        // by an app quit mid-setup — surface it as repairable.
        for index in bottles.indices where bottles[index].status == .provisioning {
            bottles[index].status = .broken
            try? save(bottles[index])
        }
    }

    // MARK: Mutations

    @discardableResult
    func createBottle(name: String, windowsVersion: WindowsVersion = .win10) throws -> Bottle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BottleError.emptyName }
        guard !bottles.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw BottleError.duplicateName(trimmed)
        }

        let bottle = Bottle(name: trimmed, windowsVersion: windowsVersion)
        try FileManager.default.createDirectory(
            at: directory(for: bottle),
            withIntermediateDirectories: true
        )
        try save(bottle)
        bottles.append(bottle)
        return bottle
    }

    func renameBottle(_ id: Bottle.ID, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BottleError.emptyName }
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        guard !bottles.contains(where: {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else {
            throw BottleError.duplicateName(trimmed)
        }

        bottles[index].name = trimmed
        try save(bottles[index])
    }

    func deleteBottle(_ id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        try FileManager.default.removeItem(at: directory(for: bottles[index]))
        bottles.remove(at: index)
    }

    /// Recursive copy of an existing bottle: same prefix, same backend,
    /// same installed games and verbs — only the id, name, and createdAt
    /// change. Callers must ensure no games are running in the source.
    @discardableResult
    func cloneBottle(_ id: Bottle.ID, newName: String) throws -> Bottle {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BottleError.emptyName }
        guard let source = bottle(with: id) else { throw BottleError.notFound }
        guard !bottles.contains(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else {
            throw BottleError.duplicateName(trimmed)
        }

        var clone = source
        clone.id = UUID()
        clone.name = trimmed
        clone.createdAt = .now
        clone.status = .ready

        let fm = FileManager.default
        try fm.createDirectory(
            at: directory(for: clone),
            withIntermediateDirectories: true
        )
        let sourcePrefix = prefixDirectory(for: source)
        let destPrefix = prefixDirectory(for: clone)
        if fm.fileExists(atPath: sourcePrefix.path) {
            try fm.copyItem(at: sourcePrefix, to: destPrefix)
            // Stale wineserver lock files from the moment of copy would
            // confuse a future launch — drop them.
            for stale in [".update-timestamp"] {
                try? fm.removeItem(at: destPrefix.appending(path: stale))
            }
        }

        try save(clone)
        bottles.append(clone)
        return clone
    }

    // MARK: Steam fast-path (clone a known-good install)

    /// A ready bottle that already holds a complete Steam install (its
    /// `steamui.dll` is present), usable as a clone donor so new Steam
    /// bottles skip the slow vcredist + corefonts + Steam-download install
    /// chain — the chain that's both slow under Rosetta and prone to hang
    /// on a dead corefonts mirror.
    func steamDonorBottle(excluding excludeID: Bottle.ID?) -> Bottle? {
        let candidates = bottles.filter { candidate in
            candidate.id != excludeID && candidate.status == .ready
                && FileManager.default.fileExists(
                    atPath: SteamPaths.uiMarker(inDriveC: driveCDirectory(for: candidate)).path)
        }
        // Prefer a donor that already has the shared "Steamworks Common
        // Redistributables" installed, so the clone inherits a working redist
        // and games don't re-trigger the (WoW64-stalling) redist install.
        return candidates.first(where: hasSteamworksRedist) ?? candidates.first
    }

    /// Whether a bottle's Steam has the shared redistributables committed.
    func hasSteamworksRedist(_ bottle: Bottle) -> Bool {
        FileManager.default.fileExists(
            atPath: SteamPaths.sharedRedist(inDriveC: driveCDirectory(for: bottle)).path)
    }

    /// Replaces `targetID`'s freshly-initialized prefix with a clone of
    /// `donorID`'s, and inherits the donor's proven graphics backend so the
    /// cloned Steam renders exactly as the donor does. Uses `cp -c`
    /// (clonefile(2), copy-on-write) — even a multi-GB Steam tree seeds in
    /// seconds with no real disk duplication, versus the 10–20 min install.
    func seedPrefix(into targetID: Bottle.ID, fromBottle donorID: Bottle.ID) async throws {
        guard let target = bottle(with: targetID), let donor = bottle(with: donorID) else {
            throw BottleError.notFound
        }
        let fm = FileManager.default
        let donorPrefix = prefixDirectory(for: donor)
        let targetPrefix = prefixDirectory(for: target)
        guard fm.fileExists(atPath: donorPrefix.path) else { throw BottleError.notFound }

        // Drop the fresh prefix and clone the donor's in its place.
        try? fm.removeItem(at: targetPrefix)
        let result = try await ProcessRunner.run(
            URL(filePath: "/bin/cp"),
            arguments: ["-c", "-R", donorPrefix.path, targetPrefix.path]
        )
        guard result.succeeded else { throw BottleError.seedFailed(result.standardError) }

        // A stale update lock captured at the copy instant confuses launch.
        try? fm.removeItem(at: targetPrefix.appending(path: ".update-timestamp"))
        // Inherit the donor's working render config.
        try setGraphics(backend: donor.graphicsBackend, for: targetID)
    }

    func bottle(with id: Bottle.ID) -> Bottle? {
        bottles.first { $0.id == id }
    }

    /// The bottle's Windows C: drive on disk.
    func driveCDirectory(for bottle: Bottle) -> URL {
        prefixDirectory(for: bottle).appending(path: "drive_c", directoryHint: .isDirectory)
    }

    /// The Steam client root inside this bottle, if Steam is installed
    /// (the dir holding `steamapps/` + `depotcache/`). nil for non-Steam bottles.
    func steamRoot(for bottle: Bottle) -> URL? {
        let driveC = driveCDirectory(for: bottle)
        return FileManager.default.fileExists(atPath: SteamPaths.uiMarker(inDriveC: driveC).path)
            ? SteamPaths.clientRoot(inDriveC: driveC) : nil
    }

    /// Finishes any Steam install that downloaded + extracted but stalled on
    /// the commit step (the WoW64 dead-service gap — see SteamInstallCommitter).
    /// Runs the filesystem work off the main actor. Returns the names committed.
    /// Caller must ensure Steam isn't running for this bottle.
    func commitStuckSteamInstalls(in bottle: Bottle) async -> [String] {
        guard let root = steamRoot(for: bottle) else { return [] }
        return await Task.detached(priority: .utility) {
            SteamInstallCommitter.commitStuckInstalls(steamRoot: root)
        }.value
    }

    /// Runs the VC++/DirectX/OpenAL redistributables Steam unpacked into a
    /// game's `_CommonRedist` but never executed (the WoW64 dead-service gap —
    /// see SteamRedistInstaller). Idempotent: a per-prefix marker records what's
    /// already run, so this is a cheap no-op after the first pass. Returns the
    /// human names of the runtimes installed this pass (empty if none pending).
    /// Caller must ensure Steam isn't running for this bottle.
    func installPendingSteamRedists(
        in bottle: Bottle,
        redistInstaller: RedistInstaller,
        wineManager: WineManager
    ) async -> [String] {
        guard let root = steamRoot(for: bottle) else { return [] }
        let pending = await Task.detached(priority: .utility) {
            SteamRedistInstaller.pendingRedists(steamRoot: root)
        }.value
        guard !pending.isEmpty else { return [] }
        do {
            try await redistInstaller.install(
                pending.map(\.url), bottle: bottle,
                bottleManager: self, wineManager: wineManager
            )
            SteamRedistInstaller.markInstalled(pending.map(\.key), steamRoot: root)
            return Array(Set(pending.map { $0.kind.displayName })).sorted()
        } catch {
            return []  // couldn't spawn the installer — leave it pending to retry next exit
        }
    }

    func addGame(_ game: Game, to id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        bottles[index].games.append(game)
        try save(bottles[index])
    }

    /// Imports installed Heroic games into a bottle by symlinking each game's
    /// install directory under `drive_c/Heroic/<folder>` (no copy — even a
    /// multi-GB game is instant) and registering its exe. Idempotent: skips a
    /// game whose exe path is already registered. Returns the titles imported.
    @discardableResult
    func importHeroicGames(_ games: [HeroicGame], into id: Bottle.ID) throws -> [String] {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        let fm = FileManager.default
        let heroicDir = driveCDirectory(for: bottles[index])
            .appending(path: "Heroic", directoryHint: .isDirectory)
        try fm.createDirectory(at: heroicDir, withIntermediateDirectories: true)

        var imported: [String] = []
        for game in games {
            let folder = game.folderName ?? game.installPath.lastPathComponent
            let link = heroicDir.appending(path: folder, directoryHint: .isDirectory)
            // Symlink the install dir in (leave an existing link/dir as-is).
            if !fm.fileExists(atPath: link.path) {
                try fm.createSymbolicLink(at: link, withDestinationURL: game.installPath)
            }
            let exePath = "Heroic/\(folder)/\(game.executable)"
            guard !bottles[index].games.contains(where: { $0.executablePath == exePath }) else { continue }
            bottles[index].games.append(Game(name: game.title, executablePath: exePath))
            imported.append(game.title)
        }
        if !imported.isEmpty { try save(bottles[index]) }
        return imported
    }

    func updateGame(_ game: Game, in id: Bottle.ID) throws {
        guard let bottleIndex = bottles.firstIndex(where: { $0.id == id }),
              let gameIndex = bottles[bottleIndex].games.firstIndex(where: { $0.id == game.id })
        else {
            throw BottleError.notFound
        }
        bottles[bottleIndex].games[gameIndex] = game
        try save(bottles[bottleIndex])
    }

    func removeGame(_ gameID: Game.ID, from id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        bottles[index].games.removeAll { $0.id == gameID }
        try save(bottles[index])
    }

    func setGraphics(backend: GraphicsBackend, config: DXMTConfig? = nil, for id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        bottles[index].graphicsBackend = backend
        if let config {
            bottles[index].dxmtConfig = config
        }
        try save(bottles[index])
    }

    func setRetinaMode(_ enabled: Bool, for id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        bottles[index].retinaMode = enabled
        try save(bottles[index])
    }

    func setPerformance(_ options: PerformanceOptions, for id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        bottles[index].performance = options
        try save(bottles[index])
    }

    /// Applies a performance preset, but only if the user hasn't customized
    /// performance yet (so we never clobber a manual tune) and the preset
    /// isn't a no-op. Returns true if applied.
    @discardableResult
    func applyPerformanceIfDefault(_ options: PerformanceOptions, for id: Bottle.ID) -> Bool {
        guard let index = bottles.firstIndex(where: { $0.id == id }),
              bottles[index].performance == PerformanceOptions(),
              options != PerformanceOptions() else { return false }
        bottles[index].performance = options
        try? save(bottles[index])
        return true
    }

    /// Applies the bottle's current backend's recommended performance
    /// defaults (e.g. 60 fps cap + MetalFX for the D3DMetal AAA path), when
    /// untuned — so heavy titles hold a steady frame rate without manual work.
    @discardableResult
    func applyRecommendedPerformanceIfDefault(for id: Bottle.ID) -> Bool {
        guard let bottle = bottle(with: id) else { return false }
        return applyPerformanceIfDefault(PerformanceOptions.recommended(for: bottle.graphicsBackend), for: id)
    }

    /// Auto-picks a graphics backend for a game about to launch from an
    /// untouched bottle, so unconfigured bottles "just work". Persists the pick
    /// as a per-game override (+ matching performance preset) and returns the
    /// game to launch. A near-instant no-op once a bottle has any deliberate
    /// backend or the game has an explicit override — see SmartBackendSelector
    /// for the (conservative) decision rules.
    func prepareSmartBackend(
        for game: Game,
        in bottle: Bottle,
        crossOverAvailable: Bool,
        sikarugirAvailable: Bool
    ) async -> Game {
        guard SmartBackendSelector.canAutoPick(game: game, bottleBackend: bottle.graphicsBackend) else {
            return game
        }

        // 1. A validated recipe is authoritative and needs no scan.
        if let backend = SmartBackendSelector.recipeBackend(game: game, bottleBackend: bottle.graphicsBackend) {
            return applyAutoBackend(
                backend,
                recipe: GameRecipeCatalog.recipe(forExecutablePath: game.executablePath),
                to: game, in: bottle
            )
        }

        // 2. Otherwise scan for markers that demand a modern backend (off-main).
        let installDir = driveCDirectory(for: bottle)
            .appending(path: (game.executablePath as NSString).deletingLastPathComponent)
        let findings = await Task.detached(priority: .userInitiated) {
            CompatibilityScanner.scan(gameDirectory: installDir)
        }.value
        if let backend = SmartBackendSelector.markerBackend(
            game: game, bottleBackend: bottle.graphicsBackend, findings: findings,
            crossOverAvailable: crossOverAvailable, sikarugirAvailable: sikarugirAvailable
        ) {
            return applyAutoBackend(backend, recipe: nil, to: game, in: bottle)
        }
        return game
    }

    /// Persists an auto-picked backend as the game's override plus the matching
    /// performance preset (the recipe's exact tuning when known, else the
    /// backend's steady-FPS default). Returns the updated game, or the original
    /// unchanged if the write failed.
    private func applyAutoBackend(
        _ backend: GraphicsBackend, recipe: GameRecipe?, to game: Game, in bottle: Bottle
    ) -> Game {
        var updated = game
        updated.graphicsBackend = backend
        do {
            try updateGame(updated, in: bottle.id)
            if let recipe {
                applyPerformanceIfDefault(recipe.performance, for: bottle.id)
            } else if backend == .sikarugir || backend == .gptk {
                applyRecommendedPerformanceIfDefault(for: bottle.id)
            }
            return updated
        } catch {
            return game
        }
    }

    func setWinetricksVerbInstalled(_ slug: String, for id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        bottles[index].installedWinetricksVerbs.insert(slug)
        try save(bottles[index])
    }

    /// Re-reads the prefix's actual Windows version (winecfg may have
    /// changed it) and updates metadata if it drifted.
    func reconcileWindowsVersion(for id: Bottle.ID) {
        guard let index = bottles.firstIndex(where: { $0.id == id }),
              bottles[index].status == .ready,
              let actual = WinePrefixInspector.windowsVersion(
                ofPrefix: prefixDirectory(for: bottles[index])
              ),
              actual != bottles[index].windowsVersion
        else { return }
        bottles[index].windowsVersion = actual
        try? save(bottles[index])
    }

    func setStatus(_ status: BottleStatus, for id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        bottles[index].status = status
        try save(bottles[index])
    }

    private func save(_ bottle: Bottle) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bottle)
        try data.write(to: directory(for: bottle).appending(path: Self.metadataFilename), options: .atomic)
    }
}
