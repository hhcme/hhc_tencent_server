using HHCServerManager.Windows.Application.ServerManagement;
using HHCServerManager.Windows.Domain.Security;
using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;
using HHCServerManager.Windows.Infrastructure.Credentials;
using HHCServerManager.Windows.Infrastructure.Storage;

namespace HHCServerManager.Windows.Tests;

public sealed class WindowsPhase8CoreTests
{
    [Fact]
    public async Task SqliteRepositoryPersistsServerProfilesWithoutCredentialMaterial()
    {
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var profile = ServerProfile.Create(
            "Prod",
            "203.0.113.10",
            22,
            "root",
            SshAuthType.PrivateKey,
            "ops");

        await repository.UpsertAsync(profile);
        var persisted = await repository.FindAsync(profile.Id);

        Assert.NotNull(persisted);
        Assert.Equal("Prod", persisted.Name);
        Assert.Equal("server_", persisted.CredentialRef[..7]);
        Assert.DoesNotContain("BEGIN OPENSSH", string.Join(" ", (await repository.ListAsync()).Select(p => p.CredentialRef)));
    }

    [Fact]
    public async Task HostKeyTrustStoreDetectsTrustedAndMismatchedKeys()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var profile = await service.AddServerAsync(
            "Prod",
            "example.internal",
            22,
            "root",
            SshAuthType.Password,
            null,
            new CredentialInput.Password("secret"));

        var unknown = await service.CheckHostKeyAsync(profile, new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"));
        Assert.Equal(HostKeyTrustDecision.Unknown, unknown.Decision);

        await service.TrustHostKeyAsync(profile, new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"));
        var trusted = await service.CheckHostKeyAsync(profile, new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"));
        var mismatch = await service.CheckHostKeyAsync(profile, new SshHostKey("ssh-ed25519", "SHA256:second", "ssh-ed25519 BBBB"));

        Assert.Equal(HostKeyTrustDecision.Trusted, trusted.Decision);
        Assert.Equal(HostKeyTrustDecision.Mismatch, mismatch.Decision);
    }

    [Fact]
    public async Task ServerDeletionRemovesCredentialAndTrustedHostKey()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var profile = await service.AddServerAsync(
            "Prod",
            "example.internal",
            22,
            "root",
            SshAuthType.Password,
            null,
            new CredentialInput.Password("secret"));
        await service.TrustHostKeyAsync(profile, new SshHostKey("ssh-rsa", "SHA256:trusted", "ssh-rsa AAAA"));

        await service.DeleteServerAsync(profile.Id);

        Assert.Null(await repository.FindAsync(profile.Id));
        Assert.Null(await credentials.ReadAsync(profile.CredentialRef));
        Assert.Null(await hostKeys.FindAsync(profile.Id, profile.Endpoint));
    }

    [Fact]
    public async Task WindowsCredentialStoreIsExplicitlyWindowsOnly()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var store = new WindowsCredentialStore();
        await Assert.ThrowsAsync<PlatformNotSupportedException>(() =>
            store.SaveAsync("test", new CredentialInput.Password("secret")));
    }
}
