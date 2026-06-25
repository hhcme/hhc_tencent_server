import XCTest
@testable import HHCServerManager

@MainActor
final class ServerWorkspaceViewModelTests: XCTestCase {
    func testRemoteOperationRiskFactoryBuildsConfirmationMessages() {
        let unit = SystemdUnit(
            name: "nginx.service",
            loadState: "loaded",
            activeState: "active",
            subState: "running",
            description: "Nginx"
        )
        let entry = CronEntry(
            schedule: "0 2 * * *",
            command: "/usr/bin/backup",
            isEnabled: true,
            originalLine: "0 2 * * * /usr/bin/backup"
        )
        let file = RemoteFileEntry(
            name: "config.yml",
            path: "/srv/app/config.yml",
            kind: .file,
            size: 12,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        let restartRisk = RemoteOperationRiskFactory.systemd(action: .restart, unit: unit)
        XCTAssertEqual(restartRisk.level, .high)
        XCTAssertEqual(restartRisk.auditTargetType, "systemd")
        XCTAssertTrue(restartRisk.confirmationMessage.contains("systemctl restart nginx.service"))

        let cronDeleteRisk = RemoteOperationRiskFactory.cron(action: .delete, entry: entry)
        XCTAssertEqual(cronDeleteRisk.level, .high)
        XCTAssertTrue(cronDeleteRisk.confirmationMessage.contains("crontab <updated file>"))
        XCTAssertTrue(cronDeleteRisk.confirmationMessage.contains("backup"))

        let permissiveChmodRisk = RemoteOperationRiskFactory.changePermissions(entry: file, mode: "777")
        XCTAssertEqual(permissiveChmodRisk.level, .high)
        XCTAssertTrue(permissiveChmodRisk.confirmationMessage.contains("chmod 777"))

        let nginxSaveRisk = RemoteOperationRiskFactory.saveNginxConfig(path: "/etc/nginx/nginx.conf")
        XCTAssertEqual(nginxSaveRisk.level, .high)
        XCTAssertTrue(nginxSaveRisk.confirmationMessage.contains("rollback"))

        let environmentRisk = RemoteOperationRiskFactory.saveEnvironmentFile(path: "/srv/app/.env")
        XCTAssertEqual(environmentRisk.auditTargetType, "environment")
        XCTAssertTrue(environmentRisk.confirmationMessage.contains("Environment changes"))
    }

    func testCloudSecurityGroupRuleChangePreviewBuildsDiffAndRisk() {
        let group = CloudSecurityGroup(
            accountId: UUID(),
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            securityGroupId: "sg-123",
            name: "prod",
            description: nil,
            projectId: nil,
            isDefault: false,
            createdTime: nil,
            updatedTime: nil
        )
        let existingRule = CloudSecurityGroupRule(
            direction: .ingress,
            policyIndex: 0,
            protocolName: "TCP",
            port: "443",
            cidrBlock: "10.0.0.0/8",
            ipv6CidrBlock: nil,
            referencedSecurityGroupId: nil,
            action: "ACCEPT",
            description: nil,
            modifiedTime: nil
        )
        let snapshot = CloudSecurityGroupPolicySnapshot(
            group: group,
            version: "1",
            ingress: [existingRule],
            egress: [],
            capturedAt: Date()
        )
        let draft = CloudSecurityGroupRuleDraft(
            direction: .ingress,
            protocolName: "tcp",
            port: "22",
            cidrBlock: "0.0.0.0/0",
            action: "accept",
            description: "ssh"
        )

        let preview = CloudSecurityGroupRuleChangePreview.adding(draft: draft, to: snapshot)
        let risk = RemoteOperationRiskFactory.securityGroupChange(preview)

        XCTAssertEqual(preview.beforeIngressCount, 1)
        XCTAssertEqual(preview.afterIngressCount, 2)
        XCTAssertEqual(preview.afterEgressCount, 0)
        XCTAssertEqual(preview.proposedRule.protocolName, "TCP")
        XCTAssertEqual(preview.proposedRule.action, "ACCEPT")
        XCTAssertTrue(preview.commandPreview.contains("AuthorizeSecurityGroupIngress"))
        XCTAssertTrue(preview.warnings.contains { $0.contains("public internet") })
        XCTAssertEqual(risk.level, .critical)
        XCTAssertTrue(risk.confirmationMessage.contains("Ingress rules: 1 -> 2"))

        let removePreview = CloudSecurityGroupRuleChangePreview.removing(rule: existingRule, from: snapshot)
        XCTAssertEqual(removePreview.afterIngressCount, 0)
        XCTAssertTrue(removePreview.warnings.contains { $0.contains("interrupt") })
    }

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

    func testDeploymentProjectDraftSavesAndBuildsPreview() throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let viewModel = ServerWorkspaceViewModel()

        viewModel.startNewDeploymentProject(serverId: profile.id)
        viewModel.deploymentName = "API"
        viewModel.deploymentRepositoryURL = "git@gitlab.com:hhc/api.git"
        viewModel.deploymentBranch = "release/2026.06"
        viewModel.deploymentPath = "/srv/api"
        viewModel.deploymentBuildCommand = "npm ci && npm run build"
        viewModel.deploymentRestartCommand = "systemctl restart api.service"
        viewModel.refreshDeploymentPlan()
        viewModel.saveDeploymentProject(profile: profile, repository: repository)

        XCTAssertNil(viewModel.deploymentErrorMessage)
        XCTAssertEqual(viewModel.deploymentProjects.map(\.name), ["API"])
        XCTAssertEqual(viewModel.selectedDeploymentProject?.deployPath, "/srv/api")
        XCTAssertTrue(viewModel.deploymentCommandPlan?.commandPreview.contains("git reset --hard 'origin/release/2026.06'") == true)
        XCTAssertTrue(viewModel.deploymentCommandPlan?.commandPreview.contains("systemctl restart api.service") == true)
    }

