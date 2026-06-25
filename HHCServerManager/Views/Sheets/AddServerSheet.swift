import SwiftUI

struct AddServerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = AddServerViewModel()

    let onSaved: (ServerProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Server")
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 22)

            Form {
                Section("Server") {
                    TextField("Name", text: $viewModel.name)
                    TextField("Host", text: $viewModel.host)
                    TextField("Port", text: $viewModel.port)
                    TextField("Username", text: $viewModel.username)
                    TextField("Group", text: $viewModel.groupName)
                }

                Section("Authentication") {
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
    }

    private func save() {
        do {
            let profile = try viewModel.save(using: appState.serverManagementService)
            onSaved(profile)
            dismiss()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
