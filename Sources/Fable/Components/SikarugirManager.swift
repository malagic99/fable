import Foundation

enum SikarugirError: LocalizedError {
    case notInstalled
    case engineTarballMissing(String)
    case rendererMissing(String)
    case binaryNotFound(String)
    case gptk4Unavailable

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "This backend needs the Wine 10 graphics engine, which Fable hasn't downloaded yet. Pick the backend again on the bottle page, or rerun the setup wizard from Settings → About, and Fable downloads it."
        case .engineTarballMissing(let path):
            "Sikarugir is installed but its Wine engine tarball wasn't found under \(path)."
        case .rendererMissing(let path):
            "Sikarugir's D3DMetal renderer wasn't found under \(path)."
        case .binaryNotFound(let searched):
            "Sikarugir engine extracted but no wine binary was found under \(searched)."
        case .gptk4Unavailable:
            "No Game Porting Toolkit 4 D3DMetal found. Install GPTK 4 (Apple's dmg) through Components first — GPTK 3's framework is too old to pair with Sikarugir's Wine."
        }
    }
}

/// The breakthrough D3D12-on-Metal backend: Sikarugir ships a modern
/// Wine (10.0) engine PLUS a D3DMetal renderer whose dispatch DLLs are
/// recompiled against that same wine. This is the matched pair Apple's
/// GPTK lacks — GPTK binds D3DMetal to wine-7.7 whose SEH can't unwind
/// modern MSVC C++ exceptions (the 007 First Light int3 wall).
///
/// Fable doesn't ship any of this (D3DMetal.framework is Apple's). It
/// downloads the engine and the template that carries the renderer from
/// Sikarugir's own GitHub releases, pinned by SHA-256 in versions.json — the
/// same files the Sikarugir app fetches for itself — extracts the GPL wine
/// engine into its own component dir, and overlays the d3dmetal renderer
/// onto it. Until v1.2 both came from the user's Sikarugir install, which
/// exists only as a Homebrew cask: a Terminal wall before the first game.
/// That install is still read as a fallback when the catalog has no entry.
@MainActor
final class SikarugirManager: ObservableObject {
    let componentManager: ComponentManager
    /// Where the engine and its template are downloaded from. Nil only in
    /// tests and old call sites — then the user's Sikarugir install is the
    /// only source, as it was before v1.2.
    let catalog: VersionCatalog?

    nonisolated static let componentID = "sikarugir"
    /// The template whose renderer is built for Wine 10. A renderer is tied
    /// to one Wine generation, so this is not the Wine 11 path's template.
    nonisolated static let templateComponentID = "sikarugir-template-wine10"

    /// The install in flight, shared by every caller, so two triggers can't
    /// run two downloads into one archive.
    private var installTask: Task<Void, Error>?

    /// D3D DLLs D3DMetal provides as Wine builtins. Forced builtin at
    /// launch so any native DLLs in the prefix don't shadow them.
    nonisolated static let builtinDLLs = ["d3d11", "d3d12", "dxgi", "nvapi64"]

