# Phase 1: App Skeleton and Real SSH MVP

> Phase 1 is complete only when the app can safely store a server profile, verify the host key, authenticate with password or a supported private key, connect to a real server, execute one remote command, and disconnect.

Design document: `docs/en/2026-06-25-server-manager-design.md`

Local design snapshots: `docs/assets/design/macos-mvp-v0.2/README.md`

Current implementation entry point: macOS native Phase 1. The app starts with a server list, opening a server enters a dedicated server workspace, and the workspace toolbar provides an explicit server switcher.

## 1. Goals

Phase 1 should deliver:

1. A runnable macOS 14+ SwiftUI application skeleton.
2. Server profile CRUD persisted with SQLite and GRDB.
3. SSH credentials stored in macOS Keychain, never as plaintext SQLite fields.
4. Required App Sandbox entitlements.
5. A real SSH flow: TCP connect -> SSH handshake -> host key trust -> user authentication -> exec command -> disconnect.
6. Startup server list, add-server sheet, dedicated server workspace, server switcher, host-key trust sheet, connect/disconnect controls, and smoke-test output.
7. Unit tests for models, repositories, Keychain wrapper, service orchestration, host-key trust, and SSH state transitions.
8. Optional real SSH integration tests enabled through environment variables.

## 2. Non-goals

Phase 1 does not implement:

- Full PTY terminal.
- SFTP file manager.
- Dashboard graphs or real-time monitoring.
- Cloud provider APIs, instance discovery, cloud monitoring, and security group management.
- systemd, Nginx, firewall, cron, or environment management.
- GitLab deployment, webhook server, or rollback.
- Verdaccio or Dart/Flutter package registry installation.
- SSH agent, keyboard-interactive authentication, jump hosts, or port forwarding.

These features depend on a stable real SSH foundation and belong to later phases.

## 3. Technical Constraints

| Item | Choice |
|------|--------|
| Project type | Xcode macOS App project |
| Language | Swift 6.1+ |
| UI | SwiftUI + Observation |
| SSH | SwiftNIO SSH 0.13.x |
| DB | GRDB 7.x + SQLite |
| Secrets | macOS Keychain |
| Minimum OS | macOS 14 |

Use a narrow SwiftNIO SSH version range and commit `Package.resolved`.

```swift
.package(url: "https://github.com/apple/swift-nio-ssh.git", .upToNextMinor(from: "0.13.0")),
.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
```

## 4. Project Structure

Use a standard Xcode app project. Do not mix it with a Swift Package `Sources/` root.

```text
HHCServerManager/
├── HHCServerManager.xcodeproj
├── HHCServerManager/
│   ├── App/
│   │   ├── HHCServerManagerApp.swift
│   │   └── AppState.swift
│   ├── Models/
│   │   ├── ServerProfile.swift
│   │   ├── TrustedHostKey.swift
│   │   └── CommandResult.swift
│   ├── Services/
│   │   ├── SSH/
│   │   │   ├── SSHClient.swift
│   │   │   ├── SSHConnection.swift
│   │   │   ├── SSHConnectionState.swift
│   │   │   ├── SSHError.swift
│   │   │   ├── HostKeyTrustStore.swift
│   │   │   └── NIOSSHAdapters.swift
│   │   ├── Storage/
│   │   │   ├── AppDatabase.swift
│   │   │   ├── ServerRepository.swift
│   │   │   └── KeychainService.swift
│   │   └── ServerManagementService.swift
│   ├── ViewModels/
│   │   ├── ServerBrowserViewModel.swift
│   │   ├── AddServerViewModel.swift
│   │   ├── ServerWorkspaceViewModel.swift
│   │   └── ServerSwitcherViewModel.swift
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── ServerBrowser/
│   │   │   ├── ServerBrowserView.swift
│   │   │   ├── ServerRowView.swift
│   │   │   ├── ServerSummaryPanel.swift
│   │   │   └── EmptyServerListView.swift
│   │   ├── ServerWorkspace/
│   │   │   ├── ServerWorkspaceView.swift
│   │   │   ├── ServerWorkspaceSidebar.swift
│   │   │   ├── ServerOverviewView.swift
│   │   │   ├── SmokeTestOutputView.swift
│   │   │   └── ServerSwitcherPopover.swift
│   │   └── Sheets/
│   │       ├── AddServerSheet.swift
│   │       └── HostKeyTrustSheet.swift
│   └── Utilities/
│       └── Constants.swift
└── HHCServerManagerTests/
    ├── Models/
    ├── Services/
    └── Integration/
```

