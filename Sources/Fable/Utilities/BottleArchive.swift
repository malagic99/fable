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
        /// How `prefixChecksum` was computed. Absent (nil) in archives from
        /// before v1.3.3, which hashed the raw tar stream — extended
        /// attributes, owner names and all — and so never verified for a
        /// real bottle on import (copying adds `com.apple.provenance` and
        /// drops group-write bits). ``ChecksumFormat/normalized`` leaves
        /// those out. Older Fable ignores the field.
        var checksumFormat: Int? = nil
        /// Set on donor exports: the Windows profile name used in place of
        /// the owner's Mac user name. Import renames it to the importer's.
        /// Older Fable ignores it, and the bottle works under this name.
        var profilePlaceholder: String? = nil

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

    /// Tar patterns (relative to the archive root, `prefix/...`) that turn a
    /// Steam bottle into a shareable DONOR: the client itself travels, but
    /// installed games (licensed content that the recipient may not own),
    /// downloads, per-account data, and the owner's login/session state stay
    /// home. The friend logs in as themselves; Steam regenerates config.
    static func donorExclusions(for bottle: Bottle) -> [String] {
        let steam = "\(prefixEntryName)/drive_c/\(SteamPaths.clientDirRelative)"
        // Games outside steamapps (bridge downloads, games added by hand).
        let gameFolders = DonorExport.gameFolders(of: bottle).map {
            "\(prefixEntryName)/drive_c/" + DonorExport.literalPattern($0)
        }
        return gameFolders + [
            "\(steam)/steamapps",   // installed games, manifests, downloads
            "\(steam)/userdata",    // per-account cloud/config
            "\(steam)/config",      // loginusers.vdf + session tokens
            "\(steam)/logs",
            "\(steam)/dumps",
            "\(steam)/appcache",
            "\(steam)/depotcache",
            "\(steam)/ssfn*",       // sentry files (machine auth)
            // The client keeps more login state OUTSIDE its own folder, in the
            // Windows user's local AppData: local.vdf's ConnectCache (the
            // saved "remember me" token) and htmlcache, whose Cookies hold
            // steamLoginSecure web sessions for store, checkout and community.
            // Both regenerate on first launch. The `*` stands for the donor's
            // Wine user name (their Mac user name).
            "\(prefixEntryName)/drive_c/users/*/AppData/Local/Steam",
            // Logs written by Windows programs — installers, launchers,
            // games — are full of the owner's paths and user name, and a
            // donor needs none of them (external review 2026-11-23).
            "*.log",
        ]
    }

    /// The bottle metadata that matches `donorExclusions(for:)`: only the
    /// Steam client stays on the wall — every game's files are left out, so
    /// its entry goes too — and the owner's list of installed Steam apps is
    /// dropped (it also stopped the friend's own installs being added).
    static func donorBottle(_ bottle: Bottle) -> Bottle {
        var donor = bottle
        donor.games.removeAll { !DonorExport.isSteamClient($0) }
        donor.steamSyncedAppIDs = nil
        return donor
    }

    /// Tar+zstd the bottle (manifest + bottle.json + prefix tree) into
    /// `destination`. Returns the destination URL on success.
    /// MainActor-isolated because it reads BottleManager paths.
    ///
    /// Scale matters here: a Steam donor bottle is ~56 GB. The prefix is
    /// tarred IN PLACE (it already sits at `<bottleDir>/prefix`, the exact
    /// entry name the archive wants) and the checksum is streamed through a
    /// pipe — no staged copy of the prefix, no full-size temp tar. Only the
    /// two small JSON files are staged.
    ///
    /// `excluding` takes tar patterns relative to the archive root (see
    /// `donorExclusions(for:)`). The SAME exclusions feed the checksum stream and
    /// the archive — they must agree, or the import-side verification would
    /// reject every donor archive.
    @MainActor
    @discardableResult
    static func pack(
        _ bottle: Bottle,
        bottleManager: BottleManager,
        catalog: VersionCatalog,
        to destination: URL,
        excluding: [String] = [],
        sanitizeRegistry: Bool = false,
        ownerUserName: String = NSUserName()
    ) async throws -> URL {
        let fm = FileManager.default
        let source = bottleManager.directory(for: bottle)
        var prefixSource = bottleManager.prefixDirectory(for: bottle)
        guard fm.fileExists(atPath: source.path) else {
            throw ArchiveError.bottleDirectoryMissing(source.path)
        }

        // Stage just the JSON entries; the prefix is read from its home.
        let staging = fm.temporaryDirectory
            .appending(path: "fable-archive-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // A donor needs a registry without the owner's Steam account in it.
        // The prefix is tarred in place, so the change is made in a
        // copy-on-write clone beside the bottle: seconds and almost no disk
        // even for a 150 GB Steam bottle. Cloning fails rather than silently
        // falling back to a full copy, and the clone is always removed.
        if sanitizeRegistry, fm.fileExists(atPath: prefixSource.path) {
            let clone = try await cloneForDonor(prefixSource, beside: source)
            defer { try? fm.removeItem(at: clone.deletingLastPathComponent()) }
            // The account data, and the owner's Mac user name wherever it
            // names the profile or the home folder. A registry that exists
            // but can't be read as text is not exported as it is (external
            // review N2).
            for name in DonorExport.registryFiles {
                let registry = clone.appending(path: name)
                guard fm.fileExists(atPath: registry.path) else { continue }
                guard var text = try? String(contentsOf: registry, encoding: .utf8) else {
                    throw ArchiveError.registryUnreadable
                }
                if name == "user.reg" { text = DonorExport.sanitizedUserRegistry(text) }
                text = DonorExport.replacingProfileName(
                    text, user: ownerUserName, with: DonorExport.profilePlaceholder)
                try text.write(to: registry, atomically: false, encoding: .utf8)
            }
            var excluding = excluding
            if try DonorExport.anonymizeProfile(prefix: clone, user: ownerUserName) {
                excluding = DonorExport.renamingProfile(
                    in: excluding, user: ownerUserName, prefixEntry: prefixEntryName)
            }
            prefixSource = clone
            return try await packTree(
                bottle, prefixSource: prefixSource, staging: staging, catalog: catalog,
                to: destination, excluding: excluding, profilePlaceholder: DonorExport.profilePlaceholder)
        }
        return try await packTree(
            bottle, prefixSource: prefixSource, staging: staging, catalog: catalog,
            to: destination, excluding: excluding)
    }

    /// Clones `prefix` with clonefile(2) into a fresh folder inside
    /// `bottleDirectory` (same volume, so the clone is free). Returns the
    /// clone's `prefix` folder.
    @MainActor
    private static func cloneForDonor(_ prefix: URL, beside bottleDirectory: URL) async throws -> URL {
        let holder = bottleDirectory.appending(path: ".donor-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: holder, withIntermediateDirectories: true)
        let clone = holder.appending(path: prefixEntryName, directoryHint: .isDirectory)
        let result = try await ProcessRunner.run(
            URL(filePath: "/bin/cp"), arguments: ["-c", "-R", prefix.path, clone.path])
        guard result.succeeded else {
            try? FileManager.default.removeItem(at: holder)
            throw ArchiveError.tarFailed("couldn't make a copy-on-write copy of the bottle: \(result.standardError)")
        }
        return clone
    }

    @MainActor
    private static func packTree(
        _ bottle: Bottle, prefixSource: URL, staging: URL, catalog: VersionCatalog,
        to destination: URL, excluding: [String], profilePlaceholder: String? = nil
    ) async throws -> URL {
        let fm = FileManager.default
        // An empty prefix still needs a directory for tar to reference.
        let prefixParent: URL
        if fm.fileExists(atPath: prefixSource.path) {
            prefixParent = prefixSource.deletingLastPathComponent()
        } else {
            try fm.createDirectory(
                at: staging.appending(path: prefixEntryName), withIntermediateDirectories: true
            )
            prefixParent = staging
        }

        let bottleJSON = try JSONEncoder.fablePretty().encode(bottle)
        try bottleJSON.write(to: staging.appending(path: bottleEntryName))

        // Checksum the prefix tar stream so the importer can validate
        // before doing anything irreversible.
        let checksum = try await prefixChecksum(
            stagingPrefix: prefixParent.appending(path: prefixEntryName, directoryHint: .isDirectory),
            excluding: excluding,
            format: .normalized
        )

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
            prefixChecksum: checksum,
            checksumFormat: ChecksumFormat.normalized.rawValue,
            profilePlaceholder: profilePlaceholder
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
            arguments: excluding.map { "--exclude=\($0)" } + [
                "--zstd",
                "-cf", destination.path,
                "-C", staging.path,
                manifestEntryName,
                bottleEntryName,
                "-C", prefixParent.path,
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

    /// The tar arguments that unpack an archive into `directory`.
    ///
    /// -p keeps permission bits as archived (without it the umask
    /// drops group-write and the checksum can't match). Ownership is
    /// never restored for a non-root user. On macOS -p also restores
    /// file flags, ACLs and extended attributes, which an archive from
    /// someone else could use to make files undeletable or writable by
    /// other users (external review N1); none of them is in the
    /// checksum, so they are not restored.
    static func extractArguments(archive: URL, into directory: URL) -> [String] {
        // Order matters: bsdtar's -p turns flags, ACLs, attributes and Mac
        // metadata back on, so the --no-… options must come after it.
        [
            "--zstd", "-x", "-p", "--no-fflags", "--no-acls", "--no-xattrs", "--no-mac-metadata",
            "-f", archive.path, "-C", directory.path,
        ]
    }

    /// Extracts the archive into a temporary working directory.
    /// Verifies schema version, prefix checksum, and that bottle.json
    /// decodes cleanly. Caller cleans up `workingDirectory`.
    static func unpack(
        _ archive: URL,
        importerUserName: String = NSUserName(),
        scratchRoot: URL = FileManager.default.temporaryDirectory
    ) async throws -> UnpackedBottle {
        let fm = FileManager.default
        let workingDir = scratchRoot
            .appending(path: "fable-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: workingDir, withIntermediateDirectories: true)
        // Whatever goes wrong from here on, the scratch folder goes with it —
        // an unreadable manifest or a failed checksum run once left a copy of
        // the whole bottle in the temp folder.
        do {
            return try await unpack(archive, into: workingDir, importerUserName: importerUserName)
        } catch {
            try? fm.removeItem(at: workingDir)
            throw error
        }
    }

    private static func unpack(
        _ archive: URL, into workingDir: URL, importerUserName: String
    ) async throws -> UnpackedBottle {
        let fm = FileManager.default
        let result = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/tar"),
            arguments: extractArguments(archive: archive, into: workingDir)
        )
        guard result.succeeded else {
            throw ArchiveError.tarFailed(result.standardError)
        }

        // Manifest + bottle.json must both be present.
        let manifestURL = workingDir.appending(path: manifestEntryName)
        let bottleURL = workingDir.appending(path: bottleEntryName)
        guard fm.fileExists(atPath: manifestURL.path),
              fm.fileExists(atPath: bottleURL.path)
        else {
            throw ArchiveError.malformed("archive missing manifest.json or bottle.json")
        }

        let manifest = try JSONDecoder.fable().decode(
            Manifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.schemaVersion <= Manifest.currentSchemaVersion else {
            throw ArchiveError.unsupportedSchema(manifest.schemaVersion)
        }

        let bottle = try JSONDecoder.fable().decode(
            Bottle.self,
            from: Data(contentsOf: bottleURL)
        )

        // Re-checksum the prefix to detect corruption, or an edit that didn't
        // update the manifest. This is integrity, not authenticity: the
        // manifest travels in the same archive, so whoever repacks a bottle
        // can recompute it. Treat an imported .fbottle as trusted as its sender.
        let prefixDir = workingDir.appending(path: prefixEntryName, directoryHint: .isDirectory)
        let format = ChecksumFormat(rawValue: manifest.checksumFormat ?? ChecksumFormat.raw.rawValue) ?? .raw
        let recomputed = try await prefixChecksum(stagingPrefix: prefixDir, format: format)
        guard recomputed == manifest.prefixChecksum else {
            throw ArchiveError.checksumMismatch(
                expected: manifest.prefixChecksum,
                actual: recomputed
            )
        }

        // Verified, so now it can change: a donor's profile takes the
        // importer's name.
        if manifest.profilePlaceholder == DonorExport.profilePlaceholder {
            DonorExport.restoreProfile(prefix: prefixDir, user: importerUserName)
        }
        // CrossOver's bottle config can set environment variables for every
        // launch (`[EnvironmentVariables]`) — DYLD_INSERT_LIBRARIES included —
        // past the per-game screen. Fable writes its own minimal one when a
        // bottle first runs on CrossOver, so the sender's is dropped.
        try? fm.removeItem(at: prefixDir.appending(path: crossOverConfigName))

        return UnpackedBottle(
            manifest: manifest,
            bottle: bottle,
            workingDirectory: workingDir
        )
    }

    /// CrossOver's per-bottle config, which an import never keeps.
    static let crossOverConfigName = "cxbottle.conf"

    // MARK: Checksum

    /// Streams a stable tar of the prefix tree straight into sha256 — a
    /// shell pipeline, so a 56 GB prefix never touches a temp file. The
    /// digest is over the uncompressed tar bytes (same invocation as ever,
    /// so archives written by older Fable versions still verify).
    /// How a prefix checksum is computed.
    enum ChecksumFormat: Int, Sendable {
        /// The raw tar stream (archives from before v1.3.3).
        case raw = 1
        /// Only what survives copying to another Mac: names, contents,
        /// permission bits, times, link targets — no extended attributes,
        /// ACLs, file flags, or owner names.
        case normalized = 2

        var tarFlags: String {
            switch self {
            case .raw: ""
            case .normalized:
                "--no-xattrs --no-acls --no-fflags --no-mac-metadata --uid 0 --gid 0 --uname fable --gname fable"
            }
        }
    }

    private static func prefixChecksum(
        stagingPrefix: URL, excluding: [String] = [], format: ChecksumFormat
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: stagingPrefix.path) else { return emptyChecksum }

        // Exclusions ride in ${3}… so no pattern ever touches shell parsing
        // (braces: $10 would otherwise parse as ${1}0).
        let excludeArgs = (3..<(3 + excluding.count)).map { #"--exclude="${\#($0)}""# }.joined(separator: " ")
            + (format.tarFlags.isEmpty ? "" : " " + format.tarFlags)
        let result = try await ProcessRunner.run(
            URL(filePath: "/bin/sh"),
            arguments: [
                "-c", #"tar \#(excludeArgs) -cf - -C "$1" "$2" | shasum -a 256"#, "--",
                stagingPrefix.deletingLastPathComponent().path,
                stagingPrefix.lastPathComponent,
            ] + excluding
        )
        guard result.succeeded,
              let hex = result.standardOutput.split(separator: " ").first,
              hex.count == 64
        else {
            throw ArchiveError.tarFailed(result.standardError)
        }
        return "sha256:" + hex
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
    case registryUnreadable

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
        case .registryUnreadable:
            "One of the bottle's registry files couldn't be read as text, so the account details and user name in it couldn't be removed. Nothing was exported."
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
