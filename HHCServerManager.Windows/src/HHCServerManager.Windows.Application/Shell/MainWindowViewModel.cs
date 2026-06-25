using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Application.ServerManagement;
using HHCServerManager.Windows.Domain.Security;
using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;

namespace HHCServerManager.Windows.Application.Shell;

public sealed class MainWindowViewModel : INotifyPropertyChanged
{
    private readonly IServerProfileRepository _profiles;
    private readonly ServerManagementService _serverManagement;
    private readonly IWindowsSshClient _sshClient;
    private ServerProfile? _selectedServer;
    private WindowsConnectionState _connectionState = WindowsConnectionState.Disconnected;
    private PendingHostKeyTrust? _pendingHostKeyTrust;
    private string _statusMessage = "Select a server to connect.";
    private string _commandOutput = "Command output will appear here after connection.";
    private string _serverSearchText = string.Empty;
    private ServerProfile? _selectedVisibleServer;
    private string? _errorMessage;

    public MainWindowViewModel(
        IServerProfileRepository profiles,
        ServerManagementService serverManagement,
        IWindowsSshClient sshClient)
    {
        _profiles = profiles;
        _serverManagement = serverManagement;
        _sshClient = sshClient;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<ServerProfile> Servers { get; } = [];

    public ObservableCollection<ServerProfile> VisibleServers { get; } = [];

    public string ServerSearchText
    {
        get => _serverSearchText;
        set
        {
            if (SetProperty(ref _serverSearchText, value))
            {
                RefreshVisibleServers();
            }
        }
    }

    public ServerProfile? SelectedVisibleServer
    {
        get => _selectedVisibleServer;
        set
        {
            if (SetProperty(ref _selectedVisibleServer, value) && value is not null)
            {
                SelectedServer = value;
            }
        }
    }

    public ServerProfile? SelectedServer
    {
        get => _selectedServer;
        set
        {
            if (SetProperty(ref _selectedServer, value))
            {
                SyncSelectedVisibleServer();
                Disconnect();
                StatusMessage = value is null ? "Select a server to connect." : $"Ready: {value.Username}@{value.Host}:{value.Port}";
                CommandOutput = "Command output will appear here after connection.";
                OnPropertyChanged(nameof(SelectedServerTitle));
                OnPropertyChanged(nameof(SelectedServerSubtitle));
                OnPropertyChanged(nameof(CanConnect));
                OnPropertyChanged(nameof(CanRunSmokeTest));
            }
        }
    }

    public string SelectedServerTitle => SelectedServer?.Name ?? "No server selected";

    public string SelectedServerSubtitle =>
        SelectedServer is null
            ? "Add or select a server to begin."
            : $"{SelectedServer.Username}@{SelectedServer.Host}:{SelectedServer.Port} · {ConnectionState}";

    public WindowsConnectionState ConnectionState
    {
        get => _connectionState;
        private set
        {
            if (SetProperty(ref _connectionState, value))
            {
                OnPropertyChanged(nameof(SelectedServerSubtitle));
                OnPropertyChanged(nameof(CanConnect));
                OnPropertyChanged(nameof(CanRunSmokeTest));
                OnPropertyChanged(nameof(CanConfirmHostKey));
                OnPropertyChanged(nameof(CanDisconnect));
                OnPropertyChanged(nameof(IsBusy));
            }
        }
    }

    public PendingHostKeyTrust? PendingHostKeyTrust
    {
        get => _pendingHostKeyTrust;
        private set
        {
            if (SetProperty(ref _pendingHostKeyTrust, value))
            {
                OnPropertyChanged(nameof(CanConfirmHostKey));
                OnPropertyChanged(nameof(HostKeyTrustMessage));
            }
        }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        private set => SetProperty(ref _statusMessage, value);
    }

    public string CommandOutput
    {
        get => _commandOutput;
        private set => SetProperty(ref _commandOutput, value);
    }

    public string? ErrorMessage
    {
        get => _errorMessage;
        private set
        {
            if (SetProperty(ref _errorMessage, value))
            {
                OnPropertyChanged(nameof(HasError));
            }
        }
    }

    public bool HasError => ErrorMessage is not null;

    public bool HasVisibleServers => VisibleServers.Count > 0;

    public bool IsServerListEmpty => !HasVisibleServers;

    public string ServerListEmptyTitle => Servers.Count == 0 ? "No servers" : "No matching servers";

    public string ServerListEmptyMessage =>
        Servers.Count == 0
            ? "Add a Windows SSH server to start."
            : "Adjust the search text or clear the filter.";

    public bool IsBusy => ConnectionState is WindowsConnectionState.CheckingHostKey or WindowsConnectionState.RunningSmokeTest;

    public bool CanConnect => SelectedServer is not null && !IsBusy && ConnectionState != WindowsConnectionState.Connected;

    public bool CanRunSmokeTest => SelectedServer is not null && ConnectionState == WindowsConnectionState.Connected;

    public bool CanConfirmHostKey => PendingHostKeyTrust is not null && ConnectionState == WindowsConnectionState.AwaitingHostKeyTrust;

    public bool CanDisconnect => ConnectionState != WindowsConnectionState.Disconnected && !IsBusy;

    public string HostKeyTrustMessage
    {
        get
        {
            if (PendingHostKeyTrust is null)
            {
                return "Host key trust is required before the first connection.";
            }

            var prefix = PendingHostKeyTrust.IsMismatch
                ? "The presented host key differs from the trusted key."
                : "This is the first time connecting to this host.";
            return $"{prefix} Presented fingerprint: {PendingHostKeyTrust.PresentedKey.FingerprintSha256}";
        }
    }

    public async Task LoadServersAsync(CancellationToken cancellationToken = default)
    {
        var loaded = await _profiles.ListAsync(cancellationToken);
        Servers.Clear();
        foreach (var profile in loaded)
        {
            Servers.Add(profile);
        }

        RefreshVisibleServers();
        SelectedServer ??= Servers.FirstOrDefault();
    }

    public async Task AddPasswordServerAsync(
        string name,
        string host,
        int port,
        string username,
        string password,
        string? groupName = null,
        CancellationToken cancellationToken = default)
    {
        ErrorMessage = null;
        try
        {
            var profile = await _serverManagement.AddServerAsync(
                name,
                host,
                port,
                username,
                SshAuthType.Password,
                groupName,
                new CredentialInput.Password(password),
                cancellationToken);
            Servers.Add(profile);
            RefreshVisibleServers();
            SelectedServer = profile;
            StatusMessage = $"Added {profile.Name}.";
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            ErrorMessage = error.Message;
            StatusMessage = "Could not add server.";
        }
    }

    public async Task AddPrivateKeyServerAsync(
        string name,
        string host,
        int port,
        string username,
        string privateKey,
        string? passphrase = null,
        string? groupName = null,
        CancellationToken cancellationToken = default)
    {
        ErrorMessage = null;
        try
        {
            var profile = await _serverManagement.AddServerAsync(
                name,
                host,
                port,
                username,
                SshAuthType.PrivateKey,
                groupName,
                new CredentialInput.PrivateKey(System.Text.Encoding.UTF8.GetBytes(privateKey.Trim()), passphrase),
                cancellationToken);
            Servers.Add(profile);
            RefreshVisibleServers();
            SelectedServer = profile;
            StatusMessage = $"Added {profile.Name}.";
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            ErrorMessage = error.Message;
            StatusMessage = "Could not add server.";
        }
    }

    public async Task DeleteSelectedServerAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedServer is null)
        {
            return;
        }