## 5. Entitlements

Configure:

- App Sandbox: enabled.
- Outgoing Connections (Client): enabled.
- Keychain Sharing: enabled, using the app's bundle/team access group.
- User Selected File Read Only: enabled if private-key file selection is supported.

Phase 1 should read a selected private key and store its content in Keychain. Relying on a file path alone is not enough in a sandboxed macOS app.

## 6. Data Model

`ServerProfile`:

```swift
enum SSHAuthType: String, Codable, CaseIterable {
    case password
    case privateKey
}

struct ServerProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authType: SSHAuthType
    var keychainRef: String
    var groupName: String?
    var createdAt: Date
    var updatedAt: Date
}
```

`keychainRef` must be a logical reference such as `server_<uuid>`. Passwords, private-key content, passphrases, and raw file paths must not be stored in `ServerProfile`.

`TrustedHostKey`:

```swift
struct TrustedHostKey: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var serverId: UUID
    var host: String
    var port: Int
    var algorithm: String
    var fingerprintSHA256: String
    var rawPublicKey: String?
    var trustedAt: Date
}
```

SQLite schema:

```sql
CREATE TABLE server_profiles (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    host TEXT NOT NULL,
    port INTEGER NOT NULL DEFAULT 22,
    username TEXT NOT NULL,
    auth_type TEXT NOT NULL,
    keychain_ref TEXT NOT NULL,
    group_name TEXT,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

CREATE TABLE trusted_host_keys (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    host TEXT NOT NULL,
    port INTEGER NOT NULL,
    algorithm TEXT NOT NULL,
    fingerprint_sha256 TEXT NOT NULL,
    raw_public_key TEXT,
    trusted_at DATETIME NOT NULL,
    UNIQUE(server_id, algorithm, fingerprint_sha256)
);
```

GRDB migrations must enable foreign keys. Deleting a server must delete its trusted host-key rows.

## 7. Credential Lifecycle

UI credential input exists only in memory:

```swift
enum CredentialInput: Equatable {
    case password(String)
    case privateKey(data: Data, passphrase: String?)
}
```

Suggested Keychain keys:

| Key | Value |
|-----|-------|
| `ssh_password_<keychainRef>` | UTF-8 password |
| `ssh_private_key_<keychainRef>` | private-key bytes |
| `ssh_private_key_passphrase_<keychainRef>` | optional passphrase |

`ServerManagementService` orchestrates writes:

1. Generate `ServerProfile.id` and `keychainRef`.
2. Save credentials to Keychain.
3. Save profile to SQLite.
4. If SQLite fails, remove the newly written Keychain records.
5. If Keychain fails, do not create a database row.

Deleting a server should disconnect first, remove database rows, and then remove Keychain items. Keychain cleanup failures should be logged and retried later instead of blocking the UI.

## 8. SSH Architecture

Expose a small protocol to the rest of the app:

```swift
protocol SSHClientProtocol: Sendable {
    func connect(profile: ServerProfile, credential: CredentialInput) async throws
    func execute(_ command: String, timeout: Duration) async throws -> CommandResult
    func disconnect() async
}
```

`SSHManager` should be an actor-based connection pool:

```swift
actor SSHManager {
    func connection(for profile: ServerProfile) async -> SSHClientProtocol
    func connect(profile: ServerProfile, credential: CredentialInput) async throws
    func execute(serverId: UUID, command: String, timeout: Duration) async throws -> CommandResult
    func disconnect(serverId: UUID) async
    func disconnectAll() async
}
```

`SSHConnection.connect` must perform a real network connection. A sleep followed by `connected` is not acceptable.

Connection steps:

1. Use `ClientBootstrap`.
2. Install `NIOSSHHandler`.
3. Implement server authentication for host-key verification.
4. Implement user authentication for password and supported private keys.
5. Open a session child channel.
6. Send an exec request.
7. Collect stdout, stderr, and exit status.
8. Close the child channel and keep the SSH connection alive until disconnect.

Smoke-test command:

```sh
printf hhc-ssh-ok
```

Acceptance: exit code is `0` and stdout contains `hhc-ssh-ok`.

## 9. Private-key Boundary

Phase 1 must support password authentication. Private-key authentication should support at least one real tested key format or be explicitly marked as a blocker with disabled UI.

| Type | Phase 1 requirement |
|------|---------------------|
| password | Required |
| unencrypted Ed25519 private key | Required, or a documented P0 blocker after technical validation |
| passphrase-protected OpenSSH private key | Optional |
| ssh-agent | Out of scope |
| keyboard-interactive | Out of scope |

