import Foundation

struct UserState: Equatable {
    var events: [UserEvent]

    init(events: [UserEvent] = []) {
        self.events = events
    }

    mutating func append(_ event: UserEvent) {
        events.append(event)
    }

    mutating func append(contentsOf events: [UserEvent]) {
        self.events.append(contentsOf: events)
    }

    mutating func subtract(prefixState: UserState) {
        let count = commonPrefixCount(with: prefixState)
        if count > 0 {
            events.removeFirst(count)
        }
    }

    func diff(from existingState: UserState) -> Data {
        let count = commonPrefixCount(with: existingState)
        let diffEvents = Array(events.dropFirst(count))
        return UserMessageCodec.encode(events: diffEvents)
    }

    mutating func apply(diff data: Data) throws {
        let decoded = try UserMessageCodec.decode(data: data)
        events.append(contentsOf: decoded)
    }

    private func commonPrefixCount(with other: UserState) -> Int {
        let limit = min(events.count, other.events.count)
        var index = 0
        while index < limit {
            if events[index] != other.events[index] {
                break
            }
            index += 1
        }
        return index
    }
}
