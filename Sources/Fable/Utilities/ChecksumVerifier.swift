import CryptoKit
import Foundation

enum ChecksumError: LocalizedError {
    case mismatch(file: String, expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .mismatch(let file, _, _):
            "Downloaded file \(file) failed checksum verification. The download may be corrupted — try again."
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

    /// Throws ChecksumError.mismatch unless the file's SHA-256 equals
    /// `expected` (case-insensitive hex).
    static func verify(_ fileURL: URL, sha256 expected: String) throws {
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
