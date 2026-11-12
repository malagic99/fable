import Foundation
import Testing
@testable import Fable

/// v1.3, FRICL's second capability: an engine can be checked against a
/// record of what it consisted of when it was set up.
@Suite("Engine integrity manifests")
struct RuntimeManifestTests {

    /// A small engine-shaped tree: a binary, a library, and a link to it.
    private func makeEngine() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "fable-engine-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "wswine.bundle/bin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "wswine.bundle/lib"), withIntermediateDirectories: true)
        try Data("wine".utf8).write(to: root.appending(path: "wswine.bundle/bin/wine"))
        try Data("shared".utf8).write(to: root.appending(path: "wswine.bundle/lib/libd3dshared.dylib"))
        try fm.createSymbolicLink(
            atPath: root.appending(path: "wswine.bundle/lib/d3d12.so").path,
            withDestinationPath: "libd3dshared.dylib")
        return root
    }

    private func record(_ root: URL, origin: RuntimeManifest.Origin = .installed) throws -> RuntimeManifest {
        try RuntimeIntegrity.record(root: root, componentID: "sikarugir11", version: "11.0_1", origin: origin)
    }

    @Test
    func aFreshRecordVerifiesAsIntact() throws {
        let root = try makeEngine()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try record(root)

        #expect(manifest.entries.count == 3)
        #expect(manifest.entries["wswine.bundle/lib/d3d12.so"]?.link == "libd3dshared.dylib")
        #expect(manifest.entries["wswine.bundle/bin/wine"]?.sha256?.count == 64)
        // The record itself is not part of what it records.
        #expect(manifest.entries[RuntimeManifest.fileName] == nil)

        let report = try RuntimeIntegrity.verify(root: root)
        #expect(report.isIntact)
        #expect(report.checkedFiles == 3)
        #expect(report.manifestID == manifest.id)
    }

    @Test
    func everyKindOfChangeIsNamed() throws {
        let root = try makeEngine()
        defer { try? FileManager.default.removeItem(at: root) }
        try record(root)
        let fm = FileManager.default

        try Data("patched".utf8).write(to: root.appending(path: "wswine.bundle/bin/wine"))
        try fm.removeItem(at: root.appending(path: "wswine.bundle/lib/libd3dshared.dylib"))
        try Data("stray".utf8).write(to: root.appending(path: "wswine.bundle/lib/extra.dylib"))
        // The link now points elsewhere.
        try fm.removeItem(at: root.appending(path: "wswine.bundle/lib/d3d12.so"))
        try fm.createSymbolicLink(
            atPath: root.appending(path: "wswine.bundle/lib/d3d12.so").path, withDestinationPath: "extra.dylib")

        let report = try RuntimeIntegrity.verify(root: root)
        #expect(!report.isIntact)
        #expect(report.modified == ["wswine.bundle/bin/wine"])
        #expect(report.missing == ["wswine.bundle/lib/libd3dshared.dylib"])
        #expect(report.added == ["wswine.bundle/lib/extra.dylib"])
        #expect(report.relinked == ["wswine.bundle/lib/d3d12.so"])
        #expect(report.differenceCount == 4)
    }

    /// The bug class this exists for: renderer libraries that must stay links
    /// to one file were once copied as separate files, and D3D12 called a
    /// null pointer. Same bytes, different kind — still a change.
    @Test
    func aLinkReplacedByACopyOfItsTargetIsAChange() throws {
        let root = try makeEngine()
        defer { try? FileManager.default.removeItem(at: root) }
        try record(root)
        let link = root.appending(path: "wswine.bundle/lib/d3d12.so")
        try FileManager.default.removeItem(at: link)
        try Data("shared".utf8).write(to: link)

        #expect(try RuntimeIntegrity.verify(root: root).modified == ["wswine.bundle/lib/d3d12.so"])
    }

    @Test
    func theIDDependsOnContentsNotOnWhenOrWhere() throws {
        let first = try makeEngine()
        let second = try makeEngine()
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let a = try RuntimeIntegrity.record(
            root: first, componentID: "sikarugir11", version: "11.0_1", origin: .installed,
            at: Date(timeIntervalSince1970: 1))
        let b = try RuntimeIntegrity.record(
            root: second, componentID: "sikarugir11", version: "11.0_1", origin: .adopted,
            at: Date(timeIntervalSince1970: 2))
        #expect(a.id == b.id)

        try Data("different".utf8).write(to: second.appending(path: "wswine.bundle/bin/wine"))
        #expect(try record(second).id != a.id)
    }

    @Test
    func aDeliberateChangeIsRerecordedKeepingItsOrigin() throws {
        let root = try makeEngine()
        defer { try? FileManager.default.removeItem(at: root) }
        try RuntimeIntegrity.record(
            root: root, componentID: "sikarugir", version: "v", origin: .installed,
            source: ["engineArchiveSHA256": "abc"])
        try Data("gptk4".utf8).write(to: root.appending(path: "wswine.bundle/lib/libd3dshared.dylib"))
        #expect(try !RuntimeIntegrity.verify(root: root).isIntact)

        RuntimeIntegrity.rerecord(root: root, noting: ["d3dMetalFramework": "gptk4"])
        #expect(try RuntimeIntegrity.verify(root: root).isIntact)
        let manifest = try RuntimeIntegrity.load(root: root)
        #expect(manifest.origin == .installed)
        #expect(manifest.source == ["engineArchiveSHA256": "abc", "d3dMetalFramework": "gptk4"])
    }

    @Test
    func noRecordIsAnErrorNotAPass() throws {
        let root = try makeEngine()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: RuntimeIntegrity.IntegrityError.self) { try RuntimeIntegrity.verify(root: root) }
        try Data("{ not json".utf8).write(to: RuntimeIntegrity.manifestURL(in: root))
        #expect(throws: RuntimeIntegrity.IntegrityError.self) { try RuntimeIntegrity.verify(root: root) }
        // Rerecording an engine with no record must not invent one.
        try FileManager.default.removeItem(at: RuntimeIntegrity.manifestURL(in: root))
        RuntimeIntegrity.rerecord(root: root)
        #expect(!RuntimeIntegrity.hasManifest(root: root))
    }

    @Test
    func adoptionCoversOldEnginesButNotHalfBuiltOnes() throws {
        let components = FileManager.default.temporaryDirectory
            .appending(path: "fable-components-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: components) }
        let fm = FileManager.default
        func engine(_ id: String, _ version: String, marker: String?) throws -> URL {
            let root = components.appending(path: "\(id)/\(version)", directoryHint: .isDirectory)
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: root.appending(path: "wine"))
            if let marker { try Data("1".utf8).write(to: root.appending(path: marker)) }
            return root
        }
        let plain = try engine(WineManager.componentID, "11.10_1", marker: nil)
        let assembled = try engine(Sikarugir11Manager.engineComponentID, "11.0_1", marker: Sikarugir11Manager.assembledMarker)
        let halfBuilt = try engine(SikarugirManager.componentID, "WS12WineSikarugir10.0_4", marker: nil)
        let notAnEngine = try engine("winetricks", "20240105", marker: nil)

        #expect(RuntimeIntegrity.adoptUnrecordedEngines(componentsRoot: components) == 2)
        #expect(try RuntimeIntegrity.load(root: plain).origin == .adopted)
        #expect(try RuntimeIntegrity.load(root: assembled).origin == .adopted)
        #expect(!RuntimeIntegrity.hasManifest(root: halfBuilt))
        #expect(!RuntimeIntegrity.hasManifest(root: notAnEngine))
        // A second pass adopts nothing and overwrites nothing.
        #expect(RuntimeIntegrity.adoptUnrecordedEngines(componentsRoot: components) == 0)
    }

    @Test
    func theWordingSaysWhatAnAdoptedRecordCannotProve() {
        var report = RuntimeIntegrity.Report(
            manifestID: String(repeating: "a", count: 64), origin: .installed,
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000), checkedFiles: 4733)
        let installed = RuntimeIntegrity.checkLine(engineName: "Sikarugir (Wine 10)", report: report)
        #expect(!installed.isProblem)
        #expect(installed.summary.contains("4733"))
        #expect(installed.detail?.contains("aaaaaaaaaaaa") == true)

        report.origin = .adopted
        let adopted = RuntimeIntegrity.checkLine(engineName: "Wine", report: report)
        #expect(adopted.summary != installed.summary)
        #expect(adopted.summary.contains("Wine"))
        #expect(!adopted.summary.contains("%"))

        report.missing = ["a"]; report.modified = (1...9).map { "m\($0)" }
        let changed = RuntimeIntegrity.checkLine(engineName: "Wine", report: report)
        #expect(changed.isProblem)
        #expect(changed.summary.contains("10"))
        // Six paths shown, the rest counted.
        #expect(changed.detail?.components(separatedBy: "\n").count == 7)
        #expect(!changed.summary.contains("%"))
    }
}
