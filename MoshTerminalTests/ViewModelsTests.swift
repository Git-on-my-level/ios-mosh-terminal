import XCTest
@testable import MoshTerminal

final class ViewModelsTests: XCTestCase {
    func testHostsListViewModelLoadHostsSortsByDisplayNameThenHostnameThenUsername() async {
        let mockRepo = MockHostRepository()
        mockRepo.hosts = [
            HostProfile(
                displayName: "Charlie",
                hostname: "host1.example.com",
                username: "user2",
                sshPort: 22,
                keyRefId: "key-1",
                lastConnectedAt: nil
            ),
            HostProfile(
                displayName: "alpha",
                hostname: "host2.example.com",
                username: "user1",
                sshPort: 22,
                keyRefId: "key-2",
                lastConnectedAt: nil
            ),
            HostProfile(
                displayName: "Alpha",
                hostname: "host1.example.com",
                username: "user1",
                sshPort: 22,
                keyRefId: "key-3",
                lastConnectedAt: nil
            ),
            HostProfile(
                displayName: "Alpha",
                hostname: "host2.example.com",
                username: "user1",
                sshPort: 22,
                keyRefId: "key-4",
                lastConnectedAt: nil
            ),
            HostProfile(
                displayName: "Alpha",
                hostname: "host1.example.com",
                username: "user2",
                sshPort: 22,
                keyRefId: "key-5",
                lastConnectedAt: nil
            )
        ]

        let viewModel = HostsListViewModel(hostRepository: mockRepo)
        await viewModel.loadHosts()

        XCTAssertEqual(viewModel.hosts.count, 5)
        XCTAssertEqual(viewModel.hosts[0].displayName, "Alpha")
        XCTAssertEqual(viewModel.hosts[0].hostname, "host1.example.com")
        XCTAssertEqual(viewModel.hosts[0].username, "user1")

        XCTAssertEqual(viewModel.hosts[1].displayName, "Alpha")
        XCTAssertEqual(viewModel.hosts[1].hostname, "host1.example.com")
        XCTAssertEqual(viewModel.hosts[1].username, "user2")

        XCTAssertEqual(viewModel.hosts[2].displayName, "Alpha")
        XCTAssertEqual(viewModel.hosts[2].hostname, "host2.example.com")
        XCTAssertEqual(viewModel.hosts[2].username, "user1")

        XCTAssertEqual(viewModel.hosts[3].displayName, "alpha")
        XCTAssertEqual(viewModel.hosts[3].hostname, "host2.example.com")
        XCTAssertEqual(viewModel.hosts[3].username, "user1")

        XCTAssertEqual(viewModel.hosts[4].displayName, "Charlie")
        XCTAssertEqual(viewModel.hosts[4].hostname, "host1.example.com")
        XCTAssertEqual(viewModel.hosts[4].username, "user2")
    }

