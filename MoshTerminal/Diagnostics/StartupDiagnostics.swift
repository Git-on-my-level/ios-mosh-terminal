import Foundation

struct StartupDiagnosticsSnapshot: Codable {
    var appInitMs: Double?
    var appEnvironmentInitStartMs: Double?
    var appEnvironmentInitEndMs: Double?
    var rootViewAppearMs: Double?
    var hostsLoadStartMs: Double?
    var hostsLoadEndMs: Double?

    var terminalViewInitCount: Int = 0
    var terminalSessionControllerInitCount: Int = 0
    var tipJarStartCount: Int = 0
    var networkMonitorStartCount: Int = 0
}

@MainActor
final class StartupDiagnostics: ObservableObject {
    static let shared = StartupDiagnostics()

    private let userDefaultsKey = "mosh.startup_diagnostics.json"

    @Published private(set) var snapshot = StartupDiagnosticsSnapshot()

    private var baselineUptime: Double = 0
    private var isEnabled: Bool = false

    private init() {
        isEnabled = ProcessInfo.processInfo.environment["MOSH_DIAGNOSTICS"] == "1"
        if isEnabled {
            baselineUptime = ProcessInfo.processInfo.systemUptime
        }
    }

    private func currentRelativeMs() -> Double {
        guard isEnabled else { return 0 }
        return (ProcessInfo.processInfo.systemUptime - baselineUptime) * 1000
    }

    private func save() {
        guard isEnabled else { return }
        if let data = try? JSONEncoder().encode(snapshot),
           let jsonString = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(jsonString, forKey: userDefaultsKey)
        }
    }

    func markAppInit() {
        guard isEnabled else { return }
        snapshot.appInitMs = currentRelativeMs()
        save()
    }

    func markAppEnvironmentInitStart() {
        guard isEnabled else { return }
        snapshot.appEnvironmentInitStartMs = currentRelativeMs()
        save()
    }

    func markAppEnvironmentInitEnd() {
        guard isEnabled else { return }
        snapshot.appEnvironmentInitEndMs = currentRelativeMs()
        save()
    }

    func markRootViewAppear() {
        guard isEnabled else { return }
        snapshot.rootViewAppearMs = currentRelativeMs()
        save()
    }

    func markHostsLoadStart() {
        guard isEnabled else { return }
        snapshot.hostsLoadStartMs = currentRelativeMs()
        save()
    }

    func markHostsLoadEnd() {
        guard isEnabled else { return }
        snapshot.hostsLoadEndMs = currentRelativeMs()
        save()
    }

    func incrementTerminalViewInit() {
        guard isEnabled else { return }
        snapshot.terminalViewInitCount += 1
        save()
    }

    func incrementTerminalSessionControllerInit() {
        guard isEnabled else { return }
        snapshot.terminalSessionControllerInitCount += 1
        save()
    }

    func incrementTipJarStart() {
        guard isEnabled else { return }
        snapshot.tipJarStartCount += 1
        save()
    }

    func incrementNetworkMonitorStart() {
        guard isEnabled else { return }
        snapshot.networkMonitorStartCount += 1
        save()
    }

    var diagnosticsJSON: String? {
        guard isEnabled else { return nil }
        if let data = try? JSONEncoder().encode(snapshot),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return nil
    }
}
