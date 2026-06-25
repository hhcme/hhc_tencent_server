import XCTest
@testable import HHCServerManager

final class CloudIntegrationTests: XCTestCase {
    func testRealTencentCloudReadOnlySyncWhenEnvironmentIsConfigured() async throws {
        let harness = try makeHarness(
            providerId: .tencentCloud,
            adapter: TencentCloudAdapter(),
            configuration: .tencentCloud
        )
        try await verifyReadOnlySync(harness)
    }

    func testRealAlibabaCloudReadOnlySyncWhenEnvironmentIsConfigured() async throws {
        let harness = try makeHarness(
            providerId: .alibabaCloud,
            adapter: AlibabaCloudAdapter(),
            configuration: .alibabaCloud
        )
        try await verifyReadOnlySync(harness)
    }

    func testRealHuaweiCloudReadOnlySyncWhenEnvironmentIsConfigured() async throws {
        let harness = try makeHarness(
            providerId: .huaweiCloud,
            adapter: HuaweiCloudAdapter(),
            configuration: .huaweiCloud
        )
        try await verifyReadOnlySync(harness)
    }

    private func verifyReadOnlySync(_ harness: Harness) async throws {
        defer {
            try? harness.accountService.deleteAccount(harness.account)
        }

        await XCTAssertNoThrowAsync(
            try await harness.syncService.validateAccount(harness.account),
            "Real \(harness.account.providerId.displayName) credential validation failed."
        )

        let regions = try await harness.syncService.fetchRegions(account: harness.account)
        XCTAssertFalse(regions.isEmpty, "Real \(harness.account.providerId.displayName) region/project list is empty.")

        let regionId = harness.regionId ?? regions.first(where: \.available)?.id ?? regions[0].id
        let links = try await harness.syncService.syncInstances(account: harness.account, regionId: regionId)
        XCTAssertEqual(
            try harness.repository.fetchCloudInstanceLinks(accountId: harness.account.id)
                .filter { $0.regionId == regionId },
            links
        )

        _ = try await harness.syncService.syncDisks(account: harness.account, regionId: regionId)
        _ = try await harness.syncService.syncSnapshots(account: harness.account, regionId: regionId)
        _ = try await harness.syncService.syncBillingStates(account: harness.account, regionId: regionId)

        let resources = try harness.syncService.loadUnifiedCloudResources(
            accountId: harness.account.id,
            regionId: regionId,
            query: CloudResourceSearchQuery(kinds: Set(CloudResourceKind.allCases))
        )
        XCTAssertTrue(
            resources.allSatisfy { $0.providerId == harness.account.providerId && $0.regionId == regionId },
            "Unified resources must stay scoped to the configured provider and region."
        )
        XCTAssertEqual(
            Set(resources.map(\.kind)).isSubset(of: Set(CloudResourceKind.allCases)),
            true
        )
    }

    private func makeHarness(
        providerId: CloudProviderID,
        adapter: any CloudProviderAdapter,
        configuration: CloudTestConfiguration
    ) throws -> Harness {
        guard Self.testEnvironment()["HHC_TEST_CLOUD_REAL"] == "1" else {
            throw XCTSkip("Set HHC_TEST_CLOUD_REAL=1 and provider credentials to run real read-only cloud sync tests.")
        }
        guard let credential = configuration.credential(from: Self.testEnvironment()) else {
            throw XCTSkip(configuration.skipMessage)
        }

        let repository = ServerRepository(database: try AppDatabase.inMemory())
        let keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.cloud-tests.\(UUID().uuidString)")
        let accountService = CloudAccountService(repository: repository, keychain: keychain)
        let account = try accountService.createAccount(
            providerId: providerId,
            displayName: "\(providerId.displayName) Integration",
            credential: credential
        )
        let syncService = CloudInstanceSyncService(
            repository: repository,
            keychain: keychain,
            registry: CloudProviderRegistry(adapters: [adapter]),
            serverManagementService: ServerManagementService(repository: repository, keychain: keychain)
        )
        return Harness(
            repository: repository,
            accountService: accountService,
            syncService: syncService,
            account: account,
            regionId: configuration.regionId(from: Self.testEnvironment())
        )
    }

