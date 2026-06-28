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

enum ServerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case manualSSH
    case tencentLighthouse
    case tencentCVM
    case alibabaECS
    case huaweiECS
    case selfHosted

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manualSSH:
            "手动 SSH"
        case .tencentLighthouse:
            "腾讯云轻量应用服务器"
        case .tencentCVM:
            "腾讯云 CVM"
        case .alibabaECS:
            "阿里云 ECS"
        case .huaweiECS:
            "华为云 ECS"
        case .selfHosted:
            "自建服务器/VPS"
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
    var serverKind: ServerKind = .manualSSH
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

struct SystemdServiceSummary: Equatable, Hashable, Sendable {
    var total: Int
    var running: Int
    var stopped: Int
    var failed: Int
    var commonApplications: Int
}

enum SystemdServiceClassifier {
    static func summary(for units: [SystemdUnit]) -> SystemdServiceSummary {
        SystemdServiceSummary(
            total: units.count,
            running: units.filter(\.isRunning).count,
            stopped: units.filter { !isFailed($0) && !$0.isRunning }.count,
            failed: units.filter(isFailed).count,
            commonApplications: units.filter(isCommonApplication).count
        )
    }

    static func isFailed(_ unit: SystemdUnit) -> Bool {
        unit.activeState.localizedCaseInsensitiveCompare("failed") == .orderedSame ||
            unit.subState.localizedCaseInsensitiveContains("failed") ||
            unit.loadState.localizedCaseInsensitiveContains("failed")
    }

    static func isCommonApplication(_ unit: SystemdUnit) -> Bool {
        commonApplicationName(for: unit) != nil
    }

    static func commonApplicationName(for unit: SystemdUnit) -> String? {
        let haystack = "\(unit.name) \(unit.description)".lowercased()
        return commonApplicationRules.first { rule in
            haystack.contains(rule.keyword)
        }?.label
    }

    private static let commonApplicationRules: [(keyword: String, label: String)] = [
        ("nginx", "Nginx"),
        ("apache", "Apache"),
        ("caddy", "Caddy"),
        ("mysql", "MySQL"),
        ("mariadb", "MariaDB"),
        ("postgres", "PostgreSQL"),
        ("redis", "Redis"),
        ("mongodb", "MongoDB"),
        ("docker", "Docker"),
        ("containerd", "Containerd"),
        ("node", "Node.js"),
        ("pm2", "PM2"),
        ("php", "PHP"),
        ("gitea", "Gitea"),
        ("gitlab", "GitLab"),
        ("verdaccio", "Verdaccio"),
    ]
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

enum DatabaseServiceKind: String, CaseIterable, Identifiable, Sendable {
    case mysql
    case mariadb
    case postgresql
    case redis

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mysql:
            "MySQL"
        case .mariadb:
            "MariaDB"
        case .postgresql:
            "PostgreSQL"
        case .redis:
            "Redis"
        }
    }

    var defaultPort: String {
        switch self {
        case .mysql, .mariadb:
            "3306"
        case .postgresql:
            "5432"
        case .redis:
            "6379"
        }
    }
}

struct DatabaseService: Identifiable, Equatable, Hashable, Sendable {
    var id: String { kind.rawValue }
    var kind: DatabaseServiceKind
    var unitName: String?
    var activeState: String
    var subState: String
    var isInstalled: Bool
    var version: String?
    var listenEndpoints: [String]
    var dataPath: String?
    var recentLog: String?

    var isRunning: Bool {
        activeState == "active"
    }

    var statusText: String {
        guard isInstalled else { return "not found" }
        if activeState == "unknown" { return "installed" }
        return subState.isEmpty ? activeState : "\(activeState) / \(subState)"
    }
}

struct DatabaseServiceSnapshot: Equatable, Hashable, Sendable {
    var services: [DatabaseService]
    var capturedAt: Date
}

struct DatabaseServiceSummary: Equatable, Hashable, Sendable {
    var total: Int
    var installed: Int
    var running: Int
    var attention: Int
    var missing: Int
}

enum DatabaseServiceFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case installed
    case running
    case attention
    case missing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .installed:
            "已安装"
        case .running:
            "运行中"
        case .attention:
            "需关注"
        case .missing:
            "未发现"
        }
    }
}

enum DatabaseServiceInspector {
    static func summary(for services: [DatabaseService]) -> DatabaseServiceSummary {
        DatabaseServiceSummary(
            total: services.count,
            installed: services.filter(\.isInstalled).count,
            running: services.filter(\.isRunning).count,
            attention: services.filter(needsAttention).count,
            missing: services.filter { !$0.isInstalled }.count
        )
    }

    static func filter(_ services: [DatabaseService], by filter: DatabaseServiceFilter) -> [DatabaseService] {
        services.filter { service in
            switch filter {
            case .all:
                true
            case .installed:
                service.isInstalled
            case .running:
                service.isRunning
            case .attention:
                needsAttention(service)
            case .missing:
                !service.isInstalled
            }
        }
    }

    static func needsAttention(_ service: DatabaseService) -> Bool {
        service.isInstalled && !service.isRunning
    }
}

struct DatabaseBackupRestorePlan: Equatable, Hashable, Sendable {
    var serviceKind: DatabaseServiceKind
    var backupPath: String
    var backupCommand: String
    var restoreCommand: String
    var prerequisites: [String]
    var warnings: [String]
}

struct DatabaseBackupResult: Equatable, Hashable, Sendable {
    var serviceKind: DatabaseServiceKind
    var backupPath: String
    var output: String
    var capturedAt: Date
}

struct NetworkInterfaceTrafficUsage: Identifiable, Equatable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var receivedBytes: Double
    var transmittedBytes: Double

    var totalBytes: Double {
        receivedBytes + transmittedBytes
    }
}

struct NetworkTrafficSummary: Equatable, Hashable, Sendable {
    var interfaceCount: Int
    var receivedBytes: Double
    var transmittedBytes: Double
    var busiestInterface: NetworkInterfaceTrafficUsage?

    var totalBytes: Double {
        receivedBytes + transmittedBytes
    }

    var hasTraffic: Bool {
        totalBytes > 0
    }
}