    /// Sikarugir's on-disk home.
    nonisolated static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Sikarugir", directoryHint: .isDirectory)
    }

    @Published private(set) var isDiscovered = false

    /// What the user asked for, mirrored from settings so an update can
    /// re-apply the pairing without the manager reaching into the settings
    /// store. Defaults to the tested pairing.
    var preferredD3DMetalSource: D3DMetalSource = .sikarugir

    init(componentManager: ComponentManager, catalog: VersionCatalog? = nil) {
        self.componentManager = componentManager
        self.catalog = catalog
        refresh()
    }

    /// The engine and template entries, when the catalog can supply both.
    nonisolated var catalogPair: (engine: VersionCatalog.Component, template: VersionCatalog.Component)? {
        guard let engine = catalog?.components[Self.componentID],
              let template = catalog?.components[Self.templateComponentID]
        else { return nil }
        return (engine, template)
    }

    /// True when Fable has somewhere to get the engine from: its own catalog,
    /// or a Sikarugir install on this Mac.
    func refresh() {
        isDiscovered = catalogPair != nil
            || ((try? engineTarball()) != nil && (try? d3dMetalRenderer()) != nil)
    }

    var isInstalled: Bool {
        (try? wineBinary()) != nil
    }

    /// D3DMetal setup state, for the onboarding step.
    enum D3DMetalStatus: Equatable {
        case missing                                  // no Sikarugir on the Mac
        /// Sikarugir is installed but hasn't downloaded its engine yet — it
        /// fetches that on first launch, so this is the state of someone who
        /// dragged the app across and never opened it. Worth naming: it used
        /// to read as `.missing`, which sent people back to re-download an app
        /// they already had.
        case incomplete
        case notInstalled(available: String)          // found, not yet extracted into Fable
        case ready(version: String)                   // installed and current
        case updateAvailable(installed: String, available: String)
    }

    /// Where the Sikarugir app itself lives, when it's somewhere we can find
    /// it. Only used to offer to open it — the support directory, not the app,
    /// is what Fable actually reads, and the two don't have to sit together.
    /// The Homebrew cask installs it as "Sikarugir Creator.app", not
    /// "Sikarugir.app" — matching only the latter found nothing on a Mac that
    /// had it installed. Both names are searched, newest naming first, in the
    /// two places casks and hand-installs land.
    nonisolated static var appLocation: URL? {
        let roots = [
            URL(filePath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
        let names = ["Sikarugir Creator.app", "Sikarugir.app"]
        for root in roots {
            for name in names {
                let candidate = root.appending(path: name)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    /// True when Sikarugir has left anything behind — the app, or the support
    /// directory it creates on first launch.
    nonisolated static var isPresentOnMac: Bool {
        appLocation != nil
            || FileManager.default.fileExists(atPath: supportDirectory.path)
    }

    /// The engine version Fable can install: the catalog's, else whatever a
    /// Sikarugir install has on disk (from its engine tarball name).
    nonisolated func availableVersion() -> String? {
        if let pair = catalogPair { return pair.engine.version }
        return (try? engineTarball()).map {
            $0.deletingPathExtension().deletingPathExtension().lastPathComponent
        }
    }

    /// The engine version Fable has extracted (newest installed component dir,
    /// whatever any bottle is pinned to).
    func installedVersion() -> String? {
        componentManager.newestInstalledDirectory(for: Self.componentID)?.lastPathComponent
    }

    /// Resolves onboarding status from what's discovered vs. installed. Pure, so
    /// the decision is unit-tested independently of the filesystem.
    nonisolated static func status(
        discovered: Bool, available: String?, installed: String?,
        sikarugirPresent: Bool = false
    ) -> D3DMetalStatus {
        guard discovered, let available else {
            // Sikarugir on disk but nothing to extract means it was installed
            // and never opened — a different problem, and a much smaller one,
            // than not having it at all.
            return sikarugirPresent ? .incomplete : .missing
        }
        guard let installed else { return .notInstalled(available: available) }
        return installed == available
            ? .ready(version: installed)
            : .updateAvailable(installed: installed, available: available)
    }

    func d3dMetalStatus() -> D3DMetalStatus {
        let installed = installedVersion()
        return Self.status(
            discovered: isDiscovered,
            available: Self.versionToOffer(available: availableVersion(), installed: installed),
            installed: installed,
            sikarugirPresent: Self.isPresentOnMac)
    }

    /// The version worth offering against what's installed. An engine newer
    /// than the catalog's (extracted from a newer Sikarugir install, before
    /// v1.2) is not out of date — never offer to "update" it downward.
    nonisolated static func versionToOffer(available: String?, installed: String?) -> String? {
        guard let installed, let available else { return available }
        return VersionCompare.newest([installed, available]) == installed ? installed : available
    }

    /// Human-friendly version label, e.g. "WS12WineSikarugir10.0_4" → "10.0_4".
    nonisolated static func displayVersion(_ raw: String) -> String {
        if let range = raw.range(of: "Sikarugir") {
            let tail = String(raw[range.upperBound...])
            if !tail.isEmpty { return tail }
        }
        return raw
    }

    // MARK: Discovery (Sikarugir's install on disk)

    /// The wine 10.0 engine tarball Sikarugir ships (extracted per-bottle
    /// by Sikarugir itself; Fable extracts its own copy).
    nonisolated func engineTarball() throws -> URL {
        let engines = Self.supportDirectory.appending(path: "Engines", directoryHint: .isDirectory)
        let tarballs = (try? FileManager.default.contentsOfDirectory(
            at: engines, includingPropertiesForKeys: nil
        )) ?? []
        guard let tarball = tarballs.first(where: {
            $0.lastPathComponent.hasPrefix("WS") && $0.pathExtension == "xz"
        }) else {
            throw SikarugirError.engineTarballMissing(engines.path)
        }
        return tarball
    }

    /// The d3dmetal renderer directory inside Sikarugir's Template app.
    /// Holds wine/x86_64-{windows,unix} dispatch + external/framework.
    nonisolated func d3dMetalRenderer() throws -> URL {
        if let downloaded = Self.downloadedRenderer() { return downloaded }
        let templateRoot = Self.supportDirectory.appending(path: "Template", directoryHint: .isDirectory)
        let templates = (try? FileManager.default.contentsOfDirectory(
            at: templateRoot, includingPropertiesForKeys: nil
        )) ?? []
        for template in templates where template.pathExtension == "app" {
            let renderer = template
                .appending(path: "Contents/Frameworks/renderer/d3dmetal", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: renderer.path) {
                return renderer
            }
        }
        throw SikarugirError.rendererMissing(templateRoot.path)
    }

    /// The renderer inside the template Fable downloaded, newest first.
    nonisolated static func downloadedRenderer(
        componentsRoot: URL = AppPaths.components
    ) -> URL? {
        let root = componentsRoot.appending(path: templateComponentID, directoryHint: .isDirectory)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
        var remaining = names
        while let newest = VersionCompare.newest(remaining) {
            remaining.removeAll { $0 == newest }
            let versionRoot = root.appending(path: newest, directoryHint: .isDirectory)
            if let app = Sikarugir11Manager.templateApp(in: versionRoot),
               let renderer = Sikarugir11Manager.renderer(in: app) {
                return renderer
            }
        }
        return nil
    }

    // MARK: Install (extract engine + overlay d3dmetal)

    /// Downloads (or, without a catalog, extracts from a Sikarugir install)
    /// the wine 10.0 engine into Fable's components and overlays the d3dmetal
    /// renderer. Idempotent — skips if the engine is already there, finished.
    func ensureInstalled() async throws {
        if let installTask { return try await installTask.value }
        let task = Task { try await self.install() }
        installTask = task
        defer { installTask = nil }
        try await task.value
    }

    /// The marker written last, once the renderer is overlaid. An engine
    /// directory without it was interrupted part-way and is assembled again.
    nonisolated static let assembledMarker = ".d3dmetal-version"

    private func install() async throws {
        guard isDiscovered, let version = availableVersion() else {
            throw SikarugirError.notInstalled
        }

        // Already on this version, or on a newer one extracted from a newer
        // Sikarugir install: just self-heal support libs (the engine's lib can
        // be missing the TLS/font dylibs — libfreetype = blank Steam text,
        // libgnutls = no QR/online) without a full reinstall.
        if isInstalled, let installed = installedVersion(),
           VersionCompare.newest([installed, version]) == installed,
           let existing = componentManager.newestInstalledDirectory(for: Self.componentID),
           FileManager.default.fileExists(
               atPath: existing.appending(path: Self.assembledMarker).path) {
            let backfilled = (try? backfillSupportLibs()) ?? false
            let existingLib = existing.appending(path: "wswine.bundle/lib", directoryHint: .isDirectory)
            let patched = (try? await Self.patchD3DMetalRpath(lib: existingLib)) ?? false
            if backfilled || patched {
                // A repair Fable made is not damage: the record follows it.
                await Task.detached(priority: .utility) {
                    RuntimeIntegrity.rerecord(root: existing, noting: ["repaired": "support libraries or rpath"])
                }.value
            }
            return
        }
        // Otherwise this is a fresh install OR an update to a newer engine —
        // it goes into its own version dir. Bottles pinned to the old version
        // stay on it (BottleRuntime); new and unpinned bottles get this one.

        let installRoot: URL
        let renderer: URL
        if let pair = catalogPair {
            // 1. Download both, checksum-pinned. The engine archive unpacks to
            //    wswine.bundle/… at the root of its version directory.
            installRoot = try await componentManager.install(id: Self.componentID, component: pair.engine)
            let templateRoot = try await componentManager.install(
                id: Self.templateComponentID, component: pair.template)
            guard let app = Sikarugir11Manager.templateApp(in: templateRoot),
                  let found = Sikarugir11Manager.renderer(in: app)
            else { throw SikarugirError.rendererMissing(templateRoot.path) }
            renderer = found
        } else {
            let tarball = try engineTarball()
            renderer = try d3dMetalRenderer()
            installRoot = AppPaths.components
                .appending(path: Self.componentID, directoryHint: .isDirectory)
                .appending(path: version, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: installRoot, withIntermediateDirectories: true)

            // 1. Extract the engine (wswine.bundle/…) into the component dir.
            let extract = try await ProcessRunner.run(
                URL(filePath: "/usr/bin/tar"),
                arguments: ["-xJf", tarball.path, "-C", installRoot.path]
            )
            guard extract.succeeded else {
                throw ComponentError.extractionFailed(extract.standardError)
            }
        }

        // 2. Overlay the d3dmetal renderer onto the engine's lib tree.
        let bundle = installRoot.appending(path: "wswine.bundle", directoryHint: .isDirectory)
        let lib = bundle.appending(path: "lib", directoryHint: .isDirectory)
        try Self.overlay(renderer: renderer, intoLib: lib)

        // 2a. Patch d3d12.so's rpath so it can dlopen D3DMetal.framework
        //      from lib/external/ via @rpath. The overlay copies d3d12.so
        //      with only @loader_path in its LC_RPATH, which resolves to
        //      lib/wine/x86_64-unix/ — not where external/ lives.
        try await Self.patchD3DMetalRpath(lib: lib, layout: .rosetta)

        // 2b. Copy Sikarugir's bundled support dylibs (libinotify,
        //     gnutls, freetype, etc.) from the Template app's
        //     Frameworks/ into wswine.bundle/lib/. Sikarugir's wineserver
        //     dlopens these via `bin/../lib/`, but the engine tarball
        //     itself doesn't carry them — Sikarugir keeps them in the
        //     app bundle. Without this step the FIRST launch crashes
        //     with `dyld: Library not loaded: @rpath/libinotify.0.dylib`.
        //     Real-world bite: user's Sikarugir backend, 2026-06-15.
        try Self.copyBundleSupportLibs(renderer: renderer, intoLib: lib)

        // 3. Strip quarantine — Rosetta-loaded wine fails dlopen on
        //    quarantined dylibs/frameworks otherwise.
        _ = try? await ProcessRunner.run(
            URL(filePath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", installRoot.path]
        )

        try? Data("Sikarugir D3DMetal (\(version))".utf8)
            .write(to: installRoot.appending(path: Self.assembledMarker))
        // Record what a correct engine looks like, now that it is one.
        var source = ["renderer": renderer.path.contains("/\(Self.templateComponentID)/") ? "catalog template" : "Sikarugir install"]
        if let pair = catalogPair {
            source["engineArchiveSHA256"] = pair.engine.sha256
            source["templateVersion"] = pair.template.version
            source["templateArchiveSHA256"] = pair.template.sha256
        }
        await RuntimeIntegrity.recordDetached(
            root: installRoot, componentID: Self.componentID, version: version,
            origin: .installed, source: source)

        refresh()
        // A fresh extract lays down Sikarugir's own framework, so an opted-in
        // GPTK 4 pairing would be silently reverted by an update. Re-apply it.
        if preferredD3DMetalSource == .gptk4, gptk4Framework() != nil {
            try? await setD3DMetalSource(.gptk4)
        }
    }

    /// Re-stages Sikarugir's support dylibs into an already-installed
    /// engine if the load-bearing ones are missing (libfreetype for text,
    /// libgnutls for TLS/online). No-op once present. Lets installs made
    /// before this staging existed pick up the dylibs on next launch
    /// rather than forcing a delete-and-reinstall.
    @discardableResult
    func backfillSupportLibs() throws -> Bool {
        guard let root = componentManager.installedDirectory(for: Self.componentID) else { return false }
        let lib = root.appending(path: "wswine.bundle/lib", directoryHint: .isDirectory)
        let freetype = lib.appending(path: "libfreetype.dylib")
        let freetype6 = lib.appending(path: "libfreetype.6.dylib")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: freetype.path), !fm.fileExists(atPath: freetype6.path) else { return false }
        guard let renderer = try? d3dMetalRenderer() else { return false }
        try Self.copyBundleSupportLibs(renderer: renderer, intoLib: lib)
        return true
    }

    /// Copies the support dylibs the engine wineserver/wine64 dlopen
    /// at runtime (libinotify, gnutls, freetype, etc.) from Sikarugir's
    /// Template app `Contents/Frameworks/` into our engine's `lib/`. Symlinks
    /// are preserved with `cp -P` so `libinotify.dylib → libinotify.0.dylib`
    /// stays a link, not a duplicate file.
    nonisolated private static func copyBundleSupportLibs(renderer: URL, intoLib lib: URL) throws {
        // renderer is …/Template-1.0.10.app/Contents/Frameworks/renderer/d3dmetal
        // so its grandparent is the Frameworks dir we want to mine.
        let frameworks = renderer.deletingLastPathComponent().deletingLastPathComponent()
        let fm = FileManager.default
        guard fm.fileExists(atPath: frameworks.path) else { return }
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
        let items = (try? fm.contentsOfDirectory(at: frameworks, includingPropertiesForKeys: nil)) ?? []
        for item in items where item.pathExtension == "dylib" {
            let target = lib.appending(path: item.lastPathComponent)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            // copyItem follows symlinks; use the underlying syscall via
            // FileManager's link-preserving copy where possible.
            do {
                let attrs = try fm.attributesOfItem(atPath: item.path)
                if (attrs[.type] as? FileAttributeType) == .typeSymbolicLink {
                    let dest = try fm.destinationOfSymbolicLink(atPath: item.path)
                    try fm.createSymbolicLink(atPath: target.path, withDestinationPath: dest)
                } else {
                    try fm.copyItem(at: item, to: target)
                }
            } catch {
                // Skip unreadable entries — won't all be required at runtime.
                continue
            }
        }
    }

    /// Copies the renderer's three payload groups into the engine lib:
    /// the guest PE DLLs, the host-side `.so`s, and `external/*`. The two
    /// architecture-named directories come from ``WineLayout`` rather than
    /// literals — see docs/FEX-MIGRATION.md.
    nonisolated private static func overlay(
        renderer: URL, intoLib lib: URL, layout: WineLayout = .rosetta
    ) throws {
        let fm = FileManager.default
        let groups = [
            ("wine/\(layout.peDirectory)", "wine/\(layout.peDirectory)"),
            ("wine/\(layout.unixDirectory)", "wine/\(layout.unixDirectory)"),
            ("external", "external"),
        ]
        for (src, dst) in groups {
            let source = renderer.appending(path: src, directoryHint: .isDirectory)
            let destination = lib.appending(path: dst, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: source.path) else { continue }
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                let target = destination.appending(path: item.lastPathComponent)
                if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    /// Ensures the D3DMetal dispatch `.so` files carry an LC_RPATH entry
    /// that lets `@rpath/D3DMetal.framework/D3DMetal` resolve to
    /// `lib/external/D3DMetal.framework/…`. Sikarugir's d3d11.so and
    /// dxgi.so ship with this rpath already; d3d12.so does not — without
    /// it, D3D12 games fail at adapter creation ("D3D12RHI is not
    /// supported"). Idempotent: skips .so files that already have it.
    @discardableResult
    nonisolated private static func patchD3DMetalRpath(
        lib: URL, layout: WineLayout = .rosetta
    ) async throws -> Bool {
        let unixDir = lib.appending(path: "wine/\(layout.unixDirectory)", directoryHint: .isDirectory)
        let neededRpath = "@loader_path/../../external"
        var changed = false
        for name in ["d3d12.so", "d3d11.so", "dxgi.so"] {
            let so = unixDir.appending(path: name)
            guard FileManager.default.fileExists(atPath: so.path) else { continue }
            // In Swift, not with otool/install_name_tool: those need Xcode's
            // Command Line Tools, which a clean Mac doesn't have, and their
            // failure used to be ignored here — leaving an engine that
            // installed fine and couldn't create a D3D12 device.
            guard try MachORpath.add(neededRpath, to: so) else { continue }
            let signed = try await ProcessRunner.run(
                URL(filePath: "/usr/bin/codesign"),
                arguments: ["--force", "--sign", "-", so.path])
            guard signed.succeeded else {
                throw ComponentError.extractionFailed("codesign \(name): \(signed.standardError)")
            }
            changed = true
        }
        return changed
    }

    // MARK: D3DMetal source (experimental GPTK 4 pairing)

    /// Which D3DMetal framework the installed engine is currently running.
    enum D3DMetalSource: String, Sendable {
        /// The framework Sikarugir ships — the tested pairing.
        case sikarugir
        /// Apple's newer framework, lifted from an installed GPTK 4.
        case gptk4
    }

    /// Records the active source beside the engine.
    ///
    /// Written, never read back: the toggle's own state lives in settings and
    /// is re-applied on update, so this is a breadcrumb for whoever is looking
    /// at the component on disk — which is how the equivalent drift in the
    /// GPTK component was actually found. If Fable should ever *report* the
    /// installed renderer, this is what it reads, but nothing does today.
    nonisolated static let sourceMarkerName = ".d3dmetal-source"

    /// GPTK 4's framework inside an installed GPTK component, if present.
    ///
    /// GPTK 3.x and 4.x install to the same component layout, so presence
    /// alone proves nothing — only a framework that exports GPTK 4's
    /// additional `IUnknownIface` symbol is new enough to pair with modern
    /// Wine. Checked by symbol rather than by version string because the
    /// component directory is named for the Wine build, not the framework, and
    /// on this machine a directory labelled `3.0-3` already held GPTK 4's
    /// framework after a hand-injection.
    func gptk4Framework() -> URL? {
        guard let root = componentManager.installedDirectory(for: GPTKManager.componentID) else {
            return nil
        }
        let candidates = [
            "Game Porting Toolkit.app/Contents/Resources/wine/lib/external/D3DMetal.framework",
            "lib/external/D3DMetal.framework",
        ]
        for relative in candidates {
            let framework = root.appending(path: relative, directoryHint: .isDirectory)
            let binary = framework.appending(path: "Versions/A/D3DMetal")
            guard FileManager.default.fileExists(atPath: binary.path) else { continue }
            if Self.exportsGPTK4Marker(binary) { return framework }
        }
        return nil
    }

    /// True when the framework is GPTK 4 or newer — the only generation whose
    /// dispatch surface modern Wine can link against. See ``D3DMetalIdentity``.
    nonisolated static func exportsGPTK4Marker(_ binary: URL) -> Bool {
        D3DMetalIdentity.generation(of: binary) == .gptk4OrNewer
    }

    /// Points the installed engine at `source`, swapping the framework if the
    /// engine isn't already on it. Idempotent, and safe to call on every
    /// launch — that's how the choice survives a Sikarugir update, which would
    /// otherwise overwrite the swap with the stock framework and silently
    /// change behaviour.
    func setD3DMetalSource(_ source: D3DMetalSource) async throws {
        guard let root = componentManager.installedDirectory(for: Self.componentID) else {
            throw SikarugirError.notInstalled
        }
        let external = root.appending(
            path: "wswine.bundle/lib/external", directoryHint: .isDirectory)
        let installed = external.appending(path: "D3DMetal.framework", directoryHint: .isDirectory)
        // Stock framework, stashed before the first swap so .sikarugir can be
        // restored without reinstalling the whole component.
        let backup = root.appending(path: ".d3dmetal-stock", directoryHint: .isDirectory)
        let fm = FileManager.default

        let replacement: URL
        switch source {
        case .gptk4:
            guard let framework = gptk4Framework() else { throw SikarugirError.gptk4Unavailable }
            if !fm.fileExists(atPath: backup.path) {
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                try fm.copyItem(
                    at: installed, to: backup.appending(path: "D3DMetal.framework"))
            }
            replacement = framework
        case .sikarugir:
            let stashed = backup.appending(path: "D3DMetal.framework", directoryHint: .isDirectory)
            // Nothing stashed means the engine was never swapped — already stock.
            guard fm.fileExists(atPath: stashed.path) else {
                try? Data(source.rawValue.utf8).write(to: root.appending(path: Self.sourceMarkerName))
                return
            }
            replacement = stashed
        }

        if fm.fileExists(atPath: installed.path) { try fm.removeItem(at: installed) }
        try fm.copyItem(at: replacement, to: installed)
        // Rosetta refuses to dlopen a quarantined dylib, and it does it by
        // killing the process rather than returning an error.
        _ = try? await ProcessRunner.run(
            URL(filePath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", installed.path])
        _ = try? await ProcessRunner.run(
            URL(filePath: "/usr/bin/codesign"),
            arguments: ["--force", "--sign", "-", installed.path])
        try? Data(source.rawValue.utf8).write(to: root.appending(path: Self.sourceMarkerName))
        // Fable changed the engine on purpose: the record follows, or the
        // next check would report the swap as damage.
        let framework = source.rawValue
        await Task.detached(priority: .utility) {
            RuntimeIntegrity.rerecord(root: root, noting: ["d3dMetalFramework": framework])
        }.value
    }

    // MARK: Binaries

    func wineBinary() throws -> URL {
        guard let root = componentManager.installedDirectory(for: Self.componentID) else {
            throw ComponentError.notInstalled(Self.componentID)
        }
        let candidate = root
            .appending(path: "wswine.bundle/bin/wine64")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        let fallback = root.appending(path: "wswine.bundle/bin/wine")
        if FileManager.default.isExecutableFile(atPath: fallback.path) {
            return fallback
        }
        throw SikarugirError.binaryNotFound(root.path)
    }

    func wineserverBinary() throws -> URL {
        try wineBinary().deletingLastPathComponent().appending(path: "wineserver")
    }

    // MARK: Launch

    /// The wswine.bundle root for an install (…/wswine.bundle), derived
    /// from the wine binary at …/wswine.bundle/bin/wine.
    func bundleRoot() throws -> URL {
        try wineBinary().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Forces the D3DMetal-backed builtin d3d DLLs so nothing in the
    /// prefix's system32 shadows them, AND points D3DMetal at its
    /// framework.
    ///
    /// `WINEMSYNC=1` (NOT esync) is load-bearing for Steam: esync's eventfd
    /// waits degrade into a CPU spin-poll under Rosetta, so Steam's IOCP
    /// network threads pin 4+ cores in `__wine_syscall_dispatcher` and starve
    /// downloads to ~0 with multi-minute stalls. msync uses Mach's
    /// `os_sync_wait_on_address`, so those threads block properly — measured
    /// 411%→32% CPU and 0→60+ Mbps on a stuck 30 GB download. The Sikarugir
    /// wine supports both; we deliberately override its esync default.
    /// See memory fable-steam-install-wow64-gap.
    ///
    /// `D3DMETAL_FRAMEWORK_PATH` is the load-bearing piece: the d3dmetal
    /// dispatch (d3d11.so) dlopens D3DMetal via this env var, falling back
    /// to /System/Library/Frameworks (where it isn't). Without it the
    /// Metal client surface is never created, so anything using the GPU
    /// compositor — most visibly Steam's CEF login — renders as a black
    /// square. Discovered 2026-06-24; see memory fable-winemac-drv-gap.
    /// `CX_APPLEGPTK_LIBD3DSHARED_PATH` points at the shared GPTK lib the
    /// dispatch also needs. Both files ship inside the bundle's
    /// `lib/external` (staged from Sikarugir's renderer at install).
    nonisolated static func launchEnvironment(baseOverrides: String, bundleRoot: URL?) -> [String: String] {
        var env: [String: String] = [
            "WINEDLLOVERRIDES": "\(baseOverrides);\(builtinDLLs.joined(separator: ","))=b",
            "WINEMSYNC": "1",
        ]
        guard let bundleRoot else { return env }
        let external = bundleRoot.appending(path: "lib/external", directoryHint: .isDirectory)
        let framework = external.appending(path: "D3DMetal.framework/Versions/A/D3DMetal")
        if FileManager.default.fileExists(atPath: framework.path) {
            env["D3DMETAL_FRAMEWORK_PATH"] = framework.path
        }
        let d3dshared = external.appending(path: "libd3dshared.dylib")
        if FileManager.default.fileExists(atPath: d3dshared.path) {
            env["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = d3dshared.path
        }
        return env
    }
}
