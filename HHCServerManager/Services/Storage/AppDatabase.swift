import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            "Could not open database: \(message)"
        case let .prepareFailed(message):
            "Could not prepare database statement: \(message)"
        case let .stepFailed(message):
            "Could not execute database statement: \(message)"
        case let .bindFailed(message):
            "Could not bind database value: \(message)"
        }
    }
}

enum SQLiteValue {
    case text(String)
    case int(Int)
    case double(Double)
    case null
}

final class AppDatabase: @unchecked Sendable {
    private let db: OpaquePointer?
    private let queue = DispatchQueue(label: "me.hhc.HHCServerManager.database")

    static func string(from date: Date) -> String {
        dateFormatter().string(from: date)
    }

    static func date(from string: String) -> Date? {
        dateFormatter().date(from: string)
    }

    private static func dateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func production() throws -> AppDatabase {
        let supportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appURL = supportURL.appendingPathComponent("HHCServerManager", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        return try AppDatabase(url: appURL.appendingPathComponent("HHCServerManager.sqlite"))
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(databasePath: ":memory:")
    }

    convenience init(url: URL) throws {
        try self.init(databasePath: url.path)
    }

    private init(databasePath: String) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databasePath, &opened, flags, nil) == SQLITE_OK else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DatabaseError.openFailed(message)
        }
        db = opened
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        try queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage)
            }
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(lastErrorMessage)
            }
        }
    }

    func query<T>(_ sql: String, bindings: [SQLiteValue] = [], map: (OpaquePointer) throws -> T) throws -> [T] {
        try queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage)
            }
            defer { sqlite3_finalize(statement) }
            try bind(bindings, to: statement)

            var rows: [T] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_ROW {
                    rows.append(try map(statement!))
                } else if result == SQLITE_DONE {
                    return rows
                } else {
                    throw DatabaseError.stepFailed(lastErrorMessage)
                }
            }
        }
    }

    private func migrate() throws {
        try execute("PRAGMA foreign_keys = ON")
        try execute("""
            CREATE TABLE IF NOT EXISTS server_profiles (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                host TEXT NOT NULL,
                port INTEGER NOT NULL DEFAULT 22,
                username TEXT NOT NULL,
                auth_type TEXT NOT NULL,
                keychain_ref TEXT NOT NULL,
                group_name TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS trusted_host_keys (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
                host TEXT NOT NULL,
                port INTEGER NOT NULL,
                algorithm TEXT NOT NULL,
                fingerprint_sha256 TEXT NOT NULL,
                raw_public_key TEXT NOT NULL,
                trusted_at TEXT NOT NULL,
                UNIQUE(server_id, algorithm, fingerprint_sha256)
            )
        """)
    }

    private var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(db))
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case let .text(text):
                result = sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case let .int(int):
                result = sqlite3_bind_int64(statement, index, sqlite3_int64(int))
            case let .double(double):
                result = sqlite3_bind_double(statement, index, double)
            case .null:
                result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else {
                throw DatabaseError.bindFailed(lastErrorMessage)
            }
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
