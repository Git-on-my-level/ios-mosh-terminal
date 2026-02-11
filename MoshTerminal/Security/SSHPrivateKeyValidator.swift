import CryptoKit
import Foundation

enum SSHPrivateKeyValidationError: Error, LocalizedError, Equatable {
    case empty
    case unsupportedFormat
    case invalidPEM
    case invalidBase64
    case invalidOpenSSH
    case unsupportedKeyType

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Key data is empty."
        case .unsupportedFormat:
            return "Unsupported private key format."
        case .invalidPEM:
            return "Private key PEM block is invalid."
        case .invalidBase64:
            return "Private key is not valid base64."
        case .invalidOpenSSH:
            return "OpenSSH private key data is invalid."
        case .unsupportedKeyType:
            return "Only RSA and ED25519 keys are supported."
        }
    }
}

struct SSHPrivateKeyValidationResult: Equatable {
    let keyType: SSHKeyType
    let requiresPassphrase: Bool
}

struct SSHPrivateKeyValidator {
    static func validate(_ text: String) throws -> SSHPrivateKeyValidationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SSHPrivateKeyValidationError.empty
        }

        if trimmed.contains("-----BEGIN OPENSSH PRIVATE KEY-----") {
            return try validateOpenSSH(trimmed)
        }

        if trimmed.contains("-----BEGIN RSA PRIVATE KEY-----") {
            return try validateRSAPEM(trimmed)
        }

        throw SSHPrivateKeyValidationError.unsupportedFormat
    }

    private static func validateOpenSSH(_ text: String) throws -> SSHPrivateKeyValidationResult {
        let base64 = try extractPEMBlock(text, begin: "-----BEGIN OPENSSH PRIVATE KEY-----", end: "-----END OPENSSH PRIVATE KEY-----")
        guard let data = Data(base64Encoded: base64) else {
            throw SSHPrivateKeyValidationError.invalidBase64
        }
        guard data.starts(with: openSSHPrefixData) else {
            throw SSHPrivateKeyValidationError.invalidOpenSSH
        }
        var reader = SSHKeyDataReader(data: data)
        guard reader.consume(bytes: openSSHPrefixData.count) else {
            throw SSHPrivateKeyValidationError.invalidOpenSSH
        }
        guard let cipherName = reader.readSSHString() else {
            throw SSHPrivateKeyValidationError.invalidOpenSSH
        }
        guard let kdfName = reader.readSSHString() else {
            throw SSHPrivateKeyValidationError.invalidOpenSSH
        }
        let requiresPassphrase = cipherName != "none" || kdfName != "none"

        let keyType = detectKeyType(in: data)
        guard keyType != .unknown else {
            throw SSHPrivateKeyValidationError.unsupportedKeyType
        }

        return SSHPrivateKeyValidationResult(keyType: keyType, requiresPassphrase: requiresPassphrase)
    }

    private static func validateRSAPEM(_ text: String) throws -> SSHPrivateKeyValidationResult {
        _ = try extractPEMBlock(text, begin: "-----BEGIN RSA PRIVATE KEY-----", end: "-----END RSA PRIVATE KEY-----")
        let requiresPassphrase = text.contains("ENCRYPTED")
        return SSHPrivateKeyValidationResult(keyType: .rsa, requiresPassphrase: requiresPassphrase)
    }

    private static func extractPEMBlock(_ text: String, begin: String, end: String) throws -> String {
        guard let beginRange = text.range(of: begin),
              let endRange = text.range(of: end) else {
            throw SSHPrivateKeyValidationError.invalidPEM
        }
        let bodyStart = beginRange.upperBound
        let bodyEnd = endRange.lowerBound
        guard bodyStart < bodyEnd else {
            throw SSHPrivateKeyValidationError.invalidPEM
        }
        let body = text[bodyStart..<bodyEnd]
        let stripped = body
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else {
            throw SSHPrivateKeyValidationError.invalidPEM
        }
        return stripped
    }

    private static func detectKeyType(in data: Data) -> SSHKeyType {
        if data.range(of: Data("ssh-ed25519".utf8)) != nil {
            return .ed25519
        }
        if data.range(of: Data("ssh-rsa".utf8)) != nil {
            return .rsa
        }
        return .unknown
    }

    private static let openSSHPrefixData = Data("openssh-key-v1\0".utf8)
}

private struct SSHKeyDataReader {
    private let data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func consume(bytes count: Int) -> Bool {
        guard offset + count <= data.count else { return false }
        offset += count
        return true
    }

