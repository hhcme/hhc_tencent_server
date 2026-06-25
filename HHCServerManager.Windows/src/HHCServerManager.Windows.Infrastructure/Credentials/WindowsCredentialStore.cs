using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Domain.Ssh;

namespace HHCServerManager.Windows.Infrastructure.Credentials;

public sealed class WindowsCredentialStore(string targetPrefix = "HHCServerManager.Windows") : ICredentialStore
{
    public Task SaveAsync(string credentialRef, CredentialInput credential, CancellationToken cancellationToken = default)
    {
        EnsureWindows();
        cancellationToken.ThrowIfCancellationRequested();

        var payload = JsonSerializer.SerializeToUtf8Bytes(CredentialPayload.From(credential));
        if (payload.Length > 5120)
        {
            throw new InvalidOperationException("Windows Credential Manager generic credentials cannot exceed 5120 bytes.");
        }

        var credentialBlob = Marshal.AllocHGlobal(payload.Length);
        try
        {
            Marshal.Copy(payload, 0, credentialBlob, payload.Length);
            var native = new NativeCredential
            {
                Type = CredentialType.Generic,
                TargetName = TargetName(credentialRef),
                CredentialBlob = credentialBlob,
                CredentialBlobSize = (uint)payload.Length,
                Persist = CredentialPersist.LocalMachine,
                UserName = Environment.UserName
            };
            if (!CredWrite(ref native, 0))
            {
                throw new InvalidOperationException($"CredWrite failed with Win32 error {Marshal.GetLastWin32Error()}.");
            }
        }
        finally
        {
            CryptographicOperationsShim.ZeroMemory(payload);
            Marshal.FreeHGlobal(credentialBlob);
        }

        return Task.CompletedTask;
    }

    public Task<CredentialInput?> ReadAsync(string credentialRef, CancellationToken cancellationToken = default)
    {
        EnsureWindows();
        cancellationToken.ThrowIfCancellationRequested();

        if (!CredRead(TargetName(credentialRef), CredentialType.Generic, 0, out var credentialPtr))
        {
            var error = Marshal.GetLastWin32Error();
            if (error == ErrorNotFound)
            {
                return Task.FromResult<CredentialInput?>(null);
            }
            throw new InvalidOperationException($"CredRead failed with Win32 error {error}.");
        }

        try
        {
            var native = Marshal.PtrToStructure<NativeCredential>(credentialPtr);
            var payload = new byte[native.CredentialBlobSize];
            Marshal.Copy(native.CredentialBlob, payload, 0, payload.Length);
            var decoded = JsonSerializer.Deserialize<CredentialPayload>(payload)
                ?? throw new InvalidOperationException("Credential payload is invalid.");
            return Task.FromResult<CredentialInput?>(decoded.ToCredential());
        }
        finally
        {
            CredFree(credentialPtr);
        }
    }

    public Task DeleteAsync(string credentialRef, CancellationToken cancellationToken = default)
    {
        EnsureWindows();
        cancellationToken.ThrowIfCancellationRequested();

        if (!CredDelete(TargetName(credentialRef), CredentialType.Generic, 0))
        {
            var error = Marshal.GetLastWin32Error();
            if (error != ErrorNotFound)
            {
                throw new InvalidOperationException($"CredDelete failed with Win32 error {error}.");
            }
        }
        return Task.CompletedTask;
    }

    private string TargetName(string credentialRef) => $"{targetPrefix}/{credentialRef}";

    private static void EnsureWindows()
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            throw new PlatformNotSupportedException("Windows Credential Manager is only available on Windows.");
        }
    }

    private sealed record CredentialPayload(string Kind, string? Password, string? PrivateKeyBase64, string? Passphrase)
    {
        public static CredentialPayload From(CredentialInput credential) =>
            credential switch
            {
                CredentialInput.Password password => new("password", password.Value, null, null),
                CredentialInput.PrivateKey privateKey => new("privateKey", null, Convert.ToBase64String(privateKey.Data), privateKey.Passphrase),
                _ => throw new ArgumentOutOfRangeException(nameof(credential))
            };

        public CredentialInput ToCredential() =>
            Kind switch
            {
                "password" when Password is not null => new CredentialInput.Password(Password),
                "privateKey" when PrivateKeyBase64 is not null => new CredentialInput.PrivateKey(Convert.FromBase64String(PrivateKeyBase64), Passphrase),
                _ => throw new InvalidOperationException("Credential payload kind is invalid.")
            };
    }

    private const int ErrorNotFound = 1168;

    private enum CredentialType : uint
    {
        Generic = 1
    }

    private enum CredentialPersist : uint
    {
        LocalMachine = 2
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeCredential
    {
        public uint Flags;
        public CredentialType Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public CredentialPersist Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref NativeCredential userCredential, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, CredentialType type, uint reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, CredentialType type, uint flags);

    [DllImport("advapi32.dll", SetLastError = false)]
    private static extern void CredFree(IntPtr buffer);
}

internal static class CryptographicOperationsShim
{
    public static void ZeroMemory(byte[] buffer)
    {
        Array.Clear(buffer, 0, buffer.Length);
    }
}
