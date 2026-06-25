import SwiftUI

struct ServerWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ServerWorkspaceViewModel()
    @State private var selectedSection = "overview"
    @State private var commandText = ""

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
                    .foregroundStyle(.secondary)
                Label("Services", systemImage: "gearshape.2")
                    .tag("services")
                    .foregroundStyle(.secondary)
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
        .onAppear {
            viewModel.configure(initialState: appState.connectionState(for: profile))
            viewModel.loadCommandHistory(profile: profile, repository: appState.repository)
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
                            dashboardService: appState.dashboardService
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
