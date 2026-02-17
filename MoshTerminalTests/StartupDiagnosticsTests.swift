import XCTest
@testable import MoshTerminal

final class StartupDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    func testDiagnosticsSnapshotEncodesAndDecodes() {
        let originalEnv = ProcessInfo.processInfo.environment["MOSH_DIAGNOSTICS"]
        defer {
            if let originalEnv = originalEnv {
                setEnvironmentVariable("MOSH_DIAGNOSTICS", value: originalEnv)
            } else {
                unsetEnvironmentVariable("MOSH_DIAGNOSTICS")
            }
        }

        setEnvironmentVariable("MOSH_DIAGNOSTICS", value: "1")

        let snapshot = StartupDiagnosticsSnapshot(
            appInitMs: 10.5,
            appEnvironmentInitStartMs: 11.0,
            appEnvironmentInitEndMs: 50.3,
            rootViewAppearMs: 55.0,
            hostsLoadStartMs: 60.0,
            hostsLoadEndMs: 75.5,
            terminalViewInitCount: 2,
            terminalSessionControllerInitCount: 3,
            tipJarStartCount: 1,
            networkMonitorStartCount: 1
        )

        let data = try! JSONEncoder().encode(snapshot)
        let decoded = try! JSONDecoder().decode(StartupDiagnosticsSnapshot.self, from: data)

        XCTAssertEqual(decoded.appInitMs, 10.5)
        XCTAssertEqual(decoded.appEnvironmentInitStartMs, 11.0)
        XCTAssertEqual(decoded.appEnvironmentInitEndMs, 50.3)
        XCTAssertEqual(decoded.rootViewAppearMs, 55.0)
        XCTAssertEqual(decoded.hostsLoadStartMs, 60.0)
        XCTAssertEqual(decoded.hostsLoadEndMs, 75.5)
        XCTAssertEqual(decoded.terminalViewInitCount, 2)
        XCTAssertEqual(decoded.terminalSessionControllerInitCount, 3)
        XCTAssertEqual(decoded.tipJarStartCount, 1)
        XCTAssertEqual(decoded.networkMonitorStartCount, 1)
    }

    func testDiagnosticsDisabledByDefault() {
        let env = ProcessInfo.processInfo.environment
        if env["MOSH_DIAGNOSTICS"] == "1" {
            unsetEnvironmentVariable("MOSH_DIAGNOSTICS")
        }

        let snapshot = StartupDiagnosticsSnapshot()
        XCTAssertNil(snapshot.appInitMs)
        XCTAssertEqual(snapshot.terminalViewInitCount, 0)
    }

    private func setEnvironmentVariable(_ name: String, value: String) {
        XCTAssertEqual(setenv(name, value, 1), 0)
    }

    private func unsetEnvironmentVariable(_ name: String) {
        XCTAssertEqual(unsetenv(name), 0)
    }
}
