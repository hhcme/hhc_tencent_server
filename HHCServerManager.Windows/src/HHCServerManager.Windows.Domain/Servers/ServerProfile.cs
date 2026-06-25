namespace HHCServerManager.Windows.Domain.Servers;

public enum SshAuthType
{
    Password,
    PrivateKey
}

public sealed record ServerProfile(
    Guid Id,
    string Name,
    string Host,
    int Port,
    string Username,
    SshAuthType AuthType,
    string CredentialRef,
    string? GroupName,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt)
{
    public static ServerProfile Create(
        string name,
        string host,
        int port,
        string username,
        SshAuthType authType,
        string? groupName,
        TimeProvider? timeProvider = null)
    {
        var now = (timeProvider ?? TimeProvider.System).GetUtcNow();
        return new ServerProfile(
            Guid.NewGuid(),
            Required(name, nameof(name)),
            Required(host, nameof(host)),
            ValidatePort(port),
            Required(username, nameof(username)),
            authType,
            $"server_{Guid.NewGuid():N}",
            BlankToNull(groupName),
            now,
            now);
    }

    public ServerProfile Rename(string name, string? groupName, TimeProvider? timeProvider = null) =>
        this with
        {
            Name = Required(name, nameof(name)),
            GroupName = BlankToNull(groupName),
            UpdatedAt = (timeProvider ?? TimeProvider.System).GetUtcNow()
        };

    public ServerProfile Update(
        string name,
        string host,
        int port,
        string username,
        SshAuthType authType,
        string? groupName,
        TimeProvider? timeProvider = null) =>
        this with
        {
            Name = Required(name, nameof(name)),
            Host = Required(host, nameof(host)),
            Port = ValidatePort(port),
            Username = Required(username, nameof(username)),
            AuthType = authType,
            GroupName = BlankToNull(groupName),
            UpdatedAt = (timeProvider ?? TimeProvider.System).GetUtcNow()
        };

    public ServerEndpoint Endpoint => new(Host, Port);

    private static string Required(string value, string name)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            throw new ArgumentException($"{name} is required.", name);
        }
        return trimmed;
    }

    private static int ValidatePort(int port)
    {
        if (port is < 1 or > 65535)
        {
            throw new ArgumentOutOfRangeException(nameof(port), "Port must be between 1 and 65535.");
        }
        return port;
    }

    private static string? BlankToNull(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrEmpty(trimmed) ? null : trimmed;
    }
}

public sealed record ServerEndpoint(string Host, int Port);
