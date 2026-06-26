import Foundation
import Testing
@testable import Fable

/// The Steam-bottle clone fast path: instead of re-running the slow
/// vcredist + corefonts + Steam-download install chain, a new Steam bottle
/// clones an existing complete Steam install (APFS clonefile) and inherits
/// its working graphics backend.
@MainActor
@Suite struct SteamFastPathTests {

    private func makeManager() -> (BottleManager, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SteamFastPath-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (BottleManager(bottlesDirectory: root.appending(path: "Bottles")), root)
    }

    /// Plant the marker file the donor detection looks for.
    private func plantSteam(in bottle: Bottle, manager: BottleManager) throws {
        let steamDir = manager.driveCDirectory(for: bottle)
            .appending(path: "Program Files (x86)/Steam", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: steamDir, withIntermediateDirectories: true)
        try Data("steamui".utf8).write(to: steamDir.appending(path: "steamui.dll"))
    }

    @Test
    func steamTemplateIsEligibleForFastPath() {
        let steam = BottleTemplateCatalog.all.first { $0.id == "steam-ready" }
        #expect(steam?.installsSteam == true)
        // Steam needs Sikarugir to render its CEF login (not DXMT).
        #expect(steam?.graphicsBackend == .sikarugir)
        // A non-Steam template is not eligible.
        let vanilla = BottleTemplateCatalog.all.first { $0.isVanilla }
        #expect(vanilla?.installsSteam == false)
    }

    @Test
    func donorDetectionFindsCompleteSteamInstallAndExcludesTarget() throws {
        let (manager, root) = makeManager()
        defer { try? FileManager.default.removeItem(at: root) }

        let donor = try manager.createBottle(name: "Has Steam")
        try manager.setStatus(.ready, for: donor.id)
        try plantSteam(in: donor, manager: manager)
        let target = try manager.createBottle(name: "New Steam")
        try manager.setStatus(.ready, for: target.id)

        // Found, and the target itself is never offered as its own donor.
        #expect(manager.steamDonorBottle(excluding: target.id)?.id == donor.id)
        #expect(manager.steamDonorBottle(excluding: donor.id) == nil)
    }

    @Test
    func donorDetectionIgnoresBottlesWithoutSteam() throws {
        let (manager, root) = makeManager()
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = try manager.createBottle(name: "No Steam")
        try manager.setStatus(.ready, for: plain.id)
        #expect(manager.steamDonorBottle(excluding: nil) == nil)
    }

    @Test
    func donorPrefersOneWithSharedRedist() throws {
        let (manager, root) = makeManager()
        defer { try? FileManager.default.removeItem(at: root) }

        // Plain Steam bottle created first (so naive order would pick it)…
        let plain = try manager.createBottle(name: "Steam no redist")
        try manager.setStatus(.ready, for: plain.id)
        try plantSteam(in: plain, manager: manager)
        // …and one that also has the shared redist installed.
        let withRedist = try manager.createBottle(name: "Steam with redist")
        try manager.setStatus(.ready, for: withRedist.id)
        try plantSteam(in: withRedist, manager: manager)
        let redist = manager.driveCDirectory(for: withRedist)
            .appending(path: "Program Files (x86)/Steam/steamapps/common/Steamworks Shared/_CommonRedist",
                       directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: redist, withIntermediateDirectories: true)

        // The redist-complete donor wins, so clones inherit a working redist.
        #expect(manager.steamDonorBottle(excluding: nil)?.id == withRedist.id)
        #expect(manager.hasSteamworksRedist(withRedist) == true)
        #expect(manager.hasSteamworksRedist(plain) == false)
    }

    @Test
    func seedPrefixClonesDonorAndInheritsBackend() async throws {
        let (manager, root) = makeManager()
        defer { try? FileManager.default.removeItem(at: root) }

        // Donor: a complete Steam install on the Sikarugir backend.
        let donor = try manager.createBottle(name: "Donor")
        try manager.setStatus(.ready, for: donor.id)
        try plantSteam(in: donor, manager: manager)
        try Data("save".utf8).write(
            to: manager.driveCDirectory(for: donor).appending(path: "marker.txt")
        )
        try manager.setGraphics(backend: .sikarugir, for: donor.id)

        // Target: a fresh bottle on a different backend.
        let target = try manager.createBottle(name: "Target")
        try manager.setStatus(.ready, for: target.id)
        try manager.setGraphics(backend: .off, for: target.id)
        // Give it a throwaway prefix that should be replaced by the clone.
        let targetPrefix = manager.prefixDirectory(for: target)
        try FileManager.default.createDirectory(at: targetPrefix, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: targetPrefix.appending(path: "old.txt"))

        try await manager.seedPrefix(into: target.id, fromBottle: donor.id)

        // The donor's files are now in the target; the stale prefix is gone.
        let clonedMarker = manager.driveCDirectory(for: target).appending(path: "marker.txt")
        #expect(FileManager.default.fileExists(atPath: clonedMarker.path))
        #expect(!FileManager.default.fileExists(atPath: targetPrefix.appending(path: "old.txt").path))
        // And the proven backend was inherited.
        #expect(manager.bottle(with: target.id)?.graphicsBackend == .sikarugir)
    }
}
