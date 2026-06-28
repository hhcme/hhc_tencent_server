import XCTest
@testable import HHCServerManager

@MainActor
final class AddServerViewModelTests: XCTestCase {
    func testValidationRequiresNameHostUserPortAndCredential() {
        let viewModel = AddServerViewModel()
        XCTAssertEqual(viewModel.validationError, L10n.string("Name is required."))

        viewModel.name = "Tencent"
        XCTAssertEqual(viewModel.validationError, L10n.string("Host is required."))

        viewModel.host = "example.internal"
        viewModel.port = "70000"
        XCTAssertEqual(viewModel.validationError, L10n.string("Port must be between 1 and 65535."))

        viewModel.port = "22"
        viewModel.username = ""
        XCTAssertEqual(viewModel.validationError, L10n.string("Username is required."))

        viewModel.username = "root"
        viewModel.authType = .privateKey
        XCTAssertEqual(viewModel.validationError, L10n.string("Private key is required."))

        viewModel.privateKeyData = Data("key".utf8)
        XCTAssertNil(viewModel.validationError)
    }

    func testPasswordAuthRequiresPassword() {
        let viewModel = AddServerViewModel()
        viewModel.name = "Tencent"
        viewModel.host = "example.internal"
        viewModel.port = "22"
        viewModel.username = "root"
        viewModel.authType = .password

        XCTAssertEqual(viewModel.validationError, L10n.string("Password is required."))
        viewModel.password = "secret"
        XCTAssertNil(viewModel.validationError)
    }

    func testEditingExistingPasswordServerDoesNotRequireReenteringPassword() {
        let viewModel = AddServerViewModel()
        viewModel.configureForEditing(makeProfile(authType: .password))

        XCTAssertNil(viewModel.validationError)
        XCTAssertEqual(viewModel.name, "Tencent")
        XCTAssertEqual(viewModel.authType, .password)
        XCTAssertEqual(viewModel.serverKind, .manualSSH)
        XCTAssertTrue(viewModel.password.isEmpty)
    }

    func testEditingExistingPrivateKeyServerDoesNotRequireSelectingKeyAgain() {
        let viewModel = AddServerViewModel()
        viewModel.configureForEditing(makeProfile(authType: .privateKey))

        XCTAssertNil(viewModel.validationError)
        XCTAssertEqual(viewModel.privateKeyFileName, L10n.string("Existing private key"))
    }

