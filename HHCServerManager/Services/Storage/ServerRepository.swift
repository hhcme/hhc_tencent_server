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

    func countCommandHistory(serverId: UUID) throws -> Int {
        try database.query("""
            SELECT COUNT(*)
            FROM command_history
            WHERE server_id = ?
        """, bindings: [
            .text(serverId.uuidString),
        ]) { statement in
            Int(sqlite3_column_int(statement, 0))
        }.first ?? 0
    }

    func deleteCommandHistory(serverId: UUID) throws {
        try database.execute("""
            DELETE FROM command_history
            WHERE server_id = ?
        """, bindings: [
            .text(serverId.uuidString),
        ])
    }

    func saveServerCapabilities(_ capabilities: ServerCapabilities, serverId: UUID) throws {
        try database.execute("""
            INSERT INTO server_capabilities (
                server_id, os_name, os_version, kernel_version, has_proc, has_systemd, has_sftp, detected_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(server_id) DO UPDATE SET
                os_name = excluded.os_name,
                os_version = excluded.os_version,
                kernel_version = excluded.kernel_version,
                has_proc = excluded.has_proc,
                has_systemd = excluded.has_systemd,
                has_sftp = excluded.has_sftp,
                detected_at = excluded.detected_at
        """, bindings: [
            .text(serverId.uuidString),
            capabilities.osName.map(SQLiteValue.text) ?? .null,
            capabilities.osVersion.map(SQLiteValue.text) ?? .null,
            capabilities.kernelVersion.map(SQLiteValue.text) ?? .null,
            .int(capabilities.hasProc ? 1 : 0),
            .int(capabilities.hasSystemd ? 1 : 0),
            .int(capabilities.hasSFTP ? 1 : 0),
            .text(AppDatabase.string(from: capabilities.detectedAt)),
        ])
    }

    func fetchServerCapabilities(serverId: UUID) throws -> ServerCapabilities? {
        try database.query("""
            SELECT os_name, os_version, kernel_version, has_proc, has_systemd, has_sftp, detected_at
            FROM server_capabilities
            WHERE server_id = ?
            LIMIT 1
        """, bindings: [
            .text(serverId.uuidString),
        ]) { statement in
            Self.mapServerCapabilities(statement)
        }.first
    }

    func saveDashboardSnapshot(_ snapshot: ServerDashboardSnapshot, serverId: UUID) throws {
        try saveServerCapabilities(snapshot.capabilities, serverId: serverId)
        let capabilitiesJSON = try encodeJSON(snapshot.capabilities)
        let metricsJSON = try encodeJSON(snapshot.metrics)
        let warningsJSON = try encodeJSON(snapshot.warnings)
        try database.execute("""
            INSERT INTO dashboard_snapshots (
                id, server_id, capabilities_json, metrics_json, warnings_json, captured_at
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, bindings: [
            .text(UUID().uuidString),
            .text(serverId.uuidString),
            .text(capabilitiesJSON),
            .text(metricsJSON),
            .text(warningsJSON),
            .text(AppDatabase.string(from: snapshot.capturedAt)),
        ])
    }

    func fetchLatestDashboardSnapshot(serverId: UUID) throws -> ServerDashboardSnapshot? {
        try database.query("""
            SELECT capabilities_json, metrics_json, warnings_json, captured_at
            FROM dashboard_snapshots
            WHERE server_id = ?
            ORDER BY captured_at DESC
            LIMIT 1
        """, bindings: [
            .text(serverId.uuidString),
        ]) { statement in
            try self.mapDashboardSnapshot(statement)
        }.first
    }

    func upsertRemoteFileTransferJob(_ job: RemoteFileTransferJob, serverId: UUID) throws {
        try database.execute("""
            INSERT INTO remote_file_transfers (
                id, server_id, direction, remote_path, local_path, status, byte_count,
                progress_fraction, backend, supports_resume, supports_streaming_progress,
                message, started_at, finished_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                direction = excluded.direction,
                remote_path = excluded.remote_path,
                local_path = excluded.local_path,
                status = excluded.status,
                byte_count = excluded.byte_count,
                progress_fraction = excluded.progress_fraction,
                backend = excluded.backend,
                supports_resume = excluded.supports_resume,
                supports_streaming_progress = excluded.supports_streaming_progress,
                message = excluded.message,
                started_at = excluded.started_at,
                finished_at = excluded.finished_at
        """, bindings: [
            .text(job.id.uuidString),
            .text(serverId.uuidString),
            .text(job.direction.rawValue),
            .text(job.remotePath),
            .text(job.localPath),
            .text(job.status.rawValue),
            job.byteCount.map { .int(Int($0)) } ?? .null,
            job.progressFraction.map(SQLiteValue.double) ?? .null,
            .text(job.backend.rawValue),
            .int(job.supportsResume ? 1 : 0),
            .int(job.supportsStreamingProgress ? 1 : 0),
            job.message.map(SQLiteValue.text) ?? .null,
            .text(AppDatabase.string(from: job.startedAt)),
            job.finishedAt.map { .text(AppDatabase.string(from: $0)) } ?? .null,
        ])
    }

    func fetchRemoteFileTransferJobs(serverId: UUID, limit: Int = 20) throws -> [RemoteFileTransferJob] {
        try database.query("""
            SELECT id, direction, remote_path, local_path, status, byte_count,
                   progress_fraction, backend, supports_resume, supports_streaming_progress,
                   message, started_at, finished_at
            FROM remote_file_transfers
            WHERE server_id = ?
            ORDER BY started_at DESC
            LIMIT ?
        """, bindings: [
            .text(serverId.uuidString),
            .int(max(1, limit)),
        ]) { statement in
            try Self.mapRemoteFileTransferJob(statement)
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

    func saveRemoteChangeLog(_ entry: RemoteChangeLogEntry) throws {
        try database.execute("""
            INSERT INTO remote_change_logs (
                id, server_id, provider_id, target_type, target_id, action,
                before_snapshot, after_snapshot, status, message, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, bindings: [
            .text(entry.id.uuidString),
            entry.serverId.map { .text($0.uuidString) } ?? .null,
            entry.providerId.map { .text($0.rawValue) } ?? .null,
            .text(entry.targetType),
            entry.targetId.map(SQLiteValue.text) ?? .null,
            .text(entry.action),
            entry.beforeSnapshot.map(SQLiteValue.text) ?? .null,
            entry.afterSnapshot.map(SQLiteValue.text) ?? .null,
            .text(entry.status),
            entry.message.map(SQLiteValue.text) ?? .null,
            .text(AppDatabase.string(from: entry.createdAt)),
        ])
    }

    func fetchRemoteChangeLogs(serverId: UUID? = nil, limit: Int = 100) throws -> [RemoteChangeLogEntry] {
        if let serverId {
            return try database.query("""
                SELECT id, server_id, provider_id, target_type, target_id, action,
                       before_snapshot, after_snapshot, status, message, created_at
                FROM remote_change_logs
                WHERE server_id = ?
                ORDER BY created_at DESC
                LIMIT ?
            """, bindings: [
                .text(serverId.uuidString),
                .int(max(1, limit)),
            ]) { statement in
                try Self.mapRemoteChangeLogEntry(statement)
            }
        }

        return try database.query("""
            SELECT id, server_id, provider_id, target_type, target_id, action,
                   before_snapshot, after_snapshot, status, message, created_at
            FROM remote_change_logs
            ORDER BY created_at DESC
            LIMIT ?
        """, bindings: [
            .int(max(1, limit)),
        ]) { statement in
            try Self.mapRemoteChangeLogEntry(statement)
        }
    }

    func fetchCloudProviderAccounts() throws -> [CloudProviderAccount] {
        try database.query("""
            SELECT id, provider_id, display_name, keychain_ref, enabled, created_at, updated_at
            FROM cloud_provider_accounts
            ORDER BY updated_at DESC
        """) { statement in
            try Self.mapCloudProviderAccount(statement)
        }
    }

    func upsertCloudProviderAccount(_ account: CloudProviderAccount) throws {
        try database.execute("""
            INSERT INTO cloud_provider_accounts (
                id, provider_id, display_name, keychain_ref, enabled, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                provider_id = excluded.provider_id,
                display_name = excluded.display_name,
                keychain_ref = excluded.keychain_ref,
                enabled = excluded.enabled,
                updated_at = excluded.updated_at
        """, bindings: [
            .text(account.id.uuidString),
            .text(account.providerId.rawValue),
            .text(account.displayName),
            .text(account.keychainRef),
            .int(account.enabled ? 1 : 0),
            .text(AppDatabase.string(from: account.createdAt)),
            .text(AppDatabase.string(from: account.updatedAt)),
        ])
    }

    func deleteCloudProviderAccount(id: UUID) throws {
        try database.execute("DELETE FROM cloud_provider_accounts WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    func fetchCloudInstanceLinks(accountId: UUID? = nil) throws -> [CloudInstanceLink] {
        if let accountId {
            return try database.query("""
                SELECT id, server_id, account_id, provider_id, region_id, instance_id, display_name,
                       public_ip, private_ip, status, instance_type, zone_id, vpc_id, security_group_ids, raw_json, last_synced_at
                FROM cloud_instance_links
                WHERE account_id = ?
                ORDER BY last_synced_at DESC, display_name ASC
            """, bindings: [.text(accountId.uuidString)]) { statement in
                try Self.mapCloudInstanceLink(statement)
            }
        }

        return try database.query("""
            SELECT id, server_id, account_id, provider_id, region_id, instance_id, display_name,
                   public_ip, private_ip, status, instance_type, zone_id, vpc_id, security_group_ids, raw_json, last_synced_at
            FROM cloud_instance_links
            ORDER BY last_synced_at DESC, display_name ASC
        """) { statement in
            try Self.mapCloudInstanceLink(statement)
        }
    }

    func fetchCloudInstanceLink(accountId: UUID, regionId: String, instanceId: String) throws -> CloudInstanceLink {
        let links = try database.query("""
            SELECT id, server_id, account_id, provider_id, region_id, instance_id, display_name,
                   public_ip, private_ip, status, instance_type, zone_id, vpc_id, security_group_ids, raw_json, last_synced_at
            FROM cloud_instance_links
            WHERE account_id = ? AND region_id = ? AND instance_id = ?
            LIMIT 1
        """, bindings: [
            .text(accountId.uuidString),
            .text(regionId),
            .text(instanceId),
        ]) { statement in
            try Self.mapCloudInstanceLink(statement)
        }

        return links.first ?? CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: accountId,
            providerId: .tencentCloud,
            regionId: regionId,
            instanceId: instanceId,
            displayName: nil,
            publicIp: nil,
            privateIp: nil,
            status: nil,
            instanceType: nil,
            zoneId: nil,
            vpcId: nil,
            securityGroupIds: [],
            rawJSON: nil,
            lastSyncedAt: nil
        )
    }

    func upsertCloudInstanceLink(_ link: CloudInstanceLink) throws {
        try database.execute("""
            INSERT INTO cloud_instance_links (
                id, server_id, account_id, provider_id, region_id, instance_id, display_name,
                public_ip, private_ip, status, instance_type, zone_id, vpc_id, security_group_ids, raw_json, last_synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, region_id, instance_id) DO UPDATE SET
                server_id = excluded.server_id,
                provider_id = excluded.provider_id,
                display_name = excluded.display_name,
                public_ip = excluded.public_ip,
                private_ip = excluded.private_ip,
                status = excluded.status,
                instance_type = excluded.instance_type,
                zone_id = excluded.zone_id,
                vpc_id = excluded.vpc_id,
                security_group_ids = excluded.security_group_ids,
                raw_json = excluded.raw_json,
                last_synced_at = excluded.last_synced_at
        """, bindings: [
            .text(link.id.uuidString),
            link.serverId.map { .text($0.uuidString) } ?? .null,
            .text(link.accountId.uuidString),
            .text(link.providerId.rawValue),
            .text(link.regionId),
            .text(link.instanceId),
            link.displayName.map(SQLiteValue.text) ?? .null,
            link.publicIp.map(SQLiteValue.text) ?? .null,
            link.privateIp.map(SQLiteValue.text) ?? .null,
            link.status.map(SQLiteValue.text) ?? .null,
            link.instanceType.map(SQLiteValue.text) ?? .null,
            link.zoneId.map(SQLiteValue.text) ?? .null,
            link.vpcId.map(SQLiteValue.text) ?? .null,
            .text(Self.encodeStringArray(link.securityGroupIds)),
            link.rawJSON.map(SQLiteValue.text) ?? .null,
            link.lastSyncedAt.map { .text(AppDatabase.string(from: $0)) } ?? .null,
        ])
    }

    func unlinkCloudInstanceFromServer(serverId: UUID) throws {
        try database.execute(
            "UPDATE cloud_instance_links SET server_id = NULL WHERE server_id = ?",
            bindings: [.text(serverId.uuidString)]
        )
    }

    func fetchCloudDisks(accountId: UUID? = nil, regionId: String? = nil) throws -> [CloudDisk] {
        let baseSQL = """
            SELECT id, account_id, provider_id, region_id, disk_id, instance_id, name,
                   disk_type, size_gb, status, billing_type, expired_time, raw_json, last_synced_at
            FROM cloud_disks
        """
        let (whereClause, bindings) = Self.cloudResourceWhereClause(accountId: accountId, regionId: regionId)
        return try database.query("""
            \(baseSQL)
            \(whereClause)
            ORDER BY last_synced_at DESC, name ASC, disk_id ASC
        """, bindings: bindings) { statement in
            try Self.mapCloudDisk(statement)
        }
    }

    func upsertCloudDisk(_ disk: CloudDisk) throws {
        try database.execute("""
            INSERT INTO cloud_disks (
                id, account_id, provider_id, region_id, disk_id, instance_id, name,
                disk_type, size_gb, status, billing_type, expired_time, raw_json, last_synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, region_id, disk_id) DO UPDATE SET
                provider_id = excluded.provider_id,
                instance_id = excluded.instance_id,
                name = excluded.name,
                disk_type = excluded.disk_type,
                size_gb = excluded.size_gb,
                status = excluded.status,
                billing_type = excluded.billing_type,
                expired_time = excluded.expired_time,
                raw_json = excluded.raw_json,
                last_synced_at = excluded.last_synced_at
        """, bindings: [
            .text(disk.id.uuidString),
            .text(disk.accountId.uuidString),
            .text(disk.providerId.rawValue),
            .text(disk.regionId),
            .text(disk.diskId),
            disk.instanceId.map(SQLiteValue.text) ?? .null,
            disk.name.map(SQLiteValue.text) ?? .null,
            disk.diskType.map(SQLiteValue.text) ?? .null,
            disk.sizeGB.map(SQLiteValue.int) ?? .null,
            disk.status.map(SQLiteValue.text) ?? .null,
            disk.billingType.map(SQLiteValue.text) ?? .null,
            disk.expiredTime.map { .text(AppDatabase.string(from: $0)) } ?? .null,
            disk.rawJSON.map(SQLiteValue.text) ?? .null,
            disk.lastSyncedAt.map { .text(AppDatabase.string(from: $0)) } ?? .null,
        ])
    }

    func fetchCloudSnapshots(accountId: UUID? = nil, regionId: String? = nil) throws -> [CloudSnapshot] {
        let baseSQL = """
            SELECT id, account_id, provider_id, region_id, snapshot_id, disk_id, name,
                   status, size_gb, created_at_provider, raw_json, last_synced_at
            FROM cloud_snapshots
        """
        let (whereClause, bindings) = Self.cloudResourceWhereClause(accountId: accountId, regionId: regionId)
        return try database.query("""
            \(baseSQL)
            \(whereClause)
            ORDER BY last_synced_at DESC, created_at_provider DESC, name ASC, snapshot_id ASC
        """, bindings: bindings) { statement in
            try Self.mapCloudSnapshot(statement)
        }
    }

    func upsertCloudSnapshot(_ snapshot: CloudSnapshot) throws {
        try database.execute("""
            INSERT INTO cloud_snapshots (
                id, account_id, provider_id, region_id, snapshot_id, disk_id, name,
                status, size_gb, created_at_provider, raw_json, last_synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, region_id, snapshot_id) DO UPDATE SET
                provider_id = excluded.provider_id,
                disk_id = excluded.disk_id,
                name = excluded.name,
                status = excluded.status,
                size_gb = excluded.size_gb,
                created_at_provider = excluded.created_at_provider,
                raw_json = excluded.raw_json,
                last_synced_at = excluded.last_synced_at
        """, bindings: [
            .text(snapshot.id.uuidString),
            .text(snapshot.accountId.uuidString),
            .text(snapshot.providerId.rawValue),
            .text(snapshot.regionId),
            .text(snapshot.snapshotId),
            snapshot.diskId.map(SQLiteValue.text) ?? .null,
            snapshot.name.map(SQLiteValue.text) ?? .null,
            snapshot.status.map(SQLiteValue.text) ?? .null,
            snapshot.sizeGB.map(SQLiteValue.int) ?? .null,
            snapshot.createdAtProvider.map { .text(AppDatabase.string(from: $0)) } ?? .null,
            snapshot.rawJSON.map(SQLiteValue.text) ?? .null,
            snapshot.lastSyncedAt.map { .text(AppDatabase.string(from: $0)) } ?? .null,
        ])
    }

    func deleteCloudSnapshot(accountId: UUID, regionId: String, snapshotId: String) throws {
        try database.execute("""
            DELETE FROM cloud_snapshots
            WHERE account_id = ? AND region_id = ? AND snapshot_id = ?
        """, bindings: [
            .text(accountId.uuidString),
            .text(regionId),
            .text(snapshotId),
        ])
    }

    func fetchCloudBillingStates(accountId: UUID? = nil) throws -> [CloudBillingState] {
        let whereClause = accountId.map { _ in "WHERE account_id = ?" } ?? ""
        let bindings: [SQLiteValue] = accountId.map { [.text($0.uuidString)] } ?? []
        return try database.query("""
            SELECT id, account_id, provider_id, resource_type, resource_id, billing_type,
                   expire_at, status, raw_json, last_synced_at
            FROM cloud_billing_states
            \(whereClause)
            ORDER BY last_synced_at DESC, resource_type ASC, resource_id ASC
        """, bindings: bindings) { statement in
            try Self.mapCloudBillingState(statement)
        }
    }

    func upsertCloudBillingState(_ state: CloudBillingState) throws {
        try database.execute("""
            INSERT INTO cloud_billing_states (
                id, account_id, provider_id, resource_type, resource_id, billing_type,
                expire_at, status, raw_json, last_synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, provider_id, resource_type, resource_id) DO UPDATE SET
                billing_type = excluded.billing_type,
                expire_at = excluded.expire_at,
                status = excluded.status,
                raw_json = excluded.raw_json,
                last_synced_at = excluded.last_synced_at
        """, bindings: [
            .text(state.id.uuidString),
            .text(state.accountId.uuidString),
            .text(state.providerId.rawValue),
            .text(state.resourceType),
            .text(state.resourceId),
            state.billingType.map(SQLiteValue.text) ?? .null,
            state.expireAt.map { .text(AppDatabase.string(from: $0)) } ?? .null,
            state.status.map(SQLiteValue.text) ?? .null,
            state.rawJSON.map(SQLiteValue.text) ?? .null,
            state.lastSyncedAt.map { .text(AppDatabase.string(from: $0)) } ?? .null,
        ])
    }

    func fetchDeploymentProjects(serverId: UUID? = nil) throws -> [DeploymentProject] {
        if let serverId {
            return try database.query("""
                SELECT id, server_id, name, repository_url, branch, deploy_path,
                       build_command, restart_command, health_check_command,
                       webhook_enabled, webhook_secret_ref, created_at, updated_at
                FROM deployment_projects
                WHERE server_id = ?
                ORDER BY updated_at DESC
            """, bindings: [.text(serverId.uuidString)]) { statement in
                try Self.mapDeploymentProject(statement)
            }
        }

        return try database.query("""
            SELECT id, server_id, name, repository_url, branch, deploy_path,
                   build_command, restart_command, health_check_command,
                   webhook_enabled, webhook_secret_ref, created_at, updated_at
            FROM deployment_projects
            ORDER BY updated_at DESC
        """) { statement in
            try Self.mapDeploymentProject(statement)
        }
    }

    func upsertDeploymentProject(_ project: DeploymentProject) throws {
        try database.execute("""
            INSERT INTO deployment_projects (
                id, server_id, name, repository_url, branch, deploy_path,
                build_command, restart_command, health_check_command,
                webhook_enabled, webhook_secret_ref, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                server_id = excluded.server_id,
                name = excluded.name,
                repository_url = excluded.repository_url,
                branch = excluded.branch,
                deploy_path = excluded.deploy_path,
                build_command = excluded.build_command,
                restart_command = excluded.restart_command,
                health_check_command = excluded.health_check_command,
                webhook_enabled = excluded.webhook_enabled,
                webhook_secret_ref = excluded.webhook_secret_ref,
                updated_at = excluded.updated_at
        """, bindings: [
            .text(project.id.uuidString),
            .text(project.serverId.uuidString),
            .text(project.name),
            .text(project.repositoryURL),
            .text(project.branch),
            .text(project.deployPath),
            project.buildCommand.map(SQLiteValue.text) ?? .null,
            project.restartCommand.map(SQLiteValue.text) ?? .null,
            project.healthCheckCommand.map(SQLiteValue.text) ?? .null,
            .int(project.webhookEnabled ? 1 : 0),
            project.webhookSecretRef.map(SQLiteValue.text) ?? .null,
            .text(AppDatabase.string(from: project.createdAt)),
            .text(AppDatabase.string(from: project.updatedAt)),
        ])
    }

    func deleteDeploymentProject(id: UUID) throws {
        try database.execute("DELETE FROM deployment_projects WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    func saveDeploymentRun(_ run: DeploymentRun) throws {
        try database.execute("""
            INSERT INTO deployment_runs (
                id, project_id, trigger_type, requested_ref, previous_commit,
                target_commit, status, started_at, finished_at, summary
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                project_id = excluded.project_id,
                trigger_type = excluded.trigger_type,
                requested_ref = excluded.requested_ref,
                previous_commit = excluded.previous_commit,
                target_commit = excluded.target_commit,
                status = excluded.status,
                started_at = excluded.started_at,
                finished_at = excluded.finished_at,
                summary = excluded.summary
        """, bindings: [
            .text(run.id.uuidString),
            .text(run.projectId.uuidString),
            .text(run.triggerType.rawValue),
            run.requestedRef.map(SQLiteValue.text) ?? .null,
            run.previousCommit.map(SQLiteValue.text) ?? .null,
            run.targetCommit.map(SQLiteValue.text) ?? .null,
            .text(run.status.rawValue),
            .text(AppDatabase.string(from: run.startedAt)),
            run.finishedAt.map { .text(AppDatabase.string(from: $0)) } ?? .null,
            run.summary.map(SQLiteValue.text) ?? .null,
        ])
    }

    func fetchDeploymentRuns(projectId: UUID, limit: Int = 50) throws -> [DeploymentRun] {
        try database.query("""
            SELECT id, project_id, trigger_type, requested_ref, previous_commit,
                   target_commit, status, started_at, finished_at, summary
            FROM deployment_runs
            WHERE project_id = ?
            ORDER BY started_at DESC
            LIMIT ?
        """, bindings: [
            .text(projectId.uuidString),
            .int(max(1, limit)),
        ]) { statement in
            try Self.mapDeploymentRun(statement)
        }
    }

    func saveDeploymentLog(_ entry: DeploymentLogEntry) throws {
        try database.execute("""
            INSERT INTO deployment_logs (
                id, run_id, step_name, stream, message, created_at
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, bindings: [
            .text(entry.id.uuidString),
            .text(entry.runId.uuidString),
            .text(entry.stepName),
            .text(entry.stream.rawValue),
            .text(entry.message),
            .text(AppDatabase.string(from: entry.createdAt)),
        ])
    }

    func fetchDeploymentLogs(runId: UUID) throws -> [DeploymentLogEntry] {
        try database.query("""
            SELECT id, run_id, step_name, stream, message, created_at
            FROM deployment_logs
            WHERE run_id = ?
            ORDER BY created_at ASC
        """, bindings: [.text(runId.uuidString)]) { statement in
            try Self.mapDeploymentLogEntry(statement)
        }
    }

    func fetchRegistryInstances(serverId: UUID? = nil) throws -> [RegistryInstance] {
        if let serverId {
            return try database.query("""
                SELECT id, server_id, kind, name, install_path, data_path, listen_host,
                       listen_port, service_name, version, status, created_at, updated_at
                FROM registry_instances
                WHERE server_id = ?
                ORDER BY updated_at DESC
            """, bindings: [.text(serverId.uuidString)]) { statement in
                try Self.mapRegistryInstance(statement)
            }
        }

        return try database.query("""
            SELECT id, server_id, kind, name, install_path, data_path, listen_host,
                   listen_port, service_name, version, status, created_at, updated_at
            FROM registry_instances
            ORDER BY updated_at DESC
        """) { statement in
            try Self.mapRegistryInstance(statement)
        }
    }

    func fetchRegistryInstance(
        serverId: UUID,
        kind: PackageRegistryKind,
        installPath: String,
        serviceName: String
    ) throws -> RegistryInstance? {
        try database.query("""
            SELECT id, server_id, kind, name, install_path, data_path, listen_host,
                   listen_port, service_name, version, status, created_at, updated_at
            FROM registry_instances
            WHERE server_id = ? AND kind = ? AND install_path = ? AND service_name = ?
            LIMIT 1
        """, bindings: [
            .text(serverId.uuidString),
            .text(kind.rawValue),
            .text(installPath),
            .text(serviceName),
        ]) { statement in
            try Self.mapRegistryInstance(statement)
        }.first
    }

    func upsertRegistryInstance(_ instance: RegistryInstance) throws {
        try database.execute("""
            INSERT INTO registry_instances (
                id, server_id, kind, name, install_path, data_path, listen_host,
                listen_port, service_name, version, status, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(server_id, kind, install_path, service_name) DO UPDATE SET
                name = excluded.name,
                data_path = excluded.data_path,
                listen_host = excluded.listen_host,
                listen_port = excluded.listen_port,
                version = excluded.version,
                status = excluded.status,
                updated_at = excluded.updated_at
        """, bindings: [
            .text(instance.id.uuidString),
            .text(instance.serverId.uuidString),
            .text(instance.kind.rawValue),
            .text(instance.name),
            .text(instance.installPath),
            .text(instance.dataPath),
            .text(instance.listenHost),
            .int(instance.listenPort),
            .text(instance.serviceName),
            .text(instance.version),
            instance.status.map(SQLiteValue.text) ?? .null,
            .text(AppDatabase.string(from: instance.createdAt)),
            .text(AppDatabase.string(from: instance.updatedAt)),
        ])
    }

    func deleteRegistryInstance(id: UUID) throws {
        try database.execute("DELETE FROM registry_instances WHERE id = ?", bindings: [.text(id.uuidString)])
    }

    func upsertRegistryBackup(_ record: RegistryBackupRecord) throws {
        try database.execute("""
            INSERT INTO registry_backups (
                id, registry_id, backup_path, status, size_bytes, created_at, restored_at, message
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                backup_path = excluded.backup_path,
                status = excluded.status,
                size_bytes = excluded.size_bytes,
                restored_at = excluded.restored_at,
                message = excluded.message
        """, bindings: [
            .text(record.id.uuidString),
            .text(record.registryId.uuidString),
            .text(record.backupPath),
            .text(record.status.rawValue),
            record.sizeBytes.map { .int(Int($0)) } ?? .null,
            .text(AppDatabase.string(from: record.createdAt)),
            record.restoredAt.map { .text(AppDatabase.string(from: $0)) } ?? .null,
            record.message.map(SQLiteValue.text) ?? .null,
        ])
    }

    func fetchRegistryBackups(registryId: UUID, limit: Int = 50) throws -> [RegistryBackupRecord] {
        try database.query("""
            SELECT id, registry_id, backup_path, status, size_bytes, created_at, restored_at, message
            FROM registry_backups
            WHERE registry_id = ?
            ORDER BY created_at DESC
            LIMIT ?
        """, bindings: [
            .text(registryId.uuidString),
            .int(max(1, limit)),
        ]) { statement in
            try Self.mapRegistryBackupRecord(statement)
        }
    }

    func fetchRegistryBackups(serverId: UUID, limit: Int = 50) throws -> [RegistryBackupRecord] {
        try database.query("""
            SELECT b.id, b.registry_id, b.backup_path, b.status, b.size_bytes,
                   b.created_at, b.restored_at, b.message
            FROM registry_backups b
            INNER JOIN registry_instances r ON r.id = b.registry_id
            WHERE r.server_id = ?
            ORDER BY b.created_at DESC
            LIMIT ?
        """, bindings: [
            .text(serverId.uuidString),
            .int(max(1, limit)),
        ]) { statement in
            try Self.mapRegistryBackupRecord(statement)
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

    private static func mapServerCapabilities(_ statement: OpaquePointer) -> ServerCapabilities {
        ServerCapabilities(
            osName: optionalString(statement, 0),
            osVersion: optionalString(statement, 1),
            kernelVersion: optionalString(statement, 2),
            hasProc: sqlite3_column_int(statement, 3) != 0,
            hasSystemd: sqlite3_column_int(statement, 4) != 0,
            hasSFTP: sqlite3_column_int(statement, 5) != 0,
            detectedAt: date(statement, 6)
        )
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        let data = try jsonEncoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DatabaseError.bindFailed("Could not encode dashboard snapshot JSON.")
        }
        return text
    }

    private static func encodeStringArray(_ value: [String]) -> String {
        guard let data = try? JSONEncoder().encode(value) else {
            return "[]"
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeStringArray(_ value: String?) -> [String] {
        guard let value,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func mapDashboardSnapshot(_ statement: OpaquePointer) throws -> ServerDashboardSnapshot {
        let capabilitiesData = Data(Self.string(statement, 0).utf8)
        let metricsData = Data(Self.string(statement, 1).utf8)
        let warningsData = Data(Self.string(statement, 2).utf8)
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        return ServerDashboardSnapshot(
            capabilities: try jsonDecoder.decode(ServerCapabilities.self, from: capabilitiesData),
            metrics: try jsonDecoder.decode([DashboardMetric].self, from: metricsData),
            warnings: try jsonDecoder.decode([DashboardWarning].self, from: warningsData),
            capturedAt: Self.date(statement, 3)
        )
    }

    private static func mapRemoteFileTransferJob(_ statement: OpaquePointer) throws -> RemoteFileTransferJob {
        RemoteFileTransferJob(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            direction: RemoteFileTransferDirection(rawValue: string(statement, 1)) ?? .upload,
            remotePath: string(statement, 2),
            localPath: string(statement, 3),
            status: RemoteFileTransferStatus(rawValue: string(statement, 4)) ?? .failed,
            byteCount: optionalInt64(statement, 5),
            progressFraction: optionalDouble(statement, 6),
            backend: RemoteFileTransferBackend(rawValue: string(statement, 7)) ?? .unknown,
            supportsResume: sqlite3_column_int(statement, 8) != 0,
            supportsStreamingProgress: sqlite3_column_int(statement, 9) != 0,
            message: optionalString(statement, 10),
            startedAt: date(statement, 11),
            finishedAt: optionalDate(statement, 12)
        )
    }

    private static func mapRemoteChangeLogEntry(_ statement: OpaquePointer) throws -> RemoteChangeLogEntry {
        RemoteChangeLogEntry(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            serverId: optionalUUID(statement, 1),
            providerId: optionalString(statement, 2).flatMap(CloudProviderID.init(rawValue:)),
            targetType: string(statement, 3),
            targetId: optionalString(statement, 4),
            action: string(statement, 5),
            beforeSnapshot: optionalString(statement, 6),
            afterSnapshot: optionalString(statement, 7),
            status: string(statement, 8),
            message: optionalString(statement, 9),
            createdAt: date(statement, 10)
        )
    }

    private static func mapCloudProviderAccount(_ statement: OpaquePointer) throws -> CloudProviderAccount {
        CloudProviderAccount(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            providerId: CloudProviderID(rawValue: string(statement, 1)) ?? .tencentCloud,
            displayName: string(statement, 2),
            keychainRef: string(statement, 3),
            enabled: sqlite3_column_int(statement, 4) != 0,
            createdAt: date(statement, 5),
            updatedAt: date(statement, 6)
        )
    }

    private static func mapCloudInstanceLink(_ statement: OpaquePointer) throws -> CloudInstanceLink {
        CloudInstanceLink(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            serverId: optionalUUID(statement, 1),
            accountId: UUID(uuidString: string(statement, 2)) ?? UUID(),
            providerId: CloudProviderID(rawValue: string(statement, 3)) ?? .tencentCloud,
            regionId: string(statement, 4),
            instanceId: string(statement, 5),
            displayName: optionalString(statement, 6),
            publicIp: optionalString(statement, 7),
            privateIp: optionalString(statement, 8),
            status: optionalString(statement, 9),
            instanceType: optionalString(statement, 10),
            zoneId: optionalString(statement, 11),
            vpcId: optionalString(statement, 12),
            securityGroupIds: decodeStringArray(optionalString(statement, 13)),
            rawJSON: optionalString(statement, 14),
            lastSyncedAt: optionalDate(statement, 15)
        )
    }

    private static func mapCloudDisk(_ statement: OpaquePointer) throws -> CloudDisk {
        CloudDisk(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            accountId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            providerId: CloudProviderID(rawValue: string(statement, 2)) ?? .tencentCloud,
            regionId: string(statement, 3),
            diskId: string(statement, 4),
            instanceId: optionalString(statement, 5),
            name: optionalString(statement, 6),
            diskType: optionalString(statement, 7),
            sizeGB: optionalInt(statement, 8),
            status: optionalString(statement, 9),
            billingType: optionalString(statement, 10),
            expiredTime: optionalDate(statement, 11),
            rawJSON: optionalString(statement, 12),
            lastSyncedAt: optionalDate(statement, 13)
        )
    }

    private static func mapCloudSnapshot(_ statement: OpaquePointer) throws -> CloudSnapshot {
        CloudSnapshot(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            accountId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            providerId: CloudProviderID(rawValue: string(statement, 2)) ?? .tencentCloud,
            regionId: string(statement, 3),
            snapshotId: string(statement, 4),
            diskId: optionalString(statement, 5),
            name: optionalString(statement, 6),
            status: optionalString(statement, 7),
            sizeGB: optionalInt(statement, 8),
            createdAtProvider: optionalDate(statement, 9),
            rawJSON: optionalString(statement, 10),
            lastSyncedAt: optionalDate(statement, 11)
        )
    }

    private static func mapCloudBillingState(_ statement: OpaquePointer) throws -> CloudBillingState {
        CloudBillingState(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            accountId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            providerId: CloudProviderID(rawValue: string(statement, 2)) ?? .tencentCloud,
            resourceType: string(statement, 3),
            resourceId: string(statement, 4),
            billingType: optionalString(statement, 5),
            expireAt: optionalDate(statement, 6),
            status: optionalString(statement, 7),
            rawJSON: optionalString(statement, 8),
            lastSyncedAt: optionalDate(statement, 9)
        )
    }

    private static func mapDeploymentProject(_ statement: OpaquePointer) throws -> DeploymentProject {
        DeploymentProject(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            serverId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            name: string(statement, 2),
            repositoryURL: string(statement, 3),
            branch: string(statement, 4),
            deployPath: string(statement, 5),
            buildCommand: optionalString(statement, 6),
            restartCommand: optionalString(statement, 7),
            healthCheckCommand: optionalString(statement, 8),
            webhookEnabled: sqlite3_column_int(statement, 9) != 0,
            webhookSecretRef: optionalString(statement, 10),
            createdAt: date(statement, 11),
            updatedAt: date(statement, 12)
        )
    }

    private static func mapDeploymentRun(_ statement: OpaquePointer) throws -> DeploymentRun {
        DeploymentRun(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            projectId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            triggerType: DeploymentTriggerType(rawValue: string(statement, 2)) ?? .manual,
            requestedRef: optionalString(statement, 3),
            previousCommit: optionalString(statement, 4),
            targetCommit: optionalString(statement, 5),
            status: DeploymentRunStatus(rawValue: string(statement, 6)) ?? .pending,
            startedAt: date(statement, 7),
            finishedAt: optionalDate(statement, 8),
            summary: optionalString(statement, 9)
        )
    }

    private static func mapDeploymentLogEntry(_ statement: OpaquePointer) throws -> DeploymentLogEntry {
        DeploymentLogEntry(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            runId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            stepName: string(statement, 2),
            stream: DeploymentLogStream(rawValue: string(statement, 3)) ?? .system,
            message: string(statement, 4),
            createdAt: date(statement, 5)
        )
    }

    private static func mapRegistryInstance(_ statement: OpaquePointer) throws -> RegistryInstance {
        RegistryInstance(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            serverId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            kind: PackageRegistryKind(rawValue: string(statement, 2)) ?? .verdaccio,
            name: string(statement, 3),
            installPath: string(statement, 4),
            dataPath: string(statement, 5),
            listenHost: string(statement, 6),
            listenPort: Int(sqlite3_column_int(statement, 7)),
            serviceName: string(statement, 8),
            version: string(statement, 9),
            status: optionalString(statement, 10),
            createdAt: date(statement, 11),
            updatedAt: date(statement, 12)
        )
    }

    private static func mapRegistryBackupRecord(_ statement: OpaquePointer) throws -> RegistryBackupRecord {
        RegistryBackupRecord(
            id: UUID(uuidString: string(statement, 0)) ?? UUID(),
            registryId: UUID(uuidString: string(statement, 1)) ?? UUID(),
            backupPath: string(statement, 2),
            status: RegistryBackupStatus(rawValue: string(statement, 3)) ?? .created,
            sizeBytes: optionalInt64(statement, 4),
            createdAt: date(statement, 5),
            restoredAt: optionalDate(statement, 6),
            message: optionalString(statement, 7)
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

    private static func optionalDate(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return AppDatabase.date(from: string(statement, index))
    }

    private static func optionalUUID(_ statement: OpaquePointer, _ index: Int32) -> UUID? {
        guard let value = optionalString(statement, index) else { return nil }
        return UUID(uuidString: value)
    }

    private static func optionalInt32(_ statement: OpaquePointer, _ index: Int32) -> Int32? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int(statement, index)
    }

    private static func optionalInt64(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private static func optionalInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private static func optionalDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private static func optionalDuration(_ statement: OpaquePointer, _ index: Int32) -> TimeInterval? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return TimeInterval(sqlite3_column_int(statement, index)) / 1_000
    }

    private static func cloudResourceWhereClause(accountId: UUID?, regionId: String?) -> (String, [SQLiteValue]) {
        var conditions: [String] = []
        var bindings: [SQLiteValue] = []
        if let accountId {
            conditions.append("account_id = ?")
            bindings.append(.text(accountId.uuidString))
        }
        if let regionId {
            conditions.append("region_id = ?")
            bindings.append(.text(regionId))
        }
        guard !conditions.isEmpty else { return ("", []) }
        return ("WHERE \(conditions.joined(separator: " AND "))", bindings)
    }
}
