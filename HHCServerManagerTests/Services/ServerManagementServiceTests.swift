import XCTest
@testable import HHCServerManager

final class ServerManagementServiceTests: XCTestCase {
    func testCreateServerStoresProfileAndPasswordCredential() throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "Tencent",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: "prod",
            authType: .password,
            credential: .password("secret")
        )

        let servers = try harness.repository.fetchServers()
        XCTAssertEqual(servers.map(\.id), [profile.id])
        XCTAssertEqual(try harness.keychain.readPassword(keychainRef: profile.keychainRef), "secret")
    }

    func testDeleteServerRemovesProfileTrustedKeysAndCredentials() throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "Tencent",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .privateKey,
            credential: .privateKey(data: Data("key".utf8), passphrase: nil)
        )
        try harness.repository.saveTrustedHostKey(TrustedHostKey(
            id: UUID(),
            serverId: profile.id,
            host: profile.host,
            port: profile.port,
            algorithm: "ssh-ed25519",
            fingerprintSHA256: "SHA256:test",
            rawPublicKey: "example.internal ssh-ed25519 AAAATEST",
            trustedAt: Date()
        ))

        try harness.service.deleteServer(profile)

        XCTAssertTrue(try harness.repository.fetchServers().isEmpty)
        XCTAssertTrue(try harness.repository.fetchTrustedHostKeys(serverId: profile.id).isEmpty)
        XCTAssertNil(try harness.keychain.readPrivateKey(keychainRef: profile.keychainRef))
    }

    func testUpdateServerCanKeepExistingCredential() throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "Tencent",
            host: "old.example",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("original")
        )

        let updated = try harness.service.updateServer(
            profile,
            name: "Renamed",
            host: "new.example",
            port: 2222,
            username: "ubuntu",
            groupName: "prod",
            authType: .password,
            credentialUpdate: .keepExisting
        )

        XCTAssertEqual(updated.id, profile.id)
        XCTAssertEqual(updated.keychainRef, profile.keychainRef)
        XCTAssertEqual(updated.name, "Renamed")
        XCTAssertEqual(updated.port, 2222)
        XCTAssertEqual(try harness.keychain.readPassword(keychainRef: profile.keychainRef), "original")
    }

    func testUpdateServerCanReplaceCredentialWithoutChangingKeychainRef() throws {
        let harness = try Harness()
        let profile = try harness.service.createServer(
            name: "Tencent",
            host: "example.internal",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("old")
        )

        let updated = try harness.service.updateServer(
            profile,
            name: profile.name,
            host: profile.host,
            port: profile.port,
            username: profile.username,
            groupName: nil,
            authType: .password,
            credentialUpdate: .replace(.password("new"))
        )

        XCTAssertEqual(updated.keychainRef, profile.keychainRef)
        XCTAssertEqual(try harness.keychain.readPassword(keychainRef: profile.keychainRef), "new")
    }

    func testCloudAccountServiceCreatesUpdatesAndDeletesAccountWithCredential() throws {
        let harness = try Harness()
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: " Tencent Read Only ",
            credential: CloudProviderCredential(secretId: "sid-1", secretKey: "skey-1")
        )

        XCTAssertEqual(account.displayName, "Tencent Read Only")
        XCTAssertEqual(try harness.repository.fetchCloudProviderAccounts().map(\.id), [account.id])
        XCTAssertEqual(
            try harness.keychain.readCloudCredential(keychainRef: account.keychainRef),
            CloudProviderCredential(secretId: "sid-1", secretKey: "skey-1")
        )

        let updated = try harness.cloudAccountService.updateAccount(
            account,
            displayName: "Tencent Disabled",
            enabled: false,
            credential: CloudProviderCredential(secretId: "sid-2", secretKey: "skey-2")
        )

        XCTAssertEqual(updated.keychainRef, account.keychainRef)
        XCTAssertFalse(updated.enabled)
        XCTAssertEqual(try harness.repository.fetchCloudProviderAccounts()[0].displayName, "Tencent Disabled")
        XCTAssertEqual(
            try harness.keychain.readCloudCredential(keychainRef: account.keychainRef),
            CloudProviderCredential(secretId: "sid-2", secretKey: "skey-2")
        )

        try harness.cloudAccountService.deleteAccount(updated)

        XCTAssertTrue(try harness.repository.fetchCloudProviderAccounts().isEmpty)
        XCTAssertNil(try harness.keychain.readCloudCredential(keychainRef: account.keychainRef))
    }

    func testCloudProviderRegistryResolvesCapabilitiesAndAdapter() throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .tencentCloud,
            capabilities: [.regions, .instanceDiscovery]
        )
        let registry = CloudProviderRegistry(adapters: [adapter])

        XCTAssertEqual(registry.registeredProviderIds, [.tencentCloud])
        XCTAssertTrue(registry.supports(.regions, providerId: .tencentCloud))
        XCTAssertTrue(registry.supports(.instanceDiscovery, providerId: .tencentCloud))
        XCTAssertFalse(registry.supports(.powerActions, providerId: .tencentCloud))
        XCTAssertNoThrow(try registry.require(.regions, providerId: .tencentCloud))
        XCTAssertThrowsError(try registry.require(.powerActions, providerId: .tencentCloud)) { error in
            XCTAssertEqual(
                error as? CloudProviderError,
                .unsupportedCapability(providerId: .tencentCloud, capability: .powerActions)
            )
        }

        let resolved = try registry.adapter(for: .tencentCloud)
        XCTAssertEqual(resolved.providerId, .tencentCloud)
    }

    func testCloudProviderRegistryThrowsForMissingAdapter() {
        let registry = CloudProviderRegistry()

        XCTAssertThrowsError(try registry.adapter(for: .tencentCloud)) { error in
            XCTAssertEqual(error as? CloudProviderError, .adapterNotRegistered(.tencentCloud))
        }
    }

    func testCloudProviderRequestRunnerReturnsBeforeTimeout() async throws {
        let value = try await CloudProviderRequestRunner.withTimeout(0.2) {
            try await Task.sleep(nanoseconds: 1_000_000)
            return "ok"
        }

        XCTAssertEqual(value, "ok")
    }

    func testCloudProviderRequestRunnerTimesOut() async {
        do {
            _ = try await CloudProviderRequestRunner.withTimeout(0.001) {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return "late"
            }
            XCTFail("Expected timeout.")
        } catch {
            XCTAssertEqual(error as? CloudProviderError, .timeout(0.001))
        }
    }

    func testDashboardServiceParsesLinuxCapabilityAndMetricOutputs() {
        let os = DashboardService.parseOSRelease("""
        NAME="Ubuntu"
        VERSION_ID="24.04"
        PRETTY_NAME="Ubuntu 24.04.2 LTS"
        """)
        XCTAssertEqual(os.name, "Ubuntu 24.04.2 LTS")
        XCTAssertEqual(os.version, "24.04")
        XCTAssertTrue(DashboardService.parseYesNo("yes\n"))
        XCTAssertEqual(DashboardService.parseLoadAverage("0.10 0.20 0.30 1/100 12345"), "0.10 / 0.20 / 0.30")
        XCTAssertEqual(DashboardService.parseCPUCount("4\n"), "4")
        XCTAssertEqual(DashboardService.parseProcessSummary("total=120 running=2 sleeping=117 stopped=0 zombie=1\n"), "120 / 2 / 1")
        XCTAssertEqual(DashboardService.parseNetworkTotals("""
            Inter-|   Receive                                                |  Transmit
             face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
                lo: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0
              eth0: 1048576 0 0 0 0 0 0 0 2097152 0 0 0 0 0 0 0
        """), "1.0 MiB / 2.0 MiB")

        let memory = DashboardService.parseMemoryUsage("""
        MemTotal:        2048000 kB
        MemAvailable:    1024000 kB
        """)
        XCTAssertEqual(memory, "1000 MiB / 2.0 GiB")

        let disk = DashboardService.parseRootDiskUsage("/dev/vda1 20971520 10485760 10485760 50% /")
        XCTAssertEqual(disk, "10.0 GiB / 20.0 GiB")
    }

    func testDashboardServiceAppendsCloudMetricsWhenLinked() async throws {
        let harness = try Harness(adapters: [
            MockCloudProviderAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudMetrics]
            )
        ])
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let profile = try harness.service.createServer(
            name: "prod",
            host: "203.0.113.1",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        try harness.repository.upsertCloudInstanceLink(CloudInstanceLink(
            id: UUID(),
            serverId: profile.id,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-123",
            displayName: "prod",
            publicIp: "203.0.113.1",
            privateIp: "10.0.0.2",
            status: "RUNNING",
            instanceType: "mock",
            zoneId: "ap-guangzhou-1",
            vpcId: "vpc-123",
            rawJSON: nil,
            lastSyncedAt: Date()
        ))
        let registry = CloudProviderRegistry(adapters: [
            MockCloudProviderAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudMetrics]
            )
        ])
        let cloudMetricService = CloudMetricService(
            repository: harness.repository,
            keychain: harness.keychain,
            registry: registry,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let dashboardService = DashboardService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let snapshot = try await dashboardService.loadSnapshot(
            profile: profile,
            sshClient: DashboardServiceMockSSHClient(),
            cloudMetricService: cloudMetricService
        )

        XCTAssertTrue(snapshot.metrics.contains(DashboardMetric(name: "Cloud CPU", value: "21.2", unit: "%", source: "Cloud API")))
        XCTAssertTrue(snapshot.metrics.contains { $0.source == "SSH" })
    }

    func testRemoteFileServiceParsesFindListingAndPaths() {
        let entries = RemoteFileService.parseFindListing("""
        z.log\tf\t2048\t1700000010.5\t-rw-r--r--
        bin\td\t4096\t1700000000.0\tdrwxr-xr-x
        current\tl\t12\t1700000020.0\tlrwxrwxrwx
        """, basePath: "/var/www")

        XCTAssertEqual(entries.map(\.name), ["bin", "current", "z.log"])
        XCTAssertEqual(entries[0].kind, .directory)
        XCTAssertEqual(entries[0].path, "/var/www/bin")
        XCTAssertEqual(entries[1].kind, .symlink)
        XCTAssertEqual(entries[1].size, 12)
        XCTAssertEqual(entries[2].modifiedAt, Date(timeIntervalSince1970: 1_700_000_010.5))
        XCTAssertEqual(RemoteFileService.normalizedDirectoryPath(" /tmp/ "), "/tmp")
        XCTAssertEqual(RemoteFileService.parentPath(for: "/var/www"), "/var")
        XCTAssertEqual(RemoteFileService.parentPath(for: "/"), "/")
        XCTAssertEqual(RemoteFileService.parentPath(for: "~/app.env"), "~")
        XCTAssertEqual(RemoteFileService.parentPath(for: "~/sites/app.env"), "~/sites")
        XCTAssertEqual(RemoteFileService.normalizedFilePath("copy.env"), "~/copy.env")
        XCTAssertEqual(RemoteFileService.normalizedFilePath("/var/www/copy.env"), "/var/www/copy.env")
    }

    func testRemoteFileServiceRenamesAndMovesToTrashWithSafeCommands() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let entry = RemoteFileEntry(
            name: "index.html",
            path: "/var/www/index.html",
            kind: .file,
            size: 10,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        try await service.rename(entry: entry, to: "home.html", profile: profile, sshClient: client)
        let trashPath = try await service.moveToTrash(entry: entry, profile: profile, sshClient: client)

        XCTAssertEqual(client.commands.count, 2)
        XCTAssertEqual(client.commands[0], "mv -n -- '/var/www/index.html' '/var/www/home.html'")
        XCTAssertTrue(client.commands[1].contains("mkdir -p -- '~/.hhc-server-manager-trash' && mv -n -- '/var/www/index.html' '~/.hhc-server-manager-trash/"))
        XCTAssertTrue(trashPath.hasPrefix("~/.hhc-server-manager-trash/"))
        XCTAssertTrue(trashPath.hasSuffix("-index.html"))
    }

    func testRemoteFileServiceRejectsUnsafeRenameTargets() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService()
        let entry = RemoteFileEntry(
            name: "index.html",
            path: "/var/www/index.html",
            kind: .file,
            size: 10,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        do {
            try await service.rename(entry: entry, to: "../bad", profile: profile, sshClient: client)
            XCTFail("Expected invalid rename target.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "File name cannot be empty, '.', '..', or contain '/'.")
            XCTAssertTrue(client.commands.isEmpty)
        }
    }

    func testRemoteFileServiceReadsAndSavesSmallUTF8TextWithBackup() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient(responses: [
            CommandResult(
                command: "",
                stdout: Data("hello\n".utf8).base64EncodedString(),
                stderr: "",
                exitCode: 0,
                duration: 0
            ),
            CommandResult(command: "", stdout: "", stderr: "", exitCode: 0, duration: 0),
        ])
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let entry = RemoteFileEntry(
            name: "app.env",
            path: "/var/www/app.env",
            kind: .file,
            size: 6,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        let textFile = try await service.readTextFile(entry: entry, profile: profile, sshClient: client)
        let saveResult = try await service.saveTextFile(
            path: entry.path,
            content: "updated\n",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(textFile.content, "hello\n")
        XCTAssertEqual(textFile.byteCount, 6)
        XCTAssertEqual(saveResult.path, "/var/www/app.env")
        XCTAssertTrue(saveResult.backupPath?.hasPrefix("/var/www/app.env.hhc-backup-") == true)
        XCTAssertEqual(client.commands.count, 2)
        XCTAssertTrue(client.commands[0].contains("base64 < '/var/www/app.env'"))
        XCTAssertTrue(client.commands[1].contains("base64 -d > \"$tmp\""))
        XCTAssertTrue(client.commands[1].contains("cp -p -- '/var/www/app.env' \"$backup\""))
        XCTAssertTrue(client.commands[1].contains("mv -- \"$tmp\" '/var/www/app.env'"))
    }

    func testRemoteFileServiceSavesTextAsNewRemotePathWithoutBackup() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })

        let result = try await service.saveTextFileAs(
            sourcePath: "/var/www/app.env",
            targetPath: "/var/www/app.env.copy",
            content: "copy\n",
            profile: profile,
            sshClient: client
        )

        XCTAssertEqual(result.path, "/var/www/app.env.copy")
        XCTAssertNil(result.backupPath)
        XCTAssertEqual(client.commands.count, 1)
        XCTAssertTrue(client.commands[0].contains("test ! -e \"$target\""))
        XCTAssertTrue(client.commands[0].contains("mv -- \"$tmp\" \"$target\""))
    }

    func testRemoteFileServiceChangesPermissionsWithValidatedOctalMode() async throws {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService()
        let entry = RemoteFileEntry(
            name: "app.env",
            path: "/var/www/app.env",
            kind: .file,
            size: 6,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        try await service.changePermissions(entry: entry, mode: " 640 ", profile: profile, sshClient: client)

        XCTAssertEqual(client.commands, ["chmod -- '640' '/var/www/app.env'"])
    }

    func testRemoteFileServiceRejectsInvalidPermissionModesBeforeSSH() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService()
        let entry = RemoteFileEntry(
            name: "app.env",
            path: "/var/www/app.env",
            kind: .file,
            size: 6,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        do {
            try await service.changePermissions(entry: entry, mode: "88x", profile: profile, sshClient: client)
            XCTFail("Expected invalid mode to be rejected.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Permissions must be a 3 or 4 digit octal mode, for example 644 or 0755.")
            XCTAssertTrue(client.commands.isEmpty)
        }
    }

    func testRemoteFileServiceRejectsOversizedKnownTextFileBeforeSSHRead() async {
        let profile = makeServiceTestProfile()
        let client = RecordingSSHClient()
        let service = RemoteFileService()
        let entry = RemoteFileEntry(
            name: "large.log",
            path: "/var/www/large.log",
            kind: .file,
            size: Int64(RemoteFileService.maxEditableTextBytes + 1),
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        do {
            _ = try await service.readTextFile(entry: entry, profile: profile, sshClient: client)
            XCTFail("Expected large text read to be rejected.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "File is larger than the 256 KiB text editing limit.")
            XCTAssertTrue(client.commands.isEmpty)
        }
    }

    func testRemoteFileServiceUploadsAndDownloadsThroughTransferClient() async throws {
        let profile = makeServiceTestProfile()
        let transferClient = RecordingTransferClient()
        let service = RemoteFileService(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let localUploadURL = URL(fileURLWithPath: "/tmp/app.env")
        let localDownloadURL = URL(fileURLWithPath: "/tmp/downloaded.env")
        let entry = RemoteFileEntry(
            name: "app.env",
            path: "/var/www/app.env",
            kind: .file,
            size: 6,
            modifiedAt: nil,
            permissions: "-rw-r--r--"
        )

        let upload = try await service.uploadFile(
            localURL: localUploadURL,
            toDirectoryPath: "/var/www",
            profile: profile,
            transferClient: transferClient
        )
        let download = try await service.downloadFile(
            entry: entry,
            to: localDownloadURL,
            profile: profile,
            transferClient: transferClient
        )

        XCTAssertEqual(upload.remotePath, "/var/www/app.env")
        XCTAssertEqual(download.localPath, "/tmp/downloaded.env")
        XCTAssertEqual(transferClient.uploads.map(\.remotePath), ["/var/www/app.env"])
        XCTAssertEqual(transferClient.downloads.map(\.remotePath), ["/var/www/app.env"])
    }

    func testCloudInstanceSyncUpsertsInstancesAndPreservesServerLink() async throws {
        let adapter = MockCloudProviderAdapter(
            providerId: .tencentCloud,
            capabilities: [.regions, .instanceDiscovery, .instanceMetadata]
        )
        let harness = try Harness(adapters: [adapter], now: { Date(timeIntervalSince1970: 1_700_000_100) })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let server = try harness.service.createServer(
            name: "Linked",
            host: "203.0.113.1",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        try harness.repository.upsertCloudInstanceLink(CloudInstanceLink(
            id: UUID(),
            serverId: server.id,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-123",
            displayName: "old-name",
            publicIp: "198.51.100.10",
            privateIp: nil,
            status: "STOPPED",
            instanceType: nil,
            zoneId: nil,
            vpcId: nil,
            rawJSON: nil,
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let links = try await harness.cloudInstanceSyncService.syncInstances(
            account: account,
            regionId: "ap-guangzhou"
        )

        XCTAssertEqual(links.count, 1)
        let persisted = try XCTUnwrap(try harness.repository.fetchCloudInstanceLinks(accountId: account.id).first)
        XCTAssertEqual(persisted.serverId, server.id)
        XCTAssertEqual(persisted.displayName, "mock-instance")
        XCTAssertEqual(persisted.publicIp, "203.0.113.1")
        XCTAssertEqual(persisted.status, "RUNNING")
        XCTAssertEqual(persisted.lastSyncedAt, Date(timeIntervalSince1970: 1_700_000_100))
    }

    func testCloudInstanceSyncCreatesServerFromInstanceAndLinksIt() throws {
        let harness = try Harness()
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let link = CloudInstanceLink(
            id: UUID(),
            serverId: nil,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-123",
            displayName: "prod-1",
            publicIp: "203.0.113.1",
            privateIp: "10.0.0.2",
            status: "RUNNING",
            instanceType: "S5.SMALL1",
            zoneId: "ap-guangzhou-3",
            vpcId: "vpc-1",
            rawJSON: nil,
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let profile = try harness.cloudInstanceSyncService.createServerFromInstance(
            link,
            username: "ubuntu",
            authType: .password,
            credential: .password("secret")
        )

        XCTAssertEqual(profile.name, "prod-1")
        XCTAssertEqual(profile.host, "203.0.113.1")
        XCTAssertEqual(profile.username, "ubuntu")
        XCTAssertEqual(profile.groupName, "Tencent Cloud")
        XCTAssertEqual(try harness.keychain.readPassword(keychainRef: profile.keychainRef), "secret")
        let persistedLink = try XCTUnwrap(try harness.repository.fetchCloudInstanceLinks().first)
        XCTAssertEqual(persistedLink.serverId, profile.id)
        XCTAssertEqual(persistedLink.instanceId, "ins-123")

        try harness.cloudInstanceSyncService.unlinkInstanceFromServer(server: profile)
        XCTAssertNil(try harness.repository.fetchCloudInstanceLinks().first?.serverId)
        XCTAssertEqual(try harness.repository.fetchServers().map(\.id), [profile.id])
    }

    func testTencentCloudAdapterFetchRegionsSignsRequestAndParsesResponse() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "TotalCount": 2,
                "RegionSet": [
                  {"Region": "ap-guangzhou", "RegionName": "South China (Guangzhou)", "RegionState": "AVAILABLE"},
                  {"Region": "ap-shanghai", "RegionName": "East China (Shanghai)", "RegionState": "UNAVAILABLE"}
                ],
                "RequestId": "request-1"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )

        let regions = try await adapter.fetchRegions(credential: CloudProviderCredential(
            secretId: "AKIDEXAMPLE",
            secretKey: "SECRETEXAMPLE"
        ))

        XCTAssertEqual(regions, [
            CloudRegion(id: "ap-guangzhou", displayName: "South China (Guangzhou)", available: true),
            CloudRegion(id: "ap-shanghai", displayName: "East China (Shanghai)", available: false),
        ])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "region.intl.tencentcloudapi.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Action"), "DescribeRegions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Version"), "2022-06-27")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Host"), "region.intl.tencentcloudapi.com")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-TC-Region"))
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.contains(
            "Credential=AKIDEXAMPLE/2019-02-25/region/tc3_request"
        ) == true)

        let payload = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(payload["Product"] as? String, "cvm")
        XCTAssertEqual(payload["Scene"] as? Int, 1)
    }

    func testTencentCloudAdapterFetchInstancesPaginatesAndParsesResponse() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "TotalCount": 2,
                "InstanceSet": [
                  {
                    "InstanceId": "ins-1",
                    "InstanceName": "prod-1",
                    "InstanceState": "RUNNING",
                    "InstanceType": "S5.SMALL1",
                    "PublicIpAddresses": ["203.0.113.1"],
                    "PrivateIpAddresses": ["10.0.0.2"],
                    "Placement": {"Zone": "ap-guangzhou-3"},
                    "VirtualPrivateCloud": {"VpcId": "vpc-1"}
                  }
                ],
                "RequestId": "request-1"
              }
            }
            """,
            """
            {
              "Response": {
                "TotalCount": 2,
                "InstanceSet": [
                  {
                    "InstanceId": "ins-2",
                    "InstanceName": "prod-2",
                    "InstanceState": "STOPPED",
                    "InstanceType": "S5.MEDIUM2",
                    "PublicIpAddresses": [],
                    "PrivateIpAddresses": ["10.0.0.3"],
                    "Placement": {"Zone": "ap-guangzhou-4"},
                    "VirtualPrivateCloud": {"VpcId": "vpc-2"}
                  }
                ],
                "RequestId": "request-2"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )

        let instances = try await adapter.fetchInstances(
            credential: CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE"),
            regionId: "ap-guangzhou"
        )

        XCTAssertEqual(instances.map(\.id), ["ins-1", "ins-2"])
        XCTAssertEqual(instances[0].publicIp, "203.0.113.1")
        XCTAssertEqual(instances[0].privateIp, "10.0.0.2")
        XCTAssertEqual(instances[0].zoneId, "ap-guangzhou-3")
        XCTAssertEqual(instances[1].publicIp, nil)
        XCTAssertEqual(instances[1].status, "STOPPED")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "X-TC-Region"), "ap-guangzhou")
        XCTAssertEqual(transport.requests[0].jsonBody?["Offset"] as? Int, 0)
        XCTAssertEqual(transport.requests[1].jsonBody?["Offset"] as? Int, 1)
    }

    func testTencentCloudAdapterFetchMetricSeriesUsesMonitorAPI() async throws {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "MetricName": "CPUUsage",
                "DataPoints": [
                  {
                    "Dimensions": [{"Name": "InstanceId", "Value": "ins-1"}],
                    "Timestamps": [1700000000, 1700000300],
                    "Values": [12.5, 18.75]
                  }
                ],
                "RequestId": "request-monitor"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_551_113_065) },
            timeout: 1
        )

        let series = try await adapter.fetchMetricSeries(
            credential: CloudProviderCredential(secretId: "AKIDEXAMPLE", secretKey: "SECRETEXAMPLE"),
            query: CloudMetricQuery(
                namespace: "QCE/CVM",
                metricName: "CPUUsage",
                instanceId: "ins-1",
                regionId: "ap-guangzhou",
                period: 300,
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                endTime: Date(timeIntervalSince1970: 1_700_000_300)
            )
        )

        XCTAssertEqual(series.metricName, "CPUUsage")
        XCTAssertEqual(series.values, [12.5, 18.75])
        XCTAssertEqual(series.unit, "%")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.host, "monitor.intl.tencentcloudapi.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Action"), "GetMonitorData")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Version"), "2018-07-24")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-TC-Region"), "ap-guangzhou")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.contains(
            "Credential=AKIDEXAMPLE/2019-02-25/monitor/tc3_request"
        ) == true)
        let payload = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(payload["Namespace"] as? String, "QCE/CVM")
        XCTAssertEqual(payload["MetricName"] as? String, "CPUUsage")
        XCTAssertEqual(payload["Period"] as? Int, 300)
    }

    func testCloudMetricServiceLoadsLinkedTencentCloudCPUMetric() async throws {
        let harness = try Harness(adapters: [
            MockCloudProviderAdapter(
                providerId: .tencentCloud,
                capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudMetrics]
            )
        ], now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let account = try harness.cloudAccountService.createAccount(
            providerId: .tencentCloud,
            displayName: "Tencent",
            credential: CloudProviderCredential(secretId: "sid", secretKey: "skey")
        )
        let profile = try harness.service.createServer(
            name: "prod",
            host: "203.0.113.1",
            port: 22,
            username: "root",
            groupName: nil,
            authType: .password,
            credential: .password("secret")
        )
        var link = CloudInstanceLink(
            id: UUID(),
            serverId: profile.id,
            accountId: account.id,
            providerId: .tencentCloud,
            regionId: "ap-guangzhou",
            instanceId: "ins-123",
            displayName: "prod",
            publicIp: "203.0.113.1",
            privateIp: "10.0.0.2",
            status: "RUNNING",
            instanceType: "mock",
            zoneId: "ap-guangzhou-1",
            vpcId: "vpc-123",
            rawJSON: nil,
            lastSyncedAt: Date()
        )
        try harness.repository.upsertCloudInstanceLink(link)
        let service = CloudMetricService(
            repository: harness.repository,
            keychain: harness.keychain,
            registry: CloudProviderRegistry(adapters: [
                MockCloudProviderAdapter(
                    providerId: .tencentCloud,
                    capabilities: [.regions, .instanceDiscovery, .instanceMetadata, .cloudMetrics]
                )
            ]),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let metrics = try await service.loadMetrics(for: profile)

        XCTAssertEqual(metrics, [
            DashboardMetric(name: "Cloud CPU", value: "21.2", unit: "%", source: "Cloud API")
        ])
        link.serverId = nil
        try harness.repository.upsertCloudInstanceLink(link)
        let metricsAfterUnlink = try await service.loadMetrics(for: profile)
        XCTAssertEqual(metricsAfterUnlink, [])
    }

    func testTencentCloudAdapterMapsProviderErrors() async {
        let transport = MockTencentCloudTransport(responses: [
            """
            {
              "Response": {
                "Error": {
                  "Code": "AuthFailure.SecretIdNotFound",
                  "Message": "secret id not found"
                },
                "RequestId": "request-error"
              }
            }
            """
        ])
        let adapter = TencentCloudAdapter(transport: transport, timeout: 1)

        do {
            _ = try await adapter.fetchRegions(credential: CloudProviderCredential(
                secretId: "AKIDEXAMPLE",
                secretKey: "SECRETEXAMPLE"
            ))
            XCTFail("Expected authentication failure.")
        } catch {
            XCTAssertEqual(error as? CloudProviderError, .authenticationFailed("secret id not found"))
        }
    }

    private final class Harness {
        let repository: ServerRepository
        let keychain: KeychainService
        let service: ServerManagementService
        let cloudAccountService: CloudAccountService
        let cloudInstanceSyncService: CloudInstanceSyncService

        init(
            adapters: [any CloudProviderAdapter] = [
                MockCloudProviderAdapter(
                    providerId: .tencentCloud,
                    capabilities: [.regions, .instanceDiscovery, .instanceMetadata]
                ),
            ],
            now: @escaping @Sendable () -> Date = Date.init
        ) throws {
            repository = ServerRepository(database: try AppDatabase.inMemory())
            keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.tests.\(UUID().uuidString)")
            service = ServerManagementService(repository: repository, keychain: keychain)
            cloudAccountService = CloudAccountService(repository: repository, keychain: keychain)
            cloudInstanceSyncService = CloudInstanceSyncService(
                repository: repository,
                keychain: keychain,
                registry: CloudProviderRegistry(adapters: adapters),
                serverManagementService: service,
                now: now
            )
        }
    }
}

