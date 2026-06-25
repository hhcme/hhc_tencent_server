import CryptoKit
import Foundation
import Network

final class ServerManagementService: @unchecked Sendable {
    private let repository: ServerRepository
    private let keychain: any ServerCredentialStore
    private let makeUUID: @Sendable () -> UUID

    init(
        repository: ServerRepository,
        keychain: any ServerCredentialStore,
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.repository = repository
        self.keychain = keychain
        self.makeUUID = makeUUID
    }

    func createServer(
        name: String,
        host: String,
        port: Int,
        username: String,
        groupName: String?,
        authType: SSHAuthType,
        credential: CredentialInput
    ) throws -> ServerProfile {
        let now = Date()
        let id = makeUUID()
        let keychainRef = "server_\(id.uuidString)"

        do {
            switch credential {
            case let .password(password):
                try keychain.savePassword(password, keychainRef: keychainRef)
            case let .privateKey(data, passphrase):
                try keychain.savePrivateKey(data, passphrase: passphrase, keychainRef: keychainRef)
            }

            let profile = ServerProfile(
                id: id,
                name: name,
                host: host,
                port: port,
                username: username,
                authType: authType,
                keychainRef: keychainRef,
                groupName: groupName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                createdAt: now,
                updatedAt: now
            )
            try repository.upsert(profile)
            return profile
        } catch {
            keychain.deleteCredentials(keychainRef: keychainRef)
            throw error
        }
    }

    func deleteServer(_ profile: ServerProfile) throws {
        try repository.deleteServer(id: profile.id)
        keychain.deleteCredentials(keychainRef: profile.keychainRef)
    }

    func updateServer(
        _ existing: ServerProfile,
        name: String,
        host: String,
        port: Int,
        username: String,
        groupName: String?,
        authType: SSHAuthType,
        credentialUpdate: CredentialUpdate
    ) throws -> ServerProfile {
        let originalCredential = try existingCredential(for: existing)

        if case let .replace(credential) = credentialUpdate {
            try saveCredential(credential, keychainRef: existing.keychainRef)
        }

        let updated = ServerProfile(
            id: existing.id,
            name: name,
            host: host,
            port: port,
            username: username,
            authType: authType,
            keychainRef: existing.keychainRef,
            groupName: groupName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        do {
            try repository.upsert(updated)
            return updated
        } catch {
            if credentialUpdate != .keepExisting {
                restoreCredential(originalCredential, keychainRef: existing.keychainRef)
            }
            throw error
        }
    }

    private func saveCredential(_ credential: CredentialInput, keychainRef: String) throws {
        switch credential {
        case let .password(password):
            try keychain.savePassword(password, keychainRef: keychainRef)
        case let .privateKey(data, passphrase):
            try keychain.savePrivateKey(data, passphrase: passphrase, keychainRef: keychainRef)
        }
    }

    private func existingCredential(for profile: ServerProfile) throws -> CredentialInput? {
        switch profile.authType {
        case .password:
            return try keychain.readPassword(keychainRef: profile.keychainRef).map(CredentialInput.password)
        case .privateKey:
            guard let data = try keychain.readPrivateKey(keychainRef: profile.keychainRef) else {
                return nil
            }
            let passphrase = try keychain.readPrivateKeyPassphrase(keychainRef: profile.keychainRef)
            return .privateKey(data: data, passphrase: passphrase)
        }
    }

    private func restoreCredential(_ credential: CredentialInput?, keychainRef: String) {
        guard let credential else {
            keychain.deleteCredentials(keychainRef: keychainRef)
            return
        }
        try? saveCredential(credential, keychainRef: keychainRef)
    }

    func configureDeploymentWebhook(
        project: DeploymentProject,
        enabled: Bool,
        secret: String?
    ) throws -> DeploymentProject {
        var updated = project
        updated.webhookEnabled = enabled
        updated.updatedAt = Date()

        if enabled {
            let trimmedSecret = secret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmedSecret.isEmpty, project.webhookSecretRef == nil {
                throw DeploymentWebhookError.secretMissing
            }
            let keychainRef = project.webhookSecretRef ?? "deployment_webhook_\(project.id.uuidString)"
            if !trimmedSecret.isEmpty {
                try keychain.saveWebhookSecret(trimmedSecret, keychainRef: keychainRef)
            }
            updated.webhookSecretRef = keychainRef
        } else {
            if let keychainRef = project.webhookSecretRef {
                keychain.deleteWebhookSecret(keychainRef: keychainRef)
            }
            updated.webhookSecretRef = nil
        }

        try repository.upsertDeploymentProject(updated)
        return updated
    }

    func deleteDeploymentProject(_ project: DeploymentProject) throws {
        if let keychainRef = project.webhookSecretRef {
            keychain.deleteWebhookSecret(keychainRef: keychainRef)
        }
        try repository.deleteDeploymentProject(id: project.id)
    }
}

final class CloudAccountService: @unchecked Sendable {
    private let repository: ServerRepository
    private let keychain: KeychainService

    init(repository: ServerRepository, keychain: KeychainService) {
        self.repository = repository
        self.keychain = keychain
    }

    func createAccount(
        providerId: CloudProviderID,
        displayName: String,
        credential: CloudProviderCredential,
        enabled: Bool = true
    ) throws -> CloudProviderAccount {
        let now = Date()
        let id = UUID()
        let keychainRef = "cloud_\(id.uuidString)"

        do {
            try keychain.saveCloudCredential(credential, keychainRef: keychainRef)
            let account = CloudProviderAccount(
                id: id,
                providerId: providerId,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                keychainRef: keychainRef,
                enabled: enabled,
                createdAt: now,
                updatedAt: now
            )
            try repository.upsertCloudProviderAccount(account)
            return account
        } catch {
            keychain.deleteCloudCredential(keychainRef: keychainRef)
            throw error
        }
    }

    func updateAccount(
        _ existing: CloudProviderAccount,
        displayName: String,
        enabled: Bool,
        credential: CloudProviderCredential?
    ) throws -> CloudProviderAccount {
        if let credential {
            try keychain.saveCloudCredential(credential, keychainRef: existing.keychainRef)
        }

        let updated = CloudProviderAccount(
            id: existing.id,
            providerId: existing.providerId,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            keychainRef: existing.keychainRef,
            enabled: enabled,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
        try repository.upsertCloudProviderAccount(updated)
        return updated
    }

    func deleteAccount(_ account: CloudProviderAccount) throws {
        try repository.deleteCloudProviderAccount(id: account.id)
        keychain.deleteCloudCredential(keychainRef: account.keychainRef)
    }
}

final class CloudInstanceSyncService: @unchecked Sendable {
    private let repository: ServerRepository
    private let keychain: KeychainService
    private let registry: CloudProviderRegistry
    private let serverManagementService: ServerManagementService
    private let now: @Sendable () -> Date

    init(
        repository: ServerRepository,
        keychain: KeychainService,
        registry: CloudProviderRegistry,
        serverManagementService: ServerManagementService,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.keychain = keychain
        self.registry = registry
        self.serverManagementService = serverManagementService
        self.now = now
    }

    func validateAccount(_ account: CloudProviderAccount) async throws {
        let credential = try credential(for: account)
        try await registry.adapter(for: account.providerId).validateCredential(credential)
    }

    func fetchRegions(account: CloudProviderAccount) async throws -> [CloudRegion] {
        let credential = try credential(for: account)
        return try await registry.adapter(for: account.providerId).fetchRegions(credential: credential)
    }

    func syncInstances(account: CloudProviderAccount, regionId: String) async throws -> [CloudInstanceLink] {
        guard account.enabled else {
            throw CloudProviderError.providerFailure("Cloud account is disabled.")
        }

        try registry.require(.instanceDiscovery, providerId: account.providerId)
        let credential = try credential(for: account)
        let instances = try await registry.adapter(for: account.providerId).fetchInstances(
            credential: credential,
            regionId: regionId
        )

        var links: [CloudInstanceLink] = []
        let syncedAt = now()
        for instance in instances {
            var existing = try repository.fetchCloudInstanceLink(
                accountId: account.id,
                regionId: instance.regionId,
                instanceId: instance.id
            )
            existing.apply(instance: instance, accountId: account.id, syncedAt: syncedAt)
            try repository.upsertCloudInstanceLink(existing)
            links.append(existing)
        }
        return links
    }

    func syncDisks(account: CloudProviderAccount, regionId: String) async throws -> [CloudDisk] {
        guard account.enabled else {
            throw CloudProviderError.providerFailure("Cloud account is disabled.")
        }

        try registry.require(.cloudDisks, providerId: account.providerId)
        let syncedAt = now()
        let credential = try credential(for: account)
        let disks = try await registry.adapter(for: account.providerId).fetchDisks(
            credential: credential,
            accountId: account.id,
            regionId: regionId,
            capturedAt: syncedAt
        )

        for disk in disks {
            try repository.upsertCloudDisk(disk)
        }
        return disks
    }

    func syncSnapshots(account: CloudProviderAccount, regionId: String) async throws -> [CloudSnapshot] {
        guard account.enabled else {
            throw CloudProviderError.providerFailure("Cloud account is disabled.")
        }

        try registry.require(.cloudSnapshots, providerId: account.providerId)
        let syncedAt = now()
        let credential = try credential(for: account)
        let snapshots = try await registry.adapter(for: account.providerId).fetchSnapshots(
            credential: credential,
            accountId: account.id,
            regionId: regionId,
            capturedAt: syncedAt
        )

        for snapshot in snapshots {
            try repository.upsertCloudSnapshot(snapshot)
        }
        return snapshots
    }

    func createSnapshot(
        account: CloudProviderAccount,
        regionId: String,
        diskId: String,
        snapshotName: String
    ) async throws -> CloudSnapshot {
        guard account.enabled else {
            throw CloudProviderError.providerFailure("Cloud account is disabled.")
        }
        let trimmedName = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CloudProviderError.providerFailure("Snapshot name is required.")
        }
        try registry.require(.snapshotActions, providerId: account.providerId)
        let capturedAt = now()
        let credential = try credential(for: account)
        do {
            let snapshot = try await registry.adapter(for: account.providerId).createSnapshot(
                credential: credential,
                accountId: account.id,
                regionId: regionId,
                diskId: diskId,
                snapshotName: trimmedName,
                capturedAt: capturedAt
            )
            try repository.upsertCloudSnapshot(snapshot)
            try saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_snapshot",
                targetId: snapshot.snapshotId,
                action: "create_snapshot",
                beforeSnapshot: "disk=\(diskId)",
                afterSnapshot: "snapshot=\(snapshot.snapshotId), name=\(trimmedName)",
                status: "success",
                message: "region=\(regionId)",
                createdAt: capturedAt
            )
            return snapshot
        } catch {
            try? saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_snapshot",
                targetId: diskId,
                action: "create_snapshot",
                beforeSnapshot: "disk=\(diskId)",
                afterSnapshot: nil,
                status: "failed",
                message: error.localizedDescription,
                createdAt: capturedAt
            )
            throw error
        }
    }

    func deleteSnapshot(
        account: CloudProviderAccount,
        regionId: String,
        snapshotId: String,
        currentStatus: String?
    ) async throws {
        guard account.enabled else {
            throw CloudProviderError.providerFailure("Cloud account is disabled.")
        }
        if let currentStatus, !Self.canDeleteSnapshot(providerId: account.providerId, status: currentStatus) {
            throw CloudProviderError.providerFailure("Only completed snapshots can be deleted safely. Current status: \(currentStatus).")
        }
        try registry.require(.snapshotActions, providerId: account.providerId)
        let capturedAt = now()
        let credential = try credential(for: account)
        do {
            try await registry.adapter(for: account.providerId).deleteSnapshot(
                credential: credential,
                regionId: regionId,
                snapshotId: snapshotId
            )
            try repository.deleteCloudSnapshot(accountId: account.id, regionId: regionId, snapshotId: snapshotId)
            try saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_snapshot",
                targetId: snapshotId,
                action: "delete_snapshot",
                beforeSnapshot: "snapshot=\(snapshotId), status=\(currentStatus ?? "unknown")",
                afterSnapshot: nil,
                status: "success",
                message: "region=\(regionId)",
                createdAt: capturedAt
            )
        } catch {
            try? saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_snapshot",
                targetId: snapshotId,
                action: "delete_snapshot",
                beforeSnapshot: "snapshot=\(snapshotId), status=\(currentStatus ?? "unknown")",
                afterSnapshot: nil,
                status: "failed",
                message: error.localizedDescription,
                createdAt: capturedAt
            )
            throw error
        }
    }

    func attachDisk(
        account: CloudProviderAccount,
        regionId: String,
        diskId: String,
        instanceId: String,
        currentStatus: String?
    ) async throws {
        guard account.enabled else {
            throw CloudProviderError.providerFailure("Cloud account is disabled.")
        }
        let trimmedInstanceId = instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstanceId.isEmpty else {
            throw CloudProviderError.providerFailure("Target instance id is required.")
        }
        if let currentStatus, !Self.canAttachDisk(providerId: account.providerId, status: currentStatus) {
            throw CloudProviderError.providerFailure("Only detached or available disks can be attached safely. Current status: \(currentStatus).")
        }
        try registry.require(.diskAttachmentActions, providerId: account.providerId)
        let capturedAt = now()
        let credential = try credential(for: account)
        do {
            try await registry.adapter(for: account.providerId).attachDisk(
                credential: credential,
                regionId: regionId,
                diskId: diskId,
                instanceId: trimmedInstanceId
            )
            try persistDiskTransition(
                account: account,
                regionId: regionId,
                diskId: diskId,
                instanceId: trimmedInstanceId,
                status: "ATTACHING",
                capturedAt: capturedAt
            )
            try saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_disk",
                targetId: diskId,
                action: "attach_disk",
                beforeSnapshot: "disk=\(diskId), status=\(currentStatus ?? "unknown")",
                afterSnapshot: "instance=\(trimmedInstanceId), status=ATTACHING",
                status: "success",
                message: "region=\(regionId)",
                createdAt: capturedAt
            )
        } catch {
            try? saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_disk",
                targetId: diskId,
                action: "attach_disk",
                beforeSnapshot: "disk=\(diskId), status=\(currentStatus ?? "unknown")",
                afterSnapshot: "instance=\(trimmedInstanceId)",
                status: "failed",
                message: error.localizedDescription,
                createdAt: capturedAt
            )
            throw error
        }
    }

    func detachDisk(
        account: CloudProviderAccount,
        regionId: String,
        diskId: String,
        currentInstanceId: String?,
        currentStatus: String?
    ) async throws {
        guard account.enabled else {
            throw CloudProviderError.providerFailure("Cloud account is disabled.")
        }
        if let currentStatus, !Self.canDetachDisk(providerId: account.providerId, status: currentStatus) {
            throw CloudProviderError.providerFailure("Only attached or in-use disks can be detached safely. Current status: \(currentStatus).")
        }
        try registry.require(.diskAttachmentActions, providerId: account.providerId)
        let capturedAt = now()
        let credential = try credential(for: account)
        do {
            try await registry.adapter(for: account.providerId).detachDisk(
                credential: credential,
                regionId: regionId,
                diskId: diskId
            )
            try persistDiskTransition(
                account: account,
                regionId: regionId,
                diskId: diskId,
                instanceId: currentInstanceId,
                status: "DETACHING",
                capturedAt: capturedAt
            )
            try saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_disk",
                targetId: diskId,
                action: "detach_disk",
                beforeSnapshot: "disk=\(diskId), instance=\(currentInstanceId ?? "unknown"), status=\(currentStatus ?? "unknown")",
                afterSnapshot: "status=DETACHING",
                status: "success",
                message: "region=\(regionId)",
                createdAt: capturedAt
            )
        } catch {
            try? saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_disk",
                targetId: diskId,
                action: "detach_disk",
                beforeSnapshot: "disk=\(diskId), instance=\(currentInstanceId ?? "unknown"), status=\(currentStatus ?? "unknown")",
                afterSnapshot: nil,
                status: "failed",
                message: error.localizedDescription,
                createdAt: capturedAt
            )
            throw error
        }
    }

    func startInstance(
        account: CloudProviderAccount,
        regionId: String,
        instanceId: String,
        currentStatus: String?
    ) async throws {
        try await performInstancePowerAction(
            account: account,
            regionId: regionId,
            instanceId: instanceId,
            currentStatus: currentStatus,
            adapterAction: { adapter, credential in
                try await adapter.startInstance(credential: credential, regionId: regionId, instanceId: instanceId)
            },
            action: "start_instance",
            powerAction: .start,
            transitionStatus: "STARTING"
        )
    }

    func stopInstance(
        account: CloudProviderAccount,
        regionId: String,
        instanceId: String,
        currentStatus: String?
    ) async throws {
        try await performInstancePowerAction(
            account: account,
            regionId: regionId,
            instanceId: instanceId,
            currentStatus: currentStatus,
            adapterAction: { adapter, credential in
                try await adapter.stopInstance(credential: credential, regionId: regionId, instanceId: instanceId)
            },
            action: "stop_instance",
            powerAction: .stop,
            transitionStatus: "STOPPING"
        )
    }

    func rebootInstance(
        account: CloudProviderAccount,
        regionId: String,
        instanceId: String,
        currentStatus: String?
    ) async throws {
        try await performInstancePowerAction(
            account: account,
            regionId: regionId,
            instanceId: instanceId,
            currentStatus: currentStatus,
            adapterAction: { adapter, credential in
                try await adapter.rebootInstance(credential: credential, regionId: regionId, instanceId: instanceId)
            },
            action: "reboot_instance",
            powerAction: .reboot,
            transitionStatus: "REBOOTING"
        )
    }

    func syncBillingStates(account: CloudProviderAccount, regionId: String) async throws -> [CloudBillingState] {
        guard account.enabled else {
            throw CloudProviderError.providerFailure("Cloud account is disabled.")
        }

        try registry.require(.cloudBilling, providerId: account.providerId)
        let syncedAt = now()
        let credential = try credential(for: account)
        let states = try await registry.adapter(for: account.providerId).fetchBillingStates(
            credential: credential,
            accountId: account.id,
            regionId: regionId,
            capturedAt: syncedAt
        )

        for state in states {
            try repository.upsertCloudBillingState(state)
        }
        return states
    }

    func loadUnifiedCloudResources(
        accountId: UUID? = nil,
        regionId: String? = nil,
        query: CloudResourceSearchQuery = CloudResourceSearchQuery()
    ) throws -> [CloudUnifiedResource] {
        let resources = CloudResourceSearchService.unifiedResources(
            instances: try repository.fetchCloudInstanceLinks(accountId: accountId),
            disks: try repository.fetchCloudDisks(accountId: accountId, regionId: regionId),
            snapshots: try repository.fetchCloudSnapshots(accountId: accountId, regionId: regionId),
            billingStates: try repository.fetchCloudBillingStates(accountId: accountId)
        )
        let scoped = regionId.map { region in
            resources.filter { resource in
                resource.regionId == nil || resource.regionId == region
            }
        } ?? resources
        return CloudResourceSearchService.search(scoped, query: query)
    }

    func linkInstance(_ link: CloudInstanceLink, to server: ServerProfile) throws -> CloudInstanceLink {
        var linked = link
        linked.serverId = server.id
        linked.lastSyncedAt = link.lastSyncedAt ?? now()
        try repository.upsertCloudInstanceLink(linked)
        return linked
    }

    func unlinkInstanceFromServer(server: ServerProfile) throws {
        try repository.unlinkCloudInstanceFromServer(serverId: server.id)
    }

    func createServerFromInstance(
        _ link: CloudInstanceLink,
        username: String,
        authType: SSHAuthType,
        credential: CredentialInput
    ) throws -> ServerProfile {
        let host = link.publicIp ?? link.privateIp
        guard let host, !host.isEmpty else {
            throw CloudProviderError.providerFailure("Cloud instance does not expose an IP address.")
        }

        let profile = try serverManagementService.createServer(
            name: link.displayName ?? link.instanceId,
            host: host,
            port: 22,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            groupName: link.providerId.displayName,
            authType: authType,
            credential: credential
        )
        _ = try linkInstance(link, to: profile)
        return profile
    }

    private func saveCloudChangeLog(
        providerId: CloudProviderID,
        targetType: String,
        targetId: String?,
        action: String,
        beforeSnapshot: String?,
        afterSnapshot: String?,
        status: String,
        message: String?,
        createdAt: Date
    ) throws {
        try repository.saveRemoteChangeLog(RemoteChangeLogEntry(
            id: UUID(),
            serverId: nil,
            providerId: providerId,
            targetType: targetType,
            targetId: targetId,
            action: action,
            beforeSnapshot: beforeSnapshot,
            afterSnapshot: afterSnapshot,
            status: status,
            message: message,
            createdAt: createdAt
        ))
    }

    private func persistDiskTransition(
        account: CloudProviderAccount,
        regionId: String,
        diskId: String,
        instanceId: String?,
        status: String,
        capturedAt: Date
    ) throws {
        var disk = try repository.fetchCloudDisks(accountId: account.id, regionId: regionId)
            .first { $0.diskId == diskId } ?? CloudDisk(
                id: UUID(),
                accountId: account.id,
                providerId: account.providerId,
                regionId: regionId,
                diskId: diskId,
                instanceId: instanceId,
                name: nil,
                diskType: nil,
                sizeGB: nil,
                status: status,
                billingType: nil,
                expiredTime: nil,
                rawJSON: nil,
                lastSyncedAt: capturedAt
            )
        disk.instanceId = instanceId
        disk.status = status
        disk.lastSyncedAt = capturedAt
        try repository.upsertCloudDisk(disk)
    }

    private func performInstancePowerAction(
        account: CloudProviderAccount,
        regionId: String,
        instanceId: String,
        currentStatus: String?,
        adapterAction: (any CloudProviderAdapter, CloudProviderCredential) async throws -> Void,
        action: String,
        powerAction: InstancePowerAction,
        transitionStatus: String
    ) async throws {
        guard account.enabled else {
            throw CloudProviderError.providerFailure("Cloud account is disabled.")
        }
        if let currentStatus, !Self.canPerformInstancePowerAction(
            providerId: account.providerId,
            action: powerAction,
            status: currentStatus
        ) {
            throw CloudProviderError.providerFailure("Instance status \(currentStatus) is not valid for \(action).")
        }
        try registry.require(.powerActions, providerId: account.providerId)
        let capturedAt = now()
        let credential = try credential(for: account)
        do {
            try await adapterAction(registry.adapter(for: account.providerId), credential)
            try persistInstanceTransition(
                account: account,
                regionId: regionId,
                instanceId: instanceId,
                status: transitionStatus,
                capturedAt: capturedAt
            )
            try saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_instance",
                targetId: instanceId,
                action: action,
                beforeSnapshot: "instance=\(instanceId), status=\(currentStatus ?? "unknown")",
                afterSnapshot: "status=\(transitionStatus)",
                status: "success",
                message: "region=\(regionId)",
                createdAt: capturedAt
            )
        } catch {
            try? saveCloudChangeLog(
                providerId: account.providerId,
                targetType: "cloud_instance",
                targetId: instanceId,
                action: action,
                beforeSnapshot: "instance=\(instanceId), status=\(currentStatus ?? "unknown")",
                afterSnapshot: nil,
                status: "failed",
                message: error.localizedDescription,
                createdAt: capturedAt
            )
            throw error
        }
    }

    private enum InstancePowerAction {
        case start
        case stop
        case reboot
    }

    private static func canPerformInstancePowerAction(
        providerId: CloudProviderID,
        action: InstancePowerAction,
        status: String
    ) -> Bool {
        let cloudAction: CloudInstancePowerAction
        switch action {
        case .start:
            cloudAction = .start
        case .stop:
            cloudAction = .stop
        case .reboot:
            cloudAction = .reboot
        }
        return CloudResourceActionPolicy.canPerformPowerAction(
            providerId: providerId,
            action: cloudAction,
            status: status
        )
    }

    private func persistInstanceTransition(
        account: CloudProviderAccount,
        regionId: String,
        instanceId: String,
        status: String,
        capturedAt: Date
    ) throws {
        var link = try repository.fetchCloudInstanceLink(accountId: account.id, regionId: regionId, instanceId: instanceId)
        link.accountId = account.id
        link.providerId = account.providerId
        link.regionId = regionId
        link.instanceId = instanceId
        link.status = status
        link.lastSyncedAt = capturedAt
        try repository.upsertCloudInstanceLink(link)
    }

    private func credential(for account: CloudProviderAccount) throws -> CloudProviderCredential {
        guard let credential = try keychain.readCloudCredential(keychainRef: account.keychainRef) else {
            throw CloudProviderError.authenticationFailed("Cloud credential is missing from Keychain.")
        }
        return credential
    }

    private static func canDeleteSnapshot(providerId: CloudProviderID, status: String) -> Bool {
        CloudResourceActionPolicy.canDeleteSnapshot(providerId: providerId, status: status)
    }

    private static func canAttachDisk(providerId: CloudProviderID, status: String) -> Bool {
        CloudResourceActionPolicy.canAttachDisk(providerId: providerId, status: status)
    }

    private static func canDetachDisk(providerId: CloudProviderID, status: String) -> Bool {
        CloudResourceActionPolicy.canDetachDisk(providerId: providerId, status: status)
    }
}

enum DeploymentCommandBuilderError: LocalizedError, Equatable {
    case invalidRepositoryURL
    case invalidBranch
    case invalidCommit
    case deployPathOutsideAllowedRoots(String)
    case invalidCommand(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL:
            "Repository URL must be an HTTPS, SSH, or git@ GitLab-style URL."
        case .invalidBranch:
            "Branch can only contain letters, numbers, slash, dot, underscore, and dash."
        case .invalidCommit:
            "Commit must be a 7 to 40 character hexadecimal Git commit."
        case let .deployPathOutsideAllowedRoots(path):
            "Deploy path \(path) is outside the allowed deployment roots."
        case let .invalidCommand(label):
            "\(label) command must be a single non-empty line without null bytes."
        }
    }
}

struct DeploymentPathPolicy: Equatable, Sendable {
    var allowedRoots: [String]

    static let defaultPolicy = DeploymentPathPolicy(allowedRoots: [
        "/srv",
        "/var/www",
        "/opt",
        "/home",
    ])

    func allowedRoot(for path: String) -> String? {
        let normalized = Self.normalized(path)
        return allowedRoots
            .map(Self.normalized)
            .first { root in
                normalized == root || normalized.hasPrefix("\(root)/")
            }
    }

    private static func normalized(_ path: String) -> String {
        var result = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasSuffix("/") && result.count > 1 {
            result.removeLast()
        }
        return result
    }
}

enum DeploymentCommandBuilder {
    static func buildPlan(
        for project: DeploymentProject,
        pathPolicy: DeploymentPathPolicy = .defaultPolicy
    ) throws -> DeploymentCommandPlan {
        try validate(project: project, pathPolicy: pathPolicy)
        let deployPath = project.deployPath.trimmed
        let branch = project.branch.trimmed
        let repositoryURL = project.repositoryURL.trimmed
        let quotedPath = shellQuote(deployPath)
        let quotedParent = shellQuote(parentDirectory(for: deployPath))
        let quotedRepository = shellQuote(repositoryURL)
        let quotedBranch = shellQuote(branch)

        var steps = [
            DeploymentCommandStep(
                name: "prepare",
                command: "mkdir -p \(quotedParent)",
                isDestructive: false,
                description: "Ensure the parent deployment directory exists."
            ),
            DeploymentCommandStep(
                name: "git_check",
                command: "command -v git",
                isDestructive: false,
                description: "Verify that git is installed on the remote server."
            ),
            DeploymentCommandStep(
                name: "current_commit",
                command: "if [ -d \(quotedPath)/.git ]; then cd \(quotedPath) && git rev-parse HEAD; else printf '\\n'; fi",
                isDestructive: false,
                description: "Capture the currently deployed commit for rollback."
            ),
            DeploymentCommandStep(
                name: "clone_or_fetch",
                command: "if [ -d \(quotedPath)/.git ]; then cd \(quotedPath) && git fetch --prune origin \(quotedBranch); else git clone --branch \(quotedBranch) --single-branch \(quotedRepository) \(quotedPath); fi",
                isDestructive: false,
                description: "Clone the repository or fetch the selected branch."
            ),
            DeploymentCommandStep(
                name: "checkout",
                command: "cd \(quotedPath) && git checkout \(quotedBranch) && git reset --hard \(shellQuote("origin/\(branch)"))",
                isDestructive: true,
                description: "Reset the deployment working tree to the selected branch."
            ),
            DeploymentCommandStep(
                name: "target_commit",
                command: "cd \(quotedPath) && git rev-parse HEAD",
                isDestructive: false,
                description: "Record the deployed target commit."
            ),
        ]

        if let buildCommand = project.buildCommand?.trimmed.nilIfEmpty {
            steps.append(DeploymentCommandStep(
                name: "build",
                command: "cd \(quotedPath) && \(buildCommand)",
                isDestructive: false,
                description: "Run the configured build command."
            ))
        }
        if let restartCommand = project.restartCommand?.trimmed.nilIfEmpty {
            steps.append(DeploymentCommandStep(
                name: "restart",
                command: "cd \(quotedPath) && \(restartCommand)",
                isDestructive: true,
                description: "Run the configured restart command."
            ))
        }
        if let healthCheckCommand = project.healthCheckCommand?.trimmed.nilIfEmpty {
            steps.append(DeploymentCommandStep(
                name: "health_check",
                command: "cd \(quotedPath) && \(healthCheckCommand)",
                isDestructive: false,
                description: "Run the configured health check command."
            ))
        }

        guard let allowedRoot = pathPolicy.allowedRoot(for: deployPath) else {
            throw DeploymentCommandBuilderError.deployPathOutsideAllowedRoots(deployPath)
        }
        return DeploymentCommandPlan(
            project: project,
            allowedRoot: allowedRoot,
            steps: steps
        )
    }

    static func buildRollbackPlan(
        for project: DeploymentProject,
        targetCommit: String,
        pathPolicy: DeploymentPathPolicy = .defaultPolicy
    ) throws -> DeploymentCommandPlan {
        try validate(project: project, pathPolicy: pathPolicy)
        guard isValidCommit(targetCommit.trimmed) else { throw DeploymentCommandBuilderError.invalidCommit }

        let deployPath = project.deployPath.trimmed
        let quotedPath = shellQuote(deployPath)
        let quotedCommit = shellQuote(targetCommit.trimmed)
        var steps = [
            DeploymentCommandStep(
                name: "git_check",
                command: "command -v git",
                isDestructive: false,
                description: "Verify that git is installed on the remote server."
            ),
            DeploymentCommandStep(
                name: "current_commit",
                command: "cd \(quotedPath) && git rev-parse HEAD",
                isDestructive: false,
                description: "Capture the currently deployed commit before rollback."
            ),
            DeploymentCommandStep(
                name: "checkout",
                command: "cd \(quotedPath) && git checkout \(quotedCommit) && git reset --hard \(quotedCommit)",
                isDestructive: true,
                description: "Reset the deployment working tree to the previous commit."
            ),
            DeploymentCommandStep(
                name: "target_commit",
                command: "cd \(quotedPath) && git rev-parse HEAD",
                isDestructive: false,
                description: "Record the rollback target commit."
            ),
        ]

        if let buildCommand = project.buildCommand?.trimmed.nilIfEmpty {
            steps.append(DeploymentCommandStep(
                name: "build",
                command: "cd \(quotedPath) && \(buildCommand)",
                isDestructive: false,
                description: "Run the configured build command after rollback."
            ))
        }
        if let restartCommand = project.restartCommand?.trimmed.nilIfEmpty {
            steps.append(DeploymentCommandStep(
                name: "restart",
                command: "cd \(quotedPath) && \(restartCommand)",
                isDestructive: true,
                description: "Run the configured restart command after rollback."
            ))
        }
        if let healthCheckCommand = project.healthCheckCommand?.trimmed.nilIfEmpty {
            steps.append(DeploymentCommandStep(
                name: "health_check",
                command: "cd \(quotedPath) && \(healthCheckCommand)",
                isDestructive: false,
                description: "Run the configured health check command after rollback."
            ))
        }

        guard let allowedRoot = pathPolicy.allowedRoot(for: deployPath) else {
            throw DeploymentCommandBuilderError.deployPathOutsideAllowedRoots(deployPath)
        }
        return DeploymentCommandPlan(project: project, allowedRoot: allowedRoot, steps: steps)
    }

    static func validate(
        project: DeploymentProject,
        pathPolicy: DeploymentPathPolicy = .defaultPolicy
    ) throws {
        guard isValidRepositoryURL(project.repositoryURL.trimmed) else {
            throw DeploymentCommandBuilderError.invalidRepositoryURL
        }
        guard isValidBranch(project.branch.trimmed) else {
            throw DeploymentCommandBuilderError.invalidBranch
        }
        guard pathPolicy.allowedRoot(for: project.deployPath) != nil else {
            throw DeploymentCommandBuilderError.deployPathOutsideAllowedRoots(project.deployPath.trimmed)
        }
        try validateCommand(project.buildCommand, label: "Build")
        try validateCommand(project.restartCommand, label: "Restart")
        try validateCommand(project.healthCheckCommand, label: "Health check")
    }

    private static func isValidRepositoryURL(_ url: String) -> Bool {
        guard !url.isEmpty, !url.contains("\n"), !url.contains("\0") else { return false }
        return url.hasPrefix("https://") ||
            url.hasPrefix("ssh://") ||
            url.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+:.+\.git$"#, options: .regularExpression) != nil
    }

    private static func isValidBranch(_ branch: String) -> Bool {
        guard !branch.isEmpty, branch != ".", branch != ".." else { return false }
        guard branch.range(of: #"^[A-Za-z0-9][A-Za-z0-9._/-]*$"#, options: .regularExpression) != nil else {
            return false
        }
        return !branch.contains("..") && !branch.hasSuffix("/") && !branch.contains("//")
    }