    func testRunDeploymentPersistsRunLogsFromWorkspace() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let viewModel = ServerWorkspaceViewModel()
        let client = DeploymentWorkspaceMockSSHClient()
        let runner = DeploymentRunner(
            repository: repository,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        viewModel.startNewDeploymentProject(serverId: profile.id)
        viewModel.deploymentName = "API"
        viewModel.deploymentRepositoryURL = "git@gitlab.com:hhc/api.git"
        viewModel.deploymentBranch = "main"
        viewModel.deploymentPath = "/srv/api"
        viewModel.deploymentBuildCommand = "npm run build"

        viewModel.runDeployment(
            profile: profile,
            sshClient: client,
            deploymentRunner: runner,
            repository: repository
        )
        try await waitUntil { viewModel.isRunningDeployment == false && viewModel.selectedDeploymentRun != nil }

        XCTAssertEqual(viewModel.selectedDeploymentRun?.status, .succeeded)
        XCTAssertEqual(viewModel.selectedDeploymentRun?.previousCommit, "abc123")
        XCTAssertEqual(viewModel.selectedDeploymentRun?.targetCommit, "def456")
        XCTAssertTrue(viewModel.deploymentLogs.contains { $0.stepName == "finish" && $0.message == "Deployment completed." })
        XCTAssertTrue(client.commands.contains { $0.contains("git reset --hard 'origin/main'") })
    }

