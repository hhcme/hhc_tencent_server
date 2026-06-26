import Foundation

enum SSHAuthType: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password:
            L10n.string("Password")
        case .privateKey:
            L10n.string("Private Key")
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

    var clipboardText: String {
        var lines = [
            "$ \(command)",
            "exit: \(exitCode)",
            String(format: "duration: %.2fs", duration),
            "",
            "stdout:",
            stdout.isEmpty ? "(empty)" : stdout,
        ]
        if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(contentsOf: [
                "",
                "stderr:",
                stderr,
            ])
        }
        return lines.joined(separator: "\n")
    }
}

struct ServerCapabilities: Codable, Equatable, Hashable, Sendable {
    var osName: String?
    var osVersion: String?
    var kernelVersion: String?
    var hasProc: Bool
    var hasSystemd: Bool
    var hasSFTP: Bool
    var detectedAt: Date
}

struct DashboardMetric: Identifiable, Codable, Equatable, Hashable, Sendable {
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

struct DashboardWarning: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String { source }
    var source: String
    var message: String
}

struct ServerDashboardSnapshot: Codable, Equatable, Hashable, Sendable {
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
    var id: String { "\(sourcePath ?? "user"):\(originalLine)" }
    var schedule: String
    var command: String
    var isEnabled: Bool
    var originalLine: String
    var sourcePath: String? = nil
    var runAsUser: String? = nil

    var isUserCrontabEntry: Bool {
        sourcePath == nil
    }
}

struct CronTabSnapshot: Equatable, Hashable, Sendable {
    var entries: [CronEntry]
    var rawText: String
    var userRawText: String
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

struct NginxConfigUpsertResult: Equatable, Hashable, Sendable {
    var file: NginxConfigFile
    var content: String
    var backupPath: String?
    var testResult: NginxTestResult
    var createdNewFile: Bool
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

enum FirewallRuleDirection: String, CaseIterable, Identifiable, Sendable {
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

enum FirewallRuleAction: String, CaseIterable, Identifiable, Sendable {
    case allow
    case deny

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allow:
            "Allow"
        case .deny:
            "Deny"
        }
    }
}

enum FirewallRuleProtocol: String, CaseIterable, Identifiable, Sendable {
    case tcp
    case udp

    var id: String { rawValue }

    var displayName: String { rawValue.uppercased() }
}

enum FirewallRuleMutationAction: String, CaseIterable, Identifiable, Sendable {
    case add
    case delete

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .add:
            "Add"
        case .delete:
            "Delete"
        }
    }
}

struct FirewallRuleDraft: Equatable, Hashable, Sendable {
    var mutation: FirewallRuleMutationAction
    var direction: FirewallRuleDirection
    var action: FirewallRuleAction
    var proto: FirewallRuleProtocol
    var port: Int
    var cidr: String
}

struct FirewallRuleMutationResult: Equatable, Hashable, Sendable {
    var draft: FirewallRuleDraft
    var command: String
    var beforeSnapshot: FirewallSnapshot
    var afterSnapshot: FirewallSnapshot
    var result: CommandResult
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

enum RemoteFileTransferBackend: String, Equatable, Hashable, Sendable {
    case unknown
    case rsync
    case openSSHSFTP
    case scp
    case nativeSFTP

    var displayName: String {
        switch self {
        case .unknown:
            "unknown"
        case .rsync:
            "rsync"
        case .openSSHSFTP:
            "OpenSSH SFTP"
        case .scp:
            "scp"
        case .nativeSFTP:
            "native SFTP"
        }
    }
}

struct RemoteFileTransferResult: Equatable, Hashable, Sendable {
    var remotePath: String
    var localPath: String
    var byteCount: Int64?
    var duration: TimeInterval
    var backend: RemoteFileTransferBackend = .unknown
    var supportsResume: Bool = false
    var supportsStreamingProgress: Bool = false
}

struct RemoteFileTransferProgress: Equatable, Hashable, Sendable {
    var completedBytes: Int64?
    var totalBytes: Int64?
    var fraction: Double?
    var transferRateBytesPerSecond: Double?
    var estimatedSecondsRemaining: TimeInterval?

