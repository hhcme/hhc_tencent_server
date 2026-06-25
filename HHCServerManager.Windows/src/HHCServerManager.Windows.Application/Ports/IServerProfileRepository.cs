using HHCServerManager.Windows.Domain.Servers;

namespace HHCServerManager.Windows.Application.Ports;

public interface IServerProfileRepository
{
    Task<IReadOnlyList<ServerProfile>> ListAsync(CancellationToken cancellationToken = default);
    Task<ServerProfile?> FindAsync(Guid id, CancellationToken cancellationToken = default);
    Task UpsertAsync(ServerProfile profile, CancellationToken cancellationToken = default);
    Task DeleteAsync(Guid id, CancellationToken cancellationToken = default);
}