If private-key parsing fails, the UI should explain that the key format or encryption mode is not supported yet, instead of showing a generic authentication failure.

## 10. Host-key Trust

First connection:

1. Receive server public key.
2. Compute SHA256 fingerprint.
3. Look up `trusted_host_keys`.
4. If unknown, enter `awaitingHostTrust`.
5. Show host, port, algorithm, and fingerprint in a trust sheet.
6. Continue only after user confirmation.
7. Rejecting the key disconnects and returns an error.

Later connections:

1. Compare against trusted records.
2. Matching fingerprints continue.
3. Mismatches enter a blocking `hostKeyChanged` state.
4. Never overwrite a changed host key silently.

## 11. AppState and ViewModels

`AppState` should be `@MainActor @Observable`:

```swift
@MainActor
@Observable
final class AppState {
    var selectedServerId: UUID?
    var servers: [ServerProfile] = []
    var connectionStates: [UUID: SSHConnectionState] = [:]
}
```

Service responsibilities:

- `ServerRepository`: SQLite only.
- `KeychainService`: Keychain only.
- `ServerManagementService`: profile and credential orchestration.
- `SSHManager`: connection pool and SSH operations.

View models must not write Keychain directly and must not expose NIO channels.

## 12. UI Scope

Phase 1 UI must use `docs/assets/design/macos-mvp-v0.2/README.md` as the implementation reference.

### 12.1 Startup Server List

- The first screen is the server list, not a single-server detail view.
- Left source list includes All Servers, Favorites, Recently Used, Groups, and Cloud/Manual SSH categories.
- Main area lists server name, host, group, connection state, cloud source, and last-used time.
- Selecting a server shows a summary panel with name, group, host, state, and primary actions.
- `Open` enters the dedicated server workspace.
- `Connect` may connect from the list, but connection state remains scoped to that server.
- Search, grouping, filtering, and delete-with-confirmation are required.

### 12.2 Dedicated Server Workspace

- Opening a server enters a dedicated workspace.
- Toolbar includes back to server list, current server name, server switcher, and operation shortcuts.
- Left workspace navigation is scoped to the current server: Overview, Terminal, Files, Services, Processes, Logs, Configuration, Cloud.
- Phase 1 implements only Overview: server information, connection state, Connect / Disconnect, Smoke Test, and output.
- Later tabs may be disabled placeholders, but must not claim implementation.
- Server switcher popover lists available servers and switches workspace context without returning to the startup list.

### 12.3 Add Server Sheet

Fields:

- Name
- Host
- Port
- Username
- Group
- Auth type: password / private key
- Password or private-key picker
- Optional private-key passphrase

Behavior:

- Save stores profile and credentials.
- Test & Save performs a real smoke test before keeping the record.
- If Test & Save fails, DB and Keychain writes are rolled back unless the user explicitly chooses to keep the profile.
- First host-key trust confirmation must bind the trust record to the pending server id.
- Port validation is `1...65535`.
- Host must be non-empty. Preserve room for domain, IPv4, and IPv6 input instead of over-validating with a fragile regex.

### 12.4 Host-key Trust Sheet

- Unknown hosts show a sheet with host, port, algorithm, and SHA256 fingerprint.
- Trust writes a `trusted_host_keys` row and continues.
- Reject disconnects and returns a clear error.
- Host-key changes are blocking warnings.

## 13. Implementation Tasks

### Task 1: Initialize project

- [ ] Create Xcode macOS SwiftUI app.
- [ ] Set bundle id and minimum deployment target macOS 14.
- [ ] Configure App Sandbox, Outgoing Connections, Keychain Sharing, and User Selected File Read Only.
- [ ] Add SwiftNIO SSH and GRDB dependencies.
- [ ] Commit `Package.resolved`.
- [ ] Create the directory structure.

Acceptance:

- [ ] `Cmd + R` launches an empty app.
- [ ] Entitlements include outgoing network and Keychain configuration.

### Task 2: Models and database

- [ ] Implement `ServerProfile`, `TrustedHostKey`, and `CommandResult`.
- [ ] Implement `AppDatabase` and GRDB migrations.
- [ ] Implement `ServerRepository`.
- [ ] Implement `TrustedHostKeyRepository` or fold it into `HostKeyTrustStore`.
- [ ] Add tests for insert/update/delete/fetch/cascade delete.

### Task 3: KeychainService

- [ ] Implement save/read/delete for password, private key, and passphrase.
- [ ] Support custom service name for test isolation.
- [ ] Return explicit error types.
- [ ] Add tests for save, read, overwrite, delete, and cleanup.