    init(
        completedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        fraction: Double? = nil,
        transferRateBytesPerSecond: Double? = nil,
        estimatedSecondsRemaining: TimeInterval? = nil
    ) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.fraction = fraction.map(Self.clampedFraction)
        self.transferRateBytesPerSecond = transferRateBytesPerSecond
        self.estimatedSecondsRemaining = estimatedSecondsRemaining
    }

    private static func clampedFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
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
    case interrupted

    var isRetryable: Bool {
        switch self {
        case .failed, .cancelled, .interrupted:
            true
        case .pending, .running, .succeeded:
            false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .interrupted:
            true
        case .pending, .running:
            false
        }
    }
}

struct RemoteFileTransferJob: Identifiable, Equatable, Hashable, Sendable {
    var id: UUID
    var direction: RemoteFileTransferDirection
    var remotePath: String
    var localPath: String
    var status: RemoteFileTransferStatus
    var byteCount: Int64?
    var progressFraction: Double?
    var backend: RemoteFileTransferBackend = .unknown
    var supportsResume: Bool = false
    var supportsStreamingProgress: Bool = false
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

enum PackageRegistryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case verdaccio

    var id: String { rawValue }
}

struct RegistryInstance: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var serverId: UUID
    var kind: PackageRegistryKind
    var name: String
    var installPath: String
    var dataPath: String
    var listenHost: String
    var listenPort: Int
    var serviceName: String
    var version: String
    var status: String?
    var createdAt: Date
    var updatedAt: Date
}

enum RegistryBackupStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case created
    case failed
    case restored
    case restoreFailed

    var id: String { rawValue }
}

struct RegistryBackupRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var registryId: UUID
    var backupPath: String
    var status: RegistryBackupStatus
    var sizeBytes: Int64?
    var createdAt: Date
    var restoredAt: Date?
    var message: String?
}

struct PubHostedRepositoryDraft: Codable, Equatable, Hashable, Sendable {
    var hostedURL: String
    var packageName: String
    var tokenEnvironmentVariable: String
    var includeFlutterCommand: Bool

    init(
        hostedURL: String = "https://pub.example.com",
        packageName: String = "my_private_package",
        tokenEnvironmentVariable: String = "PUB_TOKEN",
        includeFlutterCommand: Bool = true
    ) {
        self.hostedURL = hostedURL
        self.packageName = packageName
        self.tokenEnvironmentVariable = tokenEnvironmentVariable
        self.includeFlutterCommand = includeFlutterCommand
    }
}

enum PubHostedRepositoryCheckStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case passed
    case warning

    var id: String { rawValue }
}

struct PubHostedRepositoryCheck: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var status: PubHostedRepositoryCheckStatus
    var detail: String
}

struct PubHostedRepositoryPlan: Codable, Equatable, Hashable, Sendable {
    var hostedURL: String
    var packageName: String
    var tokenEnvironmentVariable: String
    var pubspecSnippet: String
    var publishToSnippet: String
    var tokenCommand: String
    var publishCommand: String
    var getCommand: String
    var flutterGetCommand: String?
    var checks: [PubHostedRepositoryCheck]
    var warnings: [String]
    var generatedAt: Date

    var combinedInstructions: String {
        var sections = [
            "# pubspec.yaml dependency\n\(pubspecSnippet)",
            "# package pubspec.yaml publish target\n\(publishToSnippet)",
            "# token setup\n\(tokenCommand)",
            "# publish\n\(publishCommand)",
            "# get\n\(getCommand)",
        ]
        if let flutterGetCommand {
            sections.append("# Flutter get\n\(flutterGetCommand)")
        }
        return sections.joined(separator: "\n\n")
    }
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

    static func firewallRule(_ draft: FirewallRuleDraft, backend: FirewallBackend, command: String?) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "firewall-\(draft.mutation.rawValue)-\(backend.rawValue)-\(draft.direction.rawValue)-\(draft.proto.rawValue)-\(draft.port)-\(draft.cidr)",
            level: draft.action == .allow && draft.cidr == "0.0.0.0/0" ? .high : .medium,
            title: "\(draft.mutation.displayName) Firewall Rule",
            target: "\(backend.displayName) \(draft.direction.displayName.lowercased()) \(draft.action.rawValue) \(draft.proto.rawValue)/\(draft.port) \(draft.cidr)",
            commandPreview: command,
            impact: ["Firewall rules may immediately allow or block network traffic on the remote server."],
            recovery: draft.mutation == .add ? "Delete the same rule if access becomes too broad." : "Add the same rule again if traffic should remain permitted.",
            auditTargetType: "firewall",
            auditAction: draft.mutation.rawValue
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

