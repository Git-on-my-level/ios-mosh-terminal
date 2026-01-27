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
}
