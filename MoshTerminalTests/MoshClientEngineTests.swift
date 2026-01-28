#if canImport(MoshClient)
import XCTest
@testable import MoshTerminal

final class MoshClientEngineTests: XCTestCase {
    func testStopAwaitsStopAndDestroy() async throws {
        let mock = MockMoshClientAPI()
        let engine = MoshClientEngine(api: mock.api)
        let connectInfo = MoshConnectInfo(udpPort: 60000, sessionKey: "abc123=", serverAddress: "example.com")
        try await engine.start(connectInfo: connectInfo, initialTerminalSize: TerminalSize(cols: 80, rows: 24))

        await engine.stop()

        XCTAssertEqual(mock.callOrder, ["stop", "destroy"])
        XCTAssertEqual(mock.stopCalls, 1)
        XCTAssertEqual(mock.destroyCalls, 1)
    }

    func testStopIgnoresLateCallbacks() async throws {
        let mock = MockMoshClientAPI()
        let engine = MoshClientEngine(api: mock.api)
        let connectInfo = MoshConnectInfo(udpPort: 60000, sessionKey: "abc123=", serverAddress: "example.com")
        var receivedStates: [MoshEngineState] = []
        engine.onStateChange = { state in
            receivedStates.append(state)
        }
        try await engine.start(connectInfo: connectInfo, initialTerminalSize: TerminalSize(cols: 80, rows: 24))

        await engine.stop()
        mock.emitState(.connected)

        guard let lastState = receivedStates.last else {
            XCTFail("Expected idle state after stop.")
            return
        }
        if case .idle = lastState {
        } else {
            XCTFail("Expected idle state after stop.")
        }
        XCTAssertFalse(receivedStates.contains { if case .connected = $0 { return true } else { return false } })
    }

    func testStopIsIdempotent() async throws {
        let mock = MockMoshClientAPI()
        let engine = MoshClientEngine(api: mock.api)
        let connectInfo = MoshConnectInfo(udpPort: 60000, sessionKey: "abc123=", serverAddress: "example.com")
        try await engine.start(connectInfo: connectInfo, initialTerminalSize: TerminalSize(cols: 80, rows: 24))

        await engine.stop()
        await engine.stop()

        XCTAssertEqual(mock.stopCalls, 1)
        XCTAssertEqual(mock.destroyCalls, 1)
    }
}

private final class MockMoshClientAPI {
    private(set) var stopCalls = 0
    private(set) var destroyCalls = 0
    private(set) var callOrder: [String] = []

    private var handle: OpaquePointer?
    private var stateCallback: MoshStateCallback?
    private var stateContext: UnsafeMutableRawPointer?
    private var lastStateCallback: MoshStateCallback?
    private var lastStateContext: UnsafeMutableRawPointer?

    lazy var api = MoshClientAPI(
        create: { [weak self] context in
            guard let self else { return nil }
            let handle = OpaquePointer(bitPattern: 0x1)
            self.handle = handle
            self.stateContext = context
            return handle
        },
        setOutputCallback: { _, _, _ in },
        setStateCallback: { [weak self] _, callback, context in
            guard let self else { return }
            if let callback {
                self.lastStateCallback = callback
                self.lastStateContext = context
            }
            self.stateCallback = callback
            self.stateContext = context
        },
        start: { _, _, _, _, _, _ in 0 },
        send: { _, _, _ in },
        setSize: { _, _, _ in },
        stop: { [weak self] _ in
            guard let self else { return }
            self.stopCalls += 1
            self.callOrder.append("stop")
        },
        destroy: { [weak self] _ in
            guard let self else { return }
            self.destroyCalls += 1
            self.callOrder.append("destroy")
            self.handle = nil
        }
    )

    func emitState(_ state: MoshClientState) {
        if let callback = stateCallback {
            callback(state.rawValue, stateContext)
        } else if let callback = lastStateCallback {
            callback(state.rawValue, lastStateContext)
        }
    }
}
#endif
