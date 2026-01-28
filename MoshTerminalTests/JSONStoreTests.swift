import XCTest
@testable import MoshTerminal

final class JSONStoreTests: XCTestCase {
    func testRoundTripSaveLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("store.json")
        let store = JSONStore(fileURL: fileURL)

        let host = HostProfile(
            displayName: "Home Lab",
            hostname: "mosh.example.net",
            username: "mosh",
            sshPort: 22,
            keyRefId: "key-1",
            lastConnectedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let key = TrustedHostKey(
            hostname: "mosh.example.net",
            port: 22,
            fingerprint: "SHA256:abc123",
            addedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        var state = StoreState.empty()
        state.hosts = [host]
        state.trustedHostKeys = [key]
        try store.save(state)

        let loaded = try store.load()
        XCTAssertEqual(loaded.schemaVersion, StoreState.currentSchemaVersion)
        XCTAssertEqual(loaded.hosts, [host])
        XCTAssertEqual(loaded.trustedHostKeys, [key])
    }

    func testUnsupportedSchemaVersionThrows() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("store.json")
        let json = """
        {
          \"schemaVersion\": 99,
          \"hosts\": [],
          \"trustedHostKeys\": []
        }
        """
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try json.data(using: .utf8)?.write(to: fileURL, options: [.atomic])

        let store = JSONStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? StoreError, .unsupportedVersion(99))
        }
    }

    func testMigratesLegacySchemaVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("store.json")
        let json = """
        {
          \"schemaVersion\": 0,
          \"hosts\": [],
          \"trustedHostKeys\": []
        }
        """
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try json.data(using: .utf8)?.write(to: fileURL, options: [.atomic])

        let store = JSONStore(fileURL: fileURL)
        let loaded = try store.load()
        XCTAssertEqual(loaded.schemaVersion, StoreState.currentSchemaVersion)
        XCTAssertEqual(loaded.hosts.count, 0)
        XCTAssertEqual(loaded.trustedHostKeys.count, 0)
    }
}
