import CryptoKit
import Foundation
import Testing
@testable import Fable

/// The Authenticode check, against a tiny PE signed by a throwaway test CA
/// (generated once with OpenSSL; the key isn't kept). The real Microsoft
/// installers are covered by the opt-in LiveRedistSignatureTests.
@Suite struct AuthenticodeTests {
    static let testPublisher = AuthenticodePublisher(
        name: "Fable Test Publisher",
        anchors: [Data(base64Encoded: testRoot, options: .ignoreUnknownCharacters)!]
    )

    /// 1,928 bytes: a 512-byte PE32 image (no sections) plus its signature.
    /// Header checksum at 152, security directory entry at 216.
    static let signedProgram = """
    TVoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAQAAAAFBFAABMAQAAAAAAAAAAAAAAAAAA4AACAQsBAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0EgAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAIgFAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAARmFibGUgQXV0aGVudGlj
    b2RlIGZpeHR1cmUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACI
    BQAAAAICADCCBXUGCSqGSIb3DQEHAqCCBWYwggViAgEBMQ8wDQYJYIZIAWUDBAIBBQAwVgYKKwYB
    BAGCNwIBBKBIMEYwEQYKKwYBBAGCNwIBDzADAwEAMDEwDQYJYIZIAWUDBAIBBQAEIGXRi8Bli6Z6
    wcmSTQzT4HYRVlXFhtFwwy/ZbOQvDIeloIIDQTCCAz0wggIloAMCAQICAQIwDQYJKoZIhvcNAQEL
    BQAwLzETMBEGA1UECgwKRmFibGUgVGVzdDEYMBYGA1UEAwwPRmFibGUgVGVzdCBSb290MCAXDTI2
    MTEyMzE2MDM1NFoYDzIxMjYxMDMwMTYwMzU0WjA+MR0wGwYDVQQKDBRGYWJsZSBUZXN0IFB1Ymxp
    c2hlcjEdMBsGA1UEAwwURmFibGUgVGVzdCBQdWJsaXNoZXIwggEiMA0GCSqGSIb3DQEBAQUAA4IB
    DwAwggEKAoIBAQCxS/jr3jGItBtFSEqvakZe2sYlOuVdL3oDEPe/eI52dRzPE8QSFEScV9/1UIV+
    tNAKLtviqwAi1jbUHGDXrxw6ERgBusL4wvOhVtbRwS/A5fDuzx7GUckAu4FlVXHMDBp8Az7f8e8j
    FnyM1DBAnDnQ3xCAwdzpinmsjUFlN1bchtxEiLsj4TPA4Xc9Tu91qaNWG1wqwISfFNFENlo/85Yk
    662TZfyT4fZVJfeSh4QnN/WIrD7TPX5FqicuaTukELaxubGrNRL8QpFAM+QhdziCj5lysfi2QlEu
    y/I/yztENQWMwqtdp/EEviWWZj1b5mOua7ivrXU4Qyk78ylwf28/AgMBAAGjUzBRMAkGA1UdEwQC
    MAAwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB8GA1UdIwQYMBaAFGaJkdns
    A+dR9RxnrxXgJtsr9/FnMA0GCSqGSIb3DQEBCwUAA4IBAQC+Fx5H8rrMe/HdZBqcst4r71kxBQXJ
    ELDLcmKTqpFFyB07jWXcHgVzV56r4avU6l9vYRieTuc8NTu2Y6h+R8RTM/HpUZpSguQwqpVVpgQU
    N4D2OWquB9Ridj6hW+N4gn3PsocaJaiRyS3j5j31gUTuIauj7wVG49avbbhd1fOk+AnoqYvYH7Ew
    nY1BgZCs75d+qB2bVY1kvKSEC1iG0yU39xMrvZkzfqLI2sVXaw1SSaxKAU0UUtMR8dE5kS9Po33N
    PoK3PexoAVyOIY1GkjR+ErcgYERaREI+VNWmAWsjL8lVXcg0RWBCth1DUwq+lgbQR8oIRi46KMVk
    rFzpcTFRMYIBrTCCAakCAQEwNDAvMRMwEQYDVQQKDApGYWJsZSBUZXN0MRgwFgYDVQQDDA9GYWJs
    ZSBUZXN0IFJvb3QCAQIwDQYJYIZIAWUDBAIBBQCgTDAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIB
    BDAvBgkqhkiG9w0BCQQxIgQgaA3V44fbGZdP02CbsVRc7Oz41nkPuudmeKgEDDR6zVgwDQYJKoZI
    hvcNAQEBBQAEggEAL05g46p0MgbACuOjh2Z6GEJPExKXIZt5LaN065eK/0vkoYxoI4v9jBwlEvbl
    LE5FYK8zF8zNmqgbDyYKaT/wKGHMtZ4DiDfkiYRZTkSXZqL/FBgexo5FIZN2e8HgEHeBrveM6BdI
    ER7YSeS6Jlb65u9kHho7tIh8bdPpnEs4/bYTZDy10CU62g/8jm4MIYkwN0YG0hggQE1pPtfp08r9
    ysR8cvTkjB/pPbjbxtN5Gbca0v4cOpcC5gHU24ZK48nWs3IPIsRduStlV0uHclxz3SHbZHoUcsZl
    BEqd9/pdsIfvrVJHyq/bduaRcemTJY0RaRiEP70G4zsO8aPsfUaopgAAAAAAAAA=
    """

