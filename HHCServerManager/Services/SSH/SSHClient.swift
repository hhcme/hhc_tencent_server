import Foundation

protocol SSHClient: Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult
    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult
    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws
}

protocol RemoteFileTransferClient: Sendable {
    func uploadFile(
        localURL: URL,
        remotePath: String,
        profile: ServerProfile,
        progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?
    ) async throws -> RemoteFileTransferResult

    func downloadFile(
        remotePath: String,
        localURL: URL,
        profile: ServerProfile,
        progressHandler: (@Sendable (RemoteFileTransferProgress) -> Void)?
    ) async throws -> RemoteFileTransferResult
}

extension RemoteFileTransferClient {
    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        try await uploadFile(localURL: localURL, remotePath: remotePath, profile: profile, progressHandler: nil)
    }

    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile) async throws -> RemoteFileTransferResult {
        try await downloadFile(remotePath: remotePath, localURL: localURL, profile: profile, progressHandler: nil)
    }
}
