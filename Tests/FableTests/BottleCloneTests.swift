import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct BottleCloneTests {
    private func makeFixture() throws -> (BottleManager, Bottle, URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BottleCloneTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bottlesDir = root.appending(path: "Bottles", directoryHint: .isDirectory)
        let bottleManager = BottleManager(bottlesDirectory: bottlesDir)
        var bottle = try bottleManager.createBottle(name: "Source")
        try bottleManager.setStatus(.ready, for: bottle.id)

        // Plant a fake prefix with a known file so the clone copies it.
        let prefix = bottleManager.prefixDirectory(for: bottle)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        try Data("hello".utf8).write(
            to: prefix.appending(path: "drive_c-test-marker.txt")
        )
        try bottleManager.setWinetricksVerbInstalled("corefonts", for: bottle.id)
        var perf = PerformanceOptions()
        perf.metalHUD = true
        try bottleManager.setPerformance(perf, for: bottle.id)

        bottle = try #require(bottleManager.bottle(with: bottle.id))
        return (bottleManager, bottle, root)
    }

    @Test
    func clonePreservesSettingsAndCopiesPrefix() throws {
        let (bottles, source, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let clone = try bottles.cloneBottle(source.id, newName: "Source Copy")

        #expect(clone.id != source.id)
        #expect(clone.name == "Source Copy")
        #expect(clone.status == .ready)
        #expect(clone.installedWinetricksVerbs == ["corefonts"])
        #expect(clone.performance.metalHUD == true)

        let clonedFile = bottles.prefixDirectory(for: clone)
            .appending(path: "drive_c-test-marker.txt")
        let bytes = try Data(contentsOf: clonedFile)
        #expect(String(decoding: bytes, as: UTF8.self) == "hello")
    }

    @Test
    func clonePersistsAcrossReload() throws {
        let (bottles, source, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let clone = try bottles.cloneBottle(source.id, newName: "Source Copy")
        let reloaded = BottleManager(bottlesDirectory: bottles.bottlesDirectory)
        #expect(reloaded.bottle(with: clone.id) != nil)
        #expect(reloaded.bottles.count == 2)
    }

    @Test
    func cloneRejectsDuplicateName() throws {
        let (bottles, source, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: BottleError.self) {
            _ = try bottles.cloneBottle(source.id, newName: "Source")
        }
    }

    @Test
    func cloneRejectsEmptyName() throws {
        let (bottles, source, root) = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: BottleError.self) {
            _ = try bottles.cloneBottle(source.id, newName: "   ")
        }
    }
}

@Suite struct BottleTemplateCatalogTests {
    @Test
    func catalogIncludesVanillaAsDefault() {
        #expect(BottleTemplateCatalog.default.isVanilla)
        #expect(BottleTemplateCatalog.all.contains(BottleTemplateCatalog.default))
    }

    @Test
    func templatesReferenceKnownDependencyIDs() {
        let knownDeps = Set(DependencyCatalog.all.map(\.id))
        for tmpl in BottleTemplateCatalog.all {
            for depID in tmpl.dependencyIDs {
                #expect(knownDeps.contains(depID), "\(tmpl.id) → unknown dep \(depID)")
            }
        }
    }

    @Test
    func steamReadyTemplateUsesSikarugirBackend() throws {
        let steam = try #require(BottleTemplateCatalog.all.first { $0.id == "steam-ready" })
        #expect(steam.graphicsBackend == .sikarugir)
        #expect(steam.winetricksVerbs.contains("steam"))
    }
}