private struct MockCloudProviderAdapter: CloudProviderAdapter {
    let providerId: CloudProviderID
    let displayName = "Mock Cloud"
    let capabilities: Set<CloudCapability>

    func validateCredential(_ credential: CloudProviderCredential) async throws {}

    func fetchRegions(credential: CloudProviderCredential) async throws -> [CloudRegion] {
        [
            CloudRegion(id: "ap-guangzhou", displayName: "Guangzhou", available: true),
        ]
    }

    func fetchInstances(credential: CloudProviderCredential, regionId: String) async throws -> [CloudProviderInstance] {
        [
            CloudProviderInstance(
                id: "ins-123",
                providerId: providerId,
                regionId: regionId,
                displayName: "mock-instance",
                publicIp: "203.0.113.1",
                privateIp: "10.0.0.2",
                status: "RUNNING",
                instanceType: "mock",
                zoneId: "\(regionId)-1",
                vpcId: "vpc-123",
                rawJSON: nil
            ),
        ]
    }

    func fetchMetricSeries(credential: CloudProviderCredential, query: CloudMetricQuery) async throws -> CloudMetricSeries {
        CloudMetricSeries(
            metricName: query.metricName,
            instanceId: query.instanceId,
            regionId: query.regionId,
            unit: "%",
            values: [18.5, 21.25],
            timestamps: [query.startTime, query.endTime]
        )
    }
}