    static func deploymentRollback(project: DeploymentProject, run: DeploymentRun) -> RemoteOperationRisk {
        let targetCommit = run.previousCommit ?? "previous commit"
        return RemoteOperationRisk(
            id: "deployment-rollback-\(project.id)-\(run.id)",
            level: .high,
            title: "Rollback Deployment",
            target: "\(project.name) -> \(targetCommit)",
            commandPreview: "git checkout \(targetCommit) && git reset --hard \(targetCommit)",
            impact: [
                "The deployment working tree will be reset to the selected previous commit.",
                "Configured build, restart, and health check commands will run again.",
            ],
            recovery: "Run a new deployment from the target branch if the rollback needs to be undone.",
            auditTargetType: "deployment",
            auditAction: "rollback"
        )
    }

    static func deploymentRun(project: DeploymentProject, plan: DeploymentCommandPlan) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "deployment-run-\(project.id)-\(project.updatedAt.timeIntervalSince1970)",
            level: .high,
            title: "Run Deployment",
            target: "\(project.name) -> \(project.deployPath)",
            commandPreview: plan.commandPreview,
            impact: [
                "The deployment working tree may be cloned, fetched, checked out, and reset.",
                "Configured build, restart, and health check commands will run on the remote server.",
            ],
            recovery: "Use rollback from a completed run if the deployment needs to be reverted.",
            auditTargetType: "deployment",
            auditAction: "deploy"
        )
    }

    static func verdaccioServiceAction(_ action: VerdaccioServiceAction, draft: VerdaccioInstallDraft) -> RemoteOperationRisk {
        let serviceName = "\(draft.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)).service"
        let level: RemoteOperationRiskLevel = action == .stop ? .high : .medium
        return RemoteOperationRisk(
            id: "verdaccio-service-\(action.rawValue)-\(serviceName)",
            level: level,
            title: "\(action.displayName) Verdaccio",
            target: serviceName,
            commandPreview: VerdaccioManager.serviceActionCommand(action, for: draft),
            impact: ["The Verdaccio service state will change on the remote server."],
            recovery: "Use another service action after reviewing systemd status and Verdaccio logs.",
            auditTargetType: "registry",
            auditAction: action.rawValue
        )
    }

    static func verdaccioUpgrade(draft: VerdaccioInstallDraft) -> RemoteOperationRisk {
        let serviceName = "\(draft.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)).service"
        return RemoteOperationRisk(
            id: "verdaccio-upgrade-\(serviceName)-\(draft.version.trimmingCharacters(in: .whitespacesAndNewlines))",
            level: .high,
            title: "Upgrade Verdaccio",
            target: "\(serviceName) -> \(draft.version.trimmingCharacters(in: .whitespacesAndNewlines))",
            commandPreview: "backup systemd unit -> write pinned Verdaccio \(draft.version.trimmingCharacters(in: .whitespacesAndNewlines)) unit -> daemon-reload -> restart -> health check",
            impact: [
                "The Verdaccio systemd unit will be replaced with the selected pinned version.",
                "The registry service will restart and may briefly interrupt package publish/install requests.",
            ],
            recovery: "Restore the backed up systemd unit and restart Verdaccio if the upgrade needs to be reverted.",
            auditTargetType: "registry",
            auditAction: "upgrade"
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
            recovery: preview.action == .add ? "Remove the same rule if the cloud-side change was too broad." : "Add the same rule again if traffic should remain allowed.",
            auditTargetType: "security_group",
            auditAction: preview.action.rawValue
        )
    }

    static func createCloudSnapshot(resource: CloudUnifiedResource, snapshotName: String) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "cloud-snapshot-create-\(resource.id)-\(snapshotName)",
            level: .high,
            title: "Create Cloud Snapshot",
            target: "\(resource.displayName) (\(resource.resourceId))",
            commandPreview: cloudSnapshotCreatePreview(resource: resource, snapshotName: snapshotName),
            impact: [
                "The cloud provider will create a new disk snapshot.",
                "Snapshot creation may incur storage cost and can take time to become usable.",
            ],
            recovery: "Delete the new snapshot from the Cloud Resources center or provider console if it is not needed.",
            auditTargetType: "cloud_snapshot",
            auditAction: "create_snapshot"
        )
    }

    static func deleteCloudSnapshot(resource: CloudUnifiedResource) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "cloud-snapshot-delete-\(resource.id)",
            level: .critical,
            title: "Delete Cloud Snapshot",
            target: "\(resource.displayName) (\(resource.resourceId))",
            commandPreview: cloudSnapshotDeletePreview(resource: resource),
            impact: [
                "The selected cloud snapshot will be deleted from the provider account.",
                "Deleted snapshots cannot be used for future disk recovery.",
            ],
            recovery: "Create a replacement snapshot before deletion if this is still needed for rollback.",
            auditTargetType: "cloud_snapshot",
            auditAction: "delete_snapshot"
        )
    }

    static func attachCloudDisk(resource: CloudUnifiedResource, instanceId: String) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "cloud-disk-attach-\(resource.id)-\(instanceId)",
            level: .high,
            title: "Attach Cloud Disk",
            target: "\(resource.displayName) (\(resource.resourceId))",
            commandPreview: cloudDiskAttachPreview(resource: resource, instanceId: instanceId),
            impact: [
                "The disk will be attached to the selected cloud instance.",
                "The instance may expose the disk as a new block device that still needs OS-side mounting.",
            ],
            recovery: "Detach the disk again after confirming no filesystem writes are in progress.",
            auditTargetType: "cloud_disk",
            auditAction: "attach_disk"
        )
    }

    static func detachCloudDisk(resource: CloudUnifiedResource) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "cloud-disk-detach-\(resource.id)",
            level: .critical,
            title: "Detach Cloud Disk",
            target: "\(resource.displayName) (\(resource.resourceId))",
            commandPreview: cloudDiskDetachPreview(resource: resource),
            impact: [
                "The disk will be detached from its current cloud instance.",
                "Applications using this disk may fail if the filesystem is still mounted or actively written.",
            ],
            recovery: "Reattach the disk to the original instance and inspect application logs if the detach was unintended.",
            auditTargetType: "cloud_disk",
            auditAction: "detach_disk"
        )
    }

    static func cloudInstancePower(resource: CloudUnifiedResource, action: CloudInstancePowerAction) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "cloud-instance-\(action.auditAction)-\(resource.id)",
            level: action == .start ? .high : .critical,
            title: "\(action.displayName) Cloud Instance",
            target: "\(resource.displayName) (\(resource.resourceId))",
            commandPreview: cloudInstancePowerPreview(resource: resource, action: action),
            impact: action.impact,
            recovery: action.recovery,
            auditTargetType: "cloud_instance",
            auditAction: action.auditAction
        )
    }

    private static func cloudSnapshotCreatePreview(resource: CloudUnifiedResource, snapshotName: String) -> String {
        switch resource.providerId {
        case .tencentCloud:
            "CreateSnapshot DiskId=\(resource.resourceId) SnapshotName=\(snapshotName)"
        case .alibabaCloud:
            "CreateSnapshot DiskId=\(resource.resourceId) SnapshotName=\(snapshotName)"
        case .huaweiCloud:
            "POST /v2/{project_id}/cloudsnapshots volume_id=\(resource.resourceId) name=\(snapshotName)"
        }
    }

    private static func cloudSnapshotDeletePreview(resource: CloudUnifiedResource) -> String {
        switch resource.providerId {
        case .tencentCloud:
            "DeleteSnapshots SnapshotIds=[\(resource.resourceId)]"
        case .alibabaCloud:
            "DeleteSnapshot SnapshotId=\(resource.resourceId)"
        case .huaweiCloud:
            "DELETE /v2/{project_id}/cloudsnapshots/\(resource.resourceId)"
        }
    }

    private static func cloudDiskAttachPreview(resource: CloudUnifiedResource, instanceId: String) -> String {
        switch resource.providerId {
        case .tencentCloud:
            "AttachDisks DiskIds=[\(resource.resourceId)] InstanceId=\(instanceId)"
        case .alibabaCloud:
            "AttachDisk DiskId=\(resource.resourceId) InstanceId=\(instanceId)"
        case .huaweiCloud:
            "POST /v2.1/{project_id}/cloudvolumes/\(resource.resourceId)/action os-attach server_id=\(instanceId)"
        }
    }

    private static func cloudDiskDetachPreview(resource: CloudUnifiedResource) -> String {
        switch resource.providerId {
        case .tencentCloud:
            "DetachDisks DiskIds=[\(resource.resourceId)]"
        case .alibabaCloud:
            "DetachDisk DiskId=\(resource.resourceId)"
        case .huaweiCloud:
            "POST /v2.1/{project_id}/cloudvolumes/\(resource.resourceId)/action os-detach"
        }
    }

    private static func cloudInstancePowerPreview(resource: CloudUnifiedResource, action: CloudInstancePowerAction) -> String {
        switch resource.providerId {
        case .tencentCloud:
            "\(action.tencentAPIAction) InstanceIds=[\(resource.resourceId)]"
        case .alibabaCloud:
            "\(action.alibabaAPIAction) InstanceId=\(resource.resourceId)"
        case .huaweiCloud:
            "POST /v2.1/{project_id}/servers/\(resource.resourceId)/action \(action.huaweiAction)"
        }
    }
}

