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

    func validateCredential(_ credential: CloudProviderCredential) async throws {}

    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion] { [] }

    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance] { [] }

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
}
