import CryptoKit
import Foundation
import Security

/// Who must have signed a downloaded Windows installer.
struct AuthenticodePublisher: Sendable {
    /// The signing certificate's subject must carry exactly this
    /// organization *and* common name.
    let name: String
    /// DER root certificates the chain must end in — and only these: the
    /// system trust store is not consulted.
    let anchors: [Data]

    /// Microsoft's code-signing hierarchy: `Microsoft Root Certificate
    /// Authority 2011` → `Microsoft Code Signing PCA 2011` → `Microsoft
    /// Corporation`. Everything Fable downloads from Microsoft (the Visual C++
    /// and DirectX redistributables) is signed this way.
    ///
    /// The root isn't in macOS's trust store, so it ships here. It is the
    /// certificate Microsoft publishes at
    /// microsoft.com/pki/certs/MicRooCerAut2011_2011_03_22.crt, whose published
    /// SHA-1 thumbprint is 8F43288AD272F3103B6FB1428485EA3014C0BCFE; a test
    /// pins its SHA-256 so it can't drift unnoticed.
    static let microsoft = AuthenticodePublisher(
        name: "Microsoft Corporation",
        anchors: [Data(base64Encoded: microsoftRoot2011, options: .ignoreUnknownCharacters)!]
    )

    static let microsoftRoot2011 = """
    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
    """
}

enum AuthenticodeError: LocalizedError, Equatable {
    /// Not a Windows program, or one Fable can't read the layout of.
    case notAProgram(String)
    /// A Windows program with no signature at all.
    case unsigned(String)
    /// A signature that is malformed, uses an algorithm Fable doesn't accept,
    /// or doesn't cover this exact file.
    case badSignature(String, reason: String)
    /// A valid signature from someone other than the expected publisher.
    case wrongPublisher(String, expected: String)

    var errorDescription: String? {
        switch self {
        case .notAProgram(let file):
            "\(file) isn't the Windows installer Fable expected, so Fable won't run it."
        case .unsigned(let file):
            "\(file) isn't signed, so Fable won't run it. The download may have been tampered with."
        case .badSignature(let file, _):
            "\(file) failed its signature check, so Fable won't run it. The download may be corrupted or tampered with — try again."
        case .wrongPublisher(let file, let expected):
            "\(file) isn't signed by \(expected), so Fable won't run it."
        }
    }
}

/// Checks the Authenticode signature of a Windows program on disk: that the
/// signature covers every byte of the file, that its signer chains to one of
/// the publisher's own roots, and that the signer is that publisher.
///
/// macOS can't do this for us — `CMSDecoder` rejects Authenticode's content
/// type — so the PKCS #7 structure is walked here and the cryptography is
/// handed to Security.framework (`SecKeyVerifySignature`, `SecTrust`).
///
/// Deliberate limits:
/// - SHA-256 only. Both Microsoft redistributables Fable downloads use it.
/// - Expired signing certificates are accepted: the chain is evaluated at the
///   signing certificate's start date, as Windows does for timestamped
///   signatures (Microsoft's signer certificates last about a year; the
///   installers live for many). Revocation is not checked.
/// - Only the primary signature is checked; a nested second signature is
///   ignored.
enum Authenticode {
    static func verify(_ file: URL, publisher: AuthenticodePublisher) throws {
        let name = file.lastPathComponent
        let data = try Data(contentsOf: file, options: .alwaysMapped)
        let layout = try PELayout(data, file: name)

        let signed = try SignedData(pkcs7: layout.pkcs7(in: data, file: name), file: name)
        let actual = layout.imageDigest(of: data)
        guard actual == signed.imageDigest else {
            throw AuthenticodeError.badSignature(name, reason: "file digest doesn't match the signed digest")
        }
        try signed.verifySignerAndChain(publisher: publisher, file: name)
    }

    // MARK: - PE layout

    /// Where the signature lives in a PE file, and which bytes it covers.
    struct PELayout: Equatable {
        let checksumOffset: Int
        let securityDirectoryOffset: Int
        let certificateTableOffset: Int
        let certificateTableSize: Int

