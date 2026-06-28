import XCTest
@testable import HHCServerManager

final class ServerManagementServiceTests: XCTestCase {
    @MainActor
    func testAppStateStartsWithEmptyServerListAndNoWorkspaceSelection() throws {
        let harness = try AppStateHarness()

        XCTAssertTrue(harness.appState.servers.isEmpty)
        XCTAssertNil(harness.appState.selectedServerId)
        XCTAssertNil(harness.appState.selectedServer)
        XCTAssertNil(harness.appState.startupError)
    }

    @MainActor
    func testAppStateOpensClosesAndSwitchesWorkspaceSelection() throws {
        let harness = try AppStateHarness()
        let primary = try harness.appState.serverManagementService.createServer(
            name: "Tencent Production",
            host: "prod.example.internal",
            port: 22,
            username: "root",
            groupName: "prod",
            authType: .password,
            credential: .password("secret-1")
        )
        let secondary = try harness.appState.serverManagementService.createServer(
            name: "Tencent Staging",
            host: "staging.example.internal",
            port: 22,
            username: "ubuntu",
            groupName: "staging",
            authType: .password,
            credential: .password("secret-2")
        )

        harness.appState.reloadServers()

        XCTAssertEqual(Set(harness.appState.servers.map(\.id)), Set([primary.id, secondary.id]))

        harness.appState.openWorkspace(for: primary)
        XCTAssertEqual(harness.appState.selectedServer?.id, primary.id)

        harness.appState.selectedServerId = secondary.id
        XCTAssertEqual(harness.appState.selectedServer?.id, secondary.id)

        harness.appState.closeWorkspace()
        XCTAssertNil(harness.appState.selectedServerId)
        XCTAssertNil(harness.appState.selectedServer)
    }

