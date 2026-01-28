import Foundation

enum SessionKeyError: Error, Equatable {
    case invalidLength
    case invalidBase64
    case invalidDecodedLength
}

enum SessionKey {
    static func decode(_ printable: String) throws -> [UInt8] {
        let normalized: String
        switch printable.count {
        case 22:
            normalized = printable + "=="
        case 24:
            guard printable.hasSuffix("==") else {
                throw SessionKeyError.invalidLength
            }
            normalized = printable
        default:
            throw SessionKeyError.invalidLength
        }

        guard let data = Data(base64Encoded: normalized) else {
            throw SessionKeyError.invalidBase64
        }
        guard data.count == 16 else {
            throw SessionKeyError.invalidDecodedLength
        }
        return Array(data)
    }
}
