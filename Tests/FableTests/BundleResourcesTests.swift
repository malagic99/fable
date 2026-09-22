import Foundation
import Testing

@testable import Fable

@Suite("Bundled resources")
struct BundleResourcesTests {

    /// The regression behind v0.23.3 crashing on launch for everyone except
    /// the machine that built it.
    ///
    /// SwiftPM's `Bundle.module` looks beside the executable and then at an
    /// absolute path inside the build directory of the compiling machine. An
    /// .app keeps resources in `Contents/Resources`, so the first misses and
    /// the second only exists on the developer's Mac — where it silently
    /// rescues every launch and hides the bug. Anywhere else the accessor
    /// reaches its `fatalError` and the app dies with SIGTRAP before drawing.
    ///
    /// Resolving the bundle at all is the assertion: `Bundle.fableResources`
    /// must find resources through a path that survives being shipped.
    @Test
    func resourceBundleResolves() {
        #expect(Bundle.fableResources.bundleURL.lastPathComponent.hasSuffix(".bundle"))
    }

    /// versions.json is read during startup, so losing it is a launch crash
    /// rather than a degraded feature.
    @Test
    func bundledVersionCatalogLoads() throws {
        let catalog = try VersionCatalog.loadBundled()
        #expect(!catalog.components.isEmpty)
        #expect(catalog.components["wine"] != nil)
    }

    /// Localized lookups go through the same bundle; if it resolved to
    /// something without the string tables, keys would render raw on screen.
    @Test
    func localizedStringsResolveThroughTheSameBundle() {
        let sidebar = L10n.string("sidebar.bottles")
        #expect(sidebar != "sidebar.bottles", "key echoed back — string table not found")
        #expect(!sidebar.isEmpty)
    }

    /// The tests above run from a test runner, not an `.app`, so they would
    /// have passed while v0.23.3 was crashing on every other Mac. This is the
    /// check that actually holds the line: nothing may reach for
    /// `Bundle.module` directly, because its build-directory fallback makes a
    /// packaging mistake invisible on the machine that builds the release.
    @Test
    func nothingUsesBundleModuleDirectly() throws {
        let sources = URL(filePath: #filePath)
            .deletingLastPathComponent()      // FableTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // repo root
            .appending(path: "Sources/Fable")
        let accessor = "BundleResources.swift"   // the one place allowed to fall back

        var offenders: [String] = []
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        for case let url as URL in enumerator! where url.pathExtension == "swift" {
            guard url.lastPathComponent != accessor,
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                guard line.contains("Bundle.module") || line.contains("bundle: .module") else { continue }
                // Prose about the pitfall is fine; code reaching for it is not.
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("///") || code.hasPrefix("*") { continue }
                offenders.append("\(url.lastPathComponent):\(index + 1): \(code)")
            }
        }
        #expect(offenders.isEmpty, """
            Use Bundle.fableResources instead — Bundle.module resolves via the \
            build directory of the machine that compiled it, so this crashes \
            on every other Mac while working on yours:
            \(offenders.joined(separator: "\n"))
            """)
    }
}
