import XCTest
@testable import HHCServerManager

final class HostKeyTrustStoreTests: XCTestCase {
    func testUnknownHostKeyRequiresTrustDecision() throws {
        let harness = try Harness()
        let evaluation = try harness.store.evaluate(harness.currentKey, for: harness.profile)

        XCTAssertEqual(evaluation, .unknown(harness.currentKey))
    }

    func testTrustedHostKeyMatchesAfterTrust() throws {
        let harness = try Harness()
        try harness.store.trust(harness.currentKey, for: harness.profile)

        let evaluation = try harness.store.evaluate(harness.currentKey, for: harness.profile)

        XCTAssertEqual(evaluation, .trusted)
    }

    func testChangedHostKeyBlocksWhenAlgorithmMatchesButFingerprintDiffers() throws {
        let harness = try Harness()
        try harness.store.trust(harness.currentKey, for: harness.profile)
        let changed = HostKeyInfo(
            host: harness.profile.host,
            port: harness.profile.port,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:changed",
            rawPublicKey: "\(harness.profile.host) ssh-ed25519 BBBB"
        )

        let evaluation = try harness.store.evaluate(changed, for: harness.profile)

        guard case let .changed(current, trusted) = evaluation else {
            return XCTFail("Expected changed evaluation.")
        }
        XCTAssertEqual(current, changed)
        XCTAssertEqual(trusted.fingerprintSHA256, harness.currentKey.fingerprintSHA256)
    }

    func testImportsMatchingKnownHostsLineAndTrustsProfile() throws {
        let harness = try Harness()
        let key = Self.publicKey([1, 2, 3, 4])
        let result = try harness.store.importKnownHosts(
            """
            # Existing user known_hosts entry
            other.internal ssh-ed25519 \(Self.publicKey([9, 9, 9]))
            example.internal ssh-ed25519 \(key) imported-comment
            """,
            for: harness.profile
        )

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.skippedCount, 2)
        XCTAssertEqual(try harness.store.evaluate(Self.hostKey(profile: harness.profile, publicKey: key), for: harness.profile), .trusted)
    }

    func testImportsBracketedKnownHostsEntryForNonDefaultPort() throws {
        let harness = try Harness(port: 2222)
        let key = Self.publicKey([5, 6, 7, 8])
        let result = try harness.store.importKnownHosts(
            "[example.internal]:2222 ssh-ed25519 \(key)",
            for: harness.profile
        )

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(try harness.store.evaluate(Self.hostKey(profile: harness.profile, publicKey: key), for: harness.profile), .trusted)
    }

    func testKnownHostsImportSkipsHashedMarkerAndInvalidLines() throws {
        let harness = try Harness()
        let result = try harness.store.importKnownHosts(
            """
            |1|hashed|entry ssh-ed25519 \(Self.publicKey([1]))
            @cert-authority *.internal ssh-ed25519 \(Self.publicKey([2]))
            example.internal ssh-ed25519 not-base64
            """,
            for: harness.profile
        )

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.skippedCount, 3)
        XCTAssertTrue(try harness.repository.fetchTrustedHostKeys(serverId: harness.profile.id).isEmpty)
    }

    private static func hostKey(profile: ServerProfile, publicKey: String) -> HostKeyInfo {
        let hostPattern = profile.port == 22 ? profile.host : "[\(profile.host)]:\(profile.port)"
        let line = "\(hostPattern) ssh-ed25519 \(publicKey)"
        return HostKeyTrustStore.hostKeyInfo(fromKnownHostsLine: line, matching: profile)!
    }

    private static func publicKey(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
    }

    private final class Harness {
        let repository: ServerRepository
        let store: HostKeyTrustStore
        let profile: ServerProfile
        let currentKey: HostKeyInfo

        init(port: Int = 22) throws {
            repository = ServerRepository(database: try AppDatabase.inMemory())
            store = HostKeyTrustStore(repository: repository)
            profile = ServerProfile(
                id: UUID(),
                name: "Test",
                host: "example.internal",
                port: port,
                username: "root",
                authType: .privateKey,
                keychainRef: "server_test",
                groupName: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            try repository.upsert(profile)
            currentKey = HostKeyInfo(
                host: profile.host,
                port: profile.port,
                algorithm: "ssh-ed25519",
                fingerprintSHA256: "SHA256:current",
                rawPublicKey: "\(profile.host) ssh-ed25519 AAAA"
            )
        }
    }
}
