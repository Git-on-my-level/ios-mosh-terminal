import Foundation

struct TimestampedState<State> {
    let num: UInt64
    let state: State
    let timestampMillis: UInt64
}

final class TransportSender {
    enum Constants {
        static let minSendIntervalMillis: UInt64 = 20
        static let maxSendIntervalMillis: UInt64 = 250
        static let ackIntervalMillis: UInt64 = 3_000
        static let ackDelayMillis: UInt64 = 100
        static let activeRetryTimeoutMillis: UInt64 = 10_000
        static let sendMinDelayMillis: UInt64 = 8
        static let maxSentStates = 32
    }

    var currentState = UserState()
    private(set) var sentStates: [TimestampedState<UserState>] = []
    private(set) var ackNum: UInt64 = 0
    var isConnected: Bool = false

    private var lastAckedState = UserState()
    private(set) var lastAckedStateNum: UInt64 = 0
    private var lastSentState = UserState()
    private var lastSentStateNum: UInt64 = 0
    private var lastSendMillis: UInt64?
    private var lastActivityMillis: UInt64?
    private var nextAckTimeMillis: UInt64?
    private var nextSendTimeMillis: UInt64?
    private var ackDirty = false

    func setConnected(_ connected: Bool, nowMillis: UInt64) {
        isConnected = connected
        if connected {
            scheduleIfNeeded(nowMillis: nowMillis)
        } else {
            nextAckTimeMillis = nil
            nextSendTimeMillis = nil
        }
    }

    func setAckNum(_ remoteStateNum: UInt64) {
        if remoteStateNum != ackNum {
            ackNum = remoteStateNum
            ackDirty = true
        }
    }

    func processAckThrough(_ ack: UInt64) {
        guard ack >= lastAckedStateNum else {
            return
        }

        if let matched = sentStates.last(where: { $0.num <= ack }) {
            lastAckedState = matched.state
            lastAckedStateNum = matched.num
        } else if ack >= lastSentStateNum {
            lastAckedState = lastSentState
            lastAckedStateNum = lastSentStateNum
        }

        sentStates.removeAll { $0.num <= ack }
    }

    func tick(nowMillis: UInt64) -> [TransportInstruction] {
        guard isConnected else {
            return []
        }

        scheduleIfNeeded(nowMillis: nowMillis)

        let dueAck = nextAckTimeMillis.map { nowMillis >= $0 } ?? false
        let dueSend = nextSendTimeMillis.map { nowMillis >= $0 } ?? false
        let minDelayPassed = lastSendMillis.map { nowMillis >= $0 + Constants.minSendIntervalMillis } ?? true
        let hasNewState = currentState != lastSentState
        let canResend = shouldResend(nowMillis: nowMillis)

        if !(minDelayPassed && (dueSend || dueAck || canResend)) {
            return []
        }

        let sendingState: UserState
        let newNum: UInt64
        let includeStateDiff: Bool

        if hasNewState {
            newNum = lastSentStateNum + 1
            sendingState = currentState
            includeStateDiff = true
        } else if canResend && lastSentStateNum > 0 {
            newNum = lastSentStateNum
            sendingState = lastSentState
            includeStateDiff = true
        } else {
            newNum = 0
            sendingState = currentState
            includeStateDiff = false
        }

        var instruction = TransportInstruction(protocolVersion: 2)
        instruction.ackNum = ackNum
        instruction.chaff = randomChaff()

        if includeStateDiff {
            instruction.oldNum = lastAckedStateNum
            instruction.newNum = newNum
            instruction.diff = sendingState.diff(from: lastAckedState)
        }

        if includeStateDiff && hasNewState {
            lastSentState = currentState
            lastSentStateNum = newNum
            let timestamped = TimestampedState(num: newNum, state: currentState, timestampMillis: nowMillis)
            sentStates.append(timestamped)
            if sentStates.count > Constants.maxSentStates {
                sentStates.remove(at: sentStates.count / 2)
            }
        } else if includeStateDiff && canResend {
            if let index = sentStates.firstIndex(where: { $0.num == newNum }) {
                sentStates[index] = TimestampedState(num: newNum, state: sentStates[index].state, timestampMillis: nowMillis)
            }
        }

        lastSendMillis = nowMillis
        if hasNewState {
            nextSendTimeMillis = nowMillis + Constants.minSendIntervalMillis
        } else {
            nextSendTimeMillis = nil
        }

        if ackDirty || dueAck {
            ackDirty = false
            nextAckTimeMillis = nowMillis + Constants.ackIntervalMillis
        }

        return [instruction]
    }

    func waitTime(nowMillis: UInt64) -> Int {
        guard isConnected else {
            return Int.max
        }

        scheduleIfNeeded(nowMillis: nowMillis)

        var candidates: [UInt64] = []

        if let nextSend = nextSendTimeMillis {
            candidates.append(applyMinSendInterval(to: nextSend))
        }

        if let nextAck = nextAckTimeMillis {
            candidates.append(applyMinSendInterval(to: nextAck))
        }

        if let resendTime = nextResendTime(nowMillis: nowMillis) {
            candidates.append(applyMinSendInterval(to: resendTime))
        }

        guard let earliest = candidates.min() else {
            return Int.max
        }

        if earliest <= nowMillis {
            return 0
        }

        let delta = earliest - nowMillis
        return delta > UInt64(Int.max) ? Int.max : Int(delta)
    }

    private func scheduleIfNeeded(nowMillis: UInt64) {
        if currentState != lastSentState {
            let proposed = nowMillis + Constants.sendMinDelayMillis
            if let existing = nextSendTimeMillis {
                if proposed > existing {
                    nextSendTimeMillis = proposed
                }
            } else {
                nextSendTimeMillis = proposed
            }
            lastActivityMillis = nowMillis
        }

        if ackDirty && nextAckTimeMillis == nil {
            nextAckTimeMillis = nowMillis + Constants.ackDelayMillis
        }
    }

    private func shouldResend(nowMillis: UInt64) -> Bool {
        guard currentState == lastSentState, !sentStates.isEmpty else {
            return false
        }
        guard let lastSend = lastSendMillis else {
            return false
        }
        guard let lastActivity = lastActivityMillis else {
            return false
        }
        if nowMillis > lastActivity + Constants.activeRetryTimeoutMillis {
            return false
        }
        return nowMillis >= lastSend + Constants.maxSendIntervalMillis
    }

    private func nextResendTime(nowMillis: UInt64) -> UInt64? {
        guard currentState == lastSentState, !sentStates.isEmpty else {
            return nil
        }
        guard let lastSend = lastSendMillis else {
            return nil
        }
        guard let lastActivity = lastActivityMillis else {
            return nil
        }
        if nowMillis > lastActivity + Constants.activeRetryTimeoutMillis {
            return nil
        }
        return lastSend + Constants.maxSendIntervalMillis
    }

    private func applyMinSendInterval(to candidate: UInt64) -> UInt64 {
        guard let lastSend = lastSendMillis else {
            return candidate
        }
        let minAllowed = lastSend + Constants.minSendIntervalMillis
        return max(candidate, minAllowed)
    }

    private func randomChaff() -> Data {
        let lengthByte = SecureRandom.bytes(count: 1).first ?? 0
        let length = Int(lengthByte % 17)
        if length == 0 {
            return Data()
        }
        return Data(SecureRandom.bytes(count: length))
    }
}
