using HHCServerManager.Windows.Application.Shell;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;

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
        var nameBox = new TextBox { PlaceholderText = "Production API" };
        var hostBox = new TextBox { PlaceholderText = "server.example.com" };
        var portBox = new NumberBox { Value = 22, Minimum = 1, Maximum = 65535 };
        var usernameBox = new TextBox { PlaceholderText = "root" };
        var authBox = new ComboBox { SelectedIndex = 0 };
        authBox.Items.Add("Password");
        authBox.Items.Add("Private key");
        var passwordBox = new PasswordBox { PlaceholderText = "Password" };
        var privateKeyBox = new TextBox
        {
            PlaceholderText = "-----BEGIN OPENSSH PRIVATE KEY-----",
            AcceptsReturn = true,
            MinHeight = 140,
            TextWrapping = TextWrapping.NoWrap,
            Visibility = Visibility.Collapsed
        };
        var passphraseBox = new PasswordBox
        {
            PlaceholderText = "Passphrase (optional)",
            Visibility = Visibility.Collapsed
        };
        authBox.SelectionChanged += (_, _) =>
        {
            var usePrivateKey = authBox.SelectedIndex == 1;
            passwordBox.Visibility = usePrivateKey ? Visibility.Collapsed : Visibility.Visible;
            privateKeyBox.Visibility = usePrivateKey ? Visibility.Visible : Visibility.Collapsed;
            passphraseBox.Visibility = usePrivateKey ? Visibility.Visible : Visibility.Collapsed;
        };
        var content = new StackPanel { Spacing = 10 };
        content.Children.Add(new TextBlock { Text = "Name" });
        content.Children.Add(nameBox);
        content.Children.Add(new TextBlock { Text = "Host" });
        content.Children.Add(hostBox);
        content.Children.Add(new TextBlock { Text = "Port" });
        content.Children.Add(portBox);
        content.Children.Add(new TextBlock { Text = "Username" });
        content.Children.Add(usernameBox);
        content.Children.Add(new TextBlock { Text = "Authentication" });
        content.Children.Add(authBox);
        content.Children.Add(new TextBlock { Text = "Password or private key" });
        content.Children.Add(passwordBox);
        content.Children.Add(privateKeyBox);
        content.Children.Add(passphraseBox);

        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Add server",
            Content = content,
            PrimaryButtonText = "Add",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            if (authBox.SelectedIndex == 1)
            {
                await ViewModel.AddPrivateKeyServerAsync(
                    nameBox.Text,
                    hostBox.Text,
                    double.IsNaN(portBox.Value) ? 22 : (int)portBox.Value,
                    usernameBox.Text,
                    privateKeyBox.Text,
                    passphraseBox.Password);
            }
            else
            {
                await ViewModel.AddPasswordServerAsync(
                    nameBox.Text,
                    hostBox.Text,
                    double.IsNaN(portBox.Value) ? 22 : (int)portBox.Value,
                    usernameBox.Text,
                    passwordBox.Password);
            }
        }
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await ViewModel.LoadServersAsync();

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