    static let testRoot = """
    MIIDHTCCAgWgAwIBAgIBATANBgkqhkiG9w0BAQsFADAvMRMwEQYDVQQKDApGYWJsZSBUZXN0MRgw
    FgYDVQQDDA9GYWJsZSBUZXN0IFJvb3QwIBcNMjYxMTIzMTYwMzUzWhgPMjEyNjEwMzAxNjAzNTNa
    MC8xEzARBgNVBAoMCkZhYmxlIFRlc3QxGDAWBgNVBAMMD0ZhYmxlIFRlc3QgUm9vdDCCASIwDQYJ
    KoZIhvcNAQEBBQADggEPADCCAQoCggEBAL4mCu8GfBx+PGERieEfKeppzivQnDic+FBbEeUz+4Eh
    PTe/CxzKi6OqXTxR7qxtcV7YK/CwOJW9NqnBXlrYlziQxtspoQ26QhkpQVWJm6EWFkFXJJK/Kkde
    CfX8QsMlpst+9GyeijCPZfEfRic7dDXg/3kjD0t1E8uBbnQk/SEquimUxxRxiwABPh4bf4vPXj7G
    DilIDxgNxwRZnhnAy7H2F+632QQaFNT5RQjmbe62bZ2hmrn919UVVJs9wrdi4ku98OF8abveKzIG
    CnmyzKq1wUQ+3BuY4w2QLiEMv4PPODpdKoLAE48xwRcUdI/cZ8Risl+KMjQAiAF8lGQijOMCAwEA
    AaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMCAQYwHQYDVR0OBBYEFGaJkdnsA+dR
    9RxnrxXgJtsr9/FnMA0GCSqGSIb3DQEBCwUAA4IBAQCnEjWwZVYVsKOt9ij0dW5qQ1tVR6rpNxd2
    wNc6HtaOY+Ut67z45LcTSNzTJi2+HLcq6OPchXPGXwQq/D644JJFmDNPmKrUQGVMdXzW24gFtdrW
    ugN6wkJwhvgpT8VlVCp8LIqGmuI242EywYhS4KJpGN+RLTVWP6iVVI6hSHzLDb67MpbHLgXrLrfs
    a79Bp1U2X8XgLM4UPOqXSRWEodIlM/oVnHJOI6BZHru2dmtXjSstHblY8Npimq33khkSzvx5APDe
    +CkN10W+t9QM9l+FxRmvM23qVQZgq6XUBJws01cWzRcUrM53EVMDNJSZMsqgD2/XwYSOGVS4Hbyu
    /rMa
    """

