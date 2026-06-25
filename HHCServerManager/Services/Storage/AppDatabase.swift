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
        try execute("""
            CREATE TABLE IF NOT EXISTS command_history (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
                command TEXT NOT NULL,
                exit_code INTEGER,
                duration_ms INTEGER,
                created_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_command_history_server_created_at
            ON command_history(server_id, created_at DESC)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS server_capabilities (
                server_id TEXT PRIMARY KEY NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
                os_name TEXT,
                os_version TEXT,
                kernel_version TEXT,
                has_proc INTEGER NOT NULL DEFAULT 0,
                has_systemd INTEGER NOT NULL DEFAULT 0,
                has_sftp INTEGER NOT NULL DEFAULT 0,
                detected_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS dashboard_snapshots (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
                capabilities_json TEXT NOT NULL,
                metrics_json TEXT NOT NULL,
                warnings_json TEXT NOT NULL,
                captured_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_dashboard_snapshots_server_captured_at
            ON dashboard_snapshots(server_id, captured_at DESC)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS remote_file_transfers (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
                direction TEXT NOT NULL,
                remote_path TEXT NOT NULL,
                local_path TEXT NOT NULL,
                status TEXT NOT NULL,
                byte_count INTEGER,
                progress_fraction REAL,
                message TEXT,
                started_at TEXT NOT NULL,
                finished_at TEXT
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_remote_file_transfers_server_started_at
            ON remote_file_transfers(server_id, started_at DESC)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS operation_logs (
                id TEXT PRIMARY KEY NOT NULL,
                scope TEXT NOT NULL,
                action TEXT NOT NULL,
                target_id TEXT,
                status TEXT NOT NULL,
                message TEXT,
                created_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_operation_logs_created_at
            ON operation_logs(created_at DESC)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS remote_change_logs (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT REFERENCES server_profiles(id) ON DELETE SET NULL,
                provider_id TEXT,
                target_type TEXT NOT NULL,
                target_id TEXT,
                action TEXT NOT NULL,
                before_snapshot TEXT,
                after_snapshot TEXT,
                status TEXT NOT NULL,
                message TEXT,
                created_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_remote_change_logs_created_at
            ON remote_change_logs(created_at DESC)
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_remote_change_logs_server_created_at
            ON remote_change_logs(server_id, created_at DESC)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS cloud_provider_accounts (
                id TEXT PRIMARY KEY NOT NULL,
                provider_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                keychain_ref TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS cloud_instance_links (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT REFERENCES server_profiles(id) ON DELETE SET NULL,
                account_id TEXT NOT NULL REFERENCES cloud_provider_accounts(id) ON DELETE CASCADE,
                provider_id TEXT NOT NULL,
                region_id TEXT NOT NULL,
                instance_id TEXT NOT NULL,
                display_name TEXT,
                public_ip TEXT,
                private_ip TEXT,
                status TEXT,
                instance_type TEXT,
                zone_id TEXT,
                vpc_id TEXT,
                raw_json TEXT,
                last_synced_at TEXT,
                UNIQUE(account_id, region_id, instance_id)
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_cloud_instance_links_server
            ON cloud_instance_links(server_id)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS cloud_disks (
                id TEXT PRIMARY KEY NOT NULL,
                account_id TEXT NOT NULL REFERENCES cloud_provider_accounts(id) ON DELETE CASCADE,
                provider_id TEXT NOT NULL,
                region_id TEXT NOT NULL,
                disk_id TEXT NOT NULL,
                instance_id TEXT,
                name TEXT,
                disk_type TEXT,
                size_gb INTEGER,
                status TEXT,
                billing_type TEXT,
                expired_time TEXT,
                raw_json TEXT,
                last_synced_at TEXT,
                UNIQUE(account_id, region_id, disk_id)
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_cloud_disks_account_region
            ON cloud_disks(account_id, region_id)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS cloud_snapshots (
                id TEXT PRIMARY KEY NOT NULL,
                account_id TEXT NOT NULL REFERENCES cloud_provider_accounts(id) ON DELETE CASCADE,
                provider_id TEXT NOT NULL,
                region_id TEXT NOT NULL,
                snapshot_id TEXT NOT NULL,
                disk_id TEXT,
                name TEXT,
                status TEXT,
                size_gb INTEGER,
                created_at_provider TEXT,
                raw_json TEXT,
                last_synced_at TEXT,
                UNIQUE(account_id, region_id, snapshot_id)
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_cloud_snapshots_account_region
            ON cloud_snapshots(account_id, region_id)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS cloud_billing_states (
                id TEXT PRIMARY KEY NOT NULL,
                account_id TEXT NOT NULL REFERENCES cloud_provider_accounts(id) ON DELETE CASCADE,
                provider_id TEXT NOT NULL,
                resource_type TEXT NOT NULL,
                resource_id TEXT NOT NULL,
                billing_type TEXT,
                expire_at TEXT,
                status TEXT,
                raw_json TEXT,
                last_synced_at TEXT,
                UNIQUE(account_id, provider_id, resource_type, resource_id)
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_cloud_billing_states_account
            ON cloud_billing_states(account_id)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS deployment_projects (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                repository_url TEXT NOT NULL,
                branch TEXT NOT NULL,
                deploy_path TEXT NOT NULL,
                build_command TEXT,
                restart_command TEXT,
                health_check_command TEXT,
                webhook_enabled INTEGER NOT NULL DEFAULT 0,
                webhook_secret_ref TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_deployment_projects_server_updated_at
            ON deployment_projects(server_id, updated_at DESC)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS deployment_runs (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL REFERENCES deployment_projects(id) ON DELETE CASCADE,
                trigger_type TEXT NOT NULL,
                requested_ref TEXT,
                previous_commit TEXT,
                target_commit TEXT,
                status TEXT NOT NULL,
                started_at TEXT NOT NULL,
                finished_at TEXT,
                summary TEXT
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_deployment_runs_project_started_at
            ON deployment_runs(project_id, started_at DESC)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS deployment_logs (
                id TEXT PRIMARY KEY NOT NULL,
                run_id TEXT NOT NULL REFERENCES deployment_runs(id) ON DELETE CASCADE,
                step_name TEXT NOT NULL,
                stream TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_deployment_logs_run_created_at
            ON deployment_logs(run_id, created_at ASC)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS registry_instances (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
                kind TEXT NOT NULL,
                name TEXT NOT NULL,
                install_path TEXT NOT NULL,
                data_path TEXT NOT NULL,
                listen_host TEXT NOT NULL,
                listen_port INTEGER NOT NULL,
                service_name TEXT NOT NULL,
                version TEXT NOT NULL,
                status TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)
        try execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_registry_instances_identity
            ON registry_instances(server_id, kind, install_path, service_name)
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_registry_instances_server_updated_at
            ON registry_instances(server_id, updated_at DESC)
        """)
        try execute("""
            CREATE TABLE IF NOT EXISTS registry_backups (
                id TEXT PRIMARY KEY NOT NULL,
                registry_id TEXT NOT NULL REFERENCES registry_instances(id) ON DELETE CASCADE,
                backup_path TEXT NOT NULL,
                status TEXT NOT NULL,
                size_bytes INTEGER,
                created_at TEXT NOT NULL,
                restored_at TEXT,
                message TEXT
            )
        """)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_registry_backups_registry_created_at
            ON registry_backups(registry_id, created_at DESC)
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
