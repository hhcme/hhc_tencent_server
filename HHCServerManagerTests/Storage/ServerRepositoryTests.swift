import XCTest
@testable import HHCServerManager

final class ServerRepositoryTests: XCTestCase {
    func testInsertFetchUpdateDeleteServer() throws {
        let repository = try makeRepository()
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_010)

        let original = ServerProfile(
            id: id,
            name: "Tencent Test",
            host: "example.internal",
            port: 22,
            username: "root",
            authType: .privateKey,
            keychainRef: "server_\(id.uuidString)",
            groupName: "prod",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try repository.upsert(original)
        var servers = try repository.fetchServers()
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].id, id)
        XCTAssertEqual(servers[0].authType, .privateKey)
        XCTAssertEqual(servers[0].groupName, "prod")

        var updated = original
        updated.name = "Renamed"
        updated.port = 2222
        updated.groupName = nil
        updated.updatedAt = Date(timeIntervalSince1970: 1_700_000_020)
        try repository.upsert(updated)

        servers = try repository.fetchServers()
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].name, "Renamed")
        XCTAssertEqual(servers[0].port, 2222)
        XCTAssertNil(servers[0].groupName)

        try repository.deleteServer(id: id)
        XCTAssertTrue(try repository.fetchServers().isEmpty)
    }

    func testDeletingServerCascadesTrustedHostKeys() throws {
        let repository = try makeRepository()
        let server = makeServer()
        try repository.upsert(server)
        try repository.saveTrustedHostKey(TrustedHostKey(
            id: UUID(),
            serverId: server.id,
            host: server.host,
            port: server.port,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:test",
            rawPublicKey: "example.internal ssh-ed25519 AAAATEST",
            trustedAt: Date()
        ))

        XCTAssertEqual(try repository.fetchTrustedHostKeys(serverId: server.id).count, 1)
        try repository.deleteServer(id: server.id)
        XCTAssertTrue(try repository.fetchTrustedHostKeys(serverId: server.id).isEmpty)
    }

    private func makeRepository() throws -> ServerRepository {
        ServerRepository(database: try AppDatabase.inMemory())
    }

    private func makeServer() -> ServerProfile {
        let id = UUID()
        return ServerProfile(
            id: id,
            name: "Test",
            host: "example.internal",
            port: 22,
            username: "root",
            authType: .privateKey,
            keychainRef: "server_\(id.uuidString)",
            groupName: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
