import Foundation

public enum UserEvent: Equatable {
    case keystroke(Data)
    case resize(cols: Int, rows: Int)
}

enum HostEvent: Equatable {
    case hostBytes(Data)
    case resize(cols: Int, rows: Int)
    case echoAck(UInt64)
}

struct UserMessageCodec {
    static func encode(events: [UserEvent]) -> Data {
        var merged: [UserEvent] = []
        var pendingKeystroke: Data?

        for event in events {
            switch event {
            case .keystroke(let data):
                if pendingKeystroke == nil {
                    pendingKeystroke = data
                } else {
                    pendingKeystroke?.append(data)
                }
            case .resize:
                if let pending = pendingKeystroke {
                    merged.append(.keystroke(pending))
                    pendingKeystroke = nil
                }
                merged.append(event)
            }
        }

        if let pending = pendingKeystroke {
            merged.append(.keystroke(pending))
        }

        var writer = ProtoWriter()
        for event in merged {
            let instruction = encodeInstruction(for: event)
            writer.writeKey(fieldNumber: 1, wireType: 2)
            writer.writeLengthDelimited(instruction)
        }
        return writer.data
    }

    static func decode(data: Data) throws -> [UserEvent] {
        var reader = ProtoReader(data: data)
        var events: [UserEvent] = []

        while !reader.isAtEnd {
            let key = try reader.readKey()
            if key.fieldNumber == 1, key.wireType == 2 {
                let instruction = try reader.readLengthDelimited()
                let decoded = try decodeInstruction(from: instruction)
                events.append(contentsOf: decoded)
            } else {
                try reader.skipField(wireType: key.wireType)
            }
        }

        return events
    }

    private static func encodeInstruction(for event: UserEvent) -> Data {
        var instructionWriter = ProtoWriter()
        switch event {
        case .keystroke(let data):
            var keystrokeWriter = ProtoWriter()
            keystrokeWriter.writeKey(fieldNumber: 4, wireType: 2)
            keystrokeWriter.writeLengthDelimited(data)
            instructionWriter.writeKey(fieldNumber: 2, wireType: 2)
            instructionWriter.writeLengthDelimited(keystrokeWriter.data)
        case .resize(let cols, let rows):
            var resizeWriter = ProtoWriter()
            resizeWriter.writeKey(fieldNumber: 5, wireType: 0)
            resizeWriter.writeVarint(UInt64(cols))
            resizeWriter.writeKey(fieldNumber: 6, wireType: 0)
            resizeWriter.writeVarint(UInt64(rows))
            instructionWriter.writeKey(fieldNumber: 3, wireType: 2)
            instructionWriter.writeLengthDelimited(resizeWriter.data)
        }
        return instructionWriter.data
    }