enum NetworkTrafficInspector {
    static func parseInterfaceBreakdown(_ value: String) -> [NetworkInterfaceTrafficUsage] {
        value
            .split(separator: ";")
            .compactMap { rawItem -> NetworkInterfaceTrafficUsage? in
                let item = String(rawItem).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let firstSpace = item.firstIndex(where: \.isWhitespace) else { return nil }
                let name = String(item[..<firstSpace])
                let pair = String(item[firstSpace...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let bytes = bytePair(from: pair) else { return nil }
                return NetworkInterfaceTrafficUsage(
                    name: name,
                    receivedBytes: bytes.received,
                    transmittedBytes: bytes.transmitted
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalBytes == rhs.totalBytes {
                    return lhs.name < rhs.name
                }
                return lhs.totalBytes > rhs.totalBytes
            }
    }

    static func summary(for interfaces: [NetworkInterfaceTrafficUsage]) -> NetworkTrafficSummary {
        NetworkTrafficSummary(
            interfaceCount: interfaces.count,
            receivedBytes: interfaces.reduce(0) { $0 + $1.receivedBytes },
            transmittedBytes: interfaces.reduce(0) { $0 + $1.transmittedBytes },
            busiestInterface: interfaces.max { lhs, rhs in
                lhs.totalBytes < rhs.totalBytes
            }
        )
    }

    static func trafficShare(
        for interface: NetworkInterfaceTrafficUsage,
        in summary: NetworkTrafficSummary
    ) -> Double {
        guard summary.totalBytes > 0 else { return 0 }
        return min(max(interface.totalBytes / summary.totalBytes, 0), 1)
    }

    static func attentionMessages(for summary: NetworkTrafficSummary) -> [String] {
        guard summary.interfaceCount > 0 else {
            return ["未解析到非 lo 网卡明细，无法判断单网卡流量分布。"]
        }
        guard let busiest = summary.busiestInterface,
              summary.totalBytes > 0
        else {
            return []
        }

        let share = trafficShare(for: busiest, in: summary)
        if share >= 0.9, summary.interfaceCount > 1 {
            return ["\(busiest.name) 承载超过 90% 的累计流量，建议确认默认路由和业务出口是否符合预期。"]
        }
        return []
    }

    private static func bytePair(from value: String) -> (received: Double, transmitted: Double)? {
        let parts = value.split(separator: "/").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let received = byteValue(parts[0]),
              let transmitted = byteValue(parts[1])
        else { return nil }
        return (received, transmitted)
    }

    private static func byteValue(_ value: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let numberRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let number = Double(value[numberRange])
        else { return nil }

        switch value[unitRange].lowercased() {
        case "b":
            return number
        case "kib", "kb":
            return number * 1024
        case "mib", "mb":
            return number * 1024 * 1024
        case "gib", "gb":
            return number * 1024 * 1024 * 1024
        case "tib", "tb":
            return number * 1024 * 1024 * 1024 * 1024
        default:
            return nil
        }
    }
}

enum DockerContainerAction: String, CaseIterable, Identifiable, Sendable {
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

struct DockerContainer: Identifiable, Equatable, Hashable, Sendable {
    var id: String { containerID }
    var containerID: String
    var image: String
    var command: String
    var createdAt: String
    var runningFor: String
    var ports: String
    var status: String
    var state: String
    var names: String
    var size: String?

    var displayName: String {
        names.nilIfEmpty ?? containerID
    }

    var isRunning: Bool {
        state.lowercased() == "running" || status.lowercased().hasPrefix("up ")
    }
}

struct DockerImage: Identifiable, Equatable, Hashable, Sendable {
    var id: String { imageID }
    var imageID: String
    var repository: String
    var tag: String
    var digest: String?
    var createdAt: String
    var createdSince: String
    var size: String

    var displayName: String {
        if tag.isEmpty || tag == "<none>" {
            return repository
        }
        return "\(repository):\(tag)"
    }
}

struct DockerImagePullResult: Equatable, Hashable, Sendable {
    var reference: String
    var output: String
    var capturedAt: Date
}

struct DockerImageRemoveResult: Equatable, Hashable, Sendable {
    var imageID: String
    var output: String
    var capturedAt: Date
}

struct DockerSnapshot: Equatable, Hashable, Sendable {
    var isAvailable: Bool
    var version: String?
    var unavailableReason: String?
    var containers: [DockerContainer]
    var images: [DockerImage]
    var capturedAt: Date

    var runningContainerCount: Int {
        containers.filter(\.isRunning).count
    }
}

struct DockerContainerLog: Equatable, Hashable, Sendable {
    var containerID: String
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

struct CronEntrySummary: Equatable, Hashable, Sendable {
    var total: Int
    var enabled: Int
    var disabled: Int
    var userEntries: Int
    var systemEntries: Int
}

enum CronEntryClassifier {
    static func summary(for entries: [CronEntry]) -> CronEntrySummary {
        CronEntrySummary(
            total: entries.count,
            enabled: entries.filter(\.isEnabled).count,
            disabled: entries.filter { !$0.isEnabled }.count,
            userEntries: entries.filter(\.isUserCrontabEntry).count,
            systemEntries: entries.filter { !$0.isUserCrontabEntry }.count
        )
    }

    static func sourceTitle(for entry: CronEntry) -> String {
        entry.sourcePath ?? "User crontab"
    }

    static func runAsTitle(for entry: CronEntry) -> String {
        if let runAsUser = entry.runAsUser?.nilIfEmpty {
            return runAsUser
        }
        return entry.isUserCrontabEntry ? "SSH user" : "-"
    }
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

struct NginxSite: Identifiable, Equatable, Hashable, Sendable {
    var id: String {
        "\(configPath)#\(blockIndex)"
    }

    var configPath: String
    var blockIndex: Int
    var serverNames: [String]
    var listen: [String]
    var root: String?
    var hasSSL: Bool
    var sslCertificatePaths: [String]
    var sslCertificates: [NginxSSLCertificate]
    var proxyPasses: [String]

    var primaryName: String {
        serverNames.first ?? "_"
    }

    var isReverseProxy: Bool {
        !proxyPasses.isEmpty
    }
}

struct NginxSSLCertificate: Identifiable, Equatable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var subject: String?
    var issuer: String?
    var notAfter: Date?
    var inspectionError: String?

    var hasInspectionError: Bool {
        inspectionError?.isEmpty == false
    }
}

struct NginxSiteList: Equatable, Hashable, Sendable {
    var sites: [NginxSite]
    var capturedAt: Date
}

struct NginxSiteSummary: Equatable, Hashable, Sendable {
    var total: Int
    var sslEnabled: Int
    var reverseProxy: Int
    var staticSites: Int
    var certificateIssues: Int
}

enum NginxSiteFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case ssl
    case reverseProxy
    case staticSite
    case certificateIssues

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .ssl:
            "SSL"
        case .reverseProxy:
            "反向代理"
        case .staticSite:
            "静态站点"
        case .certificateIssues:
            "证书异常"
        }
    }
}

enum NginxSiteInspector {
    static func summary(for sites: [NginxSite]) -> NginxSiteSummary {
        NginxSiteSummary(
            total: sites.count,
            sslEnabled: sites.filter(\.hasSSL).count,
            reverseProxy: sites.filter(\.isReverseProxy).count,
            staticSites: sites.filter(isStaticSite).count,
            certificateIssues: sites.filter(hasCertificateIssue).count
        )
    }

    static func filter(_ sites: [NginxSite], by filter: NginxSiteFilter) -> [NginxSite] {
        sites.filter { site in
            switch filter {
            case .all:
                true
            case .ssl:
                site.hasSSL
            case .reverseProxy:
                site.isReverseProxy
            case .staticSite:
                isStaticSite(site)
            case .certificateIssues:
                hasCertificateIssue(site)
            }
        }
    }

    static func isStaticSite(_ site: NginxSite) -> Bool {
        site.root?.nilIfEmpty != nil && !site.isReverseProxy
    }

    static func hasCertificateIssue(_ site: NginxSite) -> Bool {
        guard site.hasSSL else { return false }
        if site.sslCertificatePaths.isEmpty { return true }
        if site.sslCertificates.isEmpty { return true }
        return site.sslCertificates.contains { certificate in
            certificate.hasInspectionError || certificate.notAfter.map { $0 < Date() } == true
        }
    }
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

struct NginxReverseProxyDraft: Equatable, Hashable, Sendable {
    var serverName: String
    var upstreamURL: String
    var configPath: String
    var clientMaxBodySize: String
    var enableWebSocket: Bool

    init(
        serverName: String = "example.com",
        upstreamURL: String = "http://127.0.0.1:3000",
        configPath: String = "/etc/nginx/conf.d/example-proxy.conf",
        clientMaxBodySize: String = "50m",
        enableWebSocket: Bool = true
    ) {
        self.serverName = serverName
        self.upstreamURL = upstreamURL
        self.configPath = configPath
        self.clientMaxBodySize = clientMaxBodySize
        self.enableWebSocket = enableWebSocket
    }
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

struct EnvironmentVariableAnalysis: Equatable, Hashable, Sendable {
    var keys: [String]
    var sensitiveKeys: [String]

    var variableCount: Int {
        keys.count
    }
}

struct EnvironmentVariableChangeSummary: Equatable, Hashable, Sendable {
    var addedKeys: [String]
    var changedKeys: [String]
    var removedKeys: [String]

    var hasChanges: Bool {
        !addedKeys.isEmpty || !changedKeys.isEmpty || !removedKeys.isEmpty
    }

    var allChangedKeys: [String] {
        Array(Set(addedKeys + changedKeys + removedKeys)).sorted()
    }
}

enum EnvironmentVariableInspector {
    static func analyze(_ content: String) -> EnvironmentVariableAnalysis {
        let keys = Array(parsedVariables(from: content).keys).sorted()
        return EnvironmentVariableAnalysis(
            keys: keys,
            sensitiveKeys: keys.filter(isSensitiveKey).sorted()
        )
    }

    static func changeSummary(from original: String, to draft: String) -> EnvironmentVariableChangeSummary {
        let originalVariables = parsedVariables(from: original)
        let draftVariables = parsedVariables(from: draft)
        let originalKeys = Set(originalVariables.keys)
        let draftKeys = Set(draftVariables.keys)
        let sharedKeys = originalKeys.intersection(draftKeys)

        return EnvironmentVariableChangeSummary(
            addedKeys: Array(draftKeys.subtracting(originalKeys)).sorted(),
            changedKeys: sharedKeys.filter { originalVariables[$0] != draftVariables[$0] }.sorted(),
            removedKeys: Array(originalKeys.subtracting(draftKeys)).sorted()
        )
    }

    static func maskedKeyList(_ keys: [String], limit: Int = 4) -> String {
        guard !keys.isEmpty else { return "None" }
        let visible = keys.prefix(limit).joined(separator: ", ")
        let remaining = keys.count - min(keys.count, limit)
        return remaining > 0 ? "\(visible) +\(remaining)" : visible
    }

    private static func parsedVariables(from content: String) -> [String: String] {
        content.components(separatedBy: .newlines).reduce(into: [String: String]()) { variables, rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let equalsIndex = line.firstIndex(of: "=") else { return }
            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else { return }
            let value = String(line[line.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)
            variables[key] = value
        }
    }

    private static func isValidKey(_ key: String) -> Bool {
        key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let uppercased = key.uppercased()
        return [
            "PASSWORD",
            "PASS",
            "SECRET",
            "TOKEN",
            "PRIVATE_KEY",
            "ACCESS_KEY",
            "CREDENTIAL",
            "AUTH",
        ].contains { uppercased.contains($0) }
    }
}

enum RemoteFileKind: String, Equatable, Hashable {
    case directory
    case file
    case symlink
    case other
}

enum RemoteFileCreationKind: String, CaseIterable, Identifiable, Sendable {
    case file
    case directory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file:
            "New File"
        case .directory:
            "New Folder"
        }
    }

    var defaultName: String {
        switch self {
        case .file:
            "untitled.txt"
        case .directory:
            "new-folder"
        }
    }
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

struct CommandHistorySummary: Equatable, Hashable, Sendable {
    var total: Int
    var succeeded: Int
    var failed: Int
    var averageDuration: TimeInterval?
    var lastRunAt: Date?
}

enum CommandHistoryStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case succeeded
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .succeeded:
            "成功"
        case .failed:
            "失败"
        }
    }
}

enum CommandHistoryInspector {
    static func summary(for entries: [CommandHistoryEntry]) -> CommandHistorySummary {
        let durations = entries.compactMap(\.duration)
        return CommandHistorySummary(
            total: entries.count,
            succeeded: entries.filter { $0.exitCode == 0 }.count,
            failed: entries.filter { $0.exitCode != 0 }.count,
            averageDuration: durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count),
            lastRunAt: entries.map(\.createdAt).max()
        )
    }

