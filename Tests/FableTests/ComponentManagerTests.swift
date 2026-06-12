import Foundation
import Testing
@testable import Fable

@MainActor
@Suite struct ComponentManagerTests {
    /// Creates a temp workspace with a small .tar.gz archive containing
    /// payload.txt, returning (manager, archive URL, its sha256, cleanup dir).
    private func makeFixture() async throws -> (ComponentManager, URL, String, URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appending(path: "ComponentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let contents = root.appending(path: "contents", directoryHint: .isDirectory)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("wine goes here".utf8).write(to: contents.appending(path: "payload.txt"))

        let archive = root.appending(path: "component.tar.gz")
        let tar = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: ["-czf", archive.path, "-C", contents.path, "payload.txt"]
        )
        try #require(tar.succeeded)

        let manager = ComponentManager(
            componentsDirectory: root.appending(path: "Components", directoryHint: .isDirectory),
            downloadsDirectory: root.appending(path: "Downloads", directoryHint: .isDirectory)
        )
        try fm.createDirectory(at: manager.downloadsDirectory, withIntermediateDirectories: true)

        return (manager, archive, try ChecksumVerifier.sha256(of: archive), root)
    }

    @Test
    func installsFromArchiveWithVerification() async throws {
        let (manager, archive, sha, root) = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let component = VersionCatalog.Component(
            name: "Test", version: "1.0", url: archive, sha256: sha
        )
        let installed = try await manager.install(id: "test", component: component)

        #expect(manager.state(of: "test") == .installed)
        #expect(installed == manager.installedDirectory(for: "test", version: "1.0"))
        let payload = installed.appending(path: "payload.txt")
        #expect(try String(contentsOf: payload, encoding: .utf8) == "wine goes here")
    }

    @Test
    func installIsIdempotentWhenVersionPresent() async throws {
        let (manager, archive, sha, root) = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let component = VersionCatalog.Component(
            name: "Test", version: "1.0", url: archive, sha256: sha
        )
        let first = try await manager.install(id: "test", component: component)
        // Second call must short-circuit (the archive could even be gone).
        let second = try await manager.install(id: "test", component: component)
        #expect(first == second)
    }

    @Test
    func badChecksumFailsAndInstallsNothing() async throws {
        let (manager, archive, _, root) = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let component = VersionCatalog.Component(
            name: "Test", version: "1.0", url: archive,
            sha256: String(repeating: "0", count: 64)
        )
        await #expect(throws: ChecksumError.self) {
            try await manager.install(id: "test", component: component)
        }
        #expect(manager.installedDirectory(for: "test", version: "1.0") == nil)
        if case .failed = manager.state(of: "test") {} else {
            Issue.record("expected .failed state, got \(manager.state(of: "test"))")
        }
    }

    @Test
    func corruptArchiveFailsAndInstallsNothing() async throws {
        let (manager, _, _, root) = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let bogus = root.appending(path: "bogus.tar.gz")
        try Data("not a tarball".utf8).write(to: bogus)
        let component = VersionCatalog.Component(
            name: "Test", version: "1.0", url: bogus,
            sha256: try ChecksumVerifier.sha256(of: bogus)
        )
        await #expect(throws: ComponentError.self) {
            try await manager.install(id: "test", component: component)
        }
        #expect(manager.installedDirectory(for: "test", version: "1.0") == nil)
    }
}
