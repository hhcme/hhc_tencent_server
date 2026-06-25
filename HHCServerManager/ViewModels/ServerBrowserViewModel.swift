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
