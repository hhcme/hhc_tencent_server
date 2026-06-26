using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;

namespace HHCServerManager.Windows.Application.Ports;

public interface IServerProfileRepository
{
    Task<IReadOnlyList<ServerProfile>> ListAsync(CancellationToken cancellationToken = default);
    Task<ServerProfile?> FindAsync(Guid id, CancellationToken cancellationToken = default);
    Task UpsertAsync(ServerProfile profile, CancellationToken cancellationToken = default);
    Task DeleteAsync(Guid id, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<CommandHistoryEntry>> ListRecentCommandHistoryAsync(Guid serverId, int limit = 10, CancellationToken cancellationToken = default);
    Task SaveCommandHistoryAsync(CommandHistoryEntry entry, CancellationToken cancellationToken = default);
}