    private static func isValidCommit(_ commit: String) -> Bool {
        commit.range(of: #"^[A-Fa-f0-9]{7,40}$"#, options: .regularExpression) != nil
    }

    private static func validateCommand(_ command: String?, label: String) throws {
        guard let command else { return }
        let trimmed = command.trimmed
        guard !trimmed.isEmpty,
              !trimmed.contains("\n"),
              !trimmed.contains("\r"),
              !trimmed.contains("\0")
        else {
            throw DeploymentCommandBuilderError.invalidCommand(label)
        }
    }

    private static func parentDirectory(for path: String) -> String {
        let trimmed = path.trimmed
        guard let slashIndex = trimmed.lastIndex(of: "/"), slashIndex != trimmed.startIndex else {
            return "."
        }
        return String(trimmed[..<slashIndex])
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

enum DeploymentLogRedactor {
    private static let redacted = "<redacted>"
    private static let patterns: [(String, String)] = [
        (#"(?i)\b(authorization)\s*[:=]\s*(bearer\s+)?[A-Za-z0-9._~+/=-]+"#, "$1=<redacted>"),
        (#"(?i)\b(token|secret|password|passwd|api[_-]?key|access[_-]?key|private[_-]?key)\s*[:=]\s*['"]?[^'"\s]+"#, "$1=<redacted>"),
        (#"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]+"#, "$1 <redacted>"),
        (#"(https?://)[^/\s:@]+:[^/\s@]+@"#, "$1<redacted>@"),
        (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, redacted),
    ]

    static func redact(_ message: String) -> String {
        patterns.reduce(message) { partial, pattern in
            partial.replacingOccurrences(
                of: pattern.0,
                with: pattern.1,
                options: [.regularExpression]
            )
        }
    }
}

final class DeploymentRunner: @unchecked Sendable {
    private let repository: ServerRepository
    private let pathPolicy: DeploymentPathPolicy
    private let now: @Sendable () -> Date

    init(
        repository: ServerRepository,
        pathPolicy: DeploymentPathPolicy = .defaultPolicy,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.pathPolicy = pathPolicy
        self.now = now
    }

    func run(
        project: DeploymentProject,
        profile: ServerProfile,
        sshClient: SSHClient,
        triggerType: DeploymentTriggerType = .manual,
        requestedRef: String? = nil
    ) async throws -> DeploymentRun {
        let plan = try DeploymentCommandBuilder.buildPlan(for: project, pathPolicy: pathPolicy)
        return try await runPlan(
            plan,
            project: project,
            profile: profile,
            sshClient: sshClient,
            triggerType: triggerType,
            requestedRef: requestedRef ?? project.branch,
            initialTargetCommit: nil,
            startMessage: "Starting deployment for \(project.name).",
            successSummary: "Deployment completed."
        )
    }

    func rollback(
        project: DeploymentProject,
        targetCommit: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> DeploymentRun {
        let plan = try DeploymentCommandBuilder.buildRollbackPlan(for: project, targetCommit: targetCommit, pathPolicy: pathPolicy)
        return try await runPlan(
            plan,
            project: project,
            profile: profile,
            sshClient: sshClient,
            triggerType: .rollback,
            requestedRef: targetCommit,
            initialTargetCommit: targetCommit,
            startMessage: "Starting rollback for \(project.name) to \(targetCommit).",
            successSummary: "Rollback completed."
        )
    }

    private func runPlan(
        _ plan: DeploymentCommandPlan,
        project: DeploymentProject,
        profile: ServerProfile,
        sshClient: SSHClient,
        triggerType: DeploymentTriggerType,
        requestedRef: String?,
        initialTargetCommit: String?,
        startMessage: String,
        successSummary: String
    ) async throws -> DeploymentRun {
        var run = DeploymentRun(
            id: UUID(),
            projectId: project.id,
            triggerType: triggerType,
            requestedRef: requestedRef,
            previousCommit: nil,
            targetCommit: initialTargetCommit,
            status: .running,
            startedAt: now(),
            finishedAt: nil,
            summary: nil
        )
        try repository.saveDeploymentRun(run)
        try saveLog(runId: run.id, stepName: "plan", stream: .system, message: startMessage)

        for step in plan.steps {
            if Task.isCancelled {
                return try finish(run, status: .cancelled, summary: "Deployment cancelled before \(step.name).")
            }

            try saveLog(runId: run.id, stepName: step.name, stream: .system, message: step.description)
            do {
                let result = try await sshClient.execute(step.command, profile: profile)
                try saveCommandOutput(result, runId: run.id, stepName: step.name)

                if step.name == "current_commit" {
                    run.previousCommit = result.stdout.firstLine?.trimmed.nilIfEmpty
                    try repository.saveDeploymentRun(run)
                } else if step.name == "target_commit" {
                    run.targetCommit = result.stdout.firstLine?.trimmed.nilIfEmpty
                    try repository.saveDeploymentRun(run)
                }

                guard result.exitCode == 0 else {
                    return try finish(
                        run,
                        status: .failed,
                        summary: "\(step.name) failed with exit code \(result.exitCode)."
                    )
                }
            } catch {
                let status: DeploymentRunStatus = Task.isCancelled || (error as? SSHClientError) == .cancelled ? .cancelled : .failed
                try saveLog(runId: run.id, stepName: step.name, stream: .stderr, message: error.localizedDescription)
                return try finish(run, status: status, summary: error.localizedDescription)
            }
        }

        return try finish(run, status: .succeeded, summary: successSummary)
    }

    private func saveCommandOutput(
        _ result: CommandResult,
        runId: UUID,
        stepName: String
    ) throws {
        if let stdout = result.stdout.trimmed.nilIfEmpty {
            try saveLog(runId: runId, stepName: stepName, stream: .stdout, message: stdout)
        }
        if let stderr = result.stderr.trimmed.nilIfEmpty {
            try saveLog(runId: runId, stepName: stepName, stream: .stderr, message: stderr)
        }
        try saveLog(runId: runId, stepName: stepName, stream: .system, message: "Exit \(result.exitCode) in \(String(format: "%.2f", result.duration))s.")
    }

    private func finish(
        _ run: DeploymentRun,
        status: DeploymentRunStatus,
        summary: String
    ) throws -> DeploymentRun {
        var finished = run
        finished.status = status
        finished.finishedAt = now()
        finished.summary = summary
        try repository.saveDeploymentRun(finished)
        try saveLog(runId: finished.id, stepName: "finish", stream: .system, message: summary)
        return finished
    }

    private func saveLog(
        runId: UUID,
        stepName: String,
        stream: DeploymentLogStream,
        message: String
    ) throws {
        try repository.saveDeploymentLog(DeploymentLogEntry(
            id: UUID(),
            runId: runId,
            stepName: stepName,
            stream: stream,
            message: DeploymentLogRedactor.redact(message),
            createdAt: now()
        ))
    }
}

enum DeploymentWebhookError: LocalizedError, Equatable {
    case invalidPayload
    case unsupportedEvent
    case missingToken
    case invalidToken
    case projectNotFound
    case serverNotFound
    case secretMissing

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            "Webhook payload is not a valid GitLab push event."
        case .unsupportedEvent:
            "Only GitLab push events are supported."
        case .missingToken:
            "GitLab webhook token is missing."
        case .invalidToken:
            "GitLab webhook token is invalid."
        case .projectNotFound:
            "No enabled deployment project matches this webhook."
        case .serverNotFound:
            "The deployment project's server no longer exists."
        case .secretMissing:
            "Webhook secret is missing."
        }
    }
}

struct DeploymentWebhookEvent: Equatable, Sendable {
    var branch: String
    var repositoryCandidates: Set<String>
    var requestedRef: String
}

final class DeploymentWebhookService: @unchecked Sendable {
    private let repository: ServerRepository
    private let keychain: KeychainService
    private let runner: DeploymentRunner

    init(repository: ServerRepository, keychain: KeychainService, runner: DeploymentRunner) {
        self.repository = repository
        self.keychain = keychain
        self.runner = runner
    }

    func handleGitLabPush(
        headers: [String: String],
        body: Data,
        sshClient: SSHClient
    ) async throws -> DeploymentRun {
        guard header("X-Gitlab-Event", in: headers) == nil || header("X-Gitlab-Event", in: headers) == "Push Hook" else {
            throw DeploymentWebhookError.unsupportedEvent
        }
        guard let token = header("X-Gitlab-Token", in: headers), !token.isEmpty else {
            throw DeploymentWebhookError.missingToken
        }

        let event = try Self.parseGitLabPush(body)
        let project = try matchingProject(for: event)
        guard let secretRef = project.webhookSecretRef,
              let expectedToken = try keychain.readWebhookSecret(keychainRef: secretRef)
        else {
            throw DeploymentWebhookError.secretMissing
        }
        guard Self.constantTimeEquals(token, expectedToken) else {
            throw DeploymentWebhookError.invalidToken
        }

        guard let profile = try repository.fetchServers().first(where: { $0.id == project.serverId }) else {
            throw DeploymentWebhookError.serverNotFound
        }
        try saveWebhookOperationLog(
            project: project,
            status: "started",
            message: "Webhook push \(event.requestedRef) accepted for \(project.name)."
        )
        let run = try await runner.run(
            project: project,
            profile: profile,
            sshClient: sshClient,
            triggerType: .webhook,
            requestedRef: event.requestedRef
        )
        try saveWebhookOperationLog(
            project: project,
            status: run.status.rawValue,
            message: "Webhook deployment run \(run.id.uuidString) finished with \(run.status.rawValue)."
        )
        return run
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = [UInt8](lhs.utf8)
        let right = [UInt8](rhs.utf8)
        let maxCount = max(left.count, right.count)
        var diff = UInt8(left.count ^ right.count)
        for index in 0..<maxCount {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            diff |= leftByte ^ rightByte
        }
        return diff == 0
    }

    static func parseGitLabPush(_ body: Data) throws -> DeploymentWebhookEvent {
        guard
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
            json["object_kind"] as? String == "push",
            let ref = json["ref"] as? String,
            ref.hasPrefix("refs/heads/")
        else {
            throw DeploymentWebhookError.invalidPayload
        }

        let branch = String(ref.dropFirst("refs/heads/".count))
        var candidates = Set<String>()
        collectRepositoryCandidates(from: json["project"], into: &candidates)
        collectRepositoryCandidates(from: json["repository"], into: &candidates)
        guard !candidates.isEmpty else {
            throw DeploymentWebhookError.invalidPayload
        }

        return DeploymentWebhookEvent(branch: branch, repositoryCandidates: candidates, requestedRef: ref)
    }

    private func matchingProject(for event: DeploymentWebhookEvent) throws -> DeploymentProject {
        let projects = try repository.fetchDeploymentProjects().filter {
            $0.webhookEnabled && $0.branch == event.branch
        }
        guard let project = projects.first(where: { project in
            event.repositoryCandidates.contains(Self.normalizedRepositoryURL(project.repositoryURL))
        }) else {
            throw DeploymentWebhookError.projectNotFound
        }
        return project
    }

    private func saveWebhookOperationLog(project: DeploymentProject, status: String, message: String) throws {
        try repository.saveOperationLog(OperationLogEntry(
            id: UUID(),
            scope: "deployment",
            action: "webhook_trigger",
            targetId: project.id.uuidString,
            status: status,
            message: message,
            createdAt: Date()
        ))
    }

    private func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func collectRepositoryCandidates(from object: Any?, into candidates: inout Set<String>) {
        guard let dictionary = object as? [String: Any] else { return }
        for key in ["git_ssh_url", "git_http_url", "ssh_url", "http_url", "web_url", "url"] {
            if let value = dictionary[key] as? String {
                candidates.insert(normalizedRepositoryURL(value))
            }
        }
        if let path = dictionary["path_with_namespace"] as? String {
            candidates.insert(normalizedRepositoryURL("gitlab.com/\(path)"))
        }
    }

    private static func normalizedRepositoryURL(_ rawURL: String) -> String {
        var value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("git@") {
            value.removeFirst("git@".count)
            value = value.replacingOccurrences(of: ":", with: "/", options: [], range: value.startIndex..<value.endIndex)
        }
        for prefix in ["https://", "http://", "ssh://"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        if value.hasSuffix(".git") {
            value.removeLast(".git".count)
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

struct DeploymentWebhookHTTPRequest: Equatable, Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

enum DeploymentWebhookHTTPError: LocalizedError, Equatable {
    case malformedRequest
    case bodyTooLarge
    case unsupportedMethod
    case unsupportedPath

    var errorDescription: String? {
        switch self {
        case .malformedRequest:
            "Webhook HTTP request is malformed."
        case .bodyTooLarge:
            "Webhook HTTP request body is too large."
        case .unsupportedMethod:
            "Webhook listener only accepts POST requests."
        case .unsupportedPath:
            "Webhook listener only accepts /webhooks/gitlab."
        }
    }
}

final class DeploymentWebhookHTTPServer: @unchecked Sendable {
    private let webhookService: DeploymentWebhookService
    private let sshClient: SSHClient
    private let queue = DispatchQueue(label: "me.hhc.HHCServerManager.webhook")
    private var listener: NWListener?

    init(webhookService: DeploymentWebhookService, sshClient: SSHClient) {
        self.webhookService = webhookService
        self.sshClient = sshClient
    }

    var port: UInt16? {
        listener?.port?.rawValue
    }

    func start(port: UInt16 = 0) throws {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw DeploymentWebhookHTTPError.malformedRequest
        }
        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    static func parseRequest(_ data: Data, maxBodyBytes: Int = 1_048_576) throws -> DeploymentWebhookHTTPRequest {
        guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw DeploymentWebhookHTTPError.malformedRequest
        }
        let headerData = data[..<separatorRange.lowerBound]
        let body = Data(data[separatorRange.upperBound...])
        guard body.count <= maxBodyBytes,
              let headerText = String(data: headerData, encoding: .utf8)
        else {
            throw body.count > maxBodyBytes ? DeploymentWebhookHTTPError.bodyTooLarge : DeploymentWebhookHTTPError.malformedRequest
        }

        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw DeploymentWebhookHTTPError.malformedRequest
        }
        lines.removeFirst()
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw DeploymentWebhookHTTPError.malformedRequest
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        return DeploymentWebhookHTTPRequest(
            method: requestParts[0],
            path: requestParts[1],
            headers: headers,
            body: body
        )
    }

    static func response(statusCode: Int, reason: String, body: String) -> Data {
        let bodyData = Data(body.utf8)
        return Data([
            "HTTP/1.1 \(statusCode) \(reason)",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            body,
        ].joined(separator: "\r\n").utf8)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_100_000) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                let responseData = Self.response(statusCode: 500, reason: "Internal Server Error", body: error.localizedDescription)
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            guard let data else {
                let responseData = Self.response(statusCode: 400, reason: "Bad Request", body: "Missing request data.")
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            Task {
                let responseData = await self.handleRequestData(data)
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func handleRequestData(_ data: Data) async -> Data {
        do {
            let request = try Self.parseRequest(data)
            guard request.method == "POST" else {
                throw DeploymentWebhookHTTPError.unsupportedMethod
            }
            guard request.path == "/webhooks/gitlab" else {
                throw DeploymentWebhookHTTPError.unsupportedPath
            }

            _ = try await webhookService.handleGitLabPush(
                headers: request.headers,
                body: request.body,
                sshClient: sshClient
            )
            return Self.response(statusCode: 202, reason: "Accepted", body: "Webhook accepted.")
        } catch let error as DeploymentWebhookHTTPError {
            return Self.response(statusCode: 400, reason: "Bad Request", body: error.localizedDescription)
        } catch {
            return Self.response(statusCode: 401, reason: "Unauthorized", body: error.localizedDescription)
        }
    }
}

enum RegistryKind: String, Equatable, Sendable {
    case verdaccio
}

enum PubRegistryCandidateKind: String, Equatable, Sendable {
    case hostedRepository
    case selfHostedServer
    case privateGitDependency
}

enum PubRegistryCandidateVerdict: String, Equatable, Sendable {
    case supportedIntegration
    case researchOnly
    case notARegistry
}

struct PubRegistryCandidateEvaluation: Equatable, Sendable {
    var kind: PubRegistryCandidateKind
    var name: String
    var verdict: PubRegistryCandidateVerdict
    var reasons: [String]
}

struct PubRegistryResearchReport: Equatable, Sendable {
    var candidates: [PubRegistryCandidateEvaluation]
    var implementationDecision: String
    var shouldImplementSelfHostedInstaller: Bool
    var supportedProductPath: String
    var evaluatedAt: Date
}

enum PubRegistryResearchHarness {
    static func currentReport(evaluatedAt: Date = Date()) -> PubRegistryResearchReport {
        PubRegistryResearchReport(
            candidates: [
                PubRegistryCandidateEvaluation(
                    kind: .hostedRepository,
                    name: "Dart Hosted Pub Repository v2",
                    verdict: .supportedIntegration,
                    reasons: [
                        "Dart supports custom hosted repositories through hosted-url, publish_to, credentials, and token workflows.",
                        "The protocol is suitable for integrating existing providers without HHC owning server maintenance.",
                        "This path keeps Flutter and dart pub workflows closest to the official toolchain.",
                    ]
                ),
                PubRegistryCandidateEvaluation(
                    kind: .selfHostedServer,
                    name: "unpub",
                    verdict: .researchOnly,
                    reasons: [
                        "It is a community self-hosted pub server, not an official deployable Dart service.",
                        "Maintenance and compatibility risk are too high to ship as a one-click server installer before live validation.",
                        "Use as a reference candidate only; do not expose install actions in the product yet.",
                    ]
                ),
                PubRegistryCandidateEvaluation(
                    kind: .selfHostedServer,
                    name: "dart-lang/pub_server",
                    verdict: .researchOnly,
                    reasons: [
                        "It is useful as protocol/reference material, but not a committed production server target for this app.",
                        "Owning a compliant Hosted Pub Repository implementation would expand Phase 6 beyond the current scope.",
                    ]
                ),
                PubRegistryCandidateEvaluation(
                    kind: .privateGitDependency,
                    name: "Private Git dependencies",
                    verdict: .notARegistry,
                    reasons: [
                        "Private Git works for selected package dependencies but does not provide package publishing, discovery, or registry management.",
                        "Keep it as guidance in project documentation, not as a registry installer.",
                    ]
                ),
            ],
            implementationDecision: "Do not implement a Dart/Flutter self-hosted pub registry installer in Phase 6.",
            shouldImplementSelfHostedInstaller: false,
            supportedProductPath: "Support external Hosted Pub Repository configuration assistance first: hosted-url, publish_to, token setup notes, and project-level validation.",
            evaluatedAt: evaluatedAt
        )
    }
}

enum PubHostedRepositoryAssistantError: LocalizedError, Equatable {
    case invalidHostedURL
    case invalidPackageName
    case invalidTokenEnvironmentVariable

    var errorDescription: String? {
        switch self {
        case .invalidHostedURL:
            "Enter an http or https hosted repository URL without credentials, query, or fragment."
        case .invalidPackageName:
            "Enter a Dart package name using lowercase letters, numbers, and underscores, starting with a letter."
        case .invalidTokenEnvironmentVariable:
            "Enter an environment variable name using uppercase letters, numbers, and underscores."
        }
    }
}

enum PubHostedRepositoryAssistant {
    static func buildPlan(
        draft: PubHostedRepositoryDraft,
        generatedAt: Date = Date()
    ) throws -> PubHostedRepositoryPlan {
        let hostedURL = try normalizedHostedURL(draft.hostedURL)
        let packageName = try normalizedPackageName(draft.packageName)
        let tokenEnvironmentVariable = try normalizedTokenEnvironmentVariable(draft.tokenEnvironmentVariable)
        var checks = [
            PubHostedRepositoryCheck(
                id: "hosted-url",
                title: "Hosted URL",
                status: hostedURL.hasPrefix("https://") ? .passed : .warning,
                detail: hostedURL.hasPrefix("https://")
                    ? "Uses HTTPS and can be referenced by dart pub."
                    : "HTTP is allowed for trusted internal networks only."
            ),
            PubHostedRepositoryCheck(
                id: "package-name",
                title: "Package Name",
                status: .passed,
                detail: "\(packageName) is a valid Dart package name."
            ),
            PubHostedRepositoryCheck(
                id: "token-env",
                title: "Token Storage",
                status: .passed,
                detail: "The generated command reads the token from \(tokenEnvironmentVariable)."
            ),
        ]
        let warnings = warnings(for: hostedURL)
        if warnings.contains(where: { $0.contains("HTTP") }) {
            checks.append(PubHostedRepositoryCheck(
                id: "transport",
                title: "Transport",
                status: .warning,
                detail: "Use HTTPS before exposing the repository outside a private network."
            ))
        }

        return PubHostedRepositoryPlan(
            hostedURL: hostedURL,
            packageName: packageName,
            tokenEnvironmentVariable: tokenEnvironmentVariable,
            pubspecSnippet: """
            dependencies:
              \(packageName):
                hosted: \(hostedURL)
                version: ^1.0.0
            """,
            publishToSnippet: "publish_to: \(hostedURL)",
            tokenCommand: "dart pub token add \(hostedURL) --env-var \(tokenEnvironmentVariable)",
            publishCommand: "dart pub publish",
            getCommand: "dart pub get",
            flutterGetCommand: draft.includeFlutterCommand ? "flutter pub get" : nil,
            checks: checks,
            warnings: warnings,
            generatedAt: generatedAt
        )
    }

    private static func normalizedHostedURL(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .newlines) == nil,
              trimmed.range(of: "\0") == nil,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw PubHostedRepositoryAssistantError.invalidHostedURL
        }

        var normalized = components
        normalized.scheme = scheme
        guard let url = normalized.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
            throw PubHostedRepositoryAssistantError.invalidHostedURL
        }
        return url
    }

    private static func normalizedPackageName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(
            of: #"^[a-z][a-z0-9_]{0,63}$"#,
            options: .regularExpression
        ) != nil else {
            throw PubHostedRepositoryAssistantError.invalidPackageName
        }
        return trimmed
    }

    private static func normalizedTokenEnvironmentVariable(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(
            of: #"^[A-Z_][A-Z0-9_]{0,127}$"#,
            options: .regularExpression
        ) != nil else {
            throw PubHostedRepositoryAssistantError.invalidTokenEnvironmentVariable
        }
        return trimmed
    }

    private static func warnings(for hostedURL: String) -> [String] {
        var warnings = [
            "Do not store repository tokens in pubspec.yaml or source control.",
            "This assumes the server implements the Dart Hosted Pub Repository protocol.",
        ]
        if hostedURL.hasPrefix("http://") {
            warnings.append("HTTP hosted repositories should stay on trusted internal networks.")
        }
        return warnings
    }
}

enum RegistryPreflightStatus: String, Equatable, Sendable {
    case passed
    case warning
    case failed
}

struct RegistryPreflightCheck: Equatable, Sendable {
    var id: String
    var title: String
    var status: RegistryPreflightStatus
    var detail: String
    var remediation: String?
}

struct RegistryPreflightReport: Equatable, Sendable {
    var checks: [RegistryPreflightCheck]
    var rawOutput: String
    var capturedAt: Date

    var isReady: Bool {
        checks.allSatisfy { $0.status != .failed }
    }
}

struct VerdaccioInstallDraft: Equatable, Sendable {
    var name: String
    var installPath: String
    var dataPath: String
    var listenHost: String
    var listenPort: Int
    var serviceName: String
    var version: String

    static let defaultVersion = "5.31.1"

    init(
        name: String = "Verdaccio",
        installPath: String = "/srv/verdaccio",
        dataPath: String = "/srv/verdaccio/storage",
        listenHost: String = "127.0.0.1",
        listenPort: Int = 4873,
        serviceName: String = "verdaccio",
        version: String = Self.defaultVersion
    ) {
        self.name = name
        self.installPath = installPath
        self.dataPath = dataPath
        self.listenHost = listenHost
        self.listenPort = listenPort
        self.serviceName = serviceName
        self.version = version
    }
}

enum VerdaccioPackageAccessMode: String, Equatable, Sendable {
    case publicReadAuthenticatedPublish
    case authenticatedReadAndPublish
}

struct VerdaccioConfigPolicy: Equatable, Sendable {
    var upstreamRegistryURL: String
    var accessMode: VerdaccioPackageAccessMode

    init(
        upstreamRegistryURL: String = "https://registry.npmjs.org/",
        accessMode: VerdaccioPackageAccessMode = .publicReadAuthenticatedPublish
    ) {
        self.upstreamRegistryURL = upstreamRegistryURL
        self.accessMode = accessMode
    }
}

struct VerdaccioNginxProxyDraft: Equatable, Sendable {
    var serverName: String
    var configPath: String
    var clientMaxBodySize: String

    init(
        serverName: String,
        configPath: String = "/etc/nginx/conf.d/verdaccio.conf",
        clientMaxBodySize: String = "100m"
    ) {
        self.serverName = serverName
        self.configPath = configPath
        self.clientMaxBodySize = clientMaxBodySize
    }
}

struct VerdaccioInstallResult: Equatable, Sendable {
    var configPath: String
    var servicePath: String
    var healthCheckURL: String
    var healthCheckOutput: String
}

struct VerdaccioStatusSnapshot: Equatable, Sendable {
    var serviceName: String
    var activeState: String
    var subState: String
    var version: String?
    var storageBytes: Int64?
    var recentLogs: String
    var capturedAt: Date

    var isRunning: Bool {
        activeState == "active" && subState == "running"
    }
}

struct VerdaccioConfigFile: Equatable, Sendable {
    var path: String
    var content: String
    var capturedAt: Date
}

struct VerdaccioConfigSaveResult: Equatable, Sendable {
    var path: String
    var backupPath: String
}

enum VerdaccioUserMutationAction: String, Equatable, Sendable {
    case create
    case updatePassword
    case delete
}

struct VerdaccioUserMutationResult: Equatable, Sendable {
    var username: String
    var action: VerdaccioUserMutationAction
    var htpasswdPath: String
    var backupPath: String
}

struct VerdaccioPackageSummary: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var versionCount: Int
    var latestVersion: String?
    var sizeBytes: Int64?
    var modifiedAt: Date?
}

struct VerdaccioRegistryBackupResult: Equatable, Sendable {
    var backupPath: String
    var sizeBytes: Int64?
    var historyRecord: RegistryBackupRecord?
}

struct VerdaccioRegistryRestoreResult: Equatable, Sendable {
    var backupPath: String
    var rollbackBackupPath: String
    var healthCheckURL: String
    var healthCheckOutput: String
    var historyRecord: RegistryBackupRecord?
}

struct VerdaccioNpmSmokeTestResult: Equatable, Sendable {
    var packageName: String
    var version: String
    var registryURL: String
    var publishOutput: String
    var installOutput: String
    var requireOutput: String
}

enum VerdaccioServiceAction: String, CaseIterable, Identifiable, Equatable, Sendable {
    case start
    case stop
    case restart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .start:
            "Start"
        case .stop:
            "Stop"
        case .restart:
            "Restart"
        }
    }
}

struct VerdaccioServiceActionResult: Equatable, Sendable {
    var action: VerdaccioServiceAction
    var serviceName: String
    var commandOutput: String
    var healthCheckOutput: String?
    var snapshot: VerdaccioStatusSnapshot
}

struct VerdaccioUpgradeResult: Equatable, Sendable {
    var version: String
    var servicePath: String
    var backupPath: String
    var healthCheckURL: String
    var healthCheckOutput: String
    var snapshot: VerdaccioStatusSnapshot
}

enum RegistryConfigurationError: LocalizedError, Equatable {
    case invalidName
    case invalidPath(String)
    case invalidHost
    case invalidPort
    case invalidServiceName
    case invalidVersion
    case invalidRegistryURL
    case invalidProxyServerName
    case invalidProxyBodySize
    case invalidRegistryUsername
    case invalidRegistryPassword
    case invalidRegistryEmail

    var errorDescription: String? {
        switch self {
        case .invalidName:
            "Registry name cannot be empty or contain line breaks."
        case let .invalidPath(path):
            "Registry path \(path) must be under /srv, /opt, /var/lib, or /home and cannot contain line breaks."
        case .invalidHost:
            "Listen host must be a local, private, or explicit IP address without line breaks."
        case .invalidPort:
            "Listen port must be between 1024 and 65535."
        case .invalidServiceName:
            "Service name can only contain letters, numbers, underscore, dot, at sign, and dash."
        case .invalidVersion:
            "Verdaccio version must be pinned to a stable semver version such as 5.31.1."
        case .invalidRegistryURL:
            "Upstream registry URL must be an http(s) URL without credentials, query, fragment, or line breaks."
        case .invalidProxyServerName:
            "Nginx server_name must be a domain, wildcard domain, IP address, or underscore without unsafe characters."
        case .invalidProxyBodySize:
            "Nginx client_max_body_size must be a positive number followed by k, m, or g."
        case .invalidRegistryUsername:
            "Registry username must be 1-64 characters and can only contain letters, numbers, dot, underscore, at sign, and dash."
        case .invalidRegistryPassword:
            "Registry password must be 8-4096 characters and cannot contain line breaks or null bytes."
        case .invalidRegistryEmail:
            "Registry email must be a simple email address without line breaks or null bytes."
        }
    }
}

enum VerdaccioConfigurationBuilder {
    static func validate(_ draft: VerdaccioInstallDraft) throws {
        guard !draft.name.trimmed.isEmpty,
              !draft.name.contains("\n"),
              !draft.name.contains("\r"),
              !draft.name.contains("\0")
        else {
            throw RegistryConfigurationError.invalidName
        }
        try validatePath(draft.installPath)
        try validatePath(draft.dataPath)
        guard isValidListenHost(draft.listenHost.trimmed) else {
            throw RegistryConfigurationError.invalidHost
        }
        guard (1024...65535).contains(draft.listenPort) else {
            throw RegistryConfigurationError.invalidPort
        }
        guard draft.serviceName.trimmed.range(
            of: #"^[A-Za-z0-9_.@-]+$"#,
            options: .regularExpression
        ) != nil else {
            throw RegistryConfigurationError.invalidServiceName
        }
        guard isStablePinnedVersion(draft.version.trimmed) else {
            throw RegistryConfigurationError.invalidVersion
        }
    }

    static func configurationYAML(
        for draft: VerdaccioInstallDraft,
        policy: VerdaccioConfigPolicy = VerdaccioConfigPolicy()
    ) throws -> String {
        try validate(draft)
        try validate(policy)
        let packagePolicy = packagePolicyLines(for: policy.accessMode)
        return """
        storage: \(draft.dataPath.trimmed)

        listen:
          - \(draft.listenHost.trimmed):\(draft.listenPort)

        auth:
          htpasswd:
            file: ./htpasswd
            max_users: -1

        uplinks:
          npmjs:
            url: \(policy.upstreamRegistryURL.trimmed)

        packages:
          '@*/*':
            access: \(packagePolicy.access)
            publish: \(packagePolicy.publish)
            proxy: npmjs
          '**':
            access: \(packagePolicy.access)
            publish: \(packagePolicy.publish)
            proxy: npmjs

        logs:
          - {type: stdout, format: pretty, level: http}

        security:
          api:
            jwt:
              sign:
                expiresIn: 29d
        """
    }

    static func validate(_ policy: VerdaccioConfigPolicy) throws {
        let url = policy.upstreamRegistryURL.trimmed
        guard !url.isEmpty,
              !url.contains("\n"),
              !url.contains("\r"),
              !url.contains("\0"),
              let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.nilIfEmpty != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw RegistryConfigurationError.invalidRegistryURL
        }
    }

    static func nginxProxyConfig(for draft: VerdaccioInstallDraft, proxy: VerdaccioNginxProxyDraft) throws -> String {
        try validate(draft)
        try validate(proxy)
        let upstreamHost = draft.listenHost.trimmed == "0.0.0.0" ? "127.0.0.1" : draft.listenHost.trimmed
        return """
        # Generated by HHC Server Manager for Verdaccio.
        # HTTPS is intentionally not managed here. Add TLS certificates in your existing Nginx/ACME workflow.
        server {
            listen 80;
            server_name \(proxy.serverName.trimmed);

            client_max_body_size \(proxy.clientMaxBodySize.trimmed.lowercased());

            location / {
                proxy_pass http://\(upstreamHost):\(draft.listenPort);
                proxy_http_version 1.1;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection "upgrade";
            }
        }
        """
    }

    static func nginxProxyConfigFile(for proxy: VerdaccioNginxProxyDraft) throws -> NginxConfigFile {
        let path = try NginxConfigManager.validatedConfigPath(proxy.configPath)
        try validate(proxy)
        return NginxConfigFile(path: path, size: nil, modifiedAt: nil)
    }

    static func validate(_ proxy: VerdaccioNginxProxyDraft) throws {
        let serverName = proxy.serverName.trimmed
        guard serverName.range(
            of: #"^(_|(\*\.)?[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*|([0-9]{1,3}\.){3}[0-9]{1,3})$"#,
            options: .regularExpression
        ) != nil,
            !serverName.contains("\n"),
            !serverName.contains("\r"),
            !serverName.contains("\0")
        else {
            throw RegistryConfigurationError.invalidProxyServerName
        }
        let bodySize = proxy.clientMaxBodySize.trimmed.lowercased()
        guard bodySize.range(of: #"^[1-9][0-9]*[kmg]$"#, options: .regularExpression) != nil else {
            throw RegistryConfigurationError.invalidProxyBodySize
        }
        _ = try NginxConfigManager.validatedConfigPath(proxy.configPath)
    }

    static func systemdService(for draft: VerdaccioInstallDraft) throws -> String {
        try validate(draft)
        let installPath = draft.installPath.trimmed
        let serviceName = draft.serviceName.trimmed
        return """
        [Unit]
        Description=Verdaccio private npm registry (\(draft.name.trimmed))
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=simple
        User=\(serviceName)
        Group=\(serviceName)
        WorkingDirectory=\(installPath)
        Environment=NODE_ENV=production
        ExecStart=\(installPath)/node_modules/.bin/verdaccio --config \(installPath)/config.yaml
        Restart=on-failure
        RestartSec=5
        NoNewPrivileges=true
        PrivateTmp=true
        ProtectSystem=full
        ProtectHome=true
        ReadWritePaths=\(installPath) \(draft.dataPath.trimmed)

        [Install]
        WantedBy=multi-user.target
        """
    }

    private static func validatePath(_ path: String) throws {
        let trimmed = path.trimmed
        guard !trimmed.isEmpty,
              trimmed.range(
                  of: #"^/(srv|opt|var/lib|home)(/[A-Za-z0-9._@-]+)+$"#,
                  options: .regularExpression
              ) != nil
        else {
            throw RegistryConfigurationError.invalidPath(trimmed)
        }
    }

    private static func isValidListenHost(_ host: String) -> Bool {
        guard !host.isEmpty,
              !host.contains("\n"),
              !host.contains("\r"),
              !host.contains("\0")
        else { return false }
        if ["127.0.0.1", "localhost", "0.0.0.0"].contains(host) {
            return true
        }
        return host.range(
            of: #"^(10(\.[0-9]{1,3}){3}|172\.(1[6-9]|2[0-9]|3[0-1])(\.[0-9]{1,3}){2}|192\.168(\.[0-9]{1,3}){2})$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isStablePinnedVersion(_ version: String) -> Bool {
        version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func packagePolicyLines(for mode: VerdaccioPackageAccessMode) -> (access: String, publish: String) {
        switch mode {
        case .publicReadAuthenticatedPublish:
            ("$all", "$authenticated")
        case .authenticatedReadAndPublish:
            ("$authenticated", "$authenticated")
        }
    }
}

final class VerdaccioInstaller: @unchecked Sendable {
    func install(
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioInstallResult {
        let command = try Self.installCommand(for: draft)
        let installResult = try await CloudProviderRequestRunner.withTimeout(120) {
            try await sshClient.execute(command, profile: profile)
        }
        guard installResult.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: installResult, fallback: "Verdaccio installation failed."))
        }

        let healthCheckURL = Self.healthCheckURL(for: draft)
        let healthResult = try await CloudProviderRequestRunner.withTimeout(45) {
            try await sshClient.execute(Self.healthCheckCommand(url: healthCheckURL), profile: profile)
        }
        guard healthResult.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: healthResult, fallback: "Verdaccio health check failed."))
        }