    static func filter(
        _ entries: [CommandHistoryEntry],
        query: String,
        status: CommandHistoryStatusFilter
    ) -> [CommandHistoryEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            let matchesStatus: Bool
            switch status {
            case .all:
                matchesStatus = true
            case .succeeded:
                matchesStatus = entry.exitCode == 0
            case .failed:
                matchesStatus = entry.exitCode != 0
            }

            let matchesQuery = normalizedQuery.isEmpty ||
                entry.command.lowercased().contains(normalizedQuery)

            return matchesStatus && matchesQuery
        }
    }
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

extension DeploymentProject {
    var referencedSystemdUnitNames: [String] {
        Self.referencedSystemdUnitNames(in: restartCommand)
    }

    static func referencedSystemdUnitNames(in command: String?) -> [String] {
        guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty,
              let regex = try? NSRegularExpression(
                pattern: #"\bsystemctl\s+(?:--user\s+)?(?:--no-block\s+)?(?:start|stop|restart|reload|try-restart)\s+(?:--\s+)?['\"]?([A-Za-z0-9:_.@-]+)['\"]?"#
              )
        else { return [] }

        let range = NSRange(command.startIndex..., in: command)
        var seen = Set<String>()
        return regex.matches(in: command, range: range).compactMap { match in
            guard let unitRange = Range(match.range(at: 1), in: command) else { return nil }
            let unit = Self.normalizedSystemdUnitName(String(command[unitRange]))
            guard !seen.contains(unit) else { return nil }
            seen.insert(unit)
            return unit
        }
    }

    static func projects(_ projects: [DeploymentProject], referencing unitName: String) -> [DeploymentProject] {
        let normalizedUnitName = normalizedSystemdUnitName(unitName)
        return projects.filter { project in
            project.referencedSystemdUnitNames.contains(normalizedUnitName)
        }
    }

    private static func normalizedSystemdUnitName(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains(".") {
            return value
        }
        return "\(value).service"
    }
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

enum GitLabServiceEdition: String, Codable, CaseIterable, Identifiable, Sendable {
    case ce

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ce:
            L10n.string("Community Edition")
        }
    }

    var packageName: String {
        switch self {
        case .ce:
            "gitlab-ce"
        }
    }
}

enum GitLabInstallMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case linuxPackage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linuxPackage:
            L10n.string("Linux package")
        }
    }
}

struct GitLabServiceInstance: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var serverId: UUID
    var edition: GitLabServiceEdition
    var externalURL: String
    var packageName: String
    var installedVersion: String?
    var status: String?
    var webURL: String?
    var createdAt: Date
    var updatedAt: Date
}

struct GitLabInstallDraft: Codable, Equatable, Hashable, Sendable {
    var externalURL: String
    var edition: GitLabServiceEdition
    var installMethod: GitLabInstallMethod
    var openFirewallPorts: Bool
    var notes: String

    init(
        externalURL: String = "http://",
        edition: GitLabServiceEdition = .ce,
        installMethod: GitLabInstallMethod = .linuxPackage,
        openFirewallPorts: Bool = true,
        notes: String = ""
    ) {
        self.externalURL = externalURL
        self.edition = edition
        self.installMethod = installMethod
        self.openFirewallPorts = openFirewallPorts
        self.notes = notes
    }
}

enum GitLabPreflightCheckStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case passed
    case warning
    case failed

    var id: String { rawValue }
}

struct GitLabPreflightCheck: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var status: GitLabPreflightCheckStatus
    var detail: String
    var remediation: String?
}

struct GitLabPreflightReport: Codable, Equatable, Hashable, Sendable {
    var checks: [GitLabPreflightCheck]
    var detectedOS: String?
    var existingVersion: String?
    var generatedAt: Date

    var isReady: Bool {
        !checks.contains { $0.status == .failed }
    }

    var warnings: [GitLabPreflightCheck] {
        checks.filter { $0.status == .warning }
    }
}

struct GitLabInstallResult: Codable, Equatable, Hashable, Sendable {
    var instance: GitLabServiceInstance
    var healthCheckOutput: String
    var statusOutput: String
}

struct GitLabStatusSnapshot: Codable, Equatable, Hashable, Sendable {
    var installed: Bool
    var version: String?
    var status: String
    var externalURL: String?
    var webReachable: Bool
    var rootPasswordHint: String
    var recentLogs: String
    var capturedAt: Date
}

enum GitLabServiceAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case start
    case stop
    case restart
    case reconfigure

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .start:
            L10n.string("Start")
        case .stop:
            L10n.string("Stop")
        case .restart:
            L10n.string("Restart")
        case .reconfigure:
            L10n.string("Reconfigure")
        }
    }
}

struct GitLabServiceActionResult: Codable, Equatable, Hashable, Sendable {
    var action: GitLabServiceAction
    var output: String
    var snapshot: GitLabStatusSnapshot
}

struct GiteaInstallDraft: Codable, Equatable, Hashable, Sendable {
    var externalURL: String
    var installPath: String
    var dataPath: String
    var serviceName: String
    var listenPort: Int

    init(
        externalURL: String = "http://",
        installPath: String = "/usr/local/bin/gitea",
        dataPath: String = "/var/lib/gitea",
        serviceName: String = "gitea",
        listenPort: Int = 3000
    ) {
        self.externalURL = externalURL
        self.installPath = installPath
        self.dataPath = dataPath
        self.serviceName = serviceName
        self.listenPort = listenPort
    }
}

struct GiteaInstallResult: Codable, Equatable, Hashable, Sendable {
    var externalURL: String
    var version: String?
    var status: String
}

enum GitNativeServiceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case gitea
    case gitLab

    var id: String { rawValue }
}

