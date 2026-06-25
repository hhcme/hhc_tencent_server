import XCTest
@testable import HHCServerManager

final class SSHIntegrationTests: XCTestCase {
    func testRealPrivateKeySmokeTestWhenEnvironmentIsConfigured() async throws {
        let harness = try makeRealSSHHarness()
        defer { try? harness.service.deleteServer(harness.profile) }

        try await Self.trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)
        let result = try await harness.sshClient.runSmokeTest(profile: harness.profile)
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(result.stdout, "hhc-ssh-ok", result.stderr)
    }

    func testRealSFTPTransferRoundTripWhenEnvironmentIsConfigured() async throws {
        let harness = try makeRealSSHHarness(disableRsync: true, disableSCPFallback: true)
        defer { try? harness.service.deleteServer(harness.profile) }
        try await Self.trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)

        let token = "hhc-transfer-\(UUID().uuidString)"
        let remoteBasePath = "/tmp/\(token)"
        let remoteUploadPath = "\(remoteBasePath)/uploaded.txt"

        let mkdir = try await harness.sshClient.execute("mkdir -p -- \(Self.shellQuote(remoteBasePath))", profile: harness.profile)
        XCTAssertEqual(mkdir.exitCode, 0, mkdir.stderr)
        guard mkdir.exitCode == 0 else {
            return
        }

        let localDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(token, isDirectory: true)
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: localDirectory) }

        let uploadURL = localDirectory.appendingPathComponent("upload.txt")
        let downloadURL = localDirectory.appendingPathComponent("download.txt")
        let content = "hhc-sftp-ok-\(UUID().uuidString)\n"
        try content.write(to: uploadURL, atomically: true, encoding: .utf8)

        let uploadProgress = ProgressRecorder()
        let upload = try await harness.sshClient.uploadFile(
            localURL: uploadURL,
            remotePath: remoteUploadPath,
            profile: harness.profile
        ) { progress in
            uploadProgress.append(progress)
        }
        XCTAssertEqual(upload.remotePath, remoteUploadPath)
        XCTAssertEqual(upload.byteCount, Int64(Data(content.utf8).count))
        XCTAssertEqual(uploadProgress.last?.fraction, 1)

        let verify = try await harness.sshClient.execute("cat -- \(Self.shellQuote(remoteUploadPath))", profile: harness.profile)
        XCTAssertEqual(verify.exitCode, 0, verify.stderr)
        XCTAssertEqual(verify.stdout, content)

        let downloadProgress = ProgressRecorder()
        let download = try await harness.sshClient.downloadFile(
            remotePath: remoteUploadPath,
            localURL: downloadURL,
            profile: harness.profile
        ) { progress in
            downloadProgress.append(progress)
        }
        XCTAssertEqual(download.localPath, downloadURL.path)
        XCTAssertEqual(download.byteCount, Int64(Data(content.utf8).count))
        XCTAssertEqual(downloadProgress.last?.fraction, 1)
        XCTAssertEqual(try String(contentsOf: downloadURL, encoding: .utf8), content)

        _ = try? await harness.sshClient.execute("rm -rf -- \(Self.shellQuote(remoteBasePath))", profile: harness.profile)
    }

    func testRealSFTPResumePartialTransfersWhenEnvironmentIsConfigured() async throws {
        let harness = try makeRealSSHHarness(disableRsync: true, disableSCPFallback: true)
        defer { try? harness.service.deleteServer(harness.profile) }
        try await Self.trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)

        let token = "hhc-sftp-resume-\(UUID().uuidString)"
        let remoteBasePath = "/tmp/\(token)"
        let uploadRemotePath = "\(remoteBasePath)/resume-upload.txt"
        let downloadRemotePath = "\(remoteBasePath)/resume-download.txt"
        let cleanup = "rm -rf -- \(Self.shellQuote(remoteBasePath))"

        do {
            let mkdir = try await harness.sshClient.execute("mkdir -p -- \(Self.shellQuote(remoteBasePath))", profile: harness.profile)
            XCTAssertEqual(mkdir.exitCode, 0, mkdir.stderr)
            guard mkdir.exitCode == 0 else {
                return
            }

            let localDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(token, isDirectory: true)
            try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: localDirectory) }

            let uploadPrefix = "hhc-upload-prefix-\(UUID().uuidString)"
            let uploadContent = "\(uploadPrefix)-suffix-\(UUID().uuidString)\n"
            let uploadURL = localDirectory.appendingPathComponent("resume-upload.txt")
            try uploadContent.write(to: uploadURL, atomically: true, encoding: .utf8)

            let seedUpload = try await harness.sshClient.execute(
                "printf %s \(Self.shellQuote(uploadPrefix)) > \(Self.shellQuote(uploadRemotePath))",
                profile: harness.profile
            )
            XCTAssertEqual(seedUpload.exitCode, 0, seedUpload.stderr)

            let uploadProgress = ProgressRecorder()
            let upload = try await harness.sshClient.uploadFile(
                localURL: uploadURL,
                remotePath: uploadRemotePath,
                profile: harness.profile
            ) { progress in
                uploadProgress.append(progress)
            }
            XCTAssertEqual(upload.remotePath, uploadRemotePath)
            XCTAssertEqual(upload.byteCount, Int64(Data(uploadContent.utf8).count))
            XCTAssertEqual(uploadProgress.last?.fraction, 1)

            let verifyUpload = try await harness.sshClient.execute("cat -- \(Self.shellQuote(uploadRemotePath))", profile: harness.profile)
            XCTAssertEqual(verifyUpload.exitCode, 0, verifyUpload.stderr)
            XCTAssertEqual(verifyUpload.stdout, uploadContent)

            let downloadPrefix = "hhc-download-prefix-\(UUID().uuidString)"
            let downloadContent = "\(downloadPrefix)-suffix-\(UUID().uuidString)\n"
            let downloadURL = localDirectory.appendingPathComponent("resume-download.txt")
            try downloadPrefix.write(to: downloadURL, atomically: true, encoding: .utf8)

            let seedDownload = try await harness.sshClient.execute(
                "printf %s \(Self.shellQuote(downloadContent)) > \(Self.shellQuote(downloadRemotePath))",
                profile: harness.profile
            )
            XCTAssertEqual(seedDownload.exitCode, 0, seedDownload.stderr)

            let downloadProgress = ProgressRecorder()
            let download = try await harness.sshClient.downloadFile(
                remotePath: downloadRemotePath,
                localURL: downloadURL,
                profile: harness.profile
            ) { progress in
                downloadProgress.append(progress)
            }
            XCTAssertEqual(download.localPath, downloadURL.path)
            XCTAssertEqual(download.byteCount, Int64(Data(downloadContent.utf8).count))
            XCTAssertEqual(downloadProgress.last?.fraction, 1)
            XCTAssertEqual(try String(contentsOf: downloadURL, encoding: .utf8), downloadContent)

            _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
        } catch {
            _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
            throw error
        }
    }

    func testRealDeploymentRunnerDeploysTemporaryRepositoryWhenEnvironmentIsConfigured() async throws {
        guard Self.testEnvironment()["HHC_TEST_DEPLOYMENT_REAL"] == "1" else {
            throw XCTSkip("Set HHC_TEST_DEPLOYMENT_REAL=1 with the real SSH environment to run the deployment integration test.")
        }

        let harness = try makeRealSSHHarness()
        defer { try? harness.service.deleteServer(harness.profile) }
        try await Self.trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)

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

    @MainActor
    func testRealSystemdAndCronWritesAuditAndCleanupWhenExplicitlyEnabled() async throws {
        guard Self.testEnvironment()["HHC_TEST_SECURITY_REAL"] == "1" else {
            throw XCTSkip("Set HHC_TEST_SECURITY_REAL=1 with the real SSH environment to run the guarded systemd/Cron write integration test.")
        }

        let harness = try makeRealSSHHarness()
        defer { try? harness.service.deleteServer(harness.profile) }
        try await Self.trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)

        let dependencyCheck = try await harness.sshClient.execute(
            "command -v systemctl >/dev/null && test -w /etc/systemd/system && command -v crontab >/dev/null",
            profile: harness.profile
        )
        guard dependencyCheck.exitCode == 0 else {
            throw XCTSkip("Real systemd/Cron write test requires systemctl, crontab, and write access to /etc/systemd/system.")
        }

        let token = "hhc-phase4-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))"
        let unitName = "\(token).service"
        let unitPath = "/etc/systemd/system/\(unitName)"
        let systemdMarker = "/tmp/\(token).systemd"
        let cronMarker = "/tmp/\(token).cron"
        let originalCrontab = try await harness.sshClient.execute("crontab -l 2>/dev/null || true", profile: harness.profile).stdout
        let cleanup = Self.phase4SecurityCleanupCommand(
            unitName: unitName,
            unitPath: unitPath,
            systemdMarker: systemdMarker,
            cronMarker: cronMarker,
            originalCrontab: originalCrontab
        )

        do {
            _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
            let installUnit = """
            cat > \(Self.shellQuote(unitPath)) <<'__HHC_SYSTEMD_UNIT__'
            [Unit]
            Description=HHC Server Manager integration smoke

            [Service]
            Type=oneshot
            ExecStart=/bin/sh -c 'printf hhc-systemd-ok > \(systemdMarker)'
            __HHC_SYSTEMD_UNIT__
            systemctl daemon-reload
            """
            let installResult = try await harness.sshClient.execute(installUnit, profile: harness.profile)
            XCTAssertEqual(installResult.exitCode, 0, installResult.stderr)

            let viewModel = ServerWorkspaceViewModel()
            let systemdManager = SystemdServiceManager()
            let cronManager = CronManager()

            viewModel.performSystemdAction(
                .restart,
                unitName: unitName,
                profile: harness.profile,
                sshClient: harness.sshClient,
                systemdServiceManager: systemdManager,
                repository: harness.repository
            )
            try await Self.waitUntil { viewModel.isPerformingSystemdAction == false }
            XCTAssertNil(viewModel.systemdErrorMessage)
            XCTAssertEqual(viewModel.systemdActionMessage, "Restart requested for \(unitName).")

            let marker = try await harness.sshClient.execute("cat -- \(Self.shellQuote(systemdMarker))", profile: harness.profile)
            XCTAssertEqual(marker.exitCode, 0, marker.stderr)
            XCTAssertEqual(marker.stdout, "hhc-systemd-ok")

            viewModel.loadCron(profile: harness.profile, sshClient: harness.sshClient, cronManager: cronManager)
            try await Self.waitUntil { viewModel.isLoadingCron == false }
            XCTAssertNil(viewModel.cronErrorMessage)

            let cronCommand = "printf hhc-cron-ok > \(cronMarker)"
            viewModel.addCronEntry(
                schedule: "0 0 31 2 *",
                command: cronCommand,
                profile: harness.profile,
                sshClient: harness.sshClient,
                cronManager: cronManager,
                repository: harness.repository
            )
            try await Self.waitUntil { viewModel.isMutatingCron == false }
            XCTAssertNil(viewModel.cronErrorMessage)
            let addedEntry = try XCTUnwrap(viewModel.cronSnapshot?.entries.first { $0.command == cronCommand })

            viewModel.performCronEntryAction(
                .disable,
                entry: addedEntry,
                profile: harness.profile,
                sshClient: harness.sshClient,
                cronManager: cronManager,
                repository: harness.repository
            )
            try await Self.waitUntil { viewModel.isMutatingCron == false }
            XCTAssertNil(viewModel.cronErrorMessage)
            let disabledEntry = try XCTUnwrap(viewModel.cronSnapshot?.entries.first { $0.command == cronCommand })
            XCTAssertFalse(disabledEntry.isEnabled)

            viewModel.performCronEntryAction(
                .enable,
                entry: disabledEntry,
                profile: harness.profile,
                sshClient: harness.sshClient,
                cronManager: cronManager,
                repository: harness.repository
            )
            try await Self.waitUntil { viewModel.isMutatingCron == false }
            XCTAssertNil(viewModel.cronErrorMessage)
            let enabledEntry = try XCTUnwrap(viewModel.cronSnapshot?.entries.first { $0.command == cronCommand })
            XCTAssertTrue(enabledEntry.isEnabled)

            viewModel.performCronEntryAction(
                .delete,
                entry: enabledEntry,
                profile: harness.profile,
                sshClient: harness.sshClient,
                cronManager: cronManager,
                repository: harness.repository
            )
            try await Self.waitUntil { viewModel.isMutatingCron == false }
            XCTAssertNil(viewModel.cronErrorMessage)
            XCTAssertFalse(viewModel.cronSnapshot?.rawText.contains(cronCommand) == true)

            let logs = try harness.repository.fetchRemoteChangeLogs(serverId: harness.profile.id)
            XCTAssertTrue(logs.contains { $0.targetType == "systemd" && $0.targetId == unitName && $0.action == "restart" && $0.status == "success" })
            XCTAssertTrue(logs.contains { $0.targetType == "cron" && $0.action == "add" && $0.status == "success" })
            XCTAssertTrue(logs.contains { $0.targetType == "cron" && $0.action == "disable" && $0.status == "success" })
            XCTAssertTrue(logs.contains { $0.targetType == "cron" && $0.action == "enable" && $0.status == "success" })
            XCTAssertTrue(logs.contains { $0.targetType == "cron" && $0.action == "delete" && $0.status == "success" })

            let cleanupResult = try await harness.sshClient.execute(cleanup, profile: harness.profile)
            XCTAssertEqual(cleanupResult.exitCode, 0, cleanupResult.stderr)
        } catch {
            _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
            throw error
        }
    }

    @MainActor
    func testRealEnvironmentFileSaveAuditsAndCleanupWhenExplicitlyEnabled() async throws {
        guard Self.testEnvironment()["HHC_TEST_SECURITY_REAL"] == "1" else {
            throw XCTSkip("Set HHC_TEST_SECURITY_REAL=1 with the real SSH environment to run the guarded environment file write integration test.")
        }

        let harness = try makeRealSSHHarness()
        defer { try? harness.service.deleteServer(harness.profile) }
        try await Self.trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)

        let homeResult = try await harness.sshClient.execute("printf '%s' \"$HOME\"", profile: harness.profile)
        XCTAssertEqual(homeResult.exitCode, 0, homeResult.stderr)
        let homePath = homeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard homePath.hasPrefix("/") else {
            throw XCTSkip("Real environment file write test requires an absolute remote HOME path.")
        }

        let token = "hhc-phase4-env-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))"
        let envBasePath = "\(homePath)/\(token)"
        let envPath = "\(envBasePath)/.env"
        let cleanup = "rm -rf -- \(Self.shellQuote(envBasePath))"

        do {
            _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
            let setup = """
            mkdir -p -- \(Self.shellQuote(envBasePath)); \
            printf 'HHC_VALUE=before\\n' > \(Self.shellQuote(envPath))
            """
            let setupResult = try await harness.sshClient.execute(setup, profile: harness.profile)
            XCTAssertEqual(setupResult.exitCode, 0, setupResult.stderr)

            let viewModel = ServerWorkspaceViewModel()
            let manager = EnvironmentFileManager()
            viewModel.loadEnvironmentFiles(
                profile: harness.profile,
                sshClient: harness.sshClient,
                environmentFileManager: manager
            )
            try await Self.waitUntil(timeout: 20) {
                viewModel.isLoadingEnvironmentFiles == false
                    && viewModel.environmentFileList?.files.contains { $0.path == envPath } == true
            }
            let file = try XCTUnwrap(viewModel.environmentFileList?.files.first { $0.path == envPath })

            viewModel.selectEnvironmentFile(
                file,
                profile: harness.profile,
                sshClient: harness.sshClient,
                environmentFileManager: manager
            )
            try await Self.waitUntil {
                viewModel.isLoadingEnvironmentFileContent == false
                    && viewModel.environmentFileContent?.file.path == envPath
            }
            XCTAssertEqual(viewModel.environmentFileDraft, "HHC_VALUE=before\n")

            viewModel.environmentFileDraft = "HHC_VALUE=after\n"
            viewModel.saveEnvironmentFile(
                profile: harness.profile,
                sshClient: harness.sshClient,
                environmentFileManager: manager,
                repository: harness.repository
            )
            try await Self.waitUntil {
                viewModel.isSavingEnvironmentFile == false
                    && viewModel.environmentActionMessage?.contains("Saved environment file") == true
            }
            XCTAssertNil(viewModel.environmentErrorMessage)
            XCTAssertEqual(viewModel.environmentFileContent?.content, "HHC_VALUE=after\n")

            let remoteContent = try await harness.sshClient.execute("cat -- \(Self.shellQuote(envPath))", profile: harness.profile)
            XCTAssertEqual(remoteContent.exitCode, 0, remoteContent.stderr)
            XCTAssertEqual(remoteContent.stdout, "HHC_VALUE=after\n")

            let backupCheck = try await harness.sshClient.execute(
                "find \(Self.shellQuote(envBasePath)) -maxdepth 1 -name '.env.hhc-backup-*' -type f | wc -l",
                profile: harness.profile
            )
            XCTAssertEqual(backupCheck.exitCode, 0, backupCheck.stderr)
            XCTAssertEqual(backupCheck.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "1")

            let logs = try harness.repository.fetchRemoteChangeLogs(serverId: harness.profile.id)
            XCTAssertTrue(logs.contains {
                $0.targetType == "environment"
                    && $0.targetId == envPath
                    && $0.action == "save"
                    && $0.status == "success"
                    && $0.beforeSnapshot == "HHC_VALUE=before"
                    && $0.afterSnapshot == "HHC_VALUE=after"
            })

            let cleanupResult = try await harness.sshClient.execute(cleanup, profile: harness.profile)
            XCTAssertEqual(cleanupResult.exitCode, 0, cleanupResult.stderr)
        } catch {
            _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
            throw error
        }
    }

    @MainActor
    func testRealNginxTemporaryConfigReloadsAndCleansUpWhenExplicitlyEnabled() async throws {
        guard Self.testEnvironment()["HHC_TEST_NGINX_REAL"] == "1" else {
            throw XCTSkip("Set HHC_TEST_NGINX_REAL=1 with the real SSH environment to run the guarded Nginx write/reload integration test.")
        }

        let harness = try makeRealSSHHarness()
        defer { try? harness.service.deleteServer(harness.profile) }
        try await Self.trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)

        let preflight = try await harness.sshClient.execute(Self.nginxTemporaryConfigPreflightCommand(), profile: harness.profile)
        guard preflight.exitCode == 0 else {
            throw XCTSkip("Real Nginx write/reload test requires a running nginx service and an included writable conf.d directory.")
        }
        let configDirectory = preflight.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configDirectory.hasPrefix("/etc/nginx/") || configDirectory.hasPrefix("/www/server/nginx/") else {
            throw XCTSkip("Refusing to write outside known Nginx configuration roots.")
        }

        let manager = NginxConfigManager()
        let viewModel = ServerWorkspaceViewModel()
        let token = "hhc-phase4-nginx-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))"
        let listenPort = Int.random(in: 43_000...49_000)
        let configPath = "\(configDirectory)/\(token).conf"
        let cleanup = "rm -f -- \(Self.shellQuote(configPath)) \(Self.shellQuote(configPath)).hhc-backup-* \(Self.shellQuote(configPath)).hhc-tmp.*; nginx -t >/dev/null 2>&1 && (systemctl reload nginx 2>/dev/null || nginx -s reload) || true"

        do {
            _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
            let content = """
            server {
                listen 127.0.0.1:\(listenPort);
                server_name \(token).invalid;
                location / {
                    return 204;
                }
            }
            """

            let upsert = try await manager.upsertConfig(
                path: configPath,
                content: content,
                profile: harness.profile,
                sshClient: harness.sshClient
            )
            XCTAssertTrue(upsert.createdNewFile)
            XCTAssertFalse(upsert.rolledBack)
            XCTAssertTrue(upsert.testResult.succeeded)

            let file = upsert.file
            viewModel.selectNginxConfig(file, profile: harness.profile, sshClient: harness.sshClient, nginxConfigManager: manager)
            try await Self.waitUntil {
                viewModel.isLoadingNginxConfigContent == false
                    && viewModel.nginxConfigContent?.file.path == configPath
            }

            let editedContent = content + "\n# hhc edited through ServerWorkspaceViewModel\n"
            viewModel.nginxConfigDraft = editedContent
            viewModel.saveNginxConfig(
                profile: harness.profile,
                sshClient: harness.sshClient,
                nginxConfigManager: manager,
                repository: harness.repository
            )
            try await Self.waitUntil {
                viewModel.isSavingNginxConfig == false
                    && viewModel.nginxActionMessage?.contains("Saved Nginx config") == true
            }
            XCTAssertNil(viewModel.nginxErrorMessage)
            XCTAssertEqual(viewModel.nginxConfigContent?.content, editedContent)

            viewModel.reloadNginx(
                profile: harness.profile,
                sshClient: harness.sshClient,
                nginxConfigManager: manager,
                repository: harness.repository
            )
            try await Self.waitUntil {
                viewModel.isReloadingNginx == false
                    && viewModel.nginxActionMessage == "Reloaded Nginx."
            }
            XCTAssertNil(viewModel.nginxErrorMessage)

            let smoke = try await harness.sshClient.execute(
                "curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:\(listenPort)/",
                profile: harness.profile
            )
            XCTAssertEqual(smoke.exitCode, 0, smoke.stderr)
            XCTAssertEqual(smoke.stdout, "204")

            let logs = try harness.repository.fetchRemoteChangeLogs(serverId: harness.profile.id)
            XCTAssertTrue(logs.contains {
                $0.targetType == "nginx"
                    && $0.targetId == configPath
                    && $0.action == "save"
                    && $0.status == "success"
            })
            XCTAssertTrue(logs.contains {
                $0.targetType == "nginx"
                    && $0.targetId == configPath
                    && $0.action == "reload"
                    && $0.status == "success"
            })

            let cleanupResult = try await harness.sshClient.execute(cleanup, profile: harness.profile)
            XCTAssertEqual(cleanupResult.exitCode, 0, cleanupResult.stderr)

            let removed = try await harness.sshClient.execute("test ! -e \(Self.shellQuote(configPath))", profile: harness.profile)
            XCTAssertEqual(removed.exitCode, 0, removed.stderr)
        } catch {
            _ = try? await harness.sshClient.execute(cleanup, profile: harness.profile)
            throw error
        }
    }

    func testRealVerdaccioLifecycleWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["HHC_TEST_VERDACCIO_REAL"] == "1" else {
            throw XCTSkip("Set HHC_TEST_VERDACCIO_REAL=1 with the real SSH environment to run the Verdaccio lifecycle integration test.")
        }

        let harness = try makeRealSSHHarness()
        defer { try? harness.service.deleteServer(harness.profile) }
        try await Self.trustHostKeyIfNeeded(harness.sshClient, profile: harness.profile)

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

    private func makeRealSSHHarness(disableRsync: Bool = false, disableSCPFallback: Bool = false) throws -> RealSSHHarness {
        let environment = Self.testEnvironment()
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
        let sshClient = OpenSSHClient(
            repository: repository,
            keychain: keychain,
            isRsyncEnabled: !disableRsync,
            isSCPFallbackEnabled: !disableSCPFallback
        )
        return RealSSHHarness(
            repository: repository,
            keychain: keychain,
            service: service,
            profile: profile,
            sshClient: sshClient
        )
    }

    private static func testEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        guard
            let home = environment["HOME"],
            let localEnvironment = try? readLocalTestEnvironment(
                from: URL(fileURLWithPath: home).appendingPathComponent(".hhc_tencent_server_test_env")
            )
        else {
            return environment
        }

        environment.merge(localEnvironment) { processValue, _ in processValue }
        return environment
    }

    private static func readLocalTestEnvironment(from url: URL) throws -> [String: String] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { return }
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                result[key] = value
            }
    }

    private static func trustHostKeyIfNeeded(_ sshClient: OpenSSHClient, profile: ServerProfile) async throws {
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

    private static func phase4SecurityCleanupCommand(
        unitName: String,
        unitPath: String,
        systemdMarker: String,
        cronMarker: String,
        originalCrontab: String
    ) -> String {
        let crontabData = Data(originalCrontab.utf8).base64EncodedString()
        return """
        systemctl reset-failed \(shellQuote(unitName)) >/dev/null 2>&1 || true; \
        rm -f -- \(shellQuote(unitPath)) \(shellQuote(systemdMarker)) \(shellQuote(cronMarker)); \
        systemctl daemon-reload >/dev/null 2>&1 || true; \
        if [ -n \(shellQuote(crontabData)) ]; then \
          printf '%s' \(shellQuote(crontabData)) | base64 -d | crontab -; \
        else \
          crontab -r >/dev/null 2>&1 || true; \
        fi
        """
    }

    private static func nginxTemporaryConfigPreflightCommand() -> String {
        """
        set -e; \
        command -v nginx >/dev/null 2>&1; \
        nginx -t >/dev/null 2>&1; \
        if command -v systemctl >/dev/null 2>&1; then systemctl is-active --quiet nginx; fi; \
        info=$(nginx -V 2>&1 || true); \
        conf=$(printf '%s' "$info" | tr ' ' '\\n' | sed -n 's/^--conf-path=//p' | tail -n 1); \
        [ -n "$conf" ] || conf=/etc/nginx/nginx.conf; \
        base=$(dirname -- "$conf"); \
        for dir in "$base/conf.d" /etc/nginx/conf.d "$base/vhost" "$base/sites-enabled"; do \
          [ -d "$dir" ] || continue; \
          [ -w "$dir" ] || continue; \
          case "$dir" in /etc/nginx/*|/www/server/nginx/*) ;; *) continue ;; esac; \
          if grep -R "include[[:space:]].*$(basename "$dir")/\\\\*\\\\.conf" "$conf" "$base"/*.conf >/dev/null 2>&1; then \
            printf '%s' "$dir"; exit 0; \
          fi; \
        done; \
        exit 4
        """
    }

    @MainActor
    private static func waitUntil(
        timeout: TimeInterval = 15,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for async UI state.")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

private struct RealSSHHarness {
    let repository: ServerRepository
    let keychain: KeychainService
    let service: ServerManagementService
    let profile: ServerProfile
    let sshClient: OpenSSHClient
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RemoteFileTransferProgress] = []

    var last: RemoteFileTransferProgress? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }

    func append(_ progress: RemoteFileTransferProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }
}
