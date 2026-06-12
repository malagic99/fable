import Foundation

enum ComponentState: Equatable, Sendable {
    case notInstalled
    case downloading(DownloadProgress)
    case verifying
    case extracting
    case installed
    case failed(String)
}

enum ComponentError: LocalizedError {
    case extractionFailed(String)
    case notInstalled(String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed(let detail):
            "Couldn't extract the downloaded archive: \(detail)"
        case .notInstalled(let id):
            "Component “\(id)” isn't installed yet."
        }
    }
}

/// Downloads, verifies, and extracts runtime components (Wine, DXMT).
/// Installed layout: Components/<id>/<version>/<archive contents>.
@MainActor
final class ComponentManager: ObservableObject {
    @Published private(set) var states: [String: ComponentState] = [:]

    let componentsDirectory: URL
    let downloadsDirectory: URL

    init(
        componentsDirectory: URL = AppPaths.components,
        downloadsDirectory: URL = AppPaths.downloads
    ) {
        self.componentsDirectory = componentsDirectory
        self.downloadsDirectory = downloadsDirectory
    }

    func state(of id: String) -> ComponentState {
        states[id] ?? (installedDirectory(for: id) != nil ? .installed : .notInstalled)
    }

    /// Directory of the newest installed version of a component, or nil.
    /// A version only exists on disk once extraction fully succeeded.
    func installedDirectory(for id: String) -> URL? {
        let componentDir = componentsDirectory.appending(path: id, directoryHint: .isDirectory)
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: componentDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        return versions.sorted { $0.lastPathComponent < $1.lastPathComponent }.last
    }

    func installedDirectory(for id: String, version: String) -> URL? {
        let dir = componentsDirectory
            .appending(path: id, directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Ensures `component` is installed, downloading if needed.
    /// Returns the installed version directory.
    @discardableResult
    func install(id: String, component: VersionCatalog.Component) async throws -> URL {
        if let existing = installedDirectory(for: id, version: component.version) {
            states[id] = .installed
            return existing
        }

        do {
            let archive = downloadsDirectory.appending(path: component.url.lastPathComponent)
            defer { try? FileManager.default.removeItem(at: archive) }

            // A checksum mismatch means a corrupted download — one fresh
            // attempt is worthwhile before giving up.
            do {
                try await downloadAndVerify(component, id: id, to: archive)
            } catch is ChecksumError {
                try? FileManager.default.removeItem(at: archive)
                try await downloadAndVerify(component, id: id, to: archive)
            }

            states[id] = .extracting
            let installed = try await extract(archive, id: id, version: component.version)
            states[id] = .installed
            return installed
        } catch is CancellationError {
            states[id] = .notInstalled
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            states[id] = .notInstalled
            throw CancellationError()
        } catch {
            states[id] = .failed(error.localizedDescription)
            throw error
        }
    }

    private func downloadAndVerify(
        _ component: VersionCatalog.Component,
        id: String,
        to archive: URL
    ) async throws {
        states[id] = .downloading(DownloadProgress(bytesReceived: 0, totalBytes: nil))
        try await DownloadManager.download(from: component.url, to: archive) { [weak self] progress in
            Task { @MainActor in self?.states[id] = .downloading(progress) }
        }

        if !component.sha256.isEmpty {
            states[id] = .verifying
            let expected = component.sha256
            try await Task.detached {
                try ChecksumVerifier.verify(archive, sha256: expected)
            }.value
        }
    }

    /// Extracts to a staging directory first, then moves into place, so a
    /// failed extraction never looks like an installed version.
    private func extract(_ archive: URL, id: String, version: String) async throws -> URL {
        let fm = FileManager.default
        let staging = downloadsDirectory.appending(
            path: "staging-\(id)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: ["-xf", archive.path, "-C", staging.path]
        )
        guard result.succeeded else {
            throw ComponentError.extractionFailed(result.standardError)
        }

        let destination = componentsDirectory
            .appending(path: id, directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: staging, to: destination)
        return destination
    }
}
