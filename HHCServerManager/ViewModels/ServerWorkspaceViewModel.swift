import Foundation

@MainActor
final class ServerWorkspaceViewModel: ObservableObject {
    @Published var isRunningSmokeTest = false
    @Published var commandResult: CommandResult?
    @Published var errorMessage: String?
    @Published var pendingHostKey: HostKeyInfo?

    func runSmokeTest(profile: ServerProfile, sshClient: SSHClient) {
        isRunningSmokeTest = true
        errorMessage = nil
        commandResult = nil

        Task {
            do {
                let result = try await sshClient.runSmokeTest(profile: profile)
                await MainActor.run {
                    self.commandResult = result
                    self.isRunningSmokeTest = false
                }
            } catch SSHClientError.unknownHostKey(let hostKeyInfo) {
                await MainActor.run {
                    self.pendingHostKey = hostKeyInfo
                    self.isRunningSmokeTest = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isRunningSmokeTest = false
                }
            }
        }
    }

    func trustPendingHostKey(profile: ServerProfile, sshClient: SSHClient) {
        guard let pendingHostKey else { return }
        do {
            try sshClient.trustHostKey(pendingHostKey, for: profile)
            self.pendingHostKey = nil
            runSmokeTest(profile: profile, sshClient: sshClient)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