enum CloudProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case tencentCloud = "tencent_cloud"
    case alibabaCloud = "alibaba_cloud"
    case huaweiCloud = "huawei_cloud"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tencentCloud:
            "Tencent Cloud"
        case .alibabaCloud:
            "Alibaba Cloud"
        case .huaweiCloud:
            "Huawei Cloud"
        }
    }
}

enum CloudInstancePowerAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case start
    case stop
    case reboot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .start:
            "Start"
        case .stop:
            "Stop"
        case .reboot:
            "Reboot"
        }
    }

    var auditAction: String {
        switch self {
        case .start:
            "start_instance"
        case .stop:
            "stop_instance"
        case .reboot:
            "reboot_instance"
        }
    }

    var tencentAPIAction: String {
        switch self {
        case .start:
            "StartInstances"
        case .stop:
            "StopInstances"
        case .reboot:
            "RebootInstances"
        }
    }

    var alibabaAPIAction: String {
        switch self {
        case .start:
            "StartInstance"
        case .stop:
            "StopInstance"
        case .reboot:
            "RebootInstance"
        }
    }

    var huaweiAction: String {
        switch self {
        case .start:
            "os-start"
        case .stop:
            "os-stop"
        case .reboot:
            "reboot"
        }
    }

    var transitionStatus: String {
        switch self {
        case .start:
            "STARTING"
        case .stop:
            "STOPPING"
        case .reboot:
            "REBOOTING"
        }
    }

    var progressTitle: String {
        switch self {
        case .start:
            "Starting instance..."
        case .stop:
            "Stopping instance..."
        case .reboot:
            "Rebooting instance..."
        }
    }

    var impact: [String] {
        switch self {
        case .start:
            ["The cloud instance will begin booting and may start billing or service workloads."]
        case .stop:
            [
                "The cloud instance will be stopped and running services will become unavailable.",
                "Unsaved in-memory application state may be lost.",
            ]
        case .reboot:
            [
                "The cloud instance will restart and connected users may be interrupted.",
                "Services on the instance will be temporarily unavailable.",
            ]
        }
    }

    var recovery: String {
        switch self {
        case .start:
            "Stop the instance again if the start was unintended."
        case .stop:
            "Start the instance again after confirming dependent services are safe to resume."
        case .reboot:
            "Wait for the instance to return to RUNNING, then inspect service and system logs."
        }
    }
}