    @MainActor
    func testAppStateReloadClearsWorkspaceSelectionWhenSelectedServerWasRemoved() throws {
        let harness = try AppStateHarness()
        let profile = try harness.appState.serverManagementService.createServer(
            name: "Removed Elsewhere",
            host: "removed.example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )

        harness.appState.reloadServers()
        harness.appState.openWorkspace(for: profile)
        try harness.repository.deleteServer(id: profile.id)

        harness.appState.reloadServers()

        XCTAssertTrue(harness.appState.servers.isEmpty)
        XCTAssertNil(harness.appState.selectedServerId)
        XCTAssertNil(harness.appState.selectedServer)
    }

    @MainActor
    func testAppStateReloadsPersistedServerProfilesAfterDatabaseReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HHCServerManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("HHCServerManager.sqlite")
        let keychainServiceName = "me.hhc.HHCServerManagerTests.persisted-app-state.\(UUID().uuidString)"
        var keychainRef: String?
        defer {
            if let keychainRef {
                KeychainService(serviceName: keychainServiceName).deleteCredentials(keychainRef: keychainRef)
            }
        }

        do {
            let database = try AppDatabase(url: databaseURL)
            let repository = ServerRepository(database: database)
            let keychain = KeychainService(serviceName: keychainServiceName)
            let appState = AppState(repository: repository, keychain: keychain)
            let profile = try appState.serverManagementService.createServer(
                name: "Persistent Server",
                host: "persistent.example.internal",
                port: 2222,
                username: "deploy",
                groupName: "production",
                authType: .password,
                credential: .password("persisted-secret")
            )
            keychainRef = profile.keychainRef
            appState.reloadServers()

            XCTAssertEqual(appState.servers.map(\.id), [profile.id])
            XCTAssertEqual(try keychain.readPassword(keychainRef: profile.keychainRef), "persisted-secret")
        }

        do {
            let reopenedDatabase = try AppDatabase(url: databaseURL)
            let reopenedRepository = ServerRepository(database: reopenedDatabase)
            let reopenedKeychain = KeychainService(serviceName: keychainServiceName)
            let reopenedAppState = AppState(repository: reopenedRepository, keychain: reopenedKeychain)
            let profile = try XCTUnwrap(reopenedAppState.servers.first)

            XCTAssertEqual(reopenedAppState.servers.count, 1)
            XCTAssertEqual(profile.name, "Persistent Server")
            XCTAssertEqual(profile.host, "persistent.example.internal")
            XCTAssertEqual(profile.port, 2222)
            XCTAssertEqual(profile.username, "deploy")
            XCTAssertEqual(profile.groupName, "production")
            XCTAssertEqual(profile.authType, .password)
            XCTAssertNil(reopenedAppState.selectedServerId)
            XCTAssertEqual(try reopenedKeychain.readPassword(keychainRef: profile.keychainRef), "persisted-secret")
        }
    }

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
        XCTAssertEqual(servers.first?.serverKind, .manualSSH)
        XCTAssertEqual(try harness.keychain.readPassword(keychainRef: profile.keychainRef), "secret")
    }

    func testCreateServerRemovesNewCredentialWhenDatabaseWriteFails() throws {
        let database = try AppDatabase.inMemory()
        let repository = ServerRepository(database: database)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.tests.db-failure.\(UUID().uuidString)")
        let fixedID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let service = ServerManagementService(
            repository: repository,
            keychain: keychain,
            makeUUID: { fixedID }
        )
        let keychainRef = "server_\(fixedID.uuidString)"
        defer { keychain.deleteCredentials(keychainRef: keychainRef) }

        try database.execute("DROP TABLE server_profiles")

        XCTAssertThrowsError(try service.createServer(
            name: "Broken DB",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        ))
        XCTAssertNil(try keychain.readPassword(keychainRef: keychainRef))
    }

    func testCreateServerDoesNotPersistProfileWhenKeychainWriteFails() throws {
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = FailingServerCredentialStore()
        let service = ServerManagementService(repository: repository, keychain: keychain)

        XCTAssertThrowsError(try service.createServer(
            name: "No Credential",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )) { error in
            XCTAssertEqual(error as? FailingServerCredentialStore.Error, .writeFailed)
        }
        XCTAssertTrue(try repository.fetchServers().isEmpty)
        XCTAssertEqual(keychain.deletedCredentialRefs.count, 1)
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

    @MainActor
    func testAppStateDeletingSelectedServerClearsSelectionConnectionAndCredential() throws {
        let database = try AppDatabase.inMemory()
        let repository = ServerRepository(database: database)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.app-state.\(UUID().uuidString)")
        let appState = AppState(repository: repository, keychain: keychain)
        let profile = try appState.serverManagementService.createServer(
            name: "Selected",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        appState.reloadServers()
        appState.openWorkspace(for: profile)
        appState.setConnectionState(.connected, for: profile)

        appState.delete(profile)

        XCTAssertNil(appState.selectedServerId)
        XCTAssertNil(appState.selectedServer)
        XCTAssertEqual(appState.connectionState(for: profile), .disconnected)
        XCTAssertTrue(appState.servers.isEmpty)
        XCTAssertTrue(try repository.fetchServers().isEmpty)
        XCTAssertNil(try keychain.readPassword(keychainRef: profile.keychainRef))
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

    func testUpdateServerRestoresOriginalCredentialWhenDatabaseWriteFails() throws {
        let database = try AppDatabase.inMemory()
        let repository = ServerRepository(database: database)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.tests.update-db-failure.\(UUID().uuidString)")
        let service = ServerManagementService(repository: repository, keychain: keychain)
        let profile = try service.createServer(
            name: "Tencent",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("original")
        )
        defer { keychain.deleteCredentials(keychainRef: profile.keychainRef) }

        try database.execute("DROP TABLE server_profiles")

        XCTAssertThrowsError(try service.updateServer(
            profile,
            name: "Renamed",
            host: "new.example",
            port: 2222,
            username: "ubuntu",
            groupName: nil,
            authType: .password,
            credentialUpdate: .replace(.password("new"))
        ))
        XCTAssertEqual(try keychain.readPassword(keychainRef: profile.keychainRef), "original")
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

    func testCloudResourceActionPolicyUsesProviderSpecificStatuses() {
        XCTAssertTrue(CloudResourceActionPolicy.canPerformPowerAction(
            providerId: .tencentCloud,
            action: .start,
            status: " STOPPED "
        ))
        XCTAssertTrue(CloudResourceActionPolicy.canPerformPowerAction(
            providerId: .alibabaCloud,
            action: .reboot,
            status: "Running"
        ))
        XCTAssertTrue(CloudResourceActionPolicy.canPerformPowerAction(
            providerId: .huaweiCloud,
            action: .start,
            status: "SHUTOFF"
        ))
        XCTAssertTrue(CloudResourceActionPolicy.canPerformPowerAction(
            providerId: .huaweiCloud,
            action: .stop,
            status: "ACTIVE"
        ))
        XCTAssertFalse(CloudResourceActionPolicy.canPerformPowerAction(
            providerId: .alibabaCloud,
            action: .stop,
            status: "Stopped"
        ))

        XCTAssertTrue(CloudResourceActionPolicy.canDeleteSnapshot(providerId: .tencentCloud, status: "NORMAL"))
        XCTAssertTrue(CloudResourceActionPolicy.canDeleteSnapshot(providerId: .alibabaCloud, status: "accomplished"))
        XCTAssertTrue(CloudResourceActionPolicy.canDeleteSnapshot(providerId: .huaweiCloud, status: "available"))
        XCTAssertFalse(CloudResourceActionPolicy.canDeleteSnapshot(providerId: .huaweiCloud, status: "creating"))

        XCTAssertTrue(CloudResourceActionPolicy.canAttachDisk(providerId: .tencentCloud, status: "DETACHED"))
        XCTAssertTrue(CloudResourceActionPolicy.canAttachDisk(providerId: .alibabaCloud, status: "Available"))
        XCTAssertTrue(CloudResourceActionPolicy.canAttachDisk(providerId: .huaweiCloud, status: "available"))
        XCTAssertTrue(CloudResourceActionPolicy.canAttachDisk(providerId: .huaweiCloud, status: nil))
        XCTAssertTrue(CloudResourceActionPolicy.canDetachDisk(providerId: .tencentCloud, status: "ATTACHED"))
        XCTAssertTrue(CloudResourceActionPolicy.canDetachDisk(providerId: .alibabaCloud, status: "In_use"))
        XCTAssertTrue(CloudResourceActionPolicy.canDetachDisk(providerId: .huaweiCloud, status: "in-use"))
        XCTAssertFalse(CloudResourceActionPolicy.canDetachDisk(providerId: .huaweiCloud, status: nil))
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
                    securityGroupIds: [],
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

    func testCloudProviderRequestLimiterCapsConcurrentOperations() async throws {
        let limiter = CloudProviderRequestLimiter(maxConcurrentRequests: 2)
        let probe = CloudProviderRequestLimiterProbe()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try await CloudProviderRequestRunner.run(timeout: 1, limiter: limiter) {
                        await probe.enter()
                        try await Task.sleep(nanoseconds: 20_000_000)
                        await probe.leave()
                    }
                }
            }

            try await group.waitForAll()
        }

        let snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.maxRunning, 2)
        XCTAssertEqual(snapshot.running, 0)
    }

    func testCloudProviderRequestLimiterCancelsWaitingOperationWithoutLeakingSlot() async throws {
        let limiter = CloudProviderRequestLimiter(maxConcurrentRequests: 1)
        let probe = CloudProviderRequestLimiterProbe()

        let firstTask = Task {
            try await CloudProviderRequestRunner.run(timeout: 1, limiter: limiter) {
                await probe.enter()
                try await Task.sleep(nanoseconds: 80_000_000)
                await probe.leave()
            }
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        let waitingTask = Task {
            try await CloudProviderRequestRunner.run(timeout: 1, limiter: limiter) {
                await probe.enter()
                await probe.leave()
            }
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        waitingTask.cancel()

        do {
            try await waitingTask.value
            XCTFail("Expected queued cloud provider request to cancel.")
        } catch {
            XCTAssertTrue(error is CancellationError || error as? CloudProviderError == .cancelled)
        }

        try await firstTask.value
        let value = try await CloudProviderRequestRunner.withTimeout(0.2) {
            try await CloudProviderRequestRunner.run(timeout: 1, limiter: limiter) {
                "ok"
            }
        }

        XCTAssertEqual(value, "ok")
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

    func testDeploymentProjectExtractsReferencedSystemdUnits() {
        XCTAssertEqual(
            DeploymentProject.referencedSystemdUnitNames(
                in: #"sudo systemctl restart "api.service" && systemctl --user reload worker && systemctl restart -- api.service"#
            ),
            ["api.service", "worker.service"]
        )
        XCTAssertEqual(
            DeploymentProject.referencedSystemdUnitNames(
                in: "cd /srv/site && systemctl --no-block try-restart queue@prod.service"
            ),
            ["queue@prod.service"]
        )
        XCTAssertEqual(DeploymentProject.referencedSystemdUnitNames(in: "pm2 reload ecosystem.config.js"), [])
        XCTAssertEqual(DeploymentProject.referencedSystemdUnitNames(in: nil), [])
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

    func testGitLabInstallerBuildsLinuxPackageInstallCommand() throws {
        let draft = GitLabInstallDraft(externalURL: "http://gitlab.example.internal")

        let command = try GitLabInstaller.installCommand(for: draft)

        XCTAssertTrue(command.contains("package_name='gitlab-ce'"))
        XCTAssertTrue(command.contains("env EXTERNAL_URL=\"$external_url\" apt-get install -y \"$package_name\""))
        XCTAssertTrue(command.contains("script.deb.sh"))
        XCTAssertTrue(command.contains("script.rpm.sh"))
        XCTAssertTrue(command.contains("gitlab-ctl status"))
    }

    func testGitLabInstallerRejectsUnsafeExternalURL() {
        let draft = GitLabInstallDraft(externalURL: "https://user:pass@gitlab.example.internal")

        XCTAssertThrowsError(try GitLabInstaller.installCommand(for: draft)) { error in
            XCTAssertEqual(error as? GitLabServiceError, .invalidExternalURL)
        }
    }

    func testGitLabPreflightParserBuildsBlockingAndWarningChecks() {
        let output = """
        __HHC_GITLAB_OS_ID__ubuntu
        __HHC_GITLAB_OS_VERSION__24.04
        __HHC_GITLAB_OS_PRETTY__Ubuntu 24.04 LTS
        __HHC_GITLAB_PACKAGE_MANAGER__apt-get
        __HHC_GITLAB_IS_ROOT__no
        __HHC_GITLAB_SUDO_NOPASS__yes
        __HHC_GITLAB_MEM_KB__16777216
        __HHC_GITLAB_CPU_COUNT__2
        __HHC_GITLAB_DISK_KB__80000000
        __HHC_GITLAB_CURL__no
        __HHC_GITLAB_CA_CERTS__yes
        __HHC_GITLAB_VERSION__
        __HHC_GITLAB_PORT_80__used
        __HHC_GITLAB_PORT_443__free
        __HHC_GITLAB_PORT_22__used
        """

        let report = GitLabInstaller.parsePreflight(
            output: output,
            draft: GitLabInstallDraft(externalURL: "http://gitlab.example.internal"),
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.detectedOS, "Ubuntu 24.04 LTS")
        XCTAssertTrue(report.checks.contains { $0.id == "port-80" && $0.status == .warning })
        XCTAssertTrue(report.checks.contains { $0.id == "curl" && $0.status == .warning })
    }

    func testGitLabPreflightParserFailsWhenSudoAndMemoryAreMissing() {
        let output = """
        __HHC_GITLAB_OS_ID__ubuntu
        __HHC_GITLAB_OS_PRETTY__Ubuntu 24.04 LTS
        __HHC_GITLAB_PACKAGE_MANAGER__apt-get
        __HHC_GITLAB_IS_ROOT__no
        __HHC_GITLAB_SUDO_NOPASS__no
        __HHC_GITLAB_MEM_KB__1024
        __HHC_GITLAB_CPU_COUNT__1
        __HHC_GITLAB_DISK_KB__1024
        __HHC_GITLAB_CURL__yes
        __HHC_GITLAB_CA_CERTS__yes
        __HHC_GITLAB_PORT_80__free
        __HHC_GITLAB_PORT_443__free
        __HHC_GITLAB_PORT_22__used
        """

        let report = GitLabInstaller.parsePreflight(
            output: output,
            draft: GitLabInstallDraft(externalURL: "http://gitlab.example.internal")
        )

        XCTAssertFalse(report.isReady)
        XCTAssertTrue(report.checks.contains { $0.id == "privileges" && $0.status == .failed })
        XCTAssertTrue(report.checks.contains { $0.id == "memory" && $0.status == .failed })
        XCTAssertTrue(report.checks.contains { $0.id == "disk" && $0.status == .failed })
    }

    func testGitLabStatusParserReadsStatusAndRedactsLogs() {
        let logs = Data("token=super-secret\nGitLab started\n".utf8).base64EncodedString()
        let status = Data("run: gitaly: (pid 10) 12s\n".utf8).base64EncodedString()
        let output = """
        __HHC_GITLAB_STATUS_INSTALLED__yes
        __HHC_GITLAB_STATUS_VERSION__18.0.1
        __HHC_GITLAB_STATUS_EXTERNAL_URL__http://gitlab.example.internal
        __HHC_GITLAB_STATUS_REACHABLE__yes
        __HHC_GITLAB_STATUS_TEXT__\(status)
        __HHC_GITLAB_STATUS_LOGS__\(logs)
        """

        let snapshot = GitLabManager.parseStatus(output: output, capturedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertTrue(snapshot.installed)
        XCTAssertEqual(snapshot.version, "18.0.1")
        XCTAssertEqual(snapshot.status, "running")
        XCTAssertEqual(snapshot.externalURL, "http://gitlab.example.internal")
        XCTAssertTrue(snapshot.webReachable)
        XCTAssertTrue(snapshot.recentLogs.contains("token=<redacted>"))
        XCTAssertFalse(snapshot.recentLogs.contains("super-secret"))
    }

    func testGiteaInstallerBuildsLightweightInstallCommand() throws {
        let draft = GiteaInstallDraft(
            externalURL: "http://git.example.internal:3000",
            installPath: "/usr/local/bin/gitea",
            dataPath: "/var/lib/gitea",
            serviceName: "gitea",
            listenPort: 3000
        )

        let command = try GiteaInstaller.installCommand(for: draft)

        XCTAssertTrue(command.contains("api.github.com/repos/go-gitea/gitea/releases/latest"))
        XCTAssertTrue(command.contains("dl.gitea.com/gitea"))
        XCTAssertTrue(command.contains("/etc/gitea/app.ini"))
        XCTAssertTrue(command.contains("HTTP_PORT = $listen_port"))
        XCTAssertTrue(command.contains("DB_TYPE = sqlite3"))
        XCTAssertTrue(command.contains("systemctl enable --now \"${service_name}.service\""))
    }

    func testGiteaInstallerRejectsUnsafeExternalURL() {
        let draft = GiteaInstallDraft(externalURL: "https://user:pass@gitea.example.internal")

        XCTAssertThrowsError(try GiteaInstaller.installCommand(for: draft)) { error in
            XCTAssertEqual(error as? GiteaInstallError, .invalidExternalURL)
        }
    }

    func testGiteaInstallerParsesInstallResultMarkers() {
        let draft = GiteaInstallDraft(externalURL: "http://fallback.example.internal:3000")
        let output = """
        __HHC_GITEA_VERSION__1.24.2
        __HHC_GITEA_STATUS__active
        __HHC_GITEA_URL__http://git.example.internal:3000
        """

        let result = GiteaInstaller.parseInstallResult(output: output, draft: draft)

        XCTAssertEqual(result.version, "1.24.2")
        XCTAssertEqual(result.status, "active")
        XCTAssertEqual(result.externalURL, "http://git.example.internal:3000")
    }

    func testGiteaAPIClientLoadsNativeSnapshotFromOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/user/repos": #"""
            [{"id":1,"name":"app","full_name":"team/app","owner":{"login":"alice"},"private":true,"archived":false,"default_branch":"main","description":"backend","html_url":"http://git/team/app","updated_at":"2026-06-28T01:00:00Z","stars_count":2,"forks_count":1}]
            """#,
            "/api/v1/admin/users": #"""
            [{"id":7,"login":"alice","full_name":"Alice","email":"alice@example.com","is_admin":true,"active":true,"last_login":"2026-06-28T02:00:00Z"}]
            """#,
            "/api/v1/user": #"""
            {"id":7,"login":"alice","full_name":"Alice","email":"alice@example.com","is_admin":true,"active":true,"last_login":"2026-06-28T02:00:00Z"}
            """#,
            "/api/v1/user/keys": #"""
            [{"id":33,"title":"deploy mac","key":"ssh-ed25519 AAAATEST deploy@example.com","fingerprint":"SHA256:test","url":"http://git/api/v1/user/keys/33","read_only":false,"created_at":"2026-06-28T01:30:00Z"}]
            """#,
            "/api/v1/users/alice/tokens": #"""
            [{"id":44,"name":"hhc mac","scopes":["read:repository","read:user"],"sha1":"secret-token","token_last_eight":"abcd1234","created_at":"2026-06-28T01:40:00Z","last_used_at":"2026-06-28T02:40:00Z"}]
            """#,
            "/api/v1/packages/alice": #"""
            [{"id":55,"owner":{"login":"alice"},"name":"@hhc/app","type":"npm","version":"1.0.0","repository":{"full_name":"team/app"},"html_url":"http://git/alice/-/packages/npm/@hhc/app/1.0.0","created_at":"2026-06-28T04:00:00Z"}]
            """#,
            "/api/v1/user/orgs": #"""
            [{"id":3,"username":"team","full_name":"Team","description":"core team","website":"https://example.com"}]
            """#,
            "/api/v1/packages/team": #"""
            [{"id":56,"owner":{"username":"team"},"name":"backend-sdk","type":"pub","version":"0.2.0","repository":{"full_name":"team/app"},"created_at":"2026-06-28T04:30:00Z"}]
            """#,
            "/api/v1/version": #"""
            {"version":"1.24.2"}
            """#,
            "/api/v1/admin/cron": #"""
            [{"name":"repo_health_check","schedule":"@every 24h","exec_times":8,"prev":"2026-06-28T00:00:00Z","next":"2026-06-29T00:00:00Z"}]
            """#,
            "/api/v1/orgs/team/teams": #"""
            [{"id":12,"name":"Developers","description":"Ship code","organization":{"username":"team"},"permission":"write","includes_all_repositories":true,"can_create_org_repo":true,"units":["repo.code","repo.issues"]}]
            """#,
            "/api/v1/teams/12/members": #"""
            [{"id":7,"login":"alice","full_name":"Alice","email":"alice@example.com","is_admin":true,"active":true,"last_login":"2026-06-28T02:00:00Z"}]
            """#,
            "/api/v1/teams/12/repos": #"""
            [{"id":1,"name":"app","full_name":"team/app","owner":{"login":"team"},"private":true,"archived":false,"default_branch":"main","updated_at":"2026-06-28T01:00:00Z"}]
            """#,
            "/api/v1/repos/issues/search": #"""
            [{"id":20,"number":5,"title":"Fix deploy","state":"open","repository":{"full_name":"team/app"},"user":{"login":"alice"},"assignees":[{"login":"deploybot"}],"labels":[{"name":"bug"},{"name":"deploy"}],"milestone":{"title":"v1.0"},"html_url":"http://git/team/app/issues/5","updated_at":"2026-06-28T03:00:00Z"}]
            """#,
        ])
        let client = GiteaAPIClient(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let snapshot = try await client.loadSnapshot(baseURL: "http://git.example.com", token: "gitea-token")
        let requests = transport.snapshotRequests()

        XCTAssertEqual(snapshot.repositories.first?.fullName, "team/app")
        XCTAssertEqual(snapshot.repositories.first?.owner, "alice")
        XCTAssertEqual(snapshot.repositories.first?.isArchived, false)
        XCTAssertEqual(snapshot.users.first?.username, "alice")
        XCTAssertEqual(snapshot.organizations.first?.username, "team")
        XCTAssertEqual(snapshot.teams.first?.name, "Developers")
        XCTAssertEqual(snapshot.teams.first?.organization, "team")
        XCTAssertEqual(snapshot.teamMembers.first?.teamId, 12)
        XCTAssertEqual(snapshot.teamMembers.first?.username, "alice")
        XCTAssertEqual(snapshot.teamRepositories.first?.teamId, 12)
        XCTAssertEqual(snapshot.teamRepositories.first?.fullName, "team/app")
        XCTAssertEqual(snapshot.keys.first?.title, "deploy mac")
        XCTAssertEqual(snapshot.keys.first?.fingerprint, "SHA256:test")
        XCTAssertEqual(snapshot.tokens.first?.username, "alice")
        XCTAssertEqual(snapshot.tokens.first?.name, "hhc mac")
        XCTAssertEqual(snapshot.tokens.first?.tokenLastEight, "abcd1234")
        XCTAssertEqual(snapshot.packages.count, 2)
        XCTAssertEqual(snapshot.packages.first?.owner, "alice")
        XCTAssertEqual(snapshot.packages.first?.name, "@hhc/app")
        XCTAssertEqual(snapshot.packages.first?.type, "npm")
        XCTAssertEqual(snapshot.packages.first?.repository, "team/app")
        XCTAssertEqual(snapshot.adminOverview.version, "1.24.2")
        XCTAssertEqual(snapshot.adminOverview.cronTasks.first?.name, "repo_health_check")
        XCTAssertEqual(snapshot.adminOverview.cronTasks.first?.schedule, "@every 24h")
        XCTAssertEqual(snapshot.adminOverview.cronTasks.first?.execTimes, 8)
        XCTAssertEqual(snapshot.issues.first?.repository, "team/app")
        XCTAssertEqual(snapshot.issues.first?.assignees, ["deploybot"])
        XCTAssertEqual(snapshot.issues.first?.labels, ["bug", "deploy"])
        XCTAssertEqual(snapshot.issues.first?.milestone, "v1.0")
        XCTAssertEqual(snapshot.issues.first?.htmlURL, "http://git/team/app/issues/5")
        XCTAssertEqual(snapshot.pullRequests.first?.title, "Fix deploy")
        XCTAssertEqual(snapshot.pullRequests.first?.assignees, ["deploybot"])
        XCTAssertEqual(snapshot.pullRequests.first?.labels, ["bug", "deploy"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "token gitea-token" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/user/repos" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/user/keys" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/users/alice/tokens" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/packages/alice" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/packages/team" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/version" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/admin/cron" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/orgs/team/teams" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/teams/12/members" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v1/teams/12/repos" })
    }

    func testGitLabAPIClientLoadsNativeSnapshotFromOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects": #"""
            [{"id":11,"name":"app","path_with_namespace":"team/app","visibility":"private","default_branch":"main","web_url":"http://gitlab/team/app","last_activity_at":"2026-06-28T01:00:00Z","archived":false}]
            """#,
            "/api/v4/groups": #"""
            [{"id":2,"name":"team","full_path":"team","visibility":"private","web_url":"http://gitlab/groups/team"}]
            """#,
            "/api/v4/users": #"""
            [{"id":99,"username":"deploybot","name":"Deploy Bot","state":"active","web_url":"http://gitlab/deploybot","is_admin":false}]
            """#,
            "/api/v4/projects/11/members/all": #"""
            [{"id":99,"username":"deploybot","name":"Deploy Bot","state":"active","web_url":"http://gitlab/deploybot","access_level":30,"expires_at":"2026-12-31","created_at":"2026-06-28T00:00:00Z"}]
            """#,
            "/api/v4/groups/2/members/all": #"""
            [{"id":99,"username":"deploybot","name":"Deploy Bot","state":"active","web_url":"http://gitlab/deploybot","access_level":40,"expires_at":null,"created_at":"2026-06-28T00:00:00Z"}]
            """#,
            "/api/v4/issues": #"""
            [{"id":31,"iid":8,"title":"Fix deploy","state":"opened","project_id":11,"author":{"username":"alice"},"assignees":[{"username":"deploybot"}],"labels":["bug","deploy"],"milestone":{"title":"v1.0"},"web_url":"http://gitlab/team/app/-/issues/8","updated_at":"2026-06-28T02:00:00Z"}]
            """#,
            "/api/v4/merge_requests": #"""
            [{"id":41,"iid":4,"title":"Deploy MR","state":"opened","source_branch":"feature","target_branch":"main","project_id":11,"author":{"username":"alice"},"assignees":[{"username":"deploybot"}],"reviewers":[{"username":"reviewer"}],"labels":["deploy"],"milestone":{"title":"v1.0"},"web_url":"http://gitlab/team/app/-/merge_requests/4","updated_at":"2026-06-28T03:00:00Z"}]
            """#,
            "/api/v4/projects/11/pipelines": #"""
            [{"id":51,"ref":"main","sha":"abcdef123456","status":"success","web_url":"http://gitlab/team/app/-/pipelines/51","updated_at":"2026-06-28T04:00:00Z"}]
            """#,
            "/api/v4/projects/11/jobs": #"""
            [{"id":71,"name":"deploy","stage":"deploy","ref":"main","status":"manual","web_url":"http://gitlab/team/app/-/jobs/71","duration":12.3,"started_at":"2026-06-28T04:30:00Z","finished_at":null}]
            """#,
            "/api/v4/projects/11/packages": #"""
            [{"id":81,"name":"team-app","version":"1.0.0","package_type":"npm","status":"default","created_at":"2026-06-28T04:40:00Z","updated_at":"2026-06-28T04:45:00Z"}]
            """#,
            "/api/v4/projects/11/variables": #"""
            [{"key":"DEPLOY_ENV","variable_type":"env_var","environment_scope":"production","protected":true,"masked":true,"raw":false,"description":"Deploy target"}]
            """#,
            "/api/v4/projects/11/deploy_keys": #"""
            [{"id":61,"title":"deploy mac","key":"ssh-ed25519 AAAATEST deploy@example.com","fingerprint":"SHA256:test","can_push":true,"created_at":"2026-06-28T05:00:00Z","expires_at":"2027-06-28"}]
            """#,
            "/api/v4/projects/11/deploy_tokens": #"""
            [{"id":62,"name":"registry deploy","username":"gitlab+deploy-token-62","scopes":["read_repository","read_package_registry"],"revoked":false,"expired":false,"active":true,"created_at":"2026-06-28T05:10:00Z","expires_at":"2027-06-28"}]
            """#,
            "/api/v4/projects/11/repository/branches": #"""
            [{"name":"main","merged":false,"protected":true,"default":true,"can_push":false,"web_url":"http://gitlab/team/app/-/tree/main","commit":{"short_id":"abcdef12","title":"Initial commit","committed_date":"2026-06-28T05:30:00Z"}}]
            """#,
            "/api/v4/projects/11/repository/tags": #"""
            [{"name":"v1.0.0","message":"release","target":"abcdef123456","protected":false,"commit":{"short_id":"abcdef12","title":"Initial commit"},"created_at":"2026-06-28T06:00:00Z"}]
            """#,
            "/api/v4/runners/all": #"""
            [{"id":91,"description":"shell-runner","name":"runner-1","status":"online","runner_type":"instance_type","is_shared":true,"active":true,"paused":false,"online":true,"tag_list":["shell","deploy"],"version":"18.0.0","contacted_at":"2026-06-28T06:30:00Z"}]
            """#,
            "/api/v4/metadata": #"""
            {"version":"18.0.1","revision":"abc123","enterprise":false}
            """#,
            "/api/v4/application/statistics": #"""
            {"users":12,"active_users":9,"projects":5,"groups":2,"issues":20,"merge_requests":7}
            """#,
            "/api/v4/license": #"""
            {"plan":"default","starts_at":"2026-01-01","expires_at":null,"expired":false,"user_limit":null,"active_users":9}
            """#,
            "/-/health": "GitLab OK",
            "/-/readiness": "GitLab OK",
            "/-/liveness": "GitLab OK",
        ])
        let client = GitLabAPIClient(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let snapshot = try await client.loadSnapshot(baseURL: "http://gitlab.example.com", token: "gitlab-token")
        let requests = transport.snapshotRequests()

        XCTAssertEqual(snapshot.projects.first?.pathWithNamespace, "team/app")
        XCTAssertEqual(snapshot.groups.first?.fullPath, "team")
        XCTAssertEqual(snapshot.users.first?.username, "deploybot")
        XCTAssertEqual(snapshot.members.count, 2)
        XCTAssertEqual(snapshot.members.first?.scope, .project)
        XCTAssertEqual(snapshot.members.first?.targetId, 11)
        XCTAssertEqual(snapshot.members.first?.userId, 99)
        XCTAssertEqual(snapshot.members.last?.scope, .group)
        XCTAssertEqual(snapshot.members.last?.targetId, 2)
        XCTAssertEqual(snapshot.issues.first?.iid, 8)
        XCTAssertEqual(snapshot.issues.first?.author, "alice")
        XCTAssertEqual(snapshot.issues.first?.assignees, ["deploybot"])
        XCTAssertEqual(snapshot.issues.first?.labels, ["bug", "deploy"])
        XCTAssertEqual(snapshot.issues.first?.milestone, "v1.0")
        XCTAssertEqual(snapshot.mergeRequests.first?.sourceBranch, "feature")
        XCTAssertEqual(snapshot.mergeRequests.first?.author, "alice")
        XCTAssertEqual(snapshot.mergeRequests.first?.assignees, ["deploybot"])
        XCTAssertEqual(snapshot.mergeRequests.first?.reviewers, ["reviewer"])
        XCTAssertEqual(snapshot.mergeRequests.first?.labels, ["deploy"])
        XCTAssertEqual(snapshot.mergeRequests.first?.milestone, "v1.0")
        XCTAssertEqual(snapshot.pipelines.first?.projectId, 11)
        XCTAssertEqual(snapshot.pipelines.first?.status, "success")
        XCTAssertEqual(snapshot.jobs.first?.projectId, 11)
        XCTAssertEqual(snapshot.jobs.first?.name, "deploy")
        XCTAssertEqual(snapshot.jobs.first?.status, "manual")
        XCTAssertEqual(snapshot.packages.first?.projectId, 11)
        XCTAssertEqual(snapshot.packages.first?.name, "team-app")
        XCTAssertEqual(snapshot.packages.first?.packageType, "npm")
        XCTAssertEqual(snapshot.runners.first?.description, "shell-runner")
        XCTAssertEqual(snapshot.runners.first?.tagList, ["shell", "deploy"])
        XCTAssertEqual(snapshot.variables.first?.projectId, 11)
        XCTAssertEqual(snapshot.variables.first?.key, "DEPLOY_ENV")
        XCTAssertEqual(snapshot.variables.first?.environmentScope, "production")
        XCTAssertEqual(snapshot.variables.first?.masked, true)
        XCTAssertEqual(snapshot.deployKeys.first?.projectId, 11)
        XCTAssertEqual(snapshot.deployKeys.first?.title, "deploy mac")
        XCTAssertEqual(snapshot.deployKeys.first?.canPush, true)
        XCTAssertEqual(snapshot.deployTokens.first?.projectId, 11)
        XCTAssertEqual(snapshot.deployTokens.first?.name, "registry deploy")
        XCTAssertEqual(snapshot.deployTokens.first?.scopes, ["read_repository", "read_package_registry"])
        XCTAssertEqual(snapshot.branches.first?.projectId, 11)
        XCTAssertEqual(snapshot.branches.first?.name, "main")
        XCTAssertEqual(snapshot.branches.first?.isDefault, true)
        XCTAssertEqual(snapshot.branches.first?.protected, true)
        XCTAssertEqual(snapshot.tags.first?.projectId, 11)
        XCTAssertEqual(snapshot.tags.first?.name, "v1.0.0")
        XCTAssertEqual(snapshot.tags.first?.message, "release")
        XCTAssertEqual(snapshot.adminOverview.version, "18.0.1")
        XCTAssertEqual(snapshot.adminOverview.revision, "abc123")
        XCTAssertEqual(snapshot.adminOverview.enterprise, false)
        XCTAssertEqual(snapshot.adminOverview.licensePlan, "default")
        XCTAssertEqual(snapshot.adminOverview.userCount, 12)
        XCTAssertEqual(snapshot.adminOverview.activeUserCount, 9)
        XCTAssertEqual(snapshot.adminOverview.projectCount, 5)
        XCTAssertEqual(snapshot.adminOverview.groupCount, 2)
        XCTAssertEqual(snapshot.adminOverview.issueCount, 20)
        XCTAssertEqual(snapshot.adminOverview.mergeRequestCount, 7)
        XCTAssertEqual(snapshot.adminOverview.runnerCount, 1)
        XCTAssertEqual(snapshot.adminOverview.healthStatus, "GitLab OK")
        XCTAssertTrue(snapshot.adminOverview.unavailableReasons.isEmpty)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "gitlab-token" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/users" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/projects/11/members/all" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/groups/2/members/all" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/projects/11/pipelines" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/projects/11/jobs" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/projects/11/packages" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/runners/all" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/projects/11/variables" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/projects/11/deploy_keys" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/projects/11/deploy_tokens" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/projects/11/repository/branches" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/projects/11/repository/tags" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/metadata" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/application/statistics" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/api/v4/license" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/-/health" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/-/readiness" })
        XCTAssertTrue(requests.contains { $0.url?.path == "/-/liveness" })
    }

    func testGiteaAPIClientCreatesAndDeletesRepositoryWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/user/repos": #"""
            {"id":9,"name":"native-app","full_name":"alice/native-app","owner":{"login":"alice"},"private":true,"default_branch":"main","description":"Created from HHC","html_url":"http://git/alice/native-app","updated_at":"2026-06-28T01:00:00Z","stars_count":0,"forks_count":0}
            """#,
        ])
        let client = GiteaAPIClient(transport: transport)

        let repository = try await client.createRepository(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GitNativeRepositoryDraft(
                name: "native-app",
                description: "Created from HHC",
                isPrivate: true,
                autoInitialize: true
            )
        )
        try await client.deleteRepository(baseURL: "http://git.example.com", token: "gitea-token", fullName: repository.fullName)

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(requests.first?.url?.path, "/api/v1/user/repos")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        let createBody = try XCTUnwrap(requests.first?.httpBody)
        let createJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        XCTAssertEqual(createJSON["name"] as? String, "native-app")
        XCTAssertEqual(createJSON["description"] as? String, "Created from HHC")
        XCTAssertEqual(createJSON["private"] as? Bool, true)
        XCTAssertEqual(createJSON["auto_init"] as? Bool, true)
        XCTAssertEqual(requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(requests.last?.url?.path, "/api/v1/repos/alice/native-app")
    }

    func testGiteaAPIClientUpdatesRepositorySettingsWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/repos/team/app": #"""
            {"id":1,"name":"app","full_name":"team/app","owner":{"login":"alice"},"private":false,"archived":true,"default_branch":"release/v1","description":"updated backend","has_issues":false,"has_wiki":true,"has_pull_requests":false,"has_packages":true,"html_url":"http://git/team/app","updated_at":"2026-06-28T01:00:00Z","stars_count":2,"forks_count":1}
            """#,
        ])
        let client = GiteaAPIClient(transport: transport)

        let repository = try await client.updateRepository(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaRepositorySettingsDraft(
                fullName: " team/app ",
                description: " updated backend ",
                isPrivate: false,
                defaultBranch: " release/v1 ",
                hasIssues: false,
                hasWiki: true,
                hasPullRequests: false,
                hasPackages: true,
                archived: true
            )
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(repository.fullName, "team/app")
        XCTAssertEqual(repository.isArchived, true)
        XCTAssertEqual(repository.defaultBranch, "release/v1")
        XCTAssertEqual(repository.hasIssues, false)
        XCTAssertEqual(repository.hasWiki, true)
        XCTAssertEqual(repository.hasPullRequests, false)
        XCTAssertEqual(repository.hasPackages, true)
        XCTAssertEqual(requests.first?.httpMethod, "PATCH")
        XCTAssertEqual(requests.first?.url?.path, "/api/v1/repos/team/app")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        let body = try XCTUnwrap(requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["description"] as? String, "updated backend")
        XCTAssertEqual(json["private"] as? Bool, false)
        XCTAssertEqual(json["default_branch"] as? String, "release/v1")
        XCTAssertEqual(json["has_issues"] as? Bool, false)
        XCTAssertEqual(json["has_wiki"] as? Bool, true)
        XCTAssertEqual(json["has_pull_requests"] as? Bool, false)
        XCTAssertEqual(json["has_packages"] as? Bool, true)
        XCTAssertEqual(json["archived"] as? Bool, true)
    }

    func testGiteaAPIClientCreatesUpdatesAndDeletesUserWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/admin/users": #"""
            {"id":18,"login":"deploybot","full_name":"Deploy Bot","email":"deploybot@example.com","is_admin":false,"active":true,"last_login":"2026-06-28T02:00:00Z"}
            """#,
            "/api/v1/admin/users/deploybot": #"""
            {"id":18,"login":"deploybot","full_name":"Deploy Owner","email":"deploy-owner@example.com","is_admin":true,"active":false,"last_login":"2026-06-28T02:00:00Z"}
            """#,
        ])
        let client = GiteaAPIClient(transport: transport)

        let user = try await client.createUser(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaUserDraft(
                username: " deploybot ",
                email: " deploybot@example.com ",
                password: "initial-password",
                fullName: " Deploy Bot ",
                mustChangePassword: true,
                isActive: true,
                isAdmin: false,
                prohibitLogin: false,
                restricted: true
            )
        )
        let updatedUser = try await client.updateUser(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaUserDraft(
                originalUsername: user.username,
                username: " deploybot ",
                email: " deploy-owner@example.com ",
                password: "reset-password",
                fullName: " Deploy Owner ",
                mustChangePassword: true,
                isActive: false,
                isAdmin: true,
                prohibitLogin: true,
                restricted: false
            )
        )
        try await client.deleteUser(baseURL: "http://git.example.com", token: "gitea-token", username: updatedUser.username)

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(user.username, "deploybot")
        XCTAssertEqual(updatedUser.fullName, "Deploy Owner")

        let createRequest = requests[0]
        XCTAssertEqual(createRequest.httpMethod, "POST")
        XCTAssertEqual(createRequest.url?.path, "/api/v1/admin/users")
        XCTAssertEqual(createRequest.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        let body = try XCTUnwrap(createRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["username"] as? String, "deploybot")
        XCTAssertEqual(json["email"] as? String, "deploybot@example.com")
        XCTAssertEqual(json["password"] as? String, "initial-password")
        XCTAssertEqual(json["full_name"] as? String, "Deploy Bot")
        XCTAssertEqual(json["must_change_password"] as? Bool, true)
        XCTAssertEqual(json["admin"] as? Bool, false)
        XCTAssertEqual(json["restricted"] as? Bool, true)

        let updateRequest = requests[1]
        XCTAssertEqual(updateRequest.httpMethod, "PATCH")
        XCTAssertEqual(updateRequest.url?.path, "/api/v1/admin/users/deploybot")
        let updateBody = try XCTUnwrap(updateRequest.httpBody)
        let updateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        XCTAssertEqual(updateJSON["source_id"] as? Int, 0)
        XCTAssertEqual(updateJSON["login_name"] as? String, "deploybot")
        XCTAssertEqual(updateJSON["email"] as? String, "deploy-owner@example.com")
        XCTAssertEqual(updateJSON["password"] as? String, "reset-password")
        XCTAssertEqual(updateJSON["full_name"] as? String, "Deploy Owner")
        XCTAssertEqual(updateJSON["must_change_password"] as? Bool, true)
        XCTAssertEqual(updateJSON["active"] as? Bool, false)
        XCTAssertEqual(updateJSON["admin"] as? Bool, true)
        XCTAssertEqual(updateJSON["prohibit_login"] as? Bool, true)
        XCTAssertEqual(updateJSON["restricted"] as? Bool, false)

        let deleteRequest = requests[2]
        XCTAssertEqual(deleteRequest.httpMethod, "DELETE")
        XCTAssertEqual(deleteRequest.url?.path, "/api/v1/admin/users/deploybot")
    }

    func testGiteaAPIClientCreatesUpdatesAndDeletesOrganizationWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/orgs": #"""
            {"id":31,"username":"mobile-team","full_name":"Mobile Team","description":"iOS and Flutter apps","website":"https://example.com/mobile","visibility":"limited"}
            """#,
            "/api/v1/orgs/mobile-team": #"""
            {"id":31,"username":"mobile-team","full_name":"Mobile Platform","description":"Native app group","website":"https://example.com/native","visibility":"private"}
            """#,
        ])
        let client = GiteaAPIClient(transport: transport)

        let organization = try await client.createOrganization(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaOrganizationDraft(
                username: " mobile-team ",
                fullName: " Mobile Team ",
                description: " iOS and Flutter apps ",
                website: " https://example.com/mobile ",
                visibility: "limited"
            )
        )
        let updatedOrganization = try await client.updateOrganization(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaOrganizationDraft(
                originalUsername: organization.username,
                username: " mobile-team ",
                fullName: " Mobile Platform ",
                description: " Native app group ",
                website: " https://example.com/native ",
                visibility: "private"
            )
        )
        try await client.deleteOrganization(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            username: updatedOrganization.username
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(organization.username, "mobile-team")
        XCTAssertEqual(organization.visibility, "limited")

        let createRequest = requests[0]
        XCTAssertEqual(createRequest.httpMethod, "POST")
        XCTAssertEqual(createRequest.url?.path, "/api/v1/orgs")
        XCTAssertEqual(createRequest.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        let createBody = try XCTUnwrap(createRequest.httpBody)
        let createJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        XCTAssertEqual(createJSON["username"] as? String, "mobile-team")
        XCTAssertEqual(createJSON["full_name"] as? String, "Mobile Team")
        XCTAssertEqual(createJSON["description"] as? String, "iOS and Flutter apps")
        XCTAssertEqual(createJSON["website"] as? String, "https://example.com/mobile")
        XCTAssertEqual(createJSON["visibility"] as? String, "limited")

        let updateRequest = requests[1]
        XCTAssertEqual(updatedOrganization.fullName, "Mobile Platform")
        XCTAssertEqual(updatedOrganization.visibility, "private")
        XCTAssertEqual(updateRequest.httpMethod, "PATCH")
        XCTAssertEqual(updateRequest.url?.path, "/api/v1/orgs/mobile-team")
        let updateBody = try XCTUnwrap(updateRequest.httpBody)
        let updateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        XCTAssertNil(updateJSON["username"])
        XCTAssertEqual(updateJSON["full_name"] as? String, "Mobile Platform")
        XCTAssertEqual(updateJSON["description"] as? String, "Native app group")
        XCTAssertEqual(updateJSON["website"] as? String, "https://example.com/native")
        XCTAssertEqual(updateJSON["visibility"] as? String, "private")

        let deleteRequest = requests[2]
        XCTAssertEqual(deleteRequest.httpMethod, "DELETE")
        XCTAssertEqual(deleteRequest.url?.path, "/api/v1/orgs/mobile-team")
    }

    func testGiteaAPIClientCreatesUpdatesAndDeletesTeamWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/orgs/team/teams": #"""
            {"id":34,"name":"Platform","description":"Native apps","permission":"write","includes_all_repositories":false,"can_create_org_repo":true,"units":["repo.code","repo.issues"],"organization":{"username":"team"}}
            """#,
            "/api/v1/teams/34": #"""
            {"id":34,"name":"Platform Leads","description":"Release owners","permission":"admin","includes_all_repositories":true,"can_create_org_repo":true,"units":["repo.code","repo.pulls"],"organization":{"username":"team"}}
            """#,
        ])
        let client = GiteaAPIClient(transport: transport)

        let team = try await client.createTeam(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaTeamDraft(
                organization: " team ",
                name: " Platform ",
                description: " Native apps ",
                permission: "write",
                includesAllRepositories: false,
                canCreateOrgRepo: true,
                units: ["repo.code", "repo.issues"]
            )
        )
        let updatedTeam = try await client.updateTeam(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaTeamDraft(
                teamId: team.id,
                organization: " team ",
                name: " Platform Leads ",
                description: " Release owners ",
                permission: "admin",
                includesAllRepositories: true,
                canCreateOrgRepo: true,
                units: ["repo.code", "repo.pulls"]
            )
        )
        try await client.deleteTeam(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            teamId: updatedTeam.id
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(team.organization, "team")
        XCTAssertEqual(team.name, "Platform")
        XCTAssertEqual(updatedTeam.name, "Platform Leads")

        let createRequest = requests[0]
        XCTAssertEqual(createRequest.httpMethod, "POST")
        XCTAssertEqual(createRequest.url?.path, "/api/v1/orgs/team/teams")
        XCTAssertEqual(createRequest.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        let createBody = try XCTUnwrap(createRequest.httpBody)
        let createJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        XCTAssertEqual(createJSON["name"] as? String, "Platform")
        XCTAssertEqual(createJSON["description"] as? String, "Native apps")
        XCTAssertEqual(createJSON["permission"] as? String, "write")
        XCTAssertEqual(createJSON["includes_all_repositories"] as? Bool, false)
        XCTAssertEqual(createJSON["can_create_org_repo"] as? Bool, true)
        XCTAssertEqual(createJSON["units"] as? [String], ["repo.code", "repo.issues"])

        let updateRequest = requests[1]
        XCTAssertEqual(updateRequest.httpMethod, "PATCH")
        XCTAssertEqual(updateRequest.url?.path, "/api/v1/teams/34")
        let updateBody = try XCTUnwrap(updateRequest.httpBody)
        let updateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        XCTAssertEqual(updateJSON["name"] as? String, "Platform Leads")
        XCTAssertEqual(updateJSON["description"] as? String, "Release owners")
        XCTAssertEqual(updateJSON["permission"] as? String, "admin")
        XCTAssertEqual(updateJSON["includes_all_repositories"] as? Bool, true)
        XCTAssertEqual(updateJSON["can_create_org_repo"] as? Bool, true)
        XCTAssertEqual(updateJSON["units"] as? [String], ["repo.code", "repo.pulls"])

        let deleteRequest = requests[2]
        XCTAssertEqual(deleteRequest.httpMethod, "DELETE")
        XCTAssertEqual(deleteRequest.url?.path, "/api/v1/teams/34")
    }

    func testGiteaAPIClientAddsAndRemovesTeamMemberWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [:])
        let client = GiteaAPIClient(transport: transport)

        try await client.addTeamMember(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaTeamMemberDraft(teamId: 12, username: "alice")
        )
        try await client.removeTeamMember(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            teamId: 12,
            username: "alice"
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.first?.httpMethod, "PUT")
        XCTAssertEqual(requests.first?.url?.path, "/api/v1/teams/12/members/alice")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        XCTAssertEqual(requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(requests.last?.url?.path, "/api/v1/teams/12/members/alice")
    }

    func testGiteaAPIClientAddsAndRemovesTeamRepositoryWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [:])
        let client = GiteaAPIClient(transport: transport)

        try await client.addTeamRepository(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaTeamRepositoryDraft(teamId: 12, repositoryFullName: "team/app")
        )
        try await client.removeTeamRepository(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            teamId: 12,
            repositoryFullName: "team/app"
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.first?.httpMethod, "PUT")
        XCTAssertEqual(requests.first?.url?.path, "/api/v1/teams/12/repos/team/app")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        XCTAssertEqual(requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(requests.last?.url?.path, "/api/v1/teams/12/repos/team/app")
    }

    func testGiteaAPIClientCreatesAndDeletesKeyWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/user/keys": #"""
            {"id":33,"title":"deploy mac","key":"ssh-ed25519 AAAATEST deploy@example.com","fingerprint":"SHA256:test","url":"http://git/api/v1/user/keys/33","read_only":true,"created_at":"2026-06-28T01:30:00Z"}
            """#,
        ])
        let client = GiteaAPIClient(transport: transport)

        let key = try await client.createKey(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaKeyDraft(
                title: "deploy mac",
                key: "ssh-ed25519 AAAATEST deploy@example.com",
                isReadOnly: true
            )
        )
        try await client.deleteKey(baseURL: "http://git.example.com", token: "gitea-token", keyId: key.id)

        let requests = transport.snapshotRequests()
        XCTAssertEqual(key.fingerprint, "SHA256:test")
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(requests.first?.url?.path, "/api/v1/user/keys")
        let body = try XCTUnwrap(requests.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "deploy mac")
        XCTAssertEqual(json["key"] as? String, "ssh-ed25519 AAAATEST deploy@example.com")
        XCTAssertEqual(json["read_only"] as? Bool, true)
        XCTAssertEqual(requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(requests.last?.url?.path, "/api/v1/user/keys/33")
    }

    func testGiteaAPIClientCreatesAndDeletesAccessTokenWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/users/alice/tokens": #"""
            {"id":44,"name":"hhc mac","scopes":["read:repository","read:user"],"sha1":"secret-token","token_last_eight":"abcd1234","created_at":"2026-06-28T01:40:00Z","last_used_at":null}
            """#,
            "/api/v1/users/alice/tokens/44": "{}",
        ])
        let client = GiteaAPIClient(transport: transport)

        let result = try await client.createAccessToken(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            draft: GiteaAccessTokenDraft(
                username: " alice ",
                name: " hhc mac ",
                scopes: ["read:repository", "read:user"]
            )
        )
        try await client.deleteAccessToken(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            username: "alice",
            tokenId: result.token.id
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(result.secret, "secret-token")
        XCTAssertEqual(result.token.username, "alice")
        XCTAssertEqual(result.token.tokenLastEight, "abcd1234")

        let createRequest = requests[0]
        XCTAssertEqual(createRequest.httpMethod, "POST")
        XCTAssertEqual(createRequest.url?.path, "/api/v1/users/alice/tokens")
        XCTAssertEqual(createRequest.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        let body = try XCTUnwrap(createRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "hhc mac")
        XCTAssertEqual(json["scopes"] as? [String], ["read:repository", "read:user"])

        let deleteRequest = requests[1]
        XCTAssertEqual(deleteRequest.httpMethod, "DELETE")
        XCTAssertEqual(deleteRequest.url?.path, "/api/v1/users/alice/tokens/44")
    }

    func testGiteaAPIClientDeletesPackageAndPackageVersionWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [:])
        let client = GiteaAPIClient(transport: transport)

        try await client.deletePackage(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            owner: "alice",
            type: "npm",
            name: "@hhc/app",
            version: "1.0.0"
        )
        try await client.deletePackage(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            owner: "team",
            type: "pub",
            name: "backend_sdk",
            version: nil
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(requests.first?.url?.path, "/api/v1/packages/alice/npm/@hhc%2Fapp/1.0.0")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        XCTAssertEqual(requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(requests.last?.url?.path, "/api/v1/packages/team/pub/backend_sdk")
    }

    func testGiteaAPIClientLoadsPackageDetailWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/packages/alice/npm/@hhc%2Fapp": #"""
            [{"id":55,"owner":{"login":"alice"},"name":"@hhc/app","type":"npm","version":"1.0.0","repository":{"full_name":"team/app"},"html_url":"http://git/alice/-/packages/npm/@hhc/app/1.0.0","created_at":"2026-06-28T04:00:00Z"},{"id":56,"owner":{"login":"alice"},"name":"@hhc/app","type":"npm","version":"1.1.0","repository":{"full_name":"team/app"},"created_at":"2026-06-28T05:00:00Z"}]
            """#,
            "/api/v1/packages/alice/npm/@hhc%2Fapp/1.1.0": #"""
            {"id":56,"owner":{"login":"alice"},"name":"@hhc/app","type":"npm","version":"1.1.0","repository":{"full_name":"team/app"},"html_url":"http://git/alice/-/packages/npm/@hhc/app/1.1.0","created_at":"2026-06-28T05:00:00Z"}
            """#,
            "/api/v1/packages/alice/npm/@hhc%2Fapp/1.1.0/files": #"""
            [{"id":90,"name":"hhc-app-1.1.0.tgz","size":4096,"md5":"md5-test","sha1":"sha1-test","sha256":"sha256-test","sha512":"sha512-test"}]
            """#,
        ])
        let client = GiteaAPIClient(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let detail = try await client.packageDetail(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            owner: "alice",
            type: "npm",
            name: "@hhc/app",
            version: "1.1.0"
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(detail.owner, "alice")
        XCTAssertEqual(detail.type, "npm")
        XCTAssertEqual(detail.name, "@hhc/app")
        XCTAssertEqual(detail.selectedVersion, "1.1.0")
        XCTAssertEqual(detail.package?.version, "1.1.0")
        XCTAssertEqual(detail.versions.map(\.version), ["1.0.0", "1.1.0"])
        XCTAssertEqual(detail.files.first?.name, "hhc-app-1.1.0.tgz")
        XCTAssertEqual(detail.files.first?.size, 4096)
        XCTAssertEqual(detail.files.first?.sha256, "sha256-test")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "token gitea-token" })
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/api/v1/packages/alice/npm/@hhc%2Fapp",
            "/api/v1/packages/alice/npm/@hhc%2Fapp/1.1.0",
            "/api/v1/packages/alice/npm/@hhc%2Fapp/1.1.0/files",
        ])
    }

    func testGitLabAPIClientCreatesAndDeletesProjectWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects": #"""
            {"id":15,"name":"native-app","path_with_namespace":"team/native-app","visibility":"internal","default_branch":"main","web_url":"http://gitlab/team/native-app","last_activity_at":"2026-06-28T01:00:00Z","archived":false}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)

        let project = try await client.createProject(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            draft: GitNativeRepositoryDraft(
                name: "native-app",
                description: "Created from HHC",
                isPrivate: false,
                autoInitialize: true
            )
        )
        try await client.deleteProject(baseURL: "http://gitlab.example.com", token: "gitlab-token", projectId: project.id)

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(requests.first?.url?.path, "/api/v4/projects")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let createBody = try XCTUnwrap(requests.first?.httpBody)
        let createJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        XCTAssertEqual(createJSON["name"] as? String, "native-app")
        XCTAssertEqual(createJSON["description"] as? String, "Created from HHC")
        XCTAssertEqual(createJSON["visibility"] as? String, "internal")
        XCTAssertEqual(createJSON["initialize_with_readme"] as? Bool, true)
        XCTAssertEqual(requests.last?.httpMethod, "DELETE")
        XCTAssertEqual(requests.last?.url?.path, "/api/v4/projects/15")
    }

    func testGitLabAPIClientUpdatesProjectSettingsWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/15": #"""
            {"id":15,"name":"native-app","path_with_namespace":"team/native-app","description":"updated project","visibility":"public","default_branch":"release/v1","web_url":"http://gitlab/team/native-app","last_activity_at":"2026-06-28T01:00:00Z","archived":true}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)

        let project = try await client.updateProject(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            draft: GitLabProjectSettingsDraft(
                projectId: 15,
                pathWithNamespace: "team/native-app",
                description: "updated project",
                visibility: "public",
                defaultBranch: "release/v1",
                archived: true
            )
        )

        let request = try XCTUnwrap(transport.snapshotRequests().first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v4/projects/15")
        XCTAssertEqual(request.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["description"] as? String, "updated project")
        XCTAssertEqual(json["visibility"] as? String, "public")
        XCTAssertEqual(json["default_branch"] as? String, "release/v1")
        XCTAssertEqual(json["archived"] as? Bool, true)
        XCTAssertEqual(project.description, "updated project")
        XCTAssertEqual(project.visibility, "public")
        XCTAssertEqual(project.defaultBranch, "release/v1")
        XCTAssertEqual(project.archived, true)
    }

    func testGitLabAPIClientCreatesUpdatesAndDeletesGroupWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/groups": #"""
            {"id":27,"name":"Mobile Team","full_path":"platform/mobile","visibility":"private","web_url":"http://gitlab/groups/platform/mobile"}
            """#,
            "/api/v4/groups/27": #"""
            {"id":27,"name":"Mobile Platform","full_path":"platform/mobile-platform","visibility":"internal","web_url":"http://gitlab/groups/platform/mobile-platform"}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)

        let group = try await client.createGroup(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            draft: GitLabGroupDraft(
                name: " Mobile Team ",
                path: " mobile ",
                description: "iOS and Flutter apps",
                visibility: "private",
                parentId: 9
            )
        )
        let updatedGroup = try await client.updateGroup(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            draft: GitLabGroupDraft(
                groupId: group.id,
                name: " Mobile Platform ",
                path: " mobile-platform ",
                description: "Native app group",
                visibility: "internal",
                parentId: 9
            )
        )
        try await client.deleteGroup(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            groupId: updatedGroup.id
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests.count, 3)
        let request = requests[0]
        XCTAssertEqual(group.id, 27)
        XCTAssertEqual(group.fullPath, "platform/mobile")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v4/groups")
        XCTAssertEqual(request.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "Mobile Team")
        XCTAssertEqual(json["path"] as? String, "mobile")
        XCTAssertEqual(json["description"] as? String, "iOS and Flutter apps")
        XCTAssertEqual(json["visibility"] as? String, "private")
        XCTAssertEqual(json["parent_id"] as? Int, 9)

        let updateRequest = requests[1]
        XCTAssertEqual(updatedGroup.id, 27)
        XCTAssertEqual(updatedGroup.fullPath, "platform/mobile-platform")
        XCTAssertEqual(updateRequest.httpMethod, "PUT")
        XCTAssertEqual(updateRequest.url?.path, "/api/v4/groups/27")
        XCTAssertEqual(updateRequest.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let updateBody = try XCTUnwrap(updateRequest.httpBody)
        let updateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        XCTAssertEqual(updateJSON["name"] as? String, "Mobile Platform")
        XCTAssertEqual(updateJSON["path"] as? String, "mobile-platform")
        XCTAssertEqual(updateJSON["description"] as? String, "Native app group")
        XCTAssertEqual(updateJSON["visibility"] as? String, "internal")
        XCTAssertNil(updateJSON["parent_id"])

        let deleteRequest = requests[2]
        XCTAssertEqual(deleteRequest.httpMethod, "DELETE")
        XCTAssertEqual(deleteRequest.url?.path, "/api/v4/groups/27")
        XCTAssertEqual(deleteRequest.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
    }

    func testGiteaAPIClientUpdatesIssueStateWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v1/repos/team/app/issues/5": #"""
            {"id":20,"number":5,"title":"Fix deploy","state":"closed","repository":{"full_name":"team/app"},"user":{"login":"alice"},"updated_at":"2026-06-28T03:00:00Z"}
            """#,
        ])
        let client = GiteaAPIClient(transport: transport)

        let issue = try await client.updateIssueState(
            baseURL: "http://git.example.com",
            token: "gitea-token",
            repositoryFullName: "team/app",
            issueNumber: 5,
            action: .close
        )

        let request = try XCTUnwrap(transport.snapshotRequests().first)
        XCTAssertEqual(issue.state, "closed")
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path, "/api/v1/repos/team/app/issues/5")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token gitea-token")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["state"] as? String, "closed")
    }

    func testGitLabAPIClientUpdatesIssueAndMergeRequestStateWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/issues/8": #"""
            {"id":31,"iid":8,"title":"Fix deploy","state":"closed","project_id":11,"web_url":"http://gitlab/team/app/-/issues/8","updated_at":"2026-06-28T02:00:00Z"}
            """#,
            "/api/v4/projects/11/merge_requests/4": #"""
            {"id":41,"iid":4,"title":"Deploy MR","state":"reopened","source_branch":"feature","target_branch":"main","project_id":11,"web_url":"http://gitlab/team/app/-/merge_requests/4","updated_at":"2026-06-28T03:00:00Z"}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)

        let issue = try await client.updateIssueState(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            issueIid: 8,
            action: .close
        )
        let mergeRequest = try await client.updateMergeRequestState(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            mergeRequestIid: 4,
            action: .reopen
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(issue.state, "closed")
        XCTAssertEqual(mergeRequest.state, "reopened")
        XCTAssertEqual(requests.first?.httpMethod, "PUT")
        XCTAssertEqual(requests.first?.url?.path, "/api/v4/projects/11/issues/8")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let issueBody = try XCTUnwrap(requests.first?.httpBody)
        let issueJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: issueBody) as? [String: Any])
        XCTAssertEqual(issueJSON["state_event"] as? String, "close")
        XCTAssertEqual(requests.last?.httpMethod, "PUT")
        XCTAssertEqual(requests.last?.url?.path, "/api/v4/projects/11/merge_requests/4")
        let mergeBody = try XCTUnwrap(requests.last?.httpBody)
        let mergeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: mergeBody) as? [String: Any])
        XCTAssertEqual(mergeJSON["state_event"] as? String, "reopen")
    }

    func testGitLabAPIClientRetriesAndCancelsPipelineWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/pipelines/51/retry": #"""
            {"id":51,"ref":"main","sha":"abcdef123456","status":"pending","project_id":11,"web_url":"http://gitlab/team/app/-/pipelines/51","updated_at":"2026-06-28T04:00:00Z"}
            """#,
            "/api/v4/projects/11/pipelines/51/cancel": #"""
            {"id":51,"ref":"main","sha":"abcdef123456","status":"canceled","project_id":11,"web_url":"http://gitlab/team/app/-/pipelines/51","updated_at":"2026-06-28T04:05:00Z"}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)

        let retried = try await client.retryPipeline(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            pipelineId: 51
        )
        let canceled = try await client.cancelPipeline(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            pipelineId: 51
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(retried.status, "pending")
        XCTAssertEqual(canceled.status, "canceled")
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(requests.first?.url?.path, "/api/v4/projects/11/pipelines/51/retry")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        XCTAssertNil(requests.first?.httpBody)
        XCTAssertEqual(requests.last?.httpMethod, "POST")
        XCTAssertEqual(requests.last?.url?.path, "/api/v4/projects/11/pipelines/51/cancel")
        XCTAssertNil(requests.last?.httpBody)
    }

    func testGitLabAPIClientRetriesCancelsAndPlaysJobWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/jobs/71/retry": #"""
            {"id":71,"name":"deploy","stage":"deploy","ref":"main","status":"pending","web_url":"http://gitlab/team/app/-/jobs/71","duration":null,"started_at":null,"finished_at":null}
            """#,
            "/api/v4/projects/11/jobs/71/cancel": #"""
            {"id":71,"name":"deploy","stage":"deploy","ref":"main","status":"canceled","web_url":"http://gitlab/team/app/-/jobs/71","duration":12.3,"started_at":"2026-06-28T04:30:00Z","finished_at":"2026-06-28T04:31:00Z"}
            """#,
            "/api/v4/projects/11/jobs/71/play": #"""
            {"id":71,"name":"deploy","stage":"deploy","ref":"main","status":"running","web_url":"http://gitlab/team/app/-/jobs/71","duration":null,"started_at":"2026-06-28T04:32:00Z","finished_at":null}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)

        let retried = try await client.retryJob(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            jobId: 71
        )
        let canceled = try await client.cancelJob(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            jobId: 71
        )
        let played = try await client.playJob(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            jobId: 71
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(retried.projectId, 11)
        XCTAssertEqual(retried.status, "pending")
        XCTAssertEqual(canceled.status, "canceled")
        XCTAssertEqual(played.status, "running")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/v4/projects/11/jobs/71/retry")
        XCTAssertEqual(requests[1].httpMethod, "POST")
        XCTAssertEqual(requests[1].url?.path, "/api/v4/projects/11/jobs/71/cancel")
        XCTAssertEqual(requests[2].httpMethod, "POST")
        XCTAssertEqual(requests[2].url?.path, "/api/v4/projects/11/jobs/71/play")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "gitlab-token" })
    }

    func testGitLabAPIClientLoadsJobTraceWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/jobs/71/trace": """
            section_start:deploy
            $ echo deploy
            success
            """,
        ])
        let client = GitLabAPIClient(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let trace = try await client.jobTrace(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            jobId: 71
        )

        let request = try XCTUnwrap(transport.snapshotRequests().first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v4/projects/11/jobs/71/trace")
        XCTAssertEqual(request.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        XCTAssertEqual(trace.projectId, 11)
        XCTAssertEqual(trace.jobId, 71)
        XCTAssertTrue(trace.text.contains("echo deploy"))
        XCTAssertEqual(trace.capturedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testGitLabAPIClientCreatesUpdatesAndDeletesVariableWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/variables": #"""
            {"key":"DEPLOY_ENV","variable_type":"env_var","environment_scope":"production","protected":true,"masked":true,"raw":false,"description":"Deploy target"}
            """#,
            "/api/v4/projects/11/variables/DEPLOY_ENV": #"""
            {"key":"DEPLOY_ENV","variable_type":"env_var","environment_scope":"production","protected":true,"masked":false,"raw":true,"description":"Deploy target"}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)
        let createDraft = GitLabVariableDraft(
            projectId: 11,
            key: "DEPLOY_ENV",
            value: "prod-secret",
            environmentScope: "production",
            variableType: "env_var",
            protected: true,
            masked: true,
            raw: false
        )
        let updateDraft = GitLabVariableDraft(
            projectId: 11,
            key: "DEPLOY_ENV",
            value: "new-secret",
            environmentScope: "production",
            variableType: "env_var",
            protected: true,
            masked: false,
            raw: true
        )

        let created = try await client.createVariable(baseURL: "http://gitlab.example.com", token: "gitlab-token", draft: createDraft)
        let updated = try await client.updateVariable(baseURL: "http://gitlab.example.com", token: "gitlab-token", draft: updateDraft)
        try await client.deleteVariable(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            key: "DEPLOY_ENV",
            environmentScope: "production"
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(created.projectId, 11)
        XCTAssertEqual(updated.projectId, 11)
        XCTAssertEqual(updated.raw, true)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/v4/projects/11/variables")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let createBody = try XCTUnwrap(requests[0].httpBody)
        let createJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: Any])
        XCTAssertEqual(createJSON["key"] as? String, "DEPLOY_ENV")
        XCTAssertEqual(createJSON["value"] as? String, "prod-secret")
        XCTAssertEqual(createJSON["environment_scope"] as? String, "production")
        XCTAssertEqual(createJSON["protected"] as? Bool, true)
        XCTAssertEqual(createJSON["masked"] as? Bool, true)

        XCTAssertEqual(requests[1].httpMethod, "PUT")
        XCTAssertEqual(requests[1].url?.path, "/api/v4/projects/11/variables/DEPLOY_ENV")
        XCTAssertEqual(requests[1].url?.query, "filter%5Benvironment_scope%5D=production")
        let updateBody = try XCTUnwrap(requests[1].httpBody)
        let updateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        XCTAssertEqual(updateJSON["value"] as? String, "new-secret")
        XCTAssertEqual(updateJSON["masked"] as? Bool, false)
        XCTAssertEqual(updateJSON["raw"] as? Bool, true)

        XCTAssertEqual(requests[2].httpMethod, "DELETE")
        XCTAssertEqual(requests[2].url?.path, "/api/v4/projects/11/variables/DEPLOY_ENV")
        XCTAssertEqual(requests[2].url?.query, "filter%5Benvironment_scope%5D=production")
    }

    func testGitLabAPIClientCreatesAndDeletesDeployKeyWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/deploy_keys": #"""
            {"id":61,"title":"deploy mac","key":"ssh-ed25519 AAAATEST deploy@example.com","fingerprint":"SHA256:test","can_push":true,"created_at":"2026-06-28T05:00:00Z","expires_at":"2027-06-28"}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)

        let deployKey = try await client.createDeployKey(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            draft: GitLabDeployKeyDraft(
                projectId: 11,
                title: "deploy mac",
                key: "ssh-ed25519 AAAATEST deploy@example.com",
                canPush: true
            )
        )
        try await client.deleteDeployKey(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            keyId: deployKey.id
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(deployKey.projectId, 11)
        XCTAssertEqual(deployKey.fingerprint, "SHA256:test")
        XCTAssertEqual(deployKey.canPush, true)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/v4/projects/11/deploy_keys")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let body = try XCTUnwrap(requests[0].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "deploy mac")
        XCTAssertEqual(json["key"] as? String, "ssh-ed25519 AAAATEST deploy@example.com")
        XCTAssertEqual(json["can_push"] as? Bool, true)
        XCTAssertEqual(requests[1].httpMethod, "DELETE")
        XCTAssertEqual(requests[1].url?.path, "/api/v4/projects/11/deploy_keys/61")
    }

    func testGitLabAPIClientDeletesDeployTokenWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/deploy_tokens/62": "{}",
        ])
        let client = GitLabAPIClient(transport: transport)

        try await client.deleteDeployToken(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            tokenId: 62
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests[0].httpMethod, "DELETE")
        XCTAssertEqual(requests[0].url?.path, "/api/v4/projects/11/deploy_tokens/62")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
    }

    func testGitLabAPIClientCreatesDeployTokenWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/deploy_tokens": #"""
            {"id":62,"name":"registry deploy","username":"gitlab+deploy-token-62","token":"glpat-secret","scopes":["read_repository","read_package_registry"],"revoked":false,"expired":false,"active":true,"created_at":"2026-06-28T05:10:00Z","expires_at":"2027-06-28"}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)

        let result = try await client.createDeployToken(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            draft: GitLabDeployTokenDraft(
                projectId: 11,
                name: "registry deploy",
                username: "deploybot",
                expiresAt: "2027-06-28",
                readRepository: true,
                readRegistry: false,
                writeRegistry: false,
                readPackageRegistry: true,
                writePackageRegistry: false
            )
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(result.deployToken.projectId, 11)
        XCTAssertEqual(result.deployToken.name, "registry deploy")
        XCTAssertEqual(result.token, "glpat-secret")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/v4/projects/11/deploy_tokens")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let body = try XCTUnwrap(requests[0].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "registry deploy")
        XCTAssertEqual(json["username"] as? String, "deploybot")
        XCTAssertEqual(json["expires_at"] as? String, "2027-06-28")
        XCTAssertEqual(json["scopes"] as? [String], ["read_repository", "read_package_registry"])
    }

    func testGitLabAPIClientDeletesPackageWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/packages/81": "{}",
        ])
        let client = GitLabAPIClient(transport: transport)

        try await client.deletePackage(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            packageId: 81
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(requests[0].httpMethod, "DELETE")
        XCTAssertEqual(requests[0].url?.path, "/api/v4/projects/11/packages/81")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
    }

    func testGitLabAPIClientCreatesAndDeletesTagWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/repository/tags": #"""
            {"name":"v1.0.0","message":"release","target":"abcdef123456","protected":false,"commit":{"short_id":"abcdef12","title":"Initial commit"},"created_at":"2026-06-28T06:00:00Z"}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)

        let tag = try await client.createTag(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            draft: GitLabTagDraft(
                projectId: 11,
                name: "v1.0.0",
                ref: "main",
                message: "release"
            )
        )
        try await client.deleteTag(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            projectId: 11,
            tagName: tag.name
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(tag.projectId, 11)
        XCTAssertEqual(tag.name, "v1.0.0")
        XCTAssertEqual(tag.commitShortID, "abcdef12")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/v4/projects/11/repository/tags")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let body = try XCTUnwrap(requests[0].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["tag_name"] as? String, "v1.0.0")
        XCTAssertEqual(json["ref"] as? String, "main")
        XCTAssertEqual(json["message"] as? String, "release")
        XCTAssertEqual(requests[1].httpMethod, "DELETE")
        XCTAssertEqual(requests[1].url?.path, "/api/v4/projects/11/repository/tags/v1.0.0")
    }

    func testGitLabAPIClientAddsUpdatesAndDeletesMemberWithOfficialAPIShape() async throws {
        let transport = MockGitServiceHTTPTransport(responses: [
            "/api/v4/projects/11/members": #"""
            {"id":99,"username":"deploybot","name":"Deploy Bot","state":"active","web_url":"http://gitlab/deploybot","access_level":30,"expires_at":"2026-12-31","created_at":"2026-06-28T00:00:00Z"}
            """#,
            "/api/v4/projects/11/members/99": #"""
            {"id":99,"username":"deploybot","name":"Deploy Bot","state":"active","web_url":"http://gitlab/deploybot","access_level":40,"expires_at":"2027-01-31","created_at":"2026-06-28T00:00:00Z"}
            """#,
        ])
        let client = GitLabAPIClient(transport: transport)
        let addDraft = GitLabMemberDraft(
            scope: .project,
            targetId: 11,
            userId: 99,
            accessLevel: 30,
            expiresAt: "2026-12-31"
        )
        let updateDraft = GitLabMemberDraft(
            scope: .project,
            targetId: 11,
            userId: 99,
            accessLevel: 40,
            expiresAt: "2027-01-31"
        )

        let added = try await client.addMember(baseURL: "http://gitlab.example.com", token: "gitlab-token", draft: addDraft)
        let updated = try await client.updateMember(baseURL: "http://gitlab.example.com", token: "gitlab-token", draft: updateDraft)
        try await client.deleteMember(
            baseURL: "http://gitlab.example.com",
            token: "gitlab-token",
            scope: .group,
            targetId: 2,
            userId: 99
        )

        let requests = transport.snapshotRequests()
        XCTAssertEqual(added.scope, .project)
        XCTAssertEqual(added.targetId, 11)
        XCTAssertEqual(added.accessLevel, 30)
        XCTAssertEqual(updated.accessLevel, 40)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/v4/projects/11/members")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "PRIVATE-TOKEN"), "gitlab-token")
        let addBody = try XCTUnwrap(requests[0].httpBody)
        let addJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: addBody) as? [String: Any])
        XCTAssertEqual(addJSON["user_id"] as? Int, 99)
        XCTAssertEqual(addJSON["access_level"] as? Int, 30)
        XCTAssertEqual(addJSON["expires_at"] as? String, "2026-12-31")
        XCTAssertEqual(requests[1].httpMethod, "PUT")
        XCTAssertEqual(requests[1].url?.path, "/api/v4/projects/11/members/99")
        let updateBody = try XCTUnwrap(requests[1].httpBody)
        let updateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        XCTAssertEqual(updateJSON["access_level"] as? Int, 40)
        XCTAssertEqual(updateJSON["expires_at"] as? String, "2027-01-31")
        XCTAssertEqual(requests[2].httpMethod, "DELETE")
        XCTAssertEqual(requests[2].url?.path, "/api/v4/groups/2/members/99")
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
        XCTAssertTrue(service.contains("ExecStart=/srv/verdaccio/node_modules/.bin/verdaccio --config /srv/verdaccio/config.yaml"))
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

    func testNginxReverseProxyConfigurationBuilderGeneratesConfig() throws {
        let draft = NginxReverseProxyDraft(
            serverName: "api.example.com",
            upstreamURL: "http://127.0.0.1:8080",
            configPath: "/etc/nginx/conf.d/api-proxy.conf",
            clientMaxBodySize: "100m",
            enableWebSocket: true
        )

        let config = try NginxReverseProxyConfigurationBuilder.config(for: draft)
        let file = try NginxReverseProxyConfigurationBuilder.configFile(for: draft)

        XCTAssertEqual(file.path, "/etc/nginx/conf.d/api-proxy.conf")
        XCTAssertTrue(config.contains("server_name api.example.com;"))
        XCTAssertTrue(config.contains("client_max_body_size 100m;"))
        XCTAssertTrue(config.contains("proxy_pass http://127.0.0.1:8080;"))
        XCTAssertTrue(config.contains("proxy_set_header Upgrade $http_upgrade;"))
        XCTAssertTrue(config.contains("HTTPS is intentionally not managed here"))
    }

    func testNginxReverseProxyConfigurationBuilderRejectsUnsafeDrafts() {
        XCTAssertThrowsError(
            try NginxReverseProxyConfigurationBuilder.config(
                for: NginxReverseProxyDraft(
                    serverName: "api.example.com;rm",
                    upstreamURL: "http://127.0.0.1:8080",
                    configPath: "/etc/nginx/conf.d/api-proxy.conf"
                )
            )
        ) { error in
            XCTAssertEqual(error as? NginxReverseProxyConfigurationError, .invalidServerName)
        }

        XCTAssertThrowsError(
            try NginxReverseProxyConfigurationBuilder.config(
                for: NginxReverseProxyDraft(
                    serverName: "api.example.com",
                    upstreamURL: "http://user:pass@127.0.0.1:8080",
                    configPath: "/etc/nginx/conf.d/api-proxy.conf"
                )
            )
        ) { error in
            XCTAssertEqual(error as? NginxReverseProxyConfigurationError, .invalidUpstreamURL)
        }

        XCTAssertThrowsError(
            try NginxReverseProxyConfigurationBuilder.config(
                for: NginxReverseProxyDraft(
                    serverName: "api.example.com",
                    upstreamURL: "http://127.0.0.1:8080",
                    configPath: "/etc/nginx/conf.d/api-proxy.conf",
                    clientMaxBodySize: "0m"
                )
            )
        ) { error in
            XCTAssertEqual(error as? NginxReverseProxyConfigurationError, .invalidBodySize)
        }

        XCTAssertThrowsError(
            try NginxReverseProxyConfigurationBuilder.configFile(
                for: NginxReverseProxyDraft(
                    serverName: "api.example.com",
                    upstreamURL: "http://127.0.0.1:8080",
                    configPath: "/tmp/api-proxy.conf"
                )
            )
        )
    }

    func testDockerManagerParsesSnapshot() {
        let snapshot = DockerManager.parseSnapshot("""
        __HHC_DOCKER_VERSION__\t26.1.4
        __HHC_DOCKER_CONTAINER__\t{"ID":"abc123","Image":"nginx:latest","Command":"\\"nginx -g daemon off;\\"","CreatedAt":"2026-06-28 01:00:00 +0800 CST","RunningFor":"2 hours ago","Ports":"0.0.0.0:80->80/tcp","Status":"Up 2 hours","State":"running","Names":"web","Size":"1.2kB"}
        __HHC_DOCKER_CONTAINER__\t{"ID":"def456","Image":"redis:7","Command":"\\"docker-entrypoint.sh redis-server\\"","CreatedAt":"2026-06-28 00:00:00 +0800 CST","RunningFor":"3 hours ago","Ports":"6379/tcp","Status":"Exited (0) 1 hour ago","State":"exited","Names":"redis","Size":"0B"}
        __HHC_DOCKER_IMAGE__\t{"ID":"sha256:111","Repository":"nginx","Tag":"latest","Digest":"<none>","CreatedAt":"2026-06-20 00:00:00 +0800 CST","CreatedSince":"8 days ago","Size":"192MB"}
        """, capturedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertTrue(snapshot.isAvailable)
        XCTAssertEqual(snapshot.version, "26.1.4")
        XCTAssertEqual(snapshot.containers.count, 2)
        XCTAssertEqual(snapshot.containers.first?.names, "web")
        XCTAssertEqual(snapshot.runningContainerCount, 1)
        XCTAssertEqual(snapshot.images.first?.displayName, "nginx:latest")
    }

    func testDockerManagerParsesUnavailableSnapshot() {
        let snapshot = DockerManager.parseSnapshot("""
        __HHC_DOCKER_UNAVAILABLE__\tDocker CLI not found
        """)

        XCTAssertFalse(snapshot.isAvailable)
        XCTAssertEqual(snapshot.unavailableReason, "Docker CLI not found")
        XCTAssertTrue(snapshot.containers.isEmpty)
        XCTAssertTrue(snapshot.images.isEmpty)
    }

    func testDockerManagerPerformsContainerActionsAndReadsLogs() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "web\n", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: "2026-06-28T00:00:00Z ready\n", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = DockerManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        try await manager.perform(.restart, containerID: "web", profile: profile, sshClient: client)
        let log = try await manager.readLogs(containerID: "web", limit: 50, profile: profile, sshClient: client)

        XCTAssertEqual(client.commands.first, "docker restart 'web'")
        XCTAssertEqual(client.commands.last, "docker logs --tail 50 --timestamps 'web' 2>&1")
        XCTAssertEqual(log.containerID, "web")
        XCTAssertTrue(log.text.contains("ready"))
    }

    func testDockerManagerPullsAndRemovesImages() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "Pulled\n", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: "Untagged: nginx:latest\nDeleted: sha256:111\n", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = DockerManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let pull = try await manager.pullImage(reference: "nginx:latest", profile: profile, sshClient: client)
        let remove = try await manager.removeImage(imageID: "sha256:111", profile: profile, sshClient: client)

        XCTAssertEqual(client.commands.first, "docker pull 'nginx:latest'")
        XCTAssertEqual(client.commands.last, "docker rmi 'sha256:111'")
        XCTAssertEqual(pull.reference, "nginx:latest")
        XCTAssertTrue(remove.output.contains("Deleted"))
    }

    func testDockerManagerRejectsUnsafeContainerReferences() {
        XCTAssertThrowsError(try DockerManager.validatedContainerReference("web;rm"))
        XCTAssertThrowsError(try DockerManager.validatedContainerReference("../web"))
    }

    func testDockerManagerRejectsUnsafeImageReferences() {
        XCTAssertThrowsError(try DockerManager.validatedImageReference("nginx;rm"))
        XCTAssertThrowsError(try DockerManager.validatedImageReference("../nginx"))
        XCTAssertThrowsError(try DockerManager.validatedImageReference("registry.example.com//nginx:latest"))
        XCTAssertEqual(try DockerManager.validatedImageReference("registry.example.com/team/nginx:1.25"), "registry.example.com/team/nginx:1.25")
        XCTAssertEqual(try DockerManager.validatedImageReference("nginx@sha256:abcdef"), "nginx@sha256:abcdef")
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

    func testPubHostedRepositoryAssistantBuildsDartAndFlutterConfiguration() throws {
        let plan = try PubHostedRepositoryAssistant.buildPlan(
            draft: PubHostedRepositoryDraft(
                hostedURL: "https://pub.example.com/",
                packageName: "team_package",
                tokenEnvironmentVariable: "HHC_PUB_TOKEN",
                includeFlutterCommand: true
            ),
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(plan.hostedURL, "https://pub.example.com")
        XCTAssertEqual(plan.packageName, "team_package")
        XCTAssertEqual(plan.tokenEnvironmentVariable, "HHC_PUB_TOKEN")
        XCTAssertTrue(plan.pubspecSnippet.contains("hosted: https://pub.example.com"))
        XCTAssertTrue(plan.pubspecSnippet.contains("team_package:"))
        XCTAssertEqual(plan.publishToSnippet, "publish_to: https://pub.example.com")
        XCTAssertEqual(plan.tokenCommand, "dart pub token add https://pub.example.com --env-var HHC_PUB_TOKEN")
        XCTAssertEqual(plan.publishCommand, "dart pub publish")
        XCTAssertEqual(plan.getCommand, "dart pub get")
        XCTAssertEqual(plan.flutterGetCommand, "flutter pub get")
        XCTAssertTrue(plan.checks.allSatisfy { $0.status == .passed })
        XCTAssertTrue(plan.warnings.contains { $0.contains("source control") })
        XCTAssertEqual(plan.generatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testPubHostedRepositoryAssistantWarnsForHttpInternalRepository() throws {
        let plan = try PubHostedRepositoryAssistant.buildPlan(
            draft: PubHostedRepositoryDraft(
                hostedURL: "http://pub.internal:8080/team",
                packageName: "team_package",
                tokenEnvironmentVariable: "PUB_TOKEN",
                includeFlutterCommand: false
            )
        )

        XCTAssertEqual(plan.hostedURL, "http://pub.internal:8080/team")
        XCTAssertNil(plan.flutterGetCommand)
        XCTAssertTrue(plan.checks.contains { $0.status == .warning })
        XCTAssertTrue(plan.warnings.contains { $0.contains("HTTP") })
    }

    func testPubHostedRepositoryAssistantRejectsUnsafeInputs() {
        XCTAssertThrowsError(try PubHostedRepositoryAssistant.buildPlan(
            draft: PubHostedRepositoryDraft(hostedURL: "https://user:secret@pub.example.com", packageName: "team_package")
        )) { error in
            XCTAssertEqual(error as? PubHostedRepositoryAssistantError, .invalidHostedURL)
        }

        XCTAssertThrowsError(try PubHostedRepositoryAssistant.buildPlan(
            draft: PubHostedRepositoryDraft(hostedURL: "https://pub.example.com?token=secret", packageName: "team_package")
        )) { error in
            XCTAssertEqual(error as? PubHostedRepositoryAssistantError, .invalidHostedURL)
        }

        XCTAssertThrowsError(try PubHostedRepositoryAssistant.buildPlan(
            draft: PubHostedRepositoryDraft(hostedURL: "https://pub.example.com", packageName: "TeamPackage")
        )) { error in
            XCTAssertEqual(error as? PubHostedRepositoryAssistantError, .invalidPackageName)
        }

        XCTAssertThrowsError(try PubHostedRepositoryAssistant.buildPlan(
            draft: PubHostedRepositoryDraft(
                hostedURL: "https://pub.example.com",
                packageName: "team_package",
                tokenEnvironmentVariable: "pub-token"
            )
        )) { error in
            XCTAssertEqual(error as? PubHostedRepositoryAssistantError, .invalidTokenEnvironmentVariable)
        }
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

        XCTAssertTrue(command.contains("registry_host=${registry_url#http://}"))
        XCTAssertTrue(command.contains("printf '//%s/:_auth=%s\\n' \"$registry_host\" \"$auth\""))
        XCTAssertTrue(command.contains("npm publish --userconfig \"$npmrc\" --registry \"$registry_url\" --access public"))
        XCTAssertTrue(command.contains("npm install \"$package_name@$package_version\" --userconfig \"$npmrc\" --registry \"$registry_url\""))
        XCTAssertTrue(command.contains("npm unpublish \"$package_name@$package_version\" --userconfig \"$npmrc\" --registry \"$registry_url\" --force"))
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
        XCTAssertTrue(upgradeCommand.contains("npm install --prefix '/srv/verdaccio' --omit=dev --no-audit --no-fund 'verdaccio@5.31.2'"))
        XCTAssertTrue(upgradeCommand.contains("__HHC_VERDACCIO_SERVICE_UPGRADE__"))
        XCTAssertTrue(try VerdaccioConfigurationBuilder.systemdService(for: draft).contains("/srv/verdaccio/node_modules/.bin/verdaccio"))
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
        XCTAssertTrue(client.commands.contains { $0.contains("for attempt in $(seq 1 8)") && $0.contains("http://127.0.0.1:4873/-/ping") })
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
        XCTAssertTrue(command.contains("npm install --prefix \"$install_path\" --omit=dev --no-audit --no-fund 'verdaccio@5.31.1'"))
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
        XCTAssertTrue(client.commands[1].contains("for attempt in $(seq 1 8)"))
        XCTAssertTrue(client.commands[1].contains("http://127.0.0.1:4873/-/ping"))
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

    func testVerdaccioManagerParsesPackageDetail() throws {
        let detail = try VerdaccioManager.parsePackageDetail(
            Data("""
            {
              "name": "@team/ui",
              "dist-tags": { "latest": "1.1.0", "beta": "1.2.0-beta.1" },
              "readme": "# UI\\nPrivate package",
              "time": { "1.0.0": "2026-06-28T01:00:00Z", "1.1.0": "2026-06-28T02:00:00Z" },
              "_attachments": {
                "ui-1.0.0.tgz": { "length": 1024 },
                "ui-1.1.0.tgz": { "length": 2048 }
              },
              "versions": {
                "1.0.0": {
                  "description": "Initial",
                  "dependencies": { "lodash": "^4.17.21" },
                  "dist": { "tarball": "http://127.0.0.1:4873/@team/ui/-/ui-1.0.0.tgz" }
                },
                "1.1.0": {
                  "description": "Stable",
                  "dependencies": { "dayjs": "^1.11.0" },
                  "dist": { "tarball": "http://127.0.0.1:4873/@team/ui/-/ui-1.1.0.tgz" }
                }
              }
            }
            """.utf8),
            fallbackName: "@team/ui",
            registryURL: "http://127.0.0.1:4873",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(detail.name, "@team/ui")
        XCTAssertEqual(detail.latestVersion, "1.1.0")
        XCTAssertEqual(detail.distTags["beta"], "1.2.0-beta.1")
        XCTAssertEqual(detail.versions.map(\.version), ["1.1.0", "1.0.0"])
        XCTAssertEqual(detail.versions.first?.dependencies["dayjs"], "^1.11.0")
        XCTAssertEqual(detail.versions.first?.sizeBytes, 2048)
        XCTAssertEqual(detail.readme, "# UI\nPrivate package")
        XCTAssertEqual(detail.installCommand, "npm install @team/ui@1.1.0 --registry http://127.0.0.1:4873")
        XCTAssertEqual(detail.capturedAt, Date(timeIntervalSince1970: 1_700_000_000))
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

    func testVerdaccioManagerReadsPackageDetailFromStorage() async throws {
        let profile = makeServiceTestProfile()
        let metadata = Data("""
        {"name":"@team/ui","dist-tags":{"latest":"1.1.0"},"versions":{"1.1.0":{"description":"Stable"}}}
        """.utf8).base64EncodedString()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: metadata, stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let detail = try await manager.packageDetail(
            draft: VerdaccioInstallDraft(),
            packageName: "@team/ui",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(detail.name, "@team/ui")
        XCTAssertEqual(detail.latestVersion, "1.1.0")
        XCTAssertEqual(detail.installCommand, "npm install @team/ui@1.1.0 --registry http://127.0.0.1:4873")
        XCTAssertTrue(client.commands[0].contains("relative_path='@team/ui/package.json'"))
        XCTAssertTrue(client.commands[0].contains("base64 < \"$package_json\""))
    }

    func testVerdaccioManagerDeletesPackageWithBackupRestartAndHealthCheck() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "__HHC_VERDACCIO_PACKAGE_BACKUP__/srv/verdaccio/backups/verdaccio-package-team-ui-20260628-120000.tar.gz\n", stderr: "", exitCode: 0, duration: 0),
            CommandResult(command: "", stdout: "ok\n", stderr: "", exitCode: 0, duration: 0),
        ])
        let manager = VerdaccioManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await manager.deletePackage(
            draft: VerdaccioInstallDraft(),
            packageName: "@team/ui",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(result.packageName, "@team/ui")
        XCTAssertTrue(result.backupPath.hasPrefix("/srv/verdaccio/backups/verdaccio-package-team-ui-"))
        XCTAssertEqual(result.healthCheckOutput, "ok")
        XCTAssertTrue(client.commands[0].contains("relative_path='@team/ui'"))
        XCTAssertTrue(client.commands[0].contains("install -d -m 0750 \"$backup_dir\""))
        XCTAssertTrue(client.commands[0].contains("tar -czf \"$backup_path\""))
        XCTAssertTrue(client.commands[0].contains("rm -rf -- \"$package_dir\""))
        XCTAssertTrue(client.commands[0].contains("systemctl restart"))
        XCTAssertTrue(client.commands[0].contains("'verdaccio.service'"))
        XCTAssertTrue(client.commands[1].contains("127.0.0.1:4873/-/ping"))
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
        XCTAssertTrue(client.commands[1].contains("for attempt in $(seq 1 8)"))
        XCTAssertTrue(client.commands[1].contains("http://127.0.0.1:4873/-/ping"))
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
        XCTAssertEqual(DashboardService.parseUptime("up 2 weeks, 3 days, 4 hours\n"), "2 weeks, 3 days, 4 hours")
        XCTAssertEqual(DashboardService.parseUptime("1d 2h 3m\n"), "1d 2h 3m")
        XCTAssertEqual(DashboardService.parseProcessSummary("total=120 running=2 sleeping=117 stopped=0 zombie=1\n"), "120 / 2 / 1")
        XCTAssertEqual(DashboardService.parseNetworkTotals("""
            Inter-|   Receive                                                |  Transmit
             face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
                lo: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0
              eth0: 1048576 0 0 0 0 0 0 0 2097152 0 0 0 0 0 0 0
              ens5: 524288 0 0 0 0 0 0 0 1048576 0 0 0 0 0 0 0
        """), "1.5 MiB / 3.0 MiB")
        XCTAssertEqual(DashboardService.parsePrimaryNetworkInterface("""
            Inter-|   Receive                                                |  Transmit
             face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
                lo: 9999999 0 0 0 0 0 0 0 9999999 0 0 0 0 0 0 0
              eth0: 1048576 0 0 0 0 0 0 0 1048576 0 0 0 0 0 0 0
              ens5: 524288 0 0 0 0 0 0 0 4194304 0 0 0 0 0 0 0
        """), "ens5 512.0 KiB / 4.0 MiB")
        XCTAssertEqual(DashboardService.parseNetworkInterfaceBreakdown("""
            Inter-|   Receive                                                |  Transmit
             face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
                lo: 9999999 0 0 0 0 0 0 0 9999999 0 0 0 0 0 0 0
              eth0: 1048576 0 0 0 0 0 0 0 1048576 0 0 0 0 0 0 0
              ens5: 524288 0 0 0 0 0 0 0 4194304 0 0 0 0 0 0 0
        """), "ens5 512.0 KiB / 4.0 MiB; eth0 1.0 MiB / 1.0 MiB")

        let memory = DashboardService.parseMemoryUsage("""
        MemTotal:        2048000 kB
        MemAvailable:    1024000 kB
        """)
        XCTAssertEqual(memory, "1000 MiB / 2.0 GiB")

        let disk = DashboardService.parseRootDiskUsage("/dev/vda1 20971520 10485760 10485760 50% /")
        XCTAssertEqual(disk, "10.0 GiB / 20.0 GiB")
    }

    func testNetworkTrafficInspectorParsesAndSummarizesInterfaces() {
        let interfaces = NetworkTrafficInspector.parseInterfaceBreakdown(
            "eth0 1.0 MiB / 3.0 MiB; ens5 2.0 MiB / 1.0 MiB; invalid; enp1s0 512.0 KiB / 512.0 KiB"
        )

        XCTAssertEqual(interfaces.map(\.name), ["eth0", "ens5", "enp1s0"])
        XCTAssertEqual(interfaces[0].receivedBytes, 1_048_576, accuracy: 1)
        XCTAssertEqual(interfaces[0].transmittedBytes, 3_145_728, accuracy: 1)

        let summary = NetworkTrafficInspector.summary(for: interfaces)
        XCTAssertEqual(summary.interfaceCount, 3)
        XCTAssertEqual(summary.receivedBytes, 3_670_016, accuracy: 1)
        XCTAssertEqual(summary.transmittedBytes, 4_718_592, accuracy: 1)
        XCTAssertEqual(summary.busiestInterface?.name, "eth0")
        XCTAssertEqual(
            NetworkTrafficInspector.trafficShare(for: interfaces[0], in: summary),
            0.5,
            accuracy: 0.001
        )
    }

    func testNetworkTrafficInspectorFlagsSingleInterfaceDominance() {
        let interfaces = NetworkTrafficInspector.parseInterfaceBreakdown(
            "eth0 9.0 GiB / 1.0 GiB; ens5 256.0 MiB / 128.0 MiB"
        )
        let summary = NetworkTrafficInspector.summary(for: interfaces)

        let messages = NetworkTrafficInspector.attentionMessages(for: summary)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("eth0"))
        XCTAssertTrue(messages[0].contains("90%"))
        XCTAssertEqual(NetworkTrafficInspector.attentionMessages(for: NetworkTrafficInspector.summary(for: [])), [
            "未解析到非 lo 网卡明细，无法判断单网卡流量分布。",
        ])
    }

    func testDashboardServiceParsesCommonOSReleaseVariants() {
        let ubuntu = DashboardService.parseOSRelease("""
        NAME="Ubuntu"
        VERSION_ID="24.04"
        PRETTY_NAME="Ubuntu 24.04.2 LTS"
        """)
        XCTAssertEqual(ubuntu.name, "Ubuntu 24.04.2 LTS")
        XCTAssertEqual(ubuntu.version, "24.04")

        let debian = DashboardService.parseOSRelease("""
        NAME=Debian GNU/Linux
        VERSION="12 (bookworm)"
        VERSION_ID="12"
        """)
        XCTAssertEqual(debian.name, "Debian GNU/Linux 12 (bookworm)")
        XCTAssertEqual(debian.version, "12")

        let centOS = DashboardService.parseOSRelease("""
        NAME="CentOS Linux"
        VERSION="7 (Core)"
        ID="centos"
        VERSION_ID="7"
        PRETTY_NAME="CentOS Linux 7 (Core)"
        """)
        XCTAssertEqual(centOS.name, "CentOS Linux 7 (Core)")
        XCTAssertEqual(centOS.version, "7")

        let almaLinux = DashboardService.parseOSRelease("""
        # AlmaLinux common layout
        NAME="AlmaLinux"
        VERSION="9.4 (Seafoam Ocelot)"
        ID="almalinux"
        VERSION_ID="9.4"
        PRETTY_NAME="AlmaLinux 9.4 (Seafoam Ocelot)"
        """)
        XCTAssertEqual(almaLinux.name, "AlmaLinux 9.4 (Seafoam Ocelot)")
        XCTAssertEqual(almaLinux.version, "9.4")

        let escaped = DashboardService.parseOSRelease("""
        NAME='Custom Linux'
        VERSION_ID='1.0'
        PRETTY_NAME="Custom \\"Linux\\""
        """)
        XCTAssertEqual(escaped.name, "Custom \"Linux\"")
        XCTAssertEqual(escaped.version, "1.0")
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

    func testSystemdServiceClassifierSummarizesAndRecognizesApplications() throws {
        let units = [
            SystemdUnit(
                name: "nginx.service",
                loadState: "loaded",
                activeState: "active",
                subState: "running",
                description: "A high performance web server"
            ),
            SystemdUnit(
                name: "verdaccio.service",
                loadState: "loaded",
                activeState: "inactive",
                subState: "dead",
                description: "Private npm registry"
            ),
            SystemdUnit(
                name: "broken-worker.service",
                loadState: "loaded",
                activeState: "failed",
                subState: "failed",
                description: "Background job"
            ),
            SystemdUnit(
                name: "ssh.service",
                loadState: "loaded",
                activeState: "active",
                subState: "running",
                description: "OpenBSD Secure Shell server"
            ),
        ]

        let summary = SystemdServiceClassifier.summary(for: units)
        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.running, 2)
        XCTAssertEqual(summary.stopped, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.commonApplications, 2)
        XCTAssertEqual(SystemdServiceClassifier.commonApplicationName(for: units[0]), "Nginx")
        XCTAssertEqual(SystemdServiceClassifier.commonApplicationName(for: units[1]), "Verdaccio")
        XCTAssertTrue(SystemdServiceClassifier.isFailed(units[2]))
        XCTAssertFalse(SystemdServiceClassifier.isCommonApplication(units[3]))
    }

    func testDatabaseServiceManagerParsesSnapshotAndFillsMissingKinds() throws {
        let log = Data("2026-06-28T01:00:00 mysql started\n".utf8).base64EncodedString()
        let services = DatabaseServiceManager.parseSnapshot("""
        __HHC_DB_ROW__\tmysql\tmysqld.service\tactive\trunning\tyes\tmysql  Ver 8.0.42\t0.0.0.0:3306\t/var/lib/mysql\t\(log)
        __HHC_DB_ROW__\tredis\t\tunknown\tunknown\tno\t\t\t\t
        """)

        XCTAssertEqual(services.map(\.kind), DatabaseServiceKind.allCases)
        let mysql = try XCTUnwrap(services.first { $0.kind == .mysql })
        XCTAssertEqual(mysql.unitName, "mysqld.service")
        XCTAssertTrue(mysql.isRunning)
        XCTAssertEqual(mysql.version, "mysql  Ver 8.0.42")
        XCTAssertEqual(mysql.listenEndpoints, ["0.0.0.0:3306"])
        XCTAssertEqual(mysql.dataPath, "/var/lib/mysql")
        XCTAssertTrue(mysql.recentLog?.contains("mysql started") == true)

        let redis = try XCTUnwrap(services.first { $0.kind == .redis })
        XCTAssertFalse(redis.isInstalled)
        XCTAssertNil(redis.unitName)

        let postgresql = try XCTUnwrap(services.first { $0.kind == .postgresql })
        XCTAssertFalse(postgresql.isInstalled)
        XCTAssertEqual(postgresql.statusText, "not found")
    }

    func testDatabaseServiceManagerBuildsBackupRestorePlans() throws {
        let mysql = DatabaseService(
            kind: .mysql,
            unitName: "mysqld.service",
            activeState: "active",
            subState: "running",
            isInstalled: true,
            version: "mysql  Ver 8.0.42",
            listenEndpoints: ["127.0.0.1:3306"],
            dataPath: "/var/lib/mysql",
            recentLog: nil
        )
        let mysqlPlan = DatabaseServiceManager.backupRestorePlan(for: mysql, timestamp: "20260628-120000")

        XCTAssertEqual(mysqlPlan.backupPath, "~/hhc-db-backups/mysql-20260628-120000.sql.gz")
        XCTAssertTrue(mysqlPlan.backupCommand.contains("mysqldump --single-transaction"))
        XCTAssertTrue(mysqlPlan.restoreCommand.contains("gunzip -c ~/hhc-db-backups/mysql-20260628-120000.sql.gz | mysql"))
        XCTAssertTrue(mysqlPlan.warnings.contains { $0.contains("恢复会覆盖") })

        let postgresql = DatabaseService(
            kind: .postgresql,
            unitName: "postgresql.service",
            activeState: "active",
            subState: "running",
            isInstalled: true,
            version: "psql (PostgreSQL) 15.8",
            listenEndpoints: ["127.0.0.1:5432"],
            dataPath: "/var/lib/postgresql",
            recentLog: nil
        )
        let postgresqlPlan = DatabaseServiceManager.backupRestorePlan(for: postgresql, timestamp: "20260628-120000")

        XCTAssertTrue(postgresqlPlan.backupCommand.contains("sudo -u postgres pg_dumpall"))
        XCTAssertTrue(postgresqlPlan.restoreCommand.contains("sudo -u postgres psql"))

        let redis = DatabaseService(
            kind: .redis,
            unitName: "redis-server.service",
            activeState: "active",
            subState: "running",
            isInstalled: true,
            version: "Redis server v=7.2.0",
            listenEndpoints: ["127.0.0.1:6379"],
            dataPath: "/srv/redis",
            recentLog: nil
        )
        let redisPlan = DatabaseServiceManager.backupRestorePlan(for: redis, timestamp: "20260628-120000")

        XCTAssertTrue(redisPlan.backupCommand.contains("redis-cli BGSAVE"))
        XCTAssertTrue(redisPlan.backupCommand.contains("/srv/redis/dump.rdb"))
        XCTAssertTrue(redisPlan.restoreCommand.contains("systemctl stop redis-server.service"))
        XCTAssertTrue(redisPlan.restoreCommand.contains("systemctl start redis-server.service"))
    }

    func testDatabaseServiceInspectorSummarizesAndFiltersServices() {
        let services = [
            DatabaseService(
                kind: .mysql,
                unitName: "mysql.service",
                activeState: "active",
                subState: "running",
                isInstalled: true,
                version: "mysql 8",
                listenEndpoints: ["127.0.0.1:3306"],
                dataPath: "/var/lib/mysql",
                recentLog: nil
            ),
            DatabaseService(
                kind: .postgresql,
                unitName: "postgresql.service",
                activeState: "inactive",
                subState: "dead",
                isInstalled: true,
                version: "psql 15",
                listenEndpoints: [],
                dataPath: "/var/lib/postgresql",
                recentLog: nil
            ),
            DatabaseService(
                kind: .redis,
                unitName: nil,
                activeState: "missing",
                subState: "missing",
                isInstalled: false,
                version: nil,
                listenEndpoints: [],
                dataPath: nil,
                recentLog: nil
            ),
        ]

        let summary = DatabaseServiceInspector.summary(for: services)

        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.installed, 2)
        XCTAssertEqual(summary.running, 1)
        XCTAssertEqual(summary.attention, 1)
        XCTAssertEqual(summary.missing, 1)
        XCTAssertEqual(DatabaseServiceInspector.filter(services, by: .installed).map(\.kind), [.mysql, .postgresql])
        XCTAssertEqual(DatabaseServiceInspector.filter(services, by: .running).map(\.kind), [.mysql])
        XCTAssertEqual(DatabaseServiceInspector.filter(services, by: .attention).map(\.kind), [.postgresql])
        XCTAssertEqual(DatabaseServiceInspector.filter(services, by: .missing).map(\.kind), [.redis])
    }

    func testDatabaseServiceManagerCreatesBackup() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(command: "", stdout: "backup complete\n", stderr: "", exitCode: 0, duration: 0),
        ])
        let service = DatabaseService(
            kind: .mysql,
            unitName: "mysqld.service",
            activeState: "active",
            subState: "running",
            isInstalled: true,
            version: "mysql  Ver 8.0.42",
            listenEndpoints: ["127.0.0.1:3306"],
            dataPath: "/var/lib/mysql",
            recentLog: nil
        )
        let manager = DatabaseServiceManager(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await manager.createBackup(service: service, profile: profile, sshClient: client)

        XCTAssertEqual(result.serviceKind, .mysql)
        XCTAssertEqual(result.backupPath, "~/hhc-db-backups/mysql-20231114-221320.sql.gz")
        XCTAssertTrue(result.output.contains("backup complete"))
        XCTAssertEqual(client.commands.first, "mkdir -p ~/hhc-db-backups && mysqldump --single-transaction --routines --events --all-databases | gzip > ~/hhc-db-backups/mysql-20231114-221320.sql.gz")
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
        XCTAssertEqual(snapshot.entries.map(\.command), ["/usr/bin/backup", "/usr/local/bin/system-health"])
        XCTAssertNil(snapshot.entries[0].sourcePath)
        XCTAssertEqual(snapshot.entries[1].sourcePath, "/etc/cron.d/hhc-system")
        XCTAssertEqual(snapshot.entries[1].runAsUser, "root")
        let cronSummary = CronEntryClassifier.summary(for: snapshot.entries)
        XCTAssertEqual(cronSummary.total, 2)
        XCTAssertEqual(cronSummary.enabled, 2)
        XCTAssertEqual(cronSummary.disabled, 0)
        XCTAssertEqual(cronSummary.userEntries, 1)
        XCTAssertEqual(cronSummary.systemEntries, 1)
        XCTAssertEqual(CronEntryClassifier.sourceTitle(for: snapshot.entries[0]), "User crontab")
        XCTAssertEqual(CronEntryClassifier.runAsTitle(for: snapshot.entries[0]), "SSH user")
        XCTAssertEqual(CronEntryClassifier.sourceTitle(for: snapshot.entries[1]), "/etc/cron.d/hhc-system")
        XCTAssertEqual(CronEntryClassifier.runAsTitle(for: snapshot.entries[1]), "root")
        do {
            try await manager.perform(.delete, entry: snapshot.entries[1], profile: profile, sshClient: client)
            XCTFail("Expected system cron entry mutation to fail.")
        } catch SSHClientError.processFailed(let message) {
            XCTAssertTrue(message.contains("read-only"))
        }

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

        let sites = NginxConfigManager.parseSites(in: """
        server {
            listen 80;
            server_name example.com www.example.com;
            root /var/www/example;
        }
        server {
            listen 443 ssl http2;
            server_name api.example.com;
            # proxy_pass http://ignored.internal;
            location / {
                proxy_pass http://127.0.0.1:3000;
            }
            ssl_certificate /etc/letsencrypt/live/api/fullchain.pem;
        }
        """, configPath: "/etc/nginx/conf.d/example.conf")
        XCTAssertEqual(sites.count, 2)
        XCTAssertEqual(sites[0].serverNames, ["example.com", "www.example.com"])
        XCTAssertEqual(sites[0].listen, ["80"])
        XCTAssertEqual(sites[0].root, "/var/www/example")
        XCTAssertFalse(sites[0].hasSSL)
        XCTAssertEqual(sites[1].serverNames, ["api.example.com"])
        XCTAssertEqual(sites[1].listen, ["443 ssl http2"])
        XCTAssertTrue(sites[1].hasSSL)
        XCTAssertEqual(sites[1].sslCertificatePaths, ["/etc/letsencrypt/live/api/fullchain.pem"])
        XCTAssertEqual(sites[1].proxyPasses, ["http://127.0.0.1:3000"])
        let certificates = NginxConfigManager.parseCertificateInspections("""
        __HHC_NGINX_CERT__\t/etc/letsencrypt/live/api/fullchain.pem
        __HHC_NGINX_CERT_NOT_AFTER__\tJun 20 12:00:00 2027 GMT
        __HHC_NGINX_CERT_SUBJECT__\tCN=api.example.com
        __HHC_NGINX_CERT_ISSUER__\tCN=R3
        """)
        let certificateExpiry = Date(timeIntervalSince1970: 1_813_492_800)
        XCTAssertEqual(certificates["/etc/letsencrypt/live/api/fullchain.pem"]?.notAfter, certificateExpiry)
        XCTAssertEqual(certificates["/etc/letsencrypt/live/api/fullchain.pem"]?.subject, "CN=api.example.com")

        let list = try await manager.listConfigs(profile: profile, sshClient: client)
        XCTAssertEqual(list.files.map(\.path), ["/www/server/nginx/conf/nginx.conf", "/www/server/nginx/conf/vhost/site.conf"])
        XCTAssertTrue(client.commands.contains { $0.contains("nginx -V") })

        let content = try await manager.readConfig(file: list.files[0], profile: profile, sshClient: client)
        XCTAssertEqual(content.content, "user www-data;\n")
        XCTAssertTrue(client.commands.contains { $0.contains("base64 < '/www/server/nginx/conf/nginx.conf'") })

        let siteList = try await manager.listSites(profile: profile, sshClient: client)
        let sslSite = try XCTUnwrap(siteList.sites.first { $0.primaryName == "api.example.com" })
        XCTAssertEqual(sslSite.sslCertificatePaths, ["/etc/letsencrypt/live/api/fullchain.pem"])
        XCTAssertEqual(sslSite.sslCertificates.first?.notAfter, certificateExpiry)
        XCTAssertTrue(client.commands.contains { $0.contains("openssl x509") })

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

    func testNginxSiteInspectorSummarizesAndFiltersSites() {
        let staticSite = NginxSite(
            configPath: "/etc/nginx/conf.d/static.conf",
            blockIndex: 0,
            serverNames: ["example.com"],
            listen: ["80"],
            root: "/var/www/example",
            hasSSL: false,
            sslCertificatePaths: [],
            sslCertificates: [],
            proxyPasses: []
        )
        let proxySite = NginxSite(
            configPath: "/etc/nginx/conf.d/api.conf",
            blockIndex: 0,
            serverNames: ["api.example.com"],
            listen: ["443 ssl"],
            root: nil,
            hasSSL: true,
            sslCertificatePaths: ["/etc/letsencrypt/live/api/fullchain.pem"],
            sslCertificates: [
                NginxSSLCertificate(
                    path: "/etc/letsencrypt/live/api/fullchain.pem",
                    subject: "CN=api.example.com",
                    issuer: "CN=R3",
                    notAfter: Date(timeIntervalSince1970: 2_000_000_000),
                    inspectionError: nil
                ),
            ],
            proxyPasses: ["http://127.0.0.1:3000"]
        )
        let brokenSSL = NginxSite(
            configPath: "/etc/nginx/conf.d/broken.conf",
            blockIndex: 0,
            serverNames: ["broken.example.com"],
            listen: ["443 ssl"],
            root: "/var/www/broken",
            hasSSL: true,
            sslCertificatePaths: ["/etc/ssl/missing.pem"],
            sslCertificates: [
                NginxSSLCertificate(
                    path: "/etc/ssl/missing.pem",
                    subject: nil,
                    issuer: nil,
                    notAfter: nil,
                    inspectionError: "cannot read certificate"
                ),
            ],
            proxyPasses: []
        )
        let sites = [staticSite, proxySite, brokenSSL]

        let summary = NginxSiteInspector.summary(for: sites)

        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.sslEnabled, 2)
        XCTAssertEqual(summary.reverseProxy, 1)
        XCTAssertEqual(summary.staticSites, 2)
        XCTAssertEqual(summary.certificateIssues, 1)
        XCTAssertEqual(NginxSiteInspector.filter(sites, by: .ssl).map(\.primaryName), ["api.example.com", "broken.example.com"])
        XCTAssertEqual(NginxSiteInspector.filter(sites, by: .reverseProxy).map(\.primaryName), ["api.example.com"])
        XCTAssertEqual(NginxSiteInspector.filter(sites, by: .staticSite).map(\.primaryName), ["example.com", "broken.example.com"])
        XCTAssertEqual(NginxSiteInspector.filter(sites, by: .certificateIssues).map(\.primaryName), ["broken.example.com"])
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
        let nftSnapshot = FirewallSnapshot(
            backend: .nft,
            status: "installed",
            rulesText: """
            table inet filter {
              chain input {
                type filter hook input priority 0; policy accept;
              }
              chain output {
                type filter hook output priority 0; policy accept;
              }
            }
            """,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(
            try FirewallManager.command(for: draft, snapshot: nftSnapshot),
            "nft add rule inet 'filter' 'input' ip saddr '203.0.113.0/24' tcp dport 443 counter accept comment 'hhc:ingress:allow:tcp:443:203.0.113.0/24'"
        )
        let deleteDraft = FirewallRuleDraft(
            mutation: .delete,
            direction: .egress,
            action: .deny,
            proto: .udp,
            port: 53,
            cidr: "198.51.100.10/32"
        )
        let deleteCommand = try FirewallManager.command(for: deleteDraft, snapshot: nftSnapshot)
        XCTAssertTrue(deleteCommand.contains("nft -a list chain inet 'filter' 'output'"))
        XCTAssertTrue(deleteCommand.contains("sprintf(\"%c\", 34) marker sprintf(\"%c\", 34)"))
        XCTAssertTrue(deleteCommand.contains("nft delete rule inet 'filter' 'output' handle \"$handle\""))
        XCTAssertThrowsError(try FirewallManager.command(for: draft, snapshot: FirewallSnapshot(
            backend: .nft,
            status: "installed",
            rulesText: "table ip nat { chain prerouting { type nat hook prerouting priority 0; } }",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )))
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

        let analysis = EnvironmentVariableInspector.analyze("""
        # comment
        APP_ENV=prod
        export API_TOKEN=secret
        DATABASE_PASSWORD="hidden"
        invalid-key=value
        """)
        XCTAssertEqual(analysis.keys, ["API_TOKEN", "APP_ENV", "DATABASE_PASSWORD"])
        XCTAssertEqual(analysis.sensitiveKeys, ["API_TOKEN", "DATABASE_PASSWORD"])
        XCTAssertEqual(EnvironmentVariableInspector.maskedKeyList(analysis.sensitiveKeys), "API_TOKEN, DATABASE_PASSWORD")

        let changes = EnvironmentVariableInspector.changeSummary(
            from: "APP_ENV=prod\nOLD_KEY=1\nUNCHANGED=yes\n",
            to: "APP_ENV=staging\nNEW_KEY=2\nUNCHANGED=yes\n"
        )
        XCTAssertEqual(changes.addedKeys, ["NEW_KEY"])
        XCTAssertEqual(changes.changedKeys, ["APP_ENV"])
        XCTAssertEqual(changes.removedKeys, ["OLD_KEY"])
        XCTAssertEqual(changes.allChangedKeys, ["APP_ENV", "NEW_KEY", "OLD_KEY"])

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
            securityGroupIds: ["sg-123"],
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
        XCTAssertTrue(snapshot.metrics.contains(DashboardMetric(name: "Cloud Memory", value: "21.2", unit: "%", source: "Cloud API")))
        XCTAssertTrue(snapshot.metrics.contains(DashboardMetric(name: "Cloud Disk Read", value: "21.2", unit: "B/s", source: "Cloud API")))
        XCTAssertTrue(snapshot.metrics.contains(DashboardMetric(name: "Cloud Disk Write", value: "21.2", unit: "B/s", source: "Cloud API")))
        XCTAssertTrue(snapshot.metrics.contains(DashboardMetric(name: "Cloud Network In", value: "21.2", unit: "B/s", source: "Cloud API")))
        XCTAssertTrue(snapshot.metrics.contains(DashboardMetric(name: "Cloud Network Out", value: "21.2", unit: "B/s", source: "Cloud API")))
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

    func testRemoteFileServiceCreatesFilesAndDirectoriesWithoutOverwrite() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let file = try await service.createItem(
            named: "notes.txt",
            kind: .file,
            inDirectoryPath: "/var/www",
            profile: profile,
            sshClient: client
        )
        let directory = try await service.createItem(
            named: "assets",
            kind: .directory,
            inDirectoryPath: "/var/www",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(file.path, "/var/www/notes.txt")
        XCTAssertEqual(file.kind, .file)
        XCTAssertEqual(file.size, 0)
        XCTAssertEqual(directory.path, "/var/www/assets")
        XCTAssertEqual(directory.kind, .directory)
        XCTAssertEqual(client.commands, [
            "set -e; test ! -e '/var/www/notes.txt'; : > '/var/www/notes.txt'",
            "mkdir -- '/var/www/assets'",
        ])
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

    func testRemoteFileServiceRejectsUnsafeCreateTargets() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService()

        do {
            _ = try await service.createItem(
                named: "../bad",
                kind: .file,
                inDirectoryPath: "/var/www",
                profile: profile,
                sshClient: client
            )
            XCTFail("Expected invalid create target.")
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
            securityGroupIds: [],
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
            securityGroupIds: [],
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
            securityGroupIds: [],
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
            securityGroupIds: [],
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

    func testCloudSnapshotActionFailureWritesAuditLogWithoutPersistingSnapshot() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .alibabaCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudSnapshots, .snapshotActions],
            actionFailures: ["create_snapshot"]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_540)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .alibabaCloud,
            displayName: "Alibaba",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )

        do {
            _ = try await harness.cloudInstanceSyncService.createSnapshot(
                account: account,
                regionId: "ap-southeast-1",
                diskId: "d-1",
                snapshotName: "before-risky-change"
            )
            XCTFail("Expected create snapshot failure.")
        } catch {
            XCTAssertEqual(
                error as? CloudProviderError,
                .providerFailure("forced create_snapshot failure")
            )
        }

        XCTAssertTrue(try harness.repository.fetchCloudSnapshots(accountId: account.id).isEmpty)
        let log = try XCTUnwrap(try harness.repository.fetchRemoteChangeLogs().first { $0.action == "create_snapshot" })
        XCTAssertEqual(log.providerId, .alibabaCloud)
        XCTAssertEqual(log.targetId, "d-1")
        XCTAssertEqual(log.status, "failed")
        XCTAssertTrue(log.message?.contains("forced create_snapshot failure") == true)
    }

    func testCloudDiskActionFailureWritesAuditLogWithoutMutatingDiskCache() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .huaweiCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudDisks, .diskAttachmentActions],
            actionFailures: ["attach_disk"]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_550)
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
            diskId: "vol-fail",
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

        do {
            try await harness.cloudInstanceSyncService.attachDisk(
                account: account,
                regionId: "ap-southeast-1|project-1",
                diskId: "vol-fail",
                instanceId: "server-target",
                currentStatus: "available"
            )
            XCTFail("Expected attach disk failure.")
        } catch {
            XCTAssertEqual(
                error as? CloudProviderError,
                .providerFailure("forced attach_disk failure")
            )
        }

        let disk = try XCTUnwrap(try harness.repository.fetchCloudDisks(accountId: account.id).first { $0.diskId == "vol-fail" })
        XCTAssertNil(disk.instanceId)
        XCTAssertEqual(disk.status, "available")
        let log = try XCTUnwrap(try harness.repository.fetchRemoteChangeLogs().first { $0.action == "attach_disk" })
        XCTAssertEqual(log.providerId, .huaweiCloud)
        XCTAssertEqual(log.targetId, "vol-fail")
        XCTAssertEqual(log.status, "failed")
        XCTAssertTrue(log.message?.contains("forced attach_disk failure") == true)
    }

    func testCloudInstancePowerActionFailureWritesAuditLogWithoutMutatingInstanceCache() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .alibabaCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .powerActions],
            actionFailures: ["stop_instance"]
        )
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_560)
        let harness = try Harness(adapters: [adapter], now: { capturedAt })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .alibabaCloud,
            displayName: "Alibaba",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let link = CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: account.id,
            providerId: .alibabaCloud,
            regionId: "ap-southeast-1",
            instanceId: "i-fail",
            displayName: "prod",
            publicIp: "203.0.113.12",
            privateIp: "10.0.0.12",
            status: "Running",
            instanceType: "ecs.g7.large",
            zoneId: "ap-southeast-1a",
            vpcId: "vpc-1",
            securityGroupIds: [],
            rawJSON: nil,
            lastSyncedAt: nil
        )
        try harness.repository.upsertCloudInstanceLink(link)

        do {
            try await harness.cloudInstanceSyncService.stopInstance(
                account: account,
                regionId: "ap-southeast-1",
                instanceId: "i-fail",
                currentStatus: "Running"
            )
            XCTFail("Expected stop instance failure.")
        } catch {
            XCTAssertEqual(
                error as? CloudProviderError,
                .providerFailure("forced stop_instance failure")
            )
        }

        let storedLink = try harness.repository.fetchCloudInstanceLink(
            accountId: account.id,
            regionId: "ap-southeast-1",
            instanceId: "i-fail"
        )
        XCTAssertEqual(storedLink.status, "Running")
        XCTAssertNil(storedLink.lastSyncedAt)
        let log = try XCTUnwrap(try harness.repository.fetchRemoteChangeLogs().first { $0.action == "stop_instance" })
        XCTAssertEqual(log.providerId, .alibabaCloud)
        XCTAssertEqual(log.targetId, "i-fail")
        XCTAssertEqual(log.status, "failed")
        XCTAssertTrue(log.message?.contains("forced stop_instance failure") == true)
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
            securityGroupIds: [],
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
                    "VirtualPrivateCloud": {"VpcId": "vpc-1"},
                    "SecurityGroupIds": ["sg-web", "sg-ssh"]
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
        XCTAssertEqual(instances[0].securityGroupIds, ["sg-web", "sg-ssh"])
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

    func testTencentCloudAdapterMapsDashboardMetricNames() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "MetricName": "MemUsage",
                "DataPoints": [
                  {
                    "Dimensions": [{"Name": "InstanceId", "Value": "ins-1"}],
                    "Timestamps": [1700000300],
                    "Values": [63.5]
                  }
                ],
                "RequestId": "request-monitor-memory"
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
                metricName: "MemoryUsage",
                instanceId: "ins-1",
                regionId: "ap-guangzhou",
                period: 300,
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                endTime: Date(timeIntervalSince1970: 1_700_000_300)
            )
        )

        XCTAssertEqual(series.metricName, "MemoryUsage")
        XCTAssertEqual(series.unit, "%")
        XCTAssertEqual(series.values, [63.5])
        XCTAssertEqual(transport.requests[0].jsonBody?["MetricName"] as? String, "MemUsage")
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
            securityGroupIds: ["sg-123"],
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

    func testCloudMetricServiceLoadsLinkedTencentCloudDashboardMetrics() async throws {
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
            securityGroupIds: [],
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
            DashboardMetric(name: "Cloud CPU", value: "21.2", unit: "%", source: "Cloud API"),
            DashboardMetric(name: "Cloud Memory", value: "21.2", unit: "%", source: "Cloud API"),
            DashboardMetric(name: "Cloud Disk Read", value: "21.2", unit: "B/s", source: "Cloud API"),
            DashboardMetric(name: "Cloud Disk Write", value: "21.2", unit: "B/s", source: "Cloud API"),
            DashboardMetric(name: "Cloud Network In", value: "21.2", unit: "B/s", source: "Cloud API"),
            DashboardMetric(name: "Cloud Network Out", value: "21.2", unit: "B/s", source: "Cloud API"),
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
                    },
                    "SecurityGroupIds": {"SecurityGroupId": ["sg-web", "sg-ssh"]}
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
        XCTAssertEqual(instances[0].securityGroupIds, ["sg-web", "sg-ssh"])
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

    func testAlibabaCloudAdapterFetchesMetricSeriesUsesCloudMonitorAPI() async throws {
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let endTime = Date(timeIntervalSince1970: 1_700_000_600)
        let transport = MockAlibabaCloudTransport(responses: [
            #"""
            {
              "RequestId": "aliyun-metrics",
              "Code": "200",
              "Datapoints": "[{\"timestamp\":1700000600000,\"Average\":25.75},{\"timestamp\":1700000300000,\"Average\":\"20.5\"}]",
              "Period": "300"
            }
            """#,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { startTime },
            nonce: { "nonce-metric" },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK")

        let series = try await adapter.fetchMetricSeries(
            credential: credential,
            query: CloudMetricQuery(
                namespace: "QCE/CVM",
                metricName: "CPUUsage",
                instanceId: "i-1",
                regionId: "ap-southeast-1",
                period: 300,
                startTime: startTime,
                endTime: endTime
            )
        )

        XCTAssertTrue(adapter.capabilities.contains(.cloudMetrics))
        XCTAssertEqual(series.metricName, "CPUUsage")
        XCTAssertEqual(series.instanceId, "i-1")
        XCTAssertEqual(series.regionId, "ap-southeast-1")
        XCTAssertEqual(series.unit, "%")
        XCTAssertEqual(series.values, [20.5, 25.75])
        XCTAssertEqual(series.timestamps, [
            Date(timeIntervalSince1970: 1_700_000_300),
            Date(timeIntervalSince1970: 1_700_000_600),
        ])

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.host, "metrics.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-action"), "DescribeMetricList")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-version"), "2019-01-01")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-signature-nonce"), "nonce-metric")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("ACS3-HMAC-SHA256 Credential=ALIYUNAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("Namespace"), "acs_ecs_dashboard")
        XCTAssertEqual(transport.requests[0].queryValue("MetricName"), "CPUUtilization")
        XCTAssertEqual(transport.requests[0].queryValue("Dimensions"), #"{"instanceId":"i-1"}"#)
        XCTAssertEqual(transport.requests[0].queryValue("StartTime"), "1700000000000")
        XCTAssertEqual(transport.requests[0].queryValue("EndTime"), "1700000600000")
        XCTAssertEqual(transport.requests[0].queryValue("Period"), "300")
    }

    func testAlibabaCloudAdapterMapsDashboardMetricNames() async throws {
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let endTime = Date(timeIntervalSince1970: 1_700_000_600)
        let transport = MockAlibabaCloudTransport(responses: [
            #"""
            {
              "RequestId": "aliyun-network-metrics",
              "Code": "200",
              "Datapoints": "[{\"timestamp\":1700000600000,\"Average\":4096}]",
              "Period": "300"
            }
            """#,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { startTime },
            nonce: { "nonce-network" },
            timeout: 1
        )

        let series = try await adapter.fetchMetricSeries(
            credential: CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK"),
            query: CloudMetricQuery(
                namespace: "QCE/CVM",
                metricName: "NetworkInBytes",
                instanceId: "i-1",
                regionId: "ap-southeast-1",
                period: 300,
                startTime: startTime,
                endTime: endTime
            )
        )

        XCTAssertEqual(series.metricName, "NetworkInBytes")
        XCTAssertEqual(series.unit, "B/s")
        XCTAssertEqual(series.values, [4096])
        XCTAssertEqual(transport.requests[0].queryValue("MetricName"), "networkin_rate")
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

    func testAlibabaCloudAdapterAppliesSecurityGroupRuleChangesUsesSignedECSAPI() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockAlibabaCloudTransport(responses: [
            """
            {
              "RequestId": "request-authorize"
            }
            """,
            """
            {
              "RequestId": "request-revoke"
            }
            """,
        ])
        let adapter = AlibabaCloudAdapter(
            transport: transport,
            now: { capturedAt },
            nonce: { "nonce-sg-action" },
            timeout: 1
        )
        let group = CloudSecurityGroup(
            accountId: UUID(),
            providerId: .alibabaCloud,
            regionId: "ap-southeast-1",
            securityGroupId: "sg-1",
            name: "web",
            description: nil,
            projectId: "rg-1",
            isDefault: nil,
            createdTime: nil,
            updatedTime: nil
        )
        let addPreview = CloudSecurityGroupRuleChangePreview.adding(
            draft: CloudSecurityGroupRuleDraft(
                direction: .ingress,
                protocolName: "TCP",
                port: "443",
                cidrBlock: "203.0.113.0/24",
                action: "ACCEPT",
                description: "HTTPS"
            ),
            to: CloudSecurityGroupPolicySnapshot(group: group, version: nil, ingress: [], egress: [], capturedAt: capturedAt)
        )
        let removePreview = CloudSecurityGroupRuleChangePreview.removing(
            rule: CloudSecurityGroupRule(
                direction: .egress,
                policyIndex: 2,
                providerRuleId: nil,
                protocolName: "udp",
                port: "53/53",
                cidrBlock: "198.51.100.0/24",
                ipv6CidrBlock: nil,
                referencedSecurityGroupId: nil,
                action: "drop",
                description: "DNS deny",
                modifiedTime: nil
            ),
            from: CloudSecurityGroupPolicySnapshot(group: group, version: nil, ingress: [], egress: [], capturedAt: capturedAt)
        )
        let credential = CloudProviderCredential(secretId: "ALIYUNAK", secretKey: "ALIYUNSK")

        XCTAssertTrue(addPreview.commandPreview.hasPrefix("Alibaba Cloud AuthorizeSecurityGroup "))
        let authorizeRequestId = try await adapter.applySecurityGroupRuleChange(
            credential: credential,
            preview: addPreview
        )
        let revokeRequestId = try await adapter.applySecurityGroupRuleChange(
            credential: credential,
            preview: removePreview
        )

        XCTAssertTrue(adapter.capabilities.contains(.securityGroupActions))
        XCTAssertEqual(authorizeRequestId, "request-authorize")
        XCTAssertEqual(revokeRequestId, "request-revoke")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-action"), "AuthorizeSecurityGroup")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-acs-signature-nonce"), "nonce-sg-action")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("ACS3-HMAC-SHA256 Credential=ALIYUNAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("RegionId"), "ap-southeast-1")
        XCTAssertEqual(transport.requests[0].queryValue("SecurityGroupId"), "sg-1")
        XCTAssertEqual(transport.requests[0].queryValue("IpProtocol"), "tcp")
        XCTAssertEqual(transport.requests[0].queryValue("PortRange"), "443/443")
        XCTAssertEqual(transport.requests[0].queryValue("SourceCidrIp"), "203.0.113.0/24")
        XCTAssertEqual(transport.requests[0].queryValue("Policy"), "accept")
        XCTAssertEqual(transport.requests[0].queryValue("Priority"), "1")
        XCTAssertEqual(transport.requests[0].queryValue("Description"), "HTTPS")
        XCTAssertEqual(transport.requests[1].url?.host, "ecs.ap-southeast-1.aliyuncs.com")
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "x-acs-action"), "RevokeSecurityGroupEgress")
        XCTAssertEqual(transport.requests[1].queryValue("IpProtocol"), "udp")
        XCTAssertEqual(transport.requests[1].queryValue("PortRange"), "53/53")
        XCTAssertEqual(transport.requests[1].queryValue("DestCidrIp"), "198.51.100.0/24")
        XCTAssertEqual(transport.requests[1].queryValue("Policy"), "drop")
        XCTAssertEqual(transport.requests[1].queryValue("Priority"), "2")
        XCTAssertEqual(transport.requests[1].queryValue("Description"), "DNS deny")
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
                  "security_groups": [{"name": "sg-web"}, {"name": "sg-ssh"}],
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
        XCTAssertEqual(instances[0].securityGroupIds, ["sg-web", "sg-ssh"])
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

    func testHuaweiCloudAdapterFetchesMetricSeriesUsesCESAPI() async throws {
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let endTime = Date(timeIntervalSince1970: 1_700_000_600)
        let transport = MockHuaweiCloudTransport(responses: [
            """
            {
              "datapoints": [
                {"timestamp": 1700000600000, "average": 35.25, "unit": "%"},
                {"timestamp": "1700000300000", "average": "30.5", "unit": "%"}
              ]
            }
            """,
        ])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { startTime },
            timeout: 1
        )
        let credential = CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK")

        let series = try await adapter.fetchMetricSeries(
            credential: credential,
            query: CloudMetricQuery(
                namespace: "QCE/CVM",
                metricName: "CPUUsage",
                instanceId: "server-1",
                regionId: "ap-southeast-1|project-1",
                period: 300,
                startTime: startTime,
                endTime: endTime
            )
        )

        XCTAssertTrue(adapter.capabilities.contains(.cloudMetrics))
        XCTAssertEqual(series.metricName, "CPUUsage")
        XCTAssertEqual(series.instanceId, "server-1")
        XCTAssertEqual(series.regionId, "ap-southeast-1|project-1")
        XCTAssertEqual(series.unit, "%")
        XCTAssertEqual(series.values, [30.5, 35.25])
        XCTAssertEqual(series.timestamps, [
            Date(timeIntervalSince1970: 1_700_000_300),
            Date(timeIntervalSince1970: 1_700_000_600),
        ])

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].httpMethod, "GET")
        XCTAssertEqual(transport.requests[0].url?.host, "ces.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/V1.0/project-1/metric-data")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-Sdk-Date"), "20231114T221320Z")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("SDK-HMAC-SHA256 Access=HUAWEIAK") == true)
        XCTAssertEqual(transport.requests[0].queryValue("namespace"), "SYS.ECS")
        XCTAssertEqual(transport.requests[0].queryValue("metric_name"), "cpu_util")
        XCTAssertEqual(transport.requests[0].queryValue("dim.0"), "instance_id,server-1")
        XCTAssertEqual(transport.requests[0].queryValue("filter"), "average")
        XCTAssertEqual(transport.requests[0].queryValue("period"), "300")
        XCTAssertEqual(transport.requests[0].queryValue("from"), "1700000000000")
        XCTAssertEqual(transport.requests[0].queryValue("to"), "1700000600000")
    }

    func testHuaweiCloudAdapterMapsDashboardMetricNames() async throws {
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let endTime = Date(timeIntervalSince1970: 1_700_000_600)
        let transport = MockHuaweiCloudTransport(responses: [
            """
            {
              "datapoints": [
                {"timestamp": 1700000600000, "average": 8192, "unit": "B/s"}
              ]
            }
            """,
        ])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { startTime },
            timeout: 1
        )

        let series = try await adapter.fetchMetricSeries(
            credential: CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK"),
            query: CloudMetricQuery(
                namespace: "QCE/CVM",
                metricName: "NetworkOutBytes",
                instanceId: "server-1",
                regionId: "ap-southeast-1|project-1",
                period: 300,
                startTime: startTime,
                endTime: endTime
            )
        )

        XCTAssertEqual(series.metricName, "NetworkOutBytes")
        XCTAssertEqual(series.unit, "B/s")
        XCTAssertEqual(series.values, [8192])
        XCTAssertEqual(transport.requests[0].queryValue("metric_name"), "network_outgoing_bytes_rate")
    }

    func testHuaweiCloudAdapterFetchesBillingStatesFromInstancesAndDisks() async throws {
        let accountId = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockHuaweiCloudTransport(responses: [
            """
            {
              "count": 1,
              "servers": [
                {
                  "id": "server-1",
                  "name": "prod-hw",
                  "status": "ACTIVE",
                  "metadata": {"charging_mode": "prePaid"},
                  "addresses": {}
                }
              ]
            }
            """,
            """
            {
              "count": 1,
              "volumes": [
                {
                  "id": "vol-1",
                  "name": "prod-system",
                  "size": 80,
                  "status": "in-use",
                  "volume_type": "SSD",
                  "metadata": {"billingMode": "postPaid"}
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

        let states = try await adapter.fetchBillingStates(
            credential: credential,
            accountId: accountId,
            regionId: "ap-southeast-1|project-1",
            capturedAt: capturedAt
        )

        XCTAssertTrue(adapter.capabilities.contains(.cloudBilling))
        XCTAssertEqual(states.map(\.resourceType), ["instance", "disk"])
        XCTAssertEqual(states.map(\.resourceId), ["server-1", "vol-1"])
        XCTAssertEqual(states.map(\.providerId), [.huaweiCloud, .huaweiCloud])
        XCTAssertEqual(states.map(\.accountId), [accountId, accountId])
        XCTAssertEqual(states.map(\.billingType), ["prePaid", "postPaid"])
        XCTAssertEqual(states.map(\.status), ["ACTIVE", "in-use"])
        XCTAssertEqual(states.map(\.lastSyncedAt), [capturedAt, capturedAt])

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.host, "ecs.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/v1.1/project-1/cloudservers/detail")
        XCTAssertEqual(transport.requests[1].url?.host, "evs.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[1].url?.path, "/v2/project-1/cloudvolumes/detail")
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
        XCTAssertEqual(snapshot.ingress[0].providerRuleId, "rule-ingress")
        XCTAssertEqual(snapshot.egress.count, 1)
        XCTAssertEqual(snapshot.egress[0].protocolName, "any")
        XCTAssertNil(snapshot.egress[0].cidrBlock)
        XCTAssertEqual(snapshot.egress[0].ipv6CidrBlock, "2001:db8::/64")
        XCTAssertEqual(snapshot.egress[0].referencedSecurityGroupId, "sg-peer")
        XCTAssertEqual(snapshot.egress[0].providerRuleId, "rule-egress")
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

    func testHuaweiCloudAdapterAppliesSecurityGroupRuleChangesUsesSignedVPCAPI() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transport = MockHuaweiCloudTransport(responses: [
            """
            {
              "security_group_rule": {
                "id": "rule-created",
                "security_group_id": "sg-hw-1",
                "direction": "ingress",
                "ethertype": "IPv4",
                "protocol": "tcp",
                "port_range_min": 443,
                "port_range_max": 443,
                "remote_ip_prefix": "203.0.113.0/24",
                "action": "allow",
                "priority": 1
              }
            }
            """,
            "",
        ])
        let adapter = HuaweiCloudAdapter(
            transport: transport,
            now: { capturedAt },
            timeout: 1
        )
        let group = CloudSecurityGroup(
            accountId: UUID(),
            providerId: .huaweiCloud,
            regionId: "ap-southeast-1|project-1",
            securityGroupId: "sg-hw-1",
            name: "web",
            description: nil,
            projectId: "project-1",
            isDefault: nil,
            createdTime: nil,
            updatedTime: nil
        )
        let addPreview = CloudSecurityGroupRuleChangePreview.adding(
            draft: CloudSecurityGroupRuleDraft(
                direction: .ingress,
                protocolName: "TCP",
                port: "443",
                cidrBlock: "203.0.113.0/24",
                action: "ACCEPT",
                description: "HTTPS"
            ),
            to: CloudSecurityGroupPolicySnapshot(group: group, version: nil, ingress: [], egress: [], capturedAt: capturedAt)
        )
        let removePreview = CloudSecurityGroupRuleChangePreview.removing(
            rule: CloudSecurityGroupRule(
                direction: .egress,
                policyIndex: 2,
                providerRuleId: "rule-egress",
                protocolName: "udp",
                port: "53/53",
                cidrBlock: nil,
                ipv6CidrBlock: "2001:db8::/64",
                referencedSecurityGroupId: nil,
                action: "deny",
                description: "DNS deny",
                modifiedTime: nil
            ),
            from: CloudSecurityGroupPolicySnapshot(group: group, version: nil, ingress: [], egress: [], capturedAt: capturedAt)
        )
        let credential = CloudProviderCredential(secretId: "HUAWEIAK", secretKey: "HUAWEISK")

        XCTAssertTrue(addPreview.commandPreview.hasPrefix("Huawei Cloud CreateSecurityGroupRule "))
        let createdRuleId = try await adapter.applySecurityGroupRuleChange(
            credential: credential,
            preview: addPreview
        )
        let deletedRuleId = try await adapter.applySecurityGroupRuleChange(
            credential: credential,
            preview: removePreview
        )

        XCTAssertTrue(adapter.capabilities.contains(.securityGroupActions))
        XCTAssertEqual(createdRuleId, "rule-created")
        XCTAssertEqual(deletedRuleId, "rule-egress")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].httpMethod, "POST")
        XCTAssertEqual(transport.requests[0].url?.host, "vpc.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[0].url?.path, "/v3/project-1/vpc/security-group-rules")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-Sdk-Date"), "20231114T221320Z")
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("SDK-HMAC-SHA256 Access=HUAWEIAK") == true)
        let body = try XCTUnwrap(transport.requests[0].jsonBody?["security_group_rule"] as? [String: Any])
        XCTAssertEqual(body["security_group_id"] as? String, "sg-hw-1")
        XCTAssertEqual(body["direction"] as? String, "ingress")
        XCTAssertEqual(body["protocol"] as? String, "tcp")
        XCTAssertEqual(body["ethertype"] as? String, "IPv4")
        XCTAssertEqual(body["port_range_min"] as? Int, 443)
        XCTAssertEqual(body["port_range_max"] as? Int, 443)
        XCTAssertEqual(body["remote_ip_prefix"] as? String, "203.0.113.0/24")
        XCTAssertEqual(body["action"] as? String, "allow")
        XCTAssertEqual(body["priority"] as? Int, 1)
        XCTAssertEqual(body["description"] as? String, "HTTPS")
        XCTAssertEqual(transport.requests[1].httpMethod, "DELETE")
        XCTAssertEqual(transport.requests[1].url?.host, "vpc.ap-southeast-1.myhuaweicloud.com")
        XCTAssertEqual(transport.requests[1].url?.path, "/v3/project-1/vpc/security-group-rules/rule-egress")
        XCTAssertNil(transport.requests[1].httpBody)
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

    @MainActor
    private final class AppStateHarness {
        let repository: ServerRepository
        let keychain: KeychainService
        let appState: AppState

        init() throws {
            repository = ServerRepository(database: try AppDatabase.inMemory())
            keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.app-state.\(UUID().uuidString)")
            appState = AppState(repository: repository, keychain: keychain)
        }
    }
}

private final class FailingServerCredentialStore: ServerCredentialStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case writeFailed
    }

    private(set) var deletedCredentialRefs: [String] = []

    func savePassword(_ password: String, keychainRef: String) throws {
        throw Error.writeFailed
    }

    func readPassword(keychainRef: String) throws -> String? {
        nil
    }

    func savePrivateKey(_ data: Data, passphrase: String?, keychainRef: String) throws {
        throw Error.writeFailed
    }

    func readPrivateKey(keychainRef: String) throws -> Data? {
        nil
    }

    func readPrivateKeyPassphrase(keychainRef: String) throws -> String? {
        nil
    }

    func deleteCredentials(keychainRef: String) {
        deletedCredentialRefs.append(keychainRef)
    }

    func saveWebhookSecret(_ secret: String, keychainRef: String) throws {
        throw Error.writeFailed
    }

    func readWebhookSecret(keychainRef: String) throws -> String? {
        nil
    }

    func deleteWebhookSecret(keychainRef: String) {}
}

