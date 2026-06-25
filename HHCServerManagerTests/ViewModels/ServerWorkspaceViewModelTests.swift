import XCTest
@testable import HHCServerManager

@MainActor
final class ServerWorkspaceViewModelTests: XCTestCase {
    func testCommandResultClipboardTextIncludesOutputAndMetadata() {
        let result = CommandResult(
            command: "printf hhc-ssh-ok",
            stdout: "hhc-ssh-ok\n",
            stderr: "warn\n",
            exitCode: 0,
            duration: 0.123
        )

        XCTAssertEqual(result.clipboardText, """
        $ printf hhc-ssh-ok
        exit: 0
        duration: 0.12s

        stdout:
        hhc-ssh-ok


        stderr:
        warn

        """)
    }

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

        let deploymentProject = DeploymentProject(
            id: UUID(),
            serverId: UUID(),
            name: "Website",
            repositoryURL: "git@gitlab.com:hhc/site.git",
            branch: "main",
            deployPath: "/srv/site",
            buildCommand: "npm ci",
            restartCommand: "systemctl restart site.service",
            healthCheckCommand: nil,
            webhookEnabled: true,
            webhookSecretRef: "deployment_webhook_ref",
            createdAt: Date(),
            updatedAt: Date()
        )
        let deploymentRun = DeploymentRun(
            id: UUID(),
            projectId: deploymentProject.id,
            triggerType: .manual,
            requestedRef: "main",
            previousCommit: "abc1234",
            targetCommit: "def5678",
            status: .succeeded,
            startedAt: Date(),
            finishedAt: Date(),
            summary: "Deployment completed."
        )
        let rollbackRisk = RemoteOperationRiskFactory.deploymentRollback(project: deploymentProject, run: deploymentRun)
        XCTAssertEqual(rollbackRisk.level, .high)
        XCTAssertEqual(rollbackRisk.auditTargetType, "deployment")
        XCTAssertEqual(rollbackRisk.auditAction, "rollback")
        XCTAssertTrue(rollbackRisk.confirmationMessage.contains("git reset --hard abc1234"))

        let diskResource = CloudUnifiedResource(
            id: "disk:account:ap-guangzhou:disk-123",
            kind: .disk,
            accountId: UUID(),
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            resourceId: "disk-123",
            displayName: "prod-data",
            status: "ATTACHED",
            primaryAddress: nil,
            secondaryText: nil,
            lastSyncedAt: nil
        )
        let createSnapshotRisk = RemoteOperationRiskFactory.createCloudSnapshot(resource: diskResource, snapshotName: "before-upgrade")
        XCTAssertEqual(createSnapshotRisk.level, .high)
        XCTAssertEqual(createSnapshotRisk.auditAction, "create_snapshot")
        XCTAssertTrue(createSnapshotRisk.confirmationMessage.contains("CreateSnapshot DiskId=disk-123"))

        let snapshotResource = CloudUnifiedResource(
            id: "snapshot:account:ap-guangzhou:snap-123",
            kind: .snapshot,
            accountId: UUID(),
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            resourceId: "snap-123",
            displayName: "before-upgrade",
            status: "NORMAL",
            primaryAddress: nil,
            secondaryText: nil,
            lastSyncedAt: nil
        )
        let deleteSnapshotRisk = RemoteOperationRiskFactory.deleteCloudSnapshot(resource: snapshotResource)
        XCTAssertEqual(deleteSnapshotRisk.level, .critical)
        XCTAssertEqual(deleteSnapshotRisk.auditAction, "delete_snapshot")
        XCTAssertTrue(deleteSnapshotRisk.confirmationMessage.contains("DeleteSnapshots SnapshotIds=[snap-123]"))

        let attachDiskRisk = RemoteOperationRiskFactory.attachCloudDisk(resource: diskResource, instanceId: "ins-456")
        XCTAssertEqual(attachDiskRisk.level, .high)
        XCTAssertEqual(attachDiskRisk.auditTargetType, "cloud_disk")
        XCTAssertEqual(attachDiskRisk.auditAction, "attach_disk")
        XCTAssertTrue(attachDiskRisk.confirmationMessage.contains("AttachDisks DiskIds=[disk-123] InstanceId=ins-456"))

        let detachDiskRisk = RemoteOperationRiskFactory.detachCloudDisk(resource: diskResource)
        XCTAssertEqual(detachDiskRisk.level, .critical)
        XCTAssertEqual(detachDiskRisk.auditTargetType, "cloud_disk")
        XCTAssertEqual(detachDiskRisk.auditAction, "detach_disk")
        XCTAssertTrue(detachDiskRisk.confirmationMessage.contains("DetachDisks DiskIds=[disk-123]"))

        let instanceResource = CloudUnifiedResource(
            id: "instance:account:ap-guangzhou:ins-123",
            kind: .instance,
            accountId: UUID(),
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            resourceId: "ins-123",
            displayName: "prod-1",
            status: "RUNNING",
            primaryAddress: "203.0.113.2",
            secondaryText: "S5.SMALL1",
            lastSyncedAt: nil
        )
        let stopInstanceRisk = RemoteOperationRiskFactory.cloudInstancePower(resource: instanceResource, action: .stop)
        XCTAssertEqual(stopInstanceRisk.level, .critical)
        XCTAssertEqual(stopInstanceRisk.auditTargetType, "cloud_instance")
        XCTAssertEqual(stopInstanceRisk.auditAction, "stop_instance")
        XCTAssertTrue(stopInstanceRisk.confirmationMessage.contains("StopInstances InstanceIds=[ins-123]"))

        let startInstanceRisk = RemoteOperationRiskFactory.cloudInstancePower(resource: instanceResource, action: .start)
        XCTAssertEqual(startInstanceRisk.level, .high)
        XCTAssertEqual(startInstanceRisk.auditAction, "start_instance")
        XCTAssertTrue(startInstanceRisk.confirmationMessage.contains("StartInstances InstanceIds=[ins-123]"))

        let alibabaDiskResource = CloudUnifiedResource(
            id: "disk:account:cn-hangzhou:d-123",
            kind: .disk,
            accountId: UUID(),
            providerId: .alibabaCloud,
            regionId: "cn-hangzhou",
            resourceId: "d-123",
            displayName: "ali-data",
            status: "Available",
            primaryAddress: nil,
            secondaryText: nil,
            lastSyncedAt: nil
        )
        XCTAssertTrue(
            RemoteOperationRiskFactory.attachCloudDisk(resource: alibabaDiskResource, instanceId: "i-123")
                .confirmationMessage
                .contains("AttachDisk DiskId=d-123 InstanceId=i-123")
        )

        let alibabaSnapshotResource = CloudUnifiedResource(
            id: "snapshot:account:cn-hangzhou:s-123",
            kind: .snapshot,
            accountId: UUID(),
            providerId: .alibabaCloud,
            regionId: "cn-hangzhou",
            resourceId: "s-123",
            displayName: "ali-snapshot",
            status: "accomplished",
            primaryAddress: nil,
            secondaryText: nil,
            lastSyncedAt: nil
        )
        XCTAssertTrue(
            RemoteOperationRiskFactory.deleteCloudSnapshot(resource: alibabaSnapshotResource)
                .confirmationMessage
                .contains("DeleteSnapshot SnapshotId=s-123")
        )

        let huaweiInstanceResource = CloudUnifiedResource(
            id: "instance:account:ap-southeast-1:server-123",
            kind: .instance,
            accountId: UUID(),
            providerId: .huaweiCloud,
            regionId: "ap-southeast-1",
            resourceId: "server-123",
            displayName: "hw-prod",
            status: "ACTIVE",
            primaryAddress: "10.0.0.5",
            secondaryText: "s6.small.1",
            lastSyncedAt: nil
        )
        XCTAssertTrue(
            RemoteOperationRiskFactory.cloudInstancePower(resource: huaweiInstanceResource, action: .reboot)
                .confirmationMessage
                .contains("POST /v2.1/{project_id}/servers/server-123/action reboot")
        )
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
            providerRuleId: nil,
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

    func testConnectIgnoresDuplicateTapWhileSmokeTestIsRunning() async throws {
        let profile = makeProfile()
        let client = MockSSHClient(delayNanoseconds: 100_000_000)
        let viewModel = ServerWorkspaceViewModel()

        viewModel.connect(profile: profile, sshClient: client)
        viewModel.connect(profile: profile, sshClient: client)
        try await waitUntil { viewModel.isRunningSmokeTest == false }

        XCTAssertEqual(client.smokeTestCallCount, 1)
        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertEqual(viewModel.commandResult?.stdout, "hhc-ssh-ok")
    }

