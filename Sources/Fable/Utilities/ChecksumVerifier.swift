import CryptoKit
import Foundation

enum ChecksumError: LocalizedError {
    case mismatch(file: String, expected: String, actual: String)
    /// No usable SHA-256 to check against — the download is refused rather
    /// than installed unverified.
    case notPinned(file: String)

    var errorDescription: String? {
        switch self {
        case .mismatch(let file, _, _):
            "Downloaded file \(file) failed checksum verification. The download may be corrupted — try again."
        case .notPinned(let file):
            "\(file) has no checksum to verify it against, so Fable won't install it."
        }
    }
}

/// Streaming SHA-256 of files on disk, for verifying downloaded components.
enum ChecksumVerifier {
    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// True for a SHA-256 written as 64 hex digits (either case).
    static func isPinned(_ sha256: String) -> Bool {
        sha256.count == 64 && sha256.allSatisfy(\.isHexDigit)
    }

    /// Throws ChecksumError.mismatch unless the file's SHA-256 equals
    /// `expected` (case-insensitive hex), and ChecksumError.notPinned when
    /// `expected` isn't a SHA-256 at all — an empty or malformed pin fails
    /// closed instead of skipping the check.
    static func verify(_ fileURL: URL, sha256 expected: String) throws {
        guard isPinned(expected) else {
            throw ChecksumError.notPinned(file: fileURL.lastPathComponent)
        }
        let actual = try sha256(of: fileURL)
        guard actual.lowercased() == expected.lowercased() else {
            throw ChecksumError.mismatch(
                file: fileURL.lastPathComponent,
                expected: expected.lowercased(),
                actual: actual
            )
        }
    }
}
