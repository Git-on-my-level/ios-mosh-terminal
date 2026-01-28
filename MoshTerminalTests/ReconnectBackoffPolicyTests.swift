import XCTest
@testable import MoshTerminal

final class ReconnectBackoffPolicyTests: XCTestCase {
    func testDelayUsesExponentialWithCapWhenNoJitter() {
        let policy = ReconnectBackoffPolicy(baseDelay: 1, maxDelay: 6, multiplier: 2, jitter: 0)
        let delays = (0...5).map { policy.delay(forAttempt: $0, randomUnit: { 0.5 }) }

        XCTAssertEqual(delays[0], 0, accuracy: 0.0001)
        XCTAssertEqual(delays[1], 1, accuracy: 0.0001)
        XCTAssertEqual(delays[2], 2, accuracy: 0.0001)
        XCTAssertEqual(delays[3], 4, accuracy: 0.0001)
        XCTAssertEqual(delays[4], 6, accuracy: 0.0001)
        XCTAssertEqual(delays[5], 6, accuracy: 0.0001)
    }

    func testDelayAppliesJitterWithinBounds() {
        let policy = ReconnectBackoffPolicy(baseDelay: 10, maxDelay: 10, multiplier: 2, jitter: 0.2)

        let minDelay = policy.delay(forAttempt: 1, randomUnit: { 0 })
        let maxDelay = policy.delay(forAttempt: 1, randomUnit: { 1 })
        let midDelay = policy.delay(forAttempt: 1, randomUnit: { 0.5 })

        XCTAssertEqual(minDelay, 8, accuracy: 0.0001)
        XCTAssertEqual(maxDelay, 12, accuracy: 0.0001)
        XCTAssertEqual(midDelay, 10, accuracy: 0.0001)
    }

    func testStateResetsOnSuccess() {
        let policy = ReconnectBackoffPolicy(baseDelay: 1, maxDelay: 10, multiplier: 2, jitter: 0)
        var state = ReconnectBackoffState(policy: policy, randomUnit: { 0.5 })

        XCTAssertEqual(state.nextDelay(), 0, accuracy: 0.0001)
        state.recordFailure()
        XCTAssertEqual(state.nextDelay(), 1, accuracy: 0.0001)
        state.recordFailure()
        XCTAssertEqual(state.nextDelay(), 2, accuracy: 0.0001)
        state.recordSuccess()
        XCTAssertEqual(state.nextDelay(), 0, accuracy: 0.0001)
    }
}
