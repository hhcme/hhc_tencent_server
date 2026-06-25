namespace HHCServerManager.Windows.Domain.Ssh;

public sealed record SshHostKey(string Algorithm, string FingerprintSha256, string? RawPublicKey);
