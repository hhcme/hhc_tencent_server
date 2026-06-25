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

struct SystemdUnit: Identifiable, Equatable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var loadState: String
    var activeState: String
    var subState: String
    var description: String

    var isRunning: Bool {
        activeState == "active"
    }
}

struct SystemdUnitList: Equatable, Hashable, Sendable {
    var units: [SystemdUnit]
    var capturedAt: Date
}

enum SystemdUnitAction: String, CaseIterable, Identifiable, Sendable {
    case start
    case stop
    case restart
    case reload

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .start:
            "Start"
        case .stop:
            "Stop"
        case .restart:
            "Restart"
        case .reload:
            "Reload"
        }
    }
}

struct SystemdJournalLog: Equatable, Hashable, Sendable {
    var unitName: String
    var text: String
    var capturedAt: Date
}

struct CronEntry: Identifiable, Equatable, Hashable, Sendable {
    var id: String { originalLine }
    var schedule: String
    var command: String
    var isEnabled: Bool
    var originalLine: String
}

struct CronTabSnapshot: Equatable, Hashable, Sendable {
    var entries: [CronEntry]
    var rawText: String
    var capturedAt: Date
}

enum CronEntryAction: String, CaseIterable, Identifiable, Sendable {
    case enable
    case disable
    case delete

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .enable:
            "Enable"
        case .disable:
            "Disable"
        case .delete:
            "Delete"
        }
    }
}

struct NginxConfigFile: Identifiable, Equatable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var size: Int64?
    var modifiedAt: Date?
}

struct NginxConfigContent: Equatable, Hashable, Sendable {
    var file: NginxConfigFile
    var content: String
    var byteCount: Int
    var capturedAt: Date
}

struct NginxConfigList: Equatable, Hashable, Sendable {
    var files: [NginxConfigFile]
    var capturedAt: Date
}

struct NginxTestResult: Equatable, Hashable, Sendable {
    var succeeded: Bool
    var output: String
    var capturedAt: Date
}

struct NginxConfigSaveResult: Equatable, Hashable, Sendable {
    var file: NginxConfigFile
    var content: String
    var backupPath: String
    var testResult: NginxTestResult
    var rolledBack: Bool
    var capturedAt: Date
}

enum FirewallBackend: String, CaseIterable, Identifiable, Sendable {
    case firewalld
    case ufw
    case nft
    case iptables

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .firewalld:
            "firewalld"
        case .ufw:
            "ufw"
        case .nft:
            "nftables"
        case .iptables:
            "iptables"
        }
    }
}

struct FirewallSnapshot: Equatable, Hashable, Sendable {
    var backend: FirewallBackend
    var status: String
    var rulesText: String
    var capturedAt: Date
}

struct EnvironmentFile: Identifiable, Equatable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var size: Int64?
    var modifiedAt: Date?
    var source: String
}

struct EnvironmentFileList: Equatable, Hashable, Sendable {
    var files: [EnvironmentFile]
    var capturedAt: Date
}

struct EnvironmentFileContent: Equatable, Hashable, Sendable {
    var file: EnvironmentFile
    var content: String
    var byteCount: Int
    var capturedAt: Date
}

struct EnvironmentFileSaveResult: Equatable, Hashable, Sendable {
    var file: EnvironmentFile
    var content: String
    var backupPath: String
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

struct RemoteChangeLogEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var serverId: UUID?
    var providerId: CloudProviderID?
    var targetType: String
    var targetId: String?
    var action: String
    var beforeSnapshot: String?
    var afterSnapshot: String?
    var status: String
    var message: String?
    var createdAt: Date
}

struct DeploymentProject: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var serverId: UUID
    var name: String
    var repositoryURL: String
    var branch: String
    var deployPath: String
    var buildCommand: String?
    var restartCommand: String?
    var healthCheckCommand: String?
    var webhookEnabled: Bool
    var webhookSecretRef: String?
    var createdAt: Date
    var updatedAt: Date
}

enum DeploymentTriggerType: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case rollback
    case webhook

    var id: String { rawValue }
}

enum DeploymentRunStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled

    var id: String { rawValue }
}

struct DeploymentRun: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var projectId: UUID
    var triggerType: DeploymentTriggerType
    var requestedRef: String?
    var previousCommit: String?
    var targetCommit: String?
    var status: DeploymentRunStatus
    var startedAt: Date
    var finishedAt: Date?
    var summary: String?
}

