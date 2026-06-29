import AppKit
import SwiftUI

struct ServerWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ServerWorkspaceViewModel()
    @State private var selectedSection = "overview"
    @State private var commandText = ""
    @State private var terminalSnippetCategory: TerminalCommandCategory = .system
    @State private var terminalHistorySearchText = ""
    @State private var terminalHistoryStatusFilter: CommandHistoryStatusFilter = .all
    @State private var serviceSearchText = ""
    @State private var serviceFilter: ServiceListFilter = .all
    @State private var pendingClearCommandHistory = false
    @State private var filePathText = "~"
    @State private var remoteFileRenameEntry: RemoteFileEntry?
    @State private var remoteFileRenameText = ""
    @State private var remoteFileCreateKind: RemoteFileCreationKind?
    @State private var remoteFileCreateName = ""
    @State private var remoteFileTrashEntry: RemoteFileEntry?
    @State private var selectedRemoteFileIDs: Set<String> = []
    @State private var remoteFilePermissionsEntry: RemoteFileEntry?
    @State private var remoteFilePermissionsText = ""
    @State private var pendingSystemdAction: SystemdActionRequest?
    @State private var databaseServiceFilter: DatabaseServiceFilter = .all
    @State private var pendingDatabaseAction: DatabaseServiceActionRequest?
    @State private var pendingDatabaseBackup: DatabaseBackupRequest?
    @State private var pendingDockerAction: DockerContainerActionRequest?
    @State private var cronScheduleText = "0 2 * * *"
    @State private var cronCommandText = ""
    @State private var cronFilter: CronEntryFilter = .all
    @State private var pendingCronAction: CronActionRequest?
    @State private var nginxSiteFilter: NginxSiteFilter = .all
    @State private var pendingNginxReload = false
    @State private var pendingNginxSave = false
    @State private var pendingNginxReverseProxyWrite = false
    @State private var pendingEnvironmentSave = false
    @State private var pendingFirewallRule: FirewallRuleRequest?
    @State private var pendingCloudSecurityGroupRule: CloudSecurityGroupRuleRequest?
    @State private var pendingDeploymentRun: DeploymentRunRequest?
    @State private var pendingDeploymentRollback: DeploymentRollbackRequest?
    @State private var pendingVerdaccioInstall = false
    @State private var pendingVerdaccioUserDelete = false
    @State private var pendingVerdaccioPackageDeletion: VerdaccioPackageDeletionRequest?
    @State private var pendingVerdaccioRestore = false
    @State private var pendingVerdaccioProxyReload = false
    @State private var pendingRegistryRisk: RegistryRiskRequest?
    @State private var pendingGitLabInstall = false
    @State private var pendingGiteaInstall = false
    @State private var pendingGitLabServiceAction: GitLabServiceAction?
    @State private var pendingGitNativeDeletion: GitNativeDeletionRequest?
    @State private var pendingGitNativeIssueState: GitNativeIssueStateRequest?
    @State private var pendingGiteaRepositorySettingsSave = false
    @State private var pendingGitLabProjectSettingsSave = false
    @State private var pendingGitLabPipelineAction: GitLabPipelineActionRequest?
    @State private var pendingGitLabVariableSave: GitLabVariableSaveRequest?
    @State private var pendingGitLabVariableDeletion: GitLabVariableDeletionRequest?
    @State private var pendingGitLabGroupSave: GitLabGroupSaveRequest?
    @State private var pendingGitLabMemberSave: GitLabMemberSaveRequest?
    @State private var pendingGitLabMemberDeletion: GitLabMemberDeletionRequest?
    @State private var pendingGiteaUserSave: GiteaUserSaveRequest?
    @State private var pendingGiteaUserDeletion: GiteaUserDeletionRequest?
    @State private var pendingGiteaOrganizationSave: GiteaOrganizationSaveRequest?
    @State private var pendingGiteaOrganizationDeletion: GiteaOrganizationDeletionRequest?
    @State private var pendingGiteaTeamSave: GiteaTeamSaveRequest?
    @State private var pendingGiteaTeamDeletion: GiteaTeamDeletionRequest?
    @State private var pendingGiteaTeamMemberSave: GiteaTeamMemberSaveRequest?
    @State private var pendingGiteaTeamMemberDeletion: GiteaTeamMemberDeletionRequest?
    @State private var pendingGiteaTeamRepositorySave: GiteaTeamRepositorySaveRequest?
    @State private var pendingGiteaTeamRepositoryDeletion: GiteaTeamRepositoryDeletionRequest?
    @State private var pendingGiteaKeySave = false
    @State private var pendingGiteaKeyDeletion: GiteaKeyDeletionRequest?
    @State private var pendingGiteaAccessTokenSave = false
    @State private var pendingGiteaAccessTokenDeletion: GiteaAccessTokenDeletionRequest?
    @State private var pendingGiteaPackageDeletion: GiteaPackageDeletionRequest?
    @State private var pendingGitLabDeployKeySave = false
    @State private var pendingGitLabDeployKeyDeletion: GitLabDeployKeyDeletionRequest?
    @State private var pendingGitLabDeployTokenSave = false
    @State private var pendingGitLabDeployTokenDeletion: GitLabDeployTokenDeletionRequest?
    @State private var pendingGitLabPackageDeletion: GitLabPackageDeletionRequest?
    @State private var pendingGitLabTagSave = false
    @State private var pendingGitLabTagDeletion: GitLabTagDeletionRequest?
    @State private var pendingGitLabJobAction: GitLabJobActionRequest?
    @State private var developmentServiceCategory: DevelopmentServiceCategory = .git
    @State private var selectedGitWorkbenchService: GitWorkbenchService = .gitea
    @State private var gitNativeManagementTab: GitNativeManagementTab = .overview
    @State private var npmManagementTab: NpmManagementTab = .overview
    @State private var gitIssueStateFilter: GitIssueStateFilter = .all
    @State private var securityGroupDraftDirection: CloudSecurityGroupRuleDirection = .ingress
    @State private var securityGroupDraftProtocol = "TCP"
    @State private var securityGroupDraftPort = "22"
    @State private var securityGroupDraftCIDR = "0.0.0.0/0"
    @State private var securityGroupDraftAction = "ACCEPT"
    @State private var securityGroupDraftDescription = ""
    @State private var securityGroupRulePreview: CloudSecurityGroupRuleChangePreview?
    @State private var firewallRuleMutation: FirewallRuleMutationAction = .add
    @State private var firewallRuleDirection: FirewallRuleDirection = .ingress
    @State private var firewallRuleAction: FirewallRuleAction = .allow
    @State private var firewallRuleProtocol: FirewallRuleProtocol = .tcp
    @State private var firewallRulePort = "22"
    @State private var firewallRuleCIDR = "0.0.0.0/0"
    @State private var auditSearchText = ""
    @State private var auditStatusFilter = "all"
    @State private var auditTargetFilter = "all"
    @State private var auditShowsSnapshots = false

    let profile: ServerProfile

    var body: some View {
        workspaceSplitView
            .sheet(item: $viewModel.pendingHostKey) { hostKey in
                HostKeyTrustSheet(
                    hostKey: hostKey,
                    trust: {
                        viewModel.trustPendingHostKey(profile: profile, sshClient: appState.sshClient)
                    },
                    reject: {
                        viewModel.rejectPendingHostKey()
                    }
                )
            }
            .alert(L10n.string("SSH Error"), isPresented: errorBinding) {
                Button(L10n.string("OK")) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Clear Command History?", isPresented: $pendingClearCommandHistory) {
                Button("Cancel", role: .cancel) {}
                Button("Clear History", role: .destructive) {
                    viewModel.clearCommandHistory(profile: profile, repository: appState.repository)
                }
            } message: {
                Text("This removes saved command metadata for this server. Command output is not stored.")
            }
            .alert("Move to Trash?", isPresented: remoteFileTrashBinding) {
                Button("Cancel", role: .cancel) {
                    remoteFileTrashEntry = nil
                }
                Button("Move", role: .destructive) {
                    if let entry = remoteFileTrashEntry {
                        viewModel.moveRemoteFileToTrash(
                            entry,
                            profile: profile,
                            sshClient: appState.sshClient,
                            remoteFileService: appState.remoteFileService,
                            repository: appState.repository
                        )
                    }
                    remoteFileTrashEntry = nil
                }
            } message: {
                Text(remoteFileTrashEntry.map { RemoteOperationRiskFactory.moveToTrash(entry: $0).confirmationMessage } ?? "")
            }
            .alert(item: $pendingSystemdAction) { request in
                Alert(
                    title: Text("\(request.action.displayName) \(request.unit.name)?"),
                    message: Text(request.risk.confirmationMessage),
                    primaryButton: .destructive(Text(request.action.displayName)) {
                        viewModel.performSystemdAction(
                            request.action,
                            unitName: request.unit.name,
                            profile: profile,
                            sshClient: appState.sshClient,
                            systemdServiceManager: appState.systemdServiceManager,
                            repository: appState.repository
                        )
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(item: $pendingDatabaseAction) { request in
                Alert(
                    title: Text("\(request.action.displayName) \(request.service.kind.displayName)?"),
                    message: Text(request.risk.confirmationMessage),
                    primaryButton: .destructive(Text(request.action.displayName)) {
                        viewModel.performDatabaseServiceAction(
                            request.action,
                            service: request.service,
                            profile: profile,
                            sshClient: appState.sshClient,
                            databaseServiceManager: appState.databaseServiceManager,
                            repository: appState.repository
                        )
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(item: $pendingDatabaseBackup) { request in
                Alert(
                    title: Text("Create \(request.service.kind.displayName) Backup?"),
                    message: Text(request.risk.confirmationMessage),
                    primaryButton: .default(Text("Create Backup")) {
                        viewModel.createDatabaseBackup(
                            service: request.service,
                            profile: profile,
                            sshClient: appState.sshClient,
                            databaseServiceManager: appState.databaseServiceManager,
                            repository: appState.repository
                        )
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(item: $pendingDockerAction) { request in
                Alert(
                    title: Text("\(request.action.displayName) \(request.container.displayName)?"),
                    message: Text(request.risk.confirmationMessage),
                    primaryButton: request.action == .stop || request.action == .restart
                        ? .destructive(Text(request.action.displayName)) { performDockerAction(request) }
                        : .default(Text(request.action.displayName)) { performDockerAction(request) },
                    secondaryButton: .cancel()
                )
            }
            .alert(item: $pendingCronAction) { request in
                Alert(
                    title: Text("\(request.action.displayName) Cron Entry?"),
                    message: Text(request.risk.confirmationMessage),
                    primaryButton: request.action == .delete ? .destructive(Text(request.action.displayName)) {
                        performCronAction(request)
                    } : .default(Text(request.action.displayName)) {
                        performCronAction(request)
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert("Reload Nginx?", isPresented: $pendingNginxReload) {
                Button("Cancel", role: .cancel) {}
                Button("Reload") {
                    reloadNginx()
                }
            } message: {
                nginxReloadMessageText
            }
            .alert("Save Nginx Config?", isPresented: $pendingNginxSave) {
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    saveNginxConfig()
                }
            } message: {
                nginxSaveMessageText
            }
            .alert("Write Reverse Proxy?", isPresented: $pendingNginxReverseProxyWrite) {
                Button("Cancel", role: .cancel) {}
                Button("Write") {
                    writeNginxReverseProxy()
                }
            } message: {
                nginxReverseProxyWriteMessageText
            }
            .alert("Save Environment File?", isPresented: $pendingEnvironmentSave) {
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    viewModel.saveEnvironmentFile(
                        profile: profile,
                        sshClient: appState.sshClient,
                        environmentFileManager: appState.environmentFileManager,
                        repository: appState.repository
                    )
                }
            } message: {
                Text(RemoteOperationRiskFactory.saveEnvironmentFile(path: viewModel.environmentFileContent?.file.path ?? "environment file").confirmationMessage)
            }
            .alert(item: $pendingFirewallRule, content: firewallRuleAlert)
            .alert(item: $pendingCloudSecurityGroupRule, content: cloudSecurityGroupRuleAlert)
            .alert(item: $pendingDeploymentRun) { request in
                Alert(
                    title: Text("Run Deployment?"),
                    message: Text(request.risk.confirmationMessage),
                    primaryButton: .destructive(Text("Run")) {
                        viewModel.runDeployment(
                            profile: profile,
                            sshClient: appState.sshClient,
                            deploymentRunner: appState.deploymentRunner,
                            repository: appState.repository,
                            serverManagementService: appState.serverManagementService
                        )
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(item: $pendingDeploymentRollback) { request in
                Alert(
                    title: Text("Rollback Deployment?"),
                    message: Text(request.risk.confirmationMessage),
                    primaryButton: .destructive(Text("Rollback")) {
                        viewModel.rollbackDeployment(
                            profile: profile,
                            sshClient: appState.sshClient,
                            deploymentRunner: appState.deploymentRunner,
                            repository: appState.repository
                        )
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert("Install Verdaccio?", isPresented: $pendingVerdaccioInstall) {
                Button("Cancel", role: .cancel) {}
                Button("Install", role: .destructive) {
                    viewModel.installVerdaccio(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioInstaller: appState.verdaccioInstaller,
                        verdaccioManager: appState.verdaccioManager
                    )
                }
            } message: {
                Text(verdaccioInstallConfirmationMessage)
            }
            .alert("Delete Verdaccio User?", isPresented: $pendingVerdaccioUserDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    viewModel.deleteVerdaccioUser(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager,
                        repository: appState.repository
                    )
                }
            } message: {
                Text(verdaccioUserDeleteConfirmationMessage)
            }
            .alert(item: $pendingVerdaccioPackageDeletion, content: verdaccioPackageDeletionAlert)
            .alert("Restore Verdaccio Backup?", isPresented: $pendingVerdaccioRestore) {
                Button("Cancel", role: .cancel) {}
                Button("Restore", role: .destructive) {
                    viewModel.restoreVerdaccioBackup(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager,
                        repository: appState.repository
                    )
                }
            } message: {
                Text(verdaccioRestoreConfirmationMessage)
            }
            .alert("Reload Nginx?", isPresented: $pendingVerdaccioProxyReload) {
                Button("Cancel", role: .cancel) {}
                Button("Reload", role: .destructive) {
                    viewModel.reloadVerdaccioNginxProxy(
                        profile: profile,
                        sshClient: appState.sshClient,
                        nginxConfigManager: appState.nginxConfigManager,
                        repository: appState.repository
                    )
                }
            } message: {
                Text(verdaccioProxyReloadConfirmationMessage)
            }
            .alert(item: $pendingRegistryRisk, content: registryRiskAlert)
            .alert(item: $pendingGitNativeDeletion) { request in
                Alert(
                    title: Text("Delete \(request.displayType)?"),
                    message: Text("This deletes \(request.displayName) from \(request.serviceTitle). This remote write operation cannot be undone from HHC Server Manager."),
                    primaryButton: .destructive(Text("Delete")) {
                        performGitNativeDeletion(request)
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(item: $pendingGitNativeIssueState, content: gitNativeIssueStateAlert)
            .alert("保存 Gitea 仓库设置?", isPresented: $pendingGiteaRepositorySettingsSave) {
                Button("保存") {
                    performGiteaRepositorySettingsSave()
                }
                Button(L10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text("This updates \(viewModel.giteaRepositorySettingsDraft.trimmedFullName): visibility, default branch, description, feature switches, and archived state.")
            }
            .alert("保存 GitLab Project 设置?", isPresented: $pendingGitLabProjectSettingsSave) {
                Button("保存") {
                    performGitLabProjectSettingsSave()
                }
                Button(L10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text("This updates \(viewModel.gitLabProjectSettingsDraft.trimmedPathWithNamespace): visibility, default branch, description, and archived state.")
            }
            .alert(item: $pendingGitLabPipelineAction, content: gitLabPipelineActionAlert)
            .alert(item: $pendingGitLabJobAction, content: gitLabJobActionAlert)
            .alert(item: $pendingGitLabVariableSave, content: gitLabVariableSaveAlert)
            .alert(item: $pendingGitLabVariableDeletion, content: gitLabVariableDeletionAlert)
            .alert(item: $pendingGitLabGroupSave, content: gitLabGroupSaveAlert)
            .alert(item: $pendingGitLabMemberSave, content: gitLabMemberSaveAlert)
            .alert(item: $pendingGitLabMemberDeletion, content: gitLabMemberDeletionAlert)
            .alert(item: $pendingGiteaUserSave, content: giteaUserSaveAlert)
            .alert(item: $pendingGiteaUserDeletion, content: giteaUserDeletionAlert)
            .alert(item: $pendingGiteaOrganizationSave, content: giteaOrganizationSaveAlert)
            .alert(item: $pendingGiteaOrganizationDeletion, content: giteaOrganizationDeletionAlert)
            .alert(item: $pendingGiteaTeamSave, content: giteaTeamSaveAlert)
            .alert(item: $pendingGiteaTeamDeletion, content: giteaTeamDeletionAlert)
            .alert(item: $pendingGiteaTeamMemberSave, content: giteaTeamMemberSaveAlert)
            .alert(item: $pendingGiteaTeamMemberDeletion, content: giteaTeamMemberDeletionAlert)
            .alert(item: $pendingGiteaTeamRepositorySave, content: giteaTeamRepositorySaveAlert)
            .alert(item: $pendingGiteaTeamRepositoryDeletion, content: giteaTeamRepositoryDeletionAlert)
            .alert("添加 Gitea SSH Key?", isPresented: $pendingGiteaKeySave) {
                Button("添加") {
                    performGiteaKeySave()
                }
                Button(L10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text("This adds \(viewModel.giteaKeyDraft.trimmedTitle) to the current Gitea account. Only single-line OpenSSH public keys are accepted.")
            }
            .alert(item: $pendingGiteaKeyDeletion, content: giteaKeyDeletionAlert)
            .alert("创建 Gitea Access Token?", isPresented: $pendingGiteaAccessTokenSave) {
                Button("创建") {
                    performGiteaAccessTokenSave()
                }
                Button(L10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text("This creates \(viewModel.giteaAccessTokenDraft.trimmedName) for \(viewModel.giteaAccessTokenDraft.trimmedUsername) with scopes: \(viewModel.giteaAccessTokenDraft.scopes.joined(separator: ", ")). The token secret is shown only once.")
            }
            .alert(item: $viewModel.giteaAccessTokenCreationResult, content: giteaAccessTokenSecretAlert)
            .alert(item: $pendingGiteaAccessTokenDeletion, content: giteaAccessTokenDeletionAlert)
            .alert(item: $pendingGiteaPackageDeletion, content: giteaPackageDeletionAlert)
            .alert("添加 GitLab Deploy Key?", isPresented: $pendingGitLabDeployKeySave) {
                Button("添加") {
                    performGitLabDeployKeySave()
                }
                Button(L10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text("This adds \(viewModel.gitLabDeployKeyDraft.trimmedTitle) to project \(viewModel.gitLabDeployKeyDraft.projectId). can_push: \(viewModel.gitLabDeployKeyDraft.canPush ? "true" : "false").")
            }
            .alert(item: $pendingGitLabDeployKeyDeletion, content: gitLabDeployKeyDeletionAlert)
            .alert("创建 GitLab Deploy Token?", isPresented: $pendingGitLabDeployTokenSave) {
                Button("创建") {
                    performGitLabDeployTokenSave()
                }
                Button(L10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text("This creates \(viewModel.gitLabDeployTokenDraft.trimmedName) for project \(viewModel.gitLabDeployTokenDraft.projectId) with scopes: \(viewModel.gitLabDeployTokenDraft.selectedScopes.joined(separator: ", ")). The token secret is shown only once.")
            }
            .alert(item: $viewModel.gitLabDeployTokenCreationResult, content: gitLabDeployTokenSecretAlert)
            .alert(item: $pendingGitLabDeployTokenDeletion, content: gitLabDeployTokenDeletionAlert)
            .alert(item: $pendingGitLabPackageDeletion, content: gitLabPackageDeletionAlert)
            .alert("创建 GitLab Tag?", isPresented: $pendingGitLabTagSave) {
                Button("创建") {
                    performGitLabTagSave()
                }
                Button(L10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text("This creates tag \(viewModel.gitLabTagDraft.trimmedName) from ref \(viewModel.gitLabTagDraft.trimmedRef) in project \(viewModel.gitLabTagDraft.projectId).")
            }
            .alert(item: $pendingGitLabTagDeletion, content: gitLabTagDeletionAlert)
            .modifier(developmentServiceAlertsModifier)
            .modifier(remoteFileEditorSheetsModifier)
            .onAppear {
                viewModel.configure(profile: profile, initialState: appState.connectionState(for: profile))
                viewModel.loadCommandHistory(profile: profile, repository: appState.repository)
                viewModel.loadCachedDashboardSnapshot(profile: profile, repository: appState.repository)
                viewModel.loadRemoteFileTransferHistory(profile: profile, repository: appState.repository)
                viewModel.loadGitLabServiceInstance(profile: profile, repository: appState.repository)
            }
            .onDisappear {
                viewModel.stopDashboardAutoRefresh()
            }
            .onChange(of: viewModel.connectionState) { _, newState in
                appState.setConnectionState(newState, for: profile)
            }
    }

    private var workspaceSplitView: some View {
        NavigationSplitView {
            workspaceSidebar
        } detail: {
            workspaceDetail
        }
    }

    private var workspaceSidebar: some View {
        List(selection: $selectedSection) {
            Label(L10n.string("Overview"), systemImage: "gauge.with.dots.needle.67percent")
                .tag("overview")
            Label(L10n.string("Terminal"), systemImage: "terminal")
                .tag("terminal")
            Label(L10n.string("Files"), systemImage: "folder")
                .tag("files")
            Label(L10n.string("Services"), systemImage: "gearshape.2")
                .tag("services")
            Label("Docker", systemImage: "shippingbox")
                .tag("docker")
            Label("流量监控", systemImage: "chart.xyaxis.line")
                .tag("traffic")
            Label("数据库", systemImage: "cylinder.split.1x2")
                .tag("databases")
            Label("Nginx", systemImage: "network")
                .tag("nginx")
            Label(L10n.string("Firewall"), systemImage: "firewall")
                .tag("firewall")
            Label(L10n.string("Security Groups"), systemImage: "lock.shield")
                .tag("securityGroups")
            Label(L10n.string("Project Deployments"), systemImage: "arrow.down.doc")
                .tag("deployments")
            Label("Git", systemImage: "point.3.connected.trianglepath.dotted")
                .tag("devGit")
            Label("npm", systemImage: "shippingbox")
                .tag("devNpm")
            Label("pub", systemImage: "paperplane")
                .tag("devPub")
            Label(L10n.string("Audit"), systemImage: "list.bullet.rectangle")
                .tag("audit")
            Label(L10n.string("Environment"), systemImage: "slider.horizontal.3")
                .tag("environment")
            Label("Cron", systemImage: "calendar.badge.clock")
                .tag("cron")
            Label(L10n.string("Cloud"), systemImage: "cloud")
                .tag("cloud")
                .foregroundStyle(.secondary)
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
    }

    private var workspaceDetail: some View {
        VStack(spacing: 0) {
            workspaceToolbar
            Divider()
            detailContent
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case "terminal":
            commandPanel
        case "files":
            filesPanel
        case "services":
            servicesPanel
        case "docker":
            dockerPanel
        case "traffic":
            trafficPanel
        case "databases":
            databasesPanel
        case "nginx":
            nginxPanel
        case "firewall":
            firewallPanel
        case "securityGroups":
            securityGroupsPanel
        case "deployments":
            deploymentsPanel
        case "devGit", "devNpm", "devPub":
            developmentServicesPanel(defaultCategory: devServiceCategoryFromSection)
        case "audit":
            auditPanel
        case "environment":
            environmentPanel
        case "cron":
            cronPanel
        default:
            overview
        }
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 10) {
            Button {
                appState.closeWorkspace()
            } label: {
                Label(L10n.string("Servers"), systemImage: "chevron.left")
            }

            Picker(L10n.string("Current Server"), selection: currentServerBinding) {
                ForEach(appState.servers) { server in
                    Text(server.name).tag(server.id)
                }
            }
            .frame(maxWidth: 280)

            Spacer()
        }
        .padding(12)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.name)
                        .font(.title.weight(.semibold))
                    Text(profile.endpoint)
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text("Host").foregroundStyle(.secondary)
                        Text(profile.host)
                    }
                    GridRow {
                        Text("Port").foregroundStyle(.secondary)
                        Text("\(profile.port)")
                    }
                    GridRow {
                        Text("Username").foregroundStyle(.secondary)
                        Text(profile.username)
                    }
                    GridRow {
                        Text("Authentication").foregroundStyle(.secondary)
                        Text(profile.authType.displayName)
                    }
                    GridRow {
                        Text("Type").foregroundStyle(.secondary)
                        Text(profile.serverKind.displayName)
                    }
                }

                HStack(spacing: 10) {
                    connectionBadge

                    Button {
                        refreshOverviewData()
                    } label: {
                        if isOverviewRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("刷新总览", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isOverviewRefreshing)

                    Toggle(isOn: dashboardAutoRefreshBinding) {
                        Label(L10n.string("Auto"), systemImage: "timer")
                    }
                    .toggleStyle(.switch)
                    .disabled(viewModel.connectionState == .connecting)

                    Button {
                        viewModel.connect(profile: profile, sshClient: appState.sshClient)
                    } label: {
                        Label(L10n.string("Connect"), systemImage: "bolt.horizontal.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRunningSmokeTest || viewModel.connectionState == .connecting)

                    Button {
                        viewModel.disconnect()
                    } label: {
                        Label(L10n.string("Disconnect"), systemImage: "xmark.circle")
                    }
                    .disabled(viewModel.connectionState == .disconnected || viewModel.connectionState == .connecting)
                }

                Divider()

                dashboardPanel

                overviewServicePanel

                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if viewModel.dashboardSnapshot == nil ||
                viewModel.systemdUnitList == nil ||
                viewModel.databaseServiceSnapshot == nil ||
                viewModel.nginxConfigList == nil ||
                viewModel.dockerSnapshot == nil ||
                !viewModel.didLoadDeploymentProjects {
                refreshOverviewData()
            }
        }
    }

    private func refreshOverviewData() {
        viewModel.refreshDashboard(
            profile: profile,
            sshClient: appState.sshClient,
            dashboardService: appState.dashboardService,
            cloudMetricService: appState.cloudMetricService,
            repository: appState.repository
        )
        viewModel.loadSystemdUnits(
            profile: profile,
            sshClient: appState.sshClient,
            systemdServiceManager: appState.systemdServiceManager
        )
        viewModel.loadDatabaseServices(
            profile: profile,
            sshClient: appState.sshClient,
            databaseServiceManager: appState.databaseServiceManager
        )
        viewModel.loadNginxConfigs(
            profile: profile,
            sshClient: appState.sshClient,
            nginxConfigManager: appState.nginxConfigManager
        )
        viewModel.loadDockerSnapshot(
            profile: profile,
            sshClient: appState.sshClient,
            dockerManager: appState.dockerManager
        )
        viewModel.loadDeploymentProjectSummary(profile: profile, repository: appState.repository)
    }

    private var isOverviewRefreshing: Bool {
        viewModel.isRefreshingDashboard ||
            viewModel.isLoadingSystemdUnits ||
            viewModel.isLoadingDatabaseServices ||
            viewModel.isLoadingNginxConfigs ||
            viewModel.isLoadingDocker ||
            viewModel.isLoadingDeployments
    }

    private var dockerPanel: some View {
        DockerWorkspacePanel(
            viewModel: viewModel,
            profile: profile,
            appState: appState,
            pendingAction: $pendingDockerAction
        )
    }

    private var dashboardPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.string("Dashboard"))
                    .font(.title2.weight(.semibold))
                Spacer()
                if let capturedAt = viewModel.dashboardSnapshot?.capturedAt {
                    Text(capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.dashboardErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if let snapshot = viewModel.dashboardSnapshot {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(dashboardResourceCards(snapshot)) { card in
                        DashboardResourceRingCard(card: card)
                    }
                }

                if !snapshot.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snapshot.warnings) { warning in
                            Label("\(L10n.string(warning.source)): \(L10n.string(warning.message))", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    DashboardTrendPanel(snapshots: viewModel.dashboardSnapshots)
                        .frame(minWidth: 360)

                    DashboardSystemInfoPanel(
                        profile: profile,
                        snapshot: snapshot,
                        extraCapabilities: overviewRuntimeCapabilities
                    )
                    .frame(minWidth: 280, maxWidth: 360)
                }

                DashboardMetricsTable(metrics: snapshot.metrics)
            } else {
                ContentUnavailableView(
                    L10n.string("No Dashboard Snapshot"),
                    systemImage: "gauge.with.dots.needle.67percent",
                    description: Text(L10n.string("Refresh the dashboard to collect SSH metrics and server capabilities."))
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }

    private func dashboardResourceCards(_ snapshot: ServerDashboardSnapshot) -> [DashboardResourceCard] {
        let loadMetric = metric(named: "Load Average", in: snapshot)
        let cpuMetric = metric(named: "CPU Cores", in: snapshot)
        let memoryMetric = metric(named: "Memory", in: snapshot)
        let diskMetric = metric(named: "Root Disk", in: snapshot)
        let cpuCores = DashboardMetricParser.cpuCores(from: cpuMetric?.value) ?? 1
        let load = DashboardMetricParser.loadAverage(from: loadMetric?.value)
        let loadPercent = min(max((load.first ?? 0) / Double(max(cpuCores, 1)), 0), 1)
        let memoryUsage = DashboardMetricParser.usagePair(from: memoryMetric?.value)
        let diskUsage = DashboardMetricParser.usagePair(from: diskMetric?.value)

        return [
            DashboardResourceCard(
                title: L10n.string("Load Average"),
                value: loadMetric?.value ?? "--",
                subtitle: loadPercent < 0.7 ? "运行流畅" : "负载偏高",
                fraction: loadPercent,
                tint: loadPercent < 0.7 ? .green : .orange,
                systemImage: "speedometer"
            ),
            DashboardResourceCard(
                title: "CPU",
                value: "\(cpuCores) 核心",
                subtitle: "在线核心数",
                fraction: loadPercent,
                tint: .blue,
                systemImage: "cpu"
            ),
            DashboardResourceCard(
                title: L10n.string("Memory"),
                value: memoryMetric?.value ?? "--",
                subtitle: memoryUsage.map { "\(Int(($0.fraction * 100).rounded()))% 已用" } ?? "暂无数据",
                fraction: memoryUsage?.fraction ?? 0,
                tint: .green,
                systemImage: "memorychip"
            ),
            DashboardResourceCard(
                title: L10n.string("Root Disk"),
                value: diskMetric?.value ?? "--",
                subtitle: diskUsage.map { "\(Int(($0.fraction * 100).rounded()))% 已用" } ?? "暂无数据",
                fraction: diskUsage?.fraction ?? 0,
                tint: (diskUsage?.fraction ?? 0) > 0.85 ? .orange : .green,
                systemImage: "internaldrive"
            ),
        ]
    }

    private func metric(named name: String, in snapshot: ServerDashboardSnapshot) -> DashboardMetric? {
        snapshot.metrics.first { $0.name == name }
    }

    private var overviewServicePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("服务概览")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("systemd / 网站 / 数据库")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(overviewServiceCards) { card in
                    Button {
                        selectedSection = card.targetSection
                    } label: {
                        OverviewServiceCardView(card: card)
                    }
                    .buttonStyle(.plain)
                    .help("打开\(card.title)")
                }
            }

            let risks = overviewRiskItems
            if !risks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("风险提示")
                        .font(.headline)
                    ForEach(risks) { item in
                        Label(item.message, systemImage: item.systemImage)
                            .font(.caption)
                            .foregroundStyle(item.color)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var overviewServiceCards: [OverviewServiceCard] {
        let units = viewModel.systemdUnitList?.units ?? []
        let runningUnits = units.filter(\.isRunning).count
        let failedUnits = units.filter { $0.activeState == "failed" || $0.subState == "failed" }.count
        let installedDatabases = viewModel.databaseServiceSnapshot?.services.filter(\.isInstalled) ?? []
        let runningDatabases = installedDatabases.filter(\.isRunning).count
        let sites = viewModel.nginxSiteList?.sites ?? []
        let sslSites = sites.filter(\.hasSSL).count
        let dockerSnapshot = viewModel.dockerSnapshot
        let dockerContainers = dockerSnapshot?.containers ?? []

        return [
            OverviewServiceCard(
                title: "systemd 服务",
                value: units.isEmpty ? "--" : "\(runningUnits)/\(units.count)",
                subtitle: failedUnits > 0 ? "\(failedUnits) 个失败" : "运行中 / 总数",
                systemImage: "gearshape.2",
                tint: failedUnits > 0 ? .orange : .green,
                targetSection: "services"
            ),
            OverviewServiceCard(
                title: "网站",
                value: sites.isEmpty ? "--" : "\(sites.count)",
                subtitle: sites.isEmpty ? "未发现 Nginx 站点" : "\(sslSites) 个 SSL",
                systemImage: "globe",
                tint: sites.isEmpty ? .secondary : .blue,
                targetSection: "nginx"
            ),
            OverviewServiceCard(
                title: "数据库",
                value: installedDatabases.isEmpty ? "--" : "\(runningDatabases)/\(installedDatabases.count)",
                subtitle: installedDatabases.isEmpty ? "未发现数据库服务" : "运行中 / 已安装",
                systemImage: "cylinder.split.1x2",
                tint: runningDatabases == installedDatabases.count ? .green : .orange,
                targetSection: "databases"
            ),
            OverviewServiceCard(
                title: "部署项目",
                value: viewModel.deploymentProjects.isEmpty ? "--" : "\(viewModel.deploymentProjects.count)",
                subtitle: "Git 项目配置",
                systemImage: "arrow.down.doc",
                tint: viewModel.deploymentProjects.isEmpty ? .secondary : .purple,
                targetSection: "deployments"
            ),
            OverviewServiceCard(
                title: "Docker",
                value: dockerSnapshot?.isAvailable == true ? "\(dockerSnapshot?.runningContainerCount ?? 0)/\(dockerContainers.count)" : "--",
                subtitle: dockerSnapshot?.isAvailable == true ? "运行中 / 容器总数" : (dockerSnapshot?.unavailableReason ?? "未探测"),
                systemImage: "shippingbox",
                tint: dockerSnapshot?.isAvailable == true ? .blue : .secondary,
                targetSection: "docker"
            ),
        ]
    }

    private var overviewRuntimeCapabilities: [RuntimeCapabilityBadge] {
        let databaseServices = viewModel.databaseServiceSnapshot?.services ?? []
        return [
            RuntimeCapabilityBadge(title: "nginx", enabled: viewModel.nginxConfigList != nil),
            RuntimeCapabilityBadge(title: "mysql", enabled: databaseServices.contains { $0.kind == .mysql && $0.isInstalled }),
            RuntimeCapabilityBadge(title: "mariadb", enabled: databaseServices.contains { $0.kind == .mariadb && $0.isInstalled }),
            RuntimeCapabilityBadge(title: "postgres", enabled: databaseServices.contains { $0.kind == .postgresql && $0.isInstalled }),
            RuntimeCapabilityBadge(title: "redis", enabled: databaseServices.contains { $0.kind == .redis && $0.isInstalled }),
            RuntimeCapabilityBadge(title: "docker", enabled: viewModel.dockerSnapshot?.isAvailable == true),
        ]
    }

    private var overviewRiskItems: [OverviewRiskItem] {
        var items: [OverviewRiskItem] = []

        if let snapshot = viewModel.dashboardSnapshot {
            if let memory = DashboardMetricParser.usagePair(from: metric(named: "Memory", in: snapshot)?.value),
               memory.fraction >= 0.85 {
                items.append(OverviewRiskItem(message: "内存使用率已超过 85%。", color: .orange))
            }
            if let disk = DashboardMetricParser.usagePair(from: metric(named: "Root Disk", in: snapshot)?.value),
               disk.fraction >= 0.85 {
                items.append(OverviewRiskItem(message: "根分区磁盘使用率已超过 85%。", color: .orange))
            }
            items.append(contentsOf: snapshot.warnings.map {
                OverviewRiskItem(message: "\($0.source): \($0.message)", color: .orange)
            })
        }

        let failedUnits = (viewModel.systemdUnitList?.units ?? []).filter {
            $0.activeState == "failed" || $0.subState == "failed"
        }
        if !failedUnits.isEmpty {
            items.append(OverviewRiskItem(
                message: "\(failedUnits.count) 个 systemd 服务处于失败状态。",
                color: .orange,
                systemImage: "exclamationmark.triangle"
            ))
        }

        let stoppedDatabases = (viewModel.databaseServiceSnapshot?.services ?? []).filter {
            $0.isInstalled && !$0.isRunning
        }
        if !stoppedDatabases.isEmpty {
            items.append(OverviewRiskItem(
                message: "\(stoppedDatabases.map { $0.kind.displayName }.joined(separator: ", ")) 数据库服务未运行。",
                color: .orange,
                systemImage: "cylinder.split.1x2"
            ))
        }

        if viewModel.nginxTestResult?.succeeded == false {
            items.append(OverviewRiskItem(
                message: "Nginx 配置测试失败，reload 前需要修复配置。",
                color: .red,
                systemImage: "xmark.octagon"
            ))
        }

        if viewModel.nginxSiteList?.sites.isEmpty == true {
            items.append(OverviewRiskItem(
                message: "未从 Nginx 配置中识别到站点。",
                color: .secondary,
                systemImage: "network"
            ))
        }

        return items
    }

    private var trafficPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("流量监控")
                            .font(.title2.weight(.semibold))
                        Text("基于 SSH 采集的 /proc/net/dev 累计流量，连续快照会计算实时上下行。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isOverviewRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        refreshOverviewData()
                    } label: {
                        Label("刷新流量", systemImage: "arrow.clockwise")
                    }
                    .disabled(isOverviewRefreshing)
                }

                if let latest = trafficLatestPoint {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                        TrafficSummaryCard(
                            title: "实时上行",
                            value: formatTrafficRate(latest.uploadRate),
                            subtitle: "TX 速率",
                            systemImage: "arrow.up.circle",
                            tint: .green
                        )
                        TrafficSummaryCard(
                            title: "实时下行",
                            value: formatTrafficRate(latest.downloadRate),
                            subtitle: "RX 速率",
                            systemImage: "arrow.down.circle",
                            tint: .orange
                        )
                        TrafficSummaryCard(
                            title: "累计接收",
                            value: formatTrafficBytes(latest.receivedBytes),
                            subtitle: activeNetworkInterfaceLabel,
                            systemImage: "tray.and.arrow.down",
                            tint: .blue
                        )
                        TrafficSummaryCard(
                            title: "累计发送",
                            value: formatTrafficBytes(latest.transmittedBytes),
                            subtitle: latest.capturedAt.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "tray.and.arrow.up",
                            tint: .purple
                        )
                        TrafficSummaryCard(
                            title: "活跃网卡",
                            value: activeNetworkInterfaceName,
                            subtitle: "按累计收发量选择",
                            systemImage: "network",
                            tint: .teal
                        )
                    }

                    if !trafficRiskItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("异常提示")
                                .font(.headline)
                            ForEach(trafficRiskItems) { item in
                                Label(item.message, systemImage: item.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(item.color)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    TrafficTrendPanel(points: trafficPoints)
                    TrafficInterfaceOverviewPanel(summary: trafficInterfaceSummary)
                    TrafficInterfaceTable(
                        interfaces: trafficInterfaceUsages,
                        summary: trafficInterfaceSummary
                    )
                    TrafficHistoryTable(points: trafficPoints)
                } else {
                    ContentUnavailableView(
                        "暂无流量数据",
                        systemImage: "chart.xyaxis.line",
                        description: Text("点击刷新后会采集服务器网卡累计收发量。连续采样后显示上下行速率。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if viewModel.dashboardSnapshot == nil {
                refreshOverviewData()
            }
        }
    }

    private var trafficPoints: [TrafficSnapshotPoint] {
        viewModel.dashboardSnapshots.compactMap { snapshot in
            guard let network = metric(named: "Network", in: snapshot),
                  let bytes = DashboardMetricParser.bytePair(from: network.value)
            else { return nil }
            return TrafficSnapshotPoint(
                capturedAt: snapshot.capturedAt,
                receivedBytes: bytes.received,
                transmittedBytes: bytes.transmitted,
                interfaceName: activeNetworkInterfaceName(in: snapshot)
            )
        }
        .withRates()
    }

    private var trafficLatestPoint: TrafficSnapshotPoint? {
        trafficPoints.last
    }

    private var trafficInterfaceUsages: [NetworkInterfaceTrafficUsage] {
        guard let snapshot = viewModel.dashboardSnapshots.last,
              let value = metric(named: "Network Interfaces", in: snapshot)?.value
        else { return [] }
        return NetworkTrafficInspector.parseInterfaceBreakdown(value)
    }

    private var trafficInterfaceSummary: NetworkTrafficSummary {
        NetworkTrafficInspector.summary(for: trafficInterfaceUsages)
    }

    private var trafficRiskItems: [OverviewRiskItem] {
        guard let latest = trafficLatestPoint else { return [] }
        var items: [OverviewRiskItem] = []
        let highRateThreshold = 5 * 1024 * 1024.0
        if latest.downloadRate >= highRateThreshold {
            items.append(OverviewRiskItem(
                message: "下行流量超过 5 MiB/s，建议检查下载任务或异常访问。",
                color: .orange,
                systemImage: "arrow.down.circle"
            ))
        }
        if latest.uploadRate >= highRateThreshold {
            items.append(OverviewRiskItem(
                message: "上行流量超过 5 MiB/s，建议检查备份、同步或外发流量。",
                color: .orange,
                systemImage: "arrow.up.circle"
            ))
        }
        if trafficPoints.count < 2 {
            items.append(OverviewRiskItem(
                message: "需要至少两次采样才能计算实时速率。",
                color: .secondary,
                systemImage: "timer"
            ))
        }
        for message in NetworkTrafficInspector.attentionMessages(for: trafficInterfaceSummary) {
            items.append(OverviewRiskItem(
                message: message,
                color: .orange,
                systemImage: "network.badge.shield.half.filled"
            ))
        }
        return items
    }

    private var activeNetworkInterfaceName: String {
        trafficLatestPoint?.interfaceName ?? "--"
    }

    private var activeNetworkInterfaceLabel: String {
        activeNetworkInterfaceName == "--" ? "非 lo 网卡合计" : "活跃网卡 \(activeNetworkInterfaceName)"
    }

    private func activeNetworkInterfaceName(in snapshot: ServerDashboardSnapshot) -> String? {
        guard let value = metric(named: "Active Network Interface", in: snapshot)?.value else {
            return nil
        }
        return value.split(separator: " ").first.map(String.init)
    }

    private func formatTrafficBytes(_ bytes: Double) -> String {
        TrafficFormatter.bytes(bytes)
    }

    private func formatTrafficRate(_ bytesPerSecond: Double) -> String {
        "\(TrafficFormatter.bytes(bytesPerSecond))/s"
    }

    private func capabilityPanel(_ capabilities: ServerCapabilities) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            if let osName = capabilities.osName {
                GridRow {
                    Text(L10n.string("OS")).foregroundStyle(.secondary)
                    Text(osName)
                }
            }
            if let kernelVersion = capabilities.kernelVersion {
                GridRow {
                    Text(L10n.string("Kernel")).foregroundStyle(.secondary)
                    Text(kernelVersion)
                }
            }
            GridRow {
                Text(L10n.string("Capabilities")).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    CapabilityBadge(title: "/proc", enabled: capabilities.hasProc)
                    CapabilityBadge(title: "systemd", enabled: capabilities.hasSystemd)
                    CapabilityBadge(title: "sftp", enabled: capabilities.hasSFTP)
                }
            }
        }
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Terminal")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 8) {
                    TextField("Run a single command", text: $commandText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            runCommand()
                        }

                    Button {
                        runCommand()
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRunningCommand || commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        viewModel.cancelCommand()
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .disabled(!viewModel.isRunningCommand)
                }

                terminalSessionOverview

                HStack(spacing: 8) {
                    quickCommandButton("uptime")
                    quickCommandButton("whoami")
                    quickCommandButton("df -h")
                    quickCommandButton("free -h")
                }

                terminalSnippetPanel
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.commandHistory.isEmpty &&
                        viewModel.persistedCommandHistory.isEmpty &&
                        viewModel.lastCommandFailure == nil {
                        ContentUnavailableView(
                            "No Commands Yet",
                            systemImage: "terminal",
                            description: Text("Run a command to see stdout, stderr, exit code, and duration.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        if let failure = viewModel.lastCommandFailure {
                            CommandFailureView(failure: failure)
                        }

                        ForEach(Array(viewModel.commandHistory.enumerated()), id: \.offset) { _, result in
                            CommandResultView(result: result)
                        }
                    }

                    if !viewModel.persistedCommandHistory.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                        persistedHistorySection
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var terminalSessionOverview: some View {
        let summary = CommandHistoryInspector.summary(for: viewModel.persistedCommandHistory)
        let averageDuration = summary.averageDuration.map { String(format: "%.2fs", $0) } ?? "--"
        let lastRun = summary.lastRunAt?.formatted(date: .abbreviated, time: .shortened) ?? "None"

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], alignment: .leading, spacing: 10) {
            terminalOverviewCard(title: "历史命令", value: "\(summary.total)", detail: "saved metadata", icon: "clock.arrow.circlepath", color: .blue)
            terminalOverviewCard(title: "成功", value: "\(summary.succeeded)", detail: "exit 0", icon: "checkmark.circle", color: .green)
            terminalOverviewCard(title: "失败", value: "\(summary.failed)", detail: "non-zero/error", icon: "xmark.octagon", color: summary.failed > 0 ? .red : .secondary)
            terminalOverviewCard(title: "平均耗时", value: averageDuration, detail: "recorded runs", icon: "timer", color: .purple)
            terminalOverviewCard(title: "最近执行", value: lastRun, detail: viewModel.isRunningCommand ? "running" : "idle", icon: "terminal", color: viewModel.isRunningCommand ? .orange : .secondary)
        }
    }

    private func terminalOverviewCard(title: String, value: String, detail: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var terminalSnippetPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Command Snippets")
                    .font(.headline)
                Spacer()
                Picker("Category", selection: $terminalSnippetCategory) {
                    ForEach(TerminalCommandCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 520)
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 220), spacing: 10),
            ], spacing: 10) {
                ForEach(terminalCommandSnippets.filter { $0.category == terminalSnippetCategory }) { snippet in
                    TerminalCommandSnippetButton(snippet: snippet) {
                        commandText = snippet.command
                    }
                }
            }
        }
    }

    private var terminalCommandSnippets: [TerminalCommandSnippet] {
        [
            TerminalCommandSnippet(category: .system, title: "Load & uptime", command: "uptime", systemImage: "speedometer"),
            TerminalCommandSnippet(category: .system, title: "CPU cores", command: "getconf _NPROCESSORS_ONLN || nproc", systemImage: "cpu"),
            TerminalCommandSnippet(category: .system, title: "Memory usage", command: "free -h", systemImage: "memorychip"),
            TerminalCommandSnippet(category: .system, title: "Disk usage", command: "df -h", systemImage: "internaldrive"),
            TerminalCommandSnippet(category: .system, title: "Top processes", command: "ps aux --sort=-%mem | head -20", systemImage: "list.number"),
            TerminalCommandSnippet(category: .logs, title: "Kernel errors", command: "dmesg --level=err,warn | tail -80", systemImage: "exclamationmark.triangle"),
            TerminalCommandSnippet(category: .logs, title: "System journal", command: "journalctl -n 100 --no-pager", systemImage: "doc.text.magnifyingglass"),
            TerminalCommandSnippet(category: .logs, title: "Failed units", command: "systemctl --failed --no-pager", systemImage: "xmark.octagon"),
            TerminalCommandSnippet(category: .logs, title: "Auth log", command: "tail -100 /var/log/auth.log 2>/dev/null || tail -100 /var/log/secure", systemImage: "lock.doc"),
            TerminalCommandSnippet(category: .network, title: "Listening ports", command: "ss -tulpen", systemImage: "network"),
            TerminalCommandSnippet(category: .network, title: "Network totals", command: "cat /proc/net/dev", systemImage: "chart.xyaxis.line"),
            TerminalCommandSnippet(category: .network, title: "Public IP", command: "curl -4 ifconfig.me || curl -4 ipinfo.io/ip", systemImage: "globe"),
            TerminalCommandSnippet(category: .network, title: "Firewall status", command: "ufw status verbose 2>/dev/null || firewall-cmd --state && firewall-cmd --list-all", systemImage: "firewall"),
            TerminalCommandSnippet(category: .services, title: "Nginx status", command: "systemctl status nginx --no-pager", systemImage: "network"),
            TerminalCommandSnippet(category: .services, title: "Nginx test", command: "nginx -t", systemImage: "checkmark.seal"),
            TerminalCommandSnippet(category: .services, title: "MySQL status", command: "systemctl status mysql --no-pager || systemctl status mysqld --no-pager", systemImage: "cylinder.split.1x2"),
            TerminalCommandSnippet(category: .services, title: "Redis status", command: "systemctl status redis --no-pager || systemctl status redis-server --no-pager", systemImage: "bolt.horizontal"),
            TerminalCommandSnippet(category: .docker, title: "Docker version", command: "docker version", systemImage: "shippingbox"),
            TerminalCommandSnippet(category: .docker, title: "Containers", command: "docker ps -a --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}'", systemImage: "square.stack.3d.up"),
            TerminalCommandSnippet(category: .docker, title: "Images", command: "docker images", systemImage: "photo.stack"),
            TerminalCommandSnippet(category: .docker, title: "Docker disk usage", command: "docker system df", systemImage: "externaldrive"),
        ]
    }

    private var deploymentsPanel: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.string("Project Deployments"))
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        viewModel.startNewDeploymentProject(serverId: profile.id)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(L10n.string("New deployment project"))
                }

                if viewModel.deploymentProjects.isEmpty {
                    ContentUnavailableView(
                        L10n.string("No Deployment Projects"),
                        systemImage: "arrow.down.doc",
                        description: Text(L10n.string("Create a project to deploy a Git repository over SSH. This is for app releases, not GitLab server installation."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    List(selection: deploymentProjectSelectionBinding) {
                        ForEach(viewModel.deploymentProjects) { project in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name)
                                    .font(.headline)
                                Text("\(project.branch) -> \(project.deployPath)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, 4)
                            .tag(Optional(project.id))
                        }
                    }
                    .listStyle(.sidebar)
                }

                if let message = viewModel.deploymentActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if let error = viewModel.deploymentErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(20)
            .frame(minWidth: 260, idealWidth: 300)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    deploymentServiceOverview
                    Divider()
                    deploymentProjectForm
                    Divider()
                    deploymentCommandPreview
                    Divider()
                    deploymentRunHistory
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            viewModel.loadDeploymentProjects(profile: profile, repository: appState.repository)
            if viewModel.systemdUnitList == nil && !viewModel.isLoadingSystemdUnits {
                viewModel.loadSystemdUnits(
                    profile: profile,
                    sshClient: appState.sshClient,
                    systemdServiceManager: appState.systemdServiceManager
                )
            }
        }
    }

    private var deploymentServiceOverview: some View {
        let links = deploymentServiceLinks()
        let runningCount = links.filter { $0.unit?.isRunning == true }.count
        let unhealthyCount = links.filter { link in
            guard let unit = link.unit else { return true }
            return !unit.isRunning
        }.count

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("项目/服务概览")
                        .font(.title3.weight(.semibold))
                    Text("从部署项目的 restart 命令识别 systemd 服务，直接查看运行状态并执行常用操作。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.loadSystemdUnits(
                        profile: profile,
                        sshClient: appState.sshClient,
                        systemdServiceManager: appState.systemdServiceManager
                    )
                } label: {
                    if viewModel.isLoadingSystemdUnits {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("刷新服务", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isSystemdBusy)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                DeploymentServiceMetricCard(title: "部署项目", value: "\(viewModel.deploymentProjects.count)", subtitle: "本服务器", systemImage: "arrow.down.doc", tint: .purple)
                DeploymentServiceMetricCard(title: "关联服务", value: "\(links.count)", subtitle: "由 restart 命令识别", systemImage: "gearshape.2", tint: .blue)
                DeploymentServiceMetricCard(title: "运行中", value: "\(runningCount)", subtitle: "systemd active", systemImage: "checkmark.circle", tint: .green)
                DeploymentServiceMetricCard(title: "需关注", value: "\(unhealthyCount)", subtitle: "未运行或未刷新", systemImage: "exclamationmark.triangle", tint: unhealthyCount > 0 ? .orange : .secondary)
            }

            if links.isEmpty {
                ContentUnavailableView(
                    "暂无关联服务",
                    systemImage: "link",
                    description: Text("在项目的 Restart 字段里使用 systemctl restart app.service 后，这里会显示服务状态。")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        deploymentServiceHeader("项目")
                        deploymentServiceHeader("服务")
                        deploymentServiceHeader("状态")
                            .frame(width: 150, alignment: .leading)
                        deploymentServiceHeader("操作")
                            .frame(width: 170, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)

                    Divider()

                    ForEach(links) { link in
                        deploymentServiceLinkRow(link)
                        Divider()
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func deploymentServiceLinks() -> [DeploymentServiceLink] {
        let units = viewModel.systemdUnitList?.units ?? []
        return viewModel.deploymentProjects.flatMap { project in
            project.referencedSystemdUnitNames.map { unitName in
                DeploymentServiceLink(
                    project: project,
                    unitName: unitName,
                    unit: units.first { $0.name == unitName }
                )
            }
        }
    }

    private func deploymentServiceHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deploymentServiceLinkRow(_ link: DeploymentServiceLink) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(link.project.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(link.project.branch) -> \(link.project.deployPath)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(link.unitName)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                Text(link.unit.map { $0.description.isEmpty ? "未刷新或未发现" : $0.description } ?? "未刷新或未发现")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if let unit = link.unit {
                    SystemdStateBadge(unit: unit)
                } else {
                    Text("未知")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
            }
            .frame(width: 150, alignment: .leading)

            HStack(spacing: 6) {
                if let unit = link.unit {
                    Button {
                        viewModel.selectSystemdUnit(
                            unit,
                            profile: profile,
                            sshClient: appState.sshClient,
                            systemdServiceManager: appState.systemdServiceManager
                        )
                        selectedSection = "services"
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .frame(width: 24, height: 24)
                    }
                    .help("打开服务详情")
                    .disabled(isSystemdBusy)

                    serviceIconButton(.start, unit: unit)
                    serviceIconButton(.stop, unit: unit)
                    serviceIconButton(.restart, unit: unit)
                } else {
                    Button {
                        viewModel.loadSystemdUnits(
                            profile: profile,
                            sshClient: appState.sshClient,
                            systemdServiceManager: appState.systemdServiceManager
                        )
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(isSystemdBusy)
                }
            }
            .frame(width: 170, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var auditPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Audit")
                            .font(.title2.weight(.semibold))
                        Text("Recent writes and local operations for \(profile.name).")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.copyAuditLogsReportToPasteboard(profile: profile)
                    } label: {
                        Label("Copy Markdown", systemImage: "doc.on.doc")
                    }
                    .disabled(viewModel.remoteChangeLogs.isEmpty && viewModel.operationLogs.isEmpty)
                    Button {
                        viewModel.loadAuditLogs(profile: profile, repository: appState.repository)
                    } label: {
                        if viewModel.isLoadingAuditLogs {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoadingAuditLogs)
                }

                if let error = viewModel.auditLogErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }

                if let message = viewModel.auditLogActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }

                auditSummaryGrid
                auditFilterBar
                auditRemoteChangesSection
                auditOperationLogsSection
            }
            .padding(24)
        }
        .onAppear {
            viewModel.loadAuditLogs(profile: profile, repository: appState.repository)
        }
    }

    private var auditRemoteChangesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remote Change Logs")
                .font(.headline)
            if filteredRemoteChangeLogs.isEmpty {
                ContentUnavailableView(
                    "No Remote Changes",
                    systemImage: "list.bullet.rectangle",
                    description: Text(viewModel.remoteChangeLogs.isEmpty ? "Write actions for this server will appear here after they run." : "No remote changes match the current filters.")
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredRemoteChangeLogs) { entry in
                        auditRemoteChangeRow(entry)
                    }
                }
            }
        }
    }

    private var auditOperationLogsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Operation Logs")
                .font(.headline)
            if filteredOperationLogs.isEmpty {
                ContentUnavailableView(
                    "No Operations",
                    systemImage: "clock.badge.questionmark",
                    description: Text(viewModel.operationLogs.isEmpty ? "Local command and webhook operations will appear here." : "No operations match the current filters.")
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredOperationLogs) { entry in
                        auditOperationLogRow(entry)
                    }
                }
            }
        }
    }

    private var auditSummaryGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            auditSummaryCard("Remote Writes", value: "\(viewModel.remoteChangeLogs.count)", systemImage: "externaldrive.badge.checkmark")
            auditSummaryCard("Local Ops", value: "\(viewModel.operationLogs.count)", systemImage: "macwindow.badge.plus")
            auditSummaryCard("Failed", value: "\(auditFailureCount)", systemImage: "exclamationmark.triangle")
            auditSummaryCard("Latest", value: auditLatestTimeText, systemImage: "clock")
        }
    }

    private func auditSummaryCard(_ title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 66)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var auditFilterBar: some View {
        HStack(spacing: 10) {
            TextField("Search target, action, message", text: $auditSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)

            Picker("Status", selection: $auditStatusFilter) {
                Text("All Status").tag("all")
                ForEach(auditStatuses, id: \.self) { status in
                    Text(status).tag(status)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Picker("Target", selection: $auditTargetFilter) {
                Text("All Targets").tag("all")
                ForEach(auditTargetTypes, id: \.self) { targetType in
                    Text(targetType).tag(targetType)
                }
            }
            .labelsHidden()
            .frame(width: 180)

            Toggle("Snapshots", isOn: $auditShowsSnapshots)
                .toggleStyle(.checkbox)

            Spacer()

            if hasAuditFilters {
                Button {
                    auditSearchText = ""
                    auditStatusFilter = "all"
                    auditTargetFilter = "all"
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
            }
        }
    }

    private func auditRemoteChangeRow(_ entry: RemoteChangeLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.targetType) · \(entry.action)")
                    .font(.headline)
                Spacer()
                auditStatusBadge(entry.status)
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let targetId = entry.targetId, !targetId.isEmpty {
                Text(targetId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let message = entry.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            if auditShowsSnapshots {
                HStack(alignment: .top, spacing: 10) {
                    auditSnapshotView(title: "Before", value: entry.beforeSnapshot)
                    auditSnapshotView(title: "After", value: entry.afterSnapshot)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func auditOperationLogRow(_ entry: OperationLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.scope) · \(entry.action)")
                    .font(.headline)
                Spacer()
                auditStatusBadge(entry.status)
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let targetId = entry.targetId, !targetId.isEmpty {
                Text(targetId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let message = entry.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func auditSnapshotView(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value?.isEmpty == false ? value ?? "" : "No snapshot")
                .font(.caption.monospaced())
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func auditStatusBadge(_ status: String) -> some View {
        Text(status)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(auditStatusColor(status).opacity(0.16), in: Capsule())
            .foregroundStyle(auditStatusColor(status))
    }

    private func auditStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "success", "succeeded":
            .green
        case "failed", "failure":
            .red
        case "cancelled", "canceled":
            .orange
        default:
            .secondary
        }
    }

    private var filteredRemoteChangeLogs: [RemoteChangeLogEntry] {
        viewModel.remoteChangeLogs.filter { entry in
            auditMatchesStatus(entry.status) &&
            auditMatchesTarget(entry.targetType) &&
            auditMatchesSearch([
                entry.targetType,
                entry.targetId ?? "",
                entry.action,
                entry.status,
                entry.providerId?.displayName ?? "",
                entry.message ?? "",
                entry.beforeSnapshot ?? "",
                entry.afterSnapshot ?? "",
            ])
        }
    }

    private var filteredOperationLogs: [OperationLogEntry] {
        viewModel.operationLogs.filter { entry in
            auditMatchesStatus(entry.status) &&
            auditMatchesSearch([
                entry.scope,
                entry.action,
                entry.targetId ?? "",
                entry.status,
                entry.message ?? "",
            ])
        }
    }

    private var auditStatuses: [String] {
        Array(Set((viewModel.remoteChangeLogs.map(\.status) + viewModel.operationLogs.map(\.status)).filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var auditTargetTypes: [String] {
        Array(Set(viewModel.remoteChangeLogs.map(\.targetType).filter { !$0.isEmpty }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var auditFailureCount: Int {
        viewModel.remoteChangeLogs.filter { auditIsFailure($0.status) }.count +
        viewModel.operationLogs.filter { auditIsFailure($0.status) }.count
    }

    private var auditLatestTimeText: String {
        let latest = (viewModel.remoteChangeLogs.map(\.createdAt) + viewModel.operationLogs.map(\.createdAt)).max()
        return latest?.formatted(date: .omitted, time: .shortened) ?? "-"
    }

    private var hasAuditFilters: Bool {
        !auditSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        auditStatusFilter != "all" ||
        auditTargetFilter != "all"
    }

    private func auditMatchesStatus(_ status: String) -> Bool {
        auditStatusFilter == "all" || status == auditStatusFilter
    }

    private func auditMatchesTarget(_ targetType: String) -> Bool {
        auditTargetFilter == "all" || targetType == auditTargetFilter
    }

    private func auditMatchesSearch(_ values: [String]) -> Bool {
        let query = auditSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return values.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func auditIsFailure(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized == "failed" || normalized == "failure" || normalized.contains("error")
    }

    private func developmentServicesPanel(defaultCategory: DevelopmentServiceCategory) -> some View {
        VStack(spacing: 0) {
            developmentServicesHeader(defaultCategory: defaultCategory)
            Divider()

            developmentServiceContent
        }
        .onAppear {
            developmentServiceCategory = defaultCategory
            viewModel.loadGitLabServiceInstance(profile: profile, repository: appState.repository)
            viewModel.loadGitNativeTokenState(profile: profile, keychain: appState.keychain)
        }
    }

    private var devServiceCategoryFromSection: DevelopmentServiceCategory {
        switch selectedSection {
        case "devNpm": .npm
        case "devPub": .pub
        default: .git
        }
    }

    @ViewBuilder
    private var developmentServiceContent: some View {
        if developmentServiceCategory == .git {
            gitNativeWorkbenchPanel
        } else if developmentServiceCategory == .npm {
            npmNativeWorkbenchPanel
        } else {
            pubNativeWorkbenchPanel
        }
    }

    private func developmentServicesHeader(defaultCategory: DevelopmentServiceCategory) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(defaultCategory.title)
                    .font(.title2.weight(.semibold))
                Text(defaultCategory.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var gitNativeWorkbenchPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                gitServiceSegmentedPicker

                gitPageContent
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var gitPageContent: some View {
        if activeGitPageState == .notInstalled {
            gitInstallWizard
        } else {
            gitManagementPanel
        }
    }

    private var gitServiceSegmentedPicker: some View {
        HStack(alignment: .firstTextBaseline) {
            Picker("Git 服务", selection: $selectedGitWorkbenchService) {
                ForEach(GitWorkbenchService.allCases) { service in
                    Label(service.title, systemImage: service.systemImage)
                        .tag(service)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Spacer()

            Text(gitServiceStateTitle(selectedGitWorkbenchService))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(gitServiceStateColor(selectedGitWorkbenchService).opacity(0.16), in: Capsule())
                .foregroundStyle(gitServiceStateColor(selectedGitWorkbenchService))
        }
    }

    // MARK: - Git Install Wizard (pre-install)

    @ViewBuilder
    private var gitInstallWizard: some View {
        switch selectedGitWorkbenchService {
        case .gitea:
            giteaInstallWizard
        case .gitLab:
            gitLabInstallWizard
        }
    }

    private var giteaInstallWizard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isInstallingGitea && !viewModel.giteaInstallSteps.isEmpty {
                InstallProgressView(steps: viewModel.giteaInstallSteps, title: "正在安装 Gitea")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Gitea", systemImage: "leaf")
                        .font(.title3.weight(.semibold))
                    Text("轻量私有 Git 托管，适合轻量应用服务器和个人/小团队。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                giteaInstallSummarySection

                HStack(spacing: 8) {
                    Button {
                        pendingGiteaInstall = true
                    } label: {
                        Label("安装 Gitea", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isInstallingGitea)

                    Button {
                        viewModel.openGiteaInBrowser()
                    } label: {
                        Label("打开后台", systemImage: "safari")
                    }
                    .disabled((viewModel.giteaInstallResult?.externalURL ?? viewModel.giteaDraft.externalURL).trimmingCharacters(in: .whitespacesAndNewlines) == "http://")
                }
            }

            if let error = viewModel.giteaErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var gitLabInstallWizard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isInstallingGitLab && !viewModel.gitLabInstallSteps.isEmpty {
                InstallProgressView(steps: viewModel.gitLabInstallSteps, title: "正在安装 GitLab CE")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("GitLab CE", systemImage: "square.stack.3d.up")
                        .font(.title3.weight(.semibold))
                    Text("完整 DevOps 平台，适合资源充足的服务器；轻量机器需先通过预检。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                gitLabFeedbackBanner

                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        developmentServiceRecommendationsSection
                        gitLabInstallSettingsSection
                        gitLabPreflightSection
                    }
                    .frame(minWidth: 420, maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 14) {
                        gitLabStatusSection
                        gitLabServiceActionsSection
                    }
                    .frame(minWidth: 340, idealWidth: 420, maxWidth: 520, alignment: .topLeading)
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.runGitLabPreflight(
                            profile: profile,
                            sshClient: appState.sshClient,
                            gitLabInstaller: appState.gitLabInstaller
                        )
                    } label: {
                        if viewModel.isRunningGitLabPreflight {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("预检", systemImage: "checklist")
                        }
                    }
                    .disabled(isGitLabBusy || !isGitLabDraftValid)

                    Button {
                        pendingGitLabInstall = true
                    } label: {
                        Label(viewModel.gitLabPreflightReport?.isReady == false ? "强制安装" : "安装", systemImage: "arrow.down.circle")
                    }
                    .disabled(isGitLabBusy || !isGitLabDraftValid || !hasGitLabPreflightReport)

                    Button {
                        viewModel.openGitLabInBrowser()
                    } label: {
                        Label("打开后台", systemImage: "safari")
                    }
                    .disabled(!isGitLabDraftValid)
                }
            }

            if let error = viewModel.gitLabErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Git Management Panel (post-install)

    @ViewBuilder
    private var gitManagementPanel: some View {
        switch selectedGitWorkbenchService {
        case .gitea:
            giteaManagementPanel
        case .gitLab:
            gitLabManagementPanel
        }
    }

    private var giteaManagementPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            gitNativeServiceHeader(
                title: "Gitea 原生管理",
                subtitle: "轻量 Git 托管，适合轻量应用服务器和个人/小团队使用。",
                service: .gitea
            ) {
                HStack(spacing: 8) {
                    Button {
                        viewModel.openGiteaInBrowser()
                    } label: {
                        Label("打开后台", systemImage: "safari")
                    }
                    .disabled((viewModel.giteaInstallResult?.externalURL ?? viewModel.giteaDraft.externalURL).trimmingCharacters(in: .whitespacesAndNewlines) == "http://")
                }
            }

            giteaInstallSummarySection
            gitNativeManagementWorkbench(service: .gitea)
        }
    }

    private var gitLabManagementPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            gitNativeServiceHeader(
                title: "GitLab 原生管理",
                subtitle: "完整 DevOps 平台，覆盖项目、组、成员、MR、CI/CD。",
                service: .gitLab
            ) {
                HStack(spacing: 8) {
                    Button {
                        viewModel.loadGitLabStatus(
                            profile: profile,
                            sshClient: appState.sshClient,
                            gitLabManager: appState.gitLabManager,
                            repository: appState.repository
                        )
                    } label: {
                        if viewModel.isLoadingGitLabStatus {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isGitLabBusy || !isGitLabDraftValid)

                    Button {
                        viewModel.openGitLabInBrowser()
                    } label: {
                        Label("打开后台", systemImage: "safari")
                    }
                    .disabled(!isGitLabDraftValid)
                }
            }

            gitLabFeedbackBanner

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    gitLabStatusSection
                    gitLabServiceActionsSection
                    gitLabBackupPreviewSection
                }
                .frame(minWidth: 340, idealWidth: 420, maxWidth: 520, alignment: .topLeading)
            }

            gitNativeManagementWorkbench(service: .gitLab)
        }
    }

    private func gitNativeServiceHeader<Actions: View>(
        title: String,
        subtitle: String,
        service: GitWorkbenchService,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(gitServiceAuthHint(service), systemImage: "key.horizontal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actions()
        }
    }

    private var giteaInstallSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gitea 安装与初始化")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("访问地址").foregroundStyle(.secondary)
                    Text(viewModel.giteaInstallResult?.externalURL ?? viewModel.giteaDraft.externalURL)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("监听端口").foregroundStyle(.secondary)
                    Text("\(viewModel.giteaDraft.listenPort)")
                }
                GridRow {
                    Text("服务名").foregroundStyle(.secondary)
                    Text(viewModel.giteaDraft.serviceName)
                }
                GridRow {
                    Text("状态").foregroundStyle(.secondary)
                    Text(viewModel.giteaInstallResult?.status ?? "未安装或尚未刷新")
                }
            }

            if let message = viewModel.giteaActionMessage {
                Label(message, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = viewModel.giteaErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func gitNativeManagementWorkbench(service: GitWorkbenchService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            gitNativeAuthorizationSection(service: service)

            if gitNativeIsTokenBound(service) {
                gitNativeLoadedContent(service: service)
            } else {
                gitNativeLockedContent(service: service)
            }
        }
    }

    private func gitNativeAuthorizationSection(service: GitWorkbenchService) -> some View {
        let tokenBinding: Binding<String> = service == .gitea ? $viewModel.giteaTokenDraft : $viewModel.gitLabTokenDraft
        let isBound = gitNativeIsTokenBound(service)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(service.title) API 授权")
                    .font(.headline)
                Spacer()
                Text(isBound ? "已绑定 Keychain Token" : "等待绑定 Token")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isBound ? .green : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isBound ? Color.green : Color.orange).opacity(0.14), in: Capsule())
            }

            HStack(spacing: 8) {
                SecureField("管理员 API Token", text: tokenBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)

                Button {
                    viewModel.saveGitNativeToken(
                        service: gitNativeServiceKind(service),
                        token: tokenBinding.wrappedValue,
                        profile: profile,
                        keychain: appState.keychain
                    )
                } label: {
                    Label("保存 Token", systemImage: "key")
                }
                .disabled(tokenBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    viewModel.loadGitNativeSnapshot(
                        service: gitNativeServiceKind(service),
                        profile: profile,
                        keychain: appState.keychain,
                        giteaAPIClient: appState.giteaAPIClient,
                        gitLabAPIClient: appState.gitLabAPIClient
                    )
                } label: {
                    if viewModel.isLoadingGitNativeSnapshot {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新原生数据", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(!isBound || viewModel.isLoadingGitNativeSnapshot)

                Button(role: .destructive) {
                    viewModel.deleteGitNativeToken(
                        service: gitNativeServiceKind(service),
                        profile: profile,
                        keychain: appState.keychain
                    )
                } label: {
                    Label("移除", systemImage: "trash")
                }
                .disabled(!isBound)
            }

            Label("Token 只保存在本机 Keychain。读取仓库、用户、组织/组、Issue、PR/MR、Pipeline 等对象走 \(service.title) 官方 API。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = viewModel.gitNativeActionMessage {
                Label(message, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = viewModel.gitNativeErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func gitNativeLoadedContent(service: GitWorkbenchService) -> some View {
        if service == .gitea, let snapshot = viewModel.giteaNativeSnapshot {
            giteaNativeSnapshotContent(snapshot)
        } else if service == .gitLab, let snapshot = viewModel.gitLabNativeSnapshot {
            gitLabNativeSnapshotContent(snapshot)
        } else {
            VStack(spacing: 10) {
                ContentUnavailableView(
                    "尚未加载原生数据",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("保存 Token 后点击“刷新原生数据”，会拉取原版 Web 后台的核心对象并显示为原生列表。")
                )
                .frame(maxWidth: .infinity, minHeight: 170)

                gitNativeManagementAreaGrid(service: service)
            }
        }
    }

    private func gitNativeLockedContent(service: GitWorkbenchService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            gitNativeManagementAreaGrid(service: service)
            Label("未绑定 Token 时只展示产品映射和安装运维入口，不执行业务对象读取或写操作。", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func gitNativeManagementAreaGrid(service: GitWorkbenchService) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(service.managementAreas) { area in
                VStack(alignment: .leading, spacing: 6) {
                    Label(area.title, systemImage: area.systemImage)
                        .font(.subheadline.weight(.semibold))
                    Text(area.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func giteaNativeSnapshotContent(_ snapshot: GiteaNativeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            gitNativeSummaryGrid([
                GitNativeSummaryMetric(title: "Repositories", value: "\(snapshot.repositories.count)", detail: "对应 Web: Repositories"),
                GitNativeSummaryMetric(title: "Users", value: "\(snapshot.users.count)", detail: "对应 Web: Site Admin / Users"),
                GitNativeSummaryMetric(title: "Organizations", value: "\(snapshot.organizations.count)", detail: "对应 Web: Organizations / Teams"),
                GitNativeSummaryMetric(title: "Issues / PR", value: "\(snapshot.issues.count) / \(snapshot.pullRequests.count)", detail: snapshot.capturedAt.formatted(date: .omitted, time: .shortened)),
                GitNativeSummaryMetric(title: "Packages", value: "\(snapshot.packages.count)", detail: "对应 Web: Packages"),
                GitNativeSummaryMetric(title: "Admin", value: snapshot.adminOverview.version ?? "unknown", detail: "Cron \(snapshot.adminOverview.cronTasks.count)"),
            ])

            gitNativeTabPicker

            switch gitNativeManagementTab {
            case .overview:
                gitNativeManagementAreaGrid(service: .gitea)
            case .repositories:
                VStack(alignment: .leading, spacing: 12) {
                    gitNativeRepositoryMutationSection(service: .gitea)
                    giteaRepositorySettingsSection
                    gitNativeObjectList(
                        title: "Repositories",
                        subtitle: "名称、Owner、可见性、归档状态、默认分支、更新时间、stars/forks。",
                        rows: snapshot.repositories.map {
                            GitNativeObjectRowData(
                                title: $0.fullName,
                                subtitle: [
                                    $0.isPrivate ? "private" : "public",
                                    $0.isArchived == true ? "archived" : nil,
                                    $0.defaultBranch,
                                    giteaRepositoryFeatureSummary($0),
                                ].compactMap { $0 }.joined(separator: " · "),
                                metadata: [$0.owner, $0.updatedAt?.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "),
                                systemImage: "folder.badge.gearshape",
                                giteaRepositoryEditRequest: GiteaRepositoryEditRequest(repository: $0),
                                deletionRequest: GitNativeDeletionRequest(
                                    kind: .giteaRepository(fullName: $0.fullName),
                                    displayName: $0.fullName
                                )
                            )
                        }
                    )
                }
            case .users:
                giteaMembersManagementSection(snapshot)
            case .issues:
                giteaIssueManagementSection(snapshot)
            case .automation:
                giteaAccessManagementSection(snapshot)
            }
        }
    }

    private func giteaAccessManagementSection(_ snapshot: GiteaNativeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            giteaKeyMutationSection
            giteaAccessTokenMutationSection(users: snapshot.users)

            gitNativeObjectList(
                title: "SSH Keys",
                subtitle: "当前账号 SSH Key、指纹、只读状态和创建时间；对应 Web: SSH / GPG Keys。",
                rows: snapshot.keys.map { key in
                    GitNativeObjectRowData(
                        title: key.title,
                        subtitle: key.fingerprint ?? key.key,
                        metadata: [
                            key.isReadOnly == true ? "read only" : "read/write",
                            key.createdAt?.formatted(date: .abbreviated, time: .shortened),
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "key",
                        giteaKeyDeletionRequest: GiteaKeyDeletionRequest(
                            keyId: key.id,
                            title: key.title,
                            fingerprint: key.fingerprint
                        )
                    )
                }
            )

            gitNativeObjectList(
                title: "Access Tokens",
                subtitle: "当前账号 Access Token、scope、创建和最后使用时间；对应 Web: Applications / Access Tokens。",
                rows: snapshot.tokens.map { token in
                    GitNativeObjectRowData(
                        title: token.name,
                        subtitle: token.scopes.joined(separator: ", "),
                        metadata: [
                            token.tokenLastEight.map { "last eight \($0)" },
                            token.createdAt?.formatted(date: .abbreviated, time: .shortened),
                            token.lastUsedAt.map { "used \($0.formatted(date: .abbreviated, time: .shortened))" },
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "person.badge.key",
                        giteaAccessTokenDeletionRequest: GiteaAccessTokenDeletionRequest(
                            username: token.username,
                            tokenId: token.id,
                            name: token.name,
                            tokenLastEight: token.tokenLastEight
                        )
                    )
                }
            )

            gitNativeObjectList(
                title: "Packages",
                subtitle: "包名、类型、版本、绑定仓库和发布时间；对应 Web: Packages。",
                rows: snapshot.packages.map { package in
                    GitNativeObjectRowData(
                        title: package.name,
                        subtitle: [
                            package.owner,
                            package.type,
                            package.version.map { "version \($0)" },
                            package.repository,
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: package.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "",
                        systemImage: "shippingbox",
                        giteaPackageDetailRequest: GiteaPackageDetailRequest(
                            owner: package.owner,
                            type: package.type,
                            name: package.name,
                            version: package.version
                        ),
                        giteaPackageDeletionRequest: GiteaPackageDeletionRequest(
                            owner: package.owner,
                            type: package.type,
                            name: package.name,
                            version: package.version
                        )
                    )
                }
            )

            giteaPackageDetailSection
            giteaAdminOverviewSection(snapshot.adminOverview)
            gitNativeManagementAreaGrid(service: .gitea)
        }
    }

    @ViewBuilder
    private var giteaPackageDetailSection: some View {
        if viewModel.isLoadingGiteaPackageDetail {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载 Gitea package 详情...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        } else if let detail = viewModel.selectedGiteaPackageDetail {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(detail.owner)/\(detail.name)")
                            .font(.headline)
                        Text([
                            detail.type,
                            detail.selectedVersion.map { "version \($0)" },
                            detail.package?.repository,
                            "captured \(detail.capturedAt.formatted(date: .omitted, time: .shortened))",
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("对应 Web: Packages / Detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                gitNativeObjectList(
                    title: "Package Versions",
                    subtitle: "当前包的所有版本；点击某一版本对应行的详情按钮可切换文件列表。",
                    rows: detail.versions.map { version in
                        GitNativeObjectRowData(
                            title: version.version ?? "unknown",
                            subtitle: [
                                version.owner,
                                version.type,
                                version.repository,
                            ].compactMap { $0 }.joined(separator: " · "),
                            metadata: version.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "",
                            systemImage: version.version == detail.selectedVersion ? "checkmark.seal" : "number",
                            giteaPackageDetailRequest: GiteaPackageDetailRequest(
                                owner: detail.owner,
                                type: detail.type,
                                name: detail.name,
                                version: version.version
                            ),
                            giteaPackageDeletionRequest: GiteaPackageDeletionRequest(
                                owner: detail.owner,
                                type: detail.type,
                                name: detail.name,
                                version: version.version
                            )
                        )
                    }
                )

                gitNativeObjectList(
                    title: "Package Files",
                    subtitle: "所选版本的文件、大小和校验摘要；对应 Web package file 列表。",
                    rows: detail.files.map { file in
                        GitNativeObjectRowData(
                            title: file.name,
                            subtitle: [
                                file.size.map(formatBytes),
                                file.sha256.map { "sha256 \($0)" },
                                file.sha1.map { "sha1 \($0)" },
                                file.md5.map { "md5 \($0)" },
                            ].compactMap { $0 }.joined(separator: " · "),
                            metadata: file.sha512.map { "sha512 \($0)" } ?? "",
                            systemImage: "doc.zipper"
                        )
                    }
                )
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func giteaAdminOverviewSection(_ overview: GiteaAdminOverviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            gitNativeSummaryGrid([
                GitNativeSummaryMetric(
                    title: "Gitea Version",
                    value: overview.version ?? "unknown",
                    detail: "对应 Web: Site Administration / Dashboard"
                ),
                GitNativeSummaryMetric(
                    title: "Cron Tasks",
                    value: "\(overview.cronTasks.count)",
                    detail: "对应 API: Admin / Cron"
                ),
            ])

            gitNativeObjectList(
                title: "Admin Overview / Cron",
                subtitle: "Gitea 后台任务的计划表达式、执行次数、上次和下次运行时间；当前为只读总览。",
                rows: overview.cronTasks.map { task in
                    GitNativeObjectRowData(
                        title: task.name,
                        subtitle: [
                            task.schedule.map { "schedule \($0)" },
                            task.execTimes.map { "executed \($0)" },
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: [
                            task.previousRunAt.map { "prev \($0.formatted(date: .abbreviated, time: .shortened))" },
                            task.nextRunAt.map { "next \($0.formatted(date: .abbreviated, time: .shortened))" },
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "clock.arrow.circlepath"
                    )
                }
            )
        }
    }

    private func giteaIssueManagementSection(_ snapshot: GiteaNativeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            gitIssueFilterControl
            gitNativeObjectList(
                title: "Issues / Pull Requests",
                subtitle: "对应 Gitea Web: Issues / Pull Requests。显示状态、仓库、作者、Assignee、Label、Milestone，并支持状态切换。",
                rows: giteaIssueRows(snapshot)
            )
        }
    }

    private func giteaIssueRows(_ snapshot: GiteaNativeSnapshot) -> [GitNativeObjectRowData] {
        let issueRows = snapshot.issues
            .filter { gitIssueStateFilter.includes($0.state) }
            .map { issue in
                GitNativeObjectRowData(
                    title: "#\(issue.number) \(issue.title)",
                    subtitle: gitIssueSubtitle(
                        scope: issue.repository,
                        author: issue.author,
                        assignees: issue.assignees,
                        labels: issue.labels,
                        milestone: issue.milestone
                    ),
                    metadata: issue.state,
                    systemImage: "record.circle",
                    issueStateRequest: issue.repository.map { repository in
                        GitNativeIssueStateRequest(
                            kind: .giteaIssue(repositoryFullName: repository, issueNumber: issue.number),
                            action: GitNativeIssueStateAction.suggested(for: issue.state),
                            displayName: "#\(issue.number) \(issue.title)"
                        )
                    },
                    webURL: issue.htmlURL
                )
            }
        let pullRequestRows = snapshot.pullRequests
            .filter { gitIssueStateFilter.includes($0.state) }
            .map { pullRequest in
                GitNativeObjectRowData(
                    title: "#\(pullRequest.number) \(pullRequest.title)",
                    subtitle: gitIssueSubtitle(
                        scope: pullRequest.repository,
                        author: pullRequest.author,
                        assignees: pullRequest.assignees,
                        labels: pullRequest.labels,
                        milestone: pullRequest.milestone
                    ),
                    metadata: "PR · \(pullRequest.state)",
                    systemImage: "arrow.triangle.pull",
                    issueStateRequest: pullRequest.repository.map { repository in
                        GitNativeIssueStateRequest(
                            kind: .giteaPullRequest(repositoryFullName: repository, issueNumber: pullRequest.number),
                            action: GitNativeIssueStateAction.suggested(for: pullRequest.state),
                            displayName: "PR #\(pullRequest.number) \(pullRequest.title)"
                        )
                    },
                    webURL: pullRequest.htmlURL
                )
            }
        return issueRows + pullRequestRows
    }

    private var giteaAccessTokenScopeOptions: [(id: String, title: String)] {
        [
            ("read:repository", "Read Repository"),
            ("write:repository", "Write Repository"),
            ("read:user", "Read User"),
            ("write:user", "Write User"),
            ("read:organization", "Read Organization"),
            ("write:organization", "Write Organization"),
            ("read:issue", "Read Issue"),
            ("write:issue", "Write Issue"),
            ("read:package", "Read Package"),
            ("write:package", "Write Package"),
            ("read:notification", "Read Notification"),
            ("all", "All"),
        ]
    }

    private func giteaAccessTokenMutationSection(users: [GiteaUserSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gitea Access Tokens")
                    .font(.headline)
                Spacer()
                Text("创建后只显示一次 token secret")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("用户", selection: $viewModel.giteaAccessTokenDraft.username) {
                    Text("选择用户").tag("")
                    ForEach(users) { user in
                        Text(user.username).tag(user.username)
                    }
                }
                .frame(width: 180)

                TextField("Token 名称", text: $viewModel.giteaAccessTokenDraft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Button {
                    pendingGiteaAccessTokenSave = true
                } label: {
                    if viewModel.isMutatingGiteaAccessToken {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("创建 Token", systemImage: "person.badge.key")
                    }
                }
                .disabled(!giteaAccessTokenDraftCanSubmit || viewModel.isMutatingGiteaAccessToken)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(giteaAccessTokenScopeOptions, id: \.id) { option in
                    Toggle(option.title, isOn: Binding(
                        get: {
                            viewModel.giteaAccessTokenDraft.scopes.contains(option.id)
                        },
                        set: { enabled in
                            if enabled {
                                if !viewModel.giteaAccessTokenDraft.scopes.contains(option.id) {
                                    viewModel.giteaAccessTokenDraft.scopes.append(option.id)
                                }
                            } else {
                                viewModel.giteaAccessTokenDraft.scopes.removeAll { $0 == option.id }
                            }
                        }
                    ))
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var giteaAccessTokenDraftCanSubmit: Bool {
        !viewModel.giteaAccessTokenDraft.trimmedUsername.isEmpty &&
            !viewModel.giteaAccessTokenDraft.trimmedName.isEmpty &&
            !viewModel.giteaAccessTokenDraft.scopes.isEmpty
    }

    private var giteaKeyMutationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gitea SSH Keys")
                    .font(.headline)
                Spacer()
                Text("新增会写入当前 token 所属账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("标题", text: $viewModel.giteaKeyDraft.title)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                TextField("ssh-ed25519 / ssh-rsa public key", text: $viewModel.giteaKeyDraft.key)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 320)

                Toggle("只读", isOn: $viewModel.giteaKeyDraft.isReadOnly)
                    .toggleStyle(.checkbox)

                Button {
                    pendingGiteaKeySave = true
                } label: {
                    Label("添加 Key", systemImage: "key.badge.plus")
                }
                .disabled(!giteaKeyDraftCanSubmit || viewModel.isMutatingGiteaKey)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var giteaKeyDraftCanSubmit: Bool {
        !viewModel.giteaKeyDraft.trimmedTitle.isEmpty &&
            viewModel.giteaKeyDraft.trimmedKey.hasPrefix("ssh-")
    }

    private func giteaMembersManagementSection(_ snapshot: GiteaNativeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            giteaUserMutationSection
            giteaOrganizationMutationSection
            giteaTeamMutationSection(organizations: snapshot.organizations)

            gitNativeObjectList(
                title: "Users",
                subtitle: "实例用户、管理员状态、邮箱和最后登录；删除前会二次确认。",
                rows: snapshot.users.map {
                    GitNativeObjectRowData(
                        title: $0.username,
                        subtitle: [$0.fullName, $0.email].compactMap { $0 }.joined(separator: " · "),
                        metadata: $0.isAdmin == true ? "admin" : ($0.isActive == false ? "disabled" : "active"),
                        systemImage: "person",
                        giteaUserEditRequest: GiteaUserEditRequest(user: $0),
                        giteaUserDeletionRequest: GiteaUserDeletionRequest(
                            username: $0.username,
                            email: $0.email,
                            isAdmin: $0.isAdmin == true
                        )
                    )
                }
            )

            gitNativeObjectList(
                title: "Organizations / Teams",
                subtitle: "组织、团队、权限和仓库范围；成员在下方 Team Members 管理。",
                rows: snapshot.organizations.map {
                    let organizationMetadata = [$0.fullName, $0.website]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    return GitNativeObjectRowData(
                        title: $0.username,
                        subtitle: $0.description ?? $0.fullName ?? "",
                        metadata: organizationMetadata.isEmpty ? "organization" : organizationMetadata,
                        systemImage: "building.2",
                        giteaOrganizationEditRequest: GiteaOrganizationEditRequest(organization: $0),
                        giteaOrganizationDeletionRequest: GiteaOrganizationDeletionRequest(
                            username: $0.username,
                            fullName: $0.fullName,
                            description: $0.description
                        )
                    )
                } + snapshot.teams.map { team in
                    GitNativeObjectRowData(
                        title: "\(team.organization)/\(team.name)",
                        subtitle: team.description ?? "",
                        metadata: [team.permission, team.includesAllRepositories == true ? "all repos" : nil].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "person.3.sequence",
                        giteaTeamEditRequest: GiteaTeamEditRequest(team: team),
                        giteaTeamDeletionRequest: GiteaTeamDeletionRequest(team: team)
                    )
                }
            )

            giteaTeamMemberMutationSection(teams: snapshot.teams)
            giteaTeamRepositoryMutationSection(teams: snapshot.teams, repositories: snapshot.repositories)

            gitNativeObjectList(
                title: "Team Members",
                subtitle: "团队成员、用户状态和权限来源；移除前会二次确认。",
                rows: snapshot.teamMembers.map { member in
                    let team = snapshot.teams.first { $0.id == member.teamId }
                    return GitNativeObjectRowData(
                        title: member.username,
                        subtitle: [member.fullName, member.email].compactMap { $0 }.joined(separator: " · "),
                        metadata: [
                            team.map { "\($0.organization)/\($0.name)" },
                            member.isActive == false ? "disabled" : "active",
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "person.crop.circle.badge.checkmark",
                        giteaTeamMemberEditRequest: GiteaTeamMemberEditRequest(member: member),
                        giteaTeamMemberDeletionRequest: GiteaTeamMemberDeletionRequest(
                            teamId: member.teamId,
                            username: member.username,
                            displayName: [team.map { "\($0.organization)/\($0.name)" }, member.username].compactMap { $0 }.joined(separator: " / ")
                        )
                    )
                }
            )

            gitNativeObjectList(
                title: "Team Repositories",
                subtitle: "团队绑定仓库、默认分支和更新时间；移除只解除团队权限，不删除仓库。",
                rows: snapshot.teamRepositories.map { repository in
                    let team = snapshot.teams.first { $0.id == repository.teamId }
                    return GitNativeObjectRowData(
                        title: repository.fullName,
                        subtitle: [
                            team.map { "\($0.organization)/\($0.name)" },
                            repository.isPrivate ? "private" : "public",
                            repository.defaultBranch,
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: repository.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "",
                        systemImage: "folder.badge.person.crop",
                        giteaTeamRepositoryDeletionRequest: GiteaTeamRepositoryDeletionRequest(
                            teamId: repository.teamId,
                            repositoryFullName: repository.fullName,
                            displayName: [team.map { "\($0.organization)/\($0.name)" }, repository.fullName].compactMap { $0 }.joined(separator: " / ")
                        )
                    )
                }
            )
        }
    }

    private var giteaUserMutationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.giteaUserDraft.trimmedOriginalUsername.isEmpty ? "Gitea Users" : "编辑 Gitea User")
                    .font(.headline)
                Spacer()
                Text(viewModel.giteaUserDraft.trimmedOriginalUsername.isEmpty ? "对应 Web: Site Administration / User Accounts" : "对应 Web: Site Admin / Edit User")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("用户名", text: $viewModel.giteaUserDraft.username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)

                TextField("邮箱", text: $viewModel.giteaUserDraft.email)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                SecureField(viewModel.giteaUserDraft.trimmedOriginalUsername.isEmpty ? "初始密码" : "新密码，留空不改", text: $viewModel.giteaUserDraft.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                TextField("姓名/备注", text: $viewModel.giteaUserDraft.fullName)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)
            }

            HStack(spacing: 12) {
                Toggle("首次登录改密", isOn: $viewModel.giteaUserDraft.mustChangePassword)
                    .toggleStyle(.checkbox)
                Toggle("启用", isOn: $viewModel.giteaUserDraft.isActive)
                    .toggleStyle(.checkbox)
                Toggle("管理员", isOn: $viewModel.giteaUserDraft.isAdmin)
                    .toggleStyle(.checkbox)
                Toggle("禁止登录", isOn: $viewModel.giteaUserDraft.prohibitLogin)
                    .toggleStyle(.checkbox)
                Toggle("受限用户", isOn: $viewModel.giteaUserDraft.restricted)
                    .toggleStyle(.checkbox)
                Spacer()
                Button {
                    pendingGiteaUserSave = GiteaUserSaveRequest(mode: .create)
                } label: {
                    Label("创建用户", systemImage: "person.badge.plus")
                }
                .disabled(!giteaUserDraftCanSubmit(mode: .create) || viewModel.isMutatingGiteaUser || !viewModel.giteaUserDraft.trimmedOriginalUsername.isEmpty)

                Button {
                    pendingGiteaUserSave = GiteaUserSaveRequest(mode: .update)
                } label: {
                    Label("保存用户", systemImage: "square.and.pencil")
                }
                .disabled(!giteaUserDraftCanSubmit(mode: .update) || viewModel.isMutatingGiteaUser || viewModel.giteaUserDraft.trimmedOriginalUsername.isEmpty)

                Button {
                    viewModel.giteaUserDraft = GiteaUserDraft()
                } label: {
                    Label("清空", systemImage: "xmark.circle")
                }
                .disabled(viewModel.isMutatingGiteaUser)
            }

            Text("创建和编辑用户需要 Gitea 管理员 token；密码留空时只更新资料、状态和权限。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func giteaUserDraftCanSubmit(mode: GiteaUserSaveMode) -> Bool {
        let draft = viewModel.giteaUserDraft
        let passwordIsValid = mode == .update && draft.trimmedPassword.isEmpty ? true : draft.trimmedPassword.count >= 8
        return !draft.trimmedUsername.isEmpty &&
            (mode == .create || !draft.trimmedOriginalUsername.isEmpty) &&
            draft.trimmedEmail.contains("@") &&
            passwordIsValid
    }

    private var giteaOrganizationMutationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.giteaOrganizationDraft.trimmedOriginalUsername.isEmpty ? "Gitea Organizations" : "编辑 Gitea Organization")
                    .font(.headline)
                Spacer()
                Text(viewModel.giteaOrganizationDraft.trimmedOriginalUsername.isEmpty ? "对应 Web: Organizations / New" : "对应 Web: Organization Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("组织路径", text: $viewModel.giteaOrganizationDraft.username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)

                TextField("显示名称", text: $viewModel.giteaOrganizationDraft.fullName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Picker("可见性", selection: $viewModel.giteaOrganizationDraft.visibility) {
                    Text("public").tag("public")
                    Text("limited").tag("limited")
                    Text("private").tag("private")
                }
                .frame(width: 130)

                TextField("网站，可选", text: $viewModel.giteaOrganizationDraft.website)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            HStack(spacing: 8) {
                TextField("描述，可选", text: $viewModel.giteaOrganizationDraft.description)
                    .textFieldStyle(.roundedBorder)

                Button {
                    pendingGiteaOrganizationSave = GiteaOrganizationSaveRequest(mode: .create)
                } label: {
                    if viewModel.isMutatingGiteaOrganization {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("创建组织", systemImage: "building.2.crop.circle")
                    }
                }
                .disabled(!giteaOrganizationDraftCanSubmit || viewModel.isMutatingGiteaOrganization || !viewModel.giteaOrganizationDraft.trimmedOriginalUsername.isEmpty)

                Button {
                    pendingGiteaOrganizationSave = GiteaOrganizationSaveRequest(mode: .update)
                } label: {
                    Label("保存组织", systemImage: "square.and.pencil")
                }
                .disabled(!giteaOrganizationDraftCanSubmit || viewModel.isMutatingGiteaOrganization || viewModel.giteaOrganizationDraft.trimmedOriginalUsername.isEmpty)

                Button {
                    viewModel.giteaOrganizationDraft = GiteaOrganizationDraft()
                } label: {
                    Label("清空", systemImage: "xmark.circle")
                }
                .disabled(viewModel.isMutatingGiteaOrganization)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var giteaOrganizationDraftCanSubmit: Bool {
        let draft = viewModel.giteaOrganizationDraft
        return !draft.trimmedUsername.isEmpty &&
            draft.trimmedUsername.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil &&
            ["public", "limited", "private"].contains(draft.visibility)
    }

    private var giteaTeamUnitOptions: [(id: String, title: String)] {
        [
            ("repo.code", "Code"),
            ("repo.issues", "Issues"),
            ("repo.pulls", "Pull Requests"),
            ("repo.releases", "Releases"),
            ("repo.wiki", "Wiki"),
            ("repo.projects", "Projects"),
            ("repo.packages", "Packages"),
            ("repo.actions", "Actions"),
        ]
    }

    private func giteaTeamMutationSection(organizations: [GiteaOrganizationSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.giteaTeamDraft.teamId == 0 ? "Gitea Teams" : "编辑 Gitea Team")
                    .font(.headline)
                Spacer()
                Text(viewModel.giteaTeamDraft.teamId == 0 ? "对应 Web: Organization / Teams / New" : "对应 Web: Team Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("组织", selection: $viewModel.giteaTeamDraft.organization) {
                    Text("选择组织").tag("")
                    ForEach(organizations) { organization in
                        Text(organization.username).tag(organization.username)
                    }
                }
                .frame(width: 180)
                .disabled(viewModel.giteaTeamDraft.teamId > 0)

                TextField("团队名称", text: $viewModel.giteaTeamDraft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Picker("权限", selection: $viewModel.giteaTeamDraft.permission) {
                    Text("read").tag("read")
                    Text("write").tag("write")
                    Text("admin").tag("admin")
                }
                .frame(width: 120)

                Toggle("所有仓库", isOn: $viewModel.giteaTeamDraft.includesAllRepositories)
                Toggle("允许建仓库", isOn: $viewModel.giteaTeamDraft.canCreateOrgRepo)
            }

            TextField("描述，可选", text: $viewModel.giteaTeamDraft.description)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Units")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], alignment: .leading, spacing: 6) {
                    ForEach(giteaTeamUnitOptions, id: \.id) { option in
                        Toggle(option.title, isOn: Binding(
                            get: {
                                viewModel.giteaTeamDraft.units.contains(option.id)
                            },
                            set: { enabled in
                                if enabled {
                                    if !viewModel.giteaTeamDraft.units.contains(option.id) {
                                        viewModel.giteaTeamDraft.units.append(option.id)
                                    }
                                } else {
                                    viewModel.giteaTeamDraft.units.removeAll { $0 == option.id }
                                }
                            }
                        ))
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    pendingGiteaTeamSave = GiteaTeamSaveRequest(mode: .create)
                } label: {
                    if viewModel.isMutatingGiteaTeam {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("创建团队", systemImage: "person.3.sequence")
                    }
                }
                .disabled(!giteaTeamDraftCanSubmit || viewModel.isMutatingGiteaTeam || viewModel.giteaTeamDraft.teamId > 0)

                Button {
                    pendingGiteaTeamSave = GiteaTeamSaveRequest(mode: .update)
                } label: {
                    Label("保存团队", systemImage: "square.and.pencil")
                }
                .disabled(!giteaTeamDraftCanSubmit || viewModel.isMutatingGiteaTeam || viewModel.giteaTeamDraft.teamId == 0)

                Button {
                    viewModel.giteaTeamDraft = GiteaTeamDraft()
                } label: {
                    Label("清空", systemImage: "xmark.circle")
                }
                .disabled(viewModel.isMutatingGiteaTeam)

                Spacer()

                Text("创建后可在 Team Members 中添加用户；删除团队会同步移除本地成员快照。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var giteaTeamDraftCanSubmit: Bool {
        let draft = viewModel.giteaTeamDraft
        return !draft.trimmedName.isEmpty &&
            draft.trimmedName.rangeOfCharacter(from: CharacterSet(charactersIn: "/\n\r")) == nil &&
            (draft.teamId > 0 || !draft.trimmedOrganization.isEmpty) &&
            ["read", "write", "admin"].contains(draft.permission) &&
            !draft.units.isEmpty
    }

    private func giteaTeamMemberMutationSection(teams: [GiteaTeamSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gitea Team Members")
                    .font(.headline)
                Spacer()
                Text("对应 Web: Organizations / Teams / Members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("团队", selection: $viewModel.giteaTeamMemberDraft.teamId) {
                    Text("选择团队").tag(Int64(0))
                    ForEach(teams) { team in
                        Text("\(team.organization)/\(team.name)").tag(team.id)
                    }
                }
                .frame(width: 260)

                TextField("用户名", text: $viewModel.giteaTeamMemberDraft.username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Spacer()

                Button {
                    pendingGiteaTeamMemberSave = GiteaTeamMemberSaveRequest()
                } label: {
                    Label("添加成员", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(!giteaTeamMemberDraftCanSubmit || viewModel.isMutatingGiteaTeamMember)
            }

            Text("团队成员必须是 Gitea 已存在用户；可以先在上方 Users 表单创建账号，再加入团队。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var giteaTeamMemberDraftCanSubmit: Bool {
        viewModel.giteaTeamMemberDraft.teamId > 0 && !viewModel.giteaTeamMemberDraft.trimmedUsername.isEmpty
    }

    private func giteaTeamRepositoryMutationSection(teams: [GiteaTeamSummary], repositories: [GiteaRepositorySummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gitea Team Repositories")
                    .font(.headline)
                Spacer()
                Text("对应 Web: Organizations / Teams / Repositories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("团队", selection: $viewModel.giteaTeamRepositoryDraft.teamId) {
                    Text("选择团队").tag(Int64(0))
                    ForEach(teams) { team in
                        Text("\(team.organization)/\(team.name)").tag(team.id)
                    }
                }
                .frame(width: 260)

                Picker("仓库", selection: $viewModel.giteaTeamRepositoryDraft.repositoryFullName) {
                    Text("选择仓库").tag("")
                    ForEach(repositories) { repository in
                        Text(repository.fullName).tag(repository.fullName)
                    }
                }
                .frame(width: 280)

                Spacer()

                Button {
                    pendingGiteaTeamRepositorySave = GiteaTeamRepositorySaveRequest()
                } label: {
                    Label("绑定仓库", systemImage: "folder.badge.plus")
                }
                .disabled(!giteaTeamRepositoryDraftCanSubmit || viewModel.isMutatingGiteaTeamRepository)
            }

            Text("绑定仓库只修改团队权限范围；仓库本身不会被创建、移动或删除。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var giteaTeamRepositoryDraftCanSubmit: Bool {
        viewModel.giteaTeamRepositoryDraft.teamId > 0 &&
            viewModel.giteaTeamRepositoryDraft.trimmedRepositoryFullName.split(separator: "/").count == 2
    }

    private func gitLabNativeSnapshotContent(_ snapshot: GitLabNativeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            gitNativeSummaryGrid([
                GitNativeSummaryMetric(title: "Projects", value: "\(snapshot.projects.count)", detail: "对应 Web: Projects"),
                GitNativeSummaryMetric(title: "Groups", value: "\(snapshot.groups.count)", detail: "对应 Web: Groups"),
                GitNativeSummaryMetric(title: "Users / Members", value: "\(snapshot.users.count) / \(snapshot.members.count)", detail: "对应 Web: Members"),
                GitNativeSummaryMetric(title: "Branches / Tags", value: "\(snapshot.branches.count) / \(snapshot.tags.count)", detail: "对应 Web: Repository"),
                GitNativeSummaryMetric(title: "Issues / MR", value: "\(snapshot.issues.count) / \(snapshot.mergeRequests.count)", detail: "对应 Web: Issues / Merge Requests"),
                GitNativeSummaryMetric(title: "Pipelines / Jobs", value: "\(snapshot.pipelines.count) / \(snapshot.jobs.count)", detail: snapshot.capturedAt.formatted(date: .omitted, time: .shortened)),
                GitNativeSummaryMetric(title: "Packages / Runners", value: "\(snapshot.packages.count) / \(snapshot.runners.count)", detail: "对应 Web: Registries / Runners"),
                GitNativeSummaryMetric(title: "Variables", value: "\(snapshot.variables.count)", detail: "对应 Web: CI/CD Variables"),
                GitNativeSummaryMetric(title: "Admin", value: snapshot.adminOverview.version ?? "unknown", detail: snapshot.adminOverview.healthStatus ?? "对应 Web: Admin Area"),
            ])

            gitNativeTabPicker

            switch gitNativeManagementTab {
            case .overview:
                gitNativeManagementAreaGrid(service: .gitLab)
            case .repositories:
                VStack(alignment: .leading, spacing: 12) {
                    gitNativeRepositoryMutationSection(service: .gitLab)
                    gitLabProjectSettingsSection
                    gitNativeObjectList(
                        title: "Projects",
                        subtitle: "名称、Namespace、可见性、默认分支、最后活动和归档状态。",
                        rows: snapshot.projects.map {
                            GitNativeObjectRowData(
                                title: $0.pathWithNamespace,
                                subtitle: [$0.visibility, $0.defaultBranch, $0.archived ? "archived" : nil].compactMap { $0 }.joined(separator: " · "),
                                metadata: $0.lastActivityAt?.formatted(date: .abbreviated, time: .shortened) ?? "",
                                systemImage: "folder.badge.gearshape",
                                gitLabProjectEditRequest: GitLabProjectEditRequest(project: $0),
                                deletionRequest: GitNativeDeletionRequest(
                                    kind: .gitLabProject(projectId: $0.id, pathWithNamespace: $0.pathWithNamespace),
                                    displayName: $0.pathWithNamespace
                                )
                            )
                        }
                    )
                    gitLabTagMutationSection(projects: snapshot.projects)
                    gitNativeObjectList(
                        title: "Branches",
                        subtitle: "对应 GitLab Web: Repository / Branches。当前先展示默认分支、保护状态、提交和可推送状态。",
                        rows: snapshot.branches.map { branch in
                            let projectPath = snapshot.projects.first { $0.id == branch.projectId }?.pathWithNamespace
                            return GitNativeObjectRowData(
                                title: branch.name,
                                subtitle: [
                                    projectPath ?? "project \(branch.projectId)",
                                    branch.isDefault ? "default" : nil,
                                    branch.protected ? "protected" : nil,
                                    branch.merged == true ? "merged" : nil,
                                ].compactMap { $0 }.joined(separator: " · "),
                                metadata: [
                                    branch.commitShortID,
                                    branch.canPush.map { $0 ? "can push" : "read only" },
                                ].compactMap { $0 }.joined(separator: " · "),
                                systemImage: "arrow.triangle.branch"
                            )
                        }
                    )
                    gitNativeObjectList(
                        title: "Tags",
                        subtitle: "对应 GitLab Web: Repository / Tags。支持从分支、Tag 或 commit SHA 创建标签，并删除已有标签。",
                        rows: snapshot.tags.map { tag in
                            let projectPath = snapshot.projects.first { $0.id == tag.projectId }?.pathWithNamespace
                            return GitNativeObjectRowData(
                                title: tag.name,
                                subtitle: [
                                    projectPath ?? "project \(tag.projectId)",
                                    tag.target,
                                    tag.message,
                                ].compactMap { $0 }.joined(separator: " · "),
                                metadata: [
                                    tag.protected == true ? "protected" : nil,
                                    tag.commitShortID,
                                ].compactMap { $0 }.joined(separator: " · "),
                                systemImage: "tag",
                                gitLabTagDeletionRequest: GitLabTagDeletionRequest(
                                    projectId: tag.projectId,
                                    tagName: tag.name,
                                    target: tag.target
                                )
                            )
                        }
                    )
                    gitNativeObjectList(
                        title: "Packages & Registries",
                        subtitle: "对应 GitLab Web: Deploy / Package Registry。当前先展示包类型、版本、状态和最近更新时间。",
                        rows: snapshot.packages.map { package in
                            let projectPath = snapshot.projects.first { $0.id == package.projectId }?.pathWithNamespace
                            return GitNativeObjectRowData(
                                title: package.name,
                                subtitle: [
                                    projectPath ?? "project \(package.projectId)",
                                    package.packageType,
                                    package.version.map { "version \($0)" },
                                ].compactMap { $0 }.joined(separator: " · "),
                        metadata: [
                            package.status,
                            (package.updatedAt ?? package.createdAt)?.formatted(date: .abbreviated, time: .shortened),
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "shippingbox",
                        gitLabPackageDeletionRequest: GitLabPackageDeletionRequest(
                            projectId: package.projectId,
                            packageId: package.id,
                            name: package.name,
                            version: package.version,
                            packageType: package.packageType
                        )
                    )
                }
            )
                }
            case .users:
                gitLabMembersManagementSection(snapshot)
            case .issues:
                gitLabIssueManagementSection(snapshot)
            case .automation:
                gitLabAutomationManagementSection(snapshot)
            }
        }
    }

    private func gitLabMembersManagementSection(_ snapshot: GitLabNativeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            gitLabGroupMutationSection(groups: snapshot.groups)

            gitNativeObjectList(
                title: "Groups",
                subtitle: "组路径、可见性和 Web 入口；成员权限在下方 Members 区域管理。",
                rows: snapshot.groups.map { group in
                    GitNativeObjectRowData(
                        title: group.fullPath,
                        subtitle: group.name,
                        metadata: group.visibility ?? "",
                        systemImage: "person.3",
                        gitLabGroupEditRequest: GitLabGroupEditRequest(group: group),
                        deletionRequest: GitNativeDeletionRequest(
                            kind: .gitLabGroup(groupId: group.id, fullPath: group.fullPath),
                            displayName: group.fullPath
                        )
                    )
                } + snapshot.users.map { user in
                    GitNativeObjectRowData(
                        title: user.username,
                        subtitle: user.name ?? "",
                        metadata: [user.state, user.isAdmin == true ? "admin" : nil].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "person"
                    )
                }
            )

            gitLabMemberMutationSection(projects: snapshot.projects, groups: snapshot.groups)

            gitNativeObjectList(
                title: "Members",
                subtitle: "对应 GitLab Web: Project / Group Members。支持添加、改角色、设置到期日和移除。",
                rows: snapshot.members.map { member in
                    GitNativeObjectRowData(
                        title: member.username,
                        subtitle: [
                            member.scope.displayName,
                            "target \(member.targetId)",
                            "user \(member.userId)",
                            member.expiresAt.map { "expires \($0)" },
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: gitLabAccessLevelTitle(member.accessLevel),
                        systemImage: "person.crop.circle.badge.checkmark",
                        memberEditRequest: GitLabMemberEditRequest(member: member),
                        memberDeletionRequest: GitLabMemberDeletionRequest(
                            scope: member.scope,
                            targetId: member.targetId,
                            userId: member.userId,
                            username: member.username
                        )
                    )
                }
            )
        }
    }

    private func gitLabGroupMutationSection(groups: [GitLabGroupSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.gitLabGroupDraft.groupId > 0 ? "编辑 GitLab Group" : "GitLab Groups")
                    .font(.headline)
                Spacer()
                Text(viewModel.gitLabGroupDraft.groupId > 0 ? "对应 Web: Group Settings / General" : "对应 Web: Groups / New group")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("名称", text: $viewModel.gitLabGroupDraft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                TextField("路径", text: $viewModel.gitLabGroupDraft.path)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Picker("可见性", selection: $viewModel.gitLabGroupDraft.visibility) {
                    Text("private").tag("private")
                    Text("internal").tag("internal")
                    Text("public").tag("public")
                }
                .frame(width: 130)
                Picker("父级", selection: $viewModel.gitLabGroupDraft.parentId) {
                    Text("无父级").tag(Int64(0))
                    ForEach(groups) { group in
                        Text(group.fullPath).tag(group.id)
                    }
                }
                .frame(width: 220)
            }

            HStack(spacing: 8) {
                TextField("描述，可选", text: $viewModel.gitLabGroupDraft.description)
                    .textFieldStyle(.roundedBorder)
                Button {
                    pendingGitLabGroupSave = GitLabGroupSaveRequest(mode: .create)
                } label: {
                    if viewModel.isMutatingGitLabGroup {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("创建 Group", systemImage: "person.3.sequence")
                    }
                }
                .disabled(!gitLabGroupDraftCanSubmit || viewModel.isMutatingGitLabGroup || viewModel.gitLabGroupDraft.groupId > 0)

                Button {
                    pendingGitLabGroupSave = GitLabGroupSaveRequest(mode: .update)
                } label: {
                    Label("保存 Group", systemImage: "square.and.pencil")
                }
                .disabled(!gitLabGroupDraftCanSubmit || viewModel.isMutatingGitLabGroup || viewModel.gitLabGroupDraft.groupId <= 0)

                Button {
                    viewModel.gitLabGroupDraft = GitLabGroupDraft()
                } label: {
                    Label("清空", systemImage: "xmark.circle")
                }
                .disabled(viewModel.isMutatingGitLabGroup)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var gitLabGroupDraftCanSubmit: Bool {
        let draft = viewModel.gitLabGroupDraft
        return !draft.trimmedName.isEmpty &&
            !draft.trimmedPath.isEmpty &&
            draft.trimmedPath.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil &&
            ["private", "internal", "public"].contains(draft.visibility)
    }

    private func gitLabMemberMutationSection(projects: [GitLabProjectSummary], groups: [GitLabGroupSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("GitLab Members")
                    .font(.headline)
                Spacer()
                Text("角色变更和移除会直接写入 GitLab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("范围", selection: $viewModel.gitLabMemberDraft.scope) {
                    ForEach(GitLabMemberScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .frame(width: 120)

                Picker("目标", selection: $viewModel.gitLabMemberDraft.targetId) {
                    Text("选择目标").tag(Int64(0))
                    if viewModel.gitLabMemberDraft.scope == .project {
                        ForEach(projects) { project in
                            Text(project.pathWithNamespace).tag(project.id)
                        }
                    } else {
                        ForEach(groups) { group in
                            Text(group.fullPath).tag(group.id)
                        }
                    }
                }
                .frame(width: 240)

                TextField("User ID", value: $viewModel.gitLabMemberDraft.userId, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)

                Picker("角色", selection: $viewModel.gitLabMemberDraft.accessLevel) {
                    ForEach(gitLabAccessLevels, id: \.level) { role in
                        Text(role.title).tag(role.level)
                    }
                }
                .frame(width: 150)

                TextField("到期 YYYY-MM-DD", text: $viewModel.gitLabMemberDraft.expiresAt)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }

            HStack(spacing: 8) {
                Button {
                    pendingGitLabMemberSave = GitLabMemberSaveRequest(mode: .add)
                } label: {
                    Label("添加成员", systemImage: "plus")
                }
                .disabled(!gitLabMemberDraftCanSubmit || viewModel.isMutatingGitLabMember)

                Button {
                    pendingGitLabMemberSave = GitLabMemberSaveRequest(mode: .update)
                } label: {
                    Label("更新角色", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(!gitLabMemberDraftCanSubmit || viewModel.isMutatingGitLabMember)

                Spacer()

                Text("User ID 可从上方 Users 列表读取；后续会接用户名搜索。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var gitLabMemberDraftCanSubmit: Bool {
        viewModel.gitLabMemberDraft.targetId > 0 &&
            viewModel.gitLabMemberDraft.userId > 0
    }

    private var gitLabAccessLevels: [(level: Int, title: String)] {
        [
            (10, "Guest"),
            (20, "Reporter"),
            (30, "Developer"),
            (40, "Maintainer"),
            (50, "Owner"),
        ]
    }

    private func gitLabAccessLevelTitle(_ level: Int) -> String {
        gitLabAccessLevels.first { $0.level == level }?.title ?? "Level \(level)"
    }

    private func gitLabIssueManagementSection(_ snapshot: GitLabNativeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            gitIssueFilterControl
            gitNativeObjectList(
                title: "Issues / Merge Requests",
                subtitle: "对应 GitLab Web: Issues / Merge Requests。显示项目、作者、Assignee、Reviewer、Label、Milestone 和分支。",
                rows: gitLabIssueRows(snapshot)
            )
        }
    }

    private func gitLabIssueRows(_ snapshot: GitLabNativeSnapshot) -> [GitNativeObjectRowData] {
        let issueRows = snapshot.issues
            .filter { gitIssueStateFilter.includes($0.state) }
            .map { issue in
                GitNativeObjectRowData(
                    title: "!\(issue.iid) \(issue.title)",
                    subtitle: gitIssueSubtitle(
                        scope: issue.projectId.map { "project \($0)" },
                        author: issue.author,
                        assignees: issue.assignees,
                        labels: issue.labels,
                        milestone: issue.milestone
                    ),
                    metadata: issue.state,
                    systemImage: "record.circle",
                    issueStateRequest: issue.projectId.map { projectId in
                        GitNativeIssueStateRequest(
                            kind: .gitLabIssue(projectId: projectId, iid: issue.iid),
                            action: GitNativeIssueStateAction.suggested(for: issue.state),
                            displayName: "Issue !\(issue.iid) \(issue.title)"
                        )
                    },
                    webURL: issue.webURL
                )
            }
        let mergeRequestRows = snapshot.mergeRequests
            .filter { gitIssueStateFilter.includes($0.state) }
            .map { mergeRequest in
                GitNativeObjectRowData(
                    title: "!\(mergeRequest.iid) \(mergeRequest.title)",
                    subtitle: gitIssueSubtitle(
                        scope: [
                            mergeRequest.projectId.map { "project \($0)" },
                            nonEmpty([mergeRequest.sourceBranch, mergeRequest.targetBranch].compactMap { $0 }.joined(separator: " -> ")),
                        ].compactMap { $0 }.joined(separator: " · "),
                        author: mergeRequest.author,
                        assignees: mergeRequest.assignees + mergeRequest.reviewers.map { "review \($0)" },
                        labels: mergeRequest.labels,
                        milestone: mergeRequest.milestone
                    ),
                    metadata: "MR · \(mergeRequest.state)",
                    systemImage: "arrow.triangle.merge",
                    issueStateRequest: mergeRequest.projectId.map { projectId in
                        GitNativeIssueStateRequest(
                            kind: .gitLabMergeRequest(projectId: projectId, iid: mergeRequest.iid),
                            action: GitNativeIssueStateAction.suggested(for: mergeRequest.state),
                            displayName: "MR !\(mergeRequest.iid) \(mergeRequest.title)"
                        )
                    },
                    webURL: mergeRequest.webURL
                )
            }
        return issueRows + mergeRequestRows
    }

    private func gitLabAutomationManagementSection(_ snapshot: GitLabNativeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            gitLabAdminOverviewSection(snapshot.adminOverview)

            gitNativeObjectList(
                title: "CI/CD Pipelines",
                subtitle: "Pipeline ID、分支、SHA、状态、Web 日志入口，以及重试/取消等常用操作。",
                rows: snapshot.pipelines.map { pipeline in
                    GitNativeObjectRowData(
                        title: "Pipeline #\(pipeline.id)",
                        subtitle: [pipeline.ref, pipeline.sha.map { String($0.prefix(8)) }].compactMap { $0 }.joined(separator: " · "),
                        metadata: pipeline.status,
                        systemImage: "play.rectangle",
                        pipelineActionRequests: GitLabPipelineAction.allCases.map { action in
                            GitLabPipelineActionRequest(
                                projectId: pipeline.projectId,
                                pipelineId: pipeline.id,
                                action: action,
                                displayName: "Pipeline #\(pipeline.id)"
                            )
                        }
                    )
                }
            )

            gitNativeObjectList(
                title: "CI/CD Jobs",
                subtitle: "对应 GitLab Web: CI/CD / Jobs。支持重试、取消和运行手动 Job。",
                rows: snapshot.jobs.map { job in
                    let projectPath = snapshot.projects.first { $0.id == job.projectId }?.pathWithNamespace
                    return GitNativeObjectRowData(
                        title: "#\(job.id) \(job.name)",
                        subtitle: [
                            projectPath ?? "project \(job.projectId)",
                            job.stage,
                            job.ref,
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: [
                            job.status,
                            job.duration.map { String(format: "%.0fs", $0) },
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "hammer",
                        jobActionRequests: GitLabJobAction.allCases.map { action in
                            GitLabJobActionRequest(
                                projectId: job.projectId,
                                jobId: job.id,
                                action: action,
                                displayName: "Job #\(job.id) \(job.name)"
                            )
                        },
                        gitLabJobTraceRequest: GitLabJobTraceRequest(
                            projectId: job.projectId,
                            jobId: job.id,
                            displayName: "Job #\(job.id) \(job.name)"
                        )
                    )
                }
            )

            gitLabJobTraceSection

            gitNativeObjectList(
                title: "Runners",
                subtitle: "对应 GitLab Web: Admin / CI/CD / Runners。当前先展示运行状态、类型、标签、版本和最近联系时间。",
                rows: snapshot.runners.map { runner in
                    GitNativeObjectRowData(
                        title: runner.description ?? runner.name ?? "Runner #\(runner.id)",
                        subtitle: [
                            runner.runnerType,
                            runner.isShared == true ? "shared" : nil,
                            runner.tagList.isEmpty ? nil : runner.tagList.joined(separator: ", "),
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: [
                            runner.status,
                            runner.paused == true ? "paused" : nil,
                            runner.version,
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "figure.run.circle"
                    )
                }
            )

            gitLabDeployKeyMutationSection(projects: snapshot.projects)
            gitLabDeployTokenMutationSection(projects: snapshot.projects)

            gitNativeObjectList(
                title: "Deploy Keys",
                subtitle: "对应 GitLab Web: Project / Settings / Repository / Deploy Keys。用于项目级 SSH 拉取或推送权限。",
                rows: snapshot.deployKeys.map { key in
                    let projectPath = snapshot.projects.first { $0.id == key.projectId }?.pathWithNamespace
                    return GitNativeObjectRowData(
                        title: key.title,
                        subtitle: [
                            projectPath ?? "project \(key.projectId)",
                            key.fingerprint ?? key.key,
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: [
                            key.canPush ? "can push" : "read only",
                            key.expiresAt.map { "expires \($0)" },
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "key",
                        gitLabDeployKeyDeletionRequest: GitLabDeployKeyDeletionRequest(
                            projectId: key.projectId,
                            keyId: key.id,
                            title: key.title,
                            fingerprint: key.fingerprint
                        )
                    )
                }
            )

            gitNativeObjectList(
                title: "Deploy Tokens",
                subtitle: "对应 GitLab Web: Project / Settings / Repository / Deploy Tokens。用于仓库、镜像和包仓库访问授权。",
                rows: snapshot.deployTokens.map { deployToken in
                    let projectPath = snapshot.projects.first { $0.id == deployToken.projectId }?.pathWithNamespace
                    return GitNativeObjectRowData(
                        title: deployToken.name,
                        subtitle: [
                            projectPath ?? "project \(deployToken.projectId)",
                            deployToken.username.map { "user \($0)" },
                            deployToken.scopes.isEmpty ? nil : deployToken.scopes.joined(separator: ", "),
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: [
                            deployToken.revoked ? "revoked" : nil,
                            deployToken.expired ? "expired" : nil,
                            deployToken.active == true ? "active" : nil,
                            deployToken.expiresAt.map { "expires \($0)" },
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "person.badge.key",
                        gitLabDeployTokenDeletionRequest: GitLabDeployTokenDeletionRequest(
                            projectId: deployToken.projectId,
                            tokenId: deployToken.id,
                            name: deployToken.name,
                            username: deployToken.username
                        )
                    )
                }
            )

            gitLabVariableMutationSection(projects: snapshot.projects)

            gitNativeObjectList(
                title: "CI/CD Variables",
                subtitle: "对应 GitLab Web: Settings / CI/CD / Variables。变量值不在列表中展示，只显示元数据。",
                rows: snapshot.variables.map { variable in
                    let scope = variable.environmentScope ?? "*"
                    return GitNativeObjectRowData(
                        title: variable.key,
                        subtitle: [
                            "project \(variable.projectId)",
                            "scope \(scope)",
                            variable.variableType,
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: [
                            variable.protected ? "protected" : nil,
                            variable.masked ? "masked" : nil,
                            variable.raw == true ? "raw" : nil,
                        ].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "key.horizontal",
                        variableEditRequest: GitLabVariableEditRequest(variable: variable),
                        variableDeletionRequest: GitLabVariableDeletionRequest(
                            projectId: variable.projectId,
                            key: variable.key,
                            environmentScope: scope
                        )
                    )
                }
            )
        }
    }

    private func gitLabAdminOverviewSection(_ overview: GitLabAdminOverviewSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            gitNativeSummaryGrid([
                GitNativeSummaryMetric(
                    title: "Version",
                    value: overview.version ?? "-",
                    detail: overview.enterprise == true ? "Enterprise Edition" : "Community / Unknown"
                ),
                GitNativeSummaryMetric(
                    title: "License",
                    value: overview.licensePlan ?? "-",
                    detail: overview.licenseExpired == true ? "expired" : (overview.licenseExpiresAt ?? "no expiry")
                ),
                GitNativeSummaryMetric(
                    title: "Users / Projects",
                    value: "\(overview.userCount ?? 0) / \(overview.projectCount ?? 0)",
                    detail: "active \(overview.activeUserCount ?? 0)"
                ),
                GitNativeSummaryMetric(
                    title: "Groups / Runners",
                    value: "\(overview.groupCount ?? 0) / \(overview.runnerCount ?? 0)",
                    detail: "Admin Area"
                ),
            ])

            gitNativeObjectList(
                title: "GitLab Admin Overview",
                subtitle: "对应 GitLab Web: Admin Area。当前只读展示实例版本、统计、License 和健康检查；管理员接口不可用时保留降级原因。",
                rows: [
                    GitNativeObjectRowData(
                        title: "Metadata",
                        subtitle: [
                            overview.version.map { "version \($0)" },
                            overview.revision.map { "revision \($0)" },
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: overview.enterprise == true ? "EE" : "CE / unknown",
                        systemImage: "info.circle"
                    ),
                    GitNativeObjectRowData(
                        title: "Application Statistics",
                        subtitle: [
                            "users \(overview.userCount ?? 0)",
                            "projects \(overview.projectCount ?? 0)",
                            "groups \(overview.groupCount ?? 0)",
                            "issues \(overview.issueCount ?? 0)",
                            "MR \(overview.mergeRequestCount ?? 0)",
                        ].joined(separator: " · "),
                        metadata: "active \(overview.activeUserCount ?? 0)",
                        systemImage: "chart.bar.doc.horizontal"
                    ),
                    GitNativeObjectRowData(
                        title: "License",
                        subtitle: [
                            overview.licensePlan.map { "plan \($0)" },
                            overview.licenseStartsAt.map { "starts \($0)" },
                            overview.licenseExpiresAt.map { "expires \($0)" },
                            overview.userLimit.map { "limit \($0)" },
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: overview.licenseExpired == true ? "expired" : "valid / unavailable",
                        systemImage: "checkmark.seal"
                    ),
                    GitNativeObjectRowData(
                        title: "Health Checks",
                        subtitle: [
                            overview.healthStatus.map { "health \($0)" },
                            overview.readinessStatus.map { "readiness \($0)" },
                            overview.livenessStatus.map { "liveness \($0)" },
                        ].compactMap { $0 }.joined(separator: " · "),
                        metadata: overview.unavailableReasons.isEmpty ? "all available" : "\(overview.unavailableReasons.count) unavailable",
                        systemImage: "heart.text.square"
                    ),
                ] + overview.unavailableReasons.map { reason in
                    GitNativeObjectRowData(
                        title: "Unavailable",
                        subtitle: reason,
                        metadata: "best effort",
                        systemImage: "exclamationmark.triangle"
                    )
                }
            )
        }
    }

    private var gitLabJobTraceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Job Trace")
                        .font(.headline)
                    Text("对应 GitLab Web: CI/CD / Jobs / Trace。用于在本地客户端查看构建与部署日志。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let trace = viewModel.selectedGitLabJobTrace {
                    Text("Project \(trace.projectId) · Job \(trace.jobId) · \(trace.capturedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isLoadingGitLabJobTrace {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("加载 GitLab Job trace...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if let trace = viewModel.selectedGitLabJobTrace {
                ScrollView([.vertical, .horizontal]) {
                    Text(trace.text.isEmpty ? "No trace output." : trace.text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 280)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView("未选择 Job 日志", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func gitLabDeployKeyMutationSection(projects: [GitLabProjectSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("GitLab Deploy Keys")
                    .font(.headline)
                Spacer()
                Text("新增会写入项目 Deploy Keys")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("项目", selection: $viewModel.gitLabDeployKeyDraft.projectId) {
                    Text("选择项目").tag(Int64(0))
                    ForEach(projects) { project in
                        Text(project.pathWithNamespace).tag(project.id)
                    }
                }
                .frame(width: 220)

                TextField("标题", text: $viewModel.gitLabDeployKeyDraft.title)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)

                TextField("ssh-ed25519 / ssh-rsa public key", text: $viewModel.gitLabDeployKeyDraft.key)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 320)

                Toggle("can_push", isOn: $viewModel.gitLabDeployKeyDraft.canPush)
                    .toggleStyle(.checkbox)

                Button {
                    pendingGitLabDeployKeySave = true
                } label: {
                    Label("添加 Key", systemImage: "key.badge.plus")
                }
                .disabled(!gitLabDeployKeyDraftCanSubmit || viewModel.isMutatingGitLabDeployKey)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var gitLabDeployKeyDraftCanSubmit: Bool {
        viewModel.gitLabDeployKeyDraft.projectId > 0 &&
            !viewModel.gitLabDeployKeyDraft.trimmedTitle.isEmpty &&
            viewModel.gitLabDeployKeyDraft.trimmedKey.hasPrefix("ssh-")
    }

    private func gitLabDeployTokenMutationSection(projects: [GitLabProjectSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GitLab Deploy Tokens")
                    .font(.headline)
                Spacer()
                Text("创建成功后只显示一次明文 token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Picker("项目", selection: $viewModel.gitLabDeployTokenDraft.projectId) {
                    Text("选择项目").tag(Int64(0))
                    ForEach(projects) { project in
                        Text(project.pathWithNamespace).tag(project.id)
                    }
                }
                .frame(maxWidth: 260)

                TextField("名称", text: $viewModel.gitLabDeployTokenDraft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)

                TextField("用户名，可选", text: $viewModel.gitLabDeployTokenDraft.username)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)

                TextField("到期日 YYYY-MM-DD，可选", text: $viewModel.gitLabDeployTokenDraft.expiresAt)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 190)
            }

            HStack(spacing: 16) {
                Toggle("read_repository", isOn: $viewModel.gitLabDeployTokenDraft.readRepository)
                Toggle("read_registry", isOn: $viewModel.gitLabDeployTokenDraft.readRegistry)
                Toggle("write_registry", isOn: $viewModel.gitLabDeployTokenDraft.writeRegistry)
                Toggle("read_package_registry", isOn: $viewModel.gitLabDeployTokenDraft.readPackageRegistry)
                Toggle("write_package_registry", isOn: $viewModel.gitLabDeployTokenDraft.writePackageRegistry)
                Spacer()
                Button {
                    pendingGitLabDeployTokenSave = true
                } label: {
                    if viewModel.isMutatingGitLabDeployToken {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("创建 Deploy Token", systemImage: "person.badge.key")
                    }
                }
                .disabled(!gitLabDeployTokenDraftCanSubmit || viewModel.isMutatingGitLabDeployToken)
            }
            .toggleStyle(.checkbox)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var gitLabDeployTokenDraftCanSubmit: Bool {
        viewModel.gitLabDeployTokenDraft.projectId > 0 &&
            !viewModel.gitLabDeployTokenDraft.trimmedName.isEmpty &&
            !viewModel.gitLabDeployTokenDraft.selectedScopes.isEmpty
    }

    private func gitLabTagMutationSection(projects: [GitLabProjectSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("GitLab Tags")
                    .font(.headline)
                Spacer()
                Text("创建发布标签，删除前二次确认")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("项目", selection: $viewModel.gitLabTagDraft.projectId) {
                    Text("选择项目").tag(Int64(0))
                    ForEach(projects) { project in
                        Text(project.pathWithNamespace).tag(project.id)
                    }
                }
                .frame(width: 220)

                TextField("v1.0.0", text: $viewModel.gitLabTagDraft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                TextField("ref: main / commit SHA", text: $viewModel.gitLabTagDraft.ref)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                TextField("可选 message", text: $viewModel.gitLabTagDraft.message)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)

                Button {
                    pendingGitLabTagSave = true
                } label: {
                    Label("创建 Tag", systemImage: "tag.badge.plus")
                }
                .disabled(!gitLabTagDraftCanSubmit || viewModel.isMutatingGitLabTag)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var gitLabTagDraftCanSubmit: Bool {
        viewModel.gitLabTagDraft.projectId > 0 &&
            !viewModel.gitLabTagDraft.trimmedName.isEmpty &&
            !viewModel.gitLabTagDraft.trimmedRef.isEmpty
    }

    private func gitLabVariableMutationSection(projects: [GitLabProjectSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("GitLab CI/CD Variables")
                    .font(.headline)
                Spacer()
                Text("保存前确认，value 不写入本地持久化")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("项目", selection: $viewModel.gitLabVariableDraft.projectId) {
                    Text("选择项目").tag(Int64(0))
                    ForEach(projects) { project in
                        Text(project.pathWithNamespace).tag(project.id)
                    }
                }
                .frame(width: 220)

                TextField("KEY", text: $viewModel.gitLabVariableDraft.key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)

                SecureField("VALUE", text: $viewModel.gitLabVariableDraft.value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                TextField("Scope", text: $viewModel.gitLabVariableDraft.environmentScope)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Picker("类型", selection: $viewModel.gitLabVariableDraft.variableType) {
                    Text("env_var").tag("env_var")
                    Text("file").tag("file")
                }
                .frame(width: 120)
            }

            HStack(spacing: 12) {
                Toggle("Protected", isOn: $viewModel.gitLabVariableDraft.protected)
                    .toggleStyle(.checkbox)
                Toggle("Masked", isOn: $viewModel.gitLabVariableDraft.masked)
                    .toggleStyle(.checkbox)
                Toggle("Raw", isOn: $viewModel.gitLabVariableDraft.raw)
                    .toggleStyle(.checkbox)

                Spacer()

                Button {
                    pendingGitLabVariableSave = GitLabVariableSaveRequest(mode: .create)
                } label: {
                    Label("创建", systemImage: "plus")
                }
                .disabled(!gitLabVariableDraftCanSubmit || viewModel.isMutatingGitLabVariable)

                Button {
                    pendingGitLabVariableSave = GitLabVariableSaveRequest(mode: .update)
                } label: {
                    Label("更新", systemImage: "square.and.pencil")
                }
                .disabled(!gitLabVariableDraftCanSubmit || viewModel.isMutatingGitLabVariable)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var gitLabVariableDraftCanSubmit: Bool {
        viewModel.gitLabVariableDraft.projectId > 0 &&
            !viewModel.gitLabVariableDraft.trimmedKey.isEmpty &&
            !viewModel.gitLabVariableDraft.trimmedValue.isEmpty
    }

    private var gitNativeTabPicker: some View {
        Picker("Git 原生管理区", selection: $gitNativeManagementTab) {
            ForEach(GitNativeManagementTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 560)
    }

    private func gitNativeRepositoryMutationSection(service: GitWorkbenchService) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(service == .gitea ? "新建 Gitea 仓库" : "新建 GitLab 项目")
                    .font(.headline)
                Spacer()
                Text("对应 Web: \(service == .gitea ? "Repositories / New Repository" : "Projects / New Project")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("名称", text: $viewModel.gitNativeRepositoryDraft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("描述", text: $viewModel.gitNativeRepositoryDraft.description)
                    .textFieldStyle(.roundedBorder)
                Toggle("私有", isOn: $viewModel.gitNativeRepositoryDraft.isPrivate)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Toggle("初始化 README", isOn: $viewModel.gitNativeRepositoryDraft.autoInitialize)
                    .toggleStyle(.checkbox)
                    .fixedSize()

                Button {
                    viewModel.createGitNativeRepository(
                        service: gitNativeServiceKind(service),
                        profile: profile,
                        keychain: appState.keychain,
                        giteaAPIClient: appState.giteaAPIClient,
                        gitLabAPIClient: appState.gitLabAPIClient
                    )
                } label: {
                    if viewModel.isMutatingGitNativeRepository {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("创建", systemImage: "plus")
                    }
                }
                .disabled(
                    viewModel.gitNativeRepositoryDraft.trimmedName.isEmpty ||
                    viewModel.isMutatingGitNativeRepository
                )
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var giteaRepositorySettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gitea Repository Settings")
                    .font(.headline)
                Spacer()
                Text("对应 Web: Repository / Settings / Options")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("owner/name", text: $viewModel.giteaRepositorySettingsDraft.fullName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                TextField("描述", text: $viewModel.giteaRepositorySettingsDraft.description)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 240)

                TextField("默认分支", text: $viewModel.giteaRepositorySettingsDraft.defaultBranch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Toggle("私有", isOn: $viewModel.giteaRepositorySettingsDraft.isPrivate)
                        .toggleStyle(.checkbox)
                    Toggle("归档", isOn: $viewModel.giteaRepositorySettingsDraft.archived)
                        .toggleStyle(.checkbox)
                    Toggle("Issues", isOn: $viewModel.giteaRepositorySettingsDraft.hasIssues)
                        .toggleStyle(.checkbox)
                    Toggle("Pull Requests", isOn: $viewModel.giteaRepositorySettingsDraft.hasPullRequests)
                        .toggleStyle(.checkbox)
                }

                HStack(spacing: 12) {
                    Toggle("Wiki", isOn: $viewModel.giteaRepositorySettingsDraft.hasWiki)
                        .toggleStyle(.checkbox)
                    Toggle("Packages", isOn: $viewModel.giteaRepositorySettingsDraft.hasPackages)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button {
                        pendingGiteaRepositorySettingsSave = true
                    } label: {
                        Label("保存设置", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!giteaRepositorySettingsDraftCanSubmit || viewModel.isMutatingGitNativeRepository)
                }
            }

            Text("保存会修改远端仓库基础设置和功能开关。关闭 Issues、Pull Requests、Wiki 或 Packages 后，对应 Web 页面和 API 能力会从仓库中隐藏或不可用。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var giteaRepositorySettingsDraftCanSubmit: Bool {
        let fullName = viewModel.giteaRepositorySettingsDraft.trimmedFullName
        return fullName.split(separator: "/", omittingEmptySubsequences: false).count == 2 &&
            !viewModel.giteaRepositorySettingsDraft.trimmedDefaultBranch.contains("\n")
    }

    private var gitLabProjectSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("GitLab Project Settings")
                    .font(.headline)
                Spacer()
                Text("对应 Web: Project / Settings / General")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("project id", value: $viewModel.gitLabProjectSettingsDraft.projectId, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                TextField("namespace/project", text: $viewModel.gitLabProjectSettingsDraft.pathWithNamespace)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                TextField("描述", text: $viewModel.gitLabProjectSettingsDraft.description)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)

                TextField("默认分支", text: $viewModel.gitLabProjectSettingsDraft.defaultBranch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            }

            HStack(spacing: 12) {
                Picker("可见性", selection: $viewModel.gitLabProjectSettingsDraft.visibility) {
                    Text("private").tag("private")
                    Text("internal").tag("internal")
                    Text("public").tag("public")
                }
                .frame(width: 150)

                Toggle("归档", isOn: $viewModel.gitLabProjectSettingsDraft.archived)
                    .toggleStyle(.checkbox)

                Spacer()

                Button {
                    pendingGitLabProjectSettingsSave = true
                } label: {
                    Label("保存 Project 设置", systemImage: "square.and.arrow.down")
                }
                .disabled(!gitLabProjectSettingsDraftCanSubmit || viewModel.isMutatingGitNativeRepository)
            }

            Text("保存会写入 GitLab Project 基础设置。归档项目会影响仓库写入和 CI/CD 变更，公开可见性变更请先确认团队权限边界。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var gitLabProjectSettingsDraftCanSubmit: Bool {
        viewModel.gitLabProjectSettingsDraft.projectId > 0 &&
            !viewModel.gitLabProjectSettingsDraft.trimmedPathWithNamespace.isEmpty &&
            ["private", "internal", "public"].contains(viewModel.gitLabProjectSettingsDraft.visibility) &&
            !viewModel.gitLabProjectSettingsDraft.trimmedDefaultBranch.contains("\n") &&
            !viewModel.gitLabProjectSettingsDraft.trimmedDescription.contains("\n")
    }

    private func gitNativeSummaryGrid(_ metrics: [GitNativeSummaryMetric]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.title3.weight(.semibold))
                    Text(metric.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var gitIssueFilterControl: some View {
        Picker("状态", selection: $gitIssueStateFilter) {
            ForEach(GitIssueStateFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 320)
    }

    private func gitIssueSubtitle(
        scope: String?,
        author: String?,
        assignees: [String],
        labels: [String],
        milestone: String?
    ) -> String {
        [
            scope,
            author.map { "author \($0)" },
            assignees.isEmpty ? nil : "assigned \(assignees.joined(separator: ", "))",
            labels.isEmpty ? nil : "labels \(labels.joined(separator: ", "))",
            milestone.map { "milestone \($0)" },
        ].compactMap { nonEmpty($0) }.joined(separator: " · ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func gitNativeObjectList(title: String, subtitle: String, rows: [GitNativeObjectRowData]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(rows.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if rows.isEmpty {
                ContentUnavailableView("暂无数据", systemImage: "tray")
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            GitNativeObjectRow(row: row)
                                .frame(maxWidth: .infinity)
                            if let webURL = row.webURL,
                               let url = URL(string: webURL) {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    Label("打开 Web 后台", systemImage: "safari")
                                }
                                .labelStyle(.iconOnly)
                                .help("打开 \(row.title) 的 Web 页面")
                            }
                            if let editRequest = row.giteaRepositoryEditRequest {
                                Button {
                                    fillGiteaRepositorySettingsDraft(editRequest)
                                } label: {
                                    Label("填入仓库设置", systemImage: "slider.horizontal.3")
                                }
                                .labelStyle(.iconOnly)
                                .help("填入 \(editRequest.fullName) 的仓库设置表单")
                                .disabled(viewModel.isMutatingGitNativeRepository)
                            }
                            if let editRequest = row.gitLabProjectEditRequest {
                                Button {
                                    fillGitLabProjectSettingsDraft(editRequest)
                                } label: {
                                    Label("填入 Project 设置", systemImage: "slider.horizontal.3")
                                }
                                .labelStyle(.iconOnly)
                                .help("填入 \(editRequest.pathWithNamespace) 的 Project 设置表单")
                                .disabled(viewModel.isMutatingGitNativeRepository)
                            }
                            if let editRequest = row.gitLabGroupEditRequest {
                                Button {
                                    fillGitLabGroupDraft(editRequest)
                                } label: {
                                    Label("填入 Group 设置", systemImage: "square.and.pencil")
                                }
                                .labelStyle(.iconOnly)
                                .help("填入 \(editRequest.fullPath) 的 Group 设置表单")
                                .disabled(viewModel.isMutatingGitLabGroup)
                            }
                            if let editRequest = row.giteaOrganizationEditRequest {
                                Button {
                                    fillGiteaOrganizationDraft(editRequest)
                                } label: {
                                    Label("填入组织设置", systemImage: "square.and.pencil")
                                }
                                .labelStyle(.iconOnly)
                                .help("填入 \(editRequest.username) 的组织设置表单")
                                .disabled(viewModel.isMutatingGiteaOrganization)
                            }
                            if let editRequest = row.giteaTeamEditRequest {
                                Button {
                                    fillGiteaTeamDraft(editRequest)
                                } label: {
                                    Label("填入团队设置", systemImage: "square.and.pencil")
                                }
                                .labelStyle(.iconOnly)
                                .help("填入 \(editRequest.organization)/\(editRequest.name) 的团队设置表单")
                                .disabled(viewModel.isMutatingGiteaTeam)
                            }
                            if let deletionRequest = row.deletionRequest {
                                Button(role: .destructive) {
                                    pendingGitNativeDeletion = deletionRequest
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 \(row.title)")
                                .disabled(viewModel.isMutatingGitNativeRepository)
                            }
                            if let issueStateRequest = row.issueStateRequest {
                                Button {
                                    pendingGitNativeIssueState = issueStateRequest
                                } label: {
                                    Label(issueStateRequest.action.displayName, systemImage: issueStateRequest.action == .close ? "xmark.circle" : "arrow.uturn.backward.circle")
                                }
                                .labelStyle(.iconOnly)
                                .help("\(issueStateRequest.action.displayName) \(row.title)")
                                .disabled(viewModel.isMutatingGitNativeIssueState)
                            }
                            ForEach(row.pipelineActionRequests) { request in
                                Button {
                                    pendingGitLabPipelineAction = request
                                } label: {
                                    Label(request.action.displayName, systemImage: request.action.systemImage)
                                }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(request.action == .cancel ? .red : .blue)
                                .help("\(request.action.displayName) \(row.title)")
                                .disabled(viewModel.isMutatingGitLabPipeline || request.projectId <= 0)
                            }
                            ForEach(row.jobActionRequests) { request in
                                Button {
                                    pendingGitLabJobAction = request
                                } label: {
                                    Label(request.action.displayName, systemImage: request.action.systemImage)
                                }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(request.action == .cancel ? .red : .blue)
                                .help("\(request.action.displayName) \(row.title)")
                                .disabled(viewModel.isMutatingGitLabJob || request.projectId <= 0)
                            }
                            if let traceRequest = row.gitLabJobTraceRequest {
                                Button {
                                    loadGitLabJobTrace(traceRequest)
                                } label: {
                                    Label("查看 Job 日志", systemImage: "doc.text.magnifyingglass")
                                }
                                .labelStyle(.iconOnly)
                                .help("查看 \(traceRequest.displayName) 的 Job trace")
                                .disabled(viewModel.isLoadingGitLabJobTrace || traceRequest.projectId <= 0)
                            }
                            if let variableEditRequest = row.variableEditRequest {
                                Button {
                                    fillGitLabVariableDraft(variableEditRequest)
                                } label: {
                                    Label("填入表单", systemImage: "square.and.pencil")
                                }
                                .labelStyle(.iconOnly)
                                .help("填入变量表单，输入新 value 后可更新")
                                .disabled(viewModel.isMutatingGitLabVariable)
                            }
                            if let variableDeletionRequest = row.variableDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGitLabVariableDeletion = variableDeletionRequest
                                } label: {
                                    Label("删除变量", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 GitLab 变量 \(variableDeletionRequest.key)")
                                .disabled(viewModel.isMutatingGitLabVariable)
                            }
                            if let memberEditRequest = row.memberEditRequest {
                                Button {
                                    fillGitLabMemberDraft(memberEditRequest)
                                } label: {
                                    Label("填入成员表单", systemImage: "square.and.pencil")
                                }
                                .labelStyle(.iconOnly)
                                .help("填入成员表单，可修改角色或到期日期")
                                .disabled(viewModel.isMutatingGitLabMember)
                            }
                            if let memberDeletionRequest = row.memberDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGitLabMemberDeletion = memberDeletionRequest
                                } label: {
                                    Label("移除成员", systemImage: "person.crop.circle.badge.minus")
                                }
                                .labelStyle(.iconOnly)
                                .help("移除成员 \(memberDeletionRequest.username)")
                                .disabled(viewModel.isMutatingGitLabMember)
                            }
                            if let editRequest = row.giteaTeamMemberEditRequest {
                                Button {
                                    fillGiteaTeamMemberDraft(editRequest)
                                } label: {
                                    Label("填入成员表单", systemImage: "square.and.pencil")
                                }
                                .labelStyle(.iconOnly)
                                .help("填入团队成员表单")
                                .disabled(viewModel.isMutatingGiteaTeamMember)
                            }
                            if let deletionRequest = row.giteaTeamMemberDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGiteaTeamMemberDeletion = deletionRequest
                                } label: {
                                    Label("移除成员", systemImage: "person.crop.circle.badge.minus")
                                }
                                .labelStyle(.iconOnly)
                                .help("移除成员 \(deletionRequest.username)")
                                .disabled(viewModel.isMutatingGiteaTeamMember)
                            }
                            if let deletionRequest = row.giteaTeamRepositoryDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGiteaTeamRepositoryDeletion = deletionRequest
                                } label: {
                                    Label("移除仓库", systemImage: "folder.badge.minus")
                                }
                                .labelStyle(.iconOnly)
                                .help("移除团队仓库 \(deletionRequest.repositoryFullName)")
                                .disabled(viewModel.isMutatingGiteaTeamRepository)
                            }
                            if let editRequest = row.giteaUserEditRequest {
                                Button {
                                    fillGiteaUserDraft(editRequest)
                                } label: {
                                    Label("填入用户设置", systemImage: "square.and.pencil")
                                }
                                .labelStyle(.iconOnly)
                                .help("填入 \(editRequest.username) 的用户设置表单")
                                .disabled(viewModel.isMutatingGiteaUser)
                            }
                            if let deletionRequest = row.giteaUserDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGiteaUserDeletion = deletionRequest
                                } label: {
                                    Label("删除用户", systemImage: "person.crop.circle.badge.xmark")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 Gitea 用户 \(deletionRequest.username)")
                                .disabled(viewModel.isMutatingGiteaUser)
                            }
                            if let deletionRequest = row.giteaOrganizationDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGiteaOrganizationDeletion = deletionRequest
                                } label: {
                                    Label("删除组织", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 Gitea 组织 \(deletionRequest.username)")
                                .disabled(viewModel.isMutatingGiteaOrganization)
                            }
                            if let deletionRequest = row.giteaTeamDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGiteaTeamDeletion = deletionRequest
                                } label: {
                                    Label("删除团队", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 Gitea 团队 \(deletionRequest.displayName)")
                                .disabled(viewModel.isMutatingGiteaTeam)
                            }
                            if let deletionRequest = row.giteaKeyDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGiteaKeyDeletion = deletionRequest
                                } label: {
                                    Label("删除 Key", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 SSH key \(deletionRequest.title)")
                                .disabled(viewModel.isMutatingGiteaKey)
                            }
                            if let deletionRequest = row.giteaAccessTokenDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGiteaAccessTokenDeletion = deletionRequest
                                } label: {
                                    Label("删除 Token", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 Access Token \(deletionRequest.name)")
                                .disabled(viewModel.isMutatingGiteaAccessToken)
                            }
                            if let detailRequest = row.giteaPackageDetailRequest {
                                Button {
                                    performGiteaPackageDetailLoad(detailRequest)
                                } label: {
                                    Label("查看 Package 详情", systemImage: "sidebar.right")
                                }
                                .labelStyle(.iconOnly)
                                .help("查看 Gitea package \(detailRequest.name) 详情")
                                .disabled(viewModel.isLoadingGiteaPackageDetail)
                            }
                            if let deletionRequest = row.giteaPackageDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGiteaPackageDeletion = deletionRequest
                                } label: {
                                    Label("删除 Package", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 Gitea package \(deletionRequest.name)")
                                .disabled(viewModel.isMutatingGiteaPackage)
                            }
                            if let deletionRequest = row.gitLabDeployKeyDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGitLabDeployKeyDeletion = deletionRequest
                                } label: {
                                    Label("删除 Deploy Key", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 Deploy Key \(deletionRequest.title)")
                                .disabled(viewModel.isMutatingGitLabDeployKey)
                            }
                            if let deletionRequest = row.gitLabDeployTokenDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGitLabDeployTokenDeletion = deletionRequest
                                } label: {
                                    Label("删除 Deploy Token", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 Deploy Token \(deletionRequest.name)")
                                .disabled(viewModel.isMutatingGitLabDeployToken)
                            }
                            if let deletionRequest = row.gitLabPackageDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGitLabPackageDeletion = deletionRequest
                                } label: {
                                    Label("删除 Package", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 GitLab package \(deletionRequest.name)")
                                .disabled(viewModel.isMutatingGitLabPackage)
                            }
                            if let deletionRequest = row.gitLabTagDeletionRequest {
                                Button(role: .destructive) {
                                    pendingGitLabTagDeletion = deletionRequest
                                } label: {
                                    Label("删除 Tag", systemImage: "trash")
                                }
                                .labelStyle(.iconOnly)
                                .help("删除 GitLab tag \(deletionRequest.tagName)")
                                .disabled(viewModel.isMutatingGitLabTag)
                            }
                        }
                    }
                }
            }
        }
    }

    private func gitNativeIsTokenBound(_ service: GitWorkbenchService) -> Bool {
        switch service {
        case .gitea:
            viewModel.isGiteaTokenBound
        case .gitLab:
            viewModel.isGitLabTokenBound
        }
    }

    // MARK: - Development Service Page State

    private var giteaPageState: DevelopmentServicePageState {
        if viewModel.giteaErrorMessage != nil { return .error }
        let isInstalled = viewModel.giteaInstallResult != nil
        if !isInstalled { return .notInstalled }
        if viewModel.isGiteaTokenBound { return .ready }
        return .installedNeedsToken
    }

    private var gitLabPageState: DevelopmentServicePageState {
        if viewModel.gitLabErrorMessage != nil { return .error }
        let isInstalled = viewModel.gitLabInstallResult != nil
            || viewModel.gitLabServiceInstance != nil
            || viewModel.gitLabStatusSnapshot?.installed == true
        if !isInstalled { return .notInstalled }
        if viewModel.isGitLabTokenBound { return .ready }
        return .installedNeedsToken
    }

    private var verdaccioPageState: DevelopmentServicePageState {
        if viewModel.registryErrorMessage != nil { return .error }
        let isInstalled = viewModel.verdaccioInstallResult != nil
            || viewModel.verdaccioStatusSnapshot != nil
        if !isInstalled { return .notInstalled }
        return .ready
    }

    private var activeGitPageState: DevelopmentServicePageState {
        switch selectedGitWorkbenchService {
        case .gitea: giteaPageState
        case .gitLab: gitLabPageState
        }
    }

    private func gitNativeServiceKind(_ service: GitWorkbenchService) -> GitNativeServiceKind {
        switch service {
        case .gitea:
            .gitea
        case .gitLab:
            .gitLab
        }
    }

    private func performGitNativeDeletion(_ request: GitNativeDeletionRequest) {
        switch request.kind {
        case let .giteaRepository(fullName):
            viewModel.deleteGiteaNativeRepository(
                fullName: fullName,
                profile: profile,
                keychain: appState.keychain,
                giteaAPIClient: appState.giteaAPIClient
            )
        case let .gitLabProject(projectId, pathWithNamespace):
            viewModel.deleteGitLabNativeProject(
                projectId: projectId,
                pathWithNamespace: pathWithNamespace,
                profile: profile,
                keychain: appState.keychain,
                gitLabAPIClient: appState.gitLabAPIClient
            )
        case let .gitLabGroup(groupId, fullPath):
            viewModel.deleteGitLabNativeGroup(
                groupId: groupId,
                fullPath: fullPath,
                profile: profile,
                keychain: appState.keychain,
                gitLabAPIClient: appState.gitLabAPIClient
            )
        }
    }

    private func performGitNativeIssueStateAction(_ request: GitNativeIssueStateRequest) {
        switch request.kind {
        case let .giteaIssue(repositoryFullName, issueNumber):
            viewModel.updateGiteaNativeIssueState(
                repositoryFullName: repositoryFullName,
                issueNumber: issueNumber,
                isPullRequest: false,
                action: request.action,
                profile: profile,
                keychain: appState.keychain,
                giteaAPIClient: appState.giteaAPIClient
            )
        case let .giteaPullRequest(repositoryFullName, issueNumber):
            viewModel.updateGiteaNativeIssueState(
                repositoryFullName: repositoryFullName,
                issueNumber: issueNumber,
                isPullRequest: true,
                action: request.action,
                profile: profile,
                keychain: appState.keychain,
                giteaAPIClient: appState.giteaAPIClient
            )
        case let .gitLabIssue(projectId, iid):
            viewModel.updateGitLabNativeIssueState(
                projectId: projectId,
                issueIid: iid,
                action: request.action,
                profile: profile,
                keychain: appState.keychain,
                gitLabAPIClient: appState.gitLabAPIClient
            )
        case let .gitLabMergeRequest(projectId, iid):
            viewModel.updateGitLabNativeMergeRequestState(
                projectId: projectId,
                mergeRequestIid: iid,
                action: request.action,
                profile: profile,
                keychain: appState.keychain,
                gitLabAPIClient: appState.gitLabAPIClient
            )
        }
    }

    private func performGitLabPipelineAction(_ request: GitLabPipelineActionRequest) {
        viewModel.performGitLabNativePipelineAction(
            projectId: request.projectId,
            pipelineId: request.pipelineId,
            action: request.action,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabJobAction(_ request: GitLabJobActionRequest) {
        viewModel.performGitLabNativeJobAction(
            projectId: request.projectId,
            jobId: request.jobId,
            action: request.action,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func loadGitLabJobTrace(_ request: GitLabJobTraceRequest) {
        viewModel.loadGitLabNativeJobTrace(
            projectId: request.projectId,
            jobId: request.jobId,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func giteaRepositoryFeatureSummary(_ repository: GiteaRepositorySummary) -> String {
        let enabled = [
            repository.hasIssues ? "Issues" : nil,
            repository.hasPullRequests ? "PR" : nil,
            repository.hasWiki ? "Wiki" : nil,
            repository.hasPackages ? "Packages" : nil,
        ].compactMap { $0 }
        return enabled.isEmpty ? "features off" : enabled.joined(separator: "/")
    }

    private func fillGiteaRepositorySettingsDraft(_ request: GiteaRepositoryEditRequest) {
        viewModel.giteaRepositorySettingsDraft = GiteaRepositorySettingsDraft(
            fullName: request.fullName,
            description: request.description ?? "",
            isPrivate: request.isPrivate,
            defaultBranch: request.defaultBranch ?? "",
            hasIssues: request.hasIssues,
            hasWiki: request.hasWiki,
            hasPullRequests: request.hasPullRequests,
            hasPackages: request.hasPackages,
            archived: request.isArchived
        )
    }

    private func performGiteaRepositorySettingsSave() {
        viewModel.updateGiteaNativeRepositorySettings(
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func fillGitLabProjectSettingsDraft(_ request: GitLabProjectEditRequest) {
        viewModel.gitLabProjectSettingsDraft = GitLabProjectSettingsDraft(
            projectId: request.projectId,
            pathWithNamespace: request.pathWithNamespace,
            description: request.description ?? "",
            visibility: request.visibility,
            defaultBranch: request.defaultBranch ?? "",
            archived: request.archived
        )
    }

    private func performGitLabProjectSettingsSave() {
        viewModel.updateGitLabNativeProjectSettings(
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func fillGitLabVariableDraft(_ request: GitLabVariableEditRequest) {
        viewModel.gitLabVariableDraft = GitLabVariableDraft(
            projectId: request.projectId,
            key: request.key,
            value: "",
            environmentScope: request.environmentScope,
            variableType: request.variableType ?? "env_var",
            protected: request.protected,
            masked: request.masked,
            raw: request.raw ?? false
        )
    }

    private func fillGitLabMemberDraft(_ request: GitLabMemberEditRequest) {
        viewModel.gitLabMemberDraft = GitLabMemberDraft(
            scope: request.scope,
            targetId: request.targetId,
            userId: request.userId,
            accessLevel: request.accessLevel,
            expiresAt: request.expiresAt ?? ""
        )
    }

    private func fillGitLabGroupDraft(_ request: GitLabGroupEditRequest) {
        viewModel.gitLabGroupDraft = GitLabGroupDraft(
            groupId: request.groupId,
            name: request.name,
            path: request.path,
            description: "",
            visibility: request.visibility,
            parentId: 0
        )
    }

    private func fillGiteaUserDraft(_ request: GiteaUserEditRequest) {
        viewModel.giteaUserDraft = GiteaUserDraft(
            originalUsername: request.username,
            username: request.username,
            email: request.email ?? "",
            password: "",
            fullName: request.fullName ?? "",
            mustChangePassword: false,
            isActive: request.isActive,
            isAdmin: request.isAdmin,
            prohibitLogin: false,
            restricted: false
        )
    }

    private func fillGiteaTeamMemberDraft(_ request: GiteaTeamMemberEditRequest) {
        viewModel.giteaTeamMemberDraft = GiteaTeamMemberDraft(
            teamId: request.teamId,
            username: request.username
        )
    }

    private func fillGiteaOrganizationDraft(_ request: GiteaOrganizationEditRequest) {
        viewModel.giteaOrganizationDraft = GiteaOrganizationDraft(
            originalUsername: request.username,
            username: request.username,
            fullName: request.fullName ?? "",
            description: request.description ?? "",
            website: request.website ?? "",
            visibility: request.visibility ?? "public"
        )
    }

    private func fillGiteaTeamDraft(_ request: GiteaTeamEditRequest) {
        viewModel.giteaTeamDraft = GiteaTeamDraft(
            teamId: request.teamId,
            organization: request.organization,
            name: request.name,
            description: request.description ?? "",
            permission: request.permission ?? "read",
            includesAllRepositories: request.includesAllRepositories,
            canCreateOrgRepo: request.canCreateOrgRepo,
            units: request.units.isEmpty ? ["repo.code", "repo.issues", "repo.pulls", "repo.releases"] : request.units
        )
    }

    private func performGiteaUserSave(_ request: GiteaUserSaveRequest) {
        viewModel.saveGiteaNativeUser(
            mode: request.mode,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaUserDeletion(_ request: GiteaUserDeletionRequest) {
        viewModel.deleteGiteaNativeUser(
            username: request.username,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaOrganizationSave(_ request: GiteaOrganizationSaveRequest) {
        viewModel.saveGiteaNativeOrganization(
            mode: request.mode,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaOrganizationDeletion(_ request: GiteaOrganizationDeletionRequest) {
        viewModel.deleteGiteaNativeOrganization(
            username: request.username,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaTeamSave(_ request: GiteaTeamSaveRequest) {
        viewModel.saveGiteaNativeTeam(
            mode: request.mode,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaTeamDeletion(_ request: GiteaTeamDeletionRequest) {
        viewModel.deleteGiteaNativeTeam(
            teamId: request.teamId,
            name: request.displayName,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaTeamMemberSave() {
        viewModel.addGiteaNativeTeamMember(
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaTeamMemberDeletion(_ request: GiteaTeamMemberDeletionRequest) {
        viewModel.removeGiteaNativeTeamMember(
            teamId: request.teamId,
            username: request.username,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaTeamRepositorySave() {
        viewModel.addGiteaNativeTeamRepository(
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaTeamRepositoryDeletion(_ request: GiteaTeamRepositoryDeletionRequest) {
        viewModel.removeGiteaNativeTeamRepository(
            teamId: request.teamId,
            repositoryFullName: request.repositoryFullName,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaKeySave() {
        viewModel.createGiteaNativeKey(
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaKeyDeletion(_ request: GiteaKeyDeletionRequest) {
        viewModel.deleteGiteaNativeKey(
            keyId: request.keyId,
            title: request.title,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaAccessTokenSave() {
        viewModel.createGiteaNativeAccessToken(
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaAccessTokenDeletion(_ request: GiteaAccessTokenDeletionRequest) {
        viewModel.deleteGiteaNativeAccessToken(
            username: request.username,
            tokenId: request.tokenId,
            name: request.name,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaPackageDetailLoad(_ request: GiteaPackageDetailRequest) {
        viewModel.loadGiteaNativePackageDetail(
            owner: request.owner,
            type: request.type,
            name: request.name,
            version: request.version,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGiteaPackageDeletion(_ request: GiteaPackageDeletionRequest) {
        viewModel.deleteGiteaNativePackage(
            owner: request.owner,
            type: request.type,
            name: request.name,
            version: request.version,
            profile: profile,
            keychain: appState.keychain,
            giteaAPIClient: appState.giteaAPIClient
        )
    }

    private func performGitLabDeployKeySave() {
        viewModel.createGitLabNativeDeployKey(
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabDeployKeyDeletion(_ request: GitLabDeployKeyDeletionRequest) {
        viewModel.deleteGitLabNativeDeployKey(
            projectId: request.projectId,
            keyId: request.keyId,
            title: request.title,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabDeployTokenSave() {
        viewModel.createGitLabNativeDeployToken(
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabDeployTokenDeletion(_ request: GitLabDeployTokenDeletionRequest) {
        viewModel.deleteGitLabNativeDeployToken(
            projectId: request.projectId,
            tokenId: request.tokenId,
            name: request.name,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabPackageDeletion(_ request: GitLabPackageDeletionRequest) {
        viewModel.deleteGitLabNativePackage(
            projectId: request.projectId,
            packageId: request.packageId,
            name: request.name,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabGroupSave(_ request: GitLabGroupSaveRequest) {
        switch request.mode {
        case .create:
            viewModel.createGitLabNativeGroup(
                profile: profile,
                keychain: appState.keychain,
                gitLabAPIClient: appState.gitLabAPIClient
            )
        case .update:
            viewModel.updateGitLabNativeGroup(
                profile: profile,
                keychain: appState.keychain,
                gitLabAPIClient: appState.gitLabAPIClient
            )
        }
    }

    private func performVerdaccioPackageDeletion(_ request: VerdaccioPackageDeletionRequest) {
        viewModel.deleteVerdaccioPackage(
            packageName: request.packageName,
            profile: profile,
            sshClient: appState.sshClient,
            verdaccioManager: appState.verdaccioManager
        )
    }

    private func performGitLabTagSave() {
        viewModel.createGitLabNativeTag(
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabTagDeletion(_ request: GitLabTagDeletionRequest) {
        viewModel.deleteGitLabNativeTag(
            projectId: request.projectId,
            tagName: request.tagName,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabMemberSave(_ request: GitLabMemberSaveRequest) {
        viewModel.saveGitLabNativeMember(
            mode: request.mode,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabMemberDeletion(_ request: GitLabMemberDeletionRequest) {
        viewModel.deleteGitLabNativeMember(
            scope: request.scope,
            targetId: request.targetId,
            userId: request.userId,
            username: request.username,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabVariableSave(_ request: GitLabVariableSaveRequest) {
        viewModel.saveGitLabNativeVariable(
            mode: request.mode,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private func performGitLabVariableDeletion(_ request: GitLabVariableDeletionRequest) {
        viewModel.deleteGitLabNativeVariable(
            projectId: request.projectId,
            key: request.key,
            environmentScope: request.environmentScope,
            profile: profile,
            keychain: appState.keychain,
            gitLabAPIClient: appState.gitLabAPIClient
        )
    }

    private var npmNativeWorkbenchPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                npmPageContent
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var npmPageContent: some View {
        if verdaccioPageState == .notInstalled {
            npmInstallWizard
        } else {
            npmManagementPanel
        }
    }

    // MARK: - npm Install Wizard (pre-install)

    private var npmInstallWizard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("npm 私有仓库")
                    .font(.title2.weight(.semibold))
                Text("安装 Verdaccio 私有 npm 仓库到当前服务器。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = viewModel.registryActionMessage {
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            if let error = viewModel.registryErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            verdaccioInstallSettingsSection
            registryPreflightSection

            HStack(spacing: 8) {
                Button {
                    viewModel.runRegistryPreflight(
                        profile: profile,
                        sshClient: appState.sshClient,
                        registryPreflightChecker: appState.registryPreflightChecker
                    )
                } label: {
                    if viewModel.isRunningRegistryPreflight {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("预检", systemImage: "checklist")
                    }
                }
                .disabled(isRegistryBusy || !isRegistryDraftValid)

                Button {
                    pendingVerdaccioInstall = true
                } label: {
                    if viewModel.isInstallingVerdaccio {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("安装 Verdaccio", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRegistryBusy || !isRegistryDraftValid || !isRegistryPreflightReady)
            }
        }
    }

    // MARK: - npm Management Panel (post-install)

    private var npmManagementPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            npmManagementHeader
            npmManagementTabBar

            switch npmManagementTab {
            case .overview:
                npmOverviewTab
            case .packages:
                verdaccioPackagesSection
            case .users:
                verdaccioUsersSection
            case .policy:
                verdaccioAccessPolicySection
            case .backup:
                verdaccioBackupSection
            case .proxy:
                verdaccioProxySection
            }
        }
    }

    private var npmManagementHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("npm 私有仓库")
                    .font(.title2.weight(.semibold))
                Text("Verdaccio · \(viewModel.registryDraft.listenHost):\(viewModel.registryDraft.listenPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    viewModel.loadVerdaccioStatus(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager
                    )
                } label: {
                    if viewModel.isLoadingVerdaccioStatus {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRegistryBusy)

                Button {
                    viewModel.loadVerdaccioPackages(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager
                    )
                } label: {
                    if viewModel.isLoadingVerdaccioPackages {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新包", systemImage: "shippingbox")
                    }
                }
                .disabled(isRegistryBusy)

                Button {
                    viewModel.createVerdaccioBackup(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager,
                        repository: appState.repository
                    )
                } label: {
                    if viewModel.isCreatingVerdaccioBackup {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("备份", systemImage: "archivebox")
                    }
                }
                .disabled(isRegistryBusy)
            }
        }
    }

    private var npmManagementTabBar: some View {
        Picker("npm 管理", selection: $npmManagementTab) {
            ForEach(NpmManagementTab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var npmOverviewTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let message = viewModel.registryActionMessage {
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            if let error = viewModel.registryErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            verdaccioStatusSection
            verdaccioServiceSection
        }
    }

    private var pubNativeWorkbenchPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("pub 配置助手")
                            .font(.title2.weight(.semibold))
                        Text("生成 Dart / Flutter custom hosted repository 配置；自托管 pub registry 后续单独扩展。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                pubHostedRepositorySection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func gitServiceStateTitle(_ service: GitWorkbenchService) -> String {
        switch service {
        case .gitea:
            return viewModel.giteaInstallResult == nil ? "未安装" : "已安装"
        case .gitLab:
            if let snapshot = viewModel.gitLabStatusSnapshot {
                return snapshot.installed ? snapshot.status : "未安装"
            }
            return viewModel.gitLabServiceInstance == nil ? "未安装" : "已记录"
        }
    }

    private func gitServiceStateColor(_ service: GitWorkbenchService) -> Color {
        switch service {
        case .gitea:
            return viewModel.giteaInstallResult == nil ? Color.secondary : Color.green
        case .gitLab:
            if let snapshot = viewModel.gitLabStatusSnapshot {
                return snapshot.installed ? (snapshot.status.localizedCaseInsensitiveContains("run") ? .green : .orange) : .secondary
            }
            return viewModel.gitLabServiceInstance == nil ? .secondary : .orange
        }
    }

    private func gitServiceURL(_ service: GitWorkbenchService) -> String {
        switch service {
        case .gitea:
            return viewModel.giteaInstallResult?.externalURL ?? viewModel.giteaDraft.externalURL
        case .gitLab:
            return viewModel.gitLabStatusSnapshot?.externalURL ?? viewModel.gitLabServiceInstance?.webURL ?? viewModel.gitLabDraft.externalURL
        }
    }

    private func gitServiceVersion(_ service: GitWorkbenchService) -> String {
        switch service {
        case .gitea:
            return viewModel.giteaInstallResult?.version ?? "unknown"
        case .gitLab:
            return viewModel.gitLabStatusSnapshot?.version ?? viewModel.gitLabServiceInstance?.installedVersion ?? "unknown"
        }
    }

    private func gitServiceAuthHint(_ service: GitWorkbenchService) -> String {
        switch service {
        case .gitea:
            return viewModel.giteaInstallResult == nil ? "安装后绑定管理员 Token" : "待绑定管理员 Token"
        case .gitLab:
            if viewModel.gitLabStatusSnapshot?.installed == true || viewModel.gitLabServiceInstance != nil {
                return "待绑定管理员 Token"
            }
            return "安装后绑定管理员 Token"
        }
    }

    @ViewBuilder
    private var gitLabFeedbackBanner: some View {
        if let message = viewModel.gitLabActionMessage {
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.caption)
        }
        if let error = viewModel.gitLabErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }

    private var developmentServiceRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Recommended Stack"))
                .font(.headline)
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 170), spacing: 8),
                GridItem(.flexible(minimum: 170), spacing: 8),
            ], alignment: .leading, spacing: 8) {
                developmentServiceRecommendationCard(
                    title: "Gitea",
                    subtitle: L10n.string("Lightweight private Git hosting"),
                    status: .recommended,
                    detail: L10n.string("Best fit for 2G/4G self-use servers.")
                )
                developmentServiceRecommendationCard(
                    title: "Gitea Actions",
                    subtitle: L10n.string("Automation runner"),
                    status: gitLabRecommendationStatus == .recommended ? .allowed : .recommended,
                    detail: L10n.string("Use light jobs locally; run heavy builds on another runner.")
                )
                developmentServiceRecommendationCard(
                    title: "Verdaccio",
                    subtitle: L10n.string("Private npm registry"),
                    status: .recommended,
                    detail: L10n.string("Already supported in Registries; suitable for small servers.")
                )
                developmentServiceRecommendationCard(
                    title: "GitLab CE",
                    subtitle: L10n.string("Full DevOps platform"),
                    status: gitLabRecommendationStatus,
                    detail: gitLabRecommendationDetail
                )
            }
            HStack(spacing: 8) {
                Button {
                    pendingGiteaInstall = true
                } label: {
                    if viewModel.isInstallingGitea {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L10n.string("Install Gitea"), systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isInstallingGitea)

                Button {
                    viewModel.openGiteaInBrowser()
                } label: {
                    Label(L10n.string("Open Gitea"), systemImage: "safari")
                }
                .disabled((viewModel.giteaInstallResult?.externalURL ?? viewModel.giteaDraft.externalURL).trimmingCharacters(in: .whitespacesAndNewlines) == "http://")
            }

            if let message = viewModel.giteaActionMessage {
                Label(message, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = viewModel.giteaErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let result = viewModel.giteaInstallResult {
                Text(L10n.format("Gitea status: %@%@", result.status, result.version.map { " · \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func developmentServiceRecommendationCard(
        title: String,
        subtitle: String,
        status: DevelopmentServiceRecommendationStatus,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(status.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(status.color.opacity(0.16), in: Capsule())
                    .foregroundStyle(status.color)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var gitLabInstallSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("Install Settings"))
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.validateGitLabDraftForEditing()
                } label: {
                    Label(L10n.string("Validate"), systemImage: isGitLabDraftValid ? "checkmark.circle" : "exclamationmark.triangle")
                }
                .disabled(isGitLabBusy)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.string("External URL"))
                        .foregroundStyle(.secondary)
                    TextField("http://203.0.113.10", text: $viewModel.gitLabDraft.externalURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 420)
                }
                GridRow {
                    Text(L10n.string("Edition"))
                        .foregroundStyle(.secondary)
                    Picker(L10n.string("Edition"), selection: $viewModel.gitLabDraft.edition) {
                        ForEach(GitLabServiceEdition.allCases) { edition in
                            Text(edition.displayName).tag(edition)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)
                }
                GridRow {
                    Text(L10n.string("Install Method"))
                        .foregroundStyle(.secondary)
                    Text(viewModel.gitLabDraft.installMethod.displayName)
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text(L10n.string("Firewall"))
                        .foregroundStyle(.secondary)
                    Toggle(L10n.string("Open 22/80/443 when ufw or firewalld is active"), isOn: $viewModel.gitLabDraft.openFirewallPorts)
                        .toggleStyle(.checkbox)
                }
                GridRow {
                    Text(L10n.string("Notes"))
                        .foregroundStyle(.secondary)
                    TextField(L10n.string("Optional local note"), text: $viewModel.gitLabDraft.notes)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 420)
                }
            }

            Label(gitLabDraftValidationMessage, systemImage: isGitLabDraftValid ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(isGitLabDraftValid ? Color.secondary : Color.orange)
        }
    }

    private var gitLabPreflightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("Preflight"))
                    .font(.headline)
                Spacer()
                if let report = viewModel.gitLabPreflightReport {
                    Text(report.isReady ? L10n.string("Ready") : L10n.string("Blocked"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((report.isReady ? Color.green : Color.orange).opacity(0.16), in: Capsule())
                        .foregroundStyle(report.isReady ? .green : .orange)
                }
            }

            if let report = viewModel.gitLabPreflightReport {
                LazyVGrid(columns: gitLabPreflightGridColumns, alignment: .leading, spacing: 8) {
                    ForEach(report.checks.sorted(by: gitLabPreflightCheckSort)) { check in
                        gitLabPreflightCheckCard(check)
                    }
                }
            } else {
                ContentUnavailableView(
                    L10n.string("No Preflight Yet"),
                    systemImage: "checklist",
                    description: Text(L10n.string("Run preflight to check the operating system, sudo permission, ports, memory, disk, and existing GitLab installation before installing."))
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
    }

    private var gitLabPreflightGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 220), spacing: 8, alignment: .top),
            GridItem(.flexible(minimum: 220), spacing: 8, alignment: .top),
        ]
    }

    private func gitLabPreflightCheckCard(_ check: GitLabPreflightCheck) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: gitLabPreflightIcon(check.status))
                .foregroundStyle(gitLabPreflightColor(check.status))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(check.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let remediation = check.remediation, check.status != .passed {
                    Text(remediation)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(gitLabPreflightColor(check.status).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var gitLabStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Status"))
                .font(.headline)

            if let snapshot = viewModel.gitLabStatusSnapshot {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text(L10n.string("Installed")).foregroundStyle(.secondary)
                        Text(snapshot.installed ? L10n.string("Yes") : L10n.string("No"))
                    }
                    GridRow {
                        Text(L10n.string("Status")).foregroundStyle(.secondary)
                        Text(snapshot.status)
                    }
                    GridRow {
                        Text(L10n.string("Version")).foregroundStyle(.secondary)
                        Text(snapshot.version ?? L10n.string("unknown"))
                    }
                    GridRow {
                        Text(L10n.string("External URL")).foregroundStyle(.secondary)
                        Text(snapshot.externalURL ?? viewModel.gitLabDraft.externalURL)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text(L10n.string("Web")).foregroundStyle(.secondary)
                        Text(snapshot.webReachable ? L10n.string("Reachable") : L10n.string("Not reachable yet"))
                    }
                    GridRow {
                        Text(L10n.string("Initial root password")).foregroundStyle(.secondary)
                        Text(snapshot.rootPasswordHint)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text(L10n.string("Captured")).foregroundStyle(.secondary)
                        Text(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))
                    }
                }

                if !snapshot.recentLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("Recent Logs"))
                            .font(.subheadline.weight(.semibold))
                        Text(snapshot.recentLogs)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else if let instance = viewModel.gitLabServiceInstance {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text(L10n.string("External URL")).foregroundStyle(.secondary)
                        Text(instance.externalURL)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text(L10n.string("Version")).foregroundStyle(.secondary)
                        Text(instance.installedVersion ?? L10n.string("unknown"))
                    }
                    GridRow {
                        Text(L10n.string("Status")).foregroundStyle(.secondary)
                        Text(instance.status ?? L10n.string("unknown"))
                    }
                }
            } else {
                ContentUnavailableView(
                    L10n.string("No GitLab Status"),
                    systemImage: "square.stack.3d.up",
                    description: Text(L10n.string("Install GitLab after preflight, or refresh to read an existing GitLab service on this server."))
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
    }

    private var gitLabServiceActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Service Actions"))
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(GitLabServiceAction.allCases) { action in
                    Button {
                        pendingGitLabServiceAction = action
                    } label: {
                        if viewModel.isControllingGitLabService {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(action.displayName, systemImage: gitLabServiceActionIcon(action))
                        }
                    }
                    .disabled(isGitLabBusy || !isGitLabDraftValid)
                }
            }
        }
    }

    private var gitLabBackupPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("Backup"))
                .font(.headline)
            Text(GitLabManager.backupPreviewCommand())
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Label(L10n.string("v1 only previews the GitLab backup command. Restore is intentionally manual."), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }


    private var verdaccioInstallSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Install Settings")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.validateRegistryDraftForEditing()
                } label: {
                    Label("Validate", systemImage: isRegistryDraftValid ? "checkmark.circle" : "exclamationmark.triangle")
                }
                .disabled(isRegistryBusy)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    TextField("Verdaccio", text: $viewModel.registryDraft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                }
                GridRow {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    TextField("5.31.1", text: $viewModel.registryDraft.version)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                }
                GridRow {
                    Text("Install Path")
                        .foregroundStyle(.secondary)
                    TextField("/srv/verdaccio", text: $viewModel.registryDraft.installPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 560)
                }
                GridRow {
                    Text("Data Path")
                        .foregroundStyle(.secondary)
                    TextField("/srv/verdaccio/storage", text: $viewModel.registryDraft.dataPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 560)
                }
                GridRow {
                    Text("Listen")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        TextField("127.0.0.1", text: $viewModel.registryDraft.listenHost)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: 180)
                        Text(":")
                            .foregroundStyle(.secondary)
                        TextField("4873", value: $viewModel.registryDraft.listenPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 86)
                    }
                }
                GridRow {
                    Text("Service")
                        .foregroundStyle(.secondary)
                    TextField("verdaccio", text: $viewModel.registryDraft.serviceName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 220)
                }
            }
            .disabled(isRegistryBusy)

            Label(registryDraftValidationMessage, systemImage: isRegistryDraftValid ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(isRegistryDraftValid ? Color.secondary : Color.orange)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var registryPreflightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preflight")
                .font(.headline)

            if let report = viewModel.registryPreflightReport {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    ForEach(report.checks, id: \.id) { check in
                        RegistryPreflightCheckTile(check: check)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Preflight Report",
                    systemImage: "checklist",
                    description: Text("Run preflight before installing or managing Verdaccio.")
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
    }

    private var verdaccioStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.headline)

            if let snapshot = viewModel.verdaccioStatusSnapshot {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    RegistryStatusTile(title: "Service", value: snapshot.activeState, color: snapshot.isRunning ? .green : .orange)
                    RegistryStatusTile(title: "Substate", value: snapshot.subState, color: snapshot.isRunning ? .green : .secondary)
                    RegistryStatusTile(title: "Version", value: snapshot.version ?? "unknown", color: .secondary)
                    RegistryStatusTile(title: "Storage", value: snapshot.storageBytes.map(formatBytes) ?? "unknown", color: .secondary)
                }

                if !snapshot.recentLogs.isEmpty {
                    Text(snapshot.recentLogs)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            } else {
                ContentUnavailableView("No Verdaccio Status", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
    }

    private var verdaccioServiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Service")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(VerdaccioServiceAction.allCases) { action in
                    Button(role: action == .stop ? .destructive : nil) {
                        pendingRegistryRisk = .verdaccioService(action, draft: viewModel.registryDraft)
                    } label: {
                        if viewModel.isControllingVerdaccioService {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(action.displayName, systemImage: verdaccioServiceActionIcon(action))
                        }
                    }
                    .disabled(isRegistryBusy)
                }

                Divider()
                    .frame(height: 20)

                Button(role: .destructive) {
                    pendingRegistryRisk = .verdaccioUpgrade(draft: viewModel.registryDraft)
                } label: {
                    if viewModel.isUpgradingVerdaccio {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Upgrade", systemImage: "arrow.up.circle")
                    }
                }
                .disabled(isRegistryBusy)
            }

            if let result = viewModel.verdaccioServiceActionResult {
                Label(
                    "\(result.action.displayName) completed · \(result.snapshot.activeState)/\(result.snapshot.subState)",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let result = viewModel.verdaccioUpgradeResult {
                Label(
                    "Unit updated to \(result.version) · backup \(result.backupPath)",
                    systemImage: "arrow.up.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var verdaccioAccessPolicySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Access Policy")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Upstream")
                        .foregroundStyle(.secondary)
                    TextField("https://registry.npmjs.org/", text: $viewModel.verdaccioConfigPolicyDraft.upstreamRegistryURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 420)
                }
                GridRow {
                    Text("Packages")
                        .foregroundStyle(.secondary)
                    Picker("Packages", selection: $viewModel.verdaccioConfigPolicyDraft.accessMode) {
                        ForEach(VerdaccioPackageAccessMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 480)
                }
            }
            .disabled(isRegistryBusy)

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    viewModel.saveVerdaccioConfigPolicy(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager,
                        repository: appState.repository
                    )
                } label: {
                    if viewModel.isSavingVerdaccioConfigPolicy {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Save Policy", systemImage: "lock.shield")
                    }
                }
                .disabled(isRegistryBusy || !isRegistryDraftValid || !isVerdaccioPolicyValid)

                Label(verdaccioPolicyValidationMessage, systemImage: isVerdaccioPolicyValid ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(isVerdaccioPolicyValid ? Color.secondary : Color.orange)
            }

            if let result = viewModel.verdaccioConfigSaveResult {
                Label("Saved \(result.path) · backup \(result.backupPath)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var verdaccioProxySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nginx Proxy")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Server Name")
                        .foregroundStyle(.secondary)
                    TextField("_", text: $viewModel.verdaccioProxyDraft.serverName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                GridRow {
                    Text("Config Path")
                        .foregroundStyle(.secondary)
                    TextField("/etc/nginx/conf.d/verdaccio.conf", text: $viewModel.verdaccioProxyDraft.configPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 560)
                }
                GridRow {
                    Text("Body Size")
                        .foregroundStyle(.secondary)
                    TextField("100m", text: $viewModel.verdaccioProxyDraft.clientMaxBodySize)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120)
                }
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.writeVerdaccioNginxProxy(
                        profile: profile,
                        sshClient: appState.sshClient,
                        nginxConfigManager: appState.nginxConfigManager,
                        repository: appState.repository
                    )
                } label: {
                    if viewModel.isWritingVerdaccioProxy {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Write Proxy", systemImage: "network")
                    }
                }
                .disabled(isRegistryBusy)

                Button(role: .destructive) {
                    pendingVerdaccioProxyReload = true
                } label: {
                    if viewModel.isReloadingVerdaccioProxy {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Reload Nginx", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRegistryBusy || viewModel.verdaccioProxyUpsertResult?.testResult.succeeded != true)
            }

            if let result = viewModel.verdaccioProxyUpsertResult {
                if result.testResult.succeeded {
                    Label("nginx -t passed for \(result.file.path)", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Label("nginx -t failed and the proxy config was rolled back", systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                if !result.testResult.output.isEmpty {
                    Text(result.testResult.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var pubHostedRepositorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dart / Flutter")
                .font(.headline)

            Label(
                PubRegistryResearchHarness.currentReport().supportedProductPath,
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Hosted URL")
                        .foregroundStyle(.secondary)
                    TextField("https://pub.example.com", text: $viewModel.pubHostedRepositoryDraft.hostedURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 420)
                }
                GridRow {
                    Text("Package")
                        .foregroundStyle(.secondary)
                    TextField("my_private_package", text: $viewModel.pubHostedRepositoryDraft.packageName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 260)
                }
                GridRow {
                    Text("Token Env")
                        .foregroundStyle(.secondary)
                    TextField("PUB_TOKEN", text: $viewModel.pubHostedRepositoryDraft.tokenEnvironmentVariable)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 180)
                }
            }

            Toggle("Flutter command", isOn: $viewModel.pubHostedRepositoryDraft.includeFlutterCommand)
                .toggleStyle(.checkbox)

            Button {
                viewModel.buildPubHostedRepositoryPlan()
            } label: {
                Label("Generate Config", systemImage: "doc.badge.gearshape")
            }

            if let plan = viewModel.pubHostedRepositoryPlan {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(plan.checks) { check in
                        PubHostedRepositoryCheckTile(check: check)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    PubHostedRepositorySnippetView(title: "pubspec.yaml", text: plan.pubspecSnippet)
                    PubHostedRepositorySnippetView(title: "publish_to", text: plan.publishToSnippet)
                    PubHostedRepositorySnippetView(title: "Token", text: plan.tokenCommand)
                    PubHostedRepositorySnippetView(title: "Commands", text: pubHostedRepositoryCommands(plan))
                }

                ForEach(plan.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var verdaccioBackupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backups")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Restore Path")
                        .foregroundStyle(.secondary)
                    TextField("/srv/verdaccio/backups/verdaccio-2026-06-25T12-00-00Z.tar.gz", text: $viewModel.verdaccioRestorePathDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: 560)
                }
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.createVerdaccioBackup(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager,
                        repository: appState.repository
                    )
                } label: {
                    if viewModel.isCreatingVerdaccioBackup {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Create Backup", systemImage: "archivebox")
                    }
                }
                .disabled(isRegistryBusy)

                Button(role: .destructive) {
                    pendingVerdaccioRestore = true
                } label: {
                    if viewModel.isRestoringVerdaccioBackup {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Restore", systemImage: "arrow.counterclockwise")
                    }
                }
                .disabled(isRegistryBusy || !isVerdaccioRestorePathReady)
            }

            if let backup = viewModel.verdaccioBackupResult {
                Label(
                    "Created \(backup.backupPath) · \(backup.sizeBytes.map(formatBytes) ?? "unknown")",
                    systemImage: "archivebox"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }

            if let restore = viewModel.verdaccioRestoreResult {
                Label(
                    "Restored \(restore.backupPath) · rollback \(restore.rollbackBackupPath)",
                    systemImage: "checkmark.arrow.trianglehead.counterclockwise"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var verdaccioUsersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Users")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Username")
                        .foregroundStyle(.secondary)
                    TextField("team.dev", text: $viewModel.verdaccioUsernameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                GridRow {
                    Text("Password")
                        .foregroundStyle(.secondary)
                    SecureField("8 characters minimum", text: $viewModel.verdaccioPasswordDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
                GridRow {
                    Text("Email")
                        .foregroundStyle(.secondary)
                    TextField("smoke@example.com", text: $viewModel.verdaccioEmailDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.createVerdaccioUser(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager,
                        repository: appState.repository
                    )
                } label: {
                    if viewModel.isMutatingVerdaccioUser {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Create", systemImage: "person.badge.plus")
                    }
                }
                .disabled(isRegistryBusy || !isVerdaccioUserPasswordReady)

                Button {
                    viewModel.updateVerdaccioUserPassword(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager,
                        repository: appState.repository
                    )
                } label: {
                    Label("Update Password", systemImage: "key")
                }
                .disabled(isRegistryBusy || !isVerdaccioUserPasswordReady)

                Button(role: .destructive) {
                    pendingVerdaccioUserDelete = true
                } label: {
                    Label("Delete", systemImage: "person.crop.circle.badge.minus")
                }
                .disabled(isRegistryBusy || !isVerdaccioUserReady)

                Button {
                    viewModel.runVerdaccioNpmSmokeTest(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager
                    )
                } label: {
                    if viewModel.isRunningVerdaccioNpmSmokeTest {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Run npm Test", systemImage: "checkmark.seal")
                    }
                }
                .disabled(isRegistryBusy || !isVerdaccioUserPasswordReady || !isVerdaccioEmailReady)
            }

            if let result = viewModel.verdaccioUserMutationResult {
                Label(
                    "\(verdaccioUserActionName(result.action)) \(result.username) · backup \(result.backupPath)",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }

            if let result = viewModel.verdaccioNpmSmokeTestResult {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(result.packageName)@\(result.version) verified via \(result.registryURL)", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow {
                            Text("Publish").foregroundStyle(.secondary)
                            Text(result.publishOutput.isEmpty ? "ok" : result.publishOutput)
                        }
                        GridRow {
                            Text("Install").foregroundStyle(.secondary)
                            Text(result.installOutput.isEmpty ? "ok" : result.installOutput)
                        }
                        GridRow {
                            Text("Require").foregroundStyle(.secondary)
                            Text(result.requireOutput.isEmpty ? "ok" : result.requireOutput)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var verdaccioPackagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Packages")
                .font(.headline)

            if viewModel.verdaccioPackages.isEmpty {
                ContentUnavailableView("No Packages Loaded", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.verdaccioPackages) { package in
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(package.name)
                                    .font(.headline)
                                Text("\(package.versionCount) versions · latest \(package.latestVersion ?? "unknown")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(package.sizeBytes.map(formatBytes) ?? "unknown")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                viewModel.loadVerdaccioPackageDetail(
                                    packageName: package.name,
                                    profile: profile,
                                    sshClient: appState.sshClient,
                                    verdaccioManager: appState.verdaccioManager
                                )
                            } label: {
                                if viewModel.isLoadingVerdaccioPackageDetail,
                                   viewModel.selectedVerdaccioPackageDetail?.name == package.name {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("详情", systemImage: "sidebar.right")
                                }
                            }
                            .labelStyle(.iconOnly)
                            .help("查看 \(package.name) 的 README、versions 和 dist-tags")
                            .disabled(isRegistryBusy)
                        }
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            if let detail = viewModel.selectedVerdaccioPackageDetail {
                verdaccioPackageDetailPanel(detail)
            }
        }
    }

    private func verdaccioPackageDetailPanel(_ detail: VerdaccioPackageDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.name)
                        .font(.headline)
                    Text("latest \(detail.latestVersion ?? "unknown") · \(detail.versions.count) versions · \(detail.capturedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    copyTextToPasteboard(detail.installCommand)
                } label: {
                    Label("复制安装命令", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    pendingVerdaccioPackageDeletion = VerdaccioPackageDeletionRequest(packageName: detail.name)
                } label: {
                    Label("删除包", systemImage: "trash")
                }
                .disabled(isRegistryBusy)
            }

            Text(detail.installCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            if !detail.distTags.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dist Tags")
                        .font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(detail.distTags.keys.sorted(), id: \.self) { tag in
                            Text("\(tag): \(detail.distTags[tag] ?? "")")
                                .font(.caption)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.blue.opacity(0.10), in: Capsule())
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Versions")
                    .font(.subheadline.weight(.semibold))
                ForEach(detail.versions) { version in
                    HStack(alignment: .top, spacing: 10) {
                        Text(version.version)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .frame(width: 90, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(version.description ?? "No description")
                                .font(.caption)
                            Text([
                                version.sizeBytes.map(formatBytes),
                                version.publishedAt?.formatted(date: .abbreviated, time: .shortened),
                                version.distTarball.flatMap { $0.isEmpty ? nil : $0 },
                            ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            if !version.dependencies.isEmpty {
                                Text("deps: " + version.dependencies.keys.sorted().prefix(6).joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            if let readme = detail.readme {
                VStack(alignment: .leading, spacing: 6) {
                    Text("README")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(readme)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 220)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var deploymentProjectForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.string("Deployment Project"))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    viewModel.saveDeploymentProject(
                        profile: profile,
                        repository: appState.repository,
                        serverManagementService: appState.serverManagementService
                    )
                } label: {
                    if viewModel.isSavingDeploymentProject {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L10n.string("Save"), systemImage: "tray.and.arrow.down")
                    }
                }
                .disabled(viewModel.isSavingDeploymentProject)

                Button(role: .destructive) {
                    viewModel.deleteSelectedDeploymentProject(
                        profile: profile,
                        repository: appState.repository,
                        serverManagementService: appState.serverManagementService
                    )
                } label: {
                    Label(L10n.string("Delete"), systemImage: "trash")
                }
                .disabled(viewModel.selectedDeploymentProject == nil || viewModel.isRunningDeployment)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L10n.string("Name")).foregroundStyle(.secondary)
                    TextField("Website", text: $viewModel.deploymentName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(L10n.string("Repository")).foregroundStyle(.secondary)
                    TextField("git@gitlab.com:team/project.git", text: $viewModel.deploymentRepositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text(L10n.string("Branch")).foregroundStyle(.secondary)
                    TextField("main", text: $viewModel.deploymentBranch)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text(L10n.string("Path")).foregroundStyle(.secondary)
                    TextField("/srv/app", text: $viewModel.deploymentPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text(L10n.string("Build")).foregroundStyle(.secondary)
                    TextField("npm ci && npm run build", text: $viewModel.deploymentBuildCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text(L10n.string("Restart")).foregroundStyle(.secondary)
                    TextField("systemctl restart app.service", text: $viewModel.deploymentRestartCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text(L10n.string("Health Check")).foregroundStyle(.secondary)
                    TextField("curl -fsS http://127.0.0.1:3000/health", text: $viewModel.deploymentHealthCheckCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text(L10n.string("Webhook")).foregroundStyle(.secondary)
                    Toggle(L10n.string("Enable GitLab push webhook"), isOn: $viewModel.deploymentWebhookEnabled)
                        .toggleStyle(.checkbox)
                }
                if viewModel.deploymentWebhookEnabled {
                    GridRow {
                        Text(L10n.string("Secret")).foregroundStyle(.secondary)
                        SecureField(
                            viewModel.selectedDeploymentProject?.webhookSecretRef == nil ? L10n.string("Required token") : L10n.string("Leave blank to keep existing token"),
                            text: $viewModel.deploymentWebhookSecret
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text(L10n.string("Listener")).foregroundStyle(.secondary)
                        deploymentWebhookListenerControls
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    prepareDeploymentRun()
                } label: {
                    if viewModel.isRunningDeployment {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L10n.string("Run Deployment"), systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunningDeployment || viewModel.deploymentCommandPlan == nil)

                Button {
                    prepareDeploymentRollback()
                } label: {
                    Label(L10n.string("Rollback"), systemImage: "arrow.uturn.backward")
                }
                .disabled(viewModel.isRunningDeployment || viewModel.selectedDeploymentRun?.previousCommit == nil)
                .help(L10n.string("Roll back to the previous commit captured by the selected run"))

                Button {
                    viewModel.cancelDeployment()
                } label: {
                    Label(L10n.string("Cancel"), systemImage: "stop.fill")
                }
                .disabled(!viewModel.isRunningDeployment)
            }
        }
        .onChange(of: viewModel.deploymentRepositoryURL) { _, _ in viewModel.refreshDeploymentPlan() }
        .onChange(of: viewModel.deploymentBranch) { _, _ in viewModel.refreshDeploymentPlan() }
        .onChange(of: viewModel.deploymentPath) { _, _ in viewModel.refreshDeploymentPlan() }
        .onChange(of: viewModel.deploymentBuildCommand) { _, _ in viewModel.refreshDeploymentPlan() }
        .onChange(of: viewModel.deploymentRestartCommand) { _, _ in viewModel.refreshDeploymentPlan() }
        .onChange(of: viewModel.deploymentHealthCheckCommand) { _, _ in viewModel.refreshDeploymentPlan() }
    }

    private var deploymentCommandPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.string("Command Preview"))
                    .font(.headline)
                Spacer()
                if let root = viewModel.deploymentCommandPlan?.allowedRoot {
                    Text(L10n.format("Allowed root: %@", root))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(viewModel.deploymentCommandPlan?.commandPreview ?? L10n.string("Save a valid deployment configuration to preview commands."))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var deploymentWebhookListenerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("8787", text: $viewModel.deploymentWebhookListenerPortText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 90)
                    .disabled(viewModel.isDeploymentWebhookListenerRunning)

                if viewModel.isDeploymentWebhookListenerRunning {
                    Button {
                        viewModel.stopDeploymentWebhookListener(appState.deploymentWebhookHTTPServer)
                    } label: {
                        Label(L10n.string("Stop"), systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        viewModel.startDeploymentWebhookListener(appState.deploymentWebhookHTTPServer)
                    } label: {
                        Label(L10n.string("Start"), systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            }

            if let url = viewModel.deploymentWebhookListenerURL {
                Text(url)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Label(L10n.string("Automatic deployment only works while this Mac app is running and the listener is started."), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var deploymentRunHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Runs"))
                .font(.headline)

            if viewModel.deploymentRuns.isEmpty {
                ContentUnavailableView(
                    L10n.string("No Runs Yet"),
                    systemImage: "clock",
                    description: Text(L10n.string("Run a deployment to capture status, commits, and logs."))
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Picker(L10n.string("Run"), selection: deploymentRunSelectionBinding) {
                    ForEach(viewModel.deploymentRuns) { run in
                        Text(deploymentRunTitle(run)).tag(Optional(run.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 420, alignment: .leading)

                if let run = viewModel.selectedDeploymentRun {
                    HStack {
                        Spacer()
                        Button {
                            viewModel.copySelectedDeploymentRunReportToPasteboard(profile: profile)
                        } label: {
                            Label(L10n.string("Copy Run Report"), systemImage: "doc.on.doc")
                        }
                    }

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text(L10n.string("Status")).foregroundStyle(.secondary)
                            deploymentStatusBadge(run.status)
                        }
                        GridRow {
                            Text(L10n.string("Started")).foregroundStyle(.secondary)
                            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let finishedAt = run.finishedAt {
                            GridRow {
                                Text(L10n.string("Finished")).foregroundStyle(.secondary)
                                Text(finishedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        if let previousCommit = run.previousCommit {
                            GridRow {
                                Text(L10n.string("Previous")).foregroundStyle(.secondary)
                                Text(previousCommit).font(.system(.body, design: .monospaced))
                            }
                        }
                        if let targetCommit = run.targetCommit {
                            GridRow {
                                Text(L10n.string("Target")).foregroundStyle(.secondary)
                                Text(targetCommit).font(.system(.body, design: .monospaced))
                            }
                        }
                        if let summary = run.summary {
                            GridRow {
                                Text(L10n.string("Summary")).foregroundStyle(.secondary)
                                Text(summary)
                            }
                        }
                    }

                    deploymentLogView
                }
            }
        }
    }

    private var deploymentLogView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.string("Logs"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if viewModel.isRunningDeployment {
                    Label(L10n.string("Live"), systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            if viewModel.deploymentLogs.isEmpty {
                Text(L10n.string("No logs captured for this run."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.deploymentLogs) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(entry.stepName)
                                .font(.caption.weight(.semibold))
                            Text(entry.stream.rawValue)
                                .font(.caption)
                                .foregroundStyle(deploymentLogColor(entry.stream))
                            Spacer()
                            Text(entry.createdAt.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var filesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Files")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 8) {
                    Button {
                        startCreatingRemoteFileItem(.file)
                    } label: {
                        Label("New File", systemImage: "doc.badge.plus")
                    }
                    .disabled(isRemoteFileBusy)

                    Button {
                        startCreatingRemoteFileItem(.directory)
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .disabled(isRemoteFileBusy)

                    Button {
                        chooseRemoteUploadFiles()
                    } label: {
                        Label("Upload", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isRemoteFileSelectionBusy)

                    Button {
                        chooseRemoteDownloadDirectory(for: selectedRemoteFileEntries)
                    } label: {
                        Label("Download Selected", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isRemoteFileSelectionBusy || selectedRemoteFileEntries.isEmpty)

                    Button {
                        viewModel.loadRemoteParentDirectory(
                            profile: profile,
                            sshClient: appState.sshClient,
                            remoteFileService: appState.remoteFileService
                        )
                        filePathText = RemoteFileService.parentPath(for: viewModel.remoteFilePath)
                    } label: {
                        Label("Up", systemImage: "arrow.up")
                    }
                    .disabled(isRemoteFileBusy || viewModel.remoteFilePath == "/")

                    TextField("Remote path", text: $filePathText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            loadRemoteFilesFromPathField()
                        }

                    Button {
                        loadRemoteFilesFromPathField()
                    } label: {
                        if viewModel.isLoadingRemoteFiles {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRemoteFileBusy)
                }

                if let capturedAt = viewModel.remoteDirectoryListing?.capturedAt {
                    Text("Last updated \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.remoteFileErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                if let message = viewModel.remoteFileActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }

                if viewModel.isLoadingRemoteText {
                    Label("Opening text file...", systemImage: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                }

                if viewModel.isTransferringRemoteFile {
                    Label("Transferring file...", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(.secondary)
                }

                if !viewModel.remoteFileTransferJobs.isEmpty {
                    RemoteTransferJobsView(
                        jobs: viewModel.remoteFileTransferJobs,
                        isQueuePaused: viewModel.isRemoteFileTransferQueuePaused,
                        cancel: {
                            viewModel.cancelRemoteFileTransfer()
                        },
                        cancelJob: { job in
                            viewModel.cancelRemoteFileTransfer(job)
                        },
                        clearPending: {
                            viewModel.cancelPendingRemoteFileTransfers()
                        },
                        clearCompleted: {
                            viewModel.clearCompletedRemoteFileTransferHistory(
                                profile: profile,
                                repository: appState.repository
                            )
                        },
                        pauseQueue: {
                            viewModel.pauseRemoteFileTransferQueue()
                        },
                        resumeQueue: {
                            viewModel.resumeRemoteFileTransferQueue()
                        },
                        retryAll: {
                            viewModel.retryAllRemoteFileTransfers(
                                profile: profile,
                                sshClient: appState.sshClient,
                                transferClient: appState.sshClient,
                                remoteFileService: appState.remoteFileService,
                                repository: appState.repository
                            )
                        },
                        retry: { job in
                            viewModel.retryRemoteFileTransfer(
                                job,
                                profile: profile,
                                sshClient: appState.sshClient,
                                transferClient: appState.sshClient,
                                remoteFileService: appState.remoteFileService,
                                repository: appState.repository
                            )
                        },
                        promote: { job in
                            viewModel.promoteRemoteFileTransfer(job)
                        },
                        moveUp: { job in
                            viewModel.moveRemoteFileTransferUp(job)
                        },
                        moveDown: { job in
                            viewModel.moveRemoteFileTransferDown(job)
                        }
                    )
                }
            }
            .padding(20)

            Divider()

            Group {
                if let listing = viewModel.remoteDirectoryListing {
                    remoteFileList(listing.entries)
                } else {
                    ContentUnavailableView(
                        "No Directory Loaded",
                        systemImage: "folder",
                        description: Text("Refresh to browse the remote server directory.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            filePathText = viewModel.remoteFilePath
            if viewModel.remoteDirectoryListing == nil && !viewModel.isLoadingRemoteFiles {
                viewModel.loadRemoteFiles(
                    profile: profile,
                    sshClient: appState.sshClient,
                    remoteFileService: appState.remoteFileService
                )
            }
        }
        .onChange(of: viewModel.remoteFilePath) { _, newPath in
            filePathText = newPath
            selectedRemoteFileIDs = selectedRemoteFileIDs.intersection(Set(viewModel.remoteDirectoryListing?.entries.map(\.id) ?? []))
        }
    }

    private func remoteFileList(_ entries: [RemoteFileEntry]) -> some View {
        List(entries, selection: $selectedRemoteFileIDs) { entry in
            Button {
                openRemoteFileEntry(entry)
            } label: {
                RemoteFileRow(entry: entry)
            }
            .buttonStyle(.plain)
            .tag(entry.id)
            .contextMenu {
                if entry.kind == .file {
                    Button {
                        viewModel.openRemoteTextFile(
                            entry,
                            profile: profile,
                            sshClient: appState.sshClient,
                            remoteFileService: appState.remoteFileService
                        )
                    } label: {
                        Label("Open as Text", systemImage: "doc.text")
                    }
                    .disabled(isRemoteFileBusy)
                    Button {
                        chooseRemoteDownloadDestination(for: entry)
                    } label: {
                        Label("Download", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isRemoteFileSelectionBusy)
                }
                Button {
                    startRenaming(entry)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .disabled(isRemoteFileBusy)
                Button {
                    startChangingPermissions(entry)
                } label: {
                    Label("Permissions", systemImage: "lock")
                }
                .disabled(isRemoteFileBusy)
                Button(role: .destructive) {
                    remoteFileTrashEntry = entry
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .disabled(isRemoteFileBusy)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    remoteFileTrashEntry = entry
                } label: {
                    Label("Trash", systemImage: "trash")
                }
                Button {
                    startRenaming(entry)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
                .disabled(isRemoteFileBusy)
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Empty Directory", systemImage: "folder")
            }
        }
    }

    private var servicesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("服务管理")
                            .font(.title2.weight(.semibold))
                        Text("查看服务器上已部署的 systemd 服务，并执行启动、停止、重启和日志查看。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.loadSystemdUnits(
                            profile: profile,
                            sshClient: appState.sshClient,
                            systemdServiceManager: appState.systemdServiceManager
                        )
                    } label: {
                        if viewModel.isLoadingSystemdUnits {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSystemdBusy)
                }

                HStack(spacing: 10) {
                    Picker("状态", selection: $serviceFilter) {
                        ForEach(ServiceListFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 480)

                    Spacer()

                    TextField("搜索服务名或描述", text: $serviceSearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }

                if let capturedAt = viewModel.systemdUnitList?.capturedAt {
                    Text("Last updated \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let units = viewModel.systemdUnitList?.units {
                    serviceOverview(units)
                }

                if let error = viewModel.systemdErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                if let message = viewModel.systemdActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .padding(20)

            Divider()

            Group {
                if let units = viewModel.systemdUnitList?.units {
                    HSplitView {
                        serviceTable(filteredSystemdUnits(units))
                            .frame(minWidth: 560, idealWidth: 760)
                        systemdDetailPanel
                            .frame(minWidth: 360)
                    }
                } else {
                    ContentUnavailableView(
                        "No Services Loaded",
                        systemImage: "gearshape.2",
                        description: Text("Refresh to list systemd services on the remote server.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            viewModel.loadDeploymentProjects(profile: profile, repository: appState.repository)
            if viewModel.systemdUnitList == nil && !viewModel.isLoadingSystemdUnits {
                viewModel.loadSystemdUnits(
                    profile: profile,
                    sshClient: appState.sshClient,
                    systemdServiceManager: appState.systemdServiceManager
                )
            }
        }
    }

    private func filteredSystemdUnits(_ units: [SystemdUnit]) -> [SystemdUnit] {
        let query = serviceSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return units.filter { unit in
            serviceFilter.includes(unit) &&
                (query.isEmpty ||
                 unit.name.lowercased().contains(query) ||
                 unit.description.lowercased().contains(query))
        }
    }

    private func serviceOverview(_ units: [SystemdUnit]) -> some View {
        let summary = SystemdServiceClassifier.summary(for: units)
        let columns = [GridItem(.adaptive(minimum: 145), spacing: 10)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            serviceOverviewCard(
                title: "全部服务",
                value: summary.total,
                detail: "systemd units",
                icon: "gearshape.2",
                color: .blue,
                filter: .all
            )
            serviceOverviewCard(
                title: "运行中",
                value: summary.running,
                detail: "active",
                icon: "play.circle",
                color: .green,
                filter: .running
            )
            serviceOverviewCard(
                title: "已停止",
                value: summary.stopped,
                detail: "inactive/dead",
                icon: "stop.circle",
                color: .secondary,
                filter: .stopped
            )
            serviceOverviewCard(
                title: "异常",
                value: summary.failed,
                detail: "failed",
                icon: "exclamationmark.triangle",
                color: .red,
                filter: .failed
            )
            serviceOverviewCard(
                title: "常见应用",
                value: summary.commonApplications,
                detail: "nginx/db/docker",
                icon: "square.stack.3d.up",
                color: .purple,
                filter: .app
            )
        }
    }

    private func serviceOverviewCard(
        title: String,
        value: Int,
        detail: String,
        icon: String,
        color: Color,
        filter: ServiceListFilter
    ) -> some View {
        let isSelected = serviceFilter == filter

        return Button {
            serviceFilter = filter
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(isSelected ? 0.16 : 0.08), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(value)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color.opacity(0.85) : Color.secondary.opacity(0.18), lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
        .help("筛选\(title)")
    }

    private func serviceTable(_ units: [SystemdUnit]) -> some View {
        VStack(spacing: 0) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                GridRow {
                    serviceHeader("服务名")
                    serviceHeader("状态")
                    serviceHeader("说明")
                    serviceHeader("操作")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()
                    .gridCellColumns(4)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(units) { unit in
                        serviceTableRow(unit)
                        Divider()
                    }
                }
            }
            .overlay {
                if units.isEmpty {
                    ContentUnavailableView("没有匹配服务", systemImage: "gearshape.2")
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .padding(16)
    }

    private func serviceTableRow(_ unit: SystemdUnit) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Button {
                    viewModel.selectSystemdUnit(
                        unit,
                        profile: profile,
                        sshClient: appState.sshClient,
                        systemdServiceManager: appState.systemdServiceManager
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(unit.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(unit.subState)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let category = SystemdServiceClassifier.commonApplicationName(for: unit) {
                            ServiceCategoryBadge(title: category)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                SystemdStateBadge(unit: unit)

                Text(unit.description.isEmpty ? "-" : unit.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    serviceIconButton(.start, unit: unit)
                    serviceIconButton(.stop, unit: unit)
                    serviceIconButton(.restart, unit: unit)
                    Button {
                        viewModel.selectSystemdUnit(
                            unit,
                            profile: profile,
                            sshClient: appState.sshClient,
                            systemdServiceManager: appState.systemdServiceManager
                        )
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .help("查看日志")
                    .disabled(isSystemdBusy)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(viewModel.selectedSystemdUnit?.id == unit.id ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private func serviceHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func serviceIconButton(_ action: SystemdUnitAction, unit: SystemdUnit) -> some View {
        Button {
            pendingSystemdAction = SystemdActionRequest(unit: unit, action: action)
        } label: {
            Image(systemName: systemdActionIcon(action))
                .frame(width: 24, height: 24)
        }
        .help(action.displayName)
        .disabled(isSystemdBusy || isSystemdActionRedundant(action, unit: unit))
    }

    private func isSystemdActionRedundant(_ action: SystemdUnitAction, unit: SystemdUnit) -> Bool {
        switch action {
        case .start:
            unit.isRunning
        case .stop, .restart, .reload:
            !unit.isRunning
        }
    }

    private enum ServiceListFilter: String, CaseIterable, Identifiable {
        case all
        case running
        case stopped
        case failed
        case app

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                "全部"
            case .running:
                "运行中"
            case .stopped:
                "已停止"
            case .failed:
                "异常"
            case .app:
                "常见应用"
            }
        }

        func includes(_ unit: SystemdUnit) -> Bool {
            switch self {
            case .all:
                true
            case .running:
                unit.isRunning
            case .stopped:
                !SystemdServiceClassifier.isFailed(unit) && !unit.isRunning
            case .failed:
                SystemdServiceClassifier.isFailed(unit)
            case .app:
                SystemdServiceClassifier.isCommonApplication(unit)
            }
        }
    }

    private var systemdDetailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let unit = viewModel.selectedSystemdUnit {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(unit.name)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                        Text(unit.description.isEmpty ? "No description" : unit.description)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    SystemdStateBadge(unit: unit)
                }

                HStack(spacing: 8) {
                    systemdActionButton(.start, unit: unit)
                    systemdActionButton(.stop, unit: unit)
                    systemdActionButton(.restart, unit: unit)
                    systemdActionButton(.reload, unit: unit)
                    Spacer()
                    Button {
                        viewModel.loadSystemdJournal(
                            unitName: unit.name,
                            profile: profile,
                            sshClient: appState.sshClient,
                            systemdServiceManager: appState.systemdServiceManager
                        )
                    } label: {
                        if viewModel.isLoadingSystemdJournal {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Logs", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                    .disabled(isSystemdBusy)
                }

                serviceLinkedProjectsSection(unit)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Journal")
                        .font(.headline)
                    ScrollView {
                        Text(systemdJournalText(for: unit))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                ContentUnavailableView("Select a Service", systemImage: "gearshape.2")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    private func serviceLinkedProjectsSection(_ unit: SystemdUnit) -> some View {
        let projects = DeploymentProject.projects(viewModel.deploymentProjects, referencing: unit.name)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("关联项目")
                    .font(.headline)
                Spacer()
                Text("\(projects.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if projects.isEmpty {
                Text("暂无部署项目引用 \(unit.name)。在项目 Restart 命令中使用 systemctl restart \(unit.name) 后会自动关联。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(projects) { project in
                        serviceLinkedProjectRow(project)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private func serviceLinkedProjectRow(_ project: DeploymentProject) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .foregroundStyle(.purple)
                .frame(width: 28, height: 28)
                .background(Color.purple.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(project.branch) -> \(project.deployPath)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                viewModel.selectDeploymentProject(project, repository: appState.repository)
                selectedSection = "deployments"
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .frame(width: 24, height: 24)
            }
            .help("打开部署项目")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func systemdActionButton(_ action: SystemdUnitAction, unit: SystemdUnit) -> some View {
        Button {
            pendingSystemdAction = SystemdActionRequest(unit: unit, action: action)
        } label: {
            Label(action.displayName, systemImage: systemdActionIcon(action))
        }
        .disabled(isSystemdBusy)
    }

    private func systemdActionIcon(_ action: SystemdUnitAction) -> String {
        switch action {
        case .start:
            "play.fill"
        case .stop:
            "stop.fill"
        case .restart:
            "arrow.clockwise"
        case .reload:
            "arrow.triangle.2.circlepath"
        }
    }

    private var databasesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("数据库管理")
                            .font(.title2.weight(.semibold))
                        Text("发现 MySQL、MariaDB、PostgreSQL、Redis 服务，查看状态、版本、端口、日志，并执行受控启停。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.loadDatabaseServices(
                            profile: profile,
                            sshClient: appState.sshClient,
                            databaseServiceManager: appState.databaseServiceManager
                        )
                    } label: {
                        if viewModel.isLoadingDatabaseServices {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDatabaseServiceBusy)
                }

                if let capturedAt = viewModel.databaseServiceSnapshot?.capturedAt {
                    Text("Last updated \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.databaseServiceErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                if let message = viewModel.databaseServiceActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }

                if let snapshot = viewModel.databaseServiceSnapshot {
                    databaseServiceOverview(snapshot.services)
                }
            }
            .padding(20)

            Divider()

            Group {
                if let snapshot = viewModel.databaseServiceSnapshot {
                    let filteredServices = DatabaseServiceInspector.filter(snapshot.services, by: databaseServiceFilter)
                    HSplitView {
                        databaseServiceList(filteredServices)
                            .frame(minWidth: 430, idealWidth: 520)
                        databaseServiceDetail
                            .frame(minWidth: 420)
                    }
                } else {
                    ContentUnavailableView(
                        "No Database Snapshot",
                        systemImage: "cylinder.split.1x2",
                        description: Text("Refresh to discover database services on this server.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if viewModel.databaseServiceSnapshot == nil && !viewModel.isLoadingDatabaseServices {
                viewModel.loadDatabaseServices(
                    profile: profile,
                    sshClient: appState.sshClient,
                    databaseServiceManager: appState.databaseServiceManager
                )
            }
        }
    }

    private func databaseServiceOverview(_ services: [DatabaseService]) -> some View {
        let summary = DatabaseServiceInspector.summary(for: services)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                databaseOverviewCard(title: "已安装", value: "\(summary.installed)", detail: "\(summary.total) 个候选服务", icon: "checkmark.circle", color: .green)
                databaseOverviewCard(title: "运行中", value: "\(summary.running)", detail: "active systemd", icon: "play.circle", color: .blue)
                databaseOverviewCard(title: "需关注", value: "\(summary.attention)", detail: "已安装但未运行", icon: "exclamationmark.triangle", color: summary.attention > 0 ? .orange : .secondary)
                databaseOverviewCard(title: "未发现", value: "\(summary.missing)", detail: "可后续安装", icon: "minus.circle", color: .secondary)
            }

            Picker("数据库筛选", selection: $databaseServiceFilter) {
                ForEach(DatabaseServiceFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func databaseOverviewCard(
        title: String,
        value: String,
        detail: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private func databaseServiceList(_ services: [DatabaseService]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(services) { service in
                    Button {
                        viewModel.selectDatabaseService(service)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: databaseServiceIcon(service.kind))
                                .font(.title3)
                                .frame(width: 28)
                                .foregroundStyle(service.isInstalled ? Color.accentColor : Color.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.kind.displayName)
                                    .font(.headline)
                                Text(service.version ?? "未发现安装或版本信息")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                            DatabaseServiceStateBadge(service: service)
                        }
                        .padding(12)
                        .background(
                            viewModel.selectedDatabaseService?.id == service.id
                                ? Color.accentColor.opacity(0.10)
                                : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .overlay {
            if services.isEmpty {
                ContentUnavailableView(
                    "没有匹配数据库",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("切换筛选条件或刷新服务探测结果。")
                )
            }
        }
    }

    private var databaseServiceDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let service = viewModel.selectedDatabaseService {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.kind.displayName)
                            .font(.title3.weight(.semibold))
                        Text(service.unitName ?? "未发现 systemd unit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    DatabaseServiceStateBadge(service: service)
                }

                HStack(spacing: 8) {
                    databaseServiceActionButton(.start, service: service)
                    databaseServiceActionButton(.stop, service: service)
                    databaseServiceActionButton(.restart, service: service)
                    Spacer()
                    Button {
                        viewModel.loadDatabaseServices(
                            profile: profile,
                            sshClient: appState.sshClient,
                            databaseServiceManager: appState.databaseServiceManager
                        )
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isDatabaseServiceBusy)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    databaseInfoRow("版本", service.version ?? "-")
                    databaseInfoRow("监听", service.listenEndpoints.isEmpty ? "-": service.listenEndpoints.joined(separator: ", "))
                    databaseInfoRow("默认端口", service.kind.defaultPort)
                    databaseInfoRow("数据目录", service.dataPath ?? "-")
                    databaseInfoRow("状态", service.statusText)
                }

                databaseBackupRestoreSection(service)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最近日志")
                            .font(.headline)
                        Spacer()
                        Text("只读预览")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ScrollView {
                        Text(databaseRecentLogText(service))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                ContentUnavailableView("Select a Database", systemImage: "cylinder.split.1x2")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    private func databaseInfoRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func databaseServiceActionButton(_ action: SystemdUnitAction, service: DatabaseService) -> some View {
        Button {
            pendingDatabaseAction = DatabaseServiceActionRequest(service: service, action: action)
        } label: {
            Label(action.displayName, systemImage: systemdActionIcon(action))
        }
        .disabled(isDatabaseServiceBusy || isDatabaseServiceActionDisabled(action, service: service))
    }

    private func isDatabaseServiceActionDisabled(_ action: SystemdUnitAction, service: DatabaseService) -> Bool {
        guard service.isInstalled, service.unitName != nil else { return true }
        switch action {
        case .start:
            return service.isRunning
        case .stop, .restart, .reload:
            return !service.isRunning
        }
    }

    private func databaseServiceIcon(_ kind: DatabaseServiceKind) -> String {
        switch kind {
        case .mysql, .mariadb:
            "cylinder"
        case .postgresql:
            "cylinder.split.1x2"
        case .redis:
            "memorychip"
        }
    }

    private func databaseRecentLogText(_ service: DatabaseService) -> String {
        let text = service.recentLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "暂无 journal 日志。" : text
    }

    private func databaseBackupRestoreSection(_ service: DatabaseService) -> some View {
        let plan = DatabaseServiceManager.backupRestorePlan(for: service)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("备份/恢复入口")
                        .font(.headline)
                    Text("V1 支持受控创建备份；恢复只提供命令预览和复制，不在客户端直接执行。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    pendingDatabaseBackup = DatabaseBackupRequest(service: service, plan: plan)
                } label: {
                    if viewModel.isCreatingDatabaseBackup {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Create Backup", systemImage: "externaldrive.badge.plus")
                    }
                }
                .disabled(isDatabaseServiceBusy || !service.isInstalled)
            }

            if !service.isInstalled {
                Label("未发现 \(service.kind.displayName) 安装信息，命令仅作为参考。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            databaseCommandBlock(
                title: "备份命令",
                command: plan.backupCommand,
                copyTitle: "Copy Backup",
                isEnabled: service.isInstalled
            )

            databaseCommandBlock(
                title: "恢复命令",
                command: plan.restoreCommand,
                copyTitle: "Copy Restore",
                isEnabled: service.isInstalled
            )

            if let result = viewModel.databaseBackupResult, result.serviceKind == service.kind {
                Label("最近备份：\(result.backupPath)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("前置条件")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.prerequisites, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle")
                        }
                    }
                }
                GridRow {
                    Text("风险提示")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.warnings, id: \.self) { item in
                            Label(item, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func databaseCommandBlock(
        title: String,
        command: String,
        copyTitle: String,
        isEnabled: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    copyDatabaseCommandToPasteboard(command)
                } label: {
                    Label(copyTitle, systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(!isEnabled)
            }
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func copyDatabaseCommandToPasteboard(_ command: String) {
        copyTextToPasteboard(command)
    }

    private func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private var nginxPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("网站管理")
                        .font(.title2.weight(.semibold))
                        Text("识别 Nginx server block，展示域名、监听端口、根目录、SSL、反向代理和配置文件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.testNginxConfig(
                            profile: profile,
                            sshClient: appState.sshClient,
                            nginxConfigManager: appState.nginxConfigManager
                        )
                    } label: {
                        if viewModel.isTestingNginxConfig {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Test", systemImage: "checkmark.seal")
                        }
                    }
                    .disabled(isNginxBusy)

                    Button {
                        pendingNginxReload = true
                    } label: {
                        if viewModel.isReloadingNginx {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Reload", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isNginxBusy)

                    Button {
                        viewModel.loadNginxConfigs(
                            profile: profile,
                            sshClient: appState.sshClient,
                            nginxConfigManager: appState.nginxConfigManager
                        )
                    } label: {
                        if viewModel.isLoadingNginxConfigs {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isNginxBusy)
                }

                if let capturedAt = viewModel.nginxSiteList?.capturedAt ?? viewModel.nginxConfigList?.capturedAt {
                    Text("Last updated \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.nginxErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                if let message = viewModel.nginxActionMessage {
                    Label(message, systemImage: viewModel.nginxTestResult?.succeeded == false ? "xmark.octagon" : "checkmark.circle")
                        .foregroundStyle(viewModel.nginxTestResult?.succeeded == false ? .orange : .green)
                }

                if let sites = viewModel.nginxSiteList?.sites {
                    nginxSiteOverview(sites)
                }
            }
            .padding(20)

            Divider()

            Group {
                if let files = viewModel.nginxConfigList?.files {
                    let filteredSites = NginxSiteInspector.filter(viewModel.nginxSiteList?.sites ?? [], by: nginxSiteFilter)
                    HSplitView {
                        nginxWebsiteSidebar(files: files, sites: filteredSites)
                            .frame(minWidth: 420, idealWidth: 520)
                        nginxConfigDetailPanel
                            .frame(minWidth: 420)
                    }
                } else {
                    ContentUnavailableView(
                        "No Nginx Configs Loaded",
                        systemImage: "network",
                        description: Text("Refresh to inspect the remote Nginx configuration directory.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if viewModel.nginxConfigList == nil && !viewModel.isLoadingNginxConfigs {
                viewModel.loadNginxConfigs(
                    profile: profile,
                    sshClient: appState.sshClient,
                    nginxConfigManager: appState.nginxConfigManager
                )
            }
        }
    }

    private func nginxSiteOverview(_ sites: [NginxSite]) -> some View {
        let summary = NginxSiteInspector.summary(for: sites)
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
                nginxOverviewCard(title: "站点", value: "\(summary.total)", detail: "server blocks", icon: "network", color: .blue)
                nginxOverviewCard(title: "SSL", value: "\(summary.sslEnabled)", detail: "启用证书", icon: "lock.shield", color: .green)
                nginxOverviewCard(title: "反向代理", value: "\(summary.reverseProxy)", detail: "proxy_pass", icon: "arrow.triangle.branch", color: .purple)
                nginxOverviewCard(title: "证书异常", value: "\(summary.certificateIssues)", detail: "缺失/过期/读取失败", icon: "exclamationmark.triangle", color: summary.certificateIssues > 0 ? .orange : .secondary)
            }

            Picker("站点筛选", selection: $nginxSiteFilter) {
                ForEach(NginxSiteFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func nginxOverviewCard(
        title: String,
        value: String,
        detail: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private func nginxWebsiteSidebar(files: [NginxConfigFile], sites: [NginxSite]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("网站")
                        .font(.headline)
                    Spacer()
                    Text("\(sites.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                nginxSiteList(sites)
            }
            .frame(minHeight: 260)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("配置文件")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                nginxConfigList(files)
            }
        }
    }

    private func nginxSiteList(_ sites: [NginxSite]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(sites) { site in
                    Button {
                        viewModel.selectNginxSite(
                            site,
                            profile: profile,
                            sshClient: appState.sshClient,
                            nginxConfigManager: appState.nginxConfigManager
                        )
                    } label: {
                        NginxSiteRow(site: site, isSelected: viewModel.selectedNginxSite?.id == site.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .overlay {
            if sites.isEmpty {
                ContentUnavailableView("No Sites Found", systemImage: "network")
            }
        }
    }

    private func nginxConfigList(_ files: [NginxConfigFile]) -> some View {
        List(files, selection: nginxConfigSelectionBinding) { file in
            NginxConfigRow(file: file)
                .tag(file.id)
        }
        .overlay {
            if files.isEmpty {
                ContentUnavailableView("No Config Files", systemImage: "network")
            }
        }
    }

    private var nginxConfigDetailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let file = viewModel.selectedNginxConfig {
                if let site = viewModel.selectedNginxSite {
                    nginxSiteSummary(site)
                    Divider()
                }

                nginxReverseProxyBuilderSection
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.path)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(nginxConfigMetadata(file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.isLoadingNginxConfigContent {
                    ProgressView()
                        .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Config")
                            .font(.headline)
                        Spacer()
                        Button {
                            viewModel.nginxConfigDraft = viewModel.nginxConfigContent?.content ?? ""
                        } label: {
                            Label("Revert", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(isNginxBusy || !isNginxDraftDirty)

                        Button {
                            pendingNginxSave = true
                        } label: {
                            if viewModel.isSavingNginxConfig {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isNginxBusy || !isNginxDraftDirty || viewModel.nginxConfigContent?.file.id != file.id)
                    }

                    TextEditor(text: $viewModel.nginxConfigDraft)
                        .font(.system(.caption, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .disabled(viewModel.nginxConfigContent?.file.id != file.id || viewModel.isLoadingNginxConfigContent)
                        .frame(minHeight: 260)
                        .padding(8)
                }
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                if let result = viewModel.nginxTestResult {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            result.succeeded ? "nginx -t passed" : "nginx -t failed",
                            systemImage: result.succeeded ? "checkmark.circle" : "xmark.octagon"
                        )
                        .foregroundStyle(result.succeeded ? .green : .orange)
                        Text(result.output.isEmpty ? "(empty)" : result.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                ContentUnavailableView("Select a Config", systemImage: "network")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    private var nginxReverseProxyBuilderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("反向代理")
                        .font(.headline)
                    Text("生成 Nginx server block，写入前会运行 nginx -t，失败自动回滚。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(nginxReverseProxyPreviewText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(!isNginxReverseProxyDraftValid)

                Button {
                    pendingNginxReverseProxyWrite = true
                } label: {
                    if viewModel.isWritingNginxReverseProxy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Write Config", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isNginxBusy || !isNginxReverseProxyDraftValid)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("域名")
                        .foregroundStyle(.secondary)
                    TextField("example.com", text: $viewModel.nginxReverseProxyDraft.serverName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("上游")
                        .foregroundStyle(.secondary)
                    TextField("http://127.0.0.1:3000", text: $viewModel.nginxReverseProxyDraft.upstreamURL)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("配置路径")
                        .foregroundStyle(.secondary)
                    TextField("/etc/nginx/conf.d/example-proxy.conf", text: $viewModel.nginxReverseProxyDraft.configPath)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("上传限制")
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("50m", text: $viewModel.nginxReverseProxyDraft.clientMaxBodySize)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                        Toggle("WebSocket", isOn: $viewModel.nginxReverseProxyDraft.enableWebSocket)
                    }
                }
            }

            if let error = nginxReverseProxyDraftError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(nginxReverseProxyPreviewText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func nginxSiteSummary(_ site: NginxSite) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(site.primaryName)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(site.configPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                HStack(spacing: 8) {
                    NginxSiteBadge(
                        title: NginxCertificateDisplay.badgeTitle(for: site),
                        color: NginxCertificateDisplay.badgeColor(for: site)
                    )
                    if site.isReverseProxy {
                        NginxSiteBadge(title: "Proxy", color: .blue)
                    }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                nginxSiteInfoRow("域名", site.serverNames.joined(separator: ", "))
                nginxSiteInfoRow("监听", site.listen.isEmpty ? "-" : site.listen.joined(separator: ", "))
                nginxSiteInfoRow("根目录", site.root ?? "-")
                nginxSiteInfoRow("反向代理", site.proxyPasses.isEmpty ? "-" : site.proxyPasses.joined(separator: ", "))
                if site.hasSSL {
                    nginxSiteInfoRow("证书", NginxCertificateDisplay.certificatePathSummary(for: site))
                    nginxSiteInfoRow("到期", NginxCertificateDisplay.expirySummary(for: site))
                    nginxSiteInfoRow("颁发者", NginxCertificateDisplay.issuerSummary(for: site))
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func nginxSiteInfoRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private var firewallPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Firewall")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        viewModel.loadFirewallSnapshot(
                            profile: profile,
                            sshClient: appState.sshClient,
                            firewallManager: appState.firewallManager
                        )
                    } label: {
                        if viewModel.isLoadingFirewall {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoadingFirewall)
                }

                if let capturedAt = viewModel.firewallSnapshot?.capturedAt {
                    Text("Last updated \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.firewallErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                if let message = viewModel.firewallActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .padding(20)

            Divider()

            if let snapshot = viewModel.firewallSnapshot {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        FirewallSummaryTile(title: "Backend", value: snapshot.backend.displayName, systemImage: "shield")
                        FirewallSummaryTile(title: "Status", value: snapshot.status, systemImage: "checkmark.shield")
                    }

                    firewallRuleEditor(snapshot: snapshot)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rules")
                            .font(.headline)
                        ScrollView {
                            Text(snapshot.rulesText)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            } else {
                ContentUnavailableView(
                    "No Firewall Rules Loaded",
                    systemImage: "firewall",
                    description: Text("Refresh to detect ufw, firewalld, nftables, or iptables on the remote server.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel.firewallSnapshot == nil && !viewModel.isLoadingFirewall {
                viewModel.loadFirewallSnapshot(
                    profile: profile,
                    sshClient: appState.sshClient,
                    firewallManager: appState.firewallManager
                )
            }
        }
    }

    private func firewallRuleEditor(snapshot: FirewallSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Limited Rule")
                    .font(.headline)
                Spacer()
                Button {
                    prepareFirewallRule(snapshot: snapshot)
                } label: {
                    if viewModel.isMutatingFirewall {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(firewallRuleMutation.displayName, systemImage: firewallRuleMutation == .add ? "plus.circle" : "minus.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isFirewallBusy)
            }

            HStack(spacing: 10) {
                Picker("Mode", selection: $firewallRuleMutation) {
                    ForEach(FirewallRuleMutationAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Picker("Direction", selection: $firewallRuleDirection) {
                    ForEach(FirewallRuleDirection.allCases) { direction in
                        Text(direction.displayName).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)

                Picker("Action", selection: $firewallRuleAction) {
                    ForEach(FirewallRuleAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            HStack(spacing: 10) {
                Picker("Protocol", selection: $firewallRuleProtocol) {
                    ForEach(FirewallRuleProtocol.allCases) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                TextField("Port", text: $firewallRulePort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)

                TextField("CIDR", text: $firewallRuleCIDR)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160, maxWidth: 220)
            }

            if let draft = currentFirewallRuleDraft,
               let command = try? FirewallManager.command(for: draft, snapshot: snapshot) {
                RiskPreviewView(risk: RemoteOperationRiskFactory.firewallRule(draft, backend: snapshot.backend, command: command))
            } else if snapshot.backend == .nft {
                Label("nftables edits require an existing inet/ip filter input or output chain.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var securityGroupsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Security Groups")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        viewModel.loadCloudSecurityGroups(
                            profile: profile,
                            cloudSecurityGroupService: appState.cloudSecurityGroupService
                        )
                    } label: {
                        if viewModel.isLoadingCloudSecurityGroups {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCloudSecurityGroupBusy)
                }

                if let list = viewModel.cloudSecurityGroupList {
                    Text("Region \(list.regionId) · \(list.groups.count) groups · Last updated \(list.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = viewModel.cloudSecurityGroupErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                if let message = viewModel.cloudSecurityGroupActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .padding(20)

            Divider()

            Group {
                if let groups = viewModel.cloudSecurityGroupList?.groups {
                    HSplitView {
                        cloudSecurityGroupList(groups)
                            .frame(minWidth: 340, idealWidth: 420)
                        cloudSecurityGroupDetailPanel
                            .frame(minWidth: 500)
                    }
                } else {
                    ContentUnavailableView(
                        "No Security Groups Loaded",
                        systemImage: "lock.shield",
                        description: Text("Refresh after linking this server to a cloud instance with a security-groups capable account.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if viewModel.cloudSecurityGroupList == nil && !viewModel.isLoadingCloudSecurityGroups {
                viewModel.loadCloudSecurityGroups(
                    profile: profile,
                    cloudSecurityGroupService: appState.cloudSecurityGroupService
                )
            }
        }
    }

    private func cloudSecurityGroupList(_ groups: [CloudSecurityGroup]) -> some View {
        List(groups, selection: cloudSecurityGroupSelectionBinding) { group in
            CloudSecurityGroupRow(group: group)
                .tag(group.id)
        }
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView("No Security Groups", systemImage: "lock.shield")
            }
        }
    }

    private var cloudSecurityGroupDetailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let group = viewModel.selectedCloudSecurityGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.title3.weight(.semibold))
                    Text(group.securityGroupId)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let description = group.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.isLoadingCloudSecurityGroupPolicies {
                    ProgressView()
                        .controlSize(.small)
                }

                if let snapshot = viewModel.cloudSecurityGroupPolicySnapshot,
                   snapshot.group.id == group.id {
                    HStack(spacing: 12) {
                        FirewallSummaryTile(title: "Ingress", value: "\(snapshot.ingress.count)", systemImage: "arrow.down.to.line")
                        FirewallSummaryTile(title: "Egress", value: "\(snapshot.egress.count)", systemImage: "arrow.up.to.line")
                        FirewallSummaryTile(title: "Version", value: snapshot.version ?? "unknown", systemImage: "number")
                    }

                    cloudSecurityGroupPreviewPanel(snapshot)
                    cloudSecurityRuleSection(title: "Ingress", rules: snapshot.ingress)
                    cloudSecurityRuleSection(title: "Egress", rules: snapshot.egress)
                } else {
                    ContentUnavailableView("No Rules Loaded", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("Select a Security Group", systemImage: "lock.shield")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    private func cloudSecurityGroupPreviewPanel(_ snapshot: CloudSecurityGroupPolicySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rule Preview")
                    .font(.headline)
                Spacer()
                Button {
                    securityGroupRulePreview = CloudSecurityGroupRuleChangePreview.adding(
                        draft: CloudSecurityGroupRuleDraft(
                            direction: securityGroupDraftDirection,
                            protocolName: securityGroupDraftProtocol,
                            port: securityGroupDraftPort,
                            cidrBlock: securityGroupDraftCIDR,
                            action: securityGroupDraftAction,
                            description: securityGroupDraftDescription
                        ),
                        to: snapshot
                    )
                } label: {
                    Label("Preview", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Picker("Direction", selection: $securityGroupDraftDirection) {
                        ForEach(CloudSecurityGroupRuleDirection.allCases) { direction in
                            Text(direction.displayName).tag(direction)
                        }
                    }
                    TextField("Protocol", text: $securityGroupDraftProtocol)
                    TextField("Port", text: $securityGroupDraftPort)
                    TextField("CIDR", text: $securityGroupDraftCIDR)
                    TextField("Action", text: $securityGroupDraftAction)
                }
            }
            .textFieldStyle(.roundedBorder)

            TextField("Description", text: $securityGroupDraftDescription)
                .textFieldStyle(.roundedBorder)

            if let preview = securityGroupRulePreview,
               preview.group.id == snapshot.group.id {
                VStack(alignment: .leading, spacing: 8) {
                    RiskPreviewView(risk: RemoteOperationRiskFactory.securityGroupChange(preview))
                    HStack(spacing: 12) {
                        FirewallSummaryTile(title: "Ingress After", value: "\(preview.afterIngressCount)", systemImage: "arrow.down.to.line")
                        FirewallSummaryTile(title: "Egress After", value: "\(preview.afterEgressCount)", systemImage: "arrow.up.to.line")
                    }
                    CloudSecurityGroupRuleRow(rule: preview.proposedRule)
                    Button {
                        pendingCloudSecurityGroupRule = CloudSecurityGroupRuleRequest(preview: preview)
                    } label: {
                        if viewModel.isMutatingCloudSecurityGroupRule {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Apply", systemImage: "checkmark.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCloudSecurityGroupBusy)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cloudSecurityRuleSection(title: String, rules: [CloudSecurityGroupRule]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if rules.isEmpty {
                Text("No rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(rules) { rule in
                            HStack(alignment: .top, spacing: 8) {
                                CloudSecurityGroupRuleRow(rule: rule)
                                Spacer()
                                Button {
                                    if let snapshot = viewModel.cloudSecurityGroupPolicySnapshot {
                                        pendingCloudSecurityGroupRule = CloudSecurityGroupRuleRequest(
                                            preview: CloudSecurityGroupRuleChangePreview.removing(rule: rule, from: snapshot)
                                        )
                                    }
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .tint(.red)
                                .disabled(isCloudSecurityGroupBusy)
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 120, maxHeight: 240)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var environmentPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Environment")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        viewModel.loadEnvironmentFiles(
                            profile: profile,
                            sshClient: appState.sshClient,
                            environmentFileManager: appState.environmentFileManager
                        )
                    } label: {
                        if viewModel.isLoadingEnvironmentFiles {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isEnvironmentBusy)
                }

                if let capturedAt = viewModel.environmentFileList?.capturedAt {
                    Text("Last updated \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let files = viewModel.environmentFileList?.files {
                    environmentOverview(files)
                }

                if let error = viewModel.environmentErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                if let message = viewModel.environmentActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .padding(20)

            Divider()

            Group {
                if let files = viewModel.environmentFileList?.files {
                    HSplitView {
                        environmentFileList(files)
                            .frame(minWidth: 360, idealWidth: 440)
                        environmentFileDetailPanel
                            .frame(minWidth: 420)
                    }
                } else {
                    ContentUnavailableView(
                        "No Environment Files Loaded",
                        systemImage: "slider.horizontal.3",
                        description: Text("Refresh to discover common .env, systemd drop-in, /etc/default, and /etc/sysconfig files.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if viewModel.environmentFileList == nil && !viewModel.isLoadingEnvironmentFiles {
                viewModel.loadEnvironmentFiles(
                    profile: profile,
                    sshClient: appState.sshClient,
                    environmentFileManager: appState.environmentFileManager
                )
            }
            if !viewModel.didLoadDeploymentProjects {
                viewModel.loadDeploymentProjectSummary(profile: profile, repository: appState.repository)
            }
        }
    }

    private func environmentOverview(_ files: [EnvironmentFile]) -> some View {
        let appCount = files.filter { $0.source == "app" || $0.path.contains("/var/www/") || $0.path.contains("/opt/") || $0.path.contains("/srv/") }.count
        let osCount = files.filter { $0.source == "os" || $0.path.hasPrefix("/etc/default/") || $0.path.hasPrefix("/etc/sysconfig/") }.count
        let systemdCount = files.filter { $0.source == "systemd" || $0.path.contains(".service.d/") }.count
        let linkedCount = files.filter { !linkedDeploymentProjects(for: $0).isEmpty }.count
        let columns = [GridItem(.adaptive(minimum: 140), spacing: 10)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            environmentOverviewCard(title: "配置文件", value: "\(files.count)", detail: "env sources", icon: "slider.horizontal.3", color: .blue)
            environmentOverviewCard(title: "应用配置", value: "\(appCount)", detail: ".env", icon: "app.connected.to.app.below.fill", color: .purple)
            environmentOverviewCard(title: "系统配置", value: "\(osCount)", detail: "/etc/default", icon: "gearshape.2", color: .secondary)
            environmentOverviewCard(title: "服务配置", value: "\(systemdCount)", detail: "systemd drop-in", icon: "rectangle.stack.badge.gearshape", color: .green)
            environmentOverviewCard(title: "关联项目", value: "\(linkedCount)", detail: "deploy path/service", icon: "arrow.down.doc", color: .orange)
        }
    }

    private func environmentOverviewCard(
        title: String,
        value: String,
        detail: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func environmentFileList(_ files: [EnvironmentFile]) -> some View {
        List(files, selection: environmentFileSelectionBinding) { file in
            EnvironmentFileRow(file: file)
                .tag(file.id)
        }
        .overlay {
            if files.isEmpty {
                ContentUnavailableView("No Environment Files", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var environmentFileDetailPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let file = viewModel.selectedEnvironmentFile {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.path)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(environmentFileMetadata(file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                environmentFileSummaryPanel(file)

                if viewModel.isLoadingEnvironmentFileContent {
                    ProgressView()
                        .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Variables")
                            .font(.headline)
                        Spacer()
                        Button {
                            viewModel.environmentFileDraft = viewModel.environmentFileContent?.content ?? ""
                        } label: {
                            Label("Revert", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(isEnvironmentBusy || !isEnvironmentDraftDirty)

                        Button {
                            pendingEnvironmentSave = true
                        } label: {
                            if viewModel.isSavingEnvironmentFile {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isEnvironmentBusy || !isEnvironmentDraftDirty || viewModel.environmentFileContent?.file.id != file.id)
                    }

                    TextEditor(text: $viewModel.environmentFileDraft)
                        .font(.system(.caption, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .disabled(viewModel.environmentFileContent?.file.id != file.id || viewModel.isLoadingEnvironmentFileContent)
                        .frame(minHeight: 320)
                        .padding(8)
                }
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView("Select an Environment File", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
    }

    private func environmentFileSummaryPanel(_ file: EnvironmentFile) -> some View {
        let originalContent = viewModel.environmentFileContent?.file.id == file.id ? viewModel.environmentFileContent?.content ?? "" : ""
        let draftContent = viewModel.environmentFileContent?.file.id == file.id ? viewModel.environmentFileDraft : originalContent
        let originalAnalysis = EnvironmentVariableInspector.analyze(originalContent)
        let draftAnalysis = EnvironmentVariableInspector.analyze(draftContent)
        let changes = EnvironmentVariableInspector.changeSummary(from: originalContent, to: draftContent)
        let linkedProjects = linkedDeploymentProjects(for: file)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("配置摘要")
                    .font(.headline)
                Spacer()
                if changes.hasChanges {
                    Label("\(changes.allChangedKeys.count) 个键有变更", systemImage: "pencil.and.list.clipboard")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                environmentFact("变量", "\(draftAnalysis.variableCount)", "原始 \(originalAnalysis.variableCount)")
                environmentFact("敏感键", EnvironmentVariableInspector.maskedKeyList(draftAnalysis.sensitiveKeys), "仅显示键名")
                environmentFact("关联项目", linkedProjects.isEmpty ? "None" : linkedProjects.map(\.name).joined(separator: ", "), "部署目录/服务")
                environmentFact("来源", environmentSourceTitle(file), file.source)
            }

            if changes.hasChanges {
                VStack(alignment: .leading, spacing: 6) {
                    environmentChangeRow(title: "新增", keys: changes.addedKeys, color: .green)
                    environmentChangeRow(title: "修改", keys: changes.changedKeys, color: .orange)
                    environmentChangeRow(title: "删除", keys: changes.removedKeys, color: .red)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private func environmentFact(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func environmentChangeRow(title: String, keys: [String], color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 36, alignment: .leading)
            Text(keys.isEmpty ? "None" : EnvironmentVariableInspector.maskedKeyList(keys, limit: 8))
                .font(.caption)
                .foregroundStyle(keys.isEmpty ? .secondary : .primary)
                .lineLimit(2)
        }
    }

    private func linkedDeploymentProjects(for file: EnvironmentFile) -> [DeploymentProject] {
        let path = file.path
        let systemdServiceName = environmentFileSystemdServiceName(path)
        return viewModel.deploymentProjects.filter { project in
            let deployPath = project.deployPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let normalizedDeployPath = "/\(deployPath)"
            let isInDeployPath = !project.deployPath.isEmpty &&
                (path == "\(normalizedDeployPath)/.env" || path.hasPrefix("\(normalizedDeployPath)/"))
            let isServiceDropIn = systemdServiceName.map { project.referencedSystemdUnitNames.contains($0) } ?? false
            return isInDeployPath || isServiceDropIn
        }
    }

    private func environmentFileSystemdServiceName(_ path: String) -> String? {
        let prefix = "/etc/systemd/system/"
        guard path.hasPrefix(prefix) else {
            return nil
        }
        let remaining = String(path.dropFirst(prefix.count))
        guard let serviceRange = remaining.range(of: ".service.d/")
        else { return nil }
        return "\(remaining[..<serviceRange.lowerBound]).service"
    }

    private func environmentSourceTitle(_ file: EnvironmentFile) -> String {
        switch file.source {
        case "app":
            "Application"
        case "os":
            "OS default"
        case "systemd":
            "systemd"
        case "user":
            "User"
        default:
            file.source
        }
    }

    private var cronPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Cron")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        viewModel.loadCron(
                            profile: profile,
                            sshClient: appState.sshClient,
                            cronManager: appState.cronManager
                        )
                    } label: {
                        if viewModel.isLoadingCron {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCronBusy)
                }

                HStack(spacing: 8) {
                    TextField("Schedule", text: $cronScheduleText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 160)
                    TextField("Command", text: $cronCommandText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        addCronEntry()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(isCronBusy || cronCommandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("User crontab entries can be changed here. System entries from /etc/cron.d are shown read-only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let capturedAt = viewModel.cronSnapshot?.capturedAt {
                    Text("Last updated \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let entries = viewModel.cronSnapshot?.entries {
                    cronOverview(entries)
                }

                if let error = viewModel.cronErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                if let message = viewModel.cronActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .padding(20)

            Divider()

            Group {
                if let entries = viewModel.cronSnapshot?.entries {
                    cronEntryList(filteredCronEntries(entries))
                } else {
                    ContentUnavailableView(
                        "No Cron Loaded",
                        systemImage: "calendar.badge.clock",
                        description: Text("Refresh to read the remote user's crontab.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if viewModel.cronSnapshot == nil && !viewModel.isLoadingCron {
                viewModel.loadCron(
                    profile: profile,
                    sshClient: appState.sshClient,
                    cronManager: appState.cronManager
                )
            }
        }
    }

    private func cronOverview(_ entries: [CronEntry]) -> some View {
        let summary = CronEntryClassifier.summary(for: entries)
        let columns = [GridItem(.adaptive(minimum: 130), spacing: 10)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            cronOverviewCard(
                title: "全部任务",
                value: summary.total,
                detail: "crontab",
                icon: "calendar.badge.clock",
                color: .blue,
                filter: .all
            )
            cronOverviewCard(
                title: "已启用",
                value: summary.enabled,
                detail: "active",
                icon: "checkmark.circle",
                color: .green,
                filter: .enabled
            )
            cronOverviewCard(
                title: "已禁用",
                value: summary.disabled,
                detail: "paused",
                icon: "pause.circle",
                color: .orange,
                filter: .disabled
            )
            cronOverviewCard(
                title: "用户任务",
                value: summary.userEntries,
                detail: "editable",
                icon: "person.crop.circle",
                color: .purple,
                filter: .user
            )
            cronOverviewCard(
                title: "系统任务",
                value: summary.systemEntries,
                detail: "read-only",
                icon: "lock.circle",
                color: .secondary,
                filter: .system
            )
        }
    }

    private func cronOverviewCard(
        title: String,
        value: Int,
        detail: String,
        icon: String,
        color: Color,
        filter: CronEntryFilter
    ) -> some View {
        let isSelected = cronFilter == filter

        return Button {
            cronFilter = filter
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(isSelected ? 0.16 : 0.08), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(value)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color.opacity(0.85) : Color.secondary.opacity(0.18), lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
        .help("筛选\(title)")
    }

    private func filteredCronEntries(_ entries: [CronEntry]) -> [CronEntry] {
        entries.filter { cronFilter.includes($0) }
    }

    private func cronEntryList(_ entries: [CronEntry]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                cronHeader("状态", width: 90)
                cronHeader("计划", width: 145)
                cronHeader("命令")
                cronHeader("来源", width: 180)
                cronHeader("用户", width: 90)
                cronHeader("操作", width: 106)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        cronEntryTableRow(entry)
                        Divider()
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .padding(16)
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("No Cron Entries", systemImage: "calendar.badge.clock")
                    .padding(.top, 48)
            }
        }
    }

    private func cronEntryTableRow(_ entry: CronEntry) -> some View {
        HStack(spacing: 12) {
            CronStateBadge(entry: entry)
                .frame(width: 90, alignment: .leading)

            Text(entry.schedule)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 145, alignment: .leading)

            Text(entry.command)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(CronEntryClassifier.sourceTitle(for: entry))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 180, alignment: .leading)

            Text(CronEntryClassifier.runAsTitle(for: entry))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            cronEntryActions(entry)
                .frame(width: 106, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contextMenu {
            if entry.isUserCrontabEntry {
                if entry.isEnabled {
                    Button {
                        pendingCronAction = CronActionRequest(entry: entry, action: .disable)
                    } label: {
                        Label("Disable", systemImage: "pause.fill")
                    }
                } else {
                    Button {
                        pendingCronAction = CronActionRequest(entry: entry, action: .enable)
                    } label: {
                        Label("Enable", systemImage: "play.fill")
                    }
                }
                Button(role: .destructive) {
                    pendingCronAction = CronActionRequest(entry: entry, action: .delete)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Label("Read Only", systemImage: "lock")
            }
        }
    }

    private func cronHeader(_ title: String, width: CGFloat? = nil) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func cronEntryActions(_ entry: CronEntry) -> some View {
        HStack(spacing: 6) {
            if entry.isUserCrontabEntry {
                Button {
                    pendingCronAction = CronActionRequest(entry: entry, action: entry.isEnabled ? .disable : .enable)
                } label: {
                    Image(systemName: entry.isEnabled ? "pause.fill" : "play.fill")
                        .frame(width: 24, height: 24)
                }
                .help(entry.isEnabled ? "Disable" : "Enable")
                .disabled(isCronBusy)

                Button(role: .destructive) {
                    pendingCronAction = CronActionRequest(entry: entry, action: .delete)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .help("Delete")
                .disabled(isCronBusy)
            } else {
                Label("只读", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private enum CronEntryFilter: String, CaseIterable, Identifiable {
        case all
        case enabled
        case disabled
        case user
        case system

        var id: String { rawValue }

        func includes(_ entry: CronEntry) -> Bool {
            switch self {
            case .all:
                true
            case .enabled:
                entry.isEnabled
            case .disabled:
                !entry.isEnabled
            case .user:
                entry.isUserCrontabEntry
            case .system:
                !entry.isUserCrontabEntry
            }
        }
    }

    private func addCronEntry() {
        viewModel.addCronEntry(
            schedule: cronScheduleText,
            command: cronCommandText,
            profile: profile,
            sshClient: appState.sshClient,
            cronManager: appState.cronManager,
            repository: appState.repository
        )
        cronCommandText = ""
    }

    private func performCronAction(_ request: CronActionRequest) {
        viewModel.performCronEntryAction(
            request.action,
            entry: request.entry,
            profile: profile,
            sshClient: appState.sshClient,
            cronManager: appState.cronManager,
            repository: appState.repository
        )
    }

    private func performDockerAction(_ request: DockerContainerActionRequest) {
        viewModel.performDockerContainerAction(
            request.action,
            container: request.container,
            profile: profile,
            sshClient: appState.sshClient,
            dockerManager: appState.dockerManager,
            repository: appState.repository
        )
    }

    private var currentFirewallRuleDraft: FirewallRuleDraft? {
        guard let port = Int(firewallRulePort.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return FirewallRuleDraft(
            mutation: firewallRuleMutation,
            direction: firewallRuleDirection,
            action: firewallRuleAction,
            proto: firewallRuleProtocol,
            port: port,
            cidr: firewallRuleCIDR.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func prepareFirewallRule(snapshot: FirewallSnapshot) {
        guard let draft = currentFirewallRuleDraft else {
            viewModel.firewallErrorMessage = "Enter a valid numeric port."
            return
        }

        do {
            let command = try FirewallManager.command(for: draft, snapshot: snapshot)
            pendingFirewallRule = FirewallRuleRequest(
                draft: draft,
                risk: RemoteOperationRiskFactory.firewallRule(draft, backend: snapshot.backend, command: command)
            )
        } catch {
            viewModel.firewallErrorMessage = error.localizedDescription
        }
    }

    private func applyFirewallRule(_ draft: FirewallRuleDraft) {
        viewModel.applyFirewallRule(
            draft,
            profile: profile,
            sshClient: appState.sshClient,
            firewallManager: appState.firewallManager,
            repository: appState.repository
        )
    }

    private func applyCloudSecurityGroupRule(_ preview: CloudSecurityGroupRuleChangePreview) {
        viewModel.applyCloudSecurityGroupRuleChange(
            preview,
            profile: profile,
            cloudSecurityGroupService: appState.cloudSecurityGroupService,
            repository: appState.repository
        )
    }

    private func systemdJournalText(for unit: SystemdUnit) -> String {
        guard viewModel.systemdJournalLog?.unitName == unit.name else {
            return "Select Logs to load recent journal entries."
        }
        let text = viewModel.systemdJournalLog?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "No recent logs." : text
    }

    private func loadRemoteFilesFromPathField() {
        viewModel.loadRemoteFiles(
            path: filePathText,
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService
        )
    }

    private func chooseRemoteUploadFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        if panel.runModal() == .OK {
            viewModel.uploadRemoteFiles(
                localURLs: panel.urls,
                profile: profile,
                sshClient: appState.sshClient,
                transferClient: appState.sshClient,
                remoteFileService: appState.remoteFileService,
                repository: appState.repository
            )
        }
    }

    private func chooseRemoteDownloadDirectory(for entries: [RemoteFileEntry]) {
        let files = entries.filter { $0.kind == .file }
        guard !files.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Download"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.downloadRemoteFiles(
                files,
                toDirectory: url,
                profile: profile,
                transferClient: appState.sshClient,
                remoteFileService: appState.remoteFileService,
                repository: appState.repository
            )
        }
    }

    private func chooseRemoteDownloadDestination(for entry: RemoteFileEntry) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        panel.canCreateDirectories = true
        panel.prompt = "Download"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.downloadRemoteFile(
                entry,
                to: url,
                profile: profile,
                transferClient: appState.sshClient,
                remoteFileService: appState.remoteFileService,
                repository: appState.repository
            )
        }
    }

    private func openRemoteFileEntry(_ entry: RemoteFileEntry) {
        switch entry.kind {
        case .directory:
            viewModel.openRemoteFileEntry(
                entry,
                profile: profile,
                sshClient: appState.sshClient,
                remoteFileService: appState.remoteFileService
            )
        case .file:
            viewModel.openRemoteTextFile(
                entry,
                profile: profile,
                sshClient: appState.sshClient,
                remoteFileService: appState.remoteFileService
            )
        default:
            break
        }
    }

    private func startRenaming(_ entry: RemoteFileEntry) {
        remoteFileRenameText = entry.name
        remoteFileRenameEntry = entry
    }

    private func startCreatingRemoteFileItem(_ kind: RemoteFileCreationKind) {
        remoteFileCreateName = kind.defaultName
        remoteFileCreateKind = kind
    }

    private func saveRemoteFileRename(_ entry: RemoteFileEntry) {
        viewModel.renameRemoteFile(
            entry,
            to: remoteFileRenameText,
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
        remoteFileRenameEntry = nil
    }

    private func createRemoteFileItem(_ kind: RemoteFileCreationKind) {
        viewModel.createRemoteFileItem(
            named: remoteFileCreateName,
            kind: kind,
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
        remoteFileCreateKind = nil
    }

    private func startChangingPermissions(_ entry: RemoteFileEntry) {
        remoteFilePermissionsText = RemoteFilePermissionsSheet.octalMode(from: entry.permissions)
        remoteFilePermissionsEntry = entry
    }

    private var remoteFileEditorSheetsModifier: RemoteFileEditorSheetsModifier {
        RemoteFileEditorSheetsModifier(
            viewModel: viewModel,
            profile: profile,
            appState: appState,
            renameEntry: $remoteFileRenameEntry,
            renameText: $remoteFileRenameText,
            createKind: $remoteFileCreateKind,
            createName: $remoteFileCreateName,
            permissionsEntry: $remoteFilePermissionsEntry,
            permissionsText: $remoteFilePermissionsText
        )
    }

    private var developmentServiceAlertsModifier: DevelopmentServiceAlertsModifier {
        DevelopmentServiceAlertsModifier(
            viewModel: viewModel,
            profile: profile,
            appState: appState,
            pendingGitLabInstall: $pendingGitLabInstall,
            pendingGiteaInstall: $pendingGiteaInstall,
            pendingGitLabServiceAction: $pendingGitLabServiceAction
        )
    }

    private func gitNativeIssueStateAlert(_ request: GitNativeIssueStateRequest) -> Alert {
        let title = "\(request.action.displayName) \(request.displayType)?"
        let message = "This updates \(request.displayName) on \(request.serviceTitle), matching the state action from the original web console."
        let actionTitle = request.action.displayName
        let primaryButton: Alert.Button = request.action == .close
            ? .destructive(Text(actionTitle)) { performGitNativeIssueStateAction(request) }
            : .default(Text(actionTitle)) { performGitNativeIssueStateAction(request) }
        return Alert(
            title: Text(title),
            message: Text(message),
            primaryButton: primaryButton,
            secondaryButton: .cancel()
        )
    }

    private func gitLabPipelineActionAlert(_ request: GitLabPipelineActionRequest) -> Alert {
        let title = "\(request.action.displayName) Pipeline?"
        let message = "This sends a GitLab API request for \(request.displayName). You can still open the web log afterward if deeper troubleshooting is needed."
        let actionTitle = request.action.displayName
        let primaryButton: Alert.Button = request.action == .cancel
            ? .destructive(Text(actionTitle)) { performGitLabPipelineAction(request) }
            : .default(Text(actionTitle)) { performGitLabPipelineAction(request) }
        return Alert(
            title: Text(title),
            message: Text(message),
            primaryButton: primaryButton,
            secondaryButton: .cancel()
        )
    }

    private func gitLabJobActionAlert(_ request: GitLabJobActionRequest) -> Alert {
        let title = "\(request.action.displayName) Job?"
        let message = "This sends a GitLab API request for \(request.displayName), matching the action available from the original GitLab Jobs page."
        let actionTitle = request.action.displayName
        let primaryButton: Alert.Button = request.action == .cancel
            ? .destructive(Text(actionTitle)) { performGitLabJobAction(request) }
            : .default(Text(actionTitle)) { performGitLabJobAction(request) }
        return Alert(
            title: Text(title),
            message: Text(message),
            primaryButton: primaryButton,
            secondaryButton: .cancel()
        )
    }

    private func gitLabVariableSaveAlert(_ request: GitLabVariableSaveRequest) -> Alert {
        let draft = viewModel.gitLabVariableDraft
        let title = "\(request.mode.displayName) GitLab Variable?"
        let message = "This writes \(draft.trimmedKey) to project \(draft.projectId) with scope \(draft.trimmedEnvironmentScope). The value is sent to GitLab but is not shown in HHC Server Manager after saving."
        return Alert(
            title: Text(title),
            message: Text(message),
            primaryButton: .default(Text(request.mode.displayName)) {
                performGitLabVariableSave(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func gitLabVariableDeletionAlert(_ request: GitLabVariableDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 GitLab Variable?"),
            message: Text("This deletes \(request.key) from project \(request.projectId) with scope \(request.environmentScope). This remote write operation cannot be undone from HHC Server Manager."),
            primaryButton: .destructive(Text("删除")) {
                performGitLabVariableDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func gitLabGroupSaveAlert(_ request: GitLabGroupSaveRequest) -> Alert {
        let draft = viewModel.gitLabGroupDraft
        let title = "\(request.mode.displayName) GitLab Group?"
        let parent = draft.parentId > 0 ? "parent group \(draft.parentId)" : "no parent group"
        let message = "This \(request.mode.actionDescription) \(draft.trimmedPath) in GitLab with visibility \(draft.visibility) and \(parent). Members and project permissions can be managed after saving."
        return Alert(
            title: Text(title),
            message: Text(message),
            primaryButton: .default(Text(request.mode.displayName)) {
                performGitLabGroupSave(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func gitLabMemberSaveAlert(_ request: GitLabMemberSaveRequest) -> Alert {
        let draft = viewModel.gitLabMemberDraft
        let title = "\(request.mode.displayName) GitLab Member?"
        let expiration = draft.trimmedExpiresAt.isEmpty ? "none" : draft.trimmedExpiresAt
        let message = "This writes user \(draft.userId) as \(gitLabAccessLevelTitle(draft.accessLevel)) on \(draft.scope.displayName) \(draft.targetId). Expiration: \(expiration)."
        return Alert(
            title: Text(title),
            message: Text(message),
            primaryButton: .default(Text(request.mode.displayName)) {
                performGitLabMemberSave(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func gitLabMemberDeletionAlert(_ request: GitLabMemberDeletionRequest) -> Alert {
        Alert(
            title: Text("移除 GitLab Member?"),
            message: Text("This removes \(request.username) from \(request.scope.displayName) \(request.targetId). This remote permission change cannot be undone from HHC Server Manager."),
            primaryButton: .destructive(Text("移除")) {
                performGitLabMemberDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaUserSaveAlert(_ request: GiteaUserSaveRequest) -> Alert {
        let draft = viewModel.giteaUserDraft
        let passwordMessage = draft.trimmedPassword.isEmpty ? "password unchanged" : "password will be reset"
        let stateSummary = "active=\(String(draft.isActive)), admin=\(String(draft.isAdmin)), prohibit_login=\(String(draft.prohibitLogin)), restricted=\(String(draft.restricted))"
        return Alert(
            title: Text("\(request.mode.displayName) Gitea User?"),
            message: Text("This \(request.mode.actionDescription) \(draft.trimmedUsername) in Gitea with \(stateSummary); \(passwordMessage)."),
            primaryButton: .default(Text(request.mode.displayName)) {
                performGiteaUserSave(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaUserDeletionAlert(_ request: GiteaUserDeletionRequest) -> Alert {
        let role = request.isAdmin ? " This account is marked as admin." : ""
        return Alert(
            title: Text("删除 Gitea User?"),
            message: Text("This deletes \(request.username)\(request.email.map { " (\($0))" } ?? "") from Gitea.\(role) Repositories, tokens, or ownership related to this user may be affected."),
            primaryButton: .destructive(Text("删除")) {
                performGiteaUserDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaOrganizationSaveAlert(_ request: GiteaOrganizationSaveRequest) -> Alert {
        let draft = viewModel.giteaOrganizationDraft
        let message = "This \(request.mode.actionDescription) organization \(draft.trimmedUsername) in Gitea with visibility \(draft.visibility). Team membership and repositories remain managed in their own sections."
        return Alert(
            title: Text("\(request.mode.displayName) Gitea Organization?"),
            message: Text(message),
            primaryButton: .default(Text(request.mode.displayName)) {
                performGiteaOrganizationSave(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaOrganizationDeletionAlert(_ request: GiteaOrganizationDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 Gitea Organization?"),
            message: Text("This deletes \(request.username)\(request.fullName.map { " (\($0))" } ?? "") from Gitea. Teams and team-member rows for this organization will be removed from the local snapshot after success."),
            primaryButton: .destructive(Text("删除")) {
                performGiteaOrganizationDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaTeamSaveAlert(_ request: GiteaTeamSaveRequest) -> Alert {
        let draft = viewModel.giteaTeamDraft
        let target = draft.teamId > 0 ? "\(draft.trimmedOrganization)/\(draft.trimmedName)" : "\(draft.trimmedOrganization)/\(draft.trimmedName)"
        return Alert(
            title: Text("\(request.mode.displayName) Gitea Team?"),
            message: Text("This \(request.mode.actionDescription) team \(target), permission \(draft.permission), and \(draft.units.count) enabled units. Members are managed separately."),
            primaryButton: .default(Text(request.mode.displayName)) {
                performGiteaTeamSave(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaTeamDeletionAlert(_ request: GiteaTeamDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 Gitea Team?"),
            message: Text("This deletes \(request.displayName) from Gitea and removes its member rows from the local snapshot after success. Repository permissions from this team will stop applying."),
            primaryButton: .destructive(Text("删除")) {
                performGiteaTeamDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaTeamMemberSaveAlert(_ request: GiteaTeamMemberSaveRequest) -> Alert {
        let draft = viewModel.giteaTeamMemberDraft
        return Alert(
            title: Text("添加 Gitea Team Member?"),
            message: Text("This adds \(draft.trimmedUsername) to Gitea team \(draft.teamId). The user must already exist in this Gitea instance."),
            primaryButton: .default(Text("添加")) {
                performGiteaTeamMemberSave()
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaTeamMemberDeletionAlert(_ request: GiteaTeamMemberDeletionRequest) -> Alert {
        Alert(
            title: Text("移除 Gitea Team Member?"),
            message: Text("This removes \(request.displayName). This remote permission change cannot be undone from HHC Server Manager."),
            primaryButton: .destructive(Text("移除")) {
                performGiteaTeamMemberDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaTeamRepositorySaveAlert(_ request: GiteaTeamRepositorySaveRequest) -> Alert {
        Alert(
            title: Text("绑定 Gitea Team Repository?"),
            message: Text("This adds \(viewModel.giteaTeamRepositoryDraft.trimmedRepositoryFullName) to team \(viewModel.giteaTeamRepositoryDraft.teamId). It changes team access scope but does not move or create the repository."),
            primaryButton: .default(Text("绑定")) {
                performGiteaTeamRepositorySave()
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaTeamRepositoryDeletionAlert(_ request: GiteaTeamRepositoryDeletionRequest) -> Alert {
        Alert(
            title: Text("移除 Gitea Team Repository?"),
            message: Text("This removes \(request.displayName) from the team. The repository itself will not be deleted."),
            primaryButton: .destructive(Text("移除")) {
                performGiteaTeamRepositoryDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaKeyDeletionAlert(_ request: GiteaKeyDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 Gitea SSH Key?"),
            message: Text("This deletes \(request.title)\(request.fingerprint.map { " (\($0))" } ?? ""). Existing Git operations using this key may stop working."),
            primaryButton: .destructive(Text("删除")) {
                performGiteaKeyDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaAccessTokenSecretAlert(_ result: GiteaAccessTokenCreationResult) -> Alert {
        Alert(
            title: Text("Gitea Access Token 已创建"),
            message: Text("Token for \(result.token.name):\n\(result.secret)\n\nCopy it now. Gitea will not show this secret again."),
            primaryButton: .default(Text("复制 Token")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.secret, forType: .string)
                viewModel.clearGiteaAccessTokenCreationResult()
            },
            secondaryButton: .cancel(Text("关闭")) {
                viewModel.clearGiteaAccessTokenCreationResult()
            }
        )
    }

    private func giteaAccessTokenDeletionAlert(_ request: GiteaAccessTokenDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 Gitea Access Token?"),
            message: Text("This deletes \(request.name)\(request.tokenLastEight.map { " (last eight \($0))" } ?? "") for \(request.username). API calls using this token will stop working."),
            primaryButton: .destructive(Text("删除")) {
                performGiteaAccessTokenDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func giteaPackageDeletionAlert(_ request: GiteaPackageDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 Gitea Package?"),
            message: Text("This deletes \(request.owner)/\(request.name)\(request.version.map { " version \($0)" } ?? "") from Gitea Packages. Package installs that depend on this \(request.type) artifact may fail."),
            primaryButton: .destructive(Text("删除")) {
                performGiteaPackageDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func gitLabDeployKeyDeletionAlert(_ request: GitLabDeployKeyDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 GitLab Deploy Key?"),
            message: Text("This deletes \(request.title) from project \(request.projectId)\(request.fingerprint.map { " (\($0))" } ?? ""). Existing deployments using this key may stop working."),
            primaryButton: .destructive(Text("删除")) {
                performGitLabDeployKeyDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func gitLabDeployTokenSecretAlert(_ result: GitLabDeployTokenCreationResult) -> Alert {
        Alert(
            title: Text("GitLab Deploy Token 已创建"),
            message: Text("Token for \(result.deployToken.name):\n\(result.token)\n\nCopy it now. GitLab will not show this secret again."),
            primaryButton: .default(Text("复制 Token")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.token, forType: .string)
                viewModel.clearGitLabDeployTokenCreationResult()
            },
            secondaryButton: .cancel(Text("关闭")) {
                viewModel.clearGitLabDeployTokenCreationResult()
            }
        )
    }

    private func gitLabDeployTokenDeletionAlert(_ request: GitLabDeployTokenDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 GitLab Deploy Token?"),
            message: Text("This revokes \(request.name) from project \(request.projectId)\(request.username.map { " (user \($0))" } ?? ""). Existing package, registry, or repository access using this token may stop working."),
            primaryButton: .destructive(Text("删除")) {
                performGitLabDeployTokenDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func gitLabPackageDeletionAlert(_ request: GitLabPackageDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 GitLab Package?"),
            message: Text("This deletes \(request.name)\(request.version.map { " version \($0)" } ?? "") from project \(request.projectId). Package installs that depend on this \(request.packageType) artifact may fail."),
            primaryButton: .destructive(Text("删除")) {
                performGitLabPackageDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func verdaccioPackageDeletionAlert(_ request: VerdaccioPackageDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 Verdaccio Package?"),
            message: Text("This deletes \(request.packageName) from Verdaccio storage, creates a package backup under \(viewModel.registryDraft.installPath)/backups first, restarts \(viewModel.registryDraft.serviceName).service, and runs a health check. Existing npm installs that depend on this package may fail."),
            primaryButton: .destructive(Text("删除")) {
                performVerdaccioPackageDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func gitLabTagDeletionAlert(_ request: GitLabTagDeletionRequest) -> Alert {
        Alert(
            title: Text("删除 GitLab Tag?"),
            message: Text("This deletes tag \(request.tagName) from project \(request.projectId)\(request.target.map { " (target \($0))" } ?? ""). Release or deployment flows that rely on this tag may be affected."),
            primaryButton: .destructive(Text("删除")) {
                performGitLabTagDeletion(request)
            },
            secondaryButton: .cancel()
        )
    }

    private func saveRemoteFilePermissions(_ entry: RemoteFileEntry) {
        viewModel.changeRemoteFilePermissions(
            entry,
            mode: remoteFilePermissionsText,
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
        remoteFilePermissionsEntry = nil
    }

    private func remoteTextEditorSheet(_ textFile: RemoteTextFile) -> RemoteTextEditorSheet {
        RemoteTextEditorSheet(
            textFile: textFile,
            draft: $viewModel.remoteTextDraft,
            isSaving: viewModel.isSavingRemoteText,
            cancel: {
                viewModel.closeRemoteTextEditor()
            },
            save: {
                saveRemoteTextFile()
            },
            saveAs: { targetPath in
                saveRemoteTextFileAs(targetPath)
            },
            suggestedSaveAsPath: {
                suggestedRemoteSaveAsPath(for: textFile.path)
            }
        )
    }

    private var remoteTextFileSheetBinding: Binding<RemoteTextFile?> {
        Binding(
            get: { viewModel.remoteTextFile },
            set: { viewModel.remoteTextFile = $0 }
        )
    }

    private func saveRemoteTextFile() {
        viewModel.saveRemoteTextFile(
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
    }

    private func saveRemoteTextFileAs(_ targetPath: String) {
        viewModel.saveRemoteTextFileAs(
            targetPath: targetPath,
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
    }

    private var selectedRemoteFileEntries: [RemoteFileEntry] {
        guard let entries = viewModel.remoteDirectoryListing?.entries else { return [] }
        return entries.filter { selectedRemoteFileIDs.contains($0.id) && $0.kind == .file }
    }

    private func suggestedRemoteSaveAsPath(for path: String) -> String {
        let parent = RemoteFileService.parentPath(for: path)
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name.isEmpty {
            return RemoteFileService.joinedPath(basePath: parent, name: "copy.txt")
        }
        return RemoteFileService.joinedPath(basePath: parent, name: "\(name).copy")
    }

    private var persistedHistorySection: some View {
        let filteredHistory = CommandHistoryInspector.filter(
            viewModel.persistedCommandHistory,
            query: terminalHistorySearchText,
            status: terminalHistoryStatusFilter
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Command History")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    pendingClearCommandHistory = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear saved command history")
            }

            HStack(spacing: 10) {
                TextField("搜索命令", text: $terminalHistorySearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)

                Picker("状态", selection: $terminalHistoryStatusFilter) {
                    ForEach(CommandHistoryStatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    terminalHistoryHeader("状态", width: 86)
                    terminalHistoryHeader("命令")
                    terminalHistoryHeader("耗时", width: 80)
                    terminalHistoryHeader("时间", width: 150)
                    terminalHistoryHeader("操作", width: 56)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                ForEach(filteredHistory) { entry in
                    terminalHistoryRow(entry)
                    Divider()
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if filteredHistory.isEmpty {
                    ContentUnavailableView("没有匹配命令", systemImage: "terminal")
                        .padding(.top, 46)
                }
            }
        }
    }

    private func terminalHistoryHeader(_ title: String, width: CGFloat? = nil) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func terminalHistoryRow(_ entry: CommandHistoryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            CommandHistoryStateBadge(entry: entry)
                .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.command)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.exitCode == nil {
                    Text("failed before exit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.duration.map { String(format: "%.2fs", $0) } ?? "--")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)

            Button {
                commandText = entry.command
                viewModel.rerunCommand(
                    entry,
                    profile: profile,
                    sshClient: appState.sshClient,
                    repository: appState.repository
                )
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Run this command again")
            .disabled(viewModel.isRunningCommand)
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func quickCommandButton(_ command: String) -> some View {
        Button(command) {
            commandText = command
            runCommand()
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isRunningCommand)
    }

    private func runCommand() {
        let command = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        viewModel.executeCommand(
            command,
            profile: profile,
            sshClient: appState.sshClient,
            repository: appState.repository
        )
    }

    private func historyMetadata(_ entry: CommandHistoryEntry) -> String {
        var parts: [String] = []
        if let exitCode = entry.exitCode {
            parts.append("exit \(exitCode)")
        } else {
            parts.append("failed before exit")
        }
        if let duration = entry.duration {
            parts.append(String(format: "%.2fs", duration))
        }
        parts.append(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }

    private func deploymentRunTitle(_ run: DeploymentRun) -> String {
        var parts = [
            run.status.rawValue,
            run.startedAt.formatted(date: .abbreviated, time: .shortened),
        ]
        if let targetCommit = run.targetCommit {
            parts.append(targetCommit)
        }
        return parts.joined(separator: " · ")
    }

    private func deploymentStatusBadge(_ status: DeploymentRunStatus) -> some View {
        Text(status.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(deploymentStatusColor(status).opacity(0.16), in: Capsule())
            .foregroundStyle(deploymentStatusColor(status))
    }

    private func deploymentStatusColor(_ status: DeploymentRunStatus) -> Color {
        switch status {
        case .pending:
            .secondary
        case .running:
            .blue
        case .succeeded:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        }
    }

    private func deploymentLogColor(_ stream: DeploymentLogStream) -> Color {
        switch stream {
        case .stdout:
            .green
        case .stderr:
            .orange
        case .system:
            .secondary
        }
    }

    private func prepareDeploymentRun() {
        guard let risk = viewModel.deploymentRunRisk(serverId: profile.id) else {
            return
        }
        pendingDeploymentRun = DeploymentRunRequest(risk: risk)
    }

    private func prepareDeploymentRollback() {
        guard let project = viewModel.selectedDeploymentProject else {
            viewModel.deploymentErrorMessage = "Select a deployment project before rollback."
            return
        }
        guard let run = viewModel.selectedDeploymentRun, run.previousCommit != nil else {
            viewModel.deploymentErrorMessage = "Selected run does not have a previous commit to roll back to."
            return
        }
        pendingDeploymentRollback = DeploymentRollbackRequest(project: project, run: run)
    }

    private var currentServerBinding: Binding<UUID> {
        Binding(
            get: { appState.selectedServerId ?? profile.id },
            set: { appState.selectedServerId = $0 }
        )
    }

    private var deploymentProjectSelectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedDeploymentProject?.id },
            set: { projectId in
                guard let projectId,
                      let project = viewModel.deploymentProjects.first(where: { $0.id == projectId })
                else { return }
                viewModel.selectDeploymentProject(project, repository: appState.repository)
            }
        )
    }

    private var deploymentRunSelectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedDeploymentRun?.id },
            set: { runId in
                guard let runId,
                      let run = viewModel.deploymentRuns.first(where: { $0.id == runId })
                else { return }
                viewModel.selectDeploymentRun(run, repository: appState.repository)
            }
        )
    }

    private var dashboardAutoRefreshBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isDashboardAutoRefreshEnabled },
            set: { enabled in
                viewModel.setDashboardAutoRefreshEnabled(
                    enabled,
                    profile: profile,
                    sshClient: appState.sshClient,
                    dashboardService: appState.dashboardService,
                    cloudMetricService: appState.cloudMetricService,
                    repository: appState.repository
                )
            }
        )
    }

    private var systemdSelectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedSystemdUnit?.id },
            set: { unitId in
                guard let unitId,
                      let unit = viewModel.systemdUnitList?.units.first(where: { $0.id == unitId })
                else { return }
                viewModel.selectSystemdUnit(
                    unit,
                    profile: profile,
                    sshClient: appState.sshClient,
                    systemdServiceManager: appState.systemdServiceManager
                )
            }
        )
    }

    private var nginxConfigSelectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedNginxConfig?.id },
            set: { fileId in
                guard let fileId,
                      let file = viewModel.nginxConfigList?.files.first(where: { $0.id == fileId })
                else { return }
                viewModel.selectNginxConfig(
                    file,
                    profile: profile,
                    sshClient: appState.sshClient,
                    nginxConfigManager: appState.nginxConfigManager
                )
            }
        )
    }

    private var environmentFileSelectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedEnvironmentFile?.id },
            set: { fileId in
                guard let fileId,
                      let file = viewModel.environmentFileList?.files.first(where: { $0.id == fileId })
                else { return }
                viewModel.selectEnvironmentFile(
                    file,
                    profile: profile,
                    sshClient: appState.sshClient,
                    environmentFileManager: appState.environmentFileManager
                )
            }
        )
    }

    private var cloudSecurityGroupSelectionBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedCloudSecurityGroup?.id },
            set: { groupId in
                guard let groupId,
                      let group = viewModel.cloudSecurityGroupList?.groups.first(where: { $0.id == groupId })
                else { return }
                viewModel.selectCloudSecurityGroup(
                    group,
                    cloudSecurityGroupService: appState.cloudSecurityGroupService
                )
            }
        )
    }

    private func nginxConfigText(for file: NginxConfigFile) -> String {
        guard viewModel.nginxConfigContent?.file.id == file.id else {
            return "Select Refresh to load this file."
        }
        let content = viewModel.nginxConfigContent?.content ?? ""
        return content.isEmpty ? "(empty)" : content
    }

    private func nginxConfigMetadata(_ file: NginxConfigFile) -> String {
        var parts: [String] = []
        if let size = file.size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let modifiedAt = file.modifiedAt {
            parts.append("modified \(modifiedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.isEmpty ? "Remote config file" : parts.joined(separator: " · ")
    }

    private func environmentFileMetadata(_ file: EnvironmentFile) -> String {
        var parts = [file.source]
        if let size = file.size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let modifiedAt = file.modifiedAt {
            parts.append("modified \(modifiedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private var connectionBadge: some View {
        Label {
            Text(viewModel.connectionState.displayName)
        } icon: {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .disconnected:
            .secondary
        case .connecting:
            .orange
        case .connected:
            .green
        case .failed:
            .red
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private var remoteFileTrashBinding: Binding<Bool> {
        Binding(
            get: { remoteFileTrashEntry != nil },
            set: { isPresented in
                if !isPresented {
                    remoteFileTrashEntry = nil
                }
            }
        )
    }

    private var isRemoteFileBusy: Bool {
        viewModel.isLoadingRemoteFiles ||
            viewModel.isMutatingRemoteFile ||
            viewModel.isLoadingRemoteText ||
            viewModel.isSavingRemoteText ||
            viewModel.isTransferringRemoteFile
    }

    private var isRemoteFileSelectionBusy: Bool {
        viewModel.isLoadingRemoteFiles ||
            viewModel.isMutatingRemoteFile ||
            viewModel.isLoadingRemoteText ||
            viewModel.isSavingRemoteText
    }

    private var isSystemdBusy: Bool {
        viewModel.isLoadingSystemdUnits ||
            viewModel.isPerformingSystemdAction ||
            viewModel.isLoadingSystemdJournal
    }

    private var isDatabaseServiceBusy: Bool {
        viewModel.isLoadingDatabaseServices ||
            viewModel.isPerformingDatabaseServiceAction ||
            viewModel.isCreatingDatabaseBackup
    }

    private var isCronBusy: Bool {
        viewModel.isLoadingCron || viewModel.isMutatingCron
    }

    private var isFirewallBusy: Bool {
        viewModel.isLoadingFirewall || viewModel.isMutatingFirewall
    }

    private var isNginxBusy: Bool {
        viewModel.isLoadingNginxConfigs ||
            viewModel.isLoadingNginxConfigContent ||
            viewModel.isTestingNginxConfig ||
            viewModel.isSavingNginxConfig ||
            viewModel.isWritingNginxReverseProxy ||
            viewModel.isReloadingNginx
    }

    private var nginxReverseProxyDraftError: String? {
        do {
            try NginxReverseProxyConfigurationBuilder.validate(viewModel.nginxReverseProxyDraft)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var isNginxReverseProxyDraftValid: Bool {
        nginxReverseProxyDraftError == nil
    }

    private var nginxReverseProxyPreviewText: String {
        do {
            return try NginxReverseProxyConfigurationBuilder.config(for: viewModel.nginxReverseProxyDraft)
        } catch {
            return error.localizedDescription
        }
    }

    private var nginxReloadMessageText: Text {
        Text(RemoteOperationRiskFactory.reloadNginx(path: viewModel.selectedNginxConfig?.path).confirmationMessage)
    }

    private var nginxSaveMessageText: Text {
        Text(RemoteOperationRiskFactory.saveNginxConfig(path: viewModel.nginxConfigContent?.file.path ?? "nginx").confirmationMessage)
    }

    private var nginxReverseProxyWriteMessageText: Text {
        Text("This will write a generated Nginx server block, create a backup when the target exists, run nginx -t, and roll back automatically if the test fails.")
    }

    private func reloadNginx() {
        viewModel.reloadNginx(
            profile: profile,
            sshClient: appState.sshClient,
            nginxConfigManager: appState.nginxConfigManager,
            repository: appState.repository
        )
    }

    private func saveNginxConfig() {
        viewModel.saveNginxConfig(
            profile: profile,
            sshClient: appState.sshClient,
            nginxConfigManager: appState.nginxConfigManager,
            repository: appState.repository
        )
    }

    private func writeNginxReverseProxy() {
        viewModel.writeNginxReverseProxy(
            profile: profile,
            sshClient: appState.sshClient,
            nginxConfigManager: appState.nginxConfigManager,
            repository: appState.repository
        )
    }

    private var isEnvironmentBusy: Bool {
        viewModel.isLoadingEnvironmentFiles ||
            viewModel.isLoadingEnvironmentFileContent ||
            viewModel.isSavingEnvironmentFile
    }

    private var isCloudSecurityGroupBusy: Bool {
        viewModel.isLoadingCloudSecurityGroups ||
            viewModel.isLoadingCloudSecurityGroupPolicies ||
            viewModel.isMutatingCloudSecurityGroupRule
    }

    private var isRegistryBusy: Bool {
        viewModel.isRunningRegistryPreflight ||
            viewModel.isInstallingVerdaccio ||
            viewModel.isLoadingVerdaccioStatus ||
            viewModel.isLoadingVerdaccioPackages ||
            viewModel.isLoadingVerdaccioPackageDetail ||
            viewModel.isDeletingVerdaccioPackage ||
            viewModel.isCreatingVerdaccioBackup ||
            viewModel.isRestoringVerdaccioBackup ||
            viewModel.isMutatingVerdaccioUser ||
            viewModel.isSavingVerdaccioConfigPolicy ||
            viewModel.isWritingVerdaccioProxy ||
            viewModel.isReloadingVerdaccioProxy ||
            viewModel.isRunningVerdaccioNpmSmokeTest ||
            viewModel.isControllingVerdaccioService ||
            viewModel.isUpgradingVerdaccio
    }

    private var isGitLabBusy: Bool {
        viewModel.isRunningGitLabPreflight ||
            viewModel.isInstallingGitLab ||
            viewModel.isLoadingGitLabStatus ||
            viewModel.isControllingGitLabService
    }

    private var isGitLabPreflightReady: Bool {
        viewModel.gitLabPreflightReport?.isReady == true
    }

    private var hasGitLabPreflightReport: Bool {
        viewModel.gitLabPreflightReport != nil
    }

    private var gitLabInstallAlertTitle: String {
        if viewModel.gitLabPreflightReport?.isReady == false {
            return L10n.string("Force Install GitLab?")
        }
        return L10n.string("Install GitLab?")
    }

    private var gitLabInstallConfirmationMessage: String {
        let base = RemoteOperationRiskFactory.installGitLab(draft: viewModel.gitLabDraft).confirmationMessage
        guard viewModel.gitLabPreflightReport?.isReady == false else { return base }
        let blockers = viewModel.gitLabPreflightReport?.checks
            .filter { $0.status == .failed }
            .map(\.title)
            .joined(separator: ", ") ?? ""
        return [
            L10n.format("Preflight still has blocking checks: %@.", blockers),
            L10n.string("You can force installation, but installation may fail or the service may be unusable."),
            "",
            base,
        ].joined(separator: "\n")
    }

    private var gitLabInstallMessageText: Text {
        Text(gitLabInstallConfirmationMessage)
    }

    private var giteaInstallConfirmationMessage: String {
        [
            L10n.string("This will install Gitea as a systemd service on the selected server."),
            L10n.format("External URL: %@", viewModel.giteaDraft.externalURL),
            L10n.format("Service: %@.service", viewModel.giteaDraft.serviceName),
            L10n.format("Listen port: %d", viewModel.giteaDraft.listenPort),
            L10n.format("Binary: %@", viewModel.giteaDraft.installPath),
            L10n.format("Data path: %@", viewModel.giteaDraft.dataPath),
            L10n.string("Gitea uses SQLite by default in this lightweight setup. Finish admin setup in the browser after installation."),
        ].joined(separator: "\n")
    }

    private var giteaInstallMessageText: Text {
        Text(giteaInstallConfirmationMessage)
    }

    private var gitLabRecommendationStatus: DevelopmentServiceRecommendationStatus {
        guard let report = viewModel.gitLabPreflightReport else { return .needsPreflight }
        let failedIDs = Set(report.checks.filter { $0.status == .failed }.map(\.id))
        if !failedIDs.isEmpty {
            return .forceOnly
        }
        return report.warnings.isEmpty ? .recommended : .allowed
    }

    private var gitLabRecommendationDetail: String {
        guard let report = viewModel.gitLabPreflightReport else {
            return L10n.string("Run preflight to evaluate GitLab CE on this server.")
        }
        let failedTitles = report.checks.filter { $0.status == .failed }.map(\.title)
        if !failedTitles.isEmpty {
            return L10n.format("Not recommended: %@.", failedTitles.joined(separator: ", "))
        }
        if !report.warnings.isEmpty {
            return L10n.string("Allowed with warnings; review ports and resource headroom.")
        }
        return L10n.string("Server meets the current GitLab CE preflight checks.")
    }

    private var isGitLabDraftValid: Bool {
        (try? GitLabInstaller.validate(viewModel.gitLabDraft)) != nil
    }

    private var gitLabDraftValidationMessage: String {
        do {
            try GitLabInstaller.validate(viewModel.gitLabDraft)
            return L10n.string("GitLab CE Linux package settings are ready for preflight.")
        } catch {
            return error.localizedDescription
        }
    }

    private func gitLabPreflightIcon(_ status: GitLabPreflightCheckStatus) -> String {
        switch status {
        case .passed:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    private func gitLabPreflightColor(_ status: GitLabPreflightCheckStatus) -> Color {
        switch status {
        case .passed:
            .green
        case .warning:
            .orange
        case .failed:
            .red
        }
    }

    private func gitLabPreflightCheckSort(_ lhs: GitLabPreflightCheck, _ rhs: GitLabPreflightCheck) -> Bool {
        if gitLabPreflightSortRank(lhs.status) == gitLabPreflightSortRank(rhs.status) {
            return lhs.title < rhs.title
        }
        return gitLabPreflightSortRank(lhs.status) < gitLabPreflightSortRank(rhs.status)
    }

    private func gitLabPreflightSortRank(_ status: GitLabPreflightCheckStatus) -> Int {
        switch status {
        case .failed:
            0
        case .warning:
            1
        case .passed:
            2
        }
    }

    private func gitLabServiceActionIcon(_ action: GitLabServiceAction) -> String {
        switch action {
        case .start:
            "play"
        case .stop:
            "stop"
        case .restart:
            "arrow.clockwise"
        case .reconfigure:
            "wrench.and.screwdriver"
        }
    }

    private var isRegistryPreflightReady: Bool {
        viewModel.registryPreflightReport?.isReady == true
    }

    private var isRegistryDraftValid: Bool {
        (try? VerdaccioConfigurationBuilder.validate(viewModel.registryDraft)) != nil
    }

    private var registryDraftValidationMessage: String {
        do {
            try VerdaccioConfigurationBuilder.validate(viewModel.registryDraft)
            return "Install settings are ready for preflight."
        } catch {
            return error.localizedDescription
        }
    }

    private var isVerdaccioPolicyValid: Bool {
        (try? VerdaccioConfigurationBuilder.validate(viewModel.verdaccioConfigPolicyDraft)) != nil
    }

    private var verdaccioPolicyValidationMessage: String {
        do {
            try VerdaccioConfigurationBuilder.validate(viewModel.verdaccioConfigPolicyDraft)
            return "Generated config will backup config.yaml and restart Verdaccio."
        } catch {
            return error.localizedDescription
        }
    }

    private var isVerdaccioUserReady: Bool {
        !viewModel.verdaccioUsernameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isVerdaccioUserPasswordReady: Bool {
        isVerdaccioUserReady && viewModel.verdaccioPasswordDraft.count >= 8
    }

    private var isVerdaccioEmailReady: Bool {
        let email = viewModel.verdaccioEmailDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.contains("@") && email.contains(".")
    }

    private var isVerdaccioRestorePathReady: Bool {
        !viewModel.verdaccioRestorePathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pubHostedRepositoryCommands(_ plan: PubHostedRepositoryPlan) -> String {
        [
            plan.publishCommand,
            plan.getCommand,
            plan.flutterGetCommand,
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private var verdaccioInstallConfirmationMessage: String {
        """
        This will create or reuse the \(viewModel.registryDraft.serviceName) system user, write \(viewModel.registryDraft.installPath)/config.yaml, write /etc/systemd/system/\(viewModel.registryDraft.serviceName).service, enable and restart the service, then run a health check.

        Run this only after preflight passes and you are ready to change the remote server.
        """
    }

    private var verdaccioUserDeleteConfirmationMessage: String {
        """
        This will remove \(viewModel.verdaccioUsernameDraft.trimmingCharacters(in: .whitespacesAndNewlines)) from \(viewModel.registryDraft.installPath)/htpasswd, create a backup first, and restart \(viewModel.registryDraft.serviceName).service.
        """
    }

    private var verdaccioRestoreConfirmationMessage: String {
        """
        This will stop \(viewModel.registryDraft.serviceName).service, restore config.yaml and storage from \(viewModel.verdaccioRestorePathDraft.trimmingCharacters(in: .whitespacesAndNewlines)), create a rollback archive first, restart the service, and run a health check. If restore or health check fails, the command will attempt rollback.
        """
    }

    private var verdaccioProxyReloadConfirmationMessage: String {
        """
        This will run nginx -t and reload Nginx if the test passes. Existing connections should stay open, but the active Nginx configuration will change for all served sites.
        """
    }

    private func verdaccioUserActionName(_ action: VerdaccioUserMutationAction) -> String {
        switch action {
        case .create:
            "Created"
        case .updatePassword:
            "Updated"
        case .delete:
            "Deleted"
        }
    }

    private func verdaccioServiceActionIcon(_ action: VerdaccioServiceAction) -> String {
        switch action {
        case .start:
            "play"
        case .stop:
            "stop"
        case .restart:
            "arrow.clockwise"
        }
    }

    private func performVerdaccioServiceAction(_ action: VerdaccioServiceAction) {
        viewModel.performVerdaccioServiceAction(
            action,
            profile: profile,
            sshClient: appState.sshClient,
            verdaccioManager: appState.verdaccioManager,
            repository: appState.repository
        )
    }

    private func installGitLab() {
        viewModel.installGitLabWithProgress(
            profile: profile,
            sshClient: appState.sshClient,
            gitLabInstaller: appState.gitLabInstaller,
            repository: appState.repository
        )
    }

    private func installGitea() {
        viewModel.installGiteaWithProgress(
            profile: profile,
            sshClient: appState.sshClient,
            repository: appState.repository
        )
    }

    private func gitLabServiceActionAlert(_ action: GitLabServiceAction) -> Alert {
        let risk = RemoteOperationRiskFactory.gitLabServiceAction(action, draft: viewModel.gitLabDraft)
        let primaryButton: Alert.Button = action == .stop || action == .restart || action == .reconfigure
            ? .destructive(Text(action.displayName)) { performGitLabServiceAction(action) }
            : .default(Text(action.displayName)) { performGitLabServiceAction(action) }
        return Alert(
            title: Text(L10n.format("%@ GitLab?", action.displayName)),
            message: Text(risk.confirmationMessage),
            primaryButton: primaryButton,
            secondaryButton: .cancel()
        )
    }

    private func performGitLabServiceAction(_ action: GitLabServiceAction) {
        viewModel.performGitLabServiceAction(
            action,
            profile: profile,
            sshClient: appState.sshClient,
            gitLabManager: appState.gitLabManager,
            repository: appState.repository
        )
    }

    private func performRegistryRiskRequest(_ request: RegistryRiskRequest) {
        switch request.action {
        case .verdaccioService(let action):
            performVerdaccioServiceAction(action)
        case .verdaccioUpgrade:
            viewModel.upgradeVerdaccio(
                profile: profile,
                sshClient: appState.sshClient,
                verdaccioManager: appState.verdaccioManager,
                repository: appState.repository
            )
        }
    }

    private func firewallRuleAlert(_ request: FirewallRuleRequest) -> Alert {
        let title = "\(request.draft.mutation.displayName) Firewall Rule?"
        let actionTitle = request.draft.mutation.displayName
        let primaryButton: Alert.Button = request.draft.mutation == .delete
            ? .destructive(Text(actionTitle)) { applyFirewallRule(request.draft) }
            : .default(Text(actionTitle)) { applyFirewallRule(request.draft) }
        return Alert(
            title: Text(title),
            message: Text(request.risk.confirmationMessage),
            primaryButton: primaryButton,
            secondaryButton: .cancel()
        )
    }

    private func cloudSecurityGroupRuleAlert(_ request: CloudSecurityGroupRuleRequest) -> Alert {
        let title = "\(request.preview.action.displayName) Security Group Rule?"
        let actionTitle = request.preview.action.displayName
        let primaryButton: Alert.Button = request.preview.action == .remove
            ? .destructive(Text(actionTitle)) { applyCloudSecurityGroupRule(request.preview) }
            : .default(Text(actionTitle)) { applyCloudSecurityGroupRule(request.preview) }
        return Alert(
            title: Text(title),
            message: Text(request.risk.confirmationMessage),
            primaryButton: primaryButton,
            secondaryButton: .cancel()
        )
    }

    private func registryRiskAlert(_ request: RegistryRiskRequest) -> Alert {
        let primaryButton: Alert.Button = request.isDestructive
            ? .destructive(Text(request.confirmButtonTitle)) { performRegistryRiskRequest(request) }
            : .default(Text(request.confirmButtonTitle)) { performRegistryRiskRequest(request) }
        return Alert(
            title: Text("\(request.risk.title)?"),
            message: Text(request.risk.confirmationMessage),
            primaryButton: primaryButton,
            secondaryButton: .cancel()
        )
    }

    private var isNginxDraftDirty: Bool {
        viewModel.nginxConfigDraft != (viewModel.nginxConfigContent?.content ?? "")
    }

    private var isEnvironmentDraftDirty: Bool {
        viewModel.environmentFileDraft != (viewModel.environmentFileContent?.content ?? "")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct SystemdActionRequest: Identifiable {
    var unit: SystemdUnit
    var action: SystemdUnitAction

    var id: String {
        "\(unit.id)-\(action.id)"
    }

    var risk: RemoteOperationRisk {
        RemoteOperationRiskFactory.systemd(action: action, unit: unit)
    }
}

private struct DatabaseServiceActionRequest: Identifiable {
    var service: DatabaseService
    var action: SystemdUnitAction

    var id: String {
        "\(service.id)-\(action.id)"
    }

    var risk: RemoteOperationRisk {
        RemoteOperationRiskFactory.databaseService(action: action, service: service)
    }
}

private struct DatabaseBackupRequest: Identifiable {
    var service: DatabaseService
    var plan: DatabaseBackupRestorePlan

    var id: String {
        "\(service.id)-backup-\(plan.backupPath)"
    }

    var risk: RemoteOperationRisk {
        RemoteOperationRiskFactory.databaseBackup(service: service, plan: plan)
    }
}

private struct DockerContainerActionRequest: Identifiable {
    var container: DockerContainer
    var action: DockerContainerAction

    var id: String {
        "\(container.id)-\(action.id)"
    }

    var risk: RemoteOperationRisk {
        RemoteOperationRiskFactory.dockerContainer(action: action, container: container)
    }
}

private struct DockerImageRemoveRequest: Identifiable {
    var image: DockerImage

    var id: String {
        image.id
    }

    var risk: RemoteOperationRisk {
        RemoteOperationRiskFactory.dockerImageRemove(image)
    }
}

private struct DockerWorkspacePanel: View {
    @ObservedObject var viewModel: ServerWorkspaceViewModel
    let profile: ServerProfile
    let appState: AppState
    @Binding var pendingAction: DockerContainerActionRequest?
    @State private var imagePullReference = "nginx:latest"
    @State private var pendingImagePull = false
    @State private var pendingImageRemove: DockerImageRemoveRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(20)

            Divider()

            Group {
                if let snapshot = viewModel.dockerSnapshot {
                    if snapshot.isAvailable {
                        HSplitView {
                            containerList(snapshot.containers)
                                .frame(minWidth: 360, idealWidth: 440)
                            dockerDetail(snapshot)
                                .frame(minWidth: 520)
                        }
                    } else {
                        ContentUnavailableView(
                            "Docker 不可用",
                            systemImage: "shippingbox",
                            description: Text(snapshot.unavailableReason ?? "远端服务器未安装 Docker，或当前用户无法访问 Docker daemon。")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ContentUnavailableView(
                        "No Docker Snapshot",
                        systemImage: "shippingbox",
                        description: Text("Refresh to inspect Docker containers and images on this server.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if viewModel.dockerSnapshot == nil && !viewModel.isLoadingDocker {
                refresh()
            }
        }
        .alert("Pull Docker Image?", isPresented: $pendingImagePull) {
            Button("Cancel", role: .cancel) {}
            Button("Pull") {
                pullDockerImage()
            }
        } message: {
            Text(RemoteOperationRiskFactory.dockerImagePull(reference: imagePullReference).confirmationMessage)
        }
        .alert(item: $pendingImageRemove) { request in
            Alert(
                title: Text("Remove \(request.image.displayName)?"),
                message: Text(request.risk.confirmationMessage),
                primaryButton: .destructive(Text("Remove")) {
                    removeDockerImage(request.image)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Docker")
                    .font(.title2.weight(.semibold))
                Text("通过远端 Docker CLI 查看容器、镜像和日志，支持容器启动、停止和重启。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let snapshot = viewModel.dockerSnapshot, snapshot.isAvailable {
                Text(snapshot.version.map { "Docker \($0)" } ?? "Docker")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Button {
                refresh()
            } label: {
                if viewModel.isLoadingDocker {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                if let message = viewModel.dockerActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if let error = viewModel.dockerErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .offset(y: 28)
        }
    }

    private func containerList(_ containers: [DockerContainer]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("容器")
                    .font(.headline)
                Spacer()
                Text("\(containers.filter(\.isRunning).count)/\(containers.count) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(containers) { container in
                        Button {
                            viewModel.selectDockerContainer(
                                container,
                                profile: profile,
                                sshClient: appState.sshClient,
                                dockerManager: appState.dockerManager
                            )
                        } label: {
                            DockerContainerRowView(
                                container: container,
                                isSelected: viewModel.selectedDockerContainer?.id == container.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .overlay {
                if containers.isEmpty {
                    ContentUnavailableView("No Containers", systemImage: "shippingbox")
                }
            }
        }
    }

    private func dockerDetail(_ snapshot: DockerSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    DockerMetricCard(title: "容器", value: "\(snapshot.containers.count)", subtitle: "全部", systemImage: "shippingbox", tint: .blue)
                    DockerMetricCard(title: "运行中", value: "\(snapshot.runningContainerCount)", subtitle: "running", systemImage: "checkmark.circle", tint: .green)
                    DockerMetricCard(title: "镜像", value: "\(snapshot.images.count)", subtitle: "local", systemImage: "square.stack.3d.up", tint: .purple)
                }

                if let container = viewModel.selectedDockerContainer {
                    selectedContainerDetail(container)
                } else {
                    ContentUnavailableView("Select a Container", systemImage: "shippingbox")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }

                imageList(snapshot.images)
            }
            .padding(20)
        }
    }

    private func selectedContainerDetail(_ container: DockerContainer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(container.displayName)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Text(container.image)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                DockerStateBadge(container: container)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                dockerInfoRow("ID", container.containerID)
                dockerInfoRow("状态", container.status)
                dockerInfoRow("端口", container.ports.isEmpty ? "-" : container.ports)
                dockerInfoRow("创建", container.createdAt.isEmpty ? container.runningFor : container.createdAt)
                dockerInfoRow("命令", container.command)
            }

            HStack {
                dockerActionButton(.start, container: container)
                dockerActionButton(.stop, container: container)
                dockerActionButton(.restart, container: container)
                Spacer()
                Button {
                    viewModel.loadDockerLogs(
                        container: container,
                        profile: profile,
                        sshClient: appState.sshClient,
                        dockerManager: appState.dockerManager
                    )
                } label: {
                    if viewModel.isLoadingDockerLogs {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Logs", systemImage: "doc.text")
                    }
                }
                .disabled(isBusy)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("日志")
                    .font(.headline)
                ScrollView {
                    Text(dockerLogText(for: container))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 180)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func dockerInfoRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func dockerActionButton(_ action: DockerContainerAction, container: DockerContainer) -> some View {
        Button {
            pendingAction = DockerContainerActionRequest(container: container, action: action)
        } label: {
            Label(action.displayName, systemImage: dockerActionIcon(action))
        }
        .disabled(isBusy || isDockerActionDisabled(action, container: container))
    }

    private func isDockerActionDisabled(_ action: DockerContainerAction, container: DockerContainer) -> Bool {
        switch action {
        case .start:
            container.isRunning
        case .stop, .restart:
            !container.isRunning
        }
    }

    private func dockerActionIcon(_ action: DockerContainerAction) -> String {
        switch action {
        case .start:
            "play.fill"
        case .stop:
            "stop.fill"
        case .restart:
            "arrow.clockwise"
        }
    }

    private func imageList(_ images: [DockerImage]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("镜像")
                    .font(.headline)
                Spacer()
                Text("\(images.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("nginx:latest", text: $imagePullReference)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button {
                    pendingImagePull = true
                } label: {
                    if viewModel.isMutatingDockerImage {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Pull", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || !isImagePullReferenceValid)
            }

            if !isImagePullReferenceValid {
                Label("镜像名称只支持常见 Docker reference 字符，不能包含空格、命令符号或路径跳转。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 0) {
                ForEach(images) { image in
                    DockerImageRowView(
                        image: image,
                        remove: {
                            pendingImageRemove = DockerImageRemoveRequest(image: image)
                        },
                        isDisabled: isBusy
                    )
                    if image.id != images.last?.id {
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if images.isEmpty {
                    ContentUnavailableView("No Images", systemImage: "square.stack.3d.up")
                        .frame(minHeight: 120)
                }
            }
        }
    }

    private func dockerLogText(for container: DockerContainer) -> String {
        guard viewModel.dockerContainerLog?.containerID == container.containerID else {
            return "Select Logs to load recent container output."
        }
        let text = viewModel.dockerContainerLog?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "No recent Docker logs." : text
    }

    private func refresh() {
        viewModel.loadDockerSnapshot(
            profile: profile,
            sshClient: appState.sshClient,
            dockerManager: appState.dockerManager
        )
    }

    private func pullDockerImage() {
        viewModel.pullDockerImage(
            reference: imagePullReference,
            profile: profile,
            sshClient: appState.sshClient,
            dockerManager: appState.dockerManager,
            repository: appState.repository
        )
    }

    private func removeDockerImage(_ image: DockerImage) {
        viewModel.removeDockerImage(
            image,
            profile: profile,
            sshClient: appState.sshClient,
            dockerManager: appState.dockerManager,
            repository: appState.repository
        )
    }

    private var isBusy: Bool {
        viewModel.isLoadingDocker ||
            viewModel.isMutatingDockerContainer ||
            viewModel.isMutatingDockerImage ||
            viewModel.isLoadingDockerLogs
    }

    private var isImagePullReferenceValid: Bool {
        (try? DockerManager.validatedImageReference(imagePullReference)) != nil
    }
}

private struct DockerContainerRowView: View {
    let container: DockerContainer
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            DockerStateBadge(container: container)
            VStack(alignment: .leading, spacing: 3) {
                Text(container.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(container.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DockerImageRowView: View {
    let image: DockerImage
    let remove: () -> Void
    let isDisabled: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(image.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(image.imageID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(image.size)
                    .font(.caption.weight(.semibold))
                Text(image.createdSince.isEmpty ? image.createdAt : image.createdSince)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Remove image")
            .disabled(isDisabled)
        }
        .padding(10)
    }
}

private struct DockerStateBadge: View {
    let container: DockerContainer

    var body: some View {
        Text(container.isRunning ? "运行中" : stoppedStateText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(container.isRunning ? .green : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((container.isRunning ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
    }

    private var stoppedStateText: String {
        let state = container.state.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.isEmpty ? "停止" : state
    }
}

private struct DockerMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CronActionRequest: Identifiable {
    var entry: CronEntry
    var action: CronEntryAction

    var id: String {
        "\(entry.id)-\(action.id)"
    }

    var risk: RemoteOperationRisk {
        RemoteOperationRiskFactory.cron(action: action, entry: entry)
    }
}

private struct FirewallRuleRequest: Identifiable {
    var draft: FirewallRuleDraft
    var risk: RemoteOperationRisk

    var id: String {
        risk.id
    }
}

private struct CloudSecurityGroupRuleRequest: Identifiable {
    var preview: CloudSecurityGroupRuleChangePreview

    var id: String {
        preview.id
    }

    var risk: RemoteOperationRisk {
        RemoteOperationRiskFactory.securityGroupChange(preview)
    }
}

private struct DeploymentRollbackRequest: Identifiable {
    var project: DeploymentProject
    var run: DeploymentRun

    var id: String {
        "\(project.id)-\(run.id)"
    }

    var risk: RemoteOperationRisk {
        RemoteOperationRiskFactory.deploymentRollback(project: project, run: run)
    }
}

private struct DeploymentRunRequest: Identifiable {
    var risk: RemoteOperationRisk

    var id: String {
        risk.id
    }
}

private struct RegistryRiskRequest: Identifiable {
    enum Action {
        case verdaccioService(VerdaccioServiceAction)
        case verdaccioUpgrade
    }

    var action: Action
    var risk: RemoteOperationRisk

    var id: String {
        risk.id
    }

    var confirmButtonTitle: String {
        switch action {
        case .verdaccioService(let action):
            action.displayName
        case .verdaccioUpgrade:
            "Upgrade"
        }
    }

    var isDestructive: Bool {
        switch action {
        case .verdaccioService(let action):
            action == .stop || action == .restart
        case .verdaccioUpgrade:
            true
        }
    }

    static func verdaccioService(_ action: VerdaccioServiceAction, draft: VerdaccioInstallDraft) -> RegistryRiskRequest {
        RegistryRiskRequest(
            action: .verdaccioService(action),
            risk: RemoteOperationRiskFactory.verdaccioServiceAction(action, draft: draft)
        )
    }

    static func verdaccioUpgrade(draft: VerdaccioInstallDraft) -> RegistryRiskRequest {
        RegistryRiskRequest(
            action: .verdaccioUpgrade,
            risk: RemoteOperationRiskFactory.verdaccioUpgrade(draft: draft)
        )
    }
}

private struct VerdaccioPackageDeletionRequest: Identifiable {
    let id = UUID()
    var packageName: String
}

private enum DevelopmentServiceRecommendationStatus {
    case recommended
    case allowed
    case needsPreflight
    case forceOnly

    var displayName: String {
        switch self {
        case .recommended:
            L10n.string("Recommended")
        case .allowed:
            L10n.string("Allowed")
        case .needsPreflight:
            L10n.string("Needs Preflight")
        case .forceOnly:
            L10n.string("Force Only")
        }
    }

    var color: Color {
        switch self {
        case .recommended:
            .green
        case .allowed:
            .blue
        case .needsPreflight:
            .secondary
        case .forceOnly:
            .orange
        }
    }
}

private struct NginxSiteRow: View {
    let site: NginxSite
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: site.isReverseProxy ? "arrow.triangle.branch" : "globe")
                .foregroundStyle(site.hasSSL ? .green : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(site.primaryName)
                        .font(.headline)
                        .lineLimit(1)
                    if site.hasSSL {
                        NginxSiteBadge(
                            title: NginxCertificateDisplay.badgeTitle(for: site),
                            color: NginxCertificateDisplay.badgeColor(for: site)
                        )
                    }
                    if site.isReverseProxy {
                        NginxSiteBadge(title: "Proxy", color: .blue)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(10)
        .background(
            isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if !site.listen.isEmpty {
            parts.append(site.listen.joined(separator: ", "))
        }
        if let root = site.root {
            parts.append(root)
        } else if let proxy = site.proxyPasses.first {
            parts.append(proxy)
        }
        if site.hasSSL {
            parts.append(NginxCertificateDisplay.compactExpirySummary(for: site))
        }
        return parts.isEmpty ? site.configPath : parts.joined(separator: " · ")
    }
}

private enum NginxCertificateDisplay {
    static func badgeTitle(for site: NginxSite, now: Date = Date()) -> String {
        guard site.hasSSL else { return "HTTP" }
        if site.sslCertificates.contains(where: { isExpired($0, now: now) }) {
            return "SSL expired"
        }
        if site.sslCertificates.contains(where: { isExpiringSoon($0, now: now) }) {
            return "SSL soon"
        }
        if site.sslCertificates.contains(where: \.hasInspectionError) {
            return "SSL check"
        }
        return "SSL"
    }

    static func badgeColor(for site: NginxSite, now: Date = Date()) -> Color {
        guard site.hasSSL else { return .secondary }
        if site.sslCertificates.contains(where: { isExpired($0, now: now) }) {
            return .red
        }
        if site.sslCertificates.contains(where: { isExpiringSoon($0, now: now) }) ||
            site.sslCertificates.contains(where: \.hasInspectionError) {
            return .orange
        }
        return .green
    }

    static func certificatePathSummary(for site: NginxSite) -> String {
        guard !site.sslCertificatePaths.isEmpty else {
            return "已启用 SSL，但未解析到 ssl_certificate 指令"
        }
        return site.sslCertificatePaths.joined(separator: ", ")
    }

    static func compactExpirySummary(for site: NginxSite, now: Date = Date()) -> String {
        guard site.hasSSL else { return "HTTP" }
        let summaries = site.sslCertificates.compactMap { certificate -> String? in
            if let error = certificate.inspectionError {
                return "证书检查失败: \(error)"
            }
            guard let notAfter = certificate.notAfter else { return nil }
            return relativeExpiryText(notAfter, now: now)
        }
        if let first = summaries.first {
            return first
        }
        if site.sslCertificatePaths.isEmpty {
            return "SSL"
        }
        return "证书未检查"
    }

    static func expirySummary(for site: NginxSite, now: Date = Date()) -> String {
        guard site.hasSSL else { return "-" }
        guard !site.sslCertificates.isEmpty else {
            return site.sslCertificatePaths.isEmpty ? "未解析到证书路径" : "未读取到证书到期时间"
        }
        return site.sslCertificates.map { certificate in
            let path = certificate.path
            if let error = certificate.inspectionError {
                return "\(path): \(error)"
            }
            guard let notAfter = certificate.notAfter else {
                return "\(path): 未读取到到期时间"
            }
            let date = notAfter.formatted(date: .abbreviated, time: .shortened)
            return "\(path): \(date) (\(relativeExpiryText(notAfter, now: now)))"
        }
        .joined(separator: " | ")
    }

    static func issuerSummary(for site: NginxSite) -> String {
        let issuers = site.sslCertificates.compactMap(\.issuer)
        return issuers.isEmpty ? "-" : issuers.joined(separator: " | ")
    }

    private static func isExpired(_ certificate: NginxSSLCertificate, now: Date) -> Bool {
        guard let notAfter = certificate.notAfter else { return false }
        return notAfter <= now
    }

    private static func isExpiringSoon(_ certificate: NginxSSLCertificate, now: Date) -> Bool {
        guard let notAfter = certificate.notAfter else { return false }
        return notAfter > now && notAfter.timeIntervalSince(now) <= 14 * 24 * 60 * 60
    }

    private static func relativeExpiryText(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        let days = Int(ceil(abs(seconds) / (24 * 60 * 60)))
        if seconds <= 0 {
            return "已过期 \(days) 天"
        }
        if days <= 14 {
            return "\(days) 天后到期"
        }
        return "\(days) 天后到期"
    }
}

private struct NginxSiteBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct NginxConfigRow: View {
    let file: NginxConfigFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var metadata: String {
        var parts: [String] = []
        if let size = file.size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let modifiedAt = file.modifiedAt {
            parts.append(modifiedAt.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.isEmpty ? "config" : parts.joined(separator: " · ")
    }
}

private struct EnvironmentFileRow: View {
    let file: EnvironmentFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.path)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var metadata: String {
        var parts = [file.source]
        if let size = file.size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if let modifiedAt = file.modifiedAt {
            parts.append(modifiedAt.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }
}

private struct CloudSecurityGroupRow: View {
    let group: CloudSecurityGroup

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: group.isDefault == true ? "lock.shield.fill" : "lock.shield")
                .foregroundStyle(.blue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.body)
                    .lineLimit(1)
                Text(group.securityGroupId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let description = group.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct CloudSecurityGroupRuleRow: View {
    let rule: CloudSecurityGroupRule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(rule.action ?? "unknown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rule.action == "ACCEPT" ? .green : .orange)
                    .frame(width: 64, alignment: .leading)
                Text(rule.protocolName ?? "ALL")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 54, alignment: .leading)
                Text(rule.port ?? "all")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 90, alignment: .leading)
                Text(targetText)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            if let description = rule.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var targetText: String {
        rule.cidrBlock ?? rule.ipv6CidrBlock ?? rule.referencedSecurityGroupId ?? "any"
    }
}

private struct FirewallSummaryTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value.isEmpty ? "unknown" : value)
                    .font(.headline)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RegistryPreflightCheckTile: View {
    let check: RegistryPreflightCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(check.title)
                    .font(.headline)
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let remediation = check.remediation {
                    Text(remediation)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch check.status {
        case .passed:
            "checkmark.circle"
        case .warning:
            "exclamationmark.triangle"
        case .failed:
            "xmark.octagon"
        }
    }

    private var color: Color {
        switch check.status {
        case .passed:
            .green
        case .warning:
            .orange
        case .failed:
            .red
        }
    }
}

private struct RegistryStatusTile: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "unknown" : value)
                .font(.headline)
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Install Progress View

private struct InstallProgressView: View {
    let steps: [InstallStep]
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        // Step indicator
                        VStack(spacing: 0) {
                            Circle()
                                .fill(indicatorColor(for: step.status))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    indicatorIcon(for: step.status)
                                }
                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(lineColor(for: step.status))
                                    .frame(width: 2, height: 24)
                            }
                        }

                        // Step content
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.body.weight(step.status == .running ? .semibold : .regular))
                                .foregroundStyle(step.status == .running ? .primary : .secondary)

                            Text(statusText(for: step.status))
                                .font(.caption)
                                .foregroundStyle(statusColor(for: step.status))
                                .lineLimit(2)
                        }
                        .padding(.bottom, index < steps.count - 1 ? 16 : 0)

                        Spacer()
                    }
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func indicatorIcon(for status: InstallStepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        case .failed:
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
    }

    private func indicatorColor(for status: InstallStepStatus) -> Color {
        switch status {
        case .pending: return .secondary.opacity(0.3)
        case .running: return .accentColor
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func lineColor(for status: InstallStepStatus) -> Color {
        switch status {
        case .completed: return .green.opacity(0.4)
        case .failed: return .red.opacity(0.3)
        default: return .secondary.opacity(0.2)
        }
    }

    private func statusText(for status: InstallStepStatus) -> String {
        switch status {
        case .pending: return "等待中"
        case .running: return "执行中..."
        case .completed(let msg): return msg.isEmpty ? "已完成" : msg
        case .failed(let msg): return msg
        }
    }

    private func statusColor(for status: InstallStepStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return .accentColor
        case .completed: return .green
        case .failed: return .red
        }
    }
}

private struct PubHostedRepositoryCheckTile: View {
    let check: PubHostedRepositoryCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(check.title)
                    .font(.headline)
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch check.status {
        case .passed:
            "checkmark.circle"
        case .warning:
            "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch check.status {
        case .passed:
            .green
        case .warning:
            .orange
        }
    }
}

private struct PubHostedRepositorySnippetView: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct CommandResultView: View {
    let result: CommandResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Exit \(result.exitCode)", systemImage: result.exitCode == 0 ? "checkmark.circle" : "xmark.octagon")
                Text(String(format: "%.2fs", result.duration))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyResult()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }

            outputBlock(title: "stdout", value: result.stdout, isError: false)
            if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outputBlock(title: "stderr", value: result.stderr, isError: true)
            }
        }
    }

    private func outputBlock(title: String, value: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(isError ? .red : .secondary)
            Text(value.isEmpty ? "(empty)" : value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isError ? Color.red.opacity(0.08) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func copyResult() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.clipboardText, forType: .string)
    }
}

private struct CommandHistoryStateBadge: View {
    let entry: CommandHistoryEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        guard let exitCode = entry.exitCode else { return "失败" }
        return exitCode == 0 ? "成功" : "失败"
    }

    private var icon: String {
        entry.exitCode == 0 ? "checkmark.circle.fill" : "xmark.octagon"
    }

    private var color: Color {
        entry.exitCode == 0 ? .green : .red
    }
}

private enum TerminalCommandCategory: String, CaseIterable, Identifiable {
    case system
    case logs
    case network
    case services
    case docker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System"
        case .logs:
            "Logs"
        case .network:
            "Network"
        case .services:
            "Services"
        case .docker:
            "Docker"
        }
    }
}

private struct TerminalCommandSnippet: Identifiable, Equatable {
    var id: String { "\(category.rawValue)-\(title)-\(command)" }
    var category: TerminalCommandCategory
    var title: String
    var command: String
    var systemImage: String
}

private struct TerminalCommandSnippetButton: View {
    let snippet: TerminalCommandSnippet
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: snippet.systemImage)
                    .foregroundStyle(.blue)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(snippet.command)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
                Image(systemName: "arrow.turn.down.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(snippet.command)
    }
}

private struct DashboardResourceCard: Identifiable {
    var id: String { title }
    var title: String
    var value: String
    var subtitle: String
    var fraction: Double
    var tint: Color
    var systemImage: String
}

private struct OverviewServiceCard: Identifiable {
    var id: String { title }
    var title: String
    var value: String
    var subtitle: String
    var systemImage: String
    var tint: Color
    var targetSection: String
}

private struct OverviewRiskItem: Identifiable {
    let id = UUID()
    var message: String
    var color: Color
    var systemImage: String = "exclamationmark.triangle"
}

private enum DevelopmentServiceCategory: String, CaseIterable, Identifiable {
    case git
    case npm
    case pub

    var id: String { rawValue }

    var title: String {
        switch self {
        case .git:
            "Git"
        case .npm:
            "npm"
        case .pub:
            "pub"
        }
    }

    var systemImage: String {
        switch self {
        case .git:
            "point.3.connected.trianglepath.dotted"
        case .npm:
            "shippingbox"
        case .pub:
            "paperplane"
        }
    }

    var subtitle: String {
        switch self {
        case .git:
            "管理 Gitea 和 GitLab CE，覆盖代码托管、用户、仓库和基础 Issue/MR。"
        case .npm:
            "管理 Verdaccio 私有 npm 仓库，覆盖包、用户、策略和备份。"
        case .pub:
            "Dart/Flutter custom hosted repository 配置助手。"
        }
    }
}

private enum DevelopmentServicePageState {
    case notInstalled
    case installedNeedsToken
    case ready
    case error
}

private enum NpmManagementTab: String, CaseIterable, Identifiable {
    case overview
    case packages
    case users
    case policy
    case backup
    case proxy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .packages: "包管理"
        case .users: "用户"
        case .policy: "策略"
        case .backup: "备份"
        case .proxy: "代理"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .packages: "shippingbox"
        case .users: "person.2"
        case .policy: "lock.shield"
        case .backup: "archivebox"
        case .proxy: "network"
        }
    }
}

private enum GitWorkbenchService: String, CaseIterable, Identifiable {
    case gitea
    case gitLab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gitea:
            "Gitea"
        case .gitLab:
            "GitLab CE"
        }
    }

    var subtitle: String {
        switch self {
        case .gitea:
            "轻量私有 Git 托管，适合轻量应用服务器和个人/小团队。"
        case .gitLab:
            "完整 DevOps 平台，覆盖项目、组、成员、MR、CI/CD。"
        }
    }

    var systemImage: String {
        switch self {
        case .gitea:
            "leaf"
        case .gitLab:
            "square.stack.3d.up"
        }
    }

    var managementAreas: [GitManagementArea] {
        switch self {
        case .gitea:
            [
                GitManagementArea(title: "Repositories", systemImage: "folder.badge.gearshape", detail: "列表、创建、归档、删除、默认分支和基础设置。"),
                GitManagementArea(title: "Users", systemImage: "person.2", detail: "用户列表、创建、禁用/删除、管理员状态和重置密码入口。"),
                GitManagementArea(title: "Organizations", systemImage: "building.2", detail: "组织、团队、成员和仓库权限管理。"),
                GitManagementArea(title: "Keys / Tokens", systemImage: "key", detail: "SSH Key、Access Token 列表、创建引导和删除。"),
                GitManagementArea(title: "Issues / Pull Requests", systemImage: "arrow.triangle.pull", detail: "列表、详情、状态切换、标签和分配人员。"),
                GitManagementArea(title: "Packages / Admin", systemImage: "shippingbox", detail: "包列表、管理概览、服务日志和备份入口。"),
            ]
        case .gitLab:
            [
                GitManagementArea(title: "Projects", systemImage: "folder.badge.gearshape", detail: "项目列表、创建、归档、删除、Namespace 和基础设置。"),
                GitManagementArea(title: "Groups / Members", systemImage: "person.3", detail: "组、成员、角色、到期时间和权限变更。"),
                GitManagementArea(title: "Repository", systemImage: "arrow.triangle.branch", detail: "分支、Tags、保护状态和 Deploy Keys。"),
                GitManagementArea(title: "Issues / Merge Requests", systemImage: "arrow.triangle.merge", detail: "列表、详情、状态切换、Reviewer 和关联 Pipeline。"),
                GitManagementArea(title: "CI/CD", systemImage: "play.rectangle", detail: "Pipelines、Jobs、Variables、Runner 状态和日志入口。"),
                GitManagementArea(title: "Packages / Admin", systemImage: "shippingbox", detail: "包、实例概览、服务日志和备份命令预览。"),
            ]
        }
    }
}

private enum GitNativeManagementTab: String, CaseIterable, Identifiable {
    case overview
    case repositories
    case users
    case issues
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "总览"
        case .repositories:
            "仓库/项目"
        case .users:
            "用户/组织"
        case .issues:
            "Issue/MR"
        case .automation:
            "自动化/包"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "rectangle.grid.2x2"
        case .repositories:
            "folder.badge.gearshape"
        case .users:
            "person.3"
        case .issues:
            "record.circle"
        case .automation:
            "play.rectangle"
        }
    }
}

private struct GitManagementArea: Identifiable {
    let id = UUID()
    var title: String
    var systemImage: String
    var detail: String
}

private struct GitNativeSummaryMetric: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var detail: String
}

private struct GitNativeObjectRowData: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var metadata: String
    var systemImage: String
    var giteaRepositoryEditRequest: GiteaRepositoryEditRequest? = nil
    var gitLabProjectEditRequest: GitLabProjectEditRequest? = nil
    var gitLabGroupEditRequest: GitLabGroupEditRequest? = nil
    var giteaOrganizationEditRequest: GiteaOrganizationEditRequest? = nil
    var giteaTeamEditRequest: GiteaTeamEditRequest? = nil
    var deletionRequest: GitNativeDeletionRequest? = nil
    var issueStateRequest: GitNativeIssueStateRequest? = nil
    var pipelineActionRequests: [GitLabPipelineActionRequest] = []
    var jobActionRequests: [GitLabJobActionRequest] = []
    var gitLabJobTraceRequest: GitLabJobTraceRequest? = nil
    var webURL: String? = nil
    var variableEditRequest: GitLabVariableEditRequest? = nil
    var variableDeletionRequest: GitLabVariableDeletionRequest? = nil
    var memberEditRequest: GitLabMemberEditRequest? = nil
    var memberDeletionRequest: GitLabMemberDeletionRequest? = nil
    var giteaUserEditRequest: GiteaUserEditRequest? = nil
    var giteaUserDeletionRequest: GiteaUserDeletionRequest? = nil
    var giteaOrganizationDeletionRequest: GiteaOrganizationDeletionRequest? = nil
    var giteaTeamDeletionRequest: GiteaTeamDeletionRequest? = nil
    var giteaTeamMemberEditRequest: GiteaTeamMemberEditRequest? = nil
    var giteaTeamMemberDeletionRequest: GiteaTeamMemberDeletionRequest? = nil
    var giteaTeamRepositoryDeletionRequest: GiteaTeamRepositoryDeletionRequest? = nil
    var giteaKeyDeletionRequest: GiteaKeyDeletionRequest? = nil
    var giteaAccessTokenDeletionRequest: GiteaAccessTokenDeletionRequest? = nil
    var giteaPackageDetailRequest: GiteaPackageDetailRequest? = nil
    var giteaPackageDeletionRequest: GiteaPackageDeletionRequest? = nil
    var gitLabDeployKeyDeletionRequest: GitLabDeployKeyDeletionRequest? = nil
    var gitLabDeployTokenDeletionRequest: GitLabDeployTokenDeletionRequest? = nil
    var gitLabPackageDeletionRequest: GitLabPackageDeletionRequest? = nil
    var gitLabTagDeletionRequest: GitLabTagDeletionRequest? = nil
}

private enum GitIssueStateFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case closed
    case merged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "全部"
        case .open:
            "打开"
        case .closed:
            "关闭"
        case .merged:
            "已合并"
        }
    }

    func includes(_ state: String) -> Bool {
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .all:
            return true
        case .open:
            return normalized == "open" || normalized == "opened"
        case .closed:
            return normalized == "closed"
        case .merged:
            return normalized == "merged"
        }
    }
}

private struct GitNativeDeletionRequest: Identifiable {
    let id = UUID()
    var kind: GitNativeDeletionKind
    var displayName: String

    var displayType: String {
        switch kind {
        case .giteaRepository:
            "Repository"
        case .gitLabProject:
            "Project"
        case .gitLabGroup:
            "Group"
        }
    }

    var serviceTitle: String {
        switch kind {
        case .giteaRepository:
            "Gitea"
        case .gitLabProject, .gitLabGroup:
            "GitLab"
        }
    }
}

private enum GitNativeDeletionKind {
    case giteaRepository(fullName: String)
    case gitLabProject(projectId: Int64, pathWithNamespace: String)
    case gitLabGroup(groupId: Int64, fullPath: String)
}

private struct GitNativeIssueStateRequest: Identifiable {
    let id = UUID()
    var kind: GitNativeIssueStateKind
    var action: GitNativeIssueStateAction
    var displayName: String

    var displayType: String {
        switch kind {
        case .giteaIssue, .gitLabIssue:
            "Issue"
        case .giteaPullRequest:
            "Pull Request"
        case .gitLabMergeRequest:
            "Merge Request"
        }
    }

    var serviceTitle: String {
        switch kind {
        case .giteaIssue, .giteaPullRequest:
            "Gitea"
        case .gitLabIssue, .gitLabMergeRequest:
            "GitLab"
        }
    }
}

private enum GitNativeIssueStateKind {
    case giteaIssue(repositoryFullName: String, issueNumber: Int)
    case giteaPullRequest(repositoryFullName: String, issueNumber: Int)
    case gitLabIssue(projectId: Int64, iid: Int)
    case gitLabMergeRequest(projectId: Int64, iid: Int)
}

private struct GitLabPipelineActionRequest: Identifiable {
    let id = UUID()
    var projectId: Int64
    var pipelineId: Int64
    var action: GitLabPipelineAction
    var displayName: String
}

private struct GitLabJobActionRequest: Identifiable {
    let id = UUID()
    var projectId: Int64
    var jobId: Int64
    var action: GitLabJobAction
    var displayName: String
}

private struct GitLabJobTraceRequest {
    var projectId: Int64
    var jobId: Int64
    var displayName: String
}

private struct GitLabVariableSaveRequest: Identifiable {
    let id = UUID()
    var mode: GitLabVariableSaveMode
}

private struct GitLabVariableEditRequest {
    var projectId: Int64
    var key: String
    var environmentScope: String
    var variableType: String?
    var protected: Bool
    var masked: Bool
    var raw: Bool?

    init(variable: GitLabVariableSummary) {
        projectId = variable.projectId
        key = variable.key
        environmentScope = variable.environmentScope ?? "*"
        variableType = variable.variableType
        protected = variable.protected
        masked = variable.masked
        raw = variable.raw
    }
}

private struct GitLabVariableDeletionRequest: Identifiable {
    let id = UUID()
    var projectId: Int64
    var key: String
    var environmentScope: String
}

private struct GitLabGroupSaveRequest: Identifiable {
    let id = UUID()
    var mode: GitLabGroupSaveMode
}

private struct GitLabGroupEditRequest {
    var groupId: Int64
    var name: String
    var path: String
    var visibility: String
    var fullPath: String

    init(group: GitLabGroupSummary) {
        groupId = group.id
        name = group.name
        path = group.fullPath.split(separator: "/").last.map(String.init) ?? group.fullPath
        visibility = group.visibility ?? "private"
        fullPath = group.fullPath
    }
}

private struct GitLabMemberSaveRequest: Identifiable {
    let id = UUID()
    var mode: GitLabMemberSaveMode
}

private struct GitLabMemberEditRequest {
    var scope: GitLabMemberScope
    var targetId: Int64
    var userId: Int64
    var accessLevel: Int
    var expiresAt: String?

    init(member: GitLabMemberSummary) {
        scope = member.scope
        targetId = member.targetId
        userId = member.userId
        accessLevel = member.accessLevel
        expiresAt = member.expiresAt
    }
}

private struct GitLabMemberDeletionRequest: Identifiable {
    let id = UUID()
    var scope: GitLabMemberScope
    var targetId: Int64
    var userId: Int64
    var username: String
}

private struct GiteaRepositoryEditRequest {
    var fullName: String
    var description: String?
    var isPrivate: Bool
    var defaultBranch: String?
    var hasIssues: Bool
    var hasWiki: Bool
    var hasPullRequests: Bool
    var hasPackages: Bool
    var isArchived: Bool

    init(repository: GiteaRepositorySummary) {
        fullName = repository.fullName
        description = repository.description
        isPrivate = repository.isPrivate
        defaultBranch = repository.defaultBranch
        hasIssues = repository.hasIssues
        hasWiki = repository.hasWiki
        hasPullRequests = repository.hasPullRequests
        hasPackages = repository.hasPackages
        isArchived = repository.isArchived == true
    }
}

private struct GitLabProjectEditRequest {
    var projectId: Int64
    var pathWithNamespace: String
    var description: String?
    var visibility: String
    var defaultBranch: String?
    var archived: Bool

    init(project: GitLabProjectSummary) {
        projectId = project.id
        pathWithNamespace = project.pathWithNamespace
        description = project.description
        visibility = project.visibility ?? "private"
        defaultBranch = project.defaultBranch
        archived = project.archived
    }
}

private struct GiteaUserSaveRequest: Identifiable {
    let id = UUID()
    var mode: GiteaUserSaveMode
}

private struct GiteaUserEditRequest {
    var username: String
    var fullName: String?
    var email: String?
    var isAdmin: Bool
    var isActive: Bool

    init(user: GiteaUserSummary) {
        username = user.username
        fullName = user.fullName
        email = user.email
        isAdmin = user.isAdmin == true
        isActive = user.isActive != false
    }
}

private struct GiteaUserDeletionRequest: Identifiable {
    let id = UUID()
    var username: String
    var email: String?
    var isAdmin: Bool
}

private struct GiteaOrganizationSaveRequest: Identifiable {
    let id = UUID()
    var mode: GiteaOrganizationSaveMode
}

private struct GiteaOrganizationEditRequest {
    var username: String
    var fullName: String?
    var description: String?
    var website: String?
    var visibility: String?

    init(organization: GiteaOrganizationSummary) {
        username = organization.username
        fullName = organization.fullName
        description = organization.description
        website = organization.website
        visibility = organization.visibility
    }
}

private struct GiteaOrganizationDeletionRequest: Identifiable {
    let id = UUID()
    var username: String
    var fullName: String?
    var description: String?
}

private struct GiteaTeamSaveRequest: Identifiable {
    let id = UUID()
    var mode: GiteaTeamSaveMode
}

private struct GiteaTeamEditRequest {
    var teamId: Int64
    var organization: String
    var name: String
    var description: String?
    var permission: String?
    var includesAllRepositories: Bool
    var canCreateOrgRepo: Bool
    var units: [String]

    init(team: GiteaTeamSummary) {
        teamId = team.id
        organization = team.organization
        name = team.name
        description = team.description
        permission = team.permission
        includesAllRepositories = team.includesAllRepositories == true
        canCreateOrgRepo = team.canCreateOrgRepo ?? true
        units = team.units ?? []
    }
}

private struct GiteaTeamDeletionRequest: Identifiable {
    let id = UUID()
    var teamId: Int64
    var displayName: String

    init(team: GiteaTeamSummary) {
        teamId = team.id
        displayName = "\(team.organization)/\(team.name)"
    }
}

private struct GiteaTeamMemberSaveRequest: Identifiable {
    let id = UUID()
}

private struct GiteaTeamMemberEditRequest {
    var teamId: Int64
    var username: String

    init(member: GiteaTeamMemberSummary) {
        teamId = member.teamId
        username = member.username
    }
}

private struct GiteaTeamMemberDeletionRequest: Identifiable {
    let id = UUID()
    var teamId: Int64
    var username: String
    var displayName: String
}

private struct GiteaTeamRepositorySaveRequest: Identifiable {
    let id = UUID()
}

private struct GiteaTeamRepositoryDeletionRequest: Identifiable {
    let id = UUID()
    var teamId: Int64
    var repositoryFullName: String
    var displayName: String
}

private struct GiteaKeyDeletionRequest: Identifiable {
    let id = UUID()
    var keyId: Int64
    var title: String
    var fingerprint: String?
}

private struct GiteaAccessTokenDeletionRequest: Identifiable {
    let id = UUID()
    var username: String
    var tokenId: Int64
    var name: String
    var tokenLastEight: String?
}

private struct GiteaPackageDetailRequest: Identifiable {
    let id = UUID()
    var owner: String
    var type: String
    var name: String
    var version: String?
}

private struct GiteaPackageDeletionRequest: Identifiable {
    let id = UUID()
    var owner: String
    var type: String
    var name: String
    var version: String?
}

private struct GitLabDeployKeyDeletionRequest: Identifiable {
    let id = UUID()
    var projectId: Int64
    var keyId: Int64
    var title: String
    var fingerprint: String?
}

private struct GitLabDeployTokenDeletionRequest: Identifiable {
    let id = UUID()
    var projectId: Int64
    var tokenId: Int64
    var name: String
    var username: String?
}

private struct GitLabPackageDeletionRequest: Identifiable {
    let id = UUID()
    var projectId: Int64
    var packageId: Int64
    var name: String
    var version: String?
    var packageType: String
}

private struct GitLabTagDeletionRequest: Identifiable {
    let id = UUID()
    var projectId: Int64
    var tagName: String
    var target: String?
}

private struct GitNativeObjectRow: View {
    var row: GitNativeObjectRowData

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.systemImage)
                .foregroundStyle(.blue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if !row.metadata.isEmpty {
                Text(row.metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TrafficSnapshotPoint: Identifiable {
    var id: Date { capturedAt }
    var capturedAt: Date
    var receivedBytes: Double
    var transmittedBytes: Double
    var interfaceName: String?
    var downloadRate: Double = 0
    var uploadRate: Double = 0
}

private extension Array where Element == TrafficSnapshotPoint {
    func withRates() -> [TrafficSnapshotPoint] {
        guard count > 1 else { return self }
        var points = self
        for index in points.indices.dropFirst() {
            let previous = points[points.index(before: index)]
            let seconds = Swift.max(points[index].capturedAt.timeIntervalSince(previous.capturedAt), 1)
            points[index].downloadRate = Swift.max(0, points[index].receivedBytes - previous.receivedBytes) / seconds
            points[index].uploadRate = Swift.max(0, points[index].transmittedBytes - previous.transmittedBytes) / seconds
        }
        return points
    }
}

private enum TrafficFormatter {
    static func bytes(_ bytes: Double) -> String {
        if bytes < 1024 {
            return String(format: "%.0f B", bytes)
        }
        let kib = bytes / 1024
        if kib < 1024 {
            return String(format: "%.1f KiB", kib)
        }
        let mib = kib / 1024
        if mib < 1024 {
            return String(format: "%.1f MiB", mib)
        }
        let gib = mib / 1024
        if gib < 1024 {
            return String(format: "%.1f GiB", gib)
        }
        return String(format: "%.1f TiB", gib / 1024)
    }
}

private struct TrafficSummaryCard: View {
    var title: String
    var value: String
    var subtitle: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .frame(minHeight: 90)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TrafficTrendPanel: View {
    let points: [TrafficSnapshotPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("上下行趋势")
                    .font(.headline)
                Spacer()
                Text("最近 \(points.count) 次采样")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if points.count < 2 {
                ContentUnavailableView(
                    "暂无趋势",
                    systemImage: "waveform.path.ecg",
                    description: Text("再刷新一次后会显示上下行速率折线。")
                )
                .frame(minHeight: 220)
            } else {
                DashboardLineChart(series: [
                    DashboardLineSeries(color: .green, values: normalizedRates(\.uploadRate)),
                    DashboardLineSeries(color: .orange, values: normalizedRates(\.downloadRate)),
                ])
                .frame(height: 220)

                HStack(spacing: 14) {
                    legend("上行", color: .green)
                    legend("下行", color: .orange)
                    Spacer()
                    Text("峰值 \(TrafficFormatter.bytes(maxRate))/s")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var maxRate: Double {
        max(points.map(\.downloadRate).max() ?? 0, points.map(\.uploadRate).max() ?? 0)
    }

    private func normalizedRates(_ keyPath: KeyPath<TrafficSnapshotPoint, Double>) -> [Double] {
        let maxValue = max(maxRate, 1)
        return points.map { min(max($0[keyPath: keyPath] / maxValue, 0), 1) }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrafficInterfaceOverviewPanel: View {
    let summary: NetworkTrafficSummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            TrafficSummaryCard(
                title: "网卡数量",
                value: "\(summary.interfaceCount)",
                subtitle: "非 lo 网卡",
                systemImage: "network",
                tint: .teal
            )
            TrafficSummaryCard(
                title: "网卡接收",
                value: TrafficFormatter.bytes(summary.receivedBytes),
                subtitle: "全部网卡累计 RX",
                systemImage: "arrow.down.to.line.compact",
                tint: .blue
            )
            TrafficSummaryCard(
                title: "网卡发送",
                value: TrafficFormatter.bytes(summary.transmittedBytes),
                subtitle: "全部网卡累计 TX",
                systemImage: "arrow.up.to.line.compact",
                tint: .purple
            )
            TrafficSummaryCard(
                title: "主流量网卡",
                value: summary.busiestInterface?.name ?? "--",
                subtitle: busiestInterfaceSubtitle,
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: .green
            )
        }
    }

    private var busiestInterfaceSubtitle: String {
        guard let busiest = summary.busiestInterface else {
            return "暂无累计流量"
        }
        let share = NetworkTrafficInspector.trafficShare(for: busiest, in: summary)
        return "占比 \(share.formatted(.percent.precision(.fractionLength(0))))"
    }
}

private struct TrafficInterfaceTable: View {
    let interfaces: [NetworkInterfaceTrafficUsage]
    let summary: NetworkTrafficSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("网卡明细")
                    .font(.headline)
                Spacer()
                Text("非 lo 网卡")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if interfaces.isEmpty {
                ContentUnavailableView(
                    "暂无网卡明细",
                    systemImage: "network",
                    description: Text("刷新后会从 /proc/net/dev 解析每张非 lo 网卡的累计收发量。")
                )
                .frame(minHeight: 160)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        header("网卡")
                        header("累计接收")
                        header("累计发送")
                        header("总量")
                        header("占比")
                    }
                    Divider()
                        .gridCellColumns(5)
                    ForEach(interfaces) { item in
                        GridRow {
                            Text(item.name)
                                .fontWeight(.semibold)
                            Text(TrafficFormatter.bytes(item.receivedBytes))
                            Text(TrafficFormatter.bytes(item.transmittedBytes))
                            Text(TrafficFormatter.bytes(item.totalBytes))
                            trafficShareBar(for: item)
                        }
                        .font(.caption)
                        .monospacedDigit()
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func trafficShareBar(for item: NetworkInterfaceTrafficUsage) -> some View {
        let share = NetworkTrafficInspector.trafficShare(for: item, in: summary)
        return HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(Color.green.opacity(0.72))
                        .frame(width: proxy.size.width * share)
                }
            }
            .frame(width: 76, height: 6)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private struct TrafficHistoryTable: View {
    let points: [TrafficSnapshotPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("流量历史")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    header("时间")
                    header("下行速率")
                    header("上行速率")
                    header("累计接收")
                    header("累计发送")
                }
                Divider()
                    .gridCellColumns(5)
                ForEach(points.reversed()) { point in
                    GridRow {
                        Text(point.capturedAt.formatted(date: .omitted, time: .standard))
                        Text("\(TrafficFormatter.bytes(point.downloadRate))/s")
                        Text("\(TrafficFormatter.bytes(point.uploadRate))/s")
                        Text(TrafficFormatter.bytes(point.receivedBytes))
                        Text(TrafficFormatter.bytes(point.transmittedBytes))
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct DeploymentServiceLink: Identifiable {
    var project: DeploymentProject
    var unitName: String
    var unit: SystemdUnit?

    var id: String {
        "\(project.id.uuidString):\(unitName)"
    }
}

private struct DeploymentServiceMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct OverviewServiceCardView: View {
    let card: OverviewServiceCard

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.systemImage)
                .font(.title2)
                .foregroundStyle(card.tint)
                .frame(width: 34, height: 34)
                .background(card.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(card.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(card.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(minHeight: 86)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DashboardResourceRingCard: View {
    let card: DashboardResourceCard

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label(card.title, systemImage: card.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(card.value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(card.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DashboardRingProgress(fraction: card.fraction, tint: card.tint)
                .frame(width: 76, height: 76)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DashboardRingProgress: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.14), lineWidth: 7)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((min(max(fraction, 0), 1) * 100).rounded()))%")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
        }
    }
}

private struct DashboardTrendPanel: View {
    let snapshots: [ServerDashboardSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("资源趋势")
                    .font(.headline)
                Spacer()
                Text("最近 \(snapshots.count) 次采样")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if snapshots.count < 2 {
                ContentUnavailableView(
                    "暂无趋势",
                    systemImage: "chart.xyaxis.line",
                    description: Text("多刷新几次后会显示负载、内存和磁盘趋势。")
                )
                .frame(minHeight: 220)
            } else {
                DashboardLineChart(series: chartSeries)
                    .frame(height: 220)
                HStack(spacing: 14) {
                    chartLegend("负载", color: .green)
                    chartLegend("内存", color: .blue)
                    chartLegend("磁盘", color: .orange)
                }
                .font(.caption)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var chartSeries: [DashboardLineSeries] {
        let loadValues = snapshots.map { snapshot in
            let cores = DashboardMetricParser.cpuCores(from: metric("CPU Cores", in: snapshot)?.value) ?? 1
            let load = DashboardMetricParser.loadAverage(from: metric("Load Average", in: snapshot)?.value).first ?? 0
            return min(max(load / Double(max(cores, 1)), 0), 1)
        }
        let memoryValues = snapshots.map { snapshot in
            DashboardMetricParser.usagePair(from: metric("Memory", in: snapshot)?.value)?.fraction ?? 0
        }
        let diskValues = snapshots.map { snapshot in
            DashboardMetricParser.usagePair(from: metric("Root Disk", in: snapshot)?.value)?.fraction ?? 0
        }
        return [
            DashboardLineSeries(color: .green, values: loadValues),
            DashboardLineSeries(color: .blue, values: memoryValues),
            DashboardLineSeries(color: .orange, values: diskValues),
        ]
    }

    private func metric(_ name: String, in snapshot: ServerDashboardSnapshot) -> DashboardMetric? {
        snapshot.metrics.first { $0.name == name }
    }

    private func chartLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DashboardLineSeries {
    var color: Color
    var values: [Double]
}

private struct DashboardLineChart: View {
    let series: [DashboardLineSeries]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { _ in
                        Divider()
                        Spacer(minLength: 0)
                    }
                    Divider()
                }
                .opacity(0.45)

                ForEach(Array(series.enumerated()), id: \.offset) { _, line in
                    path(for: line.values, size: size)
                        .stroke(line.color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    ForEach(Array(points(for: line.values, size: size).enumerated()), id: \.offset) { _, point in
                        Circle()
                            .fill(line.color)
                            .frame(width: 5, height: 5)
                            .position(point)
                    }
                }
            }
        }
    }

    private func points(for values: [Double], size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let horizontalStep = values.count == 1 ? 0 : size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, rawValue in
            let value = min(max(rawValue, 0), 1)
            return CGPoint(
                x: CGFloat(index) * horizontalStep,
                y: size.height - CGFloat(value) * size.height
            )
        }
    }

    private func path(for values: [Double], size: CGSize) -> Path {
        let points = points(for: values, size: size)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

private struct DashboardSystemInfoPanel: View {
    let profile: ServerProfile
    let snapshot: ServerDashboardSnapshot
    let extraCapabilities: [RuntimeCapabilityBadge]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统信息")
                .font(.headline)

            VStack(spacing: 0) {
                infoRow("类型", profile.serverKind.displayName)
                infoRow("主机", profile.host)
                infoRow("系统", snapshot.capabilities.osName ?? "--")
                infoRow("内核", snapshot.capabilities.kernelVersion ?? "--")
                infoRow("运行", metric("Uptime")?.value ?? "--")
                infoRow("用户", profile.username)
                HStack(alignment: .top, spacing: 8) {
                    Text("能力")
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
                        CapabilityBadge(title: "/proc", enabled: snapshot.capabilities.hasProc)
                        CapabilityBadge(title: "systemd", enabled: snapshot.capabilities.hasSystemd)
                        CapabilityBadge(title: "sftp", enabled: snapshot.capabilities.hasSFTP)
                        ForEach(extraCapabilities) { capability in
                            CapabilityBadge(title: capability.title, enabled: capability.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }

    private func metric(_ name: String) -> DashboardMetric? {
        snapshot.metrics.first { $0.name == name }
    }
}

private struct RuntimeCapabilityBadge: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var enabled: Bool
}

private struct DashboardMetricsTable: View {
    let metrics: [DashboardMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("指标明细")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    tableHeader("指标")
                    tableHeader("值")
                    tableHeader("单位")
                    tableHeader("来源")
                }
                Divider()
                    .gridCellColumns(4)
                ForEach(metrics) { metric in
                    GridRow {
                        Text(L10n.string(metric.name))
                        Text(metric.value)
                            .fontWeight(.semibold)
                        Text(metric.unit.map(L10n.string) ?? "--")
                            .foregroundStyle(.secondary)
                        Text(L10n.string(metric.source))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tableHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private enum DashboardMetricParser {
    static func loadAverage(from value: String?) -> [Double] {
        guard let value else { return [] }
        return value
            .split(separator: "/")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func cpuCores(from value: String?) -> Int? {
        guard let value else { return nil }
        return Int(value.trimmingCharacters(in: CharacterSet.decimalDigits.inverted))
    }

    static func usagePair(from value: String?) -> (used: Double, total: Double, fraction: Double)? {
        guard let value else { return nil }
        let parts = value.split(separator: "/").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let used = storageValue(parts[0]),
              let total = storageValue(parts[1]),
              total > 0
        else { return nil }
        return (used, total, min(max(used / total, 0), 1))
    }

    static func bytePair(from value: String?) -> (received: Double, transmitted: Double)? {
        guard let value else { return nil }
        let parts = value.split(separator: "/").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let received = storageValue(parts[0]),
              let transmitted = storageValue(parts[1])
        else { return nil }
        return (received, transmitted)
    }

    private static func storageValue(_ value: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let numberRange = Range(match.range(at: 1), in: value),
              let unitRange = Range(match.range(at: 2), in: value),
              let number = Double(value[numberRange])
        else { return nil }
        switch value[unitRange].lowercased() {
        case "b":
            return number
        case "kib", "kb":
            return number * 1024
        case "mib", "mb":
            return number * 1024 * 1024
        case "gib", "gb":
            return number * 1024 * 1024 * 1024
        case "tib", "tb":
            return number * 1024 * 1024 * 1024 * 1024
        default:
            return number
        }
    }
}

private struct CapabilityBadge: View {
    let title: String
    let enabled: Bool

    var body: some View {
        Label(title, systemImage: enabled ? "checkmark.circle" : "minus.circle")
            .font(.caption)
            .foregroundStyle(enabled ? .green : .secondary)
    }
}

private struct SystemdUnitRow: View {
    let unit: SystemdUnit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: unit.isRunning ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(unit.isRunning ? .green : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(unit.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(unit.description.isEmpty ? "\(unit.activeState) / \(unit.subState)" : unit.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(unit.activeState)
                .font(.caption)
                .foregroundStyle(unit.isRunning ? .green : .secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

private struct SystemdStateBadge: View {
    let unit: SystemdUnit

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(unit.activeState)
                .font(.caption.weight(.semibold))
                .foregroundStyle(unit.isRunning ? .green : .secondary)
            Text("\(unit.loadState) / \(unit.subState)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}

private struct ServiceCategoryBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.12), in: Capsule())
    }
}

private struct DatabaseServiceStateBadge: View {
    let service: DatabaseService

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(service.unitName ?? "no unit")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        guard service.isInstalled else { return "未发现" }
        return service.isRunning ? "运行中" : service.activeState
    }

    private var color: Color {
        if !service.isInstalled { return .secondary }
        return service.isRunning ? .green : .orange
    }
}

private struct CronStateBadge: View {
    let entry: CronEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(entry.isEnabled ? .green : .orange)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.isEnabled ? .green : .orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background((entry.isEnabled ? Color.green : Color.orange).opacity(0.12), in: Capsule())
    }

    private var title: String {
        entry.isEnabled ? "启用" : "禁用"
    }
}

private struct RemoteFileRow: View {
    let entry: RemoteFileEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let size = entry.size, entry.kind != .directory {
                Text(Self.formatBytes(size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch entry.kind {
        case .directory:
            "folder"
        case .file:
            "doc"
        case .symlink:
            "link"
        case .other:
            "questionmark.square"
        }
    }

    private var iconColor: Color {
        entry.kind == .directory ? .accentColor : .secondary
    }

    private var metadata: String {
        var parts = [entry.permissions]
        if let modifiedAt = entry.modifiedAt {
            parts.append(modifiedAt.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append(entry.path)
        return parts.joined(separator: " · ")
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value < 1024 {
            return "\(bytes) B"
        }
        let kib = value / 1024
        if kib < 1024 {
            return String(format: "%.1f KiB", kib)
        }
        let mib = kib / 1024
        if mib < 1024 {
            return String(format: "%.1f MiB", mib)
        }
        return String(format: "%.1f GiB", mib / 1024)
    }
}

private struct DevelopmentServiceAlertsModifier: ViewModifier {
    @ObservedObject var viewModel: ServerWorkspaceViewModel
    let profile: ServerProfile
    let appState: AppState
    @Binding var pendingGitLabInstall: Bool
    @Binding var pendingGiteaInstall: Bool
    @Binding var pendingGitLabServiceAction: GitLabServiceAction?

    func body(content: Content) -> some View {
        content
            .alert(gitLabInstallAlertTitle, isPresented: $pendingGitLabInstall) {
                Button(L10n.string("Cancel"), role: .cancel) {}
                Button(L10n.string("Install"), role: .destructive) {
                    installGitLab()
                }
            } message: {
                Text(gitLabInstallConfirmationMessage)
            }
            .alert(L10n.string("Install Gitea?"), isPresented: $pendingGiteaInstall) {
                Button(L10n.string("Cancel"), role: .cancel) {}
                Button(L10n.string("Install"), role: .destructive) {
                    installGitea()
                }
            } message: {
                Text(giteaInstallConfirmationMessage)
            }
            .alert(item: $pendingGitLabServiceAction) { action in
                gitLabServiceActionAlert(action)
            }
    }

    private var gitLabInstallAlertTitle: String {
        if viewModel.gitLabPreflightReport?.isReady == false {
            return L10n.string("Force Install GitLab?")
        }
        return L10n.string("Install GitLab?")
    }

    private var gitLabInstallConfirmationMessage: String {
        let base = RemoteOperationRiskFactory.installGitLab(draft: viewModel.gitLabDraft).confirmationMessage
        guard viewModel.gitLabPreflightReport?.isReady == false else { return base }
        let blockers = viewModel.gitLabPreflightReport?.checks
            .filter { $0.status == .failed }
            .map(\.title)
            .joined(separator: ", ") ?? ""
        return [
            L10n.format("Preflight still has blocking checks: %@.", blockers),
            L10n.string("You can force installation, but installation may fail or the service may be unusable."),
            "",
            base,
        ].joined(separator: "\n")
    }

    private var giteaInstallConfirmationMessage: String {
        [
            L10n.string("This will install Gitea as a systemd service on the selected server."),
            L10n.format("External URL: %@", viewModel.giteaDraft.externalURL),
            L10n.format("Service: %@.service", viewModel.giteaDraft.serviceName),
            L10n.format("Listen port: %d", viewModel.giteaDraft.listenPort),
            L10n.format("Binary: %@", viewModel.giteaDraft.installPath),
            L10n.format("Data path: %@", viewModel.giteaDraft.dataPath),
            L10n.string("Gitea uses SQLite by default in this lightweight setup. Finish admin setup in the browser after installation."),
        ].joined(separator: "\n")
    }

    private func installGitLab() {
        viewModel.installGitLabWithProgress(
            profile: profile,
            sshClient: appState.sshClient,
            gitLabInstaller: appState.gitLabInstaller,
            repository: appState.repository
        )
    }

    private func installGitea() {
        viewModel.installGiteaWithProgress(
            profile: profile,
            sshClient: appState.sshClient,
            repository: appState.repository
        )
    }

    private func gitLabServiceActionAlert(_ action: GitLabServiceAction) -> Alert {
        let risk = RemoteOperationRiskFactory.gitLabServiceAction(action, draft: viewModel.gitLabDraft)
        let primaryButton: Alert.Button = action == .stop || action == .restart || action == .reconfigure
            ? .destructive(Text(action.displayName)) { performGitLabServiceAction(action) }
            : .default(Text(action.displayName)) { performGitLabServiceAction(action) }
        return Alert(
            title: Text(L10n.format("%@ GitLab?", action.displayName)),
            message: Text(risk.confirmationMessage),
            primaryButton: primaryButton,
            secondaryButton: .cancel()
        )
    }

    private func performGitLabServiceAction(_ action: GitLabServiceAction) {
        viewModel.performGitLabServiceAction(
            action,
            profile: profile,
            sshClient: appState.sshClient,
            gitLabManager: appState.gitLabManager,
            repository: appState.repository
        )
    }
}

private struct RemoteFileEditorSheetsModifier: ViewModifier {
    @ObservedObject var viewModel: ServerWorkspaceViewModel
    let profile: ServerProfile
    let appState: AppState
    @Binding var renameEntry: RemoteFileEntry?
    @Binding var renameText: String
    @Binding var createKind: RemoteFileCreationKind?
    @Binding var createName: String
    @Binding var permissionsEntry: RemoteFileEntry?
    @Binding var permissionsText: String

    func body(content: Content) -> some View {
        content
            .sheet(item: $renameEntry) { entry in
                RenameRemoteFileSheet(
                    entry: entry,
                    name: $renameText,
                    cancel: {
                        renameEntry = nil
                    },
                    rename: {
                        renameRemoteFile(entry)
                    }
                )
            }
            .sheet(item: $createKind) { kind in
                CreateRemoteFileItemSheet(
                    kind: kind,
                    name: $createName,
                    directoryPath: viewModel.remoteFilePath,
                    cancel: {
                        createKind = nil
                    },
                    create: {
                        createRemoteFileItem(kind)
                    }
                )
            }
            .sheet(item: $permissionsEntry) { entry in
                RemoteFilePermissionsSheet(
                    entry: entry,
                    mode: $permissionsText,
                    cancel: {
                        permissionsEntry = nil
                    },
                    save: {
                        changeRemoteFilePermissions(entry)
                    }
                )
            }
            .sheet(item: remoteTextFileBinding) { textFile in
                remoteTextEditorSheet(textFile)
            }
    }

    private var remoteTextFileBinding: Binding<RemoteTextFile?> {
        Binding(
            get: { viewModel.remoteTextFile },
            set: { viewModel.remoteTextFile = $0 }
        )
    }

    private func renameRemoteFile(_ entry: RemoteFileEntry) {
        viewModel.renameRemoteFile(
            entry,
            to: renameText,
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
        renameEntry = nil
    }

    private func createRemoteFileItem(_ kind: RemoteFileCreationKind) {
        viewModel.createRemoteFileItem(
            named: createName,
            kind: kind,
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
        createKind = nil
    }

    private func changeRemoteFilePermissions(_ entry: RemoteFileEntry) {
        viewModel.changeRemoteFilePermissions(
            entry,
            mode: permissionsText,
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
        permissionsEntry = nil
    }

    private func remoteTextEditorSheet(_ textFile: RemoteTextFile) -> RemoteTextEditorSheet {
        RemoteTextEditorSheet(
            textFile: textFile,
            draft: $viewModel.remoteTextDraft,
            isSaving: viewModel.isSavingRemoteText,
            cancel: {
                viewModel.closeRemoteTextEditor()
            },
            save: {
                saveRemoteTextFile()
            },
            saveAs: { targetPath in
                saveRemoteTextFileAs(targetPath)
            },
            suggestedSaveAsPath: {
                suggestedRemoteSaveAsPath(for: textFile.path)
            }
        )
    }

    private func saveRemoteTextFile() {
        viewModel.saveRemoteTextFile(
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
    }

    private func saveRemoteTextFileAs(_ targetPath: String) {
        viewModel.saveRemoteTextFileAs(
            targetPath: targetPath,
            profile: profile,
            sshClient: appState.sshClient,
            remoteFileService: appState.remoteFileService,
            repository: appState.repository
        )
    }

    private func suggestedRemoteSaveAsPath(for path: String) -> String {
        let parent = RemoteFileService.parentPath(for: path)
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name.isEmpty {
            return RemoteFileService.joinedPath(basePath: parent, name: "copy.txt")
        }
        return RemoteFileService.joinedPath(basePath: parent, name: "\(name).copy")
    }
}

private struct RenameRemoteFileSheet: View {
    let entry: RemoteFileEntry
    @Binding var name: String
    let cancel: () -> Void
    let rename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Rename")
                .font(.title2.weight(.semibold))

            Text(entry.path)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Rename", action: rename)
                    .buttonStyle(.borderedProminent)
                    .disabled(RemoteFileService.validatedFileName(name).isEmpty || name == entry.name)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct CreateRemoteFileItemSheet: View {
    let kind: RemoteFileCreationKind
    @Binding var name: String
    let directoryPath: String
    let cancel: () -> Void
    let create: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kind.title)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(directoryPath)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("Creates a new \(kind == .file ? "empty file" : "folder") in the current remote directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .disabled(RemoteFileService.validatedFileName(name).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct RemoteFilePermissionsSheet: View {
    let entry: RemoteFileEntry
    @Binding var mode: String
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.path)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("Current: \(entry.permissions)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Octal mode", text: $mode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            RiskPreviewView(risk: RemoteOperationRiskFactory.changePermissions(entry: entry, mode: mode))

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Apply", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!Self.isValidOctalMode(mode))
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    static func octalMode(from permissions: String) -> String {
        guard permissions.count >= 10 else { return "644" }
        let permissionCharacters = Array(permissions.dropFirst().prefix(9))
        guard permissionCharacters.count == 9 else { return "644" }
        let chunks = stride(from: 0, to: 9, by: 3).map { offset in
            permissionCharacters[offset..<offset + 3].reduce(0) { value, character in
                value + (character == "r" ? 4 : character == "w" ? 2 : character == "x" || character == "s" || character == "t" ? 1 : 0)
            }
        }
        return chunks.map(String.init).joined()
    }

    private static func isValidOctalMode(_ mode: String) -> Bool {
        let trimmed = mode.trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = Array(trimmed)
        return [3, 4].contains(characters.count) && characters.allSatisfy { "01234567".contains($0) }
    }
}

private struct RiskPreviewView: View {
    let risk: RemoteOperationRisk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(risk.level.displayName, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(risk.title)
                    .font(.caption.weight(.semibold))
                Spacer()
            }

            Text(risk.target)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            if let command = risk.commandPreview {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Text(risk.impact.joined(separator: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch risk.level {
        case .low:
            .secondary
        case .medium:
            .orange
        case .high, .critical:
            .red
        }
    }
}

private struct RemoteTextEditorSheet: View {
    let textFile: RemoteTextFile
    @Binding var draft: String
    let isSaving: Bool
    let cancel: () -> Void
    let save: () -> Void
    let saveAs: (String) -> Void
    let suggestedSaveAsPath: () -> String
    @State private var saveAsPath = ""
    @State private var isShowingSaveAs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(textFile.path)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(Self.formatBytes(textFile.byteCount)) · \(textFile.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close", action: cancel)
                    .disabled(isSaving)
                Button {
                    saveAsPath = suggestedSaveAsPath()
                    isShowingSaveAs = true
                } label: {
                    Label("Save As", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(isSaving)
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }

            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .sheet(isPresented: $isShowingSaveAs) {
            RemoteTextSaveAsSheet(
                sourcePath: textFile.path,
                targetPath: $saveAsPath,
                isSaving: isSaving,
                cancel: {
                    isShowingSaveAs = false
                },
                save: {
                    saveAs(saveAsPath)
                    isShowingSaveAs = false
                }
            )
        }
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let value = Double(bytes)
        if value < 1024 {
            return "\(bytes) B"
        }
        let kib = value / 1024
        if kib < 1024 {
            return String(format: "%.1f KiB", kib)
        }
        return String(format: "%.1f MiB", kib / 1024)
    }
}

private struct RemoteTextSaveAsSheet: View {
    let sourcePath: String
    @Binding var targetPath: String
    let isSaving: Bool
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Save As")
                .font(.title2.weight(.semibold))

            Text(sourcePath)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            TextField("Remote path", text: $targetPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .disabled(isSaving)
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || RemoteFileService.normalizedFilePath(targetPath).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct RemoteTransferJobsView: View {
    let jobs: [RemoteFileTransferJob]
    let isQueuePaused: Bool
    let cancel: () -> Void
    let cancelJob: (RemoteFileTransferJob) -> Void
    let clearPending: () -> Void
    let clearCompleted: () -> Void
    let pauseQueue: () -> Void
    let resumeQueue: () -> Void
    let retryAll: () -> Void
    let retry: (RemoteFileTransferJob) -> Void
    let promote: (RemoteFileTransferJob) -> Void
    let moveUp: (RemoteFileTransferJob) -> Void
    let moveDown: (RemoteFileTransferJob) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Transfers", systemImage: "arrow.up.arrow.down")
                    .font(.headline)
                Spacer()
                if jobs.contains(where: { $0.status.isRetryable }) {
                    Button {
                        retryAll()
                    } label: {
                        Label("Resume All", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.bordered)
                }
                if jobs.contains(where: { $0.status == .pending }) {
                    Button {
                        isQueuePaused ? resumeQueue() : pauseQueue()
                    } label: {
                        Label(isQueuePaused ? "Resume" : "Pause", systemImage: isQueuePaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        clearPending()
                    } label: {
                        Label("Clear Pending", systemImage: "minus.circle")
                    }
                    .buttonStyle(.bordered)
                }
                if jobs.contains(where: { $0.status.isTerminal }) {
                    Button {
                        clearCompleted()
                    } label: {
                        Label("Clear Finished", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                if jobs.contains(where: { $0.status == .running }) {
                    Button {
                        cancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }

            ForEach(jobs.prefix(4)) { job in
                HStack(spacing: 10) {
                    Image(systemName: iconName(for: job))
                        .foregroundStyle(color(for: job))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(job.direction.displayName) \(fileName(for: job))")
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if job.status == .running, job.progressFraction == nil {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: 180)
                        } else if let progressFraction = job.progressFraction {
                            ProgressView(value: progressFraction)
                                .controlSize(.small)
                                .frame(maxWidth: 180)
                        }
                        Text(metadata(for: job))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if job.status == .pending {
                        pendingOrderControls(for: job)
                    }

                    if job.status == .pending || job.status == .running {
                        Button {
                            cancelJob(job)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Cancel this transfer")
                    }

                    if job.status.isRetryable {
                        Button {
                            retry(job)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Resume transfer")
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func pendingOrderControls(for job: RemoteFileTransferJob) -> some View {
        let pendingJobs = jobs.filter { $0.status == .pending }
        if let index = pendingJobs.firstIndex(where: { $0.id == job.id }) {
            Button {
                promote(job)
            } label: {
                Image(systemName: "arrow.up.to.line")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Move to next in queue")

            Button {
                moveUp(job)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Move transfer up")

            Button {
                moveDown(job)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == pendingJobs.count - 1)
            .help("Move transfer down")
        }
    }

    private func iconName(for job: RemoteFileTransferJob) -> String {
        switch job.status {
        case .pending:
            "hourglass"
        case .running:
            "clock.arrow.circlepath"
        case .succeeded:
            "checkmark.circle"
        case .failed:
            "xmark.octagon"
        case .cancelled:
            "minus.circle"
        case .interrupted:
            "exclamationmark.triangle"
        }
    }

    private func color(for job: RemoteFileTransferJob) -> Color {
        switch job.status {
        case .pending:
            .secondary
        case .running:
            .accentColor
        case .succeeded:
            .green
        case .failed:
            .red
        case .cancelled:
            .secondary
        case .interrupted:
            .orange
        }
    }

    private func fileName(for job: RemoteFileTransferJob) -> String {
        switch job.direction {
        case .upload:
            URL(fileURLWithPath: job.localPath).lastPathComponent
        case .download:
            URL(fileURLWithPath: job.remotePath).lastPathComponent
        }
    }

    private func metadata(for job: RemoteFileTransferJob) -> String {
        var parts = [job.status.rawValue.capitalized]
        if job.backend != .unknown {
            parts.append(job.backend.displayName)
        }
        if job.supportsResume {
            parts.append("resumable")
        }
        if job.supportsStreamingProgress {
            parts.append("streaming progress")
        }
        if let progressFraction = job.progressFraction {
            parts.append("\(Int((progressFraction * 100).rounded()))%")
        } else if job.status == .running {
            parts.append("In progress")
        }
        if let byteCount = job.byteCount {
            parts.append(formatBytes(byteCount))
        }
        if let finishedAt = job.finishedAt {
            parts.append(finishedAt.formatted(date: .omitted, time: .shortened))
        } else {
            parts.append(job.startedAt.formatted(date: .omitted, time: .shortened))
        }
        if let message = job.message {
            parts.append(message)
        } else {
            parts.append(job.remotePath)
        }
        return parts.joined(separator: " · ")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value < 1024 {
            return "\(bytes) B"
        }
        let kib = value / 1024
        if kib < 1024 {
            return String(format: "%.1f KiB", kib)
        }
        return String(format: "%.1f MiB", kib / 1024)
    }
}

private struct CommandFailureView: View {
    let failure: CommandFailureSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Command Failed", systemImage: "xmark.octagon")
                .font(.headline)
                .foregroundStyle(.red)

            Text(failure.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Text(failure.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct HostKeyTrustSheet: View {
    let hostKey: HostKeyInfo
    let trust: () -> Void
    let reject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Trust Host Key?")
                .font(.title2.weight(.semibold))

            Text("Confirm this fingerprint before connecting. Trusting it stores the host key for this server and blocks future mismatches.")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("Host").foregroundStyle(.secondary)
                    Text("\(hostKey.host):\(hostKey.port)")
                }
                GridRow {
                    Text("Algorithm").foregroundStyle(.secondary)
                    Text(hostKey.algorithm)
                }
                GridRow {
                    Text("SHA256").foregroundStyle(.secondary)
                    Text(hostKey.fingerprintSHA256)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            HStack {
                Spacer()
                Button("Reject", role: .cancel, action: reject)
                Button("Trust") {
                    trust()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

extension HostKeyInfo: Identifiable {
    var id: String {
        "\(host):\(port):\(algorithm):\(fingerprintSHA256)"
    }
}
