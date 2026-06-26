import Foundation
import Testing
@testable import Fable

/// Discovery + idempotency of the bundled-redist runner that closes the
/// "Steam unpacks vcredist into _CommonRedist but never runs it" gap.
@Suite struct SteamRedistInstallerTests {
    private let fm = FileManager.default

    private func makeSteamRoot() throws -> URL {
        let root = fm.temporaryDirectory
            .appending(path: "steam-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func plant(_ relativePath: String, in steamRoot: URL) throws -> URL {
        let url = steamRoot.appending(path: relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: url)
        return url
    }

    @Test
    func findsRecognizedRedistsAndIgnoresUnknownInstallers() throws {
        let root = try makeSteamRoot()
        defer { try? fm.removeItem(at: root) }

        _ = try plant("steamapps/common/MyGame/_CommonRedist/vcredist/2022/vc_redist.x64.exe", in: root)
        _ = try plant("steamapps/common/MyGame/_CommonRedist/DirectX/Jun2010/DXSETUP.exe", in: root)
        // A generic installer we don't know how to silence — must be skipped.
        _ = try plant("steamapps/common/MyGame/_CommonRedist/Weird/setup.exe", in: root)
        // A redist data file that isn't an .exe — must be skipped.
        _ = try plant("steamapps/common/MyGame/_CommonRedist/DirectX/Jun2010/dxdllreg_x86.cab", in: root)
        // The game body itself must never be walked.
        _ = try plant("steamapps/common/MyGame/Binaries/Game.exe", in: root)

        let pending = SteamRedistInstaller.pendingRedists(steamRoot: root)
        // Compare on the symlink-stable relative keys (temp dirs are /var → /private/var).
        let keys = Set(pending.map(\.key))
        #expect(keys == [
            "steamapps/common/mygame/_commonredist/vcredist/2022/vc_redist.x64.exe",
            "steamapps/common/mygame/_commonredist/directx/jun2010/dxsetup.exe",
        ])
        // VC++ ranks before DirectX in install order.
        #expect(pending.map(\.kind) == [.vcRedist, .directX])
    }

    @Test
    func skipsRedistsAlreadyRecordedInMarker() throws {
        let root = try makeSteamRoot()
        defer { try? fm.removeItem(at: root) }
        _ = try plant("steamapps/common/A/_CommonRedist/vcredist/vc_redist.x86.exe", in: root)
        _ = try plant("steamapps/common/A/_CommonRedist/vcredist/vc_redist.x64.exe", in: root)

        let first = SteamRedistInstaller.pendingRedists(steamRoot: root)
        #expect(first.count == 2)

        // Mark the first one done; only the other should remain pending.
        SteamRedistInstaller.markInstalled([first[0].key], steamRoot: root)
        let second = SteamRedistInstaller.pendingRedists(steamRoot: root)
        #expect(second.map(\.key) == [first[1].key])

        // Marking everything makes it a clean no-op (the steady state).
        SteamRedistInstaller.markInstalled(second.map(\.key), steamRoot: root)
        #expect(SteamRedistInstaller.pendingRedists(steamRoot: root).isEmpty)
    }

    @Test
    func ignoresFilesOutsideCommonRedist() throws {
        let root = try makeSteamRoot()
        defer { try? fm.removeItem(at: root) }
        // A vcredist sitting loose in the game dir (not under _CommonRedist).
        _ = try plant("steamapps/common/B/redist/vc_redist.x64.exe", in: root)
        #expect(SteamRedistInstaller.pendingRedists(steamRoot: root).isEmpty)
    }

    @Test
    func emptyWhenNoSteamappsTree() throws {
        let root = try makeSteamRoot()
        defer { try? fm.removeItem(at: root) }
        #expect(SteamRedistInstaller.pendingRedists(steamRoot: root).isEmpty)
    }
}
