import Foundation

@MainActor
final class ServerWorkspaceViewModel: ObservableObject {
    @Published var isRunningSmokeTest = false
    @Published var isRunningCommand = false
    @Published var connectionState: SSHConnectionState = .disconnected
    @Published var isRefreshingDashboard = false
    @Published var dashboardSnapshot: ServerDashboardSnapshot?
    @Published var dashboardErrorMessage: String?
    @Published var commandResult: CommandResult?
    @Published var commandHistory: [CommandResult] = []
    @Published var persistedCommandHistory: [CommandHistoryEntry] = []
    @Published var lastCommandFailure: CommandFailureSummary?
    @Published var errorMessage: String?
    @Published var pendingHostKey: HostKeyInfo?
    private var pendingHostKeyAction: PendingHostKeyAction?
    private var commandTask: Task<Void, Never>?
    private var runningCommand: String?

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

    func loadCommandHistory(profile: ServerProfile, repository: ServerRepository) {
        do {
            persistedCommandHistory = try repository.fetchCommandHistory(serverId: profile.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshDashboard(
        profile: ServerProfile,
        sshClient: SSHClient,
        dashboardService: DashboardService
    ) {
        isRefreshingDashboard = true
        dashboardErrorMessage = nil

        Task {
            do {
                let snapshot = try await dashboardService.loadSnapshot(profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.dashboardSnapshot = snapshot
                    self.isRefreshingDashboard = false
                }
            } catch {
                await MainActor.run {
                    self.dashboardErrorMessage = error.localizedDescription
                    self.isRefreshingDashboard = false
                }
            }
        }
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
                    if case .connect = action {
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
                    if case .connect = action {
                        self.connectionState = .failed(error.localizedDescription)
                    }
                    self.isRunningSmokeTest = false
                }
            }
        }
    }

    func executeCommand(
        _ command: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        repository: ServerRepository? = nil
    ) {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            errorMessage = "Command cannot be empty."
            return
        }

        isRunningCommand = true
        errorMessage = nil
        commandResult = nil
        lastCommandFailure = nil
        runningCommand = trimmedCommand

        commandTask?.cancel()
        commandTask = Task {
            do {
                let result = try await sshClient.execute(trimmedCommand, profile: profile)
                await MainActor.run {
                    self.storeCommandResult(result)
                    self.persistCommandResult(result, profile: profile, repository: repository)
                    self.isRunningCommand = false
                    self.commandTask = nil
                    self.runningCommand = nil
                }
            } catch SSHClientError.unknownHostKey(let hostKeyInfo) {
                await MainActor.run {
                    self.pendingHostKey = hostKeyInfo
                    self.pendingHostKeyAction = .command(trimmedCommand, repository)
                    self.isRunningCommand = false
                    self.commandTask = nil
                    self.runningCommand = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.storeCommandCancellation(command: trimmedCommand)
                }
            } catch SSHClientError.cancelled {
                await MainActor.run {
                    self.storeCommandCancellation(command: trimmedCommand)
                }
            } catch {
                await MainActor.run {
                    self.persistCommandFailure(
                        command: trimmedCommand,
                        error: error,
                        profile: profile,
                        repository: repository
                    )
                    self.errorMessage = error.localizedDescription
                    self.isRunningCommand = false
                    self.commandTask = nil
                    self.runningCommand = nil
                }
            }
        }
    }

    func cancelCommand() {
        guard isRunningCommand else { return }
        commandTask?.cancel()
        commandTask = nil
        isRunningCommand = false
        lastCommandFailure = CommandFailureSummary(
            command: runningCommand ?? "Current command",
            message: SSHClientError.cancelled.localizedDescription
        )
        runningCommand = nil
    }

    func rerunCommand(
        _ entry: CommandHistoryEntry,
        profile: ServerProfile,
        sshClient: SSHClient,
        repository: ServerRepository? = nil
    ) {
        executeCommand(entry.command, profile: profile, sshClient: sshClient, repository: repository)
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
            case let .command(command, repository):
                executeCommand(command, profile: profile, sshClient: sshClient, repository: repository)
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
        lastCommandFailure = nil
        commandHistory.insert(result, at: 0)
    }

    private func persistCommandResult(
        _ result: CommandResult,
        profile: ServerProfile,
        repository: ServerRepository?
    ) {
        guard let repository else { return }
        let entry = CommandHistoryEntry(
            id: UUID(),
            serverId: profile.id,
            command: result.command,
            exitCode: result.exitCode,
            duration: result.duration,
            createdAt: Date()
        )
        do {
            try repository.saveCommandHistory(entry)
            try repository.saveOperationLog(OperationLogEntry(
                id: UUID(),
                scope: "ssh",
                action: "execute_command",
                targetId: profile.id.uuidString,
                status: result.exitCode == 0 ? "success" : "failed",
                message: "exit_code=\(result.exitCode)",
                createdAt: Date()
            ))
            persistedCommandHistory.insert(entry, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistCommandFailure(
        command: String,
        error: Error,
        profile: ServerProfile,
        repository: ServerRepository?
    ) {
        lastCommandFailure = CommandFailureSummary(
            command: command,
            message: error.localizedDescription
        )
        guard let repository else { return }
        do {
            try repository.saveCommandHistory(CommandHistoryEntry(
                id: UUID(),
                serverId: profile.id,
                command: command,
                exitCode: nil,
                duration: nil,
                createdAt: Date()
            ))
            try repository.saveOperationLog(OperationLogEntry(
                id: UUID(),
                scope: "ssh",
                action: "execute_command",
                targetId: profile.id.uuidString,
                status: "failed",
                message: error.localizedDescription,
                createdAt: Date()
            ))
            persistedCommandHistory = try repository.fetchCommandHistory(serverId: profile.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func storeCommandCancellation(command: String) {
        lastCommandFailure = CommandFailureSummary(
            command: command,
            message: SSHClientError.cancelled.localizedDescription
        )
        errorMessage = nil
        isRunningCommand = false
        commandTask = nil
        runningCommand = nil
    }
}

struct CommandFailureSummary: Equatable, Hashable {
    var command: String
    var message: String
}

private enum PendingHostKeyAction {
    case connect
    case smokeTest
    case command(String, ServerRepository?)
}
