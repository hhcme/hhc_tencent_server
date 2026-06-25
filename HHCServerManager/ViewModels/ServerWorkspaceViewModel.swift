import Foundation

@MainActor
final class ServerWorkspaceViewModel: ObservableObject {
    @Published var isRunningSmokeTest = false
    @Published var isRunningCommand = false
    @Published var connectionState: SSHConnectionState = .disconnected
    @Published var isRefreshingDashboard = false
    @Published var isDashboardAutoRefreshEnabled = false
    @Published var dashboardSnapshot: ServerDashboardSnapshot?
    @Published var dashboardErrorMessage: String?
    @Published var remoteFilePath = "~"
    @Published var remoteDirectoryListing: RemoteDirectoryListing?
    @Published var isLoadingRemoteFiles = false
    @Published var isMutatingRemoteFile = false
    @Published var remoteFileErrorMessage: String?
    @Published var remoteFileActionMessage: String?
    @Published var remoteTextFile: RemoteTextFile?
    @Published var remoteTextDraft = ""
    @Published var isLoadingRemoteText = false
    @Published var isSavingRemoteText = false
    @Published var isTransferringRemoteFile = false
    @Published var remoteFileTransferJobs: [RemoteFileTransferJob] = []
    @Published var systemdUnitList: SystemdUnitList?
    @Published var selectedSystemdUnit: SystemdUnit?
    @Published var systemdJournalLog: SystemdJournalLog?
    @Published var isLoadingSystemdUnits = false
    @Published var isPerformingSystemdAction = false
    @Published var isLoadingSystemdJournal = false
    @Published var systemdErrorMessage: String?
    @Published var systemdActionMessage: String?
    @Published var cronSnapshot: CronTabSnapshot?
    @Published var isLoadingCron = false
    @Published var isMutatingCron = false
    @Published var cronErrorMessage: String?
    @Published var cronActionMessage: String?
    @Published var commandResult: CommandResult?
    @Published var commandHistory: [CommandResult] = []
    @Published var persistedCommandHistory: [CommandHistoryEntry] = []
    @Published var lastCommandFailure: CommandFailureSummary?
    @Published var errorMessage: String?
    @Published var pendingHostKey: HostKeyInfo?
    private var pendingHostKeyAction: PendingHostKeyAction?
    private var commandTask: Task<Void, Never>?
    private var runningCommand: String?
    private var dashboardAutoRefreshTask: Task<Void, Never>?
    private var transferTask: Task<Void, Never>?
    private var runningTransferJobId: UUID?
    private var transferQueue: [QueuedRemoteFileTransfer] = []

