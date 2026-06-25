using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Domain.Security;
using HHCServerManager.Windows.Domain.Servers;
using Microsoft.Data.Sqlite;

namespace HHCServerManager.Windows.Infrastructure.Storage;

public sealed class SqliteHostKeyTrustStore : IHostKeyTrustStore, IAsyncDisposable
{
    private readonly SqliteConnection _connection;

    public SqliteHostKeyTrustStore(string connectionString)
    {
        _connection = new SqliteConnection(connectionString);
        _connection.Open();
        Migrate();
    }

    public async Task<TrustedHostKey?> FindAsync(Guid serverId, ServerEndpoint endpoint, CancellationToken cancellationToken = default)
    {
        await using var command = _connection.CreateCommand();
        command.CommandText = """
            SELECT id, server_id, host, port, algorithm, fingerprint_sha256, raw_public_key, trusted_at
            FROM trusted_host_keys
            WHERE server_id = $serverId AND host = $host AND port = $port
            """;
        command.Parameters.AddWithValue("$serverId", serverId.ToString());
        command.Parameters.AddWithValue("$host", endpoint.Host);
        command.Parameters.AddWithValue("$port", endpoint.Port);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? ReadKey(reader) : null;
    }

    public async Task SaveAsync(TrustedHostKey key, CancellationToken cancellationToken = default)
    {
        await using var command = _connection.CreateCommand();
        command.CommandText = """
            INSERT INTO trusted_host_keys (id, server_id, host, port, algorithm, fingerprint_sha256, raw_public_key, trusted_at)
            VALUES ($id, $serverId, $host, $port, $algorithm, $fingerprint, $rawPublicKey, $trustedAt)
            ON CONFLICT(server_id, host, port) DO UPDATE SET
                algorithm = excluded.algorithm,
                fingerprint_sha256 = excluded.fingerprint_sha256,
                raw_public_key = excluded.raw_public_key,
                trusted_at = excluded.trusted_at
            """;
        command.Parameters.AddWithValue("$id", key.Id.ToString());
        command.Parameters.AddWithValue("$serverId", key.ServerId.ToString());
        command.Parameters.AddWithValue("$host", key.Host);
        command.Parameters.AddWithValue("$port", key.Port);
        command.Parameters.AddWithValue("$algorithm", key.Algorithm);
        command.Parameters.AddWithValue("$fingerprint", key.FingerprintSha256);
        command.Parameters.AddWithValue("$rawPublicKey", (object?)key.RawPublicKey ?? DBNull.Value);
        command.Parameters.AddWithValue("$trustedAt", key.TrustedAt.ToString("O"));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task DeleteForServerAsync(Guid serverId, CancellationToken cancellationToken = default)
    {
        await using var command = _connection.CreateCommand();
        command.CommandText = "DELETE FROM trusted_host_keys WHERE server_id = $serverId";
        command.Parameters.AddWithValue("$serverId", serverId.ToString());
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private void Migrate()
    {
        using var command = _connection.CreateCommand();
        command.CommandText = """
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS trusted_host_keys (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT NOT NULL,
                host TEXT NOT NULL,
                port INTEGER NOT NULL,
                algorithm TEXT NOT NULL,
                fingerprint_sha256 TEXT NOT NULL,
                raw_public_key TEXT,
                trusted_at TEXT NOT NULL,
                UNIQUE(server_id, host, port)
            );
            """;
        command.ExecuteNonQuery();
    }

    private static TrustedHostKey ReadKey(SqliteDataReader reader) =>
        new(
            Guid.Parse(reader.GetString(0)),
            Guid.Parse(reader.GetString(1)),
            reader.GetString(2),
            reader.GetInt32(3),
            reader.GetString(4),
            reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            DateTimeOffset.Parse(reader.GetString(7)));

    public ValueTask DisposeAsync() => _connection.DisposeAsync();
}
