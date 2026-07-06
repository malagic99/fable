import Foundation

/// One installable winetricks verb. The id is the slug (`corefonts`),
/// the title is the human label (`MS Arial, Times New Roman, …`).
struct WinetricksVerb: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case apps
        case benchmarks
        case dlls
        case fonts
        case settings

        var id: String { rawValue }

        var displayName: String { L10n.string("winetricks.category.\(rawValue)") }
    }

    let id: String
    let category: Category
    let title: String

    /// Combined haystack for filtering — `dotnet48 .NET Framework 4.8`.
    var searchText: String { "\(id) \(title)".lowercased() }
}

/// Parses the upstream winetricks shell script's `w_metadata` blocks
/// into a verb list.
///
/// Format (one block per verb):
///     w_metadata <slug> <category> \
///         title="MS Arial, ..." \
///         publisher="Microsoft" \
///         ...
enum WinetricksCatalog {
    /// Scans `script` for `w_metadata` blocks and returns the verbs.
    static func verbs(fromScript script: String) -> [WinetricksVerb] {
        var result: [WinetricksVerb] = []
        let lines = script.split(separator: "\n", omittingEmptySubsequences: false)
        var index = 0
        while index < lines.count {
            let raw = lines[index]
            if let verb = parseHeader(raw) {
                let title = scanTitle(lines: lines, after: index)
                result.append(WinetricksVerb(
                    id: verb.slug,
                    category: verb.category,
                    title: title ?? verb.slug
                ))
            }
            index += 1
        }
        return result
    }

    /// Recognizes `w_metadata <slug> <category> [\]`. Returns nil if it
    /// isn't a verb header (some scripts call `w_metadata()` without args).
    private static func parseHeader(_ raw: Substring) -> (slug: String, category: WinetricksVerb.Category)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("w_metadata ") else { return nil }
        let after = trimmed.dropFirst("w_metadata ".count)
        let parts = after.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2,
              let category = WinetricksVerb.Category(rawValue: String(parts[1]))
        else { return nil }
        return (String(parts[0]), category)
    }

    /// `title="..."` may sit on the header line or any subsequent
    /// continuation line in the same metadata block.
    private static func scanTitle(lines: [Substring], after headerIndex: Int) -> String? {
        var i = headerIndex
        // Look at the header line and up to a handful of continuation
        // lines (winetricks blocks are short and end at a non-backslash line).
        while i < lines.count && i - headerIndex < 12 {
            let line = lines[i]
            if let value = capturedString(in: line, key: "title") {
                return value
            }
            // Stop at end of metadata block: a line that doesn't end with \
            // and isn't the header itself.
            if i != headerIndex && !line.hasSuffix("\\") {
                break
            }
            i += 1
        }
        return nil
    }

    /// Extracts the double-quoted value of `key="…"` from one line.
    private static func capturedString(in line: Substring, key: String) -> String? {
        guard let range = line.range(of: "\(key)=\"") else { return nil }
        let valueStart = range.upperBound
        guard let valueEnd = line[valueStart...].firstIndex(of: "\"") else { return nil }
        return String(line[valueStart..<valueEnd])
    }
}
