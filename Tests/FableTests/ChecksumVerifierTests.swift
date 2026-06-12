import Foundation
import Testing
@testable import Fable

@Suite struct ChecksumVerifierTests {
    private func tempFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "checksum-\(UUID().uuidString).txt")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test
    func computesKnownSHA256() throws {
        let url = try tempFile("hello")
        defer { try? FileManager.default.removeItem(at: url) }

        // shasum -a 256 of "hello"
        #expect(try ChecksumVerifier.sha256(of: url) ==
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test
    func verifyAcceptsMatchCaseInsensitively() throws {
        let url = try tempFile("hello")
        defer { try? FileManager.default.removeItem(at: url) }

        try ChecksumVerifier.verify(
            url,
            sha256: "2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"
        )
    }

    @Test
    func verifyThrowsOnMismatch() throws {
        let url = try tempFile("tampered")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ChecksumError.self) {
            try ChecksumVerifier.verify(url, sha256: String(repeating: "0", count: 64))
        }
    }
}