        init(_ data: Data, file: String) throws {
            func u16(_ at: Int) -> Int { Int(data[data.startIndex + at]) | Int(data[data.startIndex + at + 1]) << 8 }
            func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }

            let size = data.count
            guard size >= 0x40, u16(0) == 0x5A4D else { throw AuthenticodeError.notAProgram(file) }
            let pe = u32(0x3C)
            guard pe <= size - 24 - 2,
                  data[data.startIndex + pe ..< data.startIndex + pe + 4] == Data([0x50, 0x45, 0, 0]) else {
                throw AuthenticodeError.notAProgram(file)
            }
            let optional = pe + 24
            let directories: Int
            let directoryCount: Int
            switch u16(optional) {
            case 0x10B: directories = optional + 96; directoryCount = optional + 92
            case 0x20B: directories = optional + 112; directoryCount = optional + 108
            default: throw AuthenticodeError.notAProgram(file)
            }
            // The security directory is entry 4 (8 bytes each).
            let security = directories + 4 * 8
            guard security + 8 <= size else { throw AuthenticodeError.notAProgram(file) }
            guard u32(directoryCount) >= 5 else { throw AuthenticodeError.unsigned(file) }

            let tableOffset = u32(security)
            let tableSize = u32(security + 4)
            guard tableOffset != 0, tableSize != 0 else { throw AuthenticodeError.unsigned(file) }
            // The table must sit after the headers and end the file: bytes
            // after it would be outside the signature yet still on disk.
            guard tableOffset >= security + 8, tableSize >= 8,
                  tableOffset <= size, tableSize == size - tableOffset else {
                throw AuthenticodeError.badSignature(file, reason: "certificate table isn't at the end of the file")
            }
            checksumOffset = optional + 64
            securityDirectoryOffset = security
            certificateTableOffset = tableOffset
            certificateTableSize = tableSize
        }

        /// The byte ranges the Authenticode digest covers: everything up to
        /// the certificate table except the header checksum and the security
        /// directory entry (which change when a file is signed).
        var signedRanges: [Range<Int>] {
            [0 ..< checksumOffset,
             checksumOffset + 4 ..< securityDirectoryOffset,
             securityDirectoryOffset + 8 ..< certificateTableOffset]
        }

        func imageDigest(of data: Data) -> Data {
            var hasher = SHA256()
            for range in signedRanges {
                var start = range.lowerBound
                while start < range.upperBound {
                    let end = min(start + (1 << 20), range.upperBound)
                    hasher.update(data: data[data.startIndex + start ..< data.startIndex + end])
                    start = end
                }
            }
            return Data(hasher.finalize())
        }

