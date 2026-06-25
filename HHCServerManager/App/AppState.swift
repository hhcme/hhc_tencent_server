import Foundation

@MainActor
final class AppState: ObservableObject {
    let repository: ServerRepository
    let serverManagementService: ServerManagementService
    let sshClient: OpenSSHClient

    @Published var servers: [ServerProfile] = []
    @Published var selectedServerId: UUID?
    @Published var connectionStates: [UUID: SSHConnectionState] = [:]
    @Published var startupError: String?

    init() {
        do {
            let database = try AppDatabase.production()
            let repository = ServerRepository(database: database)
            let keychain = KeychainService()
            self.repository = repository
            serverManagementService = ServerManagementService(repository: repository, keychain: keychain)
            sshClient = OpenSSHClient(repository: repository, keychain: keychain)
            reloadServers()
        } catch {
            startupError = error.localizedDescription
            let database = try! AppDatabase.inMemory()
            let repository = ServerRepository(database: database)
            let keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.fallback")
            self.repository = repository
            serverManagementService = ServerManagementService(repository: repository, keychain: keychain)
            sshClient = OpenSSHClient(repository: repository, keychain: keychain)
        }
    }

    var selectedServer: ServerProfile? {
        guard let selectedServerId else { return nil }
        return servers.first { $0.id == selectedServerId }
    }

    func reloadServers() {
        do {
            servers = try repository.fetchServers()
            if let selectedServerId, !servers.contains(where: { $0.id == selectedServerId }) {
                self.selectedServerId = nil
            }
        } catch {
            startupError = error.localizedDescription
        }
    }

    func openWorkspace(for profile: ServerProfile) {
        selectedServerId = profile.id
    }

    func closeWorkspace() {
        selectedServerId = nil
    }

    func connectionState(for profile: ServerProfile) -> SSHConnectionState {
        connectionStates[profile.id] ?? .disconnected
    }

    func setConnectionState(_ state: SSHConnectionState, for profile: ServerProfile) {
        connectionStates[profile.id] = state
    }

    func delete(_ profile: ServerProfile) {
        do {
            try serverManagementService.deleteServer(profile)
            connectionStates[profile.id] = nil
            reloadServers()
        } catch {
            startupError = error.localizedDescription
        }
    }
}
