namespace HHCServerManager.Windows.Domain.Ssh;

public sealed record CommandResult(
    string Command,
    string Stdout,
    string Stderr,
    int ExitCode,
    TimeSpan Duration)
{
    public bool Succeeded => ExitCode == 0;
}
