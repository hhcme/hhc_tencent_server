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
    @State private var remoteFilePermissionsEntry: RemoteFileEntry?
    @State private var remoteFilePermissionsText = ""
    @State private var pendingSystemdAction: SystemdActionRequest?
    @State private var cronScheduleText = "0 2 * * *"
    @State private var cronCommandText = ""
    @State private var pendingCronAction: CronActionRequest?

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
            Text(remoteFileTrashEntry.map { "Move \($0.name) to ~/.hhc-server-manager-trash on the remote server." } ?? "")
        }
        .alert(item: $pendingSystemdAction) { request in
            Alert(
                title: Text("\(request.action.displayName) \(request.unit.name)?"),
                message: Text("This will run systemctl \(request.action.rawValue) for \(request.unit.name) on the remote server."),
                primaryButton: .destructive(Text(request.action.displayName)) {
                    viewModel.performSystemdAction(
                        request.action,
                        unitName: request.unit.name,
                        profile: profile,
                        sshClient: appState.sshClient,
                        systemdServiceManager: appState.systemdServiceManager
                    )
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $pendingCronAction) { request in
            Alert(
                title: Text("\(request.action.displayName) Cron Entry?"),
                message: Text(request.entry.command),
                primaryButton: request.action == .delete ? .destructive(Text(request.action.displayName)) {
                    performCronAction(request)
                } : .default(Text(request.action.displayName)) {
                    performCronAction(request)
                },
                secondaryButton: .cancel()
            )
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
            viewModel.configure(initialState: appState.connectionState(for: profile))
            viewModel.loadCommandHistory(profile: profile, repository: appState.repository)
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
                            cloudMetricService: appState.cloudMetricService
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

    private var filesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Files")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 8) {
                    Button {
                        chooseRemoteUploadFile()
                    } label: {
                        Label("Upload", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isRemoteFileSelectionBusy)

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
        }
    }

    private func remoteFileList(_ entries: [RemoteFileEntry]) -> some View {
        List(entries) { entry in
            Button {
                openRemoteFileEntry(entry)
            } label: {
                RemoteFileRow(entry: entry)
            }
            .buttonStyle(.plain)
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
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
            cronManager: appState.cronManager
        )
        cronCommandText = ""
    }

    private func performCronAction(_ request: CronActionRequest) {
        viewModel.performCronEntryAction(
            request.action,
            entry: request.entry,
            profile: profile,
            sshClient: appState.sshClient,
            cronManager: appState.cronManager
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

    private func chooseRemoteUploadFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Upload"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.uploadRemoteFile(
                localURL: url,
                profile: profile,
                sshClient: appState.sshClient,
                transferClient: appState.sshClient,
                remoteFileService: appState.remoteFileService
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
                remoteFileService: appState.remoteFileService
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

    private var currentServerBinding: Binding<UUID> {
        Binding(
            get: { appState.selectedServerId ?? profile.id },
            set: { appState.selectedServerId = $0 }
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
                    cloudMetricService: appState.cloudMetricService
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
}

private struct SystemdActionRequest: Identifiable {
    var unit: SystemdUnit
    var action: SystemdUnitAction

    var id: String {
        "\(unit.id)-\(action.id)"
    }
}

private struct CronActionRequest: Identifiable {
    var entry: CronEntry
    var action: CronEntryAction

    var id: String {
        "\(entry.id)-\(action.id)"
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
                Text(entry.schedule)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }

            Spacer()

            Text(entry.isEnabled ? "enabled" : "disabled")
                .font(.caption)
                .foregroundStyle(entry.isEnabled ? .green : .secondary)
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
                        Text(metadata(for: job))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()
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