        /// The PKCS #7 blob in the first `WIN_CERTIFICATE` entry. Anything
        /// after it other than alignment padding is refused.
        func pkcs7(in data: Data, file: String) throws -> [UInt8] {
            let base = data.startIndex + certificateTableOffset
            func u32(_ at: Int) -> Int {
                (0..<4).reduce(0) { $0 | Int(data[base + at + $1]) << (8 * $1) }
            }
            let length = u32(0)
            let revision = Int(data[base + 4]) | Int(data[base + 5]) << 8
            let type = Int(data[base + 6]) | Int(data[base + 7]) << 8
            guard length > 8, length <= certificateTableSize, certificateTableSize - length < 8,
                  revision == 0x0200, type == 0x0002 else {
                throw AuthenticodeError.badSignature(file, reason: "unexpected certificate table entry")
            }
            return [UInt8](data[base + 8 ..< base + length])
        }
    }

    // MARK: - PKCS #7 SignedData

    struct SignedData {
        /// The PE digest the signer vouched for.
        let imageDigest: Data
        /// DER of the signer's authenticated attributes, re-tagged as a SET —
        /// the exact bytes the signature is over.
        let signedAttributes: [UInt8]
        let signature: [UInt8]
        let signer: Certificate
        /// Every certificate in the blob, signer first.
        let certificates: [Certificate]

        init(pkcs7 bytes: [UInt8], file: String) throws {
            func bad(_ reason: String) -> AuthenticodeError { .badSignature(file, reason: reason) }
            do {
                // WIN_CERTIFICATE's length counts the alignment padding, so
                // the blob may end in up to seven zero bytes — and nothing else.
                let outer = try DER(bytes).read(at: 0, limit: bytes.count)
                guard bytes.count - outer.end < 8, bytes[outer.end...].allSatisfy({ $0 == 0 })
                else { throw bad("data after the signature") }
                let der = DER(Array(bytes[..<outer.end]))
                let contentInfo = try der.children(of: der.root())
                guard contentInfo.count == 2, der.isOID(contentInfo[0], OID.signedData),
                      contentInfo[1].tag == 0xA0 else { throw bad("not PKCS #7 SignedData") }
                let signedData = try der.children(of: der.single(in: contentInfo[1]))
                // version, digestAlgorithms, encapContentInfo, [0] certs, [1] crls?, signerInfos
                guard signedData.count >= 4, let signerInfos = signedData.last, signerInfos.tag == 0x31
                else { throw bad("malformed SignedData") }

                let encap = try der.children(of: signedData[2])
                guard encap.count == 2, der.isOID(encap[0], OID.spcIndirectData), encap[1].tag == 0xA0
                else { throw bad("not an Authenticode signature") }
                let indirect = try der.single(in: encap[1])
                // SpcIndirectDataContent ::= SEQUENCE { data, DigestInfo }
                let indirectParts = try der.children(of: indirect)
                guard indirectParts.count == 2 else { throw bad("malformed SpcIndirectDataContent") }
                let digestInfo = try der.children(of: indirectParts[1])
                guard digestInfo.count == 2, digestInfo[1].tag == 0x04,
                      try der.isSHA256(digestInfo[0]) else { throw bad("file digest isn't SHA-256") }
                imageDigest = Data(der.value(digestInfo[1]))

                guard let certSet = signedData.first(where: { $0.tag == 0xA0 }) else { throw bad("no certificates") }
                let certs = try der.children(of: certSet).map { try Certificate(der.full($0)) }

                let signerList = try der.children(of: signerInfos)
                guard signerList.count == 1 else { throw bad("expected exactly one signer") }
                let info = try der.children(of: signerList[0])
                // version, issuerAndSerial, digestAlgorithm, [0] signedAttrs, sigAlg, signature, [1]?
                guard info.count >= 6, info[3].tag == 0xA0, info[5].tag == 0x04,
                      try der.isSHA256(info[2]) else { throw bad("malformed or non-SHA-256 SignerInfo") }
                let sigAlg = try der.children(of: info[4])
                guard let algOID = sigAlg.first,
                      der.isOID(algOID, OID.rsaEncryption) || der.isOID(algOID, OID.sha256WithRSA)
                else { throw bad("signature isn't RSA") }

                let issuerAndSerial = try der.children(of: info[1])
                guard issuerAndSerial.count == 2 else { throw bad("malformed signer identifier") }
                let issuer = der.full(issuerAndSerial[0])
                let serial = der.full(issuerAndSerial[1])
                guard let signer = certs.first(where: { $0.issuer == issuer && $0.serial == serial })
                else { throw bad("signer certificate missing") }

                // The authenticated attributes must say what was signed
                // (Authenticode content) and carry the digest of it.
                var contentTypeOK = false
                var messageDigest: [UInt8]?
                for attribute in try der.children(of: info[3]) {
                    let parts = try der.children(of: attribute)
                    guard parts.count == 2, parts[1].tag == 0x31 else { throw bad("malformed attribute") }
                    let values = try der.children(of: parts[1])
                    if der.isOID(parts[0], OID.contentType) {
                        guard values.count == 1, der.isOID(values[0], OID.spcIndirectData) else {
                            throw bad("signed content type isn't Authenticode")
                        }
                        contentTypeOK = true
                    } else if der.isOID(parts[0], OID.messageDigest) {
                        guard values.count == 1, values[0].tag == 0x04, messageDigest == nil else {
                            throw bad("malformed message digest")
                        }
                        messageDigest = der.value(values[0])
                    }
                }
                // The digest covers SpcIndirectDataContent's contents, without
                // its own tag and length (Authenticode's PKCS #7 v1.5 rule).
                let contentDigest = [UInt8](SHA256.hash(data: der.value(indirect)))
                guard contentTypeOK, let messageDigest, messageDigest == contentDigest else {
                    throw bad("signed attributes don't match the signed content")
                }

                var attrs = der.full(info[3])
                attrs[0] = 0x31 // [0] IMPLICIT → SET OF, as signed
                signedAttributes = attrs
                signature = der.value(info[5])
                self.signer = signer
                certificates = [signer] + certs.filter { $0.der != signer.der }
            } catch let error as AuthenticodeError {
                throw error
            } catch {
                throw bad("malformed signature")
            }
        }

        func verifySignerAndChain(publisher: AuthenticodePublisher, file: String) throws {
            func bad(_ reason: String) -> AuthenticodeError { .badSignature(file, reason: reason) }
            guard let leaf = SecCertificateCreateWithData(nil, Data(signer.der) as CFData),
                  let key = SecCertificateCopyKey(leaf) else { throw bad("unreadable signer certificate") }
            var error: Unmanaged<CFError>?
            guard SecKeyVerifySignature(
                key, .rsaSignatureMessagePKCS1v15SHA256,
                Data(signedAttributes) as CFData, Data(signature) as CFData, &error
            ) else {
                error?.release()
                throw bad("signature doesn't verify")
            }

            let chain = certificates.compactMap { SecCertificateCreateWithData(nil, Data($0.der) as CFData) }
            let anchors = publisher.anchors.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            guard chain.count == certificates.count, !anchors.isEmpty else { throw bad("unreadable certificate") }
            var trust: SecTrust?
            guard SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
                  let trust else { throw bad("couldn't evaluate the certificate chain") }
            SecTrustSetAnchorCertificates(trust, anchors as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
            SecTrustSetNetworkFetchAllowed(trust, false)
            SecTrustSetVerifyDate(trust, signer.notBefore.addingTimeInterval(60) as CFDate)
            guard SecTrustEvaluateWithError(trust, nil) else {
                throw AuthenticodeError.wrongPublisher(file, expected: publisher.name)
            }
            guard signer.organization == publisher.name, signer.commonName == publisher.name,
                  signer.allowsCodeSigning else {
                throw AuthenticodeError.wrongPublisher(file, expected: publisher.name)
            }
        }
    }

    // MARK: - X.509 (only the fields the check needs)

    struct Certificate: Equatable {
        let der: [UInt8]
        let serial: [UInt8]
        let issuer: [UInt8]
        let notBefore: Date
        let organization: String?
        let commonName: String?
        let allowsCodeSigning: Bool

        init(_ bytes: [UInt8]) throws {
            der = bytes
            let d = DER(bytes)
            let tbs = try d.children(of: d.children(of: d.root())[0])
            var i = 0
            if tbs.first?.tag == 0xA0 { i = 1 } // explicit version
            guard tbs.count >= i + 6 else { throw DER.Malformed() }
            serial = d.full(tbs[i])
            issuer = d.full(tbs[i + 2])
            notBefore = try d.time(d.children(of: tbs[i + 3])[0])
            var organization: String?
            var commonName: String?
            for rdn in try d.children(of: tbs[i + 4]) {
                for pair in try d.children(of: rdn) {
                    let parts = try d.children(of: pair)
                    guard parts.count == 2 else { continue }
                    let value = String(decoding: d.value(parts[1]), as: UTF8.self)
                    if d.isOID(parts[0], OID.organizationName) { organization = value }
                    if d.isOID(parts[0], OID.commonName) { commonName = value }
                }
            }
            self.organization = organization
            self.commonName = commonName
            var codeSigning = false
            if let extensions = tbs.dropFirst(i + 6).first(where: { $0.tag == 0xA3 }) {
                for ext in try d.children(of: d.single(in: extensions)) {
                    let parts = try d.children(of: ext)
                    guard let oid = parts.first, d.isOID(oid, OID.extendedKeyUsage),
                          let octets = parts.last, octets.tag == 0x04 else { continue }
                    let inner = DER(d.value(octets))
                    codeSigning = try inner.children(of: inner.root())
                        .contains { inner.isOID($0, OID.codeSigning) }
                }
            }
            allowsCodeSigning = codeSigning
        }
    }

    enum OID {
        static let signedData: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]
        static let spcIndirectData: [UInt8] = [0x2B, 0x06, 0x01, 0x04, 0x01, 0x82, 0x37, 0x02, 0x01, 0x04]
        static let sha256: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
        static let contentType: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x03]
        static let messageDigest: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04]
        static let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        static let sha256WithRSA: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
        static let organizationName: [UInt8] = [0x55, 0x04, 0x0A]
        static let commonName: [UInt8] = [0x55, 0x04, 0x03]
        static let extendedKeyUsage: [UInt8] = [0x55, 0x1D, 0x25]
        static let codeSigning: [UInt8] = [0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x03]
    }
}

