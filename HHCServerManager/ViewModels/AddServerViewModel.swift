import AppKit
import Foundation

@MainActor
final class AddServerViewModel: ObservableObject {
    @Published var name = ""
    @Published var host = ""
    @Published var port = "22"
    @Published var username = "root"
    @Published var groupName = ""
    @Published var authType: SSHAuthType = .privateKey
    @Published var password = ""
    @Published var privateKeyData: Data?
    @Published var privateKeyFileName = ""
    @Published var passphrase = ""
    @Published var errorMessage: String?
    @Published var isSaving = false
    private var editingProfile: ServerProfile?

    var canSave: Bool {
        validationError == nil
    }

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name is required."
        }
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Host is required."
        }
        guard let portValue = Int(port), (1...65535).contains(portValue) else {
            return "Port must be between 1 and 65535."
        }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Username is required."
        }
        switch authType {
        case .password:
            if password.isEmpty && editingProfile?.authType != .password {
                return "Password is required."
            }
        case .privateKey:
            if privateKeyData == nil && editingProfile?.authType != .privateKey {
                return "Private key is required."
            }
        }
        return nil
    }

    var isEditing: Bool {
        editingProfile != nil
    }

    func configureForEditing(_ profile: ServerProfile) {
        editingProfile = profile
        name = profile.name
        host = profile.host
        port = "\(profile.port)"
        username = profile.username
        groupName = profile.groupName ?? ""
        authType = profile.authType
        password = ""
        privateKeyData = nil
        privateKeyFileName = profile.authType == .privateKey ? "Existing private key" : ""
        passphrase = ""
    }

    func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.title = "Choose SSH Private Key"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                privateKeyData = try Data(contentsOf: url)
                privateKeyFileName = url.lastPathComponent
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func save(using service: ServerManagementService) throws -> ServerProfile {
        if let validationError {
            throw AddServerError.validation(validationError)
        }
        isSaving = true
        defer { isSaving = false }

        let portValue = Int(port) ?? 22
        if let editingProfile {
            let update: CredentialUpdate
            switch authType {
            case .password:
                update = password.isEmpty ? .keepExisting : .replace(.password(password))
            case .privateKey:
                if let privateKeyData {
                    update = .replace(.privateKey(data: privateKeyData, passphrase: passphrase.nilIfBlank))
                } else {
                    update = .keepExisting
                }
            }
            return try service.updateServer(
                editingProfile,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: portValue,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                groupName: groupName,
                authType: authType,
                credentialUpdate: update
            )
        }

        let credential: CredentialInput
        switch authType {
        case .password:
            credential = .password(password)
        case .privateKey:
            credential = .privateKey(data: privateKeyData ?? Data(), passphrase: passphrase.nilIfBlank)
        }

        return try service.createServer(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portValue,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            groupName: groupName,
            authType: authType,
            credential: credential
        )
    }
}

enum AddServerError: LocalizedError {
    case validation(String)

    var errorDescription: String? {
        switch self {
        case let .validation(message):
            message
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