enum CloudResourceActionPolicy {
    static func canPerformPowerAction(
        providerId: CloudProviderID,
        action: CloudInstancePowerAction,
        status: String?
    ) -> Bool {
        guard let normalizedStatus = normalizedStatus(status) else {
            return false
        }
        switch action {
        case .start:
            switch providerId {
            case .tencentCloud, .alibabaCloud:
                return normalizedStatus == "STOPPED"
            case .huaweiCloud:
                return normalizedStatus == "SHUTOFF" || normalizedStatus == "STOPPED"
            }
        case .stop, .reboot:
            switch providerId {
            case .tencentCloud, .alibabaCloud:
                return normalizedStatus == "RUNNING"
            case .huaweiCloud:
                return normalizedStatus == "ACTIVE" || normalizedStatus == "RUNNING"
            }
        }
    }

    static func canDeleteSnapshot(providerId: CloudProviderID, status: String?) -> Bool {
        guard let normalizedStatus = normalizedStatus(status) else {
            return false
        }
        switch providerId {
        case .tencentCloud:
            return normalizedStatus == "NORMAL"
        case .alibabaCloud:
            return normalizedStatus == "ACCOMPLISHED"
        case .huaweiCloud:
            return normalizedStatus == "AVAILABLE"
        }
    }

    static func canAttachDisk(providerId: CloudProviderID, status: String?) -> Bool {
        guard let normalizedStatus = normalizedStatus(status) else {
            return true
        }
        switch providerId {
        case .tencentCloud:
            return normalizedStatus == "UNATTACHED" || normalizedStatus == "DETACHED"
        case .alibabaCloud:
            return normalizedStatus == "AVAILABLE"
        case .huaweiCloud:
            return normalizedStatus == "AVAILABLE"
        }
    }