struct GitNativeRepositoryDraft: Equatable, Hashable, Sendable {
    var name = ""
    var description = ""
    var isPrivate = true
    var autoInitialize = true

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GitLabProjectSettingsDraft: Equatable, Hashable, Sendable {
    var projectId: Int64 = 0
    var pathWithNamespace = ""
    var description = ""
    var visibility = "private"
    var defaultBranch = ""
    var archived = false

    var trimmedPathWithNamespace: String {
        pathWithNamespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDefaultBranch: String {
        defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GitLabGroupDraft: Equatable, Hashable, Sendable {
    var groupId: Int64 = 0
    var name = ""
    var path = ""
    var description = ""
    var visibility = "private"
    var parentId: Int64 = 0

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPath: String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GitLabVariableDraft: Equatable, Hashable, Sendable {
    var projectId: Int64 = 0
    var key = ""
    var value = ""
    var environmentScope = "*"
    var variableType = "env_var"
    var protected = false
    var masked = false
    var raw = false

    var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedEnvironmentScope: String {
        let scope = environmentScope.trimmingCharacters(in: .whitespacesAndNewlines)
        return scope.isEmpty ? "*" : scope
    }
}

struct GitLabDeployKeyDraft: Equatable, Hashable, Sendable {
    var projectId: Int64 = 0
    var title = ""
    var key = ""
    var canPush = false

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GitLabDeployTokenDraft: Equatable, Hashable, Sendable {
    var projectId: Int64 = 0
    var name = ""
    var username = ""
    var expiresAt = ""
    var readRepository = true
    var readRegistry = false
    var writeRegistry = false
    var readPackageRegistry = true
    var writePackageRegistry = false

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedExpiresAt: String {
        expiresAt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var selectedScopes: [String] {
        [
            readRepository ? "read_repository" : nil,
            readRegistry ? "read_registry" : nil,
            writeRegistry ? "write_registry" : nil,
            readPackageRegistry ? "read_package_registry" : nil,
            writePackageRegistry ? "write_package_registry" : nil,
        ].compactMap { $0 }
    }
}

struct GitLabTagDraft: Equatable, Hashable, Sendable {
    var projectId: Int64 = 0
    var name = ""
    var ref = ""
    var message = ""

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRef: String {
        ref.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GitLabMemberScope: String, CaseIterable, Identifiable, Sendable {
    case project
    case group

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .project:
            "Project"
        case .group:
            "Group"
        }
    }
}

struct GitLabMemberDraft: Equatable, Hashable, Sendable {
    var scope: GitLabMemberScope = .project
    var targetId: Int64 = 0
    var userId: Int64 = 0
    var accessLevel: Int = 30
    var expiresAt = ""

    var trimmedExpiresAt: String {
        expiresAt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GitLabMemberSaveMode: String, CaseIterable, Identifiable, Sendable {
    case add
    case update

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .add:
            "添加"
        case .update:
            "更新"
        }
    }
}

enum GitLabVariableSaveMode: String, CaseIterable, Identifiable, Sendable {
    case create
    case update

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .create:
            "创建"
        case .update:
            "更新"
        }
    }
}

enum GitLabGroupSaveMode: String, CaseIterable, Identifiable, Sendable {
    case create
    case update

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .create:
            "创建"
        case .update:
            "保存"
        }
    }

    var actionDescription: String {
        switch self {
        case .create:
            "creates"
        case .update:
            "updates"
        }
    }
}

enum GitNativeIssueStateAction: String, CaseIterable, Identifiable, Sendable {
    case close
    case reopen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .close:
            "关闭"
        case .reopen:
            "重新打开"
        }
    }

    static func suggested(for state: String) -> GitNativeIssueStateAction {
        let normalized = state.lowercased()
        if normalized == "closed" || normalized == "merged" {
            return .reopen
        }
        return .close
    }
}

enum GitLabPipelineAction: String, CaseIterable, Identifiable, Sendable {
    case retry
    case cancel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .retry:
            "重试"
        case .cancel:
            "取消"
        }
    }

    var systemImage: String {
        switch self {
        case .retry:
            "arrow.clockwise.circle"
        case .cancel:
            "xmark.circle"
        }
    }
}

enum GitLabJobAction: String, CaseIterable, Identifiable, Sendable {
    case retry
    case cancel
    case play

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .retry:
            "重试"
        case .cancel:
            "取消"
        case .play:
            "运行"
        }
    }

    var systemImage: String {
        switch self {
        case .retry:
            "arrow.clockwise.circle"
        case .cancel:
            "xmark.circle"
        case .play:
            "play.circle"
        }
    }
}

struct GiteaNativeSnapshot: Decodable, Equatable, Hashable, Sendable {
    var repositories: [GiteaRepositorySummary]
    var users: [GiteaUserSummary]
    var organizations: [GiteaOrganizationSummary]
    var teams: [GiteaTeamSummary]
    var teamMembers: [GiteaTeamMemberSummary]
    var teamRepositories: [GiteaTeamRepositorySummary]
    var keys: [GiteaKeySummary]
    var tokens: [GiteaAccessTokenSummary]
    var packages: [GiteaPackageSummary]
    var adminOverview: GiteaAdminOverviewSummary
    var issues: [GiteaIssueSummary]
    var pullRequests: [GiteaPullRequestSummary]
    var capturedAt: Date
}

struct GiteaRepositorySummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var name: String
    var fullName: String
    var owner: String
    var isPrivate: Bool
    var isArchived: Bool?
    var defaultBranch: String?
    var description: String?
    var hasIssues: Bool = false
    var hasWiki: Bool = false
    var hasPullRequests: Bool = false
    var hasPackages: Bool = false
    var htmlURL: String?
    var updatedAt: Date?
    var starsCount: Int?
    var forksCount: Int?
}

struct GiteaRepositorySettingsDraft: Equatable, Hashable, Sendable {
    var fullName = ""
    var description = ""
    var isPrivate = true
    var defaultBranch = ""
    var hasIssues = true
    var hasWiki = true
    var hasPullRequests = true
    var hasPackages = true
    var archived = false

    var trimmedFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDefaultBranch: String {
        defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GiteaUserSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var username: String
    var fullName: String?
    var email: String?
    var isAdmin: Bool?
    var isActive: Bool?
    var lastLogin: Date?
}

struct GiteaUserDraft: Equatable, Hashable, Sendable {
    var originalUsername = ""
    var username = ""
    var email = ""
    var password = ""
    var fullName = ""
    var mustChangePassword = true
    var isActive = true
    var isAdmin = false
    var prohibitLogin = false
    var restricted = false

    var trimmedOriginalUsername: String {
        originalUsername.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GiteaUserSaveMode: String, CaseIterable, Identifiable, Sendable {
    case create
    case update

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .create:
            "创建"
        case .update:
            "保存"
        }
    }

    var actionDescription: String {
        switch self {
        case .create:
            "creates"
        case .update:
            "updates"
        }
    }
}

struct GiteaOrganizationSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var username: String
    var fullName: String?
    var description: String?
    var website: String?
    var visibility: String?
}

struct GiteaOrganizationDraft: Equatable, Hashable, Sendable {
    var originalUsername = ""
    var username = ""
    var fullName = ""
    var description = ""
    var website = ""
    var visibility = "public"

    var trimmedOriginalUsername: String {
        originalUsername.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedFullName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedWebsite: String {
        website.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GiteaOrganizationSaveMode: String, CaseIterable, Identifiable, Sendable {
    case create
    case update

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .create:
            "创建"
        case .update:
            "保存"
        }
    }

    var actionDescription: String {
        switch self {
        case .create:
            "creates"
        case .update:
            "updates"
        }
    }
}

struct GiteaTeamSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var organization: String
    var name: String
    var description: String?
    var permission: String?
    var includesAllRepositories: Bool?
    var canCreateOrgRepo: Bool?
    var units: [String]?
}

struct GiteaTeamDraft: Equatable, Hashable, Sendable {
    var teamId: Int64 = 0
    var organization = ""
    var name = ""
    var description = ""
    var permission = "read"
    var includesAllRepositories = false
    var canCreateOrgRepo = true
    var units: [String] = ["repo.code", "repo.issues", "repo.pulls", "repo.releases"]

    var trimmedOrganization: String {
        organization.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GiteaTeamSaveMode: String, CaseIterable, Identifiable, Sendable {
    case create
    case update

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .create:
            "创建"
        case .update:
            "保存"
        }
    }

    var actionDescription: String {
        switch self {
        case .create:
            "creates"
        case .update:
            "updates"
        }
    }
}

struct GiteaTeamMemberSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: String { "\(teamId):\(username)" }
    var teamId: Int64
    var username: String
    var fullName: String?
    var email: String?
    var isAdmin: Bool?
    var isActive: Bool?
    var lastLogin: Date?
}

struct GiteaTeamMemberDraft: Equatable, Hashable, Sendable {
    var teamId: Int64 = 0
    var username = ""

    var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GiteaTeamRepositorySummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: String { "\(teamId):\(fullName)" }
    var teamId: Int64
    var repositoryId: Int64
    var fullName: String
    var owner: String
    var name: String
    var isPrivate: Bool
    var defaultBranch: String?
    var updatedAt: Date?
}

struct GiteaTeamRepositoryDraft: Equatable, Hashable, Sendable {
    var teamId: Int64 = 0
    var repositoryFullName = ""

    var trimmedRepositoryFullName: String {
        repositoryFullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GiteaKeySummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var title: String
    var key: String
    var fingerprint: String?
    var url: String?
    var isReadOnly: Bool?
    var createdAt: Date?
}

struct GiteaKeyDraft: Equatable, Hashable, Sendable {
    var title = ""
    var key = ""
    var isReadOnly = false

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GiteaAccessTokenSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var username: String = ""
    var name: String
    var scopes: [String]
    var sha1: String?
    var tokenLastEight: String?
    var createdAt: Date?
    var lastUsedAt: Date?
}

struct GiteaAccessTokenDraft: Equatable, Hashable, Sendable {
    var username = ""
    var name = ""
    var scopes: [String] = ["read:repository", "read:user"]

