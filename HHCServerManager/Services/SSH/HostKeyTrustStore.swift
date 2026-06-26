import Foundation
import CryptoKit

enum HostKeyTrustEvaluation: Equatable {
    case trusted
    case unknown(HostKeyInfo)
    case changed(current: HostKeyInfo, trusted: TrustedHostKey)
}

struct KnownHostsImportResult: Equatable {
    var importedCount: Int
    var skippedCount: Int
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

    @discardableResult
    func importKnownHosts(_ content: String, for profile: ServerProfile) throws -> KnownHostsImportResult {
        var importedCount = 0
        var skippedCount = 0

        for line in content.components(separatedBy: .newlines) {
            guard let hostKeyInfo = Self.hostKeyInfo(fromKnownHostsLine: line, matching: profile) else {
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    skippedCount += 1
                }
                continue
            }
            try trust(hostKeyInfo, for: profile)
            importedCount += 1
        }

        return KnownHostsImportResult(importedCount: importedCount, skippedCount: skippedCount)
    }

    @discardableResult
    func importKnownHosts(from url: URL, for profile: ServerProfile) throws -> KnownHostsImportResult {
        try importKnownHosts(String(contentsOf: url, encoding: .utf8), for: profile)
    }

    static func hostKeyInfo(fromKnownHostsLine line: String, matching profile: ServerProfile) -> HostKeyInfo? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty,
              !trimmedLine.hasPrefix("#"),
              !trimmedLine.hasPrefix("@"),
              !trimmedLine.hasPrefix("|")
        else {
            return nil
        }

        let fields = trimmedLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 3 else { return nil }
        let hostPatterns = fields[0].split(separator: ",").map(String.init)
        let algorithm = String(fields[1])
        let publicKey = String(fields[2])
        guard algorithm.hasPrefix("ssh-"),
              let publicKeyData = Data(base64Encoded: publicKey)
        else {
            return nil
        }

        guard hostPatterns.contains(where: { hostPatternMatches($0, profile: profile) }) else {
            return nil
        }

        return HostKeyInfo(
            host: profile.host,
            port: profile.port,
            algorithm: algorithm,
            fingerprintSHA256: "SHA256:\(sha256Base64WithoutPadding(publicKeyData))",
            rawPublicKey: "\(profile.host) \(algorithm) \(publicKey)"
        )
    }

    private static func hostPatternMatches(_ pattern: String, profile: ServerProfile) -> Bool {
        if pattern.hasPrefix("[") {
            return pattern == "[\(profile.host)]:\(profile.port)"
        }
        guard !pattern.hasPrefix("!") else { return false }
        return profile.port == 22 && pattern == profile.host
    }

    private static func sha256Base64WithoutPadding(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}
