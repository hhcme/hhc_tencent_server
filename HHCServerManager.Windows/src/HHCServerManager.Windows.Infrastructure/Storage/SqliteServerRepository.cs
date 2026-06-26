using HHCServerManager.Windows.Application.Ports;
using HHCServerManager.Windows.Domain.Servers;
using HHCServerManager.Windows.Domain.Ssh;
using Microsoft.Data.Sqlite;

namespace HHCServerManager.Windows.Infrastructure.Storage;

public sealed class SqliteServerRepository : IServerProfileRepository, IAsyncDisposable
{
    private readonly SqliteConnection _connection;

    public SqliteServerRepository(string connectionString)
    {
        _connection = new SqliteConnection(connectionString);
        _connection.Open();
        Migrate();
    }

    public async Task<IReadOnlyList<ServerProfile>> ListAsync(CancellationToken cancellationToken = default)
    {
        var profiles = new List<ServerProfile>();
        await using var command = _connection.CreateCommand();
        command.CommandText = """
            SELECT id, name, host, port, username, auth_type, credential_ref, group_name, created_at, updated_at
            FROM server_profiles
            ORDER BY name COLLATE NOCASE ASC
            """;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            profiles.Add(ReadProfile(reader));
        }
        return profiles;
    }

    public async Task<ServerProfile?> FindAsync(Guid id, CancellationToken cancellationToken = default)
    {
        await using var command = _connection.CreateCommand();
        command.CommandText = """
            SELECT id, name, host, port, username, auth_type, credential_ref, group_name, created_at, updated_at
            FROM server_profiles
            WHERE id = $id
            """;
        command.Parameters.AddWithValue("$id", id.ToString());
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? ReadProfile(reader) : null;
    }

    public async Task UpsertAsync(ServerProfile profile, CancellationToken cancellationToken = default)
    {
        await using var command = _connection.CreateCommand();
        command.CommandText = """
            INSERT INTO server_profiles (id, name, host, port, username, auth_type, credential_ref, group_name, created_at, updated_at)
            VALUES ($id, $name, $host, $port, $username, $authType, $credentialRef, $groupName, $createdAt, $updatedAt)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                host = excluded.host,
                port = excluded.port,
                username = excluded.username,
                auth_type = excluded.auth_type,
                credential_ref = excluded.credential_ref,
                group_name = excluded.group_name,
                updated_at = excluded.updated_at
            """;
        BindProfile(command, profile);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task DeleteAsync(Guid id, CancellationToken cancellationToken = default)
    {
        await using var command = _connection.CreateCommand();
        command.CommandText = "DELETE FROM server_profiles WHERE id = $id";
        command.Parameters.AddWithValue("$id", id.ToString());
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<CommandHistoryEntry>> ListRecentCommandHistoryAsync(
        Guid serverId,
        int limit = 10,
        CancellationToken cancellationToken = default)
    {
        var history = new List<CommandHistoryEntry>();
        await using var command = _connection.CreateCommand();
        command.CommandText = """
            SELECT id, server_id, command, exit_code, duration_ms, ran_at
            FROM command_history
            WHERE server_id = $serverId
            ORDER BY ran_at DESC, rowid DESC
            LIMIT $limit
            """;
        command.Parameters.AddWithValue("$serverId", serverId.ToString());
        command.Parameters.AddWithValue("$limit", Math.Max(1, limit));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            history.Add(ReadCommandHistory(reader));
        }
        return history;
    }

    public async Task SaveCommandHistoryAsync(CommandHistoryEntry entry, CancellationToken cancellationToken = default)
    {
        await using var command = _connection.CreateCommand();
        command.CommandText = """
            INSERT INTO command_history (id, server_id, command, exit_code, duration_ms, ran_at)
            VALUES ($id, $serverId, $command, $exitCode, $durationMs, $ranAt)
            """;
        command.Parameters.AddWithValue("$id", entry.Id.ToString());
        command.Parameters.AddWithValue("$serverId", entry.ServerId.ToString());
        command.Parameters.AddWithValue("$command", entry.Command);
        command.Parameters.AddWithValue("$exitCode", entry.ExitCode);
        command.Parameters.AddWithValue("$durationMs", entry.DurationMilliseconds);
        command.Parameters.AddWithValue("$ranAt", entry.RanAt.ToString("O"));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private void Migrate()
    {
        using var command = _connection.CreateCommand();
        command.CommandText = """
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS server_profiles (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                host TEXT NOT NULL,
                port INTEGER NOT NULL DEFAULT 22,
                username TEXT NOT NULL,
                auth_type TEXT NOT NULL,
                credential_ref TEXT NOT NULL,
                group_name TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS command_history (
                id TEXT PRIMARY KEY NOT NULL,
                server_id TEXT NOT NULL,
                command TEXT NOT NULL,
                exit_code INTEGER NOT NULL,
                duration_ms INTEGER NOT NULL,
                ran_at TEXT NOT NULL,
                FOREIGN KEY(server_id) REFERENCES server_profiles(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_command_history_server_ran_at
            ON command_history(server_id, ran_at DESC);
            """;
        command.ExecuteNonQuery();
    }

    private static ServerProfile ReadProfile(SqliteDataReader reader) =>
        new(
            Guid.Parse(reader.GetString(0)),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetInt32(3),
            reader.GetString(4),
            Enum.Parse<SshAuthType>(reader.GetString(5)),
            reader.GetString(6),
            reader.IsDBNull(7) ? null : reader.GetString(7),
            DateTimeOffset.Parse(reader.GetString(8)),
            DateTimeOffset.Parse(reader.GetString(9)));

    private static CommandHistoryEntry ReadCommandHistory(SqliteDataReader reader) =>
        new(
            Guid.Parse(reader.GetString(0)),
            Guid.Parse(reader.GetString(1)),
            reader.GetString(2),
            reader.GetInt32(3),
            reader.GetInt64(4),
            DateTimeOffset.Parse(reader.GetString(5)));

    private static void BindProfile(SqliteCommand command, ServerProfile profile)
    {
        command.Parameters.AddWithValue("$id", profile.Id.ToString());
        command.Parameters.AddWithValue("$name", profile.Name);
        command.Parameters.AddWithValue("$host", profile.Host);
        command.Parameters.AddWithValue("$port", profile.Port);
        command.Parameters.AddWithValue("$username", profile.Username);
        command.Parameters.AddWithValue("$authType", profile.AuthType.ToString());
        command.Parameters.AddWithValue("$credentialRef", profile.CredentialRef);
        command.Parameters.AddWithValue("$groupName", (object?)profile.GroupName ?? DBNull.Value);
        command.Parameters.AddWithValue("$createdAt", profile.CreatedAt.ToString("O"));
        command.Parameters.AddWithValue("$updatedAt", profile.UpdatedAt.ToString("O"));
    }

    public ValueTask DisposeAsync() => _connection.DisposeAsync();
}
