import Foundation

enum AppUpdateError: LocalizedError {
    case noDownloadableAsset
    case downloadFailed(String)
    case archiveUnreadable(String)
    case notAFableBuild(String)
    case wrongVersion(expected: String, found: String)
    case signatureInvalid
    case installLocationNotWritable(String)

    var errorDescription: String? {
        switch self {
        case .noDownloadableAsset:
            return "That release has no Fable app attached to download."
        case .downloadFailed(let detail):
            return "Download failed: \(detail)"
        case .archiveUnreadable(let detail):
            return "The downloaded archive couldn't be opened: \(detail)"
        case .notAFableBuild(let detail):
            return "The download doesn't contain a Fable app (\(detail)). Nothing was changed."
        case .wrongVersion(let expected, let found):
            return "The download is version \(found), not \(expected). Nothing was changed."
        case .signatureInvalid:
            return "The downloaded app's signature is damaged, so it was not installed."
        case .installLocationNotWritable(let path):
            return "Fable can't update itself at \(path) — move it to your Applications folder and try again."
        }
    }
}

/// Downloads a release and installs it over the running app.
///
/// Fable has only ever been updated by hand: the banner opened the release
/// page and the user did the rest. That's a poor fit for a tool whose whole
/// job is removing fiddly manual steps, and it means bug fixes reach people
/// slowly or not at all.
///
/// The app bundle can't be overwritten while it's running, so the swap is done
/// by a short script that waits for this process to exit, moves the old bundle
/// aside, copies the new one in, and relaunches — restoring the old bundle if
/// the copy fails, so a half-finished update can't leave an unlaunchable app.
///
/// Everything that can be checked *before* the swap is checked before the
/// swap: that the archive really holds a Fable app, that its version is the one
/// advertised, and that its signature verifies. Fable is ad-hoc signed, so that
/// last check proves the bundle wasn't damaged in transit — not who built it.
/// Until there's a Developer ID, the trust boundary is GitHub over HTTPS.
enum AppUpdateInstaller {

    /// Where this build is installed. `nil` when it isn't a real bundle
    /// (a `swift run` binary), which is also when self-updating makes no sense.
    static var installedLocation: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// True when the running app is somewhere Fable may replace without asking
    /// for an administrator. A bundle the user doesn't own needs privileges
    /// this app deliberately doesn't ask for.
    static func canSelfUpdate() -> Bool {
        guard let app = installedLocation else { return false }
        return FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: app.path)
    }

    // MARK: Download

    /// Fetches `asset` to a temporary directory, reporting 0…1 progress.
    static func download(
        from asset: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: asset)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AppUpdateError.downloadFailed("HTTP \(http.statusCode)")
        }
        let expected = response.expectedContentLength
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "fable-update-\(UUID().uuidString).zip")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destination) else {
            throw AppUpdateError.downloadFailed("couldn't write to \(destination.path)")
        }
        defer { try? handle.close() }

        var buffer = Data()
        var received: Int64 = 0
        buffer.reserveCapacity(1 << 16)
        for try await byte in bytes {
            buffer.append(byte)
            received += 1
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 { progress(Double(received) / Double(expected)) }
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
        progress(1)
        return destination
    }

    // MARK: Verify

    /// Unpacks `archive` and returns the Fable app inside it, having checked
    /// it is what the release claimed. Throws before touching the installed
    /// app if anything is off.
    /// `expectedBundleID` defaults to this app's own, and is a parameter so
    /// the check can be exercised outside a Fable bundle — where `Bundle.main`
    /// is whatever is running the test, not Fable.
    static func unpackAndVerify(
        archive: URL, expectedVersion: String,
        expectedBundleID: String? = Bundle.main.bundleIdentifier
    ) async throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appending(path: "fable-update-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let unzip = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archive.path, staging.path])
        guard unzip.succeeded else {
            throw AppUpdateError.archiveUnreadable(unzip.standardError)
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: staging, includingPropertiesForKeys: nil)) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw AppUpdateError.notAFableBuild("no .app in the archive")
        }

        let plist = app.appending(path: "Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String
        else { throw AppUpdateError.notAFableBuild("unreadable Info.plist") }
        guard bundleID == expectedBundleID else {
            throw AppUpdateError.notAFableBuild("bundle id \(bundleID)")
        }
        let found = info["CFBundleShortVersionString"] as? String ?? "?"
        guard found == expectedVersion else {
            throw AppUpdateError.wrongVersion(expected: expectedVersion, found: found)
        }

        // Ad-hoc signatures carry no identity, but they still detect a bundle
        // damaged or altered after it was built.
        let verify = try await ProcessRunner.run(
            URL(filePath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", app.path])
        guard verify.succeeded else { throw AppUpdateError.signatureInvalid }

        return app
    }

    // MARK: Install

    /// Replaces the running app with `newApp` and relaunches.
    ///
    /// Returns once the handoff script is running; the caller is expected to
    /// terminate the app immediately so the script can proceed.
    static func scheduleSwapAndRelaunch(newApp: URL) throws {
        guard let installed = installedLocation else {
            throw AppUpdateError.installLocationNotWritable("this build isn't an app bundle")
        }
        guard canSelfUpdate() else {
            throw AppUpdateError.installLocationNotWritable(installed.path)
        }

        let script = FileManager.default.temporaryDirectory
            .appending(path: "fable-update-\(UUID().uuidString).sh")
        // Moves the old bundle aside rather than deleting it, so a failed copy
        // can be undone — a half-written bundle would be unlaunchable, and the
        // user would have no app and no obvious way back.
        let body = """
        #!/bin/sh
        set -u
        pid=$1
        installed=$2
        staged=$3
        backup="${installed}.old-$$"

        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done

        if ! /bin/mv "$installed" "$backup" 2>/dev/null; then
          /usr/bin/open "$installed" 2>/dev/null
          exit 1
        fi
        if /usr/bin/ditto "$staged" "$installed"; then
          /usr/bin/xattr -cr "$installed" 2>/dev/null
          /bin/rm -rf "$backup"
        else
          /bin/rm -rf "$installed"
          /bin/mv "$backup" "$installed"
        fi
        /usr/bin/open "$installed"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            script.path, String(ProcessInfo.processInfo.processIdentifier),
            installed.path, newApp.path,
        ]
        try process.run()
    }
}
