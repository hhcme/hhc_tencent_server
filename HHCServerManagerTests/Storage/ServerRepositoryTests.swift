import XCTest
@testable import HHCServerManager

final class ServerRepositoryTests: XCTestCase {
    func testInsertFetchUpdateDeleteServer() throws {
        let repository = try makeRepository()
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_010)

        let original = ServerProfile(
            id: id,
            name: "Tencent Test",
            host: "example.internal",
            port: 22,
            username: "root",
            authType: .privateKey,
            keychainRef: "server_\(id.uuidString)",
            groupName: "prod",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try repository.upsert(original)
        var servers = try repository.fetchServers()
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].id, id)
        XCTAssertEqual(servers[0].authType, .privateKey)
        XCTAssertEqual(servers[0].groupName, "prod")

        var updated = original
        updated.name = "Renamed"
        updated.port = 2222
        updated.groupName = nil
        updated.updatedAt = Date(timeIntervalSince1970: 1_700_000_020)
        try repository.upsert(updated)

        servers = try repository.fetchServers()
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers[0].name, "Renamed")
        XCTAssertEqual(servers[0].port, 2222)
        XCTAssertNil(servers[0].groupName)

        try repository.deleteServer(id: id)
        XCTAssertTrue(try repository.fetchServers().isEmpty)
    }

    func testDeletingServerCascadesTrustedHostKeys() throws {
        let repository = try makeRepository()
        let server = makeServer()
        try repository.upsert(server)
        try repository.saveTrustedHostKey(TrustedHostKey(
            id: UUID(),
            serverId: server.id,
            host: server.host,
            port: server.port,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:test",
            rawPublicKey: "example.internal ssh-ed25519 AAAATEST",
            trustedAt: Date()
        ))

        XCTAssertEqual(try repository.fetchTrustedHostKeys(serverId: server.id).count, 1)
        try repository.deleteServer(id: server.id)
        XCTAssertTrue(try repository.fetchTrustedHostKeys(serverId: server.id).isEmpty)
    }

    func testCommandHistoryPersistsOrdersAndCascadesWithServer() throws {
        let repository = try makeRepository()
        let server = makeServer()
        try repository.upsert(server)

        let first = CommandHistoryEntry(
            id: UUID(),
            serverId: server.id,
            command: "whoami",
            exitCode: 0,
            duration: 0.123,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let second = CommandHistoryEntry(
            id: UUID(),
            serverId: server.id,
            command: "uptime",
            exitCode: 1,
            duration: 1.5,
            createdAt: Date(timeIntervalSince1970: 1_700_000_010)
        )

        try repository.saveCommandHistory(first)
        try repository.saveCommandHistory(second)

        let history = try repository.fetchCommandHistory(serverId: server.id)
        XCTAssertEqual(history.map(\.command), ["uptime", "whoami"])
        XCTAssertEqual(history[0].exitCode, 1)
        XCTAssertEqual(try XCTUnwrap(history[0].duration), 1.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(history[1].duration), 0.123, accuracy: 0.001)

        try repository.deleteServer(id: server.id)
        XCTAssertTrue(try repository.fetchCommandHistory(serverId: server.id).isEmpty)
    }

    func testOperationLogsPersistInReverseChronologicalOrder() throws {
        let repository = try makeRepository()
        try repository.saveOperationLog(OperationLogEntry(
            id: UUID(),
            scope: "ssh",
            action: "execute_command",
            targetId: "server-a",
            status: "success",
            message: "exit_code=0",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try repository.saveOperationLog(OperationLogEntry(
            id: UUID(),
            scope: "ssh",
            action: "execute_command",
            targetId: "server-b",
            status: "failed",
            message: "timeout",
            createdAt: Date(timeIntervalSince1970: 1_700_000_020)
        ))

        let logs = try repository.fetchOperationLogs()
        XCTAssertEqual(logs.map(\.targetId), ["server-b", "server-a"])
        XCTAssertEqual(logs[0].status, "failed")
        XCTAssertEqual(logs[1].message, "exit_code=0")
    }

    func testRemoteChangeLogsPersistFilterAndCascadeServerToNull() throws {
        let repository = try makeRepository()
        let server = makeServer()
        try repository.upsert(server)
        let older = RemoteChangeLogEntry(
            id: UUID(),
            serverId: server.id,
            providerId: nil,
            targetType: "cron",
            targetId: "0 2 * * * /usr/bin/backup",
            action: "disable",
            beforeSnapshot: "0 2 * * * /usr/bin/backup",
            afterSnapshot: "# HHC_DISABLED 0 2 * * * /usr/bin/backup",
            status: "success",
            message: "disabled",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newer = RemoteChangeLogEntry(
            id: UUID(),
            serverId: nil,
            providerId: .tencentCloud,
            targetType: "security_group",
            targetId: "sg-123",
            action: "add_rule",
            beforeSnapshot: "[]",
            afterSnapshot: "[rule]",
            status: "failed",
            message: "permission denied",
            createdAt: Date(timeIntervalSince1970: 1_700_000_020)
        )

        try repository.saveRemoteChangeLog(older)
        try repository.saveRemoteChangeLog(newer)

        let all = try repository.fetchRemoteChangeLogs()
        XCTAssertEqual(all.map(\.targetType), ["security_group", "cron"])
        XCTAssertEqual(all[0].providerId, .tencentCloud)
        XCTAssertEqual(all[1].beforeSnapshot, "0 2 * * * /usr/bin/backup")

        let serverLogs = try repository.fetchRemoteChangeLogs(serverId: server.id)
        XCTAssertEqual(serverLogs.map(\.action), ["disable"])

        try repository.deleteServer(id: server.id)
        let afterDelete = try XCTUnwrap(repository.fetchRemoteChangeLogs().first { $0.id == older.id })
        XCTAssertNil(afterDelete.serverId)
    }

    func testCloudProviderAccountsPersistUpdateAndDelete() throws {
        let repository = try makeRepository()
        let account = CloudProviderAccount(
            id: UUID(),
            providerId: .tencentCloud,
            displayName: "Tencent",
            keychainRef: "cloud_test",
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try repository.upsertCloudProviderAccount(account)

        var accounts = try repository.fetchCloudProviderAccounts()
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].displayName, "Tencent")
        XCTAssertTrue(accounts[0].enabled)

        var updated = account
        updated.displayName = "Tencent Read Only"
        updated.enabled = false
        updated.updatedAt = Date(timeIntervalSince1970: 1_700_000_050)
        try repository.upsertCloudProviderAccount(updated)

        accounts = try repository.fetchCloudProviderAccounts()
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].displayName, "Tencent Read Only")
        XCTAssertFalse(accounts[0].enabled)

        try repository.deleteCloudProviderAccount(id: account.id)
        XCTAssertTrue(try repository.fetchCloudProviderAccounts().isEmpty)
    }

    func testCloudInstanceLinksUpsertUnlinkAndCascadeWithAccount() throws {
        let repository = try makeRepository()
        let server = makeServer()
        try repository.upsert(server)
        let account = CloudProviderAccount(
            id: UUID(),
            providerId: .tencentCloud,
            displayName: "Tencent",
            keychainRef: "cloud_test",
            enabled: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        try repository.upsertCloudProviderAccount(account)

        let link = CloudInstanceLink(
            id: UUID(),
            serverId: server.id,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-123",
            displayName: "prod-1",
            publicIp: "203.0.113.1",
            privateIp: "10.0.0.2",
            status: "RUNNING",
            instanceType: "S5.SMALL1",
            zoneId: "ap-guangzhou-1",
            vpcId: "vpc-123",
            rawJSON: #"{"InstanceId":"ins-123"}"#,
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try repository.upsertCloudInstanceLink(link)

        var links = try repository.fetchCloudInstanceLinks(accountId: account.id)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].serverId, server.id)
        XCTAssertEqual(links[0].publicIp, "203.0.113.1")

        var updated = link
        updated.id = UUID()
        updated.serverId = nil
        updated.displayName = "prod-renamed"
        updated.status = "STOPPED"
        updated.lastSyncedAt = Date(timeIntervalSince1970: 1_700_000_030)
        try repository.upsertCloudInstanceLink(updated)

        links = try repository.fetchCloudInstanceLinks(accountId: account.id)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].displayName, "prod-renamed")
        XCTAssertNil(links[0].serverId)
        XCTAssertEqual(links[0].status, "STOPPED")

        updated.serverId = server.id
        try repository.upsertCloudInstanceLink(updated)
        try repository.unlinkCloudInstanceFromServer(serverId: server.id)
        XCTAssertNil(try repository.fetchCloudInstanceLinks(accountId: account.id)[0].serverId)

        try repository.deleteCloudProviderAccount(id: account.id)
        XCTAssertTrue(try repository.fetchCloudInstanceLinks().isEmpty)
    }

    func testDeploymentProjectsRunsAndLogsPersistAndCascade() throws {
        let repository = try makeRepository()
        let server = makeServer()
        try repository.upsert(server)

        let project = DeploymentProject(
            id: UUID(),
            serverId: server.id,
            name: "Website",
            repositoryURL: "git@gitlab.com:hhc/site.git",
            branch: "main",
            deployPath: "/srv/site",
            buildCommand: "npm ci && npm run build",
            restartCommand: "systemctl restart site.service",
            healthCheckCommand: "curl -fsS http://127.0.0.1:3000/health",
            webhookEnabled: true,
            webhookSecretRef: "deploy_secret",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try repository.upsertDeploymentProject(project)

        var projects = try repository.fetchDeploymentProjects(serverId: server.id)
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].name, "Website")
        XCTAssertEqual(projects[0].buildCommand, "npm ci && npm run build")
        XCTAssertTrue(projects[0].webhookEnabled)

        var updatedProject = project
        updatedProject.branch = "release"
        updatedProject.webhookEnabled = false
        updatedProject.webhookSecretRef = nil
        updatedProject.updatedAt = Date(timeIntervalSince1970: 1_700_000_010)
        try repository.upsertDeploymentProject(updatedProject)
        projects = try repository.fetchDeploymentProjects()
        XCTAssertEqual(projects.map(\.branch), ["release"])
        XCTAssertFalse(projects[0].webhookEnabled)
        XCTAssertNil(projects[0].webhookSecretRef)

        var run = DeploymentRun(
            id: UUID(),
            projectId: project.id,
            triggerType: .manual,
            requestedRef: "main",
            previousCommit: "abc123",
            targetCommit: nil,
            status: .running,
            startedAt: Date(timeIntervalSince1970: 1_700_000_020),
            finishedAt: nil,
            summary: nil
        )
        try repository.saveDeploymentRun(run)
        run.status = .succeeded
        run.targetCommit = "def456"
        run.finishedAt = Date(timeIntervalSince1970: 1_700_000_030)
        run.summary = "deployed"
        try repository.saveDeploymentRun(run)

        let runs = try repository.fetchDeploymentRuns(projectId: project.id)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].status, .succeeded)
        XCTAssertEqual(runs[0].previousCommit, "abc123")
        XCTAssertEqual(runs[0].targetCommit, "def456")
        XCTAssertEqual(runs[0].summary, "deployed")

        let olderLog = DeploymentLogEntry(
            id: UUID(),
            runId: run.id,
            stepName: "fetch",
            stream: .stdout,
            message: "Fetching origin",
            createdAt: Date(timeIntervalSince1970: 1_700_000_021)
        )
        let newerLog = DeploymentLogEntry(
            id: UUID(),
            runId: run.id,
            stepName: "build",
            stream: .stderr,
            message: "warning",
            createdAt: Date(timeIntervalSince1970: 1_700_000_022)
        )
        try repository.saveDeploymentLog(newerLog)
        try repository.saveDeploymentLog(olderLog)

        let logs = try repository.fetchDeploymentLogs(runId: run.id)
        XCTAssertEqual(logs.map(\.stepName), ["fetch", "build"])
        XCTAssertEqual(logs.map(\.stream), [.stdout, .stderr])

        try repository.deleteDeploymentProject(id: project.id)
        XCTAssertTrue(try repository.fetchDeploymentProjects(serverId: server.id).isEmpty)
        XCTAssertTrue(try repository.fetchDeploymentRuns(projectId: project.id).isEmpty)
        XCTAssertTrue(try repository.fetchDeploymentLogs(runId: run.id).isEmpty)
    }

    private func makeRepository() throws -> ServerRepository {
        ServerRepository(database: try AppDatabase.inMemory())
    }

    private func makeServer() -> ServerProfile {
        let id = UUID()
        return ServerProfile(
            id: id,
            name: "Test",
            host: "example.internal",
            port: 22,
            username: "root",
            authType: .privateKey,
            keychainRef: "server_\(id.uuidString)",
            groupName: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
