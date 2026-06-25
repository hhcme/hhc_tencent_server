import XCTest
@testable import HHCServerManager

final class KeychainServiceTests: XCTestCase {
    private var service: KeychainService!
    private var keychainRef: String!

    override func setUp() {
        super.setUp()
        service = KeychainService(serviceName: "me.hhc.HHCServerManager.tests.\(UUID().uuidString)")
        keychainRef = "server_\(UUID().uuidString)"
    }

    override func tearDown() {
        service.deleteCredentials(keychainRef: keychainRef)
        keychainRef = nil
        service = nil
        super.tearDown()
    }

    func testPasswordRoundTripOverwriteAndDelete() throws {
        try service.savePassword("first", keychainRef: keychainRef)
        XCTAssertEqual(try service.readPassword(keychainRef: keychainRef), "first")

        try service.savePassword("second", keychainRef: keychainRef)
        XCTAssertEqual(try service.readPassword(keychainRef: keychainRef), "second")

        service.deleteCredentials(keychainRef: keychainRef)
        XCTAssertNil(try service.readPassword(keychainRef: keychainRef))
    }

    func testPrivateKeyRoundTripAndDeleteMissingIsNotFailure() throws {
        let keyData = Data("private-key-data".utf8)
        try service.savePrivateKey(keyData, passphrase: "phrase", keychainRef: keychainRef)
        XCTAssertEqual(try service.readPrivateKey(keychainRef: keychainRef), keyData)

        service.deleteCredentials(keychainRef: keychainRef)
        service.deleteCredentials(keychainRef: keychainRef)
        XCTAssertNil(try service.readPrivateKey(keychainRef: keychainRef))
    }
}
