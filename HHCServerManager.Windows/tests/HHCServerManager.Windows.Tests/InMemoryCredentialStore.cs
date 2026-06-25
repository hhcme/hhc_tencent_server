using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Domain.Ssh;

namespace HHCServerManager.Windows.Tests;

internal sealed class InMemoryCredentialStore : ICredentialStore
{
    private readonly Dictionary<string, CredentialInput> _credentials = new();

    public Task SaveAsync(string credentialRef, CredentialInput credential, CancellationToken cancellationToken = default)
    {
        _credentials[credentialRef] = credential;
        return Task.CompletedTask;
    }

    public Task<CredentialInput?> ReadAsync(string credentialRef, CancellationToken cancellationToken = default) =>
        Task.FromResult(_credentials.GetValueOrDefault(credentialRef));

    public Task DeleteAsync(string credentialRef, CancellationToken cancellationToken = default)
    {
        _credentials.Remove(credentialRef);
        return Task.CompletedTask;
    }
}
