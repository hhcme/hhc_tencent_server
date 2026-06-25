using HHCServerManager.Windows.Domain.Security;
using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;

namespace HHCServerManager.Windows.Application.Shell;

public sealed record PendingHostKeyTrust(
    ServerProfile Profile,
    SshHostKey PresentedKey,
    TrustedHostKey? ExistingTrustedKey)
{
    public bool IsMismatch => ExistingTrustedKey is not null;
}