        return VerdaccioInstallResult(
            configPath: "\(draft.installPath.trimmed)/config.yaml",
            servicePath: "/etc/systemd/system/\(draft.serviceName.trimmed).service",
            healthCheckURL: healthCheckURL,
            healthCheckOutput: DeploymentLogRedactor.redact(healthResult.stdout.trimmed.nilIfEmpty ?? "ok")
        )
    }

    static func installCommand(for draft: VerdaccioInstallDraft) throws -> String {
        try VerdaccioConfigurationBuilder.validate(draft)
        let installPath = draft.installPath.trimmed
        let dataPath = draft.dataPath.trimmed
        let serviceName = draft.serviceName.trimmed
        let configData = Data(try VerdaccioConfigurationBuilder.configurationYAML(for: draft).utf8).base64EncodedString()
        let serviceData = Data(try VerdaccioConfigurationBuilder.systemdService(for: draft).utf8).base64EncodedString()
        return """
        set -e; \
        install_path=\(shellQuote(installPath)); \
        data_path=\(shellQuote(dataPath)); \
        service_name=\(shellQuote(serviceName)); \
        if ! id -u "$service_name" >/dev/null 2>&1; then useradd --system --home-dir "$install_path" --shell /usr/sbin/nologin "$service_name"; fi; \
        install -d -m 0755 -o "$service_name" -g "$service_name" "$install_path" "$data_path"; \
        base64 -d > "$install_path/config.yaml" <<'__HHC_VERDACCIO_CONFIG__'
        \(configData)
        __HHC_VERDACCIO_CONFIG__
        chown "$service_name:$service_name" "$install_path/config.yaml"; \
        chmod 0640 "$install_path/config.yaml"; \
        npm install --prefix "$install_path" --omit=dev --no-audit --no-fund \(shellQuote("verdaccio@\(draft.version.trimmed)")); \
        chown -R "$service_name:$service_name" "$install_path"; \
        base64 -d > \(shellQuote("/etc/systemd/system/\(serviceName).service")) <<'__HHC_VERDACCIO_SERVICE__'
        \(serviceData)
        __HHC_VERDACCIO_SERVICE__
        chmod 0644 \(shellQuote("/etc/systemd/system/\(serviceName).service")); \
        systemctl daemon-reload; \
        systemctl enable --now \(shellQuote("\(serviceName).service")); \
        systemctl restart \(shellQuote("\(serviceName).service"))
        """
    }

    private static func healthCheckURL(for draft: VerdaccioInstallDraft) -> String {
        let host = draft.listenHost.trimmed == "0.0.0.0" ? "127.0.0.1" : draft.listenHost.trimmed
        return "http://\(host):\(draft.listenPort)/-/ping"
    }

    private static func healthCheckCommand(url: String) -> String {
        """
        url=\(shellQuote(url)); \
        for attempt in $(seq 1 8); do curl -fsS --max-time 3 "$url" && exit 0; sleep 2; done; \
        curl -fsS --max-time 5 "$url"
        """
    }

    private static func redactedOutput(from result: CommandResult, fallback: String) -> String {
        DeploymentLogRedactor.redact(
            [result.stderr.trimmed, result.stdout.trimmed]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .nilIfEmpty ?? fallback
        )
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

final class VerdaccioManager: @unchecked Sendable {
    static let maxConfigBytes = 256 * 1024
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func loadStatus(
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioStatusSnapshot {
        try VerdaccioConfigurationBuilder.validate(draft)
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(Self.statusCommand(for: draft), profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not load Verdaccio status."))
        }
        return Self.parseStatus(result.stdout, serviceName: draft.serviceName.trimmed, capturedAt: now())
    }

    func readConfig(
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioConfigFile {
        try VerdaccioConfigurationBuilder.validate(draft)
        let path = "\(draft.installPath.trimmed)/config.yaml"
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(Self.readConfigCommand(path: path), profile: profile)
        }
        guard result.exitCode == 0 else {
            if result.stdout.hasPrefix("__HHC_VERDACCIO_CONFIG_TOO_LARGE__") {
                throw SSHClientError.processFailed("Verdaccio config is larger than the 256 KiB editing limit.")
            }
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not read Verdaccio config."))
        }
        let encoded = result.stdout.split(whereSeparator: { $0.isWhitespace }).joined()
        guard let data = Data(base64Encoded: encoded), let content = String(data: data, encoding: .utf8) else {
            throw SSHClientError.processFailed("Verdaccio config is not valid UTF-8 text.")
        }
        return VerdaccioConfigFile(path: path, content: content, capturedAt: now())
    }

    func saveConfig(
        draft: VerdaccioInstallDraft,
        content: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioConfigSaveResult {
        try VerdaccioConfigurationBuilder.validate(draft)
        let data = Data(content.utf8)
        guard data.count <= Self.maxConfigBytes else {
            throw SSHClientError.processFailed("Verdaccio config is larger than the 256 KiB editing limit.")
        }
        let path = "\(draft.installPath.trimmed)/config.yaml"
        let timestamp = Self.timestamp(for: now())
        let backupPath = "\(path).hhc-backup-\(timestamp)"
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(
                Self.saveConfigCommand(
                    path: path,
                    backupPath: backupPath,
                    serviceName: draft.serviceName.trimmed,
                    encodedContent: data.base64EncodedString()
                ),
                profile: profile
            )
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not save Verdaccio config."))
        }
        return VerdaccioConfigSaveResult(path: path, backupPath: backupPath)
    }

    func saveGeneratedConfig(
        draft: VerdaccioInstallDraft,
        policy: VerdaccioConfigPolicy,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioConfigSaveResult {
        let content = try VerdaccioConfigurationBuilder.configurationYAML(for: draft, policy: policy)
        return try await saveConfig(
            draft: draft,
            content: content,
            profile: profile,
            sshClient: sshClient
        )
    }

    func createUser(
        draft: VerdaccioInstallDraft,
        username: String,
        password: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioUserMutationResult {
        try validateUsername(username)
        try validatePassword(password)
        let backupPath = htpasswdBackupPath(for: draft)
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(
                Self.upsertUserCommand(
                    draft: draft,
                    username: username.trimmed,
                    password: password,
                    backupPath: backupPath,
                    requireExistingUser: false
                ),
                profile: profile
            )
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not create Verdaccio user."))
        }
        return VerdaccioUserMutationResult(
            username: username.trimmed,
            action: .create,
            htpasswdPath: Self.htpasswdPath(for: draft),
            backupPath: backupPath
        )
    }

    func updateUserPassword(
        draft: VerdaccioInstallDraft,
        username: String,
        password: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioUserMutationResult {
        try validateUsername(username)
        try validatePassword(password)
        let backupPath = htpasswdBackupPath(for: draft)
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(
                Self.upsertUserCommand(
                    draft: draft,
                    username: username.trimmed,
                    password: password,
                    backupPath: backupPath,
                    requireExistingUser: true
                ),
                profile: profile
            )
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not update Verdaccio user."))
        }
        return VerdaccioUserMutationResult(
            username: username.trimmed,
            action: .updatePassword,
            htpasswdPath: Self.htpasswdPath(for: draft),
            backupPath: backupPath
        )
    }

    func deleteUser(
        draft: VerdaccioInstallDraft,
        username: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioUserMutationResult {
        try validateUsername(username)
        let backupPath = htpasswdBackupPath(for: draft)
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(
                Self.deleteUserCommand(
                    draft: draft,
                    username: username.trimmed,
                    backupPath: backupPath
                ),
                profile: profile
            )
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not delete Verdaccio user."))
        }
        return VerdaccioUserMutationResult(
            username: username.trimmed,
            action: .delete,
            htpasswdPath: Self.htpasswdPath(for: draft),
            backupPath: backupPath
        )
    }

    func listPackages(
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> [VerdaccioPackageSummary] {
        try VerdaccioConfigurationBuilder.validate(draft)
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(Self.packageListCommand(for: draft), profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not list Verdaccio packages."))
        }
        return Self.parsePackageList(result.stdout)
    }

    func runNpmSmokeTest(
        draft: VerdaccioInstallDraft,
        username: String,
        password: String,
        email: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioNpmSmokeTestResult {
        try VerdaccioConfigurationBuilder.validate(draft)
        try validateUsername(username)
        try validatePassword(password)
        try validateEmail(email)
        let timestamp = Self.timestamp(for: now())
            .lowercased()
            .replacingOccurrences(of: ".", with: "-")
        let packageName = "@hhc-smoke/pkg-\(timestamp)"
        let version = "0.0.1"
        let registryURL = Self.registryURL(for: draft)
        let result = try await CloudProviderRequestRunner.withTimeout(90) {
            try await sshClient.execute(
                Self.npmSmokeTestCommand(
                    packageName: packageName,
                    version: version,
                    registryURL: registryURL,
                    username: username.trimmed,
                    password: password,
                    email: email.trimmed
                ),
                profile: profile
            )
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Verdaccio npm smoke test failed."))
        }
        let markers = Self.parseMarkers(result.stdout)
        return VerdaccioNpmSmokeTestResult(
            packageName: packageName,
            version: version,
            registryURL: registryURL,
            publishOutput: markers["PUBLISH"] ?? "",
            installOutput: markers["INSTALL"] ?? "",
            requireOutput: markers["REQUIRE"] ?? ""
        )
    }

    func performServiceAction(
        _ action: VerdaccioServiceAction,
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioServiceActionResult {
        try VerdaccioConfigurationBuilder.validate(draft)
        let result = try await CloudProviderRequestRunner.withTimeout(30) {
            try await sshClient.execute(Self.serviceActionCommand(action, for: draft), profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not \(action.rawValue) Verdaccio."))
        }

        var healthCheckOutput: String?
        if action != .stop {
            let healthResult = try await CloudProviderRequestRunner.withTimeout(45) {
                try await sshClient.execute(Self.healthCheckCommand(url: Self.healthCheckURL(for: draft)), profile: profile)
            }
            guard healthResult.exitCode == 0 else {
                throw SSHClientError.processFailed(Self.redactedOutput(from: healthResult, fallback: "Verdaccio health check failed after \(action.rawValue)."))
            }
            healthCheckOutput = DeploymentLogRedactor.redact(healthResult.stdout.trimmed.nilIfEmpty ?? "ok")
        }

        let snapshot = try await loadStatus(draft: draft, profile: profile, sshClient: sshClient)
        return VerdaccioServiceActionResult(
            action: action,
            serviceName: "\(draft.serviceName.trimmed).service",
            commandOutput: DeploymentLogRedactor.redact(result.stdout.trimmed.nilIfEmpty ?? "ok"),
            healthCheckOutput: healthCheckOutput,
            snapshot: snapshot
        )
    }

    func upgrade(
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioUpgradeResult {
        try VerdaccioConfigurationBuilder.validate(draft)
        let servicePath = "/etc/systemd/system/\(draft.serviceName.trimmed).service"
        let backupPath = "\(draft.installPath.trimmed)/backups/\(draft.serviceName.trimmed).service.hhc-backup-\(Self.timestamp(for: now()))"
        let result = try await CloudProviderRequestRunner.withTimeout(90) {
            try await sshClient.execute(Self.upgradeCommand(for: draft, backupPath: backupPath), profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not upgrade Verdaccio."))
        }

        let healthCheckURL = Self.healthCheckURL(for: draft)
        let healthResult = try await CloudProviderRequestRunner.withTimeout(45) {
            try await sshClient.execute(Self.healthCheckCommand(url: healthCheckURL), profile: profile)
        }
        guard healthResult.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: healthResult, fallback: "Verdaccio health check failed after upgrade."))
        }
        let snapshot = try await loadStatus(draft: draft, profile: profile, sshClient: sshClient)
        return VerdaccioUpgradeResult(
            version: draft.version.trimmed,
            servicePath: servicePath,
            backupPath: backupPath,
            healthCheckURL: healthCheckURL,
            healthCheckOutput: DeploymentLogRedactor.redact(healthResult.stdout.trimmed.nilIfEmpty ?? "ok"),
            snapshot: snapshot
        )
    }

    func createBackup(
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        sshClient: SSHClient,
        repository: ServerRepository? = nil
    ) async throws -> VerdaccioRegistryBackupResult {
        try VerdaccioConfigurationBuilder.validate(draft)
        let backupPath = "\(draft.installPath.trimmed)/backups/verdaccio-\(Self.timestamp(for: now())).tar.gz"
        let result = try await CloudProviderRequestRunner.withTimeout(60) {
            try await sshClient.execute(Self.backupCommand(for: draft, backupPath: backupPath), profile: profile)
        }
        guard result.exitCode == 0 else {
            try recordBackupHistory(
                draft: draft,
                profile: profile,
                repository: repository,
                backupPath: backupPath,
                status: .failed,
                sizeBytes: nil,
                restoredAt: nil,
                message: Self.redactedOutput(from: result, fallback: "Could not create Verdaccio backup.")
            )
            throw SSHClientError.processFailed(Self.redactedOutput(from: result, fallback: "Could not create Verdaccio backup."))
        }
        let sizeBytes = Int64(result.stdout.trimmed.nilIfEmpty ?? "")
        let historyRecord = try recordBackupHistory(
            draft: draft,
            profile: profile,
            repository: repository,
            backupPath: backupPath,
            status: .created,
            sizeBytes: sizeBytes,
            restoredAt: nil,
            message: nil
        )
        return VerdaccioRegistryBackupResult(
            backupPath: backupPath,
            sizeBytes: sizeBytes,
            historyRecord: historyRecord
        )
    }

    func restoreBackup(
        draft: VerdaccioInstallDraft,
        backupPath: String,
        profile: ServerProfile,
        sshClient: SSHClient,
        repository: ServerRepository? = nil
    ) async throws -> VerdaccioRegistryRestoreResult {
        try VerdaccioConfigurationBuilder.validate(draft)
        let backupPath = try Self.validatedBackupPath(backupPath, for: draft)
        let rollbackPath = "\(draft.installPath.trimmed)/backups/restore-rollback-\(Self.timestamp(for: now())).tar.gz"
        let restoreResult = try await CloudProviderRequestRunner.withTimeout(60) {
            try await sshClient.execute(
                Self.restoreCommand(for: draft, backupPath: backupPath, rollbackBackupPath: rollbackPath),
                profile: profile
            )
        }
        guard restoreResult.exitCode == 0 else {
            try recordBackupHistory(
                draft: draft,
                profile: profile,
                repository: repository,
                backupPath: backupPath,
                status: .restoreFailed,
                sizeBytes: nil,
                restoredAt: now(),
                message: Self.redactedOutput(from: restoreResult, fallback: "Could not restore Verdaccio backup.")
            )
            throw try await restoreFailureWithRollback(
                draft: draft,
                rollbackPath: rollbackPath,
                result: restoreResult,
                profile: profile,
                sshClient: sshClient,
                fallback: "Could not restore Verdaccio backup."
            )
        }

        let healthCheckURL = Self.healthCheckURL(for: draft)
        let healthResult = try await CloudProviderRequestRunner.withTimeout(45) {
            try await sshClient.execute(Self.healthCheckCommand(url: healthCheckURL), profile: profile)
        }
        guard healthResult.exitCode == 0 else {
            let rollbackResult = try await CloudProviderRequestRunner.withTimeout(60) {
                try await sshClient.execute(
                    Self.rollbackCommand(for: draft, rollbackBackupPath: rollbackPath),
                    profile: profile
                )
            }
            let healthMessage = Self.redactedOutput(from: healthResult, fallback: "Verdaccio restore health check failed.")
            if rollbackResult.exitCode == 0 {
                try recordBackupHistory(
                    draft: draft,
                    profile: profile,
                    repository: repository,
                    backupPath: backupPath,
                    status: .restoreFailed,
                    sizeBytes: nil,
                    restoredAt: now(),
                    message: healthMessage
                )
                throw SSHClientError.processFailed("\(healthMessage)\nRollback attempted using \(rollbackPath).")
            }
            let rollbackMessage = Self.redactedOutput(from: rollbackResult, fallback: "Rollback failed.")
            try recordBackupHistory(
                draft: draft,
                profile: profile,
                repository: repository,
                backupPath: backupPath,
                status: .restoreFailed,
                sizeBytes: nil,
                restoredAt: now(),
                message: "\(healthMessage)\nRollback failed: \(rollbackMessage)"
            )
            throw SSHClientError.processFailed("\(healthMessage)\nRollback failed using \(rollbackPath): \(rollbackMessage)")
        }

        let historyRecord = try recordBackupHistory(
            draft: draft,
            profile: profile,
            repository: repository,
            backupPath: backupPath,
            status: .restored,
            sizeBytes: nil,
            restoredAt: now(),
            message: nil
        )

        return VerdaccioRegistryRestoreResult(
            backupPath: backupPath,
            rollbackBackupPath: rollbackPath,
            healthCheckURL: healthCheckURL,
            healthCheckOutput: DeploymentLogRedactor.redact(healthResult.stdout.trimmed.nilIfEmpty ?? "ok"),
            historyRecord: historyRecord
        )
    }

    @discardableResult
    private func recordBackupHistory(
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        repository: ServerRepository?,
        backupPath: String,
        status: RegistryBackupStatus,
        sizeBytes: Int64?,
        restoredAt: Date?,
        message: String?
    ) throws -> RegistryBackupRecord? {
        guard let repository else { return nil }
        let capturedAt = now()
        let existing = try repository.fetchRegistryInstance(
            serverId: profile.id,
            kind: .verdaccio,
            installPath: draft.installPath.trimmed,
            serviceName: draft.serviceName.trimmed
        )
        let registry = RegistryInstance(
            id: existing?.id ?? UUID(),
            serverId: profile.id,
            kind: .verdaccio,
            name: draft.name.trimmed,
            installPath: draft.installPath.trimmed,
            dataPath: draft.dataPath.trimmed,
            listenHost: draft.listenHost.trimmed,
            listenPort: draft.listenPort,
            serviceName: draft.serviceName.trimmed,
            version: draft.version.trimmed,
            status: status == .failed ? "backup_failed" : "active",
            createdAt: existing?.createdAt ?? capturedAt,
            updatedAt: capturedAt
        )
        try repository.upsertRegistryInstance(registry)
        let record = RegistryBackupRecord(
            id: UUID(),
            registryId: registry.id,
            backupPath: backupPath,
            status: status,
            sizeBytes: sizeBytes,
            createdAt: capturedAt,
            restoredAt: restoredAt,
            message: message
        )
        try repository.upsertRegistryBackup(record)
        return record
    }

    private func restoreFailureWithRollback(
        draft: VerdaccioInstallDraft,
        rollbackPath: String,
        result: CommandResult,
        profile: ServerProfile,
        sshClient: SSHClient,
        fallback: String
    ) async throws -> SSHClientError {
        let restoreMessage = Self.redactedOutput(from: result, fallback: fallback)
        let rollbackResult = try await CloudProviderRequestRunner.withTimeout(60) {
            try await sshClient.execute(Self.rollbackCommand(for: draft, rollbackBackupPath: rollbackPath), profile: profile)
        }
        if rollbackResult.exitCode == 0 {
            return SSHClientError.processFailed("\(restoreMessage)\nRollback attempted using \(rollbackPath).")
        }
        let rollbackMessage = Self.redactedOutput(from: rollbackResult, fallback: "Rollback failed.")
        return SSHClientError.processFailed("\(restoreMessage)\nRollback failed using \(rollbackPath): \(rollbackMessage)")
    }

    private func validateUsername(_ username: String) throws {
        let username = username.trimmed
        guard !username.isEmpty,
              username.count <= 64,
              username.range(of: #"^[A-Za-z0-9._@-]+$"#, options: .regularExpression) != nil,
              !username.contains(":")
        else {
            throw RegistryConfigurationError.invalidRegistryUsername
        }
    }

    private func validatePassword(_ password: String) throws {
        guard (8...4096).contains(password.count),
              !password.contains("\n"),
              !password.contains("\r"),
              !password.contains("\0")
        else {
            throw RegistryConfigurationError.invalidRegistryPassword
        }
    }

    private func validateEmail(_ email: String) throws {
        let email = email.trimmed
        guard !email.isEmpty,
              email.count <= 254,
              email.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil,
              !email.contains("\n"),
              !email.contains("\r"),
              !email.contains("\0")
        else {
            throw RegistryConfigurationError.invalidRegistryEmail
        }
    }

    private func htpasswdBackupPath(for draft: VerdaccioInstallDraft) -> String {
        "\(Self.htpasswdPath(for: draft)).hhc-backup-\(Self.timestamp(for: now()))"
    }

    static func parseStatus(
        _ output: String,
        serviceName: String,
        capturedAt: Date = Date()
    ) -> VerdaccioStatusSnapshot {
        let values = markerValues(from: output)
        return VerdaccioStatusSnapshot(
            serviceName: serviceName,
            activeState: values["ACTIVE_STATE"]?.nilIfEmpty ?? "unknown",
            subState: values["SUB_STATE"]?.nilIfEmpty ?? "unknown",
            version: values["VERSION"]?.nilIfEmpty,
            storageBytes: Int64(values["STORAGE_BYTES"] ?? ""),
            recentLogs: DeploymentLogRedactor.redact(values["LOGS"] ?? ""),
            capturedAt: capturedAt
        )
    }

    static func parsePackageList(_ output: String) -> [VerdaccioPackageSummary] {
        output
            .components(separatedBy: .newlines)
            .compactMap { line -> VerdaccioPackageSummary? in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 5 else { return nil }
                let name = parts[0].trimmed
                guard !name.isEmpty else { return nil }
                let versionCount = Int(parts[1]) ?? 0
                let latestVersion = parts[2].trimmed.nilIfEmpty
                let sizeBytes = Int64(parts[3])
                let modifiedAt = TimeInterval(parts[4]).map(Date.init(timeIntervalSince1970:))
                return VerdaccioPackageSummary(
                    name: name,
                    versionCount: versionCount,
                    latestVersion: latestVersion,
                    sizeBytes: sizeBytes,
                    modifiedAt: modifiedAt
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func htpasswdPath(for draft: VerdaccioInstallDraft) -> String {
        "\(draft.installPath.trimmed)/htpasswd"
    }

    static func upsertUserCommand(
        draft: VerdaccioInstallDraft,
        username: String,
        password: String,
        backupPath: String,
        requireExistingUser: Bool
    ) -> String {
        let encodedPassword = Data(password.utf8).base64EncodedString()
        let mode = requireExistingUser ? "update" : "create"
        return """
        set -e; \
        install_path=\(shellQuote(draft.installPath.trimmed)); \
        service_name=\(shellQuote(draft.serviceName.trimmed)); \
        username=\(shellQuote(username.trimmed)); \
        backup=\(shellQuote(backupPath)); \
        htpasswd_file="$install_path/htpasswd"; \
        service="$service_name.service"; \
        command -v htpasswd >/dev/null 2>&1 || { echo 'htpasswd command is required to manage Verdaccio users.' >&2; exit 127; }; \
        touch "$htpasswd_file"; \
        chown "$service_name:$service_name" "$htpasswd_file"; \
        chmod 0640 "$htpasswd_file"; \
        if [ \(shellQuote(mode)) = 'create' ] && grep -q "^$username:" "$htpasswd_file"; then echo 'Verdaccio user already exists.' >&2; exit 4; fi; \
        if [ \(shellQuote(mode)) = 'update' ] && ! grep -q "^$username:" "$htpasswd_file"; then echo 'Verdaccio user does not exist.' >&2; exit 5; fi; \
        password_file=$(mktemp); \
        trap 'rm -f -- "$password_file"' EXIT; \
        base64 -d > "$password_file" <<'__HHC_VERDACCIO_USER_PASSWORD__'
        \(encodedPassword)
        __HHC_VERDACCIO_USER_PASSWORD__
        cp -p -- "$htpasswd_file" "$backup"; \
        htpasswd -B -i "$htpasswd_file" "$username" < "$password_file"; \
        chown "$service_name:$service_name" "$htpasswd_file"; \
        chmod 0640 "$htpasswd_file"; \
        systemctl restart "$service"; \
        printf '__HHC_VERDACCIO_HTPASSWD_BACKUP__%s\\n' "$backup"
        """
    }

    static func deleteUserCommand(
        draft: VerdaccioInstallDraft,
        username: String,
        backupPath: String
    ) -> String {
        """
        set -e; \
        install_path=\(shellQuote(draft.installPath.trimmed)); \
        service_name=\(shellQuote(draft.serviceName.trimmed)); \
        username=\(shellQuote(username.trimmed)); \
        backup=\(shellQuote(backupPath)); \
        htpasswd_file="$install_path/htpasswd"; \
        service="$service_name.service"; \
        command -v htpasswd >/dev/null 2>&1 || { echo 'htpasswd command is required to manage Verdaccio users.' >&2; exit 127; }; \
        test -f "$htpasswd_file" || { echo 'Verdaccio htpasswd file does not exist.' >&2; exit 5; }; \
        if ! grep -q "^$username:" "$htpasswd_file"; then echo 'Verdaccio user does not exist.' >&2; exit 5; fi; \
        cp -p -- "$htpasswd_file" "$backup"; \
        htpasswd -D "$htpasswd_file" "$username"; \
        chown "$service_name:$service_name" "$htpasswd_file"; \
        chmod 0640 "$htpasswd_file"; \
        systemctl restart "$service"; \
        printf '__HHC_VERDACCIO_HTPASSWD_BACKUP__%s\\n' "$backup"
        """
    }

    static func statusCommand(for draft: VerdaccioInstallDraft) -> String {
        let service = shellQuote("\(draft.serviceName.trimmed).service")
        let dataPath = shellQuote(draft.dataPath.trimmed)
        return """
        service=\(service); install_path=\(shellQuote(draft.installPath.trimmed)); data_path=\(dataPath); \
        printf '__HHC_VERDACCIO_ACTIVE_STATE__%s\\n' "$(systemctl show "$service" --property=ActiveState --value 2>/dev/null || echo unknown)"; \
        printf '__HHC_VERDACCIO_SUB_STATE__%s\\n' "$(systemctl show "$service" --property=SubState --value 2>/dev/null || echo unknown)"; \
        printf '__HHC_VERDACCIO_VERSION__%s\\n' "$("$install_path/node_modules/.bin/verdaccio" --version 2>/dev/null || true)"; \
        printf '__HHC_VERDACCIO_STORAGE_BYTES__%s\\n' "$(du -sb "$data_path" 2>/dev/null | awk '{print $1}' || echo 0)"; \
        printf '__HHC_VERDACCIO_LOGS__'; journalctl -u "$service" -n 80 --no-pager 2>/dev/null | tail -n 80 | base64 | tr -d '\\n'; printf '\\n'
        """
    }

    static func packageListCommand(for draft: VerdaccioInstallDraft) -> String {
        let dataPath = shellQuote(draft.dataPath.trimmed)
        return """
        data_path=\(dataPath); \
        find "$data_path" -mindepth 1 -maxdepth 3 -type f -name package.json -print 2>/dev/null | while IFS= read -r package_json; do \
          package_dir=$(dirname -- "$package_json"); \
          rel=${package_dir#"$data_path"/}; \
          case "$rel" in _*|*/_*) continue ;; esac; \
          versions=$(find "$package_dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | wc -l | tr -d '[:space:]'); \
          latest=$(find "$package_dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\\n' 2>/dev/null | sort -V | tail -n 1); \
          size=$(du -sb "$package_dir" 2>/dev/null | awk '{print $1}'); \
          modified=$(stat -c %Y "$package_dir" 2>/dev/null || echo 0); \
          printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$rel" "$versions" "$latest" "$size" "$modified"; \
        done
        """
    }

    static func npmSmokeTestCommand(
        packageName: String,
        version: String,
        registryURL: String,
        username: String,
        password: String,
        email: String
    ) -> String {
        let encodedPassword = Data(password.utf8).base64EncodedString()
        let packageJSON = Data("""
        {"name":"\(packageName)","version":"\(version)","description":"HHC Verdaccio smoke test package","main":"index.js"}
        """.utf8).base64EncodedString()
        let indexJS = Data("""
        module.exports = "hhc-verdaccio-smoke-ok";
        """.utf8).base64EncodedString()
        return """
        set -e; \
        command -v npm >/dev/null 2>&1 || { echo 'npm command is required for Verdaccio smoke test.' >&2; exit 127; }; \
        registry_url=\(shellQuote(registryURL)); package_name=\(shellQuote(packageName)); package_version=\(shellQuote(version)); username=\(shellQuote(username.trimmed)); email=\(shellQuote(email.trimmed)); \
        registry_host=${registry_url#http://}; registry_host=${registry_host#https://}; \
        work_dir=$(mktemp -d); password_file=$(mktemp); npmrc="$work_dir/.npmrc"; publish_log="$work_dir/publish.log"; install_log="$work_dir/install.log"; \
        cleanup() { npm unpublish "$package_name@$package_version" --userconfig "$npmrc" --registry "$registry_url" --force >/dev/null 2>&1 || true; rm -rf -- "$work_dir" "$password_file"; }; \
        trap cleanup EXIT; \
        base64 -d > "$password_file" <<'__HHC_VERDACCIO_SMOKE_PASSWORD__'
        \(encodedPassword)
        __HHC_VERDACCIO_SMOKE_PASSWORD__
        auth=$(printf '%s:%s' "$username" "$(cat "$password_file")" | base64 | tr -d '\\n'); \
        { printf 'registry=%s\\n' "$registry_url"; printf '//%s/:_auth=%s\\n' "$registry_host" "$auth"; printf '//%s/:username=%s\\n' "$registry_host" "$username"; printf '//%s/:email=%s\\n' "$registry_host" "$email"; printf '//%s/:always-auth=true\\n' "$registry_host"; } > "$npmrc"; \
        cd "$work_dir"; \
        mkdir package install; \
        base64 -d > package/package.json <<'__HHC_VERDACCIO_SMOKE_PACKAGE__'
        \(packageJSON)
        __HHC_VERDACCIO_SMOKE_PACKAGE__
        base64 -d > package/index.js <<'__HHC_VERDACCIO_SMOKE_INDEX__'
        \(indexJS)
        __HHC_VERDACCIO_SMOKE_INDEX__
        cd "$work_dir/package"; npm publish --userconfig "$npmrc" --registry "$registry_url" --access public > "$publish_log"; \
        cd "$work_dir/install"; npm init -y >/dev/null; npm install "$package_name@$package_version" --userconfig "$npmrc" --registry "$registry_url" > "$install_log"; \
        require_output=$(node -e "process.stdout.write(require('$package_name'))"); \
        printf '__HHC_VERDACCIO_NPM_PACKAGE__%s\\n' "$package_name"; \
        printf '__HHC_VERDACCIO_NPM_PUBLISH__%s\\n' "$(tail -n 3 "$publish_log" | tr '\\n' ' ' | sed 's/[[:space:]]\\{1,\\}/ /g')"; \
        printf '__HHC_VERDACCIO_NPM_INSTALL__%s\\n' "$(tail -n 3 "$install_log" | tr '\\n' ' ' | sed 's/[[:space:]]\\{1,\\}/ /g')"; \
        printf '__HHC_VERDACCIO_NPM_REQUIRE__%s\\n' "$require_output"
        """
    }

    static func serviceActionCommand(_ action: VerdaccioServiceAction, for draft: VerdaccioInstallDraft) -> String {
        let service = shellQuote("\(draft.serviceName.trimmed).service")
        return "set -e; service=\(service); systemctl \(action.rawValue) \"$service\"; systemctl show \"$service\" --property=ActiveState --property=SubState --no-pager"
    }

    static func upgradeCommand(for draft: VerdaccioInstallDraft, backupPath: String) throws -> String {
        try VerdaccioConfigurationBuilder.validate(draft)
        let servicePath = "/etc/systemd/system/\(draft.serviceName.trimmed).service"
        let serviceData = Data(try VerdaccioConfigurationBuilder.systemdService(for: draft).utf8).base64EncodedString()
        return """
        set -e; \
        service_path=\(shellQuote(servicePath)); backup_path=\(shellQuote(backupPath)); service=\(shellQuote("\(draft.serviceName.trimmed).service")); \
        backup_dir=$(dirname -- "$backup_path"); install -d -m 0750 "$backup_dir"; \
        test -f "$service_path"; \
        cp -p -- "$service_path" "$backup_path"; \
        npm install --prefix \(shellQuote(draft.installPath.trimmed)) --omit=dev --no-audit --no-fund \(shellQuote("verdaccio@\(draft.version.trimmed)")); \
        chown -R \(shellQuote("\(draft.serviceName.trimmed):\(draft.serviceName.trimmed)")) \(shellQuote(draft.installPath.trimmed)); \
        base64 -d > "$service_path" <<'__HHC_VERDACCIO_SERVICE_UPGRADE__'
        \(serviceData)
        __HHC_VERDACCIO_SERVICE_UPGRADE__
        chmod 0644 "$service_path"; \
        systemctl daemon-reload; \
        systemctl restart "$service"; \
        printf '__HHC_VERDACCIO_SERVICE_BACKUP__%s\\n' "$backup_path"
        """
    }

    static func backupCommand(for draft: VerdaccioInstallDraft, backupPath: String) -> String {
        let installPath = shellQuote(draft.installPath.trimmed)
        let dataPath = shellQuote(draft.dataPath.trimmed)
        let backupPath = shellQuote(backupPath)
        return """
        set -e; \
        install_path=\(installPath); data_path=\(dataPath); backup_path=\(backupPath); \
        data_parent=$(dirname -- "$data_path"); data_name=$(basename -- "$data_path"); \
        backup_dir=$(dirname -- "$backup_path"); \
        install -d -m 0750 "$backup_dir"; \
        tar -czf "$backup_path" -C "$install_path" config.yaml -C "$data_parent" "$data_name"; \
        stat -c %s "$backup_path"
        """
    }

    static func restoreCommand(
        for draft: VerdaccioInstallDraft,
        backupPath: String,
        rollbackBackupPath: String
    ) -> String {
        restoreCommand(
            for: draft,
            archivePath: backupPath,
            rollbackBackupPath: rollbackBackupPath,
            createRollback: true
        )
    }

    static func rollbackCommand(for draft: VerdaccioInstallDraft, rollbackBackupPath: String) -> String {
        restoreCommand(
            for: draft,
            archivePath: rollbackBackupPath,
            rollbackBackupPath: nil,
            createRollback: false
        )
    }

    static func readConfigCommand(path: String) -> String {
        """
        path=\(shellQuote(path)); \
        bytes=$(wc -c < "$path" 2>/dev/null | tr -d '[:space:]' || echo 0); \
        if [ "$bytes" -gt \(maxConfigBytes) ]; then echo "__HHC_VERDACCIO_CONFIG_TOO_LARGE__$bytes"; exit 3; fi; \
        base64 < "$path"
        """
    }

    static func saveConfigCommand(
        path: String,
        backupPath: String,
        serviceName: String,
        encodedContent: String
    ) -> String {
        let temporaryPath = "\(path).hhc-tmp-\(UUID().uuidString)"
        return """
        set -e; \
        path=\(shellQuote(path)); \
        backup=\(shellQuote(backupPath)); \
        tmp=\(shellQuote(temporaryPath)); \
        service=\(shellQuote("\(serviceName).service")); \
        trap 'rm -f -- "$tmp"' EXIT; \
        cp -p -- "$path" "$backup"; \
        base64 -d > "$tmp" <<'__HHC_VERDACCIO_CONFIG_EOF__'
        \(encodedContent)
        __HHC_VERDACCIO_CONFIG_EOF__
        chown --reference="$path" "$tmp"; \
        chmod --reference="$path" "$tmp"; \
        mv -- "$tmp" "$path"; \
        systemctl restart "$service"; \
        trap - EXIT
        """
    }

    private static func markerValues(from output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) where line.hasPrefix("__HHC_VERDACCIO_") {
            let keyStart = line.index(line.startIndex, offsetBy: "__HHC_VERDACCIO_".count)
            guard let markerEnd = line.range(of: "__", range: keyStart..<line.endIndex) else { continue }
            let key = String(line[keyStart..<markerEnd.lowerBound])
            let value = String(line[markerEnd.upperBound...]).trimmed
            if key == "LOGS", let data = Data(base64Encoded: value), let decoded = String(data: data, encoding: .utf8) {
                values[key] = decoded
            } else {
                values[key] = value
            }
        }
        return values
    }

    private static func redactedOutput(from result: CommandResult, fallback: String) -> String {
        DeploymentLogRedactor.redact(
            [result.stderr.trimmed, result.stdout.trimmed]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .nilIfEmpty ?? fallback
        )
    }

    private static func restoreCommand(
        for draft: VerdaccioInstallDraft,
        archivePath: String,
        rollbackBackupPath: String?,
        createRollback: Bool
    ) -> String {
        let installPath = shellQuote(draft.installPath.trimmed)
        let dataPath = shellQuote(draft.dataPath.trimmed)
        let archivePath = shellQuote(archivePath)
        let rollbackSetup: String
        if createRollback, let rollbackBackupPath {
            rollbackSetup = "rollback_path=\(shellQuote(rollbackBackupPath)); rollback_dir=$(dirname -- \"$rollback_path\"); install -d -m 0750 \"$rollback_dir\"; tar -czf \"$rollback_path\" -C \"$install_path\" config.yaml -C \"$data_parent\" \"$data_name\"; "
        } else {
            rollbackSetup = ""
        }
        return """
        set -e; \
        install_path=\(installPath); data_path=\(dataPath); archive_path=\(archivePath); service=\(shellQuote("\(draft.serviceName.trimmed).service")); \
        data_parent=$(dirname -- "$data_path"); data_name=$(basename -- "$data_path"); restore_dir=$(mktemp -d); \
        trap 'rm -rf -- "$restore_dir"' EXIT; \
        systemctl stop "$service"; \
        \(rollbackSetup)\
        tar -xzf "$archive_path" -C "$restore_dir"; \
        test -f "$restore_dir/config.yaml"; \
        test -d "$restore_dir/$data_name"; \
        rm -rf -- "$data_path"; \
        install -d -m 0755 "$data_path"; \
        cp -a "$restore_dir/$data_name/." "$data_path/"; \
        cp -p "$restore_dir/config.yaml" "$install_path/config.yaml"; \
        systemctl start "$service"; \
        trap - EXIT; \
        rm -rf -- "$restore_dir"
        """
    }

    private static func validatedBackupPath(_ path: String, for draft: VerdaccioInstallDraft) throws -> String {
        let trimmed = path.trimmed
        let backupsPrefix = "\(draft.installPath.trimmed)/backups/"
        guard trimmed.hasPrefix(backupsPrefix),
              trimmed.hasSuffix(".tar.gz"),
              trimmed.range(of: #"^/(srv|opt|var/lib|home)(/[A-Za-z0-9._@-]+)+\.tar\.gz$"#, options: .regularExpression) != nil,
              !trimmed.contains("/../"),
              !trimmed.contains("\n"),
              !trimmed.contains("\r"),
              !trimmed.contains("\0")
        else {
            throw RegistryConfigurationError.invalidPath(trimmed)
        }
        return trimmed
    }

    private static func healthCheckURL(for draft: VerdaccioInstallDraft) -> String {
        let host = draft.listenHost.trimmed == "0.0.0.0" ? "127.0.0.1" : draft.listenHost.trimmed
        return "http://\(host):\(draft.listenPort)/-/ping"
    }

    private static func healthCheckCommand(url: String) -> String {
        """
        url=\(shellQuote(url)); \
        for attempt in $(seq 1 8); do curl -fsS --max-time 3 "$url" && exit 0; sleep 2; done; \
        curl -fsS --max-time 5 "$url"
        """
    }

    private static func registryURL(for draft: VerdaccioInstallDraft) -> String {
        let host = draft.listenHost.trimmed == "0.0.0.0" ? "127.0.0.1" : draft.listenHost.trimmed
        return "http://\(host):\(draft.listenPort)"
    }

    private static func parseMarkers(_ output: String) -> [String: String] {
        var markers: [String: String] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("__HHC_VERDACCIO_NPM_"),
                  let range = line.range(of: "__", range: line.index(line.startIndex, offsetBy: 20)..<line.endIndex)
            else { continue }
            let key = String(line[line.index(line.startIndex, offsetBy: 20)..<range.lowerBound])
            let value = String(line[range.upperBound...])
            markers[key] = value
        }
        return markers
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}

final class RegistryPreflightChecker: @unchecked Sendable {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func run(
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> RegistryPreflightReport {
        try VerdaccioConfigurationBuilder.validate(draft)
        let command = Self.preflightCommand(for: draft)
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Registry preflight check failed.")
        }
        return Self.parseReport(result.stdout, capturedAt: now())
    }

    static func parseReport(_ output: String, capturedAt: Date = Date()) -> RegistryPreflightReport {
        let values = markerValues(from: output)
        let nodeVersion = values["NODE_VERSION"]?.nilIfEmpty
        let packageManager = values["PACKAGE_MANAGER"]?.nilIfEmpty
        let diskAvailableKB = Int(values["DISK_AVAILABLE_KB"] ?? "") ?? 0

        let checks = [
            RegistryPreflightCheck(
                id: "node",
                title: "Node.js",
                status: nodeVersion == nil ? .failed : .passed,
                detail: nodeVersion ?? "Node.js was not found.",
                remediation: nodeVersion == nil ? "Install Node.js LTS before installing Verdaccio." : nil
            ),
            RegistryPreflightCheck(
                id: "package_manager",
                title: "Package manager",
                status: packageManager == nil ? .failed : .passed,
                detail: packageManager ?? "npm, pnpm, or yarn was not found.",
                remediation: packageManager == nil ? "Install npm, pnpm, or yarn on the server." : nil
            ),
            RegistryPreflightCheck(
                id: "htpasswd",
                title: "htpasswd",
                status: values["HTPASSWD"] == "yes" ? .passed : .warning,
                detail: values["HTPASSWD"] == "yes" ? "htpasswd is available for Verdaccio user management." : "htpasswd was not found; install and package workflows can continue, but user add/update/delete actions will be unavailable.",
                remediation: values["HTPASSWD"] == "yes" ? nil : "Install apache2-utils, httpd-tools, or the distribution package that provides htpasswd."
            ),
            RegistryPreflightCheck(
                id: "systemd",
                title: "systemd",
                status: values["SYSTEMD"] == "yes" ? .passed : .failed,
                detail: values["SYSTEMD"] == "yes" ? "systemctl is available." : "systemctl was not found.",
                remediation: values["SYSTEMD"] == "yes" ? nil : "Use a systemd-based distribution or add a separate service runner."
            ),
            RegistryPreflightCheck(
                id: "port",
                title: "Listen port",
                status: values["PORT_BUSY"] == "yes" ? .failed : .passed,
                detail: values["PORT_BUSY"] == "yes" ? "The configured listen port is already in use." : "The configured listen port is available.",
                remediation: values["PORT_BUSY"] == "yes" ? "Choose another port or stop the existing service." : nil
            ),
            RegistryPreflightCheck(
                id: "paths",
                title: "Install and data paths",
                status: values["INSTALL_PARENT_WRITABLE"] == "yes" && values["DATA_PARENT_WRITABLE"] == "yes" ? .passed : .failed,
                detail: "Install parent writable: \(values["INSTALL_PARENT_WRITABLE"] ?? "unknown"); data parent writable: \(values["DATA_PARENT_WRITABLE"] ?? "unknown").",
                remediation: values["INSTALL_PARENT_WRITABLE"] == "yes" && values["DATA_PARENT_WRITABLE"] == "yes" ? nil : "Create the parent directories or run with an account that has write permission."
            ),
            RegistryPreflightCheck(
                id: "disk",
                title: "Disk space",
                status: diskAvailableKB >= 524_288 ? .passed : .warning,
                detail: diskAvailableKB > 0 ? "\(diskAvailableKB / 1024) MiB available near the registry data path." : "Could not determine available disk space.",
                remediation: diskAvailableKB >= 524_288 ? nil : "Keep at least 512 MiB free for package storage and cache."
            ),
        ]
        return RegistryPreflightReport(checks: checks, rawOutput: output, capturedAt: capturedAt)
    }

    static func preflightCommand(for draft: VerdaccioInstallDraft) -> String {
        let installPath = shellQuote(draft.installPath.trimmed)
        let dataPath = shellQuote(draft.dataPath.trimmed)
        let port = draft.listenPort
        return """
        install_path=\(installPath); data_path=\(dataPath); port=\(port); \
        install_parent=$(dirname -- "$install_path"); data_parent=$(dirname -- "$data_path"); \
        printf '__HHC_REGISTRY_NODE_VERSION__%s\\n' "$(node --version 2>/dev/null || true)"; \
        if command -v npm >/dev/null 2>&1; then printf '__HHC_REGISTRY_PACKAGE_MANAGER__npm %s\\n' "$(npm --version 2>/dev/null || true)"; elif command -v pnpm >/dev/null 2>&1; then printf '__HHC_REGISTRY_PACKAGE_MANAGER__pnpm %s\\n' "$(pnpm --version 2>/dev/null || true)"; elif command -v yarn >/dev/null 2>&1; then printf '__HHC_REGISTRY_PACKAGE_MANAGER__yarn %s\\n' "$(yarn --version 2>/dev/null || true)"; else printf '__HHC_REGISTRY_PACKAGE_MANAGER__\\n'; fi; \
        command -v htpasswd >/dev/null 2>&1 && printf '__HHC_REGISTRY_HTPASSWD__yes\\n' || printf '__HHC_REGISTRY_HTPASSWD__no\\n'; \
        command -v systemctl >/dev/null 2>&1 && printf '__HHC_REGISTRY_SYSTEMD__yes\\n' || printf '__HHC_REGISTRY_SYSTEMD__no\\n'; \
        if (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null || true) | awk '{print $4}' | grep -Eq "[:.]$port$"; then printf '__HHC_REGISTRY_PORT_BUSY__yes\\n'; else printf '__HHC_REGISTRY_PORT_BUSY__no\\n'; fi; \
        test -d "$install_parent" && test -w "$install_parent" && printf '__HHC_REGISTRY_INSTALL_PARENT_WRITABLE__yes\\n' || printf '__HHC_REGISTRY_INSTALL_PARENT_WRITABLE__no\\n'; \
        test -d "$data_parent" && test -w "$data_parent" && printf '__HHC_REGISTRY_DATA_PARENT_WRITABLE__yes\\n' || printf '__HHC_REGISTRY_DATA_PARENT_WRITABLE__no\\n'; \
        printf '__HHC_REGISTRY_DISK_AVAILABLE_KB__%s\\n' "$(df -Pk "$data_parent" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)"
        """
    }

    private static func markerValues(from output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) where line.hasPrefix("__HHC_REGISTRY_") {
            let keyStart = line.index(line.startIndex, offsetBy: "__HHC_REGISTRY_".count)
            guard let markerEnd = line.range(of: "__", range: keyStart..<line.endIndex) else { continue }
            let key = String(line[keyStart..<markerEnd.lowerBound])
            values[key] = String(line[markerEnd.upperBound...]).trimmed
        }
        return values
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

final class DashboardService: @unchecked Sendable {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func loadSnapshot(
        profile: ServerProfile,
        sshClient: SSHClient,
        cloudMetricService: CloudMetricService? = nil
    ) async throws -> ServerDashboardSnapshot {
        async let osRelease = runDashboardCommand("cat /etc/os-release 2>/dev/null || true", profile: profile, sshClient: sshClient)
        async let kernel = runDashboardCommand("uname -r", profile: profile, sshClient: sshClient)
        async let proc = runDashboardCommand("test -d /proc && echo yes || echo no", profile: profile, sshClient: sshClient)
        async let systemd = runDashboardCommand("command -v systemctl >/dev/null 2>&1 && echo yes || echo no", profile: profile, sshClient: sshClient)
        async let sftp = runDashboardCommand("command -v sftp >/dev/null 2>&1 && echo yes || echo no", profile: profile, sshClient: sshClient)
        async let loadavg = runOptionalDashboardCommand("Load Average", command: "cat /proc/loadavg 2>/dev/null || true", profile: profile, sshClient: sshClient)
        async let meminfo = runOptionalDashboardCommand("Memory", command: "cat /proc/meminfo 2>/dev/null || true", profile: profile, sshClient: sshClient)
        async let disk = runOptionalDashboardCommand("Root Disk", command: "df -kP / 2>/dev/null | tail -1 || true", profile: profile, sshClient: sshClient)
        async let cpu = runOptionalDashboardCommand("CPU Cores", command: "getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 0", profile: profile, sshClient: sshClient)
        async let network = runOptionalDashboardCommand("Network", command: "cat /proc/net/dev 2>/dev/null || true", profile: profile, sshClient: sshClient)
        async let processes = runOptionalDashboardCommand("Processes", command: "ps -eo stat= 2>/dev/null | awk '{total++; state=substr($1,1,1); counts[state]++} END {printf \"total=%d running=%d sleeping=%d stopped=%d zombie=%d\\n\", total, counts[\"R\"], counts[\"S\"] + counts[\"I\"], counts[\"T\"], counts[\"Z\"]}'", profile: profile, sshClient: sshClient)

        let osReleaseResult = try await osRelease
        let os = Self.parseOSRelease(osReleaseResult.stdout)
        let kernelResult = try await kernel
        let procResult = try await proc
        let systemdResult = try await systemd
        let sftpResult = try await sftp
        let optionalResults = await [
            loadavg,
            meminfo,
            disk,
            cpu,
            network,
            processes,
        ]
        var warnings = optionalResults.compactMap(\.warning)

        let detectedAt = now()
        let capabilities = ServerCapabilities(
            osName: os.name,
            osVersion: os.version,
            kernelVersion: kernelResult.stdout.trimmed.nilIfEmpty,
            hasProc: Self.parseYesNo(procResult.stdout),
            hasSystemd: Self.parseYesNo(systemdResult.stdout),
            hasSFTP: Self.parseYesNo(sftpResult.stdout),
            detectedAt: detectedAt
        )

        var metrics: [DashboardMetric] = []
        if let load = Self.parseLoadAverage(optionalResults[0].stdout) {
            metrics.append(DashboardMetric(name: "Load Average", value: load, unit: "1m 5m 15m", source: "SSH"))
        }
        if let memory = Self.parseMemoryUsage(optionalResults[1].stdout) {
            metrics.append(DashboardMetric(name: "Memory", value: memory, unit: nil, source: "SSH"))
        }
        if let disk = Self.parseRootDiskUsage(optionalResults[2].stdout) {
            metrics.append(DashboardMetric(name: "Root Disk", value: disk, unit: nil, source: "SSH"))
        }
        if let cpuCount = Self.parseCPUCount(optionalResults[3].stdout) {
            metrics.append(DashboardMetric(name: "CPU Cores", value: cpuCount, unit: "online", source: "SSH"))
        }
        if let networkSummary = Self.parseNetworkTotals(optionalResults[4].stdout) {
            metrics.append(DashboardMetric(name: "Network", value: networkSummary, unit: "rx / tx", source: "SSH"))
        }
        if let processSummary = Self.parseProcessSummary(optionalResults[5].stdout) {
            metrics.append(DashboardMetric(name: "Processes", value: processSummary, unit: "total / running / zombie", source: "SSH"))
        }
        if let cloudMetricService {
            do {
                metrics.append(contentsOf: try await cloudMetricService.loadMetrics(for: profile))
            } catch {
                warnings.append(DashboardWarning(source: "Cloud API", message: error.localizedDescription))
            }
        }

        return ServerDashboardSnapshot(capabilities: capabilities, metrics: metrics, warnings: warnings, capturedAt: detectedAt)
    }

    private func runDashboardCommand(
        _ command: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> CommandResult {
        try await CloudProviderRequestRunner.withTimeout(8) {
            try await sshClient.execute(command, profile: profile)
        }
    }

    private func runOptionalDashboardCommand(
        _ source: String,
        command: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async -> DashboardCommandOutput {
        do {
            let result = try await runDashboardCommand(command, profile: profile, sshClient: sshClient)
            return DashboardCommandOutput(stdout: result.stdout, warning: nil)
        } catch {
            return DashboardCommandOutput(
                stdout: "",
                warning: DashboardWarning(source: source, message: error.localizedDescription)
            )
        }
    }

    static func parseOSRelease(_ text: String) -> (name: String?, version: String?) {
        let values = Self.parseOSReleaseFields(text)
        let fallbackName = Self.compactOSName(
            name: values["NAME"],
            version: Self.nonEmptyOSReleaseValue(values["VERSION"]) ?? values["VERSION_ID"]
        )
        return (
            Self.nonEmptyOSReleaseValue(values["PRETTY_NAME"]) ?? fallbackName,
            Self.nonEmptyOSReleaseValue(values["VERSION_ID"]) ?? Self.nonEmptyOSReleaseValue(values["VERSION"])
        )
    }

    private static func parseOSReleaseFields(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  !line.hasPrefix("#"),
                  let separatorIndex = line.firstIndex(of: "=")
            else { continue }

            let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { continue }

            let rawValue = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
            values[key] = Self.decodeOSReleaseValue(rawValue)
        }
        return values
    }

    private static func decodeOSReleaseValue(_ rawValue: String) -> String {
        guard rawValue.count >= 2,
              let first = rawValue.first,
              let last = rawValue.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else { return rawValue }

        let body = rawValue.dropFirst().dropLast()
        guard first == "\"" else { return String(body) }

        var decoded = ""
        var isEscaping = false
        for character in body {
            if isEscaping {
                switch character {
                case "\"", "\\", "$", "`":
                    decoded.append(character)
                case "n":
                    decoded.append("\n")
                case "t":
                    decoded.append("\t")
                default:
                    decoded.append(character)
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                decoded.append(character)
            }
        }
        if isEscaping {
            decoded.append("\\")
        }
        return decoded
    }

    private static func compactOSName(name: String?, version: String?) -> String? {
        [Self.nonEmptyOSReleaseValue(name), Self.nonEmptyOSReleaseValue(version)]
            .compactMap(\.self)
            .joined(separator: " ")
            .nilIfEmpty
    }

    private static func nonEmptyOSReleaseValue(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func parseYesNo(_ text: String) -> Bool {
        text.trimmed == "yes"
    }

    static func parseLoadAverage(_ text: String) -> String? {
        let parts = text.split(separator: " ").prefix(3).map(String.init)
        guard parts.count == 3 else { return nil }
        return parts.joined(separator: " / ")
    }

    static func parseMemoryUsage(_ text: String) -> String? {
        var values: [String: Double] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 2 else { continue }
            values[parts[0].trimmingCharacters(in: CharacterSet(charactersIn: ":"))] = Double(parts[1])
        }
        guard let total = values["MemTotal"], total > 0 else { return nil }
        let available = values["MemAvailable"] ?? values["MemFree"] ?? 0
        let used = max(0, total - available)
        return "\(Self.formatKiB(used)) / \(Self.formatKiB(total))"
    }

    static func parseRootDiskUsage(_ text: String) -> String? {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count >= 5, let used = Double(parts[2]), let total = Double(parts[1]) else { return nil }
        return "\(Self.formatKiB(used)) / \(Self.formatKiB(total))"
    }

    static func parseCPUCount(_ text: String) -> String? {
        let value = text.trimmed
        guard Int(value) != nil, value != "0" else { return nil }
        return value
    }

    static func parseNetworkTotals(_ text: String) -> String? {
        var receivedBytes: Double = 0
        var transmittedBytes: Double = 0
        for line in text.split(separator: "\n").map(String.init) {
            guard line.contains(":") else { continue }
            let interfaceAndData = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard interfaceAndData.count == 2 else { continue }
            let interface = interfaceAndData[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard interface != "lo" else { continue }
            let columns = interfaceAndData[1].split(separator: " ").map(String.init)
            guard columns.count >= 16,
                  let received = Double(columns[0]),
                  let transmitted = Double(columns[8])
            else { continue }
            receivedBytes += received
            transmittedBytes += transmitted
        }
        guard receivedBytes > 0 || transmittedBytes > 0 else { return nil }
        return "\(Self.formatBytes(receivedBytes)) / \(Self.formatBytes(transmittedBytes))"
    }

    static func parseProcessSummary(_ text: String) -> String? {
        var values: [String: Int] = [:]
        for pair in text.split(whereSeparator: { $0.isWhitespace }) {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let value = Int(parts[1]) else { continue }
            values[parts[0]] = value
        }
        guard let total = values["total"], total > 0 else { return nil }
        let running = values["running"] ?? 0
        let zombie = values["zombie"] ?? 0
        return "\(total) / \(running) / \(zombie)"
    }

    private static func formatKiB(_ kib: Double) -> String {
        let mib = kib / 1024
        if mib < 1024 {
            return String(format: "%.0f MiB", mib)
        }
        return String(format: "%.1f GiB", mib / 1024)
    }

    private static func formatBytes(_ bytes: Double) -> String {
        if bytes < 1024 {
            return String(format: "%.0f B", bytes)
        }
        let kib = bytes / 1024
        if kib < 1024 {
            return String(format: "%.1f KiB", kib)
        }
        let mib = kib / 1024
        if mib < 1024 {
            return String(format: "%.1f MiB", mib)
        }
        return String(format: "%.1f GiB", mib / 1024)
    }
}

private struct DashboardCommandOutput: Sendable {
    var stdout: String
    var warning: DashboardWarning?
}

final class CloudMetricService: @unchecked Sendable {
    private struct MetricDefinition {
        var queryMetricName: String
        var displayName: String
        var fallbackUnit: String?
    }

    private static let metricDefinitions: [MetricDefinition] = [
        MetricDefinition(queryMetricName: "CPUUsage", displayName: "Cloud CPU", fallbackUnit: "%"),
        MetricDefinition(queryMetricName: "MemoryUsage", displayName: "Cloud Memory", fallbackUnit: "%"),
        MetricDefinition(queryMetricName: "DiskReadBytes", displayName: "Cloud Disk Read", fallbackUnit: "B/s"),
        MetricDefinition(queryMetricName: "DiskWriteBytes", displayName: "Cloud Disk Write", fallbackUnit: "B/s"),
        MetricDefinition(queryMetricName: "NetworkInBytes", displayName: "Cloud Network In", fallbackUnit: "B/s"),
        MetricDefinition(queryMetricName: "NetworkOutBytes", displayName: "Cloud Network Out", fallbackUnit: "B/s"),
    ]

    private let repository: ServerRepository
    private let keychain: KeychainService
    private let registry: CloudProviderRegistry
    private let now: @Sendable () -> Date

    init(
        repository: ServerRepository,
        keychain: KeychainService,
        registry: CloudProviderRegistry,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.keychain = keychain
        self.registry = registry
        self.now = now
    }

    func loadMetrics(for profile: ServerProfile) async throws -> [DashboardMetric] {
        guard let link = try repository.fetchCloudInstanceLinks().first(where: { $0.serverId == profile.id }) else {
            return []
        }
        guard let account = try repository.fetchCloudProviderAccounts().first(where: { $0.id == link.accountId && $0.enabled }) else {
            return []
        }
        try registry.require(.cloudMetrics, providerId: account.providerId)
        guard let credential = try keychain.readCloudCredential(keychainRef: account.keychainRef) else {
            throw CloudProviderError.authenticationFailed("Cloud credential is missing from Keychain.")
        }

        let end = now()
        let start = end.addingTimeInterval(-30 * 60)
        let adapter = try registry.adapter(for: account.providerId)
        var metrics: [DashboardMetric] = []
        var firstError: Error?

        for definition in Self.metricDefinitions {
            do {
                let series = try await adapter.fetchMetricSeries(
                    credential: credential,
                    query: CloudMetricQuery(
                        namespace: "QCE/CVM",
                        metricName: definition.queryMetricName,
                        instanceId: link.instanceId,
                        regionId: link.regionId,
                        period: 300,
                        startTime: start,
                        endTime: end
                    )
                )
                guard let latest = series.values.last else {
                    continue
                }
                metrics.append(DashboardMetric(
                    name: definition.displayName,
                    value: String(format: "%.1f", latest),
                    unit: series.unit ?? definition.fallbackUnit,
                    source: "Cloud API"
                ))
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if metrics.isEmpty, let firstError {
            throw firstError
        }
        return metrics
    }
}

final class CloudSecurityGroupService: @unchecked Sendable {
    private let repository: ServerRepository
    private let keychain: KeychainService
    private let registry: CloudProviderRegistry
    private let now: @Sendable () -> Date

    init(
        repository: ServerRepository,
        keychain: KeychainService,
        registry: CloudProviderRegistry,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.keychain = keychain
        self.registry = registry
        self.now = now
    }

    func loadSecurityGroups(for profile: ServerProfile) async throws -> CloudSecurityGroupList {
        let context = try linkedCloudContext(for: profile)
        let groups: [CloudSecurityGroup]
        do {
            groups = try await registry.adapter(for: context.account.providerId).fetchSecurityGroups(
                credential: context.credential,
                accountId: context.account.id,
                regionId: context.link.regionId
            )
        } catch {
            throw Self.securityGroupAccessError(
                error,
                providerId: context.account.providerId,
                operation: "read security groups",
                requiredPermission: "security group read permissions"
            )
        }
        let filteredGroups = Self.groupsForLinkedInstance(groups, securityGroupIds: context.link.securityGroupIds)
        return CloudSecurityGroupList(
            accountId: context.account.id,
            providerId: context.account.providerId,
            regionId: context.link.regionId,
            instanceId: context.link.instanceId,
            groups: filteredGroups.sorted { left, right in
                left.name.localizedStandardCompare(right.name) == .orderedAscending
            },
            capturedAt: now()
        )
    }

    func loadPolicies(for group: CloudSecurityGroup) async throws -> CloudSecurityGroupPolicySnapshot {
        guard let account = try repository.fetchCloudProviderAccounts().first(where: { $0.id == group.accountId && $0.enabled }) else {
            throw CloudProviderError.authenticationFailed("Linked cloud account is missing or disabled.")
        }
        do {
            try registry.require(.securityGroups, providerId: account.providerId)
        } catch {
            throw Self.securityGroupAccessError(
                error,
                providerId: account.providerId,
                operation: "read security group rules",
                requiredPermission: "security group rule read permissions"
            )
        }
        guard let credential = try keychain.readCloudCredential(keychainRef: account.keychainRef) else {
            throw CloudProviderError.authenticationFailed("Cloud credential is missing from Keychain.")
        }
        do {
            return try await registry.adapter(for: account.providerId).fetchSecurityGroupPolicies(
                credential: credential,
                group: group,
                capturedAt: now()
            )
        } catch {
            throw Self.securityGroupAccessError(
                error,
                providerId: account.providerId,
                operation: "read security group rules",
                requiredPermission: "security group rule read permissions"
            )
        }
    }

    func applyRuleChange(_ preview: CloudSecurityGroupRuleChangePreview) async throws -> CloudSecurityGroupRuleChangeResult {
        guard let account = try repository.fetchCloudProviderAccounts().first(where: { $0.id == preview.group.accountId && $0.enabled }) else {
            throw CloudProviderError.authenticationFailed("Linked cloud account is missing or disabled.")
        }
        do {
            try registry.require(.securityGroupActions, providerId: account.providerId)
        } catch {
            throw Self.securityGroupAccessError(
                error,
                providerId: account.providerId,
                operation: "\(preview.action.displayName.lowercased()) security group rule",
                requiredPermission: "security group rule write permissions"
            )
        }
        guard let credential = try keychain.readCloudCredential(keychainRef: account.keychainRef) else {
            throw CloudProviderError.authenticationFailed("Cloud credential is missing from Keychain.")
        }
        let beforeSnapshot = try await loadPolicies(for: preview.group)
        let requestId: String?
        do {
            requestId = try await registry.adapter(for: account.providerId).applySecurityGroupRuleChange(
                credential: credential,
                preview: preview
            )
        } catch {
            throw Self.securityGroupAccessError(
                error,
                providerId: account.providerId,
                operation: "\(preview.action.displayName.lowercased()) security group rule",
                requiredPermission: "security group rule write permissions"
            )
        }
        let afterSnapshot = try await loadPolicies(for: preview.group)
        return CloudSecurityGroupRuleChangeResult(
            preview: preview,
            requestId: requestId,
            beforeSnapshot: beforeSnapshot,
            afterSnapshot: afterSnapshot,
            capturedAt: now()
        )
    }

    private func linkedCloudContext(for profile: ServerProfile) throws -> (
        link: CloudInstanceLink,
        account: CloudProviderAccount,
        credential: CloudProviderCredential
    ) {
        guard let link = try repository.fetchCloudInstanceLinks().first(where: { $0.serverId == profile.id }) else {
            throw CloudProviderError.providerFailure("This server is not linked to a cloud instance.")
        }
        guard let account = try repository.fetchCloudProviderAccounts().first(where: { $0.id == link.accountId && $0.enabled }) else {
            throw CloudProviderError.authenticationFailed("Linked cloud account is missing or disabled.")
        }
        do {
            try registry.require(.securityGroups, providerId: account.providerId)
        } catch {
            throw Self.securityGroupAccessError(
                error,
                providerId: account.providerId,
                operation: "read security groups",
                requiredPermission: "security group read permissions"
            )
        }
        guard let credential = try keychain.readCloudCredential(keychainRef: account.keychainRef) else {
            throw CloudProviderError.authenticationFailed("Cloud credential is missing from Keychain.")
        }
        return (link, account, credential)
    }

    private static func groupsForLinkedInstance(
        _ groups: [CloudSecurityGroup],
        securityGroupIds: [String]
    ) -> [CloudSecurityGroup] {
        let linkedIds = Set(securityGroupIds.filter { !$0.isEmpty })
        guard !linkedIds.isEmpty else {
            return groups
        }
        return groups.filter { linkedIds.contains($0.securityGroupId) }
    }

    private static func securityGroupAccessError(
        _ error: Error,
        providerId: CloudProviderID,
        operation: String,
        requiredPermission: String
    ) -> Error {
        let guidance = "\(providerId.displayName) could not \(operation). Grant \(requiredPermission) to this cloud account, then retry."
        if let cloudError = error as? CloudProviderError {
            switch cloudError {
            case let .permissionDenied(message):
                return CloudProviderError.permissionDenied("\(guidance) Provider message: \(message)")
            case let .unsupportedCapability(_, capability):
                return CloudProviderError.permissionDenied("\(guidance) Adapter capability \(capability.rawValue) is not available.")
            default:
                return cloudError
            }
        }
        return CloudProviderError.permissionDenied("\(guidance) Provider message: \(error.localizedDescription)")
    }
}

final class SystemdServiceManager: @unchecked Sendable {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func listUnits(profile: ServerProfile, sshClient: SSHClient) async throws -> SystemdUnitList {
        let command = """
        command -v systemctl >/dev/null 2>&1 || exit 3; \
        systemctl list-units --type=service --all --no-legend --no-pager --plain | \
        awk '{unit=$1; load=$2; active=$3; substate=$4; $1=$2=$3=$4=""; sub(/^ +/, ""); print unit "\\t" load "\\t" active "\\t" substate "\\t" $0}'
        """
        let result = try await CloudProviderRequestRunner.withTimeout(12) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            if result.exitCode == 3 {
                throw SSHClientError.processFailed("systemd is not available on this server.")
            }
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not list systemd services.")
        }
        return SystemdUnitList(units: Self.parseUnitList(result.stdout), capturedAt: now())
    }

    func perform(
        _ action: SystemdUnitAction,
        unitName: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws {
        let unit = try Self.validatedUnitName(unitName)
        let command = "systemctl \(action.rawValue) -- \(Self.shellQuote(unit))"
        let result = try await CloudProviderRequestRunner.withTimeout(20) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not \(action.rawValue) \(unit).")
        }
    }

    func readJournal(
        unitName: String,
        limit: Int = 120,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> SystemdJournalLog {
        let unit = try Self.validatedUnitName(unitName)
        let clampedLimit = min(max(limit, 20), 500)
        let command = "journalctl -u \(Self.shellQuote(unit)) -n \(clampedLimit) --no-pager --output=short-iso"
        let result = try await CloudProviderRequestRunner.withTimeout(12) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not read journal for \(unit).")
        }
        return SystemdJournalLog(unitName: unit, text: result.stdout, capturedAt: now())
    }

    static func parseUnitList(_ text: String) -> [SystemdUnit] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { return nil }
            return SystemdUnit(
                name: parts[0],
                loadState: parts[1],
                activeState: parts[2],
                subState: parts[3],
                description: parts[4].trimmed
            )
        }
        .sorted { left, right in
            if left.isRunning, !right.isRunning { return true }
            if !left.isRunning, right.isRunning { return false }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    static func validatedUnitName(_ unitName: String) throws -> String {
        let trimmed = unitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Za-z0-9:_.@-]+\.service$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            throw SSHClientError.processFailed("Only simple .service unit names are supported.")
        }
        return trimmed
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

final class CronManager: @unchecked Sendable {
    static let disabledPrefix = "# HHC_DISABLED "

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func load(profile: ServerProfile, sshClient: SSHClient) async throws -> CronTabSnapshot {
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute("crontab -l 2>/dev/null || true", profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not read crontab.")
        }
        return CronTabSnapshot(entries: Self.parse(result.stdout), rawText: result.stdout, capturedAt: now())
    }

    func add(
        schedule: String,
        command: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws {
        let normalizedLine = try Self.makeEntryLine(schedule: schedule, command: command)
        let snapshot = try await load(profile: profile, sshClient: sshClient)
        var lines = Self.normalizedLines(snapshot.rawText)
        lines.append(normalizedLine)
        try await install(lines: lines, profile: profile, sshClient: sshClient)
    }

    func perform(
        _ action: CronEntryAction,
        entry: CronEntry,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws {
        let snapshot = try await load(profile: profile, sshClient: sshClient)
        let lines = Self.normalizedLines(snapshot.rawText)
        guard let index = lines.firstIndex(of: entry.originalLine) else {
            throw SSHClientError.processFailed("Cron entry no longer exists.")
        }
        var updated = lines
        switch action {
        case .enable:
            guard !entry.isEnabled else { return }
            updated[index] = String(entry.originalLine.dropFirst(Self.disabledPrefix.count))
        case .disable:
            guard entry.isEnabled else { return }
            updated[index] = "\(Self.disabledPrefix)\(entry.originalLine)"
        case .delete:
            updated.remove(at: index)
        }
        try await install(lines: updated, profile: profile, sshClient: sshClient)
    }

    static func parse(_ text: String) -> [CronEntry] {
        normalizedLines(text).compactMap { line in
            parseLine(line)
        }
    }

    static func makeEntryLine(schedule: String, command: String) throws -> String {
        let normalizedSchedule = schedule.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCommand.isEmpty else {
            throw SSHClientError.processFailed("Cron command cannot be empty.")
        }
        guard !normalizedCommand.contains("\n") && !normalizedCommand.contains("\r") else {
            throw SSHClientError.processFailed("Cron command must be a single line.")
        }
        guard isValidSchedule(normalizedSchedule) else {
            throw SSHClientError.processFailed("Cron schedule must contain exactly five fields.")
        }
        return "\(normalizedSchedule) \(normalizedCommand)"
    }

    private func install(lines: [String], profile: ServerProfile, sshClient: SSHClient) async throws {
        let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        let encoded = Data(content.utf8).base64EncodedString()
        let backupPath = "~/.hhc-crontab-backup-\(Self.timestamp(for: now()))"
        let command = """
        set -e; \
        crontab -l > \(Self.shellQuote(backupPath)) 2>/dev/null || true; \
        base64 -d <<'__HHC_CRON_EOF__' | crontab -
        \(encoded)
        __HHC_CRON_EOF__
        """
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not install crontab.")
        }
    }

    private static func parseLine(_ line: String) -> CronEntry? {
        let isDisabled = line.hasPrefix(disabledPrefix)
        let activeLine = isDisabled ? String(line.dropFirst(disabledPrefix.count)) : line
        guard !activeLine.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") else { return nil }
        let parts = activeLine.split(maxSplits: 5, whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count == 6 else { return nil }
        let schedule = parts.prefix(5).joined(separator: " ")
        return CronEntry(
            schedule: schedule,
            command: parts[5],
            isEnabled: !isDisabled,
            originalLine: line
        )
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isValidSchedule(_ schedule: String) -> Bool {
        schedule.split(whereSeparator: { $0.isWhitespace }).count == 5
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}

final class NginxConfigManager: @unchecked Sendable {
    static let maxConfigBytes = 512 * 1024

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func listConfigs(profile: ServerProfile, sshClient: SSHClient) async throws -> NginxConfigList {
        let command = """
        command -v nginx >/dev/null 2>&1 || exit 3; \
        info=$(nginx -V 2>&1 || true); \
        prefix=$(printf '%s' "$info" | tr ' ' '\\n' | sed -n 's/^--prefix=//p' | tail -n 1); \
        conf=$(printf '%s' "$info" | tr ' ' '\\n' | sed -n 's/^--conf-path=//p' | tail -n 1); \
        if [ -z "$conf" ] && [ -n "$prefix" ]; then conf="$prefix/conf/nginx.conf"; fi; \
        { [ -n "$conf" ] && dirname "$conf"; [ -n "$prefix" ] && printf '%s/conf\\n' "$prefix"; printf '%s\\n' /etc/nginx /usr/local/nginx/conf /opt/nginx/conf; } | \
        awk 'NF && !seen[$0]++' | while IFS= read -r dir; do \
        [ -d "$dir" ] && find "$dir" -type f -name '*.conf' -printf '%p\\t%s\\t%T@\\n' 2>/dev/null; \
        done | sort
        """
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            if result.exitCode == 3 {
                throw SSHClientError.processFailed("Nginx is not available on this server.")
            }
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not list Nginx configs.")
        }
        return NginxConfigList(files: Self.parseConfigListing(result.stdout), capturedAt: now())
    }

    func readConfig(
        file: NginxConfigFile,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> NginxConfigContent {
        let path = try Self.validatedConfigPath(file.path)
        if let size = file.size, size > Self.maxConfigBytes {
            throw SSHClientError.processFailed("Nginx config is larger than the editable preview limit.")
        }
        let command = """
        bytes=$(wc -c < \(Self.shellQuote(path)) 2>/dev/null | tr -d '[:space:]' || echo 0); \
        if [ "$bytes" -gt \(Self.maxConfigBytes) ]; then echo "__HHC_NGINX_CONFIG_TOO_LARGE__$bytes"; exit 3; fi; \
        base64 < \(Self.shellQuote(path))
        """
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            if result.exitCode == 3 {
                throw SSHClientError.processFailed("Nginx config is larger than the editable preview limit.")
            }
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not read \(path).")
        }
        let encoded = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: encoded),
              let content = String(data: data, encoding: .utf8)
        else {
            throw SSHClientError.processFailed("Nginx config is not valid UTF-8 text.")
        }
        return NginxConfigContent(
            file: file,
            content: content,
            byteCount: data.count,
            capturedAt: now()
        )
    }

    func testConfig(profile: ServerProfile, sshClient: SSHClient) async throws -> NginxTestResult {
        let result = try await CloudProviderRequestRunner.withTimeout(12) {
            try await sshClient.execute("nginx -t", profile: profile)
        }
        return NginxTestResult(
            succeeded: result.exitCode == 0,
            output: Self.combinedOutput(result),
            capturedAt: now()
        )
    }

    func saveConfig(
        file: NginxConfigFile,
        content: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> NginxConfigSaveResult {
        let path = try Self.validatedConfigPath(file.path)
        let data = Data(content.utf8)
        guard data.count <= Self.maxConfigBytes else {
            throw SSHClientError.processFailed("Nginx config is larger than the editable preview limit.")
        }
        let backupPath = "\(path).hhc-backup-\(Self.timestamp(for: now()))"
        let encoded = data.base64EncodedString()
        let command = """
        set -e; \
        path=\(Self.shellQuote(path)); \
        backup=\(Self.shellQuote(backupPath)); \
        tmp=$(mktemp "$path.hhc-tmp.XXXXXX"); \
        cleanup() { rm -f "$tmp"; }; \
        trap cleanup EXIT; \
        cp -p -- "$path" "$backup"; \
        base64 -d > "$tmp" <<'__HHC_NGINX_CONFIG_EOF__'
        \(encoded)
        __HHC_NGINX_CONFIG_EOF__
        chmod --reference="$path" "$tmp" 2>/dev/null || true; \
        chown --reference="$path" "$tmp" 2>/dev/null || true; \
        mv -- "$tmp" "$path"; \
        if nginx -t > /tmp/hhc-nginx-test-$$.log 2>&1; then \
        cat /tmp/hhc-nginx-test-$$.log; rm -f /tmp/hhc-nginx-test-$$.log; exit 0; \
        else \
        status=$?; cat /tmp/hhc-nginx-test-$$.log; rm -f /tmp/hhc-nginx-test-$$.log; cp -p -- "$backup" "$path"; exit 4; \
        fi
        """
        let result = try await CloudProviderRequestRunner.withTimeout(15) {
            try await sshClient.execute(command, profile: profile)
        }
        let testResult = NginxTestResult(
            succeeded: result.exitCode == 0,
            output: Self.combinedOutput(result),
            capturedAt: now()
        )
        if result.exitCode == 0 || result.exitCode == 4 {
            return NginxConfigSaveResult(
                file: file,
                content: content,
                backupPath: backupPath,
                testResult: testResult,
                rolledBack: result.exitCode == 4,
                capturedAt: now()
            )
        }
        throw SSHClientError.processFailed(Self.combinedOutput(result).nilIfEmpty ?? "Could not save \(path).")
    }

    func upsertConfig(
        path: String,
        content: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> NginxConfigUpsertResult {
        let path = try Self.validatedConfigPath(path)
        let data = Data(content.utf8)
        guard data.count <= Self.maxConfigBytes else {
            throw SSHClientError.processFailed("Nginx config is larger than the editable preview limit.")
        }
        let backupPath = "\(path).hhc-backup-\(Self.timestamp(for: now()))"
        let encoded = data.base64EncodedString()
        let command = """
        set -e; \
        path=\(Self.shellQuote(path)); \
        backup=\(Self.shellQuote(backupPath)); \
        parent=$(dirname -- "$path"); \
        tmp=$(mktemp "$path.hhc-tmp.XXXXXX"); \
        cleanup() { rm -f "$tmp"; }; \
        trap cleanup EXIT; \
        install -d -m 0755 "$parent"; \
        if [ -f "$path" ]; then created_new=0; cp -p -- "$path" "$backup"; else created_new=1; backup=""; fi; \
        printf '__HHC_NGINX_CREATED__%s\\n' "$created_new"; \
        printf '__HHC_NGINX_BACKUP__%s\\n' "$backup"; \
        base64 -d > "$tmp" <<'__HHC_NGINX_CONFIG_EOF__'
        \(encoded)
        __HHC_NGINX_CONFIG_EOF__
        if [ -f "$path" ]; then chmod --reference="$path" "$tmp" 2>/dev/null || true; chown --reference="$path" "$tmp" 2>/dev/null || true; else chmod 0644 "$tmp"; fi; \
        mv -- "$tmp" "$path"; \
        if nginx -t > /tmp/hhc-nginx-test-$$.log 2>&1; then \
        cat /tmp/hhc-nginx-test-$$.log; rm -f /tmp/hhc-nginx-test-$$.log; exit 0; \
        else \
        status=$?; cat /tmp/hhc-nginx-test-$$.log; rm -f /tmp/hhc-nginx-test-$$.log; if [ "$created_new" = "1" ]; then rm -f -- "$path"; else cp -p -- "$backup" "$path"; fi; exit 4; \
        fi
        """
        let result = try await CloudProviderRequestRunner.withTimeout(15) {
            try await sshClient.execute(command, profile: profile)
        }
        let testResult = NginxTestResult(
            succeeded: result.exitCode == 0,
            output: Self.combinedOutput(result),
            capturedAt: now()
        )
        if result.exitCode == 0 || result.exitCode == 4 {
            let createdNewFile = result.stdout.contains("__HHC_NGINX_CREATED__1")
            let backup = Self.markerValue("__HHC_NGINX_BACKUP__", from: result.stdout)
            return NginxConfigUpsertResult(
                file: NginxConfigFile(path: path, size: Int64(data.count), modifiedAt: now()),
                content: content,
                backupPath: backup?.nilIfEmpty,
                testResult: testResult,
                createdNewFile: createdNewFile,
                rolledBack: result.exitCode == 4,
                capturedAt: now()
            )
        }
        throw SSHClientError.processFailed(Self.combinedOutput(result).nilIfEmpty ?? "Could not save \(path).")
    }

    func reload(profile: ServerProfile, sshClient: SSHClient) async throws -> NginxTestResult {
        let test = try await testConfig(profile: profile, sshClient: sshClient)
        guard test.succeeded else {
            throw SSHClientError.processFailed(test.output.nilIfEmpty ?? "nginx -t failed.")
        }
        let command = "systemctl reload nginx 2>/dev/null || nginx -s reload"
        let result = try await CloudProviderRequestRunner.withTimeout(15) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.combinedOutput(result).nilIfEmpty ?? "Could not reload Nginx.")
        }
        return test
    }

    static func parseConfigListing(_ text: String) -> [NginxConfigFile] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let path = parts.first,
                  (try? validatedConfigPath(path)) != nil
            else { return nil }
            let size = parts.indices.contains(1) ? Int64(parts[1]) : nil
            let modifiedAt = parts.indices.contains(2)
                ? Double(parts[2]).map { Date(timeIntervalSince1970: $0) }
                : nil
            return NginxConfigFile(path: path, size: size, modifiedAt: modifiedAt)
        }
        .sorted { left, right in
            left.path.localizedStandardCompare(right.path) == .orderedAscending
        }
    }

    static func validatedConfigPath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              !trimmed.contains("\n"),
              !trimmed.contains("\r"),
              !trimmed.contains("/../"),
              !trimmed.hasSuffix("/.."),
              trimmed.hasSuffix(".conf"),
              trimmed.contains("/nginx/")
        else {
            throw SSHClientError.processFailed("Only Nginx configuration paths are supported.")
        }
        return trimmed
    }

    private static func combinedOutput(_ result: CommandResult) -> String {
        [result.stdout.trimmed, result.stderr.trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func markerValue(_ marker: String, from output: String) -> String? {
        output.components(separatedBy: .newlines)
            .first { $0.hasPrefix(marker) }
            .map { String($0.dropFirst(marker.count)).trimmed }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}

final class FirewallManager: @unchecked Sendable {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func loadSnapshot(profile: ServerProfile, sshClient: SSHClient) async throws -> FirewallSnapshot {
        let command = """
        if command -v firewall-cmd >/dev/null 2>&1; then \
        printf '__HHC_FIREWALL_BACKEND__\\nfirewalld\\n__HHC_FIREWALL_STATUS__\\n'; \
        firewall-cmd --state 2>&1 || true; \
        printf '__HHC_FIREWALL_RULES__\\n'; \
        firewall-cmd --list-all-zones 2>&1 || true; \
        elif command -v ufw >/dev/null 2>&1; then \
        printf '__HHC_FIREWALL_BACKEND__\\nufw\\n__HHC_FIREWALL_STATUS__\\n'; \
        ufw status 2>&1 | sed -n '1p'; \
        printf '__HHC_FIREWALL_RULES__\\n'; \
        ufw status verbose 2>&1 || true; \
        elif command -v nft >/dev/null 2>&1; then \
        printf '__HHC_FIREWALL_BACKEND__\\nnft\\n__HHC_FIREWALL_STATUS__\\ninstalled\\n__HHC_FIREWALL_RULES__\\n'; \
        nft list ruleset 2>&1 || true; \
        elif command -v iptables >/dev/null 2>&1; then \
        printf '__HHC_FIREWALL_BACKEND__\\niptables\\n__HHC_FIREWALL_STATUS__\\ninstalled\\n__HHC_FIREWALL_RULES__\\n'; \
        iptables -S 2>&1 || true; \
        else exit 3; fi
        """
        let result = try await CloudProviderRequestRunner.withTimeout(12) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            if result.exitCode == 3 {
                throw SSHClientError.processFailed("No supported firewall backend was found.")
            }
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not read firewall rules.")
        }
        return try Self.parseSnapshot(result.stdout, capturedAt: now())
    }

    func applyRule(
        _ draft: FirewallRuleDraft,
        snapshot: FirewallSnapshot,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> FirewallRuleMutationResult {
        let command = try Self.command(for: draft, snapshot: snapshot)
        let result = try await CloudProviderRequestRunner.withTimeout(20) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? result.stdout.nilIfEmpty ?? "Firewall rule update failed.")
        }
        let refreshed = try await loadSnapshot(profile: profile, sshClient: sshClient)
        return FirewallRuleMutationResult(
            draft: draft,
            command: command,
            beforeSnapshot: snapshot,
            afterSnapshot: refreshed,
            result: result
        )
    }

    static func command(for draft: FirewallRuleDraft, backend: FirewallBackend) throws -> String {
        try validate(draft)
        switch backend {
        case .firewalld:
            guard draft.direction == .ingress else {
                throw SSHClientError.processFailed("firewalld egress rules are not supported by the limited rule editor.")
            }
            let verb = draft.mutation == .add ? "--add-rich-rule" : "--remove-rich-rule"
            let ruleAction = draft.action == .allow ? "accept" : "drop"
            let richRule = "rule family=\"ipv4\" source address=\"\(draft.cidr)\" port protocol=\"\(draft.proto.rawValue)\" port=\"\(draft.port)\" \(ruleAction)"
            return "firewall-cmd --permanent \(verb)=\(shellQuote(richRule)) && firewall-cmd --reload"
        case .ufw:
            let mutation = draft.mutation == .add ? "" : "delete "
            let direction = draft.direction == .ingress ? "in" : "out"
            let action = draft.action == .allow ? "allow" : "deny"
            let endpoint = draft.direction == .ingress
                ? "from \(shellQuote(draft.cidr)) to any port \(draft.port)"
                : "to \(shellQuote(draft.cidr)) port \(draft.port)"
            return "ufw \(mutation)\(action) \(direction) proto \(draft.proto.rawValue) \(endpoint)"
        case .iptables:
            let operation = draft.mutation == .add ? "-A" : "-D"
            let chain = draft.direction == .ingress ? "INPUT" : "OUTPUT"
            let jump = draft.action == .allow ? "ACCEPT" : "DROP"
            let cidrFlag = draft.direction == .ingress ? "-s" : "-d"
            return "iptables \(operation) \(chain) -p \(draft.proto.rawValue) \(cidrFlag) \(shellQuote(draft.cidr)) --dport \(draft.port) -j \(jump)"
        case .nft:
            throw SSHClientError.processFailed("Refresh nftables rules before editing so an existing table and chain can be selected.")
        }
    }

    static func command(for draft: FirewallRuleDraft, snapshot: FirewallSnapshot) throws -> String {
        try validate(draft)
        guard snapshot.backend == .nft else {
            return try command(for: draft, backend: snapshot.backend)
        }
        let target = try nftTarget(for: draft.direction, rulesText: snapshot.rulesText)
        let marker = nftMarker(for: draft)
        let addressFlag = draft.direction == .ingress ? "saddr" : "daddr"
        let nftAction = draft.action == .allow ? "accept" : "drop"
        let chainCommand = "\(target.family) \(shellQuote(target.table)) \(shellQuote(target.chain))"
        switch draft.mutation {
        case .add:
            return "nft add rule \(chainCommand) ip \(addressFlag) \(shellQuote(draft.cidr)) \(draft.proto.rawValue) dport \(draft.port) counter \(nftAction) comment \(shellQuote(marker))"
        case .delete:
            return """
            set -e; marker=\(shellQuote(marker)); handle=$(nft -a list chain \(chainCommand) | awk -v marker="$marker" 'index($0, "comment " sprintf("%c", 34) marker sprintf("%c", 34)) { print $NF; exit }'); \
            if [ -z "$handle" ]; then echo "No HHC-managed nftables rule found for $marker" >&2; exit 4; fi; \
            nft delete rule \(chainCommand) handle "$handle"
            """
        }
    }

    static func parseSnapshot(_ text: String, capturedAt: Date) throws -> FirewallSnapshot {
        guard let backendText = section("__HHC_FIREWALL_BACKEND__", in: text).firstLine,
              let backend = FirewallBackend(rawValue: backendText.trimmed)
        else {
            throw SSHClientError.processFailed("Could not parse firewall backend.")
        }
        let status = section("__HHC_FIREWALL_STATUS__", in: text)
            .trimmed
            .nilIfEmpty ?? "unknown"
        let rules = section("__HHC_FIREWALL_RULES__", in: text)
            .trimmed
            .nilIfEmpty ?? "(empty)"
        return FirewallSnapshot(
            backend: backend,
            status: status,
            rulesText: rules,
            capturedAt: capturedAt
        )
    }

    private static func section(_ marker: String, in text: String) -> String {
        guard let start = text.range(of: "\(marker)\n") else { return "" }
        let remaining = text[start.upperBound...]
        if let end = remaining.range(of: "\n__HHC_FIREWALL_") {
            return String(remaining[..<end.lowerBound])
        }
        return String(remaining)
    }

    private static func validate(_ draft: FirewallRuleDraft) throws {
        guard (1...65_535).contains(draft.port) else {
            throw SSHClientError.processFailed("Firewall port must be between 1 and 65535.")
        }
        guard isValidIPv4CIDR(draft.cidr) else {
            throw SSHClientError.processFailed("Firewall CIDR must be an IPv4 CIDR such as 203.0.113.0/24.")
        }
    }

    private static func isValidIPv4CIDR(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              (0...32).contains(prefix)
        else {
            return false
        }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard let number = Int(octet), (0...255).contains(number) else { return false }
            return String(number) == String(octet)
        }
    }

    private struct NftTarget: Equatable {
        var family: String
        var table: String
        var chain: String
    }

    private static func nftTarget(for direction: FirewallRuleDirection, rulesText: String) throws -> NftTarget {
        let hook = direction == .ingress ? "input" : "output"
        var currentTable: (family: String, name: String)?
        var currentChain: String?
        let normalized = rulesText
            .replacingOccurrences(of: "{", with: " {\n")
            .replacingOccurrences(of: "}", with: "\n}\n")
            .replacingOccurrences(of: ";", with: ";\n")

        for rawLine in normalized.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)

            if parts.first == "table", parts.count >= 4 {
                let family = parts[1]
                let table = unquotedNftName(parts[2])
                if ["inet", "ip"].contains(family), isSafeNftIdentifier(table) {
                    currentTable = (family, table)
                } else {
                    currentTable = nil
                }
                currentChain = nil
                continue
            }

            if line == "}" {
                if currentChain != nil {
                    currentChain = nil
                } else {
                    currentTable = nil
                }
                continue
            }

            guard let table = currentTable else { continue }
            if parts.first == "chain", parts.count >= 3 {
                let chain = unquotedNftName(parts[1])
                currentChain = isSafeNftIdentifier(chain) ? chain : nil
                continue
            }

            guard let chain = currentChain else { continue }
            if line.contains("type filter"),
               line.contains("hook \(hook)"),
               !line.contains("hook \(hook)dev") {
                return NftTarget(family: table.family, table: table.name, chain: chain)
            }
        }

        throw SSHClientError.processFailed("No compatible nftables \(hook) chain was found. HHC only edits existing inet/ip filter chains.")
    }

    private static func nftMarker(for draft: FirewallRuleDraft) -> String {
        "hhc:\(draft.direction.rawValue):\(draft.action.rawValue):\(draft.proto.rawValue):\(draft.port):\(draft.cidr)"
    }

    private static func unquotedNftName(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'{};"))
    }

    private static func isSafeNftIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

final class EnvironmentFileManager: @unchecked Sendable {
    static let maxEditableBytes = 256 * 1024

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func listFiles(profile: ServerProfile, sshClient: SSHClient) async throws -> EnvironmentFileList {
        let command = """
        { \
        home=${HOME:-}; \
        if [ -n "$home" ] && [ -d "$home" ]; then \
        find "$home" -maxdepth 3 -type f -name '.env' -printf '%p\\t%s\\t%T@\\tuser\\n' 2>/dev/null; \
        find "$home" -maxdepth 3 -type f -name '*.env' -printf '%p\\t%s\\t%T@\\tuser\\n' 2>/dev/null; \
        fi; \
        if [ -d /var/www ]; then \
        find /var/www -maxdepth 4 -type f -name '.env' -printf '%p\\t%s\\t%T@\\tapp\\n' 2>/dev/null; \
        find /var/www -maxdepth 4 -type f -name '*.env' -printf '%p\\t%s\\t%T@\\tapp\\n' 2>/dev/null; \
        fi; \
        if [ -d /opt ]; then \
        find /opt -maxdepth 4 -type f -name '.env' -printf '%p\\t%s\\t%T@\\tapp\\n' 2>/dev/null; \
        find /opt -maxdepth 4 -type f -name '*.env' -printf '%p\\t%s\\t%T@\\tapp\\n' 2>/dev/null; \
        fi; \
        if [ -d /srv ]; then \
        find /srv -maxdepth 4 -type f -name '.env' -printf '%p\\t%s\\t%T@\\tapp\\n' 2>/dev/null; \
        find /srv -maxdepth 4 -type f -name '*.env' -printf '%p\\t%s\\t%T@\\tapp\\n' 2>/dev/null; \
        fi; \
        [ -d /etc/default ] && find /etc/default -maxdepth 1 -type f -printf '%p\\t%s\\t%T@\\tos\\n' 2>/dev/null; \
        [ -d /etc/sysconfig ] && find /etc/sysconfig -maxdepth 1 -type f -printf '%p\\t%s\\t%T@\\tos\\n' 2>/dev/null; \
        [ -d /etc/systemd/system ] && find /etc/systemd/system -path '*.service.d/*.conf' -type f -printf '%p\\t%s\\t%T@\\tsystemd\\n' 2>/dev/null; \
        } | sort -u
        """
        let result = try await CloudProviderRequestRunner.withTimeout(12) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not list environment files.")
        }
        return EnvironmentFileList(files: Self.parseFileListing(result.stdout), capturedAt: now())
    }

    func readFile(
        file: EnvironmentFile,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> EnvironmentFileContent {
        let path = try Self.validatedEnvironmentPath(file.path)
        if let size = file.size, size > Self.maxEditableBytes {
            throw SSHClientError.processFailed("Environment file is larger than the editable preview limit.")
        }
        let command = """
        bytes=$(wc -c < \(Self.shellQuote(path)) 2>/dev/null | tr -d '[:space:]' || echo 0); \
        if [ "$bytes" -gt \(Self.maxEditableBytes) ]; then echo "__HHC_ENV_FILE_TOO_LARGE__$bytes"; exit 3; fi; \
        base64 < \(Self.shellQuote(path))
        """
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            if result.exitCode == 3 {
                throw SSHClientError.processFailed("Environment file is larger than the editable preview limit.")
            }
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not read \(path).")
        }
        let encoded = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: encoded),
              let content = String(data: data, encoding: .utf8)
        else {
            throw SSHClientError.processFailed("Environment file is not valid UTF-8 text.")
        }
        return EnvironmentFileContent(file: file, content: content, byteCount: data.count, capturedAt: now())
    }

    func saveFile(
        file: EnvironmentFile,
        content: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> EnvironmentFileSaveResult {
        let path = try Self.validatedEnvironmentPath(file.path)
        let data = Data(content.utf8)
        guard data.count <= Self.maxEditableBytes else {
            throw SSHClientError.processFailed("Environment file is larger than the editable preview limit.")
        }
        let backupPath = "\(path).hhc-backup-\(Self.timestamp(for: now()))"
        let encoded = data.base64EncodedString()
        let command = """
        set -e; \
        path=\(Self.shellQuote(path)); \
        backup=\(Self.shellQuote(backupPath)); \
        tmp=$(mktemp "$path.hhc-tmp.XXXXXX"); \
        cleanup() { rm -f "$tmp"; }; \
        trap cleanup EXIT; \
        cp -p -- "$path" "$backup"; \
        base64 -d > "$tmp" <<'__HHC_ENV_FILE_EOF__'
        \(encoded)
        __HHC_ENV_FILE_EOF__
        chmod --reference="$path" "$tmp" 2>/dev/null || true; \
        chown --reference="$path" "$tmp" 2>/dev/null || true; \
        mv -- "$tmp" "$path"
        """
        let result = try await CloudProviderRequestRunner.withTimeout(12) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.combinedOutput(result).nilIfEmpty ?? "Could not save \(path).")
        }
        return EnvironmentFileSaveResult(file: file, content: content, backupPath: backupPath, capturedAt: now())
    }

    static func parseFileListing(_ text: String) -> [EnvironmentFile] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let path = parts.first,
                  (try? validatedEnvironmentPath(path)) != nil
            else { return nil }
            let size = parts.indices.contains(1) ? Int64(parts[1]) : nil
            let modifiedAt = parts.indices.contains(2)
                ? Double(parts[2]).map { Date(timeIntervalSince1970: $0) }
                : nil
            let source = parts.indices.contains(3) && !parts[3].isEmpty ? parts[3] : source(for: path)
            return EnvironmentFile(path: path, size: size, modifiedAt: modifiedAt, source: source)
        }
        .reduce(into: [String: EnvironmentFile]()) { files, file in
            files[file.path] = file
        }
        .values
        .sorted { left, right in
            left.path.localizedStandardCompare(right.path) == .orderedAscending
        }
    }

    static func validatedEnvironmentPath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              !trimmed.contains("\n"),
              !trimmed.contains("\r"),
              !trimmed.contains("/../"),
              !trimmed.hasSuffix("/..")
        else {
            throw SSHClientError.processFailed("Only supported environment file paths are allowed.")
        }

        let isDotEnv = (trimmed.hasSuffix("/.env") || trimmed.hasSuffix(".env"))
            && (trimmed.hasPrefix("/home/") || trimmed.hasPrefix("/root/") || trimmed.hasPrefix("/var/www/") || trimmed.hasPrefix("/opt/") || trimmed.hasPrefix("/srv/"))
        let isEtcDefault = trimmed.hasPrefix("/etc/default/") && trimmed.dropFirst("/etc/default/".count).contains("/") == false
        let isEtcSysconfig = trimmed.hasPrefix("/etc/sysconfig/") && trimmed.dropFirst("/etc/sysconfig/".count).contains("/") == false
        let isSystemdDropIn = trimmed.hasPrefix("/etc/systemd/system/")
            && trimmed.contains(".service.d/")
            && trimmed.hasSuffix(".conf")
        guard isDotEnv || isEtcDefault || isEtcSysconfig || isSystemdDropIn else {
            throw SSHClientError.processFailed("Only supported environment file paths are allowed.")
        }
        return trimmed
    }

    private static func source(for path: String) -> String {
        if path.hasPrefix("/etc/systemd/system/") {
            return "systemd"
        }
        if path.hasPrefix("/etc/default/") || path.hasPrefix("/etc/sysconfig/") {
            return "os"
        }
        if path.hasPrefix("/var/www/") || path.hasPrefix("/opt/") {
            return "app"
        }
        return "user"
    }

    private static func combinedOutput(_ result: CommandResult) -> String {
        [result.stdout.trimmed, result.stderr.trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}

final class RemoteFileService: @unchecked Sendable {
    static let maxEditableTextBytes = 256 * 1024

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func listDirectory(
        path: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> RemoteDirectoryListing {
        let normalizedPath = Self.normalizedDirectoryPath(path)
        let command = """
        cd -- \(Self.shellQuote(normalizedPath)) && find . -maxdepth 1 -mindepth 1 -printf '%f\\t%y\\t%s\\t%T@\\t%M\\n' 2>/dev/null | sort
        """
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not list \(normalizedPath).")
        }
        return RemoteDirectoryListing(
            path: normalizedPath,
            entries: Self.parseFindListing(result.stdout, basePath: normalizedPath),
            capturedAt: now()
        )
    }

    func rename(
        entry: RemoteFileEntry,
        to newName: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws {
        let targetName = Self.validatedFileName(newName)
        guard !targetName.isEmpty else {
            throw SSHClientError.processFailed("File name cannot be empty, '.', '..', or contain '/'.")
        }
        guard targetName != entry.name else { return }
        let targetPath = Self.joinedPath(basePath: Self.parentPath(for: entry.path), name: targetName)
        let command = "mv -n -- \(Self.shellQuote(entry.path)) \(Self.shellQuote(targetPath))"
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not rename \(entry.name).")
        }
    }

    func moveToTrash(
        entry: RemoteFileEntry,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> String {
        let trashDirectory = "~/.hhc-server-manager-trash"
        let timestamp = Self.trashTimestamp(for: now())
        let trashPath = Self.joinedPath(basePath: trashDirectory, name: "\(timestamp)-\(entry.name)")
        let command = "mkdir -p -- \(Self.shellQuote(trashDirectory)) && mv -n -- \(Self.shellQuote(entry.path)) \(Self.shellQuote(trashPath))"
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not move \(entry.name) to trash.")
        }
        return trashPath
    }

    func readTextFile(
        entry: RemoteFileEntry,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> RemoteTextFile {
        guard entry.kind == .file else {
            throw SSHClientError.processFailed("Only regular files can be opened as text.")
        }
        if let size = entry.size, size > Self.maxEditableTextBytes {
            throw SSHClientError.processFailed("File is larger than the 256 KiB text editing limit.")
        }

        let command = """
        bytes=$(wc -c < \(Self.shellQuote(entry.path)) 2>/dev/null | tr -d '[:space:]' || echo 0); \
        if [ "$bytes" -gt \(Self.maxEditableTextBytes) ]; then echo "__HHC_FILE_TOO_LARGE__$bytes"; exit 3; fi; \
        base64 < \(Self.shellQuote(entry.path))
        """
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            if result.stdout.hasPrefix("__HHC_FILE_TOO_LARGE__") {
                throw SSHClientError.processFailed("File is larger than the 256 KiB text editing limit.")
            }
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not read \(entry.name).")
        }
        let encoded = result.stdout
            .split(whereSeparator: { $0.isWhitespace })
            .joined()
        guard let data = Data(base64Encoded: encoded), let content = String(data: data, encoding: .utf8) else {
            throw SSHClientError.processFailed("File is not valid UTF-8 text.")
        }
        return RemoteTextFile(path: entry.path, content: content, byteCount: data.count, capturedAt: now())
    }

    func saveTextFile(
        path: String,
        content: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> RemoteTextSaveResult {
        let data = Data(content.utf8)
        guard data.count <= Self.maxEditableTextBytes else {
            throw SSHClientError.processFailed("File is larger than the 256 KiB text editing limit.")
        }
        let encoded = data.base64EncodedString()
        let timestamp = Self.trashTimestamp(for: now())
        let backupPath = "\(path).hhc-backup-\(timestamp)"
        let temporaryPath = "\(path).hhc-tmp-\(UUID().uuidString)"
        let command = """
        set -e; \
        tmp=\(Self.shellQuote(temporaryPath)); \
        backup=\(Self.shellQuote(backupPath)); \
        trap 'rm -f -- "$tmp"' EXIT; \
        base64 -d > "$tmp" <<'__HHC_TEXT_EOF__'
        \(encoded)
        __HHC_TEXT_EOF__
        cp -p -- \(Self.shellQuote(path)) "$backup"; \
        mv -- "$tmp" \(Self.shellQuote(path)); \
        trap - EXIT
        """
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not save \(path).")
        }
        return RemoteTextSaveResult(path: path, backupPath: backupPath)
    }

    func saveTextFileAs(
        sourcePath: String,
        targetPath: String,
        content: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> RemoteTextSaveResult {
        let normalizedTargetPath = Self.normalizedFilePath(targetPath)
        guard !normalizedTargetPath.isEmpty else {
            throw SSHClientError.processFailed("Save As path cannot be empty, '/', '~', or a directory path.")
        }
        guard normalizedTargetPath != sourcePath else {
            return try await saveTextFile(
                path: sourcePath,
                content: content,
                profile: profile,
                sshClient: sshClient
            )
        }

        let data = Data(content.utf8)
        guard data.count <= Self.maxEditableTextBytes else {
            throw SSHClientError.processFailed("File is larger than the 256 KiB text editing limit.")
        }
        let encoded = data.base64EncodedString()
        let temporaryPath = "\(normalizedTargetPath).hhc-tmp-\(UUID().uuidString)"
        let command = """
        set -e; \
        tmp=\(Self.shellQuote(temporaryPath)); \
        target=\(Self.shellQuote(normalizedTargetPath)); \
        trap 'rm -f -- "$tmp"' EXIT; \
        test ! -e "$target"; \
        base64 -d > "$tmp" <<'__HHC_TEXT_EOF__'
        \(encoded)
        __HHC_TEXT_EOF__
        mv -- "$tmp" "$target"; \
        trap - EXIT
        """
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not save \(normalizedTargetPath).")
        }
        return RemoteTextSaveResult(path: normalizedTargetPath, backupPath: nil)
    }

    func changePermissions(
        entry: RemoteFileEntry,
        mode: String,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws {
        let normalizedMode = try Self.validatedPermissionMode(mode)
        let command = "chmod -- \(Self.shellQuote(normalizedMode)) \(Self.shellQuote(entry.path))"
        let result = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute(command, profile: profile)
        }
        guard result.exitCode == 0 else {
            throw SSHClientError.processFailed(result.stderr.nilIfEmpty ?? "Could not change permissions for \(entry.name).")
        }
    }

    func uploadFile(
        localURL: URL,
        toDirectoryPath directoryPath: String,
        profile: ServerProfile,
        transferClient: RemoteFileTransferClient,
        progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)? = nil
    ) async throws -> RemoteFileTransferResult {
        let fileName = Self.validatedFileName(localURL.lastPathComponent)
        guard !fileName.isEmpty else {
            throw SSHClientError.processFailed("Local file name cannot be empty, '.', '..', or contain '/'.")
        }
        let remotePath = Self.joinedPath(basePath: Self.normalizedDirectoryPath(directoryPath), name: fileName)
        return try await transferClient.uploadFile(
            localURL: localURL,
            remotePath: remotePath,
            profile: profile,
            progressHandler: progressHandler
        )
    }

    func downloadFile(
        entry: RemoteFileEntry,
        to localURL: URL,
        profile: ServerProfile,
        transferClient: RemoteFileTransferClient,
        progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)? = nil
    ) async throws -> RemoteFileTransferResult {
        guard entry.kind == .file else {
            throw SSHClientError.processFailed("Only regular files can be downloaded.")
        }
        return try await transferClient.downloadFile(
            remotePath: entry.path,
            localURL: localURL,
            profile: profile,
            progressHandler: progressHandler
        )
    }

    static func parentPath(for path: String) -> String {
        let normalized = normalizedDirectoryPath(path)
        guard normalized != "/" else { return "/" }
        if normalized.hasPrefix("~/") {
            let components = normalized.dropFirst(2).split(separator: "/").map(String.init)
            let parent = components.dropLast().joined(separator: "/")
            return parent.isEmpty ? "~" : "~/\(parent)"
        }
        let components = normalized.split(separator: "/").map(String.init)
        let parent = components.dropLast().joined(separator: "/")
        return parent.isEmpty ? "/" : "/\(parent)"
    }

    static func normalizedDirectoryPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "~" }
        if trimmed == "/" || trimmed == "~" {
            return trimmed
        }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    static func normalizedFilePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/", trimmed != "~", !trimmed.hasSuffix("/") else {
            return ""
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return trimmed
        }
        return joinedPath(basePath: "~", name: trimmed)
    }

    static func validatedFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !trimmed.contains("/") else {
            return ""
        }
        return trimmed
    }

    static func validatedPermissionMode(_ mode: String) throws -> String {
        let trimmed = mode.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(trimmed)
        guard [3, 4].contains(characters.count), characters.allSatisfy({ "01234567".contains($0) }) else {
            throw SSHClientError.processFailed("Permissions must be a 3 or 4 digit octal mode, for example 644 or 0755.")
        }
        return trimmed
    }

    static func parseFindListing(_ text: String, basePath: String) -> [RemoteFileEntry] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { return nil }
            let name = parts[0]
            let kind = kind(fromFindType: parts[1])
            let size = Int64(parts[2])
            let modifiedAt = Double(parts[3]).map(Date.init(timeIntervalSince1970:))
            return RemoteFileEntry(
                name: name,
                path: joinedPath(basePath: basePath, name: name),
                kind: kind,
                size: size,
                modifiedAt: modifiedAt,
                permissions: parts[4]
            )
        }
        .sorted { left, right in
            if left.kind == .directory, right.kind != .directory { return true }
            if left.kind != .directory, right.kind == .directory { return false }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private static func kind(fromFindType type: String) -> RemoteFileKind {
        switch type {
        case "d":
            .directory
        case "f":
            .file
        case "l":
            .symlink
        default:
            .other
        }
    }

    static func joinedPath(basePath: String, name: String) -> String {
        if basePath == "/" {
            return "/\(name)"
        }
        if basePath == "~" {
            return "~/\(name)"
        }
        return "\(basePath)/\(name)"
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func trashTimestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

protocol CloudProviderAdapter: Sendable {
    var providerId: CloudProviderID { get }
    var displayName: String { get }
    var capabilities: Set<CloudCapability> { get }

    func validateCredential(_ credential: CloudProviderCredential) async throws
    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion]
    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance]
    func fetchMetricSeries(credential: CloudProviderCredential, query: CloudMetricQuery) async throws -> CloudMetricSeries
    func fetchSecurityGroups(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String
    ) async throws -> [CloudSecurityGroup]
    func fetchSecurityGroupPolicies(
        credential: CloudProviderCredential,
        group: CloudSecurityGroup,
        capturedAt: Date
    ) async throws -> CloudSecurityGroupPolicySnapshot
    func applySecurityGroupRuleChange(
        credential: CloudProviderCredential,
        preview: CloudSecurityGroupRuleChangePreview
    ) async throws -> String?
    func fetchDisks(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudDisk]
    func fetchSnapshots(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudSnapshot]
    func fetchBillingStates(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudBillingState]
    func createSnapshot(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        diskId: String,
        snapshotName: String,
        capturedAt: Date
    ) async throws -> CloudSnapshot
    func deleteSnapshot(
        credential: CloudProviderCredential,
        regionId: String,
        snapshotId: String
    ) async throws
    func attachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String,
        instanceId: String
    ) async throws
    func detachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String
    ) async throws
    func startInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws
    func stopInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws
    func rebootInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws
}

extension CloudProviderAdapter {
    func applySecurityGroupRuleChange(
        credential: CloudProviderCredential,
        preview: CloudSecurityGroupRuleChangePreview
    ) async throws -> String? {
        throw CloudProviderError.unsupportedCapability(providerId: providerId, capability: .securityGroupActions)
    }
}

enum CloudProviderError: LocalizedError, Equatable {
    case adapterNotRegistered(CloudProviderID)
    case unsupportedCapability(providerId: CloudProviderID, capability: CloudCapability)
    case authenticationFailed(String)
    case permissionDenied(String)
    case rateLimited(String)
    case networkFailure(String)
    case providerFailure(String)
    case timeout(TimeInterval)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .adapterNotRegistered(providerId):
            "No cloud provider adapter is registered for \(providerId.displayName)."
        case let .unsupportedCapability(providerId, capability):
            "\(providerId.displayName) does not support \(capability.rawValue)."
        case let .authenticationFailed(message):
            "Cloud provider authentication failed: \(message)"
        case let .permissionDenied(message):
            "Cloud provider permission denied: \(message)"
        case let .rateLimited(message):
            "Cloud provider rate limited the request: \(message)"
        case let .networkFailure(message):
            "Cloud provider network request failed: \(message)"
        case let .providerFailure(message):
            "Cloud provider returned an error: \(message)"
        case let .timeout(seconds):
            "Cloud provider request timed out after \(seconds)s."
        case .cancelled:
            "Cloud provider request was cancelled."
        }
    }
}

