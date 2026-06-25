import XCTest
@testable import HHCServerManager

final class ServerManagementServiceTests: XCTestCase {
    func testCreateServerStoresProfileAndPasswordCredential() throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "Tencent",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: "prod",
            authType: .password,
            credential: .password("secret")
        )

        let servers = try harness.repository.fetchServers()
        XCTAssertEqual(servers.map(\.id), [profile.id])
        XCTAssertEqual(try harness.keychain.readPassword(keychainRef: profile.keychainRef), "secret")
    }

    func testDeleteServerRemovesProfileTrustedKeysAndCredentials() throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "Tencent",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .privateKey,
            credential: .privateKey(data: Data("key".utf8), passphrase: nil)
        )
        try harness.repository.saveTrustedHostKey(TrustedHostKey(
            id: UUID(),
            serverId: profile.id,
            host: profile.host,
            port: profile.port,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:test",
            rawPublicKey: "example.internal ssh-ed25519 AAAATEST",
            trustedAt: Date()
        ))

        try harness.service.deleteServer(profile)

        XCTAssertTrue(try harness.repository.fetchServers().isEmpty)
        XCTAssertTrue(try harness.repository.fetchTrustedHostKeys(serverId: profile.id).isEmpty)
        XCTAssertNil(try harness.keychain.readPrivateKey(keychainRef: profile.keychainRef))
    }

    func testUpdateServerCanKeepExistingCredential() throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "Tencent",
            host: "old.example",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("original")
        )

        let updated = try harness.service.updateServer(
            profile,
            name: "Renamed",
            host: "new.example",
            port: 2222,
            username: "ubuntu",
            groupName: "prod",
            authType: .password,
            credentialUpdate: .keepExisting
        )

        XCTAssertEqual(updated.id, profile.id)
        XCTAssertEqual(updated.keychainRef, profile.keychainRef)
        XCTAssertEqual(updated.name, "Renamed")
        XCTAssertEqual(updated.port, 2222)
        XCTAssertEqual(try harness.keychain.readPassword(keychainRef: profile.keychainRef), "original")
    }

    func testUpdateServerCanReplaceCredentialWithoutChangingKeychainRef() throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "Tencent",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("old")
        )

        let updated = try harness.service.updateServer(
            profile,
            name: profile.name,
            host: profile.host,
            port: profile.port,
            username: profile.username,
            groupName: nil,
            authType: .password,
            credentialUpdate: .replace(.password("new"))
        )

        XCTAssertEqual(updated.keychainRef, profile.keychainRef)
        XCTAssertEqual(try harness.keychain.readPassword(keychainRef: profile.keychainRef), "new")
    }

    func testCloudAccountServiceCreatesUpdatesAndDeletesAccountWithCredential() throws {
        let harness = try Harness()
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: " Tencent Read Only ",
            credential: CloudProviderCredential(secretId: "sid-1", secretKey: "skey-1")
        )

        XCTAssertEqual(account.displayName, "Tencent Read Only")
        XCTAssertEqual(try harness.repository.fetchCloudProviderAccounts().map(\.id), [account.id])
        XCTAssertEqual(
            try harness.keychain.readCloudCredential(keychainRef: account.keychainRef),
            CloudProviderCredential(secretId: "sid-1", secretKey: "skey-1")
        )

        let updated = try harness.cloudAccountService.updateAccount(
            account,
            displayName: "Tencent Disabled",
            enabled: false,
            credential: CloudProviderCredential(secretId: "sid-2", secretKey: "skey-2")
        )

        XCTAssertEqual(updated.keychainRef, account.keychainRef)
        XCTAssertFalse(updated.enabled)
        XCTAssertEqual(try harness.repository.fetchCloudProviderAccounts()[0].displayName, "Tencent Disabled")
        XCTAssertEqual(
            try harness.keychain.readCloudCredential(keychainRef: account.keychainRef),
            CloudProviderCredential(secretId: "sid-2", secretKey: "skey-2")
        )

        try harness.cloudAccountService.deleteAccount(updated)

        XCTAssertTrue(try harness.repository.fetchCloudProviderAccounts().isEmpty)
        XCTAssertNil(try harness.keychain.readCloudCredential(keychainRef: account.keychainRef))
    }

    func testCloudProviderRegistryResolvesCapabilitiesAndAdapter() throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .tencentCloud,
            capabilities: [.regions, .instanceDiscovery]
        )
        let registry = CloudProviderRegistry(adapters: [adapter])

        XCTAssertEqual(registry.registeredProviderIds, [.tencentCloud])
        XCTAssertTrue(registry.supports(.regions, providerId: .tencentCloud))
        XCTAssertTrue(registry.supports(.instanceDiscovery, providerId: .tencentCloud))
        XCTAssertFalse(registry.supports(.powerActions, providerId: .tencentCloud))
        XCTAssertNoThrow(try registry.require(.regions, providerId: .tencentCloud))
        XCTAssertThrowsError(try registry.require(.powerActions, providerId: .tencentCloud)) { error in
            XCTAssertEqual(
                error as? CloudProviderError,
                .unsupportedCapability(providerId: .tencentCloud, capability: .powerActions)
            )
        }

        let resolved = try registry.adapter(for: .tencentCloud)
        XCTAssertEqual(resolved.providerId, .tencentCloud)
    }

    func testCloudProviderRegistryThrowsForMissingAdapter() {
        let registry = CloudProviderRegistry()

        XCTAssertThrowsError(try registry.adapter(for: .tencentCloud)) { error in
            XCTAssertEqual(error as? CloudProviderError, .adapterNotRegistered(.tencentCloud))
        }
    }

    func testProviderCapabilityMatrixShowsRegisteredAndMissingAdapters() {
        let registry = CloudProviderRegistry(adapters: [
            MockCloudProviderAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .cloudDisks]
            )
        ])

        let matrix = ProviderCapabilityMatrixBuilder.build(registry: registry)

        XCTAssertEqual(matrix.status(providerId: .tencentCloud, capability: .regions)?.isRegistered, true)
        XCTAssertEqual(matrix.status(providerId: .tencentCloud, capability: .cloudDisks)?.isSupported, true)
        XCTAssertEqual(matrix.status(providerId: .tencentCloud, capability: .cloudSnapshots)?.isSupported, false)
        XCTAssertEqual(matrix.status(providerId: .alibabaCloud, capability: .instanceDiscovery)?.isRegistered, false)
        XCTAssertEqual(matrix.status(providerId: .huaweiCloud, capability: .instanceDiscovery)?.providerName, "Huawei Cloud")
    }

    func testCloudResourceSearchUnifiesFiltersAndSearchesResources() {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let resources = CloudResourceSearchService.unifiedResources(
            instances: [
                CloudInstanceLink(
                    id: UUID(),
                    serverId: nil,
                    accountId: accountId,
                    providerId: .tencentCloud,
                    regionId: "ap-guangzhou",
                    instanceId: "ins-123",
                    displayName: "prod-api",
                    publicIp: "203.0.113.8",
                    privateIp: "10.0.0.8",
                    status: "RUNNING",
                    instanceType: "S5.SMALL1",
                    zoneId: "ap-guangzhou-3",
                    vpcId: "vpc-123",
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                ),
            ],
            securityGroups: [
                CloudSecurityGroup(
                    accountId: accountId,
                    providerId: .tencentCloud,
                    regionId: "ap-guangzhou",
                    securityGroupId: "sg-123",
                    name: "web",
                    description: "public ingress",
                    projectId: nil,
                    isDefault: false,
                    createdTime: nil,
                    updatedTime: nil
                ),
            ],
            disks: [
                CloudDisk(
                    id: UUID(),
                    accountId: accountId,
                    providerId: .tencentCloud,
                    regionId: "ap-guangzhou",
                    diskId: "disk-123",
                    instanceId: "ins-123",
                    name: "prod-data",
                    diskType: "CLOUD_PREMIUM",
                    sizeGB: 100,
                    status: "ATTACHED",
                    billingType: "POSTPAID_BY_HOUR",
                    expiredTime: nil,
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                ),
            ],
            snapshots: [
                CloudSnapshot(
                    id: UUID(),
                    accountId: accountId,
                    providerId: .tencentCloud,
                    regionId: "ap-guangzhou",
                    snapshotId: "snap-123",
                    diskId: "disk-123",
                    name: "prod-before-upgrade",
                    status: "NORMAL",
                    sizeGB: 100,
                    createdAtProvider: capturedAt,
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                ),
            ],
            billingStates: [
                CloudBillingState(
                    id: UUID(),
                    accountId: accountId,
                    providerId: .tencentCloud,
                    resourceType: "disk",
                    resourceId: "disk-123",
                    billingType: "POSTPAID_BY_HOUR",
                    expireAt: nil,
                    status: "ATTACHED",
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                ),
            ]
        )

        XCTAssertEqual(resources.count, 5)
        XCTAssertEqual(
            Set(CloudResourceSearchService.search(resources, query: CloudResourceSearchQuery(text: "prod", kinds: [.instance, .disk, .snapshot])).map(\.kind)),
            Set([.instance, .disk, .snapshot])
        )
        XCTAssertEqual(
            CloudResourceSearchService.search(resources, query: CloudResourceSearchQuery(providerId: .tencentCloud, regionId: "ap-guangzhou", kinds: [.disk], status: "ATTACHED")).map(\.resourceId),
            ["disk-123"]
        )
        XCTAssertTrue(CloudResourceSearchService.search(resources, query: CloudResourceSearchQuery(text: "public ingress")).contains { $0.kind == .securityGroup })
    }

    func testCloudProviderRequestRunnerReturnsBeforeTimeout() async throws {
        let value = try await CloudProviderRequestRunner.withTimeout(0.2) {
            try await Task.sleep(nanoseconds: 1_000_000)
            return "ok"
        }

        XCTAssertEqual(value, "ok")
    }

    func testCloudProviderRequestRunnerTimesOut() async {
        do {
            _ = try await CloudProviderRequestRunner.withTimeout(0.001) {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return "late"
            }
            XCTFail("Expected timeout.")
        } catch {
            XCTAssertEqual(error as? CloudProviderError, .timeout(0.001))
        }
    }

    func testDeploymentCommandBuilderBuildsControlledPlan() throws {
        let project = DeploymentProject(
            id: UUID(),
            serverId: UUID(),
            name: "Website",
            repositoryURL: "git@gitlab.com:hhc/site.git",
            branch: "release/2026.06",
            deployPath: "/srv/site",
            buildCommand: "npm ci && npm run build",
            restartCommand: "systemctl restart site.service",
            healthCheckCommand: "curl -fsS http://127.0.0.1:3000/health",
            webhookEnabled: false,
            webhookSecretRef: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let plan = try DeploymentCommandBuilder.buildPlan(for: project)

        XCTAssertEqual(plan.allowedRoot, "/srv")
        XCTAssertEqual(plan.steps.map(\.name), [
            "prepare",
            "git_check",
            "current_commit",
            "clone_or_fetch",
            "checkout",
            "target_commit",
            "build",
            "restart",
            "health_check",
        ])
        XCTAssertTrue(plan.steps.first { $0.name == "checkout" }?.isDestructive == true)
        XCTAssertTrue(plan.commandPreview.contains("git clone --branch 'release/2026.06'"))
        XCTAssertTrue(plan.commandPreview.contains("git reset --hard 'origin/release/2026.06'"))
        XCTAssertTrue(plan.commandPreview.contains("cd '/srv/site' && npm ci && npm run build"))
    }

    func testDeploymentCommandBuilderRejectsUnsafeConfiguration() {
        var project = DeploymentProject(
            id: UUID(),
            serverId: UUID(),
            name: "Website",
            repositoryURL: "git@gitlab.com:hhc/site.git",
            branch: "main",
            deployPath: "/srv/site",
            buildCommand: nil,
            restartCommand: nil,
            healthCheckCommand: nil,
            webhookEnabled: false,
            webhookSecretRef: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        project.deployPath = "/etc/site"
        XCTAssertThrowsError(try DeploymentCommandBuilder.buildPlan(for: project)) { error in
            XCTAssertEqual(error as? DeploymentCommandBuilderError, .deployPathOutsideAllowedRoots("/etc/site"))
        }

        project.deployPath = "/srv/site"
        project.branch = "../main"
        XCTAssertThrowsError(try DeploymentCommandBuilder.buildPlan(for: project)) { error in
            XCTAssertEqual(error as? DeploymentCommandBuilderError, .invalidBranch)
        }

        project.branch = "main"
        project.repositoryURL = "file:///tmp/repo"
        XCTAssertThrowsError(try DeploymentCommandBuilder.buildPlan(for: project)) { error in
            XCTAssertEqual(error as? DeploymentCommandBuilderError, .invalidRepositoryURL)
        }

        project.repositoryURL = "https://gitlab.com/hhc/site.git"
        project.buildCommand = "npm ci\nrm -rf /"
        XCTAssertThrowsError(try DeploymentCommandBuilder.buildPlan(for: project)) { error in
            XCTAssertEqual(error as? DeploymentCommandBuilderError, .invalidCommand("Build"))
        }
    }

    func testDeploymentRunnerExecutesStepsAndPersistsLogs() async throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "prod",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        let project = makeDeploymentProject(serverId: profile.id)
        try harness.repository.upsertDeploymentProject(project)
        let client = DeploymentRunnerMockSSHClient()
        let runner = DeploymentRunner(
            repository: harness.repository,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let run = try await runner.run(project: project, profile: profile, sshClient: client)

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.previousCommit, "abc123")
        XCTAssertEqual(run.targetCommit, "def456")
        XCTAssertEqual(run.summary, "Deployment completed.")
        XCTAssertTrue(client.commands.contains { $0.contains("git reset --hard 'origin/main'") })

        let persisted = try harness.repository.fetchDeploymentRuns(projectId: project.id)
        XCTAssertEqual(persisted.map(\.status), [.succeeded])
        XCTAssertEqual(persisted[0].previousCommit, "abc123")
        XCTAssertEqual(persisted[0].targetCommit, "def456")

        let logs = try harness.repository.fetchDeploymentLogs(runId: run.id)
        XCTAssertTrue(logs.contains { $0.stepName == "current_commit" && $0.message == "abc123" })
        XCTAssertTrue(logs.contains { $0.stepName == "target_commit" && $0.message == "def456" })
        XCTAssertTrue(logs.contains { $0.stepName == "finish" && $0.message == "Deployment completed." })
    }

    func testDeploymentRunnerStopsOnFailedStep() async throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "prod",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        var project = makeDeploymentProject(serverId: profile.id)
        project.buildCommand = "npm run build"
        try harness.repository.upsertDeploymentProject(project)
        let client = DeploymentRunnerMockSSHClient(failingStep: "build")
        let runner = DeploymentRunner(
            repository: harness.repository,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let run = try await runner.run(project: project, profile: profile, sshClient: client)

        XCTAssertEqual(run.status, .failed)
        XCTAssertEqual(run.summary, "build failed with exit code 1.")
        XCTAssertFalse(client.commands.contains { $0.contains("systemctl restart") })

        let logs = try harness.repository.fetchDeploymentLogs(runId: run.id)
        XCTAssertTrue(logs.contains { $0.stepName == "build" && $0.stream == .stderr && $0.message == "build failed" })
        XCTAssertTrue(logs.contains { $0.stepName == "finish" && $0.message == "build failed with exit code 1." })
    }

    func testDeploymentRunnerPersistsCancellation() async throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "prod",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        let project = makeDeploymentProject(serverId: profile.id)
        try harness.repository.upsertDeploymentProject(project)
        let client = DeploymentRunnerMockSSHClient(cancelledStep: "git_check")
        let runner = DeploymentRunner(
            repository: harness.repository,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let run = try await runner.run(project: project, profile: profile, sshClient: client)

        XCTAssertEqual(run.status, .cancelled)
        XCTAssertEqual(run.summary, SSHClientError.cancelled.localizedDescription)
        XCTAssertFalse(client.commands.contains { $0.contains("git reset --hard") })

        let logs = try harness.repository.fetchDeploymentLogs(runId: run.id)
        XCTAssertTrue(logs.contains { $0.stepName == "git_check" && $0.stream == .stderr })
        XCTAssertTrue(logs.contains { $0.stepName == "finish" && $0.message == SSHClientError.cancelled.localizedDescription })
    }

    func testDeploymentRunnerRedactsSensitiveLogOutput() async throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "prod",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        var project = makeDeploymentProject(serverId: profile.id)
        project.buildCommand = nil
        project.restartCommand = nil
        project.healthCheckCommand = nil
        try harness.repository.upsertDeploymentProject(project)
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "token=abc123 password:super-secret Authorization: Bearer abc.def\n", stderr: "https://user:pass@example.com/repo.git", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "abc123\n", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "def456\n", stderr: "", exitCode: 0, duration: 0.1),
        ])
        let runner = DeploymentRunner(repository: harness.repository)

        let run = try await runner.run(project: project, profile: profile, sshClient: client)

        let combinedLogs = try harness.repository.fetchDeploymentLogs(runId: run.id)
            .map(\.message)
            .joined(separator: "\n")
        XCTAssertTrue(combinedLogs.contains("token=<redacted>"))
        XCTAssertTrue(combinedLogs.contains("password=<redacted>"))
        XCTAssertTrue(combinedLogs.contains("Authorization=<redacted>"))
        XCTAssertTrue(combinedLogs.contains("https://<redacted>@example.com/repo.git"))
        XCTAssertFalse(combinedLogs.contains("abc.def"))
        XCTAssertFalse(combinedLogs.contains("super-secret"))
        XCTAssertFalse(combinedLogs.contains("user:pass"))
    }

    func testDeploymentRunnerRollsBackToPreviousCommit() async throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "prod",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        let project = makeDeploymentProject(serverId: profile.id)
        try harness.repository.upsertDeploymentProject(project)
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "def456\n", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "abc1234\n", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "built\n", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0.1),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0.1),
        ])
        let runner = DeploymentRunner(
            repository: harness.repository,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let run = try await runner.rollback(
            project: project,
            targetCommit: "abc1234",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(run.triggerType, .rollback)
        XCTAssertEqual(run.requestedRef, "abc1234")
        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.previousCommit, "def456")
        XCTAssertEqual(run.targetCommit, "abc1234")
        XCTAssertEqual(run.summary, "Rollback completed.")
        XCTAssertTrue(client.commands.contains { $0.contains("git reset --hard 'abc1234'") })
    }

    func testDeploymentWebhookSecretIsStoredInKeychainReferenceOnly() throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "prod",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        let project = makeDeploymentProject(serverId: profile.id)
        try harness.repository.upsertDeploymentProject(project)

        let enabled = try harness.service.configureDeploymentWebhook(
            project: project,
            enabled: true,
            secret: "gitlab-token"
        )

        XCTAssertTrue(enabled.webhookEnabled)
        XCTAssertEqual(enabled.webhookSecretRef, "deployment_webhook_\(project.id.uuidString)")
        XCTAssertEqual(try harness.keychain.readWebhookSecret(keychainRef: try XCTUnwrap(enabled.webhookSecretRef)), "gitlab-token")

        let stored = try XCTUnwrap(harness.repository.fetchDeploymentProjects(serverId: profile.id).first)
        XCTAssertEqual(stored.webhookSecretRef, enabled.webhookSecretRef)
        XCTAssertNotEqual(stored.webhookSecretRef, "gitlab-token")

        let disabled = try harness.service.configureDeploymentWebhook(project: enabled, enabled: false, secret: nil)
        XCTAssertFalse(disabled.webhookEnabled)
        XCTAssertNil(disabled.webhookSecretRef)
        XCTAssertNil(try harness.keychain.readWebhookSecret(keychainRef: "deployment_webhook_\(project.id.uuidString)"))
    }

    func testDeploymentWebhookServiceFiltersAndTriggersRun() async throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "prod",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        var project = makeDeploymentProject(serverId: profile.id)
        project.repositoryURL = "git@gitlab.com:hhc/site.git"
        project.branch = "main"
        try harness.repository.upsertDeploymentProject(project)
        project = try harness.service.configureDeploymentWebhook(
            project: project,
            enabled: true,
            secret: "gitlab-token"
        )
        let runner = DeploymentRunner(
            repository: harness.repository,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let webhookService = DeploymentWebhookService(
            repository: harness.repository,
            keychain: harness.keychain,
            runner: runner
        )
        let client = DeploymentRunnerMockSSHClient()

        let run = try await webhookService.handleGitLabPush(
            headers: [
                "X-Gitlab-Event": "Push Hook",
                "X-Gitlab-Token": "gitlab-token",
            ],
            body: gitLabPushPayload(branch: "main", sshURL: "git@gitlab.com:hhc/site.git"),
            sshClient: client
        )

        XCTAssertEqual(run.triggerType, .webhook)
        XCTAssertEqual(run.requestedRef, "refs/heads/main")
        XCTAssertEqual(run.status, .succeeded)
        XCTAssertTrue(client.commands.contains { $0.contains("git reset --hard 'origin/main'") })

        let operationLogs = try harness.repository.fetchOperationLogs()
        XCTAssertEqual(operationLogs.map(\.action), ["webhook_trigger", "webhook_trigger"])
        XCTAssertTrue(operationLogs.contains { $0.status == "started" })
        XCTAssertTrue(operationLogs.contains { $0.status == "succeeded" })
        XCTAssertTrue(operationLogs.allSatisfy { $0.targetId == project.id.uuidString })
    }

    func testDeploymentWebhookServiceRejectsInvalidTokenAndBranch() async throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "prod",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        var project = makeDeploymentProject(serverId: profile.id)
        try harness.repository.upsertDeploymentProject(project)
        project = try harness.service.configureDeploymentWebhook(
            project: project,
            enabled: true,
            secret: "gitlab-token"
        )
        let service = DeploymentWebhookService(
            repository: harness.repository,
            keychain: harness.keychain,
            runner: DeploymentRunner(repository: harness.repository)
        )

        XCTAssertFalse(DeploymentWebhookService.constantTimeEquals("gitlab-token", "bad-token"))
        XCTAssertTrue(DeploymentWebhookService.constantTimeEquals("gitlab-token", "gitlab-token"))

        do {
            _ = try await service.handleGitLabPush(
                headers: ["X-Gitlab-Token": "bad-token"],
                body: gitLabPushPayload(branch: "main", sshURL: "git@gitlab.com:hhc/site.git"),
                sshClient: DeploymentRunnerMockSSHClient()
            )
            XCTFail("Expected invalid token.")
        } catch {
            XCTAssertEqual(error as? DeploymentWebhookError, .invalidToken)
        }

        do {
            _ = try await service.handleGitLabPush(
                headers: ["X-Gitlab-Token": "gitlab-token"],
                body: gitLabPushPayload(branch: "develop", sshURL: "git@gitlab.com:hhc/site.git"),
                sshClient: DeploymentRunnerMockSSHClient()
            )
            XCTFail("Expected no matching project.")
        } catch {
            XCTAssertEqual(error as? DeploymentWebhookError, .projectNotFound)
        }
    }

    func testDeploymentWebhookHTTPServerParsesRequestsAndResponses() throws {
        let body = gitLabPushPayload(branch: "main", sshURL: "git@gitlab.com:hhc/site.git")
        let headers = [
            "POST /webhooks/gitlab HTTP/1.1",
            "Host: 127.0.0.1:8787",
            "X-Gitlab-Event: Push Hook",
            "X-Gitlab-Token: gitlab-token",
            "Content-Length: \(body.count)",
            "",
            "",
        ].joined(separator: "\r\n")
        let raw = Data(headers.utf8) + body

        let request = try DeploymentWebhookHTTPServer.parseRequest(raw)

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/webhooks/gitlab")
        XCTAssertEqual(request.headers["X-Gitlab-Token"], "gitlab-token")
        XCTAssertEqual(request.body, body)

        let response = String(
            data: DeploymentWebhookHTTPServer.response(statusCode: 202, reason: "Accepted", body: "ok"),
            encoding: .utf8
        )
        XCTAssertTrue(response?.contains("HTTP/1.1 202 Accepted") == true)
        XCTAssertTrue(response?.contains("Content-Length: 2") == true)
    }

    func testVerdaccioConfigurationBuilderGeneratesPinnedConfigAndService() throws {
        let draft = VerdaccioInstallDraft(
            name: "Team Registry",
            installPath: "/srv/verdaccio",
            dataPath: "/srv/verdaccio/storage",
            listenHost: "127.0.0.1",
            listenPort: 4873,
            serviceName: "verdaccio",
            version: "5.31.1"
        )

        let yaml = try VerdaccioConfigurationBuilder.configurationYAML(for: draft)
        let service = try VerdaccioConfigurationBuilder.systemdService(for: draft)

        XCTAssertTrue(yaml.contains("storage: /srv/verdaccio/storage"))
        XCTAssertTrue(yaml.contains("- 127.0.0.1:4873"))
        XCTAssertTrue(yaml.contains("auth:\n  htpasswd:"))
        XCTAssertTrue(yaml.contains("max_users: -1"))
        XCTAssertTrue(yaml.contains("url: https://registry.npmjs.org/"))
        XCTAssertTrue(yaml.contains("proxy: npmjs"))
        XCTAssertTrue(service.contains("verdaccio@5.31.1"))
        XCTAssertTrue(service.contains("ReadWritePaths=/srv/verdaccio /srv/verdaccio/storage"))
    }

    func testVerdaccioConfigurationBuilderGeneratesCustomUpstreamAndAccessPolicy() throws {
        let yaml = try VerdaccioConfigurationBuilder.configurationYAML(
            for: VerdaccioInstallDraft(),
            policy: VerdaccioConfigPolicy(
                upstreamRegistryURL: "https://registry.npmmirror.com/",
                accessMode: .authenticatedReadAndPublish
            )
        )

        XCTAssertTrue(yaml.contains("url: https://registry.npmmirror.com/"))
        XCTAssertTrue(yaml.contains("access: $authenticated"))
        XCTAssertFalse(yaml.contains("access: $all"))
        XCTAssertTrue(yaml.contains("publish: $authenticated"))
    }

    func testVerdaccioConfigurationBuilderRejectsUnsafeDrafts() {
        var draft = VerdaccioInstallDraft()

        draft.version = "latest"
        XCTAssertThrowsError(try VerdaccioConfigurationBuilder.configurationYAML(for: draft)) { error in
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidVersion)
        }

        draft.version = "5.31.1"
        draft.installPath = "/etc/verdaccio"
        XCTAssertThrowsError(try VerdaccioConfigurationBuilder.configurationYAML(for: draft)) { error in
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidPath("/etc/verdaccio"))
        }

        draft.installPath = "/srv/verdaccio"
        draft.dataPath = "/srv/verdaccio/storage;rm"
        XCTAssertThrowsError(try VerdaccioConfigurationBuilder.configurationYAML(for: draft)) { error in
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidPath("/srv/verdaccio/storage;rm"))
        }

        draft.dataPath = "/srv/verdaccio/storage"
        draft.listenPort = 80
        XCTAssertThrowsError(try VerdaccioConfigurationBuilder.configurationYAML(for: draft)) { error in
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidPort)
        }

        draft.listenPort = 4873
        draft.serviceName = "verdaccio;rm"
        XCTAssertThrowsError(try VerdaccioConfigurationBuilder.configurationYAML(for: draft)) { error in
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidServiceName)
        }
    }

    func testVerdaccioConfigurationBuilderRejectsUnsafeUpstreamRegistryURL() {
        XCTAssertThrowsError(
            try VerdaccioConfigurationBuilder.configurationYAML(
                for: VerdaccioInstallDraft(),
                policy: VerdaccioConfigPolicy(upstreamRegistryURL: "https://user:pass@example.com/")
            )
        ) { error in
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidRegistryURL)
        }

        XCTAssertThrowsError(
            try VerdaccioConfigurationBuilder.configurationYAML(
                for: VerdaccioInstallDraft(),
                policy: VerdaccioConfigPolicy(upstreamRegistryURL: "javascript:alert(1)")
            )
        ) { error in
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidRegistryURL)
        }
    }

    func testVerdaccioConfigurationBuilderGeneratesNginxProxyConfig() throws {
        let proxy = VerdaccioNginxProxyDraft(
            serverName: "registry.example.com",
            configPath: "/www/server/nginx/conf/vhost/verdaccio.conf",
            clientMaxBodySize: "200m"
        )
        let config = try VerdaccioConfigurationBuilder.nginxProxyConfig(
            for: VerdaccioInstallDraft(listenHost: "0.0.0.0", listenPort: 4873),
            proxy: proxy
        )
        let file = try VerdaccioConfigurationBuilder.nginxProxyConfigFile(for: proxy)

        XCTAssertEqual(file.path, "/www/server/nginx/conf/vhost/verdaccio.conf")
        XCTAssertTrue(config.contains("server_name registry.example.com;"))
        XCTAssertTrue(config.contains("client_max_body_size 200m;"))
        XCTAssertTrue(config.contains("proxy_pass http://127.0.0.1:4873;"))
        XCTAssertTrue(config.contains("HTTPS is intentionally not managed here"))
        XCTAssertTrue(config.contains("proxy_set_header X-Forwarded-Proto $scheme;"))
    }

    func testVerdaccioConfigurationBuilderRejectsUnsafeNginxProxyConfig() {
        XCTAssertThrowsError(
            try VerdaccioConfigurationBuilder.nginxProxyConfig(
                for: VerdaccioInstallDraft(),
                proxy: VerdaccioNginxProxyDraft(
                    serverName: "registry.example.com;rm",
                    configPath: "/www/server/nginx/conf/vhost/verdaccio.conf"
                )
            )
        ) { error in
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidProxyServerName)
        }

        XCTAssertThrowsError(
            try VerdaccioConfigurationBuilder.nginxProxyConfig(
                for: VerdaccioInstallDraft(),
                proxy: VerdaccioNginxProxyDraft(
                    serverName: "registry.example.com",
                    configPath: "/tmp/verdaccio.conf"
                )
            )
        )

        XCTAssertThrowsError(
            try VerdaccioConfigurationBuilder.nginxProxyConfig(
                for: VerdaccioInstallDraft(),
                proxy: VerdaccioNginxProxyDraft(
                    serverName: "registry.example.com",
                    configPath: "/www/server/nginx/conf/vhost/verdaccio.conf",
                    clientMaxBodySize: "0m"
                )
            )
        ) { error in
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidProxyBodySize)
        }
    }

    func testPubRegistryResearchHarnessKeepsSelfHostedPubAsResearchOnly() {
        let report = PubRegistryResearchHarness.currentReport(
            evaluatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertFalse(report.shouldImplementSelfHostedInstaller)
        XCTAssertTrue(report.implementationDecision.contains("Do not implement"))
        XCTAssertTrue(report.supportedProductPath.contains("Hosted Pub Repository"))
        XCTAssertEqual(report.evaluatedAt, Date(timeIntervalSince1970: 1_700_000_000))

        let hosted = report.candidates.first { $0.kind == .hostedRepository }
        XCTAssertEqual(hosted?.verdict, .supportedIntegration)
        XCTAssertTrue(hosted?.reasons.joined(separator: " ").contains("official toolchain") == true)

        let selfHosted = report.candidates.filter { $0.kind == .selfHostedServer }
        XCTAssertFalse(selfHosted.isEmpty)
        XCTAssertTrue(selfHosted.allSatisfy { $0.verdict == .researchOnly })

        let git = report.candidates.first { $0.kind == .privateGitDependency }
        XCTAssertEqual(git?.verdict, .notARegistry)
    }

    func testVerdaccioUserCommandsUseHtpasswdWithoutPlaintextPassword() {
        let draft = VerdaccioInstallDraft()
        let command = VerdaccioManager.upsertUserCommand(
            draft: draft,
            username: "team.dev",
            password: "Correct-Horse-Secret-123",
            backupPath: "/srv/verdaccio/htpasswd.hhc-backup-20260625190000",
            requireExistingUser: false
        )

        XCTAssertTrue(command.contains("command -v htpasswd"))
        XCTAssertTrue(command.contains("htpasswd -B -i"))
        XCTAssertTrue(command.contains("systemctl restart \"$service\""))
        XCTAssertTrue(command.contains("__HHC_VERDACCIO_HTPASSWD_BACKUP__"))
        XCTAssertFalse(command.contains("Correct-Horse-Secret-123"))

        let deleteCommand = VerdaccioManager.deleteUserCommand(
            draft: draft,
            username: "team.dev",
            backupPath: "/srv/verdaccio/htpasswd.hhc-backup-20260625190000"
        )

        XCTAssertTrue(deleteCommand.contains("htpasswd -D"))
        XCTAssertTrue(deleteCommand.contains("cp -p -- \"$htpasswd_file\" \"$backup\""))
        XCTAssertTrue(deleteCommand.contains("systemctl restart \"$service\""))
    }

    func testVerdaccioNpmSmokeTestCommandPublishesInstallsAndHidesPassword() {
        let command = VerdaccioManager.npmSmokeTestCommand(
            packageName: "@hhc-smoke/pkg-test",
            version: "0.0.1",
            registryURL: "http://127.0.0.1:4873",
            username: "team.dev",
            password: "Correct-Horse-Secret-123",
            email: "team@example.com"
        )

        XCTAssertTrue(command.contains("npm adduser --registry \"$registry_url\" --auth-type=legacy"))
        XCTAssertTrue(command.contains("npm publish --registry \"$registry_url\" --access public"))
        XCTAssertTrue(command.contains("npm install \"$package_name@$package_version\" --registry \"$registry_url\""))
        XCTAssertTrue(command.contains("npm unpublish \"$package_name@$package_version\" --registry \"$registry_url\" --force"))
        XCTAssertTrue(command.contains("__HHC_VERDACCIO_NPM_REQUIRE__"))
        XCTAssertFalse(command.contains("Correct-Horse-Secret-123"))
    }

    func testVerdaccioServiceActionAndUpgradeCommandsAreControlled() throws {
        let draft = VerdaccioInstallDraft(version: "5.31.2")
        let restartCommand = VerdaccioManager.serviceActionCommand(.restart, for: draft)
        let upgradeCommand = try VerdaccioManager.upgradeCommand(
            for: draft,
            backupPath: "/srv/verdaccio/backups/verdaccio.service.hhc-backup-2026"
        )

        XCTAssertTrue(restartCommand.contains("systemctl restart \"$service\""))
        XCTAssertTrue(restartCommand.contains("systemctl show \"$service\""))
        XCTAssertFalse(restartCommand.contains(";rm"))
        XCTAssertTrue(upgradeCommand.contains("cp -p -- \"$service_path\" \"$backup_path\""))
        XCTAssertTrue(upgradeCommand.contains("__HHC_VERDACCIO_SERVICE_UPGRADE__"))
        XCTAssertTrue(try VerdaccioConfigurationBuilder.systemdService(for: draft).contains("verdaccio@5.31.2"))
        XCTAssertTrue(upgradeCommand.contains("systemctl daemon-reload"))
        XCTAssertTrue(upgradeCommand.contains("systemctl restart \"$service\""))
    }

    func testVerdaccioManagerCreatesUpdatesAndDeletesUsersWithBackups() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "__HHC_VERDACCIO_HTPASSWD_BACKUP__/srv/verdaccio/htpasswd.hhc-backup\n", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: "__HHC_VERDACCIO_HTPASSWD_BACKUP__/srv/verdaccio/htpasswd.hhc-backup\n", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: "__HHC_VERDACCIO_HTPASSWD_BACKUP__/srv/verdaccio/htpasswd.hhc-backup\n", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_719_318_000) })

        let created = try await manager.createUser(
            draft: VerdaccioInstallDraft(),
            username: "team.dev",
            password: "Correct-Horse-Secret-123",
            profile: profile,
            sshClient: client
        )
        let updated = try await manager.updateUserPassword(
            draft: VerdaccioInstallDraft(),
            username: "team.dev",
            password: "Correct-Horse-Secret-456",
            profile: profile,
            sshClient: client
        )
        let deleted = try await manager.deleteUser(
            draft: VerdaccioInstallDraft(),
            username: "team.dev",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(created.action, .create)
        XCTAssertEqual(updated.action, .updatePassword)
        XCTAssertEqual(deleted.action, .delete)
        XCTAssertEqual(created.htpasswdPath, "/srv/verdaccio/htpasswd")
        XCTAssertTrue(created.backupPath.contains("htpasswd.hhc-backup-2024-"))
        XCTAssertTrue(client.commands[0].contains("htpasswd -B -i"))
        XCTAssertTrue(client.commands[1].contains("'update'"))
        XCTAssertTrue(client.commands[2].contains("htpasswd -D"))
        XCTAssertFalse(client.commands.joined(separator: "\n").contains("Correct-Horse-Secret"))
    }

    func testVerdaccioManagerRejectsUnsafeUserInputsBeforeSSH() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let manager = VerdaccioManager()

        do {
            _ = try await manager.createUser(
                draft: VerdaccioInstallDraft(),
                username: "team:dev",
                password: "Correct-Horse-Secret-123",
                profile: profile,
                sshClient: client
            )
            XCTFail("Expected invalid username to be rejected.")
        } catch {
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidRegistryUsername)
        }

        do {
            _ = try await manager.updateUserPassword(
                draft: VerdaccioInstallDraft(),
                username: "team.dev",
                password: "short",
                profile: profile,
                sshClient: client
            )
            XCTFail("Expected invalid password to be rejected.")
        } catch {
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidRegistryPassword)
        }

        XCTAssertTrue(client.commands.isEmpty)
    }

    func testVerdaccioManagerControlsServiceAndUpgradesWithHealthCheck() async throws {
        let profile = makeServiceTestProfile()
        let logs = Data("Verdaccio restarted\n".utf8).base64EncodedString()
        let status = CommandResult(
            command: "",
            stdout: """
            __HHC_VERDACCIO_ACTIVE_STATE__active
            __HHC_VERDACCIO_SUB_STATE__running
            __HHC_VERDACCIO_VERSION__5.31.2
            __HHC_VERDACCIO_STORAGE_BYTES__2048
            __HHC_VERDACCIO_LOGS__\(logs)
            """,
            stderr: "",
            exitCode: 0,
            duration: 0
        )
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "ActiveState=active\nSubState=running\n", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: #"{"ok":"verdaccio"}"#, stderr: "", exitCode: 0, duration: 0),
            status,
            CommandResult(command: "", stdout: "__HHC_VERDACCIO_SERVICE_BACKUP__/srv/verdaccio/backups/verdaccio.service.hhc-backup-2026\n", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: #"{"ok":"verdaccio"}"#, stderr: "", exitCode: 0, duration: 0),
            status,
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let restarted = try await manager.performServiceAction(
            .restart,
            draft: VerdaccioInstallDraft(version: "5.31.2"),
            profile: profile,
            sshClient: client
        )
        let upgraded = try await manager.upgrade(
            draft: VerdaccioInstallDraft(version: "5.31.2"),
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(restarted.action, .restart)
        XCTAssertEqual(restarted.healthCheckOutput, #"{"ok":"verdaccio"}"#)
        XCTAssertTrue(restarted.snapshot.isRunning)
        XCTAssertEqual(upgraded.version, "5.31.2")
        XCTAssertTrue(upgraded.backupPath.contains("/srv/verdaccio/backups/verdaccio.service.hhc-backup-"))
        XCTAssertEqual(upgraded.healthCheckOutput, #"{"ok":"verdaccio"}"#)
        XCTAssertTrue(client.commands.contains { $0.contains("systemctl restart \"$service\"") })
        XCTAssertTrue(client.commands.contains { $0.contains("__HHC_VERDACCIO_SERVICE_UPGRADE__") })
        XCTAssertTrue(client.commands.contains { $0.contains("curl -fsS --max-time 5 'http://127.0.0.1:4873/-/ping'") })
    }

    func testVerdaccioManagerRunsNpmSmokeTestAndRejectsInvalidEmail() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(
                command: "",
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
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await manager.runNpmSmokeTest(
            draft: VerdaccioInstallDraft(),
            username: "team.dev",
            password: "Correct-Horse-Secret-123",
            email: "team@example.com",
            profile: profile,
            sshClient: client
        )

        XCTAssertTrue(result.packageName.hasPrefix("@hhc-smoke/pkg-"))
        XCTAssertEqual(result.version, "0.0.1")
        XCTAssertEqual(result.registryURL, "http://127.0.0.1:4873")
        XCTAssertEqual(result.requireOutput, "hhc-verdaccio-smoke-ok")
        XCTAssertTrue(client.commands[0].contains("npm publish"))
        XCTAssertFalse(client.commands[0].contains("Correct-Horse-Secret-123"))

        do {
            _ = try await manager.runNpmSmokeTest(
                draft: VerdaccioInstallDraft(),
                username: "team.dev",
                password: "Correct-Horse-Secret-123",
                email: "not-an-email",
                profile: profile,
                sshClient: client
            )
            XCTFail("Expected invalid email to be rejected.")
        } catch {
            XCTAssertEqual(error as? RegistryConfigurationError, .invalidRegistryEmail)
        }
    }

    func testRegistryPreflightCheckerParsesReadyReport() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(
                command: "",
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
            ),
        ])
        let checker = RegistryPreflightChecker(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let report = try await checker.run(draft: VerdaccioInstallDraft(), profile: profile, sshClient: client)

        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.checks.map(\.status), [.passed, .passed, .passed, .passed, .passed, .passed, .passed])
        XCTAssertTrue(client.commands[0].contains("node --version"))
        XCTAssertTrue(client.commands[0].contains("command -v htpasswd"))
        XCTAssertTrue(client.commands[0].contains("port=4873"))
        XCTAssertEqual(report.capturedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testRegistryPreflightCheckerFlagsMissingDependenciesAndBusyPort() {
        let report = RegistryPreflightChecker.parseReport("""
        __HHC_REGISTRY_NODE_VERSION__
        __HHC_REGISTRY_PACKAGE_MANAGER__
        __HHC_REGISTRY_HTPASSWD__no
        __HHC_REGISTRY_SYSTEMD__no
        __HHC_REGISTRY_PORT_BUSY__yes
        __HHC_REGISTRY_INSTALL_PARENT_WRITABLE__no
        __HHC_REGISTRY_DATA_PARENT_WRITABLE__yes
        __HHC_REGISTRY_DISK_AVAILABLE_KB__128000
        """)

        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.checks.first { $0.id == "node" }?.status, .failed)
        XCTAssertEqual(report.checks.first { $0.id == "package_manager" }?.status, .failed)
        XCTAssertEqual(report.checks.first { $0.id == "htpasswd" }?.status, .warning)
        XCTAssertEqual(report.checks.first { $0.id == "systemd" }?.status, .failed)
        XCTAssertEqual(report.checks.first { $0.id == "port" }?.status, .failed)
        XCTAssertEqual(report.checks.first { $0.id == "paths" }?.status, .failed)
        XCTAssertEqual(report.checks.first { $0.id == "disk" }?.status, .warning)
    }

    func testVerdaccioInstallerBuildsSafeInstallCommand() throws {
        let command = try VerdaccioInstaller.installCommand(for: VerdaccioInstallDraft())

        XCTAssertTrue(command.contains("useradd --system --home-dir \"$install_path\""))
        XCTAssertTrue(command.contains("install -d -m 0755 -o \"$service_name\" -g \"$service_name\" \"$install_path\" \"$data_path\""))
        XCTAssertTrue(command.contains("base64 -d > \"$install_path/config.yaml\""))
        XCTAssertTrue(command.contains("base64 -d > '/etc/systemd/system/verdaccio.service'"))
        XCTAssertTrue(command.contains("systemctl daemon-reload"))
        XCTAssertTrue(command.contains("systemctl enable --now 'verdaccio.service'"))
        XCTAssertTrue(command.contains("systemctl restart 'verdaccio.service'"))
        XCTAssertFalse(command.contains("latest"))
    }

    func testVerdaccioInstallerInstallsAndRunsHealthCheck() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: #"{"ok":"verdaccio"}"#, stderr: "", exitCode: 0, duration: 0),
        ])
        let installer = VerdaccioInstaller()

        let result = try await installer.install(
            draft: VerdaccioInstallDraft(listenHost: "0.0.0.0"),
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(result.configPath, "/srv/verdaccio/config.yaml")
        XCTAssertEqual(result.servicePath, "/etc/systemd/system/verdaccio.service")
        XCTAssertEqual(result.healthCheckURL, "http://127.0.0.1:4873/-/ping")
        XCTAssertEqual(result.healthCheckOutput, #"{"ok":"verdaccio"}"#)
        XCTAssertEqual(client.commands.count, 2)
        XCTAssertTrue(client.commands[0].contains("systemctl restart 'verdaccio.service'"))
        XCTAssertEqual(client.commands[1], "curl -fsS --max-time 5 'http://127.0.0.1:4873/-/ping'")
    }

    func testVerdaccioInstallerStopsWhenInstallCommandFails() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "token=secret-value", stderr: "install failed", exitCode: 1, duration: 0),
        ])
        let installer = VerdaccioInstaller()

        do {
            _ = try await installer.install(draft: VerdaccioInstallDraft(), profile: profile, sshClient: client)
            XCTFail("Expected install failure.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("install failed"))
            XCTAssertFalse(error.localizedDescription.contains("secret-value"))
            XCTAssertEqual(client.commands.count, 1)
        }
    }

    func testVerdaccioInstallerFailsWhenHealthCheckFails() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: "", stderr: "connection refused", exitCode: 7, duration: 0),
        ])
        let installer = VerdaccioInstaller()

        do {
            _ = try await installer.install(draft: VerdaccioInstallDraft(), profile: profile, sshClient: client)
            XCTFail("Expected health check failure.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("connection refused"))
            XCTAssertEqual(client.commands.count, 2)
        }
    }

    func testVerdaccioManagerParsesStatusAndRedactsLogs() async throws {
        let profile = makeServiceTestProfile()
        let logs = Data("started token=secret-value\nready\n".utf8).base64EncodedString()
        let client = RecordingSSHClient(responses: [
            CommandResult(
                command: "",
                stdout: """
                __HHC_VERDACCIO_ACTIVE_STATE__active
                __HHC_VERDACCIO_SUB_STATE__running
                __HHC_VERDACCIO_VERSION__5.31.1
                __HHC_VERDACCIO_STORAGE_BYTES__4096
                __HHC_VERDACCIO_LOGS__\(logs)
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            ),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let snapshot = try await manager.loadStatus(
            draft: VerdaccioInstallDraft(),
            profile: profile,
            sshClient: client
        )

        XCTAssertTrue(snapshot.isRunning)
        XCTAssertEqual(snapshot.version, "5.31.1")
        XCTAssertEqual(snapshot.storageBytes, 4096)
        XCTAssertTrue(snapshot.recentLogs.contains("token=<redacted>"))
        XCTAssertFalse(snapshot.recentLogs.contains("secret-value"))
        XCTAssertTrue(client.commands[0].contains("systemctl show \"$service\" --property=ActiveState"))
        XCTAssertTrue(client.commands[0].contains("journalctl -u \"$service\""))
    }

    func testVerdaccioManagerReadsConfigAsUTF8() async throws {
        let profile = makeServiceTestProfile()
        let config = "storage: /srv/verdaccio/storage\n"
        let client = RecordingSSHClient(responses: [
            CommandResult(
                command: "",
                stdout: Data(config.utf8).base64EncodedString(),
                stderr: "",
                exitCode: 0,
                duration: 0
            ),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let file = try await manager.readConfig(
            draft: VerdaccioInstallDraft(),
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(file.path, "/srv/verdaccio/config.yaml")
        XCTAssertEqual(file.content, config)
        XCTAssertTrue(client.commands[0].contains("base64 < \"$path\""))
    }

    func testVerdaccioManagerSavesConfigWithBackupAndRestart() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await manager.saveConfig(
            draft: VerdaccioInstallDraft(),
            content: "storage: /srv/verdaccio/storage\n",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(result.path, "/srv/verdaccio/config.yaml")
        XCTAssertTrue(result.backupPath.hasPrefix("/srv/verdaccio/config.yaml.hhc-backup-"))
        XCTAssertTrue(client.commands[0].contains("cp -p -- \"$path\" \"$backup\""))
        XCTAssertTrue(client.commands[0].contains("base64 -d > \"$tmp\""))
        XCTAssertTrue(client.commands[0].contains("systemctl restart \"$service\""))
    }

    func testVerdaccioManagerSavesGeneratedConfigPolicyWithBackupAndRestart() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await manager.saveGeneratedConfig(
            draft: VerdaccioInstallDraft(),
            policy: VerdaccioConfigPolicy(
                upstreamRegistryURL: "https://registry.npmmirror.com/",
                accessMode: .authenticatedReadAndPublish
            ),
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(result.path, "/srv/verdaccio/config.yaml")
        XCTAssertTrue(result.backupPath.hasPrefix("/srv/verdaccio/config.yaml.hhc-backup-"))
        XCTAssertTrue(client.commands[0].contains("cp -p -- \"$path\" \"$backup\""))
        let expectedConfig = try VerdaccioConfigurationBuilder.configurationYAML(
            for: VerdaccioInstallDraft(),
            policy: VerdaccioConfigPolicy(
                upstreamRegistryURL: "https://registry.npmmirror.com/",
                accessMode: .authenticatedReadAndPublish
            )
        )
        XCTAssertTrue(client.commands[0].contains(Data(expectedConfig.utf8).base64EncodedString()))
        XCTAssertTrue(client.commands[0].contains("systemctl restart \"$service\""))
    }

    func testVerdaccioManagerRejectsOversizedConfigBeforeSSH() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let manager = VerdaccioManager()

        do {
            _ = try await manager.saveConfig(
                draft: VerdaccioInstallDraft(),
                content: String(repeating: "a", count: VerdaccioManager.maxConfigBytes + 1),
                profile: profile,
                sshClient: client
            )
            XCTFail("Expected oversized config failure.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("larger than the 256 KiB"))
            XCTAssertTrue(client.commands.isEmpty)
        }
    }

    func testVerdaccioManagerParsesPackageList() {
        let packages = VerdaccioManager.parsePackageList("""
        @team/ui\t2\t1.1.0\t2048\t1700000002
        api-client\t3\t2.0.0\t4096\t1700000001
        malformed
        """)

        XCTAssertEqual(packages.map(\.name), ["@team/ui", "api-client"])
        XCTAssertEqual(packages[0].versionCount, 2)
        XCTAssertEqual(packages[0].latestVersion, "1.1.0")
        XCTAssertEqual(packages[0].sizeBytes, 2048)
        XCTAssertEqual(packages[0].modifiedAt, Date(timeIntervalSince1970: 1_700_000_002))
    }

    func testVerdaccioManagerListsPackagesFromStorage() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(
                command: "",
                stdout: """
                api-client\t1\t1.0.0\t1024\t1700000000
                @team/ui\t2\t1.1.0\t2048\t1700000002
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            ),
        ])
        let manager = VerdaccioManager()

        let packages = try await manager.listPackages(
            draft: VerdaccioInstallDraft(),
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(packages.map(\.name), ["@team/ui", "api-client"])
        XCTAssertTrue(client.commands[0].contains("find \"$data_path\" -mindepth 1 -maxdepth 3 -type f -name package.json"))
        XCTAssertTrue(client.commands[0].contains("printf '%s\\t%s\\t%s\\t%s\\t%s\\n'"))
    }

    func testVerdaccioManagerCreatesRegistryBackupArchive() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "8192\n", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await manager.createBackup(
            draft: VerdaccioInstallDraft(),
            profile: profile,
            sshClient: client
        )

        XCTAssertTrue(result.backupPath.hasPrefix("/srv/verdaccio/backups/verdaccio-"))
        XCTAssertTrue(result.backupPath.hasSuffix(".tar.gz"))
        XCTAssertEqual(result.sizeBytes, 8192)
        XCTAssertTrue(client.commands[0].contains("install -d -m 0750 \"$backup_dir\""))
        XCTAssertTrue(client.commands[0].contains("data_parent=$(dirname -- \"$data_path\"); data_name=$(basename -- \"$data_path\")"))
        XCTAssertTrue(client.commands[0].contains("tar -czf \"$backup_path\" -C \"$install_path\" config.yaml -C \"$data_parent\" \"$data_name\""))
        XCTAssertTrue(client.commands[0].contains("stat -c %s \"$backup_path\""))
    }

    func testVerdaccioManagerRecordsBackupHistoryWhenRepositoryProvided() async throws {
        let profile = makeServiceTestProfile()
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        try repository.upsert(profile)
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "8192\n", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await manager.createBackup(
            draft: VerdaccioInstallDraft(),
            profile: profile,
            sshClient: client,
            repository: repository
        )

        let registries = try repository.fetchRegistryInstances(serverId: profile.id)
        XCTAssertEqual(registries.count, 1)
        XCTAssertEqual(registries[0].kind, .verdaccio)
        XCTAssertEqual(registries[0].installPath, "/srv/verdaccio")
        XCTAssertEqual(registries[0].status, "active")

        let backups = try repository.fetchRegistryBackups(registryId: registries[0].id)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups[0].backupPath, result.backupPath)
        XCTAssertEqual(backups[0].status, .created)
        XCTAssertEqual(backups[0].sizeBytes, 8192)
        XCTAssertEqual(result.historyRecord?.id, backups[0].id)
    }

    func testVerdaccioManagerRestoresBackupAndChecksHealth() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: #"{"ok":"verdaccio"}"#, stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await manager.restoreBackup(
            draft: VerdaccioInstallDraft(),
            backupPath: "/srv/verdaccio/backups/verdaccio-2026-06-25T12-00-00.000Z.tar.gz",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(result.backupPath, "/srv/verdaccio/backups/verdaccio-2026-06-25T12-00-00.000Z.tar.gz")
        XCTAssertTrue(result.rollbackBackupPath.hasPrefix("/srv/verdaccio/backups/restore-rollback-"))
        XCTAssertEqual(result.healthCheckURL, "http://127.0.0.1:4873/-/ping")
        XCTAssertEqual(result.healthCheckOutput, #"{"ok":"verdaccio"}"#)
        XCTAssertEqual(client.commands.count, 2)
        XCTAssertTrue(client.commands[0].contains("systemctl stop \"$service\""))
        XCTAssertTrue(client.commands[0].contains("tar -czf \"$rollback_path\" -C \"$install_path\" config.yaml -C \"$data_parent\" \"$data_name\""))
        XCTAssertTrue(client.commands[0].contains("tar -xzf \"$archive_path\" -C \"$restore_dir\""))
        XCTAssertTrue(client.commands[0].contains("test -f \"$restore_dir/config.yaml\""))
        XCTAssertTrue(client.commands[0].contains("test -d \"$restore_dir/$data_name\""))
        XCTAssertTrue(client.commands[0].contains("systemctl start \"$service\""))
        XCTAssertEqual(client.commands[1], "curl -fsS --max-time 5 'http://127.0.0.1:4873/-/ping'")
    }

    func testVerdaccioManagerRecordsRestoreHistoryWhenRepositoryProvided() async throws {
        let profile = makeServiceTestProfile()
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        try repository.upsert(profile)
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: "ok", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await manager.restoreBackup(
            draft: VerdaccioInstallDraft(),
            backupPath: "/srv/verdaccio/backups/verdaccio-2026-06-25T12-00-00.000Z.tar.gz",
            profile: profile,
            sshClient: client,
            repository: repository
        )

        let registry = try XCTUnwrap(repository.fetchRegistryInstances(serverId: profile.id).first)
        let backups = try repository.fetchRegistryBackups(registryId: registry.id)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups[0].status, .restored)
        XCTAssertEqual(backups[0].backupPath, result.backupPath)
        XCTAssertEqual(backups[0].restoredAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(result.historyRecord?.id, backups[0].id)
    }

    func testVerdaccioManagerRollsBackWhenRestoreHealthCheckFails() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: "token=secret-value", stderr: "connection refused", exitCode: 7, duration: 0),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        do {
            _ = try await manager.restoreBackup(
                draft: VerdaccioInstallDraft(),
                backupPath: "/srv/verdaccio/backups/verdaccio-2026-06-25T12-00-00.000Z.tar.gz",
                profile: profile,
                sshClient: client
            )
            XCTFail("Expected restore health check failure.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("connection refused"))
            XCTAssertTrue(error.localizedDescription.contains("Rollback attempted using /srv/verdaccio/backups/restore-rollback-"))
            XCTAssertFalse(error.localizedDescription.contains("secret-value"))
            XCTAssertEqual(client.commands.count, 3)
            XCTAssertTrue(client.commands[2].contains("archive_path='/srv/verdaccio/backups/restore-rollback-"))
            XCTAssertFalse(client.commands[2].contains("rollback_path="))
            XCTAssertTrue(client.commands[2].contains("tar -xzf \"$archive_path\" -C \"$restore_dir\""))
        }
    }

    func testVerdaccioManagerRecordsRestoreFailureHistoryWhenRepositoryProvided() async throws {
        let profile = makeServiceTestProfile()
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        try repository.upsert(profile)
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: "token=secret-value", stderr: "connection refused", exitCode: 7, duration: 0),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        do {
            _ = try await manager.restoreBackup(
                draft: VerdaccioInstallDraft(),
                backupPath: "/srv/verdaccio/backups/verdaccio-2026-06-25T12-00-00.000Z.tar.gz",
                profile: profile,
                sshClient: client,
                repository: repository
            )
            XCTFail("Expected restore health check failure.")
        } catch {
            let registry = try XCTUnwrap(repository.fetchRegistryInstances(serverId: profile.id).first)
            let backups = try repository.fetchRegistryBackups(registryId: registry.id)
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(backups[0].status, .restoreFailed)
            XCTAssertEqual(backups[0].backupPath, "/srv/verdaccio/backups/verdaccio-2026-06-25T12-00-00.000Z.tar.gz")
            XCTAssertTrue(try XCTUnwrap(backups[0].message).contains("connection refused"))
            XCTAssertFalse(try XCTUnwrap(backups[0].message).contains("secret-value"))
        }
    }

    func testVerdaccioManagerRollsBackWhenRestoreCommandFails() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "token=secret-value", stderr: "tar failed", exitCode: 2, duration: 0),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        do {
            _ = try await manager.restoreBackup(
                draft: VerdaccioInstallDraft(),
                backupPath: "/srv/verdaccio/backups/verdaccio-2026-06-25T12-00-00.000Z.tar.gz",
                profile: profile,
                sshClient: client
            )
            XCTFail("Expected restore command failure.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("tar failed"))
            XCTAssertTrue(error.localizedDescription.contains("Rollback attempted using /srv/verdaccio/backups/restore-rollback-"))
            XCTAssertFalse(error.localizedDescription.contains("secret-value"))
            XCTAssertEqual(client.commands.count, 2)
            XCTAssertTrue(client.commands[1].contains("archive_path='/srv/verdaccio/backups/restore-rollback-"))
            XCTAssertFalse(client.commands[1].contains("rollback_path="))
        }
    }

    func testVerdaccioManagerRejectsUnsafeRestoreBackupPathBeforeSSH() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let manager = VerdaccioManager()

        do {
            _ = try await manager.restoreBackup(
                draft: VerdaccioInstallDraft(),
                backupPath: "/tmp/verdaccio.tar.gz",
                profile: profile,
                sshClient: client
            )
            XCTFail("Expected unsafe backup path failure.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("must be under"))
            XCTAssertTrue(client.commands.isEmpty)
        }
    }

    func testDashboardServiceParsesLinuxCapabilityAndMetricOutputs() {
        let os = DashboardService.parseOSRelease("""
        NAME="Ubuntu"
        VERSION_ID="24.04"
        PRETTY_NAME="Ubuntu 24.04.2 LTS"
        """)
        XCTAssertEqual(os.name, "Ubuntu 24.04.2 LTS")
        XCTAssertEqual(os.version, "24.04")
        XCTAssertTrue(DashboardService.parseYesNo("yes\n"))
        XCTAssertEqual(DashboardService.parseLoadAverage("0.10 0.20 0.30 1/100 12345"), "0.10 / 0.20 / 0.30")
        XCTAssertEqual(DashboardService.parseCPUCount("4\n"), "4")
        XCTAssertEqual(DashboardService.parseProcessSummary("total=120 running=2 sleeping=117 stopped=0 zombie=1\n"), "120 / 2 / 1")
        XCTAssertEqual(DashboardService.parseNetworkTotals("""
            Inter-|   Receive                                                |  Transmit
             face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
                lo: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0
              eth0: 1048576 0 0 0 0 0 0 0 2097152 0 0 0 0 0 0 0
        """), "1.0 MiB / 2.0 MiB")

        let memory = DashboardService.parseMemoryUsage("""
        MemTotal:        2048000 kB
        MemAvailable:    1024000 kB
        """)
        XCTAssertEqual(memory, "1000 MiB / 2.0 GiB")

        let disk = DashboardService.parseRootDiskUsage("/dev/vda1 20971520 10485760 10485760 50% /")
        XCTAssertEqual(disk, "10.0 GiB / 20.0 GiB")
    }

    func testSystemdServiceManagerParsesUnitListAndValidatesUnitNames() throws {
        let units = SystemdServiceManager.parseUnitList("""
        nginx.service\tloaded\tactive\trunning\tA high performance web server
        ssh.service\tloaded\tactive\trunning\tOpenBSD Secure Shell server
        apt-daily.service\tloaded\tinactive\tdead\tDaily apt download activities
        """)

        XCTAssertEqual(units.map(\.name), ["nginx.service", "ssh.service", "apt-daily.service"])
        XCTAssertTrue(units[0].isRunning)
        XCTAssertEqual(units[2].description, "Daily apt download activities")
        XCTAssertEqual(try SystemdServiceManager.validatedUnitName("nginx.service"), "nginx.service")
        XCTAssertEqual(try SystemdServiceManager.validatedUnitName("foo@bar.service"), "foo@bar.service")
        XCTAssertThrowsError(try SystemdServiceManager.validatedUnitName("nginx.service; reboot"))
        XCTAssertThrowsError(try SystemdServiceManager.validatedUnitName("nginx.socket"))
    }

    func testSystemdServiceManagerListsActsAndReadsJournal() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSystemdSSHClient()
        let manager = SystemdServiceManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let list = try await manager.listUnits(profile: profile, sshClient: client)
        XCTAssertEqual(list.units.map(\.name), ["nginx.service", "ssh.service"])

        try await manager.perform(.restart, unitName: "nginx.service", profile: profile, sshClient: client)
        XCTAssertTrue(client.commands.contains("systemctl restart -- 'nginx.service'"))

        let log = try await manager.readJournal(unitName: "nginx.service", limit: 42, profile: profile, sshClient: client)
        XCTAssertEqual(log.unitName, "nginx.service")
        XCTAssertTrue(log.text.contains("Started nginx.service"))
        XCTAssertTrue(client.commands.contains("journalctl -u 'nginx.service' -n 42 --no-pager --output=short-iso"))
    }

    func testCronManagerParsesValidatesAndMutatesCrontab() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingCronSSHClient()
        let manager = CronManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let parsed = CronManager.parse("""
        # comment
        0 2 * * * /usr/bin/backup
        # HHC_DISABLED */5 * * * * /usr/bin/ping
        """)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].schedule, "0 2 * * *")
        XCTAssertTrue(parsed[0].isEnabled)
        XCTAssertFalse(parsed[1].isEnabled)
        XCTAssertEqual(try CronManager.makeEntryLine(schedule: "*/10 * * * *", command: "/usr/bin/echo ok"), "*/10 * * * * /usr/bin/echo ok")
        XCTAssertThrowsError(try CronManager.makeEntryLine(schedule: "* * * *", command: "bad"))
        XCTAssertThrowsError(try CronManager.makeEntryLine(schedule: "* * * * *", command: "bad\nline"))

        var snapshot = try await manager.load(profile: profile, sshClient: client)
        XCTAssertEqual(snapshot.entries.map(\.command), ["/usr/bin/backup"])

        try await manager.add(schedule: "*/5 * * * *", command: "/usr/bin/health", profile: profile, sshClient: client)
        XCTAssertTrue(client.installedCrontab.contains("*/5 * * * * /usr/bin/health"))
        XCTAssertTrue(client.commands.contains { $0.contains(".hhc-crontab-backup-") })

        snapshot = try await manager.load(profile: profile, sshClient: client)
        let health = try XCTUnwrap(snapshot.entries.first { $0.command == "/usr/bin/health" })
        try await manager.perform(.disable, entry: health, profile: profile, sshClient: client)
        XCTAssertTrue(client.installedCrontab.contains("# HHC_DISABLED */5 * * * * /usr/bin/health"))

        snapshot = try await manager.load(profile: profile, sshClient: client)
        let disabledHealth = try XCTUnwrap(snapshot.entries.first { $0.command == "/usr/bin/health" })
        try await manager.perform(.enable, entry: disabledHealth, profile: profile, sshClient: client)
        XCTAssertTrue(client.installedCrontab.contains("*/5 * * * * /usr/bin/health"))
        XCTAssertFalse(client.installedCrontab.contains("# HHC_DISABLED */5 * * * * /usr/bin/health"))

        snapshot = try await manager.load(profile: profile, sshClient: client)
        let enabledHealth = try XCTUnwrap(snapshot.entries.first { $0.command == "/usr/bin/health" })
        try await manager.perform(.delete, entry: enabledHealth, profile: profile, sshClient: client)
        XCTAssertFalse(client.installedCrontab.contains("/usr/bin/health"))
    }

    func testNginxConfigManagerListsReadsTestsAndReloads() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingNginxSSHClient()
        let manager = NginxConfigManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let parsed = NginxConfigManager.parseConfigListing("""
        /etc/nginx/nginx.conf\t320\t1700000000.5
        /tmp/not-nginx.conf\t12\t1700000000.5
        /www/server/nginx/conf/vhost/site.conf\t120\t1700000001.0
        """)
        XCTAssertEqual(parsed.map(\.path), ["/etc/nginx/nginx.conf", "/www/server/nginx/conf/vhost/site.conf"])
        XCTAssertEqual(parsed[0].size, 320)
        XCTAssertEqual(try NginxConfigManager.validatedConfigPath("/etc/nginx/nginx.conf"), "/etc/nginx/nginx.conf")
        XCTAssertEqual(try NginxConfigManager.validatedConfigPath("/www/server/nginx/conf/nginx.conf"), "/www/server/nginx/conf/nginx.conf")
        XCTAssertThrowsError(try NginxConfigManager.validatedConfigPath("/etc/passwd"))
        XCTAssertThrowsError(try NginxConfigManager.validatedConfigPath("/etc/nginx/../passwd"))

        let list = try await manager.listConfigs(profile: profile, sshClient: client)
        XCTAssertEqual(list.files.map(\.path), ["/www/server/nginx/conf/nginx.conf", "/www/server/nginx/conf/vhost/site.conf"])
        XCTAssertTrue(client.commands.contains { $0.contains("nginx -V") })

        let content = try await manager.readConfig(file: list.files[0], profile: profile, sshClient: client)
        XCTAssertEqual(content.content, "user www-data;\n")
        XCTAssertTrue(client.commands.contains { $0.contains("base64 < '/www/server/nginx/conf/nginx.conf'") })

        let test = try await manager.testConfig(profile: profile, sshClient: client)
        XCTAssertTrue(test.succeeded)
        XCTAssertTrue(test.output.contains("syntax is ok"))

        _ = try await manager.reload(profile: profile, sshClient: client)
        XCTAssertTrue(client.commands.contains("nginx -t"))
        XCTAssertTrue(client.commands.contains("systemctl reload nginx 2>/dev/null || nginx -s reload"))

        let saved = try await manager.saveConfig(
            file: list.files[0],
            content: "user nginx;\n",
            profile: profile,
            sshClient: client
        )
        XCTAssertFalse(saved.rolledBack)
        XCTAssertTrue(saved.testResult.succeeded)
        XCTAssertTrue(saved.backupPath.contains(".hhc-backup-"))
        XCTAssertEqual(client.configs["/www/server/nginx/conf/nginx.conf"], "user nginx;\n")
        XCTAssertTrue(client.commands.contains { $0.contains("cp -p -- \"$path\" \"$backup\"") })

        client.testSucceeds = false
        let rolledBack = try await manager.saveConfig(
            file: list.files[0],
            content: "broken;",
            profile: profile,
            sshClient: client
        )
        XCTAssertTrue(rolledBack.rolledBack)
        XCTAssertFalse(rolledBack.testResult.succeeded)
        XCTAssertEqual(client.configs["/www/server/nginx/conf/nginx.conf"], "user nginx;\n")
    }

    func testNginxConfigManagerUpsertsVerdaccioProxyConfigAndReloads() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingNginxSSHClient()
        let manager = NginxConfigManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let proxy = VerdaccioNginxProxyDraft(
            serverName: "registry.example.com",
            configPath: "/www/server/nginx/conf/vhost/verdaccio.conf"
        )
        let content = try VerdaccioConfigurationBuilder.nginxProxyConfig(
            for: VerdaccioInstallDraft(),
            proxy: proxy
        )

        let upserted = try await manager.upsertConfig(
            path: proxy.configPath,
            content: content,
            profile: profile,
            sshClient: client
        )
        _ = try await manager.reload(profile: profile, sshClient: client)

        XCTAssertTrue(upserted.createdNewFile)
        XCTAssertFalse(upserted.rolledBack)
        XCTAssertNil(upserted.backupPath)
        XCTAssertEqual(client.configs[proxy.configPath], content)
        XCTAssertTrue(client.commands.contains { $0.contains("install -d -m 0755 \"$parent\"") })
        XCTAssertTrue(client.commands.contains("nginx -t"))
        XCTAssertTrue(client.commands.contains("systemctl reload nginx 2>/dev/null || nginx -s reload"))

        client.testSucceeds = false
        let rolledBack = try await manager.upsertConfig(
            path: "/www/server/nginx/conf/vhost/broken-verdaccio.conf",
            content: "server {",
            profile: profile,
            sshClient: client
        )
        XCTAssertTrue(rolledBack.createdNewFile)
        XCTAssertTrue(rolledBack.rolledBack)
        XCTAssertNil(client.configs["/www/server/nginx/conf/vhost/broken-verdaccio.conf"])
    }

    func testFirewallManagerParsesAndLoadsSupportedBackends() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let parsed = try FirewallManager.parseSnapshot("""
        __HHC_FIREWALL_BACKEND__
        ufw
        __HHC_FIREWALL_STATUS__
        Status: active
        __HHC_FIREWALL_RULES__
        Status: active
        22/tcp ALLOW Anywhere
        """, capturedAt: capturedAt)
        XCTAssertEqual(parsed.backend, .ufw)
        XCTAssertEqual(parsed.status, "Status: active")
        XCTAssertTrue(parsed.rulesText.contains("22/tcp"))

        let profile = makeServiceTestProfile()
        let client = RecordingFirewallSSHClient()
        let manager = FirewallManager(now: { capturedAt })

        var snapshot = try await manager.loadSnapshot(profile: profile, sshClient: client)
        XCTAssertEqual(snapshot.backend, .firewalld)
        XCTAssertEqual(snapshot.status, "running")
        XCTAssertTrue(snapshot.rulesText.contains("public"))
        XCTAssertTrue(client.commands[0].contains("firewall-cmd --list-all-zones 2>&1 || true"))

        client.firewalldRunning = false
        snapshot = try await manager.loadSnapshot(profile: profile, sshClient: client)
        XCTAssertEqual(snapshot.backend, .firewalld)
        XCTAssertEqual(snapshot.status, "not running")
        XCTAssertTrue(snapshot.rulesText.contains("FirewallD is not running"))

        client.backend = .nft
        snapshot = try await manager.loadSnapshot(profile: profile, sshClient: client)
        XCTAssertEqual(snapshot.backend, .nft)
        XCTAssertTrue(snapshot.rulesText.contains("table inet filter"))

        XCTAssertThrowsError(try FirewallManager.parseSnapshot("bad", capturedAt: capturedAt))
    }

    func testFirewallManagerBuildsAndAppliesLimitedRuleCommands() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingFirewallSSHClient()
        let manager = FirewallManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let draft = FirewallRuleDraft(
            mutation: .add,
            direction: .ingress,
            action: .allow,
            proto: .tcp,
            port: 443,
            cidr: "203.0.113.0/24"
        )

        XCTAssertEqual(
            try FirewallManager.command(for: draft, backend: .ufw),
            "ufw allow in proto tcp from '203.0.113.0/24' to any port 443"
        )
        XCTAssertEqual(
            try FirewallManager.command(for: draft, backend: .iptables),
            "iptables -A INPUT -p tcp -s '203.0.113.0/24' --dport 443 -j ACCEPT"
        )
        XCTAssertTrue(try FirewallManager.command(for: draft, backend: .firewalld).contains("--add-rich-rule='rule family=\"ipv4\""))
        XCTAssertThrowsError(try FirewallManager.command(for: draft, backend: .nft))
        XCTAssertThrowsError(try FirewallManager.command(for: FirewallRuleDraft(
            mutation: .add,
            direction: .ingress,
            action: .allow,
            proto: .tcp,
            port: 70_000,
            cidr: "203.0.113.0/24"
        ), backend: .ufw))

        let snapshot = try await manager.loadSnapshot(profile: profile, sshClient: client)
        let result = try await manager.applyRule(draft, snapshot: snapshot, profile: profile, sshClient: client)

        XCTAssertEqual(result.command, try FirewallManager.command(for: draft, backend: .firewalld))
        XCTAssertEqual(result.beforeSnapshot.backend, .firewalld)
        XCTAssertEqual(result.afterSnapshot.backend, .firewalld)
        XCTAssertTrue(client.commands.contains(where: { $0.contains("firewall-cmd --permanent --add-rich-rule") }))
    }

    func testEnvironmentFileManagerListsReadsAndSavesWithBackup() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingEnvironmentSSHClient()
        let manager = EnvironmentFileManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let parsed = EnvironmentFileManager.parseFileListing("""
        /var/www/app/.env\t30\t1700000000.5\tapp
        /etc/default/nginx\t20\t1700000001.0\tos
        /tmp/secret\t12\t1700000002.0\tbad
        /etc/systemd/system/api.service.d/env.conf\t42\t1700000003.0\tsystemd
        """)
        XCTAssertEqual(parsed.map(\.path), [
            "/etc/default/nginx",
            "/etc/systemd/system/api.service.d/env.conf",
            "/var/www/app/.env",
        ])
        XCTAssertEqual(parsed[0].source, "os")
        XCTAssertEqual(try EnvironmentFileManager.validatedEnvironmentPath("/var/www/app/.env"), "/var/www/app/.env")
        XCTAssertEqual(try EnvironmentFileManager.validatedEnvironmentPath("/etc/default/nginx"), "/etc/default/nginx")
        XCTAssertThrowsError(try EnvironmentFileManager.validatedEnvironmentPath("/etc/passwd"))
        XCTAssertThrowsError(try EnvironmentFileManager.validatedEnvironmentPath("/tmp/secret.env"))
        XCTAssertThrowsError(try EnvironmentFileManager.validatedEnvironmentPath("/var/www/../app/.env"))

        let list = try await manager.listFiles(profile: profile, sshClient: client)
        XCTAssertEqual(list.files.map(\.path), ["/etc/default/nginx", "/var/www/app/.env"])
        XCTAssertTrue(client.commands[0].contains("find /var/www"))

        let content = try await manager.readFile(file: list.files[1], profile: profile, sshClient: client)
        XCTAssertEqual(content.content, "APP_ENV=prod\n")
        XCTAssertTrue(client.commands.contains { $0.contains("base64 < '/var/www/app/.env'") })

        let saved = try await manager.saveFile(
            file: list.files[1],
            content: "APP_ENV=staging\n",
            profile: profile,
            sshClient: client
        )
        XCTAssertEqual(client.files["/var/www/app/.env"], "APP_ENV=staging\n")
        XCTAssertTrue(saved.backupPath.contains(".hhc-backup-"))
        XCTAssertTrue(client.commands.contains { $0.contains("__HHC_ENV_FILE_EOF__") })
    }

    func testDashboardServiceAppendsCloudMetricsWhenLinked() async throws {
        let harness = try Harness(adapters: [
            MockCloudProviderAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudMetrics]
            )
        ])
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let profile = try harness.service.createServer(
            name: "prod",
            host: "203.0.113.1",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        try harness.repository.upsertCloudInstanceLink(CloudInstanceLink(
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
        let registry = CloudProviderRegistry(adapters: [
            MockCloudProviderAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudMetrics]
            )
        ])
        let cloudMetricService = CloudMetricService(
            repository: harness.repository,
            keychain: harness.keychain,
            registry: registry,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let dashboardService = DashboardService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let snapshot = try await dashboardService.loadSnapshot(
            profile: profile,
            sshClient: DashboardServiceMockSSHClient(),
            cloudMetricService: cloudMetricService
        )

        XCTAssertTrue(snapshot.metrics.contains(DashboardMetric(name: "Cloud CPU", value: "21.2", unit: "%", source: "Cloud API")))
        XCTAssertTrue(snapshot.metrics.contains { $0.source == "SSH" })
    }

    func testRemoteFileServiceParsesFindListingAndPaths() {
        let entries = RemoteFileService.parseFindListing("""
        z.log\tf\t2048\t1700000010.5\t-rw-r--r--
        bin\td\t4096\t1700000000.0\tdrwxr-xr-x
        current\tl\t12\t1700000020.0\tlrwxrwxrwx
        """, basePath: "/var/www")

        XCTAssertEqual(entries.map(\.name), ["bin", "current", "z.log"])
        XCTAssertEqual(entries[0].kind, .directory)
        XCTAssertEqual(entries[0].path, "/var/www/bin")
        XCTAssertEqual(entries[1].kind, .symlink)
        XCTAssertEqual(entries[1].size, 12)
        XCTAssertEqual(entries[2].modifiedAt, Date(timeIntervalSince1970: 1_700_000_010.5))
        XCTAssertEqual(RemoteFileService.normalizedDirectoryPath(" /tmp/ "), "/tmp")
        XCTAssertEqual(RemoteFileService.parentPath(for: "/var/www"), "/var")
        XCTAssertEqual(RemoteFileService.parentPath(for: "/"), "/")
        XCTAssertEqual(RemoteFileService.parentPath(for: "~/app.env"), "~")
        XCTAssertEqual(RemoteFileService.parentPath(for: "~/sites/app.env"), "~/sites")
        XCTAssertEqual(RemoteFileService.normalizedFilePath("copy.env"), "~/copy.env")
        XCTAssertEqual(RemoteFileService.normalizedFilePath("/var/www/copy.env"), "/var/www/copy.env")
    }

    func testRemoteFileServiceRenamesAndMovesToTrashWithSafeCommands() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let entry = RemoteFileEntry(
            name: "index.html",
            path: "/var/www/index.html",
            kind: .file,
            size: 10,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        try await service.rename(entry: entry, to: "home.html", profile: profile, sshClient: client)
        let trashPath = try await service.moveToTrash(entry: entry, profile: profile, sshClient: client)

        XCTAssertEqual(client.commands.count, 2)
        XCTAssertEqual(client.commands[0], "mv -n -- '/var/www/index.html' '/var/www/home.html'")
        XCTAssertTrue(client.commands[1].contains("mkdir -p -- '~/.hhc-server-manager-trash' && mv -n -- '/var/www/index.html' '~/.hhc-server-manager-trash/"))
        XCTAssertTrue(trashPath.hasPrefix("~/.hhc-server-manager-trash/"))
        XCTAssertTrue(trashPath.hasSuffix("-index.html"))
    }

    func testRemoteFileServiceRejectsUnsafeRenameTargets() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService()
        let entry = RemoteFileEntry(
            name: "index.html",
            path: "/var/www/index.html",
            kind: .file,
            size: 10,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        do {
            try await service.rename(entry: entry, to: "../bad", profile: profile, sshClient: client)
            XCTFail("Expected invalid rename target.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "File name cannot be empty, '.', '..', or contain '/'.")
            XCTAssertTrue(client.commands.isEmpty)
        }
    }

    func testRemoteFileServiceReadsAndSavesSmallUTF8TextWithBackup() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(
                command: "",
                stdout: Data("hello\n".utf8).base64EncodedString(),
                stderr: "",
                exitCode: 0,
                duration: 0
            ),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
        ])
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let entry = RemoteFileEntry(
            name: "app.env",
            path: "/var/www/app.env",
            kind: .file,
            size: 6,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        let textFile = try await service.readTextFile(entry: entry, profile: profile, sshClient: client)
        let saveResult = try await service.saveTextFile(
            path: entry.path,
            content: "updated\n",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(textFile.content, "hello\n")
        XCTAssertEqual(textFile.byteCount, 6)
        XCTAssertEqual(saveResult.path, "/var/www/app.env")
        XCTAssertTrue(saveResult.backupPath?.hasPrefix("/var/www/app.env.hhc-backup-") == true)
        XCTAssertEqual(client.commands.count, 2)
        XCTAssertTrue(client.commands[0].contains("base64 < '/var/www/app.env'"))
        XCTAssertTrue(client.commands[1].contains("base64 -d > \"$tmp\""))
        XCTAssertTrue(client.commands[1].contains("cp -p -- '/var/www/app.env' \"$backup\""))
        XCTAssertTrue(client.commands[1].contains("mv -- \"$tmp\" '/var/www/app.env'"))
    }

    func testRemoteFileServiceSavesTextAsNewRemotePathWithoutBackup() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await service.saveTextFileAs(
            sourcePath: "/var/www/app.env",
            targetPath: "/var/www/app.env.copy",
            content: "copy\n",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(result.path, "/var/www/app.env.copy")
        XCTAssertNil(result.backupPath)
        XCTAssertEqual(client.commands.count, 1)
        XCTAssertTrue(client.commands[0].contains("test ! -e \"$target\""))
        XCTAssertTrue(client.commands[0].contains("mv -- \"$tmp\" \"$target\""))
    }

    func testRemoteFileServiceChangesPermissionsWithValidatedOctalMode() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService()
        let entry = RemoteFileEntry(
            name: "app.env",
            path: "/var/www/app.env",
            kind: .file,
            size: 6,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        try await service.changePermissions(entry: entry, mode: " 640 ", profile: profile, sshClient: client)

        XCTAssertEqual(client.commands, ["chmod -- '640' '/var/www/app.env'"])
    }

    func testRemoteFileServiceRejectsInvalidPermissionModesBeforeSSH() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService()
        let entry = RemoteFileEntry(
            name: "app.env",
            path: "/var/www/app.env",
            kind: .file,
            size: 6,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        do {
            try await service.changePermissions(entry: entry, mode: "88x", profile: profile, sshClient: client)
            XCTFail("Expected invalid mode to be rejected.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Permissions must be a 3 or 4 digit octal mode, for example 644 or 0755.")
            XCTAssertTrue(client.commands.isEmpty)
        }
    }

    func testRemoteFileServiceRejectsOversizedKnownTextFileBeforeSSHRead() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService()
        let entry = RemoteFileEntry(
            name: "large.log",
            path: "/var/www/large.log",
            kind: .file,
            size: Int64(RemoteFileService.maxEditableTextBytes + 1),
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        do {
            _ = try await service.readTextFile(entry: entry, profile: profile, sshClient: client)
            XCTFail("Expected large text read to be rejected.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "File is larger than the 256 KiB text editing limit.")
            XCTAssertTrue(client.commands.isEmpty)
        }
    }

    func testRemoteFileServiceUploadsAndDownloadsThroughTransferClient() async throws {
        let profile = makeServiceTestProfile()
        let transferClient = RecordingTransferClient()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let localUploadURL = URL(fileURLWithPath: "/tmp/app.env")
        let localDownloadURL = URL(fileURLWithPath: "/tmp/downloaded.env")
        let entry = RemoteFileEntry(
            name: "app.env",
            path: "/var/www/app.env",
            kind: .file,
            size: 6,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        let upload = try await service.uploadFile(
            localURL: localUploadURL,
            toDirectoryPath: "/var/www",
            profile: profile,
            transferClient: transferClient
        )
        let download = try await service.downloadFile(
            entry: entry,
            to: localDownloadURL,
            profile: profile,
            transferClient: transferClient
        )

        XCTAssertEqual(upload.remotePath, "/var/www/app.env")
        XCTAssertEqual(download.localPath, "/tmp/downloaded.env")
        XCTAssertEqual(transferClient.uploads.map(\.remotePath), ["/var/www/app.env"])
        XCTAssertEqual(transferClient.downloads.map(\.remotePath), ["/var/www/app.env"])
    }

    func testCloudInstanceSyncUpsertsInstancesAndPreservesServerLink() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .tencentCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata]
        )
        let harness = try Harness(adapters: [adapter], now: { Date(timeIntervalSince1970: 1_700_000_100) })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let server = try harness.service.createServer(
            name: "Linked",
            host: "203.0.113.1",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        try harness.repository.upsertCloudInstanceLink(CloudInstanceLink(
            id: UUID(),
            serverId: server.id,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-123",
            displayName: "old-name",
            publicIp: "198.51.100.10",
            privateIp: nil,
            status: "STOPPED",
            instanceType: nil,
            zoneId: nil,
            vpcId: nil,
            rawJSON: nil,
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let links = try await harness.cloudInstanceSyncService.syncInstances(
            account: account,
            regionId: "ap-guangzhou"
        )

        XCTAssertEqual(links.count, 1)
        let persisted = try XCTUnwrap(try harness.repository.fetchCloudInstanceLinks(accountId: account.id).first)
        XCTAssertEqual(persisted.serverId, server.id)
        XCTAssertEqual(persisted.displayName, "mock-instance")
        XCTAssertEqual(persisted.publicIp, "203.0.113.1")
        XCTAssertEqual(persisted.status, "RUNNING")
        XCTAssertEqual(persisted.lastSyncedAt, Date(timeIntervalSince1970: 1_700_000_100))
    }

    func testCloudAdvancedResourceSyncPersistsAndSearchesResources() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .tencentCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudDisks, .cloudSnapshots, .cloudBilling]
        )
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let harness = try Harness(adapters: [adapter], now: { syncedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )

        _ = try await harness.cloudInstanceSyncService.syncInstances(account: account, regionId: "ap-guangzhou")
        let disks = try await harness.cloudInstanceSyncService.syncDisks(account: account, regionId: "ap-guangzhou")
        let snapshots = try await harness.cloudInstanceSyncService.syncSnapshots(account: account, regionId: "ap-guangzhou")
        let billingStates = try await harness.cloudInstanceSyncService.syncBillingStates(account: account, regionId: "ap-guangzhou")

        XCTAssertEqual(disks.map(\.diskId), ["disk-123"])
        XCTAssertEqual(snapshots.map(\.snapshotId), ["snap-123"])
        XCTAssertEqual(billingStates.map(\.resourceId), ["ins-123"])
        XCTAssertEqual(try harness.repository.fetchCloudDisks(accountId: account.id).first?.lastSyncedAt, syncedAt)
        XCTAssertEqual(try harness.repository.fetchCloudSnapshots(accountId: account.id).first?.lastSyncedAt, syncedAt)
        XCTAssertEqual(try harness.repository.fetchCloudBillingStates(accountId: account.id).first?.lastSyncedAt, syncedAt)

        let searchResults = try harness.cloudInstanceSyncService.loadUnifiedCloudResources(
            accountId: account.id,
            regionId: "ap-guangzhou",
            query: CloudResourceSearchQuery(text: "disk", kinds: [.disk, .snapshot, .billing])
        )

        XCTAssertEqual(Set(searchResults.map(\.kind)), [.disk, .snapshot])
        XCTAssertEqual(Set(searchResults.map(\.resourceId)), ["disk-123", "snap-123"])
    }

    func testCloudSnapshotActionsPersistCacheAndAuditLogs() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .tencentCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudSnapshots, .snapshotActions]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_300)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )

        let snapshot = try await harness.cloudInstanceSyncService.createSnapshot(
            account: account,
            regionId: "ap-guangzhou",
            diskId: "disk-123",
            snapshotName: "before-upgrade"
        )

        XCTAssertEqual(snapshot.snapshotId, "snap-created")
        XCTAssertEqual(try harness.repository.fetchCloudSnapshots(accountId: account.id).map(\.snapshotId), ["snap-created"])
        var logs = try harness.repository.fetchRemoteChangeLogs()
        let createLog = try XCTUnwrap(logs.first { $0.action == "create_snapshot" })
        XCTAssertEqual(createLog.providerId, .tencentCloud)
        XCTAssertEqual(createLog.status, "success")

        try await harness.cloudInstanceSyncService.deleteSnapshot(
            account: account,
            regionId: "ap-guangzhou",
            snapshotId: snapshot.snapshotId,
            currentStatus: "NORMAL"
        )

        XCTAssertTrue(try harness.repository.fetchCloudSnapshots(accountId: account.id).isEmpty)
        logs = try harness.repository.fetchRemoteChangeLogs()
        let deleteLog = try XCTUnwrap(logs.first { $0.action == "delete_snapshot" })
        XCTAssertEqual(deleteLog.targetId, "snap-created")
        XCTAssertEqual(deleteLog.status, "success")
    }

    func testCloudSnapshotDeleteAllowsAlibabaCompletedStatus() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .alibabaCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudSnapshots, .snapshotActions]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_350)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .alibabaCloud,
            displayName: "Alibaba",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        try harness.repository.upsertCloudSnapshot(
            CloudSnapshot(
                id: UUID(),
                accountId: account.id,
                providerId: .alibabaCloud,
                regionId: "ap-southeast-1",
                snapshotId: "snap-created",
                diskId: "disk-123",
                name: "before-upgrade",
                status: "accomplished",
                sizeGB: 50,
                createdAtProvider: capturedAt,
                rawJSON: nil,
                lastSyncedAt: capturedAt
            )
        )

        try await harness.cloudInstanceSyncService.deleteSnapshot(
            account: account,
            regionId: "ap-southeast-1",
            snapshotId: "snap-created",
            currentStatus: "accomplished"
        )

        XCTAssertTrue(try harness.repository.fetchCloudSnapshots(accountId: account.id).isEmpty)
        let logs = try harness.repository.fetchRemoteChangeLogs()
        let deleteLog = try XCTUnwrap(logs.first { $0.action == "delete_snapshot" })
        XCTAssertEqual(deleteLog.providerId, .alibabaCloud)
        XCTAssertEqual(deleteLog.targetId, "snap-created")
        XCTAssertEqual(deleteLog.status, "success")
    }

    func testCloudSnapshotDeleteAllowsHuaweiAvailableStatus() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .huaweiCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudSnapshots, .snapshotActions]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_360)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .huaweiCloud,
            displayName: "Huawei",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        try harness.repository.upsertCloudSnapshot(
            CloudSnapshot(
                id: UUID(),
                accountId: account.id,
                providerId: .huaweiCloud,
                regionId: "ap-southeast-1|project-1",
                snapshotId: "snap-created",
                diskId: "vol-1",
                name: "before-upgrade",
                status: "available",
                sizeGB: 50,
                createdAtProvider: capturedAt,
                rawJSON: nil,
                lastSyncedAt: capturedAt
            )
        )

        try await harness.cloudInstanceSyncService.deleteSnapshot(
            account: account,
            regionId: "ap-southeast-1|project-1",
            snapshotId: "snap-created",
            currentStatus: "available"
        )

        XCTAssertTrue(try harness.repository.fetchCloudSnapshots(accountId: account.id).isEmpty)
        let logs = try harness.repository.fetchRemoteChangeLogs()
        let deleteLog = try XCTUnwrap(logs.first { $0.action == "delete_snapshot" })
        XCTAssertEqual(deleteLog.providerId, .huaweiCloud)
        XCTAssertEqual(deleteLog.targetId, "snap-created")
        XCTAssertEqual(deleteLog.status, "success")
    }

    func testCloudDiskAttachmentActionsPersistCacheAndAuditLogs() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .tencentCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudDisks, .diskAttachmentActions]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_400)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        try harness.repository.upsertCloudDisk(CloudDisk(
            id: UUID(),
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            diskId: "disk-attach",
            instanceId: nil,
            name: "data",
            diskType: "CLOUD_PREMIUM",
            sizeGB: 100,
            status: "UNATTACHED",
            billingType: "POSTPAID_BY_HOUR",
            expiredTime: nil,
            rawJSON: nil,
            lastSyncedAt: nil
        ))

        try await harness.cloudInstanceSyncService.attachDisk(
            account: account,
            regionId: "ap-guangzhou",
            diskId: "disk-attach",
            instanceId: "ins-target",
            currentStatus: "UNATTACHED"
        )

        var disk = try XCTUnwrap(harness.repository.fetchCloudDisks(accountId: account.id).first { $0.diskId == "disk-attach" })
        XCTAssertEqual(disk.instanceId, "ins-target")
        XCTAssertEqual(disk.status, "ATTACHING")
        var logs = try harness.repository.fetchRemoteChangeLogs()
        let attachLog = try XCTUnwrap(logs.first { $0.action == "attach_disk" })
        XCTAssertEqual(attachLog.targetId, "disk-attach")
        XCTAssertEqual(attachLog.status, "success")

        disk.status = "ATTACHED"
        try harness.repository.upsertCloudDisk(disk)
        try await harness.cloudInstanceSyncService.detachDisk(
            account: account,
            regionId: "ap-guangzhou",
            diskId: "disk-attach",
            currentInstanceId: "ins-target",
            currentStatus: "ATTACHED"
        )

        let detachingDisk = try XCTUnwrap(harness.repository.fetchCloudDisks(accountId: account.id).first { $0.diskId == "disk-attach" })
        XCTAssertEqual(detachingDisk.instanceId, "ins-target")
        XCTAssertEqual(detachingDisk.status, "DETACHING")
        logs = try harness.repository.fetchRemoteChangeLogs()
        let detachLog = try XCTUnwrap(logs.first { $0.action == "detach_disk" })
        XCTAssertEqual(detachLog.targetId, "disk-attach")
        XCTAssertEqual(detachLog.status, "success")
    }

    func testCloudDiskAttachmentActionsAllowAlibabaStatuses() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .alibabaCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudDisks, .diskAttachmentActions]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_450)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .alibabaCloud,
            displayName: "Alibaba",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        try harness.repository.upsertCloudDisk(CloudDisk(
            id: UUID(),
            accountId: account.id,
            providerId: .alibabaCloud,
            regionId: "ap-southeast-1",
            diskId: "d-attach",
            instanceId: nil,
            name: "data",
            diskType: "cloud_essd",
            sizeGB: 100,
            status: "Available",
            billingType: "PostPaid",
            expiredTime: nil,
            rawJSON: nil,
            lastSyncedAt: nil
        ))

        try await harness.cloudInstanceSyncService.attachDisk(
            account: account,
            regionId: "ap-southeast-1",
            diskId: "d-attach",
            instanceId: "i-target",
            currentStatus: "Available"
        )

        var disk = try XCTUnwrap(harness.repository.fetchCloudDisks(accountId: account.id).first { $0.diskId == "d-attach" })
        XCTAssertEqual(disk.instanceId, "i-target")
        XCTAssertEqual(disk.status, "ATTACHING")
        var logs = try harness.repository.fetchRemoteChangeLogs()
        let attachLog = try XCTUnwrap(logs.first { $0.action == "attach_disk" })
        XCTAssertEqual(attachLog.providerId, .alibabaCloud)
        XCTAssertEqual(attachLog.targetId, "d-attach")
        XCTAssertEqual(attachLog.status, "success")

        disk.status = "In_use"
        try harness.repository.upsertCloudDisk(disk)
        try await harness.cloudInstanceSyncService.detachDisk(
            account: account,
            regionId: "ap-southeast-1",
            diskId: "d-attach",
            currentInstanceId: "i-target",
            currentStatus: "In_use"
        )

        let detachingDisk = try XCTUnwrap(harness.repository.fetchCloudDisks(accountId: account.id).first { $0.diskId == "d-attach" })
        XCTAssertEqual(detachingDisk.instanceId, "i-target")
        XCTAssertEqual(detachingDisk.status, "DETACHING")
        logs = try harness.repository.fetchRemoteChangeLogs()
        let detachLog = try XCTUnwrap(logs.first { $0.action == "detach_disk" })
        XCTAssertEqual(detachLog.providerId, .alibabaCloud)
        XCTAssertEqual(detachLog.targetId, "d-attach")
        XCTAssertEqual(detachLog.status, "success")
    }

    func testCloudDiskAttachmentActionsAllowHuaweiStatuses() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .huaweiCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudDisks, .diskAttachmentActions]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_470)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .huaweiCloud,
            displayName: "Huawei",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        try harness.repository.upsertCloudDisk(CloudDisk(
            id: UUID(),
            accountId: account.id,
            providerId: .huaweiCloud,
            regionId: "ap-southeast-1|project-1",
            diskId: "vol-attach",
            instanceId: nil,
            name: "data",
            diskType: "SSD",
            sizeGB: 100,
            status: "available",
            billingType: "postPaid",
            expiredTime: nil,
            rawJSON: nil,
            lastSyncedAt: nil
        ))

        try await harness.cloudInstanceSyncService.attachDisk(
            account: account,
            regionId: "ap-southeast-1|project-1",
            diskId: "vol-attach",
            instanceId: "server-target",
            currentStatus: "available"
        )

        var disk = try XCTUnwrap(harness.repository.fetchCloudDisks(accountId: account.id).first { $0.diskId == "vol-attach" })
        XCTAssertEqual(disk.instanceId, "server-target")
        XCTAssertEqual(disk.status, "ATTACHING")
        var logs = try harness.repository.fetchRemoteChangeLogs()
        let attachLog = try XCTUnwrap(logs.first { $0.action == "attach_disk" })
        XCTAssertEqual(attachLog.providerId, .huaweiCloud)
        XCTAssertEqual(attachLog.targetId, "vol-attach")
        XCTAssertEqual(attachLog.status, "success")

        disk.status = "in-use"
        try harness.repository.upsertCloudDisk(disk)
        try await harness.cloudInstanceSyncService.detachDisk(
            account: account,
            regionId: "ap-southeast-1|project-1",
            diskId: "vol-attach",
            currentInstanceId: "server-target",
            currentStatus: "in-use"
        )

        let detachingDisk = try XCTUnwrap(harness.repository.fetchCloudDisks(accountId: account.id).first { $0.diskId == "vol-attach" })
        XCTAssertEqual(detachingDisk.instanceId, "server-target")
        XCTAssertEqual(detachingDisk.status, "DETACHING")
        logs = try harness.repository.fetchRemoteChangeLogs()
        let detachLog = try XCTUnwrap(logs.first { $0.action == "detach_disk" })
        XCTAssertEqual(detachLog.providerId, .huaweiCloud)
        XCTAssertEqual(detachLog.targetId, "vol-attach")
        XCTAssertEqual(detachLog.status, "success")
    }

    func testCloudInstancePowerActionsPersistCacheAndAuditLogs() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .tencentCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .powerActions]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        var link = CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-power",
            displayName: "prod",
            publicIp: "203.0.113.2",
            privateIp: "10.0.0.9",
            status: "STOPPED",
            instanceType: "S5.SMALL1",
            zoneId: "ap-guangzhou-3",
            vpcId: "vpc-1",
            rawJSON: nil,
            lastSyncedAt: nil
        )
        try harness.repository.upsertCloudInstanceLink(link)

        try await harness.cloudInstanceSyncService.startInstance(
            account: account,
            regionId: "ap-guangzhou",
            instanceId: "ins-power",
            currentStatus: "STOPPED"
        )

        var storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-guangzhou",
            instanceId: "ins-power"
        )
        XCTAssertEqual(storedLink.status, "STARTING")
        XCTAssertEqual(storedLink.lastSyncedAt, capturedAt)
        var logs = try harness.repository.fetchRemoteChangeLogs()
        XCTAssertEqual(logs.first { $0.action == "start_instance" }?.status, "success")

        link.status = "RUNNING"
        try harness.repository.upsertCloudInstanceLink(link)
        try await harness.cloudInstanceSyncService.rebootInstance(
            account: account,
            regionId: "ap-guangzhou",
            instanceId: "ins-power",
            currentStatus: "RUNNING"
        )
        storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-guangzhou",
            instanceId: "ins-power"
        )
        XCTAssertEqual(storedLink.status, "REBOOTING")

        link.status = "RUNNING"
        try harness.repository.upsertCloudInstanceLink(link)
        try await harness.cloudInstanceSyncService.stopInstance(
            account: account,
            regionId: "ap-guangzhou",
            instanceId: "ins-power",
            currentStatus: "RUNNING"
        )
        storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-guangzhou",
            instanceId: "ins-power"
        )
        XCTAssertEqual(storedLink.status, "STOPPING")
        logs = try harness.repository.fetchRemoteChangeLogs()
        XCTAssertEqual(logs.first { $0.action == "reboot_instance" }?.status, "success")
        XCTAssertEqual(logs.first { $0.action == "stop_instance" }?.status, "success")
    }

    func testCloudInstancePowerActionsAllowAlibabaStatuses() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .alibabaCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .powerActions]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_520)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .alibabaCloud,
            displayName: "Alibaba",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        var link = CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: account.id,
            providerId: .alibabaCloud,
            regionId: "ap-southeast-1",
            instanceId: "i-power",
            displayName: "prod",
            publicIp: "203.0.113.12",
            privateIp: "10.0.0.12",
            status: "Stopped",
            instanceType: "ecs.g7.large",
            zoneId: "ap-southeast-1a",
            vpcId: "vpc-1",
            rawJSON: nil,
            lastSyncedAt: nil
        )
        try harness.repository.upsertCloudInstanceLink(link)

        try await harness.cloudInstanceSyncService.startInstance(
            account: account,
            regionId: "ap-southeast-1",
            instanceId: "i-power",
            currentStatus: "Stopped"
        )

        var storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-southeast-1",
            instanceId: "i-power"
        )
        XCTAssertEqual(storedLink.status, "STARTING")
        XCTAssertEqual(storedLink.lastSyncedAt, capturedAt)

        link.status = "Running"
        try harness.repository.upsertCloudInstanceLink(link)
        try await harness.cloudInstanceSyncService.rebootInstance(
            account: account,
            regionId: "ap-southeast-1",
            instanceId: "i-power",
            currentStatus: "Running"
        )
        storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-southeast-1",
            instanceId: "i-power"
        )
        XCTAssertEqual(storedLink.status, "REBOOTING")

        link.status = "Running"
        try harness.repository.upsertCloudInstanceLink(link)
        try await harness.cloudInstanceSyncService.stopInstance(
            account: account,
            regionId: "ap-southeast-1",
            instanceId: "i-power",
            currentStatus: "Running"
        )
        storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-southeast-1",
            instanceId: "i-power"
        )
        XCTAssertEqual(storedLink.status, "STOPPING")
        let logs = try harness.repository.fetchRemoteChangeLogs()
        XCTAssertEqual(logs.first { $0.action == "start_instance" }?.providerId, .alibabaCloud)
        XCTAssertEqual(logs.first { $0.action == "start_instance" }?.status, "success")
        XCTAssertEqual(logs.first { $0.action == "reboot_instance" }?.status, "success")
        XCTAssertEqual(logs.first { $0.action == "stop_instance" }?.status, "success")
    }

    func testCloudInstancePowerActionsAllowHuaweiStatuses() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .huaweiCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .powerActions]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_530)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .huaweiCloud,
            displayName: "Huawei",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        var link = CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: account.id,
            providerId: .huaweiCloud,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-power",
            displayName: "prod",
            publicIp: "203.0.113.13",
            privateIp: "10.0.0.13",
            status: "SHUTOFF",
            instanceType: "s6.large.2",
            zoneId: "ap-southeast-1a",
            vpcId: nil,
            rawJSON: nil,
            lastSyncedAt: nil
        )
        try harness.repository.upsertCloudInstanceLink(link)

        try await harness.cloudInstanceSyncService.startInstance(
            account: account,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-power",
            currentStatus: "SHUTOFF"
        )

        var storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-power"
        )
        XCTAssertEqual(storedLink.status, "STARTING")
        XCTAssertEqual(storedLink.lastSyncedAt, capturedAt)

        link.status = "ACTIVE"
        try harness.repository.upsertCloudInstanceLink(link)
        try await harness.cloudInstanceSyncService.rebootInstance(
            account: account,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-power",
            currentStatus: "ACTIVE"
        )
        storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-power"
        )
        XCTAssertEqual(storedLink.status, "REBOOTING")

        link.status = "ACTIVE"
        try harness.repository.upsertCloudInstanceLink(link)
        try await harness.cloudInstanceSyncService.stopInstance(
            account: account,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-power",
            currentStatus: "ACTIVE"
        )
        storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-power"
        )
        XCTAssertEqual(storedLink.status, "STOPPING")
        let logs = try harness.repository.fetchRemoteChangeLogs()
        XCTAssertEqual(logs.first { $0.action == "start_instance" }?.providerId, .huaweiCloud)
        XCTAssertEqual(logs.first { $0.action == "start_instance" }?.status, "success")
        XCTAssertEqual(logs.first { $0.action == "reboot_instance" }?.status, "success")
        XCTAssertEqual(logs.first { $0.action == "stop_instance" }?.status, "success")
    }

    func testCloudInstanceSyncCreatesServerFromInstanceAndLinksIt() throws {
        let harness = try Harness()
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let link = CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-123",
            displayName: "prod-1",
            publicIp: "203.0.113.1",
            privateIp: "10.0.0.2",
            status: "RUNNING",
            instanceType: "S5.SMALL1",
            zoneId: "ap-guangzhou-3",
            vpcId: "vpc-1",
            rawJSON: nil,
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let profile = try harness.cloudInstanceSyncService.createServerFromInstance(
            link,
            username: "ubuntu",
            authType: .password,
            credential: .password("secret")
        )

        XCTAssertEqual(profile.name, "prod-1")
        XCTAssertEqual(profile.host, "203.0.113.1")
        XCTAssertEqual(profile.username, "ubuntu")
        XCTAssertEqual(profile.groupName, "Tencent Cloud")
        XCTAssertEqual(try harness.keychain.readPassword(keychainRef: profile.keychainRef), "secret")
        let persistedLink = try XCTUnwrap(try harness.repository.fetchCloudInstanceLinks().first)
        XCTAssertEqual(persistedLink.serverId, profile.id)
        XCTAssertEqual(persistedLink.instanceId, "ins-123")

        try harness.cloudInstanceSyncService.unlinkInstanceFromServer(server: profile)
        XCTAssertNil(try harness.repository.fetchCloudInstanceLinks().first?.serverId)
        XCTAssertEqual(try harness.repository.fetchServers().map(\.id), [profile.id])
    }

    func testTencentCloudAdapterFetchRegionsSignsRequestAndParsesResponse() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "TotalCount": 2,
                "RegionSet": [
                  {"Region": "ap-guangzhou", "RegionName": "South China (Guangzhou)", "RegionState": "AVAILABLE"},
                  {"Region": "ap-shanghai", "RegionName": "East China (Shanghai)", "RegionState": "UNAVAILABLE"}
                ],
                "RequestId": "request-1"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )

        let regions = try await adapter.fetchRegions(credential: CloudProviderCredential(
            secretId: "AKIDEXAMPLE",
            secretKey: "SECRETEXAMPLE"
        ))

        XCTAssertEqual(regions, [
            CloudRegion(id: "ap-guangzhou", displayName: "South China (Guangzhou)", available: true),
            CloudRegion(id: "ap-shanghai", displayName: "East China (Shanghai)", available: false),
        ])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "region.intl.tencentcloudapi.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Action"), "DescribeRegions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Version"), "2022-06-27")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Host"), "region.intl.tencentcloudapi.com")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-TC-Region"))
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.contains(
            "Credential=AKIDEXAMPLE/2019-02-25/region/tc3_request"
        ) == true)

        let payload = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(payload["Product"] as? String, "cvm")
        XCTAssertEqual(payload["Scene"] as? Int, 1)
    }

    func testTencentCloudAdapterFetchInstancesPaginatesAndParsesResponse() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "TotalCount": 2,
                "InstanceSet": [
                  {
                    "InstanceId": "ins-1",
                    "InstanceName": "prod-1",
                    "InstanceState": "RUNNING",
                    "InstanceType": "S5.SMALL1",
                    "PublicIpAddresses": ["203.0.113.1"],
                    "PrivateIpAddresses": ["10.0.0.2"],
                    "Placement": {"Zone": "ap-guangzhou-3"},
                    "VirtualPrivateCloud": {"VpcId": "vpc-1"}
                  }
                ],
                "RequestId": "request-1"
              }
            }
            """,
            """
            {
              "Response": {
                "TotalCount": 2,
                "InstanceSet": [
                  {
                    "InstanceId": "ins-2",
                    "InstanceName": "prod-2",
                    "InstanceState": "STOPPED",
                    "InstanceType": "S5.MEDIUM2",
                    "PublicIpAddresses": [],
                    "PrivateIpAddresses": ["10.0.0.3"],
                    "Placement": {"Zone": "ap-guangzhou-4"},
                    "VirtualPrivateCloud": {"VpcId": "vpc-2"}
                  }
                ],
                "RequestId": "request-2"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )

        let instances = try await adapter.fetchInstances(
            credential: CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE"),
            regionId: "ap-guangzhou"
        )

        XCTAssertEqual(instances.map(\.id), ["ins-1", "ins-2"])
        XCTAssertEqual(instances[0].publicIp, "203.0.113.1")
        XCTAssertEqual(instances[0].privateIp, "10.0.0.2")
        XCTAssertEqual(instances[0].zoneId, "ap-guangzhou-3")
        XCTAssertEqual(instances[1].publicIp, nil)
        XCTAssertEqual(instances[1].status, "STOPPED")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Region"), "ap-guangzhou")
        XCTAssertEqual(transport.requests[0].jsonBody?["Offset"] as? Int, 0)
        XCTAssertEqual(transport.requests[1].jsonBody?["Offset"] as? Int, 1)
    }

    func testTencentCloudAdapterFetchMetricSeriesUsesMonitorAPI() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "MetricName": "CPUUsage",
                "DataPoints": [
                  {
                    "Dimensions": [{"Name": "InstanceId", "Value": "ins-1"}],
                    "Timestamps": [1700000000, 1700000300],
                    "Values": [12.5, 18.75]
                  }
                ],
                "RequestId": "request-monitor"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )

        let series = try await adapter.fetchMetricSeries(
            credential: CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE"),
            query: CloudMetricQuery(
                namespace: "QCE/CVM",
                metricName: "CPUUsage",
                instanceId: "ins-1",
                regionId: "ap-guangzhou",
                period: 300,
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                endTime: Date(timeIntervalSince1970: 1_700_000_300)
            )
        )

        XCTAssertEqual(series.metricName, "CPUUsage")
        XCTAssertEqual(series.values, [12.5, 18.75])
        XCTAssertEqual(series.unit, "%")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.host, "monitor.intl.tencentcloudapi.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Action"), "GetMonitorData")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Version"), "2018-07-24")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Region"), "ap-guangzhou")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.contains(
            "Credential=AKIDEXAMPLE/2019-02-25/monitor/tc3_request"
        ) == true)
        let payload = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(payload["Namespace"] as? String, "QCE/CVM")
        XCTAssertEqual(payload["MetricName"] as? String, "CPUUsage")
        XCTAssertEqual(payload["Period"] as? Int, 300)
    }

    func testTencentCloudAdapterFetchSecurityGroupsAndPoliciesUsesVpcAPI() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "TotalCount": 1,
                "SecurityGroupSet": [
                  {
                    "SecurityGroupId": "sg-123",
                    "SecurityGroupName": "web",
                    "SecurityGroupDesc": "web ingress",
                    "ProjectId": 0,
                    "IsDefault": false,
                    "CreatedTime": "2026-06-01 10:00:00",
                    "UpdateTime": "2026-06-02 10:00:00"
                  }
                ],
                "RequestId": "request-sg"
              }
            }
            """,
            """
            {
              "Response": {
                "SecurityGroupPolicySet": {
                  "Version": "7",
                  "Ingress": [
                    {
                      "PolicyIndex": 0,
                      "Protocol": "TCP",
                      "Port": "22",
                      "CidrBlock": "203.0.113.0/24",
                      "Action": "ACCEPT",
                      "PolicyDescription": "SSH",
                      "ModifyTime": "2026-06-02 10:00:00"
                    }
                  ],
                  "Egress": [
                    {
                      "PolicyIndex": 0,
                      "Protocol": "ALL",
                      "Port": "all",
                      "CidrBlock": "0.0.0.0/0",
                      "Action": "ACCEPT"
                    }
                  ]
                },
                "RequestId": "request-policy"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )

        let accountId = UUID()
        let groups = try await adapter.fetchSecurityGroups(
            credential: CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE"),
            accountId: accountId,
            regionId: "ap-guangzhou"
        )
        XCTAssertEqual(groups.map(\.securityGroupId), ["sg-123"])
        XCTAssertEqual(groups[0].accountId, accountId)
        XCTAssertEqual(groups[0].name, "web")
        XCTAssertEqual(groups[0].description, "web ingress")

        let snapshot = try await adapter.fetchSecurityGroupPolicies(
            credential: CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE"),
            group: groups[0],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(snapshot.version, "7")
        XCTAssertEqual(snapshot.ingress.first?.protocolName, "TCP")
        XCTAssertEqual(snapshot.ingress.first?.port, "22")
        XCTAssertEqual(snapshot.ingress.first?.cidrBlock, "203.0.113.0/24")
        XCTAssertEqual(snapshot.egress.first?.port, "all")

        XCTAssertEqual(transport.requests[0].url?.host, "vpc.intl.tencentcloudapi.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Action"), "DescribeSecurityGroups")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Version"), "2017-03-12")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Region"), "ap-guangzhou")
        XCTAssertEqual(transport.requests[0].jsonBody?["Offset"] as? Int, 0)
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "X-TC-Action"), "DescribeSecurityGroupPolicies")
        XCTAssertEqual(transport.requests[1].jsonBody?["SecurityGroupId"] as? String, "sg-123")
    }

    func testTencentCloudAdapterAppliesSecurityGroupRuleChanges() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "RequestId": "request-authorize"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )
        let group = CloudSecurityGroup(
            accountId: UUID(),
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            securityGroupId: "sg-123",
            name: "web",
            description: nil,
            projectId: nil,
            isDefault: false,
            createdTime: nil,
            updatedTime: nil
        )
        let preview = CloudSecurityGroupRuleChangePreview.adding(
            draft: CloudSecurityGroupRuleDraft(
                direction: .ingress,
                protocolName: "TCP",
                port: "443",
                cidrBlock: "203.0.113.0/24",
                action: "ACCEPT",
                description: "HTTPS"
            ),
            to: CloudSecurityGroupPolicySnapshot(group: group, version: "7", ingress: [], egress: [], capturedAt: Date())
        )

        let requestId = try await adapter.applySecurityGroupRuleChange(
            credential: CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE"),
            preview: preview
        )

        XCTAssertEqual(requestId, "request-authorize")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Action"), "AuthorizeSecurityGroupIngress")
        XCTAssertEqual(transport.requests[0].url?.host, "vpc.intl.tencentcloudapi.com")
        XCTAssertEqual(transport.requests[0].jsonBody?["SecurityGroupId"] as? String, "sg-123")
        let policySet = try XCTUnwrap(transport.requests[0].jsonBody?["SecurityGroupPolicySet"] as? [String: Any])
        let ingress = try XCTUnwrap(policySet["Ingress"] as? [[String: Any]])
        XCTAssertEqual(ingress.first?["Protocol"] as? String, "TCP")
        XCTAssertEqual(ingress.first?["Port"] as? String, "443")
        XCTAssertEqual(ingress.first?["CidrBlock"] as? String, "203.0.113.0/24")
        XCTAssertEqual(ingress.first?["Action"] as? String, "ACCEPT")
    }

    func testTencentCloudAdapterFetchesDisksSnapshotsAndBillingStates() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "TotalCount": 1,
                "DiskSet": [
                  {
                    "DiskId": "disk-123",
                    "DiskName": "prod-data",
                    "DiskType": "CLOUD_PREMIUM",
                    "DiskUsage": "DATA_DISK",
                    "DiskSize": 100,
                    "DiskState": "ATTACHED",
                    "InstanceId": "ins-123",
                    "DiskChargeType": "POSTPAID_BY_HOUR",
                    "DeadlineTime": "2026-07-01 00:00:00"
                  }
                ],
                "RequestId": "request-disks"
              }
            }
            """,
            """
            {
              "Response": {
                "TotalCount": 1,
                "SnapshotSet": [
                  {
                    "SnapshotId": "snap-123",
                    "SnapshotName": "before-upgrade",
                    "SnapshotState": "NORMAL",
                    "DiskId": "disk-123",
                    "DiskSize": 100,
                    "CreateTime": "2026-06-25 12:00:00"
                  }
                ],
                "RequestId": "request-snapshots"
              }
            }
            """,
            """
            {
              "Response": {
                "TotalCount": 1,
                "InstanceSet": [
                  {
                    "InstanceId": "ins-123",
                    "InstanceName": "prod",
                    "InstanceState": "RUNNING",
                    "InstanceType": "S5.SMALL1",
                    "PublicIpAddresses": ["203.0.113.8"],
                    "PrivateIpAddresses": ["10.0.0.8"],
                    "Placement": {"Zone": "ap-guangzhou-3"},
                    "VirtualPrivateCloud": {"VpcId": "vpc-123"},
                    "InstanceChargeType": "PREPAID",
                    "ExpiredTime": "2026-07-10 00:00:00"
                  }
                ],
                "RequestId": "request-instances"
              }
            }
            """,
            """
            {
              "Response": {
                "TotalCount": 1,
                "DiskSet": [
                  {
                    "DiskId": "disk-123",
                    "DiskName": "prod-data",
                    "DiskType": "CLOUD_PREMIUM",
                    "DiskSize": 100,
                    "DiskState": "ATTACHED",
                    "InstanceId": "ins-123",
                    "DiskChargeType": "POSTPAID_BY_HOUR"
                  }
                ],
                "RequestId": "request-disks-2"
              }
            }
            """,
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let credential = CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE")

        let disks = try await adapter.fetchDisks(
            credential: credential,
            accountId: accountId,
            regionId: "ap-guangzhou",
            capturedAt: capturedAt
        )
        let snapshots = try await adapter.fetchSnapshots(
            credential: credential,
            accountId: accountId,
            regionId: "ap-guangzhou",
            capturedAt: capturedAt
        )
        let billing = try await adapter.fetchBillingStates(
            credential: credential,
            accountId: accountId,
            regionId: "ap-guangzhou",
            capturedAt: capturedAt
        )

        XCTAssertEqual(disks.map(\.diskId), ["disk-123"])
        XCTAssertEqual(disks[0].name, "prod-data")
        XCTAssertEqual(disks[0].sizeGB, 100)
        XCTAssertEqual(disks[0].billingType, "POSTPAID_BY_HOUR")
        XCTAssertEqual(snapshots.map(\.snapshotId), ["snap-123"])
        XCTAssertEqual(snapshots[0].diskId, "disk-123")
        XCTAssertEqual(snapshots[0].status, "NORMAL")
        XCTAssertEqual(billing.map(\.resourceType), ["instance", "disk"])
        XCTAssertEqual(billing.first { $0.resourceType == "instance" }?.billingType, "PREPAID")
        XCTAssertEqual(billing.first { $0.resourceType == "disk" }?.billingType, "POSTPAID_BY_HOUR")

        XCTAssertEqual(transport.requests[0].url?.host, "cbs.intl.tencentcloudapi.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Action"), "DescribeDisks")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Version"), "2017-03-12")
        XCTAssertEqual(transport.requests[0].jsonBody?["Limit"] as? Int, 100)
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "X-TC-Action"), "DescribeSnapshots")
        XCTAssertEqual(transport.requests[2].value(forHTTPHeaderField: "X-TC-Action"), "DescribeInstances")
        XCTAssertEqual(transport.requests[3].value(forHTTPHeaderField: "X-TC-Action"), "DescribeDisks")
    }

    func testTencentCloudAdapterCreatesAndDeletesSnapshots() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "SnapshotId": "snap-created",
                "RequestId": "request-create"
              }
            }
            """,
            """
            {
              "Response": {
                "RequestId": "request-delete"
              }
            }
            """,
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let credential = CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE")

        let snapshot = try await adapter.createSnapshot(
            credential: credential,
            accountId: accountId,
            regionId: "ap-guangzhou",
            diskId: "disk-123",
            snapshotName: "before-upgrade",
            capturedAt: capturedAt
        )
        try await adapter.deleteSnapshot(
            credential: credential,
            regionId: "ap-guangzhou",
            snapshotId: "snap-created"
        )

        XCTAssertEqual(snapshot.snapshotId, "snap-created")
        XCTAssertEqual(snapshot.diskId, "disk-123")
        XCTAssertEqual(snapshot.status, "CREATING")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Action"), "CreateSnapshot")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Region"), "ap-guangzhou")
        XCTAssertEqual(transport.requests[0].jsonBody?["DiskId"] as? String, "disk-123")
        XCTAssertEqual(transport.requests[0].jsonBody?["SnapshotName"] as? String, "before-upgrade")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "X-TC-Action"), "DeleteSnapshots")
        XCTAssertEqual(transport.requests[1].jsonBody?["SnapshotIds"] as? [String], ["snap-created"])
    }

    func testTencentCloudAdapterAttachesAndDetachesDisks() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "RequestId": "request-attach"
              }
            }
            """,
            """
            {
              "Response": {
                "RequestId": "request-detach"
              }
            }
            """,
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE")

        try await adapter.attachDisk(
            credential: credential,
            regionId: "ap-guangzhou",
            diskId: "disk-123",
            instanceId: "ins-456"
        )
        try await adapter.detachDisk(
            credential: credential,
            regionId: "ap-guangzhou",
            diskId: "disk-123"
        )

        XCTAssertEqual(transport.requests[0].url?.host, "cbs.intl.tencentcloudapi.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Action"), "AttachDisks")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Region"), "ap-guangzhou")
        XCTAssertEqual(transport.requests[0].jsonBody?["DiskIds"] as? [String], ["disk-123"])
        XCTAssertEqual(transport.requests[0].jsonBody?["InstanceId"] as? String, "ins-456")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "X-TC-Action"), "DetachDisks")
        XCTAssertEqual(transport.requests[1].jsonBody?["DiskIds"] as? [String], ["disk-123"])
    }

    func testTencentCloudAdapterRunsInstancePowerActions() async throws {
        let transport = MockTencentCloudTransport(responses: [
            #"{"Response":{"RequestId":"request-start"}}"#,
            #"{"Response":{"RequestId":"request-stop"}}"#,
            #"{"Response":{"RequestId":"request-reboot"}}"#,
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE")

        try await adapter.startInstance(credential: credential, regionId: "ap-guangzhou", instanceId: "ins-123")
        try await adapter.stopInstance(credential: credential, regionId: "ap-guangzhou", instanceId: "ins-123")
        try await adapter.rebootInstance(credential: credential, regionId: "ap-guangzhou", instanceId: "ins-123")

        XCTAssertEqual(transport.requests.map { $0.url?.host }, [
            "cvm.intl.tencentcloudapi.com",
            "cvm.intl.tencentcloudapi.com",
            "cvm.intl.tencentcloudapi.com",
        ])
        XCTAssertEqual(transport.requests.map { $0.value(forHTTPHeaderField: "X-TC-Action") }, [
            "StartInstances",
            "StopInstances",
            "RebootInstances",
        ])
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Region"), "ap-guangzhou")
        XCTAssertEqual(transport.requests[0].jsonBody?["InstanceIds"] as? [String], ["ins-123"])
        XCTAssertEqual(transport.requests[1].jsonBody?["InstanceIds"] as? [String], ["ins-123"])
        XCTAssertEqual(transport.requests[2].jsonBody?["InstanceIds"] as? [String], ["ins-123"])
    }

    func testCloudSecurityGroupServiceLoadsLinkedServerGroupsAndPolicies() async throws {
        let harness = try Harness(adapters: [
            MockCloudProviderAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .securityGroups]
            )
        ], now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let profile = try harness.service.createServer(
            name: "prod",
            host: "203.0.113.1",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        try harness.repository.upsertCloudInstanceLink(CloudInstanceLink(
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
            repository: harness.repository,
            keychain: harness.keychain,
            registry: CloudProviderRegistry(adapters: [
                MockCloudProviderAdapter(
                    providerId: .tencentCloud,
                    capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .securityGroups]
                )
            ]),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let list = try await service.loadSecurityGroups(for: profile)
        XCTAssertEqual(list.regionId, "ap-guangzhou")
        XCTAssertEqual(list.instanceId, "ins-123")
        XCTAssertEqual(list.groups.map(\.securityGroupId), ["sg-123"])

        let policies = try await service.loadPolicies(for: list.groups[0])
        XCTAssertEqual(policies.group.securityGroupId, "sg-123")
        XCTAssertEqual(policies.ingress.first?.port, "22")
        XCTAssertEqual(policies.egress.first?.protocolName, "ALL")
    }

    func testCloudMetricServiceLoadsLinkedTencentCloudCPUMetric() async throws {
        let harness = try Harness(adapters: [
            MockCloudProviderAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudMetrics]
            )
        ], now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let profile = try harness.service.createServer(
            name: "prod",
            host: "203.0.113.1",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        var link = CloudInstanceLink(
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
        )
        try harness.repository.upsertCloudInstanceLink(link)
        let service = CloudMetricService(
            repository: harness.repository,
            keychain: harness.keychain,
            registry: CloudProviderRegistry(adapters: [
                MockCloudProviderAdapter(
                    providerId: .tencentCloud,
                    capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudMetrics]
                )
            ]),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let metrics = try await service.loadMetrics(for: profile)

        XCTAssertEqual(metrics, [
            DashboardMetric(name: "Cloud CPU", value: "21.2", unit: "%", source: "Cloud API")
        ])
        link.serverId = nil
        try harness.repository.upsertCloudInstanceLink(link)
        let metricsAfterUnlink = try await service.loadMetrics(for: profile)
        XCTAssertEqual(metricsAfterUnlink, [])
    }

    func testTencentCloudAdapterMapsProviderErrors() async {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "Error": {
                  "Code": "AuthFailure.SecretIdNotFound",
                  "Message": "secret id not found"
                },
                "RequestId": "request-error"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(transport: transport, timeout: 1)

        do {
            _ = try await adapter.fetchRegions(credential: CloudProviderCredential(
                secretId: "AKIDEXAMPLE",
                secretKey: "SECRETEXAMPLE"
            ))
            XCTFail("Expected authentication failure.")
        } catch {
            XCTAssertEqual(error as? CloudProviderError, .authenticationFailed("secret id not found"))
        }
    }

    func testAlibabaCloudAdapterFetchRegionsAndInstancesUsesSignedECSAPI() async throws {
        let transport = MockAlibabaCloudTransport(responses: [
            """
            {
              "RequestId": "aliyun-regions",
              "Regions": {
                "Region": [
                  {"RegionId": "cn-hangzhou", "LocalName": "China (Hangzhou)"},
                  {"RegionId": "ap-southeast-1", "LocalName": "Singapore"}
                ]
              }
            }
            """,
            """
            {
              "RequestId": "aliyun-instances-1",
              "TotalCount": 2,
              "Instances": {
                "Instance": [
                  {
                    "InstanceId": "i-1",
                    "InstanceName": "prod-a",
                    "Status": "Running",
                    "InstanceType": "ecs.g7.large",
                    "ZoneId": "ap-southeast-1a",
                    "InstanceChargeType": "PrePaid",
                    "ExpiredTime": "2026-07-01T00:00Z",
                    "PublicIpAddress": {"IpAddress": ["203.0.113.10"]},
                    "VpcAttributes": {
                      "VpcId": "vpc-1",
                      "PrivateIpAddress": {"IpAddress": ["10.0.0.10"]}
                    }
                  }
                ]
              }
            }
            """,
            """
            {
              "RequestId": "aliyun-instances-2",
              "TotalCount": 2,
              "Instances": {
                "Instance": [
                  {
                    "InstanceId": "i-2",
                    "InstanceName": "prod-b",
                    "Status": "Stopped",
                    "InstanceType": "ecs.g7.xlarge",
                    "ZoneId": "ap-southeast-1b",
                    "EipAddress": {"IpAddress": "198.51.100.20"},
                    "VpcAttributes": {
                      "VpcId": "vpc-2",
                      "PrivateIpAddress": {"IpAddress": ["10.0.0.20"]}
                    }
                  }
                ]
              }
            }
            """,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            nonce: { "nonce-1" },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK")

        let regions = try await adapter.fetchRegions(credential: credential)
        let instances = try await adapter.fetchInstances(credential: credential, regionId: "ap-southeast-1")

        XCTAssertEqual(regions.map(\.id), ["cn-hangzhou", "ap-southeast-1"])
        XCTAssertEqual(instances.map(\.id), ["i-1", "i-2"])
        XCTAssertEqual(instances[0].providerId, .alibabaCloud)
        XCTAssertEqual(instances[0].publicIp, "203.0.113.10")
        XCTAssertEqual(instances[0].privateIp, "10.0.0.10")
        XCTAssertEqual(instances[0].vpcId, "vpc-1")
        XCTAssertEqual(instances[0].billingType, "PrePaid")
        XCTAssertEqual(instances[1].publicIp, "198.51.100.20")

        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(transport.requests[0].url?.host, "ecs.aliyuncs.com")
        XCTAssertEqual(transport.requests[0].queryValue("Action"), nil)
        XCTAssertEqual(transport.requests[0].queryValue("Version"), nil)
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-action"), "DescribeRegions")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-version"), "2014-05-26")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-signature-nonce"), "nonce-1")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("ACS3-HMAC-SHA256 Credential=ALIYUNAK") == true)
        XCTAssertEqual(transport.requests[1].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[1].queryValue("RegionId"), "ap-southeast-1")
        XCTAssertEqual(transport.requests[1].queryValue("PageNumber"), "1")
        XCTAssertEqual(transport.requests[2].queryValue("PageNumber"), "2")
    }

    func testAlibabaCloudAdapterFetchesDisksUsesSignedECSAPI() async throws {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockAlibabaCloudTransport(responses: [
            """
            {
              "RequestId": "aliyun-disks-1",
              "TotalCount": 2,
              "Disks": {
                "Disk": [
                  {
                    "DiskId": "d-1",
                    "DiskName": "prod-system",
                    "Category": "cloud_essd",
                    "Type": "system",
                    "Size": 80,
                    "Status": "In_use",
                    "InstanceId": "i-1",
                    "DiskChargeType": "PrePaid",
                    "ExpiredTime": "2026-07-01T00:00:00Z"
                  }
                ]
              }
            }
            """,
            """
            {
              "RequestId": "aliyun-disks-2",
              "TotalCount": 2,
              "Disks": {
                "Disk": [
                  {
                    "DiskId": "d-2",
                    "DiskName": "prod-data",
                    "Category": "cloud_efficiency",
                    "Type": "data",
                    "Size": 200,
                    "Status": "Available",
                    "DiskChargeType": "PostPaid"
                  }
                ]
              }
            }
            """,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { capturedAt },
            nonce: { "nonce-disk" },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK")

        let disks = try await adapter.fetchDisks(
            credential: credential,
            accountId: accountId,
            regionId: "ap-southeast-1",
            capturedAt: capturedAt
        )

        XCTAssertEqual(disks.map(\.diskId), ["d-1", "d-2"])
        XCTAssertEqual(disks[0].accountId, accountId)
        XCTAssertEqual(disks[0].providerId, .alibabaCloud)
        XCTAssertEqual(disks[0].regionId, "ap-southeast-1")
        XCTAssertEqual(disks[0].instanceId, "i-1")
        XCTAssertEqual(disks[0].name, "prod-system")
        XCTAssertEqual(disks[0].diskType, "cloud_essd")
        XCTAssertEqual(disks[0].sizeGB, 80)
        XCTAssertEqual(disks[0].status, "In_use")
        XCTAssertEqual(disks[0].billingType, "PrePaid")
        XCTAssertNotNil(disks[0].expiredTime)
        XCTAssertEqual(disks[0].lastSyncedAt, capturedAt)
        XCTAssertEqual(disks[1].diskType, "cloud_efficiency")
        XCTAssertEqual(disks[1].billingType, "PostPaid")

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-action"), "DescribeDisks")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-version"), "2014-05-26")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-signature-nonce"), "nonce-disk")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("ACS3-HMAC-SHA256 Credential=ALIYUNAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("RegionId"), "ap-southeast-1")
        XCTAssertEqual(transport.requests[0].queryValue("PageNumber"), "1")
        XCTAssertEqual(transport.requests[0].queryValue("PageSize"), "100")
        XCTAssertEqual(transport.requests[1].queryValue("PageNumber"), "2")
    }

    func testAlibabaCloudAdapterFetchesSnapshotsUsesSignedECSAPI() async throws {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockAlibabaCloudTransport(responses: [
            """
            {
              "RequestId": "aliyun-snapshots-1",
              "TotalCount": 2,
              "Snapshots": {
                "Snapshot": [
                  {
                    "SnapshotId": "s-1",
                    "SnapshotName": "before-upgrade",
                    "Status": "accomplished",
                    "SourceDiskId": "d-1",
                    "SourceDiskSize": 80,
                    "CreationTime": "2026-07-01T00:00:00Z"
                  }
                ]
              }
            }
            """,
            """
            {
              "RequestId": "aliyun-snapshots-2",
              "TotalCount": 2,
              "Snapshots": {
                "Snapshot": [
                  {
                    "SnapshotId": "s-2",
                    "SnapshotName": "manual-backup",
                    "Status": "progressing",
                    "DiskId": "d-2",
                    "Size": 200,
                    "CreateTime": "2026-07-02T00:00:00Z"
                  }
                ]
              }
            }
            """,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { capturedAt },
            nonce: { "nonce-snapshot" },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK")

        let snapshots = try await adapter.fetchSnapshots(
            credential: credential,
            accountId: accountId,
            regionId: "ap-southeast-1",
            capturedAt: capturedAt
        )

        XCTAssertEqual(snapshots.map(\.snapshotId), ["s-1", "s-2"])
        XCTAssertEqual(snapshots[0].accountId, accountId)
        XCTAssertEqual(snapshots[0].providerId, .alibabaCloud)
        XCTAssertEqual(snapshots[0].regionId, "ap-southeast-1")
        XCTAssertEqual(snapshots[0].diskId, "d-1")
        XCTAssertEqual(snapshots[0].name, "before-upgrade")
        XCTAssertEqual(snapshots[0].status, "accomplished")
        XCTAssertEqual(snapshots[0].sizeGB, 80)
        XCTAssertNotNil(snapshots[0].createdAtProvider)
        XCTAssertEqual(snapshots[0].lastSyncedAt, capturedAt)
        XCTAssertEqual(snapshots[1].diskId, "d-2")
        XCTAssertEqual(snapshots[1].sizeGB, 200)
        XCTAssertNotNil(snapshots[1].createdAtProvider)

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-action"), "DescribeSnapshots")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-version"), "2014-05-26")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-signature-nonce"), "nonce-snapshot")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("ACS3-HMAC-SHA256 Credential=ALIYUNAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("RegionId"), "ap-southeast-1")
        XCTAssertEqual(transport.requests[0].queryValue("PageNumber"), "1")
        XCTAssertEqual(transport.requests[0].queryValue("PageSize"), "100")
        XCTAssertEqual(transport.requests[1].queryValue("PageNumber"), "2")
    }

    func testAlibabaCloudAdapterCreatesAndDeletesSnapshotsUsesSignedECSAPI() async throws {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockAlibabaCloudTransport(responses: [
            """
            {
              "RequestId": "aliyun-create-snapshot",
              "SnapshotId": "s-created"
            }
            """,
            """
            {
              "RequestId": "aliyun-delete-snapshot"
            }
            """,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { capturedAt },
            nonce: { "nonce-snapshot-action" },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK")

        let snapshot = try await adapter.createSnapshot(
            credential: credential,
            accountId: accountId,
            regionId: "ap-southeast-1",
            diskId: "d-1",
            snapshotName: "before-upgrade",
            capturedAt: capturedAt
        )
        try await adapter.deleteSnapshot(
            credential: credential,
            regionId: "ap-southeast-1",
            snapshotId: "s-created"
        )

        XCTAssertTrue(adapter.capabilities.contains(.snapshotActions))
        XCTAssertEqual(snapshot.snapshotId, "s-created")
        XCTAssertEqual(snapshot.accountId, accountId)
        XCTAssertEqual(snapshot.providerId, .alibabaCloud)
        XCTAssertEqual(snapshot.regionId, "ap-southeast-1")
        XCTAssertEqual(snapshot.diskId, "d-1")
        XCTAssertEqual(snapshot.name, "before-upgrade")
        XCTAssertEqual(snapshot.status, "CREATING")
        XCTAssertEqual(snapshot.createdAtProvider, capturedAt)
        XCTAssertEqual(snapshot.lastSyncedAt, capturedAt)

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-action"), "CreateSnapshot")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-version"), "2014-05-26")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-signature-nonce"), "nonce-snapshot-action")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("ACS3-HMAC-SHA256 Credential=ALIYUNAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("DiskId"), "d-1")
        XCTAssertEqual(transport.requests[0].queryValue("SnapshotName"), "before-upgrade")
        XCTAssertNil(transport.requests[0].queryValue("Force"))
        XCTAssertEqual(transport.requests[1].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "x-acs-action"), "DeleteSnapshot")
        XCTAssertEqual(transport.requests[1].queryValue("SnapshotId"), "s-created")
        XCTAssertNil(transport.requests[1].queryValue("Force"))
    }

    func testAlibabaCloudAdapterAttachesAndDetachesDisksUsesSignedECSAPI() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockAlibabaCloudTransport(responses: [
            """
            {
              "RequestId": "aliyun-attach-disk"
            }
            """,
            """
            {
              "RequestId": "aliyun-detach-disk"
            }
            """,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { capturedAt },
            nonce: { "nonce-disk-action" },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK")

        try await adapter.attachDisk(
            credential: credential,
            regionId: "ap-southeast-1",
            diskId: "d-1",
            instanceId: "i-1"
        )
        try await adapter.detachDisk(
            credential: credential,
            regionId: "ap-southeast-1",
            diskId: "d-1"
        )

        XCTAssertTrue(adapter.capabilities.contains(.diskAttachmentActions))
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-action"), "AttachDisk")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-version"), "2014-05-26")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-signature-nonce"), "nonce-disk-action")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("ACS3-HMAC-SHA256 Credential=ALIYUNAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("RegionId"), "ap-southeast-1")
        XCTAssertEqual(transport.requests[0].queryValue("DiskId"), "d-1")
        XCTAssertEqual(transport.requests[0].queryValue("InstanceId"), "i-1")
        XCTAssertEqual(transport.requests[1].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "x-acs-action"), "DetachDisk")
        XCTAssertEqual(transport.requests[1].queryValue("RegionId"), "ap-southeast-1")
        XCTAssertEqual(transport.requests[1].queryValue("DiskId"), "d-1")
        XCTAssertNil(transport.requests[1].queryValue("InstanceId"))
    }

    func testAlibabaCloudAdapterRunsInstancePowerActionsUsesSignedECSAPI() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockAlibabaCloudTransport(responses: [
            #"{"RequestId":"aliyun-start"}"#,
            #"{"RequestId":"aliyun-stop"}"#,
            #"{"RequestId":"aliyun-reboot"}"#,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { capturedAt },
            nonce: { "nonce-power-action" },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK")

        try await adapter.startInstance(
            credential: credential,
            regionId: "ap-southeast-1",
            instanceId: "i-1"
        )
        try await adapter.stopInstance(
            credential: credential,
            regionId: "ap-southeast-1",
            instanceId: "i-1"
        )
        try await adapter.rebootInstance(
            credential: credential,
            regionId: "ap-southeast-1",
            instanceId: "i-1"
        )

        XCTAssertTrue(adapter.capabilities.contains(.powerActions))
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(transport.requests.map { $0.value(forHTTPHeaderField: "x-acs-action") }, [
            "StartInstance",
            "StopInstance",
            "RebootInstance",
        ])
        for request in transport.requests {
            XCTAssertEqual(request.url?.host, "ecs.ap-southeast-1.aliyuncs.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-acs-version"), "2014-05-26")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-acs-signature-nonce"), "nonce-power-action")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("ACS3-HMAC-SHA256 Credential=ALIYUNAK") == true)
            XCTAssertEqual(request.queryValue("RegionId"), "ap-southeast-1")
            XCTAssertEqual(request.queryValue("InstanceId"), "i-1")
        }
    }

    func testAlibabaCloudAdapterFetchesSecurityGroupsAndPoliciesUsesSignedECSAPI() async throws {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockAlibabaCloudTransport(responses: [
            """
            {
              "RequestId": "aliyun-sg",
              "TotalCount": 1,
              "SecurityGroups": {
                "SecurityGroup": [
                  {
                    "SecurityGroupId": "sg-1",
                    "SecurityGroupName": "web",
                    "Description": "web ingress",
                    "ResourceGroupId": "rg-1",
                    "VpcId": "vpc-1",
                    "CreationTime": "2026-07-01T00:00:00Z"
                  }
                ]
              }
            }
            """,
            """
            {
              "RequestId": "aliyun-sg-attr",
              "SecurityGroupId": "sg-1",
              "SecurityGroupName": "web",
              "InnerAccessPolicy": "Accept",
              "Permissions": {
                "Permission": [
                  {
                    "Direction": "ingress",
                    "IpProtocol": "tcp",
                    "PortRange": "22/22",
                    "SourceCidrIp": "203.0.113.0/24",
                    "Policy": "Accept",
                    "Description": "SSH",
                    "Priority": 1,
                    "CreateTime": "2026-07-01T00:00:00Z"
                  },
                  {
                    "Direction": "egress",
                    "IpProtocol": "all",
                    "PortRange": "-1/-1",
                    "DestCidrIp": "0.0.0.0/0",
                    "Policy": "Accept",
                    "Priority": 1
                  }
                ]
              }
            }
            """,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { capturedAt },
            nonce: { "nonce-sg" },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK")

        let groups = try await adapter.fetchSecurityGroups(
            credential: credential,
            accountId: accountId,
            regionId: "ap-southeast-1"
        )
        let snapshot = try await adapter.fetchSecurityGroupPolicies(
            credential: credential,
            group: try XCTUnwrap(groups.first),
            capturedAt: capturedAt
        )

        XCTAssertEqual(groups.map(\.securityGroupId), ["sg-1"])
        XCTAssertEqual(groups[0].accountId, accountId)
        XCTAssertEqual(groups[0].providerId, .alibabaCloud)
        XCTAssertEqual(groups[0].regionId, "ap-southeast-1")
        XCTAssertEqual(groups[0].name, "web")
        XCTAssertEqual(groups[0].description, "web ingress")
        XCTAssertEqual(groups[0].projectId, "rg-1")
        XCTAssertEqual(groups[0].createdTime, "2026-07-01T00:00:00Z")
        XCTAssertEqual(snapshot.version, "Accept")
        XCTAssertEqual(snapshot.ingress.count, 1)
        XCTAssertEqual(snapshot.ingress[0].protocolName, "tcp")
        XCTAssertEqual(snapshot.ingress[0].port, "22/22")
        XCTAssertEqual(snapshot.ingress[0].cidrBlock, "203.0.113.0/24")
        XCTAssertEqual(snapshot.ingress[0].action, "Accept")
        XCTAssertEqual(snapshot.ingress[0].description, "SSH")
        XCTAssertEqual(snapshot.ingress[0].policyIndex, 1)
        XCTAssertEqual(snapshot.egress.count, 1)
        XCTAssertEqual(snapshot.egress[0].protocolName, "all")
        XCTAssertEqual(snapshot.egress[0].cidrBlock, "0.0.0.0/0")

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-action"), "DescribeSecurityGroups")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-version"), "2014-05-26")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-signature-nonce"), "nonce-sg")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("ACS3-HMAC-SHA256 Credential=ALIYUNAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("RegionId"), "ap-southeast-1")
        XCTAssertEqual(transport.requests[0].queryValue("PageNumber"), "1")
        XCTAssertEqual(transport.requests[0].queryValue("PageSize"), "100")
        XCTAssertEqual(transport.requests[1].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "x-acs-action"), "DescribeSecurityGroupAttribute")
        XCTAssertEqual(transport.requests[1].queryValue("RegionId"), "ap-southeast-1")
        XCTAssertEqual(transport.requests[1].queryValue("SecurityGroupId"), "sg-1")
    }

    func testHuaweiCloudAdapterFetchRegionsAndInstancesUsesSignedECSAPI() async throws {
        let transport = MockHuaweiCloudTransport(responses: [
            """
            {
              "projects": [
                {"id": "project-1", "name": "ap-southeast-1", "enabled": true},
                {"id": "project-2", "name": "ap-southeast-2", "enabled": false}
              ]
            }
            """,
            """
            {
              "count": 1,
              "servers": [
                {
                  "id": "server-1",
                  "name": "prod-hw",
                  "status": "ACTIVE",
                  "OS-EXT-STS:vm_state": "active",
                  "OS-EXT-AZ:availability_zone": "ap-southeast-1a",
                  "flavor": {"id": "s6.large.2"},
                  "metadata": {"charging_mode": "prePaid"},
                  "addresses": {
                    "net-a": [
                      {"addr": "10.0.1.5", "OS-EXT-IPS:type": "fixed"},
                      {"addr": "203.0.113.55", "OS-EXT-IPS:type": "floating"}
                    ]
                  }
                }
              ]
            }
            """,
        ])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK")

        let regions = try await adapter.fetchRegions(credential: credential)
        let instances = try await adapter.fetchInstances(credential: credential, regionId: regions[0].id)

        XCTAssertEqual(regions[0].displayName, "ap-southeast-1")
        XCTAssertEqual(regions[0].id, "ap-southeast-1|project-1")
        XCTAssertEqual(instances.map(\.id), ["server-1"])
        XCTAssertEqual(instances[0].providerId, .huaweiCloud)
        XCTAssertEqual(instances[0].regionId, "ap-southeast-1|project-1")
        XCTAssertEqual(instances[0].publicIp, "203.0.113.55")
        XCTAssertEqual(instances[0].privateIp, "10.0.1.5")
        XCTAssertEqual(instances[0].instanceType, "s6.large.2")
        XCTAssertEqual(instances[0].zoneId, "ap-southeast-1a")
        XCTAssertEqual(instances[0].billingType, "prePaid")

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "iam.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/v3/projects")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-Sdk-Date"), "20231114T221320Z")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("SDK-HMAC-SHA256 Access=HUAWEIAK") == true)
        XCTAssertEqual(transport.requests[1].url?.host, "ecs.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[1].url?.path, "/v1.1/project-1/cloudservers/detail")
        XCTAssertEqual(transport.requests[1].queryValue("limit"), "100")
        XCTAssertEqual(transport.requests[1].queryValue("offset"), "0")
    }

    func testHuaweiCloudAdapterFetchesDisksUsesSignedEVSAPI() async throws {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockHuaweiCloudTransport(responses: [
            """
            {
              "count": 2,
              "volumes": [
                {
                  "id": "vol-1",
                  "name": "prod-system",
                  "size": 80,
                  "status": "in-use",
                  "volume_type": "SSD",
                  "attachments": [
                    {"server_id": "server-1"}
                  ],
                  "metadata": {
                    "charging_mode": "prePaid",
                    "orderID": "order-1"
                  }
                }
              ]
            }
            """,
            """
            {
              "count": 2,
              "volumes": [
                {
                  "id": "vol-2",
                  "name": "prod-data",
                  "size": 200,
                  "status": "available",
                  "volume_type": "SAS",
                  "attachments": [],
                  "metadata": {
                    "billingMode": "postPaid"
                  }
                }
              ]
            }
            """,
        ])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { capturedAt },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK")

        let disks = try await adapter.fetchDisks(
            credential: credential,
            accountId: accountId,
            regionId: "ap-southeast-1|project-1",
            capturedAt: capturedAt
        )

        XCTAssertEqual(disks.map(\.diskId), ["vol-1", "vol-2"])
        XCTAssertEqual(disks[0].accountId, accountId)
        XCTAssertEqual(disks[0].providerId, .huaweiCloud)
        XCTAssertEqual(disks[0].regionId, "ap-southeast-1|project-1")
        XCTAssertEqual(disks[0].instanceId, "server-1")
        XCTAssertEqual(disks[0].name, "prod-system")
        XCTAssertEqual(disks[0].diskType, "SSD")
        XCTAssertEqual(disks[0].sizeGB, 80)
        XCTAssertEqual(disks[0].status, "in-use")
        XCTAssertEqual(disks[0].billingType, "prePaid")
        XCTAssertEqual(disks[0].lastSyncedAt, capturedAt)
        XCTAssertNil(disks[1].instanceId)
        XCTAssertEqual(disks[1].diskType, "SAS")
        XCTAssertEqual(disks[1].billingType, "postPaid")

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "evs.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/v2/project-1/cloudvolumes/detail")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-Sdk-Date"), "20231114T221320Z")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("SDK-HMAC-SHA256 Access=HUAWEIAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("limit"), "100")
        XCTAssertEqual(transport.requests[0].queryValue("offset"), "0")
        XCTAssertEqual(transport.requests[1].queryValue("offset"), "1")
    }

    func testHuaweiCloudAdapterFetchesSnapshotsUsesSignedEVSAPI() async throws {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let firstPageSnapshots = (1...10).map { index in
            """
                  {
                    "id": "snap-\(index)",
                    "name": "backup-\(index)",
                    "volume_id": "vol-\(index)",
                    "size": \(index * 10),
                    "status": "available",
                    "created_at": "2026-07-01T00:00:00.000000"
                  }
            """
        }.joined(separator: ",\n")
        let transport = MockHuaweiCloudTransport(responses: [
            """
            {
              "snapshots": [
            \(firstPageSnapshots)
              ]
            }
            """,
            """
            {
              "snapshots": [
                {
                  "id": "snap-11",
                  "name": "manual-backup",
                  "volume_id": "vol-11",
                  "size": "110",
                  "status": "creating",
                  "created_at": "2026-07-02T00:00:00Z"
                }
              ]
            }
            """,
        ])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { capturedAt },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK")

        let snapshots = try await adapter.fetchSnapshots(
            credential: credential,
            accountId: accountId,
            regionId: "ap-southeast-1|project-1",
            capturedAt: capturedAt
        )

        XCTAssertEqual(snapshots.count, 11)
        XCTAssertEqual(snapshots.first?.snapshotId, "snap-1")
        XCTAssertEqual(snapshots.first?.accountId, accountId)
        XCTAssertEqual(snapshots.first?.providerId, .huaweiCloud)
        XCTAssertEqual(snapshots.first?.regionId, "ap-southeast-1|project-1")
        XCTAssertEqual(snapshots.first?.diskId, "vol-1")
        XCTAssertEqual(snapshots.first?.name, "backup-1")
        XCTAssertEqual(snapshots.first?.status, "available")
        XCTAssertEqual(snapshots.first?.sizeGB, 10)
        XCTAssertNotNil(snapshots.first?.createdAtProvider)
        XCTAssertEqual(snapshots.first?.lastSyncedAt, capturedAt)
        XCTAssertEqual(snapshots.last?.snapshotId, "snap-11")
        XCTAssertEqual(snapshots.last?.sizeGB, 110)
        XCTAssertNotNil(snapshots.last?.createdAtProvider)

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "evs.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/v5/project-1/snapshots/detail")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-Sdk-Date"), "20231114T221320Z")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("SDK-HMAC-SHA256 Access=HUAWEIAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("limit"), "10")
        XCTAssertEqual(transport.requests[0].queryValue("offset"), "0")
        XCTAssertEqual(transport.requests[1].queryValue("offset"), "10")
    }

    func testHuaweiCloudAdapterCreatesAndDeletesSnapshotsUsesSignedEVSAPI() async throws {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockHuaweiCloudTransport(responses: [
            """
            {
              "snapshot": {
                "id": "snap-created",
                "name": "before-upgrade",
                "volume_id": "vol-1",
                "size": 80,
                "status": "creating",
                "created_at": "2026-07-01T00:00:00Z"
              }
            }
            """,
            """
            {
              "job_id": "job-delete"
            }
            """,
        ])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { capturedAt },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK")

        let snapshot = try await adapter.createSnapshot(
            credential: credential,
            accountId: accountId,
            regionId: "ap-southeast-1|project-1",
            diskId: "vol-1",
            snapshotName: "before-upgrade",
            capturedAt: capturedAt
        )
        try await adapter.deleteSnapshot(
            credential: credential,
            regionId: "ap-southeast-1|project-1",
            snapshotId: "snap-created"
        )

        XCTAssertTrue(adapter.capabilities.contains(.snapshotActions))
        XCTAssertEqual(snapshot.snapshotId, "snap-created")
        XCTAssertEqual(snapshot.accountId, accountId)
        XCTAssertEqual(snapshot.providerId, .huaweiCloud)
        XCTAssertEqual(snapshot.regionId, "ap-southeast-1|project-1")
        XCTAssertEqual(snapshot.diskId, "vol-1")
        XCTAssertEqual(snapshot.name, "before-upgrade")
        XCTAssertEqual(snapshot.status, "creating")
        XCTAssertEqual(snapshot.sizeGB, 80)
        XCTAssertNotNil(snapshot.createdAtProvider)
        XCTAssertEqual(snapshot.lastSyncedAt, capturedAt)

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].httpMethod, "POST")
        XCTAssertEqual(transport.requests[0].url?.host, "evs.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/v2/project-1/cloudsnapshots")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-Sdk-Date"), "20231114T221320Z")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("SDK-HMAC-SHA256 Access=HUAWEIAK") == true)
        let createBody = try XCTUnwrap(transport.requests[0].jsonBody?["snapshot"] as? [String: Any])
        XCTAssertEqual(createBody["name"] as? String, "before-upgrade")
        XCTAssertEqual(createBody["volume_id"] as? String, "vol-1")
        XCTAssertEqual(transport.requests[1].httpMethod, "DELETE")
        XCTAssertEqual(transport.requests[1].url?.host, "evs.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[1].url?.path, "/v2/project-1/cloudsnapshots/snap-created")
        XCTAssertNil(transport.requests[1].httpBody)
    }

    func testHuaweiCloudAdapterAttachesAndDetachesDisksUsesSignedEVSAPI() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockHuaweiCloudTransport(responses: ["{}", ""])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { capturedAt },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK")

        try await adapter.attachDisk(
            credential: credential,
            regionId: "ap-southeast-1|project-1",
            diskId: "vol-1",
            instanceId: "server-1"
        )
        try await adapter.detachDisk(
            credential: credential,
            regionId: "ap-southeast-1|project-1",
            diskId: "vol-1"
        )

        XCTAssertTrue(adapter.capabilities.contains(.diskAttachmentActions))
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].httpMethod, "POST")
        XCTAssertEqual(transport.requests[0].url?.host, "evs.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/v2/project-1/volumes/vol-1/action")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-Sdk-Date"), "20231114T221320Z")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("SDK-HMAC-SHA256 Access=HUAWEIAK") == true)
        let attachBody = try XCTUnwrap(transport.requests[0].jsonBody?["os-attach"] as? [String: Any])
        XCTAssertEqual(attachBody["instance_uuid"] as? String, "server-1")
        XCTAssertNil(attachBody["mountpoint"])
        XCTAssertNil(attachBody["mode"])
        XCTAssertEqual(transport.requests[1].httpMethod, "POST")
        XCTAssertEqual(transport.requests[1].url?.host, "evs.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[1].url?.path, "/v2/project-1/volumes/vol-1/action")
        let detachBody = try XCTUnwrap(transport.requests[1].jsonBody?["os-detach"] as? [String: Any])
        XCTAssertNil(detachBody["attachment_id"])
    }

    func testHuaweiCloudAdapterRunsInstancePowerActionsUsesSignedECSAPI() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockHuaweiCloudTransport(responses: ["{}", "", "{}"])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { capturedAt },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK")

        try await adapter.startInstance(
            credential: credential,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-1"
        )
        try await adapter.stopInstance(
            credential: credential,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-1"
        )
        try await adapter.rebootInstance(
            credential: credential,
            regionId: "ap-southeast-1|project-1",
            instanceId: "server-1"
        )

        XCTAssertTrue(adapter.capabilities.contains(.powerActions))
        XCTAssertEqual(transport.requests.count, 3)
        for request in transport.requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.host, "ecs.ap-southeast-1.myhuaweicloud.com")
            XCTAssertEqual(request.url?.path, "/v1/project-1/cloudservers/action")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Sdk-Date"), "20231114T221320Z")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SDK-HMAC-SHA256 Access=HUAWEIAK") == true)
        }

        let startBody = try XCTUnwrap(transport.requests[0].jsonBody?["os-start"] as? [String: Any])
        let startServers = try XCTUnwrap(startBody["servers"] as? [[String: Any]])
        XCTAssertEqual(startServers.first?["id"] as? String, "server-1")
        let stopBody = try XCTUnwrap(transport.requests[1].jsonBody?["os-stop"] as? [String: Any])
        XCTAssertEqual(stopBody["type"] as? String, "SOFT")
        let stopServers = try XCTUnwrap(stopBody["servers"] as? [[String: Any]])
        XCTAssertEqual(stopServers.first?["id"] as? String, "server-1")
        let rebootBody = try XCTUnwrap(transport.requests[2].jsonBody?["reboot"] as? [String: Any])
        XCTAssertEqual(rebootBody["type"] as? String, "SOFT")
        let rebootServers = try XCTUnwrap(rebootBody["servers"] as? [[String: Any]])
        XCTAssertEqual(rebootServers.first?["id"] as? String, "server-1")
    }

    func testHuaweiCloudAdapterFetchesSecurityGroupsAndPoliciesUsesSignedVPCAPI() async throws {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockHuaweiCloudTransport(responses: [
            """
            {
              "security_groups": [
                {
                  "id": "sg-hw-1",
                  "name": "web",
                  "description": "web ingress",
                  "enterprise_project_id": "0",
                  "created_at": "2026-07-01T00:00:00Z",
                  "updated_at": "2026-07-02T00:00:00Z"
                }
              ]
            }
            """,
            """
            {
              "security_group_rules": [
                {
                  "id": "rule-ingress",
                  "security_group_id": "sg-hw-1",
                  "direction": "ingress",
                  "ethertype": "IPv4",
                  "protocol": "tcp",
                  "port_range_min": 22,
                  "port_range_max": 22,
                  "remote_ip_prefix": "203.0.113.0/24",
                  "action": "allow",
                  "priority": 1,
                  "description": "SSH",
                  "created_at": "2026-07-01T00:00:00Z"
                },
                {
                  "id": "rule-egress",
                  "security_group_id": "sg-hw-1",
                  "direction": "egress",
                  "ethertype": "IPv6",
                  "protocol": "any",
                  "remote_ip_prefix": "2001:db8::/64",
                  "remote_group_id": "sg-peer",
                  "action": "allow",
                  "priority": 2,
                  "updated_at": "2026-07-03T00:00:00Z"
                }
              ]
            }
            """,
        ])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { capturedAt },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK")

        let groups = try await adapter.fetchSecurityGroups(
            credential: credential,
            accountId: accountId,
            regionId: "ap-southeast-1|project-1"
        )
        let snapshot = try await adapter.fetchSecurityGroupPolicies(
            credential: credential,
            group: try XCTUnwrap(groups.first),
            capturedAt: capturedAt
        )

        XCTAssertTrue(adapter.capabilities.contains(.securityGroups))
        XCTAssertEqual(groups.map(\.securityGroupId), ["sg-hw-1"])
        XCTAssertEqual(groups[0].accountId, accountId)
        XCTAssertEqual(groups[0].providerId, .huaweiCloud)
        XCTAssertEqual(groups[0].regionId, "ap-southeast-1|project-1")
        XCTAssertEqual(groups[0].name, "web")
        XCTAssertEqual(groups[0].description, "web ingress")
        XCTAssertEqual(groups[0].projectId, "0")
        XCTAssertEqual(groups[0].createdTime, "2026-07-01T00:00:00Z")
        XCTAssertEqual(groups[0].updatedTime, "2026-07-02T00:00:00Z")
        XCTAssertEqual(snapshot.ingress.count, 1)
        XCTAssertEqual(snapshot.ingress[0].protocolName, "tcp")
        XCTAssertEqual(snapshot.ingress[0].port, "22")
        XCTAssertEqual(snapshot.ingress[0].cidrBlock, "203.0.113.0/24")
        XCTAssertEqual(snapshot.ingress[0].action, "allow")
        XCTAssertEqual(snapshot.ingress[0].description, "SSH")
        XCTAssertEqual(snapshot.ingress[0].policyIndex, 1)
        XCTAssertEqual(snapshot.egress.count, 1)
        XCTAssertEqual(snapshot.egress[0].protocolName, "any")
        XCTAssertNil(snapshot.egress[0].cidrBlock)
        XCTAssertEqual(snapshot.egress[0].ipv6CidrBlock, "2001:db8::/64")
        XCTAssertEqual(snapshot.egress[0].referencedSecurityGroupId, "sg-peer")
        XCTAssertEqual(snapshot.egress[0].modifiedTime, "2026-07-03T00:00:00Z")

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "vpc.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/v1/project-1/security-groups")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-Sdk-Date"), "20231114T221320Z")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("SDK-HMAC-SHA256 Access=HUAWEIAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("limit"), "100")
        XCTAssertNil(transport.requests[0].queryValue("marker"))
        XCTAssertEqual(transport.requests[1].url?.host, "vpc.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[1].url?.path, "/v1/project-1/security-group-rules")
        XCTAssertEqual(transport.requests[1].queryValue("limit"), "100")
        XCTAssertEqual(transport.requests[1].queryValue("security_group_id"), "sg-hw-1")
        XCTAssertNil(transport.requests[1].queryValue("marker"))
    }

    private final class Harness {
        let repository: ServerRepository
        let keychain: KeychainService
        let service: ServerManagementService
        let cloudAccountService: CloudAccountService
        let cloudInstanceSyncService: CloudInstanceSyncService

        init(
            adapters: [any CloudProviderAdapter] = [
                MockCloudProviderAdapter(
                    providerId: .tencentCloud,
                    capabilities: [.regions, .instanceDiscovery, .instanceMetadata]
                ),
            ],
            now: @escaping @Sendable () -> Date = Date.init
        ) throws {
            repository = ServerRepository(database: try AppDatabase.inMemory())
            keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.tests.\(UUID().uuidString)")
            service = ServerManagementService(repository: repository, keychain: keychain)
            cloudAccountService = CloudAccountService(repository: repository, keychain: keychain)
            cloudInstanceSyncService = CloudInstanceSyncService(
                repository: repository,
                keychain: keychain,
                registry: CloudProviderRegistry(adapters: adapters),
                serverManagementService: service,
                now: now
            )
        }
    }
}

private struct MockCloudProviderAdapter: CloudProviderAdapter {
    let providerId: CloudProviderID
    let displayName = "Mock Cloud"
    let capabilities: Set<CloudCapability>

    func validateCredential(_ credential: CloudProviderCredential) async throws {}

    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion] {
        [
            CloudRegion(id: "ap-guangzhou", displayName: "Guangzhou", available: true),
        ]
    }

    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance] {
        [
            CloudProviderInstance(
                id: "ins-123",
                providerId: providerId,
                regionId: regionId,
                displayName: "mock-instance",
                publicIp: "203.0.113.1",
                privateIp: "10.0.0.2",
                status: "RUNNING",
                instanceType: "mock",
                zoneId: "\(regionId)-1",
                vpcId: "vpc-123",
                billingType: "POSTPAID_BY_HOUR",
                expiredTime: nil,
                rawJSON: nil
            ),
        ]
    }

    func fetchMetricSeries(credential: CloudProviderCredential, query: CloudMetricQuery) async throws -> CloudMetricSeries {
        CloudMetricSeries(
            metricName: query.metricName,
            instanceId: query.instanceId,
            regionId: query.regionId,
            unit: "%",
            values: [18.5, 21.25],
            timestamps: [query.startTime, query.endTime]
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
                createdTime: "2026-06-01 10:00:00",
                updatedTime: "2026-06-02 10:00:00"
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
                    modifiedTime: "2026-06-02 10:00:00"
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

    func fetchDisks(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudDisk] {
        [
            CloudDisk(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
                accountId: accountId,
                providerId: providerId,
                regionId: regionId,
                diskId: "disk-123",
                instanceId: "ins-123",
                name: "system-disk",
                diskType: "CLOUD_PREMIUM",
                sizeGB: 50,
                status: "ATTACHED",
                billingType: "POSTPAID_BY_HOUR",
                expiredTime: nil,
                rawJSON: nil,
                lastSyncedAt: capturedAt
            ),
        ]
    }

    func fetchSnapshots(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudSnapshot] {
        [
            CloudSnapshot(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!,
                accountId: accountId,
                providerId: providerId,
                regionId: regionId,
                snapshotId: "snap-123",
                diskId: "disk-123",
                name: "before-upgrade",
                status: "NORMAL",
                sizeGB: 50,
                createdAtProvider: Date(timeIntervalSince1970: 1_700_000_000),
                rawJSON: nil,
                lastSyncedAt: capturedAt
            ),
        ]
    }

    func fetchBillingStates(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudBillingState] {
        [
            CloudBillingState(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000789")!,
                accountId: accountId,
                providerId: providerId,
                resourceType: "instance",
                resourceId: "ins-123",
                billingType: "POSTPAID_BY_HOUR",
                expireAt: nil,
                status: "RUNNING",
                rawJSON: nil,
                lastSyncedAt: capturedAt
            ),
        ]
    }

    func createSnapshot(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        diskId: String,
        snapshotName: String,
        capturedAt: Date
    ) async throws -> CloudSnapshot {
        CloudSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000999")!,
            accountId: accountId,
            providerId: providerId,
            regionId: regionId,
            snapshotId: "snap-created",
            diskId: diskId,
            name: snapshotName,
            status: "CREATING",
            sizeGB: nil,
            createdAtProvider: capturedAt,
            rawJSON: nil,
            lastSyncedAt: capturedAt
        )
    }

    func deleteSnapshot(
        credential: CloudProviderCredential,
        regionId: String,
        snapshotId: String
    ) async throws {}

    func attachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String,
        instanceId: String
    ) async throws {}

    func detachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String
    ) async throws {}

    func startInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {}

    func stopInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {}

    func rebootInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {}
}

private func makeServiceTestProfile() -> ServerProfile {
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

private func makeDeploymentProject(serverId: UUID) -> DeploymentProject {
    DeploymentProject(
        id: UUID(),
        serverId: serverId,
        name: "Website",
        repositoryURL: "git@gitlab.com:hhc/site.git",
        branch: "main",
        deployPath: "/srv/site",
        buildCommand: "npm run build",
        restartCommand: "systemctl restart site.service",
        healthCheckCommand: "curl -fsS http://127.0.0.1:3000/health",
        webhookEnabled: false,
        webhookSecretRef: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

private func gitLabPushPayload(branch: String, sshURL: String) -> Data {
    Data("""
    {
      "object_kind": "push",
      "ref": "refs/heads/\(branch)",
      "project": {
        "path_with_namespace": "hhc/site",
        "git_ssh_url": "\(sshURL)",
        "git_http_url": "https://gitlab.com/hhc/site.git",
        "web_url": "https://gitlab.com/hhc/site"
      },
      "repository": {
        "git_ssh_url": "\(sshURL)",
        "homepage": "https://gitlab.com/hhc/site"
      }
    }
    """.utf8)
}

private final class RecordingSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []
    private var responses: [CommandResult]

    init(responses: [CommandResult] = []) {
        self.responses = responses
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if !responses.isEmpty {
            var response = responses.removeFirst()
            response.command = command
            return response
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class DeploymentRunnerMockSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []
    private let failingStep: String?
    private let cancelledStep: String?

    init(failingStep: String? = nil, cancelledStep: String? = nil) {
        self.failingStep = failingStep
        self.cancelledStep = cancelledStep
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        let step = stepName(for: command)
        if step == cancelledStep {
            throw SSHClientError.cancelled
        }
        if step == failingStep {
            return CommandResult(command: command, stdout: "", stderr: "\(step) failed", exitCode: 1, duration: 0.2)
        }
        switch step {
        case "current_commit":
            return CommandResult(command: command, stdout: "abc123\n", stderr: "", exitCode: 0, duration: 0.1)
        case "target_commit":
            return CommandResult(command: command, stdout: "def456\n", stderr: "", exitCode: 0, duration: 0.1)
        case "build":
            return CommandResult(command: command, stdout: "built\n", stderr: "", exitCode: 0, duration: 0.2)
        default:
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0.1)
        }
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}

    private func stepName(for command: String) -> String {
        if command == "command -v git" {
            return "git_check"
        }
        if command.contains("git rev-parse HEAD") && command.contains("if [ -d") {
            return "current_commit"
        }
        if command.contains("git rev-parse HEAD") {
            return "target_commit"
        }
        if command.contains("git clone") || command.contains("git fetch") {
            return "clone_or_fetch"
        }
        if command.contains("git reset --hard") {
            return "checkout"
        }
        if command.contains("npm run build") {
            return "build"
        }
        if command.contains("systemctl restart") {
            return "restart"
        }
        if command.contains("curl -fsS") {
            return "health_check"
        }
        return "prepare"
    }
}

private final class DashboardServiceMockSSHClient: SSHClient, @unchecked Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        let stdout: String
        if command.contains("/etc/os-release") {
            stdout = #"PRETTY_NAME="Ubuntu 24.04.2 LTS""#
        } else if command == "uname -r" {
            stdout = "6.8.0\n"
        } else if command.contains("test -d /proc") || command.contains("systemctl") || command.contains("sftp") {
            stdout = "yes\n"
        } else if command.contains("/proc/loadavg") {
            stdout = "0.10 0.20 0.30 1/100 12345\n"
        } else if command.contains("/proc/meminfo") {
            stdout = "MemTotal: 2048000 kB\nMemAvailable: 1024000 kB\n"
        } else if command.contains("df -kP") {
            stdout = "/dev/vda1 20971520 10485760 10485760 50% /\n"
        } else if command.contains("_NPROCESSORS_ONLN") {
            stdout = "4\n"
        } else if command.contains("/proc/net/dev") {
            stdout = "eth0: 1048576 0 0 0 0 0 0 0 2097152 0 0 0 0 0 0 0\n"
        } else if command.contains("ps -eo stat=") {
            stdout = "total=120 running=2 sleeping=117 stopped=0 zombie=1\n"
        } else {
            stdout = ""
        }
        return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class RecordingSystemdSSHClient: SSHClient, @unchecked Sendable {
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
                ssh.service\tloaded\tactive\trunning\tOpenBSD Secure Shell server
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        if command.hasPrefix("systemctl restart") {
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        if command.hasPrefix("journalctl") {
            return CommandResult(
                command: command,
                stdout: "2026-06-25T16:30:00+08:00 host systemd[1]: Started nginx.service.\n",
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class RecordingCronSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []
    private(set) var installedCrontab = "0 2 * * * /usr/bin/backup\n"

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if command == "crontab -l 2>/dev/null || true" {
            return CommandResult(command: command, stdout: installedCrontab, stderr: "", exitCode: 0, duration: 0)
        }
        if command.contains("crontab -") {
            installedCrontab = Self.decodeCrontab(from: command)
            return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
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

private final class RecordingNginxSSHClient: SSHClient, @unchecked Sendable {
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
        if command.contains("base64 -d > \"$tmp\"") {
            let path = Self.extractShellValue(named: "path", from: command) ?? "/www/server/nginx/conf/nginx.conf"
            let previous = configs[path]
            let next = Self.decodeConfig(from: command)
            let isUpsert = command.contains("__HHC_NGINX_CREATED__")
            let createdNew = previous == nil
            let backup = createdNew ? "" : (Self.extractShellValue(named: "backup", from: command) ?? "\(path).hhc-backup")
            let markers = isUpsert ? "__HHC_NGINX_CREATED__\(createdNew ? 1 : 0)\n__HHC_NGINX_BACKUP__\(backup)\n" : ""
            if testSucceeds {
                configs[path] = next
                return CommandResult(
                    command: command,
                    stdout: markers + "nginx: the configuration file /www/server/nginx/conf/nginx.conf syntax is ok\nnginx: configuration file /www/server/nginx/conf/nginx.conf test is successful\n",
                    stderr: "",
                    exitCode: 0,
                    duration: 0
                )
            }
            configs[path] = previous
            return CommandResult(
                command: command,
                stdout: markers + "nginx: [emerg] invalid number of arguments in \"server\" directive\nnginx: configuration file /www/server/nginx/conf/nginx.conf test failed\n",
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

private final class RecordingFirewallSSHClient: SSHClient, @unchecked Sendable {
    var backend: FirewallBackend = .firewalld
    var firewalldRunning = true
    private(set) var commands: [String] = []

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        switch backend {
        case .firewalld:
            return CommandResult(
                command: command,
                stdout: firewalldRunning ? """
                __HHC_FIREWALL_BACKEND__
                firewalld
                __HHC_FIREWALL_STATUS__
                running
                __HHC_FIREWALL_RULES__
                public
                  services: ssh http https
                """ : """
                __HHC_FIREWALL_BACKEND__
                firewalld
                __HHC_FIREWALL_STATUS__
                not running
                __HHC_FIREWALL_RULES__
                FirewallD is not running
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        case .ufw:
            return CommandResult(
                command: command,
                stdout: """
                __HHC_FIREWALL_BACKEND__
                ufw
                __HHC_FIREWALL_STATUS__
                Status: active
                __HHC_FIREWALL_RULES__
                Status: active
                22/tcp ALLOW Anywhere
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        case .nft:
            return CommandResult(
                command: command,
                stdout: """
                __HHC_FIREWALL_BACKEND__
                nft
                __HHC_FIREWALL_STATUS__
                installed
                __HHC_FIREWALL_RULES__
                table inet filter { chain input { type filter hook input priority 0; } }
                """,
                stderr: "",
                exitCode: 0,
                duration: 0
            )
        case .iptables:
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
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class RecordingEnvironmentSSHClient: SSHClient, @unchecked Sendable {
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

private final class RecordingTransferClient: RemoteFileTransferClient, @unchecked Sendable {
    private(set) var uploads: [(localURL: URL, remotePath: String)] = []
    private(set) var downloads: [(remotePath: String, localURL: URL)] = []

    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        uploads.append((localURL, remotePath))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: nil,
            duration: 0
        )
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        downloads.append((remotePath, localURL))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: nil,
            duration: 0
        )
    }
}

private final class MockTencentCloudTransport: TencentCloudHTTPTransport, @unchecked Sendable {
    private var responses: [String]
    private(set) var requests: [URLRequest] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = responses.isEmpty ? #"{"Response":{"RequestId":"empty"}}"# : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }
}

private final class MockAlibabaCloudTransport: AlibabaCloudHTTPTransport, @unchecked Sendable {
    private var responses: [String]
    private(set) var requests: [URLRequest] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = responses.isEmpty ? #"{"RequestId":"empty"}"# : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }
}

private final class MockHuaweiCloudTransport: HuaweiCloudHTTPTransport, @unchecked Sendable {
    private var responses: [String]
    private(set) var requests: [URLRequest] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = responses.isEmpty ? #"{"servers":[]}"# : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }
}

private extension URLRequest {
    var jsonBody: [String: Any]? {
        guard let httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
    }

    func queryValue(_ name: String) -> String? {
        guard let url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}
