import Foundation

enum SSHClientError: LocalizedError {
    case unknownHostKey(HostKeyInfo)
    case hostKeyChanged(current: HostKeyInfo, trusted: TrustedHostKey)
    case missingPrivateKey
    case passwordAuthNeedsNativeClient
    case processFailed(String)
    case invalidHostKeyScan

    var errorDescription: String? {
        switch self {
        case .unknownHostKey:
            "This server host key is not trusted yet."
        case let .hostKeyChanged(current, trusted):
            "Host key changed. Trusted \(trusted.fingerprintSHA256), current \(current.fingerprintSHA256)."
        case .missingPrivateKey:
            "Private key data was not found in Keychain."
        case .passwordAuthNeedsNativeClient:
            "Password authentication is not available in the bootstrap OpenSSH adapter yet. Use a private key for this first slice."
        case let .processFailed(message):
            message
        case .invalidHostKeyScan:
            "Could not read a valid host key from ssh-keyscan."
        }
    }
}

final class OpenSSHClient: @unchecked Sendable {
    private let repository: ServerRepository
    private let keychain: KeychainService
    private let fileManager: FileManager

    init(repository: ServerRepository, keychain: KeychainService, fileManager: FileManager = .default) {
        self.repository = repository
        self.keychain = keychain
        self.fileManager = fileManager
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        try await ensureHostKeyTrusted(profile: profile)
        try rebuildKnownHostsFile()
        let knownHostsURL = try knownHostsURL()

        var temporaryKeyURL: URL?
        if profile.authType == .privateKey {
            guard let keyData = try keychain.readPrivateKey(keychainRef: profile.keychainRef) else {
                throw SSHClientError.missingPrivateKey
            }
            temporaryKeyURL = try materializePrivateKey(keyData, serverId: profile.id)
        } else {
            throw SSHClientError.passwordAuthNeedsNativeClient
        }
        defer {
            if let temporaryKeyURL {
                try? fileManager.removeItem(at: temporaryKeyURL)
            }
        }

        let start = Date()
        var arguments = [
            "-p", "\(profile.port)",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(knownHostsURL.path)",
        ]
        if let temporaryKeyURL {
            arguments.append(contentsOf: ["-i", temporaryKeyURL.path])
        }
        arguments.append("\(profile.username)@\(profile.host)")
        arguments.append(command)

        let processResult = try await runProcess("/usr/bin/ssh", arguments: arguments)
        return CommandResult(
            command: command,
            stdout: processResult.stdout,
            stderr: processResult.stderr,
            exitCode: processResult.exitCode,
            duration: Date().timeIntervalSince(start)
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {
        let trusted = TrustedHostKey(
            id: UUID(),
            serverId: profile.id,
            host: hostKeyInfo.host,
            port: hostKeyInfo.port,
            algorithm: hostKeyInfo.algorithm,
            fingerprintSHA256: hostKeyInfo.fingerprintSHA256,
            rawPublicKey: hostKeyInfo.rawPublicKey,
            trustedAt: Date()
        )
        try repository.saveTrustedHostKey(trusted)
        try rebuildKnownHostsFile()
    }

    private func ensureHostKeyTrusted(profile: ServerProfile) async throws {
        let current = try await scanHostKey(profile: profile)
        let trustedKeys = try repository.fetchTrustedHostKeys(serverId: profile.id)
        if trustedKeys.contains(where: { $0.fingerprintSHA256 == current.fingerprintSHA256 }) {
            return
        }
        if let sameAlgorithm = trustedKeys.first(where: { $0.algorithm == current.algorithm }) {
            throw SSHClientError.hostKeyChanged(current: current, trusted: sameAlgorithm)
        }
        throw SSHClientError.unknownHostKey(current)
    }

    private func scanHostKey(profile: ServerProfile) async throws -> HostKeyInfo {
        let result = try await runProcess("/usr/bin/ssh-keyscan", arguments: [
            "-T", "5",
            "-p", "\(profile.port)",
            profile.host,
        ])
        let lines = result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let rawPublicKey = lines.first(where: { $0.contains(" ssh-ed25519 ") }) ?? lines.first else {
            throw SSHClientError.invalidHostKeyScan
        }
        let parts = rawPublicKey.split(separator: " ").map(String.init)
        guard parts.count >= 3 else {
            throw SSHClientError.invalidHostKeyScan
        }
        let algorithm = parts[1]
        let fingerprint = try await fingerprint(forKnownHostsLine: rawPublicKey)
        return HostKeyInfo(
            host: profile.host,
            port: profile.port,
            algorithm: algorithm,
            fingerprintSHA256: fingerprint,
            rawPublicKey: rawPublicKey
        )
    }

    private func fingerprint(forKnownHostsLine rawPublicKey: String) async throws -> String {
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("hhc-hostkey-\(UUID().uuidString)")
        try rawPublicKey.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: tempURL) }

        let result = try await runProcess("/usr/bin/ssh-keygen", arguments: ["-l", "-f", tempURL.path])
        guard let fingerprint = result.stdout.split(separator: " ").map(String.init).dropFirst().first else {
            throw SSHClientError.invalidHostKeyScan
        }
        return fingerprint
    }

    private func rebuildKnownHostsFile() throws {
        let keys = try repository.fetchAllTrustedHostKeys()
        let body = keys.map(\.rawPublicKey).joined(separator: "\n") + (keys.isEmpty ? "" : "\n")
        let appSupportURL = try appSupportURL()
        let knownHostsURL = try knownHostsURL()
        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try body.write(to: knownHostsURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: knownHostsURL.path)
    }

    private func materializePrivateKey(_ data: Data, serverId: UUID) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("hhc-ssh-\(serverId.uuidString)-\(UUID().uuidString)")
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private func appSupportURL() throws -> URL {
        let supportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportURL.appendingPathComponent("HHCServerManager", isDirectory: true)
    }

    private func knownHostsURL() throws -> URL {
        try appSupportURL().appendingPathComponent("known_hosts")
    }

    private func runProcess(_ executable: String, arguments: [String]) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                throw SSHClientError.processFailed(error.localizedDescription)
            }
            process.waitUntilExit()

            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ProcessResult(
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus
            )
        }.value
    }
}

private struct ProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}
