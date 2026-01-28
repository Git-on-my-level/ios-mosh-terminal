import Foundation

enum FragmentError: Error, Equatable {
    case truncated
    case invalidNumber
}

struct Fragment: Equatable {
    let id: UInt64
    let number: UInt16
    let isFinal: Bool
    let body: Data

    init(id: UInt64, number: UInt16, isFinal: Bool, body: Data) {
        precondition(number < 0x8000, "Fragment number must fit in 15 bits")
        self.id = id
        self.number = number
        self.isFinal = isFinal
        self.body = body
    }

    init(decode data: Data) throws {
        guard data.count >= 10 else {
            throw FragmentError.truncated
        }

        var id: UInt64 = 0
        for index in 0..<8 {
            id = (id << 8) | UInt64(data[index])
        }

        let combined = (UInt16(data[8]) << 8) | UInt16(data[9])
        let isFinal = (combined & 0x8000) != 0
        let number = combined & 0x7FFF
        guard number < 0x8000 else {
            throw FragmentError.invalidNumber
        }

        let body = data.subdata(in: 10..<data.count)
        self.init(id: id, number: number, isFinal: isFinal, body: body)
    }

    func encode() -> Data {
        var data = Data()
        data.reserveCapacity(10 + body.count)

        var idBE = id.bigEndian
        withUnsafeBytes(of: &idBE) { bytes in
            data.append(contentsOf: bytes)
        }

        let combined = number | (isFinal ? 0x8000 : 0)
        var combinedBE = combined.bigEndian
        withUnsafeBytes(of: &combinedBE) { bytes in
            data.append(contentsOf: bytes)
        }

        data.append(body)
        return data
    }
}

struct Fragmenter {
    static func makeFragments(instructionBytes: Data, mtu: Int, id: UInt64) -> [Fragment] {
        guard mtu > 0 else {
            return []
        }

        if instructionBytes.count <= mtu {
            return [Fragment(id: id, number: 0, isFinal: true, body: instructionBytes)]
        }

        var fragments: [Fragment] = []
        var offset = 0
        var number: UInt16 = 0

        while offset < instructionBytes.count {
            let remaining = instructionBytes.count - offset
            let length = min(remaining, mtu)
            let end = offset + length
            let body = instructionBytes.subdata(in: offset..<end)
            let isFinal = end == instructionBytes.count
            fragments.append(Fragment(id: id, number: number, isFinal: isFinal, body: body))
            offset = end
            number += 1
        }

        return fragments
    }
}

enum FragmentAssemblyError: Error, Equatable {
    case duplicateMismatch(number: UInt16)
    case incomplete
}

final class FragmentAssembly {
    private var currentId: UInt64?
    private var fragments: [UInt16: Data] = [:]
    private var finalNumber: UInt16?
    private var pendingError: FragmentAssemblyError?

    func add(_ fragment: Fragment) -> Bool {
        if currentId != fragment.id {
            reset()
            currentId = fragment.id
        }

        if let existing = fragments[fragment.number] {
            if existing != fragment.body {
                pendingError = .duplicateMismatch(number: fragment.number)
            }
            return isComplete
        }

        fragments[fragment.number] = fragment.body
        if fragment.isFinal {
            finalNumber = fragment.number
        }

        return isComplete
    }

    func assembledBytes() throws -> Data {
        if let error = pendingError {
            reset()
            throw error
        }

        guard isComplete, let finalNumber else {
            throw FragmentAssemblyError.incomplete
        }

        var output = Data()
        for number in 0...finalNumber {
            guard let body = fragments[number] else {
                reset()
                throw FragmentAssemblyError.incomplete
            }
            output.append(body)
        }

        reset()
        return output
    }

    private var isComplete: Bool {
        guard pendingError == nil, let finalNumber else {
            return false
        }

        for number in 0...finalNumber {
            if fragments[number] == nil {
                return false
            }
        }
        return true
    }

    private func reset() {
        currentId = nil
        fragments.removeAll(keepingCapacity: true)
        finalNumber = nil
        pendingError = nil
    }
}
