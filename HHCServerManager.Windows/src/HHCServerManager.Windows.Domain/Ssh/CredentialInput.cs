namespace HHCServerManager.Windows.Domain.Ssh;

public abstract record CredentialInput
{
    private CredentialInput() { }

    public sealed record Password : CredentialInput
    {
        public Password(string value)
        {
            Value = Require(value, nameof(value));
        }

        public string Value { get; }
    }

    public sealed record PrivateKey : CredentialInput
    {
        public PrivateKey(byte[] data, string? passphrase)
        {
            if (data.Length == 0)
            {
                throw new ArgumentException("Private key data is required.", nameof(data));
            }

            Data = data;
            Passphrase = string.IsNullOrWhiteSpace(passphrase) ? null : passphrase;
        }

        public byte[] Data { get; }

        public string? Passphrase { get; }
    }

    private static string Require(string value, string name)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException($"{name} is required.", name);
        }
        return value;
    }
}
