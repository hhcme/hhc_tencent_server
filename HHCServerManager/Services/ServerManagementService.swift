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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
