using HHCServerManager.Windows.Domain.Servers;

namespace HHCServerManager.Windows.Domain.Security;

public sealed record TrustedHostKey(
    Guid Id,
    Guid ServerId,
    string Host,
    int Port,
    string Algorithm,
    string FingerprintSha256,
    string? RawPublicKey,
    DateTimeOffset TrustedAt)
{
    public static TrustedHostKey Trust(
        Guid serverId,
        ServerEndpoint endpoint,
        string algorithm,
        string fingerprintSha256,
        string? rawPublicKey,
        TimeProvider? timeProvider = null) =>
        new(
            Guid.NewGuid(),
            serverId,
            endpoint.Host,
            endpoint.Port,
            Required(algorithm, nameof(algorithm)),
            Required(fingerprintSha256, nameof(fingerprintSha256)),
            string.IsNullOrWhiteSpace(rawPublicKey) ? null : rawPublicKey.Trim(),
            (timeProvider ?? TimeProvider.System).GetUtcNow());

    private static string Required(string value, string name)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            throw new ArgumentException($"{name} is required.", name);
        }
        return trimmed;
    }
}

public enum HostKeyTrustDecision
{
    Trusted,
    Unknown,
    Mismatch
}

public sealed record HostKeyCheckResult(HostKeyTrustDecision Decision, TrustedHostKey? TrustedKey);
