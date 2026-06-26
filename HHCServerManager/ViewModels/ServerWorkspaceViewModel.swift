import Foundation
import AppKit

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
    @Published var isRemoteFileTransferQueuePaused = false
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
    @Published var isMutatingCloudSecurityGroupRule = false
    @Published var cloudSecurityGroupErrorMessage: String?
    @Published var cloudSecurityGroupActionMessage: String?
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
    @Published var remoteChangeLogs: [RemoteChangeLogEntry] = []
    @Published var operationLogs: [OperationLogEntry] = []
    @Published var isLoadingAuditLogs = false
    @Published var auditLogErrorMessage: String?
    @Published var auditLogActionMessage: String?
    @Published var registryDraft = VerdaccioInstallDraft() {
        didSet {
            guard registryDraft != oldValue else { return }
            registryPreflightReport = nil
            verdaccioInstallResult = nil
            registryActionMessage = nil
        }
    }
    @Published var registryPreflightReport: RegistryPreflightReport?
    @Published var verdaccioInstallResult: VerdaccioInstallResult?
    @Published var verdaccioStatusSnapshot: VerdaccioStatusSnapshot?
    @Published var verdaccioPackages: [VerdaccioPackageSummary] = []
    @Published var verdaccioBackupResult: VerdaccioRegistryBackupResult?
    @Published var verdaccioRestoreResult: VerdaccioRegistryRestoreResult?
    @Published var verdaccioUserMutationResult: VerdaccioUserMutationResult?
    @Published var verdaccioConfigPolicyDraft = VerdaccioConfigPolicy()
    @Published var verdaccioConfigSaveResult: VerdaccioConfigSaveResult?
    @Published var verdaccioProxyDraft = VerdaccioNginxProxyDraft(serverName: "_")
    @Published var verdaccioProxyUpsertResult: NginxConfigUpsertResult?
    @Published var verdaccioNpmSmokeTestResult: VerdaccioNpmSmokeTestResult?
    @Published var verdaccioServiceActionResult: VerdaccioServiceActionResult?
    @Published var verdaccioUpgradeResult: VerdaccioUpgradeResult?
    @Published var verdaccioUsernameDraft = ""
    @Published var verdaccioPasswordDraft = ""
    @Published var verdaccioEmailDraft = "smoke@example.com"
    @Published var verdaccioRestorePathDraft = ""
    @Published var pubHostedRepositoryDraft = PubHostedRepositoryDraft()
    @Published var pubHostedRepositoryPlan: PubHostedRepositoryPlan?
    @Published var isRunningRegistryPreflight = false
    @Published var isInstallingVerdaccio = false
    @Published var isLoadingVerdaccioStatus = false
    @Published var isLoadingVerdaccioPackages = false
    @Published var isCreatingVerdaccioBackup = false
    @Published var isRestoringVerdaccioBackup = false
    @Published var isMutatingVerdaccioUser = false
    @Published var isSavingVerdaccioConfigPolicy = false
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
    private var transferQueue: [QueuedRemoteFileTransfer] = []
    private var transferTasksByJobId: [UUID: Task<Void, Never>] = [:]
    private var runningTransferRequestsByJobId: [UUID: QueuedRemoteFileTransfer] = [:]
    private var configuredServerId: UUID?
    private let maximumConcurrentRemoteFileTransfers = 2

    deinit {
        dashboardAutoRefreshTask?.cancel()
        commandTask?.cancel()
        deploymentTask?.cancel()
        deploymentLogRefreshTask?.cancel()
        transferTasksByJobId.values.forEach { $0.cancel() }
    }

    func configure(profile: ServerProfile, initialState: SSHConnectionState) {
        if configuredServerId != profile.id {
            resetServerScopedState()
            configuredServerId = profile.id
        }
        connectionState = initialState
    }

    func configure(initialState: SSHConnectionState) {
        connectionState = initialState
    }

    private func resetServerScopedState() {
        dashboardAutoRefreshTask?.cancel()
        commandTask?.cancel()
        deploymentTask?.cancel()
        deploymentLogRefreshTask?.cancel()
        transferTasksByJobId.values.forEach { $0.cancel() }
        dashboardAutoRefreshTask = nil
        commandTask = nil
        deploymentTask = nil
        deploymentLogRefreshTask = nil
        transferTasksByJobId = [:]
        runningTransferRequestsByJobId = [:]
        transferQueue = []
        runningCommand = nil

        isRunningSmokeTest = false
        isRunningCommand = false
        isRefreshingDashboard = false
        isDashboardAutoRefreshEnabled = false
        isLoadingRemoteFiles = false
        isMutatingRemoteFile = false
        isTransferringRemoteFile = false
        isLoadingSystemdUnits = false
        isPerformingSystemdAction = false
        isLoadingSystemdJournal = false
        isLoadingCron = false
        isMutatingCron = false
        isLoadingNginxConfigs = false
        isLoadingNginxConfigContent = false
        isTestingNginxConfig = false
        isSavingNginxConfig = false
        isReloadingNginx = false
        isLoadingFirewall = false
        isMutatingFirewall = false
        isLoadingEnvironmentFiles = false
        isLoadingEnvironmentFileContent = false
        isSavingEnvironmentFile = false
        isLoadingCloudSecurityGroups = false
        isLoadingCloudSecurityGroupPolicies = false
        isMutatingCloudSecurityGroupRule = false
        isLoadingDeployments = false
        isSavingDeploymentProject = false
        isRunningDeployment = false
        isRunningRegistryPreflight = false
        isInstallingVerdaccio = false
        isLoadingVerdaccioStatus = false
        isLoadingVerdaccioPackages = false
        isCreatingVerdaccioBackup = false
        isRestoringVerdaccioBackup = false
        isMutatingVerdaccioUser = false
        isSavingVerdaccioConfigPolicy = false
        isWritingVerdaccioProxy = false
        isReloadingVerdaccioProxy = false
        isRunningVerdaccioNpmSmokeTest = false
        isControllingVerdaccioService = false
        isUpgradingVerdaccio = false

        dashboardSnapshot = nil
        dashboardErrorMessage = nil
        remoteFilePath = "~"
        remoteDirectoryListing = nil
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil
        remoteTextFile = nil
        remoteTextDraft = ""
        remoteFileTransferJobs = []
        systemdUnitList = nil
        selectedSystemdUnit = nil
        systemdJournalLog = nil
        systemdErrorMessage = nil
        systemdActionMessage = nil
        cronSnapshot = nil
        cronErrorMessage = nil
        cronActionMessage = nil
        nginxConfigList = nil
        selectedNginxConfig = nil
        nginxConfigContent = nil
        nginxConfigDraft = ""
        nginxTestResult = nil
        nginxErrorMessage = nil
        nginxActionMessage = nil
        firewallSnapshot = nil
        firewallErrorMessage = nil
        firewallActionMessage = nil
        environmentFileList = nil
        selectedEnvironmentFile = nil
        environmentFileContent = nil
        environmentFileDraft = ""
        environmentErrorMessage = nil
        environmentActionMessage = nil
        cloudSecurityGroupList = nil
        selectedCloudSecurityGroup = nil
        cloudSecurityGroupPolicySnapshot = nil
        cloudSecurityGroupErrorMessage = nil
        cloudSecurityGroupActionMessage = nil
        deploymentProjects = []
        selectedDeploymentProject = nil
        deploymentRuns = []
        selectedDeploymentRun = nil
        deploymentLogs = []
        deploymentCommandPlan = nil
        deploymentErrorMessage = nil
        deploymentActionMessage = nil
        remoteChangeLogs = []
        operationLogs = []
        auditLogErrorMessage = nil
        auditLogActionMessage = nil
        registryPreflightReport = nil
        verdaccioInstallResult = nil
        verdaccioStatusSnapshot = nil
        verdaccioPackages = []
        verdaccioBackupResult = nil
        verdaccioRestoreResult = nil
        verdaccioUserMutationResult = nil
        verdaccioConfigPolicyDraft = VerdaccioConfigPolicy()
        verdaccioConfigSaveResult = nil
        verdaccioProxyUpsertResult = nil
        verdaccioNpmSmokeTestResult = nil
        verdaccioServiceActionResult = nil
        verdaccioUpgradeResult = nil
        pubHostedRepositoryPlan = nil
        registryErrorMessage = nil
        registryActionMessage = nil
        commandResult = nil
        commandHistory = []
        persistedCommandHistory = []
        lastCommandFailure = nil
        errorMessage = nil
        pendingHostKey = nil
        pendingHostKeyAction = nil
    }

    func connect(profile: ServerProfile, sshClient: SSHClient) {
        guard connectionState != .connecting, !isRunningSmokeTest else {
            return
        }
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

    func clearCommandHistory(profile: ServerProfile, repository: ServerRepository) {
        do {
            let deletedCount = try repository.countCommandHistory(serverId: profile.id)
            try repository.deleteCommandHistory(serverId: profile.id)
            persistedCommandHistory = []
            try repository.saveOperationLog(OperationLogEntry(
                id: UUID(),
                scope: "ssh",
                action: "clear_command_history",
                targetId: profile.id.uuidString,
                status: "success",
                message: "deleted_entries=\(deletedCount)",
                createdAt: Date()
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAuditLogs(profile: ServerProfile, repository: ServerRepository) {
        isLoadingAuditLogs = true
        auditLogErrorMessage = nil
        auditLogActionMessage = nil
        do {
            remoteChangeLogs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
            operationLogs = try repository.fetchOperationLogs(targetId: profile.id.uuidString)
        } catch {
            auditLogErrorMessage = error.localizedDescription
        }
        isLoadingAuditLogs = false
    }

    func auditLogsReportMarkdown(profile: ServerProfile) -> String {
        var lines: [String] = [
            "# Audit Report",
            "",
            "- Server: \(Self.markdownInline(profile.name))",
            "- Endpoint: \(Self.markdownInline(profile.endpoint))",
            "- Remote changes: \(remoteChangeLogs.count)",
            "- Local operations: \(operationLogs.count)",
            "- Generated at: \(AppDatabase.string(from: Date()))",
            "",
            "## Remote Change Logs",
        ]

        if remoteChangeLogs.isEmpty {
            lines.append("")
            lines.append("No remote change logs are loaded for this server.")
        } else {
            lines.append("")
            lines.append("| Time | Target Type | Target ID | Action | Status | Provider | Message |")
            lines.append("| --- | --- | --- | --- | --- | --- | --- |")
            for entry in remoteChangeLogs {
                lines.append([
                    AppDatabase.string(from: entry.createdAt),
                    entry.targetType,
                    entry.targetId ?? "",
                    entry.action,
                    entry.status,
                    entry.providerId?.displayName ?? "",
                    entry.message ?? "",
                ].map(Self.markdownTableCell).joined(separator: " | ").withTableBounds)
            }
        }

        lines.append("")
        lines.append("## Local Operation Logs")
        if operationLogs.isEmpty {
            lines.append("")
            lines.append("No local operation logs are loaded for this server.")
        } else {
            lines.append("")
            lines.append("| Time | Scope | Action | Target ID | Status | Message |")
            lines.append("| --- | --- | --- | --- | --- | --- |")
            for entry in operationLogs {
                lines.append([
                    AppDatabase.string(from: entry.createdAt),
                    entry.scope,
                    entry.action,
                    entry.targetId ?? "",
                    entry.status,
                    entry.message ?? "",
                ].map(Self.markdownTableCell).joined(separator: " | ").withTableBounds)
            }
        }

        return lines.joined(separator: "\n")
    }

    func copyAuditLogsReportToPasteboard(profile: ServerProfile) {
        let report = auditLogsReportMarkdown(profile: profile)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        auditLogActionMessage = "Copied \(remoteChangeLogs.count) remote changes and \(operationLogs.count) local operations as Markdown."
    }

    private static func markdownInline(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownTableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
            let jobs = try repository.fetchRemoteFileTransferJobs(serverId: profile.id)
            remoteFileTransferJobs = jobs.map { job in
                guard job.status == .pending || job.status == .running else {
                    return job
                }
                var interrupted = job
                interrupted.status = .interrupted
                interrupted.progressFraction = job.progressFraction ?? 0
                interrupted.message = "Transfer was interrupted before completion."
                interrupted.finishedAt = job.finishedAt ?? Date()
                try? repository.upsertRemoteFileTransferJob(interrupted, serverId: profile.id)
                return interrupted
            }
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
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
    ) {
        isMutatingRemoteFile = true
        remoteFileErrorMessage = nil
        remoteFileActionMessage = nil

        Task {
            do {
                try await remoteFileService.rename(entry: entry, to: newName, profile: profile, sshClient: sshClient)
                let renamedPath = RemoteFileService.joinedPath(
                    basePath: RemoteFileService.parentPath(for: entry.path),
                    name: newName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let listing = try await remoteFileService.listDirectory(
                    path: self.remoteFilePath,
                    profile: profile,
                    sshClient: sshClient
                )
                await MainActor.run {
                    self.remoteDirectoryListing = listing
                    self.remoteFilePath = listing.path
                    self.remoteFileActionMessage = "Renamed \(entry.name)."
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: entry.path,
                        action: "rename",
                        beforeSnapshot: Self.remoteFileSnapshot(entry),
                        afterSnapshot: "newPath=\(renamedPath)",
                        status: "succeeded",
                        message: self.remoteFileActionMessage
                    )
                    self.isMutatingRemoteFile = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: entry.path,
                        action: "rename",
                        beforeSnapshot: Self.remoteFileSnapshot(entry),
                        afterSnapshot: nil,
                        status: "failed",
                        message: error.localizedDescription
                    )
                    self.isMutatingRemoteFile = false
                }
            }
        }
    }

    func moveRemoteFileToTrash(
        _ entry: RemoteFileEntry,
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
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
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: entry.path,
                        action: "move_to_trash",
                        beforeSnapshot: Self.remoteFileSnapshot(entry),
                        afterSnapshot: "trashPath=\(trashPath)",
                        status: "succeeded",
                        message: self.remoteFileActionMessage
                    )
                    self.isMutatingRemoteFile = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: entry.path,
                        action: "move_to_trash",
                        beforeSnapshot: Self.remoteFileSnapshot(entry),
                        afterSnapshot: nil,
                        status: "failed",
                        message: error.localizedDescription
                    )
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
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
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
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: entry.path,
                        action: "chmod",
                        beforeSnapshot: Self.remoteFileSnapshot(entry),
                        afterSnapshot: "mode=\(mode.trimmingCharacters(in: .whitespacesAndNewlines))",
                        status: "succeeded",
                        message: self.remoteFileActionMessage
                    )
                    self.isMutatingRemoteFile = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: entry.path,
                        action: "chmod",
                        beforeSnapshot: Self.remoteFileSnapshot(entry),
                        afterSnapshot: nil,
                        status: "failed",
                        message: error.localizedDescription
                    )
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
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
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
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: remoteTextFile.path,
                        action: "save_text",
                        beforeSnapshot: Self.remoteTextSnapshot(remoteTextFile),
                        afterSnapshot: Self.remoteTextSaveSnapshot(result, byteCount: updatedFile.byteCount),
                        status: "succeeded",
                        message: self.remoteFileActionMessage
                    )
                    self.isSavingRemoteText = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: remoteTextFile.path,
                        action: "save_text",
                        beforeSnapshot: Self.remoteTextSnapshot(remoteTextFile),
                        afterSnapshot: nil,
                        status: "failed",
                        message: error.localizedDescription
                    )
                    self.isSavingRemoteText = false
                }
            }
        }
    }

    func saveRemoteTextFileAs(
        targetPath: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
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
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: result.path,
                        action: "save_text_as",
                        beforeSnapshot: Self.remoteTextSnapshot(remoteTextFile),
                        afterSnapshot: Self.remoteTextSaveSnapshot(result, byteCount: updatedFile.byteCount),
                        status: "succeeded",
                        message: self.remoteFileActionMessage
                    )
                    self.isSavingRemoteText = false
                }
            } catch {
                await MainActor.run {
                    self.remoteFileErrorMessage = error.localizedDescription
                    self.saveRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        targetType: "remote_file",
                        targetId: targetPath,
                        action: "save_text_as",
                        beforeSnapshot: Self.remoteTextSnapshot(remoteTextFile),
                        afterSnapshot: nil,
                        status: "failed",
                        message: error.localizedDescription
                    )
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
            localPath: localURL.path,
            profile: profile,
            repository: repository
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

    func uploadRemoteFiles(
        localURLs: [URL],
        profile: ServerProfile,
        sshClient: SSHClient,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
    ) {
        let urls = localURLs.filter { !$0.lastPathComponent.isEmpty }
        guard !urls.isEmpty else { return }
        let targetDirectoryPath = RemoteFileService.normalizedDirectoryPath(remoteFilePath)
        remoteFileErrorMessage = nil
        remoteFileActionMessage = "Queued \(urls.count) upload\(urls.count == 1 ? "" : "s")."

        for localURL in urls {
            let remotePath = RemoteFileService.joinedPath(
                basePath: targetDirectoryPath,
                name: localURL.lastPathComponent
            )
            let jobId = enqueueRemoteFileTransferJob(
                direction: .upload,
                remotePath: remotePath,
                localPath: localURL.path,
                profile: profile,
                repository: repository
            )
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
        }
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
            localPath: localURL.path,
            profile: profile,
            repository: repository
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

    func downloadRemoteFiles(
        _ entries: [RemoteFileEntry],
        toDirectory localDirectoryURL: URL,
        profile: ServerProfile,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
    ) {
        let files = entries.filter { $0.kind == .file }
        guard !files.isEmpty else { return }
        remoteFileErrorMessage = nil
        remoteFileActionMessage = "Queued \(files.count) download\(files.count == 1 ? "" : "s")."

        for entry in files {
            let localURL = localDirectoryURL.appendingPathComponent(entry.name, isDirectory: false)
            let jobId = enqueueRemoteFileTransferJob(
                direction: .download,
                remotePath: entry.path,
                localPath: localURL.path,
                profile: profile,
                repository: repository
            )
            transferQueue.append(.download(
                jobId: jobId,
                entry: entry,
                localURL: localURL,
                profile: profile,
                transferClient: transferClient,
                remoteFileService: remoteFileService,
                repository: repository
            ))
        }
        startNextRemoteFileTransferIfNeeded()
    }

    func retryRemoteFileTransfer(
        _ job: RemoteFileTransferJob,
        profile: ServerProfile,
        sshClient: SSHClient,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
    ) {
        guard job.status.isRetryable else { return }
        remoteFileErrorMessage = nil
        remoteFileActionMessage = "Resuming \(Self.remoteFileTransferDisplayName(job))."
        enqueueResumedRemoteFileTransfer(
            job,
            profile: profile,
            sshClient: sshClient,
            transferClient: transferClient,
            remoteFileService: remoteFileService,
            repository: repository
        )
        startNextRemoteFileTransferIfNeeded()
    }

    func retryAllRemoteFileTransfers(
        profile: ServerProfile,
        sshClient: SSHClient,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
    ) {
        let retryableJobs = remoteFileTransferJobs.filter { $0.status.isRetryable }
        guard !retryableJobs.isEmpty else { return }

        remoteFileErrorMessage = nil
        remoteFileActionMessage = "Resuming \(retryableJobs.count) transfer\(retryableJobs.count == 1 ? "" : "s")."
        for job in retryableJobs {
            enqueueResumedRemoteFileTransfer(
                job,
                profile: profile,
                sshClient: sshClient,
                transferClient: transferClient,
                remoteFileService: remoteFileService,
                repository: repository
            )
        }
        startNextRemoteFileTransferIfNeeded()
    }

    private func enqueueResumedRemoteFileTransfer(
        _ job: RemoteFileTransferJob,
        profile: ServerProfile,
        sshClient: SSHClient,
        transferClient: RemoteFileTransferClient,
        remoteFileService: RemoteFileService,
        repository: ServerRepository? = nil
    ) {
        let jobId = resumeRemoteFileTransferJob(
            job,
            profile: profile,
            repository: repository
        )
        switch job.direction {
        case .upload:
            transferQueue.append(.upload(
                jobId: jobId,
                localURL: URL(fileURLWithPath: job.localPath),
                directoryPath: RemoteFileService.normalizedDirectoryPath((job.remotePath as NSString).deletingLastPathComponent),
                profile: profile,
                sshClient: sshClient,
                transferClient: transferClient,
                remoteFileService: remoteFileService,
                repository: repository
            ))
        case .download:
            let entry = RemoteFileEntry(
                name: URL(fileURLWithPath: job.remotePath).lastPathComponent,
                path: job.remotePath,
                kind: .file,
                size: job.byteCount,
                modifiedAt: nil,
                permissions: "-rw-r--r--"
            )
            transferQueue.append(.download(
                jobId: jobId,
                entry: entry,
                localURL: URL(fileURLWithPath: job.localPath),
                profile: profile,
                transferClient: transferClient,
                remoteFileService: remoteFileService,
                repository: repository
            ))
        }
    }

    func cancelRemoteFileTransfer() {
        guard isTransferringRemoteFile else { return }
        let runningRequests = runningTransferRequestsByJobId
        let runningTasks = transferTasksByJobId
        for (jobId, task) in runningTasks {
            task.cancel()
            cancelRemoteFileTransferJobIfRunning(jobId)
            if let request = runningRequests[jobId] {
                persistRemoteFileTransferJob(jobId, profile: request.profile, repository: request.repository)
            }
            finishRunningRemoteFileTransfer(jobId)
        }
    }

    func cancelRemoteFileTransfer(_ job: RemoteFileTransferJob) {
        switch job.status {
        case .pending:
            guard let requestIndex = transferQueue.firstIndex(where: { $0.jobId == job.id }) else { return }
            let request = transferQueue.remove(at: requestIndex)
            cancelRemoteFileTransferJob(job.id)
            persistRemoteFileTransferJob(job.id, profile: request.profile, repository: request.repository)
        case .running:
            guard let task = transferTasksByJobId[job.id] else { return }
            task.cancel()
            cancelRemoteFileTransferJobIfRunning(job.id)
            if let request = runningTransferRequestsByJobId[job.id] {
                persistRemoteFileTransferJob(job.id, profile: request.profile, repository: request.repository)
            }
            finishRunningRemoteFileTransfer(job.id)
        case .succeeded, .failed, .cancelled, .interrupted:
            return
        }
    }

    func cancelPendingRemoteFileTransfers() {
        let pendingRequests = transferQueue
        transferQueue.removeAll()
        for request in pendingRequests {
            finishRemoteFileTransferJob(request.jobId, status: .cancelled, message: "Transfer cancelled.")
            persistRemoteFileTransferJob(request.jobId, profile: request.profile, repository: request.repository)
        }
    }

    func pauseRemoteFileTransferQueue() {
        guard !isRemoteFileTransferQueuePaused else { return }
        isRemoteFileTransferQueuePaused = true
        remoteFileActionMessage = "Transfer queue paused."
    }

    func resumeRemoteFileTransferQueue() {
        guard isRemoteFileTransferQueuePaused else { return }
        isRemoteFileTransferQueuePaused = false
        remoteFileActionMessage = "Transfer queue resumed."
        startNextRemoteFileTransferIfNeeded()
    }

    func promoteRemoteFileTransfer(_ job: RemoteFileTransferJob) {
        reorderPendingRemoteFileTransfer(job, targetQueueIndex: 0, actionMessage: "Transfer moved to next in queue.")
    }

    func moveRemoteFileTransferUp(_ job: RemoteFileTransferJob) {
        guard let queueIndex = transferQueue.firstIndex(where: { $0.jobId == job.id }), queueIndex > 0 else { return }
        reorderPendingRemoteFileTransfer(job, targetQueueIndex: queueIndex - 1, actionMessage: "Transfer moved up.")
    }

    func moveRemoteFileTransferDown(_ job: RemoteFileTransferJob) {
        guard let queueIndex = transferQueue.firstIndex(where: { $0.jobId == job.id }), queueIndex < transferQueue.count - 1 else { return }
        reorderPendingRemoteFileTransfer(job, targetQueueIndex: queueIndex + 1, actionMessage: "Transfer moved down.")
    }

    func clearCompletedRemoteFileTransferHistory(profile: ServerProfile, repository: ServerRepository? = nil) {
        let terminalCount = remoteFileTransferJobs.filter { $0.status.isTerminal }.count
        guard terminalCount > 0 else { return }

        do {
            try repository?.deleteTerminalRemoteFileTransferJobs(serverId: profile.id)
            try repository?.saveOperationLog(OperationLogEntry(
                id: UUID(),
                scope: "remote_file",
                action: "clear_transfer_history",
                targetId: profile.id.uuidString,
                status: "success",
                message: "deleted_entries=\(terminalCount)",
                createdAt: Date()
            ))
            remoteFileTransferJobs.removeAll { $0.status.isTerminal }
            remoteFileActionMessage = "Cleared \(terminalCount) completed transfer\(terminalCount == 1 ? "" : "s")."
            remoteFileErrorMessage = nil
        } catch {
            remoteFileErrorMessage = error.localizedDescription
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
        cloudSecurityGroupActionMessage = nil

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
        cloudSecurityGroupActionMessage = nil

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

    func applyCloudSecurityGroupRuleChange(
        _ preview: CloudSecurityGroupRuleChangePreview,
        profile: ServerProfile,
        cloudSecurityGroupService: CloudSecurityGroupService,
        repository: ServerRepository? = nil
    ) {
        isMutatingCloudSecurityGroupRule = true
        cloudSecurityGroupErrorMessage = nil
        cloudSecurityGroupActionMessage = nil

        Task {
            do {
                let result = try await cloudSecurityGroupService.applyRuleChange(preview)
                let message = "\(preview.action.displayName) security group rule succeeded."
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "security_group",
                    targetId: preview.group.securityGroupId,
                    action: preview.action.rawValue,
                    beforeSnapshot: Self.securityGroupSnapshotText(result.beforeSnapshot),
                    afterSnapshot: Self.securityGroupSnapshotText(result.afterSnapshot),
                    status: "success",
                    message: result.requestId.map { "\(message) RequestId: \($0)." } ?? message
                )
                await MainActor.run {
                    self.cloudSecurityGroupPolicySnapshot = result.afterSnapshot
                    self.cloudSecurityGroupActionMessage = message
                    self.isMutatingCloudSecurityGroupRule = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "security_group",
                    targetId: preview.group.securityGroupId,
                    action: preview.action.rawValue,
                    beforeSnapshot: self.cloudSecurityGroupPolicySnapshot.map(Self.securityGroupSnapshotText),
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.cloudSecurityGroupErrorMessage = error.localizedDescription
                    self.isMutatingCloudSecurityGroupRule = false
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

    func selectedDeploymentRunReportMarkdown(profile: ServerProfile) -> String? {
        guard let project = selectedDeploymentProject, let run = selectedDeploymentRun else { return nil }
        return deploymentRunReportMarkdown(profile: profile, project: project, run: run, logs: deploymentLogs)
    }

    func deploymentRunReportMarkdown(
        profile: ServerProfile,
        project: DeploymentProject,
        run: DeploymentRun,
        logs: [DeploymentLogEntry]
    ) -> String {
        var lines: [String] = [
            "# Deployment Run Report",
            "",
            "- Server: \(Self.markdownInline(profile.name))",
            "- Endpoint: \(Self.markdownInline(profile.endpoint))",
            "- Project: \(Self.markdownInline(project.name))",
            "- Repository: \(Self.markdownInline(project.repositoryURL))",
            "- Branch: \(Self.markdownInline(project.branch))",
            "- Deploy path: \(Self.markdownInline(project.deployPath))",
            "- Trigger: \(run.triggerType.rawValue)",
            "- Status: \(run.status.rawValue)",
            "- Started: \(AppDatabase.string(from: run.startedAt))",
            "- Finished: \(run.finishedAt.map(AppDatabase.string(from:)) ?? "running")",
            "- Requested ref: \(Self.markdownInline(run.requestedRef ?? "none"))",
            "- Previous commit: \(Self.markdownInline(run.previousCommit ?? "unknown"))",
            "- Target commit: \(Self.markdownInline(run.targetCommit ?? "unknown"))",
            "- Summary: \(Self.markdownInline(run.summary ?? "none"))",
            "",
            "## Logs",
        ]

        if logs.isEmpty {
            lines.append("")
            lines.append("No logs are loaded for this deployment run.")
            return lines.joined(separator: "\n")
        }

        lines.append("")
        lines.append("| Time | Step | Stream | Message |")
        lines.append("| --- | --- | --- | --- |")
        for entry in logs {
            lines.append([
                AppDatabase.string(from: entry.createdAt),
                entry.stepName,
                entry.stream.rawValue,
                DeploymentLogRedactor.redact(entry.message),
            ].map(Self.markdownTableCell).joined(separator: " | ").withTableBounds)
        }

        return lines.joined(separator: "\n")
    }

    func copySelectedDeploymentRunReportToPasteboard(profile: ServerProfile) {
        guard let report = selectedDeploymentRunReportMarkdown(profile: profile) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
        deploymentActionMessage = "Copied deployment run report as Markdown."
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

    func deploymentRunRisk(serverId: UUID) -> RemoteOperationRisk? {
        do {
            let project = draftDeploymentProject(serverId: serverId)
            let plan = try DeploymentCommandBuilder.buildPlan(for: project)
            deploymentCommandPlan = plan
            deploymentErrorMessage = nil
            return RemoteOperationRiskFactory.deploymentRun(project: project, plan: plan)
        } catch {
            deploymentCommandPlan = nil
            deploymentErrorMessage = error.localizedDescription
            return nil
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
                    self.saveDeploymentRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        project: project,
                        run: run,
                        action: "deploy"
                    )
                    self.isRunningDeployment = false
                    self.stopDeploymentLogRefresh()
                    self.reloadDeploymentRunState(project: project, runId: run.id, repository: repository)
                }
            } catch {
                await MainActor.run {
                    self.deploymentErrorMessage = error.localizedDescription
                    self.saveDeploymentRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        project: project,
                        action: "deploy",
                        status: "failed",
                        message: error.localizedDescription
                    )
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
                    self.saveDeploymentRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        project: project,
                        run: run,
                        action: "rollback"
                    )
                    self.isRunningDeployment = false
                    self.stopDeploymentLogRefresh()
                    self.reloadDeploymentRunState(project: project, runId: run.id, repository: repository)
                }
            } catch {
                await MainActor.run {
                    self.deploymentErrorMessage = error.localizedDescription
                    self.saveDeploymentRemoteChangeLog(
                        repository: repository,
                        profile: profile,
                        project: project,
                        action: "rollback",
                        status: "failed",
                        message: error.localizedDescription
                    )
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

    private func verdaccioUserAuditLabel(_ action: VerdaccioUserMutationAction) -> String {
        switch action {
        case .create:
            "create"
        case .updatePassword:
            "update-password"
        case .delete:
            "delete"
        }
    }

    private func saveDeploymentRemoteChangeLog(
        repository: ServerRepository,
        profile: ServerProfile,
        project: DeploymentProject,
        run: DeploymentRun,
        action: String
    ) {
        saveDeploymentRemoteChangeLog(
            repository: repository,
            profile: profile,
            project: project,
            action: action,
            status: run.status.rawValue,
            message: run.summary,
            previousCommit: run.previousCommit,
            targetCommit: run.targetCommit
        )
    }

    private func saveDeploymentRemoteChangeLog(
        repository: ServerRepository,
        profile: ServerProfile,
        project: DeploymentProject,
        action: String,
        status: String,
        message: String?,
        previousCommit: String? = nil,
        targetCommit: String? = nil
    ) {
        saveRemoteChangeLog(
            repository: repository,
            profile: profile,
            targetType: "deployment",
            targetId: project.id.uuidString,
            action: action,
            beforeSnapshot: deploymentSnapshot(project: project, commit: previousCommit),
            afterSnapshot: deploymentSnapshot(project: project, commit: targetCommit),
            status: status,
            message: message
        )
    }

    private func deploymentSnapshot(project: DeploymentProject, commit: String?) -> String {
        [
            "project=\(project.name)",
            "repository=\(project.repositoryURL)",
            "branch=\(project.branch)",
            "path=\(project.deployPath)",
            "commit=\(commit ?? "unknown")"
        ].joined(separator: "\n")
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

    private static func remoteFileSnapshot(_ entry: RemoteFileEntry) -> String {
        let lines: [String?] = [
            "path=\(entry.path)",
            "name=\(entry.name)",
            "kind=\(entry.kind.rawValue)",
            entry.size.map { "size=\($0)" },
            entry.permissions.isEmpty ? nil : "permissions=\(entry.permissions)",
        ]
        return lines.compactMap { $0 }.joined(separator: "\n")
    }

    private static func remoteTextSnapshot(_ file: RemoteTextFile) -> String {
        [
            "path=\(file.path)",
            "byteCount=\(file.byteCount)",
        ].joined(separator: "\n")
    }

    private static func remoteTextSaveSnapshot(_ result: RemoteTextSaveResult, byteCount: Int) -> String {
        let lines: [String?] = [
            "path=\(result.path)",
            "byteCount=\(byteCount)",
            result.backupPath.map { "backupPath=\($0)" },
        ]
        return lines.compactMap { $0 }.joined(separator: "\n")
    }

    private static func securityGroupSnapshotText(_ snapshot: CloudSecurityGroupPolicySnapshot) -> String {
        let ingress = snapshot.ingress.map { "ingress \($0.summary)" }.joined(separator: "\n")
        let egress = snapshot.egress.map { "egress \($0.summary)" }.joined(separator: "\n")
        return [
            "group=\(snapshot.group.securityGroupId)",
            "version=\(snapshot.version ?? "unknown")",
            "ingress:",
            ingress.isEmpty ? "(empty)" : ingress,
            "egress:",
            egress.isEmpty ? "(empty)" : egress,
        ].joined(separator: "\n")
    }

    private static func verdaccioConfigPolicySnapshot(_ policy: VerdaccioConfigPolicy) -> String {
        [
            "upstreamRegistryURL=\(policy.upstreamRegistryURL.trimmingCharacters(in: .whitespacesAndNewlines))",
            "accessMode=\(policy.accessMode.rawValue)",
        ].joined(separator: "\n")
    }

    @discardableResult
    func validateRegistryDraftForEditing() -> Bool {
        do {
            try VerdaccioConfigurationBuilder.validate(registryDraft)
            registryErrorMessage = nil
            return true
        } catch {
            registryActionMessage = nil
            registryErrorMessage = error.localizedDescription
            return false
        }
    }

    func runRegistryPreflight(
        profile: ServerProfile,
        sshClient: SSHClient,
        registryPreflightChecker: RegistryPreflightChecker
    ) {
        guard !isRunningRegistryPreflight else { return }
        guard validateRegistryDraftForEditing() else { return }
        isRunningRegistryPreflight = true
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

    func buildPubHostedRepositoryPlan(generatedAt: Date = Date()) {
        do {
            pubHostedRepositoryPlan = try PubHostedRepositoryAssistant.buildPlan(
                draft: pubHostedRepositoryDraft,
                generatedAt: generatedAt
            )
            registryErrorMessage = nil
            registryActionMessage = "Generated Dart/Flutter hosted pub configuration."
        } catch {
            pubHostedRepositoryPlan = nil
            registryActionMessage = nil
            registryErrorMessage = error.localizedDescription
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
        guard validateRegistryDraftForEditing() else { return }
        isInstallingVerdaccio = true
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

    func saveVerdaccioConfigPolicy(
        profile: ServerProfile,
        sshClient: SSHClient,
        verdaccioManager: VerdaccioManager,
        repository: ServerRepository
    ) {
        guard !isSavingVerdaccioConfigPolicy else { return }
        guard validateRegistryDraftForEditing() else { return }
        do {
            try VerdaccioConfigurationBuilder.validate(verdaccioConfigPolicyDraft)
        } catch {
            registryActionMessage = nil
            registryErrorMessage = error.localizedDescription
            return
        }
        isSavingVerdaccioConfigPolicy = true
        registryErrorMessage = nil
        registryActionMessage = nil

        Task {
            do {
                let policy = verdaccioConfigPolicyDraft
                let result = try await verdaccioManager.saveGeneratedConfig(
                    draft: registryDraft,
                    policy: policy,
                    profile: profile,
                    sshClient: sshClient
                )
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: result.path,
                    action: "verdaccio-config-policy",
                    beforeSnapshot: "backup=\(result.backupPath)",
                    afterSnapshot: Self.verdaccioConfigPolicySnapshot(policy),
                    status: "success",
                    message: "Saved Verdaccio access policy and restarted \(registryDraft.serviceName).service."
                )
                await MainActor.run {
                    self.verdaccioConfigSaveResult = result
                    self.registryActionMessage = "Saved Verdaccio access policy and restarted \(self.registryDraft.serviceName).service."
                    self.isSavingVerdaccioConfigPolicy = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: "\(registryDraft.installPath.trimmingCharacters(in: .whitespacesAndNewlines))/config.yaml",
                    action: "verdaccio-config-policy",
                    beforeSnapshot: nil,
                    afterSnapshot: Self.verdaccioConfigPolicySnapshot(verdaccioConfigPolicyDraft),
                    status: "failed",
                    message: error.localizedDescription
                )
                await MainActor.run {
                    self.registryErrorMessage = error.localizedDescription
                    self.isSavingVerdaccioConfigPolicy = false
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
                let sizeText = result.sizeBytes.map(String.init) ?? "unknown"
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: registryDraft.installPath,
                    action: "verdaccio-backup",
                    beforeSnapshot: nil,
                    afterSnapshot: "backup=\(result.backupPath)\nsizeBytes=\(sizeText)",
                    status: "success",
                    message: "Created Verdaccio backup at \(result.backupPath)."
                )
                await MainActor.run {
                    self.verdaccioBackupResult = result
                    self.verdaccioRestorePathDraft = result.backupPath
                    self.registryActionMessage = "Created Verdaccio backup at \(result.backupPath)."
                    self.isCreatingVerdaccioBackup = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: registryDraft.installPath,
                    action: "verdaccio-backup",
                    beforeSnapshot: nil,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
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
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: result.backupPath,
                    action: "verdaccio-restore",
                    beforeSnapshot: "backup=\(result.backupPath)\nrollbackBackup=\(result.rollbackBackupPath)",
                    afterSnapshot: "healthCheckURL=\(result.healthCheckURL)\nhealthCheckOutput=\(result.healthCheckOutput)",
                    status: "success",
                    message: "Restored Verdaccio backup from \(result.backupPath)."
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
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry",
                    targetId: backupPath.trimmingCharacters(in: .whitespacesAndNewlines),
                    action: "verdaccio-restore",
                    beforeSnapshot: "backup=\(backupPath.trimmingCharacters(in: .whitespacesAndNewlines))",
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
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
        verdaccioManager: VerdaccioManager,
        repository: ServerRepository
    ) {
        mutateVerdaccioUser(
            profile: profile,
            sshClient: sshClient,
            verdaccioManager: verdaccioManager,
            repository: repository,
            actionName: "Created",
            auditAction: "verdaccio-create-user",
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
        verdaccioManager: VerdaccioManager,
        repository: ServerRepository
    ) {
        mutateVerdaccioUser(
            profile: profile,
            sshClient: sshClient,
            verdaccioManager: verdaccioManager,
            repository: repository,
            actionName: "Updated",
            auditAction: "verdaccio-update-password-user",
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
        verdaccioManager: VerdaccioManager,
        repository: ServerRepository
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
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry_user",
                    targetId: result.username,
                    action: "verdaccio-\(self.verdaccioUserAuditLabel(result.action))-user",
                    beforeSnapshot: "backup=\(result.backupPath)",
                    afterSnapshot: "htpasswd=\(result.htpasswdPath)",
                    status: "success",
                    message: "Deleted Verdaccio user \(result.username)."
                )
                await MainActor.run {
                    self.verdaccioUserMutationResult = result
                    self.registryActionMessage = "Deleted Verdaccio user \(result.username). Backup: \(result.backupPath)."
                    self.isMutatingVerdaccioUser = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry_user",
                    targetId: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    action: "verdaccio-delete-user",
                    beforeSnapshot: nil,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
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
        repository: ServerRepository,
        actionName: String,
        auditAction: String,
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
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry_user",
                    targetId: result.username,
                    action: "verdaccio-\(self.verdaccioUserAuditLabel(result.action))-user",
                    beforeSnapshot: "backup=\(result.backupPath)",
                    afterSnapshot: "htpasswd=\(result.htpasswdPath)",
                    status: "success",
                    message: "\(actionName) Verdaccio user \(result.username)."
                )
                await MainActor.run {
                    self.verdaccioUserMutationResult = result
                    self.verdaccioPasswordDraft = ""
                    self.registryActionMessage = "\(actionName) Verdaccio user \(result.username). Backup: \(result.backupPath)."
                    self.isMutatingVerdaccioUser = false
                }
            } catch {
                self.saveRemoteChangeLog(
                    repository: repository,
                    profile: profile,
                    targetType: "registry_user",
                    targetId: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    action: auditAction,
                    beforeSnapshot: nil,
                    afterSnapshot: nil,
                    status: "failed",
                    message: error.localizedDescription
                )
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
        localPath: String,
        message: String? = nil,
        profile: ServerProfile,
        repository: ServerRepository?
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
            message: message,
            startedAt: Date(),
            finishedAt: nil
        ), at: 0)
        persistRemoteFileTransferJob(id, profile: profile, repository: repository)
        return id
    }

    private func resumeRemoteFileTransferJob(
        _ job: RemoteFileTransferJob,
        profile: ServerProfile,
        repository: ServerRepository?
    ) -> UUID {
        if let index = remoteFileTransferJobs.firstIndex(where: { $0.id == job.id }) {
            remoteFileTransferJobs.remove(at: index)
        }
        var resumed = job
        resumed.status = .pending
        resumed.message = "Resuming previous \(job.direction.displayName.lowercased()) transfer."
        resumed.startedAt = Date()
        resumed.finishedAt = nil
        if resumed.progressFraction == nil {
            resumed.progressFraction = 0
        }
        remoteFileTransferJobs.insert(resumed, at: 0)
        persistRemoteFileTransferJob(resumed.id, profile: profile, repository: repository)
        return resumed.id
    }

    private func startNextRemoteFileTransferIfNeeded() {
        reorderPendingRemoteFileTransferJobsToMatchQueue()

        guard !isRemoteFileTransferQueuePaused else {
            isTransferringRemoteFile = !transferTasksByJobId.isEmpty
            return
        }

        while transferTasksByJobId.count < maximumConcurrentRemoteFileTransfers, !transferQueue.isEmpty {
            let request = transferQueue.removeFirst()
            isTransferringRemoteFile = true
            runningTransferRequestsByJobId[request.jobId] = request
            markRemoteFileTransferJobRunning(request.jobId)
            persistRemoteFileTransferJob(request.jobId, profile: request.profile, repository: request.repository)

            transferTasksByJobId[request.jobId] = Task {
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
    }

    private func reorderPendingRemoteFileTransfer(
        _ job: RemoteFileTransferJob,
        targetQueueIndex: Int,
        actionMessage: String
    ) {
        guard job.status == .pending else { return }
        guard let queueIndex = transferQueue.firstIndex(where: { $0.jobId == job.id }) else { return }

        let request = transferQueue.remove(at: queueIndex)
        let boundedIndex = min(max(targetQueueIndex, 0), transferQueue.count)
        transferQueue.insert(request, at: boundedIndex)
        reorderPendingRemoteFileTransferJobsToMatchQueue()
        remoteFileErrorMessage = nil
        remoteFileActionMessage = actionMessage
    }

    private func reorderPendingRemoteFileTransferJobsToMatchQueue() {
        let queuedIds = transferQueue.map(\.jobId)
        guard !queuedIds.isEmpty else { return }

        let queuedIdSet = Set(queuedIds)
        let queuedJobsById = Dictionary(uniqueKeysWithValues: remoteFileTransferJobs
            .filter { queuedIdSet.contains($0.id) }
            .map { ($0.id, $0) })
        let orderedQueuedJobs = queuedIds.compactMap { queuedJobsById[$0] }
        var remainingJobs = remoteFileTransferJobs.filter { !queuedIdSet.contains($0.id) }
        let insertionIndex = remainingJobs.firstIndex { $0.status.isTerminal } ?? remainingJobs.count
        remainingJobs.insert(contentsOf: orderedQueuedJobs, at: insertionIndex)
        remoteFileTransferJobs = remainingJobs
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
                transferClient: transferClient,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.updateRemoteFileTransferJob(
                            jobId,
                            progress: progress,
                            profile: profile,
                            repository: repository
                        )
                    }
                }
            )
            let listing = try await remoteFileService.listDirectory(
                path: self.remoteFilePath,
                profile: profile,
                sshClient: sshClient
            )
            await MainActor.run {
                guard self.remoteFileTransferJobStatus(jobId) == .running else {
                    self.finishRunningRemoteFileTransfer(jobId)
                    return
                }
                self.remoteDirectoryListing = listing
                self.remoteFilePath = listing.path
                self.remoteFileActionMessage = "Uploaded \(localURL.lastPathComponent) to \(result.remotePath)."
                self.finishRemoteFileTransferJob(jobId, status: .succeeded, result: result, message: self.remoteFileActionMessage)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer(jobId)
            }
        } catch is CancellationError {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer(jobId)
            }
        } catch SSHClientError.cancelled {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer(jobId)
            }
        } catch {
            await MainActor.run {
                guard self.remoteFileTransferJobStatus(jobId) == .running else {
                    self.finishRunningRemoteFileTransfer(jobId)
                    return
                }
                self.remoteFileErrorMessage = error.localizedDescription
                self.finishRemoteFileTransferJob(jobId, status: .failed, message: error.localizedDescription)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer(jobId)
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
                transferClient: transferClient,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.updateRemoteFileTransferJob(
                            jobId,
                            progress: progress,
                            profile: profile,
                            repository: repository
                        )
                    }
                }
            )
            await MainActor.run {
                guard self.remoteFileTransferJobStatus(jobId) == .running else {
                    self.finishRunningRemoteFileTransfer(jobId)
                    return
                }
                self.remoteFileActionMessage = "Downloaded \(entry.name) to \(result.localPath)."
                self.finishRemoteFileTransferJob(jobId, status: .succeeded, result: result, message: self.remoteFileActionMessage)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer(jobId)
            }
        } catch is CancellationError {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer(jobId)
            }
        } catch SSHClientError.cancelled {
            await MainActor.run {
                self.cancelRemoteFileTransferJobIfRunning(jobId)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer(jobId)
            }
        } catch {
            await MainActor.run {
                guard self.remoteFileTransferJobStatus(jobId) == .running else {
                    self.finishRunningRemoteFileTransfer(jobId)
                    return
                }
                self.remoteFileErrorMessage = error.localizedDescription
                self.finishRemoteFileTransferJob(jobId, status: .failed, message: error.localizedDescription)
                self.persistRemoteFileTransferJob(jobId, profile: profile, repository: repository)
                self.finishRunningRemoteFileTransfer(jobId)
            }
        }
    }

    private func markRemoteFileTransferJobRunning(_ id: UUID) {
        guard let index = remoteFileTransferJobs.firstIndex(where: { $0.id == id }) else { return }
        remoteFileTransferJobs[index].status = .running
        remoteFileTransferJobs[index].progressFraction = remoteFileTransferJobs[index].progressFraction ?? 0
        remoteFileTransferJobs[index].startedAt = Date()
    }

    private func finishRunningRemoteFileTransfer(_ id: UUID) {
        transferTasksByJobId[id] = nil
        runningTransferRequestsByJobId[id] = nil
        isTransferringRemoteFile = !transferTasksByJobId.isEmpty
        startNextRemoteFileTransferIfNeeded()
    }

    private func remoteFileTransferJobStatus(_ id: UUID) -> RemoteFileTransferStatus? {
        remoteFileTransferJobs.first(where: { $0.id == id })?.status
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
        if let result {
            remoteFileTransferJobs[index].backend = result.backend
            remoteFileTransferJobs[index].supportsResume = result.supportsResume
            remoteFileTransferJobs[index].supportsStreamingProgress = result.supportsStreamingProgress
        }
        remoteFileTransferJobs[index].progressFraction = status == .succeeded ? 1 : remoteFileTransferJobs[index].progressFraction
        remoteFileTransferJobs[index].message = message
        remoteFileTransferJobs[index].finishedAt = Date()
    }

    private func updateRemoteFileTransferJob(
        _ id: UUID,
        progress: RemoteFileTransferProgress,
        profile: ServerProfile,
        repository: ServerRepository?
    ) {
        guard let index = remoteFileTransferJobs.firstIndex(where: { $0.id == id }) else { return }
        guard remoteFileTransferJobs[index].status == .running else { return }
        if let totalBytes = progress.totalBytes {
            remoteFileTransferJobs[index].byteCount = totalBytes
        }
        remoteFileTransferJobs[index].supportsStreamingProgress = true
        if let fraction = progress.fraction {
            remoteFileTransferJobs[index].progressFraction = fraction
        } else if let completed = progress.completedBytes,
                  let total = progress.totalBytes,
                  total > 0 {
            remoteFileTransferJobs[index].progressFraction = min(max(Double(completed) / Double(total), 0), 1)
        }
        remoteFileTransferJobs[index].message = Self.remoteFileTransferProgressMessage(progress)
        persistRemoteFileTransferJob(id, profile: profile, repository: repository)
    }

    private static func remoteFileTransferProgressMessage(_ progress: RemoteFileTransferProgress) -> String? {
        guard let completed = progress.completedBytes else {
            return nil
        }
        let progressText: String
        if let total = progress.totalBytes, total > 0 {
            progressText = "Transferred \(formatTransferBytes(completed)) of \(formatTransferBytes(total))"
        } else {
            progressText = "Transferred \(formatTransferBytes(completed))"
        }

        var details: [String] = []
        if let rate = progress.transferRateBytesPerSecond, rate > 0 {
            details.append("\(formatTransferBytes(Int64(rate.rounded())))/s")
        }
        if let eta = progress.estimatedSecondsRemaining, eta > 0 {
            details.append("ETA \(formatTransferDuration(eta))")
        }
        if details.isEmpty {
            return "\(progressText)."
        }
        return "\(progressText) · \(details.joined(separator: " · "))."
    }

    private static func formatTransferBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1_024, unitIndex < units.count - 1 {
            value /= 1_024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(value)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    private static func formatTransferDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private static func remoteFileTransferDisplayName(_ job: RemoteFileTransferJob) -> String {
        switch job.direction {
        case .upload:
            return URL(fileURLWithPath: job.localPath).lastPathComponent
        case .download:
            return URL(fileURLWithPath: job.remotePath).lastPathComponent
        }
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

    var profile: ServerProfile {
        switch self {
        case let .upload(_, _, _, profile, _, _, _, _):
            profile
        case let .download(_, _, _, profile, _, _, _):
            profile
        }
    }

    var repository: ServerRepository? {
        switch self {
        case let .upload(_, _, _, _, _, _, _, repository):
            repository
        case let .download(_, _, _, _, _, _, repository):
            repository
        }
    }
}

private extension String {
    var withTableBounds: String {
        "| \(self) |"
    }
}
