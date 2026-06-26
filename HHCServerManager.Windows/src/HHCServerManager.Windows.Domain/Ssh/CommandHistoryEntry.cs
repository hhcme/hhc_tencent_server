namespace HHCServerManager.Windows.Domain.Ssh;

public sealed record CommandHistoryEntry(
    Guid Id,
    Guid ServerId,
    string Command,
    int ExitCode,
    long DurationMilliseconds,
    DateTimeOffset RanAt)
{
    public static CommandHistoryEntry FromResult(Guid serverId, CommandResult result, DateTimeOffset? ranAt = null) =>
        new(
            Guid.NewGuid(),
            serverId,
            result.Command,
            result.ExitCode,
            (long)Math.Max(0, result.Duration.TotalMilliseconds),
            ranAt ?? DateTimeOffset.UtcNow);
}
