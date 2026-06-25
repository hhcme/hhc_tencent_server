using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;
using Renci.SshNet;
using Renci.SshNet.Common;

namespace HHCServerManager.Windows.Infrastructure.Ssh;

public sealed class SshNetClient : IWindowsSshClient
{
    public async Task<SshHostKey> ScanHostKeyAsync(ServerProfile profile, CredentialInput credential, CancellationToken cancellationToken = default)
    {
        SshHostKey? scanned = null;
        using var client = CreateClient(profile, credential);
        client.HostKeyReceived += (_, args) =>
        {
            scanned = FromHostKey(args);
            args.CanTrust = true;
        };

        await Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            client.Connect();
            client.Disconnect();
        }, cancellationToken);

        return scanned ?? throw new InvalidOperationException("SSH host key was not received.");
    }

    public async Task<CommandResult> ExecuteAsync(
        ServerProfile profile,
        CredentialInput credential,
        string command,
        CancellationToken cancellationToken = default)
    {
        var stopwatch = Stopwatch.StartNew();
        using var client = CreateClient(profile, credential);
        return await Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            client.Connect();
            try
            {
                using var sshCommand = client.CreateCommand(command);
                var stdout = sshCommand.Execute();
                stopwatch.Stop();
                return new CommandResult(
                    command,
                    stdout,
                    sshCommand.Error,
                    sshCommand.ExitStatus ?? -1,
                    stopwatch.Elapsed);
            }
            finally
            {
                client.Disconnect();
            }
        }, cancellationToken);
    }

    private static SshClient CreateClient(ServerProfile profile, CredentialInput credential)
    {
        ConnectionInfo connectionInfo = credential switch
        {
            CredentialInput.Password password => new ConnectionInfo(
                profile.Host,
                profile.Port,
                profile.Username,
                new PasswordAuthenticationMethod(profile.Username, password.Value)),
            CredentialInput.PrivateKey privateKey => new ConnectionInfo(
                profile.Host,
                profile.Port,
                profile.Username,
                new PrivateKeyAuthenticationMethod(profile.Username, PrivateKeyFile(privateKey))),
            _ => throw new ArgumentOutOfRangeException(nameof(credential))
        };
        return new SshClient(connectionInfo);
    }

    private static PrivateKeyFile PrivateKeyFile(CredentialInput.PrivateKey privateKey)
    {
        var stream = new MemoryStream(privateKey.Data, writable: false);
        return privateKey.Passphrase is null ? new PrivateKeyFile(stream) : new PrivateKeyFile(stream, privateKey.Passphrase);
    }

    private static SshHostKey FromHostKey(HostKeyEventArgs args)
    {
        var fingerprint = Convert.ToBase64String(SHA256.HashData(args.HostKey));
        var raw = $"{args.HostKeyName} {Convert.ToBase64String(args.HostKey)}";
        return new SshHostKey(args.HostKeyName, $"SHA256:{fingerprint.TrimEnd('=')}", raw);
    }
}
