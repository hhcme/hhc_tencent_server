import Foundation
import AppKit

enum ServerSourceFilter: String, CaseIterable, Identifiable {
    case all
    case manual
    case cloud

    var id: String { rawValue }
}

@MainActor
final class ServerBrowserViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedServerId: UUID?
    @Published var sourceFilter: ServerSourceFilter = .all

    func filteredServers(from servers: [ServerProfile], links: [CloudInstanceLink]) -> [ServerProfile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkedServerIds = Set(links.compactMap(\.serverId))
        return servers.filter { profile in
            switch sourceFilter {
            case .all:
                true
            case .manual:
                !linkedServerIds.contains(profile.id)
            case .cloud:
                linkedServerIds.contains(profile.id)
            }
        }.filter { profile in
            query.isEmpty ||
                profile.name.localizedCaseInsensitiveContains(query) ||
                profile.host.localizedCaseInsensitiveContains(query) ||
                profile.username.localizedCaseInsensitiveContains(query) ||
                (profile.groupName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func cloudLink(for profile: ServerProfile, links: [CloudInstanceLink]) -> CloudInstanceLink? {
        links.first { $0.serverId == profile.id }
    }
}

@MainActor
final class CloudImportViewModel: ObservableObject {
    @Published var accountDisplayName = "Tencent Cloud"
    @Published var secretId = ""
    @Published var secretKey = ""
    @Published var selectedAccountId: UUID?
    @Published var regions: [CloudRegion] = []
    @Published var selectedRegionId = ""
    @Published var instances: [CloudInstanceLink] = []
    @Published var selectedInstanceId: UUID?
    @Published var importUsername = "root"
    @Published var authType: SSHAuthType = .privateKey
    @Published var password = ""
    @Published var privateKeyData: Data?
    @Published var privateKeyFileName = ""
    @Published var passphrase = ""
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    var canAddAccount: Bool {
        !accountDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !secretId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isWorking
    }

    var canSync: Bool {
        selectedAccountId != nil && !selectedRegionId.isEmpty && !isWorking
    }

    var canImport: Bool {
        selectedInstance != nil &&
            !importUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            credentialInput != nil &&
            !isWorking
    }

    var selectedInstance: CloudInstanceLink? {
        guard let selectedInstanceId else { return nil }
        return instances.first { $0.id == selectedInstanceId }
    }

    func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.title = "Choose SSH Private Key"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                privateKeyData = try Data(contentsOf: url)
                privateKeyFileName = url.lastPathComponent
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectDefaultAccount(from accounts: [CloudProviderAccount]) {
        if selectedAccountId == nil {
            selectedAccountId = accounts.first(where: \.enabled)?.id ?? accounts.first?.id
        }
    }

    func addTencentAccount(appState: AppState) async {
        await run("Validating Tencent Cloud account...") {
            let credential = CloudProviderCredential(
                secretId: secretId.trimmingCharacters(in: .whitespacesAndNewlines),
                secretKey: secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try await appState.cloudProviderRegistry.adapter(for: .tencentCloud).validateCredential(credential)
            let account = try appState.cloudAccountService.createAccount(
                providerId: .tencentCloud,
                displayName: accountDisplayName,
                credential: credential
            )
            appState.reloadServers()
            selectedAccountId = account.id
            secretId = ""
            secretKey = ""
            statusMessage = "Account added and verified."
        }
    }

    func loadRegions(appState: AppState) async {
        guard let account = selectedAccount(from: appState.cloudProviderAccounts) else { return }
        await run("Loading regions...") {
            regions = try await appState.cloudInstanceSyncService.fetchRegions(account: account)
                .filter(\.available)
            selectedRegionId = regions.first?.id ?? ""
            statusMessage = regions.isEmpty ? "No available CVM regions returned." : "Regions loaded."
        }
    }

    func syncInstances(appState: AppState) async {
        guard let account = selectedAccount(from: appState.cloudProviderAccounts) else { return }
        await run("Syncing CVM instances...") {
            instances = try await appState.cloudInstanceSyncService.syncInstances(
                account: account,
                regionId: selectedRegionId
            )
            selectedInstanceId = instances.first?.id
            appState.reloadServers()
            statusMessage = instances.isEmpty ? "No CVM instances found in this region." : "Instances synced."
        }
    }

    func importSelectedInstance(appState: AppState) throws -> ServerProfile {
        guard let selectedInstance else {
            throw CloudImportError.validation("Select a cloud instance first.")
        }
        guard let credentialInput else {
            throw CloudImportError.validation("Choose an SSH credential for the imported server.")
        }
        let profile = try appState.cloudInstanceSyncService.createServerFromInstance(
            selectedInstance,
            username: importUsername,
            authType: authType,
            credential: credentialInput
        )
        appState.reloadServers()
        return profile
    }

    private var credentialInput: CredentialInput? {
        switch authType {
        case .password:
            password.isEmpty ? nil : .password(password)
        case .privateKey:
            privateKeyData.map { .privateKey(data: $0, passphrase: passphrase.nilIfBlank) }
        }
    }

    private func selectedAccount(from accounts: [CloudProviderAccount]) -> CloudProviderAccount? {
        guard let selectedAccountId else { return nil }
        return accounts.first { $0.id == selectedAccountId }
    }

    private func run(_ status: String, operation: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        statusMessage = status
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }
}

enum CloudResourceKindFilter: String, CaseIterable, Identifiable {
    case all
    case instance
    case disk
    case snapshot
    case billing
    case securityGroup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .instance:
            "Instances"
        case .disk:
            "Disks"
        case .snapshot:
            "Snapshots"
        case .billing:
            "Billing"
        case .securityGroup:
            "Security Groups"
        }
    }

    var queryKinds: Set<CloudResourceKind> {
        switch self {
        case .all:
            Set(CloudResourceKind.allCases)
        case .instance:
            [.instance]
        case .disk:
            [.disk]
        case .snapshot:
            [.snapshot]
        case .billing:
            [.billing]
        case .securityGroup:
            [.securityGroup]
        }
    }
}

@MainActor
final class CloudResourceCenterViewModel: ObservableObject {
    @Published var selectedAccountId: UUID?
    @Published var regions: [CloudRegion] = []
    @Published var selectedRegionId = ""
    @Published var searchText = ""
    @Published var statusFilter = ""
    @Published var kindFilter: CloudResourceKindFilter = .all
    @Published private(set) var resources: [CloudUnifiedResource] = []
    @Published private(set) var capabilityRows: [ProviderCapabilityStatus] = []
    @Published var selectedResourceId: String?
    @Published var isWorking = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    var selectedResource: CloudUnifiedResource? {
        guard let selectedResourceId else { return nil }
        return resources.first { $0.id == selectedResourceId }
    }

    var canLoadRegions: Bool {
        selectedAccountId != nil && !isWorking
    }

    var canSync: Bool {
        selectedAccountId != nil && !selectedRegionId.isEmpty && !isWorking
    }

    func selectDefaultAccount(from accounts: [CloudProviderAccount]) {
        if selectedAccountId == nil {
            selectedAccountId = accounts.first(where: \.enabled)?.id ?? accounts.first?.id
        }
    }

    func refreshCapabilityMatrix(registry: CloudProviderRegistry) {
        capabilityRows = ProviderCapabilityMatrixBuilder.build(registry: registry).rows
    }

    func refreshLocalResources(appState: AppState) {
        do {
            let query = CloudResourceSearchQuery(
                text: searchText,
                accountId: selectedAccountId,
                regionId: selectedRegionId.nilIfBlank,
                kinds: kindFilter.queryKinds,
                status: statusFilter.nilIfBlank
            )
            resources = try appState.cloudInstanceSyncService.loadUnifiedCloudResources(
                accountId: selectedAccountId,
                regionId: selectedRegionId.nilIfBlank,
                query: query
            )
            if let selectedResourceId, !resources.contains(where: { $0.id == selectedResourceId }) {
                self.selectedResourceId = resources.first?.id
            } else if selectedResourceId == nil {
                selectedResourceId = resources.first?.id
            }
            statusMessage = resources.isEmpty ? "No cached cloud resources match the current filters." : "Loaded \(resources.count) cached cloud resources."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    func loadRegions(appState: AppState) async {
        guard let account = selectedAccount(from: appState.cloudProviderAccounts) else { return }
        await run("Loading regions...") {
            regions = try await appState.cloudInstanceSyncService.fetchRegions(account: account).filter(\.available)
            selectedRegionId = regions.first?.id ?? ""
            refreshLocalResources(appState: appState)
            statusMessage = regions.isEmpty ? "No available regions returned." : "Regions loaded."
        }
    }

    func syncSelectedRegion(appState: AppState) async {
        guard let account = selectedAccount(from: appState.cloudProviderAccounts) else { return }
        await run("Syncing cloud resources...") {
            _ = try await appState.cloudInstanceSyncService.syncInstances(account: account, regionId: selectedRegionId)
            if appState.cloudProviderRegistry.supports(.cloudDisks, providerId: account.providerId) {
                _ = try await appState.cloudInstanceSyncService.syncDisks(account: account, regionId: selectedRegionId)
            }
            if appState.cloudProviderRegistry.supports(.cloudSnapshots, providerId: account.providerId) {
                _ = try await appState.cloudInstanceSyncService.syncSnapshots(account: account, regionId: selectedRegionId)
            }
            if appState.cloudProviderRegistry.supports(.cloudBilling, providerId: account.providerId) {
                _ = try await appState.cloudInstanceSyncService.syncBillingStates(account: account, regionId: selectedRegionId)
            }
            appState.reloadServers()
            refreshLocalResources(appState: appState)
            statusMessage = resources.isEmpty ? "Sync completed. No resources matched the current filters." : "Sync completed. \(resources.count) resources are visible."
        }
    }

    func resetFilters(appState: AppState) {
        searchText = ""
        statusFilter = ""
        kindFilter = .all
        refreshLocalResources(appState: appState)
    }

    private func selectedAccount(from accounts: [CloudProviderAccount]) -> CloudProviderAccount? {
        guard let selectedAccountId else { return nil }
        return accounts.first { $0.id == selectedAccountId }
    }

    private func run(_ status: String, operation: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        statusMessage = status
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }
}

enum CloudImportError: LocalizedError {
    case validation(String)

    var errorDescription: String? {
        switch self {
        case let .validation(message):
            message
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
