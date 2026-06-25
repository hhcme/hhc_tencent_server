import SwiftUI

struct ServerBrowserView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ServerBrowserViewModel()
    @State private var showingAddServer = false
    @State private var showingCloudImport = false
    @State private var showingCloudResourceCenter = false
    @State private var serverPendingEdit: ServerProfile?
    @State private var serverPendingDeletion: ServerProfile?

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.sourceFilter) {
                Label("All Servers", systemImage: "server.rack")
                    .tag(ServerSourceFilter.all)
                Label("Manual SSH", systemImage: "terminal")
                    .tag(ServerSourceFilter.manual)
                Label("Cloud", systemImage: "cloud")
                    .tag(ServerSourceFilter.cloud)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } content: {
            VStack(spacing: 0) {
                toolbar
                Divider()
                serverList
            }
            .navigationSplitViewColumnWidth(min: 380, ideal: 500)
        } detail: {
            selectedSummary
        }
        .sheet(isPresented: $showingAddServer) {
            AddServerSheet { profile in
                appState.reloadServers()
                viewModel.selectedServerId = profile.id
            }
        }
        .sheet(isPresented: $showingCloudImport) {
            CloudImportSheet { profile in
                appState.reloadServers()
                viewModel.sourceFilter = .cloud
                viewModel.selectedServerId = profile.id
            }
        }
        .sheet(isPresented: $showingCloudResourceCenter) {
            CloudResourceCenterSheet()
        }
        .sheet(item: $serverPendingEdit) { profile in
            AddServerSheet(profile: profile) { updated in
                appState.reloadServers()
                viewModel.selectedServerId = updated.id
            }
        }
        .confirmationDialog(
            "Delete server?",
            isPresented: deleteConfirmationBinding,
            presenting: serverPendingDeletion
        ) { profile in
            Button("Delete", role: .destructive) {
                appState.delete(profile)
                if viewModel.selectedServerId == profile.id {
                    viewModel.selectedServerId = nil
                }
            }
        } message: { profile in
            Text("This removes \(profile.name), its trusted host keys, and stored credentials.")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Search servers", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)

            Spacer()

            Button {
                showingCloudResourceCenter = true
            } label: {
                Label("Resources", systemImage: "externaldrive.connected.to.line.below")
            }

            Button {
                showingCloudImport = true
            } label: {
                Label("Cloud", systemImage: "cloud")
            }

            Button {
                showingAddServer = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private var serverList: some View {
        let servers = viewModel.filteredServers(from: appState.servers, links: appState.cloudInstanceLinks)
        return Group {
            if servers.isEmpty {
                ContentUnavailableView(
                    "No Servers",
                    systemImage: "server.rack",
                    description: Text("Add a server to start the SSH workflow.")
                )
            } else {
                List(servers, selection: $viewModel.selectedServerId) { profile in
                    ServerRowView(
                        profile: profile,
                        cloudLink: viewModel.cloudLink(for: profile, links: appState.cloudInstanceLinks)
                    )
                        .tag(profile.id)
                        .contextMenu {
                            Button("Open") {
                                appState.openWorkspace(for: profile)
                            }
                            Button("Edit") {
                                serverPendingEdit = profile
                            }
                            Button("Delete", role: .destructive) {
                                serverPendingDeletion = profile
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
    }

    private var selectedSummary: some View {
        let profile = appState.servers.first { $0.id == viewModel.selectedServerId }
        return Group {
            if let profile {
                ServerSummaryPanel(
                    profile: profile,
                    cloudLink: viewModel.cloudLink(for: profile, links: appState.cloudInstanceLinks),
                    open: {
                        appState.openWorkspace(for: profile)
                    },
                    edit: {
                        serverPendingEdit = profile
                    },
                    delete: {
                        serverPendingDeletion = profile
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a Server",
                    systemImage: "cursorarrow.click",
                    description: Text("Choose a server to view its connection details.")
                )
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { serverPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    serverPendingDeletion = nil
                }
            }
        )
    }
}

private struct CloudResourceCenterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CloudResourceCenterViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloud Resources")
                        .font(.title2.weight(.semibold))
                    Text("Search synced instances, disks, snapshots, billing states, and provider capabilities.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .font(.title3)
                .foregroundStyle(.secondary)
                .help("Close")
            }
            .padding(22)

            Divider()

            HSplitView {
                cloudControls
                    .frame(minWidth: 310, idealWidth: 350)

                resourceList
                    .frame(minWidth: 360, idealWidth: 470)

                resourceDetail
                    .frame(minWidth: 340, idealWidth: 430)
            }
            .padding(.horizontal, 12)

            Divider()

            HStack(spacing: 10) {
                if viewModel.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding(16)
        }
        .frame(width: 1120, height: 720)
        .onAppear {
            appState.reloadServers()
            viewModel.selectDefaultAccount(from: appState.cloudProviderAccounts)
            viewModel.refreshCapabilityMatrix(registry: appState.cloudProviderRegistry)
            viewModel.refreshLocalResources(appState: appState)
            if viewModel.selectedAccountId != nil {
                Task {
                    await viewModel.loadRegions(appState: appState)
                }
            }
        }
        .onChange(of: viewModel.selectedAccountId) {
            Task {
                await viewModel.loadRegions(appState: appState)
            }
        }
        .onChange(of: viewModel.searchText) {
            viewModel.refreshLocalResources(appState: appState)
        }
        .onChange(of: viewModel.kindFilter) {
            viewModel.refreshLocalResources(appState: appState)
        }
        .onChange(of: viewModel.statusFilter) {
            viewModel.refreshLocalResources(appState: appState)
        }
        .onChange(of: viewModel.selectedRegionId) {
            viewModel.refreshLocalResources(appState: appState)
        }
    }

    private var cloudControls: some View {
        Form {
            Section("Scope") {
                Picker("Account", selection: $viewModel.selectedAccountId) {
                    Text("All accounts").tag(Optional<UUID>.none)
                    ForEach(appState.cloudProviderAccounts) { account in
                        Text("\(account.displayName) · \(account.providerId.displayName)")
                            .tag(Optional(account.id))
                    }
                }

                Picker("Region", selection: $viewModel.selectedRegionId) {
                    Text("All loaded regions").tag("")
                    ForEach(viewModel.regions) { region in
                        Text(region.displayName).tag(region.id)
                    }
                }

                HStack {
                    Button {
                        Task {
                            await viewModel.loadRegions(appState: appState)
                        }
                    } label: {
                        Label("Regions", systemImage: "map")
                    }
                    .disabled(!viewModel.canLoadRegions)

                    Button {
                        Task {
                            await viewModel.syncSelectedRegion(appState: appState)
                        }
                    } label: {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSync)
                }
            }

            Section("Filter") {
                TextField("Search resources", text: $viewModel.searchText)
                Picker("Kind", selection: $viewModel.kindFilter) {
                    ForEach(CloudResourceKindFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                TextField("Status", text: $viewModel.statusFilter)

                Button {
                    viewModel.resetFilters(appState: appState)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
            }

            Section("Capabilities") {
                CapabilityMatrixView(rows: viewModel.capabilityRows)
            }
        }
        .formStyle(.grouped)
    }

    private var resourceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Resources")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.resources.count)")
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)

            if viewModel.resources.isEmpty {
                ContentUnavailableView(
                    "No Resources",
                    systemImage: "externaldrive.connected.to.line.below",
                    description: Text("Select an account and region, then sync cloud resources.")
                )
            } else {
                List(viewModel.resources, selection: $viewModel.selectedResourceId) { resource in
                    CloudUnifiedResourceRow(resource: resource)
                        .tag(resource.id)
                }
                .listStyle(.inset)
            }
        }
    }

    private var resourceDetail: some View {
        Group {
            if let resource = viewModel.selectedResource {
                CloudResourceDetailView(resource: resource)
            } else {
                ContentUnavailableView(
                    "Select a Resource",
                    systemImage: "cursorarrow.click",
                    description: Text("Choose a synced resource to inspect its cloud metadata.")
                )
            }
        }
    }
}

private struct CapabilityMatrixView: View {
    let rows: [ProviderCapabilityStatus]

    private var groups: [CapabilityProviderGroup] {
        Dictionary(grouping: rows, by: \.providerId)
            .map { providerId, rows in
                CapabilityProviderGroup(providerId: providerId, rows: rows.sorted { $0.capability.rawValue < $1.capability.rawValue })
            }
            .sorted { $0.providerName < $1.providerName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groups) { (group: CapabilityProviderGroup) in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(group.providerName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(group.isRegistered ? "Registered" : "Missing")
                            .font(.caption)
                            .foregroundStyle(group.isRegistered ? Color.secondary : Color.red)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(group.supportedRows) { row in
                            Label(row.capability.displayName, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .lineLimit(1)
                        }
                    }
                }
                Divider()
            }
        }
    }
}

private struct CapabilityProviderGroup: Identifiable {
    var id: String { providerId.rawValue }
    let providerId: CloudProviderID
    let rows: [ProviderCapabilityStatus]

    var providerName: String {
        rows.first?.providerName ?? providerId.displayName
    }

    var isRegistered: Bool {
        rows.first?.isRegistered == true
    }

    var supportedRows: [ProviderCapabilityStatus] {
        rows.filter(\.isSupported)
    }
}

private struct CloudUnifiedResourceRow: View {
    let resource: CloudUnifiedResource

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(resource.displayName, systemImage: iconName)
                    .font(.headline)
                Spacer()
                Text(resource.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(resource.resourceId)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 10) {
                Label(resource.providerId.displayName, systemImage: "cloud")
                if let regionId = resource.regionId {
                    Label(regionId, systemImage: "mappin.and.ellipse")
                }
                if let status = resource.status {
                    Label(status, systemImage: "circle.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    private var iconName: String {
        switch resource.kind {
        case .instance:
            "server.rack"
        case .securityGroup:
            "lock.shield"
        case .disk:
            "internaldrive"
        case .snapshot:
            "camera.filters"
        case .billing:
            "creditcard"
        }
    }
}

private struct CloudResourceDetailView: View {
    let resource: CloudUnifiedResource

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Label(resource.displayName, systemImage: iconName)
                    .font(.title3.weight(.semibold))
                Text(resource.kind.displayName)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                detailRow("Provider", resource.providerId.displayName)
                if let regionId = resource.regionId {
                    detailRow("Region", regionId)
                }
                detailRow("Resource ID", resource.resourceId)
                if let status = resource.status {
                    detailRow("Status", status)
                }
                if let primaryAddress = resource.primaryAddress {
                    detailRow(primaryLabel, primaryAddress)
                }
                if let secondaryText = resource.secondaryText {
                    detailRow(secondaryLabel, secondaryText)
                }
                if let lastSyncedAt = resource.lastSyncedAt {
                    detailRow("Last Sync", AppDatabase.string(from: lastSyncedAt))
                }
            }

            if resource.kind == .billing {
                Text("Billing data comes from cloud API fields and may lag behind the provider console.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var iconName: String {
        switch resource.kind {
        case .instance:
            "server.rack"
        case .securityGroup:
            "lock.shield"
        case .disk:
            "internaldrive"
        case .snapshot:
            "camera.filters"
        case .billing:
            "creditcard"
        }
    }

    private var primaryLabel: String {
        switch resource.kind {
        case .instance:
            "Address"
        case .disk, .snapshot:
            "Attached To"
        case .billing:
            "Billing Type"
        case .securityGroup:
            "Address"
        }
    }

    private var secondaryLabel: String {
        switch resource.kind {
        case .disk:
            "Disk"
        case .snapshot:
            "Size"
        case .billing:
            "Expire At"
        default:
            "Details"
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct CloudImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = CloudImportViewModel()

    let onImported: (ServerProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cloud Instances")
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 22)

            HSplitView {
                Form {
                    Section("Tencent Cloud Account") {
                        Picker("Account", selection: $viewModel.selectedAccountId) {
                            Text("Select an account").tag(Optional<UUID>.none)
                            ForEach(appState.cloudProviderAccounts) { account in
                                Text(account.displayName).tag(Optional(account.id))
                            }
                        }

                        TextField("Display Name", text: $viewModel.accountDisplayName)
                        TextField("SecretId", text: $viewModel.secretId)
                        SecureField("SecretKey", text: $viewModel.secretKey)

                        HStack {
                            Button {
                                Task {
                                    await viewModel.addTencentAccount(appState: appState)
                                }
                            } label: {
                                Label("Add & Verify", systemImage: "checkmark.shield")
                            }
                            .disabled(!viewModel.canAddAccount)

                            Button {
                                Task {
                                    await viewModel.loadRegions(appState: appState)
                                }
                            } label: {
                                Label("Load Regions", systemImage: "arrow.clockwise")
                            }
                            .disabled(viewModel.selectedAccountId == nil || viewModel.isWorking)
                        }
                    }

                    Section("Sync") {
                        Picker("Region", selection: $viewModel.selectedRegionId) {
                            Text("Select a region").tag("")
                            ForEach(viewModel.regions) { region in
                                Text(region.displayName).tag(region.id)
                            }
                        }

                        Button {
                            Task {
                                await viewModel.syncInstances(appState: appState)
                            }
                        } label: {
                            Label("Sync Instances", systemImage: "icloud.and.arrow.down")
                        }
                        .disabled(!viewModel.canSync)
                    }

                    Section("Import SSH Profile") {
                        TextField("Username", text: $viewModel.importUsername)

                        Picker("Auth Type", selection: $viewModel.authType) {
                            ForEach(SSHAuthType.allCases) { authType in
                                Text(authType.displayName).tag(authType)
                            }
                        }

                        if viewModel.authType == .password {
                            SecureField("Password", text: $viewModel.password)
                        } else {
                            HStack {
                                Text(viewModel.privateKeyFileName.isEmpty ? "No private key selected" : viewModel.privateKeyFileName)
                                    .foregroundStyle(viewModel.privateKeyFileName.isEmpty ? .secondary : .primary)
                                Spacer()
                                Button {
                                    viewModel.choosePrivateKey()
                                } label: {
                                    Label("Choose", systemImage: "key")
                                }
                            }
                            SecureField("Passphrase", text: $viewModel.passphrase)
                        }

                        Button {
                            importSelected()
                        } label: {
                            Label("Import as Server", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canImport)
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 360, idealWidth: 430)

                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.instances.isEmpty {
                        ContentUnavailableView(
                            "No Instances",
                            systemImage: "cloud",
                            description: Text("Add an account, load regions, then sync CVM instances.")
                        )
                    } else {
                        List(viewModel.instances, selection: $viewModel.selectedInstanceId) { instance in
                            CloudInstanceRow(link: instance)
                                .tag(instance.id)
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(minWidth: 360, idealWidth: 460)
            }
            .padding(.horizontal, 12)

            Divider()

            HStack {
                if viewModel.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding(16)
        }
        .frame(width: 900, height: 660)
        .onAppear {
            appState.reloadServers()
            viewModel.selectDefaultAccount(from: appState.cloudProviderAccounts)
        }
        .onChange(of: viewModel.selectedAccountId) {
            Task {
                await viewModel.loadRegions(appState: appState)
            }
        }
    }

    private func importSelected() {
        do {
            let profile = try viewModel.importSelectedInstance(appState: appState)
            onImported(profile)
            dismiss()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

private struct CloudInstanceRow: View {
    let link: CloudInstanceLink

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(link.displayName ?? link.instanceId)
                    .font(.headline)
                Spacer()
                if let status = link.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(link.publicIp ?? link.privateIp ?? "No IP address")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label(link.regionId, systemImage: "mappin.and.ellipse")
                if let instanceType = link.instanceType {
                    Label(instanceType, systemImage: "cpu")
                }
                if link.serverId != nil {
                    Label("Linked", systemImage: "link")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }
}

private struct ServerRowView: View {
    let profile: ServerProfile
    let cloudLink: CloudInstanceLink?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                Spacer()
                Text(cloudLink?.providerId.displayName ?? profile.authType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(profile.endpoint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let cloudLink {
                HStack(spacing: 8) {
                    Label(cloudLink.regionId, systemImage: "cloud")
                    if let status = cloudLink.status {
                        Label(status, systemImage: "circle.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            if let groupName = profile.groupName {
                Text(groupName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ServerSummaryPanel: View {
    let profile: ServerProfile
    let cloudLink: CloudInstanceLink?
    let open: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(.title2.weight(.semibold))
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
                    Text("User").foregroundStyle(.secondary)
                    Text(profile.username)
                }
                GridRow {
                    Text("Auth").foregroundStyle(.secondary)
                    Text(profile.authType.displayName)
                }
                if let groupName = profile.groupName {
                    GridRow {
                        Text("Group").foregroundStyle(.secondary)
                        Text(groupName)
                    }
                }
                if let cloudLink {
                    GridRow {
                        Text("Source").foregroundStyle(.secondary)
                        Text(cloudLink.providerId.displayName)
                    }
                    GridRow {
                        Text("Region").foregroundStyle(.secondary)
                        Text(cloudLink.regionId)
                    }
                    if let status = cloudLink.status {
                        GridRow {
                            Text("Cloud Status").foregroundStyle(.secondary)
                            Text(status)
                        }
                    }
                    GridRow {
                        Text("Instance").foregroundStyle(.secondary)
                        Text(cloudLink.instanceId)
                    }
                }
            }

            HStack {
                Button(action: open) {
                    Label("Open", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)

                Button(action: edit) {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
