using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Application.ServerManagement;
using HHCServerManager.Windows.Application.Shell;
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
    public async Task SqliteRepositoryFileDoesNotContainCredentialMaterial()
    {
        var databasePath = Path.Combine(Path.GetTempPath(), $"hhc-windows-phase8-{Guid.NewGuid():N}.sqlite");
        var connectionString = $"Data Source={databasePath};Pooling=False";
        var password = "phase8-password-should-not-be-in-sqlite";
        var privateKey = """
            -----BEGIN OPENSSH PRIVATE KEY-----
            phase8-private-key-should-not-be-in-sqlite
            -----END OPENSSH PRIVATE KEY-----
            """;
        var passphrase = "phase8-passphrase-should-not-be-in-sqlite";

        try
        {
            await using (var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:"))
            await using (var repository = new SqliteServerRepository(connectionString))
            {
                var credentials = new InMemoryCredentialStore();
                var service = new ServerManagementService(repository, hostKeys, credentials);

                await service.AddServerAsync(
                    "Password",
                    "password.example.internal",
                    22,
                    "root",
                    SshAuthType.Password,
                    null,
                    new CredentialInput.Password(password));
                await service.AddServerAsync(
                    "Private Key",
                    "private-key.example.internal",
                    22,
                    "root",
                    SshAuthType.PrivateKey,
                    "ops",
                    new CredentialInput.PrivateKey(System.Text.Encoding.UTF8.GetBytes(privateKey), passphrase));
            }

            var databaseText = System.Text.Encoding.UTF8.GetString(await File.ReadAllBytesAsync(databasePath));

            Assert.DoesNotContain(password, databaseText);
            Assert.DoesNotContain(privateKey, databaseText);
            Assert.DoesNotContain("phase8-private-key-should-not-be-in-sqlite", databaseText);
            Assert.DoesNotContain(passphrase, databaseText);
            Assert.DoesNotContain("BEGIN OPENSSH PRIVATE KEY", databaseText);
        }
        finally
        {
            if (File.Exists(databasePath))
            {
                File.Delete(databasePath);
            }
        }
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
    public async Task ServerUpdateKeepsCredentialAndClearsTrustedHostKeyWhenEndpointChanges()
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
            "ops",
            new CredentialInput.Password("secret"));
        await service.TrustHostKeyAsync(profile, new SshHostKey("ssh-ed25519", "SHA256:trusted", "ssh-ed25519 AAAA"));

        var updated = await service.UpdateServerAsync(
            profile.Id,
            "Prod API",
            "api.example.internal",
            2222,
            "deploy",
            SshAuthType.Password,
            "prod");

        Assert.Equal(profile.Id, updated.Id);
        Assert.Equal("Prod API", updated.Name);
        Assert.Equal("api.example.internal", updated.Host);
        Assert.Equal(2222, updated.Port);
        Assert.Equal("deploy", updated.Username);
        Assert.Equal("prod", updated.GroupName);
        Assert.Null(await hostKeys.FindAsync(profile.Id, profile.Endpoint));
        var credential = Assert.IsType<CredentialInput.Password>(await credentials.ReadAsync(profile.CredentialRef));
        Assert.Equal("secret", credential.Value);
    }

    [Fact]
    public async Task ServerUpdateReplacesCredentialAndRequiresCredentialWhenChangingAuthType()
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

        await Assert.ThrowsAsync<InvalidOperationException>(() => service.UpdateServerAsync(
            profile.Id,
            "Prod",
            "example.internal",
            22,
            "root",
            SshAuthType.PrivateKey,
            null));

        var keyData = System.Text.Encoding.UTF8.GetBytes("private-key-data");
        var updated = await service.UpdateServerAsync(
            profile.Id,
            "Prod",
            "example.internal",
            22,
            "root",
            SshAuthType.PrivateKey,
            null,
            new CredentialInput.PrivateKey(keyData, "passphrase"));

        Assert.Equal(SshAuthType.PrivateKey, updated.AuthType);
        var credential = Assert.IsType<CredentialInput.PrivateKey>(await credentials.ReadAsync(profile.CredentialRef));
        Assert.Equal("private-key-data", System.Text.Encoding.UTF8.GetString(credential.Data));
        Assert.Equal("passphrase", credential.Passphrase);
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

    [Fact]
    public async Task MainWindowViewModelRequiresHostKeyTrustThenRunsSmokeTest()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("printf hhc-ssh-ok", "hhc-ssh-ok", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, ssh);
        await viewModel.AddPasswordServerAsync("Prod", "example.internal", 22, "root", "secret");

        await viewModel.ConnectAsync();

        Assert.Equal(WindowsConnectionState.AwaitingHostKeyTrust, viewModel.ConnectionState);
        Assert.True(viewModel.CanConfirmHostKey);
        Assert.Contains("SHA256:first", viewModel.HostKeyTrustMessage);

        await viewModel.TrustPendingHostKeyAndConnectAsync();
        await viewModel.RunSmokeTestAsync();

        Assert.Equal(WindowsConnectionState.Connected, viewModel.ConnectionState);
        Assert.Equal("hhc-ssh-ok", viewModel.CommandOutput);
        Assert.Equal("Smoke test succeeded.", viewModel.StatusMessage);
    }

    [Fact]
    public async Task MainWindowViewModelAddsPrivateKeyServerWithoutPersistingKeyMaterialToSqlite()
    {
        var databasePath = Path.Combine(Path.GetTempPath(), $"hhc-windows-private-key-{Guid.NewGuid():N}.sqlite");
        var connectionString = $"Data Source={databasePath};Pooling=False";
        var privateKey = """
            -----BEGIN OPENSSH PRIVATE KEY-----
            phase8-viewmodel-private-key
            -----END OPENSSH PRIVATE KEY-----
            """;
        var passphrase = "phase8-viewmodel-passphrase";

        try
        {
            await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
            await using var repository = new SqliteServerRepository(connectionString);
            var credentials = new InMemoryCredentialStore();
            var service = new ServerManagementService(repository, hostKeys, credentials);
            var ssh = new FakeWindowsSshClient(
                new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
                new CommandResult("printf hhc-ssh-ok", "hhc-ssh-ok", "", 0, TimeSpan.FromMilliseconds(4)));
            var viewModel = new MainWindowViewModel(repository, service, ssh);

            await viewModel.AddPrivateKeyServerAsync(
                "Private Key Host",
                "key.example.internal",
                22,
                "deploy",
                privateKey,
                passphrase,
                "ops");

            var profile = Assert.Single(viewModel.Servers);
            Assert.Same(profile, viewModel.SelectedServer);
            Assert.Equal(SshAuthType.PrivateKey, profile.AuthType);
            Assert.Equal("ops", profile.GroupName);
            Assert.Equal("Added Private Key Host.", viewModel.StatusMessage);
            Assert.Null(viewModel.ErrorMessage);

            var storedCredential = await credentials.ReadAsync(profile.CredentialRef);
            var storedKey = Assert.IsType<CredentialInput.PrivateKey>(storedCredential);
            Assert.Equal(privateKey.Trim(), System.Text.Encoding.UTF8.GetString(storedKey.Data));
            Assert.Equal(passphrase, storedKey.Passphrase);

            var databaseText = System.Text.Encoding.UTF8.GetString(await File.ReadAllBytesAsync(databasePath));
            Assert.DoesNotContain("phase8-viewmodel-private-key", databaseText);
            Assert.DoesNotContain(passphrase, databaseText);
            Assert.DoesNotContain("BEGIN OPENSSH PRIVATE KEY", databaseText);
        }
        finally
        {
            if (File.Exists(databasePath))
            {
                File.Delete(databasePath);
            }
        }
    }

    [Fact]
    public async Task MainWindowViewModelRejectsBlankPrivateKeyServer()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("printf hhc-ssh-ok", "hhc-ssh-ok", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, ssh);

        await viewModel.AddPrivateKeyServerAsync("Private Key Host", "key.example.internal", 22, "deploy", "   ");

        Assert.Empty(viewModel.Servers);
        Assert.Equal("Could not add server.", viewModel.StatusMessage);
        Assert.Contains("Private key data is required", viewModel.ErrorMessage ?? "");
    }

    [Fact]
    public async Task MainWindowViewModelUpdatesSelectedServerAndKeepsCredentialWhenBlankReplacement()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("printf hhc-ssh-ok", "hhc-ssh-ok", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, ssh);
        await viewModel.AddPasswordServerAsync("Prod", "example.internal", 22, "root", "secret", "ops");
        var original = viewModel.SelectedServer!;

        await viewModel.UpdateSelectedServerAsync(
            "Prod API",
            "api.example.internal",
            2222,
            "deploy",
            SshAuthType.Password,
            "prod");

        var updated = Assert.Single(viewModel.Servers);
        Assert.Equal(original.Id, updated.Id);
        Assert.Same(updated, viewModel.SelectedServer);
        Assert.Equal("Prod API", updated.Name);
        Assert.Equal("api.example.internal", updated.Host);
        Assert.Equal(2222, updated.Port);
        Assert.Equal("deploy", updated.Username);
        Assert.Equal("prod", updated.GroupName);
        Assert.Equal("Updated Prod API.", viewModel.StatusMessage);
        Assert.Null(viewModel.ErrorMessage);
        var credential = Assert.IsType<CredentialInput.Password>(await credentials.ReadAsync(updated.CredentialRef));
        Assert.Equal("secret", credential.Value);
    }

    [Fact]
    public async Task MainWindowViewModelBlocksMismatchedHostKeyUntilUserReviewsIt()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var trustedSsh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("printf hhc-ssh-ok", "hhc-ssh-ok", "", 0, TimeSpan.FromMilliseconds(4)));
        var profile = await service.AddServerAsync(
            "Prod",
            "example.internal",
            22,
            "root",
            SshAuthType.Password,
            null,
            new CredentialInput.Password("secret"));
        await service.TrustHostKeyAsync(profile, trustedSsh.HostKey);

        var changedSsh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:changed", "ssh-ed25519 BBBB"),
            new CommandResult("printf hhc-ssh-ok", "hhc-ssh-ok", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, changedSsh);
        await viewModel.LoadServersAsync();

        await viewModel.ConnectAsync();

        Assert.Equal(WindowsConnectionState.AwaitingHostKeyTrust, viewModel.ConnectionState);
        Assert.True(viewModel.PendingHostKeyTrust?.IsMismatch);
        Assert.Contains("differs", viewModel.HostKeyTrustMessage);

        viewModel.RejectPendingHostKey();

        Assert.Equal(WindowsConnectionState.Disconnected, viewModel.ConnectionState);
        Assert.False(viewModel.CanConfirmHostKey);
    }

    private sealed class FakeWindowsSshClient(SshHostKey hostKey, CommandResult result) : IWindowsSshClient
    {
        public SshHostKey HostKey { get; } = hostKey;

        public Task<SshHostKey> ScanHostKeyAsync(
            ServerProfile profile,
            CredentialInput credential,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(HostKey);

        public Task<CommandResult> ExecuteAsync(
            ServerProfile profile,
            CredentialInput credential,
            string command,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(result with { Command = command });
    }
}