    var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GiteaAccessTokenCreationResult: Identifiable, Equatable, Hashable, Sendable {
    var id: Int64 { token.id }
    var token: GiteaAccessTokenSummary
    var secret: String
}

struct GiteaPackageSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var owner: String
    var name: String
    var type: String
    var version: String?
    var repository: String?
    var htmlURL: String?
    var createdAt: Date?
}

struct GiteaPackageDetail: Equatable, Hashable, Sendable {
    var id: String { "\(owner)/\(type)/\(name)#\(selectedVersion ?? "all")" }
    var owner: String
    var type: String
    var name: String
    var selectedVersion: String?
    var package: GiteaPackageSummary?
    var versions: [GiteaPackageSummary]
    var files: [GiteaPackageFileSummary]
    var capturedAt: Date
}

struct GiteaPackageFileSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var name: String
    var size: Int64?
    var md5: String?
    var sha1: String?
    var sha256: String?
    var sha512: String?
}

struct GiteaAdminOverviewSummary: Decodable, Equatable, Hashable, Sendable {
    var version: String?
    var cronTasks: [GiteaCronTaskSummary]
}

struct GiteaCronTaskSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var schedule: String?
    var execTimes: Int64?
    var previousRunAt: Date?
    var nextRunAt: Date?
}

struct GiteaIssueSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var number: Int
    var title: String
    var state: String
    var repository: String?
    var author: String?
    var assignees: [String] = []
    var labels: [String] = []
    var milestone: String?
    var htmlURL: String?
    var updatedAt: Date?
}

struct GiteaPullRequestSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var number: Int
    var title: String
    var state: String
    var repository: String?
    var author: String?
    var assignees: [String] = []
    var labels: [String] = []
    var milestone: String?
    var htmlURL: String?
    var updatedAt: Date?
}

struct GitLabAdminOverviewSummary: Decodable, Equatable, Hashable, Sendable {
    var version: String?
    var revision: String?
    var enterprise: Bool?
    var licensePlan: String?
    var licenseStartsAt: String?
    var licenseExpiresAt: String?
    var licenseExpired: Bool?
    var userLimit: Int?
    var activeUserCount: Int?
    var userCount: Int?
    var projectCount: Int?
    var groupCount: Int?
    var issueCount: Int?
    var mergeRequestCount: Int?
    var runnerCount: Int?
    var healthStatus: String?
    var readinessStatus: String?
    var livenessStatus: String?
    var unavailableReasons: [String]

    static var empty: GitLabAdminOverviewSummary {
        GitLabAdminOverviewSummary(
            version: nil,
            revision: nil,
            enterprise: nil,
            licensePlan: nil,
            licenseStartsAt: nil,
            licenseExpiresAt: nil,
            licenseExpired: nil,
            userLimit: nil,
            activeUserCount: nil,
            userCount: nil,
            projectCount: nil,
            groupCount: nil,
            issueCount: nil,
            mergeRequestCount: nil,
            runnerCount: nil,
            healthStatus: nil,
            readinessStatus: nil,
            livenessStatus: nil,
            unavailableReasons: []
        )
    }
}

struct GitLabNativeSnapshot: Decodable, Equatable, Hashable, Sendable {
    var projects: [GitLabProjectSummary]
    var groups: [GitLabGroupSummary]
    var users: [GitLabUserSummary]
    var members: [GitLabMemberSummary]
    var branches: [GitLabBranchSummary]
    var tags: [GitLabTagSummary]
    var issues: [GitLabIssueSummary]
    var mergeRequests: [GitLabMergeRequestSummary]
    var pipelines: [GitLabPipelineSummary]
    var jobs: [GitLabJobSummary]
    var packages: [GitLabPackageSummary]
    var runners: [GitLabRunnerSummary]
    var variables: [GitLabVariableSummary]
    var deployKeys: [GitLabDeployKeySummary]
    var deployTokens: [GitLabDeployTokenSummary]
    var adminOverview: GitLabAdminOverviewSummary
    var capturedAt: Date
}

extension GitLabNativeSnapshot {
    private enum CodingKeys: String, CodingKey {
        case projects
        case groups
        case users
        case members
        case branches
        case tags
        case issues
        case mergeRequests
        case pipelines
        case jobs
        case packages
        case runners
        case variables
        case deployKeys
        case deployTokens
        case adminOverview
        case capturedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decode([GitLabProjectSummary].self, forKey: .projects)
        groups = try container.decode([GitLabGroupSummary].self, forKey: .groups)
        users = try container.decode([GitLabUserSummary].self, forKey: .users)
        members = try container.decode([GitLabMemberSummary].self, forKey: .members)
        branches = try container.decode([GitLabBranchSummary].self, forKey: .branches)
        tags = try container.decode([GitLabTagSummary].self, forKey: .tags)
        issues = try container.decode([GitLabIssueSummary].self, forKey: .issues)
        mergeRequests = try container.decode([GitLabMergeRequestSummary].self, forKey: .mergeRequests)
        pipelines = try container.decode([GitLabPipelineSummary].self, forKey: .pipelines)
        jobs = try container.decode([GitLabJobSummary].self, forKey: .jobs)
        packages = try container.decode([GitLabPackageSummary].self, forKey: .packages)
        runners = try container.decode([GitLabRunnerSummary].self, forKey: .runners)
        variables = try container.decode([GitLabVariableSummary].self, forKey: .variables)
        deployKeys = try container.decode([GitLabDeployKeySummary].self, forKey: .deployKeys)
        deployTokens = try container.decode([GitLabDeployTokenSummary].self, forKey: .deployTokens)
        adminOverview = try container.decodeIfPresent(GitLabAdminOverviewSummary.self, forKey: .adminOverview) ?? .empty
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
    }
}

struct GitLabProjectSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var name: String
    var pathWithNamespace: String
    var description: String?
    var visibility: String?
    var defaultBranch: String?
    var webURL: String?
    var lastActivityAt: Date?
    var archived: Bool
}

struct GitLabGroupSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var name: String
    var fullPath: String
    var visibility: String?
    var webURL: String?
}

struct GitLabUserSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var username: String
    var name: String?
    var state: String?
    var webURL: String?
    var isAdmin: Bool?
}

struct GitLabMemberSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: String { "\(scope.rawValue):\(targetId):\(userId)" }
    var scope: GitLabMemberScope
    var targetId: Int64
    var userId: Int64
    var username: String
    var name: String?
    var state: String?
    var webURL: String?
    var accessLevel: Int
    var expiresAt: String?
    var createdAt: Date?
}

struct GitLabBranchSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: String { "\(projectId):\(name)" }
    var projectId: Int64
    var name: String
    var merged: Bool?
    var protected: Bool
    var isDefault: Bool
    var canPush: Bool?
    var webURL: String?
    var commitShortID: String?
    var commitTitle: String?
    var committedDate: Date?
}

struct GitLabTagSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: String { "\(projectId):\(name)" }
    var projectId: Int64
    var name: String
    var message: String?
    var target: String?
    var protected: Bool?
    var commitShortID: String?
    var commitTitle: String?
    var createdAt: Date?
}

struct GitLabIssueSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var iid: Int
    var title: String
    var state: String
    var projectId: Int64?
    var author: String?
    var assignees: [String] = []
    var labels: [String] = []
    var milestone: String?
    var webURL: String?
    var updatedAt: Date?
}

struct GitLabMergeRequestSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var iid: Int
    var title: String
    var state: String
    var sourceBranch: String?
    var targetBranch: String?
    var projectId: Int64?
    var author: String?
    var assignees: [String] = []
    var reviewers: [String] = []
    var labels: [String] = []
    var milestone: String?
    var webURL: String?
    var updatedAt: Date?
}

struct GitLabPipelineSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var projectId: Int64
    var ref: String?
    var sha: String?
    var status: String
    var webURL: String?
    var updatedAt: Date?
}

struct GitLabJobSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var projectId: Int64
    var name: String
    var stage: String?
    var ref: String?
    var status: String
    var webURL: String?
    var duration: Double?
    var startedAt: Date?
    var finishedAt: Date?
}

struct GitLabJobTrace: Equatable, Hashable, Sendable {
    var projectId: Int64
    var jobId: Int64
    var text: String
    var capturedAt: Date
}

