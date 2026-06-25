import CryptoKit
import Foundation
import Network

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

    private func credential(for account: CloudProviderAccount) throws -> CloudProviderCredential {
        guard let credential = try keychain.readCloudCredential(keychainRef: account.keychainRef) else {
            throw CloudProviderError.authenticationFailed("Cloud credential is missing from Keychain.")
        }
        return credential
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
    private let now: @Sendable () -> Date

    init(
        repository: ServerRepository,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.now = now
    }

    func run(
        project: DeploymentProject,
        profile: ServerProfile,
        sshClient: SSHClient,
        triggerType: DeploymentTriggerType = .manual,
        requestedRef: String? = nil
    ) async throws -> DeploymentRun {
        let plan = try DeploymentCommandBuilder.buildPlan(for: project)
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
        let plan = try DeploymentCommandBuilder.buildRollbackPlan(for: project, targetCommit: targetCommit)
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

enum RegistryConfigurationError: LocalizedError, Equatable {
    case invalidName
    case invalidPath(String)
    case invalidHost
    case invalidPort
    case invalidServiceName
    case invalidVersion

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

    static func configurationYAML(for draft: VerdaccioInstallDraft) throws -> String {
        try validate(draft)
        return """
        storage: \(draft.dataPath.trimmed)

        listen:
          - \(draft.listenHost.trimmed):\(draft.listenPort)

        uplinks:
          npmjs:
            url: https://registry.npmjs.org/

        packages:
          '@*/*':
            access: $all
            publish: $authenticated
            proxy: npmjs
          '**':
            access: $all
            publish: $authenticated
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
        ExecStart=/usr/bin/env npx --yes verdaccio@\(draft.version.trimmed) --config \(installPath)/config.yaml
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
}

final class VerdaccioInstaller: @unchecked Sendable {
    func install(
        draft: VerdaccioInstallDraft,
        profile: ServerProfile,
        sshClient: SSHClient
    ) async throws -> VerdaccioInstallResult {
        let command = try Self.installCommand(for: draft)
        let installResult = try await CloudProviderRequestRunner.withTimeout(30) {
            try await sshClient.execute(command, profile: profile)
        }
        guard installResult.exitCode == 0 else {
            throw SSHClientError.processFailed(Self.redactedOutput(from: installResult, fallback: "Verdaccio installation failed."))
        }

        let healthCheckURL = Self.healthCheckURL(for: draft)
        let healthResult = try await CloudProviderRequestRunner.withTimeout(10) {
            try await sshClient.execute("curl -fsS --max-time 5 \(Self.shellQuote(healthCheckURL))", profile: profile)
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

    static func statusCommand(for draft: VerdaccioInstallDraft) -> String {
        let service = shellQuote("\(draft.serviceName.trimmed).service")
        let dataPath = shellQuote(draft.dataPath.trimmed)
        return """
        service=\(service); data_path=\(dataPath); \
        printf '__HHC_VERDACCIO_ACTIVE_STATE__%s\\n' "$(systemctl show "$service" --property=ActiveState --value 2>/dev/null || echo unknown)"; \
        printf '__HHC_VERDACCIO_SUB_STATE__%s\\n' "$(systemctl show "$service" --property=SubState --value 2>/dev/null || echo unknown)"; \
        printf '__HHC_VERDACCIO_VERSION__%s\\n' "$(npx --yes verdaccio@\(draft.version.trimmed) --version 2>/dev/null || true)"; \
        printf '__HHC_VERDACCIO_STORAGE_BYTES__%s\\n' "$(du -sb "$data_path" 2>/dev/null | awk '{print $1}' || echo 0)"; \
        printf '__HHC_VERDACCIO_LOGS__'; journalctl -u "$service" -n 80 --no-pager 2>/dev/null | tail -n 80 | base64 | tr -d '\\n'; printf '\\n'
        """
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
        let values = Dictionary(uniqueKeysWithValues: text.split(separator: "\n").compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        })
        return (values["PRETTY_NAME"] ?? values["NAME"], values["VERSION_ID"] ?? values["VERSION"])
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
        let series = try await registry.adapter(for: account.providerId).fetchMetricSeries(
            credential: credential,
            query: CloudMetricQuery(
                namespace: "QCE/CVM",
                metricName: "CPUUsage",
                instanceId: link.instanceId,
                regionId: link.regionId,
                period: 300,
                startTime: start,
                endTime: end
            )
        )

        guard let latest = series.values.last else { return [] }
        return [
            DashboardMetric(
                name: "Cloud CPU",
                value: String(format: "%.1f", latest),
                unit: series.unit ?? "%",
                source: "Cloud API"
            )
        ]
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
        let groups = try await registry.adapter(for: context.account.providerId).fetchSecurityGroups(
            credential: context.credential,
            accountId: context.account.id,
            regionId: context.link.regionId
        )
        return CloudSecurityGroupList(
            accountId: context.account.id,
            providerId: context.account.providerId,
            regionId: context.link.regionId,
            instanceId: context.link.instanceId,
            groups: groups.sorted { left, right in
                left.name.localizedStandardCompare(right.name) == .orderedAscending
            },
            capturedAt: now()
        )
    }

    func loadPolicies(for group: CloudSecurityGroup) async throws -> CloudSecurityGroupPolicySnapshot {
        guard let account = try repository.fetchCloudProviderAccounts().first(where: { $0.id == group.accountId && $0.enabled }) else {
            throw CloudProviderError.authenticationFailed("Linked cloud account is missing or disabled.")
        }
        try registry.require(.securityGroups, providerId: account.providerId)
        guard let credential = try keychain.readCloudCredential(keychainRef: account.keychainRef) else {
            throw CloudProviderError.authenticationFailed("Cloud credential is missing from Keychain.")
        }
        return try await registry.adapter(for: account.providerId).fetchSecurityGroupPolicies(
            credential: credential,
            group: group,
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
        try registry.require(.securityGroups, providerId: account.providerId)
        guard let credential = try keychain.readCloudCredential(keychainRef: account.keychainRef) else {
            throw CloudProviderError.authenticationFailed("Cloud credential is missing from Keychain.")
        }
        return (link, account, credential)
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
        awk '{unit=$1; load=$2; active=$3; sub=$4; $1=$2=$3=$4=""; sub(/^ +/, ""); print unit "\\t" load "\\t" active "\\t" sub "\\t" $0}'
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
        transferClient: RemoteFileTransferClient
    ) async throws -> RemoteFileTransferResult {
        let fileName = Self.validatedFileName(localURL.lastPathComponent)
        guard !fileName.isEmpty else {
            throw SSHClientError.processFailed("Local file name cannot be empty, '.', '..', or contain '/'.")
        }
        let remotePath = Self.joinedPath(basePath: Self.normalizedDirectoryPath(directoryPath), name: fileName)
        return try await transferClient.uploadFile(localURL: localURL, remotePath: remotePath, profile: profile)
    }

    func downloadFile(
        entry: RemoteFileEntry,
        to localURL: URL,
        profile: ServerProfile,
        transferClient: RemoteFileTransferClient
    ) async throws -> RemoteFileTransferResult {
        guard entry.kind == .file else {
            throw SSHClientError.processFailed("Only regular files can be downloaded.")
        }
        return try await transferClient.downloadFile(remotePath: entry.path, localURL: localURL, profile: profile)
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
    let capabilities: Set<CloudCapability> = [.regions, .instanceDiscovery, .instanceMetadata, .cloudMetrics, .securityGroups]

    private let transport: TencentCloudHTTPTransport
    private let now: @Sendable () -> Date
    private let timeout: TimeInterval
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        transport: TencentCloudHTTPTransport = URLSessionTencentCloudHTTPTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        timeout: TimeInterval = 15
    ) {
        self.transport = transport
        self.now = now
        self.timeout = timeout
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
            metricName: query.metricName,
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
            unit: response.response.metricName == "CPUUsage" ? "%" : nil,
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

    private func request<Payload: Encodable, Response: Decodable>(
        credential: CloudProviderCredential,
        endpoint: TencentCloudEndpoint,
        payload: Payload
    ) async throws -> TencentCloudEnvelope<Response> {
        let body = try encoder.encode(payload)
        let request = try signedRequest(credential: credential, endpoint: endpoint, body: body)
        let (data, httpResponse) = try await CloudProviderRequestRunner.withTimeout(timeout) {
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

    private static func mapSecurityGroupRules(
        _ rules: [TencentSecurityGroupPolicy],
        direction: CloudSecurityGroupRuleDirection
    ) -> [CloudSecurityGroupRule] {
        rules.map { rule in
            CloudSecurityGroupRule(
                direction: direction,
                policyIndex: rule.policyIndex,
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

private struct TencentInstance: Decodable {
    var instanceId: String
    var instanceName: String?
    var instanceState: String?
    var instanceType: String?
    var publicIpAddresses: [String]?
    var privateIpAddresses: [String]?
    var placement: TencentPlacement?
    var virtualPrivateCloud: TencentVirtualPrivateCloud?
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
