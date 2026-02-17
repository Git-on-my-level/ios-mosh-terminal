import XCTest

final class MoshTerminalUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchEmitsStartupDiagnosticsJSON() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MOSH_DIAGNOSTICS"] = "1"
        app.launchEnvironment["MOSH_EPHEMERAL_STORE"] = "1"
        app.launchEnvironment["MOSH_SEED_HOSTS"] = "1"
        app.launch()

        let diagnosticsLabel = app.staticTexts["mosh.startup_diagnostics.json"]
        XCTAssertTrue(
            diagnosticsLabel.waitForExistence(timeout: 5),
            "Expected startup diagnostics accessibility element to appear"
        )

        let initialJSON = diagnosticsLabel.label.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(initialJSON.isEmpty, "Startup diagnostics JSON should not be empty")

        let initialSnapshot = try decodeDiagnosticsSnapshot(from: initialJSON)
        XCTAssertNotNil(initialSnapshot.rootViewAppearMs, "rootViewAppearMs should be present")
        XCTAssertGreaterThanOrEqual(initialSnapshot.terminalViewInitCount, 0)
        XCTAssertGreaterThanOrEqual(initialSnapshot.terminalSessionControllerInitCount, 0)
        XCTAssertGreaterThanOrEqual(initialSnapshot.tipJarStartCount, 0)
        XCTAssertGreaterThanOrEqual(initialSnapshot.networkMonitorStartCount, 0)

        let deadline = Date().addingTimeInterval(5)
        var latestSnapshot = initialSnapshot
        while Date() < deadline {
            let currentJSON = diagnosticsLabel.label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !currentJSON.isEmpty,
               let snapshot = try? decodeDiagnosticsSnapshot(from: currentJSON) {
                latestSnapshot = snapshot
                if snapshot.hostsLoadEndMs != nil {
                    break
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertNotNil(
            latestSnapshot.hostsLoadEndMs,
            "hostsLoadEndMs should become non-nil within timeout"
        )
    }

    func testSeededHostsAppearInHostsList() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MOSH_EPHEMERAL_STORE"] = "1"
        app.launchEnvironment["MOSH_SEED_HOSTS"] = "1"
        app.launch()

        let seedHost1 = app.staticTexts["Seed Host 1"]
        XCTAssertTrue(
            seedHost1.waitForExistence(timeout: 5),
            "Expected seeded host 'Seed Host 1' to appear in the hosts list"
        )
    }

    private func decodeDiagnosticsSnapshot(from json: String) throws -> StartupDiagnosticsSnapshotPayload {
        let data = Data(json.utf8)
        _ = try JSONSerialization.jsonObject(with: data)
        return try JSONDecoder().decode(StartupDiagnosticsSnapshotPayload.self, from: data)
    }
}

private struct StartupDiagnosticsSnapshotPayload: Decodable {
    let appInitMs: Double?
    let appEnvironmentInitStartMs: Double?
    let appEnvironmentInitEndMs: Double?
    let rootViewAppearMs: Double?
    let hostsLoadStartMs: Double?
    let hostsLoadEndMs: Double?

    let terminalViewInitCount: Int
    let terminalSessionControllerInitCount: Int
    let tipJarStartCount: Int
    let networkMonitorStartCount: Int
}
