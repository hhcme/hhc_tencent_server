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
        XCTAssertEqual(progress?.transferRateBytesPerSecond, 100 * 1_024)
        XCTAssertEqual(progress?.estimatedSecondsRemaining, 1)
    }

    func testRsyncProgressUpdateParsesHumanReadableSpeedAndETA() {
        let progress = OpenSSHClient.rsyncProgressUpdate(fromLine: "  1,048,576  25%    1.50MB/s    0:01:10")

        XCTAssertEqual(progress?.completedBytes, 1_048_576)
        XCTAssertEqual(progress?.fraction, 0.25)
        XCTAssertEqual(progress?.transferRateBytesPerSecond, 1.5 * 1_024 * 1_024)
        XCTAssertEqual(progress?.estimatedSecondsRemaining, 70)
        XCTAssertEqual(OpenSSHClient.parseRsyncTransferRate("900B/s"), 900)
        XCTAssertEqual(OpenSSHClient.parseRsyncTransferRate("2.00GB/s"), 2 * 1_024 * 1_024 * 1_024)
        XCTAssertNil(OpenSSHClient.parseRsyncTransferRate("not-a-rate"))
        XCTAssertNil(OpenSSHClient.parseRsyncETA("00:10"))
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

    func testSFTPBatchCommandsUseAppendModeWhenResuming() {
        let upload = OpenSSHClient.sftpBatchCommand(
            direction: .upload,
            localPath: "/Users/hhc/Downloads/app.tar.gz",
            remotePath: "/srv/app.tar.gz",
            resume: true
        )
        let download = OpenSSHClient.sftpBatchCommand(
            direction: .download,
            localPath: "/Users/hhc/Downloads/app.tar.gz",
            remotePath: "/srv/app.tar.gz",
            resume: true
        )

        XCTAssertEqual(upload, "put -a \"/Users/hhc/Downloads/app.tar.gz\" \"/srv/app.tar.gz\"\n")
        XCTAssertEqual(download, "get -a \"/srv/app.tar.gz\" \"/Users/hhc/Downloads/app.tar.gz\"\n")
    }

    func testSFTPResumeRequiresPositivePartialSmallerThanTotal() {
        XCTAssertTrue(OpenSSHClient.shouldResumeSFTPTransfer(partialByteCount: 512, totalByteCount: 1_024))
        XCTAssertFalse(OpenSSHClient.shouldResumeSFTPTransfer(partialByteCount: 0, totalByteCount: 1_024))
        XCTAssertFalse(OpenSSHClient.shouldResumeSFTPTransfer(partialByteCount: 1_024, totalByteCount: 1_024))
        XCTAssertFalse(OpenSSHClient.shouldResumeSFTPTransfer(partialByteCount: 2_048, totalByteCount: 1_024))
    }

    func testParseRemoteByteCountReadsWcOutput() {
        XCTAssertEqual(OpenSSHClient.parseRemoteByteCount("  4096\n"), 4_096)
        XCTAssertEqual(OpenSSHClient.parseRemoteByteCount("8192 /srv/app.tar.gz\n"), 8_192)
        XCTAssertNil(OpenSSHClient.parseRemoteByteCount(""))
        XCTAssertNil(OpenSSHClient.parseRemoteByteCount("not-a-size\n"))
    }

    func testRsyncTransferArgumentsUseAppendVerifyResumeMode() {
        let arguments = OpenSSHClient.rsyncTransferArguments(
            source: "/Users/hhc/Downloads/app.tar.gz",
            destination: "root@example.internal:/srv/app.tar.gz",
            sshCommand: "ssh -p 22"
        )

        XCTAssertEqual(arguments, [
            "--partial",
            "--append-verify",
            "--progress",
            "-e",
            "ssh -p 22",
            "/Users/hhc/Downloads/app.tar.gz",
            "root@example.internal:/srv/app.tar.gz",
        ])
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
