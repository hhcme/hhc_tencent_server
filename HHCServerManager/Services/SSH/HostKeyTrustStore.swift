import Foundation

enum HostKeyTrustEvaluation: Equatable {
    case trusted
    case unknown(HostKeyInfo)
    case changed(current: HostKeyInfo, trusted: TrustedHostKey)
}

final class HostKeyTrustStore: @unchecked Sendable {
    private let repository: ServerRepository

    init(repository: ServerRepository) {
        self.repository = repository
    }

    func evaluate(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws -> HostKeyTrustEvaluation {
        let trustedKeys = try repository.fetchTrustedHostKeys(serverId: profile.id)
        if trustedKeys.contains(where: { $0.fingerprintSHA256 == hostKeyInfo.fingerprintSHA256 }) {
            return .trusted
        }
        if let sameAlgorithm = trustedKeys.first(where: { $0.algorithm == hostKeyInfo.algorithm }) {
            return .changed(current: hostKeyInfo, trusted: sameAlgorithm)
        }
        return .unknown(hostKeyInfo)
    }

    func trust(_ hostKeyInfo: HostKeyInfo, for profile: ServerProfile) throws {
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
    }
}