struct CloudProviderRegistry: Sendable {
    private let adapters: [CloudProviderID: any CloudProviderAdapter]

    init(adapters: [any CloudProviderAdapter] = []) {
        var mapped: [CloudProviderID: any CloudProviderAdapter] = [:]
        for adapter in adapters {
            mapped[adapter.providerId] = adapter
        }
        self.adapters = mapped
    }

    var registeredProviderIds: [CloudProviderID] {
        adapters.keys.sorted { $0.rawValue < $1.rawValue }
    }

    func adapter(for providerId: CloudProviderID) throws -> any CloudProviderAdapter {
        guard let adapter = adapters[providerId] else {
            throw CloudProviderError.adapterNotRegistered(providerId)
        }
        return adapter
    }

    func capabilities(for providerId: CloudProviderID) throws -> Set<CloudCapability> {
        try adapter(for: providerId).capabilities
    }

    func supports(_ capability: CloudCapability, providerId: CloudProviderID) -> Bool {
        (try? capabilities(for: providerId).contains(capability)) ?? false
    }

    func require(_ capability: CloudCapability, providerId: CloudProviderID) throws {
        guard supports(capability, providerId: providerId) else {
            throw CloudProviderError.unsupportedCapability(providerId: providerId, capability: capability)
        }
    }
}

