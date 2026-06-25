import Foundation

protocol SSHClient: Sendable {
    func runSmokeTest(profile: ServerProfile) async throws -> CommandResult
    func execute(_ command: String, profile: ServerProfile) async throws -> CommandResult
    func trustHostKey(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws
}
