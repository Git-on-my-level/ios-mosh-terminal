import Foundation
import Security

public enum SecureRandom {
    public enum SecureRandomError: Error {
        case secRandomFailed(OSStatus)
    }

    public static func bytes(count: Int) throws -> [UInt8] {
        precondition(count >= 0)
        if count == 0 {
            return []
        }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw SecureRandomError.secRandomFailed(status)
        }
        return bytes
    }

    public static func nonThrowingBytes(count: Int) -> [UInt8] {
        do {
            return try bytes(count: count)
        } catch {
            return []
        }
    }
}