struct GitLabPackageSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var projectId: Int64
    var name: String
    var version: String?
    var packageType: String
    var status: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct GitLabRunnerSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var description: String?
    var name: String?
    var status: String?
    var runnerType: String?
    var isShared: Bool?
    var active: Bool?
    var paused: Bool?
    var online: Bool?
    var tagList: [String]
    var version: String?
    var contactedAt: Date?
}

struct GitLabVariableSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: String { "\(projectId):\(key):\(environmentScope ?? "*")" }
    var projectId: Int64
    var key: String
    var variableType: String?
    var environmentScope: String?
    var protected: Bool
    var masked: Bool
    var raw: Bool?
    var description: String?
}

struct GitLabDeployKeySummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var projectId: Int64
    var title: String
    var key: String?
    var fingerprint: String?
    var canPush: Bool
    var createdAt: Date?
    var expiresAt: String?
}

struct GitLabDeployTokenSummary: Identifiable, Decodable, Equatable, Hashable, Sendable {
    var id: Int64
    var projectId: Int64
    var name: String
    var username: String?
    var scopes: [String]
    var revoked: Bool
    var expired: Bool
    var active: Bool?
    var createdAt: Date?
    var expiresAt: String?
}

struct GitLabDeployTokenCreationResult: Identifiable, Equatable, Hashable, Sendable {
    var id: Int64 { deployToken.id }
    var deployToken: GitLabDeployTokenSummary
    var token: String
}

extension GiteaRepositorySummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case owner
        case isPrivate = "private"
        case isArchived = "archived"
        case defaultBranch = "default_branch"
        case description
        case hasIssues = "has_issues"
        case hasWiki = "has_wiki"
        case hasPullRequests = "has_pull_requests"
        case hasPackages = "has_packages"
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
        case starsCount = "stars_count"
        case forksCount = "forks_count"
    }

    private struct Owner: Decodable {
        var login: String?
        var username: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let owner = try? container.decode(Owner.self, forKey: .owner)
        let fallbackName = try container.decode(String.self, forKey: .name)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            name: fallbackName,
            fullName: (try container.decodeIfPresent(String.self, forKey: .fullName)) ?? fallbackName,
            owner: owner?.login ?? owner?.username ?? "",
            isPrivate: try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false,
            isArchived: try container.decodeIfPresent(Bool.self, forKey: .isArchived),
            defaultBranch: try container.decodeIfPresent(String.self, forKey: .defaultBranch),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            hasIssues: try container.decodeIfPresent(Bool.self, forKey: .hasIssues) ?? false,
            hasWiki: try container.decodeIfPresent(Bool.self, forKey: .hasWiki) ?? false,
            hasPullRequests: try container.decodeIfPresent(Bool.self, forKey: .hasPullRequests) ?? false,
            hasPackages: try container.decodeIfPresent(Bool.self, forKey: .hasPackages) ?? false,
            htmlURL: try container.decodeIfPresent(String.self, forKey: .htmlURL),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt),
            starsCount: try container.decodeIfPresent(Int.self, forKey: .starsCount),
            forksCount: try container.decodeIfPresent(Int.self, forKey: .forksCount)
        )
    }
}

extension GiteaUserSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case username = "login"
        case fullName = "full_name"
        case email
        case isAdmin = "is_admin"
        case isActive = "active"
        case lastLogin = "last_login"
    }
}

extension GiteaOrganizationSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case fullName = "full_name"
        case description
        case website
        case visibility
    }
}

extension GiteaTeamSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case organization
        case name
        case description
        case permission
        case includesAllRepositories = "includes_all_repositories"
        case canCreateOrgRepo = "can_create_org_repo"
        case units
    }

    private struct Organization: Decodable {
        var username: String?
        var name: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let organization = try? container.decode(Organization.self, forKey: .organization)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            organization: organization?.username ?? organization?.name ?? "",
            name: try container.decode(String.self, forKey: .name),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            permission: try container.decodeIfPresent(String.self, forKey: .permission),
            includesAllRepositories: try container.decodeIfPresent(Bool.self, forKey: .includesAllRepositories),
            canCreateOrgRepo: try container.decodeIfPresent(Bool.self, forKey: .canCreateOrgRepo),
            units: try container.decodeIfPresent([String].self, forKey: .units)
        )
    }
}

extension GiteaTeamMemberSummary {
    private enum CodingKeys: String, CodingKey {
        case username = "login"
        case fullName = "full_name"
        case email
        case isAdmin = "is_admin"
        case isActive = "active"
        case lastLogin = "last_login"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            teamId: 0,
            username: try container.decode(String.self, forKey: .username),
            fullName: try container.decodeIfPresent(String.self, forKey: .fullName),
            email: try container.decodeIfPresent(String.self, forKey: .email),
            isAdmin: try container.decodeIfPresent(Bool.self, forKey: .isAdmin),
            isActive: try container.decodeIfPresent(Bool.self, forKey: .isActive),
            lastLogin: try container.decodeIfPresent(Date.self, forKey: .lastLogin)
        )
    }
}

extension GiteaKeySummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case key
        case fingerprint
        case url
        case isReadOnly = "read_only"
        case createdAt = "created_at"
    }
}

extension GiteaAccessTokenSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case scopes
        case sha1
        case tokenLastEight = "token_last_eight"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }
}

extension GiteaPackageSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case owner
        case name
        case type
        case version
        case repository
        case htmlURL = "html_url"
        case createdAt = "created_at"
    }

    private struct Owner: Decodable {
        var username: String?
        var login: String?

        private enum CodingKeys: String, CodingKey {
            case username
            case login
        }
    }

    private struct Repository: Decodable {
        var fullName: String?
        var name: String?

        private enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case name
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let owner = try container.decodeIfPresent(Owner.self, forKey: .owner)
        let repository = try container.decodeIfPresent(Repository.self, forKey: .repository)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            owner: owner?.username ?? owner?.login ?? "",
            name: try container.decode(String.self, forKey: .name),
            type: try container.decode(String.self, forKey: .type),
            version: try container.decodeIfPresent(String.self, forKey: .version),
            repository: repository?.fullName ?? repository?.name,
            htmlURL: try container.decodeIfPresent(String.self, forKey: .htmlURL),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt)
        )
    }
}

extension GiteaPackageFileSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case size
        case md5
        case sha1
        case sha256
        case sha512
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

extension GiteaCronTaskSummary {
    private enum CodingKeys: String, CodingKey {
        case name
        case schedule
        case execTimes = "exec_times"
        case previousRunAt = "prev"
        case nextRunAt = "next"
    }
}

extension GiteaIssueSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case state
        case repository
        case user
        case assignee
        case assignees
        case labels
        case milestone
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
    }

    private struct Repository: Decodable {
        var fullName: String?
        var name: String?

        private enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case name
        }
    }

    private struct User: Decodable {
        var login: String?
        var username: String?
    }

    private struct Label: Decodable {
        var name: String?
    }

    private struct Milestone: Decodable {
        var title: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let repository = try? container.decode(Repository.self, forKey: .repository)
        let user = try? container.decode(User.self, forKey: .user)
        let assignee = try? container.decode(User.self, forKey: .assignee)
        let assignees = (try? container.decode([User].self, forKey: .assignees)) ?? []
        let labels = (try? container.decode([Label].self, forKey: .labels)) ?? []
        let milestone = try? container.decode(Milestone.self, forKey: .milestone)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            number: try container.decode(Int.self, forKey: .number),
            title: try container.decode(String.self, forKey: .title),
            state: try container.decode(String.self, forKey: .state),
            repository: repository?.fullName ?? repository?.name,
            author: user?.login ?? user?.username,
            assignees: (assignees.map { $0.login ?? $0.username } + [assignee?.login ?? assignee?.username])
                .compactMap { $0 }
                .uniqued(),
            labels: labels.compactMap(\.name),
            milestone: milestone?.title,
            htmlURL: try container.decodeIfPresent(String.self, forKey: .htmlURL),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }
}

extension GiteaPullRequestSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case state
        case repository
        case user
        case assignee
        case assignees
        case labels
        case milestone
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
    }

    private struct Repository: Decodable {
        var fullName: String?
        var name: String?

        private enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case name
        }
    }

    private struct User: Decodable {
        var login: String?
        var username: String?
    }

    private struct Label: Decodable {
        var name: String?
    }

    private struct Milestone: Decodable {
        var title: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let repository = try? container.decode(Repository.self, forKey: .repository)
        let user = try? container.decode(User.self, forKey: .user)
        let assignee = try? container.decode(User.self, forKey: .assignee)
        let assignees = (try? container.decode([User].self, forKey: .assignees)) ?? []
        let labels = (try? container.decode([Label].self, forKey: .labels)) ?? []
        let milestone = try? container.decode(Milestone.self, forKey: .milestone)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            number: try container.decode(Int.self, forKey: .number),
            title: try container.decode(String.self, forKey: .title),
            state: try container.decode(String.self, forKey: .state),
            repository: repository?.fullName ?? repository?.name,
            author: user?.login ?? user?.username,
            assignees: (assignees.map { $0.login ?? $0.username } + [assignee?.login ?? assignee?.username])
                .compactMap { $0 }
                .uniqued(),
            labels: labels.compactMap(\.name),
            milestone: milestone?.title,
            htmlURL: try container.decodeIfPresent(String.self, forKey: .htmlURL),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }
}

