import Foundation

enum ServerSourceFilter: String, CaseIterable, Identifiable {
    case all
    case manual
    case cloud

    var id: String { rawValue }
}

@MainActor
final class ServerBrowserViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedServerId: UUID?
    @Published var sourceFilter: ServerSourceFilter = .all

    func filteredServers(from servers: [ServerProfile], links: [CloudInstanceLink]) -> [ServerProfile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkedServerIds = Set(links.compactMap(\.serverId))
        return servers.filter { profile in
            switch sourceFilter {
            case .all:
                true
            case .manual:
                !linkedServerIds.contains(profile.id)
            case .cloud:
                linkedServerIds.contains(profile.id)
            }
        }.filter { profile in
            query.isEmpty ||
                profile.name.localizedCaseInsensitiveContains(query) ||
                profile.host.localizedCaseInsensitiveContains(query) ||
                profile.username.localizedCaseInsensitiveContains(query) ||
                (profile.groupName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func cloudLink(for profile: ServerProfile, links: [CloudInstanceLink]) -> CloudInstanceLink? {
        links.first { $0.serverId == profile.id }
    }
}
