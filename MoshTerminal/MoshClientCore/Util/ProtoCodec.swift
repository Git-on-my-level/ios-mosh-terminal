import Foundation

enum ProtoCodecError: Error, Equatable {
    case truncated
    case malformedVarint
    case invalidWireType
    case unsupportedWireType(Int)
    case lengthOverflow
    case valueOverflow
}

struct ProtoReader {
    private let data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool {
        offset >= data.count
    }

    mutating func readKey() throws -> (fieldNumber: Int, wireType: Int) {
        let raw = try readVarint()
        let wireType = Int(raw & 0x7)
        let fieldNumber = Int(raw >> 3)
        guard fieldNumber > 0 else {
            throw ProtoCodecError.invalidWireType
        }
        return (fieldNumber, wireType)
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<10 {
            guard offset < data.count else {
                throw ProtoCodecError.truncated
            }
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
        }
        throw ProtoCodecError.malformedVarint
    }

    mutating func readLengthDelimited() throws -> Data {
        let length64 = try readVarint()
        guard length64 <= UInt64(Int.max) else {
            throw ProtoCodecError.lengthOverflow
        }
        let length = Int(length64)
        guard offset + length <= data.count else {
            throw ProtoCodecError.truncated
        }
        let slice = data.subdata(in: offset..<(offset + length))
        offset += length
        return slice
    }

    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case 0:
            _ = try readVarint()
        case 1:
            try skipFixed(bytes: 8)
        case 2:
            let length64 = try readVarint()
            guard length64 <= UInt64(Int.max) else {
                throw ProtoCodecError.lengthOverflow
            }
            let length = Int(length64)
            try skipFixed(bytes: length)
        case 5:
            try skipFixed(bytes: 4)
        case 3, 4:
            throw ProtoCodecError.unsupportedWireType(wireType)
        default:
            throw ProtoCodecError.invalidWireType
        }
    }

    private mutating func skipFixed(bytes: Int) throws {
        guard bytes >= 0 else {
            throw ProtoCodecError.lengthOverflow
        }
        guard offset + bytes <= data.count else {
            throw ProtoCodecError.truncated
        }
        offset += bytes
    }
}

struct ProtoWriter {
    private(set) var data = Data()

    mutating func writeKey(fieldNumber: Int, wireType: Int) {
        let key = UInt64(fieldNumber << 3) | UInt64(wireType & 0x7)
        writeVarint(key)
    }

    mutating func writeVarint(_ value: UInt64) {
        var working = value
        while true {
            if (working & ~0x7F) == 0 {
                data.append(UInt8(working))
                return
            }
            data.append(UInt8((working & 0x7F) | 0x80))
            working >>= 7
        }
    }

    mutating func writeLengthDelimited(_ value: Data) {
        writeVarint(UInt64(value.count))
        data.append(value)
    }
}

struct TransportInstruction: Equatable {
    var protocolVersion: UInt32
    var oldNum: UInt64
    var newNum: UInt64
    var ackNum: UInt64
    var throwawayNum: UInt64
    var diff: Data
    var chaff: Data

    init(protocolVersion: UInt32 = 0,
         oldNum: UInt64 = 0,
         newNum: UInt64 = 0,
         ackNum: UInt64 = 0,
         throwawayNum: UInt64 = 0,
         diff: Data = Data(),
         chaff: Data = Data()) {
        self.protocolVersion = protocolVersion
        self.oldNum = oldNum
        self.newNum = newNum
        self.ackNum = ackNum
        self.throwawayNum = throwawayNum
        self.diff = diff
        self.chaff = chaff
    }

    init(decode data: Data) throws {
        var reader = ProtoReader(data: data)
        self.init()

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch key.fieldNumber {
            case 1:
                guard key.wireType == 0 else {
                    try reader.skipField(wireType: key.wireType)
                    continue
                }
                let value = try reader.readVarint()
                guard value <= UInt64(UInt32.max) else {
                    throw ProtoCodecError.valueOverflow
                }
                protocolVersion = UInt32(value)
            case 2:
                if key.wireType == 0 {
                    oldNum = try reader.readVarint()
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 3:
                if key.wireType == 0 {
                    newNum = try reader.readVarint()
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 4:
                if key.wireType == 0 {
                    ackNum = try reader.readVarint()
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 5:
                if key.wireType == 0 {
                    throwawayNum = try reader.readVarint()
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 6:
                if key.wireType == 2 {
                    diff = try reader.readLengthDelimited()
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 7:
                if key.wireType == 2 {
                    chaff = try reader.readLengthDelimited()
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            default:
                try reader.skipField(wireType: key.wireType)
            }
        }
    }

    func encode() -> Data {
        var writer = ProtoWriter()
        if protocolVersion != 0 {
            writer.writeKey(fieldNumber: 1, wireType: 0)
            writer.writeVarint(UInt64(protocolVersion))
        }
        if oldNum != 0 {
            writer.writeKey(fieldNumber: 2, wireType: 0)
            writer.writeVarint(oldNum)
        }
        if newNum != 0 {
            writer.writeKey(fieldNumber: 3, wireType: 0)
            writer.writeVarint(newNum)
        }
        if ackNum != 0 {
            writer.writeKey(fieldNumber: 4, wireType: 0)
            writer.writeVarint(ackNum)
        }
        if throwawayNum != 0 {
            writer.writeKey(fieldNumber: 5, wireType: 0)
            writer.writeVarint(throwawayNum)
        }
        if !diff.isEmpty {
            writer.writeKey(fieldNumber: 6, wireType: 2)
            writer.writeLengthDelimited(diff)
        }
        if !chaff.isEmpty {
            writer.writeKey(fieldNumber: 7, wireType: 2)
            writer.writeLengthDelimited(chaff)
        }
        return writer.data
    }
}
