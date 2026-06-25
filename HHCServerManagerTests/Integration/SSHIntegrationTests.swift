import XCTest
@testable import HHCServerManager

final class SSHIntegrationTests: XCTestCase {
    func testRealPrivateKeySmokeTestWhenEnvironmentIsConfigured() async throws {
        let harness = try makeRealSSHHarness()
        defer { try? harness.service.deleteServer(harness.profile) }

        try await trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)
        let result = try await harness.sshClient.runSmokeTest(profile: harness.profile)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hhc-ssh-ok")
    }

    func testRealDeploymentRunnerDeploysTemporaryRepositoryWhenEnvironmentIsConfigured() async throws {
        let harness = try makeRealSSHHarness()
        defer { try? harness.service.deleteServer(harness.profile) }
        try await trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)

        let token = "hhc-deploy-\(UUID().uuidString)"
        let basePath = "/tmp/\(token)"
        let sourcePath = "\(basePath)/source"
        let barePath = "\(basePath)/repo.git"
        let deployPath = "\(basePath)/app"
        defer {
            Task {
                _ = try? await harness.sshClient.execute("rm -rf -- \(Self.shellQuote(basePath))", profile: harness.profile)
            }
        }

        let setup = """
        set -e; \
        base=\(Self.shellQuote(basePath)); \
        src=\(Self.shellQuote(sourcePath)); \
        bare=\(Self.shellQuote(barePath)); \
        deploy=\(Self.shellQuote(deployPath)); \
        rm -rf -- "$base"; \
        mkdir -p "$src"; \
        cd "$src"; \
        git init -q; \
        git checkout -q -b main; \
        git config user.email hhc@example.com; \
        git config user.name HHC; \
        printf 'old\\n' > app.txt; \
        git add app.txt; \
        git commit -q -m initial; \
        old_commit=$(git rev-parse HEAD); \
        printf 'new\\n' > app.txt; \
        git commit -am update -q; \
        target_commit=$(git rev-parse HEAD); \
        git clone --bare -q "$src" "$bare"; \
        git clone -q "$bare" "$deploy"; \
        cd "$deploy"; \
        git checkout -q "$old_commit"; \
        git remote set-url origin "$bare"; \
        printf '%s\\n%s\\n' "$old_commit" "$target_commit"
        """
        let setupResult = try await harness.sshClient.execute(setup, profile: harness.profile)
        XCTAssertEqual(setupResult.exitCode, 0, setupResult.stderr)
        let commits = setupResult.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        let oldCommit = try XCTUnwrap(commits.first)
        let targetCommit = try XCTUnwrap(commits.dropFirst().first)

        let project = DeploymentProject(
            id: UUID(),
            serverId: harness.profile.id,
            name: "Integration Deployment",
            repositoryURL: "https://gitlab.com/hhc/integration.git",
            branch: "main",
            deployPath: deployPath,
            buildCommand: "test -f app.txt && printf built > build.marker",
            restartCommand: nil,
            healthCheckCommand: "test \"$(cat app.txt)\" = new && test \"$(cat build.marker)\" = built",
            webhookEnabled: false,
            webhookSecretRef: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try harness.repository.upsertDeploymentProject(project)

        let runner = DeploymentRunner(
            repository: harness.repository,
            pathPolicy: DeploymentPathPolicy(allowedRoots: [basePath])
        )
        let run = try await runner.run(project: project, profile: harness.profile, sshClient: harness.sshClient)

        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.previousCommit, oldCommit)
        XCTAssertEqual(run.targetCommit, targetCommit)
        XCTAssertEqual(run.summary, "Deployment completed.")

        let verify = try await harness.sshClient.execute(
            "cd \(Self.shellQuote(deployPath)) && git rev-parse HEAD && cat app.txt && cat build.marker",
            profile: harness.profile
        )
        XCTAssertEqual(verify.exitCode, 0, verify.stderr)
        XCTAssertTrue(verify.stdout.contains(targetCommit))
        XCTAssertTrue(verify.stdout.contains("new"))
        XCTAssertTrue(verify.stdout.contains("built"))

        let logs = try harness.repository.fetchDeploymentLogs(runId: run.id)
        XCTAssertTrue(logs.contains { $0.stepName == "build" && $0.stream == .system })
        XCTAssertTrue(logs.contains { $0.stepName == "health_check" && $0.message.contains("Exit 0") })
        XCTAssertTrue(logs.contains { $0.stepName == "finish" && $0.message == "Deployment completed." })

        _ = try? await harness.sshClient.execute("rm -rf -- \(Self.shellQuote(basePath))", profile: harness.profile)
    }

    func testRealVerdaccioLifecycleWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["HHC_TEST_VERDACCIO_REAL"] == "1" else {
            throw XCTSkip("Set HHC_TEST_VERDACCIO_REAL=1 with the real SSH environment to run the Verdaccio lifecycle integration test.")
        }

        let harness = try makeRealSSHHarness()
        defer { try? harness.service.deleteServer(harness.profile) }
        try await trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)

        let token = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(12)
        let serviceName = "hhc-verdaccio-\(token)"
        let installPath = "/srv/\(serviceName)"
        let draft = VerdaccioInstallDraft(
            name: "Integration Verdaccio",
            installPath: installPath,
            dataPath: "\(installPath)/storage",
            listenHost: "127.0.0.1",
            listenPort: Int.random(in: 48_000...58_000),
            serviceName: serviceName,
            version: VerdaccioInstallDraft.defaultVersion
        )
        let cleanup = Self.verdaccioCleanupCommand(for: draft)
        defer {
            Task {
                _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
            }
        }
        _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)

        let dependencyCheck = try await harness.sshClient.execute(
            "command -v node >/dev/null && command -v npm >/dev/null && command -v systemctl >/dev/null && command -v htpasswd >/dev/null",
            profile: harness.profile
        )
        guard dependencyCheck.exitCode == 0 else {
            throw XCTSkip("Real Verdaccio lifecycle test requires node, npm, systemctl, and htpasswd on the test server.")
        }

        let installer = VerdaccioInstaller()
        let manager = VerdaccioManager()

        let installResult = try await installer.install(draft: draft, profile: harness.profile, sshClient: harness.sshClient)
        XCTAssertEqual(installResult.configPath, "\(installPath)/config.yaml")
        XCTAssertEqual(installResult.servicePath, "/etc/systemd/system/\(serviceName).service")
        XCTAssertFalse(installResult.healthCheckOutput.isEmpty)

        let createdUser = try await manager.createUser(
            draft: draft,
            username: "hhcsmoke",
            password: "HhcSmokePassword123!",
            profile: harness.profile,
            sshClient: harness.sshClient
        )
        XCTAssertEqual(createdUser.htpasswdPath, "\(installPath)/htpasswd")

        let smoke = try await manager.runNpmSmokeTest(
            draft: draft,
            username: "hhcsmoke",
            password: "HhcSmokePassword123!",
            email: "hhc-smoke@example.com",
            profile: harness.profile,
            sshClient: harness.sshClient
        )
        XCTAssertEqual(smoke.requireOutput, "hhc-verdaccio-smoke-ok")

        let restart = try await manager.performServiceAction(.restart, draft: draft, profile: harness.profile, sshClient: harness.sshClient)
        XCTAssertTrue(restart.snapshot.isRunning)
        XCTAssertFalse(restart.healthCheckOutput?.isEmpty ?? true)

        let config = try await manager.readConfig(draft: draft, profile: harness.profile, sshClient: harness.sshClient)
        let saved = try await manager.saveConfig(
            draft: draft,
            content: config.content,
            profile: harness.profile,
            sshClient: harness.sshClient
        )
        XCTAssertEqual(saved.path, "\(installPath)/config.yaml")
        XCTAssertTrue(saved.backupPath.contains(".hhc-backup-"))

        let backup = try await manager.createBackup(
            draft: draft,
            profile: harness.profile,
            sshClient: harness.sshClient,
            repository: harness.repository
        )
        XCTAssertTrue((backup.sizeBytes ?? 0) > 0)

        let restore = try await manager.restoreBackup(
            draft: draft,
            backupPath: backup.backupPath,
            profile: harness.profile,
            sshClient: harness.sshClient,
            repository: harness.repository
        )
        XCTAssertEqual(restore.backupPath, backup.backupPath)
        XCTAssertFalse(restore.healthCheckOutput.isEmpty)

        let registries = try harness.repository.fetchRegistryInstances(serverId: harness.profile.id)
        XCTAssertEqual(registries.count, 1)
        let records = try harness.repository.fetchRegistryBackups(registryId: registries[0].id)
        XCTAssertTrue(records.contains { $0.status == .created })
        XCTAssertTrue(records.contains { $0.status == .restored })

        _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
    }

    private func makeRealSSHHarness() throws -> RealSSHHarness {
        let environment = ProcessInfo.processInfo.environment
        guard
            let host = environment["HHC_TEST_SSH_HOST"], !host.isEmpty,
            let user = environment["HHC_TEST_SSH_USER"], !user.isEmpty,
            let privateKeyPath = environment["HHC_TEST_SSH_PRIVATE_KEY"], !privateKeyPath.isEmpty
        else {
            throw XCTSkip("Set HHC_TEST_SSH_HOST, HHC_TEST_SSH_USER, and HHC_TEST_SSH_PRIVATE_KEY to run real SSH integration tests.")
        }

        let port = Int(environment["HHC_TEST_SSH_PORT"] ?? "22") ?? 22
        let keyData = try Data(contentsOf: URL(fileURLWithPath: privateKeyPath))
        let database = try AppDatabase.inMemory()
        let repository = ServerRepository(database: database)
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.integration.\(UUID().uuidString)")
        let service = ServerManagementService(repository: repository, keychain: keychain)
        let profile = try service.createServer(
            name: "Integration",
            host: host,
            port: port,
            username: user,
            groupName: nil,
            authType: .privateKey,
            credential: .privateKey(data: keyData, passphrase: environment["HHC_TEST_SSH_PASSPHRASE"])
        )
        let sshClient = OpenSSHClient(repository: repository, keychain: keychain)
        return RealSSHHarness(
            repository: repository,
            keychain: keychain,
            service: service,
            profile: profile,
            sshClient: sshClient
        )
    }

    private func trustHostKeyIfNeeded(_ sshClient: OpenSSHClient, profile: ServerProfile) async throws {
        do {
            _ = try await sshClient.runSmokeTest(profile: profile)
        } catch SSHClientError.unknownHostKey(let hostKey) {
            try sshClient.trustHostKey(hostKey, for: profile)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func verdaccioCleanupCommand(for draft: VerdaccioInstallDraft) -> String {
        let serviceName = draft.serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = "\(serviceName).service"
        return """
        service=\(shellQuote(service)); \
        service_name=\(shellQuote(serviceName)); \
        install_path=\(shellQuote(draft.installPath.trimmingCharacters(in: .whitespacesAndNewlines))); \
        systemctl disable --now "$service" >/dev/null 2>&1 || true; \
        rm -f -- "/etc/systemd/system/$service"; \
        systemctl daemon-reload >/dev/null 2>&1 || true; \
        userdel "$service_name" >/dev/null 2>&1 || true; \
        rm -rf -- "$install_path"
        """
    }
}

private struct RealSSHHarness {
    let repository: ServerRepository
    let keychain: KeychainService
    let service: ServerManagementService
    let profile: ServerProfile
    let sshClient: OpenSSHClient
}
