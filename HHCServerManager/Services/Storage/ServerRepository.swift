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

    func saveCommandHistory(_ entry: CommandHistoryEntry) throws {
        try database.execute("""
            INSERT INTO command_history (
                id, server_id, command, exit_code, duration_ms, created_at
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, bindings: [
            .text(entry.id.uuidString),
            .text(entry.serverId.uuidString),
            .text(entry.command),
            entry.exitCode.map { .int(Int($0)) } ?? .null,
            entry.duration.map { .int(Int(($0 * 1_000).rounded())) } ?? .null,
            .text(AppDatabase.string(from: entry.createdAt)),
        ])
    }

    func fetchCommandHistory(serverId: UUID, limit: Int = 50) throws -> [CommandHistoryEntry] {
        try database.query("""
            SELECT id, server_id, command, exit_code, duration_ms, created_at
            FROM command_history
            WHERE server_id = ?
            ORDER BY created_at DESC
            LIMIT ?
        """, bindings: [
            .text(serverId.uuidString),
            .int(max(1, limit)),
        ]) { statement in
            try Self.mapCommandHistoryEntry(statement)
        }
    }

    func saveOperationLog(_ entry: OperationLogEntry) throws {
        try database.execute("""
            INSERT INTO operation_logs (
                id, scope, action, target_id, status, message, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """, bindings: [
            .text(entry.id.uuidString),
            .text(entry.scope),
            .text(entry.action),
            entry.targetId.map(SQLiteValue.text) ?? .null,
            .text(entry.status),
            entry.message.map(SQLiteValue.text) ?? .null,
            .text(AppDatabase.string(from: entry.createdAt)),
        ])
    }

    func fetchOperationLogs(limit: Int = 100) throws -> [OperationLogEntry] {
        try database.query("""
            SELECT id, scope, action, target_id, status, message, created_at
            FROM operation_logs
            ORDER BY created_at DESC
            LIMIT ?
        """, bindings: [
            .int(max(1, limit)),
        ]) { statement in
            try Self.mapOperationLogEntry(statement)
        }
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

    private static func mapCommandHistoryEntry(_ statement: OpaquePointer) throws -> CommandHistoryEntry {
        CommandHistoryEntry(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            serverId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            command: string(statement, 2),
            exitCode: optionalInt32(statement, 3),
            duration: optionalDuration(statement, 4),
            createdAt: date(statement, 5)
        )
    }

    private static func mapOperationLogEntry(_ statement: OpaquePointer) throws -> OperationLogEntry {
        OperationLogEntry(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            scope: string(statement, 1),
            action: string(statement, 2),
            targetId: optionalString(statement, 3),
            status: string(statement, 4),
            message: optionalString(statement, 5),
            createdAt: date(statement, 6)
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

    private static func optionalInt32(_ statement: OpaquePointer, _ index: Int32) -> Int32? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int(statement, index)
    }

    private static func optionalDuration(_ statement: OpaquePointer, _ index: Int32) -> TimeInterval? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return TimeInterval(sqlite3_column_int(statement, index)) / 1_000
    }
}
