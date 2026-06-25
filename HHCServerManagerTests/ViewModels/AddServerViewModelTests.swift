import XCTest
@testable import HHCServerManager

@MainActor
final class AddServerViewModelTests: XCTestCase {
    func testValidationRequiresNameHostUserPortAndCredential() {
        let viewModel = AddServerViewModel()
        XCTAssertEqual(viewModel.validationError, "Name is required.")

        viewModel.name = "Tencent"
        XCTAssertEqual(viewModel.validationError, "Host is required.")

        viewModel.host = "example.internal"
        viewModel.port = "70000"
        XCTAssertEqual(viewModel.validationError, "Port must be between 1 and 65535.")

        viewModel.port = "22"
        viewModel.username = ""
        XCTAssertEqual(viewModel.validationError, "Username is required.")

        viewModel.username = "root"
        viewModel.authType = .privateKey
        XCTAssertEqual(viewModel.validationError, "Private key is required.")

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

        XCTAssertEqual(viewModel.validationError, "Password is required.")
        viewModel.password = "secret"
        XCTAssertNil(viewModel.validationError)
    }

    func testEditingExistingPasswordServerDoesNotRequireReenteringPassword() {
        let viewModel = AddServerViewModel()
        viewModel.configureForEditing(makeProfile(authType: .password))

        XCTAssertNil(viewModel.validationError)
        XCTAssertEqual(viewModel.name, "Tencent")
        XCTAssertEqual(viewModel.authType, .password)
        XCTAssertTrue(viewModel.password.isEmpty)
    }

    func testEditingExistingPrivateKeyServerDoesNotRequireSelectingKeyAgain() {
        let viewModel = AddServerViewModel()
        viewModel.configureForEditing(makeProfile(authType: .privateKey))

        XCTAssertNil(viewModel.validationError)
        XCTAssertEqual(viewModel.privateKeyFileName, "Existing private key")
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

    private func makeProfile(authType: SSHAuthType) -> ServerProfile {
        ServerProfile(
            id: UUID(),
            name: "Tencent",
            host: "example.internal",
            port: 22,
            username: "root",
            authType: authType,
            keychainRef: "server_test",
            groupName: "prod",
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private struct MockResourceCenterCloudAdapter: CloudProviderAdapter {
    let providerId: CloudProviderID
    let displayName = "Mock Cloud"
    let capabilities: Set<CloudCapability>
    var validationError: CloudProviderError?
    var regions: [CloudRegion] = []
    var instances: [CloudProviderInstance] = []

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
    ) async throws -> [CloudDisk] { [] }

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
