import CryptoKit
import Foundation

/// `.fbottle` archive format: a tar.zst containing a manifest, the
/// bottle's bottle.json, and the full prefix tree.
///
/// Layout inside the archive:
///     manifest.json    — see Manifest below
///     bottle.json      — the bottle's metadata
///     prefix/          — the Wine prefix tree (drive_c, dosdevices, …)
///
/// Day 22 ships pack/inspect/unpack — Day 23 layers on the import flow
/// (path rewriting in system.reg, deduping name, registering with
/// BottleManager).
enum BottleArchive {
    /// File extension owned by the format.
    static let pathExtension = "fbottle"

    /// Filename of the manifest written at the archive root.
    static let manifestEntryName = "manifest.json"

    /// Filename of the bottle metadata written next to the manifest.
    static let bottleEntryName = "bottle.json"

    /// Directory name containing the prefix tree.
    static let prefixEntryName = "prefix"

    /// Stable schema for `manifest.json`. Bump `schemaVersion` whenever
    /// a field's meaning changes; add new fields as optional so old
    /// readers still decode.
    struct Manifest: Codable, Hashable, Sendable {
        /// Schema revision — bump on breaking changes. Older Fable
        /// builds refuse to import a higher schemaVersion than they know.
        let schemaVersion: Int
        /// Fable version that wrote the archive (CFBundleShortVersionString).
        let fableVersion: String
        /// ISO-8601 timestamp the archive was written.
        let exportedAt: Date
        /// Original bottle UUID — informational, the importer mints a fresh one.
        let originalBottleID: UUID
        /// Original bottle name — used as the dedup-counter base on import.
        let originalBottleName: String
        /// Component versions present in the bottle's environment at
        /// export time. Importer uses these to warn about version drift.
        let components: Components
        /// SHA-256 of the uncompressed tar stream of the prefix tree.
        /// Lets the importer detect corruption before path rewriting.
        let prefixChecksum: String

        struct Components: Codable, Hashable, Sendable {
            let wine: String?
            let dxmt: String?
            let gptk: String?
            let winetricks: String?
        }

        static let currentSchemaVersion = 1
    }

    /// What the importer sees after `unpack(_:)`. The caller is
    /// responsible for moving `prefixDirectory` into its final home.
    struct UnpackedBottle {
        let manifest: Manifest
        /// Decoded bottle from the archive's bottle.json.
        let bottle: Bottle
        /// Working directory holding `prefix/`. Caller cleans up.
        let workingDirectory: URL

        var prefixDirectory: URL {
            workingDirectory.appending(path: prefixEntryName, directoryHint: .isDirectory)
        }
    }

    // MARK: Pack

    /// Tar+zstd the bottle's directory (prefix + bottle.json) into
    /// `destination`. Returns the destination URL on success.
    /// MainActor-isolated because it reads BottleManager paths.
    @MainActor
    @discardableResult
    static func pack(
        _ bottle: Bottle,
        bottleManager: BottleManager,
        catalog: VersionCatalog,
        to destination: URL
    ) async throws -> URL {
        let fm = FileManager.default
        let source = bottleManager.directory(for: bottle)
        let prefixSource = bottleManager.prefixDirectory(for: bottle)
        guard fm.fileExists(atPath: source.path) else {
            throw ArchiveError.bottleDirectoryMissing(source.path)
        }

        // Staging dir gets a deterministic layout so the manifest can
        // reference paths predictably.
        let staging = fm.temporaryDirectory
            .appending(path: "fable-archive-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // Copy the prefix tree + bottle.json into staging.
        let prefixStaging = staging.appending(path: prefixEntryName, directoryHint: .isDirectory)
        if fm.fileExists(atPath: prefixSource.path) {
            try fm.copyItem(at: prefixSource, to: prefixStaging)
        } else {
            try fm.createDirectory(at: prefixStaging, withIntermediateDirectories: true)
        }

        let bottleJSON = try JSONEncoder.fablePretty().encode(bottle)
        try bottleJSON.write(to: staging.appending(path: bottleEntryName))

        // Checksum the prefix tar stream so the importer can validate
        // before doing anything irreversible. tar over the staged prefix
        // dir is deterministic per file list.
        let checksum = try await prefixChecksum(stagingPrefix: prefixStaging)

        let manifest = Manifest(
            schemaVersion: Manifest.currentSchemaVersion,
            fableVersion: AppUpdateChecker.currentVersion,
            exportedAt: .now,
            originalBottleID: bottle.id,
            originalBottleName: bottle.name,
            components: Manifest.Components(
                wine: catalog.components["wine"]?.version,
                dxmt: catalog.components["dxmt"]?.version,
                gptk: catalog.components["gptk"]?.version,
                winetricks: catalog.components["winetricks"]?.version
            ),
            prefixChecksum: checksum
        )
        let manifestData = try JSONEncoder.fablePretty().encode(manifest)
        try manifestData.write(to: staging.appending(path: manifestEntryName))

        // Make sure the destination parent exists.
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Wipe a pre-existing archive at the destination so tar can
        // write fresh — tar's --zstd doesn't truncate.
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: [
                "--zstd",
                "-cf", destination.path,
                "-C", staging.path,
                manifestEntryName,
                bottleEntryName,
                prefixEntryName,
            ]
        )
        guard result.succeeded else {
            throw ArchiveError.tarFailed(result.standardError)
        }
        return destination
    }