/// A minimal DER reader: definite lengths and single-byte tags only, which is
/// all PKCS #7 and X.509 use. Every read is bounds-checked against its parent.
struct DER {
    struct Malformed: Error {}
    struct Node: Equatable {
        let tag: UInt8
        let start: Int
        let valueStart: Int
        let end: Int
    }

    let bytes: [UInt8]
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func root() throws -> Node {
        let node = try read(at: 0, limit: bytes.count)
        guard node.end == bytes.count else { throw Malformed() }
        return node
    }

    func read(at offset: Int, limit: Int) throws -> Node {
        guard offset + 2 <= limit else { throw Malformed() }
        let tag = bytes[offset]
        guard tag & 0x1F != 0x1F else { throw Malformed() }
        var length = Int(bytes[offset + 1])
        var header = 2
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard (1...4).contains(count), offset + 2 + count <= limit else { throw Malformed() }
            length = 0
            for k in 0..<count { length = length << 8 | Int(bytes[offset + 2 + k]) }
            header += count
        }
        let valueStart = offset + header
        guard length <= limit - valueStart else { throw Malformed() }
        return Node(tag: tag, start: offset, valueStart: valueStart, end: valueStart + length)
    }

    func children(of node: Node) throws -> [Node] {
        guard node.tag & 0x20 != 0 else { throw Malformed() } // constructed only
        var result: [Node] = []
        var offset = node.valueStart
        while offset < node.end {
            let child = try read(at: offset, limit: node.end)
            result.append(child)
            offset = child.end
        }
        return result
    }

    func single(in node: Node) throws -> Node {
        let kids = try children(of: node)
        guard kids.count == 1 else { throw Malformed() }
        return kids[0]
    }

    func value(_ node: Node) -> [UInt8] { Array(bytes[node.valueStart ..< node.end]) }
    func full(_ node: Node) -> [UInt8] { Array(bytes[node.start ..< node.end]) }

    func isOID(_ node: Node, _ oid: [UInt8]) -> Bool {
        node.tag == 0x06 && value(node) == oid
    }

    /// An AlgorithmIdentifier naming SHA-256 (parameters absent or NULL).
    func isSHA256(_ node: Node) throws -> Bool {
        let parts = try children(of: node)
        guard let first = parts.first, isOID(first, Authenticode.OID.sha256) else { return false }
        return parts.count == 1 || (parts.count == 2 && parts[1].tag == 0x05)
    }

    /// UTCTime or GeneralizedTime, `…Z` with seconds.
    func time(_ node: Node) throws -> Date {
        let text = String(decoding: value(node), as: UTF8.self)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        switch node.tag {
        case 0x17:
            formatter.dateFormat = "yyMMddHHmmss'Z'"
            // RFC 5280: two-digit years 50–99 are 19xx.
            formatter.twoDigitStartDate = Date(timeIntervalSince1970: -631_152_000) // 1950-01-01
        case 0x18: formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        default: throw Malformed()
        }
        guard let date = formatter.date(from: text) else { throw Malformed() }
        return date
    }
}
