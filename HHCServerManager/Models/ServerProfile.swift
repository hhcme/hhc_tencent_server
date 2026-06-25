import Foundation

enum SSHAuthType: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password:
            "Password"
        case .privateKey:
            "Private Key"
        }
    }
}

struct ServerProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authType: SSHAuthType
    var keychainRef: String
    var groupName: String?
    var createdAt: Date
    var updatedAt: Date

    var endpoint: String {
        "\(username)@\(host):\(port)"
    }
}

struct TrustedHostKey: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var serverId: UUID
    var host: String
    var port: Int
    var algorithm: String
    var fingerprintSHA256: String
    var rawPublicKey: String
    var trustedAt: Date
}

struct HostKeyInfo: Equatable, Hashable {
    var host: String
    var port: Int
    var algorithm: String
    var fingerprintSHA256: String
    var rawPublicKey: String
}

struct CommandResult: Equatable, Hashable {
    var command: String
    var stdout: String
    var stderr: String
    var exitCode: Int32
    var duration: TimeInterval
}

struct CommandHistoryEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var serverId: UUID
    var command: String
    var exitCode: Int32?
    var duration: TimeInterval?
    var createdAt: Date
}

struct OperationLogEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var scope: String
    var action: String
    var targetId: String?
    var status: String
    var message: String?
    var createdAt: Date
}

enum SSHConnectionState: Equatable, Hashable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var displayName: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .connecting:
            "Connecting"
        case .connected:
            "Connected"
        case .failed:
            "Failed"
        }
    }
}

enum CredentialInput: Equatable {
    case password(String)
    case privateKey(data: Data, passphrase: String?)
}

enum CredentialUpdate: Equatable {
    case keepExisting
    case replace(CredentialInput)
}