    static func canDetachDisk(providerId: CloudProviderID, status: String?) -> Bool {
        guard let normalizedStatus = normalizedStatus(status) else {
            return false
        }
        switch providerId {
        case .tencentCloud:
            return normalizedStatus == "ATTACHED"
        case .alibabaCloud:
            return normalizedStatus == "IN_USE"
        case .huaweiCloud:
            return normalizedStatus == "IN-USE" || normalizedStatus == "IN_USE"
        }
    }

    static func powerActionHint(providerId: CloudProviderID) -> String {
        switch providerId {
        case .tencentCloud, .alibabaCloud:
            return "Power actions are available for RUNNING or STOPPED instances."
        case .huaweiCloud:
            return "Power actions are available for ACTIVE or SHUTOFF instances."
        }
    }

    static func snapshotDeletionHint(providerId: CloudProviderID) -> String {
        switch providerId {
        case .tencentCloud:
            return "Only NORMAL snapshots can be deleted."
        case .alibabaCloud:
            return "Only accomplished snapshots can be deleted."
        case .huaweiCloud:
            return "Only available snapshots can be deleted."
        }
    }

    static func diskAttachmentHint(providerId: CloudProviderID) -> String {
        switch providerId {
        case .tencentCloud:
            return "Attach is available for UNATTACHED or DETACHED disks; detach is available for ATTACHED disks."
        case .alibabaCloud:
            return "Attach is available for Available disks; detach is available for In_use disks."
        case .huaweiCloud:
            return "Attach is available for available disks; detach is available for in-use disks."
        }
    }

    private static func normalizedStatus(_ status: String?) -> String? {
        guard let status else {
            return nil
        }
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed.uppercased()
    }
}

enum CloudCapability: String, Codable, CaseIterable, Identifiable, Sendable {
    case regions
    case instanceDiscovery
    case instanceMetadata
    case cloudMetrics
    case securityGroups
    case securityGroupActions
    case cloudDisks
    case cloudSnapshots
    case cloudBilling
    case snapshotActions
    case diskAttachmentActions
    case powerActions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .regions:
            "Regions"
        case .instanceDiscovery:
            "Instance Discovery"
        case .instanceMetadata:
            "Instance Metadata"
        case .cloudMetrics:
            "Cloud Metrics"
        case .securityGroups:
            "Security Groups"
        case .securityGroupActions:
            "Security Group Actions"
        case .cloudDisks:
            "Cloud Disks"
        case .cloudSnapshots:
            "Cloud Snapshots"
        case .cloudBilling:
            "Billing"
        case .snapshotActions:
            "Snapshot Actions"
        case .diskAttachmentActions:
            "Disk Attachment Actions"
        case .powerActions:
            "Power Actions"
        }
    }
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
    var securityGroupIds: [String]
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
    var securityGroupIds: [String]
    var billingType: String?
    var expiredTime: Date?
    var rawJSON: String?
}

