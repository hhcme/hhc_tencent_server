import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            "Keychain operation failed with status \(status)."
        case .itemNotFound:
            "Keychain item was not found."
        }
    }
}

protocol ServerCredentialStore: Sendable {
    func savePassword(_ password: String, keychainRef: String) throws
    func readPassword(keychainRef: String) throws -> String?
    func savePrivateKey(_ data: Data, passphrase: String?, keychainRef: String) throws
    func readPrivateKey(keychainRef: String) throws -> Data?
    func readPrivateKeyPassphrase(keychainRef: String) throws -> String?
    func deleteCredentials(keychainRef: String)
    func saveWebhookSecret(_ secret: String, keychainRef: String) throws
    func readWebhookSecret(keychainRef: String) throws -> String?
    func deleteWebhookSecret(keychainRef: String)
}

final class KeychainService: ServerCredentialStore, @unchecked Sendable {
    private let serviceName: String

    init(serviceName: String = "me.hhc.HHCServerManager") {
        self.serviceName = serviceName
    }

    func savePassword(_ password: String, keychainRef: String) throws {
        guard let data = password.data(using: .utf8) else { return }
        try save(data, account: "ssh_password_\(keychainRef)")
    }

    func readPassword(keychainRef: String) throws -> String? {
        guard let data = try readData(account: "ssh_password_\(keychainRef)") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func savePrivateKey(_ data: Data, passphrase: String?, keychainRef: String) throws {
        try save(data, account: "ssh_private_key_\(keychainRef)")
        if let passphrase, !passphrase.isEmpty {
            try save(Data(passphrase.utf8), account: "ssh_private_key_passphrase_\(keychainRef)")
        } else {
            delete(account: "ssh_private_key_passphrase_\(keychainRef)")
        }
    }

    func readPrivateKey(keychainRef: String) throws -> Data? {
        try readData(account: "ssh_private_key_\(keychainRef)")
    }

    func readPrivateKeyPassphrase(keychainRef: String) throws -> String? {
        guard let data = try readData(account: "ssh_private_key_passphrase_\(keychainRef)") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteCredentials(keychainRef: String) {
        delete(account: "ssh_password_\(keychainRef)")
        delete(account: "ssh_private_key_\(keychainRef)")
        delete(account: "ssh_private_key_passphrase_\(keychainRef)")
    }

    func saveCloudCredential(_ credential: CloudProviderCredential, keychainRef: String) throws {
        try save(Data(credential.secretId.utf8), account: "cloud_secret_id_\(keychainRef)")
        try save(Data(credential.secretKey.utf8), account: "cloud_secret_key_\(keychainRef)")
    }

    func readCloudCredential(keychainRef: String) throws -> CloudProviderCredential? {
        guard
            let secretIdData = try readData(account: "cloud_secret_id_\(keychainRef)"),
            let secretKeyData = try readData(account: "cloud_secret_key_\(keychainRef)"),
            let secretId = String(data: secretIdData, encoding: .utf8),
            let secretKey = String(data: secretKeyData, encoding: .utf8)
        else {
            return nil
        }
        return CloudProviderCredential(secretId: secretId, secretKey: secretKey)
    }

    func deleteCloudCredential(keychainRef: String) {
        delete(account: "cloud_secret_id_\(keychainRef)")
        delete(account: "cloud_secret_key_\(keychainRef)")
    }

    func saveWebhookSecret(_ secret: String, keychainRef: String) throws {
        try save(Data(secret.utf8), account: "deployment_webhook_secret_\(keychainRef)")
    }

    func readWebhookSecret(keychainRef: String) throws -> String? {
        guard let data = try readData(account: "deployment_webhook_secret_\(keychainRef)") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteWebhookSecret(keychainRef: String) {
        delete(account: "deployment_webhook_secret_\(keychainRef)")
    }

    private func save(_ data: Data, account: String) throws {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func readData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        return result as? Data
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
