import XCTest
@testable import MoshTerminal

final class RepositoryTests: XCTestCase {
    func testHostRepositoryUpsertDeleteReplace() throws {
        let store = JSONStore(fileURL: makeTempFileURL())
        let repo = HostRepository(store: store)

        let hostA = HostProfile(
            displayName: "Lab",
            hostname: "lab.example.com",
            username: "mosh",
            sshPort: 22,
            keyRefId: "key-1",
            lastConnectedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let hostB = HostProfile(
            displayName: "Prod",
            hostname: "prod.example.com",
            username: "mosh",
            sshPort: 2222,
            keyRefId: "key-2",
            lastConnectedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        try repo.upsert(hostA)
        try repo.upsert(hostB)
        XCTAssertEqual(try repo.all().count, 2)

        var updated = hostA
        updated.displayName = "Lab Updated"
        try repo.upsert(updated)
        let all = try repo.all()
        XCTAssertTrue(all.contains(where: { $0.displayName == "Lab Updated" }))

        try repo.delete(id: hostB.id)
        XCTAssertEqual(try repo.all().count, 1)

        try repo.replaceAll([hostB])
        let replaced = try repo.all()
        XCTAssertEqual(replaced, [hostB])
    }

    func testTrustedHostKeyRepositoryDeduplicatesAndSorts() throws {
        let store = JSONStore(fileURL: makeTempFileURL())
        let repo = TrustedHostKeyRepository(store: store)

        let keyA = TrustedHostKey(
            hostname: "alpha",
            port: 22,
            fingerprint: "SHA256:aaa",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let keyB = TrustedHostKey(
            hostname: "alpha",
            port: 22,
            fingerprint: "SHA256:bbb",
            addedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let keyC = TrustedHostKey(
            hostname: "beta",
            port: 22,
            fingerprint: "SHA256:ccc",
            addedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        try repo.upsert(keyB)
        try repo.upsert(keyA)
        try repo.upsert(keyC)
        try repo.upsert(keyA) // dedupe same fingerprint

        let all = try repo.all()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first?.hostname, "alpha")
        XCTAssertEqual(all.first?.fingerprint, "SHA256:aaa")

        let alphaKeys = try repo.keys(for: "alpha", port: 22)
        XCTAssertEqual(alphaKeys.count, 2)
    }

    private func makeTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return tempDir.appendingPathComponent("store.json")
    }
}
