using HHCServerManager.Windows.Domain.Security;
using HHCServerManager.Windows.Domain.Servers;

namespace HHCServerManager.Windows.Application.Ports;

public interface IHostKeyTrustStore
{
    Task<TrustedHostKey?> FindAsync(Guid serverId, ServerEndpoint endpoint, CancellationToken cancellationToken = default);
    Task SaveAsync(TrustedHostKey key, CancellationToken cancellationToken = default);
    Task DeleteForServerAsync(Guid serverId, CancellationToken cancellationToken = default);
}
