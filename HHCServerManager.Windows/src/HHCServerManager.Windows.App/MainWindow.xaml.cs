using HHCServerManager.Windows.Application.Shell;
using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace HHCServerManager.Windows.App;

public sealed partial class MainWindow : Window
{
    public MainWindowViewModel ViewModel { get; }

    public MainWindow(MainWindowViewModel viewModel)
    {
        ViewModel = viewModel;
        InitializeComponent();
        _ = ViewModel.LoadServersAsync();
    }

    private async void AddServer_Click(object sender, RoutedEventArgs e)
    {
        var form = CreateServerForm(null);
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Add server",
            Content = form.Content,
            PrimaryButtonText = "Add",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            if (form.AuthType == SshAuthType.PrivateKey)
            {
                await ViewModel.AddPrivateKeyServerAsync(
                    form.Name,
                    form.Host,
                    form.Port,
                    form.Username,
                    form.PrivateKey,
                    form.Passphrase,
                    form.GroupName);
            }
            else
            {
                await ViewModel.AddPasswordServerAsync(
                    form.Name,
                    form.Host,
                    form.Port,
                    form.Username,
                    form.Password,
                    form.GroupName);
            }
        }
    }

    private async void EditServer_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectedServer is null)
        {
            return;
        }

        var form = CreateServerForm(ViewModel.SelectedServer);
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Edit server",
            Content = form.Content,
            PrimaryButtonText = "Save",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            var replacement = form.ReplacementCredential(ViewModel.SelectedServer.AuthType);
            await ViewModel.UpdateSelectedServerAsync(
                form.Name,
                form.Host,
                form.Port,
                form.Username,
                form.AuthType,
                form.GroupName,
                replacement);
        }
    }

    private ServerForm CreateServerForm(ServerProfile? profile)
    {
        var nameBox = new TextBox { PlaceholderText = "Production API", Text = profile?.Name ?? "" };
        var hostBox = new TextBox { PlaceholderText = "server.example.com", Text = profile?.Host ?? "" };
        var portBox = new NumberBox { Value = profile?.Port ?? 22, Minimum = 1, Maximum = 65535 };
        var usernameBox = new TextBox { PlaceholderText = "root", Text = profile?.Username ?? "" };
        var groupBox = new TextBox { PlaceholderText = "ops", Text = profile?.GroupName ?? "" };
        var authBox = new ComboBox { SelectedIndex = profile?.AuthType == SshAuthType.PrivateKey ? 1 : 0 };
        authBox.Items.Add("Password");
        authBox.Items.Add("Private key");
        var passwordBox = new PasswordBox { PlaceholderText = profile is null ? "Password" : "Leave blank to keep existing credential" };
        var privateKeyBox = new TextBox
        {
            PlaceholderText = profile is null ? "-----BEGIN OPENSSH PRIVATE KEY-----" : "Leave blank to keep existing private key",
            AcceptsReturn = true,
            MinHeight = 140,
            TextWrapping = TextWrapping.NoWrap
        };
        var passphraseBox = new PasswordBox { PlaceholderText = "Passphrase (optional)" };

        void UpdateCredentialVisibility()
        {
            var usePrivateKey = authBox.SelectedIndex == 1;
            passwordBox.Visibility = usePrivateKey ? Visibility.Collapsed : Visibility.Visible;
            privateKeyBox.Visibility = usePrivateKey ? Visibility.Visible : Visibility.Collapsed;
            passphraseBox.Visibility = usePrivateKey ? Visibility.Visible : Visibility.Collapsed;
        }
        authBox.SelectionChanged += (_, _) => UpdateCredentialVisibility();
        UpdateCredentialVisibility();

        var content = new StackPanel { Spacing = 10 };
        content.Children.Add(new TextBlock { Text = "Name" });
        content.Children.Add(nameBox);
        content.Children.Add(new TextBlock { Text = "Host" });
        content.Children.Add(hostBox);
        content.Children.Add(new TextBlock { Text = "Port" });
        content.Children.Add(portBox);
        content.Children.Add(new TextBlock { Text = "Username" });
        content.Children.Add(usernameBox);
        content.Children.Add(new TextBlock { Text = "Group" });
        content.Children.Add(groupBox);
        content.Children.Add(new TextBlock { Text = "Authentication" });
        content.Children.Add(authBox);
        content.Children.Add(new TextBlock { Text = "Password or private key" });
        content.Children.Add(passwordBox);
        content.Children.Add(privateKeyBox);
        content.Children.Add(passphraseBox);
        return new ServerForm(content, nameBox, hostBox, portBox, usernameBox, groupBox, authBox, passwordBox, privateKeyBox, passphraseBox);
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await ViewModel.LoadServersAsync();

    private async void ImportKnownHosts_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectedServer is null)
        {
            return;
        }

        var knownHostsBox = new TextBox
        {
            AcceptsReturn = true,
            MinHeight = 220,
            PlaceholderText = "Paste lines from ~/.ssh/known_hosts",
            TextWrapping = TextWrapping.NoWrap
        };
        var content = new StackPanel { Spacing = 10 };
        content.Children.Add(new TextBlock
        {
            Text = "Paste OpenSSH known_hosts entries. Only entries matching the selected host and port will be trusted.",
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(knownHostsBox);

        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Import known_hosts",
            Content = content,
            PrimaryButtonText = "Import",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await ViewModel.ImportKnownHostsForSelectedServerAsync(knownHostsBox.Text);
        }
    }

    private async void ImportKnownHostsFile_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel.SelectedServer is null)
        {
            return;
        }

        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary
        };
        picker.FileTypeFilter.Add(".txt");
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));

        var file = await picker.PickSingleFileAsync();
        if (file is not null)
        {
            await ViewModel.ImportKnownHostsFileForSelectedServerAsync(file.Path);
        }
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        await ViewModel.ConnectAsync();
        if (ViewModel.CanConfirmHostKey)
        {
            await ShowHostKeyTrustDialogAsync();
        }
    }

    private async void TrustHostKey_Click(object sender, RoutedEventArgs e) => await ViewModel.TrustPendingHostKeyAndConnectAsync();

    private void RejectHostKey_Click(object sender, RoutedEventArgs e) => ViewModel.RejectPendingHostKey();

    private async void SmokeTest_Click(object sender, RoutedEventArgs e) => await ViewModel.RunSmokeTestAsync();

    private async void RunCommand_Click(object sender, RoutedEventArgs e) => await ViewModel.RunCommandAsync();

    private void CancelCommand_Click(object sender, RoutedEventArgs e) => ViewModel.Disconnect();

    private void RecentCommand_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Content: string command })
        {
            ViewModel.SelectRecentCommand(command);
        }
    }

    private void Disconnect_Click(object sender, RoutedEventArgs e) => ViewModel.Disconnect();

    private void CopyOutput_Click(object sender, RoutedEventArgs e)
    {
        var package = new DataPackage();
        package.SetText(ViewModel.CommandOutput);
        Clipboard.SetContent(package);
    }

    private async void DeleteServer_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Delete server",
            Content = "Delete the selected server, trusted host key, and stored credential?",
            PrimaryButtonText = "Delete",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await ViewModel.DeleteSelectedServerAsync();
        }
    }

    private async Task ShowHostKeyTrustDialogAsync()
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Trust SSH host key?",
            Content = ViewModel.HostKeyTrustMessage,
            PrimaryButtonText = "Trust and continue",
            CloseButtonText = "Reject",
            DefaultButton = ContentDialogButton.Close
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            await ViewModel.TrustPendingHostKeyAndConnectAsync();
        }
        else
        {
            ViewModel.RejectPendingHostKey();
        }
    }
}