    mutating func readSSHString() -> String? {
        guard let length = readUInt32() else { return nil }
        guard let bytes = readBytes(count: Int(length)) else { return nil }
        return String(data: bytes, encoding: .utf8)
    }

    private mutating func readUInt32() -> UInt32? {
        guard let bytes = readBytes(count: 4) else { return nil }
        let b0 = UInt32(bytes[0])
        let b1 = UInt32(bytes[1])
        let b2 = UInt32(bytes[2])
        let b3 = UInt32(bytes[3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    private mutating func readBytes(count: Int) -> Data? {
        guard offset + count <= data.count else { return nil }
        let slice = data[offset..<(offset + count)]
        offset += count
        return Data(slice)
    }
}

// MARK: - Key Generation / Public Key Export

enum SSHKeyExportError: Error, LocalizedError, Equatable {
    case unsupportedFormat
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Public key export is only supported for OpenSSH private keys."
        case .invalidKey:
            return "Unable to extract public key from private key."
        }
    }
}

struct SSHKeyGenerator {
    struct GeneratedKeyPair: Equatable {
        let privateKeyPEM: String
        let publicKey: String
        let keyType: SSHKeyType
        let requiresPassphrase: Bool
    }

    /// Generates an unencrypted OpenSSH ED25519 private key and the corresponding OpenSSH public key line.
    /// Notes:
    /// - We intentionally don't support passphrases yet (OpenSSH bcrypt KDF + cipher).
    /// - The private key is suitable for libssh2 `*_frommemory` auth.
    static func generateEd25519OpenSSH(comment: String) throws -> GeneratedKeyPair {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyRaw = Data(privateKey.publicKey.rawRepresentation) // 32 bytes
        let seed = Data(privateKey.rawRepresentation) // 32 bytes
        var privateKey64 = Data()
        privateKey64.append(seed)
        privateKey64.append(publicKeyRaw)

        let publicKeyBlob = SSHWireEncoding.sshString("ssh-ed25519") + SSHWireEncoding.sshData(publicKeyRaw)
        let publicKeyLine = "ssh-ed25519 \(publicKeyBlob.base64EncodedString()) \(comment)"

        let check = UInt32.random(in: UInt32.min...UInt32.max)
        var privateBlock = Data()
        privateBlock.append(SSHWireEncoding.uint32(check))
        privateBlock.append(SSHWireEncoding.uint32(check))
        privateBlock.append(SSHWireEncoding.sshString("ssh-ed25519"))
        privateBlock.append(SSHWireEncoding.sshData(publicKeyRaw))
        privateBlock.append(SSHWireEncoding.sshData(privateKey64))
        privateBlock.append(SSHWireEncoding.sshString(comment))
        privateBlock.append(SSHWireEncoding.padding(blockSize: 8, currentLength: privateBlock.count))

        var payload = Data("openssh-key-v1\0".utf8)
        payload.append(SSHWireEncoding.sshString("none")) // ciphername
        payload.append(SSHWireEncoding.sshString("none")) // kdfname
        payload.append(SSHWireEncoding.sshData(Data())) // kdfoptions
        payload.append(SSHWireEncoding.uint32(1)) // nkeys
        payload.append(SSHWireEncoding.sshData(publicKeyBlob))
        payload.append(SSHWireEncoding.sshData(privateBlock))

        let pem = SSHWireEncoding.wrapPEM(
            type: "OPENSSH PRIVATE KEY",
            base64: payload.base64EncodedString()
        )

        return GeneratedKeyPair(
            privateKeyPEM: pem,
            publicKey: publicKeyLine,
            keyType: .ed25519,
            requiresPassphrase: false
        )
    }
}

struct SSHOpenSSHPublicKeyExporter {
    /// Extracts an OpenSSH public key line (`ssh-ed25519 AAAA... comment`) from an OpenSSH private key PEM.
    static func publicKeyLine(fromOpenSSHPrivateKeyPEM pem: String, comment: String) throws -> String {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("-----BEGIN OPENSSH PRIVATE KEY-----") else {
            throw SSHKeyExportError.unsupportedFormat
        }

        let base64 = try extractPEMBlock(
            trimmed,
            begin: "-----BEGIN OPENSSH PRIVATE KEY-----",
            end: "-----END OPENSSH PRIVATE KEY-----"
        )
        guard let data = Data(base64Encoded: base64) else {
            throw SSHKeyExportError.invalidKey
        }
        guard data.starts(with: Data("openssh-key-v1\0".utf8)) else {
            throw SSHKeyExportError.invalidKey
        }

        var reader = SSHKeyDataReader(data: data)
        guard reader.consume(bytes: Data("openssh-key-v1\0".utf8).count) else {
            throw SSHKeyExportError.invalidKey
        }
        guard reader.readSSHString() != nil else { throw SSHKeyExportError.invalidKey } // ciphername
        guard reader.readSSHString() != nil else { throw SSHKeyExportError.invalidKey } // kdfname
        guard reader.readBytesSSHString() != nil else { throw SSHKeyExportError.invalidKey } // kdfoptions
        guard let nkeys = reader.readUInt32Public() else { throw SSHKeyExportError.invalidKey }
        guard nkeys >= 1 else { throw SSHKeyExportError.invalidKey }
        guard let publicKeyBlob = reader.readBytesSSHString() else { throw SSHKeyExportError.invalidKey }

        // publicKeyBlob begins with `string keytype`.
        var blobReader = SSHKeyDataReader(data: publicKeyBlob)
        guard let keyType = blobReader.readSSHString(), !keyType.isEmpty else {
            throw SSHKeyExportError.invalidKey
        }
        let base64Blob = publicKeyBlob.base64EncodedString()
        return "\(keyType) \(base64Blob) \(comment)"
    }
}

struct SSHPKCS1RSAPublicKeyExporter {
    /// Extracts an OpenSSH public key line (`ssh-rsa AAAA... comment`) from a PKCS#1 RSA private key PEM.
    static func publicKeyLine(fromRSAPrivateKeyPEM pem: String, comment: String) throws -> String {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("-----BEGIN RSA PRIVATE KEY-----") else {
            throw SSHKeyExportError.unsupportedFormat
        }

        let base64 = try extractPEMBlock(
            trimmed,
            begin: "-----BEGIN RSA PRIVATE KEY-----",
            end: "-----END RSA PRIVATE KEY-----"
        )
        guard let der = Data(base64Encoded: base64) else {
            throw SSHKeyExportError.invalidKey
        }

        // PKCS#1 RSAPrivateKey ::= SEQUENCE { version, modulus (n), publicExponent (e), ... }
        var reader = ASN1Reader(data: der)
        guard let seqLen = reader.readTagAndLength(expectedTag: 0x30) else {
            throw SSHKeyExportError.invalidKey
        }
        guard reader.remainingBytes >= seqLen else {
            throw SSHKeyExportError.invalidKey
        }
        guard reader.readIntegerMagnitude() != nil else { // version
            throw SSHKeyExportError.invalidKey
        }
        guard let modulus = reader.readIntegerMagnitude() else {
            throw SSHKeyExportError.invalidKey
        }
        guard let exponent = reader.readIntegerMagnitude() else {
            throw SSHKeyExportError.invalidKey
        }

        let publicKeyBlob =
            SSHWireEncoding.sshString("ssh-rsa")
            + SSHWireEncoding.sshData(SSHWireEncoding.mpint(exponent))
            + SSHWireEncoding.sshData(SSHWireEncoding.mpint(modulus))
        let publicKeyLine = "ssh-rsa \(publicKeyBlob.base64EncodedString()) \(comment)"
        return publicKeyLine
    }
}

struct SSHPublicKeyExporter {
    /// Extracts an OpenSSH public key line (`ssh-ed25519 ...` or `ssh-rsa ...`) from a supported private key PEM.
    static func publicKeyLine(fromPrivateKeyPEM pem: String, comment: String) throws -> String {
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("-----BEGIN OPENSSH PRIVATE KEY-----") {
            return try SSHOpenSSHPublicKeyExporter.publicKeyLine(fromOpenSSHPrivateKeyPEM: trimmed, comment: comment)
        }
        if trimmed.contains("-----BEGIN RSA PRIVATE KEY-----") {
            return try SSHPKCS1RSAPublicKeyExporter.publicKeyLine(fromRSAPrivateKeyPEM: trimmed, comment: comment)
        }
        throw SSHKeyExportError.unsupportedFormat
    }
}

private func extractPEMBlock(_ text: String, begin: String, end: String) throws -> String {
    guard let beginRange = text.range(of: begin),
          let endRange = text.range(of: end) else {
        throw SSHKeyExportError.invalidKey
    }
    let bodyStart = beginRange.upperBound
    let bodyEnd = endRange.lowerBound
    guard bodyStart < bodyEnd else {
        throw SSHKeyExportError.invalidKey
    }
    let body = text[bodyStart..<bodyEnd]
    let stripped = body
        .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !stripped.isEmpty else {
        throw SSHKeyExportError.invalidKey
    }
    return stripped
}

private enum SSHWireEncoding {
    static func uint32(_ value: UInt32) -> Data {
        var v = value.bigEndian
        return Data(bytes: &v, count: 4)
    }

