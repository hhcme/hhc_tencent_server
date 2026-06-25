using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;

namespace HHCServerManager.Windows.Application.Ports;

public interface IWindowsSshClient
{
    Task<SshHostKey> ScanHostKeyAsync(ServerProfile profile, CredentialInput credential, CancellationToken cancellationToken = default);
    Task<CommandResult> ExecuteAsync(ServerProfile profile, CredentialInput credential, string command, CancellationToken cancellationToken = default);
}
