import SwiftUI

struct AddServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = AddServerViewModel()

    let profile: ServerProfile?
    let onSaved: (ServerProfile) -> Void

    init(profile: ServerProfile? = nil, onSaved: @escaping (ServerProfile) -> Void) {
        self.profile = profile
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(profile == nil ? L10n.string("Add Server") : L10n.string("Edit Server"))
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 22)

            Form {
                Section("Server") {
                    TextField("Name", text: $viewModel.name)
                    TextField("Host", text: $viewModel.host)
                    TextField("Port", text: $viewModel.port)
                    TextField("Username", text: $viewModel.username)
                    TextField("Group", text: $viewModel.groupName)
                    Picker("Type", selection: $viewModel.serverKind) {
                        ForEach(ServerKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                }

                Section("Authentication") {
                    Picker("Auth Type", selection: $viewModel.authType) {
                        ForEach(SSHAuthType.allCases) { authType in
                            Text(authType.displayName).tag(authType)
                        }
                    }

                    if viewModel.authType == .password {
                        SecureField(profile == nil ? "Password" : "New Password", text: $viewModel.password)
                    } else {
                        HStack {
                            Text(viewModel.privateKeyFileName.isEmpty ? L10n.string("No private key selected") : viewModel.privateKeyFileName)
                                .foregroundStyle(viewModel.privateKeyFileName.isEmpty ? .secondary : .primary)
                            Spacer()
                            Button {
                                viewModel.choosePrivateKey()
                            } label: {
                                Label("Choose", systemImage: "key")
                            }
                        }
                        SecureField(profile == nil ? "Passphrase" : "New Passphrase", text: $viewModel.passphrase)
                    }
                }

                Section("Host Key Trust") {
                    HStack {
                        Text(viewModel.knownHostsFileName.isEmpty ? L10n.string("No known_hosts file selected") : viewModel.knownHostsFileName)
                            .foregroundStyle(viewModel.knownHostsFileName.isEmpty ? .secondary : .primary)
                        Spacer()
                        if !viewModel.knownHostsFileName.isEmpty {
                            Button {
                                viewModel.clearKnownHostsFile()
                            } label: {
                                Label("Clear", systemImage: "xmark.circle")
                            }
                        }
                        Button {
                            viewModel.chooseKnownHostsFile()
                        } label: {
                            Label("Import", systemImage: "checkmark.shield")
                        }
                    }
                }

                if let validationError = viewModel.validationError {
                    Text(validationError)
                        .foregroundStyle(.red)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 12)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSave || viewModel.isSaving)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
        .onAppear {
            if let profile {
                viewModel.configureForEditing(profile)
            }
        }
    }

    private func save() {
        do {
            let profile = try viewModel.save(
                using: appState.serverManagementService,
                hostKeyTrustStore: HostKeyTrustStore(repository: appState.repository)
            )
            onSaved(profile)
            dismiss()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
