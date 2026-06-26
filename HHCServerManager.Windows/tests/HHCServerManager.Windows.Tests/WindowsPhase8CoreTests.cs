using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Application.ServerManagement;
using HHCServerManager.Windows.Application.Security;
using HHCServerManager.Windows.Application.Shell;
using HHCServerManager.Windows.Domain.Security;
using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;
using HHCServerManager.Windows.Infrastructure.Credentials;
using HHCServerManager.Windows.Infrastructure.Ssh;
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
    public async Task KnownHostsImporterTrustsMatchingOpenSshHostEntry()
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
        var publicKey = Convert.ToBase64String(new byte[] { 1, 2, 3, 4 });
        var importer = new OpenSshKnownHostsImporter(hostKeys);

        var result = await importer.ImportAsync(
            $"""
            # Existing user known_hosts entry
            other.internal ssh-ed25519 {Convert.ToBase64String(new byte[] { 9 })}
            example.internal ssh-ed25519 {publicKey} imported-comment
            """,
            profile);

        var trusted = await hostKeys.FindAsync(profile.Id, profile.Endpoint);
        Assert.Equal(new KnownHostsImportResult(1, 2), result);
        Assert.NotNull(trusted);
        Assert.Equal("ssh-ed25519", trusted.Algorithm);
        Assert.StartsWith("SHA256:", trusted.FingerprintSha256, StringComparison.Ordinal);
        Assert.Equal($"example.internal ssh-ed25519 {publicKey}", trusted.RawPublicKey);
    }

    [Fact]
    public async Task KnownHostsImporterMatchesBracketedNonDefaultPortAndSkipsUnsupportedLines()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var profile = await service.AddServerAsync(
            "Prod",
            "example.internal",
            2222,
            "root",
            SshAuthType.Password,
            null,
            new CredentialInput.Password("secret"));
        var publicKey = Convert.ToBase64String(new byte[] { 5, 6, 7, 8 });
        var importer = new OpenSshKnownHostsImporter(hostKeys);

        var result = await importer.ImportAsync(
            $"""
            |1|hashed|entry ssh-ed25519 {Convert.ToBase64String(new byte[] { 1 })}
            @cert-authority *.internal ssh-ed25519 {Convert.ToBase64String(new byte[] { 2 })}
            example.internal ssh-ed25519 {Convert.ToBase64String(new byte[] { 3 })}
            [example.internal]:2222 ssh-ed25519 {publicKey}
            example.internal ssh-ed25519 not-base64
            """,
            profile);

        var trusted = await hostKeys.FindAsync(profile.Id, profile.Endpoint);
        Assert.Equal(new KnownHostsImportResult(1, 4), result);
        Assert.NotNull(trusted);
        Assert.Equal($"example.internal ssh-ed25519 {publicKey}", trusted.RawPublicKey);
    }

    [Fact]
    public async Task MainWindowViewModelImportsKnownHostsForSelectedServer()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("printf hhc-ssh-ok", "hhc-ssh-ok", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, ssh);
        await viewModel.AddPasswordServerAsync("Prod", "example.internal", 2222, "root", "secret");
        var publicKey = Convert.ToBase64String(new byte[] { 11, 12, 13, 14 });

        await viewModel.ImportKnownHostsForSelectedServerAsync(
            $"""
            other.internal ssh-ed25519 {Convert.ToBase64String(new byte[] { 1 })}
            [example.internal]:2222 ssh-ed25519 {publicKey}
            """);

        var trusted = await hostKeys.FindAsync(viewModel.SelectedServer!.Id, viewModel.SelectedServer.Endpoint);
        Assert.NotNull(trusted);
        Assert.StartsWith("SHA256:", trusted.FingerprintSha256, StringComparison.Ordinal);
        Assert.Equal($"example.internal ssh-ed25519 {publicKey}", trusted.RawPublicKey);
        Assert.Equal("Imported 1 known_hosts entry for Prod. Skipped 1.", viewModel.StatusMessage);
        Assert.Null(viewModel.ErrorMessage);
    }

    [Fact]
    public async Task MainWindowViewModelRejectsBlankKnownHostsImport()
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

        await viewModel.ImportKnownHostsForSelectedServerAsync("   ");

        Assert.Equal("Could not import known_hosts.", viewModel.StatusMessage);
        Assert.Equal("Known hosts content is required.", viewModel.ErrorMessage);
        Assert.Null(await hostKeys.FindAsync(viewModel.SelectedServer!.Id, viewModel.SelectedServer.Endpoint));
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
    public async Task MainWindowViewModelRunsCustomCommandAfterConnection()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("", "custom-output", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, ssh);
        await viewModel.AddPasswordServerAsync("Prod", "example.internal", 22, "root", "secret");
        await viewModel.ConnectAsync();
        await viewModel.TrustPendingHostKeyAndConnectAsync();

        viewModel.CommandInput = "  whoami  ";
        await viewModel.RunCommandAsync();

        Assert.Equal(WindowsConnectionState.Connected, viewModel.ConnectionState);
        Assert.Equal("custom-output", viewModel.CommandOutput);
        Assert.Equal("Command succeeded.", viewModel.StatusMessage);
        Assert.Equal(["whoami"], viewModel.RecentCommands.ToArray());
    }

    [Fact]
    public async Task MainWindowViewModelRejectsBlankCustomCommand()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("", "custom-output", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, ssh);
        await viewModel.AddPasswordServerAsync("Prod", "example.internal", 22, "root", "secret");
        await viewModel.ConnectAsync();
        await viewModel.TrustPendingHostKeyAndConnectAsync();

        viewModel.CommandInput = "   ";
        await viewModel.RunCommandAsync();

        Assert.Equal(WindowsConnectionState.Connected, viewModel.ConnectionState);
        Assert.Equal("Command is required.", viewModel.ErrorMessage);
        Assert.Equal("Could not run command.", viewModel.StatusMessage);
        Assert.Empty(viewModel.RecentCommands);
    }

    [Fact]
    public async Task MainWindowViewModelSelectsRecentCommandWithoutRunningIt()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("", "custom-output", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, ssh);
        await viewModel.AddPasswordServerAsync("Prod", "example.internal", 22, "root", "secret");
        await viewModel.ConnectAsync();
        await viewModel.TrustPendingHostKeyAndConnectAsync();

        viewModel.CommandInput = "whoami";
        await viewModel.RunCommandAsync();
        var outputAfterRun = viewModel.CommandOutput;
        viewModel.CommandInput = "uptime";

        viewModel.SelectRecentCommand("  whoami  ");

        Assert.Equal("whoami", viewModel.CommandInput);
        Assert.Equal(outputAfterRun, viewModel.CommandOutput);
        Assert.Equal("Ready to rerun: whoami", viewModel.StatusMessage);
        Assert.True(viewModel.HasRecentCommands);
        Assert.False(viewModel.HasNoRecentCommands);
    }

    [Fact]
    public async Task MainWindowViewModelRecentCommandsDeduplicateAndKeepTenItems()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("", "custom-output", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, ssh);
        await viewModel.AddPasswordServerAsync("Prod", "example.internal", 22, "root", "secret");
        await viewModel.ConnectAsync();
        await viewModel.TrustPendingHostKeyAndConnectAsync();

        for (var index = 0; index < 11; index++)
        {
            viewModel.CommandInput = $"cmd-{index}";
            await viewModel.RunCommandAsync();
        }
        viewModel.CommandInput = "cmd-4";
        await viewModel.RunCommandAsync();

        Assert.Equal(10, viewModel.RecentCommands.Count);
        Assert.Equal("cmd-4", viewModel.RecentCommands[0]);
        Assert.Equal(1, viewModel.RecentCommands.Count(command => command == "cmd-4"));
        Assert.DoesNotContain("cmd-0", viewModel.RecentCommands);
        Assert.True(viewModel.HasRecentCommands);
        Assert.False(viewModel.HasNoRecentCommands);
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
    public async Task MainWindowViewModelFiltersServerListAndKeepsWorkspaceSelection()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new FakeWindowsSshClient(
            new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA"),
            new CommandResult("printf hhc-ssh-ok", "hhc-ssh-ok", "", 0, TimeSpan.FromMilliseconds(4)));
        var viewModel = new MainWindowViewModel(repository, service, ssh);

        await viewModel.AddPasswordServerAsync("Production API", "api.prod.example.internal", 22, "deploy", "secret", "prod");
        var selected = viewModel.SelectedServer;
        await viewModel.AddPasswordServerAsync("Staging Worker", "worker.stage.example.internal", 2222, "ubuntu", "secret", "stage");

        Assert.Equal(2, viewModel.Servers.Count);
        Assert.Equal(2, viewModel.VisibleServers.Count);
        Assert.False(viewModel.IsServerListEmpty);

        viewModel.ServerSearchText = "api";
        Assert.Equal(["Production API"], viewModel.VisibleServers.Select(server => server.Name).ToArray());

        viewModel.ServerSearchText = "ubuntu";
        Assert.Equal(["Staging Worker"], viewModel.VisibleServers.Select(server => server.Name).ToArray());

        viewModel.ServerSearchText = "prod";
        Assert.Equal(["Production API"], viewModel.VisibleServers.Select(server => server.Name).ToArray());

        viewModel.SelectedServer = selected;
        viewModel.ServerSearchText = "missing";

        Assert.Empty(viewModel.VisibleServers);
        Assert.True(viewModel.IsServerListEmpty);
        Assert.Equal("No matching servers", viewModel.ServerListEmptyTitle);
        Assert.Equal("Adjust the search text or clear the filter.", viewModel.ServerListEmptyMessage);
        Assert.Same(selected, viewModel.SelectedServer);
        Assert.Null(viewModel.SelectedVisibleServer);

        viewModel.SelectedVisibleServer = null;
        Assert.Same(selected, viewModel.SelectedServer);

        viewModel.ServerSearchText = "";
        Assert.Equal(2, viewModel.VisibleServers.Count);
        Assert.Same(selected, viewModel.SelectedVisibleServer);
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

    [Fact]
    public async Task MainWindowViewModelDisconnectCancelsRunningHostKeyScan()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var ssh = new BlockingWindowsSshClient(blockScan: true);
        var viewModel = new MainWindowViewModel(repository, service, ssh);
        await viewModel.AddPasswordServerAsync("Prod", "example.internal", 22, "root", "secret");

        var connectTask = viewModel.ConnectAsync();
        await ssh.ScanStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Equal(WindowsConnectionState.CheckingHostKey, viewModel.ConnectionState);
        Assert.True(viewModel.CanDisconnect);

        viewModel.Disconnect();
        await connectTask.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.True(ssh.ScanCancellationObserved);
        Assert.Equal(WindowsConnectionState.Disconnected, viewModel.ConnectionState);
        Assert.Equal("Operation cancelled.", viewModel.StatusMessage);
        Assert.Null(viewModel.ErrorMessage);
    }

    [Fact]
    public async Task MainWindowViewModelDisconnectCancelsRunningSmokeTestAndCanReconnect()
    {
        await using var hostKeys = new SqliteHostKeyTrustStore("Data Source=:memory:");
        await using var repository = new SqliteServerRepository("Data Source=:memory:");
        var credentials = new InMemoryCredentialStore();
        var service = new ServerManagementService(repository, hostKeys, credentials);
        var hostKey = new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA");
        var profile = await service.AddServerAsync(
            "Prod",
            "example.internal",
            22,
            "root",
            SshAuthType.Password,
            null,
            new CredentialInput.Password("secret"));
        await service.TrustHostKeyAsync(profile, hostKey);
        var ssh = new BlockingWindowsSshClient(blockExecute: true, hostKey: hostKey);
        var viewModel = new MainWindowViewModel(repository, service, ssh);
        await viewModel.LoadServersAsync();
        await viewModel.ConnectAsync();

        var smokeTask = viewModel.RunSmokeTestAsync();
        await ssh.ExecuteStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.Equal(WindowsConnectionState.RunningSmokeTest, viewModel.ConnectionState);
        Assert.True(viewModel.CanDisconnect);

        viewModel.Disconnect();
        await smokeTask.WaitAsync(TimeSpan.FromSeconds(2));

        Assert.True(ssh.ExecuteCancellationObserved);
        Assert.Equal(WindowsConnectionState.Disconnected, viewModel.ConnectionState);
        Assert.Equal("Operation cancelled.", viewModel.StatusMessage);
        Assert.Null(viewModel.ErrorMessage);

        ssh.BlockExecute = false;
        await viewModel.ConnectAsync();
        await viewModel.RunSmokeTestAsync();

        Assert.Equal(WindowsConnectionState.Connected, viewModel.ConnectionState);
        Assert.Equal("hhc-ssh-ok", viewModel.CommandOutput);
    }

    [Fact]
    public async Task RealWindowsSshSmokeTestWhenEnvironmentIsConfigured()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var config = WindowsSshIntegrationConfig.TryLoad();
        if (config is null)
        {
            return;
        }

        var databasePath = Path.Combine(Path.GetTempPath(), $"hhc-windows-real-ssh-{Guid.NewGuid():N}.sqlite");
        var connectionString = $"Data Source={databasePath};Pooling=False";
        var credentialPrefix = $"HHCServerManager.Windows.Tests/{Guid.NewGuid():N}";

        try
        {
            await using var hostKeys = new SqliteHostKeyTrustStore(connectionString);
            await using var repository = new SqliteServerRepository(connectionString);
            var credentials = new WindowsCredentialStore(credentialPrefix);
            var service = new ServerManagementService(repository, hostKeys, credentials);
            var ssh = new SshNetClient();
            var viewModel = new MainWindowViewModel(repository, service, ssh);

            if (config.Credential is CredentialInput.Password password)
            {
                await viewModel.AddPasswordServerAsync(
                    "Windows Real SSH",
                    config.Host,
                    config.Port,
                    config.Username,
                    password.Value,
                    "integration");
            }
            else if (config.Credential is CredentialInput.PrivateKey privateKey)
            {
                await viewModel.AddPrivateKeyServerAsync(
                    "Windows Real SSH",
                    config.Host,
                    config.Port,
                    config.Username,
                    System.Text.Encoding.UTF8.GetString(privateKey.Data),
                    privateKey.Passphrase,
                    "integration");
            }

            var profile = Assert.Single(viewModel.Servers);
            Assert.Equal("Windows Real SSH", profile.Name);
            Assert.NotNull(await credentials.ReadAsync(profile.CredentialRef));

            await viewModel.ConnectAsync();
            Assert.Equal(WindowsConnectionState.AwaitingHostKeyTrust, viewModel.ConnectionState);
            Assert.True(viewModel.CanConfirmHostKey);
            Assert.Contains("SHA256:", viewModel.HostKeyTrustMessage);

            await viewModel.TrustPendingHostKeyAndConnectAsync();
            await viewModel.RunSmokeTestAsync();

            Assert.Equal(WindowsConnectionState.Connected, viewModel.ConnectionState);
            Assert.Equal("hhc-ssh-ok", viewModel.CommandOutput);
            Assert.Equal("Smoke test succeeded.", viewModel.StatusMessage);
            Assert.NotNull(await hostKeys.FindAsync(profile.Id, profile.Endpoint));

            await viewModel.DeleteSelectedServerAsync();
            Assert.Null(await repository.FindAsync(profile.Id));
            Assert.Null(await hostKeys.FindAsync(profile.Id, profile.Endpoint));
            Assert.Null(await credentials.ReadAsync(profile.CredentialRef));
        }
        finally
        {
            if (File.Exists(databasePath))
            {
                File.Delete(databasePath);
            }
        }
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

    private sealed class BlockingWindowsSshClient : IWindowsSshClient
    {
        private readonly SshHostKey _hostKey;
        private readonly CommandResult _result;

        public BlockingWindowsSshClient(
            bool blockScan = false,
            bool blockExecute = false,
            SshHostKey? hostKey = null,
            CommandResult? result = null)
        {
            BlockScan = blockScan;
            BlockExecute = blockExecute;
            _hostKey = hostKey ?? new SshHostKey("ssh-ed25519", "SHA256:first", "ssh-ed25519 AAAA");
            _result = result ?? new CommandResult("printf hhc-ssh-ok", "hhc-ssh-ok", "", 0, TimeSpan.FromMilliseconds(4));
        }

        public bool BlockScan { get; set; }

        public bool BlockExecute { get; set; }

        public bool ScanCancellationObserved { get; private set; }

        public bool ExecuteCancellationObserved { get; private set; }

        public TaskCompletionSource ScanStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource ExecuteStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public async Task<SshHostKey> ScanHostKeyAsync(
            ServerProfile profile,
            CredentialInput credential,
            CancellationToken cancellationToken = default)
        {
            ScanStarted.TrySetResult();
            if (!BlockScan)
            {
                return _hostKey;
            }

            try
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                ScanCancellationObserved = true;
                throw;
            }

            return _hostKey;
        }

        public async Task<CommandResult> ExecuteAsync(
            ServerProfile profile,
            CredentialInput credential,
            string command,
            CancellationToken cancellationToken = default)
        {
            ExecuteStarted.TrySetResult();
            if (!BlockExecute)
            {
                return _result with { Command = command };
            }

            try
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                ExecuteCancellationObserved = true;
                throw;
            }

            return _result with { Command = command };
        }
    }

    private sealed record WindowsSshIntegrationConfig(
        string Host,
        int Port,
        string Username,
        CredentialInput Credential)
    {
        public static WindowsSshIntegrationConfig? TryLoad()
        {
            if (!IsEnabled("HHC_WINDOWS_TEST_SSH_REAL"))
            {
                return null;
            }

            var host = Environment.GetEnvironmentVariable("HHC_WINDOWS_TEST_SSH_HOST");
            var username = Environment.GetEnvironmentVariable("HHC_WINDOWS_TEST_SSH_USER");
            if (string.IsNullOrWhiteSpace(host) || string.IsNullOrWhiteSpace(username))
            {
                return null;
            }

            var portText = Environment.GetEnvironmentVariable("HHC_WINDOWS_TEST_SSH_PORT");
            var port = int.TryParse(portText, out var parsedPort) ? parsedPort : 22;
            if (port is < 1 or > 65535)
            {
                return null;
            }

            var password = Environment.GetEnvironmentVariable("HHC_WINDOWS_TEST_SSH_PASSWORD");
            if (!string.IsNullOrEmpty(password))
            {
                return new WindowsSshIntegrationConfig(
                    host.Trim(),
                    port,
                    username.Trim(),
                    new CredentialInput.Password(password));
            }

            var privateKeyPath = Environment.GetEnvironmentVariable("HHC_WINDOWS_TEST_SSH_PRIVATE_KEY");
            if (string.IsNullOrWhiteSpace(privateKeyPath) || !File.Exists(privateKeyPath))
            {
                return null;
            }

            var privateKey = File.ReadAllBytes(privateKeyPath);
            var passphrase = Environment.GetEnvironmentVariable("HHC_WINDOWS_TEST_SSH_PASSPHRASE");
            return new WindowsSshIntegrationConfig(
                host.Trim(),
                port,
                username.Trim(),
                new CredentialInput.PrivateKey(privateKey, string.IsNullOrEmpty(passphrase) ? null : passphrase));
        }

        private static bool IsEnabled(string name)
        {
            var value = Environment.GetEnvironmentVariable(name);
            return string.Equals(value, "1", StringComparison.OrdinalIgnoreCase)
                || string.Equals(value, "true", StringComparison.OrdinalIgnoreCase)
                || string.Equals(value, "yes", StringComparison.OrdinalIgnoreCase);
        }
    }
}