    func testSaveImportsSelectedKnownHostsFileForNewServer() throws {
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.known-hosts-import.\(UUID().uuidString)")
        let service = ServerManagementService(repository: repository, keychain: keychain)
        let store = HostKeyTrustStore(repository: repository)
        let knownHostsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hhc-known-hosts-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: knownHostsURL) }

        let publicKey = Data([1, 2, 3, 4]).base64EncodedString()
        try """
        ignored.example.internal ssh-ed25519 \(Data([9]).base64EncodedString())
        example.internal ssh-ed25519 \(publicKey)
        """.write(to: knownHostsURL, atomically: true, encoding: .utf8)

        let viewModel = AddServerViewModel()
        viewModel.name = "Tencent"
        viewModel.host = "example.internal"
        viewModel.port = "22"
        viewModel.username = "root"
        viewModel.serverKind = .tencentLighthouse
        viewModel.authType = .password
        viewModel.password = "secret"
        try viewModel.selectKnownHostsFile(knownHostsURL)

        let profile = try viewModel.save(using: service, hostKeyTrustStore: store)
        defer { keychain.deleteCredentials(keychainRef: profile.keychainRef) }

        let trustedKeys = try repository.fetchTrustedHostKeys(serverId: profile.id)
        XCTAssertEqual(viewModel.knownHostsFileName, knownHostsURL.lastPathComponent)
        XCTAssertEqual(viewModel.knownHostsImportResult, KnownHostsImportResult(importedCount: 1, skippedCount: 1))
        XCTAssertEqual(profile.serverKind, .tencentLighthouse)
        XCTAssertEqual(trustedKeys.count, 1)
        XCTAssertEqual(trustedKeys.first?.host, "example.internal")
        XCTAssertEqual(trustedKeys.first?.algorithm, "ssh-ed25519")
    }

    func testCloudImportViewModelRequiresVerifiedAccountRegionInstanceAndCredential() {
        let viewModel = CloudImportViewModel()

        XCTAssertFalse(viewModel.canAddAccount)
        XCTAssertEqual(viewModel.selectedProviderId, .tencentCloud)
        viewModel.accountDisplayName = "Tencent"
        viewModel.secretId = "sid"
        viewModel.secretKey = "skey"
        XCTAssertTrue(viewModel.canAddAccount)
        XCTAssertFalse(viewModel.canSync)
        XCTAssertFalse(viewModel.canImport)

        viewModel.selectedAccountId = UUID()
        viewModel.selectedRegionId = "ap-guangzhou"
        XCTAssertTrue(viewModel.canSync)

        let accountId = UUID()
        let link = CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: accountId,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-123",
            displayName: "prod",
            publicIp: "203.0.113.1",
            privateIp: nil,
            status: "RUNNING",
            instanceType: "S5.SMALL1",
            zoneId: nil,
            vpcId: nil,
            securityGroupIds: [],
            rawJSON: nil,
            lastSyncedAt: Date()
        )
        viewModel.instances = [link]
        viewModel.selectedInstanceId = link.id
        XCTAssertFalse(viewModel.canImport)

        viewModel.authType = .password
        viewModel.password = "secret"
        XCTAssertTrue(viewModel.canImport)
    }

    func testCloudImportViewModelSwitchesProviderAndClearsSyncedState() {
        let viewModel = CloudImportViewModel()
        let instanceId = UUID()

        viewModel.secretId = "sid"
        viewModel.secretKey = "skey"
        viewModel.selectedAccountId = UUID()
        viewModel.regions = [CloudRegion(id: "ap-guangzhou", displayName: "Guangzhou", available: true)]
        viewModel.selectedRegionId = "ap-guangzhou"
        viewModel.instances = [
            CloudInstanceLink(
                id: instanceId,
                serverId: nil,
                accountId: UUID(),
                providerId: .tencentCloud,
                regionId: "ap-guangzhou",
                instanceId: "ins-123",
                displayName: "prod",
                publicIp: "203.0.113.1",
                privateIp: nil,
                status: "RUNNING",
                instanceType: "S5.SMALL1",
                zoneId: nil,
                vpcId: nil,
                securityGroupIds: [],
                rawJSON: nil,
                lastSyncedAt: Date()
            ),
        ]
        viewModel.selectedInstanceId = instanceId

        viewModel.selectProvider(.huaweiCloud)

        XCTAssertEqual(viewModel.selectedProviderId, .huaweiCloud)
        XCTAssertEqual(viewModel.accountDisplayName, "Huawei Cloud")
        XCTAssertTrue(viewModel.secretId.isEmpty)
        XCTAssertTrue(viewModel.secretKey.isEmpty)
        XCTAssertNil(viewModel.selectedAccountId)
        XCTAssertTrue(viewModel.regions.isEmpty)
        XCTAssertTrue(viewModel.selectedRegionId.isEmpty)
        XCTAssertTrue(viewModel.instances.isEmpty)
        XCTAssertNil(viewModel.selectedInstanceId)
    }

    func testServerBrowserEmptyStatesDescribeFirstRunSearchAndSourceFilters() {
        let viewModel = ServerBrowserViewModel()

        XCTAssertEqual(
            viewModel.emptyState(for: [], links: []),
            ServerBrowserEmptyState(
                title: L10n.string("No Servers"),
                systemImage: "server.rack",
                description: L10n.string("Add a server to start the SSH workflow.")
            )
        )

        let manualServer = makeProfile(name: "Manual SSH", host: "manual.example.internal")
        viewModel.searchText = "missing"
        XCTAssertEqual(
            viewModel.emptyState(for: [manualServer], links: []),
            ServerBrowserEmptyState(
                title: L10n.string("No Matching Servers"),
                systemImage: "magnifyingglass",
                description: L10n.string("Adjust the search text or choose another source.")
            )
        )

        viewModel.searchText = ""
        viewModel.sourceFilter = .cloud
        XCTAssertEqual(
            viewModel.emptyState(for: [manualServer], links: []),
            ServerBrowserEmptyState(
                title: L10n.string("No Cloud Servers"),
                systemImage: "cloud",
                description: L10n.string("Add a cloud account, sync instances, then import one as an SSH server.")
            )
        )

        viewModel.sourceFilter = .manual
        let cloudServer = makeProfile(name: "Cloud SSH", host: "cloud.example.internal")
        let cloudLink = makeCloudInstanceLink(serverId: cloudServer.id)
        XCTAssertEqual(
            viewModel.emptyState(for: [cloudServer], links: [cloudLink]),
            ServerBrowserEmptyState(
                title: L10n.string("No Manual SSH Servers"),
                systemImage: "terminal",
                description: L10n.string("Add a manual SSH server or switch to all sources.")
            )
        )
    }

    func testCloudImportViewModelDoesNotCreateAccountWhenValidationFails() async throws {
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.cloud-import-failure.\(UUID().uuidString)")
        let appState = AppState(
            repository: repository,
            keychain: keychain,
            registry: CloudProviderRegistry(adapters: [
                MockResourceCenterCloudAdapter(
                    providerId: .tencentCloud,
                    capabilities: [.regions, .instanceDiscovery],
                    validationError: .authenticationFailed("invalid cloud secret")
                ),
            ])
        )
        let viewModel = CloudImportViewModel()
        viewModel.accountDisplayName = " Tencent Invalid "
        viewModel.secretId = " sid "
        viewModel.secretKey = " skey "

        await viewModel.addCloudAccount(appState: appState)

        XCTAssertFalse(viewModel.isWorking)
        XCTAssertNil(viewModel.statusMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("invalid cloud secret") == true)
        XCTAssertNil(viewModel.selectedAccountId)
        XCTAssertEqual(viewModel.secretId, " sid ")
        XCTAssertEqual(viewModel.secretKey, " skey ")
        XCTAssertTrue(try repository.fetchCloudProviderAccounts().isEmpty)
        XCTAssertTrue(appState.cloudProviderAccounts.isEmpty)
    }

    func testCloudImportViewModelAddsVerifiedAccountAndStoresCredentialInKeychain() async throws {
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.cloud-import-success.\(UUID().uuidString)")
        let appState = AppState(
            repository: repository,
            keychain: keychain,
            registry: CloudProviderRegistry(adapters: [
                MockResourceCenterCloudAdapter(
                    providerId: .tencentCloud,
                    capabilities: [.regions, .instanceDiscovery]
                ),
            ])
        )
        let viewModel = CloudImportViewModel()
        viewModel.accountDisplayName = " Tencent Read Only "
        viewModel.secretId = " sid-success "
        viewModel.secretKey = " skey-success "

        await viewModel.addCloudAccount(appState: appState)

        let account = try XCTUnwrap(try repository.fetchCloudProviderAccounts().first)
        defer { keychain.deleteCredentials(keychainRef: account.keychainRef) }

        XCTAssertFalse(viewModel.isWorking)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.statusMessage, "Tencent Cloud account added and verified.")
        XCTAssertEqual(viewModel.selectedAccountId, account.id)
        XCTAssertTrue(viewModel.secretId.isEmpty)
        XCTAssertTrue(viewModel.secretKey.isEmpty)
        XCTAssertTrue(viewModel.regions.isEmpty)
        XCTAssertTrue(viewModel.instances.isEmpty)
        XCTAssertEqual(appState.cloudProviderAccounts.map(\.id), [account.id])
        XCTAssertEqual(account.providerId, .tencentCloud)
        XCTAssertEqual(account.displayName, "Tencent Read Only")
        XCTAssertEqual(try keychain.readCloudCredential(keychainRef: account.keychainRef), CloudProviderCredential(
            secretId: "sid-success",
            secretKey: "skey-success"
        ))
    }

    func testCloudImportViewModelSyncsImportsAndBrowserSeparatesCloudFromManualServers() async throws {
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.cloud-import-sync.\(UUID().uuidString)")
        let appState = AppState(
            repository: repository,
            keychain: keychain,
            registry: CloudProviderRegistry(adapters: [
                MockResourceCenterCloudAdapter(
                    providerId: .tencentCloud,
                    capabilities: [.regions, .instanceDiscovery],
                    regions: [CloudRegion(id: "ap-guangzhou", displayName: "Guangzhou", available: true)],
                    instances: [
                        CloudProviderInstance(
                            id: "ins-prod",
                            providerId: .tencentCloud,
                            regionId: "ap-guangzhou",
                            displayName: "prod-web",
                            publicIp: "203.0.113.20",
                            privateIp: "10.0.0.20",
                            status: "RUNNING",
                            instanceType: "S5.SMALL1",
                            zoneId: "ap-guangzhou-3",
                            vpcId: "vpc-prod",
                            securityGroupIds: ["sg-prod"],
                            billingType: nil,
                            expiredTime: nil,
                            rawJSON: nil
                        ),
                    ]
                ),
            ])
        )
        let manualServer = try appState.serverManagementService.createServer(
            name: "Manual SSH",
            host: "manual.example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("manual-secret")
        )
        let viewModel = CloudImportViewModel()
        viewModel.accountDisplayName = "Tencent Read Only"
        viewModel.secretId = "sid-sync"
        viewModel.secretKey = "skey-sync"
        await viewModel.addCloudAccount(appState: appState)
        let account = try XCTUnwrap(appState.cloudProviderAccounts.first)
        defer {
            keychain.deleteCredentials(keychainRef: account.keychainRef)
            keychain.deleteCredentials(keychainRef: manualServer.keychainRef)
            if let imported = try? repository.fetchServers().first(where: { $0.id != manualServer.id }) {
                keychain.deleteCredentials(keychainRef: imported.keychainRef)
            }
        }

        await viewModel.loadRegions(appState: appState)
        await viewModel.syncInstances(appState: appState)

        XCTAssertEqual(viewModel.selectedRegionId, "ap-guangzhou")
        XCTAssertEqual(viewModel.instances.map(\.instanceId), ["ins-prod"])
        XCTAssertEqual(viewModel.selectedInstance?.displayName, "prod-web")
        XCTAssertEqual(viewModel.statusMessage, "Instances synced.")

        viewModel.authType = .password
        viewModel.password = "cloud-secret"
        let imported = try viewModel.importSelectedInstance(appState: appState)

        XCTAssertEqual(imported.name, "prod-web")
        XCTAssertEqual(imported.host, "203.0.113.20")
        XCTAssertEqual(imported.groupName, "Tencent Cloud")
        XCTAssertEqual(imported.serverKind, .tencentCVM)
        XCTAssertEqual(try keychain.readPassword(keychainRef: imported.keychainRef), "cloud-secret")
        XCTAssertEqual(try repository.fetchCloudInstanceLinks().first { $0.instanceId == "ins-prod" }?.serverId, imported.id)

        let browser = ServerBrowserViewModel()
        browser.sourceFilter = .cloud
        XCTAssertEqual(browser.filteredServers(from: appState.servers, links: appState.cloudInstanceLinks).map(\.id), [imported.id])
        browser.sourceFilter = .manual
        XCTAssertEqual(browser.filteredServers(from: appState.servers, links: appState.cloudInstanceLinks).map(\.id), [manualServer.id])
    }

    func testCloudResourceCenterKindFiltersMapToSearchKinds() {
        XCTAssertEqual(CloudResourceKindFilter.all.queryKinds, Set(CloudResourceKind.allCases))
        XCTAssertEqual(CloudResourceKindFilter.instance.queryKinds, [.instance])
        XCTAssertEqual(CloudResourceKindFilter.disk.queryKinds, [.disk])
        XCTAssertEqual(CloudResourceKindFilter.snapshot.queryKinds, [.snapshot])
        XCTAssertEqual(CloudResourceKindFilter.billing.queryKinds, [.billing])
        XCTAssertEqual(CloudResourceKindFilter.securityGroup.queryKinds, [.securityGroup])
    }

    func testCloudResourceCenterCapabilityMatrixMarksMissingProviders() {
        let viewModel = CloudResourceCenterViewModel()
        let registry = CloudProviderRegistry(adapters: [
            MockResourceCenterCloudAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .cloudDisks, .cloudSnapshots, .cloudBilling]
            ),
        ])

        viewModel.refreshCapabilityMatrix(registry: registry)

        XCTAssertEqual(
            viewModel.capabilityRows.first {
                $0.providerId == .tencentCloud && $0.capability == .cloudDisks
            }?.isSupported,
            true
        )
        XCTAssertEqual(
            viewModel.capabilityRows.first {
                $0.providerId == .alibabaCloud && $0.capability == .instanceDiscovery
            }?.isRegistered,
            false
        )
    }

    func testCloudResourceCenterRuntimePermissionFailureDowngradesCapability() {
        let viewModel = CloudResourceCenterViewModel()
        let registry = CloudProviderRegistry(adapters: [
            MockResourceCenterCloudAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .snapshotActions]
            ),
        ])
        viewModel.refreshCapabilityMatrix(registry: registry)

        XCTAssertTrue(viewModel.supportsRuntimeCapability(.snapshotActions, providerId: .tencentCloud))

        let downgraded = viewModel.recordRuntimeCapabilityFailure(
            .snapshotActions,
            providerId: .tencentCloud,
            error: CloudProviderError.permissionDenied("UnauthorizedOperation: missing snapshot write policy")
        )

        XCTAssertTrue(downgraded)
        let status = viewModel.capabilityStatus(providerId: .tencentCloud, capability: .snapshotActions)
        XCTAssertEqual(status?.isSupported, true)
        XCTAssertEqual(status?.isRuntimeDisabled, true)
        XCTAssertEqual(status?.isEffective, false)
        XCTAssertTrue(status?.runtimeDisabledReason?.contains("UnauthorizedOperation") == true)
        XCTAssertFalse(viewModel.supportsRuntimeCapability(.snapshotActions, providerId: .tencentCloud))
    }

    func testCloudResourceCenterNonPermissionFailureDoesNotDowngradeCapability() {
        let viewModel = CloudResourceCenterViewModel()
        let registry = CloudProviderRegistry(adapters: [
            MockResourceCenterCloudAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .cloudDisks]
            ),
        ])
        viewModel.refreshCapabilityMatrix(registry: registry)

        let downgraded = viewModel.recordRuntimeCapabilityFailure(
            .cloudDisks,
            providerId: .tencentCloud,
            error: CloudProviderError.providerFailure("Cloud API returned malformed disk payload")
        )

        XCTAssertFalse(downgraded)
        XCTAssertNil(viewModel.capabilityStatus(providerId: .tencentCloud, capability: .cloudDisks)?.runtimeDisabledReason)
        XCTAssertTrue(viewModel.supportsRuntimeCapability(.cloudDisks, providerId: .tencentCloud))
    }

    func testCloudResourceCenterBuildsCapabilityMatrixMarkdownReport() {
        let viewModel = CloudResourceCenterViewModel()
        let registry = CloudProviderRegistry(adapters: [
            MockResourceCenterCloudAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .snapshotActions]
            ),
        ])
        viewModel.refreshCapabilityMatrix(registry: registry)
        _ = viewModel.recordRuntimeCapabilityFailure(
            .snapshotActions,
            providerId: .tencentCloud,
            error: CloudProviderError.permissionDenied("UnauthorizedOperation|missing snapshot policy")
        )

        let report = viewModel.capabilityMatrixReportMarkdown()

        XCTAssertTrue(report.contains("# Provider Capability Matrix"))
        XCTAssertTrue(report.contains("- Providers: 3"))
        XCTAssertTrue(report.contains("- Capabilities: \(CloudCapability.allCases.count)"))
        XCTAssertTrue(report.contains("- Runtime disabled: 1"))
        XCTAssertTrue(report.contains("| Provider | Registered | Capability | Supported | Effective | Runtime Disabled Reason |"))
        XCTAssertTrue(report.contains("| Mock Cloud | yes | Snapshot Actions | yes | no |"))
        XCTAssertTrue(report.contains("UnauthorizedOperation\\|missing snapshot policy"))
        XCTAssertTrue(report.contains("| Alibaba Cloud | no | Instance Discovery | no | no |"))
    }

    func testCloudResourceCenterRefreshAppliesLocalFiltersAndResetsSelection() throws {
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.cloud-resource-center.\(UUID().uuidString)")
        let appState = AppState(repository: repository, keychain: keychain)
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let account = CloudProviderAccount(
            id: UUID(),
            providerId: .tencentCloud,
            displayName: "Tencent",
            keychainRef: "cloud_test",
            enabled: true,
            createdAt: capturedAt,
            updatedAt: capturedAt
        )
        try repository.upsertCloudProviderAccount(account)
        try repository.upsertCloudInstanceLink(CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-prod",
            displayName: "prod-web",
            publicIp: "203.0.113.10",
            privateIp: nil,
            status: "RUNNING",
            instanceType: "S5.SMALL1",
            zoneId: nil,
            vpcId: nil,
            securityGroupIds: [],
            rawJSON: nil,
            lastSyncedAt: capturedAt
        ))
        try repository.upsertCloudDisk(CloudDisk(
            id: UUID(),
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            diskId: "disk-data",
            instanceId: "ins-prod",
            name: "prod-data",
            diskType: "CLOUD_PREMIUM",
            sizeGB: 100,
            status: "ATTACHED",
            billingType: "POSTPAID_BY_HOUR",
            expiredTime: nil,
            rawJSON: nil,
            lastSyncedAt: capturedAt
        ))
        try repository.upsertCloudDisk(CloudDisk(
            id: UUID(),
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-shanghai",
            diskId: "disk-other-region",
            instanceId: nil,
            name: "prod-data",
            diskType: "CLOUD_PREMIUM",
            sizeGB: 200,
            status: "ATTACHED",
            billingType: "POSTPAID_BY_HOUR",
            expiredTime: nil,
            rawJSON: nil,
            lastSyncedAt: capturedAt
        ))
        try repository.upsertCloudSnapshot(CloudSnapshot(
            id: UUID(),
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            snapshotId: "snap-before-upgrade",
            diskId: "disk-data",
            name: "before-upgrade",
            status: "NORMAL",
            sizeGB: 100,
            createdAtProvider: capturedAt,
            rawJSON: nil,
            lastSyncedAt: capturedAt
        ))
        appState.reloadServers()

        let viewModel = CloudResourceCenterViewModel()
        viewModel.selectedAccountId = account.id
        viewModel.selectedRegionId = "ap-guangzhou"
        viewModel.kindFilter = .disk
        viewModel.statusFilter = "ATTACHED"
        viewModel.searchText = "data"

        viewModel.refreshLocalResources(appState: appState)

        XCTAssertEqual(viewModel.resources.map(\.resourceId), ["disk-data"])
        XCTAssertEqual(viewModel.selectedResourceId, "disk:\(account.id.uuidString):ap-guangzhou:disk-data")
        XCTAssertEqual(viewModel.statusMessage, "Loaded 1 cached cloud resources.")

        viewModel.kindFilter = .snapshot
        viewModel.statusFilter = ""
        viewModel.searchText = "upgrade"

        viewModel.refreshLocalResources(appState: appState)

        XCTAssertEqual(viewModel.resources.map(\.resourceId), ["snap-before-upgrade"])
        XCTAssertEqual(viewModel.selectedResourceId, "snapshot:\(account.id.uuidString):ap-guangzhou:snap-before-upgrade")
    }

    func testCloudResourceCenterBuildsSummaryForVisibleResources() throws {
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.cloud-resource-summary.\(UUID().uuidString)")
        let appState = AppState(repository: repository, keychain: keychain)
        let olderSync = Date(timeIntervalSince1970: 1_700_000_000)
        let newerSync = Date(timeIntervalSince1970: 1_700_000_600)
        let account = CloudProviderAccount(
            id: UUID(),
            providerId: .tencentCloud,
            displayName: "Tencent",
            keychainRef: "cloud_test",
            enabled: true,
            createdAt: olderSync,
            updatedAt: olderSync
        )
        try repository.upsertCloudProviderAccount(account)
        try repository.upsertCloudInstanceLink(CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-prod",
            displayName: "prod-web",
            publicIp: "203.0.113.10",
            privateIp: nil,
            status: "RUNNING",
            instanceType: "S5.SMALL1",
            zoneId: nil,
            vpcId: nil,
            securityGroupIds: [],
            rawJSON: nil,
            lastSyncedAt: olderSync
        ))
        try repository.upsertCloudDisk(CloudDisk(
            id: UUID(),
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            diskId: "disk-error",
            instanceId: nil,
            name: "error-disk",
            diskType: "CLOUD_PREMIUM",
            sizeGB: 100,
            status: "ERROR",
            billingType: "POSTPAID_BY_HOUR",
            expiredTime: nil,
            rawJSON: nil,
            lastSyncedAt: newerSync
        ))
        try repository.upsertCloudSnapshot(CloudSnapshot(
            id: UUID(),
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            snapshotId: "snap-normal",
            diskId: "disk-error",
            name: "normal-snapshot",
            status: "NORMAL",
            sizeGB: 100,
            createdAtProvider: newerSync,
            rawJSON: nil,
            lastSyncedAt: newerSync
        ))
        appState.reloadServers()

        let viewModel = CloudResourceCenterViewModel()
        viewModel.selectedAccountId = account.id
        viewModel.selectedRegionId = "ap-guangzhou"
        viewModel.refreshLocalResources(appState: appState)

        XCTAssertEqual(viewModel.resourceSummary.totalCount, 3)
        XCTAssertEqual(viewModel.resourceSummary.attentionCount, 1)
        XCTAssertEqual(viewModel.resourceSummary.latestSyncAt, newerSync)
        XCTAssertEqual(
            viewModel.resourceSummary.kindCounts.map { "\($0.kind.rawValue):\($0.count)" },
            ["instance:1", "disk:1", "snapshot:1"]
        )
        XCTAssertEqual(viewModel.resourceSummary.providerCounts.map(\.providerId), [.tencentCloud])

        viewModel.kindFilter = .disk
        viewModel.refreshLocalResources(appState: appState)

        XCTAssertEqual(viewModel.resources.map(\.resourceId), ["disk-error"])
        XCTAssertEqual(viewModel.resourceSummary.totalCount, 1)
        XCTAssertEqual(viewModel.resourceSummary.kindCounts.map(\.kind), [.disk])
        XCTAssertEqual(viewModel.resourceSummary.attentionCount, 1)
    }

    func testCloudResourceCenterBuildsMarkdownReportForVisibleResources() throws {
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.cloud-resource-report.\(UUID().uuidString)")
        let appState = AppState(repository: repository, keychain: keychain)
        let syncedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let account = CloudProviderAccount(
            id: UUID(),
            providerId: .tencentCloud,
            displayName: "Tencent",
            keychainRef: "cloud_test",
            enabled: true,
            createdAt: syncedAt,
            updatedAt: syncedAt
        )
        try repository.upsertCloudProviderAccount(account)
        try repository.upsertCloudDisk(CloudDisk(
            id: UUID(),
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            diskId: "disk-data",
            instanceId: "ins-prod",
            name: "data|disk",
            diskType: "CLOUD_PREMIUM",
            sizeGB: 100,
            status: "ERROR",
            billingType: "POSTPAID_BY_HOUR",
            expiredTime: nil,
            rawJSON: nil,
            lastSyncedAt: syncedAt
        ))
        appState.reloadServers()

        let viewModel = CloudResourceCenterViewModel()
        viewModel.selectedAccountId = account.id
        viewModel.selectedRegionId = "ap-guangzhou"
        viewModel.kindFilter = .disk
        viewModel.statusFilter = "ERROR"
        viewModel.searchText = "data"
        viewModel.refreshLocalResources(appState: appState)

        let report = viewModel.visibleResourcesReportMarkdown()

        XCTAssertTrue(report.contains("# Cloud Resources Report"))
        XCTAssertTrue(report.contains("- Region: ap-guangzhou"))
        XCTAssertTrue(report.contains("- Kind: Disks"))
        XCTAssertTrue(report.contains("- Search: data"))
        XCTAssertTrue(report.contains("- Status: ERROR"))
        XCTAssertTrue(report.contains("- Total: 1"))
        XCTAssertTrue(report.contains("- Needs attention: 1"))
        XCTAssertTrue(report.contains("- Latest sync: \(AppDatabase.string(from: syncedAt))"))
        XCTAssertTrue(report.contains("## By Kind"))
        XCTAssertTrue(report.contains("- Disk: 1"))
        XCTAssertTrue(report.contains("## Resources"))
        XCTAssertTrue(report.contains("| Disk | Tencent Cloud | ap-guangzhou | data\\|disk | disk-data | ERROR | ins-prod | CLOUD_PREMIUM · 100 GB | \(AppDatabase.string(from: syncedAt)) |"))
    }

    func testCloudResourceCenterRefreshesProviderStateAfterDiskAction() async throws {
        let recorder = ResourceCenterCloudActionRecorder()
        let registry = CloudProviderRegistry(adapters: [
            MockResourceCenterCloudAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .cloudDisks, .diskAttachmentActions],
                regions: [CloudRegion(id: "ap-guangzhou", displayName: "Guangzhou", available: true)],
                recorder: recorder
            ),
        ])
        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManagerTests.cloud-resource-action-refresh.\(UUID().uuidString)")
        let appState = AppState(repository: repository, keychain: keychain, registry: registry)
        let account = try appState.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        try repository.upsertCloudDisk(CloudDisk(
            id: UUID(),
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            diskId: "disk-data",
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
        appState.reloadServers()

        let viewModel = CloudResourceCenterViewModel()
        viewModel.refreshCapabilityMatrix(registry: registry)
        viewModel.selectedAccountId = account.id
        viewModel.selectedRegionId = "ap-guangzhou"
        viewModel.kindFilter = .disk
        viewModel.refreshLocalResources(appState: appState)

        let diskResource = try XCTUnwrap(viewModel.resources.first { $0.resourceId == "disk-data" })
        await viewModel.attachDisk(for: diskResource, instanceId: "ins-target", appState: appState)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.statusMessage, "Disk disk-data is attaching to ins-target.")
        XCTAssertEqual(viewModel.resources.first { $0.resourceId == "disk-data" }?.status, "ATTACHED")
        XCTAssertEqual(viewModel.resources.first { $0.resourceId == "disk-data" }?.primaryAddress, "ins-target")
        XCTAssertEqual(try repository.fetchCloudDisks(accountId: account.id).first { $0.diskId == "disk-data" }?.status, "ATTACHED")
        XCTAssertEqual(try repository.fetchRemoteChangeLogs().first { $0.action == "attach_disk" }?.status, "success")
    }

    private func makeProfile(authType: SSHAuthType) -> ServerProfile {
        makeProfile(name: "Tencent", host: "example.internal", authType: authType)
    }

    private func makeProfile(
        name: String,
        host: String,
        authType: SSHAuthType = .password
    ) -> ServerProfile {
        ServerProfile(
            id: UUID(),
            name: name,
            host: host,
            port: 22,
            username: "root",
            authType: authType,
            keychainRef: "server_test",
            groupName: "prod",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeCloudInstanceLink(serverId: UUID?) -> CloudInstanceLink {
        CloudInstanceLink(
            id: UUID(),
            serverId: serverId,
            accountId: UUID(),
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-test",
            displayName: "Cloud SSH",
            publicIp: "203.0.113.10",
            privateIp: nil,
            status: "RUNNING",
            instanceType: "S5.SMALL1",
            zoneId: nil,
            vpcId: nil,
            securityGroupIds: [],
            rawJSON: nil,
            lastSyncedAt: Date()
        )
    }
}

private final class ResourceCenterCloudActionRecorder: @unchecked Sendable {
    var attachedDiskInstanceId: String?
}

private struct MockResourceCenterCloudAdapter: CloudProviderAdapter {
    let providerId: CloudProviderID
    let displayName = "Mock Cloud"
    let capabilities: Set<CloudCapability>
    var validationError: CloudProviderError?
    var regions: [CloudRegion] = []
    var instances: [CloudProviderInstance] = []
    var recorder: ResourceCenterCloudActionRecorder? = nil

    func validateCredential(_ credential: CloudProviderCredential) async throws {
        if let validationError {
            throw validationError
        }
    }

    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion] { regions }

    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance] {
        instances.filter { $0.regionId == regionId }
    }

    func fetchMetricSeries(credential: CloudProviderCredential, query: CloudMetricQuery) async throws -> CloudMetricSeries {
        CloudMetricSeries(
            metricName: query.metricName,
            instanceId: query.instanceId,
            regionId: query.regionId,
            unit: "%",
            values: [],
            timestamps: []
        )
    }

    func fetchSecurityGroups(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String
    ) async throws -> [CloudSecurityGroup] { [] }

    func fetchSecurityGroupPolicies(
        credential: CloudProviderCredential,
        group: CloudSecurityGroup,
        capturedAt: Date
    ) async throws -> CloudSecurityGroupPolicySnapshot {
        CloudSecurityGroupPolicySnapshot(group: group, version: nil, ingress: [], egress: [], capturedAt: capturedAt)
    }

    func fetchDisks(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudDisk] {
        guard let attachedDiskInstanceId = recorder?.attachedDiskInstanceId else { return [] }
        return [
            CloudDisk(
                id: UUID(),
                accountId: accountId,
                providerId: providerId,
                regionId: regionId,
                diskId: "disk-data",
                instanceId: attachedDiskInstanceId,
                name: "data",
                diskType: "CLOUD_PREMIUM",
                sizeGB: 100,
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
    ) async throws -> [CloudSnapshot] { [] }

    func fetchBillingStates(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudBillingState] { [] }

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
        recorder?.attachedDiskInstanceId = instanceId
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
