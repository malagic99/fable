import CryptoKit
import Foundation

/// What an installed engine consists of: every file's hash, every symlink's
/// target, and where it came from. FRICL's second capability — "installed"
/// is not "intact", and until now Fable could tell neither a damaged engine
/// nor an altered one from a good one.
///
/// The catalog (`versions.json`) says what can be downloaded. A manifest says
/// what is on disk, after assembly: an engine is an archive plus a renderer
/// laid over it plus an rpath patch, so no download checksum describes it.
///
/// Stored as `.fable-manifest.json` in the engine's version directory.
struct RuntimeManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let fileName = ".fable-manifest.json"

    /// How far the record can be trusted.
    enum Origin: String, Codable, Sendable {
        /// Written by Fable right after it installed and assembled the
        /// engine from checksum-pinned downloads.
        case installed
        /// Written later, from an engine that was already on disk. It records
        /// what was there, and can catch changes from then on — it cannot say
        /// the engine was right to begin with.
        case adopted
    }

    struct Entry: Codable, Equatable, Sendable {
        /// SHA-256 of a regular file's contents.
        var sha256: String?
        var size: Int64?
        /// A symlink's target, exactly as stored. Recorded because some
        /// renderer libraries must stay links to one file: copied as separate
        /// files they load as separate images and D3D12 calls a null pointer.
        var link: String?
    }

    var schemaVersion = currentSchemaVersion
    var componentID: String
    var version: String
    var origin: Origin
    var createdAt: Date
    /// The Fable version that wrote this.
    var fableVersion: String?
    /// Where the parts came from: download checksums, the template version.
    var source: [String: String]
    /// Path relative to the engine's version directory → what is there.
    var entries: [String: Entry]

    /// A stable fingerprint of the contents: same files, same id, whenever
    /// and wherever the manifest was written.
    var id: String {
        var hasher = SHA256()
        for path in entries.keys.sorted() {
            let entry = entries[path]!
            hasher.update(data: Data("\(path)\u{0}\(entry.sha256 ?? "")\u{0}\(entry.link ?? "")\n".utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    var shortID: String { String(id.prefix(12)) }
}

/// Records and checks engines against their manifests.
enum RuntimeIntegrity {
    /// The result of checking an engine against its manifest.
    struct Report: Equatable, Sendable {
        var manifestID: String
        var origin: RuntimeManifest.Origin
        var recordedAt: Date
        var checkedFiles: Int
        /// In the manifest, not on disk.
        var missing: [String] = []
        /// On disk with different contents (or a file where a link was, or
        /// the reverse).
        var modified: [String] = []
        /// A symlink pointing somewhere else than recorded.
        var relinked: [String] = []
        /// On disk, not in the manifest.
        var added: [String] = []

        var isIntact: Bool { missing.isEmpty && modified.isEmpty && relinked.isEmpty && added.isEmpty }
        var differenceCount: Int { missing.count + modified.count + relinked.count + added.count }
    }

    enum IntegrityError: LocalizedError {
        case noManifest
        case unreadableManifest

        var errorDescription: String? {
            switch self {
            case .noManifest: L10n.string("integrity.error.no_manifest")
            case .unreadableManifest: L10n.string("integrity.error.unreadable_manifest")
            }
        }
    }

    // MARK: Snapshot

    /// Everything under `root`: regular files hashed, symlinks by target.
    /// Symlinks are never followed, so a link out of the engine is recorded,
    /// not walked. The manifest file itself is left out.
    static func snapshot(of root: URL) throws -> [String: RuntimeManifest.Entry] {
        let fm = FileManager.default
        let base = root.standardizedFileURL.path
        var entries: [String: RuntimeManifest.Entry] = [:]
        guard let enumerator = fm.enumerator(atPath: base) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        while let relative = enumerator.nextObject() as? String {
            guard relative != RuntimeManifest.fileName else { continue }
            let path = base + "/" + relative
            let attributes = try fm.attributesOfItem(atPath: path)
            switch attributes[.type] as? FileAttributeType {
            case .typeSymbolicLink:
                entries[relative] = .init(link: try fm.destinationOfSymbolicLink(atPath: path))
            case .typeRegular:
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                entries[relative] = .init(sha256: try sha256(ofFileAt: path), size: size)
            default:
                continue    // directories carry nothing of their own
            }
        }
        return entries
    }

    static func sha256(ofFileAt path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(filePath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Record

    /// Writes the manifest for the engine at `root`, replacing any old one.
    /// Call only once the engine is fully installed and assembled.
    @discardableResult
    static func record(
        root: URL, componentID: String, version: String,
        origin: RuntimeManifest.Origin, source: [String: String] = [:], at date: Date = .now
    ) throws -> RuntimeManifest {
        let manifest = RuntimeManifest(
            componentID: componentID, version: version, origin: origin, createdAt: date,
            fableVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            source: source, entries: try snapshot(of: root))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: manifestURL(in: root), options: .atomic)
        return manifest
    }

    /// Re-records an engine Fable itself just changed (a renderer swap),
    /// keeping where it came from. No-op for an engine with no manifest yet.
    static func rerecord(root: URL, noting changes: [String: String] = [:]) {
        guard let existing = try? load(root: root) else { return }
        _ = try? record(
            root: root, componentID: existing.componentID, version: existing.version,
            origin: existing.origin, source: existing.source.merging(changes) { _, new in new })
    }

    /// ``record(root:componentID:version:origin:source:at:)`` off the calling
    /// actor: hashing an engine is a few hundred MB of reading. A failure to
    /// record never fails the install it follows — the engine works without a
    /// manifest, it just can't be checked.
    static func recordDetached(
        root: URL, componentID: String, version: String,
        origin: RuntimeManifest.Origin, source: [String: String] = [:]
    ) async {
        await Task.detached(priority: .utility) {
            _ = try? record(root: root, componentID: componentID, version: version, origin: origin, source: source)
        }.value
    }

    /// Engines Fable manages, by component id — the ones worth a manifest.
    static let engineComponentIDs = [
        WineManager.componentID, GPTKManager.componentID, SikarugirManager.componentID,
        Sikarugir11Manager.engineComponentID, InstallerEngineManager.componentID,
    ]

    /// Engines that are an archive and nothing more, so they can be recorded
    /// the moment they're extracted. The others are assembled afterwards and
    /// recorded by their managers once that's done.
    static let plainEngineComponentIDs: Set<String> = [WineManager.componentID, GPTKManager.componentID]

    /// Gives every installed engine version that has no manifest an `adopted`
    /// one — engines from before v1.3. Half-assembled engines are skipped:
    /// a manifest of a broken engine would bless it. Returns how many were
    /// adopted.
    @discardableResult
    static func adoptUnrecordedEngines(componentsRoot: URL = AppPaths.components) -> Int {
        let fm = FileManager.default
        var adopted = 0
        for id in engineComponentIDs {
            let componentRoot = componentsRoot.appending(path: id, directoryHint: .isDirectory)
            for version in (try? fm.contentsOfDirectory(atPath: componentRoot.path)) ?? [] where !version.hasPrefix(".") {
                let root = componentRoot.appending(path: version, directoryHint: .isDirectory)
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
                      !hasManifest(root: root), isFullyAssembled(componentID: id, root: root)
                else { continue }
                if (try? record(root: root, componentID: id, version: version, origin: .adopted)) != nil {
                    adopted += 1
                }
            }
        }
        return adopted
    }

    /// Whether an engine directory is finished. Assembled engines write a
    /// marker last; plain ones are whole as soon as they exist.
    static func isFullyAssembled(componentID: String, root: URL) -> Bool {
        let marker: String? = switch componentID {
        case SikarugirManager.componentID: SikarugirManager.assembledMarker
        case Sikarugir11Manager.engineComponentID: Sikarugir11Manager.assembledMarker
        case InstallerEngineManager.componentID: InstallerEngineManager.assembledMarker
        default: nil
        }
        guard let marker else { return true }
        return FileManager.default.fileExists(atPath: root.appending(path: marker).path)
    }

    static func manifestURL(in root: URL) -> URL {
        root.appending(path: RuntimeManifest.fileName)
    }

    static func hasManifest(root: URL) -> Bool {
        FileManager.default.fileExists(atPath: manifestURL(in: root).path)
    }

    static func load(root: URL) throws -> RuntimeManifest {
        guard hasManifest(root: root) else { throw IntegrityError.noManifest }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: manifestURL(in: root)),
              let manifest = try? decoder.decode(RuntimeManifest.self, from: data)
        else { throw IntegrityError.unreadableManifest }
        return manifest
    }

    // MARK: Verify

    /// Compares the engine at `root` with its manifest.
    static func verify(root: URL) throws -> Report {
        let manifest = try load(root: root)
        return compare(manifest: manifest, disk: try snapshot(of: root))
    }

    /// Pure, so the classification is tested without a filesystem.
    static func compare(manifest: RuntimeManifest, disk: [String: RuntimeManifest.Entry]) -> Report {
        var report = Report(
            manifestID: manifest.id, origin: manifest.origin, recordedAt: manifest.createdAt,
            checkedFiles: manifest.entries.count)
        for (path, recorded) in manifest.entries {
            guard let found = disk[path] else { report.missing.append(path); continue }
            if recorded.link != nil, found.link != nil {
                if recorded.link != found.link { report.relinked.append(path) }
            } else if recorded.sha256 != found.sha256 || (recorded.link == nil) != (found.link == nil) {
                report.modified.append(path)
            }
        }
        report.added = disk.keys.filter { manifest.entries[$0] == nil }
        report.missing.sort(); report.modified.sort(); report.relinked.sort(); report.added.sort()
        return report
    }
}

// MARK: - Presentation

extension RuntimeIntegrity {
    /// One engine's check result, worded for the bottle page.
    struct CheckLine: Hashable, Sendable {
        var summary: String
        var detail: String?
        var symbol: String
        /// True when the engine differs from its record. "No record" is not
        /// a problem: there is nothing to compare, and nothing is claimed.
        var isProblem: Bool
    }

    /// Checks one engine and words the outcome. `root` is nil when the engine
    /// isn't installed.
    static func checkLine(componentID: String, root: URL?) -> CheckLine {
        let name = BottleRuntime.displayName(forComponent: componentID)
        guard let root else {
            return CheckLine(summary: L10n.string("integrity.not_installed", name), detail: nil,
                             symbol: "questionmark.circle", isProblem: false)
        }
        do {
            return checkLine(engineName: name, report: try verify(root: root))
        } catch IntegrityError.noManifest {
            return CheckLine(summary: L10n.string("integrity.no_record", name), detail: nil,
                             symbol: "questionmark.circle", isProblem: false)
        } catch {
            return CheckLine(summary: L10n.string("integrity.check_failed", name, error.localizedDescription),
                             detail: nil, symbol: "exclamationmark.triangle", isProblem: true)
        }
    }

    /// Pure wording of a report.
    static func checkLine(engineName: String, report: Report) -> CheckLine {
        let recorded = report.recordedAt.formatted(date: .abbreviated, time: .omitted)
        if report.isIntact {
            let key = report.origin == .installed ? "integrity.intact" : "integrity.intact_adopted"
            return CheckLine(
                summary: L10n.string(key, engineName, String(report.checkedFiles), recorded),
                detail: "\(L10n.string("integrity.record_id")) \(String(report.manifestID.prefix(12)))",
                symbol: "checkmark.seal", isProblem: false)
        }
        let counts = L10n.string(
            "integrity.changed", engineName, String(report.differenceCount), recorded,
            String(report.missing.count), String(report.modified.count + report.relinked.count),
            String(report.added.count))
        // The first few paths, so it can be acted on; the rest are counted.
        let paths = (report.missing.map { "− \($0)" } + report.modified.map { "≠ \($0)" }
            + report.relinked.map { "→ \($0)" } + report.added.map { "+ \($0)" })
        var detail = paths.prefix(6).joined(separator: "\n")
        if paths.count > 6 { detail += "\n" + L10n.string("integrity.more", String(paths.count - 6)) }
        return CheckLine(summary: counts, detail: detail, symbol: "exclamationmark.triangle", isProblem: true)
    }
}
