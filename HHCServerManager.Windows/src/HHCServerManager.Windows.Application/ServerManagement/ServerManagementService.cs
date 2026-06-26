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

    public async Task<ServerProfile> UpdateServerAsync(
        Guid serverId,
        string name,
        string host,
        int port,
        string username,
        SshAuthType authType,
        string? groupName,
        CredentialInput? replacementCredential = null,
        CancellationToken cancellationToken = default)
    {
        var existing = await profiles.FindAsync(serverId, cancellationToken)
            ?? throw new InvalidOperationException("Server profile was not found.");
        if (replacementCredential is null && authType != existing.AuthType)
        {
            throw new InvalidOperationException("Changing authentication type requires a replacement credential.");
        }

        var updated = existing.Update(name, host, port, username, authType, groupName, _timeProvider);
        var endpointChanged = existing.Endpoint != updated.Endpoint;
        CredentialInput? originalCredential = null;

        if (replacementCredential is not null)
        {
            originalCredential = await credentials.ReadAsync(existing.CredentialRef, cancellationToken);
            await credentials.SaveAsync(existing.CredentialRef, replacementCredential, cancellationToken);
        }

        try
        {
            await profiles.UpsertAsync(updated, cancellationToken);
            if (endpointChanged)
            {
                await hostKeys.DeleteForServerAsync(existing.Id, cancellationToken);
            }
            return updated;
        }
        catch
        {
            if (replacementCredential is not null)
            {
                if (originalCredential is null)
                {
                    await credentials.DeleteAsync(existing.CredentialRef, cancellationToken);
                }
                else
                {
                    await credentials.SaveAsync(existing.CredentialRef, originalCredential, cancellationToken);
                }
            }
            throw;
        }
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

    public async Task<SshHostKey> ScanHostKeyAsync(
        ServerProfile profile,
        IWindowsSshClient sshClient,
        CancellationToken cancellationToken = default)
    {
        var credential = await credentials.ReadAsync(profile.CredentialRef, cancellationToken)
            ?? throw new InvalidOperationException("Credential is missing for this server.");
        return await sshClient.ScanHostKeyAsync(profile, credential, cancellationToken);
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

    public async Task<CommandResult> RunCommandAsync(
        ServerProfile profile,
        IWindowsSshClient sshClient,
        string command,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(command))
        {
            throw new InvalidOperationException("Command is required.");
        }

        var credential = await credentials.ReadAsync(profile.CredentialRef, cancellationToken)
            ?? throw new InvalidOperationException("Credential is missing for this server.");
        return await sshClient.ExecuteAsync(profile, credential, command.Trim(), cancellationToken);
    }
}
