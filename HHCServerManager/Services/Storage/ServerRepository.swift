import Foundation
import SQLite3

final class ServerRepository: @unchecked Sendable {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchServers() throws -> [ServerProfile] {
        try database.query("""
            SELECT id, name, host, port, username, auth_type, keychain_ref, group_name, created_at, updated_at
            FROM server_profiles
            ORDER BY updated_at DESC
        """) { statement in
            try Self.mapServer(statement)
        }
    }

    func upsert(_ profile: ServerProfile) throws {
        try database.execute("""
            INSERT INTO server_profiles (
                id, name, host, port, username, auth_type, keychain_ref, group_name, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                host = excluded.host,
                port = excluded.port,
                username = excluded.username,
                auth_type = excluded.auth_type,
                keychain_ref = excluded.keychain_ref,
                group_name = excluded.group_name,
                updated_at = excluded.updated_at
        """, bindings: [
            .text(profile.id.uuidString),
            .text(profile.name),
            .text(profile.host),
            .int(profile.port),
            .text(profile.username),
            .text(profile.authType.rawValue),
            .text(profile.keychainRef),
            profile.groupName.map(SQLiteValue.text) ?? .null,
            .text(AppDatabase.string(from: profile.createdAt)),
            .text(AppDatabase.string(from: profile.updatedAt)),
        ])
    }

    func deleteServer(id: UUID) throws {
        try database.execute("DELETE FROM server_profiles WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    func fetchTrustedHostKeys(serverId: UUID) throws -> [TrustedHostKey] {
        try database.query("""
            SELECT id, server_id, host, port, algorithm, fingerprint_sha256, raw_public_key, trusted_at
            FROM trusted_host_keys
            WHERE server_id = ?
            ORDER BY trusted_at DESC
        """, bindings: [.text(serverId.uuidString)]) { statement in
            try Self.mapTrustedHostKey(statement)
        }
    }

    func fetchAllTrustedHostKeys() throws -> [TrustedHostKey] {
        try database.query("""
            SELECT id, server_id, host, port, algorithm, fingerprint_sha256, raw_public_key, trusted_at
            FROM trusted_host_keys
            ORDER BY trusted_at ASC
        """) { statement in
            try Self.mapTrustedHostKey(statement)
        }
    }

    func saveTrustedHostKey(_ trustedHostKey: TrustedHostKey) throws {
        try database.execute("""
            INSERT INTO trusted_host_keys (
                id, server_id, host, port, algorithm, fingerprint_sha256, raw_public_key, trusted_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(server_id, algorithm, fingerprint_sha256) DO UPDATE SET
                raw_public_key = excluded.raw_public_key,
                trusted_at = excluded.trusted_at
        """, bindings: [
            .text(trustedHostKey.id.uuidString),
            .text(trustedHostKey.serverId.uuidString),
            .text(trustedHostKey.host),
            .int(trustedHostKey.port),
            .text(trustedHostKey.algorithm),
            .text(trustedHostKey.fingerprintSHA256),
            .text(trustedHostKey.rawPublicKey),
            .text(AppDatabase.string(from: trustedHostKey.trustedAt)),
        ])
    }

    private static func mapServer(_ statement: OpaquePointer) throws -> ServerProfile {
        let id = UUID(uuidString: string(statement, 0)) ?? UUID()
        let authType = SSHAuthType(rawValue: string(statement, 5)) ?? .privateKey
        return ServerProfile(
            id: id,
            name: string(statement, 1),
            host: string(statement, 2),
            port: Int(sqlite3_column_int(statement, 3)),
            username: string(statement, 4),
            authType: authType,
            keychainRef: string(statement, 6),
            groupName: optionalString(statement, 7),
            createdAt: date(statement, 8),
            updatedAt: date(statement, 9)
        )
    }

    private static func mapTrustedHostKey(_ statement: OpaquePointer) throws -> TrustedHostKey {
        TrustedHostKey(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            serverId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            host: string(statement, 2),
            port: Int(sqlite3_column_int(statement, 3)),
            algorithm: string(statement, 4),
            fingerprintSHA256: string(statement, 5),
            rawPublicKey: string(statement, 6),
            trustedAt: date(statement, 7)
        )
    }

    private static func string(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private static func optionalString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = string(statement, index).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func date(_ statement: OpaquePointer, _ index: Int32) -> Date {
        AppDatabase.date(from: string(statement, index)) ?? Date()
    }
}