    private static func decodeInstruction(from data: Data) throws -> [UserEvent] {
        var reader = ProtoReader(data: data)
        var events: [UserEvent] = []

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch key.fieldNumber {
            case 2:
                if key.wireType == 2 {
                    let submessage = try reader.readLengthDelimited()
                    if let event = try decodeKeystroke(from: submessage) {
                        events.append(event)
                    }
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 3:
                if key.wireType == 2 {
                    let submessage = try reader.readLengthDelimited()
                    if let event = try decodeResize(from: submessage) {
                        events.append(event)
                    }
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            default:
                try reader.skipField(wireType: key.wireType)
            }
        }

        return events
    }

    private static func decodeKeystroke(from data: Data) throws -> UserEvent? {
        var reader = ProtoReader(data: data)
        var bytes = Data()
        var found = false

        while !reader.isAtEnd {
            let key = try reader.readKey()
            if key.fieldNumber == 4, key.wireType == 2 {
                let chunk = try reader.readLengthDelimited()
                bytes.append(chunk)
                found = true
            } else {
                try reader.skipField(wireType: key.wireType)
            }
        }

        return found ? .keystroke(bytes) : nil
    }

    private static func decodeResize(from data: Data) throws -> UserEvent? {
        var reader = ProtoReader(data: data)
        var cols: Int?
        var rows: Int?

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch key.fieldNumber {
            case 5:
                if key.wireType == 0 {
                    let value = try reader.readVarint()
                    guard value <= UInt64(Int32.max) else {
                        throw ProtoCodecError.valueOverflow
                    }
                    cols = Int(value)
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 6:
                if key.wireType == 0 {
                    let value = try reader.readVarint()
                    guard value <= UInt64(Int32.max) else {
                        throw ProtoCodecError.valueOverflow
                    }
                    rows = Int(value)
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            default:
                try reader.skipField(wireType: key.wireType)
            }
        }

        guard let colsValue = cols, let rowsValue = rows else {
            return nil
        }
        return .resize(cols: colsValue, rows: rowsValue)
    }
}

struct HostMessageCodec {
    static func decode(data: Data) throws -> [HostEvent] {
        var reader = ProtoReader(data: data)
        var events: [HostEvent] = []

        while !reader.isAtEnd {
            let key = try reader.readKey()
            if key.fieldNumber == 1, key.wireType == 2 {
                let instruction = try reader.readLengthDelimited()
                let decoded = try decodeInstruction(from: instruction)
                events.append(contentsOf: decoded)
            } else {
                try reader.skipField(wireType: key.wireType)
            }
        }

        return events
    }

    private static func decodeInstruction(from data: Data) throws -> [HostEvent] {
        var reader = ProtoReader(data: data)
        var events: [HostEvent] = []

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch key.fieldNumber {
            case 2:
                if key.wireType == 2 {
                    let submessage = try reader.readLengthDelimited()
                    if let event = try decodeHostBytes(from: submessage) {
                        events.append(event)
                    }
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 3:
                if key.wireType == 2 {
                    let submessage = try reader.readLengthDelimited()
                    if let event = try decodeResize(from: submessage) {
                        events.append(event)
                    }
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 7:
                if key.wireType == 2 {
                    let submessage = try reader.readLengthDelimited()
                    if let event = try decodeEchoAck(from: submessage) {
                        events.append(event)
                    }
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            default:
                try reader.skipField(wireType: key.wireType)
            }
        }

        return events
    }

    private static func decodeHostBytes(from data: Data) throws -> HostEvent? {
        var reader = ProtoReader(data: data)
        var bytes = Data()
        var found = false

        while !reader.isAtEnd {
            let key = try reader.readKey()
            if key.fieldNumber == 4, key.wireType == 2 {
                let chunk = try reader.readLengthDelimited()
                bytes.append(chunk)
                found = true
            } else {
                try reader.skipField(wireType: key.wireType)
            }
        }

        return found ? .hostBytes(bytes) : nil
    }

    private static func decodeResize(from data: Data) throws -> HostEvent? {
        var reader = ProtoReader(data: data)
        var cols: Int?
        var rows: Int?

        while !reader.isAtEnd {
            let key = try reader.readKey()
            switch key.fieldNumber {
            case 5:
                if key.wireType == 0 {
                    let value = try reader.readVarint()
                    guard value <= UInt64(Int32.max) else {
                        throw ProtoCodecError.valueOverflow
                    }
                    cols = Int(value)
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            case 6:
                if key.wireType == 0 {
                    let value = try reader.readVarint()
                    guard value <= UInt64(Int32.max) else {
                        throw ProtoCodecError.valueOverflow
                    }
                    rows = Int(value)
                } else {
                    try reader.skipField(wireType: key.wireType)
                }
            default:
                try reader.skipField(wireType: key.wireType)
            }
        }

        guard let colsValue = cols, let rowsValue = rows else {
            return nil
        }
        return .resize(cols: colsValue, rows: rowsValue)
    }

    private static func decodeEchoAck(from data: Data) throws -> HostEvent? {
        var reader = ProtoReader(data: data)
        var value: UInt64?

        while !reader.isAtEnd {
            let key = try reader.readKey()
            if key.fieldNumber == 8, key.wireType == 0 {
                value = try reader.readVarint()
            } else {
                try reader.skipField(wireType: key.wireType)
            }
        }

        guard let echo = value else {
            return nil
        }
        return .echoAck(echo)
    }
}