struct ProviderCapabilityStatus: Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(providerId.rawValue)-\(capability.rawValue)" }
    var providerId: CloudProviderID
    var providerName: String
    var capability: CloudCapability
    var isRegistered: Bool
    var isSupported: Bool
    var runtimeDisabledReason: String?

    var isRuntimeDisabled: Bool {
        runtimeDisabledReason != nil
    }

    var isEffective: Bool {
        isRegistered && isSupported && !isRuntimeDisabled
    }
}

struct ProviderCapabilityMatrix: Equatable, Hashable, Sendable {
    var rows: [ProviderCapabilityStatus]

    func status(providerId: CloudProviderID, capability: CloudCapability) -> ProviderCapabilityStatus? {
        rows.first { $0.providerId == providerId && $0.capability == capability }
    }
}

enum ProviderCapabilityMatrixBuilder {
    static func build(
        registry: CloudProviderRegistry,
        providerIds: [CloudProviderID] = CloudProviderID.allCases,
        capabilities: [CloudCapability] = CloudCapability.allCases
    ) -> ProviderCapabilityMatrix {
        ProviderCapabilityMatrix(rows: providerIds.flatMap { providerId in
            let adapter = try? registry.adapter(for: providerId)
            let supported = adapter?.capabilities ?? []
            return capabilities.map { capability in
                ProviderCapabilityStatus(
                    providerId: providerId,
                    providerName: adapter?.displayName ?? providerId.displayName,
                    capability: capability,
                    isRegistered: adapter != nil,
                    isSupported: supported.contains(capability),
                    runtimeDisabledReason: nil
                )
            }
        })
    }
}

