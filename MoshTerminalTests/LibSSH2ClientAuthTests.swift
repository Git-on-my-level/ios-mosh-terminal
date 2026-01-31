#if LIBSSH2_AVAILABLE
import XCTest
@testable import MoshTerminal

final class LibSSH2ClientAuthTests: XCTestCase {
    func testAuthenticateDoesNotFallbackToFileAuthOnFailure() throws {
        var memoryCallCount = 0
        var fileCallCount = 0
        let authFunctions = LibSSH2Client.AuthFunctions(
            userauthPublicKeyFromMemory: { _, _, _, _, _, _, _, _ in
                memoryCallCount += 1
                return -18
            },
            userauthPublicKeyFromFile: { _, _, _, _, _, _ in
                fileCallCount += 1
                return 0
            }
        )
        let session = OpaquePointer(bitPattern: 0x1)!
        let result = try LibSSH2Client.authenticate(
            session: session,
            username: "user",
            privateKey: Data("key".utf8),
            passphrase: nil,
            authFunctions: authFunctions
        )

        XCTAssertEqual(result, -18)
        XCTAssertEqual(memoryCallCount, 1)
        XCTAssertEqual(fileCallCount, 0)
    }
}
#endif
