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

struct ServerCapabilities: Equatable, Hashable, Sendable {
    var osName: String?
    var osVersion: String?
    var kernelVersion: String?
    var hasProc: Bool
    var hasSystemd: Bool
    var hasSFTP: Bool
    var detectedAt: Date
}

struct DashboardMetric: Identifiable, Equatable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var value: String
    var unit: String?
    var source: String
}

struct CloudMetricQuery: Equatable, Hashable, Sendable {
    var namespace: String
    var metricName: String
    var instanceId: String
    var regionId: String
    var period: Int
    var startTime: Date
    var endTime: Date
}

struct CloudMetricSeries: Equatable, Hashable, Sendable {
    var metricName: String
    var instanceId: String
    var regionId: String
    var unit: String?
    var values: [Double]
    var timestamps: [Date]
}

struct DashboardWarning: Identifiable, Equatable, Hashable, Sendable {
    var id: String { source }
    var source: String
    var message: String
}

struct ServerDashboardSnapshot: Equatable, Hashable, Sendable {
    var capabilities: ServerCapabilities
    var metrics: [DashboardMetric]
    var warnings: [DashboardWarning]
    var capturedAt: Date
}

enum RemoteFileKind: String, Equatable, Hashable {
    case directory
    case file
    case symlink
    case other
}

struct RemoteFileEntry: Identifiable, Equatable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var kind: RemoteFileKind
    var size: Int64?
    var modifiedAt: Date?
    var permissions: String
}

struct RemoteDirectoryListing: Equatable, Hashable {
    var path: String
    var entries: [RemoteFileEntry]
    var capturedAt: Date
}

struct RemoteTextFile: Identifiable, Equatable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var content: String
    var byteCount: Int
    var capturedAt: Date
}

struct RemoteTextSaveResult: Equatable, Hashable, Sendable {
    var path: String
    var backupPath: String?
}

struct RemoteFileTransferResult: Equatable, Hashable, Sendable {
    var remotePath: String
    var localPath: String
    var byteCount: Int64?
    var duration: TimeInterval
}

enum RemoteFileTransferDirection: String, Equatable, Hashable, Sendable {
    case upload
    case download

    var displayName: String {
        switch self {
        case .upload:
            "Upload"
        case .download:
            "Download"
        }
    }
}

enum RemoteFileTransferStatus: String, Equatable, Hashable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled
}

struct RemoteFileTransferJob: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var direction: RemoteFileTransferDirection
    var remotePath: String
    var localPath: String
    var status: RemoteFileTransferStatus
    var byteCount: Int64?
    var message: String?
    var startedAt: Date
    var finishedAt: Date?
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

enum CloudProviderID: String, Codable, CaseIterable, Identifiable {
    case tencentCloud = "tencent_cloud"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tencentCloud:
            "Tencent Cloud"
        }
    }
}

enum CloudCapability: String, Codable, CaseIterable, Identifiable {
    case regions
    case instanceDiscovery
    case instanceMetadata
    case cloudMetrics
    case securityGroups
    case powerActions

    var id: String { rawValue }
}

struct CloudProviderAccount: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var providerId: CloudProviderID
    var displayName: String
    var keychainRef: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct CloudProviderCredential: Equatable, Hashable {
    var secretId: String
    var secretKey: String
}

struct CloudInstanceLink: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var serverId: UUID?
    var accountId: UUID
    var providerId: CloudProviderID
    var regionId: String
    var instanceId: String
    var displayName: String?
    var publicIp: String?
    var privateIp: String?
    var status: String?
    var instanceType: String?
    var zoneId: String?
    var vpcId: String?
    var rawJSON: String?
    var lastSyncedAt: Date?
}

struct CloudRegion: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var displayName: String
    var available: Bool
}

struct CloudProviderInstance: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var providerId: CloudProviderID
    var regionId: String
    var displayName: String?
    var publicIp: String?
    var privateIp: String?
    var status: String?
    var instanceType: String?
    var zoneId: String?
    var vpcId: String?
    var rawJSON: String?
}

extension CloudInstanceLink {
    mutating func apply(instance: CloudProviderInstance, accountId: UUID, syncedAt: Date) {
        self.accountId = accountId
        providerId = instance.providerId
        regionId = instance.regionId
        instanceId = instance.id
        displayName = instance.displayName
        publicIp = instance.publicIp
        privateIp = instance.privateIp
        status = instance.status
        instanceType = instance.instanceType
        zoneId = instance.zoneId
        vpcId = instance.vpcId
        rawJSON = instance.rawJSON
        lastSyncedAt = syncedAt
    }
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