extension GitLabProjectSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case pathWithNamespace = "path_with_namespace"
        case description
        case visibility
        case defaultBranch = "default_branch"
        case webURL = "web_url"
        case lastActivityAt = "last_activity_at"
        case archived
    }
}

extension GitLabGroupSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullPath = "full_path"
        case visibility
        case webURL = "web_url"
    }
}

extension GitLabUserSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case state
        case webURL = "web_url"
        case isAdmin = "is_admin"
    }
}

extension GitLabMemberSummary {
    private enum CodingKeys: String, CodingKey {
        case userId = "id"
        case username
        case name
        case state
        case webURL = "web_url"
        case accessLevel = "access_level"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scope: .project,
            targetId: 0,
            userId: try container.decode(Int64.self, forKey: .userId),
            username: try container.decode(String.self, forKey: .username),
            name: try container.decodeIfPresent(String.self, forKey: .name),
            state: try container.decodeIfPresent(String.self, forKey: .state),
            webURL: try container.decodeIfPresent(String.self, forKey: .webURL),
            accessLevel: try container.decode(Int.self, forKey: .accessLevel),
            expiresAt: try container.decodeIfPresent(String.self, forKey: .expiresAt),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt)
        )
    }
}

extension GitLabBranchSummary {
    private enum CodingKeys: String, CodingKey {
        case name
        case merged
        case protected
        case isDefault = "default"
        case canPush = "can_push"
        case webURL = "web_url"
        case commit
    }

    private struct Commit: Decodable {
        var shortID: String?
        var title: String?
        var committedDate: Date?

        private enum CodingKeys: String, CodingKey {
            case shortID = "short_id"
            case title
            case committedDate = "committed_date"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let commit = try container.decodeIfPresent(Commit.self, forKey: .commit)
        self.init(
            projectId: 0,
            name: try container.decode(String.self, forKey: .name),
            merged: try container.decodeIfPresent(Bool.self, forKey: .merged),
            protected: try container.decodeIfPresent(Bool.self, forKey: .protected) ?? false,
            isDefault: try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false,
            canPush: try container.decodeIfPresent(Bool.self, forKey: .canPush),
            webURL: try container.decodeIfPresent(String.self, forKey: .webURL),
            commitShortID: commit?.shortID,
            commitTitle: commit?.title,
            committedDate: commit?.committedDate
        )
    }
}

extension GitLabTagSummary {
    private enum CodingKeys: String, CodingKey {
        case name
        case message
        case target
        case protected
        case commit
        case createdAt = "created_at"
    }

    private struct Commit: Decodable {
        var shortID: String?
        var title: String?

        private enum CodingKeys: String, CodingKey {
            case shortID = "short_id"
            case title
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let commit = try container.decodeIfPresent(Commit.self, forKey: .commit)
        self.init(
            projectId: 0,
            name: try container.decode(String.self, forKey: .name),
            message: try container.decodeIfPresent(String.self, forKey: .message),
            target: try container.decodeIfPresent(String.self, forKey: .target),
            protected: try container.decodeIfPresent(Bool.self, forKey: .protected),
            commitShortID: commit?.shortID,
            commitTitle: commit?.title,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt)
        )
    }
}

extension GitLabIssueSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case title
        case state
        case projectId = "project_id"
        case author
        case assignee
        case assignees
        case labels
        case milestone
        case webURL = "web_url"
        case updatedAt = "updated_at"
    }

    private struct User: Decodable {
        var username: String?
        var name: String?
    }

    private struct Milestone: Decodable {
        var title: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let author = try? container.decode(User.self, forKey: .author)
        let assignee = try? container.decode(User.self, forKey: .assignee)
        let assignees = (try? container.decode([User].self, forKey: .assignees)) ?? []
        let milestone = try? container.decode(Milestone.self, forKey: .milestone)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            iid: try container.decode(Int.self, forKey: .iid),
            title: try container.decode(String.self, forKey: .title),
            state: try container.decode(String.self, forKey: .state),
            projectId: try container.decodeIfPresent(Int64.self, forKey: .projectId),
            author: author?.username ?? author?.name,
            assignees: (assignees.map { $0.username ?? $0.name } + [assignee?.username ?? assignee?.name])
                .compactMap { $0 }
                .uniqued(),
            labels: try container.decodeIfPresent([String].self, forKey: .labels) ?? [],
            milestone: milestone?.title,
            webURL: try container.decodeIfPresent(String.self, forKey: .webURL),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }
}

extension GitLabMergeRequestSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case iid
        case title
        case state
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case projectId = "project_id"
        case author
        case assignee
        case assignees
        case reviewers
        case labels
        case milestone
        case webURL = "web_url"
        case updatedAt = "updated_at"
    }

    private struct User: Decodable {
        var username: String?
        var name: String?
    }

    private struct Milestone: Decodable {
        var title: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let author = try? container.decode(User.self, forKey: .author)
        let assignee = try? container.decode(User.self, forKey: .assignee)
        let assignees = (try? container.decode([User].self, forKey: .assignees)) ?? []
        let reviewers = (try? container.decode([User].self, forKey: .reviewers)) ?? []
        let milestone = try? container.decode(Milestone.self, forKey: .milestone)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            iid: try container.decode(Int.self, forKey: .iid),
            title: try container.decode(String.self, forKey: .title),
            state: try container.decode(String.self, forKey: .state),
            sourceBranch: try container.decodeIfPresent(String.self, forKey: .sourceBranch),
            targetBranch: try container.decodeIfPresent(String.self, forKey: .targetBranch),
            projectId: try container.decodeIfPresent(Int64.self, forKey: .projectId),
            author: author?.username ?? author?.name,
            assignees: (assignees.map { $0.username ?? $0.name } + [assignee?.username ?? assignee?.name])
                .compactMap { $0 }
                .uniqued(),
            reviewers: reviewers.compactMap { $0.username ?? $0.name },
            labels: try container.decodeIfPresent([String].self, forKey: .labels) ?? [],
            milestone: milestone?.title,
            webURL: try container.decodeIfPresent(String.self, forKey: .webURL),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }
}

extension GitLabPipelineSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case ref
        case sha
        case status
        case webURL = "web_url"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            projectId: try container.decodeIfPresent(Int64.self, forKey: .projectId) ?? 0,
            ref: try container.decodeIfPresent(String.self, forKey: .ref),
            sha: try container.decodeIfPresent(String.self, forKey: .sha),
            status: try container.decode(String.self, forKey: .status),
            webURL: try container.decodeIfPresent(String.self, forKey: .webURL),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }
}

extension GitLabJobSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case name
        case stage
        case ref
        case status
        case webURL = "web_url"
        case duration
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            projectId: try container.decodeIfPresent(Int64.self, forKey: .projectId) ?? 0,
            name: try container.decode(String.self, forKey: .name),
            stage: try container.decodeIfPresent(String.self, forKey: .stage),
            ref: try container.decodeIfPresent(String.self, forKey: .ref),
            status: try container.decode(String.self, forKey: .status),
            webURL: try container.decodeIfPresent(String.self, forKey: .webURL),
            duration: try container.decodeIfPresent(Double.self, forKey: .duration),
            startedAt: try container.decodeIfPresent(Date.self, forKey: .startedAt),
            finishedAt: try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        )
    }
}

extension GitLabPackageSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case name
        case version
        case packageType = "package_type"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            projectId: try container.decodeIfPresent(Int64.self, forKey: .projectId) ?? 0,
            name: try container.decode(String.self, forKey: .name),
            version: try container.decodeIfPresent(String.self, forKey: .version),
            packageType: try container.decode(String.self, forKey: .packageType),
            status: try container.decodeIfPresent(String.self, forKey: .status),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }
}

extension GitLabRunnerSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case description
        case name
        case status
        case runnerType = "runner_type"
        case isShared = "is_shared"
        case active
        case paused
        case online
        case tagList = "tag_list"
        case version
        case contactedAt = "contacted_at"
    }
}

