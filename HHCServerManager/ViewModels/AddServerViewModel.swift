import AppKit
import Foundation

@MainActor
final class AddServerViewModel: ObservableObject {
    @Published var name = ""
    @Published var host = ""
    @Published var port = "22"
    @Published var username = "root"
    @Published var groupName = ""
    @Published var serverKind: ServerKind = .manualSSH
    @Published var authType: SSHAuthType = .privateKey
    @Published var password = ""
    @Published var privateKeyData: Data?
    @Published var privateKeyFileName = ""
    @Published var passphrase = ""
    @Published var knownHostsFileName = ""
    @Published var knownHostsImportResult: KnownHostsImportResult?
    @Published var errorMessage: String?
    @Published var isSaving = false
    private var editingProfile: ServerProfile?
    private var knownHostsContent: String?

    var canSave: Bool {
        validationError == nil
    }

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Name is required.")
        }
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Host is required.")
        }
        guard let portValue = Int(port), (1...65535).contains(portValue) else {
            return L10n.string("Port must be between 1 and 65535.")
        }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Username is required.")
        }
        switch authType {
        case .password:
            if password.isEmpty && editingProfile?.authType != .password {
                return L10n.string("Password is required.")
            }
        case .privateKey:
            if privateKeyData == nil && editingProfile?.authType != .privateKey {
                return L10n.string("Private key is required.")
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
        serverKind = profile.serverKind
        authType = profile.authType
        password = ""
        privateKeyData = nil
        privateKeyFileName = profile.authType == .privateKey ? L10n.string("Existing private key") : ""
        passphrase = ""
        knownHostsFileName = ""
        knownHostsImportResult = nil
        knownHostsContent = nil
    }

    func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose SSH Private Key")
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

    func chooseKnownHostsFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Choose known_hosts File")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try selectKnownHostsFile(url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectKnownHostsFile(_ url: URL) throws {
        knownHostsContent = try String(contentsOf: url, encoding: .utf8)
        knownHostsFileName = url.lastPathComponent
        knownHostsImportResult = nil
    }

    func clearKnownHostsFile() {
        knownHostsContent = nil
        knownHostsFileName = ""
        knownHostsImportResult = nil
    }

    func save(
        using service: ServerManagementService,
        hostKeyTrustStore: HostKeyTrustStore? = nil
    ) throws -> ServerProfile {
        if let validationError {
            throw AddServerError.validation(validationError)
        }
        isSaving = true
        defer { isSaving = false }

        let portValue = Int(port) ?? 22
        let savedProfile: ServerProfile
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
            savedProfile = try service.updateServer(
                editingProfile,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: portValue,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                groupName: groupName,
                authType: authType,
                serverKind: serverKind,
                credentialUpdate: update
            )
        } else {
            let credential: CredentialInput
            switch authType {
            case .password:
                credential = .password(password)
            case .privateKey:
                credential = .privateKey(data: privateKeyData ?? Data(), passphrase: passphrase.nilIfBlank)
            }

            savedProfile = try service.createServer(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: portValue,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                groupName: groupName,
                authType: authType,
                serverKind: serverKind,
                credential: credential
            )
        }

        if let knownHostsContent, let hostKeyTrustStore {
            knownHostsImportResult = try hostKeyTrustStore.importKnownHosts(knownHostsContent, for: savedProfile)
        }
        return savedProfile
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
