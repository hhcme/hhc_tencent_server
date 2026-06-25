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
}
