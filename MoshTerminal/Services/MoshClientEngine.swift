#if canImport(MoshClient)
import Foundation
import MoshClient

private typealias MoshOutputCallback = @convention(c) (UnsafePointer<UInt8>?, Int32, UnsafeMutableRawPointer?) -> Void
private typealias MoshStateCallback = @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void

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

private enum MoshClientState: Int32 {
    case idle = 0
    case starting = 1
    case connected = 2
    case disconnected = 3
    case failed = 4
}

final class MoshClientEngine: MoshEngine, @unchecked Sendable {
    var onOutput: (@Sendable (Data) -> Void)?
    var onStateChange: (@Sendable (MoshEngineState) -> Void)?

    private let queue = DispatchQueue(label: "com.moshterminal.moshengine")
    private var handle: OpaquePointer?

    deinit {
        if let handle {
            mosh_client_destroy(handle)
        }
    }

    func start(connectInfo: MoshConnectInfo, initialTerminalSize: TerminalSize) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: MoshEngineError.startFailed(message: "Engine deallocated."))
                    return
                }
                let context = Unmanaged.passUnretained(self).toOpaque()
                let handle = mosh_client_create(context)
                self.handle = handle
                mosh_client_set_output_callback(handle, moshOutputCallback, context)
                mosh_client_set_state_callback(handle, moshStateCallback, context)
                let result: Int32 = connectInfo.serverAddress.withCString { hostCString in
                    connectInfo.sessionKey.withCString { keyCString in
                        mosh_client_start(
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
                    continuation.resume(throwing: MoshEngineError.startFailed(message: "mosh_client_start failed (\(result))."))
                }
            }
        }
    }

    func sendInput(_ bytes: Data) async {
        queue.async { [weak self] in
            guard let self else { return }
            bytes.withUnsafeBytes { rawBuffer in
                mosh_client_send(self.handle, rawBuffer.bindMemory(to: UInt8.self).baseAddress, Int32(bytes.count))
            }
        }
    }

    func updateTerminalSize(cols: Int, rows: Int) async {
        queue.async { [weak self] in
            guard let self else { return }
            mosh_client_set_size(self.handle, Int32(cols), Int32(rows))
        }
    }

    func stop() async {
        queue.async { [weak self] in
            guard let self else { return }
            mosh_client_stop(self.handle)
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
}

private let moshOutputCallback: MoshOutputCallback = { bytes, length, context in
    guard let bytes, length > 0, let context else { return }
    let engine = Unmanaged<MoshClientEngine>.fromOpaque(context).takeUnretainedValue()
    let data = Data(bytes: bytes, count: Int(length))
    engine.handleOutput(data)
}

private let moshStateCallback: MoshStateCallback = { stateValue, context in
    guard let context else { return }
    let engine = Unmanaged<MoshClientEngine>.fromOpaque(context).takeUnretainedValue()
    let state = MoshClientState(rawValue: stateValue) ?? .failed
    engine.handleState(state)
}
#endif
