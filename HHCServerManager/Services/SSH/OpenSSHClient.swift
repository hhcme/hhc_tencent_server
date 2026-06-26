import Foundation

enum SSHClientError: LocalizedError, Equatable {
    case unknownHostKey(HostKeyInfo)
    case hostKeyChanged(current: HostKeyInfo, trusted: TrustedHostKey)
    case missingPrivateKey
    case missingPassword
    case processFailed(String)
    case invalidHostKeyScan
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unknownHostKey:
            L10n.string("This server host key is not trusted yet.")
        case let .hostKeyChanged(current, trusted):
            L10n.format("Host key changed. Trusted %@, current %@.", trusted.fingerprintSHA256, current.fingerprintSHA256)
        case .missingPrivateKey:
            L10n.string("Private key data was not found in Keychain.")
        case .missingPassword:
            L10n.string("Password was not found in Keychain.")
        case let .processFailed(message):
            message
        case .invalidHostKeyScan:
            L10n.string("Could not read a valid host key from ssh-keyscan.")
        case .cancelled:
            L10n.string("Command was cancelled.")
        }
    }
}

final class OpenSSHClient: SSHClient, RemoteFileTransferClient, @unchecked Sendable {
    private let repository: ServerRepository
    private let keychain: KeychainService
    private let hostKeyTrustStore: HostKeyTrustStore
    private let fileManager: FileManager
    private let isRsyncEnabled: Bool
    private let isSCPFallbackEnabled: Bool

    init(
        repository: ServerRepository,
        keychain: KeychainService,
        hostKeyTrustStore: HostKeyTrustStore? = nil,
        fileManager: FileManager = .default,
        isRsyncEnabled: Bool = true,
        isSCPFallbackEnabled: Bool = true
    ) {
        self.repository = repository
        self.keychain = keychain
        self.hostKeyTrustStore = hostKeyTrustStore ?? HostKeyTrustStore(repository: repository)
        self.fileManager = fileManager
        self.isRsyncEnabled = isRsyncEnabled
        self.isSCPFallbackEnabled = isSCPFallbackEnabled
    }

    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult {
        try await execute("printf hhc-ssh-ok", profile: profile)
    }

    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult {
        try await ensureHostKeyTrusted(profile: profile)
        try rebuildKnownHostsFile()
        let knownHostsURL = try knownHostsURL()

        let authContext = try makeAuthContext(profile: profile, knownHostsURL: knownHostsURL, portFlag: "-p")
        defer {
            authContext.cleanup()
        }
        var arguments = authContext.arguments
        arguments.append("\(profile.username)@\(profile.host)")
        arguments.append(command)

        let start = Date()
        let processResult = try await runProcess("/usr/bin/ssh", arguments: arguments, environment: authContext.environment)
        return CommandResult(
            command: command,
            stdout: processResult.stdout,
            stderr: processResult.stderr,
            exitCode: processResult.exitCode,
            duration: Date().timeIntervalSince(start)
        )
    }

    func uploadFile(
        localURL: URL,
        remotePath: String,
        profile: ServerProfile,
        progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?
    ) async throws -> RemoteFileTransferResult {
        try await transferFile(
            direction: .upload,
            source: localURL.path,
            remoteSourceOrDestination: "\(profile.username)@\(profile.host):\(remotePath)",
            remotePath: remotePath,
            localURL: localURL,
            profile: profile,
            progressHandler: progressHandler
        )
    }

    func downloadFile(
        remotePath: String,
        localURL: URL,
        profile: ServerProfile,
        progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?
    ) async throws -> RemoteFileTransferResult {
        try await transferFile(
            direction: .download,
            source: localURL.path,
            remoteSourceOrDestination: "\(profile.username)@\(profile.host):\(remotePath)",
            remotePath: remotePath,
            localURL: localURL,
            profile: profile,
            progressHandler: progressHandler
        )
    }

    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {
        try hostKeyTrustStore.trust(hostKeyInfo, for: profile)
        try rebuildKnownHostsFile()
    }

