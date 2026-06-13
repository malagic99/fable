import Foundation

enum BottleError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Bottle name can't be empty."
        case .duplicateName(let name):
            "A bottle named “\(name)” already exists."
        case .notFound:
            "This bottle no longer exists."
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

    func bottle(with id: Bottle.ID) -> Bottle? {
        bottles.first { $0.id == id }
    }

    /// The bottle's Windows C: drive on disk.
    func driveCDirectory(for bottle: Bottle) -> URL {
        prefixDirectory(for: bottle).appending(path: "drive_c", directoryHint: .isDirectory)
    }

    func addGame(_ game: Game, to id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        bottles[index].games.append(game)
        try save(bottles[index])
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

    func setPerformance(_ options: PerformanceOptions, for id: Bottle.ID) throws {
        guard let index = bottles.firstIndex(where: { $0.id == id }) else {
            throw BottleError.notFound
        }
        bottles[index].performance = options
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