struct CloudDisk: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var accountId: UUID
    var providerId: CloudProviderID
    var regionId: String
    var diskId: String
    var instanceId: String?
    var name: String?
    var diskType: String?
    var sizeGB: Int?
    var status: String?
    var billingType: String?
    var expiredTime: Date?
    var rawJSON: String?
    var lastSyncedAt: Date?
}

struct CloudSnapshot: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var accountId: UUID
    var providerId: CloudProviderID
    var regionId: String
    var snapshotId: String
    var diskId: String?
    var name: String?
    var status: String?
    var sizeGB: Int?
    var createdAtProvider: Date?
    var rawJSON: String?
    var lastSyncedAt: Date?
}

struct CloudBillingState: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var accountId: UUID
    var providerId: CloudProviderID
    var resourceType: String
    var resourceId: String
    var billingType: String?
    var expireAt: Date?
    var status: String?
    var rawJSON: String?
    var lastSyncedAt: Date?
}

enum CloudResourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case instance
    case securityGroup
    case disk
    case snapshot
    case billing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instance:
            "Instance"
        case .securityGroup:
            "Security Group"
        case .disk:
            "Disk"
        case .snapshot:
            "Snapshot"
        case .billing:
            "Billing"
        }
    }
}

struct CloudUnifiedResource: Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var kind: CloudResourceKind
    var accountId: UUID
    var providerId: CloudProviderID
    var regionId: String?
    var resourceId: String
    var displayName: String
    var status: String?
    var primaryAddress: String?
    var secondaryText: String?
    var lastSyncedAt: Date?
}

struct CloudResourceSearchQuery: Equatable, Hashable, Sendable {
    var text: String
    var providerId: CloudProviderID?
    var accountId: UUID?
    var regionId: String?
    var kinds: Set<CloudResourceKind>
    var status: String?

    init(
        text: String = "",
        providerId: CloudProviderID? = nil,
        accountId: UUID? = nil,
        regionId: String? = nil,
        kinds: Set<CloudResourceKind> = Set(CloudResourceKind.allCases),
        status: String? = nil
    ) {
        self.text = text
        self.providerId = providerId
        self.accountId = accountId
        self.regionId = regionId
        self.kinds = kinds
        self.status = status
    }
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
            providerRuleId ?? "no-provider-rule-id",
            protocolName ?? "ALL",
            port ?? "all",
            cidrBlock ?? ipv6CidrBlock ?? referencedSecurityGroupId ?? "any",
            action ?? "unknown",
        ].joined(separator: "|")
    }

    var direction: CloudSecurityGroupRuleDirection
    var policyIndex: Int?
    var providerRuleId: String?
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
            providerRuleId: nil,
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
        let actionName: String
        switch (group.providerId, action, proposedRule.direction) {
        case (.alibabaCloud, .add, .ingress):
            actionName = "AuthorizeSecurityGroup"
        case (.alibabaCloud, .add, .egress):
            actionName = "AuthorizeSecurityGroupEgress"
        case (.alibabaCloud, .remove, .ingress):
            actionName = "RevokeSecurityGroup"
        case (.alibabaCloud, .remove, .egress):
            actionName = "RevokeSecurityGroupEgress"
        case (.huaweiCloud, .add, _):
            actionName = "CreateSecurityGroupRule"
        case (.huaweiCloud, .remove, _):
            actionName = "DeleteSecurityGroupRule"
        default:
            let operation = action == .add ? "Authorize" : "Revoke"
            let suffix = proposedRule.direction == .ingress ? "Ingress" : "Egress"
            actionName = "\(operation)SecurityGroup\(suffix)"
        }
        return "\(group.providerId.displayName) \(actionName) \(proposedRule.summary)"
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

struct CloudSecurityGroupRuleChangeResult: Equatable, Hashable, Sendable {
    var preview: CloudSecurityGroupRuleChangePreview
    var requestId: String?
    var beforeSnapshot: CloudSecurityGroupPolicySnapshot
    var afterSnapshot: CloudSecurityGroupPolicySnapshot
    var capturedAt: Date
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
        securityGroupIds = instance.securityGroupIds
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
            L10n.string("Disconnected")
        case .connecting:
            L10n.string("Connecting")
        case .connected:
            L10n.string("Connected")
        case .failed:
            L10n.string("Failed")
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
