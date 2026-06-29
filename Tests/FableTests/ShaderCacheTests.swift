import Foundation
import Testing
@testable import Fable

/// Locating wine/D3DMetal shader caches — and never grabbing Apple/system or
/// the shared global Metal cache.
@Suite struct ShaderCacheTests {
    private let fm = FileManager.default

    private func makeCacheRoot(_ dirsWithMetal: [String], _ dirsWithout: [String] = []) throws -> URL {
        let root = fm.temporaryDirectory.appending(path: "C-\(UUID().uuidString)", directoryHint: .isDirectory)
        for name in dirsWithMetal {
            let metal = root.appending(path: "\(name)/com.apple.metal", directoryHint: .isDirectory)
            try fm.createDirectory(at: metal, withIntermediateDirectories: true)
            try Data(count: 1024).write(to: metal.appending(path: "functions.data"))
        }
        for name in dirsWithout {
            try fm.createDirectory(at: root.appending(path: name, directoryHint: .isDirectory), withIntermediateDirectories: true)
        }
        return root
    }

    @Test
    func identifiesWineCacheNames() {
        #expect(ShaderCache.isWineCacheName("com.Steambuild3264bitMetal683364419.wineskin"))
        #expect(ShaderCache.isWineCacheName("org.winehq.wine"))
        #expect(!ShaderCache.isWineCacheName("com.apple.metal"))           // global shared cache
        #expect(!ShaderCache.isWineCacheName("com.apple.CoreLocationAgent")) // system app
        #expect(!ShaderCache.isWineCacheName("com.apple.Safari"))
    }

    @Test
    func findsOnlyWineMetalCaches() throws {
        let root = try makeCacheRoot(
            ["com.Steambuild3264bitMetal1.wineskin", "com.apple.CoreLocationAgent", "com.apple.metal"],
            ["com.someapp.notmetal"]
        )
        defer { try? fm.removeItem(at: root) }

        let found = ShaderCache.wineMetalCaches(in: root).map(\.lastPathComponent)
        #expect(found == ["com.Steambuild3264bitMetal1.wineskin"])
    }

    @Test
    func requiresAnActualMetalSubfolder() throws {
        // A wine-named dir without a com.apple.metal subfolder isn't a cache.
        let root = try makeCacheRoot([], ["com.bare.wineskin"])
        defer { try? fm.removeItem(at: root) }
        #expect(ShaderCache.wineMetalCaches(in: root).isEmpty)
    }

    @Test
    func totalSizeSumsTheCaches() throws {
        let root = try makeCacheRoot(["com.a.wine", "com.b.wineskin"])
        defer { try? fm.removeItem(at: root) }
        let size = ShaderCache.totalSize(of: ShaderCache.wineMetalCaches(in: root))
        #expect(size >= 2048)   // two 1 KB function blobs, at least
    }

    @Test
    func emptyOnMissingCacheRoot() {
        let missing = fm.temporaryDirectory.appending(path: "nope-\(UUID().uuidString)")
        #expect(ShaderCache.wineMetalCaches(in: missing).isEmpty)
    }
}