internal sealed record ServerForm(
    StackPanel Content,
    TextBox NameBox,
    TextBox HostBox,
    NumberBox PortBox,
    TextBox UsernameBox,
    TextBox GroupBox,
    ComboBox AuthBox,
    PasswordBox PasswordBox,
    TextBox PrivateKeyBox,
    PasswordBox PassphraseBox)
{
    public string Name => NameBox.Text;
    public string Host => HostBox.Text;
    public int Port => double.IsNaN(PortBox.Value) ? 22 : (int)PortBox.Value;
    public string Username => UsernameBox.Text;
    public string? GroupName => string.IsNullOrWhiteSpace(GroupBox.Text) ? null : GroupBox.Text;
    public SshAuthType AuthType => AuthBox.SelectedIndex == 1 ? SshAuthType.PrivateKey : SshAuthType.Password;
    public string Password => PasswordBox.Password;
    public string PrivateKey => PrivateKeyBox.Text;
    public string? Passphrase => string.IsNullOrWhiteSpace(PassphraseBox.Password) ? null : PassphraseBox.Password;

    public CredentialInput? ReplacementCredential(SshAuthType previousAuthType)
    {
        if (AuthType == SshAuthType.Password)
        {
            return string.IsNullOrEmpty(Password) && previousAuthType == SshAuthType.Password
                ? null
                : new CredentialInput.Password(Password);
        }

        return string.IsNullOrWhiteSpace(PrivateKey) && previousAuthType == SshAuthType.PrivateKey
            ? null
            : new CredentialInput.PrivateKey(System.Text.Encoding.UTF8.GetBytes(PrivateKey.Trim()), Passphrase);
    }
}
