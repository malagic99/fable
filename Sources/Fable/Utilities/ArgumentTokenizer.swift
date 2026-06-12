import Foundation

/// Splits a launch-arguments string shell-style: whitespace-separated,
/// with single or double quotes grouping (quotes stripped). No variable
/// expansion or escapes — predictable and good enough for game flags.
enum ArgumentTokenizer {
    static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasContent = false

        for character in input {
            if let active = quote {
                if character == active {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
                hasContent = true
            } else if character.isWhitespace {
                if hasContent || !current.isEmpty {
                    tokens.append(current)
                    current = ""
                    hasContent = false
                }
            } else {
                current.append(character)
            }
        }
        if hasContent || !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Parses "KEY=VALUE" lines into environment overrides; blank lines
    /// and lines without "=" are ignored.
    static func environment(fromLines text: String) -> [String: String] {
        var env: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "="), eq != trimmed.startIndex else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eq)...])
            env[key] = value
        }
        return env
    }

    static func lines(fromEnvironment env: [String: String]) -> String {
        env.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }
}