    deinit {
        dashboardAutoRefreshTask?.cancel()
        commandTask?.cancel()
        transferTask?.cancel()
    }

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
        dashboardService: DashboardService,
        cloudMetricService: CloudMetricService? = nil
    ) {
        guard !isRefreshingDashboard else { return }
        isRefreshingDashboard = true
        dashboardErrorMessage = nil

        Task {
            do {
                let snapshot = try await dashboardService.loadSnapshot(
                    profile: profile,
                    sshClient: sshClient,
                    cloudMetricService: cloudMetricService
                )
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

    func setDashboardAutoRefreshEnabled(
        _ enabled: Bool,
        profile: ServerProfile,
        sshClient: SSHClient,
        dashboardService: DashboardService,
        cloudMetricService: CloudMetricService? = nil,
        interval: Duration = .seconds(30)
    ) {
        guard isDashboardAutoRefreshEnabled != enabled else { return }
        isDashboardAutoRefreshEnabled = enabled
        if enabled {
            startDashboardAutoRefresh(
                profile: profile,
                sshClient: sshClient,
                dashboardService: dashboardService,
                cloudMetricService: cloudMetricService,
                interval: interval
            )
        } else {
            stopDashboardAutoRefresh()
        }
    }

    func stopDashboardAutoRefresh() {
        dashboardAutoRefreshTask?.cancel()
        dashboardAutoRefreshTask = nil
        isDashboardAutoRefreshEnabled = false
    }

    private func startDashboardAutoRefresh(
        profile: ServerProfile,
        sshClient: SSHClient,
        dashboardService: DashboardService,
        cloudMetricService: CloudMetricService?,
        interval: Duration
    ) {
        dashboardAutoRefreshTask?.cancel()
        refreshDashboard(
            profile: profile,
            sshClient: sshClient,
            dashboardService: dashboardService,
            cloudMetricService: cloudMetricService
        )
        dashboardAutoRefreshTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
                await MainActor.run {
                    guard self.isDashboardAutoRefreshEnabled else { return }
                    self.refreshDashboard(
                        profile: profile,
                        sshClient: sshClient,
                        dashboardService: dashboardService,
                        cloudMetricService: cloudMetricService
                    )
                }
            }
        }
    }

    func loadRemoteFiles(
        path: String? = nil,
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService
    ) {
        let targetPath = RemoteFileService.normalizedDirectoryPath(path ?? remoteFilePath)
        remoteFilePath = targetPath
        isLoadingRemoteFiles = true
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil

        Task {
            do {
                let listing = try await remoteFileService.listDirectory(
                    path: targetPath,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.remoteDirectoryListing = listing
                    self.remoteFilePath = listing.path
                    self.isLoadingRemoteFiles = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.isLoadingRemoteFiles = false
                }
            }
        }
    }

    func openRemoteFileEntry(
        _ entry: RemoteFileEntry,
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService
    ) {
        guard entry.kind == .directory else { return }
        loadRemoteFiles(path: entry.path, profile: profile, sshClient: sshClient, remoteFileService: remoteFileService)
    }

    func loadRemoteParentDirectory(
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService
    ) {
        loadRemoteFiles(
            path: RemoteFileService.parentPath(for: remoteFilePath),
            profile: profile,
            sshClient: sshClient,
            remoteFileService: remoteFileService
        )
    }

    func renameRemoteFile(
        _ entry: RemoteFileEntry,
        to newName: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService
    ) {
        isMutatingRemoteFile = true
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil

        Task {
            do {
                try await remoteFileService.rename(entry: entry, to: newName, profile: profile, sshClient: sshClient)
                let listing = try await remoteFileService.listDirectory(
                    path: self.remoteFilePath,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.remoteDirectoryListing = listing
                    self.remoteFilePath = listing.path
                    self.remoteFileActionMessage = "Renamed \(entry.name)."
                    self.isMutatingRemoteFile = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.isMutatingRemoteFile = false
                }
            }
        }
    }

    func moveRemoteFileToTrash(
        _ entry: RemoteFileEntry,
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService
    ) {
        isMutatingRemoteFile = true
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil

        Task {
            do {
                let trashPath = try await remoteFileService.moveToTrash(
                    entry: entry,
                    profile: profile,
                    sshClient: sshClient
                )
                let listing = try await remoteFileService.listDirectory(
                    path: self.remoteFilePath,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.remoteDirectoryListing = listing
                    self.remoteFilePath = listing.path
                    self.remoteFileActionMessage = "Moved \(entry.name) to \(trashPath)."
                    self.isMutatingRemoteFile = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.isMutatingRemoteFile = false
                }
            }
        }
    }

    func changeRemoteFilePermissions(
        _ entry: RemoteFileEntry,
        mode: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService
    ) {
        isMutatingRemoteFile = true
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil

        Task {
            do {
                try await remoteFileService.changePermissions(
                    entry: entry,
                    mode: mode,
                    profile: profile,
                    sshClient: sshClient
                )
                let listing = try await remoteFileService.listDirectory(
                    path: self.remoteFilePath,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.remoteDirectoryListing = listing
                    self.remoteFilePath = listing.path
                    self.remoteFileActionMessage = "Changed permissions for \(entry.name) to \(mode)."
                    self.isMutatingRemoteFile = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.isMutatingRemoteFile = false
                }
            }
        }
    }

    func openRemoteTextFile(
        _ entry: RemoteFileEntry,
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService
    ) {
        isLoadingRemoteText = true
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil

        Task {
            do {
                let textFile = try await remoteFileService.readTextFile(
                    entry: entry,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.remoteTextFile = textFile
                    self.remoteTextDraft = textFile.content
                    self.isLoadingRemoteText = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.isLoadingRemoteText = false
                }
            }
        }
    }

    func saveRemoteTextFile(
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService
    ) {
        guard let remoteTextFile else { return }
        isSavingRemoteText = true
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil

        Task {
            do {
                let result = try await remoteFileService.saveTextFile(
                    path: remoteTextFile.path,
                    content: remoteTextDraft,
                    profile: profile,
                    sshClient: sshClient
                )
                let updatedFile = RemoteTextFile(
                    path: result.path,
                    content: self.remoteTextDraft,
                    byteCount: Data(self.remoteTextDraft.utf8).count,
                    capturedAt: Date()
                )
                let listing = try await remoteFileService.listDirectory(
                    path: self.remoteFilePath,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.remoteTextFile = updatedFile
                    self.remoteDirectoryListing = listing
                    self.remoteFileActionMessage = self.remoteTextSaveMessage(result)
                    self.isSavingRemoteText = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.isSavingRemoteText = false
                }
            }
        }
    }

    func saveRemoteTextFileAs(
        targetPath: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService
    ) {
        guard let remoteTextFile else { return }
        isSavingRemoteText = true
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil

        Task {
            do {
                let result = try await remoteFileService.saveTextFileAs(
                    sourcePath: remoteTextFile.path,
                    targetPath: targetPath,
                    content: remoteTextDraft,
                    profile: profile,
                    sshClient: sshClient
                )
                let updatedFile = RemoteTextFile(
                    path: result.path,
                    content: self.remoteTextDraft,
                    byteCount: Data(self.remoteTextDraft.utf8).count,
                    capturedAt: Date()
                )
                let listing = try await remoteFileService.listDirectory(
                    path: RemoteFileService.parentPath(for: result.path),
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.remoteTextFile = updatedFile
                    self.remoteDirectoryListing = listing
                    self.remoteFilePath = listing.path
                    self.remoteFileActionMessage = self.remoteTextSaveMessage(result)
                    self.isSavingRemoteText = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.isSavingRemoteText = false
                }
            }
        }
    }

    func closeRemoteTextEditor() {
        remoteTextFile = nil
        remoteTextDraft = ""
        isLoadingRemoteText = false
        isSavingRemoteText = false
    }

    func uploadRemoteFile(
        localURL: URL,
        profile: ServerProfile,
        sshClient: SSHClient,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService
    ) {
        let remotePath = RemoteFileService.joinedPath(
            basePath: RemoteFileService.normalizedDirectoryPath(remoteFilePath),
            name: localURL.lastPathComponent
        )
        let targetDirectoryPath = remoteFilePath
        let jobId = enqueueRemoteFileTransferJob(
            direction: .upload,
            remotePath: remotePath,
            localPath: localURL.path
        )
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil
        transferQueue.append(.upload(
            jobId: jobId,
            localURL: localURL,
            directoryPath: targetDirectoryPath,
            profile: profile,
            sshClient: sshClient,
            transferClient: transferClient,
            remoteFileService: remoteFileService
        ))
        startNextRemoteFileTransferIfNeeded()
    }

    func downloadRemoteFile(
        _ entry: RemoteFileEntry,
        to localURL: URL,
        profile: ServerProfile,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService
    ) {
        let jobId = enqueueRemoteFileTransferJob(
            direction: .download,
            remotePath: entry.path,
            localPath: localURL.path
        )
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil
        transferQueue.append(.download(
            jobId: jobId,
            entry: entry,
            localURL: localURL,
            profile: profile,
            transferClient: transferClient,
            remoteFileService: remoteFileService
        ))
        startNextRemoteFileTransferIfNeeded()
    }

    func cancelRemoteFileTransfer() {
        guard isTransferringRemoteFile else { return }
        transferTask?.cancel()
        transferTask = nil
        if let runningTransferJobId {
            cancelRemoteFileTransferJob(runningTransferJobId)
        }
    }

    func cancelPendingRemoteFileTransfers() {
        let pendingIds = transferQueue.map(\.jobId)
        transferQueue.removeAll()
        for id in pendingIds {
            finishRemoteFileTransferJob(id, status: .cancelled, message: "Transfer cancelled.")
        }
    }

    func loadSystemdUnits(
        profile: ServerProfile,
        sshClient: SSHClient,
        systemdServiceManager: SystemdServiceManager
    ) {
        isLoadingSystemdUnits = true
        systemdErrorMessage = nil
        systemdActionMessage = nil

        Task {
            do {
                let list = try await systemdServiceManager.listUnits(profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.systemdUnitList = list
                    if let selected = self.selectedSystemdUnit,
                       let refreshed = list.units.first(where: { $0.id == selected.id }) {
                        self.selectedSystemdUnit = refreshed
                    } else {
                        self.selectedSystemdUnit = list.units.first
                    }
                    self.isLoadingSystemdUnits = false
                }
            } catch {
                await MainActor.run {
                    self.systemdErrorMessage = error.localizedDescription
                    self.isLoadingSystemdUnits = false
                }
            }
        }
    }

    func selectSystemdUnit(
        _ unit: SystemdUnit,
        profile: ServerProfile,
        sshClient: SSHClient,
        systemdServiceManager: SystemdServiceManager
    ) {
        selectedSystemdUnit = unit
        loadSystemdJournal(
            unitName: unit.name,
            profile: profile,
            sshClient: sshClient,
            systemdServiceManager: systemdServiceManager
        )
    }

    func performSystemdAction(
        _ action: SystemdUnitAction,
        unitName: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        systemdServiceManager: SystemdServiceManager
    ) {
        isPerformingSystemdAction = true
        systemdErrorMessage = nil
        systemdActionMessage = nil

        Task {
            do {
                try await systemdServiceManager.perform(
                    action,
                    unitName: unitName,
                    profile: profile,
                    sshClient: sshClient
                )
                let list = try await systemdServiceManager.listUnits(profile: profile, sshClient: sshClient)
                let journal = try? await systemdServiceManager.readJournal(
                    unitName: unitName,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.systemdUnitList = list
                    self.selectedSystemdUnit = list.units.first(where: { $0.name == unitName })
                    self.systemdJournalLog = journal ?? self.systemdJournalLog
                    self.systemdActionMessage = "\(action.displayName) requested for \(unitName)."
                    self.isPerformingSystemdAction = false
                }
            } catch {
                await MainActor.run {
                    self.systemdErrorMessage = error.localizedDescription
                    self.isPerformingSystemdAction = false
                }
            }
        }
    }

    func loadSystemdJournal(
        unitName: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        systemdServiceManager: SystemdServiceManager
    ) {
        isLoadingSystemdJournal = true
        systemdErrorMessage = nil

        Task {
            do {
                let log = try await systemdServiceManager.readJournal(
                    unitName: unitName,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.systemdJournalLog = log
                    self.isLoadingSystemdJournal = false
                }
            } catch {
                await MainActor.run {
                    self.systemdErrorMessage = error.localizedDescription
                    self.isLoadingSystemdJournal = false
                }
            }
        }
    }

    func loadCron(
        profile: ServerProfile,
        sshClient: SSHClient,
        cronManager: CronManager
    ) {
        isLoadingCron = true
        cronErrorMessage = nil
        cronActionMessage = nil

        Task {
            do {
                let snapshot = try await cronManager.load(profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.cronSnapshot = snapshot
                    self.isLoadingCron = false
                }
            } catch {
                await MainActor.run {
                    self.cronErrorMessage = error.localizedDescription
                    self.isLoadingCron = false
                }
            }
        }
    }

    func addCronEntry(
        schedule: String,
        command: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        cronManager: CronManager
    ) {
        isMutatingCron = true
        cronErrorMessage = nil
        cronActionMessage = nil

        Task {
            do {
                try await cronManager.add(schedule: schedule, command: command, profile: profile, sshClient: sshClient)
                let snapshot = try await cronManager.load(profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.cronSnapshot = snapshot
                    self.cronActionMessage = "Added cron entry."
                    self.isMutatingCron = false
                }
            } catch {
                await MainActor.run {
                    self.cronErrorMessage = error.localizedDescription
                    self.isMutatingCron = false
                }
            }
        }
    }

    func performCronEntryAction(
        _ action: CronEntryAction,
        entry: CronEntry,
        profile: ServerProfile,
        sshClient: SSHClient,
        cronManager: CronManager
    ) {
        isMutatingCron = true
        cronErrorMessage = nil
        cronActionMessage = nil

        Task {
            do {
                try await cronManager.perform(action, entry: entry, profile: profile, sshClient: sshClient)
                let snapshot = try await cronManager.load(profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.cronSnapshot = snapshot
                    self.cronActionMessage = "\(action.displayName) requested for cron entry."
                    self.isMutatingCron = false
                }
            } catch {
                await MainActor.run {
                    self.cronErrorMessage = error.localizedDescription
                    self.isMutatingCron = false
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

    private func enqueueRemoteFileTransferJob(
        direction: RemoteFileTransferDirection,
        remotePath: String,
        localPath: String
    ) -> UUID {
        let id = UUID()
        remoteFileTransferJobs.insert(RemoteFileTransferJob(
            id: id,
            direction: direction,
            remotePath: remotePath,
            localPath: localPath,
            status: .pending,
            byteCount: nil,
            message: nil,
            startedAt: Date(),
            finishedAt: nil
        ), at: 0)
        return id
    }

    private func startNextRemoteFileTransferIfNeeded() {
        guard !isTransferringRemoteFile, transferTask == nil, !transferQueue.isEmpty else { return }
        let request = transferQueue.removeFirst()
        runningTransferJobId = request.jobId
        isTransferringRemoteFile = true
        markRemoteFileTransferJobRunning(request.jobId)

        transferTask = Task {
            switch request {
            case let .upload(jobId, localURL, directoryPath, profile, sshClient, transferClient, remoteFileService):
                await self.runUploadTransfer(
                    jobId: jobId,
                    localURL: localURL,
                    directoryPath: directoryPath,
                    profile: profile,
                    sshClient: sshClient,
                    transferClient: transferClient,
                    remoteFileService: remoteFileService
                )
            case let .download(jobId, entry, localURL, profile, transferClient, remoteFileService):
                await self.runDownloadTransfer(
                    jobId: jobId,
                    entry: entry,
                    localURL: localURL,
                    profile: profile,
                    transferClient: transferClient,
                    remoteFileService: remoteFileService
                )
            }
        }
    }

    private func runUploadTransfer(
        jobId: UUID,
        localURL: URL,
        directoryPath: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService
    ) async {
        do {
            let didAccess = localURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    localURL.stopAccessingSecurityScopedResource()
                }
            }
            let result = try await remoteFileService.uploadFile(
                localURL: localURL,
                toDirectoryPath: directoryPath,
                profile: profile,
                transferClient: transferClient
            )
            let listing = try await remoteFileService.listDirectory(
                path: self.remoteFilePath,
                profile: profile,
                sshClient: sshClient
            )
            await MainActor.run {
                self.remoteDirectoryListing = listing
                self.remoteFilePath = listing.path
                self.remoteFileActionMessage = "Uploaded \(localURL.lastPathComponent) to \(result.remotePath)."
                self.finishRemoteFileTransferJob(jobId, status: .succeeded, result: result, message: self.remoteFileActionMessage)
                self.finishRunningRemoteFileTransfer()
            }
        } catch is CancellationError {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
            }
        } catch SSHClientError.cancelled {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
            }
        } catch {
            await MainActor.run {
                self.remoteFileErrorMessage = error.localizedDescription
                self.finishRemoteFileTransferJob(jobId, status: .failed, message: error.localizedDescription)
                self.finishRunningRemoteFileTransfer()
            }
        }
    }

    private func runDownloadTransfer(
        jobId: UUID,
        entry: RemoteFileEntry,
        localURL: URL,
        profile: ServerProfile,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService
    ) async {
        do {
            let didAccess = localURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    localURL.stopAccessingSecurityScopedResource()
                }
            }
            let result = try await remoteFileService.downloadFile(
                entry: entry,
                to: localURL,
                profile: profile,
                transferClient: transferClient
            )
            await MainActor.run {
                self.remoteFileActionMessage = "Downloaded \(entry.name) to \(result.localPath)."
                self.finishRemoteFileTransferJob(jobId, status: .succeeded, result: result, message: self.remoteFileActionMessage)
                self.finishRunningRemoteFileTransfer()
            }
        } catch is CancellationError {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
            }
        } catch SSHClientError.cancelled {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
            }
        } catch {
            await MainActor.run {
                self.remoteFileErrorMessage = error.localizedDescription
                self.finishRemoteFileTransferJob(jobId, status: .failed, message: error.localizedDescription)
                self.finishRunningRemoteFileTransfer()
            }
        }
    }

    private func markRemoteFileTransferJobRunning(_ id: UUID) {
        guard let index = remoteFileTransferJobs.firstIndex(where: { $0.id == id }) else { return }
        remoteFileTransferJobs[index].status = .running
        remoteFileTransferJobs[index].startedAt = Date()
    }

    private func finishRunningRemoteFileTransfer() {
        isTransferringRemoteFile = false
        transferTask = nil
        runningTransferJobId = nil
        startNextRemoteFileTransferIfNeeded()
    }

    private func finishRemoteFileTransferJob(
        _ id: UUID,
        status: RemoteFileTransferStatus,
        result: RemoteFileTransferResult? = nil,
        message: String?
    ) {
        guard let index = remoteFileTransferJobs.firstIndex(where: { $0.id == id }) else { return }
        remoteFileTransferJobs[index].status = status
        remoteFileTransferJobs[index].byteCount = result?.byteCount
        remoteFileTransferJobs[index].message = message
        remoteFileTransferJobs[index].finishedAt = Date()
    }

    private func cancelRemoteFileTransferJob(_ id: UUID) {
        remoteFileErrorMessage = nil
        remoteFileActionMessage = "Transfer cancelled."
        finishRemoteFileTransferJob(id, status: .cancelled, message: "Transfer cancelled.")
        finishRunningRemoteFileTransfer()
    }

    private func cancelRemoteFileTransferJobIfRunning(_ id: UUID) {
        guard
            let index = remoteFileTransferJobs.firstIndex(where: { $0.id == id }),
            remoteFileTransferJobs[index].status == .running
        else {
            return
        }
        cancelRemoteFileTransferJob(id)
    }

    private func remoteTextSaveMessage(_ result: RemoteTextSaveResult) -> String {
        if let backupPath = result.backupPath {
            return "Saved \(result.path). Backup: \(backupPath)."
        }
        return "Saved \(result.path)."
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

private enum QueuedRemoteFileTransfer {
    case upload(
        jobId: UUID,
        localURL: URL,
        directoryPath: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService
    )
    case download(
        jobId: UUID,
        entry: RemoteFileEntry,
        localURL: URL,
        profile: ServerProfile,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService
    )

    var jobId: UUID {
        switch self {
        case let .upload(jobId, _, _, _, _, _, _):
            jobId
        case let .download(jobId, _, _, _, _, _):
            jobId
        }
    }
}
