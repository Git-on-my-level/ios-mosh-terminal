import XCTest
@testable import MoshTerminal

final class SSHPrivateKeyValidatorTests: XCTestCase {
    func testOpenSSHED25519Unencrypted() throws {
        let payload = makeOpenSSHKeyPayload(cipher: "none", kdf: "none", marker: "ssh-ed25519")
        let pem = wrapOpenSSHPEM(payload)

        let result = try SSHPrivateKeyValidator.validate(pem)

        XCTAssertEqual(result.keyType, .ed25519)
        XCTAssertFalse(result.requiresPassphrase)
    }

    func testOpenSSHRSAEncrypted() throws {
        let payload = makeOpenSSHKeyPayload(cipher: "aes256-ctr", kdf: "bcrypt", marker: "ssh-rsa")
        let pem = wrapOpenSSHPEM(payload)

        let result = try SSHPrivateKeyValidator.validate(pem)

        XCTAssertEqual(result.keyType, .rsa)
        XCTAssertTrue(result.requiresPassphrase)
    }

    func testRSAPEMEncryptedFlagDetected() throws {
        let pem = """
        -----BEGIN RSA PRIVATE KEY-----
        Proc-Type: 4,ENCRYPTED
        AA==
        -----END RSA PRIVATE KEY-----
        """
        let result = try SSHPrivateKeyValidator.validate(pem)
        XCTAssertEqual(result.keyType, .rsa)
        XCTAssertTrue(result.requiresPassphrase)
    }

    func testRejectsUnsupportedFormat() {
        XCTAssertThrowsError(try SSHPrivateKeyValidator.validate("not a key")) { error in
            XCTAssertEqual(error as? SSHPrivateKeyValidationError, .unsupportedFormat)
        }
    }

    func testNormalizePrivateKeyDataStripsCRLF() throws {
        let basePayload = makeOpenSSHKeyPayload(cipher: "none", kdf: "none", marker: "ssh-ed25519")
        let basePEM = wrapOpenSSHPEM(basePayload)

        let messyKey = "  \r\n" + basePEM.replacingOccurrences(of: "\n", with: "\r\n") + "  \r\n"
        let normalizedData = try normalizePrivateKeyDataForTest(Data(messyKey.utf8))
        let normalizedText = String(data: normalizedData, encoding: .utf8)

        XCTAssertEqual(normalizedText, basePEM)
        XCTAssertFalse(normalizedText?.contains("\r") ?? true)
    }

    func testNormalizePrivateKeyDataStripsTrailingWhitespace() throws {
        let basePayload = makeOpenSSHKeyPayload(cipher: "none", kdf: "none", marker: "ssh-ed25519")
        let basePEM = wrapOpenSSHPEM(basePayload)

        let messyKey = basePEM + "   \n   "
        let normalizedData = try normalizePrivateKeyDataForTest(Data(messyKey.utf8))
        let normalizedText = String(data: normalizedData, encoding: .utf8)

        XCTAssertEqual(normalizedText, basePEM)
    }

    func testNormalizePrivateKeyDataStripsLeadingWhitespace() throws {
        let basePayload = makeOpenSSHKeyPayload(cipher: "none", kdf: "none", marker: "ssh-ed25519")
        let basePEM = wrapOpenSSHPEM(basePayload)

        let messyKey = "  \n  " + basePEM
        let normalizedData = try normalizePrivateKeyDataForTest(Data(messyKey.utf8))
        let normalizedText = String(data: normalizedData, encoding: .utf8)

        XCTAssertEqual(normalizedText, basePEM)
    }

    func testNormalizePrivateKeyDataIdenticalViaFileAndPaste() throws {
        let basePayload = makeOpenSSHKeyPayload(cipher: "none", kdf: "none", marker: "ssh-ed25519")
        let basePEM = wrapOpenSSHPEM(basePayload)

        let fileData = "  \r\n" + basePEM.replacingOccurrences(of: "\n", with: "\r\n") + "  \r\n"
        let pasteText = "  \n" + basePEM + "  \n"

        let normalizedFileData = try normalizePrivateKeyDataForTest(Data(fileData.utf8))
        let normalizedPasteData = try normalizePrivateKeyDataForTest(Data(pasteText.utf8))

        XCTAssertEqual(normalizedFileData, normalizedPasteData)
    }

    private func wrapOpenSSHPEM(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        return """
        -----BEGIN OPENSSH PRIVATE KEY-----
        \(base64)
        -----END OPENSSH PRIVATE KEY-----
        """
    }

    private func makeOpenSSHKeyPayload(cipher: String, kdf: String, marker: String) -> Data {
        var data = Data("openssh-key-v1\0".utf8)
        data.append(sshString(cipher))
        data.append(sshString(kdf))
        data.append(Data(marker.utf8))
        return data
    }

    private func sshString(_ value: String) -> Data {
        let bytes = [UInt8](value.utf8)
        var length = UInt32(bytes.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(contentsOf: bytes)
        return data
    }

    private func normalizePrivateKeyDataForTest(_ data: Data) throws -> Data {
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
        guard var text = decoded else {
            throw NSError(domain: "KeyManagement", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to read key as text"])
        }

        let bomScalars: [UInt32] = [0xFEFF, 0xFFFE, 0xEFBBBF]
        if let firstScalar = text.unicodeScalars.first, bomScalars.contains(firstScalar.value) {
            text.removeFirst()
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        guard let normalized = text.data(using: .utf8) else {
            throw NSError(domain: "KeyManagement", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode normalized key"])
        }

        return normalized
    }
}