    func testCancelCommandStopsRunningStateAndShowsCancellationSummary() async throws {
        let profile = makeProfile()
        let client = SlowSSHClient()
        let viewModel = ServerWorkspaceViewModel()

        viewModel.executeCommand("sleep 30", profile: profile, sshClient: client)
        try await waitUntil { viewModel.isRunningCommand }
        viewModel.cancelCommand()

        XCTAssertFalse(viewModel.isRunningCommand)
        XCTAssertEqual(viewModel.lastCommandFailure, CommandFailureSummary(
            command: "sleep 30",
            message: "Command was cancelled."
        ))
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

    func testRefreshDashboardLoadsCapabilitiesAndMetrics() async throws {
        let profile = makeProfile()
        let client = DashboardMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()

        viewModel.refreshDashboard(
            profile: profile,
            sshClient: client,
            dashboardService: DashboardService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        )
        try await waitUntil { viewModel.isRefreshingDashboard == false && viewModel.dashboardSnapshot != nil }

        let snapshot = try XCTUnwrap(viewModel.dashboardSnapshot)
        XCTAssertEqual(snapshot.capabilities.osName, "Ubuntu 24.04.2 LTS")
        XCTAssertEqual(snapshot.capabilities.kernelVersion, "6.8.0")
        XCTAssertTrue(snapshot.capabilities.hasProc)
        XCTAssertTrue(snapshot.capabilities.hasSystemd)
        XCTAssertTrue(snapshot.capabilities.hasSFTP)
        XCTAssertEqual(snapshot.metrics.map(\.name), ["Load Average", "Memory", "Root Disk", "CPU Cores", "Network", "Processes"])
        XCTAssertTrue(snapshot.warnings.isEmpty)
        XCTAssertNil(viewModel.dashboardErrorMessage)
    }

    func testRefreshDashboardKeepsPartialSnapshotWhenOptionalMetricFails() async throws {
        let profile = makeProfile()
        let client = DashboardPartialFailureMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()

        viewModel.refreshDashboard(
            profile: profile,
            sshClient: client,
            dashboardService: DashboardService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        )
        try await waitUntil { viewModel.isRefreshingDashboard == false && viewModel.dashboardSnapshot != nil }

        let snapshot = try XCTUnwrap(viewModel.dashboardSnapshot)
        XCTAssertEqual(snapshot.metrics.map(\.name), ["Load Average", "Memory", "Root Disk", "CPU Cores", "Processes"])
        XCTAssertEqual(snapshot.warnings, [
            DashboardWarning(source: "Network", message: "network unavailable"),
        ])
        XCTAssertNil(viewModel.dashboardErrorMessage)
    }

    func testDashboardAutoRefreshRunsImmediatelyAndStopsWhenDisabled() async throws {
        let profile = makeProfile()
        let client = DashboardMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = DashboardService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.setDashboardAutoRefreshEnabled(
            true,
            profile: profile,
            sshClient: client,
            dashboardService: service,
            interval: .milliseconds(50)
        )

        try await waitUntil { client.snapshotRequests >= 1 && viewModel.dashboardSnapshot != nil }
        try await waitUntil { client.snapshotRequests >= 2 }

        viewModel.stopDashboardAutoRefresh()
        try await waitUntil { !viewModel.isRefreshingDashboard }
        let requestsAfterStop = client.snapshotRequests
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertFalse(viewModel.isDashboardAutoRefreshEnabled)
        XCTAssertEqual(client.snapshotRequests, requestsAfterStop)
        XCTAssertNil(viewModel.dashboardErrorMessage)
    }

    func testLoadRemoteFilesListsDirectoryAndOpensChildDirectory() async throws {
        let profile = makeProfile()
        let client = RemoteFileMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadRemoteFiles(
            path: "/var/www",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.isLoadingRemoteFiles == false && viewModel.remoteDirectoryListing != nil }

        var listing = try XCTUnwrap(viewModel.remoteDirectoryListing)
        XCTAssertEqual(viewModel.remoteFilePath, "/var/www")
        XCTAssertEqual(listing.entries.map(\.name), ["logs", "index.html"])
        XCTAssertNil(viewModel.remoteFileErrorMessage)

        viewModel.openRemoteFileEntry(
            listing.entries[0],
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil {
            viewModel.remoteDirectoryListing?.path == "/var/www/logs" &&
                viewModel.remoteDirectoryListing?.entries.map(\.name) == ["app.log"]
        }

        listing = try XCTUnwrap(viewModel.remoteDirectoryListing)
        XCTAssertEqual(listing.path, "/var/www/logs")
        XCTAssertEqual(listing.entries.map(\.name), ["app.log"])
    }

    func testRemoteFileActionsRenameAndMoveToTrashThenRefreshListing() async throws {
        let profile = makeProfile()
        let client = RemoteFileActionMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadRemoteFiles(
            path: "/var/www",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.map(\.name) == ["index.html"] }
        let original = try XCTUnwrap(viewModel.remoteDirectoryListing?.entries.first)

        viewModel.renameRemoteFile(
            original,
            to: "home.html",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.map(\.name) == ["home.html"] }
        XCTAssertEqual(viewModel.remoteFileActionMessage, "Renamed index.html.")
        XCTAssertTrue(client.commands.contains("mv -n -- '/var/www/index.html' '/var/www/home.html'"))

        let renamed = try XCTUnwrap(viewModel.remoteDirectoryListing?.entries.first)
        viewModel.moveRemoteFileToTrash(
            renamed,
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.isEmpty == true }
        XCTAssertTrue(viewModel.remoteFileActionMessage?.contains("Moved home.html to ~/.hhc-server-manager-trash/") == true)
        XCTAssertTrue(client.commands.contains { $0.contains("mkdir -p -- '~/.hhc-server-manager-trash'") })
        XCTAssertNil(viewModel.remoteFileErrorMessage)
    }

    func testRemoteTextFileOpenAndSaveRefreshesListingWithBackupMessage() async throws {
        let profile = makeProfile()
        let client = RemoteTextFileMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadRemoteFiles(
            path: "/var/www",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.map(\.name) == ["app.env"] }
        let entry = try XCTUnwrap(viewModel.remoteDirectoryListing?.entries.first)

        viewModel.openRemoteTextFile(
            entry,
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteTextFile?.content == "hello\n" }
        XCTAssertEqual(viewModel.remoteTextDraft, "hello\n")
        XCTAssertNil(viewModel.remoteFileErrorMessage)

        viewModel.remoteTextDraft = "updated\n"
        viewModel.saveRemoteTextFile(
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteFileActionMessage?.hasPrefix("Saved /var/www/app.env.") == true }

        XCTAssertEqual(viewModel.remoteTextFile?.content, "updated\n")
        XCTAssertEqual(client.content, "updated\n")
        XCTAssertTrue(viewModel.remoteFileActionMessage?.contains("Backup: /var/www/app.env.hhc-backup-") == true)
        XCTAssertEqual(viewModel.remoteDirectoryListing?.entries.map(\.name), ["app.env"])
        XCTAssertNil(viewModel.remoteFileErrorMessage)
    }

    func testRemoteTextFileSaveAsRefreshesTargetDirectoryWithoutBackupMessage() async throws {
        let profile = makeProfile()
        let client = RemoteTextFileMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadRemoteFiles(
            path: "/var/www",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.map(\.name) == ["app.env"] }
        let entry = try XCTUnwrap(viewModel.remoteDirectoryListing?.entries.first)

        viewModel.openRemoteTextFile(
            entry,
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteTextFile?.content == "hello\n" }

        viewModel.remoteTextDraft = "copy\n"
        viewModel.saveRemoteTextFileAs(
            targetPath: "/var/www/copy.env",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteFileActionMessage == "Saved /var/www/copy.env." }

        XCTAssertEqual(viewModel.remoteTextFile?.path, "/var/www/copy.env")
        XCTAssertEqual(viewModel.remoteTextFile?.content, "copy\n")
        XCTAssertEqual(viewModel.remoteDirectoryListing?.entries.map(\.name), ["app.env", "copy.env"])
        XCTAssertNil(viewModel.remoteFileErrorMessage)
    }

    func testRemoteFilePermissionsChangeRefreshesListing() async throws {
        let profile = makeProfile()
        let client = RemoteTextFileMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadRemoteFiles(
            path: "/var/www",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.map(\.name) == ["app.env"] }
        let entry = try XCTUnwrap(viewModel.remoteDirectoryListing?.entries.first)

        viewModel.changeRemoteFilePermissions(
            entry,
            mode: "640",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.first?.permissions == "-rw-r-----" }

        XCTAssertEqual(viewModel.remoteFileActionMessage, "Changed permissions for app.env to 640.")
        XCTAssertNil(viewModel.remoteFileErrorMessage)
    }

    func testRemoteFileUploadAndDownloadUpdateTransferStateAndMessages() async throws {
        let profile = makeProfile()
        let client = RemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let uploadURL = URL(fileURLWithPath: "/tmp/upload.env")
        let downloadURL = URL(fileURLWithPath: "/tmp/download.env")

        viewModel.loadRemoteFiles(
            path: "/var/www",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.map(\.name) == ["app.env"] }

        viewModel.uploadRemoteFile(
            localURL: uploadURL,
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.map(\.name) == ["app.env", "upload.env"] }
        XCTAssertEqual(client.uploads.map(\.remotePath), ["/var/www/upload.env"])
        XCTAssertEqual(viewModel.remoteFileActionMessage, "Uploaded upload.env to /var/www/upload.env.")
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.direction, .upload)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.status, .succeeded)

        let entry = try XCTUnwrap(viewModel.remoteDirectoryListing?.entries.first { $0.name == "app.env" })
        viewModel.downloadRemoteFile(
            entry,
            to: downloadURL,
            profile: profile,
            transferClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteFileActionMessage == "Downloaded app.env to /tmp/download.env." }
        XCTAssertEqual(client.downloads.map(\.remotePath), ["/var/www/app.env"])
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.direction, .download)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.status, .succeeded)
        XCTAssertFalse(viewModel.isTransferringRemoteFile)
        XCTAssertNil(viewModel.remoteFileErrorMessage)
    }

    func testRemoteFileTransferCancellationMarksRunningJobCancelled() async throws {
        let profile = makeProfile()
        let client = SlowRemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/large.log"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.isTransferringRemoteFile && viewModel.remoteFileTransferJobs.first?.status == .running }

        viewModel.cancelRemoteFileTransfer()
        try await waitUntil { viewModel.remoteFileTransferJobs.first?.status == .cancelled }

        XCTAssertFalse(viewModel.isTransferringRemoteFile)
        XCTAssertEqual(viewModel.remoteFileActionMessage, "Transfer cancelled.")
        XCTAssertNil(viewModel.remoteFileErrorMessage)
    }

    func testRemoteFileTransfersRunSeriallyWithPendingQueueState() async throws {
        let profile = makeProfile()
        let client = QueuedRemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadRemoteFiles(
            path: "/var/www",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing != nil }

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/first.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteFileTransferJobs.first?.status == .running }

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/second.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service
        )

        XCTAssertEqual(viewModel.remoteFileTransferJobs.map(\.status), [.pending, .running])
        try await waitUntil {
            viewModel.remoteFileTransferJobs.count == 2 &&
                viewModel.remoteFileTransferJobs.allSatisfy { $0.status == .succeeded }
        }

        XCTAssertEqual(client.uploads.map(\.remotePath), ["/var/www/first.env", "/var/www/second.env"])
        XCTAssertFalse(viewModel.isTransferringRemoteFile)
        XCTAssertNil(viewModel.remoteFileErrorMessage)
    }

    func testCancelPendingRemoteFileTransfersLeavesRunningTransferActive() async throws {
        let profile = makeProfile()
        let client = QueuedRemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/running.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteFileTransferJobs.first?.status == .running }

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/pending.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service
        )
        XCTAssertEqual(viewModel.remoteFileTransferJobs.map(\.status), [.pending, .running])

        viewModel.cancelPendingRemoteFileTransfers()

        XCTAssertEqual(viewModel.remoteFileTransferJobs.map(\.status), [.cancelled, .running])
        XCTAssertTrue(viewModel.isTransferringRemoteFile)
        try await waitUntil { viewModel.remoteFileTransferJobs.last?.status == .succeeded }
        XCTAssertEqual(client.uploads.map(\.remotePath), ["~/running.env"])
    }

    func testSystemdUnitsLoadSelectAndPerformAction() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = SystemdViewModelMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let manager = SystemdServiceManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadSystemdUnits(profile: profile, sshClient: client, systemdServiceManager: manager)
        try await waitUntil { viewModel.isLoadingSystemdUnits == false && viewModel.systemdUnitList != nil }

        XCTAssertEqual(viewModel.systemdUnitList?.units.map(\.name), ["nginx.service", "ssh.service"])
        XCTAssertEqual(viewModel.selectedSystemdUnit?.name, "nginx.service")
        XCTAssertNil(viewModel.systemdErrorMessage)

        let sshUnit = try XCTUnwrap(viewModel.systemdUnitList?.units.first { $0.name == "ssh.service" })
        viewModel.selectSystemdUnit(sshUnit, profile: profile, sshClient: client, systemdServiceManager: manager)
        try await waitUntil { viewModel.systemdJournalLog?.unitName == "ssh.service" }
        XCTAssertTrue(viewModel.systemdJournalLog?.text.contains("ssh ready") == true)

        viewModel.performSystemdAction(.restart, unitName: "ssh.service", profile: profile, sshClient: client, systemdServiceManager: manager, repository: repository)
        try await waitUntil { viewModel.isPerformingSystemdAction == false && viewModel.systemdActionMessage != nil }

        XCTAssertEqual(viewModel.systemdActionMessage, "Restart requested for ssh.service.")
        XCTAssertTrue(client.commands.contains("systemctl restart -- 'ssh.service'"))
        XCTAssertEqual(viewModel.selectedSystemdUnit?.name, "ssh.service")

        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].targetType, "systemd")
        XCTAssertEqual(logs[0].targetId, "ssh.service")
        XCTAssertEqual(logs[0].action, "restart")
        XCTAssertEqual(logs[0].status, "success")
        XCTAssertTrue(logs[0].beforeSnapshot?.contains("name=ssh.service") == true)
    }

    func testCronEntriesLoadAddDisableAndDelete() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = CronViewModelMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let manager = CronManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadCron(profile: profile, sshClient: client, cronManager: manager)
        try await waitUntil { viewModel.isLoadingCron == false && viewModel.cronSnapshot != nil }

        XCTAssertEqual(viewModel.cronSnapshot?.entries.map(\.command), ["/usr/bin/backup"])
        XCTAssertNil(viewModel.cronErrorMessage)

        viewModel.addCronEntry(schedule: "*/5 * * * *", command: "/usr/bin/health", profile: profile, sshClient: client, cronManager: manager, repository: repository)
        try await waitUntil { viewModel.isMutatingCron == false && viewModel.cronSnapshot?.entries.count == 2 }

        XCTAssertEqual(viewModel.cronActionMessage, "Added cron entry.")
        let health = try XCTUnwrap(viewModel.cronSnapshot?.entries.first { $0.command == "/usr/bin/health" })
        XCTAssertTrue(health.isEnabled)

        viewModel.performCronEntryAction(.disable, entry: health, profile: profile, sshClient: client, cronManager: manager, repository: repository)
        try await waitUntil { viewModel.cronSnapshot?.entries.first { $0.command == "/usr/bin/health" }?.isEnabled == false }
        XCTAssertEqual(viewModel.cronActionMessage, "Disable requested for cron entry.")

        let disabled = try XCTUnwrap(viewModel.cronSnapshot?.entries.first { $0.command == "/usr/bin/health" })
        viewModel.performCronEntryAction(.delete, entry: disabled, profile: profile, sshClient: client, cronManager: manager, repository: repository)
        try await waitUntil { viewModel.cronSnapshot?.entries.count == 1 }
        XCTAssertEqual(viewModel.cronSnapshot?.entries.map(\.command), ["/usr/bin/backup"])

        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        XCTAssertEqual(logs.map(\.action), ["delete", "disable", "add"])
        XCTAssertEqual(logs.map(\.targetType), ["cron", "cron", "cron"])
        XCTAssertTrue(logs[0].beforeSnapshot?.contains("# HHC_DISABLED */5 * * * * /usr/bin/health") == true)
        XCTAssertFalse(logs[0].afterSnapshot?.contains("/usr/bin/health") == true)
    }

    func testNginxConfigsLoadSelectTestAndReload() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = NginxViewModelMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let manager = NginxConfigManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadNginxConfigs(profile: profile, sshClient: client, nginxConfigManager: manager)
        try await waitUntil { viewModel.isLoadingNginxConfigs == false && viewModel.nginxConfigList != nil }
        try await waitUntil { viewModel.isLoadingNginxConfigContent == false && viewModel.nginxConfigContent != nil }

        XCTAssertEqual(viewModel.nginxConfigList?.files.map(\.path), ["/www/server/nginx/conf/nginx.conf", "/www/server/nginx/conf/vhost/site.conf"])
        XCTAssertEqual(viewModel.selectedNginxConfig?.path, "/www/server/nginx/conf/nginx.conf")
        XCTAssertTrue(viewModel.nginxConfigContent?.content.contains("user www-data;") == true)
        XCTAssertNil(viewModel.nginxErrorMessage)

        let site = try XCTUnwrap(viewModel.nginxConfigList?.files.first { $0.path.contains("/vhost/") })
        viewModel.selectNginxConfig(site, profile: profile, sshClient: client, nginxConfigManager: manager)
        try await waitUntil { viewModel.nginxConfigContent?.file.path == site.path }
        XCTAssertTrue(viewModel.nginxConfigContent?.content.contains("server_name example.com;") == true)

        viewModel.testNginxConfig(profile: profile, sshClient: client, nginxConfigManager: manager)
        try await waitUntil { viewModel.isTestingNginxConfig == false && viewModel.nginxTestResult != nil }
        XCTAssertEqual(viewModel.nginxActionMessage, "Nginx configuration test passed.")

        viewModel.reloadNginx(profile: profile, sshClient: client, nginxConfigManager: manager, repository: repository)
        try await waitUntil { viewModel.isReloadingNginx == false && viewModel.nginxActionMessage == "Reloaded Nginx." }
        XCTAssertTrue(client.commands.contains("systemctl reload nginx 2>/dev/null || nginx -s reload"))

        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].targetType, "nginx")
        XCTAssertEqual(logs[0].targetId, "/www/server/nginx/conf/vhost/site.conf")
        XCTAssertEqual(logs[0].action, "reload")
        XCTAssertEqual(logs[0].status, "success")
        XCTAssertTrue(logs[0].afterSnapshot?.contains("syntax is ok") == true)

        viewModel.nginxConfigDraft = "server { server_name edited.example.com; }\n"
        viewModel.saveNginxConfig(profile: profile, sshClient: client, nginxConfigManager: manager, repository: repository)
        try await waitUntil { viewModel.isSavingNginxConfig == false && viewModel.nginxActionMessage?.contains("Saved Nginx config") == true }
        XCTAssertTrue(viewModel.nginxConfigContent?.content.contains("edited.example.com") == true)

        client.testSucceeds = false
        viewModel.nginxConfigDraft = "broken;"
        viewModel.saveNginxConfig(profile: profile, sshClient: client, nginxConfigManager: manager, repository: repository)
        try await waitUntil { viewModel.isSavingNginxConfig == false && viewModel.nginxActionMessage?.contains("Restored backup") == true }
        XCTAssertTrue(viewModel.nginxConfigContent?.content.contains("edited.example.com") == true)

        let updatedLogs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        XCTAssertEqual(updatedLogs.map(\.action).prefix(3), ["save", "save", "reload"])
        XCTAssertEqual(updatedLogs.map(\.status).prefix(3), ["failed", "success", "success"])
    }

    func testFirewallSnapshotLoads() async throws {
        let profile = makeProfile()
        let client = FirewallViewModelMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let manager = FirewallManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadFirewallSnapshot(profile: profile, sshClient: client, firewallManager: manager)
        try await waitUntil { viewModel.isLoadingFirewall == false && viewModel.firewallSnapshot != nil }

        XCTAssertEqual(viewModel.firewallSnapshot?.backend, .iptables)
        XCTAssertEqual(viewModel.firewallSnapshot?.status, "installed")
        XCTAssertTrue(viewModel.firewallSnapshot?.rulesText.contains("--dport 22") == true)
        XCTAssertNil(viewModel.firewallErrorMessage)
    }

    func testEnvironmentFilesLoadSelectAndSaveWithAudit() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = EnvironmentViewModelMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let manager = EnvironmentFileManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadEnvironmentFiles(profile: profile, sshClient: client, environmentFileManager: manager)
        try await waitUntil { viewModel.isLoadingEnvironmentFiles == false && viewModel.environmentFileList != nil }
        try await waitUntil { viewModel.isLoadingEnvironmentFileContent == false && viewModel.environmentFileContent != nil }

        XCTAssertEqual(viewModel.environmentFileList?.files.map(\.path), ["/etc/default/nginx", "/var/www/app/.env"])
        XCTAssertEqual(viewModel.selectedEnvironmentFile?.path, "/etc/default/nginx")
        XCTAssertTrue(viewModel.environmentFileContent?.content.contains("NGINX_DEBUG=0") == true)
        XCTAssertNil(viewModel.environmentErrorMessage)

        let appEnv = try XCTUnwrap(viewModel.environmentFileList?.files.first { $0.path.hasSuffix(".env") })
        viewModel.selectEnvironmentFile(appEnv, profile: profile, sshClient: client, environmentFileManager: manager)
        try await waitUntil { viewModel.environmentFileContent?.file.path == appEnv.path }
        XCTAssertEqual(viewModel.environmentFileDraft, "APP_ENV=prod\n")

        viewModel.environmentFileDraft = "APP_ENV=staging\n"
        viewModel.saveEnvironmentFile(
            profile: profile,
            sshClient: client,
            environmentFileManager: manager,
            repository: repository
        )
        try await waitUntil { viewModel.isSavingEnvironmentFile == false && viewModel.environmentActionMessage?.contains("Saved environment file") == true }
        XCTAssertEqual(viewModel.environmentFileContent?.content, "APP_ENV=staging\n")

        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].targetType, "environment")
        XCTAssertEqual(logs[0].targetId, "/var/www/app/.env")
        XCTAssertEqual(logs[0].action, "save")
        XCTAssertEqual(logs[0].status, "success")
        XCTAssertEqual(logs[0].beforeSnapshot, "APP_ENV=prod")
        XCTAssertEqual(logs[0].afterSnapshot, "APP_ENV=staging")
    }

    func testCloudSecurityGroupsLoadSelectAndPolicies() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.security.\(UUID().uuidString)")
        let account = CloudProviderAccount(
            id: UUID(),
            providerId: .tencentCloud,
            displayName: "Tencent",
            keychainRef: "cloud_test_\(UUID().uuidString)",
            enabled: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        try keychain.saveCloudCredential(
            CloudProviderCredential(secretId: "sid", secretKey: "skey"),
            keychainRef: account.keychainRef
        )
        defer {
            keychain.deleteCloudCredential(keychainRef: account.keychainRef)
        }
        try repository.upsertCloudProviderAccount(account)
        try repository.upsertCloudInstanceLink(CloudInstanceLink(
            id: UUID(),
            serverId: profile.id,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-123",
            displayName: "prod",
            publicIp: "203.0.113.1",
            privateIp: "10.0.0.2",
            status: "RUNNING",
            instanceType: "mock",
            zoneId: "ap-guangzhou-1",
            vpcId: "vpc-123",
            rawJSON: nil,
            lastSyncedAt: Date()
        ))
        let service = CloudSecurityGroupService(
            repository: repository,
            keychain: keychain,
            registry: CloudProviderRegistry(adapters: [
                SecurityGroupViewModelMockCloudAdapter(providerId: .tencentCloud)
            ]),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let viewModel = ServerWorkspaceViewModel()

        viewModel.loadCloudSecurityGroups(profile: profile, cloudSecurityGroupService: service)
        try await waitUntil { viewModel.isLoadingCloudSecurityGroups == false && viewModel.cloudSecurityGroupList != nil }
        try await waitUntil { viewModel.isLoadingCloudSecurityGroupPolicies == false && viewModel.cloudSecurityGroupPolicySnapshot != nil }

        XCTAssertEqual(viewModel.cloudSecurityGroupList?.regionId, "ap-guangzhou")
        XCTAssertEqual(viewModel.cloudSecurityGroupList?.instanceId, "ins-123")
        XCTAssertEqual(viewModel.selectedCloudSecurityGroup?.securityGroupId, "sg-123")
        XCTAssertEqual(viewModel.cloudSecurityGroupPolicySnapshot?.ingress.first?.port, "22")
        XCTAssertEqual(viewModel.cloudSecurityGroupPolicySnapshot?.egress.first?.protocolName, "ALL")
        XCTAssertNil(viewModel.cloudSecurityGroupErrorMessage)
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

    private func makeRepository(with profile: ServerProfile) throws -> ServerRepository {
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        try repository.upsert(profile)
        return repository
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

private final class DeploymentWorkspaceMockSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if command.contains("if [ -d") && command.contains("git rev-parse HEAD") {
            return CommandResult(command: command, stdout: "abc123\n", stderr: "", exitCode: 0, duration: 0.1)
        }
        if command.contains("git rev-parse HEAD") {
            return CommandResult(command: command, stdout: "def456\n", stderr: "", exitCode: 0, duration: 0.1)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0.1)
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

private final class SlowSSHClient: SSHClient, @unchecked Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return CommandResult(
            command: command,
            stdout: "",
            stderr: "",
            exitCode: 0,
            duration: 5
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class DashboardMockSSHClient: SSHClient, @unchecked Sendable {
    @MainActor
    private var _snapshotRequests = 0

    @MainActor
    var snapshotRequests: Int {
        _snapshotRequests
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        let stdout: String
        if command.contains("/etc/os-release") {
            await MainActor.run {
                _snapshotRequests += 1
            }
            stdout = """
            PRETTY_NAME="Ubuntu 24.04.2 LTS"
            VERSION_ID="24.04"
            """
        } else if command == "uname -r" {
            stdout = "6.8.0\n"
        } else if command.contains("test -d /proc") || command.contains("systemctl") || command.contains("sftp") {
            stdout = "yes\n"
        } else if command.contains("/proc/loadavg") {
            stdout = "0.10 0.20 0.30 1/100 12345\n"
        } else if command.contains("/proc/meminfo") {
            stdout = """
            MemTotal:        2048000 kB
            MemAvailable:    1024000 kB
            """
        } else if command.contains("df -kP") {
            stdout = "/dev/vda1 20971520 10485760 10485760 50% /\n"
        } else if command.contains("_NPROCESSORS_ONLN") {
            stdout = "4\n"
        } else if command.contains("/proc/net/dev") {
            stdout = """
              Inter-|   Receive                                                |  Transmit
               face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
                eth0: 1048576 0 0 0 0 0 0 0 2097152 0 0 0 0 0 0 0
            """
        } else if command.contains("ps -eo stat=") {
            stdout = "total=120 running=2 sleeping=117 stopped=0 zombie=1\n"
        } else {
            stdout = ""
        }
        return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class DashboardPartialFailureMockSSHClient: SSHClient, @unchecked Sendable {
    private let successClient = DashboardMockSSHClient()

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        if command.contains("/proc/net/dev") {
            throw SSHClientError.processFailed("network unavailable")
        }
        return try await successClient.execute(command, profile: profile)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class RemoteFileMockSSHClient: SSHClient, @unchecked Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        let stdout: String
        if command.contains("cd -- '/var/www/logs'") {
            stdout = "app.log\tf\t1024\t1700000100.0\t-rw-r--r--\n"
        } else {
            stdout = """
            index.html\tf\t2048\t1700000001.0\t-rw-r--r--
            logs\td\t4096\t1700000002.0\tdrwxr-xr-x
            """
        }
        return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class RemoteFileActionMockSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []
    private var currentName: String? = "index.html"

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if command.hasPrefix("mv -n -- '/var/www/index.html' '/var/www/home.html'") {
            currentName = "home.html"
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("mkdir -p -- '~/.hhc-server-manager-trash'") {
            currentName = nil
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("find . -maxdepth 1") {
            let stdout = currentName.map { name in
                "\(name)\tf\t2048\t1700000001.0\t-rw-r--r--\n"
            } ?? ""
            return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class RemoteTextFileMockSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []
    private(set) var content = "hello\n"
    private var files: [String: (content: String, permissions: String)] = [
        "app.env": ("hello\n", "-rw-r--r--")
    ]

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if command.contains("find . -maxdepth 1") {
            let stdout = files.keys.sorted().map { name in
                let file = files[name] ?? ("", "-rw-r--r--")
                return "\(name)\tf\t\(Data(file.content.utf8).count)\t1700000001.0\t\(file.permissions)"
            }
            .joined(separator: "\n")
            return CommandResult(
                command: command,
                stdout: stdout,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("base64 < '/var/www/app.env'") {
            let current = files["app.env"]?.content ?? content
            return CommandResult(
                command: command,
                stdout: Data(current.utf8).base64EncodedString(),
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("mv -- \"$tmp\" '/var/www/app.env'") {
            content = "updated\n"
            files["app.env"] = ("updated\n", files["app.env"]?.permissions ?? "-rw-r--r--")
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("mv -- \"$tmp\" \"$target\"") && command.contains("target='/var/www/copy.env'") {
            files["copy.env"] = ("copy\n", "-rw-r--r--")
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        if command.hasPrefix("chmod -- '640' '/var/www/app.env'") {
            if let file = files["app.env"] {
                files["app.env"] = (file.content, "-rw-r-----")
            }
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class RemoteFileTransferMockSSHClient: SSHClient, RemoteFileTransferClient, @unchecked Sendable {
    private(set) var uploads: [(localURL: URL, remotePath: String)] = []
    private(set) var downloads: [(remotePath: String, localURL: URL)] = []
    private var remoteNames = ["app.env"]

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        if command.contains("find . -maxdepth 1") {
            let stdout = remoteNames.map { name in
                "\(name)\tf\t8\t1700000001.0\t-rw-r--r--"
            }
            .joined(separator: "\n")
            return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        uploads.append((localURL, remotePath))
        remoteNames.append(localURL.lastPathComponent)
        remoteNames.sort()
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 8,
            duration: 0
        )
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        downloads.append((remotePath, localURL))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 8,
            duration: 0
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class SlowRemoteFileTransferMockSSHClient: SSHClient, RemoteFileTransferClient, @unchecked Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: nil,
            duration: 5
        )
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: nil,
            duration: 5
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class QueuedRemoteFileTransferMockSSHClient: SSHClient, RemoteFileTransferClient, @unchecked Sendable {
    private(set) var uploads: [(localURL: URL, remotePath: String)] = []
    private var remoteNames: [String] = []

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        if command.contains("find . -maxdepth 1") {
            let stdout = remoteNames.sorted().map { name in
                "\(name)\tf\t8\t1700000001.0\t-rw-r--r--"
            }
            .joined(separator: "\n")
            return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        try await Task.sleep(nanoseconds: 50_000_000)
        uploads.append((localURL, remotePath))
        remoteNames.append(localURL.lastPathComponent)
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 8,
            duration: 0.05
        )
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 8,
            duration: 0
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class SystemdViewModelMockSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if command.contains("systemctl list-units") {
            return CommandResult(
                command: command,
                stdout: """
                nginx.service\tloaded\tactive\trunning\tA high performance web server
                ssh.service\tloaded\tactive\trunning\tOpenSSH server
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.hasPrefix("journalctl -u 'ssh.service'") {
            return CommandResult(
                command: command,
                stdout: "2026-06-25T16:30:00+08:00 host sshd[1]: ssh ready\n",
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.hasPrefix("systemctl restart") {
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class CronViewModelMockSSHClient: SSHClient, @unchecked Sendable {
    private(set) var crontab = "0 2 * * * /usr/bin/backup\n"

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        if command == "crontab -l 2>/dev/null || true" {
            return CommandResult(command: command, stdout: crontab, stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("crontab -") {
            crontab = Self.decodeCrontab(from: command)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}

    private static func decodeCrontab(from command: String) -> String {
        guard let start = command.range(of: "crontab -\n"),
              let end = command[start.upperBound...].range(of: "\n__HHC_CRON_EOF__")
        else { return "" }
        let encoded = String(command[start.upperBound..<end.lowerBound])
        return Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

private final class NginxViewModelMockSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []
    var configs = [
        "/www/server/nginx/conf/nginx.conf": "user www-data;\n",
        "/www/server/nginx/conf/vhost/site.conf": "server { server_name example.com; }\n",
    ]
    var testSucceeds = true

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if command.contains("nginx -V") {
            return CommandResult(
                command: command,
                stdout: """
                /www/server/nginx/conf/nginx.conf\t320\t1700000000.5
                /www/server/nginx/conf/vhost/site.conf\t120\t1700000001.0
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("base64 < '/www/server/nginx/conf/nginx.conf'") {
            return CommandResult(
                command: command,
                stdout: Data((configs["/www/server/nginx/conf/nginx.conf"] ?? "").utf8).base64EncodedString(),
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("base64 < '/www/server/nginx/conf/vhost/site.conf'") {
            return CommandResult(
                command: command,
                stdout: Data((configs["/www/server/nginx/conf/vhost/site.conf"] ?? "").utf8).base64EncodedString(),
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("base64 -d > \"$tmp\"") {
            let path = Self.extractShellValue(named: "path", from: command) ?? "/www/server/nginx/conf/nginx.conf"
            let previous = configs[path]
            let next = Self.decodeConfig(from: command)
            if testSucceeds {
                configs[path] = next
                return CommandResult(
                    command: command,
                    stdout: "nginx: the configuration file /www/server/nginx/conf/nginx.conf syntax is ok\nnginx: configuration file /www/server/nginx/conf/nginx.conf test is successful\n",
                    stderr: "",
                    exitCode: 0,
                    duration: 0
                )
            }
            configs[path] = previous
            return CommandResult(
                command: command,
                stdout: "nginx: [emerg] invalid number of arguments in \"server\" directive\nnginx: configuration file /www/server/nginx/conf/nginx.conf test failed\n",
                stderr: "",
                exitCode: 4,
                duration: 0
            )
        }
        if command == "nginx -t" {
            let exitCode: Int32 = testSucceeds ? 0 : 1
            return CommandResult(
                command: command,
                stdout: "",
                stderr: testSucceeds
                    ? "nginx: the configuration file /www/server/nginx/conf/nginx.conf syntax is ok\nnginx: configuration file /www/server/nginx/conf/nginx.conf test is successful\n"
                    : "nginx: [emerg] invalid number of arguments in \"server\" directive\nnginx: configuration file /www/server/nginx/conf/nginx.conf test failed\n",
                exitCode: exitCode,
                duration: 0
            )
        }
        if command == "systemctl reload nginx 2>/dev/null || nginx -s reload" {
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}

    private static func decodeConfig(from command: String) -> String {
        guard let start = command.range(of: "__HHC_NGINX_CONFIG_EOF__'\n"),
              let end = command[start.upperBound...].range(of: "\n__HHC_NGINX_CONFIG_EOF__")
        else { return "" }
        let encoded = String(command[start.upperBound..<end.lowerBound])
        return Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func extractShellValue(named name: String, from command: String) -> String? {
        let prefix = "\(name)='"
        guard let start = command.range(of: prefix),
              let end = command[start.upperBound...].range(of: "'")
        else { return nil }
        return String(command[start.upperBound..<end.lowerBound])
    }
}

private final class FirewallViewModelMockSSHClient: SSHClient, @unchecked Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        CommandResult(
            command: command,
            stdout: """
            __HHC_FIREWALL_BACKEND__
            iptables
            __HHC_FIREWALL_STATUS__
            installed
            __HHC_FIREWALL_RULES__
            -P INPUT ACCEPT
            -A INPUT -p tcp --dport 22 -j ACCEPT
            """,
            stderr: "",
            exitCode: 0,
            duration: 0
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class EnvironmentViewModelMockSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []
    var files = [
        "/var/www/app/.env": "APP_ENV=prod\n",
        "/etc/default/nginx": "NGINX_DEBUG=0\n",
    ]

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if command.contains("find /var/www") {
            return CommandResult(
                command: command,
                stdout: """
                /var/www/app/.env\t13\t1700000000.5\tapp
                /etc/default/nginx\t14\t1700000001.0\tos
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("base64 < '/var/www/app/.env'") {
            return CommandResult(
                command: command,
                stdout: Data((files["/var/www/app/.env"] ?? "").utf8).base64EncodedString(),
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("base64 < '/etc/default/nginx'") {
            return CommandResult(
                command: command,
                stdout: Data((files["/etc/default/nginx"] ?? "").utf8).base64EncodedString(),
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("base64 -d > \"$tmp\"") {
            let path = Self.extractShellValue(named: "path", from: command) ?? "/var/www/app/.env"
            files[path] = Self.decodeEnvironmentFile(from: command)
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}

    private static func decodeEnvironmentFile(from command: String) -> String {
        guard let start = command.range(of: "__HHC_ENV_FILE_EOF__'\n"),
              let end = command[start.upperBound...].range(of: "\n__HHC_ENV_FILE_EOF__")
        else { return "" }
        let encoded = String(command[start.upperBound..<end.lowerBound])
        return Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static func extractShellValue(named name: String, from command: String) -> String? {
        let prefix = "\(name)='"
        guard let start = command.range(of: prefix),
              let end = command[start.upperBound...].range(of: "'")
        else { return nil }
        return String(command[start.upperBound..<end.lowerBound])
    }
}

private struct SecurityGroupViewModelMockCloudAdapter: CloudProviderAdapter {
    let providerId: CloudProviderID
    let displayName = "Mock Cloud"
    let capabilities: Set<CloudCapability> = [.securityGroups]

    func validateCredential(_ credential: CloudProviderCredential) async throws {}

    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion] {
        []
    }

    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance] {
        []
    }

    func fetchMetricSeries(credential: CloudProviderCredential, query: CloudMetricQuery) async throws -> CloudMetricSeries {
        CloudMetricSeries(
            metricName: query.metricName,
            instanceId: query.instanceId,
            regionId: query.regionId,
            unit: nil,
            values: [],
            timestamps: []
        )
    }

    func fetchSecurityGroups(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String
    ) async throws -> [CloudSecurityGroup] {
        [
            CloudSecurityGroup(
                accountId: accountId,
                providerId: providerId,
                regionId: regionId,
                securityGroupId: "sg-123",
                name: "web",
                description: "web ingress",
                projectId: "0",
                isDefault: false,
                createdTime: nil,
                updatedTime: nil
            ),
        ]
    }

    func fetchSecurityGroupPolicies(
        credential: CloudProviderCredential,
        group: CloudSecurityGroup,
        capturedAt: Date
    ) async throws -> CloudSecurityGroupPolicySnapshot {
        CloudSecurityGroupPolicySnapshot(
            group: group,
            version: "7",
            ingress: [
                CloudSecurityGroupRule(
                    direction: .ingress,
                    policyIndex: 0,
                    protocolName: "TCP",
                    port: "22",
                    cidrBlock: "203.0.113.0/24",
                    ipv6CidrBlock: nil,
                    referencedSecurityGroupId: nil,
                    action: "ACCEPT",
                    description: "SSH",
                    modifiedTime: nil
                ),
            ],
            egress: [
                CloudSecurityGroupRule(
                    direction: .egress,
                    policyIndex: 0,
                    protocolName: "ALL",
                    port: "all",
                    cidrBlock: "0.0.0.0/0",
                    ipv6CidrBlock: nil,
                    referencedSecurityGroupId: nil,
                    action: "ACCEPT",
                    description: nil,
                    modifiedTime: nil
                ),
            ],
            capturedAt: capturedAt
        )
    }
}