extension GitLabVariableSummary {
    private enum CodingKeys: String, CodingKey {
        case key
        case variableType = "variable_type"
        case environmentScope = "environment_scope"
        case protected
        case masked
        case raw
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            projectId: 0,
            key: try container.decode(String.self, forKey: .key),
            variableType: try container.decodeIfPresent(String.self, forKey: .variableType),
            environmentScope: try container.decodeIfPresent(String.self, forKey: .environmentScope),
            protected: try container.decodeIfPresent(Bool.self, forKey: .protected) ?? false,
            masked: try container.decodeIfPresent(Bool.self, forKey: .masked) ?? false,
            raw: try container.decodeIfPresent(Bool.self, forKey: .raw),
            description: try container.decodeIfPresent(String.self, forKey: .description)
        )
    }
}

extension GitLabDeployKeySummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case key
        case fingerprint
        case canPush = "can_push"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            projectId: 0,
            title: try container.decode(String.self, forKey: .title),
            key: try container.decodeIfPresent(String.self, forKey: .key),
            fingerprint: try container.decodeIfPresent(String.self, forKey: .fingerprint),
            canPush: try container.decodeIfPresent(Bool.self, forKey: .canPush) ?? false,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt),
            expiresAt: try container.decodeIfPresent(String.self, forKey: .expiresAt)
        )
    }
}

extension GitLabDeployTokenSummary {
    private enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case name
        case username
        case scopes
        case revoked
        case expired
        case active
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(Int64.self, forKey: .id),
            projectId: try container.decodeIfPresent(Int64.self, forKey: .projectId) ?? 0,
            name: try container.decode(String.self, forKey: .name),
            username: try container.decodeIfPresent(String.self, forKey: .username),
            scopes: try container.decodeIfPresent([String].self, forKey: .scopes) ?? [],
            revoked: try container.decodeIfPresent(Bool.self, forKey: .revoked) ?? false,
            expired: try container.decodeIfPresent(Bool.self, forKey: .expired) ?? false,
            active: try container.decodeIfPresent(Bool.self, forKey: .active),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt),
            expiresAt: try container.decodeIfPresent(String.self, forKey: .expiresAt)
        )
    }
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

    static func databaseService(action: SystemdUnitAction, service: DatabaseService) -> RemoteOperationRisk {
        let level: RemoteOperationRiskLevel = action == .stop || action == .restart ? .high : .medium
        return RemoteOperationRisk(
            id: "database-\(action.rawValue)-\(service.kind.rawValue)",
            level: level,
            title: "\(action.displayName) Database Service",
            target: service.unitName ?? service.kind.displayName,
            commandPreview: service.unitName.map { "systemctl \(action.rawValue) \($0)" },
            impact: ["Database service state may change immediately and connected applications may be interrupted."],
            recovery: "Use the inverse service action, inspect recent logs, and restore from backups if the database fails to start.",
            auditTargetType: "database_service",
            auditAction: action.rawValue
        )
    }

    static func databaseBackup(service: DatabaseService, plan: DatabaseBackupRestorePlan) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "database-backup-\(service.kind.rawValue)-\(plan.backupPath)",
            level: .medium,
            title: "Create Database Backup",
            target: service.unitName ?? service.kind.displayName,
            commandPreview: plan.backupCommand,
            impact: [
                "A database backup command will run on the remote server.",
                "The backup file will consume disk space at \(plan.backupPath)."
            ],
            recovery: "Review the generated backup file and delete it manually if it is not needed.",
            auditTargetType: "database_service",
            auditAction: "backup"
        )
    }

    static func dockerContainer(action: DockerContainerAction, container: DockerContainer) -> RemoteOperationRisk {
        let level: RemoteOperationRiskLevel = action == .start ? .medium : .high
        return RemoteOperationRisk(
            id: "docker-\(action.rawValue)-\(container.containerID)",
            level: level,
            title: "\(action.displayName) Docker Container",
            target: container.displayName,
            commandPreview: "docker \(action.rawValue) \(container.containerID)",
            impact: ["The selected Docker container state will change on the remote server."],
            recovery: "Use another Docker action after reviewing container status and logs.",
            auditTargetType: "docker_container",
            auditAction: action.rawValue
        )
    }

    static func dockerImagePull(reference: String) -> RemoteOperationRisk {
        let target = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemoteOperationRisk(
            id: "docker-image-pull-\(target)",
            level: .medium,
            title: "Pull Docker Image",
            target: target,
            commandPreview: "docker pull \(target)",
            impact: ["The remote server will download image layers and consume disk space and network traffic."],
            recovery: "Remove the image after reviewing dependent containers if the pull is not needed.",
            auditTargetType: "docker_image",
            auditAction: "pull"
        )
    }

    static func dockerImageRemove(_ image: DockerImage) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "docker-image-remove-\(image.imageID)",
            level: .high,
            title: "Remove Docker Image",
            target: image.displayName,
            commandPreview: "docker rmi \(image.imageID)",
            impact: ["The selected Docker image will be removed if no running containers depend on it."],
            recovery: "Pull the image again if it is needed later.",
            auditTargetType: "docker_image",
            auditAction: "remove"
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
        let targetCommit = run.previousCommit ?? L10n.string("previous commit")
        return RemoteOperationRisk(
            id: "deployment-rollback-\(project.id)-\(run.id)",
            level: .high,
            title: L10n.string("Rollback Deployment"),
            target: "\(project.name) -> \(targetCommit)",
            commandPreview: "git checkout \(targetCommit) && git reset --hard \(targetCommit)",
            impact: [
                L10n.string("The deployment working tree will be reset to the selected previous commit."),
                L10n.string("Configured build, restart, and health check commands will run again."),
            ],
            recovery: L10n.string("Run a new deployment from the target branch if the rollback needs to be undone."),
            auditTargetType: "deployment",
            auditAction: "rollback"
        )
    }

    static func deploymentRun(project: DeploymentProject, plan: DeploymentCommandPlan) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "deployment-run-\(project.id)-\(project.updatedAt.timeIntervalSince1970)",
            level: .high,
            title: L10n.string("Run Deployment"),
            target: "\(project.name) -> \(project.deployPath)",
            commandPreview: plan.commandPreview,
            impact: [
                L10n.string("The deployment working tree may be cloned, fetched, checked out, and reset."),
                L10n.string("Configured build, restart, and health check commands will run on the remote server."),
            ],
            recovery: L10n.string("Use rollback from a completed run if the deployment needs to be reverted."),
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

    static func installGitLab(draft: GitLabInstallDraft) -> RemoteOperationRisk {
        RemoteOperationRisk(
            id: "gitlab-install-\(draft.edition.rawValue)-\(draft.externalURL.trimmingCharacters(in: .whitespacesAndNewlines))",
            level: .critical,
            title: L10n.string("Install GitLab"),
            target: draft.externalURL.trimmingCharacters(in: .whitespacesAndNewlines),
            commandPreview: (try? GitLabInstaller.installCommand(for: draft)) ?? L10n.string("Validate GitLab settings before previewing install commands."),
            impact: [
                L10n.string("The GitLab Linux package repository will be configured on the remote server."),
                L10n.format("The %@ package will be installed and configured for the selected external URL.", draft.edition.packageName),
                L10n.string("Ports 22, 80, and 443 may be used by GitLab or its bundled services."),
            ],
            recovery: L10n.string("Review /etc/gitlab/gitlab.rb, gitlab-ctl status, and package manager logs before retrying or uninstalling GitLab manually."),
            auditTargetType: "gitlab_service",
            auditAction: "install"
        )
    }

    static func gitLabServiceAction(_ action: GitLabServiceAction, draft: GitLabInstallDraft) -> RemoteOperationRisk {
        let level: RemoteOperationRiskLevel = action == .stop ? .high : .medium
        return RemoteOperationRisk(
            id: "gitlab-service-\(action.rawValue)-\(draft.externalURL.trimmingCharacters(in: .whitespacesAndNewlines))",
            level: level,
            title: L10n.format("%@ GitLab", action.displayName),
            target: draft.externalURL.trimmingCharacters(in: .whitespacesAndNewlines),
            commandPreview: GitLabManager.serviceActionCommand(action),
            impact: [L10n.string("The GitLab service state or generated configuration will change on the remote server.")],
            recovery: L10n.string("Use gitlab-ctl status and recent logs to inspect the result, then run another service action if needed."),
            auditTargetType: "gitlab_service",
            auditAction: action.rawValue
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
    var inferredServerKind: ServerKind {
        switch providerId {
        case .tencentCloud:
            .tencentCVM
        case .alibabaCloud:
            .alibabaECS
        case .huaweiCloud:
            .huaweiECS
        }
    }

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
