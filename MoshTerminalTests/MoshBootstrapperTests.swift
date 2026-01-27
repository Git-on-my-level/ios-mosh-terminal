import XCTest
@testable import MoshTerminal

final class MoshBootstrapperTests: XCTestCase {
    func testParsesConnectInfoFromStdout() throws {
        let result = SSHCommandResult(
            stdout: "MOSH CONNECT 60001 abcDEF+/=\n",
            stderr: "",
            exitStatus: 0
        )

        let info = try MoshBootstrapper.parseConnectInfo(from: result, serverAddress: "example.com")

        XCTAssertEqual(info.udpPort, 60001)
        XCTAssertEqual(info.sessionKey, "abcDEF+/=")
        XCTAssertEqual(info.serverAddress, "example.com")
    }

    func testParsesConnectInfoFromMixedOutput() throws {
        let result = SSHCommandResult(
            stdout: "Some banner\nMOSH CONNECT 60002 key123=\nMore text",
            stderr: "",
            exitStatus: 0
        )

        let info = try MoshBootstrapper.parseConnectInfo(from: result, serverAddress: "host")

        XCTAssertEqual(info.udpPort, 60002)
        XCTAssertEqual(info.sessionKey, "key123=")
    }

    func testDetectsMissingMoshServer() {
        let result = SSHCommandResult(
            stdout: "",
            stderr: "mosh-server: command not found",
            exitStatus: 127
        )

        XCTAssertThrowsError(try MoshBootstrapper.parseConnectInfo(from: result, serverAddress: "host")) { error in
            XCTAssertEqual(error as? MoshBootstrapError, .moshServerMissing)
        }
    }

    func testDetectsNonUtf8LocaleError() {
        let result = SSHCommandResult(
            stdout: "",
            stderr: "mosh-server needs a UTF-8 locale",
            exitStatus: 1
        )

        XCTAssertThrowsError(try MoshBootstrapper.parseConnectInfo(from: result, serverAddress: "host")) { error in
            XCTAssertEqual(error as? MoshBootstrapError, .nonUtf8Locale)
        }
    }

    func testReportsUnexpectedOutput() {
        let result = SSHCommandResult(
            stdout: "unexpected",
            stderr: "",
            exitStatus: 1
        )

        XCTAssertThrowsError(try MoshBootstrapper.parseConnectInfo(from: result, serverAddress: "host")) { error in
            if case .unexpectedOutput = error as? MoshBootstrapError {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected unexpectedOutput error")
            }
        }
    }
}
