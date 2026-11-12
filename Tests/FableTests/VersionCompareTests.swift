import Foundation
import Testing
@testable import Fable

@Suite struct VersionCompareNumericTests {
    @Test
    func comparesMultiDigitPartsNumerically() {
        #expect(VersionCompare.isNewer("11.10_1", than: "11.9_1"))
        #expect(VersionCompare.isNewer("10.0_10", than: "10.0_9"))
        #expect(!VersionCompare.isNewer("11.9_1", than: "11.10_1"))
    }

    @Test
    func comparesDigitsEmbeddedInLabels() {
        #expect(VersionCompare.isNewer("WS12WineSikarugir10.0_4", than: "WS12WineSikarugir9.0_1"))
        #expect(VersionCompare.isNewer("WS12WineSikarugir10.0_5", than: "WS12WineSikarugir10.0_4"))
    }

    @Test
    func releaseOutranksPrerelease() {
        #expect(VersionCompare.isNewer("11.0", than: "11.0-rc1"))
        #expect(!VersionCompare.isNewer("11.0-rc1", than: "11.0"))
    }

    @Test
    func newestPicksNumericMax() {
        #expect(VersionCompare.newest(["11.9_1", "11.10_1", "11.2_1"]) == "11.10_1")
        #expect(VersionCompare.newest([]) == nil)
    }
}

@MainActor
@Suite struct ComponentNewestDirectoryTests {
    @Test
    func installedDirectoryPicksNumericallyNewest() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appending(path: "NewestDir-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: root) }
        let manager = ComponentManager(
            componentsDirectory: root.appending(path: "Components", directoryHint: .isDirectory),
            downloadsDirectory: root.appending(path: "Downloads", directoryHint: .isDirectory)
        )
        for v in ["11.9_1", "11.10_1"] {
            try fm.createDirectory(
                at: manager.componentsDirectory.appending(path: "wine/\(v)", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
        #expect(manager.installedDirectory(for: "wine")?.lastPathComponent == "11.10_1")
    }
}
