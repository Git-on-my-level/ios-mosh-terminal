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

        if let loadStart = latestSnapshot.hostsLoadStartMs, let loadEnd = latestSnapshot.hostsLoadEndMs {
            let loadTimeMs = loadEnd - loadStart
            XCTAssertLessThan(
                loadTimeMs,
                1500,
                "Hosts load time should be under 1500ms"
            )
        }
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

    func testNoTerminalInitOnColdLaunch() throws {
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

        var snapshot = try decodeDiagnosticsSnapshot(from: initialJSON)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let json = try? decodeDiagnosticsSnapshot(from: diagnosticsLabel.label.trimmingCharacters(in: .whitespacesAndNewlines)) {
                snapshot = json
                if snapshot.hostsLoadEndMs != nil && snapshot.rootViewAppearMs != nil {
                    break
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertEqual(snapshot.terminalViewInitCount, 0, "No TerminalView should be initialized on cold launch")
        XCTAssertEqual(snapshot.terminalSessionControllerInitCount, 0, "No TerminalSessionController should be initialized on cold launch")

        let seedHost1 = app.staticTexts["Seed Host 1"]
        XCTAssertTrue(
            seedHost1.waitForExistence(timeout: 5),
            "Expected seeded host 'Seed Host 1' to appear in the hosts list"
        )

        var firstHostRow = app.buttons["host.row.00000000-0000-0000-0000-000000000001"]
        if !firstHostRow.exists {
            firstHostRow = app.staticTexts["Seed Host 1"]
        }
        XCTAssertTrue(
            firstHostRow.waitForExistence(timeout: 5),
            "Expected first seeded host row to exist"
        )
        firstHostRow.tap()

        let afterNavigationDeadline = Date().addingTimeInterval(3)
        var snapshotAfterNavigation = snapshot
        while Date() < afterNavigationDeadline {
            if let json = try? decodeDiagnosticsSnapshot(from: diagnosticsLabel.label.trimmingCharacters(in: .whitespacesAndNewlines)) {
                snapshotAfterNavigation = json
                if snapshotAfterNavigation.terminalViewInitCount >= 1 || snapshotAfterNavigation.terminalSessionControllerInitCount >= 1 {
                    break
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertGreaterThanOrEqual(
            snapshotAfterNavigation.terminalViewInitCount,
            1,
            "TerminalView should be initialized after navigating to a host"
        )
        XCTAssertGreaterThanOrEqual(
            snapshotAfterNavigation.terminalSessionControllerInitCount,
            1,
            "TerminalSessionController should be initialized after navigating to a host"
        )
    }

    func testTipJarNotStartedOnColdLaunch() throws {
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

        var snapshot = try decodeDiagnosticsSnapshot(from: initialJSON)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let json = try? decodeDiagnosticsSnapshot(from: diagnosticsLabel.label.trimmingCharacters(in: .whitespacesAndNewlines)) {
                snapshot = json
                if snapshot.hostsLoadEndMs != nil && snapshot.rootViewAppearMs != nil {
                    break
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertEqual(
            snapshot.tipJarStartCount,
            0,
            "TipJar should not start on cold launch"
        )

        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(
            settingsTab.waitForExistence(timeout: 5),
            "Expected Settings tab to exist"
        )
        settingsTab.tap()

        let tipJarRow = app.staticTexts["Tip Jar"]
        XCTAssertTrue(
            tipJarRow.waitForExistence(timeout: 5),
            "Expected Tip Jar row to exist in Settings"
        )
        tipJarRow.tap()

        let afterTipJarDeadline = Date().addingTimeInterval(5)
        var snapshotAfterTipJar = snapshot
        while Date() < afterTipJarDeadline {
            if let json = try? decodeDiagnosticsSnapshot(from: diagnosticsLabel.label.trimmingCharacters(in: .whitespacesAndNewlines)) {
                snapshotAfterTipJar = json
                if snapshotAfterTipJar.tipJarStartCount >= 1 {
                    break
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertGreaterThanOrEqual(
            snapshotAfterTipJar.tipJarStartCount,
            1,
            "TipJar should start after opening Tip Jar"
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