### Task 4: ServerManagementService

- [ ] Define `CredentialInput`.
- [ ] Implement add/update/delete orchestration.
- [ ] Clean up Keychain on DB write failure.
- [ ] Do not create DB rows when Keychain writes fail.
- [ ] Test compensation logic.

### Task 5: HostKeyTrustStore

- [ ] Implement fingerprint calculation.
- [ ] Implement trust lookup, save, match, and conflict errors.
- [ ] Define `HostKeyTrustDecision`: trust / reject.
- [ ] Provide an async interface for SSH delegates to wait for user decisions.
- [ ] Test first trust, matching trust, and changed fingerprint.

### Task 6: Real SSHConnection

- [ ] Use SwiftNIO SSH for real connections.
- [ ] Implement server authentication delegate.
- [ ] Implement user authentication delegate.
- [ ] Implement password authentication.
- [ ] Implement at least one private-key path, or document it as a P0 blocker with disabled UI.
- [ ] Implement `execute(command:timeout:)`.
- [ ] Implement disconnect and graceful event loop shutdown.
- [ ] Ensure observable state updates return to the main actor.

### Task 7: AppState and view models

- [ ] `AppState` uses `@MainActor @Observable`.
- [ ] `ServerBrowserViewModel` loads, searches, filters, and deletes servers.
- [ ] `AddServerViewModel` validates forms and never writes Keychain directly.
- [ ] `ServerWorkspaceViewModel` handles current server context, connect/disconnect, and smoke test.
- [ ] `ServerSwitcherViewModel` handles workspace server switching.
- [ ] Async operations expose loading and error states.

### Task 8: SwiftUI interface

- [ ] Native macOS split/toolbar structure.
- [ ] Startup server list.
- [ ] Server summary panel with Open/Connect.
- [ ] Dedicated server workspace.
- [ ] Toolbar server switcher and popover.
- [ ] Add-server sheet.
- [ ] Host-key trust sheet.
- [ ] Overview connection controls and smoke-test output.
- [ ] Delete confirmation.

### Task 9: Tests

- [ ] Model tests.
- [ ] Repository tests.
- [ ] Keychain tests.
- [ ] ServerManagementService compensation tests.
- [ ] HostKeyTrustStore tests.
- [ ] SSH state-machine tests.
- [ ] Optional real SSH integration tests.

Real SSH integration tests are enabled with environment variables:

```sh
HHC_TEST_SSH_HOST=127.0.0.1
HHC_TEST_SSH_PORT=22
HHC_TEST_SSH_USER=tester
HHC_TEST_SSH_PASSWORD=...
```

If variables are absent, integration tests should be skipped instead of failing CI.

## 14. Manual Acceptance

- [ ] First launch shows an empty server list.
- [ ] Add a password-auth server.
- [ ] The server appears in the startup server list.
- [ ] Open enters that server's workspace.
- [ ] The workspace server switcher lists available servers and changes current context.
- [ ] First connection shows host-key confirmation.
- [ ] Confirming trust connects successfully.
- [ ] Smoke test returns `hhc-ssh-ok`.
- [ ] Disconnect succeeds.
- [ ] Restarting the app keeps server profiles.
- [ ] The second connection does not ask for the same host key again.
- [ ] A changed host key blocks connection.
- [ ] Deleting a server cleans DB rows, trusted host-key records, and Keychain credentials.

## 15. Completion Criteria

Phase 1 is complete only when:

1. The app runs.
2. Server profiles persist.
3. Credentials stay in Keychain.
4. Host-key trust works.
5. Password authentication can connect to a real server.
6. `printf hhc-ssh-ok` runs remotely.
7. Disconnect releases NIO resources.
8. Unit tests pass.
9. Manual acceptance passes.
10. UI follows the local design flow: server list -> dedicated server workspace -> server switcher.

## 16. Later Phase Boundary

- **Phase 2:** cloud provider foundation and simplified command panel. Add `CloudProviderAdapter`, cloud account settings, and Tencent Cloud read-only instance discovery. Reuse Phase 1 `execute`; do not introduce PTY yet.
- **Phase 3:** dashboard, SFTP validation, and file manager.
- **Phase 4:** security groups and environment configuration.
- **Phase 5:** GitLab deployment.
- **Phase 6:** private package registries.
- **Phase 7:** more cloud providers, advanced cloud resources, snapshots, disks, and billing.
- **Phase 8:** Windows native validation with WinUI 3, Windows App SDK, and .NET/C#.
