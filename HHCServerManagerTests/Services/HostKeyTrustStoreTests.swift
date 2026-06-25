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

    private final class Harness {
        let repository: ServerRepository
        let store: HostKeyTrustStore
        let profile: ServerProfile
        let currentKey: HostKeyInfo

        init() throws {
            repository = ServerRepository(database: try AppDatabase.inMemory())
            store = HostKeyTrustStore(repository: repository)
            profile = ServerProfile(
                id: UUID(),
                name: "Test",
                host: "example.internal",
                port: 22,
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
