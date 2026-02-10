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

    func testGeneratedEd25519OpenSSHKeyValidatesAndPublicKeyExports() throws {
        let generated = try SSHKeyGenerator.generateEd25519OpenSSH(comment: "Test Key")

        let validation = try SSHPrivateKeyValidator.validate(generated.privateKeyPEM)
        XCTAssertEqual(validation.keyType, .ed25519)
        XCTAssertFalse(validation.requiresPassphrase)

        let exported = try SSHOpenSSHPublicKeyExporter.publicKeyLine(
            fromOpenSSHPrivateKeyPEM: generated.privateKeyPEM,
            comment: "Test Key"
        )
        XCTAssertEqual(exported, generated.publicKey)
        XCTAssertTrue(exported.hasPrefix("ssh-ed25519 "))
        XCTAssertTrue(exported.hasSuffix(" Test Key"))
    }

    func testRSAPEMPublicKeyExports() throws {
        let rsaPrivateKeyPEM = """
        -----BEGIN RSA PRIVATE KEY-----
        MIICXgIBAAKBgQDNYI6BYK8SbLrciRHg65MUypgCglhCMUuGWcv3fuefBSeQTwwk
        7SndEH25/b3F83qH2JZEroe9rDNlIKmLDZDmZP/xEdqu5HxSCStRhwOc44u6DpY6
        sMo8QgR2OtA8okkX4C3pv3d0MR32IClVX1L52FWIiiwqXXgjV+T2AFhVVQIDAQAB
        AoGBAItjvVSSCkC3Cxwi6798I5c46XLKhJxoWJoW2BhiSVHkbbXD8LofPQqM5sgV
        L3fqiH8qwNJcokRZW4iHYoq96lk9AVkDiQ0CXyMQULiriqDqneE/KLcYBLQ6Dtlw
        UBZLx09OQoER+ibXDJlfodRTGMCa/zzxV66afGT1V+yNRV0BAkEA8eJ7MV0l7u68
        rC+FKst1D7Ee3S0TGY3/JPDi1C8QkruJUQgpo7mcqx0lS47qMTsSTsiA6l55s8nX
        OyoG8Y9iywJBANlcsGpsfvK4duLDY8WMEQ1SnldLAaWf/WWfb07RBNsT2Nc9msmg
        yLDNtJToNXcieRquCwcwl1Ob4hxhOxdWhF8CQQDhV6yLVYskaFdvVioKr1cUUl89
        kGON2CLNyHiZUmtvN7V6v08Dj8UsCNAY70CwsqagrNyk+3UIEM8p+EJVws43AkAi
        LLCQCv7qqpYGkTHenWcQ8Sx0DRb1M3Jjx+14NuTMjRJKxSTRDrZ/FdiOkPPXB1SD
        HVoeh0VDn/6s95ySzseBAkEA2q4rpYe5CRutWMs8Kbd+W4V6jMqlTOfCW44YIgC8
        C/0eS12d7q7dFfWa6e9KzaQ6mNKzV0XaGRBtXuBwRZPhYA==
        -----END RSA PRIVATE KEY-----
        """
        let expectedPublicKeyLine = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDNYI6BYK8SbLrciRHg65MUypgCglhCMUuGWcv3fuefBSeQTwwk7SndEH25/b3F83qH2JZEroe9rDNlIKmLDZDmZP/xEdqu5HxSCStRhwOc44u6DpY6sMo8QgR2OtA8okkX4C3pv3d0MR32IClVX1L52FWIiiwqXXgjV+T2AFhVVQ== Test Key"

        let exported = try SSHPublicKeyExporter.publicKeyLine(fromPrivateKeyPEM: rsaPrivateKeyPEM, comment: "Test Key")
        XCTAssertEqual(exported, expectedPublicKeyLine)
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
