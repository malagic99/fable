import Foundation

/// A node in a Valve KeyValues (VDF) document — the format Steam's
/// `appmanifest_*.acf` files use. Either a leaf string or an ordered list
/// of child key/value pairs (order preserved so re-serializing stays close
/// to Steam's own layout).
indirect enum VDFValue: Equatable {
    case string(String)
    case object([(key: String, value: VDFValue)])

    static func == (lhs: VDFValue, rhs: VDFValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(a), .string(b)): a == b
        case let (.object(a), .object(b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    /// First child value for `key` (objects only).
    subscript(key: String) -> VDFValue? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    /// Convenience leaf-string accessor.
    func string(_ key: String) -> String? {
        if case .string(let s) = self[key] { return s }
        return nil
    }

    func int(_ key: String) -> Int? { string(key).flatMap(Int.init) }

    /// Sets `key` to a leaf string, replacing in place or appending.
    mutating func set(_ key: String, _ value: String) {
        guard case .object(var pairs) = self else { return }
        if let idx = pairs.firstIndex(where: { $0.key == key }) {
            pairs[idx].value = .string(value)
        } else {
            pairs.append((key, .string(value)))
        }
        self = .object(pairs)
    }

    /// Sets `key` to an object child, replacing in place or appending.
    mutating func set(_ key: String, object: VDFValue) {
        guard case .object(var pairs) = self else { return }
        if let idx = pairs.firstIndex(where: { $0.key == key }) {
            pairs[idx].value = object
        } else {
            pairs.append((key, object))
        }
        self = .object(pairs)
    }
}

/// Minimal Valve KeyValues reader/writer — quoted keys/values and nested
/// `{ }` blocks, which is everything `appmanifest_*.acf` uses. Not a full
/// VDF implementation (no macros, unquoted tokens, or conditionals).
enum SteamKeyValues {
    /// Parses a document into its single root pair (e.g. `"AppState" { … }`).
    static func parse(_ text: String) -> (key: String, value: VDFValue)? {
        var tokens = tokenize(text)[...]
        return parsePair(&tokens)
    }

    /// Serializes a root pair back to VDF text with tab indentation.
    static func serialize(key: String, value: VDFValue) -> String {
        var out = ""
        write(key: key, value: value, indent: 0, into: &out)
        return out
    }

    // MARK: Tokenizing

    private enum Token: Equatable { case string(String), open, close }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "{": tokens.append(.open); i += 1
            case "}": tokens.append(.close); i += 1
            case "\"":
                i += 1
                var s = ""
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count {
                        // VDF escapes: \\ \" \t \n
                        let next = chars[i + 1]
                        switch next {
                        case "\\": s.append("\\")
                        case "\"": s.append("\"")
                        case "t": s.append("\t")
                        case "n": s.append("\n")
                        default: s.append(next)
                        }
                        i += 2
                    } else {
                        s.append(chars[i]); i += 1
                    }
                }
                i += 1  // closing quote
                tokens.append(.string(s))
            case "/" where i + 1 < chars.count && chars[i + 1] == "/":
                while i < chars.count, chars[i] != "\n" { i += 1 }
            default:
                i += 1  // whitespace / stray
            }
        }
        return tokens
    }

    private static func parsePair(_ tokens: inout ArraySlice<Token>) -> (key: String, value: VDFValue)? {
        guard case .string(let key)? = tokens.first else { return nil }
        tokens = tokens.dropFirst()
        guard let next = tokens.first else { return (key, .string("")) }
        switch next {
        case .string(let value):
            tokens = tokens.dropFirst()
            return (key, .string(value))
        case .open:
            tokens = tokens.dropFirst()
            var pairs: [(key: String, value: VDFValue)] = []
            while let t = tokens.first, t != .close {
                guard let pair = parsePair(&tokens) else { break }
                pairs.append(pair)
            }
            if tokens.first == .close { tokens = tokens.dropFirst() }
            return (key, .object(pairs))
        case .close:
            return (key, .string(""))
        }
    }

    // MARK: Serializing

    private static func write(key: String, value: VDFValue, indent: Int, into out: inout String) {
        let pad = String(repeating: "\t", count: indent)
        switch value {
        case .string(let s):
            out += "\(pad)\"\(escape(key))\"\t\t\"\(escape(s))\"\n"
        case .object(let pairs):
            out += "\(pad)\"\(escape(key))\"\n\(pad){\n"
            for pair in pairs {
                write(key: pair.key, value: pair.value, indent: indent + 1, into: &out)
            }
            out += "\(pad)}\n"
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
