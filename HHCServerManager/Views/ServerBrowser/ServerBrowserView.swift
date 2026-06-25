import SwiftUI

struct ServerBrowserView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ServerBrowserViewModel()
    @State private var showingAddServer = false
    @State private var serverPendingDeletion: ServerProfile?

    var body: some View {
        NavigationSplitView {
            List(selection: .constant("all")) {
                Label("All Servers", systemImage: "server.rack")
                    .tag("all")
                Label("Favorites", systemImage: "star")
                    .tag("favorites")
                Label("Recently Used", systemImage: "clock")
                    .tag("recent")
                Label("Manual SSH", systemImage: "terminal")
                    .tag("manual")
                Label("Cloud", systemImage: "cloud")
                    .tag("cloud")
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
                showingAddServer = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private var serverList: some View {
        let servers = viewModel.filteredServers(from: appState.servers)
        return Group {
            if servers.isEmpty {
                ContentUnavailableView(
                    "No Servers",
                    systemImage: "server.rack",
                    description: Text("Add a server to start the SSH workflow.")
                )
            } else {
                List(servers, selection: $viewModel.selectedServerId) { profile in
                    ServerRowView(profile: profile)
                        .tag(profile.id)
                        .contextMenu {
                            Button("Open") {
                                appState.openWorkspace(for: profile)
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
                    open: {
                        appState.openWorkspace(for: profile)
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

private struct ServerRowView: View {
    let profile: ServerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                Spacer()
                Text(profile.authType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(profile.endpoint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
    let open: () -> Void
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
            }

            HStack {
                Button(action: open) {
                    Label("Open", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)

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
