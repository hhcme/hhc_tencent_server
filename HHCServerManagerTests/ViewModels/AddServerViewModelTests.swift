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
