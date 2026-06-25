import XCTest
@testable import HHCServerManager

final class OpenSSHClientTests: XCTestCase {
    func testPrivateKeyAuthWithoutPassphraseUsesBatchMode() throws {
        let harness = try AuthHarness()
        try harness.keychain.savePrivateKey(Data("private-key-data".utf8), passphrase: nil, keychainRef: harness.profile.keychainRef)

        let context = try harness.client.makeAuthContext(
            profile: harness.profile,
            knownHostsURL: harness.knownHostsURL,
            portFlag: "-p"
        )
        defer { context.cleanup() }

        XCTAssertTrue(context.arguments.contains("-o"))
        XCTAssertTrue(context.arguments.contains("BatchMode=yes"))
        XCTAssertTrue(context.arguments.contains("IdentitiesOnly=yes"))
        XCTAssertTrue(context.arguments.contains("-i"))
        XCTAssertNil(context.environment["SSH_ASKPASS"])
        XCTAssertNil(context.environment["HHC_SSH_PASSWORD"])
    }

    func testPrivateKeyAuthWithPassphraseUsesAskpassAndDisablesPasswordFallback() throws {
        let harness = try AuthHarness()
        try harness.keychain.savePrivateKey(
            Data("private-key-data".utf8),
            passphrase: "secret-passphrase",
            keychainRef: harness.profile.keychainRef
        )

        let context = try harness.client.makeAuthContext(
            profile: harness.profile,
            knownHostsURL: harness.knownHostsURL,
            portFlag: "-p"
        )
        defer { context.cleanup() }

        XCTAssertTrue(context.arguments.contains("BatchMode=no"))
        XCTAssertTrue(context.arguments.contains("PreferredAuthentications=publickey"))
        XCTAssertTrue(context.arguments.contains("PasswordAuthentication=no"))
        XCTAssertTrue(context.arguments.contains("KbdInteractiveAuthentication=no"))
        XCTAssertTrue(context.arguments.contains("IdentitiesOnly=yes"))
        XCTAssertNotNil(context.environment["SSH_ASKPASS"])
        XCTAssertEqual(context.environment["SSH_ASKPASS_REQUIRE"], "force")
        XCTAssertEqual(context.environment["HHC_SSH_PASSWORD"], "secret-passphrase")
        XCTAssertEqual(context.environment["DISPLAY"], "localhost:0")
    }

    func testRsyncProgressUpdateParsesByteCountAndPercent() {
        let progress = OpenSSHClient.rsyncProgressUpdate(fromLine: "      1,024  50%  100.00kB/s    0:00:01")

        XCTAssertEqual(progress?.completedBytes, 1_024)
        XCTAssertEqual(progress?.totalBytes, 2_048)
        XCTAssertEqual(progress?.fraction, 0.5)
    }

    func testRsyncProgressUpdatesParseCarriageReturnDelimitedOutput() {
        let output = "\r          512  25%   50.00kB/s    0:00:03\r        2,048 100%  100.00kB/s    0:00:00\n"

        let progress = OpenSSHClient.rsyncProgressUpdates(from: output)

        XCTAssertEqual(progress.map(\.completedBytes), [512, 2_048])
        XCTAssertEqual(progress.map(\.fraction), [0.25, 1])
    }

    func testRsyncProgressUpdateIgnoresNonProgressLines() {
        XCTAssertNil(OpenSSHClient.rsyncProgressUpdate(fromLine: "sending incremental file list"))
        XCTAssertNil(OpenSSHClient.rsyncProgressUpdate(fromLine: "large.log"))
    }

    func testSFTPBatchCommandsQuoteLocalAndRemotePaths() {
        let upload = OpenSSHClient.sftpBatchCommand(
            direction: .upload,
            localPath: "/Users/hhc/Downloads/app config \"prod\".json",
            remotePath: "/srv/app/app config \"prod\".json"
        )
        let download = OpenSSHClient.sftpBatchCommand(
            direction: .download,
            localPath: "/Users/hhc/Downloads/app config.json",
            remotePath: "/srv/app/app config.json"
        )

        XCTAssertEqual(upload, "put \"/Users/hhc/Downloads/app config \\\"prod\\\".json\" \"/srv/app/app config \\\"prod\\\".json\"\n")
        XCTAssertEqual(download, "get \"/srv/app/app config.json\" \"/Users/hhc/Downloads/app config.json\"\n")
    }

    func testSSHConfigValueEscapesSpacesAndBackslashes() {
        XCTAssertEqual(
            OpenSSHClient.sshConfigValue("/Users/hhc/Library/Application Support/HHCServerManager/known_hosts"),
            "/Users/hhc/Library/Application\\ Support/HHCServerManager/known_hosts"
        )
        XCTAssertEqual(
            OpenSSHClient.sshConfigValue("/tmp/hhc\\known hosts"),
            "/tmp/hhc\\\\known\\ hosts"
        )
    }

    private final class AuthHarness {
        let repository: ServerRepository
        let keychain: KeychainService
        let client: OpenSSHClient
        let profile: ServerProfile
        let knownHostsURL: URL

        init() throws {
            repository = ServerRepository(database: try AppDatabase.inMemory())
            keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.openssh.tests.\(UUID().uuidString)")
            client = OpenSSHClient(repository: repository, keychain: keychain)
            profile = ServerProfile(
                id: UUID(),
                name: "Test",
                host: "example.internal",
                port: 22,
                username: "root",
                authType: .privateKey,
                keychainRef: "server_\(UUID().uuidString)",
                groupName: nil,
                createdAt: Date(),
                updatedAt: Date()
            )
            knownHostsURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("hhc-known-hosts-\(UUID().uuidString)")
        }

        deinit {
            keychain.deleteCredentials(keychainRef: profile.keychainRef)
            try? FileManager.default.removeItem(at: knownHostsURL)
        }
    }
}
