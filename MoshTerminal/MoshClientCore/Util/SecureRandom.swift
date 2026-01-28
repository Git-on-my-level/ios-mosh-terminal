import Foundation
import Security

enum SecureRandom {
    static func bytes(count: Int) -> [UInt8] {
        precondition(count >= 0)
        if count == 0 {
            return []
        }
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            fatalError("SecureRandom failed with status: \(status)")
        }
        return bytes
    }
}
