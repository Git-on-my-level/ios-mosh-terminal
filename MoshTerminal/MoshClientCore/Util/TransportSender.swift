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
        static let keepaliveIntervalMillis: UInt64 = 5_000
        static let sendMinDelayMillis: UInt64 = 8
        static let maxSentStates = 32
    }

    typealias RandomBytesProvider = (Int) -> [UInt8]

    var currentState = UserState()
    private(set) var sentStates: [TimestampedState<UserState>] = []
    private(set) var ackNum: UInt64 = 0
    var isConnected: Bool = false

    private let keepaliveIntervalMillis: UInt64
    private let randomBytes: RandomBytesProvider
    private var lastAckedState = UserState()
    private(set) var lastAckedStateNum: UInt64 = 0
    private var lastSentState = UserState()
    private var lastSentStateNum: UInt64 = 0
    private var lastSentStateTimestampMillis: UInt64?
    private var lastSendMillis: UInt64?
    private var lastActivityMillis: UInt64?
    private var nextAckTimeMillis: UInt64?
    private var nextSendTimeMillis: UInt64?
    private var nextKeepaliveTimeMillis: UInt64?
    private var ackDirty = false
    private var srttMillis: Double?
    private var rttvarMillis: Double?
    private var rtoMillis: UInt64?

    var lastSentStateNumPublic: UInt64 {
        lastSentStateNum
    }

    var lastAckedStateNumPublic: UInt64 {
        lastAckedStateNum
    }

    var srttMillisPublic: UInt64? {
        srttMillis.map { UInt64(round($0)) }
    }

    init(
        keepaliveIntervalMillis: UInt64 = Constants.keepaliveIntervalMillis,
        randomBytes: @escaping RandomBytesProvider = SecureRandom.nonThrowingBytes
    ) {
        self.keepaliveIntervalMillis = keepaliveIntervalMillis
        self.randomBytes = randomBytes
    }

    func setConnected(_ connected: Bool, nowMillis: UInt64) {
        isConnected = connected
        if connected {
            if keepaliveIntervalMillis > 0 {
                nextKeepaliveTimeMillis = nowMillis + keepaliveIntervalMillis
            }
            scheduleIfNeeded(nowMillis: nowMillis)
        } else {
            nextAckTimeMillis = nil
            nextSendTimeMillis = nil
            nextKeepaliveTimeMillis = nil
            srttMillis = nil
            rttvarMillis = nil
            rtoMillis = nil
        }
    }

    func setAckNum(_ remoteStateNum: UInt64) {
        if remoteStateNum != ackNum {
            ackNum = remoteStateNum
            ackDirty = true
        }
    }

    func processAckThrough(_ ack: UInt64, nowMillis: UInt64) {
        guard ack >= lastAckedStateNum else {
            return
        }

        let previousAck = lastAckedStateNum
        let ackAdvanced = ack > previousAck

        if let matched = sentStates.last(where: { $0.num <= ack }) {
            lastAckedState = matched.state
            lastAckedStateNum = matched.num
            if ackAdvanced, nowMillis >= matched.timestampMillis {
                updateRtt(sampleMillis: nowMillis - matched.timestampMillis)
            }
        } else if ack >= lastSentStateNum {
            lastAckedState = lastSentState
            lastAckedStateNum = lastSentStateNum
            if ackAdvanced, let timestamp = lastSentStateTimestampMillis, nowMillis >= timestamp {
                updateRtt(sampleMillis: nowMillis - timestamp)
            }
        }

        sentStates.removeAll { $0.num <= ack }
    }

    func tick(nowMillis: UInt64) -> [TransportInstruction] {
        guard isConnected else {
            return []
        }

        scheduleIfNeeded(nowMillis: nowMillis)

        let hasNewState = currentState != lastSentState
        let isBackpressured = hasNewState && sentStates.count >= Constants.maxSentStates
        let canSendNewState = hasNewState && !isBackpressured
        let dueAck = nextAckTimeMillis.map { nowMillis >= $0 } ?? false
        let dueSend = canSendNewState && (nextSendTimeMillis.map { nowMillis >= $0 } ?? false)
        let minDelayPassed = lastSendMillis.map { nowMillis >= $0 + Constants.minSendIntervalMillis } ?? true
        let canResend = shouldResend(nowMillis: nowMillis, allowStale: isBackpressured)
        let dueKeepalive = keepaliveIntervalMillis > 0
            && (nextKeepaliveTimeMillis.map { nowMillis >= $0 } ?? false)

        if !(minDelayPassed && (dueSend || dueAck || canResend || dueKeepalive)) {
            return []
        }

        let sendingState: UserState
        let newNum: UInt64
        let includeStateDiff: Bool

        if canSendNewState {
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

        if includeStateDiff && canSendNewState {
            lastSentState = currentState
            lastSentStateNum = newNum
            lastSentStateTimestampMillis = nowMillis
            let timestamped = TimestampedState(num: newNum, state: currentState, timestampMillis: nowMillis)
            sentStates.append(timestamped)
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
        if keepaliveIntervalMillis > 0 {
            nextKeepaliveTimeMillis = nowMillis + keepaliveIntervalMillis
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

        let hasNewState = currentState != lastSentState
        let isBackpressured = hasNewState && sentStates.count >= Constants.maxSentStates
        let canSendNewState = hasNewState && !isBackpressured
        var candidates: [UInt64] = []

        if canSendNewState, let nextSend = nextSendTimeMillis {
            candidates.append(applyMinSendInterval(to: nextSend))
        }

        if let nextAck = nextAckTimeMillis {
            candidates.append(applyMinSendInterval(to: nextAck))
        }

        if let nextKeepalive = nextKeepaliveTimeMillis, keepaliveIntervalMillis > 0 {
            candidates.append(applyMinSendInterval(to: nextKeepalive))
        }

        if let resendTime = nextResendTime(nowMillis: nowMillis, allowStale: isBackpressured) {
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

    func debugSendIntervalMillis(nowMillis: UInt64) -> UInt64? {
        guard isConnected else { return nil }
        if let nextSend = nextSendTimeMillis {
            return nextSend > nowMillis ? nextSend - nowMillis : 0
        }
        if let lastSend = lastSendMillis {
            return Constants.maxSendIntervalMillis > 0 ? Constants.maxSendIntervalMillis : max(0, nowMillis - lastSend)
        }
        return nil
    }

    var debugRtoMillis: UInt64? {
        rtoMillis
    }

    private func scheduleIfNeeded(nowMillis: UInt64) {
        if currentState != lastSentState {
            if let existing = nextSendTimeMillis {
                if nowMillis < existing {
                    let proposed = nowMillis + Constants.sendMinDelayMillis
                    if proposed > existing {
                        nextSendTimeMillis = proposed
                    }
                }
            } else {
                nextSendTimeMillis = nowMillis
            }
            lastActivityMillis = nowMillis
        }

        if ackDirty && nextAckTimeMillis == nil {
            nextAckTimeMillis = nowMillis + Constants.ackDelayMillis
        }

        if keepaliveIntervalMillis > 0, nextKeepaliveTimeMillis == nil {
            nextKeepaliveTimeMillis = nowMillis + keepaliveIntervalMillis
        }
    }

    private func shouldResend(nowMillis: UInt64, allowStale: Bool = false) -> Bool {
        guard (allowStale || currentState == lastSentState), !sentStates.isEmpty else {
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

    private func nextResendTime(nowMillis: UInt64, allowStale: Bool = false) -> UInt64? {
        guard (allowStale || currentState == lastSentState), !sentStates.isEmpty else {
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
        let lengthByte = randomBytes(1).first ?? 0
        let length = Int(lengthByte % 17)
        if length == 0 {
            return Data()
        }
        return Data(randomBytes(length))
    }

    private func updateRtt(sampleMillis: UInt64) {
        let sample = Double(sampleMillis)
        if let srtt = srttMillis, let rttvar = rttvarMillis {
            let newRttvar = (1.0 - 0.25) * rttvar + 0.25 * abs(srtt - sample)
            let newSrtt = (1.0 - 0.125) * srtt + 0.125 * sample
            srttMillis = newSrtt
            rttvarMillis = newRttvar
        } else {
            srttMillis = sample
            rttvarMillis = sample / 2.0
        }

        if let srtt = srttMillis, let rttvar = rttvarMillis {
            let rto = ceil(srtt + 4.0 * rttvar)
            let bounded = min(max(rto, 50.0), 1000.0)
            rtoMillis = UInt64(bounded)
        }
    }
}