    private static func testEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for url in cloudEnvironmentFileURLs() {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                continue
            }
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let separator = trimmed.firstIndex(of: "=") else {
                    continue
                }
                let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(trimmed[trimmed.index(after: separator)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if environment[key] == nil {
                    environment[key] = value
                }
            }
        }
        return environment
    }

    private static func cloudEnvironmentFileURLs() -> [URL] {
        let fileManager = FileManager.default
        var urls: [URL] = []
        if let explicitPath = ProcessInfo.processInfo.environment["HHC_TEST_CLOUD_ENV_FILE"] {
            urls.append(URL(fileURLWithPath: NSString(string: explicitPath).expandingTildeInPath))
        }
        if let home = fileManager.homeDirectoryForCurrentUser.path.removingPercentEncoding {
            urls.append(URL(fileURLWithPath: home).appendingPathComponent(".hhc-server-manager/cloud.env"))
        }
        return urls
    }
}

private struct Harness {
    let repository: ServerRepository
    let accountService: CloudAccountService
    let syncService: CloudInstanceSyncService
    let account: CloudProviderAccount
    let regionId: String?
}

private enum CloudTestConfiguration {
    case tencentCloud
    case alibabaCloud
    case huaweiCloud

    var skipMessage: String {
        switch self {
        case .tencentCloud:
            "Set HHC_TEST_TENCENT_SECRET_ID and HHC_TEST_TENCENT_SECRET_KEY for Tencent Cloud read-only sync."
        case .alibabaCloud:
            "Set HHC_TEST_ALIBABA_ACCESS_KEY_ID and HHC_TEST_ALIBABA_ACCESS_KEY_SECRET for Alibaba Cloud read-only sync."
        case .huaweiCloud:
            "Set HHC_TEST_HUAWEI_ACCESS_KEY_ID and HHC_TEST_HUAWEI_SECRET_ACCESS_KEY for Huawei Cloud read-only sync."
        }
    }

    func credential(from environment: [String: String]) -> CloudProviderCredential? {
        switch self {
        case .tencentCloud:
            return credential(
                secretId: environment["HHC_TEST_TENCENT_SECRET_ID"],
                secretKey: environment["HHC_TEST_TENCENT_SECRET_KEY"]
            )
        case .alibabaCloud:
            return credential(
                secretId: environment["HHC_TEST_ALIBABA_ACCESS_KEY_ID"],
                secretKey: environment["HHC_TEST_ALIBABA_ACCESS_KEY_SECRET"]
            )
        case .huaweiCloud:
            return credential(
                secretId: environment["HHC_TEST_HUAWEI_ACCESS_KEY_ID"],
                secretKey: environment["HHC_TEST_HUAWEI_SECRET_ACCESS_KEY"]
            )
        }
    }

    func regionId(from environment: [String: String]) -> String? {
        let key: String
        switch self {
        case .tencentCloud:
            key = "HHC_TEST_TENCENT_REGION"
        case .alibabaCloud:
            key = "HHC_TEST_ALIBABA_REGION"
        case .huaweiCloud:
            key = "HHC_TEST_HUAWEI_REGION"
        }
        let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func credential(secretId: String?, secretKey: String?) -> CloudProviderCredential? {
        guard let secretId = secretId?.trimmingCharacters(in: .whitespacesAndNewlines),
              let secretKey = secretKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secretId.isEmpty,
              !secretKey.isEmpty else {
            return nil
        }
        return CloudProviderCredential(secretId: secretId, secretKey: secretKey)
    }
}

private func XCTAssertNoThrowAsync(
    _ expression: @autoclosure () async throws -> Void,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
    } catch {
        XCTFail("\(message()) \(error)", file: file, line: line)
    }
}
