import Foundation
import Testing
@testable import Fable

/// THE localization gate. SwiftUI view literals (`Text("…")`, `Button("…")`,
/// `.help("…")`, …) localize keyed by their English text — a key missing from
/// es/pt silently renders English. This suite scans the actual source tree,
/// extracts every such literal, and fails naming the exact strings to add.
///
/// Adding a UI string: write the English literal in the view, then add a line
/// to es.lproj and pt.lproj (value = the key itself is fine for proper nouns
/// like "D3DMetal"). Strings built in code go through `L10n.string("dotted.key")`
/// — those are covered by LocalizationTests' parity test instead.
@Suite struct LocalizationCoverageTests {
    /// Repo root derived from this file's location — the tests run from the
    /// package, so the sources are always siblings.
    private static let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // FableTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appending(path: "Sources/Fable", directoryHint: .isDirectory)

    /// First string argument of the initializers that take a
    /// LocalizedStringKey, plus `.help("…")` and `prompt: Text("…")`.
    private static let patterns = [
        #"(?:Text|Button|Toggle|Picker|LabeledContent|TextField|SecureField|Section|Label|Menu|Link|ContentUnavailableView)\(\s*"([^"\\]+)""#,
        #"\.help\(\s*"([^"\\]+)"\)"#,
        #"prompt:\s*Text\(\s*"([^"\\]+)"\)"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    private func stringsKeys(_ lang: String) throws -> Set<String> {
        let url = Self.sourcesRoot.appending(path: "Resources/\(lang).lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        let line = try NSRegularExpression(pattern: #"^"((?:[^"\\]|\\.)+)"\s*="#, options: [.anchorsMatchLines])
        var keys = Set<String>()
        line.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
            if let match, let range = Range(match.range(at: 1), in: text) {
                keys.insert(String(text[range]).replacingOccurrences(of: "\\\"", with: "\""))
            }
        }
        return keys
    }

    private func viewLiterals() throws -> [String: [String]] {  // literal -> files
        var found: [String: [String]] = [:]
        let enumerator = FileManager.default.enumerator(at: Self.sourcesRoot, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for regex in Self.patterns {
                regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
                    guard let match, let range = Range(match.range(at: 1), in: text) else { return }
                    let literal = String(text[range])
                    // Not UI text: dotted/underscored L10n keys, interpolations,
                    // single characters.
                    if literal.range(of: #"^[a-z0-9_.]+$"#, options: .regularExpression) != nil { return }
                    if literal.contains("\\(") || literal.count < 2 { return }
                    found[literal, default: []].append(url.lastPathComponent)
                }
            }
        }
        return found
    }

    /// `Text(cond ? "a" : "b")` and `Text("… \(x) …")` are String-typed, so
    /// they skip localization even though they look like literals — the exact
    /// trap that shipped English into the Tune sheet and trigger lab. This
    /// flags any such site not wrapped in `L10n.string`. Genuinely-verbatim
    /// cases (data, universal formats) are allowlisted by the source line.
    @Test
    func noStringTernaryOrInterpolationSkipsLocalization() throws {
        // Substrings of source lines that are legitimately non-localizable:
        // runtime data, empty fallbacks, or universal formats (hardware specs,
        // "120 fps"). Keep this list short and justified.
        let allowed = [
            "launchError ??",       // error text, verbatim
            "isEmpty ? \" \"",      // raw log line
            "performanceCores)P +", // "8P + 4E" — universal hardware spec
            "fps\" }",              // "120 fps" — universal
        ]
        let ternary = try NSRegularExpression(pattern: #"(?:Text|\.help)\([^)\n]*\?[^)\n]*"[^"]+"[^)\n]*:"#)
        let interp = try NSRegularExpression(pattern: #"Text\("[^"]*\\\([^)]*\)[^"]*"\)"#)

        var offenders: [String] = []
        let enumerator = FileManager.default.enumerator(at: Self.sourcesRoot, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let s = String(line)
                if s.contains("L10n.string") { continue }
                if allowed.contains(where: s.contains) { continue }
                let range = NSRange(s.startIndex..., in: s)
                if ternary.firstMatch(in: s, range: range) != nil
                    || interp.firstMatch(in: s, range: range) != nil {
                    offenders.append("\(url.lastPathComponent):\(n + 1)  \(s.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offenders.isEmpty,
                "String ternary/interpolation in Text/help skips localization — wrap in L10n.string or allowlist if truly verbatim:\n\(offenders.joined(separator: "\n"))")
    }

    @Test
    func everyViewLiteralHasSpanishAndPortuguese() throws {
        let es = try stringsKeys("es")
        let pt = try stringsKeys("pt")
        let literals = try viewLiterals()
        // Sanity: the scan actually sees the codebase (guards against a
        // path regression silently passing an empty set).
        #expect(literals.count > 200)

        let missing = literals.filter { !es.contains($0.key) || !pt.contains($0.key) }
        let report = missing
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\" (\($0.value.joined(separator: ", ")))" }
            .joined(separator: "\n")
        #expect(missing.isEmpty,
                "Untranslated view literals — add to es.lproj AND pt.lproj (value = key is fine for proper nouns):\n\(report)")
    }

    /// Every dotted key referenced via L10n.string("…") in code must exist in
    /// ALL languages — a missing one renders as the raw key on screen.
    @Test
    func everyL10nKeyExistsInAllLanguages() throws {
        let regex = try NSRegularExpression(pattern: #"L10n\.string\(\s*"([a-z0-9_.]+)""#)
        var used: Set<String> = []
        let enumerator = FileManager.default.enumerator(at: Self.sourcesRoot, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            regex.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, _ in
                if let match, let range = Range(match.range(at: 1), in: text) {
                    used.insert(String(text[range]))
                }
            }
        }
        #expect(used.count > 15)
        for lang in ["en", "es", "pt"] {
            let keys = try stringsKeys(lang)
            let missing = used.subtracting(keys).sorted()
            #expect(missing.isEmpty, "\(lang).lproj is missing L10n keys: \(missing)")
        }
    }
}
