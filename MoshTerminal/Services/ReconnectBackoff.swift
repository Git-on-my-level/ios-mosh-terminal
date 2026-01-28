import Foundation

struct ReconnectBackoffPolicy: Equatable {
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let multiplier: Double
    let jitter: Double

    static let `default` = ReconnectBackoffPolicy(
        baseDelay: 0.5,
        maxDelay: 8.0,
        multiplier: 2.0,
        jitter: 0.2
    )

    func delay(forAttempt attempt: Int, randomUnit: () -> Double) -> TimeInterval {
        let unclamped = baseDelay(forAttempt: attempt)
        guard unclamped > 0 else { return 0 }
        let jitterFraction = max(0, min(jitter, 1))
        let jitterAmount = unclamped * jitterFraction
        let minDelay = max(0, unclamped - jitterAmount)
        let maxDelay = unclamped + jitterAmount
        let unit = max(0, min(randomUnit(), 1))
        return minDelay + (maxDelay - minDelay) * unit
    }

    func baseDelay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let exponential = pow(multiplier, Double(attempt - 1))
        return min(maxDelay, baseDelay * exponential)
    }
}

struct ReconnectBackoffState {
    private(set) var failureCount: Int = 0
    var policy: ReconnectBackoffPolicy
    var randomUnit: () -> Double

    init(
        policy: ReconnectBackoffPolicy = .default,
        randomUnit: @escaping () -> Double = { Double.random(in: 0...1) }
    ) {
        self.policy = policy
        self.randomUnit = randomUnit
    }

    mutating func recordFailure() {
        failureCount += 1
    }

    mutating func recordSuccess() {
        failureCount = 0
    }

    mutating func nextDelay() -> TimeInterval {
        policy.delay(forAttempt: failureCount, randomUnit: randomUnit)
    }
}