private struct MockCloudProviderAdapter: CloudProviderAdapter {
    let providerId: CloudProviderID
    let displayName = "Mock Cloud"
    let capabilities: Set<CloudCapability>
    var actionFailures: Set<String> = []

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
                securityGroupIds: ["sg-123"],
                billingType: "POSTPAID_BY_HOUR",
                expiredTime: nil,
                rawJSON: nil
            ),
        ]
    }

    func fetchMetricSeries(credential: CloudProviderCredential, query: CloudMetricQuery) async throws -> CloudMetricSeries {
        let unit: String?
        switch query.metricName {
        case "CPUUsage", "MemoryUsage":
            unit = "%"
        case "DiskReadBytes", "DiskWriteBytes", "NetworkInBytes", "NetworkOutBytes":
            unit = "B/s"
        default:
            unit = nil
        }
        return CloudMetricSeries(
            metricName: query.metricName,
            instanceId: query.instanceId,
            regionId: query.regionId,
            unit: unit,
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
            CloudSecurityGroup(
                accountId: accountId,
                providerId: providerId,
                regionId: regionId,
                securityGroupId: "sg-admin",
                name: "admin",
                description: "not attached to the linked instance",
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
                    providerRuleId: nil,
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
        try throwFailureIfNeeded("create_snapshot")
        return CloudSnapshot(
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
    ) async throws {
        try throwFailureIfNeeded("delete_snapshot")
    }

    func attachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String,
        instanceId: String
    ) async throws {
        try throwFailureIfNeeded("attach_disk")
    }

    func detachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String
    ) async throws {
        try throwFailureIfNeeded("detach_disk")
    }

    func startInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        try throwFailureIfNeeded("start_instance")
    }

    func stopInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        try throwFailureIfNeeded("stop_instance")
    }

    func rebootInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        try throwFailureIfNeeded("reboot_instance")
    }

    private func throwFailureIfNeeded(_ action: String) throws {
        if actionFailures.contains(action) {
            throw CloudProviderError.providerFailure("forced \(action) failure")
        }
    }
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
    private let systemCronPath = "/etc/cron.d/hhc-system"
    private let systemCrontab = "*/15 * * * * root /usr/local/bin/system-health\n"

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if command.contains("__HHC_USER_CRONTAB__") {
            let output = """
            __HHC_USER_CRONTAB__
            \(installedCrontab)__HHC_SYSTEM_CRON_D__
            __HHC_CRON_FILE__ \(systemCronPath)
            \(systemCrontab)
            """
            return CommandResult(command: command, stdout: output, stderr: "", exitCode: 0, duration: 0)
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
        "/www/server/nginx/conf/vhost/site.conf": """
        server {
            listen 443 ssl;
            server_name api.example.com;
            ssl_certificate /etc/letsencrypt/live/api/fullchain.pem;
        }
        """,
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
        if command.contains("openssl x509") {
            return CommandResult(
                command: command,
                stdout: """
                __HHC_NGINX_CERT__\t/etc/letsencrypt/live/api/fullchain.pem
                __HHC_NGINX_CERT_NOT_AFTER__\tJun 20 12:00:00 2027 GMT
                __HHC_NGINX_CERT_SUBJECT__\tCN=api.example.com
                __HHC_NGINX_CERT_ISSUER__\tCN=R3
                """,
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

    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile, progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?) async throws -> RemoteFileTransferResult {
        uploads.append((localURL, remotePath))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: nil,
            duration: 0
        )
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile, progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?) async throws -> RemoteFileTransferResult {
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

private final class MockGitServiceHTTPTransport: GitServiceHTTPTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "MockGitServiceHTTPTransport")
    private var responses: [String: String]
    private var requests: [URLRequest] = []

    init(responses: [String: String]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = queue.sync {
            requests.append(request)
            return responses[request.url?.path ?? ""] ?? "[]"
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }

    func snapshotRequests() -> [URLRequest] {
        queue.sync { requests }
    }
}

private actor CloudProviderRequestLimiterProbe {
    private(set) var running = 0
    private(set) var maxRunning = 0

    func enter() {
        running += 1
        maxRunning = max(maxRunning, running)
    }

    func leave() {
        running -= 1
    }

    func snapshot() -> (running: Int, maxRunning: Int) {
        (running, maxRunning)
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
