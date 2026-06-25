import Foundation

@MainActor
final class AppState: ObservableObject {
    let repository: ServerRepository
    let serverManagementService: ServerManagementService
    let cloudAccountService: CloudAccountService
    let cloudInstanceSyncService: CloudInstanceSyncService
    let cloudProviderRegistry: CloudProviderRegistry
    let cloudMetricService: CloudMetricService
    let cloudSecurityGroupService: CloudSecurityGroupService
    let dashboardService: DashboardService
    let systemdServiceManager: SystemdServiceManager
    let cronManager: CronManager
    let nginxConfigManager: NginxConfigManager
    let firewallManager: FirewallManager
    let environmentFileManager: EnvironmentFileManager
    let remoteFileService: RemoteFileService
    let deploymentRunner: DeploymentRunner
    let deploymentWebhookService: DeploymentWebhookService
    let deploymentWebhookHTTPServer: DeploymentWebhookHTTPServer
    let registryPreflightChecker: RegistryPreflightChecker
    let verdaccioInstaller: VerdaccioInstaller
    let verdaccioManager: VerdaccioManager
    let sshClient: OpenSSHClient

    @Published var servers: [ServerProfile] = []
    @Published var cloudInstanceLinks: [CloudInstanceLink] = []
    @Published var cloudProviderAccounts: [CloudProviderAccount] = []
    @Published var selectedServerId: UUID?
    @Published var connectionStates: [UUID: SSHConnectionState] = [:]
    @Published var startupError: String?

    init(
        repository: ServerRepository,
        keychain: KeychainService,
        registry: CloudProviderRegistry = CloudProviderRegistry(adapters: [
            TencentCloudAdapter(),
            AlibabaCloudAdapter(),
            HuaweiCloudAdapter(),
        ])
    ) {
        self.repository = repository
        serverManagementService = ServerManagementService(repository: repository, keychain: keychain)
        cloudAccountService = CloudAccountService(repository: repository, keychain: keychain)
        cloudProviderRegistry = registry
        cloudMetricService = CloudMetricService(repository: repository, keychain: keychain, registry: registry)
        cloudSecurityGroupService = CloudSecurityGroupService(repository: repository, keychain: keychain, registry: registry)
        dashboardService = DashboardService()
        systemdServiceManager = SystemdServiceManager()
        cronManager = CronManager()
        nginxConfigManager = NginxConfigManager()
        firewallManager = FirewallManager()
        environmentFileManager = EnvironmentFileManager()
        remoteFileService = RemoteFileService()
        deploymentRunner = DeploymentRunner(repository: repository)
        registryPreflightChecker = RegistryPreflightChecker()
        verdaccioInstaller = VerdaccioInstaller()
        verdaccioManager = VerdaccioManager()
        deploymentWebhookService = DeploymentWebhookService(
            repository: repository,
            keychain: keychain,
            runner: deploymentRunner
        )
        let sshClient = OpenSSHClient(repository: repository, keychain: keychain)
        self.sshClient = sshClient
        deploymentWebhookHTTPServer = DeploymentWebhookHTTPServer(
            webhookService: deploymentWebhookService,
            sshClient: sshClient
        )
        cloudInstanceSyncService = CloudInstanceSyncService(
            repository: repository,
            keychain: keychain,
            registry: registry,
            serverManagementService: serverManagementService
        )
        reloadServers()
    }

    init() {
        do {
            let database = try AppDatabase.production()
            let repository = ServerRepository(database: database)
            let keychain = KeychainService()
            let registry = CloudProviderRegistry(adapters: [
                TencentCloudAdapter(),
                AlibabaCloudAdapter(),
                HuaweiCloudAdapter(),
            ])
            self.repository = repository
            serverManagementService = ServerManagementService(repository: repository, keychain: keychain)
            cloudAccountService = CloudAccountService(repository: repository, keychain: keychain)
            cloudProviderRegistry = registry
            cloudMetricService = CloudMetricService(repository: repository, keychain: keychain, registry: registry)
            cloudSecurityGroupService = CloudSecurityGroupService(repository: repository, keychain: keychain, registry: registry)
            dashboardService = DashboardService()
            systemdServiceManager = SystemdServiceManager()
            cronManager = CronManager()
            nginxConfigManager = NginxConfigManager()
            firewallManager = FirewallManager()
            environmentFileManager = EnvironmentFileManager()
            remoteFileService = RemoteFileService()
            deploymentRunner = DeploymentRunner(repository: repository)
            registryPreflightChecker = RegistryPreflightChecker()
            verdaccioInstaller = VerdaccioInstaller()
            verdaccioManager = VerdaccioManager()
            deploymentWebhookService = DeploymentWebhookService(
                repository: repository,
                keychain: keychain,
                runner: deploymentRunner
            )
            let sshClient = OpenSSHClient(repository: repository, keychain: keychain)
            self.sshClient = sshClient
            deploymentWebhookHTTPServer = DeploymentWebhookHTTPServer(
                webhookService: deploymentWebhookService,
                sshClient: sshClient
            )
            cloudInstanceSyncService = CloudInstanceSyncService(
                repository: repository,
                keychain: keychain,
                registry: registry,
                serverManagementService: serverManagementService
            )
            reloadServers()
        } catch {
            startupError = error.localizedDescription
            let database = try! AppDatabase.inMemory()
            let repository = ServerRepository(database: database)
            let keychain = KeychainService(serviceName: "me.hhc.HHCServerManager.fallback")
            let registry = CloudProviderRegistry(adapters: [
                TencentCloudAdapter(),
                AlibabaCloudAdapter(),
                HuaweiCloudAdapter(),
            ])
            self.repository = repository
            serverManagementService = ServerManagementService(repository: repository, keychain: keychain)
            cloudAccountService = CloudAccountService(repository: repository, keychain: keychain)
            cloudProviderRegistry = registry
            cloudMetricService = CloudMetricService(repository: repository, keychain: keychain, registry: registry)
            cloudSecurityGroupService = CloudSecurityGroupService(repository: repository, keychain: keychain, registry: registry)
            dashboardService = DashboardService()
            systemdServiceManager = SystemdServiceManager()
            cronManager = CronManager()
            nginxConfigManager = NginxConfigManager()
            firewallManager = FirewallManager()
            environmentFileManager = EnvironmentFileManager()
            remoteFileService = RemoteFileService()
            deploymentRunner = DeploymentRunner(repository: repository)
            registryPreflightChecker = RegistryPreflightChecker()
            verdaccioInstaller = VerdaccioInstaller()
            verdaccioManager = VerdaccioManager()
            deploymentWebhookService = DeploymentWebhookService(
                repository: repository,
                keychain: keychain,
                runner: deploymentRunner
            )
            let sshClient = OpenSSHClient(repository: repository, keychain: keychain)
            self.sshClient = sshClient
            deploymentWebhookHTTPServer = DeploymentWebhookHTTPServer(
                webhookService: deploymentWebhookService,
                sshClient: sshClient
            )
            cloudInstanceSyncService = CloudInstanceSyncService(
                repository: repository,
                keychain: keychain,
                registry: registry,
                serverManagementService: serverManagementService
            )
        }
    }

    var selectedServer: ServerProfile? {
        guard let selectedServerId else { return nil }
        return servers.first { $0.id == selectedServerId }
    }

    func reloadServers() {
        do {
            servers = try repository.fetchServers()
            cloudInstanceLinks = try repository.fetchCloudInstanceLinks()
            cloudProviderAccounts = try repository.fetchCloudProviderAccounts()
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