    func testKeyManagementViewModelDeleteKeysBlocksWhenReferencedByHost() async {
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false),
            StoredPrivateKeyMetadata(id: "key-2", label: "Key 2", keyType: .rsa, requiresPassphrase: true)
        ]

        let mockHostRepo = MockHostRepository()
        mockHostRepo.hosts = [
            HostProfile(
                displayName: "Host 1",
                hostname: "host1.example.com",
                username: "user1",
                sshPort: 22,
                keyRefId: "key-1",
                lastConnectedAt: nil
            )
        ]

        let viewModel = KeyManagementViewModel(store: mockKeyStore, hostRepository: mockHostRepo)
        viewModel.loadKeys()

        let key1Index = viewModel.keys.firstIndex { $0.id == "key-1" }
        XCTAssertNotNil(key1Index)

        await viewModel.deleteKeys(at: IndexSet(integer: key1Index!))

        XCTAssertNotNil(viewModel.alertMessage)
        XCTAssertTrue(viewModel.alertMessage?.contains("Host 1") ?? false)
        XCTAssertTrue(viewModel.alertMessage?.contains("assigned") ?? false)
        XCTAssertEqual(mockKeyStore.keys.count, 2)
    }

    func testKeyManagementViewModelDeleteKeysBlocksWhenMultipleKeysReferencedByHost() async {
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false),
            StoredPrivateKeyMetadata(id: "key-2", label: "Key 2", keyType: .rsa, requiresPassphrase: true)
        ]

        let mockHostRepo = MockHostRepository()
        mockHostRepo.hosts = [
            HostProfile(
                displayName: "Host 1",
                hostname: "host1.example.com",
                username: "user1",
                sshPort: 22,
                keyRefId: "key-1",
                lastConnectedAt: nil
            ),
            HostProfile(
                displayName: "Host 2",
                hostname: "host2.example.com",
                username: "user2",
                sshPort: 22,
                keyRefId: "key-2",
                lastConnectedAt: nil
            )
        ]

        let viewModel = KeyManagementViewModel(store: mockKeyStore, hostRepository: mockHostRepo)
        viewModel.loadKeys()

        await viewModel.deleteKeys(at: IndexSet([0, 1]))

        XCTAssertNotNil(viewModel.alertMessage)
        XCTAssertTrue(viewModel.alertMessage?.contains("Host 1") ?? false)
        XCTAssertTrue(viewModel.alertMessage?.contains("Host 2") ?? false)
        XCTAssertTrue(viewModel.alertMessage?.contains("assigned") ?? false)
        XCTAssertEqual(mockKeyStore.keys.count, 2)
    }

    func testKeyManagementViewModelDeleteKeysSucceedsWhenNotReferenced() async {
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false),
            StoredPrivateKeyMetadata(id: "key-2", label: "Key 2", keyType: .rsa, requiresPassphrase: true)
        ]

        let mockHostRepo = MockHostRepository()
        mockHostRepo.hosts = [
            HostProfile(
                displayName: "Host 1",
                hostname: "host1.example.com",
                username: "user1",
                sshPort: 22,
                keyRefId: "other-key",
                lastConnectedAt: nil
            )
        ]

        let viewModel = KeyManagementViewModel(store: mockKeyStore, hostRepository: mockHostRepo)
        viewModel.loadKeys()

        XCTAssertEqual(viewModel.keys.count, 2)

        await viewModel.deleteKeys(at: IndexSet(integer: 0))

        XCTAssertNil(viewModel.alertMessage)
        XCTAssertEqual(mockKeyStore.keys.count, 1)
        XCTAssertEqual(mockKeyStore.keys[0].id, "key-2")
    }

    func testHostEditorViewModelValidationEmptyHostnameFails() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = ""
        viewModel.username = "testuser"
        viewModel.sshPortText = "22"
        viewModel.selectedKeyId = "key-1"
        viewModel.hasAttemptedSave = true

        let result = viewModel.validate()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.hostnameError, "Hostname is required")
        XCTAssertTrue(result.validationErrors.contains("Hostname is required."))
    }

    func testHostEditorViewModelValidationWhitespaceHostnameFails() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = "   "
        viewModel.username = "testuser"
        viewModel.sshPortText = "22"
        viewModel.selectedKeyId = "key-1"
        viewModel.hasAttemptedSave = true

        let result = viewModel.validate()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.hostnameError, "Hostname is required")
        XCTAssertTrue(result.validationErrors.contains("Hostname is required."))
    }

    func testHostEditorViewModelValidationEmptyUsernameFails() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = "example.com"
        viewModel.username = ""
        viewModel.sshPortText = "22"
        viewModel.selectedKeyId = "key-1"
        viewModel.hasAttemptedSave = true

        let result = viewModel.validate()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.usernameError, "Username is required")
        XCTAssertTrue(result.validationErrors.contains("Username is required."))
    }

    func testHostEditorViewModelValidationWhitespaceUsernameFails() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = "example.com"
        viewModel.username = "\n\t"
        viewModel.sshPortText = "22"
        viewModel.selectedKeyId = "key-1"
        viewModel.hasAttemptedSave = true

        let result = viewModel.validate()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.usernameError, "Username is required")
        XCTAssertTrue(result.validationErrors.contains("Username is required."))
    }

    func testHostEditorViewModelValidationPortOutOfRangeFails() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = "example.com"
        viewModel.username = "testuser"
        viewModel.sshPortText = "0"
        viewModel.selectedKeyId = "key-1"
        viewModel.hasAttemptedSave = true

        let result = viewModel.validate()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.portError, "Port must be 1-65535")
        XCTAssertTrue(result.validationErrors.contains("SSH port must be between 1 and 65535."))
    }

    func testHostEditorViewModelValidationPortOverMaxFails() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = "example.com"
        viewModel.username = "testuser"
        viewModel.sshPortText = "65536"
        viewModel.selectedKeyId = "key-1"
        viewModel.hasAttemptedSave = true

        let result = viewModel.validate()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.portError, "Port must be 1-65535")
        XCTAssertTrue(result.validationErrors.contains("SSH port must be between 1 and 65535."))
    }

    func testHostEditorViewModelValidationPortNonNumericFails() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = "example.com"
        viewModel.username = "testuser"
        viewModel.sshPortText = "abc"
        viewModel.selectedKeyId = "key-1"
        viewModel.hasAttemptedSave = true

        let result = viewModel.validate()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.portError, "Port must be 1-65535")
        XCTAssertTrue(result.validationErrors.contains("SSH port must be between 1 and 65535."))
    }

    func testHostEditorViewModelValidationMissingKeyFails() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = []

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = "example.com"
        viewModel.username = "testuser"
        viewModel.sshPortText = "22"
        viewModel.selectedKeyId = nil
        viewModel.hasAttemptedSave = true

        let result = viewModel.validate()
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.keyError, "SSH key is required")
        XCTAssertTrue(result.validationErrors.contains("An SSH key is required."))
    }

    func testHostEditorViewModelValidationValidFormSucceeds() async {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.displayName = " Test Host "
        viewModel.hostname = " example.com "
        viewModel.username = " testuser "
        viewModel.sshPortText = " 22 "
        viewModel.selectedKeyId = "key-1"

        let result = viewModel.validate()
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.displayName, "Test Host")
        XCTAssertEqual(result.hostname, "example.com")
        XCTAssertEqual(result.username, "testuser")
        XCTAssertEqual(result.sshPort, 22)
        XCTAssertEqual(result.keyRefId, "key-1")
        XCTAssertEqual(viewModel.isFormValid, true)

        var savedHost: HostProfile?
        await viewModel.save { host in
            savedHost = host
        }

        XCTAssertNotNil(savedHost)
        XCTAssertEqual(savedHost?.displayName, "Test Host")
        XCTAssertEqual(savedHost?.hostname, "example.com")
        XCTAssertEqual(savedHost?.username, "testuser")
        XCTAssertEqual(savedHost?.sshPort, 22)
        XCTAssertEqual(savedHost?.keyRefId, "key-1")
    }

    func testHostEditorViewModelInlineErrorsNotShownBeforeSaveAttempt() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = ""
        viewModel.username = ""
        viewModel.sshPortText = ""
        viewModel.selectedKeyId = nil
        viewModel.hasAttemptedSave = false

        XCTAssertNil(viewModel.hostnameError)
        XCTAssertNil(viewModel.usernameError)
        XCTAssertNil(viewModel.portError)
        XCTAssertNil(viewModel.keyError)
    }

    func testHostEditorViewModelInlineErrorsShownAfterSaveAttempt() {
        let mockRepo = MockHostRepository()
        let mockKeyStore = MockPrivateKeyStore()
        mockKeyStore.keys = [
            StoredPrivateKeyMetadata(id: "key-1", label: "Key 1", keyType: .ed25519, requiresPassphrase: false)
        ]

        let viewModel = HostEditorViewModel(
            hostRepository: mockRepo,
            keyStore: mockKeyStore
        )
        viewModel.hostname = ""
        viewModel.username = ""
        viewModel.sshPortText = ""
        viewModel.selectedKeyId = nil
        viewModel.hasAttemptedSave = true

        XCTAssertNotNil(viewModel.hostnameError)
        XCTAssertNotNil(viewModel.usernameError)
        XCTAssertNotNil(viewModel.portError)
        XCTAssertNotNil(viewModel.keyError)
        XCTAssertEqual(viewModel.hostnameError, "Hostname is required")
        XCTAssertEqual(viewModel.usernameError, "Username is required")
        XCTAssertEqual(viewModel.portError, "Port must be 1-65535")
        XCTAssertEqual(viewModel.keyError, "SSH key is required")
    }
}