    private func transferFile(
        direction: RemoteFileTransferDirection,
        source: String,
        remoteSourceOrDestination: String,
        remotePath: String,
        localURL: URL,
        profile: ServerProfile,
        progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?
    ) async throws -> RemoteFileTransferResult {
        try await ensureHostKeyTrusted(profile: profile)
        try rebuildKnownHostsFile()
        let knownHostsURL = try knownHostsURL()
        let authContext = try makeAuthContext(profile: profile, knownHostsURL: knownHostsURL, portFlag: "-P")
        defer {
            authContext.cleanup()
        }

        let start = Date()
        let initialByteCount = (try? fileManager.attributesOfItem(atPath: localURL.path)[.size]) as? Int64
        progressHandler?(RemoteFileTransferProgress(completedBytes: 0, totalBytes: initialByteCount, fraction: 0))

        if let result = try await transferFileWithRsyncIfAvailable(
            direction: direction,
            source: source,
            remoteSourceOrDestination: remoteSourceOrDestination,
            remotePath: remotePath,
            localURL: localURL,
            profile: profile,
            knownHostsURL: knownHostsURL,
            progressHandler: progressHandler,
            start: start
        ) {
            return result
        }

        if let result = try await transferFileWithSFTPIfAvailable(
            direction: direction,
            remotePath: remotePath,
            localURL: localURL,
            profile: profile,
            knownHostsURL: knownHostsURL,
            progressHandler: progressHandler,
            start: start,
            initialByteCount: initialByteCount
        ) {
            return result
        }

        guard isSCPFallbackEnabled else {
            throw SSHClientError.processFailed("SFTP transfer failed and SCP fallback is disabled.")
        }

        let scpSource: String
        let scpDestination: String
        switch direction {
        case .upload:
            scpSource = source
            scpDestination = remoteSourceOrDestination
        case .download:
            scpSource = remoteSourceOrDestination
            scpDestination = source
        }
        var arguments = authContext.arguments
        arguments.append(contentsOf: [scpSource, scpDestination])
        let processResult = try await runProcess("/usr/bin/scp", arguments: arguments, environment: authContext.environment)
        guard processResult.exitCode == 0 else {
            let message = processResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHClientError.processFailed(message.isEmpty ? "File transfer failed." : message)
        }

        let byteCount = (try? fileManager.attributesOfItem(atPath: localURL.path)[.size]) as? Int64
        progressHandler?(RemoteFileTransferProgress(completedBytes: byteCount, totalBytes: byteCount ?? initialByteCount, fraction: 1))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: byteCount,
            duration: Date().timeIntervalSince(start),
            backend: .scp,
            supportsResume: false,
            supportsStreamingProgress: false
        )
    }

    private func transferFileWithSFTPIfAvailable(
        direction: RemoteFileTransferDirection,
        remotePath: String,
        localURL: URL,
        profile: ServerProfile,
        knownHostsURL: URL,
        progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?,
        start: Date,
        initialByteCount: Int64?
    ) async throws -> RemoteFileTransferResult? {
        guard fileManager.isExecutableFile(atPath: "/usr/bin/sftp") else {
            return nil
        }
        let authContext = try makeAuthContext(profile: profile, knownHostsURL: knownHostsURL, portFlag: "-P")
        let batchURL = fileManager.temporaryDirectory
            .appendingPathComponent("hhc-sftp-\(profile.id.uuidString)-\(UUID().uuidString).batch")
        var cleanupURLs = authContext.temporaryURLs
        cleanupURLs.append(batchURL)
        defer {
            SSHProcessAuthContext(
                arguments: authContext.arguments,
                environment: authContext.environment,
                temporaryURLs: cleanupURLs,
                fileManager: fileManager
            )
            .cleanup()
        }

        let shouldResume = try await shouldResumeSFTPTransfer(
            direction: direction,
            remotePath: remotePath,
            localPath: localURL.path,
            profile: profile,
            knownHostsURL: knownHostsURL
        )
        let batchCommand = Self.sftpBatchCommand(
            direction: direction,
            localPath: localURL.path,
            remotePath: remotePath,
            resume: shouldResume
        )
        try batchCommand.write(to: batchURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: batchURL.path)

        var arguments = authContext.arguments
        arguments.append(contentsOf: ["-b", batchURL.path, "\(profile.username)@\(profile.host)"])
        let processResult = try await runProcess("/usr/bin/sftp", arguments: arguments, environment: authContext.environment)
        guard processResult.exitCode == 0 else {
            if !isSCPFallbackEnabled {
                let message = processResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SSHClientError.processFailed(message.isEmpty ? "SFTP transfer failed." : message)
            }
            return nil
        }

        let byteCount = (try? fileManager.attributesOfItem(atPath: localURL.path)[.size]) as? Int64
        progressHandler?(RemoteFileTransferProgress(completedBytes: byteCount, totalBytes: byteCount ?? initialByteCount, fraction: 1))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: byteCount,
            duration: Date().timeIntervalSince(start),
            backend: .openSSHSFTP,
            supportsResume: true,
            supportsStreamingProgress: false
        )
    }

    private func transferFileWithRsyncIfAvailable(
        direction: RemoteFileTransferDirection,
        source: String,
        remoteSourceOrDestination: String,
        remotePath: String,
        localURL: URL,
        profile: ServerProfile,
        knownHostsURL: URL,
        progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?,
        start: Date
    ) async throws -> RemoteFileTransferResult? {
        guard isRsyncEnabled, fileManager.isExecutableFile(atPath: "/usr/bin/rsync") else {
            return nil
        }
        let authContext = try makeAuthContext(profile: profile, knownHostsURL: knownHostsURL, portFlag: "-p")
        defer {
            authContext.cleanup()
        }

        let rsyncSource: String
        let rsyncDestination: String
        switch direction {
        case .upload:
            rsyncSource = source
            rsyncDestination = remoteSourceOrDestination
        case .download:
            rsyncSource = remoteSourceOrDestination
            rsyncDestination = source
        }

        let sshCommand = (["ssh"] + authContext.arguments.map(Self.shellQuote)).joined(separator: " ")
        let arguments = Self.rsyncTransferArguments(
            source: rsyncSource,
            destination: rsyncDestination,
            sshCommand: sshCommand
        )
        let processResult = try await runProcessStreaming(
            "/usr/bin/rsync",
            arguments: arguments,
            environment: authContext.environment
        ) { chunk in
            for progress in Self.rsyncProgressUpdates(from: chunk) {
                progressHandler?(progress)
            }
        }

        guard processResult.exitCode == 0 else {
            return nil
        }

        let byteCount = (try? fileManager.attributesOfItem(atPath: localURL.path)[.size]) as? Int64
        progressHandler?(RemoteFileTransferProgress(completedBytes: byteCount, totalBytes: byteCount, fraction: 1))
        return RemoteFileTransferResult(
            remotePath: remotePath,
            localPath: localURL.path,
            byteCount: byteCount,
            duration: Date().timeIntervalSince(start),
            backend: .rsync,
            supportsResume: true,
            supportsStreamingProgress: true
        )
    }

    func makeAuthContext(profile: ServerProfile, knownHostsURL: URL, portFlag: String) throws -> SSHProcessAuthContext {
        var temporaryKeyURL: URL?
        var temporaryAskpassURL: URL?
        var environment: [String: String] = [:]
        var arguments = [
            portFlag, "\(profile.port)",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=\(Self.sshConfigValue(knownHostsURL.path))",
        ]

        switch profile.authType {
        case .privateKey:
            guard let keyData = try keychain.readPrivateKey(keychainRef: profile.keychainRef) else {
                throw SSHClientError.missingPrivateKey
            }
            let passphrase = try keychain.readPrivateKeyPassphrase(keychainRef: profile.keychainRef)
            temporaryKeyURL = try materializePrivateKey(keyData, serverId: profile.id)
            if let passphrase, !passphrase.isEmpty {
                temporaryAskpassURL = try materializeAskpassScript(serverId: profile.id)
                environment["SSH_ASKPASS"] = temporaryAskpassURL!.path
                environment["SSH_ASKPASS_REQUIRE"] = "force"
                environment["HHC_SSH_PASSWORD"] = passphrase
                environment["DISPLAY"] = environment["DISPLAY"] ?? "localhost:0"
                arguments.append(contentsOf: [
                    "-o", "BatchMode=no",
                    "-o", "PreferredAuthentications=publickey",
                    "-o", "PasswordAuthentication=no",
                    "-o", "KbdInteractiveAuthentication=no",
                    "-o", "IdentitiesOnly=yes",
                    "-i", temporaryKeyURL!.path,
                ])
            } else {
                arguments.append(contentsOf: [
                    "-o", "BatchMode=yes",
                    "-o", "IdentitiesOnly=yes",
                    "-i", temporaryKeyURL!.path,
                ])
            }
        case .password:
            guard let password = try keychain.readPassword(keychainRef: profile.keychainRef) else {
                throw SSHClientError.missingPassword
            }
            temporaryAskpassURL = try materializeAskpassScript(serverId: profile.id)
            environment["SSH_ASKPASS"] = temporaryAskpassURL!.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["HHC_SSH_PASSWORD"] = password
            environment["DISPLAY"] = environment["DISPLAY"] ?? "localhost:0"
            arguments.append(contentsOf: [
                "-o", "BatchMode=no",
                "-o", "NumberOfPasswordPrompts=1",
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
            ])
        }
        return SSHProcessAuthContext(
            arguments: arguments,
            environment: environment,
            temporaryURLs: [temporaryKeyURL, temporaryAskpassURL].compactMap { $0 },
            fileManager: fileManager
        )
    }

    private func ensureHostKeyTrusted(profile: ServerProfile) async throws {
        let current = try await scanHostKey(profile: profile)
        switch try hostKeyTrustStore.evaluate(current, for: profile) {
        case .trusted:
            return
        case .unknown(let hostKeyInfo):
            throw SSHClientError.unknownHostKey(hostKeyInfo)
        case let .changed(current, trusted):
            throw SSHClientError.hostKeyChanged(current: current, trusted: trusted)
        }
    }

    private func scanHostKey(profile: ServerProfile) async throws -> HostKeyInfo {
        for keyType in ["ed25519", "ecdsa", "rsa"] {
            let result = try await runProcess("/usr/bin/ssh-keyscan", arguments: [
                "-T", "5",
                "-t", keyType,
                "-p", "\(profile.port)",
                profile.host,
            ])
            if let hostKeyInfo = try await parseScannedHostKey(result.stdout, profile: profile) {
                return hostKeyInfo
            }
        }
        throw SSHClientError.invalidHostKeyScan
    }

    private func parseScannedHostKey(_ output: String, profile: ServerProfile) async throws -> HostKeyInfo? {
        guard let rawPublicKey = output
            .split(separator: "\n")
            .map(String.init)
            .first(where: { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return nil
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

    private func materializeAskpassScript(serverId: UUID) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("hhc-ssh-askpass-\(serverId.uuidString)-\(UUID().uuidString).sh")
        let body = """
        #!/bin/sh
        printf '%s' "$HHC_SSH_PASSWORD"
        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func sshConfigValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: " ", with: "\\ ")
    }

    static func sftpBatchCommand(
        direction: RemoteFileTransferDirection,
        localPath: String,
        remotePath: String,
        resume: Bool = false
    ) -> String {
        switch direction {
        case .upload:
            "\(resume ? "put -a" : "put") \(sftpBatchQuote(localPath)) \(sftpBatchQuote(remotePath))\n"
        case .download:
            "\(resume ? "get -a" : "get") \(sftpBatchQuote(remotePath)) \(sftpBatchQuote(localPath))\n"
        }
    }

    private static func sftpBatchQuote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    static func rsyncTransferArguments(source: String, destination: String, sshCommand: String) -> [String] {
        [
            "--partial",
            "--append-verify",
            "--progress",
            "-e", sshCommand,
            source,
            destination,
        ]
    }

    private func shouldResumeSFTPTransfer(
        direction: RemoteFileTransferDirection,
        remotePath: String,
        localPath: String,
        profile: ServerProfile,
        knownHostsURL: URL
    ) async throws -> Bool {
        switch direction {
        case .upload:
            guard let localSize = (try? fileManager.attributesOfItem(atPath: localPath)[.size]) as? Int64 else {
                return false
            }
            guard let remoteSize = try await remoteFileByteCount(
                remotePath,
                profile: profile,
                knownHostsURL: knownHostsURL
            ) else {
                return false
            }
            return Self.shouldResumeSFTPTransfer(partialByteCount: remoteSize, totalByteCount: localSize)
        case .download:
            guard let localSize = (try? fileManager.attributesOfItem(atPath: localPath)[.size]) as? Int64 else {
                return false
            }
            guard let remoteSize = try await remoteFileByteCount(
                remotePath,
                profile: profile,
                knownHostsURL: knownHostsURL
            ) else {
                return false
            }
            return Self.shouldResumeSFTPTransfer(partialByteCount: localSize, totalByteCount: remoteSize)
        }
    }

    private func remoteFileByteCount(
        _ remotePath: String,
        profile: ServerProfile,
        knownHostsURL: URL
    ) async throws -> Int64? {
        let authContext = try makeAuthContext(profile: profile, knownHostsURL: knownHostsURL, portFlag: "-p")
        defer {
            authContext.cleanup()
        }
        var arguments = authContext.arguments
        arguments.append("\(profile.username)@\(profile.host)")
        arguments.append("if [ -f -- \(Self.shellQuote(remotePath)) ]; then wc -c < \(Self.shellQuote(remotePath)); else exit 1; fi")
        let result = try await runProcess("/usr/bin/ssh", arguments: arguments, environment: authContext.environment)
        guard result.exitCode == 0 else {
            return nil
        }
        return Self.parseRemoteByteCount(result.stdout)
    }

    static func shouldResumeSFTPTransfer(partialByteCount: Int64, totalByteCount: Int64) -> Bool {
        partialByteCount > 0 && partialByteCount < totalByteCount
    }

    static func parseRemoteByteCount(_ output: String) -> Int64? {
        output
            .split(whereSeparator: \.isWhitespace)
            .first
            .flatMap { Int64(String($0)) }
    }

    static func rsyncProgressUpdates(from output: String) -> [RemoteFileTransferProgress] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { rsyncProgressUpdate(fromLine: String($0)) }
    }

    static func rsyncProgressUpdate(fromLine line: String) -> RemoteFileTransferProgress? {
        let columns = line
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .last?
            .split(whereSeparator: \.isWhitespace)
            .map(String.init) ?? []
        guard columns.count >= 2 else {
            return nil
        }
        let completedText = columns[0].filter { $0.isNumber }
        let percentText = columns[1].replacingOccurrences(of: "%", with: "")
        guard
            let completedBytes = Int64(completedText),
            let percent = Double(percentText)
        else {
            return nil
        }
        let fraction = percent / 100
        let totalBytes = fraction > 0 ? Int64((Double(completedBytes) / fraction).rounded()) : nil
        let transferRate = columns.count >= 3 ? parseRsyncTransferRate(columns[2]) : nil
        let eta = columns.count >= 4 ? parseRsyncETA(columns[3]) : nil
        return RemoteFileTransferProgress(
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            fraction: fraction,
            transferRateBytesPerSecond: transferRate,
            estimatedSecondsRemaining: eta
        )
    }

    static func parseRsyncTransferRate(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/s", with: "")
        guard !normalized.isEmpty else { return nil }

        let numberText = normalized.prefix { character in
            character.isNumber || character == "."
        }
        guard let number = Double(numberText) else { return nil }
        let unit = normalized.dropFirst(numberText.count).lowercased()
        let multiplier: Double
        switch unit {
        case "", "b":
            multiplier = 1
        case "k", "kb", "kib":
            multiplier = 1_024
        case "m", "mb", "mib":
            multiplier = 1_024 * 1_024
        case "g", "gb", "gib":
            multiplier = 1_024 * 1_024 * 1_024
        case "t", "tb", "tib":
            multiplier = 1_024 * 1_024 * 1_024 * 1_024
        default:
            return nil
        }
        return number * multiplier
    }

    static func parseRsyncETA(_ value: String) -> TimeInterval? {
        let parts = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .compactMap { TimeInterval($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3_600 + parts[1] * 60 + parts[2]
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

    private func runProcess(
        _ executable: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> ProcessResult {
        let processBox = ProcessBox()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()

                let process = Process()
                processBox.set(process)
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if !environment.isEmpty {
                    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
                }

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    throw SSHClientError.processFailed(error.localizedDescription)
                }

                if Task.isCancelled {
                    processBox.terminate()
                    throw SSHClientError.cancelled
                }

                process.waitUntilExit()

                if Task.isCancelled {
                    throw SSHClientError.cancelled
                }

                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                return ProcessResult(
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                )
            }.value
        } onCancel: {
            processBox.terminate()
        }
    }

    private func runProcessStreaming(
        _ executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        outputHandler: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessResult {
        let processBox = ProcessBox()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()

                let process = Process()
                processBox.set(process)
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if !environment.isEmpty {
                    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
                }

                let stdout = Pipe()
                let stderr = Pipe()
                let stdoutBuffer = LockedDataBuffer()
                let stderrBuffer = LockedDataBuffer()
                stdout.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    stdoutBuffer.append(data)
                    if let chunk = String(data: data, encoding: .utf8) {
                        outputHandler(chunk)
                    }
                }
                stderr.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    stderrBuffer.append(data)
                    if let chunk = String(data: data, encoding: .utf8) {
                        outputHandler(chunk)
                    }
                }
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                } catch {
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    throw SSHClientError.processFailed(error.localizedDescription)
                }

                if Task.isCancelled {
                    processBox.terminate()
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    throw SSHClientError.cancelled
                }

                process.waitUntilExit()
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                let remainingStdout = stdout.fileHandleForReading.readDataToEndOfFile()
                if !remainingStdout.isEmpty {
                    stdoutBuffer.append(remainingStdout)
                    if let chunk = String(data: remainingStdout, encoding: .utf8) {
                        outputHandler(chunk)
                    }
                }
                let remainingStderr = stderr.fileHandleForReading.readDataToEndOfFile()
                if !remainingStderr.isEmpty {
                    stderrBuffer.append(remainingStderr)
                    if let chunk = String(data: remainingStderr, encoding: .utf8) {
                        outputHandler(chunk)
                    }
                }

                if Task.isCancelled {
                    throw SSHClientError.cancelled
                }

                return ProcessResult(
                    stdout: String(data: stdoutBuffer.data(), encoding: .utf8) ?? "",
                    stderr: String(data: stderrBuffer.data(), encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                )
            }.value
        } onCancel: {
            processBox.terminate()
        }
    }
}

struct SSHProcessAuthContext {
    var arguments: [String]
    var environment: [String: String]
    var temporaryURLs: [URL]
    var fileManager: FileManager

    func cleanup() {
        for url in temporaryURLs {
            try? fileManager.removeItem(at: url)
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let data = storage
        lock.unlock()
        return data
    }
}

private struct ProcessResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}
