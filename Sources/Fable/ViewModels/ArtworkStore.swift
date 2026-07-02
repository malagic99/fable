import AppKit

/// Fetches and caches cover art for games (see `GameArtwork` for the pipeline
/// order). Disk cache under Application Support/Artwork so every title is
/// fetched at most once; misses are remembered per session so we don't hammer
/// the network re-trying titles that have no art.
@MainActor
final class ArtworkStore: ObservableObject {
    @Published private(set) var images: [String: NSImage] = [:]

    private var misses: Set<String> = []
    private var inFlight: Set<String> = []
    private let directory: URL

    init(directory: URL = AppPaths.artwork) {
        self.directory = directory
    }

    /// Cached artwork for a game, if any (memory-only read — cheap per frame).
    func image(for game: Game) -> NSImage? {
        image(named: game.name)
    }

    /// Same, keyed by title — used for native games.
    func image(named name: String) -> NSImage? {
        images[GameArtwork.cacheKey(for: name)]
    }

    /// Ensures artwork for a Wine game: disk cache → Steam CDN (via the
    /// bottle's manifest appid) → keyless store search → SteamGridDB.
    func fetchIfNeeded(
        game: Game,
        bottle: Bottle,
        bottleManager: BottleManager,
        settings: AppSettings
    ) async {
        guard !GameArtwork.isSteamClient(game) else { return }
        let manifestAppID = bottleManager.steamRoot(for: bottle).flatMap {
            SteamAppManifest.appID(forExecutablePath: game.executablePath, steamRoot: $0)
        }
        await fetchIfNeeded(name: game.name, knownAppID: manifestAppID, settings: settings)
    }

    /// Ensures artwork for a native game — a native Steam title carries its
    /// appid, so its cover comes straight off the CDN.
    func fetchIfNeeded(native game: NativeGame, settings: AppSettings) async {
        await fetchIfNeeded(name: game.name, knownAppID: game.steamAppID, settings: settings)
    }

    /// The shared pipeline core. No-op when disabled, already loaded,
    /// known-missing, or in flight.
    private func fetchIfNeeded(name: String, knownAppID: Int?, settings: AppSettings) async {
        let key = GameArtwork.cacheKey(for: name)
        guard !key.isEmpty,
              images[key] == nil,
              !misses.contains(key),
              !inFlight.contains(key)
        else { return }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let file = directory.appending(path: "\(key).jpg")

        // 1. Disk cache.
        if let cached = await Self.loadImage(at: file) {
            images[key] = cached
            return
        }

        guard settings.onlineArtwork else { return }

        let manifestAppID = knownAppID
        let sgdbKey = settings.steamGridDBKey.trimmingCharacters(in: .whitespaces)

        let data = await Task.detached(priority: .utility) { () -> Data? in
            // Steam CDN via the bottle's own manifest appid.
            if let appID = manifestAppID,
               let art = await Self.download(GameArtwork.steamCoverURL(appID: appID)) {
                return art
            }
            // Keyless store search by name (Epic/GOG copies of Steam titles).
            if let search = await Self.download(GameArtwork.storeSearchURL(name: name)),
               let appID = GameArtwork.appID(fromStoreSearch: search, matching: name),
               let art = await Self.download(GameArtwork.steamCoverURL(appID: appID)) {
                return art
            }
            // SteamGridDB, when the user provided a key.
            if !sgdbKey.isEmpty,
               let search = await Self.download(GameArtwork.sgdbSearchURL(name: name), bearer: sgdbKey),
               let gameID = GameArtwork.gameID(fromSGDBSearch: search),
               let grids = await Self.download(GameArtwork.sgdbGridsURL(gameID: gameID), bearer: sgdbKey),
               let gridURL = GameArtwork.gridURL(fromSGDBGrids: grids),
               let art = await Self.download(gridURL) {
                return art
            }
            return nil
        }.value

        guard let data, let image = NSImage(data: data) else {
            misses.insert(key)
            return
        }

        images[key] = image
        // Persist for next launch.
        let dir = directory
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: Custom art

    /// Sets a user-picked image as a game's cover — copied into the cache so
    /// it persists and wins over anything the pipeline would fetch.
    func setCustomArt(for game: Game, from url: URL) {
        setCustomArt(named: game.name, from: url)
    }

    /// Same, keyed by title — used for native games.
    func setCustomArt(named name: String, from url: URL) {
        let key = GameArtwork.cacheKey(for: name)
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return }
        images[key] = image
        misses.remove(key)
        let file = directory.appending(path: "\(key).jpg")
        let dir = directory
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Drops a game's cached cover (custom or fetched) and re-runs the
    /// pipeline — the escape hatch when the fetched art is wrong.
    func refreshArt(
        for game: Game,
        bottle: Bottle,
        bottleManager: BottleManager,
        settings: AppSettings
    ) async {
        let key = GameArtwork.cacheKey(for: game.name)
        images[key] = nil
        misses.remove(key)
        try? FileManager.default.removeItem(at: directory.appending(path: "\(key).jpg"))
        await fetchIfNeeded(game: game, bottle: bottle, bottleManager: bottleManager, settings: settings)
    }

    // MARK: Internals

    nonisolated private static func loadImage(at url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        }.value
    }

    nonisolated private static func download(_ url: URL, bearer: String? = nil) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Fable", forHTTPHeaderField: "User-Agent")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
