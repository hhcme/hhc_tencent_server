import Foundation

final class ServerManagementService: @unchecked Sendable {
    private let repository: ServerRepository
    private let keychain: KeychainService

    init(repository: ServerRepository, keychain: KeychainService) {
        self.repository = repository
        self.keychain = keychain
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
        let id = UUID()
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
        if case let .replace(credential) = credentialUpdate {
            switch credential {
            case let .password(password):
                try keychain.savePassword(password, keychainRef: existing.keychainRef)
            case let .privateKey(data, passphrase):
                try keychain.savePrivateKey(data, passphrase: passphrase, keychainRef: existing.keychainRef)
            }
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
        try repository.upsert(updated)
        return updated
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

protocol CloudProviderAdapter: Sendable {
    var providerId: CloudProviderID { get }
    var displayName: String { get }
    var capabilities: Set<CloudCapability> { get }

    func validateCredential(_ credential: CloudProviderCredential) async throws
    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion]
    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance]
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

enum CloudProviderRequestRunner {
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
