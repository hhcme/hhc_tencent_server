using System.Security.Cryptography;
using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Domain.Security;
using HHCServerManager.Windows.Domain.Servers;

namespace HHCServerManager.Windows.Application.Security;

public sealed class OpenSshKnownHostsImporter(
    IHostKeyTrustStore hostKeys,
    TimeProvider? timeProvider = null)
{
    private readonly TimeProvider _timeProvider = timeProvider ?? TimeProvider.System;

    public async Task<KnownHostsImportResult> ImportAsync(
        string content,
        ServerProfile profile,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(content);
        ArgumentNullException.ThrowIfNull(profile);

        var importedCount = 0;
        var skippedCount = 0;

        foreach (var line in content.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n'))
        {
            var hostKey = TryParseHostKey(line, profile);
            if (hostKey is null)
            {
                if (!string.IsNullOrWhiteSpace(line))
                {
                    skippedCount++;
                }
                continue;
            }

            await hostKeys.SaveAsync(
                TrustedHostKey.Trust(
                    profile.Id,
                    profile.Endpoint,
                    hostKey.Algorithm,
                    hostKey.FingerprintSha256,
                    hostKey.RawPublicKey,
                    _timeProvider),
                cancellationToken);
            importedCount++;
        }

        return new KnownHostsImportResult(importedCount, skippedCount);
    }

    public async Task<KnownHostsImportResult> ImportFileAsync(
        string path,
        ServerProfile profile,
        CancellationToken cancellationToken = default)
    {
        await using var stream = File.OpenRead(path);
        using var reader = new StreamReader(stream);
        return await ImportAsync(await reader.ReadToEndAsync(cancellationToken), profile, cancellationToken);
    }

    public static KnownHostsImportHostKey? TryParseHostKey(string line, ServerProfile profile)
    {
        var trimmed = line.Trim();
        if (trimmed.Length == 0 ||
            trimmed.StartsWith('#') ||
            trimmed.StartsWith('@') ||
            trimmed.StartsWith('|'))
        {
            return null;
        }

        var fields = trimmed.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length < 3)
        {
            return null;
        }

        var hostPatterns = fields[0].Split(',', StringSplitOptions.RemoveEmptyEntries);
        if (!hostPatterns.Any(pattern => HostPatternMatches(pattern, profile.Endpoint)))
        {
            return null;
        }

        var algorithm = fields[1];
        var publicKey = fields[2];
        if (!algorithm.StartsWith("ssh-", StringComparison.Ordinal))
        {
            return null;
        }

        byte[] publicKeyBytes;
        try
        {
            publicKeyBytes = Convert.FromBase64String(publicKey);
        }
        catch (FormatException)
        {
            return null;
        }

        var fingerprint = Convert.ToBase64String(SHA256.HashData(publicKeyBytes)).TrimEnd('=');
        return new KnownHostsImportHostKey(
            algorithm,
            $"SHA256:{fingerprint}",
            $"{profile.Host} {algorithm} {publicKey}");
    }

    private static bool HostPatternMatches(string pattern, ServerEndpoint endpoint)
    {
        if (pattern.StartsWith('!'))
        {
            return false;
        }

        if (pattern.StartsWith('['))
        {
            return string.Equals(pattern, $"[{endpoint.Host}]:{endpoint.Port}", StringComparison.Ordinal);
        }

        return endpoint.Port == 22 && string.Equals(pattern, endpoint.Host, StringComparison.Ordinal);
    }
}

public sealed record KnownHostsImportResult(int ImportedCount, int SkippedCount);

public sealed record KnownHostsImportHostKey(string Algorithm, string FingerprintSha256, string RawPublicKey);
