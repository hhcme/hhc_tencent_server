using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Domain.Security;
using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;

namespace HHCServerManager.Windows.Application.ServerManagement;

public sealed class ServerManagementService(
    IServerProfileRepository profiles,
    IHostKeyTrustStore hostKeys,
    ICredentialStore credentials,
    TimeProvider? timeProvider = null)
{
    private readonly TimeProvider _timeProvider = timeProvider ?? TimeProvider.System;

    public async Task<ServerProfile> AddServerAsync(
        string name,
        string host,
        int port,
        string username,
        SshAuthType authType,
        string? groupName,
        CredentialInput credential,
        CancellationToken cancellationToken = default)
    {
        var profile = ServerProfile.Create(name, host, port, username, authType, groupName, _timeProvider);
        await credentials.SaveAsync(profile.CredentialRef, credential, cancellationToken);
        try
        {
            await profiles.UpsertAsync(profile, cancellationToken);
            return profile;
        }
        catch
        {
            await credentials.DeleteAsync(profile.CredentialRef, cancellationToken);
            throw;
        }
    }

    public async Task DeleteServerAsync(Guid serverId, CancellationToken cancellationToken = default)
    {
        var profile = await profiles.FindAsync(serverId, cancellationToken);
        if (profile is null)
        {
            return;
        }

        await profiles.DeleteAsync(serverId, cancellationToken);
        await hostKeys.DeleteForServerAsync(serverId, cancellationToken);
        await credentials.DeleteAsync(profile.CredentialRef, cancellationToken);
    }

    public async Task<HostKeyCheckResult> CheckHostKeyAsync(
        ServerProfile profile,
        SshHostKey presentedKey,
        CancellationToken cancellationToken = default)
    {
        var trusted = await hostKeys.FindAsync(profile.Id, profile.Endpoint, cancellationToken);
        if (trusted is null)
        {
            return new HostKeyCheckResult(HostKeyTrustDecision.Unknown, null);
        }

        return string.Equals(trusted.FingerprintSha256, presentedKey.FingerprintSha256, StringComparison.Ordinal)
            ? new HostKeyCheckResult(HostKeyTrustDecision.Trusted, trusted)
            : new HostKeyCheckResult(HostKeyTrustDecision.Mismatch, trusted);
    }

    public async Task<TrustedHostKey> TrustHostKeyAsync(
        ServerProfile profile,
        SshHostKey presentedKey,
        CancellationToken cancellationToken = default)
    {
        var trusted = TrustedHostKey.Trust(
            profile.Id,
            profile.Endpoint,
            presentedKey.Algorithm,
            presentedKey.FingerprintSha256,
            presentedKey.RawPublicKey,
            _timeProvider);
        await hostKeys.SaveAsync(trusted, cancellationToken);
        return trusted;
    }

    public async Task<CommandResult> RunSmokeTestAsync(
        ServerProfile profile,
        IWindowsSshClient sshClient,
        CancellationToken cancellationToken = default)
    {
        var credential = await credentials.ReadAsync(profile.CredentialRef, cancellationToken)
            ?? throw new InvalidOperationException("Credential is missing for this server.");
        return await sshClient.ExecuteAsync(profile, credential, "printf hhc-ssh-ok", cancellationToken);
    }
}