    func testConfigureNewServerClearsServerScopedWorkspaceState() {
        let firstProfile = makeProfile()
        let secondProfile = makeProfile()
        let viewModel = ServerWorkspaceViewModel()
        let result = CommandResult(
            command: "printf hhc-ssh-ok",
            stdout: "hhc-ssh-ok",
            stderr: "",
            exitCode: 0,
            duration: 0.1
        )

        viewModel.configure(profile: firstProfile, initialState: .connected)
        viewModel.commandResult = result
        viewModel.commandHistory = [result]
        viewModel.persistedCommandHistory = [
            CommandHistoryEntry(
                id: UUID(),
                serverId: firstProfile.id,
                command: "printf hhc-ssh-ok",
                exitCode: 0,
                duration: 0.1,
                createdAt: Date()
            ),
        ]
        viewModel.errorMessage = "old error"
        viewModel.remoteFilePath = "/srv/old"
        viewModel.remoteDirectoryListing = RemoteDirectoryListing(
            path: "/srv/old",
            entries: [
                RemoteFileEntry(
                    name: "old.log",
                    path: "/srv/old/old.log",
                    kind: .file,
                    size: 12,
                    modifiedAt: nil,
                    permissions: "-rw-r--r--"
                ),
            ],
            capturedAt: Date()
        )

        viewModel.configure(profile: secondProfile, initialState: .disconnected)

        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertNil(viewModel.commandResult)
        XCTAssertTrue(viewModel.commandHistory.isEmpty)
        XCTAssertTrue(viewModel.persistedCommandHistory.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.remoteFilePath, "~")
        XCTAssertNil(viewModel.remoteDirectoryListing)
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

    func testDeploymentProjectRejectsPathOutsideAllowlist() throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let viewModel = ServerWorkspaceViewModel()

        viewModel.startNewDeploymentProject(serverId: profile.id)
        viewModel.deploymentName = "Bad API"
        viewModel.deploymentRepositoryURL = "git@gitlab.com:hhc/api.git"
        viewModel.deploymentBranch = "main"
        viewModel.deploymentPath = "/etc/api"
        viewModel.saveDeploymentProject(profile: profile, repository: repository)

        XCTAssertTrue(viewModel.deploymentProjects.isEmpty)
        XCTAssertTrue(try repository.fetchDeploymentProjects(serverId: profile.id).isEmpty)
        XCTAssertTrue(viewModel.deploymentErrorMessage?.contains("outside the allowed deployment roots") == true)
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
        XCTAssertEqual(viewModel.selectedDeploymentRun?.previousCommit, "abc1234")
        XCTAssertEqual(viewModel.selectedDeploymentRun?.targetCommit, "def4567")
        XCTAssertTrue(viewModel.deploymentLogs.contains { $0.stepName == "finish" && $0.message == "Deployment completed." })
        XCTAssertTrue(client.commands.contains { $0.contains("git reset --hard 'origin/main'") })
        let audit = try XCTUnwrap(try repository.fetchRemoteChangeLogs(serverId: profile.id).first)
        XCTAssertEqual(audit.targetType, "deployment")
        XCTAssertEqual(audit.targetId, viewModel.selectedDeploymentProject?.id.uuidString)
        XCTAssertEqual(audit.action, "deploy")
        XCTAssertEqual(audit.status, "succeeded")
        XCTAssertTrue(audit.beforeSnapshot?.contains("commit=abc1234") == true)
        XCTAssertTrue(audit.afterSnapshot?.contains("commit=def4567") == true)
    }

    func testRunDeploymentShowsHealthCheckFailureInWorkspace() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let viewModel = ServerWorkspaceViewModel()
        let client = DeploymentWorkspaceMockSSHClient(failingStep: "health_check")
        let runner = DeploymentRunner(repository: repository)

        viewModel.startNewDeploymentProject(serverId: profile.id)
        viewModel.deploymentName = "API"
        viewModel.deploymentRepositoryURL = "git@gitlab.com:hhc/api.git"
        viewModel.deploymentBranch = "main"
        viewModel.deploymentPath = "/srv/api"
        viewModel.deploymentHealthCheckCommand = "curl -fsS http://127.0.0.1:3000/health"

        viewModel.runDeployment(
            profile: profile,
            sshClient: client,
            deploymentRunner: runner,
            repository: repository
        )
        try await waitUntil { viewModel.isRunningDeployment == false && viewModel.selectedDeploymentRun != nil }

