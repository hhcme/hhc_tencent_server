import Foundation

protocol SSHClient: Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult
    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult
    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws
}

protocol RemoteFileTransferClient: Sendable {
    func uploadFile(localURL: URL, remotePath: String, profile: ServerProfile) async throws -> RemoteFileTransferResult
    func downloadFile(remotePath: String, localURL: URL, profile: ServerProfile) async throws -> RemoteFileTransferResult
}
