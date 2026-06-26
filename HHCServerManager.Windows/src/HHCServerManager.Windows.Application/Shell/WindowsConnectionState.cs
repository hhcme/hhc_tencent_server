namespace HHCServerManager.Windows.Application.Shell;

public enum WindowsConnectionState
{
    Disconnected,
    CheckingHostKey,
    AwaitingHostKeyTrust,
    Connected,
    RunningSmokeTest,
    RunningCommand,
    Failed
}