enum CloudResourceSearchService {
    static func unifiedResources(
        instances: [CloudInstanceLink],
        securityGroups: [CloudSecurityGroup] = [],
        disks: [CloudDisk] = [],
        snapshots: [CloudSnapshot] = [],
        billingStates: [CloudBillingState] = []
    ) -> [CloudUnifiedResource] {
        var resources: [CloudUnifiedResource] = []
        resources.append(contentsOf: instances.map { instance in
            CloudUnifiedResource(
                id: "instance:\(instance.accountId.uuidString):\(instance.regionId):\(instance.instanceId)",
                kind: .instance,
                accountId: instance.accountId,
                providerId: instance.providerId,
                regionId: instance.regionId,
                resourceId: instance.instanceId,
                displayName: instance.displayName ?? instance.instanceId,
                status: instance.status,
                primaryAddress: instance.publicIp ?? instance.privateIp,
                secondaryText: instance.instanceType,
                lastSyncedAt: instance.lastSyncedAt
            )
        })
        resources.append(contentsOf: securityGroups.map { group in
            CloudUnifiedResource(
                id: "security-group:\(group.accountId.uuidString):\(group.regionId):\(group.securityGroupId)",
                kind: .securityGroup,
                accountId: group.accountId,
                providerId: group.providerId,
                regionId: group.regionId,
                resourceId: group.securityGroupId,
                displayName: group.name,
                status: group.isDefault == true ? "default" : nil,
                primaryAddress: nil,
                secondaryText: group.description,
                lastSyncedAt: nil
            )
        })
        resources.append(contentsOf: disks.map { disk in
            CloudUnifiedResource(
                id: "disk:\(disk.accountId.uuidString):\(disk.regionId):\(disk.diskId)",
                kind: .disk,
                accountId: disk.accountId,
                providerId: disk.providerId,
                regionId: disk.regionId,
                resourceId: disk.diskId,
                displayName: disk.name ?? disk.diskId,
                status: disk.status,
                primaryAddress: disk.instanceId,
                secondaryText: [disk.diskType, disk.sizeGB.map { "\($0) GB" }].compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                lastSyncedAt: disk.lastSyncedAt
            )
        })
        resources.append(contentsOf: snapshots.map { snapshot in
            CloudUnifiedResource(
                id: "snapshot:\(snapshot.accountId.uuidString):\(snapshot.regionId):\(snapshot.snapshotId)",
                kind: .snapshot,
                accountId: snapshot.accountId,
                providerId: snapshot.providerId,
                regionId: snapshot.regionId,
                resourceId: snapshot.snapshotId,
                displayName: snapshot.name ?? snapshot.snapshotId,
                status: snapshot.status,
                primaryAddress: snapshot.diskId,
                secondaryText: snapshot.sizeGB.map { "\($0) GB" },
                lastSyncedAt: snapshot.lastSyncedAt
            )
        })
        resources.append(contentsOf: billingStates.map { billing in
            CloudUnifiedResource(
                id: "billing:\(billing.accountId.uuidString):\(billing.providerId.rawValue):\(billing.resourceType):\(billing.resourceId)",
                kind: .billing,
                accountId: billing.accountId,
                providerId: billing.providerId,
                regionId: nil,
                resourceId: billing.resourceId,
                displayName: "\(billing.resourceType) \(billing.resourceId)",
                status: billing.status,
                primaryAddress: billing.billingType,
                secondaryText: billing.expireAt.map(AppDatabase.string(from:)),
                lastSyncedAt: billing.lastSyncedAt
            )
        })
        return resources.sorted {
            if $0.providerId.rawValue != $1.providerId.rawValue {
                return $0.providerId.rawValue < $1.providerId.rawValue
            }
            if ($0.regionId ?? "") != ($1.regionId ?? "") {
                return ($0.regionId ?? "") < ($1.regionId ?? "")
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func search(_ resources: [CloudUnifiedResource], query: CloudResourceSearchQuery) -> [CloudUnifiedResource] {
        let normalizedText = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return resources.filter { resource in
            if let providerId = query.providerId, resource.providerId != providerId { return false }
            if let accountId = query.accountId, resource.accountId != accountId { return false }
            if let regionId = query.regionId, resource.regionId != regionId { return false }
            if !query.kinds.contains(resource.kind) { return false }
            if let status = query.status, resource.status?.localizedCaseInsensitiveCompare(status) != .orderedSame { return false }
            guard !normalizedText.isEmpty else { return true }
            return [
                resource.resourceId,
                resource.displayName,
                resource.status,
                resource.primaryAddress,
                resource.secondaryText,
                resource.regionId,
                resource.providerId.displayName,
                resource.kind.displayName,
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedText) }
        }
    }
}

enum CloudProviderRequestRunner {
    static func run<T: Sendable>(
        timeout seconds: TimeInterval,
        limiter: CloudProviderRequestLimiter,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await limiter.run {
            try await withTimeout(seconds, operation: operation)
        }
    }

    static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard seconds > 0 else {
            throw CloudProviderError.timeout(seconds)
        }

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CloudProviderError.timeout(seconds)
            }

            guard let value = try await group.next() else {
                throw CloudProviderError.cancelled
            }
            group.cancelAll()
            return value
        }
    }
}

actor CloudProviderRequestLimiter {
    static let shared = CloudProviderRequestLimiter(maxConcurrentRequests: 4)

    private let maxConcurrentRequests: Int
    private var runningRequests = 0
    private var waiters: [CloudProviderRequestWaiter] = []

    init(maxConcurrentRequests: Int) {
        self.maxConcurrentRequests = max(1, maxConcurrentRequests)
    }

    func run<T: Sendable>(
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire()
        do {
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if runningRequests < maxConcurrentRequests {
            runningRequests += 1
            return
        }

        let waiterId = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append(CloudProviderRequestWaiter(id: waiterId, continuation: continuation))
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterId)
            }
        }

        if acquired {
            if Task.isCancelled {
                release()
                throw CloudProviderError.cancelled
            }
            return
        }

        throw CloudProviderError.cancelled
    }

    private func release() {
        if waiters.isEmpty {
            runningRequests = max(0, runningRequests - 1)
        } else {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}

private struct CloudProviderRequestWaiter {
    let id: UUID
    let continuation: CheckedContinuation<Bool, Never>
}

protocol TencentCloudHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionTencentCloudHTTPTransport: TencentCloudHTTPTransport, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudProviderError.networkFailure("Tencent Cloud returned a non-HTTP response.")
        }
        return (data, httpResponse)
    }
}

final class TencentCloudAdapter: CloudProviderAdapter, @unchecked Sendable {
    let providerId: CloudProviderID = .tencentCloud
    let displayName = "Tencent Cloud"
    let capabilities: Set<CloudCapability> = [
        .regions,
        .instanceDiscovery,
        .instanceMetadata,
        .cloudMetrics,
        .securityGroups,
        .securityGroupActions,
        .cloudDisks,
        .cloudSnapshots,
        .cloudBilling,
        .snapshotActions,
        .diskAttachmentActions,
        .powerActions,
    ]

    private let transport: TencentCloudHTTPTransport
    private let now: @Sendable () -> Date
    private let timeout: TimeInterval
    private let requestLimiter: CloudProviderRequestLimiter
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        transport: TencentCloudHTTPTransport = URLSessionTencentCloudHTTPTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        timeout: TimeInterval = 15,
        requestLimiter: CloudProviderRequestLimiter = .shared
    ) {
        self.transport = transport
        self.now = now
        self.timeout = timeout
        self.requestLimiter = requestLimiter
    }

    func validateCredential(_ credential: CloudProviderCredential) async throws {
        _ = try await fetchRegions(credential: credential)
    }

    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion] {
        let payload = TencentDescribeRegionsPayload(product: "cvm", scene: 1)
        let response: TencentCloudEnvelope<TencentDescribeRegionsResponse> = try await request(
            credential: credential,
            endpoint: TencentCloudEndpoint(
                host: "region.intl.tencentcloudapi.com",
                service: "region",
                action: "DescribeRegions",
                version: "2022-06-27",
                region: nil
            ),
            payload: payload
        )
        try throwIfNeeded(response.response.error)
        return response.response.regionSet?.map {
            CloudRegion(
                id: $0.region,
                displayName: $0.regionName,
                available: $0.regionState == "AVAILABLE"
            )
        } ?? []
    }

    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance] {
        var offset = 0
        let limit = 100
        var instances: [CloudProviderInstance] = []
        var totalCount: Int?

        repeat {
            let payload = TencentDescribeInstancesPayload(offset: offset, limit: limit)
            let response: TencentCloudEnvelope<TencentDescribeInstancesResponse> = try await request(
                credential: credential,
                endpoint: TencentCloudEndpoint(
                    host: "cvm.intl.tencentcloudapi.com",
                    service: "cvm",
                    action: "DescribeInstances",
                    version: "2017-03-12",
                    region: regionId
                ),
                payload: payload
            )
            try throwIfNeeded(response.response.error)

            let page = response.response.instanceSet ?? []
            instances.append(contentsOf: page.map { instance in
                CloudProviderInstance(
                    id: instance.instanceId,
                    providerId: .tencentCloud,
                    regionId: regionId,
                    displayName: instance.instanceName,
                    publicIp: instance.publicIpAddresses?.first,
                    privateIp: instance.privateIpAddresses?.first,
                    status: instance.instanceState,
                    instanceType: instance.instanceType,
                    zoneId: instance.placement?.zone,
                    vpcId: instance.virtualPrivateCloud?.vpcId,
                    securityGroupIds: instance.securityGroupIds ?? [],
                    billingType: instance.instanceChargeType,
                    expiredTime: instance.expiredTime.flatMap(Self.parseTencentDate),
                    rawJSON: instance.rawJSONString
                )
            })
            totalCount = response.response.totalCount
            offset += page.count
        } while offset < (totalCount ?? 0) && offset > 0

        return instances
    }

    func fetchMetricSeries(credential: CloudProviderCredential, query: CloudMetricQuery) async throws -> CloudMetricSeries {
        let payload = TencentGetMonitorDataPayload(
            namespace: query.namespace,
            metricName: Self.tencentMetricName(query.metricName),
            instances: [
                TencentMonitorInstance(dimensions: [
                    TencentMonitorDimension(name: "InstanceId", value: query.instanceId)
                ])
            ],
            period: query.period,
            startTime: Self.iso8601String(query.startTime),
            endTime: Self.iso8601String(query.endTime)
        )
        let response: TencentCloudEnvelope<TencentGetMonitorDataResponse> = try await request(
            credential: credential,
            endpoint: TencentCloudEndpoint(
                host: "monitor.intl.tencentcloudapi.com",
                service: "monitor",
                action: "GetMonitorData",
                version: "2018-07-24",
                region: query.regionId
            ),
            payload: payload
        )
        try throwIfNeeded(response.response.error)
        let dataPoint = response.response.dataPoints?.first
        return CloudMetricSeries(
            metricName: query.metricName,
            instanceId: query.instanceId,
            regionId: query.regionId,
            unit: Self.tencentMetricUnit(query.metricName),
            values: dataPoint?.values ?? [],
            timestamps: (dataPoint?.timestamps ?? []).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    func fetchSecurityGroups(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String
    ) async throws -> [CloudSecurityGroup] {
        var offset = 0
        let limit = 100
        var groups: [CloudSecurityGroup] = []
        var totalCount: Int?

        repeat {
            let payload = TencentDescribeSecurityGroupsPayload(offset: offset, limit: limit)
            let response: TencentCloudEnvelope<TencentDescribeSecurityGroupsResponse> = try await request(
                credential: credential,
                endpoint: TencentCloudEndpoint(
                    host: "vpc.intl.tencentcloudapi.com",
                    service: "vpc",
                    action: "DescribeSecurityGroups",
                    version: "2017-03-12",
                    region: regionId
                ),
                payload: payload
            )
            try throwIfNeeded(response.response.error)
            let page = response.response.securityGroupSet ?? []
            groups.append(contentsOf: page.map { group in
                CloudSecurityGroup(
                    accountId: accountId,
                    providerId: .tencentCloud,
                    regionId: regionId,
                    securityGroupId: group.securityGroupId,
                    name: group.securityGroupName,
                    description: group.securityGroupDesc,
                    projectId: group.projectId.map(String.init),
                    isDefault: group.isDefault,
                    createdTime: group.createdTime,
                    updatedTime: group.updateTime
                )
            })
            totalCount = response.response.totalCount
            offset += page.count
        } while offset < (totalCount ?? 0) && offset > 0

        return groups
    }

    func fetchSecurityGroupPolicies(
        credential: CloudProviderCredential,
        group: CloudSecurityGroup,
        capturedAt: Date
    ) async throws -> CloudSecurityGroupPolicySnapshot {
        let payload = TencentDescribeSecurityGroupPoliciesPayload(securityGroupId: group.securityGroupId)
        let response: TencentCloudEnvelope<TencentDescribeSecurityGroupPoliciesResponse> = try await request(
            credential: credential,
            endpoint: TencentCloudEndpoint(
                host: "vpc.intl.tencentcloudapi.com",
                service: "vpc",
                action: "DescribeSecurityGroupPolicies",
                version: "2017-03-12",
                region: group.regionId
            ),
            payload: payload
        )
        try throwIfNeeded(response.response.error)
        let policySet = response.response.securityGroupPolicySet
        return CloudSecurityGroupPolicySnapshot(
            group: group,
            version: policySet?.version,
            ingress: Self.mapSecurityGroupRules(policySet?.ingress ?? [], direction: .ingress),
            egress: Self.mapSecurityGroupRules(policySet?.egress ?? [], direction: .egress),
            capturedAt: capturedAt
        )
    }

    func applySecurityGroupRuleChange(
        credential: CloudProviderCredential,
        preview: CloudSecurityGroupRuleChangePreview
    ) async throws -> String? {
        let payload = TencentSecurityGroupPolicyMutationPayload(
            securityGroupId: preview.group.securityGroupId,
            securityGroupPolicySet: TencentSecurityGroupPolicyMutationSet(preview: preview)
        )
        let action: String
        switch (preview.action, preview.proposedRule.direction) {
        case (.add, .ingress):
            action = "AuthorizeSecurityGroupIngress"
        case (.add, .egress):
            action = "AuthorizeSecurityGroupEgress"
        case (.remove, .ingress):
            action = "RevokeSecurityGroupIngress"
        case (.remove, .egress):
            action = "RevokeSecurityGroupEgress"
        }

        let response: TencentCloudEnvelope<TencentSecurityGroupPolicyMutationResponse> = try await request(
            credential: credential,
            endpoint: TencentCloudEndpoint(
                host: "vpc.intl.tencentcloudapi.com",
                service: "vpc",
                action: action,
                version: "2017-03-12",
                region: preview.group.regionId
            ),
            payload: payload
        )
        try throwIfNeeded(response.response.error)
        return response.response.requestId
    }

    func fetchDisks(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudDisk] {
        var offset = 0
        let limit = 100
        var disks: [CloudDisk] = []
        var totalCount: Int?

        repeat {
            let payload = TencentPagedPayload(offset: offset, limit: limit)
            let response: TencentCloudEnvelope<TencentDescribeDisksResponse> = try await request(
                credential: credential,
                endpoint: TencentCloudEndpoint(
                    host: "cbs.intl.tencentcloudapi.com",
                    service: "cbs",
                    action: "DescribeDisks",
                    version: "2017-03-12",
                    region: regionId
                ),
                payload: payload
            )
            try throwIfNeeded(response.response.error)
            let page = response.response.diskSet ?? []
            disks.append(contentsOf: page.map { disk in
                CloudDisk(
                    id: UUID(),
                    accountId: accountId,
                    providerId: .tencentCloud,
                    regionId: regionId,
                    diskId: disk.diskId,
                    instanceId: disk.instanceId,
                    name: disk.diskName,
                    diskType: disk.diskType ?? disk.diskUsage,
                    sizeGB: disk.diskSize,
                    status: disk.diskState,
                    billingType: disk.diskChargeType,
                    expiredTime: disk.deadlineTime.flatMap(Self.parseTencentDate),
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                )
            })
            totalCount = response.response.totalCount
            offset += page.count
        } while offset < (totalCount ?? 0) && offset > 0

        return disks
    }

    func fetchSnapshots(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudSnapshot] {
        var offset = 0
        let limit = 100
        var snapshots: [CloudSnapshot] = []
        var totalCount: Int?

        repeat {
            let payload = TencentPagedPayload(offset: offset, limit: limit)
            let response: TencentCloudEnvelope<TencentDescribeSnapshotsResponse> = try await request(
                credential: credential,
                endpoint: TencentCloudEndpoint(
                    host: "cbs.intl.tencentcloudapi.com",
                    service: "cbs",
                    action: "DescribeSnapshots",
                    version: "2017-03-12",
                    region: regionId
                ),
                payload: payload
            )
            try throwIfNeeded(response.response.error)
            let page = response.response.snapshotSet ?? []
            snapshots.append(contentsOf: page.map { snapshot in
                CloudSnapshot(
                    id: UUID(),
                    accountId: accountId,
                    providerId: .tencentCloud,
                    regionId: regionId,
                    snapshotId: snapshot.snapshotId,
                    diskId: snapshot.diskId,
                    name: snapshot.snapshotName,
                    status: snapshot.snapshotState,
                    sizeGB: snapshot.diskSize,
                    createdAtProvider: snapshot.createTime.flatMap(Self.parseTencentDate),
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                )
            })
            totalCount = response.response.totalCount
            offset += page.count
        } while offset < (totalCount ?? 0) && offset > 0

        return snapshots
    }

    func fetchBillingStates(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudBillingState] {
        let instances = try await fetchInstances(credential: credential, regionId: regionId)
        let disks = try await fetchDisks(
            credential: credential,
            accountId: accountId,
            regionId: regionId,
            capturedAt: capturedAt
        )
        var states = instances.map { instance in
            CloudBillingState(
                id: UUID(),
                accountId: accountId,
                providerId: .tencentCloud,
                resourceType: "instance",
                resourceId: instance.id,
                billingType: instance.billingType,
                expireAt: instance.expiredTime,
                status: instance.status,
                rawJSON: instance.rawJSON,
                lastSyncedAt: capturedAt
            )
        }
        states.append(contentsOf: disks.map { disk in
            CloudBillingState(
                id: UUID(),
                accountId: accountId,
                providerId: .tencentCloud,
                resourceType: "disk",
                resourceId: disk.diskId,
                billingType: disk.billingType,
                expireAt: disk.expiredTime,
                status: disk.status,
                rawJSON: disk.rawJSON,
                lastSyncedAt: capturedAt
            )
        })
        return states
    }

    func createSnapshot(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        diskId: String,
        snapshotName: String,
        capturedAt: Date
    ) async throws -> CloudSnapshot {
        let payload = TencentCreateSnapshotPayload(diskId: diskId, snapshotName: snapshotName)
        let response: TencentCloudEnvelope<TencentCreateSnapshotResponse> = try await request(
            credential: credential,
            endpoint: TencentCloudEndpoint(
                host: "cbs.intl.tencentcloudapi.com",
                service: "cbs",
                action: "CreateSnapshot",
                version: "2017-03-12",
                region: regionId
            ),
            payload: payload
        )
        try throwIfNeeded(response.response.error)
        guard let snapshotId = response.response.snapshotId, !snapshotId.isEmpty else {
            throw CloudProviderError.providerFailure("Tencent Cloud did not return a snapshot id.")
        }
        return CloudSnapshot(
            id: UUID(),
            accountId: accountId,
            providerId: .tencentCloud,
            regionId: regionId,
            snapshotId: snapshotId,
            diskId: diskId,
            name: snapshotName,
            status: "CREATING",
            sizeGB: nil,
            createdAtProvider: capturedAt,
            rawJSON: nil,
            lastSyncedAt: capturedAt
        )
    }

    func deleteSnapshot(
        credential: CloudProviderCredential,
        regionId: String,
        snapshotId: String
    ) async throws {
        let payload = TencentDeleteSnapshotsPayload(snapshotIds: [snapshotId])
        let response: TencentCloudEnvelope<TencentDeleteSnapshotsResponse> = try await request(
            credential: credential,
            endpoint: TencentCloudEndpoint(
                host: "cbs.intl.tencentcloudapi.com",
                service: "cbs",
                action: "DeleteSnapshots",
                version: "2017-03-12",
                region: regionId
            ),
            payload: payload
        )
        try throwIfNeeded(response.response.error)
    }

    func attachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String,
        instanceId: String
    ) async throws {
        let payload = TencentAttachDisksPayload(diskIds: [diskId], instanceId: instanceId)
        let response: TencentCloudEnvelope<TencentAttachDisksResponse> = try await request(
            credential: credential,
            endpoint: TencentCloudEndpoint(
                host: "cbs.intl.tencentcloudapi.com",
                service: "cbs",
                action: "AttachDisks",
                version: "2017-03-12",
                region: regionId
            ),
            payload: payload
        )
        try throwIfNeeded(response.response.error)
    }

    func detachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String
    ) async throws {
        let payload = TencentDetachDisksPayload(diskIds: [diskId])
        let response: TencentCloudEnvelope<TencentDetachDisksResponse> = try await request(
            credential: credential,
            endpoint: TencentCloudEndpoint(
                host: "cbs.intl.tencentcloudapi.com",
                service: "cbs",
                action: "DetachDisks",
                version: "2017-03-12",
                region: regionId
            ),
            payload: payload
        )
        try throwIfNeeded(response.response.error)
    }

    func startInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        try await performInstanceAction(
            credential: credential,
            regionId: regionId,
            instanceId: instanceId,
            action: "StartInstances"
        )
    }

    func stopInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        try await performInstanceAction(
            credential: credential,
            regionId: regionId,
            instanceId: instanceId,
            action: "StopInstances"
        )
    }

    func rebootInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        try await performInstanceAction(
            credential: credential,
            regionId: regionId,
            instanceId: instanceId,
            action: "RebootInstances"
        )
    }

    private func performInstanceAction(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String,
        action: String
    ) async throws {
        let payload = TencentInstanceIdsPayload(instanceIds: [instanceId])
        let response: TencentCloudEnvelope<TencentInstanceActionResponse> = try await request(
            credential: credential,
            endpoint: TencentCloudEndpoint(
                host: "cvm.intl.tencentcloudapi.com",
                service: "cvm",
                action: action,
                version: "2017-03-12",
                region: regionId
            ),
            payload: payload
        )
        try throwIfNeeded(response.response.error)
    }

    private func request<Payload: Encodable, Response: Decodable>(
        credential: CloudProviderCredential,
        endpoint: TencentCloudEndpoint,
        payload: Payload
    ) async throws -> TencentCloudEnvelope<Response> {
        let body = try encoder.encode(payload)
        let request = try signedRequest(credential: credential, endpoint: endpoint, body: body)
        let (data, httpResponse) = try await CloudProviderRequestRunner.run(timeout: timeout, limiter: requestLimiter) {
            try await self.transport.send(request)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CloudProviderError.networkFailure("HTTP \(httpResponse.statusCode)")
        }
        do {
            return try decoder.decode(TencentCloudEnvelope<Response>.self, from: data)
        } catch {
            throw CloudProviderError.providerFailure("Could not decode Tencent Cloud response: \(error.localizedDescription)")
        }
    }

    private func signedRequest(
        credential: CloudProviderCredential,
        endpoint: TencentCloudEndpoint,
        body: Data
    ) throws -> URLRequest {
        guard let url = URL(string: "https://\(endpoint.host)/") else {
            throw CloudProviderError.providerFailure("Invalid Tencent Cloud endpoint: \(endpoint.host)")
        }

        let timestamp = Int(now().timeIntervalSince1970)
        let date = Self.utcDateString(timestamp: timestamp)
        let contentType = "application/json; charset=utf-8"
        let authorization = Self.authorization(
            credential: credential,
            service: endpoint.service,
            host: endpoint.host,
            contentType: contentType,
            body: body,
            date: date,
            timestamp: timestamp
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.host, forHTTPHeaderField: "Host")
        request.setValue(endpoint.action, forHTTPHeaderField: "X-TC-Action")
        request.setValue("\(timestamp)", forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(endpoint.version, forHTTPHeaderField: "X-TC-Version")
        if let region = endpoint.region {
            request.setValue(region, forHTTPHeaderField: "X-TC-Region")
        }
        return request
    }

    private func throwIfNeeded(_ error: TencentCloudAPIError?) throws {
        guard let error else { return }
        if error.code.contains("AuthFailure") {
            throw CloudProviderError.authenticationFailed(error.message)
        }
        if error.code.contains("Unauthorized") || error.code.contains("UnsupportedOperation") {
            throw CloudProviderError.permissionDenied(error.message)
        }
        if error.code.contains("LimitExceeded") || error.code.contains("RequestLimitExceeded") {
            throw CloudProviderError.rateLimited(error.message)
        }
        throw CloudProviderError.providerFailure("\(error.code): \(error.message)")
    }

    private static func authorization(
        credential: CloudProviderCredential,
        service: String,
        host: String,
        contentType: String,
        body: Data,
        date: String,
        timestamp: Int
    ) -> String {
        let canonicalHeaders = "content-type:\(contentType)\nhost:\(host)\n"
        let signedHeaders = "content-type;host"
        let hashedPayload = sha256Hex(body)
        let canonicalRequest = [
            "POST",
            "/",
            "",
            canonicalHeaders,
            signedHeaders,
            hashedPayload,
        ].joined(separator: "\n")
        let credentialScope = "\(date)/\(service)/tc3_request"
        let stringToSign = [
            "TC3-HMAC-SHA256",
            "\(timestamp)",
            credentialScope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let secretDate = hmacSHA256(key: Data("TC3\(credential.secretKey)".utf8), data: Data(date.utf8))
        let secretService = hmacSHA256(key: secretDate, data: Data(service.utf8))
        let secretSigning = hmacSHA256(key: secretService, data: Data("tc3_request".utf8))
        let signature = hmacSHA256Hex(key: secretSigning, data: Data(stringToSign.utf8))

        return "TC3-HMAC-SHA256 Credential=\(credential.secretId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    private static func utcDateString(timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func tencentMetricName(_ metricName: String) -> String {
        switch metricName {
        case "MemoryUsage":
            return "MemUsage"
        case "DiskReadBytes":
            return "CvmDiskReadTraffic"
        case "DiskWriteBytes":
            return "CvmDiskWriteTraffic"
        case "NetworkInBytes":
            return "LanIntraffic"
        case "NetworkOutBytes":
            return "LanOuttraffic"
        default:
            return metricName
        }
    }

    private static func tencentMetricUnit(_ metricName: String) -> String? {
        switch metricName {
        case "CPUUsage", "MemoryUsage":
            return "%"
        case "DiskReadBytes", "DiskWriteBytes", "NetworkInBytes", "NetworkOutBytes":
            return "B/s"
        default:
            return nil
        }
    }

    private static func parseTencentDate(_ text: String) -> Date? {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }

    private static func mapSecurityGroupRules(
        _ rules: [TencentSecurityGroupPolicy],
        direction: CloudSecurityGroupRuleDirection
    ) -> [CloudSecurityGroupRule] {
        rules.map { rule in
            CloudSecurityGroupRule(
                direction: direction,
                policyIndex: rule.policyIndex,
                providerRuleId: nil,
                protocolName: rule.protocolName,
                port: rule.port,
                cidrBlock: rule.cidrBlock,
                ipv6CidrBlock: rule.ipv6CidrBlock,
                referencedSecurityGroupId: rule.securityGroupId,
                action: rule.action,
                description: rule.policyDescription,
                modifiedTime: rule.modifyTime
            )
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private static func hmacSHA256Hex(key: Data, data: Data) -> String {
        hmacSHA256(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }
}

protocol AlibabaCloudHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionAlibabaCloudHTTPTransport: AlibabaCloudHTTPTransport, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudProviderError.networkFailure("Alibaba Cloud returned a non-HTTP response.")
        }
        return (data, httpResponse)
    }
}

final class AlibabaCloudAdapter: CloudProviderAdapter, @unchecked Sendable {
    let providerId: CloudProviderID = .alibabaCloud
    let displayName = "Alibaba Cloud"
    let capabilities: Set<CloudCapability> = [
        .regions,
        .instanceDiscovery,
        .instanceMetadata,
        .cloudDisks,
        .cloudSnapshots,
        .cloudBilling,
        .securityGroups,
        .securityGroupActions,
        .snapshotActions,
        .diskAttachmentActions,
        .powerActions,
        .cloudMetrics,
    ]

    private let transport: AlibabaCloudHTTPTransport
    private let now: @Sendable () -> Date
    private let nonce: @Sendable () -> String
    private let timeout: TimeInterval
    private let requestLimiter: CloudProviderRequestLimiter
    private let decoder = JSONDecoder()

    init(
        transport: AlibabaCloudHTTPTransport = URLSessionAlibabaCloudHTTPTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        nonce: @escaping @Sendable () -> String = { UUID().uuidString },
        timeout: TimeInterval = 15,
        requestLimiter: CloudProviderRequestLimiter = .shared
    ) {
        self.transport = transport
        self.now = now
        self.nonce = nonce
        self.timeout = timeout
        self.requestLimiter = requestLimiter
    }

    func validateCredential(_ credential: CloudProviderCredential) async throws {
        _ = try await fetchRegions(credential: credential)
    }

    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion] {
        let response: AlibabaDescribeRegionsResponse = try await request(
            credential: credential,
            host: "ecs.aliyuncs.com",
            action: "DescribeRegions",
            queryItems: [
                URLQueryItem(name: "AcceptLanguage", value: "en-US"),
            ]
        )
        return response.regions?.region.map {
            CloudRegion(id: $0.regionId, displayName: $0.localName ?? $0.regionId, available: true)
        } ?? []
    }

    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance] {
        var pageNumber = 1
        let pageSize = 100
        var totalCount: Int?
        var instances: [CloudProviderInstance] = []

        repeat {
            let response: AlibabaDescribeInstancesResponse = try await request(
                credential: credential,
                host: "ecs.\(regionId).aliyuncs.com",
                action: "DescribeInstances",
                queryItems: [
                    URLQueryItem(name: "RegionId", value: regionId),
                    URLQueryItem(name: "PageNumber", value: "\(pageNumber)"),
                    URLQueryItem(name: "PageSize", value: "\(pageSize)"),
                ]
            )
            let page = response.instances?.instance ?? []
            instances.append(contentsOf: page.map { instance in
                CloudProviderInstance(
                    id: instance.instanceId,
                    providerId: .alibabaCloud,
                    regionId: regionId,
                    displayName: instance.instanceName,
                    publicIp: instance.publicIpAddress?.ipAddress?.first ?? instance.eipAddress?.ipAddress,
                    privateIp: instance.vpcAttributes?.privateIpAddress?.ipAddress?.first ?? instance.innerIpAddress?.ipAddress?.first,
                    status: instance.status,
                    instanceType: instance.instanceType,
                    zoneId: instance.zoneId,
                    vpcId: instance.vpcAttributes?.vpcId,
                    securityGroupIds: instance.securityGroupIds?.securityGroupId ?? [],
                    billingType: instance.instanceChargeType,
                    expiredTime: instance.expiredTime.flatMap(Self.parseAlibabaDate),
                    rawJSON: nil
                )
            })
            totalCount = response.totalCount
            pageNumber += 1
        } while instances.count < (totalCount ?? 0)

        return instances
    }

    func fetchMetricSeries(credential: CloudProviderCredential, query: CloudMetricQuery) async throws -> CloudMetricSeries {
        let dimensions = try Self.alibabaMetricDimensions(instanceId: query.instanceId)
        let response: AlibabaDescribeMetricListResponse = try await request(
            credential: credential,
            host: "metrics.\(query.regionId).aliyuncs.com",
            action: "DescribeMetricList",
            queryItems: [
                URLQueryItem(name: "Namespace", value: Self.alibabaMetricNamespace(query.namespace)),
                URLQueryItem(name: "MetricName", value: Self.alibabaMetricName(query.metricName)),
                URLQueryItem(name: "Dimensions", value: dimensions),
                URLQueryItem(name: "StartTime", value: "\(Self.millisecondsSince1970(query.startTime))"),
                URLQueryItem(name: "EndTime", value: "\(Self.millisecondsSince1970(query.endTime))"),
                URLQueryItem(name: "Period", value: "\(query.period)"),
            ],
            version: "2019-01-01"
        )
        let samples = try Self.parseAlibabaMetricDatapoints(response.datapoints)
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { datapoint -> (timestamp: Double, value: Double)? in
                guard let value = datapoint.value else { return nil }
                return (datapoint.timestamp, value)
            }
        return CloudMetricSeries(
            metricName: query.metricName,
            instanceId: query.instanceId,
            regionId: query.regionId,
            unit: Self.alibabaMetricUnit(query.metricName),
            values: samples.map(\.value),
            timestamps: samples.map { Self.dateFromAlibabaMetricTimestamp($0.timestamp) }
        )
    }

    func fetchSecurityGroups(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String
    ) async throws -> [CloudSecurityGroup] {
        var pageNumber = 1
        let pageSize = 100
        var totalCount: Int?
        var groups: [CloudSecurityGroup] = []

        repeat {
            let response: AlibabaDescribeSecurityGroupsResponse = try await request(
                credential: credential,
                host: "ecs.\(regionId).aliyuncs.com",
                action: "DescribeSecurityGroups",
                queryItems: [
                    URLQueryItem(name: "RegionId", value: regionId),
                    URLQueryItem(name: "PageNumber", value: "\(pageNumber)"),
                    URLQueryItem(name: "PageSize", value: "\(pageSize)"),
                ]
            )
            let page = response.securityGroups?.securityGroup ?? []
            guard !page.isEmpty else {
                break
            }
            groups.append(contentsOf: page.map { group in
                CloudSecurityGroup(
                    accountId: accountId,
                    providerId: .alibabaCloud,
                    regionId: regionId,
                    securityGroupId: group.securityGroupId,
                    name: group.securityGroupName ?? group.securityGroupId,
                    description: group.description,
                    projectId: group.resourceGroupId,
                    isDefault: nil,
                    createdTime: group.creationTime,
                    updatedTime: nil
                )
            })
            totalCount = response.totalCount
            pageNumber += 1
        } while groups.count < (totalCount ?? 0)

        return groups
    }

    func fetchSecurityGroupPolicies(
        credential: CloudProviderCredential,
        group: CloudSecurityGroup,
        capturedAt: Date
    ) async throws -> CloudSecurityGroupPolicySnapshot {
        let response: AlibabaDescribeSecurityGroupAttributeResponse = try await request(
            credential: credential,
            host: "ecs.\(group.regionId).aliyuncs.com",
            action: "DescribeSecurityGroupAttribute",
            queryItems: [
                URLQueryItem(name: "RegionId", value: group.regionId),
                URLQueryItem(name: "SecurityGroupId", value: group.securityGroupId),
            ]
        )
        let permissions = response.permissions?.permission ?? []
        return CloudSecurityGroupPolicySnapshot(
            group: group,
            version: response.innerAccessPolicy,
            ingress: Self.mapAlibabaSecurityGroupPermissions(permissions, direction: .ingress),
            egress: Self.mapAlibabaSecurityGroupPermissions(permissions, direction: .egress),
            capturedAt: capturedAt
        )
    }

    func applySecurityGroupRuleChange(
        credential: CloudProviderCredential,
        preview: CloudSecurityGroupRuleChangePreview
    ) async throws -> String? {
        let action: String
        switch (preview.action, preview.proposedRule.direction) {
        case (.add, .ingress):
            action = "AuthorizeSecurityGroup"
        case (.add, .egress):
            action = "AuthorizeSecurityGroupEgress"
        case (.remove, .ingress):
            action = "RevokeSecurityGroup"
        case (.remove, .egress):
            action = "RevokeSecurityGroupEgress"
        }

        let response: AlibabaSecurityGroupActionResponse = try await request(
            credential: credential,
            host: "ecs.\(preview.group.regionId).aliyuncs.com",
            action: action,
            queryItems: Self.alibabaSecurityGroupRuleQueryItems(preview)
        )
        return response.requestId
    }

    func fetchDisks(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudDisk] {
        var pageNumber = 1
        let pageSize = 100
        var totalCount: Int?
        var disks: [CloudDisk] = []

        repeat {
            let response: AlibabaDescribeDisksResponse = try await request(
                credential: credential,
                host: "ecs.\(regionId).aliyuncs.com",
                action: "DescribeDisks",
                queryItems: [
                    URLQueryItem(name: "RegionId", value: regionId),
                    URLQueryItem(name: "PageNumber", value: "\(pageNumber)"),
                    URLQueryItem(name: "PageSize", value: "\(pageSize)"),
                ]
            )
            let page = response.disks?.disk ?? []
            guard !page.isEmpty else {
                break
            }
            disks.append(contentsOf: page.map { disk in
                CloudDisk(
                    id: UUID(),
                    accountId: accountId,
                    providerId: .alibabaCloud,
                    regionId: regionId,
                    diskId: disk.diskId,
                    instanceId: disk.instanceId,
                    name: disk.diskName,
                    diskType: disk.category ?? disk.type,
                    sizeGB: disk.size,
                    status: disk.status,
                    billingType: disk.diskChargeType,
                    expiredTime: disk.expiredTime.flatMap(Self.parseAlibabaDate),
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                )
            })
            totalCount = response.totalCount
            pageNumber += 1
        } while disks.count < (totalCount ?? 0)

        return disks
    }

    func fetchSnapshots(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudSnapshot] {
        var pageNumber = 1
        let pageSize = 100
        var totalCount: Int?
        var snapshots: [CloudSnapshot] = []

        repeat {
            let response: AlibabaDescribeSnapshotsResponse = try await request(
                credential: credential,
                host: "ecs.\(regionId).aliyuncs.com",
                action: "DescribeSnapshots",
                queryItems: [
                    URLQueryItem(name: "RegionId", value: regionId),
                    URLQueryItem(name: "PageNumber", value: "\(pageNumber)"),
                    URLQueryItem(name: "PageSize", value: "\(pageSize)"),
                ]
            )
            let page = response.snapshots?.snapshot ?? []
            guard !page.isEmpty else {
                break
            }
            snapshots.append(contentsOf: page.map { snapshot in
                CloudSnapshot(
                    id: UUID(),
                    accountId: accountId,
                    providerId: .alibabaCloud,
                    regionId: regionId,
                    snapshotId: snapshot.snapshotId,
                    diskId: snapshot.sourceDiskId ?? snapshot.diskId,
                    name: snapshot.snapshotName,
                    status: snapshot.status,
                    sizeGB: snapshot.sourceDiskSize ?? snapshot.size,
                    createdAtProvider: (snapshot.creationTime ?? snapshot.createTime).flatMap(Self.parseAlibabaDate),
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                )
            })
            totalCount = response.totalCount
            pageNumber += 1
        } while snapshots.count < (totalCount ?? 0)

        return snapshots
    }

    func fetchBillingStates(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudBillingState] {
        let instances = try await fetchInstances(credential: credential, regionId: regionId)
        return instances.map { instance in
            CloudBillingState(
                id: UUID(),
                accountId: accountId,
                providerId: .alibabaCloud,
                resourceType: "instance",
                resourceId: instance.id,
                billingType: instance.billingType,
                expireAt: instance.expiredTime,
                status: instance.status,
                rawJSON: instance.rawJSON,
                lastSyncedAt: capturedAt
            )
        }
    }

    func createSnapshot(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        diskId: String,
        snapshotName: String,
        capturedAt: Date
    ) async throws -> CloudSnapshot {
        let response: AlibabaCreateSnapshotResponse = try await request(
            credential: credential,
            host: "ecs.\(regionId).aliyuncs.com",
            action: "CreateSnapshot",
            queryItems: [
                URLQueryItem(name: "DiskId", value: diskId),
                URLQueryItem(name: "SnapshotName", value: snapshotName),
            ]
        )
        guard let snapshotId = response.snapshotId, !snapshotId.isEmpty else {
            throw CloudProviderError.providerFailure("Alibaba Cloud did not return a snapshot id.")
        }
        return CloudSnapshot(
            id: UUID(),
            accountId: accountId,
            providerId: .alibabaCloud,
            regionId: regionId,
            snapshotId: snapshotId,
            diskId: diskId,
            name: snapshotName,
            status: "CREATING",
            sizeGB: nil,
            createdAtProvider: capturedAt,
            rawJSON: nil,
            lastSyncedAt: capturedAt
        )
    }

    func deleteSnapshot(
        credential: CloudProviderCredential,
        regionId: String,
        snapshotId: String
    ) async throws {
        let _: AlibabaDeleteSnapshotResponse = try await request(
            credential: credential,
            host: "ecs.\(regionId).aliyuncs.com",
            action: "DeleteSnapshot",
            queryItems: [
                URLQueryItem(name: "SnapshotId", value: snapshotId),
            ]
        )
    }

    func attachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String,
        instanceId: String
    ) async throws {
        let _: AlibabaDiskActionResponse = try await request(
            credential: credential,
            host: "ecs.\(regionId).aliyuncs.com",
            action: "AttachDisk",
            queryItems: [
                URLQueryItem(name: "RegionId", value: regionId),
                URLQueryItem(name: "DiskId", value: diskId),
                URLQueryItem(name: "InstanceId", value: instanceId),
            ]
        )
    }

    func detachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String
    ) async throws {
        let _: AlibabaDiskActionResponse = try await request(
            credential: credential,
            host: "ecs.\(regionId).aliyuncs.com",
            action: "DetachDisk",
            queryItems: [
                URLQueryItem(name: "RegionId", value: regionId),
                URLQueryItem(name: "DiskId", value: diskId),
            ]
        )
    }

    func startInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        try await performInstanceAction(
            credential: credential,
            regionId: regionId,
            instanceId: instanceId,
            action: "StartInstance"
        )
    }

    func stopInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        try await performInstanceAction(
            credential: credential,
            regionId: regionId,
            instanceId: instanceId,
            action: "StopInstance"
        )
    }

    func rebootInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        try await performInstanceAction(
            credential: credential,
            regionId: regionId,
            instanceId: instanceId,
            action: "RebootInstance"
        )
    }

    private func performInstanceAction(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String,
        action: String
    ) async throws {
        let _: AlibabaInstanceActionResponse = try await request(
            credential: credential,
            host: "ecs.\(regionId).aliyuncs.com",
            action: action,
            queryItems: [
                URLQueryItem(name: "RegionId", value: regionId),
                URLQueryItem(name: "InstanceId", value: instanceId),
            ]
        )
    }

    private func request<Response: Decodable>(
        credential: CloudProviderCredential,
        host: String,
        action: String,
        queryItems: [URLQueryItem],
        version: String = "2014-05-26"
    ) async throws -> Response {
        let request = try signedRequest(
            credential: credential,
            host: host,
            action: action,
            queryItems: queryItems,
            version: version
        )
        let (data, httpResponse) = try await CloudProviderRequestRunner.run(timeout: timeout, limiter: requestLimiter) {
            try await self.transport.send(request)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw mapAlibabaHTTPError(data: data, statusCode: httpResponse.statusCode)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw CloudProviderError.providerFailure("Could not decode Alibaba Cloud response: \(error.localizedDescription)")
        }
    }

    private func signedRequest(
        credential: CloudProviderCredential,
        host: String,
        action: String,
        queryItems: [URLQueryItem],
        version: String = "2014-05-26"
    ) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/"
        components.queryItems = queryItems
        guard let url = components.url else {
            throw CloudProviderError.providerFailure("Invalid Alibaba Cloud endpoint: \(host)")
        }

        let date = Self.acsDateString(now())
        let hashedPayload = CloudSignature.sha256Hex(Data())
        let signedHeaders = "host;x-acs-action;x-acs-content-sha256;x-acs-date;x-acs-signature-nonce;x-acs-version"
        let headers: [(String, String)] = [
            ("host", host),
            ("x-acs-action", action),
            ("x-acs-content-sha256", hashedPayload),
            ("x-acs-date", date),
            ("x-acs-signature-nonce", nonce()),
            ("x-acs-version", version),
        ]
        let canonicalHeaders = headers
            .map { "\($0.0):\($0.1.trimmingCharacters(in: .whitespacesAndNewlines))\n" }
            .joined()
        let canonicalQuery = Self.canonicalQueryString(queryItems)
        let canonicalRequest = [
            "GET",
            "/",
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            hashedPayload,
        ].joined(separator: "\n")
        let stringToSign = "ACS3-HMAC-SHA256\n\(CloudSignature.sha256Hex(Data(canonicalRequest.utf8)))"
        let signature = CloudSignature.hmacSHA256Hex(key: Data(credential.secretKey.utf8), data: Data(stringToSign.utf8))
        let authorization = "ACS3-HMAC-SHA256 Credential=\(credential.secretId),SignedHeaders=\(signedHeaders),Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        for header in headers where header.0 != "host" {
            request.setValue(header.1, forHTTPHeaderField: header.0)
        }
        request.setValue(host, forHTTPHeaderField: "Host")
        return request
    }

    private func mapAlibabaHTTPError(data: Data, statusCode: Int) -> CloudProviderError {
        if let error = try? decoder.decode(AlibabaErrorResponse.self, from: data) {
            if error.code.contains("InvalidAccessKeyId") || error.code.contains("Signature") {
                return .authenticationFailed(error.message ?? error.code)
            }
            if error.code.contains("Forbidden") || error.code.contains("Unauthorized") || error.code.contains("NoPermission") {
                return .permissionDenied(error.message ?? error.code)
            }
            if error.code.contains("Throttling") || error.code.contains("LimitExceeded") {
                return .rateLimited(error.message ?? error.code)
            }
            return .providerFailure("\(error.code): \(error.message ?? "HTTP \(statusCode)")")
        }
        return .networkFailure("HTTP \(statusCode)")
    }

    private static func canonicalQueryString(_ items: [URLQueryItem]) -> String {
        var pairs: [(String, String)] = []
        for item in items {
            pairs.append((item.name, item.value ?? ""))
        }
        pairs.sort { left, right in
            left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
        }
        var encoded: [String] = []
        for pair in pairs {
            let name = CloudSignature.percentEncode(pair.0)
            let value = CloudSignature.percentEncode(pair.1)
            encoded.append("\(name)=\(value)")
        }
        return encoded.joined(separator: "&")
    }

    private static func acsDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func parseAlibabaDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private static func millisecondsSince1970(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func dateFromAlibabaMetricTimestamp(_ timestamp: Double) -> Date {
        if timestamp > 10_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1_000)
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func alibabaMetricNamespace(_ namespace: String) -> String {
        namespace == "QCE/CVM" ? "acs_ecs_dashboard" : namespace
    }

    private static func alibabaMetricName(_ metricName: String) -> String {
        switch metricName {
        case "CPUUsage":
            return "CPUUtilization"
        case "MemoryUsage":
            return "memory_usedutilization"
        case "DiskReadBytes":
            return "disk_readbytes"
        case "DiskWriteBytes":
            return "disk_writebytes"
        case "NetworkInBytes":
            return "networkin_rate"
        case "NetworkOutBytes":
            return "networkout_rate"
        default:
            return metricName
        }
    }

    private static func alibabaMetricUnit(_ metricName: String) -> String? {
        switch metricName {
        case "CPUUsage", "MemoryUsage":
            return "%"
        case "DiskReadBytes", "DiskWriteBytes", "NetworkInBytes", "NetworkOutBytes":
            return "B/s"
        default:
            return nil
        }
    }

    private static func alibabaMetricDimensions(instanceId: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["instanceId": instanceId], options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw CloudProviderError.providerFailure("Could not encode Alibaba Cloud metric dimensions.")
        }
        return text
    }

    private static func parseAlibabaMetricDatapoints(_ text: String?) throws -> [AlibabaMetricDatapoint] {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        do {
            return try JSONDecoder().decode([AlibabaMetricDatapoint].self, from: Data(text.utf8))
        } catch {
            throw CloudProviderError.providerFailure("Could not decode Alibaba Cloud metric datapoints: \(error.localizedDescription)")
        }
    }

    private static func mapAlibabaSecurityGroupPermissions(
        _ permissions: [AlibabaSecurityGroupPermission],
        direction: CloudSecurityGroupRuleDirection
    ) -> [CloudSecurityGroupRule] {
        permissions.compactMap { permission in
            guard permission.matches(direction: direction) else {
                return nil
            }
            return CloudSecurityGroupRule(
                direction: direction,
                policyIndex: permission.priority,
                providerRuleId: nil,
                protocolName: permission.ipProtocol,
                port: permission.portRange,
                cidrBlock: direction == .ingress ? permission.sourceCidrIp : permission.destCidrIp,
                ipv6CidrBlock: direction == .ingress ? permission.ipv6SourceCidrIp : permission.ipv6DestCidrIp,
                referencedSecurityGroupId: direction == .ingress ? permission.sourceGroupId : permission.destGroupId,
                action: permission.policy,
                description: permission.description,
                modifiedTime: permission.createTime
            )
        }
    }

    private static func alibabaSecurityGroupRuleQueryItems(
        _ preview: CloudSecurityGroupRuleChangePreview
    ) -> [URLQueryItem] {
        let rule = preview.proposedRule
        var items = [
            URLQueryItem(name: "RegionId", value: preview.group.regionId),
            URLQueryItem(name: "SecurityGroupId", value: preview.group.securityGroupId),
            URLQueryItem(name: "IpProtocol", value: normalizedAlibabaProtocol(rule.protocolName)),
            URLQueryItem(name: "PortRange", value: normalizedAlibabaPortRange(rule.port)),
            URLQueryItem(name: "Policy", value: normalizedAlibabaPolicy(rule.action)),
            URLQueryItem(name: "Priority", value: "\(rule.policyIndex ?? 1)"),
        ]
        switch rule.direction {
        case .ingress:
            appendQueryItem(name: "SourceCidrIp", value: rule.cidrBlock, to: &items)
            appendQueryItem(name: "Ipv6SourceCidrIp", value: rule.ipv6CidrBlock, to: &items)
            appendQueryItem(name: "SourceGroupId", value: rule.referencedSecurityGroupId, to: &items)
        case .egress:
            appendQueryItem(name: "DestCidrIp", value: rule.cidrBlock, to: &items)
            appendQueryItem(name: "Ipv6DestCidrIp", value: rule.ipv6CidrBlock, to: &items)
            appendQueryItem(name: "DestGroupId", value: rule.referencedSecurityGroupId, to: &items)
        }
        appendQueryItem(name: "Description", value: rule.description, to: &items)
        return items
    }

    private static func appendQueryItem(name: String, value: String?, to items: inout [URLQueryItem]) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return }
        items.append(URLQueryItem(name: name, value: trimmed))
    }

    private static func normalizedAlibabaProtocol(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "all" : trimmed.lowercased()
    }

    private static func normalizedAlibabaPolicy(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "accept" : trimmed.lowercased()
    }

    private static func normalizedAlibabaPortRange(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "-1/-1" }
        if trimmed.uppercased() == "ALL" || trimmed == "-1" {
            return "-1/-1"
        }
        if trimmed.contains("/") {
            return trimmed
        }
        return "\(trimmed)/\(trimmed)"
    }
}