        XCTAssertEqual(viewModel.selectedDeploymentRun?.status, .failed)
        XCTAssertEqual(viewModel.selectedDeploymentRun?.summary, "health_check failed with exit code 1.")
        XCTAssertTrue(viewModel.deploymentLogs.contains { $0.stepName == "health_check" && $0.stream == .stderr && $0.message == "health_check failed" })
        XCTAssertTrue(client.commands.contains { $0.contains("curl -fsS http://127.0.0.1:3000/health") })
        let audit = try XCTUnwrap(try repository.fetchRemoteChangeLogs(serverId: profile.id).first)
        XCTAssertEqual(audit.targetType, "deployment")
        XCTAssertEqual(audit.action, "deploy")
        XCTAssertEqual(audit.status, "failed")
        XCTAssertEqual(audit.message, "health_check failed with exit code 1.")
    }

    func testRollbackDeploymentPersistsRemoteChangeAudit() async throws {
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
        viewModel.runDeployment(
            profile: profile,
            sshClient: client,
            deploymentRunner: runner,
            repository: repository
        )
        try await waitUntil { viewModel.isRunningDeployment == false && viewModel.selectedDeploymentRun?.status == .succeeded }

        viewModel.rollbackDeployment(
            profile: profile,
            sshClient: client,
            deploymentRunner: runner,
            repository: repository
        )
        try await waitUntil {
            viewModel.isRunningDeployment == false &&
                viewModel.selectedDeploymentRun?.triggerType == .rollback
        }

        XCTAssertTrue(client.commands.contains { $0.contains("git reset --hard 'abc1234'") })
        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        let audit = try XCTUnwrap(logs.first { $0.action == "rollback" })
        XCTAssertEqual(audit.targetType, "deployment")
        XCTAssertEqual(audit.targetId, viewModel.selectedDeploymentProject?.id.uuidString)
        XCTAssertEqual(audit.status, "succeeded")
        XCTAssertTrue(audit.beforeSnapshot?.contains("commit=def4567") == true)
        XCTAssertTrue(audit.afterSnapshot?.contains("commit=def4567") == true)
        XCTAssertTrue(audit.message?.contains("Rollback completed") == true)
    }

    func testRunDeploymentStopsWorkspaceFlowAfterBuildFailure() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let viewModel = ServerWorkspaceViewModel()
        let client = DeploymentWorkspaceMockSSHClient(failingStep: "build")
        let runner = DeploymentRunner(repository: repository)

        viewModel.startNewDeploymentProject(serverId: profile.id)
        viewModel.deploymentName = "API"
        viewModel.deploymentRepositoryURL = "git@gitlab.com:hhc/api.git"
        viewModel.deploymentBranch = "main"
        viewModel.deploymentPath = "/srv/api"
        viewModel.deploymentBuildCommand = "npm run build"
        viewModel.deploymentRestartCommand = "systemctl restart api.service"
        viewModel.deploymentHealthCheckCommand = "curl -fsS http://127.0.0.1:3000/health"

        viewModel.runDeployment(
            profile: profile,
            sshClient: client,
            deploymentRunner: runner,
            repository: repository
        )
        try await waitUntil { viewModel.isRunningDeployment == false && viewModel.selectedDeploymentRun != nil }

        XCTAssertEqual(viewModel.selectedDeploymentRun?.status, .failed)
        XCTAssertEqual(viewModel.selectedDeploymentRun?.summary, "build failed with exit code 1.")
        XCTAssertTrue(viewModel.deploymentLogs.contains { $0.stepName == "build" && $0.stream == .stderr && $0.message == "build failed" })
        XCTAssertFalse(client.commands.contains { $0.contains("systemctl restart api.service") })
        XCTAssertFalse(client.commands.contains { $0.contains("curl -fsS http://127.0.0.1:3000/health") })
    }

    func testRunDeploymentRefreshesLogsWhileRunning() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let viewModel = ServerWorkspaceViewModel()
        let client = SlowSSHClient()
        let runner = DeploymentRunner(repository: repository)

        viewModel.startNewDeploymentProject(serverId: profile.id)
        viewModel.deploymentName = "API"
        viewModel.deploymentRepositoryURL = "git@gitlab.com:hhc/api.git"
        viewModel.deploymentBranch = "main"
        viewModel.deploymentPath = "/srv/api"

        viewModel.runDeployment(
            profile: profile,
            sshClient: client,
            deploymentRunner: runner,
            repository: repository
        )

        try await waitUntil { viewModel.isRunningDeployment }
        try await waitUntil {
            viewModel.selectedDeploymentRun?.status == .running &&
                viewModel.deploymentLogs.contains { $0.stepName == "plan" }
        }

        viewModel.cancelDeployment()
        try await waitUntil { viewModel.isRunningDeployment == false }
        XCTAssertEqual(viewModel.selectedDeploymentRun?.status, .cancelled)
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
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        try repository.upsert(profile)
        let viewModel = ServerWorkspaceViewModel()

        viewModel.refreshDashboard(
            profile: profile,
            sshClient: client,
            dashboardService: DashboardService(now: { Date(timeIntervalSince1970: 1_700_000_000) }),
            repository: repository
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
        XCTAssertEqual(try repository.fetchLatestDashboardSnapshot(serverId: profile.id), snapshot)
        XCTAssertEqual(try repository.fetchServerCapabilities(serverId: profile.id), snapshot.capabilities)
    }

    func testLoadCachedDashboardSnapshotRestoresPreviousSnapshot() throws {
        let profile = makeProfile()
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        try repository.upsert(profile)
        let snapshot = ServerDashboardSnapshot(
            capabilities: ServerCapabilities(
                osName: "Ubuntu",
                osVersion: "24.04",
                kernelVersion: "6.8.0",
                hasProc: true,
                hasSystemd: true,
                hasSFTP: true,
                detectedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            metrics: [
                DashboardMetric(name: "CPU Cores", value: "4", unit: "online", source: "SSH"),
            ],
            warnings: [
                DashboardWarning(source: "Cloud API", message: "permission denied"),
            ],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        try repository.saveDashboardSnapshot(snapshot, serverId: profile.id)
        let viewModel = ServerWorkspaceViewModel()

        viewModel.loadCachedDashboardSnapshot(profile: profile, repository: repository)

        XCTAssertEqual(viewModel.dashboardSnapshot, snapshot)
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

    func testRefreshDashboardHandlesMissingProcAndCommandsAsWarnings() async throws {
        let profile = makeProfile()
        let client = DashboardNoProcMockSSHClient()
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        try repository.upsert(profile)
        let viewModel = ServerWorkspaceViewModel()

        viewModel.refreshDashboard(
            profile: profile,
            sshClient: client,
            dashboardService: DashboardService(now: { Date(timeIntervalSince1970: 1_700_000_000) }),
            repository: repository
        )
        try await waitUntil { viewModel.isRefreshingDashboard == false && viewModel.dashboardSnapshot != nil }

        let snapshot = try XCTUnwrap(viewModel.dashboardSnapshot)
        XCTAssertEqual(snapshot.capabilities.osName, "Alpine Linux 3.20")
        XCTAssertFalse(snapshot.capabilities.hasProc)
        XCTAssertFalse(snapshot.capabilities.hasSystemd)
        XCTAssertFalse(snapshot.capabilities.hasSFTP)
        XCTAssertEqual(snapshot.metrics.map(\.name), ["Root Disk", "CPU Cores"])
        XCTAssertEqual(snapshot.warnings, [
            DashboardWarning(source: "Load Average", message: "/proc unavailable"),
            DashboardWarning(source: "Memory", message: "/proc unavailable"),
            DashboardWarning(source: "Network", message: "/proc unavailable"),
            DashboardWarning(source: "Processes", message: "ps unavailable"),
        ])
        XCTAssertNil(viewModel.dashboardErrorMessage)
        XCTAssertEqual(try repository.fetchLatestDashboardSnapshot(serverId: profile.id), snapshot)
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
        let repository = try makeRepository(with: profile)
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
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.map(\.name) == ["app.env", "upload.env"] }
        XCTAssertEqual(client.uploads.map(\.remotePath), ["/var/www/upload.env"])
        XCTAssertEqual(viewModel.remoteFileActionMessage, "Uploaded upload.env to /var/www/upload.env.")
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.direction, .upload)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.status, .succeeded)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.progressFraction, 1)

        let entry = try XCTUnwrap(viewModel.remoteDirectoryListing?.entries.first { $0.name == "app.env" })
        viewModel.downloadRemoteFile(
            entry,
            to: downloadURL,
            profile: profile,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil { viewModel.remoteFileActionMessage == "Downloaded app.env to /tmp/download.env." }
        XCTAssertEqual(client.downloads.map(\.remotePath), ["/var/www/app.env"])
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.direction, .download)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.status, .succeeded)
        XCTAssertFalse(viewModel.isTransferringRemoteFile)
        XCTAssertNil(viewModel.remoteFileErrorMessage)

        let persistedJobs = try repository.fetchRemoteFileTransferJobs(serverId: profile.id)
        XCTAssertEqual(persistedJobs.map(\.direction), [.download, .upload])
        XCTAssertEqual(persistedJobs.map(\.status), [.succeeded, .succeeded])
        XCTAssertEqual(persistedJobs.first?.progressFraction, 1)
    }

    func testRemoteFileBatchUploadAndDownloadQueuesEachFile() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = RemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadRemoteFiles(
            path: "/var/www",
            profile: profile,
            sshClient: client,
            remoteFileService: service
        )
        try await waitUntil { viewModel.remoteDirectoryListing?.entries.map(\.name) == ["app.env"] }

        viewModel.uploadRemoteFiles(
            localURLs: [
                URL(fileURLWithPath: "/tmp/alpha.env"),
                URL(fileURLWithPath: "/tmp/beta.env"),
            ],
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil {
            viewModel.remoteFileTransferJobs.count == 2 &&
                viewModel.remoteFileTransferJobs.allSatisfy { $0.status == .succeeded }
        }

        XCTAssertEqual(Set(client.uploads.map(\.remotePath)), Set(["/var/www/alpha.env", "/var/www/beta.env"]))
        XCTAssertEqual(viewModel.remoteDirectoryListing?.entries.map(\.name), ["alpha.env", "app.env", "beta.env"])
        XCTAssertFalse(viewModel.isTransferringRemoteFile)

        let entries = try XCTUnwrap(viewModel.remoteDirectoryListing?.entries)
        viewModel.downloadRemoteFiles(
            entries + [
                RemoteFileEntry(
                    name: "logs",
                    path: "/var/www/logs",
                    kind: .directory,
                    size: nil,
                    modifiedAt: nil,
                    permissions: "drwxr-xr-x"
                ),
            ],
            toDirectory: URL(fileURLWithPath: "/tmp/downloads", isDirectory: true),
            profile: profile,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil { client.downloads.count == 3 && viewModel.isTransferringRemoteFile == false }

        XCTAssertEqual(
            Set(client.downloads.map(\.remotePath)),
            Set(["/var/www/alpha.env", "/var/www/app.env", "/var/www/beta.env"])
        )
        XCTAssertEqual(
            Set(client.downloads.map(\.localURL.path)),
            Set(["/tmp/downloads/alpha.env", "/tmp/downloads/app.env", "/tmp/downloads/beta.env"])
        )
        XCTAssertEqual(viewModel.remoteFileTransferJobs.filter { $0.direction == .download }.count, 3)
        XCTAssertTrue(viewModel.remoteFileTransferJobs.allSatisfy { $0.status == .succeeded })
        XCTAssertEqual(try repository.fetchRemoteFileTransferJobs(serverId: profile.id).count, 5)
    }

    func testLoadRemoteFileTransferHistoryRestoresPersistedJobs() throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let job = RemoteFileTransferJob(
            id: UUID(),
            direction: .upload,
            remotePath: "/var/www/app.env",
            localPath: "/tmp/app.env",
            status: .succeeded,
            byteCount: 2_048,
            progressFraction: 1,
            message: "Uploaded app.env to /var/www/app.env.",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
        try repository.upsertRemoteFileTransferJob(job, serverId: profile.id)
        let viewModel = ServerWorkspaceViewModel()

        viewModel.loadRemoteFileTransferHistory(profile: profile, repository: repository)

        XCTAssertEqual(viewModel.remoteFileTransferJobs, [job])
        XCTAssertNil(viewModel.remoteFileErrorMessage)
    }

    func testResumeRemoteFileTransferReusesFailedUploadJobHistory() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = RemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let failed = RemoteFileTransferJob(
            id: UUID(),
            direction: .upload,
            remotePath: "/var/www/retry.env",
            localPath: "/tmp/retry.env",
            status: .failed,
            byteCount: nil,
            progressFraction: 0.5,
            message: "Network dropped.",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        try repository.upsertRemoteFileTransferJob(failed, serverId: profile.id)
        viewModel.remoteFileTransferJobs = [failed]

        viewModel.retryRemoteFileTransfer(
            failed,
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )

        try await waitUntil { viewModel.remoteFileTransferJobs.first?.status == .succeeded }

        XCTAssertEqual(viewModel.remoteFileTransferJobs.count, 1)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.id, failed.id)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.progressFraction, 1)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.backend, .nativeSFTP)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.supportsResume, true)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.supportsStreamingProgress, true)
        XCTAssertEqual(client.uploads.map(\.remotePath), ["/var/www/retry.env"])
        let persisted = try repository.fetchRemoteFileTransferJobs(serverId: profile.id)
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.id, failed.id)
        XCTAssertEqual(persisted.first?.status, .succeeded)
        XCTAssertEqual(persisted.first?.backend, .nativeSFTP)
        XCTAssertEqual(persisted.first?.supportsResume, true)
        XCTAssertEqual(persisted.first?.supportsStreamingProgress, true)
    }

    func testResumeRemoteFileTransferReusesInterruptedDownloadJobHistory() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = RemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let interrupted = RemoteFileTransferJob(
            id: UUID(),
            direction: .download,
            remotePath: "/var/www/app.env",
            localPath: "/tmp/downloads/app.env",
            status: .interrupted,
            byteCount: 8,
            progressFraction: 0.25,
            message: "Transfer was interrupted before completion.",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        try repository.upsertRemoteFileTransferJob(interrupted, serverId: profile.id)
        viewModel.remoteFileTransferJobs = [interrupted]

        viewModel.retryRemoteFileTransfer(
            interrupted,
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )

        try await waitUntil { viewModel.remoteFileTransferJobs.first?.status == .succeeded }

        XCTAssertEqual(viewModel.remoteFileTransferJobs.count, 1)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.id, interrupted.id)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first?.progressFraction, 1)
        XCTAssertEqual(client.downloads.map(\.remotePath), ["/var/www/app.env"])
        XCTAssertEqual(client.downloads.map(\.localURL.path), ["/tmp/downloads/app.env"])
        let persisted = try repository.fetchRemoteFileTransferJobs(serverId: profile.id)
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.id, interrupted.id)
        XCTAssertEqual(persisted.first?.status, .succeeded)
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

    func testRemoteFileTransferProgressUpdatesRunningJobAndPersistence() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = SlowRemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/large.log"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil { viewModel.remoteFileTransferJobs.first?.progressFraction == 0.5 }

        let runningJob = try XCTUnwrap(viewModel.remoteFileTransferJobs.first)
        XCTAssertEqual(runningJob.status, .running)
        XCTAssertEqual(runningJob.byteCount, 1_024)
        XCTAssertEqual(runningJob.message, "Transferred 512 of 1024 bytes.")

        let persisted = try XCTUnwrap(try repository.fetchRemoteFileTransferJobs(serverId: profile.id).first)
        XCTAssertEqual(persisted.status, .running)
        XCTAssertEqual(persisted.progressFraction, 0.5)
        XCTAssertEqual(persisted.byteCount, 1_024)
        XCTAssertEqual(persisted.supportsStreamingProgress, true)
        XCTAssertEqual(persisted.message, "Transferred 512 of 1024 bytes.")

        viewModel.cancelRemoteFileTransfer()
        try await waitUntil { viewModel.remoteFileTransferJobs.first?.status == .cancelled }
    }

    func testRemoteFileTransfersRunConcurrentlyWithPendingOverflow() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
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
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil { viewModel.remoteFileTransferJobs.first?.status == .running }

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/second.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/third.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )

        XCTAssertEqual(viewModel.remoteFileTransferJobs.filter { $0.status == .running }.count, 2)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.filter { $0.status == .pending }.count, 1)
        let persistedStatuses = try repository.fetchRemoteFileTransferJobs(serverId: profile.id).map(\.status)
        XCTAssertEqual(persistedStatuses.filter { $0 == .running }.count, 2)
        XCTAssertEqual(persistedStatuses.filter { $0 == .pending }.count, 1)
        try await waitUntil {
            viewModel.remoteFileTransferJobs.count == 3 &&
                viewModel.remoteFileTransferJobs.allSatisfy { $0.status == .succeeded }
        }

        XCTAssertEqual(
            Set(client.uploads.map(\.remotePath)),
            Set(["/var/www/first.env", "/var/www/second.env", "/var/www/third.env"])
        )
        XCTAssertFalse(viewModel.isTransferringRemoteFile)
        XCTAssertNil(viewModel.remoteFileErrorMessage)
    }

    func testCancelPendingRemoteFileTransfersLeavesRunningTransferActive() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = QueuedRemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/running.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil { viewModel.remoteFileTransferJobs.first?.status == .running }

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/also-running.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil { viewModel.remoteFileTransferJobs.filter { $0.status == .running }.count == 2 }

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/pending.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        XCTAssertEqual(viewModel.remoteFileTransferJobs.filter { $0.status == .running }.count, 2)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.filter { $0.status == .pending }.count, 1)

        viewModel.cancelPendingRemoteFileTransfers()

        XCTAssertEqual(viewModel.remoteFileTransferJobs.filter { $0.status == .cancelled }.count, 1)
        XCTAssertEqual(viewModel.remoteFileTransferJobs.filter { $0.status == .running }.count, 2)
        let persistedStatusesByPath = Dictionary(
            uniqueKeysWithValues: try repository.fetchRemoteFileTransferJobs(serverId: profile.id)
                .map { ($0.localPath, $0.status) }
        )
        XCTAssertEqual(persistedStatusesByPath["/tmp/running.env"], .running)
        XCTAssertEqual(persistedStatusesByPath["/tmp/also-running.env"], .running)
        XCTAssertEqual(persistedStatusesByPath["/tmp/pending.env"], .cancelled)
        XCTAssertTrue(viewModel.isTransferringRemoteFile)
        try await waitUntil {
            viewModel.remoteFileTransferJobs.filter { $0.status == .succeeded }.count == 2 &&
                viewModel.remoteFileTransferJobs.filter { $0.status == .cancelled }.count == 1
        }
        XCTAssertEqual(Set(client.uploads.map(\.remotePath)), Set(["~/running.env", "~/also-running.env"]))
    }

    func testCancelSinglePendingRemoteFileTransferDoesNotStartIt() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = QueuedRemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/running.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/also-running.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil { viewModel.remoteFileTransferJobs.filter { $0.status == .running }.count == 2 }

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/pending.env"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        let pending = try XCTUnwrap(viewModel.remoteFileTransferJobs.first { $0.localPath == "/tmp/pending.env" })
        XCTAssertEqual(pending.status, .pending)

        viewModel.cancelRemoteFileTransfer(pending)

        XCTAssertEqual(viewModel.remoteFileTransferJobs.first { $0.localPath == "/tmp/pending.env" }?.status, .cancelled)
        XCTAssertEqual(viewModel.remoteFileActionMessage, "Transfer cancelled.")
        let persistedStatusesByPath = Dictionary(
            uniqueKeysWithValues: try repository.fetchRemoteFileTransferJobs(serverId: profile.id)
                .map { ($0.localPath, $0.status) }
        )
        XCTAssertEqual(persistedStatusesByPath["/tmp/pending.env"], .cancelled)

        try await waitUntil {
            viewModel.remoteFileTransferJobs.filter { $0.status == .succeeded }.count == 2 &&
                viewModel.remoteFileTransferJobs.first { $0.localPath == "/tmp/pending.env" }?.status == .cancelled
        }
        XCTAssertFalse(client.uploads.contains { $0.localURL.path == "/tmp/pending.env" })
    }

    func testCancelSingleRunningRemoteFileTransferLeavesOtherRunning() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = SlowRemoteFileTransferMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/first-large.log"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        viewModel.uploadRemoteFile(
            localURL: URL(fileURLWithPath: "/tmp/second-large.log"),
            profile: profile,
            sshClient: client,
            transferClient: client,
            remoteFileService: service,
            repository: repository
        )
        try await waitUntil { viewModel.remoteFileTransferJobs.filter { $0.status == .running }.count == 2 }

        let first = try XCTUnwrap(viewModel.remoteFileTransferJobs.first { $0.localPath == "/tmp/first-large.log" })
        viewModel.cancelRemoteFileTransfer(first)

        try await waitUntil {
            viewModel.remoteFileTransferJobs.first { $0.localPath == "/tmp/first-large.log" }?.status == .cancelled
        }
        XCTAssertEqual(viewModel.remoteFileTransferJobs.first { $0.localPath == "/tmp/second-large.log" }?.status, .running)
        XCTAssertTrue(viewModel.isTransferringRemoteFile)

        let persistedStatusesByPath = Dictionary(
            uniqueKeysWithValues: try repository.fetchRemoteFileTransferJobs(serverId: profile.id)
                .map { ($0.localPath, $0.status) }
        )
        XCTAssertEqual(persistedStatusesByPath["/tmp/first-large.log"], .cancelled)
        XCTAssertEqual(persistedStatusesByPath["/tmp/second-large.log"], .running)

        viewModel.cancelRemoteFileTransfer()
        try await waitUntil {
            viewModel.remoteFileTransferJobs.allSatisfy { $0.status == .cancelled }
        }
    }

    func testLoadRemoteFileTransferHistoryMarksUnfinishedJobsInterrupted() throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let pending = RemoteFileTransferJob(
            id: UUID(),
            direction: .upload,
            remotePath: "/var/www/pending.env",
            localPath: "/tmp/pending.env",
            status: .pending,
            byteCount: nil,
            progressFraction: 0,
            message: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: nil
        )
        let running = RemoteFileTransferJob(
            id: UUID(),
            direction: .download,
            remotePath: "/var/www/running.env",
            localPath: "/tmp/running.env",
            status: .running,
            byteCount: nil,
            progressFraction: nil,
            message: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_001),
            finishedAt: nil
        )
        try repository.upsertRemoteFileTransferJob(pending, serverId: profile.id)
        try repository.upsertRemoteFileTransferJob(running, serverId: profile.id)
        let viewModel = ServerWorkspaceViewModel()

        viewModel.loadRemoteFileTransferHistory(profile: profile, repository: repository)

        XCTAssertEqual(viewModel.remoteFileTransferJobs.map(\.status), [.interrupted, .interrupted])
        XCTAssertTrue(viewModel.remoteFileTransferJobs.allSatisfy { $0.message == "Transfer was interrupted before completion." })
        XCTAssertEqual(try repository.fetchRemoteFileTransferJobs(serverId: profile.id).map(\.status), [.interrupted, .interrupted])
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

    func testFirewallRuleMutationRefreshesAndAudits() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let client = FirewallViewModelMockSSHClient()
        let viewModel = ServerWorkspaceViewModel()
        let manager = FirewallManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.loadFirewallSnapshot(profile: profile, sshClient: client, firewallManager: manager)
        try await waitUntil { viewModel.firewallSnapshot != nil }
        viewModel.applyFirewallRule(
            FirewallRuleDraft(
                mutation: .add,
                direction: .ingress,
                action: .allow,
                proto: .tcp,
                port: 443,
                cidr: "203.0.113.0/24"
            ),
            profile: profile,
            sshClient: client,
            firewallManager: manager,
            repository: repository
        )

        try await waitUntil { viewModel.isMutatingFirewall == false && viewModel.firewallActionMessage != nil }

        XCTAssertTrue(client.commands.contains(where: { $0.contains("iptables -A INPUT") && $0.contains("--dport 443") }))
        XCTAssertEqual(viewModel.firewallActionMessage, "Add firewall rule succeeded.")
        XCTAssertNil(viewModel.firewallErrorMessage)
        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        XCTAssertEqual(logs.first?.targetType, "firewall")
        XCTAssertEqual(logs.first?.action, "add")
        XCTAssertEqual(logs.first?.status, "success")
        XCTAssertTrue(logs.first?.beforeSnapshot?.contains("--dport 22") == true)
        XCTAssertTrue(logs.first?.afterSnapshot?.contains("--dport 22") == true)
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
            securityGroupIds: [],
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

    func testCloudSecurityGroupsShowPermissionGuidanceWhenProviderDeniesRead() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.security-denied.\(UUID().uuidString)")
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
            securityGroupIds: [],
            rawJSON: nil,
            lastSyncedAt: Date()
        ))
        let service = CloudSecurityGroupService(
            repository: repository,
            keychain: keychain,
            registry: CloudProviderRegistry(adapters: [
                SecurityGroupViewModelMockCloudAdapter(
                    providerId: .tencentCloud,
                    fetchSecurityGroupsError: .permissionDenied("UnauthorizedOperation: CAM policy denied")
                )
            ]),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let viewModel = ServerWorkspaceViewModel()

        viewModel.loadCloudSecurityGroups(profile: profile, cloudSecurityGroupService: service)
        try await waitUntil { viewModel.isLoadingCloudSecurityGroups == false && viewModel.cloudSecurityGroupErrorMessage != nil }

        let message = try XCTUnwrap(viewModel.cloudSecurityGroupErrorMessage)
        XCTAssertTrue(message.contains("could not read security groups"))
        XCTAssertTrue(message.contains("Grant security group read permissions"))
        XCTAssertTrue(message.contains("UnauthorizedOperation"))
        XCTAssertNil(viewModel.cloudSecurityGroupList)
    }

    func testCloudSecurityGroupsUnavailableWithoutCloudLinkDoesNotAffectSSHState() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.security-unlinked.\(UUID().uuidString)")
        let service = CloudSecurityGroupService(
            repository: repository,
            keychain: keychain,
            registry: CloudProviderRegistry(adapters: [
                SecurityGroupViewModelMockCloudAdapter(providerId: .tencentCloud)
            ]),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let viewModel = ServerWorkspaceViewModel()
        viewModel.connectionState = .connected
        viewModel.commandResult = CommandResult(
            command: "printf hhc-ssh-ok",
            stdout: "hhc-ssh-ok",
            stderr: "",
            exitCode: 0,
            duration: 0.1
        )

        viewModel.loadCloudSecurityGroups(profile: profile, cloudSecurityGroupService: service)
        try await waitUntil { viewModel.isLoadingCloudSecurityGroups == false && viewModel.cloudSecurityGroupErrorMessage != nil }

        XCTAssertEqual(viewModel.connectionState, .connected)
        XCTAssertEqual(viewModel.commandResult?.stdout, "hhc-ssh-ok")
        XCTAssertTrue(viewModel.cloudSecurityGroupErrorMessage?.contains("This server is not linked to a cloud instance.") == true)
        XCTAssertNil(viewModel.cloudSecurityGroupList)
        XCTAssertNil(viewModel.selectedCloudSecurityGroup)
        XCTAssertNil(viewModel.cloudSecurityGroupPolicySnapshot)
    }

    func testCloudSecurityGroupRuleChangeAppliesRefreshesAndAudits() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.security-action.\(UUID().uuidString)")
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
            securityGroupIds: [],
            rawJSON: nil,
            lastSyncedAt: Date()
        ))
        let recorder = SecurityGroupActionRecorder()
        let service = CloudSecurityGroupService(
            repository: repository,
            keychain: keychain,
            registry: CloudProviderRegistry(adapters: [
                SecurityGroupViewModelMockCloudAdapter(providerId: .tencentCloud, recorder: recorder)
            ]),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let viewModel = ServerWorkspaceViewModel()

        viewModel.loadCloudSecurityGroups(profile: profile, cloudSecurityGroupService: service)
        try await waitUntil { viewModel.cloudSecurityGroupPolicySnapshot != nil }
        let snapshot = try XCTUnwrap(viewModel.cloudSecurityGroupPolicySnapshot)
        let preview = CloudSecurityGroupRuleChangePreview.adding(
            draft: CloudSecurityGroupRuleDraft(
                direction: .ingress,
                protocolName: "TCP",
                port: "443",
                cidrBlock: "203.0.113.0/24",
                action: "ACCEPT",
                description: "HTTPS"
            ),
            to: snapshot
        )

        viewModel.applyCloudSecurityGroupRuleChange(
            preview,
            profile: profile,
            cloudSecurityGroupService: service,
            repository: repository
        )
        try await waitUntil { viewModel.isMutatingCloudSecurityGroupRule == false && viewModel.cloudSecurityGroupActionMessage != nil }

        XCTAssertEqual(recorder.previews.map(\.proposedRule.port), ["443"])
        XCTAssertEqual(viewModel.cloudSecurityGroupActionMessage, "Add security group rule succeeded.")
        XCTAssertTrue(viewModel.cloudSecurityGroupPolicySnapshot?.ingress.contains { $0.port == "443" } == true)
        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        XCTAssertEqual(logs.first?.targetType, "security_group")
        XCTAssertEqual(logs.first?.action, "add")
        XCTAssertEqual(logs.first?.status, "success")
        XCTAssertTrue(logs.first?.afterSnapshot?.contains("443") == true)
    }

    func testCloudSecurityGroupRuleChangePermissionFailureAuditsGuidance() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.security-action-denied.\(UUID().uuidString)")
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
            securityGroupIds: [],
            rawJSON: nil,
            lastSyncedAt: Date()
        ))
        let service = CloudSecurityGroupService(
            repository: repository,
            keychain: keychain,
            registry: CloudProviderRegistry(adapters: [
                SecurityGroupViewModelMockCloudAdapter(
                    providerId: .tencentCloud,
                    applySecurityGroupRuleChangeError: .permissionDenied("AuthFailure.UnauthorizedOperation")
                )
            ]),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let viewModel = ServerWorkspaceViewModel()

        viewModel.loadCloudSecurityGroups(profile: profile, cloudSecurityGroupService: service)
        try await waitUntil { viewModel.cloudSecurityGroupPolicySnapshot != nil }
        let snapshot = try XCTUnwrap(viewModel.cloudSecurityGroupPolicySnapshot)
        let preview = CloudSecurityGroupRuleChangePreview.adding(
            draft: CloudSecurityGroupRuleDraft(
                direction: .ingress,
                protocolName: "TCP",
                port: "443",
                cidrBlock: "203.0.113.0/24",
                action: "ACCEPT",
                description: "HTTPS"
            ),
            to: snapshot
        )

        viewModel.applyCloudSecurityGroupRuleChange(
            preview,
            profile: profile,
            cloudSecurityGroupService: service,
            repository: repository
        )
        try await waitUntil { viewModel.isMutatingCloudSecurityGroupRule == false && viewModel.cloudSecurityGroupErrorMessage != nil }

        let message = try XCTUnwrap(viewModel.cloudSecurityGroupErrorMessage)
        XCTAssertTrue(message.contains("could not add security group rule"))
        XCTAssertTrue(message.contains("Grant security group rule write permissions"))
        XCTAssertTrue(message.contains("AuthFailure.UnauthorizedOperation"))
        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        XCTAssertEqual(logs.first?.targetType, "security_group")
        XCTAssertEqual(logs.first?.action, "add")
        XCTAssertEqual(logs.first?.status, "failed")
        XCTAssertTrue(logs.first?.message?.contains("Grant security group rule write permissions") == true)
    }

    func testPrivateRegistriesWorkspaceLoadsVerdaccioStateAndCreatesBackupAndRestore() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let viewModel = ServerWorkspaceViewModel()
        let client = RegistryViewModelMockSSHClient()
        let preflight = RegistryPreflightChecker(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.runRegistryPreflight(
            profile: profile,
            sshClient: client,
            registryPreflightChecker: preflight
        )
        try await waitUntil { viewModel.isRunningRegistryPreflight == false && viewModel.registryPreflightReport != nil }

        viewModel.loadVerdaccioStatus(profile: profile, sshClient: client, verdaccioManager: manager)
        try await waitUntil { viewModel.isLoadingVerdaccioStatus == false && viewModel.verdaccioStatusSnapshot != nil }

        viewModel.loadVerdaccioPackages(profile: profile, sshClient: client, verdaccioManager: manager)
        try await waitUntil { viewModel.isLoadingVerdaccioPackages == false && !viewModel.verdaccioPackages.isEmpty }

        viewModel.createVerdaccioBackup(
            profile: profile,
            sshClient: client,
            verdaccioManager: manager,
            repository: repository
        )
        try await waitUntil { viewModel.isCreatingVerdaccioBackup == false && viewModel.verdaccioBackupResult != nil }

        XCTAssertTrue(viewModel.registryPreflightReport?.isReady == true)
        XCTAssertTrue(viewModel.verdaccioStatusSnapshot?.isRunning == true)
        XCTAssertEqual(viewModel.verdaccioPackages.first?.name, "@scope/pkg")
        XCTAssertEqual(viewModel.verdaccioBackupResult?.sizeBytes, 2048)
        XCTAssertEqual(viewModel.verdaccioRestorePathDraft, "/srv/verdaccio/backups/verdaccio-2023-11-14T22-13-20.000Z.tar.gz")
        XCTAssertTrue(viewModel.registryActionMessage?.contains("Created Verdaccio backup") == true)
        XCTAssertTrue(client.commands.contains { $0.contains("command -v htpasswd") })
        XCTAssertTrue(client.commands.contains { $0.contains("journalctl -u") })
        XCTAssertTrue(client.commands.contains { $0.contains("find \"$data_path\"") })
        XCTAssertTrue(client.commands.contains { $0.contains("tar -czf") })

        viewModel.restoreVerdaccioBackup(
            profile: profile,
            sshClient: client,
            verdaccioManager: manager,
            repository: repository
        )
        try await waitUntil { viewModel.isRestoringVerdaccioBackup == false && viewModel.verdaccioRestoreResult != nil }

        XCTAssertEqual(viewModel.verdaccioRestoreResult?.backupPath, "/srv/verdaccio/backups/verdaccio-2023-11-14T22-13-20.000Z.tar.gz")
        XCTAssertTrue(viewModel.verdaccioRestoreResult?.rollbackBackupPath.hasPrefix("/srv/verdaccio/backups/restore-rollback-") == true)
        XCTAssertTrue(viewModel.registryActionMessage?.contains("Restored Verdaccio backup") == true)
        XCTAssertTrue(viewModel.verdaccioStatusSnapshot?.isRunning == true)
        XCTAssertTrue(client.commands.contains { $0.contains("tar -xzf \"$archive_path\" -C \"$restore_dir\"") })
        XCTAssertTrue(client.commands.contains { $0.contains("systemctl stop \"$service\"") })
        XCTAssertTrue(client.commands.contains { $0.contains("__HHC_VERDACCIO_ACTIVE_STATE__") })
    }

    func testPrivateRegistriesWorkspaceInstallsVerdaccioAndRefreshesStatus() async throws {
        let profile = makeProfile()
        let viewModel = ServerWorkspaceViewModel()
        let client = RegistryViewModelMockSSHClient()
        let installer = VerdaccioInstaller()
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.installVerdaccio(
            profile: profile,
            sshClient: client,
            verdaccioInstaller: installer,
            verdaccioManager: manager
        )
        try await waitUntil { viewModel.isInstallingVerdaccio == false && viewModel.verdaccioInstallResult != nil }

        XCTAssertEqual(viewModel.verdaccioInstallResult?.configPath, "/srv/verdaccio/config.yaml")
        XCTAssertEqual(viewModel.verdaccioInstallResult?.servicePath, "/etc/systemd/system/verdaccio.service")
        XCTAssertEqual(viewModel.verdaccioInstallResult?.healthCheckOutput, #"{"ok":"verdaccio"}"#)
        XCTAssertTrue(viewModel.verdaccioStatusSnapshot?.isRunning == true)
        XCTAssertTrue(viewModel.registryActionMessage?.contains("Installed Verdaccio") == true)
        XCTAssertTrue(client.commands.contains { $0.contains("systemctl enable --now 'verdaccio.service'") })
        XCTAssertTrue(client.commands.contains { $0.contains("for attempt in $(seq 1 8)") && $0.contains("http://127.0.0.1:4873/-/ping") })
        XCTAssertTrue(client.commands.contains { $0.contains("__HHC_VERDACCIO_ACTIVE_STATE__") })
    }

    func testPrivateRegistriesWorkspaceControlsAndUpgradesVerdaccioService() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let viewModel = ServerWorkspaceViewModel()
        let client = RegistryViewModelMockSSHClient()
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.registryDraft.version = "5.31.2"
        viewModel.performVerdaccioServiceAction(
            .restart,
            profile: profile,
            sshClient: client,
            verdaccioManager: manager,
            repository: repository
        )
        try await waitUntil { viewModel.isControllingVerdaccioService == false && viewModel.verdaccioServiceActionResult != nil }

        XCTAssertEqual(viewModel.verdaccioServiceActionResult?.action, .restart)
        XCTAssertTrue(viewModel.verdaccioStatusSnapshot?.isRunning == true)
        XCTAssertEqual(viewModel.registryActionMessage, "Restart requested for verdaccio.service.")

        viewModel.upgradeVerdaccio(
            profile: profile,
            sshClient: client,
            verdaccioManager: manager,
            repository: repository
        )
        try await waitUntil { viewModel.isUpgradingVerdaccio == false && viewModel.verdaccioUpgradeResult != nil }

        XCTAssertEqual(viewModel.verdaccioUpgradeResult?.version, "5.31.2")
        XCTAssertTrue(viewModel.verdaccioUpgradeResult?.backupPath.contains("/srv/verdaccio/backups/verdaccio.service.hhc-backup-") == true)
        XCTAssertTrue(viewModel.registryActionMessage?.contains("Upgraded Verdaccio to 5.31.2") == true)
        XCTAssertTrue(client.commands.contains { $0.contains("systemctl restart \"$service\"") })
        XCTAssertTrue(client.commands.contains { $0.contains("__HHC_VERDACCIO_SERVICE_UPGRADE__") })

        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id)
        XCTAssertEqual(logs.map(\.action), ["verdaccio-upgrade", "verdaccio-restart"])
        XCTAssertEqual(logs.map(\.targetType), ["registry", "registry"])
        XCTAssertTrue(logs.allSatisfy { $0.status == "success" })
    }

    func testPrivateRegistriesWorkspaceManagesVerdaccioUsers() async throws {
        let profile = makeProfile()
        let viewModel = ServerWorkspaceViewModel()
        let client = RegistryViewModelMockSSHClient()
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.verdaccioUsernameDraft = "team.dev"
        viewModel.verdaccioPasswordDraft = "Correct-Horse-Secret-123"
        viewModel.createVerdaccioUser(profile: profile, sshClient: client, verdaccioManager: manager)
        try await waitUntil { viewModel.isMutatingVerdaccioUser == false && viewModel.verdaccioUserMutationResult?.action == .create }

        XCTAssertEqual(viewModel.verdaccioUserMutationResult?.username, "team.dev")
        XCTAssertEqual(viewModel.verdaccioPasswordDraft, "")
        XCTAssertTrue(viewModel.registryActionMessage?.contains("Created Verdaccio user team.dev") == true)

        viewModel.verdaccioPasswordDraft = "Correct-Horse-Secret-456"
        viewModel.updateVerdaccioUserPassword(profile: profile, sshClient: client, verdaccioManager: manager)
        try await waitUntil { viewModel.isMutatingVerdaccioUser == false && viewModel.verdaccioUserMutationResult?.action == .updatePassword }

        viewModel.deleteVerdaccioUser(profile: profile, sshClient: client, verdaccioManager: manager)
        try await waitUntil { viewModel.isMutatingVerdaccioUser == false && viewModel.verdaccioUserMutationResult?.action == .delete }

        XCTAssertTrue(viewModel.registryActionMessage?.contains("Deleted Verdaccio user team.dev") == true)
        XCTAssertTrue(client.commands.contains { $0.contains("htpasswd -B -i") && $0.contains("'create'") })
        XCTAssertTrue(client.commands.contains { $0.contains("htpasswd -B -i") && $0.contains("'update'") })
        XCTAssertTrue(client.commands.contains { $0.contains("htpasswd -D") })
        XCTAssertFalse(client.commands.joined(separator: "\n").contains("Correct-Horse-Secret"))
    }

    func testPrivateRegistriesWorkspaceRunsNpmSmokeTest() async throws {
        let profile = makeProfile()
        let viewModel = ServerWorkspaceViewModel()
        let client = RegistryViewModelMockSSHClient()
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.verdaccioUsernameDraft = "team.dev"
        viewModel.verdaccioPasswordDraft = "Correct-Horse-Secret-123"
        viewModel.verdaccioEmailDraft = "team@example.com"
        viewModel.runVerdaccioNpmSmokeTest(profile: profile, sshClient: client, verdaccioManager: manager)
        try await waitUntil { viewModel.isRunningVerdaccioNpmSmokeTest == false && viewModel.verdaccioNpmSmokeTestResult != nil }

        XCTAssertTrue(viewModel.verdaccioNpmSmokeTestResult?.packageName.hasPrefix("@hhc-smoke/pkg-") == true)
        XCTAssertEqual(viewModel.verdaccioNpmSmokeTestResult?.requireOutput, "hhc-verdaccio-smoke-ok")
        XCTAssertEqual(viewModel.verdaccioPasswordDraft, "")
        XCTAssertTrue(viewModel.registryActionMessage?.contains("Verified npm publish/install") == true)
        XCTAssertTrue(client.commands.contains { $0.contains("npm publish") && $0.contains("npm install") })
        XCTAssertFalse(client.commands.joined(separator: "\n").contains("Correct-Horse-Secret"))
    }

    func testPrivateRegistriesWorkspaceWritesAndReloadsVerdaccioNginxProxy() async throws {
        let profile = makeProfile()
        let repository = try makeRepository(with: profile)
        let viewModel = ServerWorkspaceViewModel()
        let client = RegistryViewModelMockSSHClient()
        let manager = NginxConfigManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        viewModel.verdaccioProxyDraft = VerdaccioNginxProxyDraft(
            serverName: "registry.example.com",
            configPath: "/www/server/nginx/conf/vhost/verdaccio.conf",
            clientMaxBodySize: "200m"
        )
        viewModel.writeVerdaccioNginxProxy(
            profile: profile,
            sshClient: client,
            nginxConfigManager: manager,
            repository: repository
        )
        try await waitUntil { viewModel.isWritingVerdaccioProxy == false && viewModel.verdaccioProxyUpsertResult != nil }

        XCTAssertEqual(viewModel.verdaccioProxyUpsertResult?.file.path, "/www/server/nginx/conf/vhost/verdaccio.conf")
        XCTAssertTrue(viewModel.verdaccioProxyUpsertResult?.testResult.succeeded == true)
        XCTAssertTrue(viewModel.registryActionMessage?.contains("Wrote Verdaccio Nginx proxy") == true)
        XCTAssertTrue(client.commands.contains { $0.contains("__HHC_NGINX_CONFIG_EOF__") && $0.contains("/www/server/nginx/conf/vhost/verdaccio.conf") })

        viewModel.reloadVerdaccioNginxProxy(
            profile: profile,
            sshClient: client,
            nginxConfigManager: manager,
            repository: repository
        )
        try await waitUntil { viewModel.isReloadingVerdaccioProxy == false && viewModel.registryActionMessage == "Reloaded Nginx for Verdaccio proxy." }

        XCTAssertTrue(client.commands.contains("nginx -t"))
        XCTAssertTrue(client.commands.contains("systemctl reload nginx 2>/dev/null || nginx -s reload"))
        let logs = try repository.fetchRemoteChangeLogs(serverId: profile.id, limit: 5)
        XCTAssertEqual(logs.filter { $0.action.contains("verdaccio-proxy") }.map(\.status), ["success", "success"])
    }

    func testPrivateRegistriesWorkspaceBuildsPubHostedRepositoryPlan() {
        let viewModel = ServerWorkspaceViewModel()
        viewModel.pubHostedRepositoryDraft = PubHostedRepositoryDraft(
            hostedURL: "https://pub.example.com/team",
            packageName: "team_package",
            tokenEnvironmentVariable: "HHC_PUB_TOKEN",
            includeFlutterCommand: true
        )

        viewModel.buildPubHostedRepositoryPlan(generatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(viewModel.pubHostedRepositoryPlan?.hostedURL, "https://pub.example.com/team")
        XCTAssertTrue(viewModel.pubHostedRepositoryPlan?.pubspecSnippet.contains("team_package:") == true)
        XCTAssertEqual(viewModel.pubHostedRepositoryPlan?.flutterGetCommand, "flutter pub get")
        XCTAssertEqual(viewModel.registryActionMessage, "Generated Dart/Flutter hosted pub configuration.")
        XCTAssertNil(viewModel.registryErrorMessage)

        viewModel.pubHostedRepositoryDraft.hostedURL = "https://pub.example.com?token=secret"
        viewModel.buildPubHostedRepositoryPlan()

        XCTAssertNil(viewModel.pubHostedRepositoryPlan)
        XCTAssertNil(viewModel.registryActionMessage)
        XCTAssertTrue(viewModel.registryErrorMessage?.contains("hosted repository URL") == true)
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
    private let delayNanoseconds: UInt64
    private let lock = NSLock()
    private var smokeTestCalls = 0

    var smokeTestCallCount: Int {
        lock.withLock { smokeTestCalls }
    }

    init(result: CommandResult? = nil, error: Error? = nil, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        lock.withLock {
            smokeTestCalls += 1
        }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
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
    private let failingStep: String?

    init(failingStep: String? = nil) {
        self.failingStep = failingStep
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        let step = stepName(for: command)
        if step == failingStep {
            return CommandResult(command: command, stdout: "", stderr: "\(step) failed", exitCode: 1, duration: 0.1)
        }
        if command.contains("if [ -d") && command.contains("git rev-parse HEAD") {
            return CommandResult(command: command, stdout: "abc1234\n", stderr: "", exitCode: 0, duration: 0.1)
        }
        if command.contains("git rev-parse HEAD") {
            return CommandResult(command: command, stdout: "def4567\n", stderr: "", exitCode: 0, duration: 0.1)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0.1)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}

    private func stepName(for command: String) -> String {
        if command == "command -v git" {
            return "git_check"
        }
        if command.contains("if [ -d") && command.contains("git rev-parse HEAD") {
            return "current_commit"
        }
        if command.contains("git clone") || command.contains("git fetch") {
            return "clone_or_fetch"
        }
        if command.contains("git reset --hard") {
            return "checkout"
        }
        if command.contains("git rev-parse HEAD") {
            return "target_commit"
        }
        if command.contains("npm run build") {
            return "build"
        }
        if command.contains("curl -fsS") {
            return "health_check"
        }
        return "command"
    }
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

private final class DashboardNoProcMockSSHClient: SSHClient, @unchecked Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        if command.contains("/proc/loadavg") ||
            command.contains("/proc/meminfo") ||
            command.contains("/proc/net/dev") {
            throw SSHClientError.processFailed("/proc unavailable")
        }
        if command.contains("ps -eo stat=") {
            throw SSHClientError.processFailed("ps unavailable")
        }

        let stdout: String
        if command.contains("/etc/os-release") {
            stdout = """
            NAME="Alpine Linux"
            VERSION_ID=3.20
            """
        } else if command == "uname -r" {
            stdout = "6.6.0\n"
        } else if command.contains("test -d /proc") ||
            command.contains("systemctl") ||
            command.contains("sftp") {
            stdout = "no\n"
        } else if command.contains("df -kP") {
            stdout = "/dev/vda1 10485760 2097152 8388608 20% /\n"
        } else if command.contains("_NPROCESSORS_ONLN") {
            stdout = "2\n"
        } else {
            stdout = ""
        }
        return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
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
    private let lock = NSLock()
    private var uploadRecords: [(localURL: URL, remotePath: String)] = []
    private var downloadRecords: [(remotePath: String, localURL: URL)] = []
    private var remoteNames = ["app.env"]

    var uploads: [(localURL: URL, remotePath: String)] {
        locked { uploadRecords }
    }

    var downloads: [(remotePath: String, localURL: URL)] {
        locked { downloadRecords }
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        if command.contains("find . -maxdepth 1") {
            let names = locked { remoteNames }
            let stdout = names.map { name in
                "\(name)\tf\t8\t1700000001.0\t-rw-r--r--"
            }.joined(separator: "\n")
            return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile, progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?) async throws -> RemoteFileTransferResult {
        progressHandler?(RemoteFileTransferProgress(completedBytes: 0, totalBytes: 8, fraction: 0))
        locked {
            uploadRecords.append((localURL, remotePath))
            remoteNames.append(localURL.lastPathComponent)
            remoteNames.sort()
        }
        progressHandler?(RemoteFileTransferProgress(completedBytes: 8, totalBytes: 8, fraction: 1))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 8,
            duration: 0,
            backend: .nativeSFTP,
            supportsResume: true,
            supportsStreamingProgress: true
        )
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile, progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?) async throws -> RemoteFileTransferResult {
        locked {
            downloadRecords.append((remotePath, localURL))
        }
        progressHandler?(RemoteFileTransferProgress(completedBytes: 8, totalBytes: 8, fraction: 1))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 8,
            duration: 0,
            backend: .nativeSFTP,
            supportsResume: true,
            supportsStreamingProgress: true
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private final class SlowRemoteFileTransferMockSSHClient: SSHClient, RemoteFileTransferClient, @unchecked Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile, progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?) async throws -> RemoteFileTransferResult {
        progressHandler?(RemoteFileTransferProgress(completedBytes: 512, totalBytes: 1_024, fraction: 0.5))
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 1_024,
            duration: 5
        )
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile, progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?) async throws -> RemoteFileTransferResult {
        progressHandler?(RemoteFileTransferProgress(completedBytes: 512, totalBytes: 1_024, fraction: 0.5))
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 1_024,
            duration: 5
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class QueuedRemoteFileTransferMockSSHClient: SSHClient, RemoteFileTransferClient, @unchecked Sendable {
    private let lock = NSLock()
    private var uploadRecords: [(localURL: URL, remotePath: String)] = []
    private var remoteNames: [String] = []

    var uploads: [(localURL: URL, remotePath: String)] {
        locked { uploadRecords }
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        if command.contains("find . -maxdepth 1") {
            let names = locked { remoteNames.sorted() }
            let stdout = names.map { name in
                "\(name)\tf\t8\t1700000001.0\t-rw-r--r--"
            }
            .joined(separator: "\n")
            return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile, progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?) async throws -> RemoteFileTransferResult {
        try await Task.sleep(nanoseconds: 50_000_000)
        locked {
            uploadRecords.append((localURL, remotePath))
            remoteNames.append(localURL.lastPathComponent)
        }
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 8,
            duration: 0.05
        )
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile, progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?) async throws -> RemoteFileTransferResult {
        RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: 8,
            duration: 0
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
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
        if command.contains("__HHC_USER_CRONTAB__") {
            return CommandResult(
                command: command,
                stdout: """
                __HHC_USER_CRONTAB__
                \(crontab)__HHC_SYSTEM_CRON_D__
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
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
    private(set) var commands: [String] = []

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        return CommandResult(
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

private final class RegistryViewModelMockSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if command.contains("systemctl enable --now 'verdaccio.service'") {
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("__HHC_NGINX_CONFIG_EOF__") {
            return CommandResult(
                command: command,
                stdout: """
                __HHC_NGINX_CREATED__1
                __HHC_NGINX_BACKUP__
                nginx: the configuration file /www/server/nginx/conf/nginx.conf syntax is ok
                nginx: configuration file /www/server/nginx/conf/nginx.conf test is successful
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command == "nginx -t" {
            return CommandResult(
                command: command,
                stdout: "nginx: configuration file /www/server/nginx/conf/nginx.conf test is successful\n",
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command == "systemctl reload nginx 2>/dev/null || nginx -s reload" {
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("__HHC_VERDACCIO_SERVICE_UPGRADE__") {
            return CommandResult(
                command: command,
                stdout: "__HHC_VERDACCIO_SERVICE_BACKUP__/srv/verdaccio/backups/verdaccio.service.hhc-backup-2026\n",
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("systemctl start \"$service\"") ||
            command.contains("systemctl stop \"$service\"") ||
            command.contains("systemctl restart \"$service\"")
        {
            return CommandResult(command: command, stdout: "ActiveState=active\nSubState=running\n", stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("npm publish") && command.contains("__HHC_VERDACCIO_NPM_REQUIRE__") {
            return CommandResult(
                command: command,
                stdout: """
                __HHC_VERDACCIO_NPM_PACKAGE__@hhc-smoke/pkg-2026
                __HHC_VERDACCIO_NPM_PUBLISH__+ @hhc-smoke/pkg-2026@0.0.1
                __HHC_VERDACCIO_NPM_INSTALL__added 1 package
                __HHC_VERDACCIO_NPM_REQUIRE__hhc-verdaccio-smoke-ok
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("htpasswd -B -i") || command.contains("htpasswd -D") {
            return CommandResult(
                command: command,
                stdout: "__HHC_VERDACCIO_HTPASSWD_BACKUP__/srv/verdaccio/htpasswd.hhc-backup-2024-01-01T00-00-00Z\n",
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("curl -fsS") && command.contains("http://127.0.0.1:4873/-/ping") {
            return CommandResult(command: command, stdout: #"{"ok":"verdaccio"}"#, stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("__HHC_REGISTRY_NODE_VERSION__") {
            return CommandResult(
                command: command,
                stdout: """
                __HHC_REGISTRY_NODE_VERSION__v20.11.1
                __HHC_REGISTRY_PACKAGE_MANAGER__npm 10.2.4
                __HHC_REGISTRY_HTPASSWD__yes
                __HHC_REGISTRY_SYSTEMD__yes
                __HHC_REGISTRY_PORT_BUSY__no
                __HHC_REGISTRY_INSTALL_PARENT_WRITABLE__yes
                __HHC_REGISTRY_DATA_PARENT_WRITABLE__yes
                __HHC_REGISTRY_DISK_AVAILABLE_KB__1048576
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("__HHC_VERDACCIO_ACTIVE_STATE__") {
            let logs = Data("Verdaccio listening on 127.0.0.1:4873\n".utf8).base64EncodedString()
            return CommandResult(
                command: command,
                stdout: """
                __HHC_VERDACCIO_ACTIVE_STATE__active
                __HHC_VERDACCIO_SUB_STATE__running
                __HHC_VERDACCIO_VERSION__5.31.1
                __HHC_VERDACCIO_STORAGE_BYTES__2048
                __HHC_VERDACCIO_LOGS__\(logs)
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("find \"$data_path\"") {
            return CommandResult(
                command: command,
                stdout: "@scope/pkg\t2\t1.1.0\t2048\t1700000000\n",
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.contains("tar -xzf \"$archive_path\" -C \"$restore_dir\"") {
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("tar -czf") {
            return CommandResult(command: command, stdout: "2048\n", stderr: "", exitCode: 0, duration: 0)
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class SecurityGroupActionRecorder: @unchecked Sendable {
    var previews: [CloudSecurityGroupRuleChangePreview] = []
}

private struct SecurityGroupViewModelMockCloudAdapter: CloudProviderAdapter {
    let providerId: CloudProviderID
    let displayName = "Mock Cloud"
    let capabilities: Set<CloudCapability> = [.securityGroups, .securityGroupActions]
    var recorder: SecurityGroupActionRecorder? = nil
    var fetchSecurityGroupsError: CloudProviderError?
    var fetchSecurityGroupPoliciesError: CloudProviderError?
    var applySecurityGroupRuleChangeError: CloudProviderError?

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
        if let fetchSecurityGroupsError {
            throw fetchSecurityGroupsError
        }
        return [
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
        if let fetchSecurityGroupPoliciesError {
            throw fetchSecurityGroupPoliciesError
        }
        var ingress = [
            CloudSecurityGroupRule(
                direction: .ingress,
                policyIndex: 0,
                providerRuleId: nil,
                protocolName: "TCP",
                port: "22",
                cidrBlock: "203.0.113.0/24",
                ipv6CidrBlock: nil,
                referencedSecurityGroupId: nil,
                action: "ACCEPT",
                description: "SSH",
                modifiedTime: nil
            ),
        ]
        ingress.append(contentsOf: recorder?.previews.map(\.proposedRule) ?? [])
        return CloudSecurityGroupPolicySnapshot(
            group: group,
            version: "7",
            ingress: ingress,
            egress: [
                CloudSecurityGroupRule(
                    direction: .egress,
                    policyIndex: 0,
                    providerRuleId: nil,
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

    func applySecurityGroupRuleChange(
        credential: CloudProviderCredential,
        preview: CloudSecurityGroupRuleChangePreview
    ) async throws -> String? {
        if let applySecurityGroupRuleChangeError {
            throw applySecurityGroupRuleChangeError
        }
        recorder?.previews.append(preview)
        return "request-security-group-action"
    }

    func fetchDisks(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudDisk] {
        []
    }

    func fetchSnapshots(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudSnapshot] {
        []
    }

    func fetchBillingStates(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudBillingState] {
        []
    }

    func createSnapshot(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        diskId: String,
        snapshotName: String,
        capturedAt: Date
    ) async throws -> CloudSnapshot {
        throw CloudProviderError.unsupportedCapability(providerId: providerId, capability: .snapshotActions)
    }

    func deleteSnapshot(
        credential: CloudProviderCredential,
        regionId: String,
        snapshotId: String
    ) async throws {
        throw CloudProviderError.unsupportedCapability(providerId: providerId, capability: .snapshotActions)
    }

    func attachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String,
        instanceId: String
    ) async throws {
        throw CloudProviderError.unsupportedCapability(providerId: providerId, capability: .diskAttachmentActions)
    }

    func detachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String
    ) async throws {
        throw CloudProviderError.unsupportedCapability(providerId: providerId, capability: .diskAttachmentActions)
    }

    func startInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        throw CloudProviderError.unsupportedCapability(providerId: providerId, capability: .powerActions)
    }

    func stopInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        throw CloudProviderError.unsupportedCapability(providerId: providerId, capability: .powerActions)
    }

    func rebootInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        throw CloudProviderError.unsupportedCapability(providerId: providerId, capability: .powerActions)
    }
}
