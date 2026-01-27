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
        return bytes.withUnsafeBytes { buffer in
            buffer.load(as: UInt32.self).bigEndian
        }
    }

    private mutating func readBytes(count: Int) -> Data? {
        guard offset + count <= data.count else { return nil }
        let slice = data[offset..<(offset + count)]
        offset += count
        return Data(slice)
    }
}
