import XCTest
@testable import HHCServerManager

@MainActor
final class ServerWorkspaceViewModelTests: XCTestCase {
    func testConnectSuccessUpdatesConnectionStateAndStoresResult() async throws {
        let profile = makeProfile()
        let client = MockSSHClient(result: CommandResult(
            command: "printf hhc-ssh-ok",
            stdout: "hhc-ssh-ok",
            stderr: "",
            exitCode: 0,
            duration: 0.1
        ))
        let viewModel = ServerWorkspaceViewModel()

        viewModel.connect(profile: profile, sshClient: client)
        try await waitUntil { viewModel.isRunningSmokeTest == false }

        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertEqual(viewModel.commandResult?.stdout, "hhc-ssh-ok")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testConnectFailureUpdatesFailedState() async throws {
        let profile = makeProfile()
        let client = MockSSHClient(error: SSHClientError.processFailed("boom"))
        let viewModel = ServerWorkspaceViewModel()

        viewModel.connect(profile: profile, sshClient: client)
        try await waitUntil { viewModel.isRunningSmokeTest == false }

        XCTAssertEqual(viewModel.connectionState, .failed("boom"))
        XCTAssertEqual(viewModel.errorMessage, "boom")
    }

    func testUnknownHostKeyWaitsForTrustDecisionAndRejectDisconnects() async throws {
        let profile = makeProfile()
        let hostKey = HostKeyInfo(
            host: profile.host,
            port: profile.port,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:test",
            rawPublicKey: "\(profile.host) ssh-ed25519 AAAATEST"
        )
        let client = MockSSHClient(error: SSHClientError.unknownHostKey(hostKey))
        let viewModel = ServerWorkspaceViewModel()

        viewModel.connect(profile: profile, sshClient: client)
        try await waitUntil { viewModel.pendingHostKey != nil }

        XCTAssertEqual(viewModel.connectionState, .connecting)
        viewModel.rejectPendingHostKey()
        XCTAssertNil(viewModel.pendingHostKey)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
    }

    func testDisconnectClearsTransientErrorAndState() {
        let viewModel = ServerWorkspaceViewModel()
        viewModel.connectionState = .failed("bad")
        viewModel.errorMessage = "bad"

        viewModel.disconnect()

        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testExecuteCommandStoresResultInHistory() async throws {
        let profile = makeProfile()
        let client = MockSSHClient()
        let viewModel = ServerWorkspaceViewModel()

        viewModel.executeCommand("  uptime  ", profile: profile, sshClient: client)
        try await waitUntil { viewModel.isRunningCommand == false && viewModel.commandResult != nil }

        XCTAssertEqual(viewModel.commandResult?.command, "uptime")
        XCTAssertEqual(viewModel.commandResult?.stdout, "ran: uptime")
        XCTAssertEqual(viewModel.commandHistory.map(\.command), ["uptime"])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testExecuteCommandRejectsEmptyInput() {
        let profile = makeProfile()
        let client = MockSSHClient()
        let viewModel = ServerWorkspaceViewModel()

        viewModel.executeCommand("   ", profile: profile, sshClient: client)

        XCTAssertEqual(viewModel.errorMessage, "Command cannot be empty.")
        XCTAssertFalse(viewModel.isRunningCommand)
        XCTAssertNil(viewModel.commandResult)
        XCTAssertTrue(viewModel.commandHistory.isEmpty)
    }

    func testExecuteCommandFailureStoresFailureSummary() async throws {
        let profile = makeProfile()
        let client = MockSSHClient(error: SSHClientError.processFailed("exit 127: command not found"))
        let viewModel = ServerWorkspaceViewModel()

        viewModel.executeCommand("missing-tool", profile: profile, sshClient: client)
        try await waitUntil { viewModel.isRunningCommand == false && viewModel.lastCommandFailure != nil }

        XCTAssertEqual(viewModel.lastCommandFailure, CommandFailureSummary(
            command: "missing-tool",
            message: "exit 127: command not found"
        ))
        XCTAssertEqual(viewModel.errorMessage, "exit 127: command not found")
        XCTAssertNil(viewModel.commandResult)
    }

    func testRerunCommandExecutesPersistedHistoryEntry() async throws {
        let profile = makeProfile()
        let client = MockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let entry = CommandHistoryEntry(
            id: UUID(),
            serverId: profile.id,
            command: "df -h",
            exitCode: 0,
            duration: 0.1,
            createdAt: Date()
        )

        viewModel.rerunCommand(entry, profile: profile, sshClient: client)
        try await waitUntil { viewModel.isRunningCommand == false && viewModel.commandResult != nil }

        XCTAssertEqual(viewModel.commandResult?.command, "df -h")
        XCTAssertEqual(viewModel.commandResult?.stdout, "ran: df -h")
        XCTAssertEqual(viewModel.commandHistory.map(\.command), ["df -h"])
    }

    func testTrustPendingHostKeyResumesOriginalCommand() async throws {
        let profile = makeProfile()
        let hostKey = HostKeyInfo(
            host: profile.host,
            port: profile.port,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:test",
            rawPublicKey: "\(profile.host) ssh-ed25519 AAAATEST"
        )
        let client = TrustThenExecuteMockSSHClient(hostKey: hostKey)
        let viewModel = ServerWorkspaceViewModel()

        viewModel.executeCommand("whoami", profile: profile, sshClient: client)
        try await waitUntil { viewModel.pendingHostKey != nil }

        viewModel.trustPendingHostKey(profile: profile, sshClient: client)
        try await waitUntil { viewModel.isRunningCommand == false && viewModel.commandResult != nil }

        XCTAssertEqual(viewModel.commandResult?.command, "whoami")
        XCTAssertEqual(viewModel.commandResult?.stdout, "ran after trust: whoami")
        XCTAssertTrue(client.didTrustHostKey)
    }

    func testExecuteCommandPersistsHistoryAndOperationLog() async throws {
        let profile = makeProfile()
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        try repository.upsert(profile)
        let client = MockSSHClient()
        let viewModel = ServerWorkspaceViewModel()

        viewModel.executeCommand("whoami", profile: profile, sshClient: client, repository: repository)
        try await waitUntil { viewModel.isRunningCommand == false && !viewModel.persistedCommandHistory.isEmpty }

        let persistedHistory = try repository.fetchCommandHistory(serverId: profile.id)
        XCTAssertEqual(persistedHistory.map(\.command), ["whoami"])
        XCTAssertEqual(persistedHistory[0].exitCode, 0)
        XCTAssertEqual(viewModel.persistedCommandHistory.map(\.command), ["whoami"])

        let logs = try repository.fetchOperationLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].scope, "ssh")
        XCTAssertEqual(logs[0].action, "execute_command")
        XCTAssertEqual(logs[0].status, "success")
        XCTAssertEqual(logs[0].targetId, profile.id.uuidString)
    }

    func testLoadCommandHistoryReadsPersistedEntries() throws {
        let profile = makeProfile()
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        try repository.upsert(profile)
        try repository.saveCommandHistory(CommandHistoryEntry(
            id: UUID(),
            serverId: profile.id,
            command: "uptime",
            exitCode: 0,
            duration: 0.5,
            createdAt: Date()
        ))
        let viewModel = ServerWorkspaceViewModel()

        viewModel.loadCommandHistory(profile: profile, repository: repository)

        XCTAssertEqual(viewModel.persistedCommandHistory.map(\.command), ["uptime"])
    }

    private func makeProfile() -> ServerProfile {
        ServerProfile(
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
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition.")
    }
}

private final class MockSSHClient: SSHClient, @unchecked Sendable {
    private let result: CommandResult?
    private let error: Error?

    init(result: CommandResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        if let error {
            throw error
        }
        return result ?? CommandResult(
            command: "printf hhc-ssh-ok",
            stdout: "hhc-ssh-ok",
            stderr: "",
            exitCode: 0,
            duration: 0
        )
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        if let error {
            throw error
        }
        return result ?? CommandResult(
            command: command,
            stdout: "ran: \(command)",
            stderr: "",
            exitCode: 0,
            duration: 0
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class TrustThenExecuteMockSSHClient: SSHClient, @unchecked Sendable {
    private let hostKey: HostKeyInfo
    private var shouldThrowHostKey = true
    private(set) var didTrustHostKey = false

    init(hostKey: HostKeyInfo) {
        self.hostKey = hostKey
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        if shouldThrowHostKey {
            throw SSHClientError.unknownHostKey(hostKey)
        }
        return CommandResult(
            command: command,
            stdout: "ran after trust: \(command)",
            stderr: "",
            exitCode: 0,
            duration: 0
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {
        didTrustHostKey = true
        shouldThrowHostKey = false
    }
}
