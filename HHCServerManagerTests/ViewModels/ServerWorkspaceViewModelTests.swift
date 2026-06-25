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
        try await runSmokeTest(profile: profile)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}
