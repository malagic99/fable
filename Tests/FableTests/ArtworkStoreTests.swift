import AppKit
import Testing
@testable import Fable

/// ArtworkStore's cache semantics — the layer where the "custom Steam cover
/// vanished on relaunch" bug lived. Network is never touched: every test runs
/// with onlineArtwork off, exercising the disk-cache and custom-art paths.
@MainActor
@Suite struct ArtworkStoreTests {
    private let fm = FileManager.default

    private func tempDir() throws -> URL {
        let dir = fm.temporaryDirectory.appending(path: "art-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A real 4×4 JPEG so NSImage decoding succeeds.
    private func jpegFile(in dir: URL) throws -> URL {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(rep.representation(using: .jpeg, properties: [:]))
        let url = dir.appending(path: "source.jpg")
        try data.write(to: url)
        return url
    }

    private var offlineSettings: AppSettings {
        var settings = AppSettings()
        settings.onlineArtwork = false
        return settings
    }

    @Test
    func customArtSurvivesAColdStart() async throws {
        // The regression that shipped: setCustomArt persisted to disk, but a
        // fresh store never read it back for titles with nothing to fetch.
        let dir = try tempDir()
        defer { try? fm.removeItem(at: dir) }
        let source = try jpegFile(in: dir)
        let native = NativeGame(name: "Balatro", source: .steam(appID: 1))

        let store = ArtworkStore(directory: dir)
        store.setCustomArt(named: native.name, from: source)
        #expect(store.image(named: native.name) != nil)

        // Cold start: new store, memory empty — the disk cache must load,
        // even with online fetching disabled.
        try await Task.sleep(for: .milliseconds(200))  // let the detached write land
        let reopened = ArtworkStore(directory: dir)
        #expect(reopened.image(named: native.name) == nil)  // not yet loaded
        await reopened.fetchIfNeeded(native: native, settings: offlineSettings)
        #expect(reopened.image(named: native.name) != nil)
    }

    @Test
    func offlineWithEmptyCacheStaysEmpty() async throws {
        let dir = try tempDir()
        defer { try? fm.removeItem(at: dir) }
        let store = ArtworkStore(directory: dir)
        let native = NativeGame(name: "Nothing Here", source: .steam(appID: 2))
        await store.fetchIfNeeded(native: native, settings: offlineSettings)
        #expect(store.image(named: native.name) == nil)
    }

    @Test
    func customArtOverwritesAndClearsTheMissMark() async throws {
        let dir = try tempDir()
        defer { try? fm.removeItem(at: dir) }
        let store = ArtworkStore(directory: dir)
        let native = NativeGame(name: "Missed Once", source: .steam(appID: 3))

        // First pass finds nothing (offline, empty cache) — a miss is marked
        // for the session, so repeat calls short-circuit.
        await store.fetchIfNeeded(native: native, settings: offlineSettings)
        #expect(store.image(named: native.name) == nil)

        // Setting custom art must clear the mark and show immediately.
        let source = try jpegFile(in: dir)
        store.setCustomArt(named: native.name, from: source)
        #expect(store.image(named: native.name) != nil)
    }

    @Test
    func artDroppedOnDiskIsPickedUpNextFetch() async throws {
        // Offline fetches deliberately do NOT mark a miss (a miss = a failed
        // NETWORK attempt), so art that appears on disk later — another
        // device, a manual drop — loads on the next fetch without any reset.
        let dir = try tempDir()
        defer { try? fm.removeItem(at: dir) }
        let store = ArtworkStore(directory: dir)
        let native = NativeGame(name: "Late Arrival", source: .steam(appID: 4))

        await store.fetchIfNeeded(native: native, settings: offlineSettings)
        #expect(store.image(named: native.name) == nil)

        let key = GameArtwork.cacheKey(for: native.name)
        let source = try jpegFile(in: dir)
        try fm.copyItem(at: source, to: dir.appending(path: "\(key).jpg"))

        await store.fetchIfNeeded(native: native, settings: offlineSettings)
        #expect(store.image(named: native.name) != nil)

        // clearMisses stays safe to call regardless (the bulk-refresh path).
        store.clearMisses()
    }
}
