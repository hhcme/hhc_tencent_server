import Foundation

@MainActor
final class ServerWorkspaceViewModel: ObservableObject {
    @Published var isRunningSmokeTest = false
    @Published var isRunningCommand = false
    @Published var connectionState: SSHConnectionState = .disconnected
    @Published var commandResult: CommandResult?
    @Published var commandHistory: [CommandResult] = []
    @Published var errorMessage: String?
    @Published var pendingHostKey: HostKeyInfo?
    private var pendingHostKeyAction: PendingHostKeyAction?

    func configure(initialState: SSHConnectionState) {
        connectionState = initialState
    }

    func connect(profile: ServerProfile, sshClient: SSHClient) {
        connectionState = .connecting
        runSmokeTest(profile: profile, sshClient: sshClient, action: .connect)
    }

    func disconnect() {
        connectionState = .disconnected
        errorMessage = nil
    }

    func runSmokeTest(profile: ServerProfile, sshClient: SSHClient) {
        runSmokeTest(profile: profile, sshClient: sshClient, action: .smokeTest)
    }

    private func runSmokeTest(
        profile: ServerProfile,
        sshClient: SSHClient,
        action: PendingHostKeyAction
    ) {
        isRunningSmokeTest = true
        errorMessage = nil
        commandResult = nil

        Task {
            do {
                let result = try await sshClient.runSmokeTest(profile: profile)
                await MainActor.run {
                    self.storeCommandResult(result)
                    if action == .connect {
                        self.connectionState = result.exitCode == 0 ? .connected : .failed("Smoke test exited with \(result.exitCode).")
                    }
                    self.isRunningSmokeTest = false
                }
            } catch SSHClientError.unknownHostKey(let hostKeyInfo) {
                await MainActor.run {
                    self.pendingHostKey = hostKeyInfo
                    self.pendingHostKeyAction = action
                    self.isRunningSmokeTest = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    if action == .connect {
                        self.connectionState = .failed(error.localizedDescription)
                    }
                    self.isRunningSmokeTest = false
                }
            }
        }
    }

    func executeCommand(_ command: String, profile: ServerProfile, sshClient: SSHClient) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            errorMessage = "Command cannot be empty."
            return
        }

        isRunningCommand = true
        errorMessage = nil
        commandResult = nil

        Task {
            do {
                let result = try await sshClient.execute(trimmedCommand, profile: profile)
                await MainActor.run {
                    self.storeCommandResult(result)
                    self.isRunningCommand = false
                }
            } catch SSHClientError.unknownHostKey(let hostKeyInfo) {
                await MainActor.run {
                    self.pendingHostKey = hostKeyInfo
                    self.pendingHostKeyAction = .command(trimmedCommand)
                    self.isRunningCommand = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isRunningCommand = false
                }
            }
        }
    }

    func trustPendingHostKey(profile: ServerProfile, sshClient: SSHClient) {
        guard let pendingHostKey else { return }
        do {
            try sshClient.trustHostKey(pendingHostKey, for: profile)
            let action = pendingHostKeyAction ?? .connect
            self.pendingHostKey = nil
            pendingHostKeyAction = nil
            switch action {
            case .connect:
                connect(profile: profile, sshClient: sshClient)
            case .smokeTest:
                runSmokeTest(profile: profile, sshClient: sshClient)
            case .command(let command):
                executeCommand(command, profile: profile, sshClient: sshClient)
            }
        } catch {
            errorMessage = error.localizedDescription
            connectionState = .failed(error.localizedDescription)
        }
    }

    func rejectPendingHostKey() {
        pendingHostKey = nil
        pendingHostKeyAction = nil
        connectionState = .disconnected
        isRunningSmokeTest = false
        isRunningCommand = false
    }

    private func storeCommandResult(_ result: CommandResult) {
        commandResult = result
        commandHistory.insert(result, at: 0)
    }
}

private enum PendingHostKeyAction: Equatable {
    case connect
    case smokeTest
    case command(String)
}