protocol HuaweiCloudHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionHuaweiCloudHTTPTransport: HuaweiCloudHTTPTransport, @unchecked Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudProviderError.networkFailure("Huawei Cloud returned a non-HTTP response.")
        }
        return (data, httpResponse)
    }
}

final class HuaweiCloudAdapter: CloudProviderAdapter, @unchecked Sendable {
    let providerId: CloudProviderID = .huaweiCloud
    let displayName = "Huawei Cloud"
    let capabilities: Set<CloudCapability> = [
        .regions,
        .instanceDiscovery,
        .instanceMetadata,
        .cloudDisks,
        .cloudSnapshots,
        .cloudBilling,
        .securityGroups,
        .securityGroupActions,
        .snapshotActions,
        .diskAttachmentActions,
        .powerActions,
        .cloudMetrics,
    ]

    private let transport: HuaweiCloudHTTPTransport
    private let now: @Sendable () -> Date
    private let timeout: TimeInterval
    private let requestLimiter: CloudProviderRequestLimiter
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        transport: HuaweiCloudHTTPTransport = URLSessionHuaweiCloudHTTPTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        timeout: TimeInterval = 15,
        requestLimiter: CloudProviderRequestLimiter = .shared
    ) {
        self.transport = transport
        self.now = now
        self.timeout = timeout
        self.requestLimiter = requestLimiter
    }

    func validateCredential(_ credential: CloudProviderCredential) async throws {
        _ = try await fetchRegions(credential: credential)
    }

    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion] {
        let response: HuaweiProjectsResponse = try await request(
            credential: credential,
            host: "iam.myhuaweicloud.com",
            path: "/v3/projects",
            queryItems: []
        )
        return response.projects.compactMap { project in
            guard let name = project.name, let id = project.id else { return nil }
            return CloudRegion(
                id: Self.encodedRegionId(regionName: name, projectId: id),
                displayName: name,
                available: project.enabled ?? true
            )
        }
        .sorted { $0.displayName < $1.displayName }
    }

    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance] {
        let region = Self.decodeRegionId(regionId)
        var offset = 0
        let limit = 100
        var totalCount: Int?
        var instances: [CloudProviderInstance] = []

        repeat {
            let response: HuaweiServersDetailResponse = try await request(
                credential: credential,
                host: "ecs.\(region.regionName).myhuaweicloud.com",
                path: "/v1.1/\(CloudSignature.percentEncode(region.projectId))/cloudservers/detail",
                queryItems: [
                    URLQueryItem(name: "limit", value: "\(limit)"),
                    URLQueryItem(name: "offset", value: "\(offset)"),
                ]
            )
            instances.append(contentsOf: response.servers.map { server in
                CloudProviderInstance(
                    id: server.id,
                    providerId: .huaweiCloud,
                    regionId: regionId,
                    displayName: server.name,
                    publicIp: server.addresses?.firstAddress(type: "floating"),
                    privateIp: server.addresses?.firstAddress(type: "fixed"),
                    status: server.status ?? server.vmState,
                    instanceType: server.flavor?.id,
                    zoneId: server.availabilityZone,
                    vpcId: nil,
                    securityGroupIds: server.securityGroups?.map(\.name) ?? [],
                    billingType: server.metadata?.chargingMode,
                    expiredTime: nil,
                    rawJSON: nil
                )
            })
            totalCount = response.count
            offset += response.servers.count
        } while offset < (totalCount ?? 0) && offset > 0

        return instances
    }

    func fetchMetricSeries(credential: CloudProviderCredential, query: CloudMetricQuery) async throws -> CloudMetricSeries {
        let region = Self.decodeRegionId(query.regionId)
        let response: HuaweiMetricDataResponse = try await request(
            credential: credential,
            host: "ces.\(region.regionName).myhuaweicloud.com",
            path: "/V1.0/\(CloudSignature.percentEncode(region.projectId))/metric-data",
            queryItems: [
                URLQueryItem(name: "namespace", value: Self.huaweiMetricNamespace(query.namespace)),
                URLQueryItem(name: "metric_name", value: Self.huaweiMetricName(query.metricName)),
                URLQueryItem(name: "dim.0", value: "instance_id,\(query.instanceId)"),
                URLQueryItem(name: "filter", value: "average"),
                URLQueryItem(name: "period", value: "\(query.period)"),
                URLQueryItem(name: "from", value: "\(Self.millisecondsSince1970(query.startTime))"),
                URLQueryItem(name: "to", value: "\(Self.millisecondsSince1970(query.endTime))"),
            ]
        )
        let samples = response.datapoints
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { datapoint -> (timestamp: Int64, value: Double)? in
                guard let value = datapoint.average ?? datapoint.sum ?? datapoint.max ?? datapoint.min else {
                    return nil
                }
                return (datapoint.timestamp, value)
            }
        return CloudMetricSeries(
            metricName: query.metricName,
            instanceId: query.instanceId,
            regionId: query.regionId,
            unit: samples.isEmpty ? nil : (response.datapoints.first(where: { $0.unit != nil })?.unit ?? "%"),
            values: samples.map(\.value),
            timestamps: samples.map { Date(timeIntervalSince1970: TimeInterval($0.timestamp) / 1_000) }
        )
    }

    func fetchSecurityGroups(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String
    ) async throws -> [CloudSecurityGroup] {
        let region = Self.decodeRegionId(regionId)
        var marker: String?
        let limit = 100
        var groups: [CloudSecurityGroup] = []

        repeat {
            var queryItems = [
                URLQueryItem(name: "limit", value: "\(limit)"),
            ]
            if let marker {
                queryItems.append(URLQueryItem(name: "marker", value: marker))
            }
            let response: HuaweiSecurityGroupsResponse = try await request(
                credential: credential,
                host: "vpc.\(region.regionName).myhuaweicloud.com",
                path: "/v1/\(CloudSignature.percentEncode(region.projectId))/security-groups",
                queryItems: queryItems
            )
            guard !response.securityGroups.isEmpty else {
                break
            }
            groups.append(contentsOf: response.securityGroups.map { group in
                CloudSecurityGroup(
                    accountId: accountId,
                    providerId: .huaweiCloud,
                    regionId: regionId,
                    securityGroupId: group.id,
                    name: group.name ?? group.id,
                    description: group.description,
                    projectId: group.enterpriseProjectId ?? region.projectId,
                    isDefault: nil,
                    createdTime: group.createdAt,
                    updatedTime: group.updatedAt
                )
            })
            marker = response.securityGroups.count == limit ? response.securityGroups.last?.id : nil
        } while marker != nil

        return groups
    }

    func fetchSecurityGroupPolicies(
        credential: CloudProviderCredential,
        group: CloudSecurityGroup,
        capturedAt: Date
    ) async throws -> CloudSecurityGroupPolicySnapshot {
        let region = Self.decodeRegionId(group.regionId)
        var marker: String?
        let limit = 100
        var rules: [HuaweiSecurityGroupRule] = []

        repeat {
            var queryItems = [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "security_group_id", value: group.securityGroupId),
            ]
            if let marker {
                queryItems.append(URLQueryItem(name: "marker", value: marker))
            }
            let response: HuaweiSecurityGroupRulesResponse = try await request(
                credential: credential,
                host: "vpc.\(region.regionName).myhuaweicloud.com",
                path: "/v1/\(CloudSignature.percentEncode(region.projectId))/security-group-rules",
                queryItems: queryItems
            )
            guard !response.securityGroupRules.isEmpty else {
                break
            }
            rules.append(contentsOf: response.securityGroupRules)
            marker = response.securityGroupRules.count == limit ? response.securityGroupRules.last?.id : nil
        } while marker != nil

        return CloudSecurityGroupPolicySnapshot(
            group: group,
            version: nil,
            ingress: Self.mapHuaweiSecurityGroupRules(rules, direction: .ingress),
            egress: Self.mapHuaweiSecurityGroupRules(rules, direction: .egress),
            capturedAt: capturedAt
        )
    }

    func applySecurityGroupRuleChange(
        credential: CloudProviderCredential,
        preview: CloudSecurityGroupRuleChangePreview
    ) async throws -> String? {
        switch preview.action {
        case .add:
            return try await createSecurityGroupRule(credential: credential, preview: preview)
        case .remove:
            try await deleteSecurityGroupRule(credential: credential, preview: preview)
            return preview.proposedRule.providerRuleId
        }
    }

    func fetchDisks(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudDisk] {
        let region = Self.decodeRegionId(regionId)
        var offset = 0
        let limit = 100
        var totalCount: Int?
        var lastPageCount = 0
        var disks: [CloudDisk] = []

        repeat {
            let response: HuaweiVolumesDetailResponse = try await request(
                credential: credential,
                host: "evs.\(region.regionName).myhuaweicloud.com",
                path: "/v2/\(CloudSignature.percentEncode(region.projectId))/cloudvolumes/detail",
                queryItems: [
                    URLQueryItem(name: "limit", value: "\(limit)"),
                    URLQueryItem(name: "offset", value: "\(offset)"),
                ]
            )
            guard !response.volumes.isEmpty else {
                break
            }
            lastPageCount = response.volumes.count
            disks.append(contentsOf: response.volumes.map { volume in
                CloudDisk(
                    id: UUID(),
                    accountId: accountId,
                    providerId: .huaweiCloud,
                    regionId: regionId,
                    diskId: volume.id,
                    instanceId: volume.attachments?.first?.serverId,
                    name: volume.name,
                    diskType: volume.volumeType,
                    sizeGB: volume.size,
                    status: volume.status,
                    billingType: volume.metadata?.billingType,
                    expiredTime: nil,
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                )
            })
            totalCount = response.count
            offset += response.volumes.count
        } while totalCount.map({ offset < $0 }) ?? (lastPageCount == limit)

        return disks
    }

    func fetchSnapshots(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudSnapshot] {
        let region = Self.decodeRegionId(regionId)
        var offset = 0
        let limit = 10
        var lastPageCount = 0
        var snapshots: [CloudSnapshot] = []

        repeat {
            let response: HuaweiSnapshotsDetailResponse = try await request(
                credential: credential,
                host: "evs.\(region.regionName).myhuaweicloud.com",
                path: "/v5/\(CloudSignature.percentEncode(region.projectId))/snapshots/detail",
                queryItems: [
                    URLQueryItem(name: "limit", value: "\(limit)"),
                    URLQueryItem(name: "offset", value: "\(offset)"),
                ]
            )
            guard !response.snapshots.isEmpty else {
                break
            }
            lastPageCount = response.snapshots.count
            snapshots.append(contentsOf: response.snapshots.map { snapshot in
                CloudSnapshot(
                    id: UUID(),
                    accountId: accountId,
                    providerId: .huaweiCloud,
                    regionId: regionId,
                    snapshotId: snapshot.id,
                    diskId: snapshot.volumeId,
                    name: snapshot.name,
                    status: snapshot.status,
                    sizeGB: snapshot.size,
                    createdAtProvider: snapshot.createdAt.flatMap(Self.parseHuaweiDate),
                    rawJSON: nil,
                    lastSyncedAt: capturedAt
                )
            })
            offset += response.snapshots.count
        } while lastPageCount == limit

        return snapshots
    }

    func fetchBillingStates(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        capturedAt: Date
    ) async throws -> [CloudBillingState] {
        let instances = try await fetchInstances(credential: credential, regionId: regionId)
        let disks = try await fetchDisks(
            credential: credential,
            accountId: accountId,
            regionId: regionId,
            capturedAt: capturedAt
        )
        var states = instances.map { instance in
            CloudBillingState(
                id: UUID(),
                accountId: accountId,
                providerId: .huaweiCloud,
                resourceType: "instance",
                resourceId: instance.id,
                billingType: instance.billingType,
                expireAt: instance.expiredTime,
                status: instance.status,
                rawJSON: instance.rawJSON,
                lastSyncedAt: capturedAt
            )
        }
        states.append(contentsOf: disks.map { disk in
            CloudBillingState(
                id: UUID(),
                accountId: accountId,
                providerId: .huaweiCloud,
                resourceType: "disk",
                resourceId: disk.diskId,
                billingType: disk.billingType,
                expireAt: disk.expiredTime,
                status: disk.status,
                rawJSON: disk.rawJSON,
                lastSyncedAt: capturedAt
            )
        })
        return states
    }

    func createSnapshot(
        credential: CloudProviderCredential,
        accountId: UUID,
        regionId: String,
        diskId: String,
        snapshotName: String,
        capturedAt: Date
    ) async throws -> CloudSnapshot {
        let region = Self.decodeRegionId(regionId)
        let payload = HuaweiCreateSnapshotPayload(
            snapshot: HuaweiCreateSnapshotPayload.Snapshot(name: snapshotName, volumeId: diskId)
        )
        let response: HuaweiCreateSnapshotResponse = try await request(
            credential: credential,
            host: "evs.\(region.regionName).myhuaweicloud.com",
            path: "/v2/\(CloudSignature.percentEncode(region.projectId))/cloudsnapshots",
            queryItems: [],
            method: "POST",
            body: try encoder.encode(payload)
        )
        guard let snapshot = response.snapshot, !snapshot.id.isEmpty else {
            throw CloudProviderError.providerFailure("Huawei Cloud did not return a snapshot id.")
        }
        return CloudSnapshot(
            id: UUID(),
            accountId: accountId,
            providerId: .huaweiCloud,
            regionId: regionId,
            snapshotId: snapshot.id,
            diskId: snapshot.volumeId ?? diskId,
            name: snapshot.name ?? snapshotName,
            status: snapshot.status ?? "creating",
            sizeGB: snapshot.size,
            createdAtProvider: snapshot.createdAt.flatMap(Self.parseHuaweiDate) ?? capturedAt,
            rawJSON: nil,
            lastSyncedAt: capturedAt
        )
    }

    func deleteSnapshot(
        credential: CloudProviderCredential,
        regionId: String,
        snapshotId: String
    ) async throws {
        let region = Self.decodeRegionId(regionId)
        let _: HuaweiDeleteSnapshotResponse = try await request(
            credential: credential,
            host: "evs.\(region.regionName).myhuaweicloud.com",
            path: "/v2/\(CloudSignature.percentEncode(region.projectId))/cloudsnapshots/\(CloudSignature.percentEncode(snapshotId))",
            queryItems: [],
            method: "DELETE"
        )
    }

    func attachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String,
        instanceId: String
    ) async throws {
        let region = Self.decodeRegionId(regionId)
        let payload = HuaweiVolumeAttachPayload(
            attach: HuaweiVolumeAttachPayload.Attach(instanceUUID: instanceId)
        )
        try await requestWithoutResponse(
            credential: credential,
            host: "evs.\(region.regionName).myhuaweicloud.com",
            path: "/v2/\(CloudSignature.percentEncode(region.projectId))/volumes/\(CloudSignature.percentEncode(diskId))/action",
            queryItems: [],
            method: "POST",
            body: try encoder.encode(payload)
        )
    }

    func detachDisk(
        credential: CloudProviderCredential,
        regionId: String,
        diskId: String
    ) async throws {
        let region = Self.decodeRegionId(regionId)
        let payload = HuaweiVolumeDetachPayload(detach: HuaweiVolumeDetachPayload.Detach())
        try await requestWithoutResponse(
            credential: credential,
            host: "evs.\(region.regionName).myhuaweicloud.com",
            path: "/v2/\(CloudSignature.percentEncode(region.projectId))/volumes/\(CloudSignature.percentEncode(diskId))/action",
            queryItems: [],
            method: "POST",
            body: try encoder.encode(payload)
        )
    }

    func startInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        let payload = HuaweiServerStartPayload(
            start: HuaweiServerStartPayload.Start(
                servers: [HuaweiServerActionServer(id: instanceId)]
            )
        )
        try await performInstanceAction(credential: credential, regionId: regionId, payload: payload)
    }

    func stopInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        let payload = HuaweiServerStopPayload(
            stop: HuaweiServerStopPayload.Stop(
                type: "SOFT",
                servers: [HuaweiServerActionServer(id: instanceId)]
            )
        )
        try await performInstanceAction(credential: credential, regionId: regionId, payload: payload)
    }

    func rebootInstance(
        credential: CloudProviderCredential,
        regionId: String,
        instanceId: String
    ) async throws {
        let payload = HuaweiServerRebootPayload(
            reboot: HuaweiServerRebootPayload.Reboot(
                type: "SOFT",
                servers: [HuaweiServerActionServer(id: instanceId)]
            )
        )
        try await performInstanceAction(credential: credential, regionId: regionId, payload: payload)
    }

    private func createSecurityGroupRule(
        credential: CloudProviderCredential,
        preview: CloudSecurityGroupRuleChangePreview
    ) async throws -> String? {
        let region = Self.decodeRegionId(preview.group.regionId)
        let response: HuaweiCreateSecurityGroupRuleResponse = try await request(
            credential: credential,
            host: "vpc.\(region.regionName).myhuaweicloud.com",
            path: "/v3/\(CloudSignature.percentEncode(region.projectId))/vpc/security-group-rules",
            queryItems: [],
            method: "POST",
            body: try encoder.encode(Self.huaweiSecurityGroupRulePayload(preview))
        )
        return response.securityGroupRule?.id
    }

    private func deleteSecurityGroupRule(
        credential: CloudProviderCredential,
        preview: CloudSecurityGroupRuleChangePreview
    ) async throws {
        guard let ruleId = preview.proposedRule.providerRuleId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ruleId.isEmpty else {
            throw CloudProviderError.providerFailure("Huawei Cloud security group rule id is required for removal.")
        }
        let region = Self.decodeRegionId(preview.group.regionId)
        try await requestWithoutResponse(
            credential: credential,
            host: "vpc.\(region.regionName).myhuaweicloud.com",
            path: "/v3/\(CloudSignature.percentEncode(region.projectId))/vpc/security-group-rules/\(CloudSignature.percentEncode(ruleId))",
            queryItems: [],
            method: "DELETE"
        )
    }

    private func performInstanceAction<Payload: Encodable>(
        credential: CloudProviderCredential,
        regionId: String,
        payload: Payload
    ) async throws {
        let region = Self.decodeRegionId(regionId)
        try await requestWithoutResponse(
            credential: credential,
            host: "ecs.\(region.regionName).myhuaweicloud.com",
            path: "/v1/\(CloudSignature.percentEncode(region.projectId))/cloudservers/action",
            queryItems: [],
            method: "POST",
            body: try encoder.encode(payload)
        )
    }

    private func request<Response: Decodable>(
        credential: CloudProviderCredential,
        host: String,
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        body: Data = Data()
    ) async throws -> Response {
        let request = try signedRequest(credential: credential, host: host, path: path, queryItems: queryItems, method: method, body: body)
        let (data, httpResponse) = try await CloudProviderRequestRunner.run(timeout: timeout, limiter: requestLimiter) {
            try await self.transport.send(request)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw mapHuaweiHTTPError(data: data, statusCode: httpResponse.statusCode)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw CloudProviderError.providerFailure("Could not decode Huawei Cloud response: \(error.localizedDescription)")
        }
    }

    private func requestWithoutResponse(
        credential: CloudProviderCredential,
        host: String,
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        body: Data = Data()
    ) async throws {
        let request = try signedRequest(credential: credential, host: host, path: path, queryItems: queryItems, method: method, body: body)
        let (_, httpResponse) = try await CloudProviderRequestRunner.run(timeout: timeout, limiter: requestLimiter) {
            try await self.transport.send(request)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CloudProviderError.networkFailure("HTTP \(httpResponse.statusCode)")
        }
    }

    private func signedRequest(
        credential: CloudProviderCredential,
        host: String,
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        body: Data = Data()
    ) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw CloudProviderError.providerFailure("Invalid Huawei Cloud endpoint: \(host)\(path)")
        }

        let date = Self.sdkDateString(now())
        let canonicalQuery = Self.canonicalQueryString(queryItems)
        let canonicalURI = path.hasSuffix("/") ? path : "\(path)"
        let signedHeaders = "host;x-sdk-date"
        let canonicalHeaders = "host:\(host)\nx-sdk-date:\(date)\n"
        let payloadHash = CloudSignature.sha256Hex(body)
        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")
        let stringToSign = [
            "SDK-HMAC-SHA256",
            date,
            CloudSignature.sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")
        let signature = CloudSignature.hmacSHA256Hex(key: Data(credential.secretKey.utf8), data: Data(stringToSign.utf8))
        let authorization = "SDK-HMAC-SHA256 Access=\(credential.secretId), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(date, forHTTPHeaderField: "X-Sdk-Date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        if !body.isEmpty {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func mapHuaweiHTTPError(data: Data, statusCode: Int) -> CloudProviderError {
        if let error = try? decoder.decode(HuaweiErrorResponse.self, from: data) {
            let code = error.errorCode ?? error.code ?? "HTTP \(statusCode)"
            let message = error.errorMessage ?? error.message ?? code
            if code.contains("APIGW.0301") || code.localizedCaseInsensitiveContains("auth") || code.localizedCaseInsensitiveContains("signature") {
                return .authenticationFailed(message)
            }
            if statusCode == 403 || code.localizedCaseInsensitiveContains("forbidden") || code.localizedCaseInsensitiveContains("denied") {
                return .permissionDenied(message)
            }
            if statusCode == 429 || code.localizedCaseInsensitiveContains("throttl") || code.localizedCaseInsensitiveContains("limit") {
                return .rateLimited(message)
            }
            return .providerFailure("\(code): \(message)")
        }
        return .networkFailure("HTTP \(statusCode)")
    }

    private static func encodedRegionId(regionName: String, projectId: String) -> String {
        "\(regionName)|\(projectId)"
    }

    private static func decodeRegionId(_ value: String) -> (regionName: String, projectId: String) {
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        return (value, value)
    }

    private static func canonicalQueryString(_ items: [URLQueryItem]) -> String {
        var pairs: [(String, String)] = []
        for item in items {
            pairs.append((item.name, item.value ?? ""))
        }
        pairs.sort { left, right in
            left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
        }
        var encoded: [String] = []
        for pair in pairs {
            let name = CloudSignature.percentEncode(pair.0)
            let value = CloudSignature.percentEncode(pair.1)
            encoded.append("\(name)=\(value)")
        }
        return encoded.joined(separator: "&")
    }

    private static func sdkDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func millisecondsSince1970(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func huaweiMetricNamespace(_ namespace: String) -> String {
        namespace == "QCE/CVM" ? "SYS.ECS" : namespace
    }

    private static func huaweiMetricName(_ metricName: String) -> String {
        switch metricName {
        case "CPUUsage":
            return "cpu_util"
        case "MemoryUsage":
            return "mem_util"
        case "DiskReadBytes":
            return "disk_read_bytes_rate"
        case "DiskWriteBytes":
            return "disk_write_bytes_rate"
        case "NetworkInBytes":
            return "network_incoming_bytes_rate"
        case "NetworkOutBytes":
            return "network_outgoing_bytes_rate"
        default:
            return metricName
        }
    }

    private static func mapHuaweiSecurityGroupRules(
        _ rules: [HuaweiSecurityGroupRule],
        direction: CloudSecurityGroupRuleDirection
    ) -> [CloudSecurityGroupRule] {
        rules
            .filter { $0.direction?.caseInsensitiveCompare(direction.rawValue) == .orderedSame }
            .map { rule in
                let isIPv6 = rule.remoteIpPrefix?.contains(":") == true
                return CloudSecurityGroupRule(
                    direction: direction,
                    policyIndex: rule.priority,
                    providerRuleId: rule.id,
                    protocolName: rule.protocolName ?? rule.ethertype,
                    port: rule.portRangeText,
                    cidrBlock: isIPv6 ? nil : rule.remoteIpPrefix,
                    ipv6CidrBlock: isIPv6 ? rule.remoteIpPrefix : nil,
                    referencedSecurityGroupId: rule.remoteGroupId,
                    action: rule.action,
                    description: rule.description,
                    modifiedTime: rule.updatedAt ?? rule.createdAt
                )
            }
    }

    private static func huaweiSecurityGroupRulePayload(
        _ preview: CloudSecurityGroupRuleChangePreview
    ) -> HuaweiCreateSecurityGroupRulePayload {
        let rule = preview.proposedRule
        let portRange = huaweiPortRange(rule.port)
        return HuaweiCreateSecurityGroupRulePayload(
            securityGroupRule: HuaweiCreateSecurityGroupRulePayload.Rule(
                securityGroupId: preview.group.securityGroupId,
                direction: rule.direction.rawValue,
                protocolName: huaweiProtocol(rule.protocolName),
                ethertype: rule.ipv6CidrBlock == nil ? "IPv4" : "IPv6",
                portRangeMin: portRange.min,
                portRangeMax: portRange.max,
                remoteIpPrefix: rule.ipv6CidrBlock ?? rule.cidrBlock,
                remoteGroupId: rule.referencedSecurityGroupId,
                action: huaweiAction(rule.action),
                priority: rule.policyIndex ?? 1,
                description: rule.description
            )
        )
    }

    private static func huaweiProtocol(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.uppercased() != "ALL" else { return nil }
        return trimmed.lowercased()
    }

    private static func huaweiAction(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch trimmed {
        case "deny", "drop":
            return "deny"
        default:
            return "allow"
        }
    }

    private static func huaweiPortRange(_ value: String?) -> (min: Int?, max: Int?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.uppercased() != "ALL", trimmed != "-1" else {
            return (nil, nil)
        }
        let parts = trimmed.split(separator: "/", maxSplits: 1).compactMap { Int($0) }
        switch parts.count {
        case 1:
            return (parts[0], parts[0])
        case 2:
            return (parts[0], parts[1])
        default:
            return (nil, nil)
        }
    }

    private static func parseHuaweiDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) {
            return date
        }
        let normalized = text.contains("Z") || text.contains("+") ? text : "\(text)Z"
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: normalized) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: normalized)
    }
}

