import XCTest
@testable import MoshTerminal

final class JSONStoreTests: XCTestCase {
    func testRoundTripSaveLoad() async throws {
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
        try await store.save(state)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.schemaVersion, StoreState.currentSchemaVersion)
        XCTAssertEqual(loaded.hosts, [host])
        XCTAssertEqual(loaded.trustedHostKeys, [key])
    }

    func testUnsupportedSchemaVersionThrows() async throws {
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
        do {
            _ = try await store.load()
            XCTFail("Expected unsupported version error.")
        } catch {
            XCTAssertEqual(error as? StoreError, .unsupportedVersion(99))
        }
    }

    func testMigratesLegacySchemaVersion() async throws {
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
        let loaded = try await store.load()
        XCTAssertEqual(loaded.schemaVersion, StoreState.currentSchemaVersion)
        XCTAssertEqual(loaded.hosts.count, 0)
        XCTAssertEqual(loaded.trustedHostKeys.count, 0)
    }

    func testMigrationToSchemaV2SetsHostPersistenceDefaults() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = tempDir.appendingPathComponent("store.json")
        let json = """
        {
          \"schemaVersion\": 1,
          \"hosts\": [
            {
              \"id\": \"11111111-1111-1111-1111-111111111111\",
              \"displayName\": \"Legacy Host\",
              \"hostname\": \"legacy.example.com\",
              \"username\": \"legacy\",
              \"sshPort\": 22,
              \"keyRefId\": \"key-1\",
              \"lastConnectedAt\": \"2024-01-01T00:00:00Z\"
            }
          ],
          \"trustedHostKeys\": []
        }
        """
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try json.data(using: .utf8)?.write(to: fileURL, options: [.atomic])

        let store = JSONStore(fileURL: fileURL)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.hosts.count, 1)
        XCTAssertEqual(loaded.hosts.first?.sessionPersistenceMode, .managedTmux)
        XCTAssertEqual(loaded.hosts.first?.tmuxSetupConsent, .unknown)
    }
}
