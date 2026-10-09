import Foundation
import SwiftUI

/// Polls GitHub releases for a newer Fable build, surfaces it as a banner, and
/// installs it in place.
///
/// Updating used to mean opening the release page and doing the rest by hand,
/// which is a poor fit for a tool whose whole purpose is removing fiddly manual
/// steps — and it meant fixes reached people slowly or not at all. The download
/// is verified before anything is replaced; see ``AppUpdateInstaller`` for what
/// is checked and how the swap survives failing halfway.
@MainActor
final class AppUpdateChecker: ObservableObject {
    struct Release: Hashable, Sendable {
        let tagName: String
        /// "v0.2.0" → "0.2.0".
        let version: String
        let displayName: String
        let url: URL
        let body: String
        /// The .zip attached to the release, when there is one. Absent for a
        /// release published without a build, which is why installing is
        /// offered conditionally rather than always.
        let assetURL: URL?
        let assetBytes: Int64?
    }

    @Published private(set) var available: Release?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?

    /// Non-nil while an update is being fetched or installed; the Double is
    /// download progress in 0…1.
    @Published private(set) var installProgress: Double?
    @Published private(set) var installStage: String?

    /// Whether this build can replace itself — false for a `swift run` binary
    /// or an app installed somewhere the user can't write.
    var canInstallInPlace: Bool { AppUpdateInstaller.canSelfUpdate() }

    /// User dismissed this version's banner — don't show it again until
    /// a newer one ships. Backed by UserDefaults so it survives relaunch.
    @AppStorage("appUpdateSkippedVersion") private var skippedVersion: String = ""

    static let repo = "malagic99/fable"

    /// `CFBundleShortVersionString`. Falls back to "0" so the comparator
    /// always treats released builds as newer in dev builds.
    nonisolated static let currentVersion: String = {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }()

    /// Once an hour at most, unless `force` is true.
    func checkIfDue(force: Bool = false) async {
        if !force, let lastChecked, Date().timeIntervalSince(lastChecked) < 3600 {
            return
        }
        await check()
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        lastError = nil
        defer {
            isChecking = false
            lastChecked = .now
        }

        do {
            let release = try await Self.fetchLatestRelease(repo: Self.repo)
            applyResult(release)
        } catch {
            // Network failure / 404 / private repo are all "unknown" —
            // don't pester the user, just remember the error for the
            // Settings tab to surface if asked.
            lastError = error.localizedDescription
            available = nil
        }
    }

    /// Downloads the available release, verifies it, and swaps it in. The app
    /// quits at the end: the running bundle can't be replaced underneath
    /// itself, so a helper does the swap and relaunches.
    func downloadAndInstall() async {
        guard let release = available, let asset = release.assetURL else {
            lastError = AppUpdateError.noDownloadableAsset.localizedDescription
            return
        }
        lastError = nil
        installStage = L10n.string("update.stage.downloading")
        installProgress = 0
        defer { if lastError != nil { installProgress = nil; installStage = nil } }

        do {
            let archive = try await AppUpdateInstaller.download(from: asset) { fraction in
                Task { @MainActor in self.installProgress = fraction }
            }
            installStage = L10n.string("update.stage.verifying")
            let app = try await AppUpdateInstaller.unpackAndVerify(
                archive: archive, expectedVersion: release.version)
            installStage = L10n.string("update.stage.installing")
            try AppUpdateInstaller.scheduleSwapAndRelaunch(newApp: app)
            // The helper is waiting on this process to exit before it swaps.
            NSApplication.shared.terminate(nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func dismissBanner() {
        // Dismiss for this session only — the next launch will check again.
        available = nil
    }

    func skipThisVersion() {
        if let available {
            skippedVersion = available.version
        }
        available = nil
    }

    /// Open in the user's default browser. The download link is the
    /// release page itself, since asset names will change over time.
    func openInBrowser() {
        guard let available else { return }
        NSWorkspace.shared.open(available.url)
    }

    // MARK: Internals

    private func applyResult(_ release: Release?) {
        guard let release else {
            available = nil
            return
        }
        guard VersionCompare.isNewer(release.version, than: Self.currentVersion) else {
            available = nil
            return
        }
        if release.version == skippedVersion {
            available = nil
            return
        }
        available = release
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int64?
        }
        let tag_name: String
        let name: String?
        let html_url: URL
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    nonisolated static func fetchLatestRelease(repo: String) async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10")!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdateError.badResponse("GitHub returned HTTP \(http.statusCode) for \(repo)")
        }
        return try parseLatest(fromReleasesJSON: data)
    }

    /// Pure parsing step. Picks the first non-draft, non-prerelease
    /// release in the response (already date-ordered by GitHub).
    nonisolated static func parseLatest(fromReleasesJSON data: Data) throws -> Release? {
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        for release in releases where release.draft != true && release.prerelease != true {
            let version = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst())
                : release.tag_name
            // The app bundle, not the source tarballs GitHub attaches to
            // every release.
            let asset = release.assets?.first {
                $0.name.lowercased().hasSuffix(".zip") &&
                $0.name.lowercased().contains("fable")
            }
            return Release(
                tagName: release.tag_name,
                version: version,
                displayName: release.name ?? release.tag_name,
                url: release.html_url,
                body: release.body ?? "",
                assetURL: asset?.browser_download_url,
                assetBytes: asset?.size
            )
        }
        return nil
    }
}