    func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "authenticode-\(UUID()).exe")
        try data.write(to: url)
        return url
    }

    func program() -> Data {
        Data(base64Encoded: Self.signedProgram, options: .ignoreUnknownCharacters)!
    }

    func check(_ data: Data, publisher: AuthenticodePublisher = testPublisher) throws {
        let url = try write(data)
        defer { try? FileManager.default.removeItem(at: url) }
        try Authenticode.verify(url, publisher: publisher)
    }

    @Test func aGoodSignatureVerifies() throws {
        try check(program())
    }

    @Test func theFieldsSigningChangesAreNotCovered() throws {
        // The header checksum is rewritten after signing, so it can't be signed.
        var data = program()
        data[152] ^= 0xFF
        try check(data)
    }

    @Test func anyOtherChangedByteFails() throws {
        for offset in [0x3D, 0x58, 0x180, 511] {
            var data = program()
            data[offset] ^= 0x01
            #expect(throws: AuthenticodeError.self, "byte \(offset)") { try check(data) }
        }
        var data = program()
        data[0x180] ^= 0x01
        #expect {
            try check(data)
        } throws: { error in
            if case .badSignature(_, let reason) = error as? AuthenticodeError {
                return reason == "file digest doesn't match the signed digest"
            }
            return false
        }
    }

    @Test func aChangedSignatureFails() throws {
        var data = program()
        data[data.count - 40] ^= 0x01 // inside the RSA signature value
        #expect {
            try check(data)
        } throws: { error in
            if case .badSignature(_, let reason) = error as? AuthenticodeError {
                return reason == "signature doesn't verify"
            }
            return false
        }
    }

    @Test func bytesAfterTheSignatureAreRefused() throws {
        var data = program()
        data.append(contentsOf: [0x4D, 0x5A])
        #expect(throws: AuthenticodeError.self) { try check(data) }
    }

    @Test func anotherPublishersNameIsRefused() throws {
        let other = AuthenticodePublisher(name: "Microsoft Corporation", anchors: Self.testPublisher.anchors)
        #expect {
            try check(program(), publisher: other)
        } throws: { error in
            if case .wrongPublisher = error as? AuthenticodeError { return true }
            return false
        }
    }

    @Test func aChainToAnotherRootIsRefused() throws {
        // Right name, but the test CA isn't Microsoft's root.
        let impostor = AuthenticodePublisher(name: "Fable Test Publisher",
                                             anchors: AuthenticodePublisher.microsoft.anchors)
        #expect {
            try check(program(), publisher: impostor)
        } throws: { error in
            if case .wrongPublisher = error as? AuthenticodeError { return true }
            return false
        }
    }

    @Test func anUnsignedProgramIsRefused() throws {
        var data = program().prefix(512)
        for k in 216..<224 { data[k] = 0 }
        #expect {
            try check(Data(data))
        } throws: { error in
            if case .unsigned = error as? AuthenticodeError { return true }
            return false
        }
    }

    @Test func somethingThatIsntAProgramIsRefused() throws {
        for junk in [Data(), Data("not a program".utf8), Data(repeating: 0x4D, count: 4096)] {
            #expect(throws: AuthenticodeError.self) { try check(junk) }
        }
    }

    @Test func truncatedFilesNeverCrash() throws {
        let full = program()
        for length in stride(from: 0, to: full.count, by: 7) {
            #expect(throws: AuthenticodeError.self) { try check(full.prefix(length)) }
        }
    }

    @Test func theBundledMicrosoftRootIsTheOneMicrosoftPublishes() {
        let root = AuthenticodePublisher.microsoft.anchors[0]
        #expect(Insecure.SHA1.hash(data: root).map { String(format: "%02X", $0) }.joined()
                == "8F43288AD272F3103B6FB1428485EA3014C0BCFE")
        #expect(SHA256.hash(data: root).map { String(format: "%02x", $0) }.joined()
                == "847df6a78497943f27fc72eb93f9a637320a02b561d0a91b09e87a7807ed7c61")
    }
}

@Suite struct DependencyDownloadCheckTests {
    @Test func everyMicrosoftDownloadMustBeSignedByMicrosoft() {
        for dependency in DependencyCatalog.all where dependency.url.host()?.contains("microsoft") == true
            || dependency.url.host() == "aka.ms" {
            guard case .signedBy(let publisher) = dependency.check else {
                Issue.record("\(dependency.id) isn't signature-checked"); continue
            }
            #expect(publisher.name == "Microsoft Corporation", "\(dependency.id)")
        }
    }

    @Test func everyPinnedHashIsARealHash() {
        for dependency in DependencyCatalog.all {
            if case .sha256(let pin) = dependency.check {
                #expect(ChecksumVerifier.isPinned(pin), "\(dependency.id)")
            }
        }
    }
}