enum DeploymentLogStream: String, Codable, CaseIterable, Identifiable, Sendable {
    case stdout
    case stderr
    case system

    var id: String { rawValue }
}

struct DeploymentLogEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var runId: UUID
    var stepName: String
    var stream: DeploymentLogStream
    var message: String
    var createdAt: Date
}

struct DeploymentCommandStep: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var command: String
    var isDestructive: Bool
    var description: String
}

struct DeploymentCommandPlan: Codable, Equatable, Hashable, Sendable {
    var project: DeploymentProject
    var allowedRoot: String
    var steps: [DeploymentCommandStep]

    var commandPreview: String {
        steps.map { step in
            "# \(step.name)\n\(step.command)"
        }.joined(separator: "\n\n")
    }
}

enum RemoteOperationRiskLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high
    case critical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        case .critical:
            "Critical"
        }
    }
}

struct RemoteOperationRisk: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var level: RemoteOperationRiskLevel
    var title: String
    var target: String
    var commandPreview: String?
    var impact: [String]
    var recovery: String?
    var auditTargetType: String
    var auditAction: String

    var confirmationMessage: String {
        var lines = [
            "Risk: \(level.displayName)",
            "Target: \(target)",
        ]
        if let commandPreview, !commandPreview.isEmpty {
            lines.append("Command: \(commandPreview)")
        }
        if !impact.isEmpty {
            lines.append("Impact: \(impact.joined(separator: " "))")
        }
        if let recovery, !recovery.isEmpty {
            lines.append("Recovery: \(recovery)")
        }
        lines.append("This action will be written to the remote change audit log when supported.")
        return lines.joined(separator: "\n")
    }
}

enum RemoteOperationRiskFactory {
    static func moveToTrash(entry: RemoteFileEntry) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "remote-file-trash-\(entry.id)",
            level: .medium,
            title: "Move to Trash",
            target: entry.path,
            commandPreview: "mv -n <target> ~/.hhc-server-manager-trash/",
            impact: ["The selected remote item will disappear from its current directory."],
            recovery: "Restore it manually from ~/.hhc-server-manager-trash if needed.",
            auditTargetType: "remote_file",
            auditAction: "move_to_trash"
        )
    }

    static func changePermissions(entry: RemoteFileEntry, mode: String) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "remote-file-chmod-\(entry.id)-\(mode)",
            level: mode.hasSuffix("777") || mode.hasSuffix("666") ? .high : .medium,
            title: "Change Permissions",
            target: entry.path,
            commandPreview: "chmod \(mode) <target>",
            impact: ["Permission changes can expose files or break service access."],
            recovery: "Reapply the previous mode shown in the file list if the change is wrong.",
            auditTargetType: "remote_file",
            auditAction: "chmod"
        )
    }

    static func systemd(action: SystemdUnitAction, unit: SystemdUnit) -> RemoteOperationRisk {
        let level: RemoteOperationRiskLevel = action == .stop || action == .restart ? .high : .medium
        return RemoteOperationRisk(
            id: "systemd-\(action.rawValue)-\(unit.id)",
            level: level,
            title: "\(action.displayName) Service",
            target: unit.name,
            commandPreview: "systemctl \(action.rawValue) \(unit.name)",
            impact: ["Service state may change immediately and connected users may be interrupted."],
            recovery: "Use the inverse systemd action or inspect journal logs if the service fails.",
            auditTargetType: "systemd",
            auditAction: action.rawValue
        )
    }

    static func cron(action: CronEntryAction, entry: CronEntry) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "cron-\(action.rawValue)-\(entry.id)",
            level: action == .delete ? .high : .medium,
            title: "\(action.displayName) Cron Entry",
            target: entry.originalLine,
            commandPreview: "crontab <updated file>",
            impact: ["The remote user's scheduled task list will be rewritten."],
            recovery: "A remote crontab backup is created before write operations.",
            auditTargetType: "cron",
            auditAction: action.rawValue
        )
    }

    static func saveNginxConfig(path: String) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "nginx-save-\(path)",
            level: .high,
            title: "Save Nginx Config",
            target: path,
            commandPreview: "backup -> write temp file -> nginx -t -> rollback on failure",
            impact: ["The selected Nginx configuration file will be replaced on the remote server."],
            recovery: "A remote backup is created and failed nginx -t results are rolled back automatically.",
            auditTargetType: "nginx",
            auditAction: "save"
        )
    }

    static func reloadNginx(path: String?) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "nginx-reload-\(path ?? "nginx")",
            level: .medium,
            title: "Reload Nginx",
            target: path ?? "nginx",
            commandPreview: "nginx -t && nginx -s reload",
            impact: ["Nginx will reload active configuration after a successful config test."],
            recovery: "Fix the config and reload again if nginx -t fails.",
            auditTargetType: "nginx",
            auditAction: "reload"
        )
    }

    static func saveEnvironmentFile(path: String) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "environment-save-\(path)",
            level: .high,
            title: "Save Environment File",
            target: path,
            commandPreview: "backup -> replace selected file",
            impact: ["Environment changes may affect later service starts, deploys, or shell commands."],
            recovery: "A remote backup is created before replacing the file.",
            auditTargetType: "environment",
            auditAction: "save"
        )
    }

    static func securityGroupChange(_ preview: CloudSecurityGroupRuleChangePreview) -> RemoteOperationRisk {
        let level: RemoteOperationRiskLevel
        if preview.warnings.contains(where: { $0.lowercased().contains("public internet") }) {
            level = .critical
        } else if preview.proposedRule.direction == .ingress && preview.proposedRule.action == "ACCEPT" {
            level = .high
        } else {
            level = .medium
        }
        return RemoteOperationRisk(
            id: "security-group-\(preview.action.rawValue)-\(preview.group.securityGroupId)-\(preview.proposedRule.id)",
            level: level,
            title: "\(preview.action.displayName) Security Group Rule",
            target: "\(preview.group.name) (\(preview.group.securityGroupId))",
            commandPreview: preview.commandPreview,
            impact: preview.impact,
            recovery: "Review the generated diff before enabling future write operations. No cloud-side change is executed by this preview.",
            auditTargetType: "security_group",
            auditAction: preview.action.rawValue
        )
    }
}

