import AppKit
import SwiftUI

struct ServerWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ServerWorkspaceViewModel()
    @State private var selectedSection = "overview"
    @State private var commandText = ""
    @State private var filePathText = "~"
    @State private var remoteFileRenameEntry: RemoteFileEntry?
    @State private var remoteFileRenameText = ""
    @State private var remoteFileTrashEntry: RemoteFileEntry?
    @State private var selectedRemoteFileIDs: Set<String> = []
    @State private var remoteFilePermissionsEntry: RemoteFileEntry?
    @State private var remoteFilePermissionsText = ""
    @State private var pendingSystemdAction: SystemdActionRequest?
    @State private var cronScheduleText = "0 2 * * *"
    @State private var cronCommandText = ""
    @State private var pendingCronAction: CronActionRequest?
    @State private var pendingNginxReload = false
    @State private var pendingNginxSave = false
    @State private var pendingEnvironmentSave = false
    @State private var pendingFirewallRule: FirewallRuleRequest?
    @State private var pendingCloudSecurityGroupRule: CloudSecurityGroupRuleRequest?
    @State private var pendingDeploymentRollback: DeploymentRollbackRequest?
    @State private var pendingVerdaccioInstall = false
    @State private var pendingVerdaccioUserDelete = false
    @State private var pendingVerdaccioRestore = false
    @State private var pendingVerdaccioProxyReload = false
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

    let profile: ServerProfile

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Label("Overview", systemImage: "gauge.with.dots.needle.67percent")
                    .tag("overview")
                Label("Terminal", systemImage: "terminal")
                    .tag("terminal")
                Label("Files", systemImage: "folder")
                    .tag("files")
                Label("Services", systemImage: "gearshape.2")
                    .tag("services")
                Label("Nginx", systemImage: "network")
                    .tag("nginx")
                Label("Firewall", systemImage: "firewall")
                    .tag("firewall")
                Label("Security Groups", systemImage: "lock.shield")
                    .tag("securityGroups")
                Label("Deployments", systemImage: "arrow.down.doc")
                    .tag("deployments")
                Label("Registries", systemImage: "shippingbox")
                    .tag("registries")
                Label("Environment", systemImage: "slider.horizontal.3")
                    .tag("environment")
                Label("Cron", systemImage: "calendar.badge.clock")
                    .tag("cron")
                Label("Cloud", systemImage: "cloud")
                    .tag("cloud")
                    .foregroundStyle(.secondary)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                workspaceToolbar
                Divider()
                detailContent
            }
        }
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
        .alert("SSH Error", isPresented: errorBinding) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
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
                        remoteFileService: appState.remoteFileService
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
                viewModel.reloadNginx(
                    profile: profile,
                    sshClient: appState.sshClient,
                    nginxConfigManager: appState.nginxConfigManager,
                    repository: appState.repository
                )
            }
        } message: {
            Text(RemoteOperationRiskFactory.reloadNginx(path: viewModel.selectedNginxConfig?.path).confirmationMessage)
        }
        .alert("Save Nginx Config?", isPresented: $pendingNginxSave) {
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                viewModel.saveNginxConfig(
                    profile: profile,
                    sshClient: appState.sshClient,
                    nginxConfigManager: appState.nginxConfigManager,
                    repository: appState.repository
                )
            }
        } message: {
            Text(RemoteOperationRiskFactory.saveNginxConfig(path: viewModel.nginxConfigContent?.file.path ?? "nginx").confirmationMessage)
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
        .alert(item: $pendingFirewallRule) { request in
            Alert(
                title: Text("\(request.draft.mutation.displayName) Firewall Rule?"),
                message: Text(request.risk.confirmationMessage),
                primaryButton: request.draft.mutation == .delete ? .destructive(Text(request.draft.mutation.displayName)) {
                    applyFirewallRule(request.draft)
                } : .default(Text(request.draft.mutation.displayName)) {
                    applyFirewallRule(request.draft)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $pendingCloudSecurityGroupRule) { request in
            Alert(
                title: Text("\(request.preview.action.displayName) Security Group Rule?"),
                message: Text(request.risk.confirmationMessage),
                primaryButton: request.preview.action == .remove ? .destructive(Text(request.preview.action.displayName)) {
                    applyCloudSecurityGroupRule(request.preview)
                } : .default(Text(request.preview.action.displayName)) {
                    applyCloudSecurityGroupRule(request.preview)
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
                    verdaccioManager: appState.verdaccioManager
                )
            }
        } message: {
            Text(verdaccioUserDeleteConfirmationMessage)
        }
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
        .sheet(item: $remoteFileRenameEntry) { entry in
            RenameRemoteFileSheet(
                entry: entry,
                name: $remoteFileRenameText,
                cancel: {
                    remoteFileRenameEntry = nil
                },
                rename: {
                    viewModel.renameRemoteFile(
                        entry,
                        to: remoteFileRenameText,
                        profile: profile,
                        sshClient: appState.sshClient,
                        remoteFileService: appState.remoteFileService
                    )
                    remoteFileRenameEntry = nil
                }
            )
        }
        .sheet(item: $remoteFilePermissionsEntry) { entry in
            RemoteFilePermissionsSheet(
                entry: entry,
                mode: $remoteFilePermissionsText,
                cancel: {
                    remoteFilePermissionsEntry = nil
                },
                save: {
                    viewModel.changeRemoteFilePermissions(
                        entry,
                        mode: remoteFilePermissionsText,
                        profile: profile,
                        sshClient: appState.sshClient,
                        remoteFileService: appState.remoteFileService
                    )
                    remoteFilePermissionsEntry = nil
                }
            )
        }
        .sheet(item: $viewModel.remoteTextFile) { textFile in
            RemoteTextEditorSheet(
                textFile: textFile,
                draft: $viewModel.remoteTextDraft,
                isSaving: viewModel.isSavingRemoteText,
                cancel: {
                    viewModel.closeRemoteTextEditor()
                },
                save: {
                    viewModel.saveRemoteTextFile(
                        profile: profile,
                        sshClient: appState.sshClient,
                        remoteFileService: appState.remoteFileService
                    )
                },
                saveAs: { targetPath in
                    viewModel.saveRemoteTextFileAs(
                        targetPath: targetPath,
                        profile: profile,
                        sshClient: appState.sshClient,
                        remoteFileService: appState.remoteFileService
                    )
                },
                suggestedSaveAsPath: {
                    suggestedRemoteSaveAsPath(for: textFile.path)
                }
            )
        }
        .onAppear {
            viewModel.configure(profile: profile, initialState: appState.connectionState(for: profile))
            viewModel.loadCommandHistory(profile: profile, repository: appState.repository)
            viewModel.loadCachedDashboardSnapshot(profile: profile, repository: appState.repository)
            viewModel.loadRemoteFileTransferHistory(profile: profile, repository: appState.repository)
        }
        .onDisappear {
            viewModel.stopDashboardAutoRefresh()
        }
        .onChange(of: viewModel.connectionState) { _, newState in
            appState.setConnectionState(newState, for: profile)
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
        case "nginx":
            nginxPanel
        case "firewall":
            firewallPanel
        case "securityGroups":
            securityGroupsPanel
        case "deployments":
            deploymentsPanel
        case "registries":
            registriesPanel
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
                Label("Servers", systemImage: "chevron.left")
            }

            Picker("Current Server", selection: currentServerBinding) {
                ForEach(appState.servers) { server in
                    Text(server.name).tag(server.id)
                }
            }
            .frame(maxWidth: 280)

            Spacer()

            Button {
                viewModel.runSmokeTest(profile: profile, sshClient: appState.sshClient)
            } label: {
                if viewModel.isRunningSmokeTest {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Smoke Test", systemImage: "checkmark.seal")
                }
            }
            .disabled(viewModel.isRunningSmokeTest)
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
                }

                HStack(spacing: 10) {
                    connectionBadge

                    Button {
                        viewModel.refreshDashboard(
                            profile: profile,
                            sshClient: appState.sshClient,
                            dashboardService: appState.dashboardService,
                            cloudMetricService: appState.cloudMetricService,
                            repository: appState.repository
                        )
                    } label: {
                        if viewModel.isRefreshingDashboard {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh Dashboard", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isRefreshingDashboard)

                    Toggle(isOn: dashboardAutoRefreshBinding) {
                        Label("Auto", systemImage: "timer")
                    }
                    .toggleStyle(.switch)
                    .disabled(viewModel.connectionState == .connecting)

                    Button {
                        viewModel.connect(profile: profile, sshClient: appState.sshClient)
                    } label: {
                        Label("Connect", systemImage: "bolt.horizontal.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRunningSmokeTest || viewModel.connectionState == .connecting)

                    Button {
                        viewModel.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .disabled(viewModel.connectionState == .disconnected || viewModel.connectionState == .connecting)
                }

                Divider()

                dashboardPanel

                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dashboardPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Dashboard")
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
                capabilityPanel(snapshot.capabilities)

                if !snapshot.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snapshot.warnings) { warning in
                            Label("\(warning.source): \(warning.message)", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(snapshot.metrics) { metric in
                        DashboardMetricTile(metric: metric)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Dashboard Snapshot",
                    systemImage: "gauge.with.dots.needle.67percent",
                    description: Text("Refresh the dashboard to collect SSH metrics and server capabilities.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }

    private func capabilityPanel(_ capabilities: ServerCapabilities) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            if let osName = capabilities.osName {
                GridRow {
                    Text("OS").foregroundStyle(.secondary)
                    Text(osName)
                }
            }
            if let kernelVersion = capabilities.kernelVersion {
                GridRow {
                    Text("Kernel").foregroundStyle(.secondary)
                    Text(kernelVersion)
                }
            }
            GridRow {
                Text("Capabilities").foregroundStyle(.secondary)
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

                HStack(spacing: 8) {
                    quickCommandButton("uptime")
                    quickCommandButton("whoami")
                    quickCommandButton("df -h")
                    quickCommandButton("free -h")
                }
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

    private var deploymentsPanel: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Deployments")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button {
                        viewModel.startNewDeploymentProject(serverId: profile.id)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New deployment project")
                }

                if viewModel.deploymentProjects.isEmpty {
                    ContentUnavailableView(
                        "No Deployment Projects",
                        systemImage: "arrow.down.doc",
                        description: Text("Create a project to deploy a GitLab repository over SSH.")
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
        }
    }

    private var registriesPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Package Registries")
                            .font(.title2.weight(.semibold))
                        Text("Verdaccio · \(viewModel.registryDraft.listenHost):\(viewModel.registryDraft.listenPort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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
                                Label("Preflight", systemImage: "checklist")
                            }
                        }
                        .disabled(isRegistryBusy)

                        Button {
                            pendingVerdaccioInstall = true
                        } label: {
                            if viewModel.isInstallingVerdaccio {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Install", systemImage: "arrow.down.circle")
                            }
                        }
                        .disabled(isRegistryBusy || !isRegistryPreflightReady)

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
                                Label("Status", systemImage: "waveform.path.ecg")
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
                                Label("Packages", systemImage: "shippingbox")
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
                                Label("Backup", systemImage: "archivebox")
                            }
                        }
                        .disabled(isRegistryBusy)
                    }
                }

                if let message = viewModel.registryActionMessage {
                    Label(message, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                if let error = viewModel.registryErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Install Path").foregroundStyle(.secondary)
                        Text(viewModel.registryDraft.installPath)
                            .font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("Data Path").foregroundStyle(.secondary)
                        Text(viewModel.registryDraft.dataPath)
                            .font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("Service").foregroundStyle(.secondary)
                        Text("\(viewModel.registryDraft.serviceName).service")
                            .font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("Version").foregroundStyle(.secondary)
                        Text(viewModel.registryDraft.version)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                registryPreflightSection
                verdaccioStatusSection
                verdaccioServiceSection
                verdaccioUsersSection
                verdaccioBackupSection
                verdaccioProxySection
                verdaccioPackagesSection
                pubHostedRepositorySection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                        performVerdaccioServiceAction(action)
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
                    viewModel.upgradeVerdaccio(
                        profile: profile,
                        sshClient: appState.sshClient,
                        verdaccioManager: appState.verdaccioManager,
                        repository: appState.repository
                    )
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
                        verdaccioManager: appState.verdaccioManager
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
                        verdaccioManager: appState.verdaccioManager
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
                        }
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private var deploymentProjectForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Project")
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
                        Label("Save", systemImage: "tray.and.arrow.down")
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
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedDeploymentProject == nil || viewModel.isRunningDeployment)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Website", text: $viewModel.deploymentName)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Repository").foregroundStyle(.secondary)
                    TextField("git@gitlab.com:team/project.git", text: $viewModel.deploymentRepositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Branch").foregroundStyle(.secondary)
                    TextField("main", text: $viewModel.deploymentBranch)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Path").foregroundStyle(.secondary)
                    TextField("/srv/app", text: $viewModel.deploymentPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Build").foregroundStyle(.secondary)
                    TextField("npm ci && npm run build", text: $viewModel.deploymentBuildCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Restart").foregroundStyle(.secondary)
                    TextField("systemctl restart app.service", text: $viewModel.deploymentRestartCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Health Check").foregroundStyle(.secondary)
                    TextField("curl -fsS http://127.0.0.1:3000/health", text: $viewModel.deploymentHealthCheckCommand)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Webhook").foregroundStyle(.secondary)
                    Toggle("Enable GitLab push webhook", isOn: $viewModel.deploymentWebhookEnabled)
                        .toggleStyle(.checkbox)
                }
                if viewModel.deploymentWebhookEnabled {
                    GridRow {
                        Text("Secret").foregroundStyle(.secondary)
                        SecureField(
                            viewModel.selectedDeploymentProject?.webhookSecretRef == nil ? "Required token" : "Leave blank to keep existing token",
                            text: $viewModel.deploymentWebhookSecret
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Listener").foregroundStyle(.secondary)
                        deploymentWebhookListenerControls
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.runDeployment(
                        profile: profile,
                        sshClient: appState.sshClient,
                        deploymentRunner: appState.deploymentRunner,
                        repository: appState.repository,
                        serverManagementService: appState.serverManagementService
                    )
                } label: {
                    if viewModel.isRunningDeployment {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Run Deployment", systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunningDeployment || viewModel.deploymentCommandPlan == nil)

                Button {
                    prepareDeploymentRollback()
                } label: {
                    Label("Rollback", systemImage: "arrow.uturn.backward")
                }
                .disabled(viewModel.isRunningDeployment || viewModel.selectedDeploymentRun?.previousCommit == nil)
                .help("Roll back to the previous commit captured by the selected run")

                Button {
                    viewModel.cancelDeployment()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
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
                Text("Command Preview")
                    .font(.headline)
                Spacer()
                if let root = viewModel.deploymentCommandPlan?.allowedRoot {
                    Text("Allowed root: \(root)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(viewModel.deploymentCommandPlan?.commandPreview ?? "Save a valid deployment configuration to preview commands.")
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
                        Label("Stop", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        viewModel.startDeploymentWebhookListener(appState.deploymentWebhookHTTPServer)
                    } label: {
                        Label("Start", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            }

            if let url = viewModel.deploymentWebhookListenerURL {
                Text(url)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Label("Automatic deployment only works while this Mac app is running and the listener is started.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var deploymentRunHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runs")
                .font(.headline)

            if viewModel.deploymentRuns.isEmpty {
                ContentUnavailableView(
                    "No Runs Yet",
                    systemImage: "clock",
                    description: Text("Run a deployment to capture status, commits, and logs.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Picker("Run", selection: deploymentRunSelectionBinding) {
                    ForEach(viewModel.deploymentRuns) { run in
                        Text(deploymentRunTitle(run)).tag(Optional(run.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 420, alignment: .leading)

                if let run = viewModel.selectedDeploymentRun {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Status").foregroundStyle(.secondary)
                            deploymentStatusBadge(run.status)
                        }
                        GridRow {
                            Text("Started").foregroundStyle(.secondary)
                            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let finishedAt = run.finishedAt {
                            GridRow {
                                Text("Finished").foregroundStyle(.secondary)
                                Text(finishedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        if let previousCommit = run.previousCommit {
                            GridRow {
                                Text("Previous").foregroundStyle(.secondary)
                                Text(previousCommit).font(.system(.body, design: .monospaced))
                            }
                        }
                        if let targetCommit = run.targetCommit {
                            GridRow {
                                Text("Target").foregroundStyle(.secondary)
                                Text(targetCommit).font(.system(.body, design: .monospaced))
                            }
                        }
                        if let summary = run.summary {
                            GridRow {
                                Text("Summary").foregroundStyle(.secondary)
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
                Text("Logs")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if viewModel.isRunningDeployment {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            if viewModel.deploymentLogs.isEmpty {
                Text("No logs captured for this run.")
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
                        cancel: {
                            viewModel.cancelRemoteFileTransfer()
                        },
                        clearPending: {
                            viewModel.cancelPendingRemoteFileTransfers()
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Services")
                        .font(.title2.weight(.semibold))
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

                if let capturedAt = viewModel.systemdUnitList?.capturedAt {
                    Text("Last updated \(capturedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        systemdUnitList(units)
                            .frame(minWidth: 340, idealWidth: 420)
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
            if viewModel.systemdUnitList == nil && !viewModel.isLoadingSystemdUnits {
                viewModel.loadSystemdUnits(
                    profile: profile,
                    sshClient: appState.sshClient,
                    systemdServiceManager: appState.systemdServiceManager
                )
            }
        }
    }

    private func systemdUnitList(_ units: [SystemdUnit]) -> some View {
        List(units, selection: systemdSelectionBinding) { unit in
            SystemdUnitRow(unit: unit)
                .tag(unit.id)
        }
        .overlay {
            if units.isEmpty {
                ContentUnavailableView("No Services", systemImage: "gearshape.2")
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

    private var nginxPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Nginx")
                        .font(.title2.weight(.semibold))
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

                if let capturedAt = viewModel.nginxConfigList?.capturedAt {
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
            }
            .padding(20)

            Divider()

            Group {
                if let files = viewModel.nginxConfigList?.files {
                    HSplitView {
                        nginxConfigList(files)
                            .frame(minWidth: 360, idealWidth: 440)
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
        }
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
                    cronEntryList(entries)
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

    private func cronEntryList(_ entries: [CronEntry]) -> some View {
        List(entries) { entry in
            CronEntryRow(entry: entry)
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
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if entry.isUserCrontabEntry {
                        Button(role: .destructive) {
                            pendingCronAction = CronActionRequest(entry: entry, action: .delete)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        if entry.isEnabled {
                            Button {
                                pendingCronAction = CronActionRequest(entry: entry, action: .disable)
                            } label: {
                                Label("Disable", systemImage: "pause.fill")
                            }
                            .tint(.orange)
                        } else {
                            Button {
                                pendingCronAction = CronActionRequest(entry: entry, action: .enable)
                            } label: {
                                Label("Enable", systemImage: "play.fill")
                            }
                            .tint(.green)
                        }
                    }
                }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("No Cron Entries", systemImage: "calendar.badge.clock")
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

    private func startChangingPermissions(_ entry: RemoteFileEntry) {
        remoteFilePermissionsText = RemoteFilePermissionsSheet.octalMode(from: entry.permissions)
        remoteFilePermissionsEntry = entry
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Command History")
                .font(.headline)

            ForEach(viewModel.persistedCommandHistory) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: entry.exitCode == 0 ? "checkmark.circle" : "clock.badge.exclamationmark")
                        .foregroundStyle(entry.exitCode == 0 ? .green : .secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.command)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(historyMetadata(entry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

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
                    }
                    .buttonStyle(.borderless)
                    .help("Run this command again")
                    .disabled(viewModel.isRunningCommand)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
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
            viewModel.isReloadingNginx
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
            viewModel.isCreatingVerdaccioBackup ||
            viewModel.isRestoringVerdaccioBackup ||
            viewModel.isMutatingVerdaccioUser ||
            viewModel.isWritingVerdaccioProxy ||
            viewModel.isReloadingVerdaccioProxy ||
            viewModel.isRunningVerdaccioNpmSmokeTest ||
            viewModel.isControllingVerdaccioService ||
            viewModel.isUpgradingVerdaccio
    }

    private var isRegistryPreflightReady: Bool {
        viewModel.registryPreflightReport?.isReady == true
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

private struct DashboardMetricTile: View {
    let metric: DashboardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(metric.name)
                    .font(.headline)
                Spacer()
                Text(metric.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(metric.value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let unit = metric.unit {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
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

private struct CronEntryRow: View {
    let entry: CronEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(entry.isEnabled ? .green : .orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.command)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Text(entry.schedule)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                    if let runAsUser = entry.runAsUser {
                        Text("as \(runAsUser)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let sourcePath = entry.sourcePath {
                        Text(sourcePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            Text(entry.isUserCrontabEntry ? (entry.isEnabled ? "enabled" : "disabled") : "system")
                .font(.caption)
                .foregroundStyle(entry.isUserCrontabEntry && entry.isEnabled ? .green : .secondary)
        }
        .padding(.vertical, 4)
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
    let cancel: () -> Void
    let clearPending: () -> Void
    let retry: (RemoteFileTransferJob) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Transfers", systemImage: "arrow.up.arrow.down")
                    .font(.headline)
                Spacer()
                if jobs.contains(where: { $0.status == .pending }) {
                    Button {
                        clearPending()
                    } label: {
                        Label("Clear Pending", systemImage: "minus.circle")
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