    static func sshString(_ value: String) -> Data {
        let bytes = [UInt8](value.utf8)
        var data = Data()
        data.append(uint32(UInt32(bytes.count)))
        data.append(contentsOf: bytes)
        return data
    }

    static func sshData(_ value: Data) -> Data {
        var data = Data()
        data.append(uint32(UInt32(value.count)))
        data.append(value)
        return data
    }

    /// SSH mpint encoding expects a two's-complement big-endian integer body (without the 4-byte length).
    /// We accept unsigned magnitude bytes and prefix 0x00 if needed to keep the value positive.
    static func mpint(_ magnitude: Data) -> Data {
        var bytes = magnitude
        while bytes.count > 1, bytes.first == 0 {
            bytes.removeFirst()
        }
        if let first = bytes.first, (first & 0x80) != 0 {
            // `Data` slices can have a non-zero `startIndex`, so insert at `startIndex` (not 0).
            bytes.insert(0, at: bytes.startIndex)
        }
        return bytes
    }

    static func padding(blockSize: Int, currentLength: Int) -> Data {
        let remainder = currentLength % blockSize
        let padLen = remainder == 0 ? 0 : (blockSize - remainder)
        var pad = Data()
        if padLen > 0 {
            for i in 1...padLen {
                pad.append(UInt8(i & 0xff))
            }
        }
        return pad
    }

