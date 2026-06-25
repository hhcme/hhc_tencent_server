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
}

private struct RealSSHHarness {
    let repository: ServerRepository
    let keychain: KeychainService
    let service: ServerManagementService
    let profile: ServerProfile
    let sshClient: OpenSSHClient
}
