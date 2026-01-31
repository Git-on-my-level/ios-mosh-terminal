import XCTest
@testable import MoshTerminal

final class RepositoryTests: XCTestCase {
    func testHostRepositoryUpsertDeleteReplace() async throws {
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

        try await repo.upsert(hostA)
        try await repo.upsert(hostB)
        XCTAssertEqual(try await repo.all().count, 2)

        var updated = hostA
        updated.displayName = "Lab Updated"
        try await repo.upsert(updated)
        let all = try await repo.all()
        XCTAssertTrue(all.contains(where: { $0.displayName == "Lab Updated" }))

        try await repo.delete(id: hostB.id)
        XCTAssertEqual(try await repo.all().count, 1)

        try await repo.replaceAll([hostB])
        let replaced = try await repo.all()
        XCTAssertEqual(replaced, [hostB])
    }

    func testTrustedHostKeyRepositoryDeduplicatesAndSorts() async throws {
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

        try await repo.upsert(keyB)
        try await repo.upsert(keyA)
        try await repo.upsert(keyC)
        try await repo.upsert(keyA) // dedupe same fingerprint

        let all = try await repo.all()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first?.hostname, "alpha")
        XCTAssertEqual(all.first?.fingerprint, "SHA256:aaa")

        let alphaKeys = try await repo.keys(for: "alpha", port: 22)
        XCTAssertEqual(alphaKeys.count, 2)
    }

    func testConcurrentHostUpsertsPreserveBothChanges() async throws {
        let store = JSONStore(fileURL: makeTempFileURL())
        let repo = HostRepository(store: store)

        let hostA = HostProfile(
            displayName: "Alpha",
            hostname: "alpha.example.com",
            username: "mosh",
            sshPort: 22,
            keyRefId: "key-alpha",
            lastConnectedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let hostB = HostProfile(
            displayName: "Beta",
            hostname: "beta.example.com",
            username: "mosh",
            sshPort: 2222,
            keyRefId: "key-beta",
            lastConnectedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let errors = await withTaskGroup(of: Error?.self) { group in
            group.addTask {
                do {
                    try await repo.upsert(hostA)
                    return nil
                } catch {
                    return error
                }
            }
            group.addTask {
                do {
                    try await repo.upsert(hostB)
                    return nil
                } catch {
                    return error
                }
            }
            var results: [Error] = []
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            return results
        }

        XCTAssertTrue(errors.isEmpty)

        let all = try await repo.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(where: { $0.id == hostA.id }))
        XCTAssertTrue(all.contains(where: { $0.id == hostB.id }))
    }

    private func makeTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return tempDir.appendingPathComponent("store.json")
    }
}