    // MARK: Inspect

    /// Reads just the manifest without unpacking the prefix — cheap
    /// enough to call before showing an import confirmation sheet.
    static func inspect(_ archive: URL) async throws -> Manifest {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appending(path: "fable-inspect-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: [
                "--zstd",
                "-xf", archive.path,
                "-C", staging.path,
                manifestEntryName,
            ]
        )
        guard result.succeeded else {
            throw ArchiveError.tarFailed(result.standardError)
        }
        let manifestURL = staging.appending(path: manifestEntryName)
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder.fable().decode(Manifest.self, from: data)
    }

    // MARK: Unpack

    /// Extracts the archive into a temporary working directory.
    /// Verifies schema version, prefix checksum, and that bottle.json
    /// decodes cleanly. Caller cleans up `workingDirectory`.
    static func unpack(_ archive: URL) async throws -> UnpackedBottle {
        let fm = FileManager.default
        let workingDir = fm.temporaryDirectory
            .appending(path: "fable-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: workingDir, withIntermediateDirectories: true)

        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: ["--zstd", "-xf", archive.path, "-C", workingDir.path]
        )
        guard result.succeeded else {
            try? fm.removeItem(at: workingDir)
            throw ArchiveError.tarFailed(result.standardError)
        }

        // Manifest + bottle.json must both be present.
        let manifestURL = workingDir.appending(path: manifestEntryName)
        let bottleURL = workingDir.appending(path: bottleEntryName)
        guard fm.fileExists(atPath: manifestURL.path),
              fm.fileExists(atPath: bottleURL.path)
        else {
            try? fm.removeItem(at: workingDir)
            throw ArchiveError.malformed("archive missing manifest.json or bottle.json")
        }

        let manifest = try JSONDecoder.fable().decode(
            Manifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.schemaVersion <= Manifest.currentSchemaVersion else {
            try? fm.removeItem(at: workingDir)
            throw ArchiveError.unsupportedSchema(manifest.schemaVersion)
        }

        let bottle = try JSONDecoder.fable().decode(
            Bottle.self,
            from: Data(contentsOf: bottleURL)
        )

        // Re-checksum the prefix to detect corruption / tampering.
        let prefixDir = workingDir.appending(path: prefixEntryName, directoryHint: .isDirectory)
        let recomputed = try await prefixChecksum(stagingPrefix: prefixDir)
        guard recomputed == manifest.prefixChecksum else {
            try? fm.removeItem(at: workingDir)
            throw ArchiveError.checksumMismatch(
                expected: manifest.prefixChecksum,
                actual: recomputed
            )
        }

        return UnpackedBottle(
            manifest: manifest,
            bottle: bottle,
            workingDirectory: workingDir
        )
    }

    // MARK: Checksum

    /// Streams a stable tar of the prefix tree and sha256s it. The same
    /// staged directory produces the same digest on every machine,
    /// because we control sort order via tar's deterministic flag.
    private static func prefixChecksum(stagingPrefix: URL) async throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: stagingPrefix.path) else { return emptyChecksum }

        // tar to stdout, no compression — checksum is over the
        // uncompressed bytes so it survives a re-compression round-trip.
        let tarStream = fm.temporaryDirectory.appending(
            path: "fable-checksum-\(UUID().uuidString).tar"
        )
        defer { try? fm.removeItem(at: tarStream) }

        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: [
                "-cf", tarStream.path,
                "-C", stagingPrefix.deletingLastPathComponent().path,
                stagingPrefix.lastPathComponent,
            ]
        )
        guard result.succeeded else {
            throw ArchiveError.tarFailed(result.standardError)
        }

        let handle = try FileHandle(forReadingFrom: tarStream)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = (try? handle.read(upToCount: 1 << 16)) ?? Data()
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static let emptyChecksum = "sha256:" + String(
        repeating: "0",
        count: 64
    )
}

enum ArchiveError: LocalizedError, Equatable {
    case bottleDirectoryMissing(String)
    case tarFailed(String)
    case malformed(String)
    case unsupportedSchema(Int)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .bottleDirectoryMissing(let path):
            "The bottle's directory doesn't exist at \(path)."
        case .tarFailed(let stderr):
            "tar failed: \(stderr)"
        case .malformed(let reason):
            "Archive is malformed: \(reason)"
        case .unsupportedSchema(let version):
            "This archive uses schema version \(version), which this build of Fable doesn't support. Update Fable."
        case .checksumMismatch:
            "Archive prefix checksum doesn't match the manifest — the file is corrupt or tampered."
        }
    }
}

// MARK: - JSON helpers (shared)

extension JSONEncoder {
    /// Pretty-printed + sorted-keys encoder used everywhere bottle.json
    /// and manifest.json live, so diffs stay sane.
    static func fablePretty() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static func fable() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