enum CloudProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case tencentCloud = "tencent_cloud"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tencentCloud:
            "Tencent Cloud"
        }
    }
}

enum CloudCapability: String, Codable, CaseIterable, Identifiable, Sendable {
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

struct CloudSecurityGroup: Identifiable, Equatable, Hashable, Sendable {
    var id: String { securityGroupId }
    var accountId: UUID
    var providerId: CloudProviderID
    var regionId: String
    var securityGroupId: String
    var name: String
    var description: String?
    var projectId: String?
    var isDefault: Bool?
    var createdTime: String?
    var updatedTime: String?
}

struct CloudSecurityGroupList: Equatable, Hashable, Sendable {
    var accountId: UUID
    var providerId: CloudProviderID
    var regionId: String
    var instanceId: String?
    var groups: [CloudSecurityGroup]
    var capturedAt: Date
}

enum CloudSecurityGroupRuleDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case ingress
    case egress

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ingress:
            "Ingress"
        case .egress:
            "Egress"
        }
    }
}

struct CloudSecurityGroupRule: Identifiable, Equatable, Hashable, Sendable {
    var id: String {
        [
            direction.rawValue,
            policyIndex.map(String.init) ?? "unknown",
            protocolName ?? "ALL",
            port ?? "all",
            cidrBlock ?? ipv6CidrBlock ?? referencedSecurityGroupId ?? "any",
            action ?? "unknown",
        ].joined(separator: "|")
    }

    var direction: CloudSecurityGroupRuleDirection
    var policyIndex: Int?
    var protocolName: String?
    var port: String?
    var cidrBlock: String?
    var ipv6CidrBlock: String?
    var referencedSecurityGroupId: String?
    var action: String?
    var description: String?
    var modifiedTime: String?
}

struct CloudSecurityGroupPolicySnapshot: Equatable, Hashable, Sendable {
    var group: CloudSecurityGroup
    var version: String?
    var ingress: [CloudSecurityGroupRule]
    var egress: [CloudSecurityGroupRule]
    var capturedAt: Date
}

enum CloudSecurityGroupRuleChangeAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case add
    case remove

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .add:
            "Add"
        case .remove:
            "Remove"
        }
    }
}

struct CloudSecurityGroupRuleDraft: Equatable, Hashable, Sendable {
    var direction: CloudSecurityGroupRuleDirection
    var protocolName: String
    var port: String
    var cidrBlock: String
    var action: String
    var description: String