private func makeServiceTestProfile() -> ServerProfile {
    ServerProfile(
        id: UUID(),
        name: "Test",
        host: "example.internal",
        port: 22,
        username: "root",
        authType: .privateKey,
        keychainRef: "server_test",
        groupName: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

private final class RecordingSSHClient: SSHClient, @unchecked Sendable {
    private(set) var commands: [String] = []
    private var responses: [CommandResult]

    init(responses: [CommandResult] = []) {
        self.responses = responses
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        commands.append(command)
        if !responses.isEmpty {
            var response = responses.removeFirst()
            response.command = command
            return response
        }
        return CommandResult(command: command, stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class DashboardServiceMockSSHClient: SSHClient, @unchecked Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        let stdout: String
        if command.contains("/etc/os-release") {
            stdout = #"PRETTY_NAME="Ubuntu 24.04.2 LTS""#
        } else if command == "uname -r" {
            stdout = "6.8.0\n"
        } else if command.contains("test -d /proc") || command.contains("systemctl") || command.contains("sftp") {
            stdout = "yes\n"
        } else if command.contains("/proc/loadavg") {
            stdout = "0.10 0.20 0.30 1/100 12345\n"
        } else if command.contains("/proc/meminfo") {
            stdout = "MemTotal: 2048000 kB\nMemAvailable: 1024000 kB\n"
        } else if command.contains("df -kP") {
            stdout = "/dev/vda1 20971520 10485760 10485760 50% /\n"
        } else if command.contains("_NPROCESSORS_ONLN") {
            stdout = "4\n"
        } else if command.contains("/proc/net/dev") {
            stdout = "eth0: 1048576 0 0 0 0 0 0 0 2097152 0 0 0 0 0 0 0\n"
        } else if command.contains("ps -eo stat=") {
            stdout = "total=120 running=2 sleeping=117 stopped=0 zombie=1\n"
        } else {
            stdout = ""
        }
        return CommandResult(command: command, stdout: stdout, stderr: "", exitCode: 0, duration: 0)
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {}
}

private final class RecordingTransferClient: RemoteFileTransferClient, @unchecked Sendable {
    private(set) var uploads: [(localURL: URL, remotePath: String)] = []
    private(set) var downloads: [(remotePath: String, localURL: URL)] = []

    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        uploads.append((localURL, remotePath))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: nil,
            duration: 0
        )
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        downloads.append((remotePath, localURL))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: nil,
            duration: 0
        )
    }
}

private final class MockTencentCloudTransport: TencentCloudHTTPTransport, @unchecked Sendable {
    private var responses: [String]
    private(set) var requests: [URLRequest] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = responses.isEmpty ? #"{"Response":{"RequestId":"empty"}}"# : responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }
}

private extension URLRequest {
    var jsonBody: [String: Any]? {
        guard let httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any]
    }
}