private enum CloudSignature {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hmacSHA256Hex(key: Data, data: Data) -> String {
        let key = SymmetricKey(data: key)
        return HMAC<SHA256>.authenticationCode(for: data, using: key)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct AlibabaErrorResponse: Decodable {
    var code: String
    var message: String?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case message = "Message"
    }
}

private struct AlibabaDescribeRegionsResponse: Decodable {
    var regions: AlibabaRegions?

    enum CodingKeys: String, CodingKey {
        case regions = "Regions"
    }
}

private struct AlibabaRegions: Decodable {
    var region: [AlibabaRegion]

    enum CodingKeys: String, CodingKey {
        case region = "Region"
    }
}

private struct AlibabaRegion: Decodable {
    var regionId: String
    var localName: String?

    enum CodingKeys: String, CodingKey {
        case regionId = "RegionId"
        case localName = "LocalName"
    }
}

private struct AlibabaDescribeInstancesResponse: Decodable {
    var totalCount: Int?
    var instances: AlibabaInstances?

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case instances = "Instances"
    }
}

private struct AlibabaDescribeMetricListResponse: Decodable {
    var datapoints: String?

    enum CodingKeys: String, CodingKey {
        case datapoints = "Datapoints"
    }
}

private struct AlibabaMetricDatapoint: Decodable {
    var timestamp: Double
    var value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AlibabaDynamicCodingKey.self)
        timestamp = try container.decodeFlexibleDouble(forKeys: ["timestamp", "Timestamp"])
            ?? 0
        value = try container.decodeFlexibleDouble(forKeys: ["Average", "average", "Value", "value", "Maximum", "maximum"])
    }
}

private struct AlibabaDynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == AlibabaDynamicCodingKey {
    func decodeFlexibleDouble(forKeys names: [String]) throws -> Double? {
        for name in names {
            let key = AlibabaDynamicCodingKey(stringValue: name)
            if let double = try? decodeIfPresent(Double.self, forKey: key) {
                return double
            }
            if let int = try? decodeIfPresent(Int.self, forKey: key) {
                return Double(int)
            }
            if let string = try? decodeIfPresent(String.self, forKey: key), let double = Double(string) {
                return double
            }
        }
        return nil
    }
}

private struct AlibabaDescribeDisksResponse: Decodable {
    var totalCount: Int?
    var disks: AlibabaDisks?

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case disks = "Disks"
    }
}

private struct AlibabaDisks: Decodable {
    var disk: [AlibabaDisk]

    enum CodingKeys: String, CodingKey {
        case disk = "Disk"
    }
}

private struct AlibabaDisk: Decodable {
    var diskId: String
    var diskName: String?
    var type: String?
    var category: String?
    var size: Int?
    var status: String?
    var instanceId: String?
    var diskChargeType: String?
    var expiredTime: String?

    enum CodingKeys: String, CodingKey {
        case diskId = "DiskId"
        case diskName = "DiskName"
        case type = "Type"
        case category = "Category"
        case size = "Size"
        case status = "Status"
        case instanceId = "InstanceId"
        case diskChargeType = "DiskChargeType"
        case expiredTime = "ExpiredTime"
    }
}

private struct AlibabaDescribeSnapshotsResponse: Decodable {
    var totalCount: Int?
    var snapshots: AlibabaSnapshots?

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case snapshots = "Snapshots"
    }
}

private struct AlibabaSnapshots: Decodable {
    var snapshot: [AlibabaSnapshot]

    enum CodingKeys: String, CodingKey {
        case snapshot = "Snapshot"
    }
}

private struct AlibabaSnapshot: Decodable {
    var snapshotId: String
    var snapshotName: String?
    var status: String?
    var sourceDiskId: String?
    var diskId: String?
    var sourceDiskSize: Int?
    var size: Int?
    var creationTime: String?
    var createTime: String?

    enum CodingKeys: String, CodingKey {
        case snapshotId = "SnapshotId"
        case snapshotName = "SnapshotName"
        case status = "Status"
        case sourceDiskId = "SourceDiskId"
        case diskId = "DiskId"
        case sourceDiskSize = "SourceDiskSize"
        case size = "Size"
        case creationTime = "CreationTime"
        case createTime = "CreateTime"
    }
}

private struct AlibabaCreateSnapshotResponse: Decodable {
    var snapshotId: String?
    var requestId: String?

    enum CodingKeys: String, CodingKey {
        case snapshotId = "SnapshotId"
        case requestId = "RequestId"
    }
}

private struct AlibabaDeleteSnapshotResponse: Decodable {
    var requestId: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "RequestId"
    }
}

private struct AlibabaDiskActionResponse: Decodable {
    var requestId: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "RequestId"
    }
}

private struct AlibabaInstanceActionResponse: Decodable {
    var requestId: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "RequestId"
    }
}

private struct AlibabaSecurityGroupActionResponse: Decodable {
    var requestId: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "RequestId"
    }
}

private struct AlibabaDescribeSecurityGroupsResponse: Decodable {
    var totalCount: Int?
    var securityGroups: AlibabaSecurityGroups?

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case securityGroups = "SecurityGroups"
    }
}

private struct AlibabaSecurityGroups: Decodable {
    var securityGroup: [AlibabaSecurityGroup]

    enum CodingKeys: String, CodingKey {
        case securityGroup = "SecurityGroup"
    }
}

private struct AlibabaSecurityGroup: Decodable {
    var securityGroupId: String
    var securityGroupName: String?
    var description: String?
    var resourceGroupId: String?
    var creationTime: String?

    enum CodingKeys: String, CodingKey {
        case securityGroupId = "SecurityGroupId"
        case securityGroupName = "SecurityGroupName"
        case description = "Description"
        case resourceGroupId = "ResourceGroupId"
        case creationTime = "CreationTime"
    }
}

private struct AlibabaDescribeSecurityGroupAttributeResponse: Decodable {
    var innerAccessPolicy: String?
    var permissions: AlibabaSecurityGroupPermissions?

    enum CodingKeys: String, CodingKey {
        case innerAccessPolicy = "InnerAccessPolicy"
        case permissions = "Permissions"
    }
}

private struct AlibabaSecurityGroupPermissions: Decodable {
    var permission: [AlibabaSecurityGroupPermission]

    enum CodingKeys: String, CodingKey {
        case permission = "Permission"
    }
}

private struct AlibabaSecurityGroupPermission: Decodable {
    var direction: String?
    var ipProtocol: String?
    var portRange: String?
    var sourceCidrIp: String?
    var destCidrIp: String?
    var ipv6SourceCidrIp: String?
    var ipv6DestCidrIp: String?
    var sourceGroupId: String?
    var destGroupId: String?
    var policy: String?
    var description: String?
    var priority: Int?
    var createTime: String?

    enum CodingKeys: String, CodingKey {
        case direction = "Direction"
        case ipProtocol = "IpProtocol"
        case portRange = "PortRange"
        case sourceCidrIp = "SourceCidrIp"
        case destCidrIp = "DestCidrIp"
        case ipv6SourceCidrIp = "Ipv6SourceCidrIp"
        case ipv6DestCidrIp = "Ipv6DestCidrIp"
        case sourceGroupId = "SourceGroupId"
        case destGroupId = "DestGroupId"
        case policy = "Policy"
        case description = "Description"
        case priority = "Priority"
        case createTime = "CreateTime"
    }

    func matches(direction target: CloudSecurityGroupRuleDirection) -> Bool {
        if let direction {
            return direction.caseInsensitiveCompare(target.rawValue) == .orderedSame
        }
        switch target {
        case .ingress:
            return sourceCidrIp != nil || ipv6SourceCidrIp != nil || sourceGroupId != nil
        case .egress:
            return destCidrIp != nil || ipv6DestCidrIp != nil || destGroupId != nil
        }
    }
}

private struct AlibabaInstances: Decodable {
    var instance: [AlibabaInstance]

    enum CodingKeys: String, CodingKey {
        case instance = "Instance"
    }
}

private struct AlibabaInstance: Decodable {
    var instanceId: String
    var instanceName: String?
    var status: String?
    var instanceType: String?
    var zoneId: String?
    var instanceChargeType: String?
    var expiredTime: String?
    var publicIpAddress: AlibabaIPAddressSet?
    var innerIpAddress: AlibabaIPAddressSet?
    var eipAddress: AlibabaEIPAddress?
    var vpcAttributes: AlibabaVpcAttributes?
    var securityGroupIds: AlibabaSecurityGroupIdSet?

    enum CodingKeys: String, CodingKey {
        case instanceId = "InstanceId"
        case instanceName = "InstanceName"
        case status = "Status"
        case instanceType = "InstanceType"
        case zoneId = "ZoneId"
        case instanceChargeType = "InstanceChargeType"
        case expiredTime = "ExpiredTime"
        case publicIpAddress = "PublicIpAddress"
        case innerIpAddress = "InnerIpAddress"
        case eipAddress = "EipAddress"
        case vpcAttributes = "VpcAttributes"
        case securityGroupIds = "SecurityGroupIds"
    }
}

private struct AlibabaSecurityGroupIdSet: Decodable {
    var securityGroupId: [String]

    enum CodingKeys: String, CodingKey {
        case securityGroupId = "SecurityGroupId"
    }
}

private struct AlibabaIPAddressSet: Decodable {
    var ipAddress: [String]?

    enum CodingKeys: String, CodingKey {
        case ipAddress = "IpAddress"
    }
}

private struct AlibabaEIPAddress: Decodable {
    var ipAddress: String?

    enum CodingKeys: String, CodingKey {
        case ipAddress = "IpAddress"
    }
}

private struct AlibabaVpcAttributes: Decodable {
    var vpcId: String?
    var privateIpAddress: AlibabaIPAddressSet?

    enum CodingKeys: String, CodingKey {
        case vpcId = "VpcId"
        case privateIpAddress = "PrivateIpAddress"
    }
}

private struct HuaweiErrorResponse: Decodable {
    var errorCode: String?
    var errorMessage: String?
    var code: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_msg"
        case code
        case message
    }
}

private struct HuaweiProjectsResponse: Decodable {
    var projects: [HuaweiProject]
}

private struct HuaweiProject: Decodable {
    var id: String?
    var name: String?
    var enabled: Bool?
}

private struct HuaweiServersDetailResponse: Decodable {
    var count: Int?
    var servers: [HuaweiServer]
}

private struct HuaweiVolumesDetailResponse: Decodable {
    var count: Int?
    var volumes: [HuaweiVolume]
}

private struct HuaweiSnapshotsDetailResponse: Decodable {
    var snapshots: [HuaweiSnapshot]
}

private struct HuaweiMetricDataResponse: Decodable {
    var datapoints: [HuaweiMetricDatapoint]

    enum CodingKeys: String, CodingKey {
        case datapoints = "datapoints"
    }
}

private struct HuaweiMetricDatapoint: Decodable {
    var average: Double?
    var max: Double?
    var min: Double?
    var sum: Double?
    var timestamp: Int64
    var unit: String?

    enum CodingKeys: String, CodingKey {
        case average
        case max
        case min
        case sum
        case timestamp
        case unit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        average = try container.decodeFlexibleDoubleIfPresent(forKey: .average)
        max = try container.decodeFlexibleDoubleIfPresent(forKey: .max)
        min = try container.decodeFlexibleDoubleIfPresent(forKey: .min)
        sum = try container.decodeFlexibleDoubleIfPresent(forKey: .sum)
        timestamp = try container.decodeFlexibleInt64IfPresent(forKey: .timestamp) ?? 0
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let double = try? decodeIfPresent(Double.self, forKey: key) {
            return double
        }
        if let int = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(int)
        }
        if let string = try? decodeIfPresent(String.self, forKey: key), let double = Double(string) {
            return double
        }
        return nil
    }

    func decodeFlexibleInt64IfPresent(forKey key: Key) throws -> Int64? {
        if let int64 = try? decodeIfPresent(Int64.self, forKey: key) {
            return int64
        }
        if let int = try? decodeIfPresent(Int.self, forKey: key) {
            return Int64(int)
        }
        if let string = try? decodeIfPresent(String.self, forKey: key), let int64 = Int64(string) {
            return int64
        }
        return nil
    }
}

private struct HuaweiCreateSnapshotPayload: Encodable {
    var snapshot: Snapshot

    struct Snapshot: Encodable {
        var name: String
        var volumeId: String

        enum CodingKeys: String, CodingKey {
            case name
            case volumeId = "volume_id"
        }
    }
}

private struct HuaweiCreateSnapshotResponse: Decodable {
    var snapshot: HuaweiSnapshot?
}

private struct HuaweiDeleteSnapshotResponse: Decodable {
    var jobId: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
    }
}

private struct HuaweiVolumeAttachPayload: Encodable {
    var attach: Attach

    enum CodingKeys: String, CodingKey {
        case attach = "os-attach"
    }

    struct Attach: Encodable {
        var instanceUUID: String
        var mountpoint: String?
        var mode: String?

        enum CodingKeys: String, CodingKey {
            case instanceUUID = "instance_uuid"
            case mountpoint
            case mode
        }
    }
}

private struct HuaweiVolumeDetachPayload: Encodable {
    var detach: Detach

    enum CodingKeys: String, CodingKey {
        case detach = "os-detach"
    }

    struct Detach: Encodable {
        var attachmentId: String?

        enum CodingKeys: String, CodingKey {
            case attachmentId = "attachment_id"
        }
    }
}

private struct HuaweiServerActionServer: Encodable {
    var id: String
}

private struct HuaweiServerStartPayload: Encodable {
    var start: Start

    enum CodingKeys: String, CodingKey {
        case start = "os-start"
    }

    struct Start: Encodable {
        var servers: [HuaweiServerActionServer]
    }
}

private struct HuaweiServerStopPayload: Encodable {
    var stop: Stop

    enum CodingKeys: String, CodingKey {
        case stop = "os-stop"
    }

    struct Stop: Encodable {
        var type: String
        var servers: [HuaweiServerActionServer]
    }
}

private struct HuaweiServerRebootPayload: Encodable {
    var reboot: Reboot

    struct Reboot: Encodable {
        var type: String
        var servers: [HuaweiServerActionServer]
    }
}

private struct HuaweiCreateSecurityGroupRulePayload: Encodable {
    var securityGroupRule: Rule

    enum CodingKeys: String, CodingKey {
        case securityGroupRule = "security_group_rule"
    }

    struct Rule: Encodable {
        var securityGroupId: String
        var direction: String
        var protocolName: String?
        var ethertype: String
        var portRangeMin: Int?
        var portRangeMax: Int?
        var remoteIpPrefix: String?
        var remoteGroupId: String?
        var action: String
        var priority: Int
        var description: String?

        enum CodingKeys: String, CodingKey {
            case securityGroupId = "security_group_id"
            case direction
            case protocolName = "protocol"
            case ethertype
            case portRangeMin = "port_range_min"
            case portRangeMax = "port_range_max"
            case remoteIpPrefix = "remote_ip_prefix"
            case remoteGroupId = "remote_group_id"
            case action
            case priority
            case description
        }
    }
}

private struct HuaweiCreateSecurityGroupRuleResponse: Decodable {
    var securityGroupRule: HuaweiSecurityGroupRule?

    enum CodingKeys: String, CodingKey {
        case securityGroupRule = "security_group_rule"
    }
}

private struct HuaweiSecurityGroupsResponse: Decodable {
    var securityGroups: [HuaweiSecurityGroup]

    enum CodingKeys: String, CodingKey {
        case securityGroups = "security_groups"
    }
}

private struct HuaweiSecurityGroupRulesResponse: Decodable {
    var securityGroupRules: [HuaweiSecurityGroupRule]

    enum CodingKeys: String, CodingKey {
        case securityGroupRules = "security_group_rules"
    }
}

private struct HuaweiSecurityGroup: Decodable {
    var id: String
    var name: String?
    var description: String?
    var enterpriseProjectId: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case enterpriseProjectId = "enterprise_project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct HuaweiSecurityGroupRule: Decodable {
    var id: String?
    var direction: String?
    var ethertype: String?
    var protocolName: String?
    var portRangeMin: Int?
    var portRangeMax: Int?
    var remoteIpPrefix: String?
    var remoteGroupId: String?
    var action: String?
    var priority: Int?
    var description: String?
    var createdAt: String?
    var updatedAt: String?

    var portRangeText: String? {
        switch (portRangeMin, portRangeMax) {
        case let (min?, max?):
            return min == max ? "\(min)" : "\(min)/\(max)"
        case let (min?, nil):
            return "\(min)"
        case let (nil, max?):
            return "\(max)"
        case (nil, nil):
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case direction
        case ethertype
        case protocolName = "protocol"
        case portRangeMin = "port_range_min"
        case portRangeMax = "port_range_max"
        case remoteIpPrefix = "remote_ip_prefix"
        case remoteGroupId = "remote_group_id"
        case action
        case priority
        case description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct HuaweiSnapshot: Decodable {
    var id: String
    var name: String?
    var volumeId: String?
    var size: Int?
    var status: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case volumeId = "volume_id"
        case size
        case status
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        volumeId = try container.decodeIfPresent(String.self, forKey: .volumeId)
        if let intSize = try? container.decodeIfPresent(Int.self, forKey: .size) {
            size = intSize
        } else if let stringSize = try? container.decodeIfPresent(String.self, forKey: .size) {
            size = Int(stringSize)
        } else {
            size = nil
        }
        status = try container.decodeIfPresent(String.self, forKey: .status)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

private struct HuaweiVolume: Decodable {
    var id: String
    var name: String?
    var size: Int?
    var status: String?
    var volumeType: String?
    var attachments: [HuaweiVolumeAttachment]?
    var metadata: HuaweiVolumeMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case size
        case status
        case volumeType = "volume_type"
        case attachments
        case metadata
    }
}

private struct HuaweiVolumeAttachment: Decodable {
    var serverId: String?

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
    }
}

private struct HuaweiVolumeMetadata: Decodable {
    var chargingMode: String?
    var billingMode: String?
    var orderId: String?

    var billingType: String? {
        if let chargingMode, !chargingMode.isEmpty {
            return chargingMode
        }
        if let billingMode, !billingMode.isEmpty {
            return billingMode
        }
        if let orderId, !orderId.isEmpty {
            return "prePaid"
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case chargingMode = "charging_mode"
        case billingMode
        case orderId = "orderID"
    }
}

private struct HuaweiServer: Decodable {
    var id: String
    var name: String?
    var status: String?
    var vmState: String?
    var addresses: HuaweiAddressMap?
    var flavor: HuaweiFlavor?
    var availabilityZone: String?
    var securityGroups: [HuaweiServerSecurityGroup]?
    var metadata: HuaweiServerMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case vmState = "OS-EXT-STS:vm_state"
        case addresses
        case flavor
        case availabilityZone = "OS-EXT-AZ:availability_zone"
        case securityGroups = "security_groups"
        case metadata
    }
}

private struct HuaweiServerSecurityGroup: Decodable {
    var name: String
}

private struct HuaweiAddressMap: Decodable {
    var networks: [String: [HuaweiAddress]]

    init(from decoder: Decoder) throws {
        networks = try [String: [HuaweiAddress]](from: decoder)
    }

    func firstAddress(type: String) -> String? {
        networks.values
            .flatMap { $0 }
            .first { $0.type?.localizedCaseInsensitiveCompare(type) == .orderedSame }?
            .addr
    }
}

private struct HuaweiAddress: Decodable {
    var addr: String?
    var type: String?

    enum CodingKeys: String, CodingKey {
        case addr
        case type = "OS-EXT-IPS:type"
    }
}

private struct HuaweiFlavor: Decodable {
    var id: String?
}

private struct HuaweiServerMetadata: Decodable {
    var chargingMode: String?

    enum CodingKeys: String, CodingKey {
        case chargingMode = "charging_mode"
    }
}

private struct TencentCloudEndpoint {
    var host: String
    var service: String
    var action: String
    var version: String
    var region: String?
}

private struct TencentDescribeRegionsPayload: Encodable {
    var product: String
    var scene: Int

    enum CodingKeys: String, CodingKey {
        case product = "Product"
        case scene = "Scene"
    }
}

private struct TencentDescribeInstancesPayload: Encodable {
    var offset: Int
    var limit: Int

    enum CodingKeys: String, CodingKey {
        case offset = "Offset"
        case limit = "Limit"
    }
}

private struct TencentInstanceIdsPayload: Encodable {
    var instanceIds: [String]

    enum CodingKeys: String, CodingKey {
        case instanceIds = "InstanceIds"
    }
}

private struct TencentPagedPayload: Encodable {
    var offset: Int
    var limit: Int

    enum CodingKeys: String, CodingKey {
        case offset = "Offset"
        case limit = "Limit"
    }
}

private struct TencentDescribeSecurityGroupsPayload: Encodable {
    var offset: Int
    var limit: Int

    enum CodingKeys: String, CodingKey {
        case offset = "Offset"
        case limit = "Limit"
    }
}

private struct TencentDescribeSecurityGroupPoliciesPayload: Encodable {
    var securityGroupId: String

    enum CodingKeys: String, CodingKey {
        case securityGroupId = "SecurityGroupId"
    }
}

private struct TencentSecurityGroupPolicyMutationPayload: Encodable {
    var securityGroupId: String
    var securityGroupPolicySet: TencentSecurityGroupPolicyMutationSet

    enum CodingKeys: String, CodingKey {
        case securityGroupId = "SecurityGroupId"
        case securityGroupPolicySet = "SecurityGroupPolicySet"
    }
}

private struct TencentSecurityGroupPolicyMutationSet: Encodable {
    var ingress: [TencentSecurityGroupPolicyPayload]?
    var egress: [TencentSecurityGroupPolicyPayload]?

    init(preview: CloudSecurityGroupRuleChangePreview) {
        let policy = TencentSecurityGroupPolicyPayload(rule: preview.proposedRule)
        switch preview.proposedRule.direction {
        case .ingress:
            ingress = [policy]
            egress = nil
        case .egress:
            ingress = nil
            egress = [policy]
        }
    }

    enum CodingKeys: String, CodingKey {
        case ingress = "Ingress"
        case egress = "Egress"
    }
}

private struct TencentSecurityGroupPolicyPayload: Encodable {
    var policyIndex: Int?
    var protocolName: String?
    var port: String?
    var cidrBlock: String?
    var ipv6CidrBlock: String?
    var securityGroupId: String?
    var action: String?
    var policyDescription: String?

    init(rule: CloudSecurityGroupRule) {
        policyIndex = rule.policyIndex
        protocolName = rule.protocolName
        port = rule.port
        cidrBlock = rule.cidrBlock
        ipv6CidrBlock = rule.ipv6CidrBlock
        securityGroupId = rule.referencedSecurityGroupId
        action = rule.action
        policyDescription = rule.description
    }

    enum CodingKeys: String, CodingKey {
        case policyIndex = "PolicyIndex"
        case protocolName = "Protocol"
        case port = "Port"
        case cidrBlock = "CidrBlock"
        case ipv6CidrBlock = "Ipv6CidrBlock"
        case securityGroupId = "SecurityGroupId"
        case action = "Action"
        case policyDescription = "PolicyDescription"
    }
}

private struct TencentGetMonitorDataPayload: Encodable {
    var namespace: String
    var metricName: String
    var instances: [TencentMonitorInstance]
    var period: Int
    var startTime: String
    var endTime: String

    enum CodingKeys: String, CodingKey {
        case namespace = "Namespace"
        case metricName = "MetricName"
        case instances = "Instances"
        case period = "Period"
        case startTime = "StartTime"
        case endTime = "EndTime"
    }
}

private struct TencentCreateSnapshotPayload: Encodable {
    var diskId: String
    var snapshotName: String

    enum CodingKeys: String, CodingKey {
        case diskId = "DiskId"
        case snapshotName = "SnapshotName"
    }
}

private struct TencentDeleteSnapshotsPayload: Encodable {
    var snapshotIds: [String]

    enum CodingKeys: String, CodingKey {
        case snapshotIds = "SnapshotIds"
    }
}

private struct TencentAttachDisksPayload: Encodable {
    var diskIds: [String]
    var instanceId: String

    enum CodingKeys: String, CodingKey {
        case diskIds = "DiskIds"
        case instanceId = "InstanceId"
    }
}

private struct TencentDetachDisksPayload: Encodable {
    var diskIds: [String]

    enum CodingKeys: String, CodingKey {
        case diskIds = "DiskIds"
    }
}

private struct TencentMonitorInstance: Encodable {
    var dimensions: [TencentMonitorDimension]

    enum CodingKeys: String, CodingKey {
        case dimensions = "Dimensions"
    }
}

private struct TencentMonitorDimension: Encodable {
    var name: String
    var value: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case value = "Value"
    }
}

private struct TencentCloudEnvelope<Response: Decodable>: Decodable {
    var response: Response

    enum CodingKeys: String, CodingKey {
        case response = "Response"
    }
}

private struct TencentCloudAPIError: Decodable, Equatable {
    var code: String
    var message: String

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case message = "Message"
    }
}

private struct TencentDescribeRegionsResponse: Decodable {
    var totalCount: Int?
    var regionSet: [TencentRegionInfo]?
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case regionSet = "RegionSet"
        case error = "Error"
    }
}

private struct TencentRegionInfo: Decodable {
    var region: String
    var regionName: String
    var regionState: String?

    enum CodingKeys: String, CodingKey {
        case region = "Region"
        case regionName = "RegionName"
        case regionState = "RegionState"
    }
}

private struct TencentDescribeInstancesResponse: Decodable {
    var totalCount: Int?
    var instanceSet: [TencentInstance]?
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case instanceSet = "InstanceSet"
        case error = "Error"
    }
}

private struct TencentGetMonitorDataResponse: Decodable {
    var metricName: String?
    var dataPoints: [TencentMonitorDataPoint]?
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case metricName = "MetricName"
        case dataPoints = "DataPoints"
        case error = "Error"
    }
}

private struct TencentDescribeSecurityGroupsResponse: Decodable {
    var totalCount: Int?
    var securityGroupSet: [TencentSecurityGroup]?
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case securityGroupSet = "SecurityGroupSet"
        case error = "Error"
    }
}

private struct TencentDescribeSecurityGroupPoliciesResponse: Decodable {
    var securityGroupPolicySet: TencentSecurityGroupPolicySet?
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case securityGroupPolicySet = "SecurityGroupPolicySet"
        case error = "Error"
    }
}

private struct TencentSecurityGroupPolicyMutationResponse: Decodable {
    var requestId: String?
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case requestId = "RequestId"
        case error = "Error"
    }
}

private struct TencentDescribeDisksResponse: Decodable {
    var totalCount: Int?
    var diskSet: [TencentDisk]?
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case diskSet = "DiskSet"
        case error = "Error"
    }
}

private struct TencentDescribeSnapshotsResponse: Decodable {
    var totalCount: Int?
    var snapshotSet: [TencentSnapshot]?
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case snapshotSet = "SnapshotSet"
        case error = "Error"
    }
}

private struct TencentCreateSnapshotResponse: Decodable {
    var snapshotId: String?
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case snapshotId = "SnapshotId"
        case error = "Error"
    }
}

private struct TencentDeleteSnapshotsResponse: Decodable {
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case error = "Error"
    }
}

private struct TencentAttachDisksResponse: Decodable {
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case error = "Error"
    }
}

private struct TencentDetachDisksResponse: Decodable {
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case error = "Error"
    }
}

private struct TencentInstanceActionResponse: Decodable {
    var error: TencentCloudAPIError?

    enum CodingKeys: String, CodingKey {
        case error = "Error"
    }
}

private struct TencentMonitorDataPoint: Decodable {
    var dimensions: [TencentMonitorDimensionValue]?
    var timestamps: [Int]
    var values: [Double]

    enum CodingKeys: String, CodingKey {
        case dimensions = "Dimensions"
        case timestamps = "Timestamps"
        case values = "Values"
    }
}

private struct TencentSecurityGroup: Decodable {
    var securityGroupId: String
    var securityGroupName: String
    var securityGroupDesc: String?
    var projectId: Int?
    var isDefault: Bool?
    var createdTime: String?
    var updateTime: String?

    enum CodingKeys: String, CodingKey {
        case securityGroupId = "SecurityGroupId"
        case securityGroupName = "SecurityGroupName"
        case securityGroupDesc = "SecurityGroupDesc"
        case projectId = "ProjectId"
        case isDefault = "IsDefault"
        case createdTime = "CreatedTime"
        case updateTime = "UpdateTime"
    }
}

private struct TencentSecurityGroupPolicySet: Decodable {
    var version: String?
    var ingress: [TencentSecurityGroupPolicy]?
    var egress: [TencentSecurityGroupPolicy]?

    enum CodingKeys: String, CodingKey {
        case version = "Version"
        case ingress = "Ingress"
        case egress = "Egress"
    }
}

private struct TencentSecurityGroupPolicy: Decodable {
    var policyIndex: Int?
    var protocolName: String?
    var port: String?
    var cidrBlock: String?
    var ipv6CidrBlock: String?
    var securityGroupId: String?
    var action: String?
    var policyDescription: String?
    var modifyTime: String?

    enum CodingKeys: String, CodingKey {
        case policyIndex = "PolicyIndex"
        case protocolName = "Protocol"
        case port = "Port"
        case cidrBlock = "CidrBlock"
        case ipv6CidrBlock = "Ipv6CidrBlock"
        case securityGroupId = "SecurityGroupId"
        case action = "Action"
        case policyDescription = "PolicyDescription"
        case modifyTime = "ModifyTime"
    }
}

private struct TencentMonitorDimensionValue: Decodable {
    var name: String
    var value: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case value = "Value"
    }
}

private struct TencentDisk: Decodable {
    var diskId: String
    var diskName: String?
    var diskType: String?
    var diskUsage: String?
    var diskSize: Int?
    var diskState: String?
    var instanceId: String?
    var diskChargeType: String?
    var deadlineTime: String?

    enum CodingKeys: String, CodingKey {
        case diskId = "DiskId"
        case diskName = "DiskName"
        case diskType = "DiskType"
        case diskUsage = "DiskUsage"
        case diskSize = "DiskSize"
        case diskState = "DiskState"
        case instanceId = "InstanceId"
        case diskChargeType = "DiskChargeType"
        case deadlineTime = "DeadlineTime"
    }
}

private struct TencentSnapshot: Decodable {
    var snapshotId: String
    var snapshotName: String?
    var snapshotState: String?
    var diskId: String?
    var diskSize: Int?
    var createTime: String?

    enum CodingKeys: String, CodingKey {
        case snapshotId = "SnapshotId"
        case snapshotName = "SnapshotName"
        case snapshotState = "SnapshotState"
        case diskId = "DiskId"
        case diskSize = "DiskSize"
        case createTime = "CreateTime"
    }
}

private struct TencentInstance: Decodable {
    var instanceId: String
    var instanceName: String?
    var instanceState: String?
    var instanceType: String?
    var publicIpAddresses: [String]?
    var privateIpAddresses: [String]?
    var placement: TencentPlacement?
    var virtualPrivateCloud: TencentVirtualPrivateCloud?
    var securityGroupIds: [String]?
    var instanceChargeType: String?
    var expiredTime: String?
    var rawJSONString: String?

    enum CodingKeys: String, CodingKey {
        case instanceId = "InstanceId"
        case instanceName = "InstanceName"
        case instanceState = "InstanceState"
        case instanceType = "InstanceType"
        case publicIpAddresses = "PublicIpAddresses"
        case privateIpAddresses = "PrivateIpAddresses"
        case placement = "Placement"
        case virtualPrivateCloud = "VirtualPrivateCloud"
        case securityGroupIds = "SecurityGroupIds"
        case instanceChargeType = "InstanceChargeType"
        case expiredTime = "ExpiredTime"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        instanceId = try container.decode(String.self, forKey: .instanceId)
        instanceName = try container.decodeIfPresent(String.self, forKey: .instanceName)
        instanceState = try container.decodeIfPresent(String.self, forKey: .instanceState)
        instanceType = try container.decodeIfPresent(String.self, forKey: .instanceType)
        publicIpAddresses = try container.decodeIfPresent([String].self, forKey: .publicIpAddresses)
        privateIpAddresses = try container.decodeIfPresent([String].self, forKey: .privateIpAddresses)
        placement = try container.decodeIfPresent(TencentPlacement.self, forKey: .placement)
        virtualPrivateCloud = try container.decodeIfPresent(TencentVirtualPrivateCloud.self, forKey: .virtualPrivateCloud)
        securityGroupIds = try container.decodeIfPresent([String].self, forKey: .securityGroupIds)
        instanceChargeType = try container.decodeIfPresent(String.self, forKey: .instanceChargeType)
        expiredTime = try container.decodeIfPresent(String.self, forKey: .expiredTime)
        rawJSONString = nil
    }
}

private struct TencentPlacement: Decodable {
    var zone: String?

    enum CodingKeys: String, CodingKey {
        case zone = "Zone"
    }
}

private struct TencentVirtualPrivateCloud: Decodable {
    var vpcId: String?

    enum CodingKeys: String, CodingKey {
        case vpcId = "VpcId"
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var firstLine: String? {
        split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