    func makeRule() -> CloudSecurityGroupRule {
        CloudSecurityGroupRule(
            direction: direction,
            policyIndex: nil,
            protocolName: normalized(protocolName, fallback: "ALL"),
            port: normalized(port, fallback: "ALL"),
            cidrBlock: normalized(cidrBlock, fallback: "0.0.0.0/0"),
            ipv6CidrBlock: nil,
            referencedSecurityGroupId: nil,
            action: normalized(action, fallback: "ACCEPT"),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            modifiedTime: nil
        )
    }

    private func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed.uppercased()
    }
}

struct CloudSecurityGroupRuleChangePreview: Identifiable, Equatable, Hashable, Sendable {
    var id: String { "\(action.rawValue)-\(group.securityGroupId)-\(proposedRule.id)" }
    var group: CloudSecurityGroup
    var action: CloudSecurityGroupRuleChangeAction
    var proposedRule: CloudSecurityGroupRule
    var beforeIngressCount: Int
    var beforeEgressCount: Int
    var afterIngressCount: Int
    var afterEgressCount: Int
    var warnings: [String]

    var impact: [String] {
        [
            "Ingress rules: \(beforeIngressCount) -> \(afterIngressCount).",
            "Egress rules: \(beforeEgressCount) -> \(afterEgressCount).",
        ] + warnings
    }

    var commandPreview: String {
        let operation = action == .add ? "Authorize" : "Revoke"
        let suffix = proposedRule.direction == .ingress ? "Ingress" : "Egress"
        return "Tencent Cloud \(operation)SecurityGroup\(suffix) \(proposedRule.summary)"
    }

    static func adding(
        draft: CloudSecurityGroupRuleDraft,
        to snapshot: CloudSecurityGroupPolicySnapshot
    ) -> CloudSecurityGroupRuleChangePreview {
        let rule = draft.makeRule()
        return CloudSecurityGroupRuleChangePreview(
            group: snapshot.group,
            action: .add,
            proposedRule: rule,
            beforeIngressCount: snapshot.ingress.count,
            beforeEgressCount: snapshot.egress.count,
            afterIngressCount: snapshot.ingress.count + (rule.direction == .ingress ? 1 : 0),
            afterEgressCount: snapshot.egress.count + (rule.direction == .egress ? 1 : 0),
            warnings: warnings(for: rule, action: .add)
        )
    }

    static func removing(
        rule: CloudSecurityGroupRule,
        from snapshot: CloudSecurityGroupPolicySnapshot
    ) -> CloudSecurityGroupRuleChangePreview {
        CloudSecurityGroupRuleChangePreview(
            group: snapshot.group,
            action: .remove,
            proposedRule: rule,
            beforeIngressCount: snapshot.ingress.count,
            beforeEgressCount: snapshot.egress.count,
            afterIngressCount: max(0, snapshot.ingress.count - (rule.direction == .ingress ? 1 : 0)),
            afterEgressCount: max(0, snapshot.egress.count - (rule.direction == .egress ? 1 : 0)),
            warnings: warnings(for: rule, action: .remove)
        )
    }

    private static func warnings(
        for rule: CloudSecurityGroupRule,
        action: CloudSecurityGroupRuleChangeAction
    ) -> [String] {
        var results: [String] = []
        let target = rule.cidrBlock ?? rule.ipv6CidrBlock ?? rule.referencedSecurityGroupId ?? ""
        let exposesPublicInternet = ["0.0.0.0/0", "::/0"].contains(target)
        if action == .add,
           rule.direction == .ingress,
           rule.action == "ACCEPT",
           exposesPublicInternet {
            results.append("This ingress ACCEPT rule exposes the target to the public internet.")
        }
        if action == .add,
           rule.direction == .ingress,
           ["22", "3389"].contains(rule.port ?? "") {
            results.append("Management ports should be restricted to trusted source CIDR ranges.")
        }
        if action == .remove {
            results.append("Removing a rule can interrupt existing traffic that depends on it.")
        }
        return results
    }
}

extension CloudSecurityGroupRule {
    var summary: String {
        [
            direction.displayName,
            protocolName ?? "ALL",
            port ?? "all",
            cidrBlock ?? ipv6CidrBlock ?? referencedSecurityGroupId ?? "any",
            action ?? "unknown",
        ].joined(separator: " ")
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
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
