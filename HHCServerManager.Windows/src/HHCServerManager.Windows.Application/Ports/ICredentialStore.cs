using HHCServerManager.Windows.Domain.Ssh;

namespace HHCServerManager.Windows.Application.Ports;

public interface ICredentialStore
{
    Task SaveAsync(string credentialRef, CredentialInput credential, CancellationToken cancellationToken = default);
    Task<CredentialInput?> ReadAsync(string credentialRef, CancellationToken cancellationToken = default);
    Task DeleteAsync(string credentialRef, CancellationToken cancellationToken = default);
}
