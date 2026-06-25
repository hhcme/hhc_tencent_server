using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Application.ServerManagement;
using HHCServerManager.Windows.Application.Shell;
using HHCServerManager.Windows.Infrastructure.Credentials;
using HHCServerManager.Windows.Infrastructure.Ssh;
using HHCServerManager.Windows.Infrastructure.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;

namespace HHCServerManager.Windows.App;

public partial class App : Application
{
    private Window? window;
    private ServiceProvider? services;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        services = ConfigureServices();
        window = new MainWindow(services.GetRequiredService<MainWindowViewModel>());
        window.Activate();
    }

    private static ServiceProvider ConfigureServices()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var dataDirectory = Path.Combine(appData, "HHCServerManager");
        Directory.CreateDirectory(dataDirectory);
        var connectionString = $"Data Source={Path.Combine(dataDirectory, "hhc-server-manager-windows.sqlite")}";

        return new ServiceCollection()
            .AddSingleton<IServerProfileRepository>(_ => new SqliteServerRepository(connectionString))
            .AddSingleton<IHostKeyTrustStore>(_ => new SqliteHostKeyTrustStore(connectionString))
            .AddSingleton<ICredentialStore, WindowsCredentialStore>()
            .AddSingleton<IWindowsSshClient, SshNetClient>()
            .AddSingleton<ServerManagementService>()
            .AddTransient<MainWindowViewModel>()
            .BuildServiceProvider();
    }
}
