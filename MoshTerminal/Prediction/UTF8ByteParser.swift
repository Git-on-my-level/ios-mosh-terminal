import Foundation

enum ParsedAction {
    case print(Character, width: Int)
    case backspace
    case carriageReturn
    case arrowLeft
    case arrowRight
    case unknown
}

final class UTF8ByteParser {
    private enum State {
        case normal
        case utf8Continuing(bytesNeeded: Int, accumulated: [UInt8])
        case esc
        case csi
        case ss3
    }

    private var state: State = .normal

    func feed(_ data: Data) -> [ParsedAction] {
        var actions: [ParsedAction] = []

        for byte in data {
            switch state {
            case .normal:
                handleNormal(byte: byte, actions: &actions)

            case .utf8Continuing(let bytesNeeded, let accumulated):
                handleUTF8Continuing(byte: byte, bytesNeeded: bytesNeeded, accumulated: accumulated, actions: &actions)

            case .esc:
                handleESC(byte: byte, actions: &actions)

            case .csi:
                handleCSI(byte: byte, actions: &actions)

            case .ss3:
                handleSS3(byte: byte, actions: &actions)
            }
        }

        return actions
    }

    private func handleNormal(byte: UInt8, actions: inout [ParsedAction]) {
        switch byte {
        case 0x1B:
            state = .esc

        case 0x7F:
            actions.append(.backspace)

        case 0x0D:
            actions.append(.carriageReturn)

        case 0x00...0x1F, 0x80...0xBF:
            actions.append(.unknown)

        case 0x20...0x7E:
            let char = Character(UnicodeScalar(byte))
            actions.append(.print(char, width: 1))

        case 0xC2...0xDF:
            state = .utf8Continuing(bytesNeeded: 1, accumulated: [byte])

        case 0xE0...0xEF:
            state = .utf8Continuing(bytesNeeded: 2, accumulated: [byte])

        case 0xF0...0xF4:
            state = .utf8Continuing(bytesNeeded: 3, accumulated: [byte])

        default:
            actions.append(.unknown)
        }
    }

    private func handleUTF8Continuing(byte: UInt8, bytesNeeded: Int, accumulated: [UInt8], actions: inout [ParsedAction]) {
        guard (byte & 0xC0) == 0x80 else {
            state = .normal
            actions.append(.unknown)
            return
        }

        var newAccumulated = accumulated
        newAccumulated.append(byte)

        if newAccumulated.count == bytesNeeded + 1 {
            state = .normal

            if let char = decodeUTF8(bytes: newAccumulated) {
                let width = characterWidth(char)
                if width == 1 {
                    actions.append(.print(char, width: width))
                } else {
                    actions.append(.unknown)
                }
            } else {
                actions.append(.unknown)
            }
        } else {
            state = .utf8Continuing(bytesNeeded: bytesNeeded, accumulated: newAccumulated)
        }
    }

    private func decodeUTF8(bytes: [UInt8]) -> Character? {
        guard bytes.count >= 1, bytes.count <= 4 else { return nil }

        var codePoint: UInt32 = 0
        var shift: UInt8 = 0

        switch bytes.count {
        case 1:
            guard (bytes[0] & 0x80) == 0 else { return nil }
            codePoint = UInt32(bytes[0])

        case 2:
            guard (bytes[0] & 0xE0) == 0xC0,
                  (bytes[1] & 0xC0) == 0x80 else { return nil }
            codePoint = (UInt32(bytes[0] & 0x1F) << 6) | UInt32(bytes[1] & 0x3F)

        case 3:
            guard (bytes[0] & 0xF0) == 0xE0,
                  (bytes[1] & 0xC0) == 0x80,
                  (bytes[2] & 0xC0) == 0x80 else { return nil }
            codePoint = (UInt32(bytes[0] & 0x0F) << 12) | (UInt32(bytes[1] & 0x3F) << 6) | UInt32(bytes[2] & 0x3F)

        case 4:
            guard (bytes[0] & 0xF8) == 0xF0,
                  (bytes[1] & 0xC0) == 0x80,
                  (bytes[2] & 0xC0) == 0x80,
                  (bytes[3] & 0xC0) == 0x80 else { return nil }
            codePoint = (UInt32(bytes[0] & 0x07) << 18) | (UInt32(bytes[1] & 0x3F) << 12) | (UInt32(bytes[2] & 0x3F) << 6) | UInt32(bytes[3] & 0x3F)

        default:
            return nil
        }

        guard codePoint <= 0x10FFFF else { return nil }
        return Character(UnicodeScalar(codePoint)!)
    }

    private func handleESC(byte: UInt8, actions: inout [ParsedAction]) {
        switch byte {
        case 0x5B:
            state = .csi

        case 0x4F:
            state = .ss3

        default:
            state = .normal
            actions.append(.unknown)
        }
    }

    private func handleCSI(byte: UInt8, actions: inout [ParsedAction]) {
        switch byte {
        case 0x43:
            state = .normal
            actions.append(.arrowRight)

        case 0x44:
            state = .normal
            actions.append(.arrowLeft)

        case 0x30...0x3F, 0x3B:
            state = .csi

        case 0x20...0x2F:
            state = .csi

        default:
            state = .normal
            actions.append(.unknown)
        }
    }

    private func handleSS3(byte: UInt8, actions: inout [ParsedAction]) {
        switch byte {
        case 0x43:
            state = .normal
            actions.append(.arrowRight)

        case 0x44:
            state = .normal
            actions.append(.arrowLeft)

        default:
            state = .normal
            actions.append(.unknown)
        }
    }

    private func characterWidth(_ char: Character) -> Int {
        guard let scalar = char.unicodeScalars.first else { return 0 }

        if scalar.value < 0x80 {
            return 1
        }

        if scalar.isASCII {
            return 1
        }

        return 2
    }

    func reset() {
        state = .normal
    }
}
