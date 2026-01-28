#if canImport(MoshClient)
import Foundation
import MoshClient

typealias MoshOutputCallback = @convention(c) (UnsafePointer<UInt8>?, Int32, UnsafeMutableRawPointer?) -> Void
typealias MoshStateCallback = @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void

@_silgen_name("mosh_client_create")
private func mosh_client_create(_ context: UnsafeMutableRawPointer?) -> OpaquePointer?

@_silgen_name("mosh_client_set_output_callback")
private func mosh_client_set_output_callback(
    _ handle: OpaquePointer?,
    _ callback: MoshOutputCallback?,
    _ context: UnsafeMutableRawPointer?
)

@_silgen_name("mosh_client_set_state_callback")
private func mosh_client_set_state_callback(
    _ handle: OpaquePointer?,
    _ callback: MoshStateCallback?,
    _ context: UnsafeMutableRawPointer?
)

@_silgen_name("mosh_client_start")
private func mosh_client_start(
    _ handle: OpaquePointer?,
    _ host: UnsafePointer<CChar>?,
    _ port: UInt16,
    _ key: UnsafePointer<CChar>?,
    _ cols: Int32,
    _ rows: Int32
) -> Int32

@_silgen_name("mosh_client_send")
private func mosh_client_send(
    _ handle: OpaquePointer?,
    _ bytes: UnsafePointer<UInt8>?,
    _ length: Int32
)

@_silgen_name("mosh_client_set_size")
private func mosh_client_set_size(
    _ handle: OpaquePointer?,
    _ cols: Int32,
    _ rows: Int32
)

@_silgen_name("mosh_client_stop")
private func mosh_client_stop(_ handle: OpaquePointer?)

@_silgen_name("mosh_client_destroy")
private func mosh_client_destroy(_ handle: OpaquePointer?)

enum MoshClientState: Int32 {
    case idle = 0
    case starting = 1
    case connected = 2
    case disconnected = 3
    case failed = 4
}

struct MoshClientAPI {
    let create: @Sendable (UnsafeMutableRawPointer?) -> OpaquePointer?
    let setOutputCallback: @Sendable (OpaquePointer?, MoshOutputCallback?, UnsafeMutableRawPointer?) -> Void
    let setStateCallback: @Sendable (OpaquePointer?, MoshStateCallback?, UnsafeMutableRawPointer?) -> Void
    let start: @Sendable (OpaquePointer?, UnsafePointer<CChar>?, UInt16, UnsafePointer<CChar>?, Int32, Int32) -> Int32
    let send: @Sendable (OpaquePointer?, UnsafePointer<UInt8>?, Int32) -> Void
    let setSize: @Sendable (OpaquePointer?, Int32, Int32) -> Void
    let stop: @Sendable (OpaquePointer?) -> Void
    let destroy: @Sendable (OpaquePointer?) -> Void

    static let live = MoshClientAPI(
        create: { mosh_client_create($0) },
        setOutputCallback: { mosh_client_set_output_callback($0, $1, $2) },
        setStateCallback: { mosh_client_set_state_callback($0, $1, $2) },
        start: { mosh_client_start($0, $1, $2, $3, $4, $5) },
        send: { mosh_client_send($0, $1, $2) },
        setSize: { mosh_client_set_size($0, $1, $2) },
        stop: { mosh_client_stop($0) },
        destroy: { mosh_client_destroy($0) }
    )
}

private final class MoshClientCallbackContext {
    weak var engine: MoshClientEngine?
    var isActive = true
}

final class MoshClientEngine: MoshEngine, @unchecked Sendable {
    var onOutput: (@Sendable (Data) -> Void)?
    var onStateChange: (@Sendable (MoshEngineState) -> Void)?

    private let queue = DispatchQueue(label: "com.moshterminal.moshengine")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let api: MoshClientAPI
    private let callbackContext: MoshClientCallbackContext
    private let contextPointer: UnsafeMutableRawPointer
    private var handle: OpaquePointer?

    init(api: MoshClientAPI = .live) {
        self.api = api
        self.callbackContext = MoshClientCallbackContext()
        self.contextPointer = Unmanaged.passUnretained(callbackContext).toOpaque()
        queue.setSpecific(key: queueKey, value: 1)
        callbackContext.engine = self
    }

