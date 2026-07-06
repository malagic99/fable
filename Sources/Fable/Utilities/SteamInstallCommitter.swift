import Foundation

/// Finishes Steam installs that downloaded + extracted but can't commit.
///
/// Under Sikarugir's experimental WoW64, Steam's 32-bit privileged service
/// IPC is dead, so the final commit step (move staged files into `common/`)
/// hangs — every game, and the shared "Steamworks Common Redistributables"
/// that gates them, stalls at ~2% "installing" forever. The files ARE fully
/// extracted in `steamapps/downloading/<appid>/`, though; the only broken
/// step is the privileged move. This does that move and marks the manifest
/// installed — the manual rescue, automated, so it self-heals.
///
/// See [[fable-steam-install-wow64-gap]]. The caller MUST ensure Steam isn't
/// running for the prefix (we mutate files Steam owns).
enum SteamInstallCommitter {
    /// Walks `steamRoot/steamapps/downloading/` and commits every app that's
    /// fully extracted but not yet installed. Returns the names committed.
    /// Best-effort per app — one failure never blocks the others.
    @discardableResult
    static func commitStuckInstalls(
        steamRoot: URL,
        fileManager fm: FileManager = .default
    ) -> [String] {
        let steamapps = steamRoot.appending(path: "steamapps", directoryHint: .isDirectory)
        let downloading = steamapps.appending(path: "downloading", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: downloading.path) else { return [] }

        let entries = (try? fm.contentsOfDirectory(
            at: downloading, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []

        var committed: [String] = []
        for entry in entries {
            let appid = entry.lastPathComponent
            guard !appid.isEmpty, appid.allSatisfy(\.isNumber),
                  (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            if let name = commitApp(appid: appid, appDir: entry, steamapps: steamapps, steamRoot: steamRoot, fm: fm) {
                committed.append(name)
            }
        }
        return committed
    }

    /// Commits one app if it's fully extracted; returns its name, or nil if
    /// not eligible/ready. Exposed for testing.
    static func commitApp(
        appid: String,
        appDir: URL,
        steamapps: URL,
        steamRoot: URL,
        fm: FileManager = .default
    ) -> String? {
        let manifestURL = steamapps.appending(path: "appmanifest_\(appid).acf")
        guard let text = try? String(contentsOf: manifestURL, encoding: .utf8),
              let parsed = SteamKeyValues.parse(text), parsed.key == "AppState"
        else { return nil }
        var app = parsed.value

        guard let installdir = app.string("installdir"), !installdir.isEmpty,
              let bytesToStage = app.int("BytesToStage"), bytesToStage > 0
        else { return nil }
        // Already installed — nothing to do.
        if app.int("StateFlags") == 4 { return nil }
        // Ready only when the extracted payload matches the staged size. Both
        // measures must agree: Steam PRE-ALLOCATES depot files sparsely during
        // download, so logical size alone can look "complete" for a paused
        // half-download — allocated (on-disk) size can't be faked by sparse
        // preallocation. Committing a half-download would move broken files
        // into common/ and mark them installed.
        let sizes = directorySizes(appDir, fm: fm)
        guard sizes.logical >= Int64(bytesToStage),
              sizes.allocated >= Int64(bytesToStage) else { return nil }

        // Move the real files into common/<installdir>, merging over any
        // stub directory a prior attempt left behind.
        let dest = steamapps.appending(path: "common", directoryHint: .isDirectory)
            .appending(path: installdir, directoryHint: .isDirectory)
        do {
            try mergeMove(from: appDir, into: dest, fm: fm)
        } catch {
            return nil
        }

        // Rebuild InstalledDepots: depot ids from the per-depot state files,
        // manifest ids from depotcache (<depot>_<manifest>.manifest). Preserve
        // any sizes Steam already recorded.
        let existingDepots = app["InstalledDepots"]
        var depots = VDFValue.object([])
        for depot in depotIDs(forApp: appid, in: appDir.deletingLastPathComponent(), fm: fm) {
            guard let manifest = manifestID(forDepot: depot, steamRoot: steamRoot, fm: fm) else { continue }
            let size = existingDepots?.string(depot).flatMap { _ in existingDepots?[depot]?.string("size") } ?? "0"
            depots.set(depot, object: .object([("manifest", .string(manifest)), ("size", .string(size))]))
        }

        let buildid = app.string("TargetBuildID") ?? app.string("buildid") ?? "0"
        app.set("StateFlags", "4")
        app.set("buildid", buildid)
        app.set("SizeOnDisk", String(directorySize(dest, fm: fm)))
        app.set("BytesDownloaded", app.string("BytesToDownload") ?? "0")
        app.set("BytesStaged", String(bytesToStage))
        app.set("FullValidateAfterNextUpdate", "0")
        app.set("ScheduledAutoUpdate", "0")
        app.set("UpdateResult", "0")
        if case .object(let pairs) = depots, !pairs.isEmpty {
            app.set("InstalledDepots", object: depots)
        }

        // Back up the original manifest once, then write the installed one.
        let backup = manifestURL.appendingPathExtension("fable-bak")
        if !fm.fileExists(atPath: backup.path) {
            try? fm.copyItem(at: manifestURL, to: backup)
        }
        guard (try? SteamKeyValues.serialize(key: "AppState", value: app)
            .write(to: manifestURL, atomically: true, encoding: .utf8)) != nil else { return nil }

        // Drop the now-committed download scratch + its state files.
        try? fm.removeItem(at: appDir)
        let downloading = appDir.deletingLastPathComponent()
        for f in (try? fm.contentsOfDirectory(at: downloading, includingPropertiesForKeys: nil)) ?? []
        where f.lastPathComponent.hasPrefix("state_\(appid)") {
            try? fm.removeItem(at: f)
        }

        return app.string("name") ?? appid
    }

    // MARK: Helpers

    /// Sum of regular-file sizes under `url`, in bytes.
    static func directorySize(_ url: URL, fm: FileManager = .default) -> Int64 {
        directorySizes(url, fm: fm).logical
    }

    /// Logical (st_size) and allocated (on-disk blocks) totals in one walk.
    /// They diverge for sparse files: preallocated-but-unwritten regions count
    /// toward logical but not allocated.
    static func directorySizes(_ url: URL, fm: FileManager = .default) -> (logical: Int64, allocated: Int64) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return (0, 0)
        }
        var logical: Int64 = 0
        var allocated: Int64 = 0
        for case let item as URL in e {
            guard let v = try? item.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            logical += Int64(v.fileSize ?? 0)
            allocated += Int64(v.totalFileAllocatedSize ?? 0)
        }
        return (logical, allocated)
    }

    /// Depot ids for `appid` from `downloading/state_<appid>_<depot>.patch`.
    static func depotIDs(forApp appid: String, in downloading: URL, fm: FileManager = .default) -> [String] {
        let prefix = "state_\(appid)_"
        let ids = ((try? fm.contentsOfDirectory(at: downloading, includingPropertiesForKeys: nil)) ?? [])
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".patch") }
            .compactMap { name -> String? in
                name.dropFirst(prefix.count).dropLast(".patch".count).description
            }
            .filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        return Array(Set(ids)).sorted()
    }

    /// Manifest id for `depot` from `depotcache/<depot>_<manifest>.manifest`.
    static func manifestID(forDepot depot: String, steamRoot: URL, fm: FileManager = .default) -> String? {
        let depotcache = steamRoot.appending(path: "depotcache", directoryHint: .isDirectory)
        let prefix = "\(depot)_"
        return ((try? fm.contentsOfDirectory(at: depotcache, includingPropertiesForKeys: nil)) ?? [])
            .map(\.lastPathComponent)
            .first { $0.hasPrefix(prefix) && $0.hasSuffix(".manifest") }
            .map { String($0.dropFirst(prefix.count).dropLast(".manifest".count)) }
    }

    /// Moves every child of `src` into `dest` (created if absent), replacing
    /// same-named children, then removes the emptied `src`.
    private static func mergeMove(from src: URL, into dest: URL, fm: FileManager) throws {
        if !fm.fileExists(atPath: dest.path) {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: src, to: dest)
            return
        }
        for child in (try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? [] {
            let target = dest.appending(path: child.lastPathComponent)
            try? fm.removeItem(at: target)
            try fm.moveItem(at: child, to: target)
        }
        try? fm.removeItem(at: src)
    }
}
