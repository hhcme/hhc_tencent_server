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
    @Published var nginxConfigList: NginxConfigList?
    @Published var selectedNginxConfig: NginxConfigFile?
    @Published var nginxConfigContent: NginxConfigContent?
    @Published var nginxConfigDraft = ""
    @Published var nginxTestResult: NginxTestResult?
    @Published var isLoadingNginxConfigs = false
    @Published var isLoadingNginxConfigContent = false
    @Published var isTestingNginxConfig = false
    @Published var isSavingNginxConfig = false
    @Published var isReloadingNginx = false
    @Published var nginxErrorMessage: String?
    @Published var nginxActionMessage: String?
    @Published var firewallSnapshot: FirewallSnapshot?
    @Published var isLoadingFirewall = false
    @Published var isMutatingFirewall = false
    @Published var firewallErrorMessage: String?
    @Published var firewallActionMessage: String?
    @Published var environmentFileList: EnvironmentFileList?
    @Published var selectedEnvironmentFile: EnvironmentFile?
    @Published var environmentFileContent: EnvironmentFileContent?
    @Published var environmentFileDraft = ""
    @Published var isLoadingEnvironmentFiles = false
    @Published var isLoadingEnvironmentFileContent = false
    @Published var isSavingEnvironmentFile = false
    @Published var environmentErrorMessage: String?
    @Published var environmentActionMessage: String?
    @Published var cloudSecurityGroupList: CloudSecurityGroupList?
    @Published var selectedCloudSecurityGroup: CloudSecurityGroup?
    @Published var cloudSecurityGroupPolicySnapshot: CloudSecurityGroupPolicySnapshot?
    @Published var isLoadingCloudSecurityGroups = false
    @Published var isLoadingCloudSecurityGroupPolicies = false
    @Published var cloudSecurityGroupErrorMessage: String?
    @Published var deploymentProjects: [DeploymentProject] = []
    @Published var selectedDeploymentProject: DeploymentProject?
    @Published var deploymentRuns: [DeploymentRun] = []
    @Published var selectedDeploymentRun: DeploymentRun?
    @Published var deploymentLogs: [DeploymentLogEntry] = []
    @Published var deploymentName = ""
    @Published var deploymentRepositoryURL = ""
    @Published var deploymentBranch = "main"
    @Published var deploymentPath = "/srv/app"
    @Published var deploymentBuildCommand = ""
    @Published var deploymentRestartCommand = ""
    @Published var deploymentHealthCheckCommand = ""
    @Published var deploymentWebhookEnabled = false
    @Published var deploymentWebhookSecret = ""
    @Published var deploymentCommandPlan: DeploymentCommandPlan?
    @Published var isLoadingDeployments = false
    @Published var isSavingDeploymentProject = false
    @Published var isRunningDeployment = false
    @Published var isDeploymentWebhookListenerRunning = false
    @Published var deploymentWebhookListenerPortText = "8787"
    @Published var deploymentWebhookListenerURL: String?
    @Published var deploymentErrorMessage: String?
    @Published var deploymentActionMessage: String?
    @Published var registryDraft = VerdaccioInstallDraft()
    @Published var registryPreflightReport: RegistryPreflightReport?
    @Published var verdaccioInstallResult: VerdaccioInstallResult?
    @Published var verdaccioStatusSnapshot: VerdaccioStatusSnapshot?
    @Published var verdaccioPackages: [VerdaccioPackageSummary] = []
    @Published var verdaccioBackupResult: VerdaccioRegistryBackupResult?
    @Published var verdaccioRestoreResult: VerdaccioRegistryRestoreResult?
    @Published var verdaccioUserMutationResult: VerdaccioUserMutationResult?
    @Published var verdaccioProxyDraft = VerdaccioNginxProxyDraft(serverName: "_")
    @Published var verdaccioProxyUpsertResult: NginxConfigUpsertResult?
    @Published var verdaccioNpmSmokeTestResult: VerdaccioNpmSmokeTestResult?
    @Published var verdaccioServiceActionResult: VerdaccioServiceActionResult?
    @Published var verdaccioUpgradeResult: VerdaccioUpgradeResult?
    @Published var verdaccioUsernameDraft = ""
    @Published var verdaccioPasswordDraft = ""
    @Published var verdaccioEmailDraft = "smoke@example.com"
    @Published var verdaccioRestorePathDraft = ""
    @Published var isRunningRegistryPreflight = false
    @Published var isInstallingVerdaccio = false
    @Published var isLoadingVerdaccioStatus = false
    @Published var isLoadingVerdaccioPackages = false
    @Published var isCreatingVerdaccioBackup = false
    @Published var isRestoringVerdaccioBackup = false
    @Published var isMutatingVerdaccioUser = false
    @Published var isWritingVerdaccioProxy = false
    @Published var isReloadingVerdaccioProxy = false
    @Published var isRunningVerdaccioNpmSmokeTest = false
    @Published var isControllingVerdaccioService = false
    @Published var isUpgradingVerdaccio = false
    @Published var registryErrorMessage: String?
    @Published var registryActionMessage: String?
    @Published var commandResult: CommandResult?
    @Published var commandHistory: [CommandResult] = []
    @Published var persistedCommandHistory: [CommandHistoryEntry] = []
    @Published var lastCommandFailure: CommandFailureSummary?
    @Published var errorMessage: String?
    @Published var pendingHostKey: HostKeyInfo?
    private var pendingHostKeyAction: PendingHostKeyAction?
    private var commandTask: Task<Void, Never>?
    private var deploymentTask: Task<Void, Never>?
    private var deploymentLogRefreshTask: Task<Void, Never>?
    private var runningCommand: String?
    private var dashboardAutoRefreshTask: Task<Void, Never>?
    private var transferTask: Task<Void, Never>?
    private var runningTransferJobId: UUID?
    private var transferQueue: [QueuedRemoteFileTransfer] = []

    deinit {
        dashboardAutoRefreshTask?.cancel()
        commandTask?.cancel()
        deploymentTask?.cancel()
        deploymentLogRefreshTask?.cancel()
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

    func loadCachedDashboardSnapshot(profile: ServerProfile, repository: ServerRepository) {
        do {
            dashboardSnapshot = try repository.fetchLatestDashboardSnapshot(serverId: profile.id)
        } catch {
            dashboardErrorMessage = error.localizedDescription
        }
    }

    func loadRemoteFileTransferHistory(profile: ServerProfile, repository: ServerRepository) {
        do {
            remoteFileTransferJobs = try repository.fetchRemoteFileTransferJobs(serverId: profile.id)
        } catch {
            remoteFileErrorMessage = error.localizedDescription
        }
    }

    func refreshDashboard(
        profile: ServerProfile,
        sshClient: SSHClient,
        dashboardService: DashboardService,
        cloudMetricService: CloudMetricService? = nil,
        repository: ServerRepository? = nil
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
                try repository?.saveDashboardSnapshot(snapshot, serverId: profile.id)
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
        repository: ServerRepository? = nil,
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
                repository: repository,
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
        repository: ServerRepository?,
        interval: Duration
    ) {
        dashboardAutoRefreshTask?.cancel()
        refreshDashboard(
            profile: profile,
            sshClient: sshClient,
            dashboardService: dashboardService,
            cloudMetricService: cloudMetricService,
            repository: repository
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
                        cloudMetricService: cloudMetricService,
                        repository: repository
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
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
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
            remoteFileService: remoteFileService,
            repository: repository
        ))
        startNextRemoteFileTransferIfNeeded()
    }

    func downloadRemoteFile(
        _ entry: RemoteFileEntry,
        to localURL: URL,
        profile: ServerProfile,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
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
            remoteFileService: remoteFileService,
            repository: repository
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
        systemdServiceManager: SystemdServiceManager,
        repository: ServerRepository? = nil
    ) {
        isPerformingSystemdAction = true
        systemdErrorMessage = nil
        systemdActionMessage = nil
        let beforeSnapshot = selectedSystemdUnit.map(Self.systemdSnapshot)

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
                let afterUnit = list.units.first(where: { $0.name == unitName })
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "systemd",
                    targetId: unitName,
                    action: action.rawValue,
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: afterUnit.map(Self.systemdSnapshot),
                    status: "success",
                    message: "\(action.displayName) requested for \(unitName)."
                )
                await MainActor.run {
                    self.systemdUnitList = list
                    self.selectedSystemdUnit = afterUnit
                    self.systemdJournalLog = journal ?? self.systemdJournalLog
                    self.systemdActionMessage = "\(action.displayName) requested for \(unitName)."
                    self.isPerformingSystemdAction = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "systemd",
                    targetId: unitName,
                    action: action.rawValue,
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
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
        cronManager: CronManager,
        repository: ServerRepository? = nil
    ) {
        isMutatingCron = true
        cronErrorMessage = nil
        cronActionMessage = nil
        let beforeSnapshot = cronSnapshot?.rawText

        Task {
            do {
                try await cronManager.add(schedule: schedule, command: command, profile: profile, sshClient: sshClient)
                let snapshot = try await cronManager.load(profile: profile, sshClient: sshClient)
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "cron",
                    targetId: try? CronManager.makeEntryLine(schedule: schedule, command: command),
                    action: "add",
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: snapshot.rawText,
                    status: "success",
                    message: "Added cron entry."
                )
                await MainActor.run {
                    self.cronSnapshot = snapshot
                    self.cronActionMessage = "Added cron entry."
                    self.isMutatingCron = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "cron",
                    targetId: "\(schedule) \(command)",
                    action: "add",
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
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
        cronManager: CronManager,
        repository: ServerRepository? = nil
    ) {
        isMutatingCron = true
        cronErrorMessage = nil
        cronActionMessage = nil
        let beforeSnapshot = cronSnapshot?.rawText

        Task {
            do {
                try await cronManager.perform(action, entry: entry, profile: profile, sshClient: sshClient)
                let snapshot = try await cronManager.load(profile: profile, sshClient: sshClient)
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "cron",
                    targetId: entry.originalLine,
                    action: action.rawValue,
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: snapshot.rawText,
                    status: "success",
                    message: "\(action.displayName) requested for cron entry."
                )
                await MainActor.run {
                    self.cronSnapshot = snapshot
                    self.cronActionMessage = "\(action.displayName) requested for cron entry."
                    self.isMutatingCron = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "cron",
                    targetId: entry.originalLine,
                    action: action.rawValue,
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.cronErrorMessage = error.localizedDescription
                    self.isMutatingCron = false
                }
            }
        }
    }

    func loadNginxConfigs(
        profile: ServerProfile,
        sshClient: SSHClient,
        nginxConfigManager: NginxConfigManager
    ) {
        isLoadingNginxConfigs = true
        nginxErrorMessage = nil
        nginxActionMessage = nil

        Task {
            do {
                let list = try await nginxConfigManager.listConfigs(profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.nginxConfigList = list
                    if let selected = self.selectedNginxConfig,
                       let refreshed = list.files.first(where: { $0.id == selected.id }) {
                        self.selectedNginxConfig = refreshed
                    } else {
                        self.selectedNginxConfig = list.files.first
                    }
                    self.isLoadingNginxConfigs = false
                }
                if let selected = await MainActor.run(body: { self.selectedNginxConfig }) {
                    await MainActor.run {
                        self.selectNginxConfig(
                            selected,
                            profile: profile,
                            sshClient: sshClient,
                            nginxConfigManager: nginxConfigManager
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.nginxErrorMessage = error.localizedDescription
                    self.isLoadingNginxConfigs = false
                }
            }
        }
    }

    func selectNginxConfig(
        _ file: NginxConfigFile,
        profile: ServerProfile,
        sshClient: SSHClient,
        nginxConfigManager: NginxConfigManager
    ) {
        selectedNginxConfig = file
        isLoadingNginxConfigContent = true
        nginxErrorMessage = nil

        Task {
            do {
                let content = try await nginxConfigManager.readConfig(file: file, profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.nginxConfigContent = content
                    self.nginxConfigDraft = content.content
                    self.isLoadingNginxConfigContent = false
                }
            } catch {
                await MainActor.run {
                    self.nginxErrorMessage = error.localizedDescription
                    self.isLoadingNginxConfigContent = false
                }
            }
        }
    }

    func saveNginxConfig(
        profile: ServerProfile,
        sshClient: SSHClient,
        nginxConfigManager: NginxConfigManager,
        repository: ServerRepository? = nil
    ) {
        guard let content = nginxConfigContent else { return }
        isSavingNginxConfig = true
        nginxErrorMessage = nil
        nginxActionMessage = nil
        let beforeSnapshot = content.content
        let draft = nginxConfigDraft

        Task {
            do {
                let result = try await nginxConfigManager.saveConfig(
                    file: content.file,
                    content: draft,
                    profile: profile,
                    sshClient: sshClient
                )
                let refreshed = try await nginxConfigManager.readConfig(
                    file: content.file,
                    profile: profile,
                    sshClient: sshClient
                )
                let status = result.rolledBack ? "failed" : "success"
                let message = result.rolledBack
                    ? "Saved config failed nginx -t and was rolled back from \(result.backupPath)."
                    : "Saved config after successful nginx -t. Backup: \(result.backupPath)."
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "nginx",
                    targetId: content.file.path,
                    action: "save",
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: result.rolledBack ? refreshed.content : draft,
                    status: status,
                    message: message
                )
                await MainActor.run {
                    self.nginxConfigContent = refreshed
                    self.nginxConfigDraft = refreshed.content
                    self.nginxTestResult = result.testResult
                    self.nginxActionMessage = result.rolledBack
                        ? "Nginx test failed. Restored backup: \(result.backupPath)."
                        : "Saved Nginx config. Backup: \(result.backupPath)."
                    self.isSavingNginxConfig = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "nginx",
                    targetId: content.file.path,
                    action: "save",
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.nginxErrorMessage = error.localizedDescription
                    self.isSavingNginxConfig = false
                }
            }
        }
    }

    func testNginxConfig(
        profile: ServerProfile,
        sshClient: SSHClient,
        nginxConfigManager: NginxConfigManager
    ) {
        isTestingNginxConfig = true
        nginxErrorMessage = nil
        nginxActionMessage = nil

        Task {
            do {
                let result = try await nginxConfigManager.testConfig(profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.nginxTestResult = result
                    self.nginxActionMessage = result.succeeded ? "Nginx configuration test passed." : "Nginx configuration test failed."
                    self.isTestingNginxConfig = false
                }
            } catch {
                await MainActor.run {
                    self.nginxErrorMessage = error.localizedDescription
                    self.isTestingNginxConfig = false
                }
            }
        }
    }

    func reloadNginx(
        profile: ServerProfile,
        sshClient: SSHClient,
        nginxConfigManager: NginxConfigManager,
        repository: ServerRepository? = nil
    ) {
        isReloadingNginx = true
        nginxErrorMessage = nil
        nginxActionMessage = nil
        let beforeSnapshot = nginxTestResult?.output

        Task {
            do {
                let result = try await nginxConfigManager.reload(profile: profile, sshClient: sshClient)
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "nginx",
                    targetId: selectedNginxConfig?.path ?? "nginx",
                    action: "reload",
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: result.output,
                    status: "success",
                    message: "Reloaded Nginx after successful nginx -t."
                )
                await MainActor.run {
                    self.nginxTestResult = result
                    self.nginxActionMessage = "Reloaded Nginx."
                    self.isReloadingNginx = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "nginx",
                    targetId: selectedNginxConfig?.path ?? "nginx",
                    action: "reload",
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.nginxErrorMessage = error.localizedDescription
                    self.isReloadingNginx = false
                }
            }
        }
    }

    func loadFirewallSnapshot(
        profile: ServerProfile,
        sshClient: SSHClient,
        firewallManager: FirewallManager
    ) {
        isLoadingFirewall = true
        firewallErrorMessage = nil
        firewallActionMessage = nil

        Task {
            do {
                let snapshot = try await firewallManager.loadSnapshot(profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.firewallSnapshot = snapshot
                    self.isLoadingFirewall = false
                }
            } catch {
                await MainActor.run {
                    self.firewallErrorMessage = error.localizedDescription
                    self.isLoadingFirewall = false
                }
            }
        }
    }

    func applyFirewallRule(
        _ draft: FirewallRuleDraft,
        profile: ServerProfile,
        sshClient: SSHClient,
        firewallManager: FirewallManager,
        repository: ServerRepository? = nil
    ) {
        guard let snapshot = firewallSnapshot else {
            firewallErrorMessage = "Refresh firewall rules before applying changes."
            return
        }
        isMutatingFirewall = true
        firewallErrorMessage = nil
        firewallActionMessage = nil

        Task {
            do {
                let result = try await firewallManager.applyRule(
                    draft,
                    snapshot: snapshot,
                    profile: profile,
                    sshClient: sshClient
                )
                let message = "\(draft.mutation.displayName) firewall rule succeeded."
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "firewall",
                    targetId: "\(snapshot.backend.rawValue):\(draft.direction.rawValue):\(draft.proto.rawValue):\(draft.port):\(draft.cidr)",
                    action: draft.mutation.rawValue,
                    beforeSnapshot: result.beforeSnapshot.rulesText,
                    afterSnapshot: result.afterSnapshot.rulesText,
                    status: "success",
                    message: message
                )
                await MainActor.run {
                    self.firewallSnapshot = result.afterSnapshot
                    self.firewallActionMessage = message
                    self.isMutatingFirewall = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "firewall",
                    targetId: "\(snapshot.backend.rawValue):\(draft.direction.rawValue):\(draft.proto.rawValue):\(draft.port):\(draft.cidr)",
                    action: draft.mutation.rawValue,
                    beforeSnapshot: snapshot.rulesText,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.firewallErrorMessage = error.localizedDescription
                    self.isMutatingFirewall = false
                }
            }
        }
    }

    func loadEnvironmentFiles(
        profile: ServerProfile,
        sshClient: SSHClient,
        environmentFileManager: EnvironmentFileManager
    ) {
        isLoadingEnvironmentFiles = true
        environmentErrorMessage = nil
        environmentActionMessage = nil

        Task {
            do {
                let list = try await environmentFileManager.listFiles(profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.environmentFileList = list
                    if let selected = self.selectedEnvironmentFile,
                       let refreshed = list.files.first(where: { $0.id == selected.id }) {
                        self.selectedEnvironmentFile = refreshed
                    } else {
                        self.selectedEnvironmentFile = list.files.first
                    }
                    self.isLoadingEnvironmentFiles = false
                }
                if let selected = await MainActor.run(body: { self.selectedEnvironmentFile }) {
                    await MainActor.run {
                        self.selectEnvironmentFile(
                            selected,
                            profile: profile,
                            sshClient: sshClient,
                            environmentFileManager: environmentFileManager
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.environmentErrorMessage = error.localizedDescription
                    self.isLoadingEnvironmentFiles = false
                }
            }
        }
    }

    func selectEnvironmentFile(
        _ file: EnvironmentFile,
        profile: ServerProfile,
        sshClient: SSHClient,
        environmentFileManager: EnvironmentFileManager
    ) {
        selectedEnvironmentFile = file
        isLoadingEnvironmentFileContent = true
        environmentErrorMessage = nil

        Task {
            do {
                let content = try await environmentFileManager.readFile(file: file, profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.environmentFileContent = content
                    self.environmentFileDraft = content.content
                    self.isLoadingEnvironmentFileContent = false
                }
            } catch {
                await MainActor.run {
                    self.environmentErrorMessage = error.localizedDescription
                    self.isLoadingEnvironmentFileContent = false
                }
            }
        }
    }

    func saveEnvironmentFile(
        profile: ServerProfile,
        sshClient: SSHClient,
        environmentFileManager: EnvironmentFileManager,
        repository: ServerRepository? = nil
    ) {
        guard let content = environmentFileContent else { return }
        isSavingEnvironmentFile = true
        environmentErrorMessage = nil
        environmentActionMessage = nil
        let beforeSnapshot = content.content
        let draft = environmentFileDraft

        Task {
            do {
                let result = try await environmentFileManager.saveFile(
                    file: content.file,
                    content: draft,
                    profile: profile,
                    sshClient: sshClient
                )
                let refreshed = try await environmentFileManager.readFile(
                    file: content.file,
                    profile: profile,
                    sshClient: sshClient
                )
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "environment",
                    targetId: content.file.path,
                    action: "save",
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: refreshed.content,
                    status: "success",
                    message: "Saved environment file. Backup: \(result.backupPath)."
                )
                await MainActor.run {
                    self.environmentFileContent = refreshed
                    self.environmentFileDraft = refreshed.content
                    self.environmentActionMessage = "Saved environment file. Backup: \(result.backupPath)."
                    self.isSavingEnvironmentFile = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "environment",
                    targetId: content.file.path,
                    action: "save",
                    beforeSnapshot: beforeSnapshot,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.environmentErrorMessage = error.localizedDescription
                    self.isSavingEnvironmentFile = false
                }
            }
        }
    }

    func loadCloudSecurityGroups(
        profile: ServerProfile,
        cloudSecurityGroupService: CloudSecurityGroupService
    ) {
        isLoadingCloudSecurityGroups = true
        cloudSecurityGroupErrorMessage = nil

        Task {
            do {
                let list = try await cloudSecurityGroupService.loadSecurityGroups(for: profile)
                await MainActor.run {
                    self.cloudSecurityGroupList = list
                    if let selected = self.selectedCloudSecurityGroup,
                       let refreshed = list.groups.first(where: { $0.id == selected.id }) {
                        self.selectedCloudSecurityGroup = refreshed
                    } else {
                        self.selectedCloudSecurityGroup = list.groups.first
                    }
                    self.isLoadingCloudSecurityGroups = false
                }
                if let selected = await MainActor.run(body: { self.selectedCloudSecurityGroup }) {
                    await MainActor.run {
                        self.selectCloudSecurityGroup(
                            selected,
                            cloudSecurityGroupService: cloudSecurityGroupService
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.cloudSecurityGroupErrorMessage = error.localizedDescription
                    self.isLoadingCloudSecurityGroups = false
                }
            }
        }
    }

    func selectCloudSecurityGroup(
        _ group: CloudSecurityGroup,
        cloudSecurityGroupService: CloudSecurityGroupService
    ) {
        selectedCloudSecurityGroup = group
        isLoadingCloudSecurityGroupPolicies = true
        cloudSecurityGroupErrorMessage = nil

        Task {
            do {
                let snapshot = try await cloudSecurityGroupService.loadPolicies(for: group)
                await MainActor.run {
                    self.cloudSecurityGroupPolicySnapshot = snapshot
                    self.isLoadingCloudSecurityGroupPolicies = false
                }
            } catch {
                await MainActor.run {
                    self.cloudSecurityGroupErrorMessage = error.localizedDescription
                    self.isLoadingCloudSecurityGroupPolicies = false
                }
            }
        }
    }

    func loadDeploymentProjects(profile: ServerProfile, repository: ServerRepository) {
        isLoadingDeployments = true
        deploymentErrorMessage = nil

        do {
            deploymentProjects = try repository.fetchDeploymentProjects(serverId: profile.id)
            if let selected = selectedDeploymentProject,
               let refreshed = deploymentProjects.first(where: { $0.id == selected.id }) {
                selectDeploymentProject(refreshed, repository: repository)
            } else if selectedDeploymentProject == nil {
                resetDeploymentDraft(serverId: profile.id)
                deploymentRuns = []
                deploymentLogs = []
                selectedDeploymentRun = nil
            } else {
                selectedDeploymentProject = nil
                resetDeploymentDraft(serverId: profile.id)
                deploymentRuns = []
                deploymentLogs = []
                selectedDeploymentRun = nil
            }
            isLoadingDeployments = false
        } catch {
            deploymentErrorMessage = error.localizedDescription
            isLoadingDeployments = false
        }
    }

    func startNewDeploymentProject(serverId: UUID) {
        selectedDeploymentProject = nil
        deploymentRuns = []
        deploymentLogs = []
        selectedDeploymentRun = nil
        resetDeploymentDraft(serverId: serverId)
        deploymentActionMessage = nil
        deploymentErrorMessage = nil
    }

    func selectDeploymentProject(_ project: DeploymentProject, repository: ServerRepository) {
        selectedDeploymentProject = project
        deploymentName = project.name
        deploymentRepositoryURL = project.repositoryURL
        deploymentBranch = project.branch
        deploymentPath = project.deployPath
        deploymentBuildCommand = project.buildCommand ?? ""
        deploymentRestartCommand = project.restartCommand ?? ""
        deploymentHealthCheckCommand = project.healthCheckCommand ?? ""
        deploymentWebhookEnabled = project.webhookEnabled
        deploymentWebhookSecret = ""
        refreshDeploymentPlan()

        do {
            deploymentRuns = try repository.fetchDeploymentRuns(projectId: project.id)
            if let selected = selectedDeploymentRun,
               let refreshed = deploymentRuns.first(where: { $0.id == selected.id }) {
                selectDeploymentRun(refreshed, repository: repository)
            } else {
                selectedDeploymentRun = deploymentRuns.first
                if let run = selectedDeploymentRun {
                    deploymentLogs = try repository.fetchDeploymentLogs(runId: run.id)
                } else {
                    deploymentLogs = []
                }
            }
        } catch {
            deploymentErrorMessage = error.localizedDescription
        }
    }

    func selectDeploymentRun(_ run: DeploymentRun, repository: ServerRepository) {
        selectedDeploymentRun = run
        do {
            deploymentLogs = try repository.fetchDeploymentLogs(runId: run.id)
        } catch {
            deploymentErrorMessage = error.localizedDescription
        }
    }

    func refreshDeploymentPlan() {
        do {
            deploymentCommandPlan = try DeploymentCommandBuilder.buildPlan(for: draftDeploymentProject())
            deploymentErrorMessage = nil
        } catch {
            deploymentCommandPlan = nil
            deploymentErrorMessage = error.localizedDescription
        }
    }

    func saveDeploymentProject(
        profile: ServerProfile,
        repository: ServerRepository,
        serverManagementService: ServerManagementService? = nil
    ) {
        isSavingDeploymentProject = true
        deploymentErrorMessage = nil
        deploymentActionMessage = nil

        do {
            var project = draftDeploymentProject(serverId: profile.id)
            project.updatedAt = Date()
            try DeploymentCommandBuilder.validate(project: project)
            try repository.upsertDeploymentProject(project)
            if let serverManagementService {
                project = try serverManagementService.configureDeploymentWebhook(
                    project: project,
                    enabled: deploymentWebhookEnabled,
                    secret: deploymentWebhookSecret
                )
                deploymentWebhookSecret = ""
            }
            deploymentProjects = try repository.fetchDeploymentProjects(serverId: profile.id)
            selectedDeploymentProject = deploymentProjects.first { $0.id == project.id } ?? project
            refreshDeploymentPlan()
            deploymentRuns = try repository.fetchDeploymentRuns(projectId: project.id)
            deploymentLogs = []
            selectedDeploymentRun = deploymentRuns.first
            deploymentActionMessage = "Deployment project saved."
            isSavingDeploymentProject = false
        } catch {
            deploymentErrorMessage = error.localizedDescription
            isSavingDeploymentProject = false
        }
    }

    func deleteSelectedDeploymentProject(
        profile: ServerProfile,
        repository: ServerRepository,
        serverManagementService: ServerManagementService? = nil
    ) {
        guard let project = selectedDeploymentProject else { return }
        deploymentErrorMessage = nil
        deploymentActionMessage = nil

        do {
            if let serverManagementService {
                try serverManagementService.deleteDeploymentProject(project)
            } else {
                try repository.deleteDeploymentProject(id: project.id)
            }
            deploymentProjects = try repository.fetchDeploymentProjects(serverId: profile.id)
            startNewDeploymentProject(serverId: profile.id)
            deploymentActionMessage = "Deployment project deleted."
        } catch {
            deploymentErrorMessage = error.localizedDescription
        }
    }

    func runDeployment(
        profile: ServerProfile,
        sshClient: SSHClient,
        deploymentRunner: DeploymentRunner,
        repository: ServerRepository,
        serverManagementService: ServerManagementService? = nil
    ) {
        guard !isRunningDeployment else { return }
        saveDeploymentProject(
            profile: profile,
            repository: repository,
            serverManagementService: serverManagementService
        )
        guard let project = selectedDeploymentProject, deploymentErrorMessage == nil else { return }

        isRunningDeployment = true
        deploymentErrorMessage = nil
        deploymentActionMessage = "Deployment started."
        startDeploymentLogRefresh(project: project, repository: repository)

        deploymentTask = Task {
            do {
                let run = try await deploymentRunner.run(project: project, profile: profile, sshClient: sshClient)
                await MainActor.run {
                    self.selectedDeploymentRun = run
                    self.deploymentActionMessage = run.summary
                    self.isRunningDeployment = false
                    self.stopDeploymentLogRefresh()
                    self.reloadDeploymentRunState(project: project, runId: run.id, repository: repository)
                }
            } catch {
                await MainActor.run {
                    self.deploymentErrorMessage = error.localizedDescription
                    self.isRunningDeployment = false
                    self.stopDeploymentLogRefresh()
                    self.reloadDeploymentRunState(project: project, runId: nil, repository: repository)
                }
            }
        }
    }

    func rollbackDeployment(
        profile: ServerProfile,
        sshClient: SSHClient,
        deploymentRunner: DeploymentRunner,
        repository: ServerRepository
    ) {
        guard !isRunningDeployment else { return }
        guard let project = selectedDeploymentProject else {
            deploymentErrorMessage = "Select a deployment project before rollback."
            return
        }
        guard let previousCommit = selectedDeploymentRun?.previousCommit else {
            deploymentErrorMessage = "Selected run does not have a previous commit to roll back to."
            return
        }

        isRunningDeployment = true
        deploymentErrorMessage = nil
        deploymentActionMessage = "Rollback started."
        startDeploymentLogRefresh(project: project, repository: repository)

        deploymentTask = Task {
            do {
                let run = try await deploymentRunner.rollback(
                    project: project,
                    targetCommit: previousCommit,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.selectedDeploymentRun = run
                    self.deploymentActionMessage = run.summary
                    self.isRunningDeployment = false
                    self.stopDeploymentLogRefresh()
                    self.reloadDeploymentRunState(project: project, runId: run.id, repository: repository)
                }
            } catch {
                await MainActor.run {
                    self.deploymentErrorMessage = error.localizedDescription
                    self.isRunningDeployment = false
                    self.stopDeploymentLogRefresh()
                    self.reloadDeploymentRunState(project: project, runId: nil, repository: repository)
                }
            }
        }
    }

    func cancelDeployment() {
        deploymentTask?.cancel()
    }

    func startDeploymentWebhookListener(_ server: DeploymentWebhookHTTPServer) {
        let trimmedPort = deploymentWebhookListenerPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(trimmedPort) else {
            deploymentErrorMessage = "Webhook listener port must be between 0 and 65535."
            return
        }

        do {
            try server.start(port: port)
            let activePort = server.port ?? port
            deploymentWebhookListenerPortText = "\(activePort)"
            deploymentWebhookListenerURL = "http://127.0.0.1:\(activePort)/webhooks/gitlab"
            isDeploymentWebhookListenerRunning = true
            deploymentActionMessage = "Webhook listener started."
            deploymentErrorMessage = nil
        } catch {
            deploymentErrorMessage = error.localizedDescription
            isDeploymentWebhookListenerRunning = false
            deploymentWebhookListenerURL = nil
        }
    }

    func stopDeploymentWebhookListener(_ server: DeploymentWebhookHTTPServer) {
        server.stop()
        isDeploymentWebhookListenerRunning = false
        deploymentWebhookListenerURL = nil
        deploymentActionMessage = "Webhook listener stopped."
    }

    private func resetDeploymentDraft(serverId: UUID) {
        deploymentName = "Website"
        deploymentRepositoryURL = "git@gitlab.com:team/project.git"
        deploymentBranch = "main"
        deploymentPath = "/srv/app"
        deploymentBuildCommand = ""
        deploymentRestartCommand = ""
        deploymentHealthCheckCommand = ""
        deploymentWebhookEnabled = false
        deploymentWebhookSecret = ""
        deploymentCommandPlan = try? DeploymentCommandBuilder.buildPlan(for: draftDeploymentProject(serverId: serverId))
    }

    private func draftDeploymentProject(serverId: UUID? = nil) -> DeploymentProject {
        let now = Date()
        return DeploymentProject(
            id: selectedDeploymentProject?.id ?? UUID(),
            serverId: serverId ?? selectedDeploymentProject?.serverId ?? UUID(),
            name: optionalDeploymentText(deploymentName) ?? "Deployment",
            repositoryURL: deploymentRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: deploymentBranch.trimmingCharacters(in: .whitespacesAndNewlines),
            deployPath: deploymentPath.trimmingCharacters(in: .whitespacesAndNewlines),
            buildCommand: optionalDeploymentText(deploymentBuildCommand),
            restartCommand: optionalDeploymentText(deploymentRestartCommand),
            healthCheckCommand: optionalDeploymentText(deploymentHealthCheckCommand),
            webhookEnabled: deploymentWebhookEnabled,
            webhookSecretRef: selectedDeploymentProject?.webhookSecretRef,
            createdAt: selectedDeploymentProject?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func optionalDeploymentText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func reloadDeploymentRunState(
        project: DeploymentProject,
        runId: UUID?,
        repository: ServerRepository
    ) {
        do {
            deploymentRuns = try repository.fetchDeploymentRuns(projectId: project.id)
            if let runId {
                selectedDeploymentRun = deploymentRuns.first { $0.id == runId } ?? deploymentRuns.first
            } else {
                selectedDeploymentRun = deploymentRuns.first
            }
            if let run = selectedDeploymentRun {
                deploymentLogs = try repository.fetchDeploymentLogs(runId: run.id)
            } else {
                deploymentLogs = []
            }
        } catch {
            deploymentErrorMessage = error.localizedDescription
        }
    }

    private func startDeploymentLogRefresh(project: DeploymentProject, repository: ServerRepository) {
        deploymentLogRefreshTask?.cancel()
        deploymentLogRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.reloadDeploymentRunState(
                        project: project,
                        runId: self?.selectedDeploymentRun?.id,
                        repository: repository
                    )
                }
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func stopDeploymentLogRefresh() {
        deploymentLogRefreshTask?.cancel()
        deploymentLogRefreshTask = nil
    }

    private func saveRemoteChangeLog(
        repository: ServerRepository?,
        profile: ServerProfile,
        targetType: String,
        targetId: String?,
        action: String,
        beforeSnapshot: String?,
        afterSnapshot: String?,
        status: String,
        message: String?
    ) {
        guard let repository else { return }
        do {
            try repository.saveRemoteChangeLog(RemoteChangeLogEntry(
                id: UUID(),
                serverId: profile.id,
                providerId: nil,
                targetType: targetType,
                targetId: targetId,
                action: action,
                beforeSnapshot: beforeSnapshot,
                afterSnapshot: afterSnapshot,
                status: status,
                message: message,
                createdAt: Date()
            ))
        } catch {
            assertionFailure("Could not save remote change log: \(error.localizedDescription)")
        }
    }

    private static func systemdSnapshot(_ unit: SystemdUnit) -> String {
        [
            "name=\(unit.name)",
            "load=\(unit.loadState)",
            "active=\(unit.activeState)",
            "sub=\(unit.subState)",
            "description=\(unit.description)",
        ].joined(separator: "\n")
    }

    func runRegistryPreflight(
        profile: ServerProfile,
        sshClient: SSHClient,
        registryPreflightChecker: RegistryPreflightChecker
    ) {
        guard !isRunningRegistryPreflight else { return }
        isRunningRegistryPreflight = true
        registryErrorMessage = nil
        registryActionMessage = nil

        Task {
            do {
                let report = try await registryPreflightChecker.run(
                    draft: registryDraft,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.registryPreflightReport = report
                    self.registryActionMessage = report.isReady ? "Registry preflight passed." : "Registry preflight found blocking checks."
                    self.isRunningRegistryPreflight = false
                }
            } catch {
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isRunningRegistryPreflight = false
                }
            }
        }
    }

    func loadVerdaccioStatus(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager
    ) {
        guard !isLoadingVerdaccioStatus else { return }
        isLoadingVerdaccioStatus = true
        registryErrorMessage = nil

        Task {
            do {
                let snapshot = try await verdaccioManager.loadStatus(
                    draft: registryDraft,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.verdaccioStatusSnapshot = snapshot
                    self.registryActionMessage = snapshot.isRunning ? "Verdaccio is running." : "Verdaccio status loaded."
                    self.isLoadingVerdaccioStatus = false
                }
            } catch {
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isLoadingVerdaccioStatus = false
                }
            }
        }
    }

    func installVerdaccio(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioInstaller: VerdaccioInstaller,
        verdaccioManager: VerdaccioManager? = nil
    ) {
        guard !isInstallingVerdaccio else { return }
        isInstallingVerdaccio = true
        registryErrorMessage = nil
        registryActionMessage = nil

        Task {
            do {
                let result = try await verdaccioInstaller.install(
                    draft: registryDraft,
                    profile: profile,
                    sshClient: sshClient
                )
                var snapshot: VerdaccioStatusSnapshot?
                if let verdaccioManager {
                    snapshot = try? await verdaccioManager.loadStatus(
                        draft: registryDraft,
                        profile: profile,
                        sshClient: sshClient
                    )
                }
                await MainActor.run {
                    self.verdaccioInstallResult = result
                    if let snapshot {
                        self.verdaccioStatusSnapshot = snapshot
                    }
                    self.registryActionMessage = "Installed Verdaccio. Health check: \(result.healthCheckOutput)."
                    self.isInstallingVerdaccio = false
                }
            } catch {
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isInstallingVerdaccio = false
                }
            }
        }
    }

    func loadVerdaccioPackages(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager
    ) {
        guard !isLoadingVerdaccioPackages else { return }
        isLoadingVerdaccioPackages = true
        registryErrorMessage = nil

        Task {
            do {
                let packages = try await verdaccioManager.listPackages(
                    draft: registryDraft,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.verdaccioPackages = packages
                    self.registryActionMessage = "Loaded \(packages.count) Verdaccio packages."
                    self.isLoadingVerdaccioPackages = false
                }
            } catch {
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isLoadingVerdaccioPackages = false
                }
            }
        }
    }

    func createVerdaccioBackup(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager,
        repository: ServerRepository
    ) {
        guard !isCreatingVerdaccioBackup else { return }
        isCreatingVerdaccioBackup = true
        registryErrorMessage = nil
        registryActionMessage = nil

        Task {
            do {
                let result = try await verdaccioManager.createBackup(
                    draft: registryDraft,
                    profile: profile,
                    sshClient: sshClient,
                    repository: repository
                )
                await MainActor.run {
                    self.verdaccioBackupResult = result
                    self.verdaccioRestorePathDraft = result.backupPath
                    self.registryActionMessage = "Created Verdaccio backup at \(result.backupPath)."
                    self.isCreatingVerdaccioBackup = false
                }
            } catch {
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isCreatingVerdaccioBackup = false
                }
            }
        }
    }

    func restoreVerdaccioBackup(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager,
        repository: ServerRepository
    ) {
        guard !isRestoringVerdaccioBackup else { return }
        isRestoringVerdaccioBackup = true
        registryErrorMessage = nil
        registryActionMessage = nil
        let backupPath = verdaccioRestorePathDraft

        Task {
            do {
                let result = try await verdaccioManager.restoreBackup(
                    draft: registryDraft,
                    backupPath: backupPath,
                    profile: profile,
                    sshClient: sshClient,
                    repository: repository
                )
                var snapshot: VerdaccioStatusSnapshot?
                snapshot = try? await verdaccioManager.loadStatus(
                    draft: registryDraft,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.verdaccioRestoreResult = result
                    if let snapshot {
                        self.verdaccioStatusSnapshot = snapshot
                    }
                    self.registryActionMessage = "Restored Verdaccio backup from \(result.backupPath). Health check: \(result.healthCheckOutput)."
                    self.isRestoringVerdaccioBackup = false
                }
            } catch {
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isRestoringVerdaccioBackup = false
                }
            }
        }
    }

    func writeVerdaccioNginxProxy(
        profile: ServerProfile,
        sshClient: SSHClient,
        nginxConfigManager: NginxConfigManager,
        repository: ServerRepository
    ) {
        guard !isWritingVerdaccioProxy else { return }
        isWritingVerdaccioProxy = true
        registryErrorMessage = nil
        registryActionMessage = nil
        let proxyDraft = verdaccioProxyDraft

        Task {
            do {
                let content = try VerdaccioConfigurationBuilder.nginxProxyConfig(
                    for: registryDraft,
                    proxy: proxyDraft
                )
                let file = try VerdaccioConfigurationBuilder.nginxProxyConfigFile(for: proxyDraft)
                let result = try await nginxConfigManager.upsertConfig(
                    path: file.path,
                    content: content,
                    profile: profile,
                    sshClient: sshClient
                )
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "nginx",
                    targetId: file.path,
                    action: "upsert-verdaccio-proxy",
                    beforeSnapshot: nil,
                    afterSnapshot: result.rolledBack ? nil : content,
                    status: result.rolledBack ? "failed" : "success",
                    message: result.rolledBack
                        ? "Verdaccio proxy failed nginx -t and was rolled back."
                        : "Wrote Verdaccio proxy after successful nginx -t."
                )
                await MainActor.run {
                    self.verdaccioProxyUpsertResult = result
                    self.registryActionMessage = result.rolledBack
                        ? "Nginx test failed. Verdaccio proxy was rolled back."
                        : "Wrote Verdaccio Nginx proxy to \(result.file.path). Run reload after review."
                    self.isWritingVerdaccioProxy = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "nginx",
                    targetId: proxyDraft.configPath,
                    action: "upsert-verdaccio-proxy",
                    beforeSnapshot: nil,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isWritingVerdaccioProxy = false
                }
            }
        }
    }

    func reloadVerdaccioNginxProxy(
        profile: ServerProfile,
        sshClient: SSHClient,
        nginxConfigManager: NginxConfigManager,
        repository: ServerRepository
    ) {
        guard !isReloadingVerdaccioProxy else { return }
        isReloadingVerdaccioProxy = true
        registryErrorMessage = nil
        registryActionMessage = nil
        let target = verdaccioProxyDraft.configPath

        Task {
            do {
                let result = try await nginxConfigManager.reload(profile: profile, sshClient: sshClient)
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "nginx",
                    targetId: target,
                    action: "reload-verdaccio-proxy",
                    beforeSnapshot: verdaccioProxyUpsertResult?.testResult.output,
                    afterSnapshot: result.output,
                    status: "success",
                    message: "Reloaded Nginx after Verdaccio proxy configuration."
                )
                await MainActor.run {
                    self.registryActionMessage = "Reloaded Nginx for Verdaccio proxy."
                    self.isReloadingVerdaccioProxy = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "nginx",
                    targetId: target,
                    action: "reload-verdaccio-proxy",
                    beforeSnapshot: verdaccioProxyUpsertResult?.testResult.output,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isReloadingVerdaccioProxy = false
                }
            }
        }
    }

    func runVerdaccioNpmSmokeTest(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager
    ) {
        guard !isRunningVerdaccioNpmSmokeTest else { return }
        isRunningVerdaccioNpmSmokeTest = true
        registryErrorMessage = nil
        registryActionMessage = nil
        let username = verdaccioUsernameDraft
        let password = verdaccioPasswordDraft
        let email = verdaccioEmailDraft

        Task {
            do {
                let result = try await verdaccioManager.runNpmSmokeTest(
                    draft: registryDraft,
                    username: username,
                    password: password,
                    email: email,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.verdaccioNpmSmokeTestResult = result
                    self.verdaccioPasswordDraft = ""
                    self.registryActionMessage = "Verified npm publish/install using \(result.packageName)."
                    self.isRunningVerdaccioNpmSmokeTest = false
                }
            } catch {
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isRunningVerdaccioNpmSmokeTest = false
                }
            }
        }
    }

    func performVerdaccioServiceAction(
        _ action: VerdaccioServiceAction,
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager,
        repository: ServerRepository
    ) {
        guard !isControllingVerdaccioService else { return }
        isControllingVerdaccioService = true
        registryErrorMessage = nil
        registryActionMessage = nil

        Task {
            do {
                let result = try await verdaccioManager.performServiceAction(
                    action,
                    draft: registryDraft,
                    profile: profile,
                    sshClient: sshClient
                )
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: result.serviceName,
                    action: "verdaccio-\(action.rawValue)",
                    beforeSnapshot: nil,
                    afterSnapshot: "active=\(result.snapshot.activeState), sub=\(result.snapshot.subState)",
                    status: "success",
                    message: "Verdaccio \(action.rawValue) completed."
                )
                await MainActor.run {
                    self.verdaccioServiceActionResult = result
                    self.verdaccioStatusSnapshot = result.snapshot
                    self.registryActionMessage = "\(action.displayName) requested for \(result.serviceName)."
                    self.isControllingVerdaccioService = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: "\(registryDraft.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)).service",
                    action: "verdaccio-\(action.rawValue)",
                    beforeSnapshot: nil,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isControllingVerdaccioService = false
                }
            }
        }
    }

    func upgradeVerdaccio(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager,
        repository: ServerRepository
    ) {
        guard !isUpgradingVerdaccio else { return }
        isUpgradingVerdaccio = true
        registryErrorMessage = nil
        registryActionMessage = nil

        Task {
            do {
                let result = try await verdaccioManager.upgrade(
                    draft: registryDraft,
                    profile: profile,
                    sshClient: sshClient
                )
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: result.servicePath,
                    action: "verdaccio-upgrade",
                    beforeSnapshot: "backup=\(result.backupPath)",
                    afterSnapshot: "version=\(result.version), active=\(result.snapshot.activeState), sub=\(result.snapshot.subState)",
                    status: "success",
                    message: "Upgraded Verdaccio systemd unit to \(result.version)."
                )
                await MainActor.run {
                    self.verdaccioUpgradeResult = result
                    self.verdaccioStatusSnapshot = result.snapshot
                    self.registryActionMessage = "Upgraded Verdaccio to \(result.version). Health check: \(result.healthCheckOutput)."
                    self.isUpgradingVerdaccio = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: "/etc/systemd/system/\(registryDraft.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)).service",
                    action: "verdaccio-upgrade",
                    beforeSnapshot: nil,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isUpgradingVerdaccio = false
                }
            }
        }
    }

    func createVerdaccioUser(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager
    ) {
        mutateVerdaccioUser(
            profile: profile,
            sshClient: sshClient,
            verdaccioManager: verdaccioManager,
            actionName: "Created",
            mutation: { draft, username, password, profile, sshClient in
                try await verdaccioManager.createUser(
                    draft: draft,
                    username: username,
                    password: password,
                    profile: profile,
                    sshClient: sshClient
                )
            }
        )
    }

    func updateVerdaccioUserPassword(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager
    ) {
        mutateVerdaccioUser(
            profile: profile,
            sshClient: sshClient,
            verdaccioManager: verdaccioManager,
            actionName: "Updated",
            mutation: { draft, username, password, profile, sshClient in
                try await verdaccioManager.updateUserPassword(
                    draft: draft,
                    username: username,
                    password: password,
                    profile: profile,
                    sshClient: sshClient
                )
            }
        )
    }

    func deleteVerdaccioUser(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager
    ) {
        guard !isMutatingVerdaccioUser else { return }
        isMutatingVerdaccioUser = true
        registryErrorMessage = nil
        registryActionMessage = nil
        let username = verdaccioUsernameDraft

        Task {
            do {
                let result = try await verdaccioManager.deleteUser(
                    draft: registryDraft,
                    username: username,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.verdaccioUserMutationResult = result
                    self.registryActionMessage = "Deleted Verdaccio user \(result.username). Backup: \(result.backupPath)."
                    self.isMutatingVerdaccioUser = false
                }
            } catch {
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isMutatingVerdaccioUser = false
                }
            }
        }
    }

    private func mutateVerdaccioUser(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager,
        actionName: String,
        mutation: @escaping @Sendable (
            VerdaccioInstallDraft,
            String,
            String,
            ServerProfile,
            SSHClient
        ) async throws -> VerdaccioUserMutationResult
    ) {
        guard !isMutatingVerdaccioUser else { return }
        isMutatingVerdaccioUser = true
        registryErrorMessage = nil
        registryActionMessage = nil
        let username = verdaccioUsernameDraft
        let password = verdaccioPasswordDraft

        Task {
            do {
                let result = try await mutation(registryDraft, username, password, profile, sshClient)
                await MainActor.run {
                    self.verdaccioUserMutationResult = result
                    self.verdaccioPasswordDraft = ""
                    self.registryActionMessage = "\(actionName) Verdaccio user \(result.username). Backup: \(result.backupPath)."
                    self.isMutatingVerdaccioUser = false
                }
            } catch {
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isMutatingVerdaccioUser = false
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
            progressFraction: 0,
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
            case let .upload(jobId, localURL, directoryPath, profile, sshClient, transferClient, remoteFileService, repository):
                await self.runUploadTransfer(
                    jobId: jobId,
                    localURL: localURL,
                    directoryPath: directoryPath,
                    profile: profile,
                    sshClient: sshClient,
                    transferClient: transferClient,
                    remoteFileService: remoteFileService,
                    repository: repository
                )
            case let .download(jobId, entry, localURL, profile, transferClient, remoteFileService, repository):
                await self.runDownloadTransfer(
                    jobId: jobId,
                    entry: entry,
                    localURL: localURL,
                    profile: profile,
                    transferClient: transferClient,
                    remoteFileService: remoteFileService,
                    repository: repository
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
        remoteFileService: RemoteFileService,
        repository: ServerRepository?
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
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer()
            }
        } catch is CancellationError {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
            }
        } catch SSHClientError.cancelled {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
            }
        } catch {
            await MainActor.run {
                self.remoteFileErrorMessage = error.localizedDescription
                self.finishRemoteFileTransferJob(jobId, status: .failed, message: error.localizedDescription)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
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
        remoteFileService: RemoteFileService,
        repository: ServerRepository?
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
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer()
            }
        } catch is CancellationError {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
            }
        } catch SSHClientError.cancelled {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
            }
        } catch {
            await MainActor.run {
                self.remoteFileErrorMessage = error.localizedDescription
                self.finishRemoteFileTransferJob(jobId, status: .failed, message: error.localizedDescription)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer()
            }
        }
    }

    private func markRemoteFileTransferJobRunning(_ id: UUID) {
        guard let index = remoteFileTransferJobs.firstIndex(where: { $0.id == id }) else { return }
        remoteFileTransferJobs[index].status = .running
        remoteFileTransferJobs[index].progressFraction = nil
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
        remoteFileTransferJobs[index].progressFraction = status == .succeeded ? 1 : remoteFileTransferJobs[index].progressFraction
        remoteFileTransferJobs[index].message = message
        remoteFileTransferJobs[index].finishedAt = Date()
    }

    private func persistRemoteFileTransferJob(_ id: UUID, profile: ServerProfile, repository: ServerRepository?) {
        guard
            let repository,
            let job = remoteFileTransferJobs.first(where: { $0.id == id })
        else {
            return
        }

        do {
            try repository.upsertRemoteFileTransferJob(job, serverId: profile.id)
        } catch {
            remoteFileErrorMessage = error.localizedDescription
        }
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
        remoteFileService: RemoteFileService,
        repository: ServerRepository?
    )
    case download(
        jobId: UUID,
        entry: RemoteFileEntry,
        localURL: URL,
        profile: ServerProfile,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService,
        repository: ServerRepository?
    )

    var jobId: UUID {
        switch self {
        case let .upload(jobId, _, _, _, _, _, _, _):
            jobId
        case let .download(jobId, _, _, _, _, _, _):
            jobId
        }
    }
}