    deinit {
        callbackContext.isActive = false
        destroyHandle()
    }

    func start(connectInfo: MoshConnectInfo, initialTerminalSize: TerminalSize) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: MoshEngineError.startFailed(message: "Engine deallocated."))
                    return
                }
                self.callbackContext.isActive = true
                guard let handle = self.api.create(self.contextPointer) else {
                    continuation.resume(throwing: MoshEngineError.startFailed(message: "mosh_client_create failed."))
                    return
                }
                self.handle = handle
                self.api.setOutputCallback(handle, moshOutputCallback, self.contextPointer)
                self.api.setStateCallback(handle, moshStateCallback, self.contextPointer)
                let result: Int32 = connectInfo.serverAddress.withCString { hostCString in
                    connectInfo.sessionKey.withCString { keyCString in
                        self.api.start(
                            handle,
                            hostCString,
                            UInt16(connectInfo.udpPort),
                            keyCString,
                            Int32(initialTerminalSize.cols),
                            Int32(initialTerminalSize.rows)
                        )
                    }
                }
                if result == 0 {
                    continuation.resume()
                } else {
                    self.callbackContext.isActive = false
                    self.api.setOutputCallback(handle, nil, nil)
                    self.api.setStateCallback(handle, nil, nil)
                    self.api.destroy(handle)
                    self.handle = nil
                    continuation.resume(throwing: MoshEngineError.startFailed(message: "mosh_client_start failed (\(result))."))
                }
            }
        }
    }

    func sendInput(_ bytes: Data) async {
        queue.async { [weak self] in
            guard let self else { return }
            bytes.withUnsafeBytes { rawBuffer in
                self.api.send(self.handle, rawBuffer.bindMemory(to: UInt8.self).baseAddress, Int32(bytes.count))
            }
        }
    }

    func updateTerminalSize(cols: Int, rows: Int) async {
        queue.async { [weak self] in
            guard let self else { return }
            self.api.setSize(self.handle, Int32(cols), Int32(rows))
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.callbackContext.isActive = false
                if let handle = self.handle {
                    self.api.setOutputCallback(handle, nil, nil)
                    self.api.setStateCallback(handle, nil, nil)
                    self.api.stop(handle)
                    self.api.destroy(handle)
                    self.handle = nil
                }
                self.onStateChange?(.idle)
                continuation.resume()
            }
        }
    }

    private func handleOutput(_ data: Data) {
        onOutput?(data)
    }

    private func handleState(_ state: MoshClientState) {
        let mapped: MoshEngineState
        switch state {
        case .idle:
            mapped = .idle
        case .starting:
            mapped = .starting
        case .connected:
            mapped = .connected
        case .disconnected:
            mapped = .disconnected
        case .failed:
            mapped = .failed(MoshEngineError.startFailed(message: "Mosh client reported failure."))
        }
        onStateChange?(mapped)
    }

    private func destroyHandle() {
        guard let handle else { return }
        let work = { [api, handle, callbackContext] in
            callbackContext.isActive = false
            api.setOutputCallback(handle, nil, nil)
            api.setStateCallback(handle, nil, nil)
            api.destroy(handle)
        }
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            work()
        } else {
            queue.sync(execute: work)
        }
        self.handle = nil
    }
}

private let moshOutputCallback: MoshOutputCallback = { bytes, length, context in
    guard let bytes, length > 0, let context else { return }
    let callbackContext = Unmanaged<MoshClientCallbackContext>.fromOpaque(context).takeUnretainedValue()
    guard callbackContext.isActive, let engine = callbackContext.engine else { return }
    let data = Data(bytes: bytes, count: Int(length))
    engine.handleOutput(data)
}

private let moshStateCallback: MoshStateCallback = { stateValue, context in
    guard let context else { return }
    let callbackContext = Unmanaged<MoshClientCallbackContext>.fromOpaque(context).takeUnretainedValue()
    guard callbackContext.isActive, let engine = callbackContext.engine else { return }
    let state = MoshClientState(rawValue: stateValue) ?? .failed
    engine.handleState(state)
}
#endif
