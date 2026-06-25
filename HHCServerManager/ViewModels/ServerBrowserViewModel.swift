import Foundation

@MainActor
final class ServerBrowserViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedServerId: UUID?

    func filteredServers(from servers: [ServerProfile]) -> [ServerProfile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return servers }
        return servers.filter { profile in
            profile.name.localizedCaseInsensitiveContains(query) ||
                profile.host.localizedCaseInsensitiveContains(query) ||
                profile.username.localizedCaseInsensitiveContains(query) ||
                (profile.groupName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}