    static func wrapPEM(type: String, base64: String) -> String {
        // OpenSSH commonly wraps at 70 chars, but readers typically accept any wrapping.
        let wrapped = wrap(base64, width: 70)
        return """
        -----BEGIN \(type)-----
        \(wrapped)
        -----END \(type)-----
        """
    }

    private static func wrap(_ text: String, width: Int) -> String {
        guard width > 0 else { return text }
        var lines: [String] = []
        lines.reserveCapacity((text.count / width) + 1)
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: width, limitedBy: text.endIndex) ?? text.endIndex
            lines.append(String(text[start..<end]))
            start = end
        }
        return lines.joined(separator: "\n")
    }
}

private struct ASN1Reader {
    private let data: Data
    private(set) var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var remainingBytes: Int {
        data.count - offset
    }

    mutating func readTagAndLength(expectedTag: UInt8) -> Int? {
        guard let tag = readByte(), tag == expectedTag else { return nil }
        return readLength()
    }

    mutating func readIntegerMagnitude() -> Data? {
        guard let length = readTagAndLength(expectedTag: 0x02) else { return nil }
        guard let bytes = readBytes(count: length) else { return nil }
        // DER INTEGER is signed; strip a single leading 0x00 used to force positive values.
        var magnitude = bytes
        while magnitude.count > 1, magnitude.first == 0 {
            magnitude.removeFirst()
        }
        return magnitude
    }

    private mutating func readByte() -> UInt8? {
        guard offset < data.count else { return nil }
        let b = data[offset]
        offset += 1
        return b
    }

    private mutating func readBytes(count: Int) -> Data? {
        guard count >= 0, offset + count <= data.count else { return nil }
        let slice = data[offset..<(offset + count)]
        offset += count
        return Data(slice)
    }

    private mutating func readLength() -> Int? {
        guard let first = readByte() else { return nil }
        if (first & 0x80) == 0 {
            return Int(first)
        }
        let byteCount = Int(first & 0x7f)
        guard byteCount > 0, byteCount <= 4 else { return nil }
        guard let bytes = readBytes(count: byteCount) else { return nil }
        var length = 0
        for b in bytes {
            length = (length << 8) | Int(b)
        }
        return length
    }
}

private extension SSHKeyDataReader {
    mutating func readBytesSSHString() -> Data? {
        guard let length = readUInt32Public() else { return nil }
        return readBytesPublic(count: Int(length))
    }

    // Expose reader helpers only to this file for parsing OpenSSH structures.
    mutating func readUInt32Public() -> UInt32? {
        readUInt32()
    }

    mutating func readBytesPublic(count: Int) -> Data? {
        readBytes(count: count)
    }
}