        var deleted = SelectedServer;
        try
        {
            await _serverManagement.DeleteServerAsync(deleted.Id, cancellationToken);
            Servers.Remove(deleted);
            RefreshVisibleServers();
            SelectedServer = Servers.FirstOrDefault();
            StatusMessage = $"Deleted {deleted.Name}.";
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            ErrorMessage = error.Message;
            StatusMessage = "Could not delete server.";
        }
    }

    public async Task UpdateSelectedServerAsync(
        string name,
        string host,
        int port,
        string username,
        SshAuthType authType,
        string? groupName = null,
        CredentialInput? replacementCredential = null,
        CancellationToken cancellationToken = default)
    {
        if (SelectedServer is null)
        {
            ErrorMessage = "Select a server before editing.";
            return;
        }

        ErrorMessage = null;
        var previous = SelectedServer;
        try
        {
            var updated = await _serverManagement.UpdateServerAsync(
                previous.Id,
                name,
                host,
                port,
                username,
                authType,
                groupName,
                replacementCredential,
                cancellationToken);
            ReplaceServer(previous, updated);
            if (previous.Endpoint != updated.Endpoint)
            {
                Disconnect();
            }
            StatusMessage = $"Updated {updated.Name}.";
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            ErrorMessage = error.Message;
            StatusMessage = "Could not update server.";
        }
    }

    public async Task ConnectAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedServer is null)
        {
            ErrorMessage = "Select a server before connecting.";
            return;
        }

        await RunAsync(WindowsConnectionState.CheckingHostKey, async () =>
        {
            PendingHostKeyTrust = null;
            StatusMessage = $"Checking SSH host key for {SelectedServer.Host}.";
            var hostKey = await _serverManagement.ScanHostKeyAsync(SelectedServer, _sshClient, cancellationToken);
            var trust = await _serverManagement.CheckHostKeyAsync(SelectedServer, hostKey, cancellationToken);
            switch (trust.Decision)
            {
                case HostKeyTrustDecision.Trusted:
                    ConnectionState = WindowsConnectionState.Connected;
                    StatusMessage = $"Connected to {SelectedServer.Name}.";
                    break;
                case HostKeyTrustDecision.Unknown:
                case HostKeyTrustDecision.Mismatch:
                    PendingHostKeyTrust = new PendingHostKeyTrust(SelectedServer, hostKey, trust.TrustedKey);
                    ConnectionState = WindowsConnectionState.AwaitingHostKeyTrust;
                    StatusMessage = PendingHostKeyTrust.IsMismatch
                        ? "Host key mismatch. Review before continuing."
                        : "Host key trust confirmation required.";
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(trust.Decision));
            }
        }, cancellationToken);
    }

    public async Task TrustPendingHostKeyAndConnectAsync(CancellationToken cancellationToken = default)
    {
        if (PendingHostKeyTrust is null)
        {
            return;
        }

        var pending = PendingHostKeyTrust;
        try
        {
            await _serverManagement.TrustHostKeyAsync(pending.Profile, pending.PresentedKey, cancellationToken);
            PendingHostKeyTrust = null;
            ConnectionState = WindowsConnectionState.Connected;
            StatusMessage = $"Trusted host key and connected to {pending.Profile.Name}.";
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            ConnectionState = WindowsConnectionState.Failed;
            ErrorMessage = error.Message;
            StatusMessage = "Could not trust host key.";
        }
    }

    public void RejectPendingHostKey()
    {
        PendingHostKeyTrust = null;
        ConnectionState = WindowsConnectionState.Disconnected;
        StatusMessage = "Host key trust was rejected.";
    }

    public async Task RunSmokeTestAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedServer is null || ConnectionState != WindowsConnectionState.Connected)
        {
            ErrorMessage = "Connect to a server before running the smoke test.";
            return;
        }

        await RunAsync(WindowsConnectionState.RunningSmokeTest, async () =>
        {
            StatusMessage = "Running SSH smoke test.";
            var result = await _serverManagement.RunSmokeTestAsync(SelectedServer, _sshClient, cancellationToken);
            CommandOutput = string.IsNullOrEmpty(result.Stderr)
                ? result.Stdout
                : $"{result.Stdout}{Environment.NewLine}{result.Stderr}";
            ConnectionState = result.Succeeded ? WindowsConnectionState.Connected : WindowsConnectionState.Failed;
            StatusMessage = result.Succeeded ? "Smoke test succeeded." : $"Smoke test failed with exit code {result.ExitCode}.";
        }, cancellationToken);
    }

    public void Disconnect()
    {
        PendingHostKeyTrust = null;
        ConnectionState = WindowsConnectionState.Disconnected;
        ErrorMessage = null;
    }

    private void ReplaceServer(ServerProfile previous, ServerProfile updated)
    {
        var index = Servers.IndexOf(previous);
        if (index >= 0)
        {
            Servers[index] = updated;
        }
        RefreshVisibleServers();
        SelectedServer = updated;
    }

    private void RefreshVisibleServers()
    {
        var query = ServerSearchText.Trim();
        var visible = Servers.Where(profile =>
            query.Length == 0 ||
            profile.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            profile.Host.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            profile.Username.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            (profile.GroupName?.Contains(query, StringComparison.OrdinalIgnoreCase) ?? false));

        VisibleServers.Clear();
        foreach (var profile in visible)
        {
            VisibleServers.Add(profile);
        }

        OnPropertyChanged(nameof(HasVisibleServers));
        OnPropertyChanged(nameof(IsServerListEmpty));
        OnPropertyChanged(nameof(ServerListEmptyTitle));
        OnPropertyChanged(nameof(ServerListEmptyMessage));
        SyncSelectedVisibleServer();
    }

    private void SyncSelectedVisibleServer()
    {
        var visibleSelection = _selectedServer is not null && VisibleServers.Contains(_selectedServer)
            ? _selectedServer
            : null;
        if (!EqualityComparer<ServerProfile?>.Default.Equals(_selectedVisibleServer, visibleSelection))
        {
            _selectedVisibleServer = visibleSelection;
            OnPropertyChanged(nameof(SelectedVisibleServer));
        }
    }

    private async Task RunAsync(
        WindowsConnectionState busyState,
        Func<Task> operation,
        CancellationToken cancellationToken)
    {
        ErrorMessage = null;
        ConnectionState = busyState;
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            await operation();
        }
        catch (OperationCanceledException)
        {
            ConnectionState = WindowsConnectionState.Disconnected;
            StatusMessage = "Operation cancelled.";
        }
        catch (Exception error)
        {
            ConnectionState = WindowsConnectionState.Failed;
            ErrorMessage = error.Message;
            StatusMessage = "Operation failed.";
        }
    }

    private bool SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
