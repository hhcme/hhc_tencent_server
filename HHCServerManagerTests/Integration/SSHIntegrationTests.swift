import XCTest
@testable import HHCServerManager

final class SSHIntegrationTests: XCTestCase {
    func testRealPrivateKeySmokeTestWhenEnvironmentIsConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let host = environment["HHC_TEST_SSH_HOST"], !host.isEmpty,
            let user = environment["HHC_TEST_SSH_USER"], !user.isEmpty,
            let privateKeyPath = environment["HHC_TEST_SSH_PRIVATE_KEY"], !privateKeyPath.isEmpty
        else {
            throw XCTSkip("Set HHC_TEST_SSH_HOST, HHC_TEST_SSH_USER, and HHC_TEST_SSH_PRIVATE_KEY to run the real SSH integration test.")
        }

        let port = Int(environment["HHC_TEST_SSH_PORT"] ?? "22") ?? 22
        let keyData = try Data(contentsOf: URL(fileURLWithPath: privateKeyPath))
        let database = try AppDatabase.inMemory()
        let repository = ServerRepository(database: database)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.integration.\(UUID().uuidString)")
        let service = ServerManagementService(repository: repository, keychain: keychain)
        let profile = try service.createServer(
            name: "Integration",
            host: host,
            port: port,
            username: user,
            groupName: nil,
            authType: .privateKey,
            credential: .privateKey(data: keyData, passphrase: environment["HHC_TEST_SSH_PASSPHRASE"])
        )
        defer {
            try? service.deleteServer(profile)
        }

        let sshClient = OpenSSHClient(repository: repository, keychain: keychain)
        do {
            _ = try await sshClient.runSmokeTest(profile: profile)
            XCTFail("First connection should request host-key trust.")
        } catch SSHClientError.unknownHostKey(let hostKey) {
            try sshClient.trustHostKey(hostKey, for: profile)
        }

        let result = try await sshClient.runSmokeTest(profile: profile)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hhc-ssh-ok")
    }
}
