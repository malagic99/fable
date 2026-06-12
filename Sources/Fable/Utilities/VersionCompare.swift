import Foundation

/// Compares component version strings like "11.0_1", "11.10", "0.80".
/// Splits on . _ - and compares numerically where possible.
enum VersionCompare {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(of: candidate)
        let b = parts(of: current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : .number(0)
            let y = i < b.count ? b[i] : .number(0)
            if x == y { continue }
            switch (x, y) {
            case (.number(let n), .number(let m)): return n > m
            case (.text(let s), .text(let t)): return s > t
            // Numbered parts outrank text parts ("11.0" > "11.0-rc1").
            case (.number, .text): return true
            case (.text, .number): return false
            }
        }
        return false
    }

    private enum Part: Equatable {
        case number(Int)
        case text(String)
    }

    private static func parts(of version: String) -> [Part] {
        version
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .components(separatedBy: CharacterSet(charactersIn: "._- "))
            .filter { !$0.isEmpty }
            .map { Int($0).map(Part.number) ?? .text($0) }
    }
}
