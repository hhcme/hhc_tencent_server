# Phase 1: App Skeleton and Real SSH MVP

> This plan replaces an earlier mock-connection approach. Phase 1 is complete only when the app can safely store one server profile, verify the host key, authenticate with password or a supported private key, connect to a real server, execute one remote command, and disconnect.

## 1. Goals

Phase 1 should deliver:

1. A runnable macOS 14+ SwiftUI application skeleton.
2. Server profile CRUD persisted with SQLite and GRDB.
3. SSH credentials stored in macOS Keychain.
4. Required App Sandbox entitlements.
5. A real SSH flow: TCP connect -> SSH handshake -> host key trust -> user authentication -> exec command -> disconnect.
6. Sidebar server list, add-server sheet, detail view, connect/disconnect controls, and smoke-test output.
7. Unit tests for models, repositories, Keychain wrapper, service orchestration, and host key trust. Real SSH integration tests may be enabled with environment variables.

## 2. Non-goals

Phase 1 does not implement:

- Full PTY terminal.
- SFTP file manager.
- Dashboard graphs.
- Cloud provider APIs, instance discovery, cloud monitoring, and security group management.
- systemd, Nginx, firewall, cron, or environment management.
- GitLab deployment.
- Verdaccio or Dart/Flutter package registry installation.
- SSH agent, keyboard-interactive authentication, jump hosts, or port forwarding.

## 3. Technical constraints

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

## 4. Entitlements

Configure:

- App Sandbox: enabled.
- Outgoing Connections (Client): enabled.
- Keychain Sharing: enabled.
- User Selected File Read Only: enabled if private-key file selection is supported.

Phase 1 should read a selected private key and store its content in Keychain. Relying on a file path alone is not enough, especially in a sandboxed macOS app.

## 5. Data model

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

SQLite must enable foreign keys so deleting a server also deletes trusted host key records.

## 6. Credential lifecycle

UI credential input exists only in memory:

```swift
enum CredentialInput: Equatable {
    case password(String)
    case privateKey(data: Data, passphrase: String?)
}
```

`ServerManagementService` orchestrates profile and credential writes:

1. Generate server id and `keychainRef`.
2. Save credential to Keychain.
3. Save profile to SQLite.
4. If SQLite fails, clean up the newly created Keychain records.
5. If Keychain fails, do not create a database row.

View models must not write Keychain directly.

## 7. SSH architecture

Expose a small protocol to the rest of the app:

```swift
protocol SSHClientProtocol: Sendable {
    func connect(profile: ServerProfile, credential: CredentialInput) async throws
    func execute(_ command: String, timeout: Duration) async throws -> CommandResult
    func disconnect() async
}
```

`SSHManager` should be an actor-based connection pool. Avoid mixing `DispatchQueue.sync` with async barrier writes.

`SSHConnection.connect` must perform a real network connection. A sleep followed by `connected` is not acceptable.

Connection implementation steps:

1. Use `ClientBootstrap`.
2. Install `NIOSSHHandler`.
3. Implement server authentication for host key verification.
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

## 8. Host key trust

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

## 9. UI scope

Sidebar:

- Server list.
- Groups.
- Search.
- Connection state indicator.
- Delete with confirmation.

Add server:

- Name, host, port, username, group.
- Authentication type.
- Password or private-key picker.
- Optional private-key passphrase.
- Save.
- Test and save.

Detail view:

- Server information.
- Connection state.
- Connect and disconnect buttons.
- Smoke Test button.
- stdout, stderr, and exit code output.

## 10. Implementation tasks

1. Initialize Xcode macOS SwiftUI app and entitlements.
2. Add SwiftNIO SSH and GRDB dependencies.
3. Implement models and database migrations.
4. Implement Keychain service.
5. Implement server management orchestration.
6. Implement host key trust store.
7. Implement real SSH connection and command execution.
8. Implement AppState and view models.
9. Implement SwiftUI screens.
10. Add unit tests and optional real SSH integration tests.

## 11. Integration test environment

Real SSH integration tests should be opt-in:

```sh
HHC_TEST_SSH_HOST=127.0.0.1
HHC_TEST_SSH_PORT=22
HHC_TEST_SSH_USER=tester
HHC_TEST_SSH_PASSWORD=...
```

If the variables are absent, integration tests should be skipped instead of failing CI.

## 12. Manual acceptance

- First launch shows an empty list.
- Add a password-auth server.
- First connection shows host key confirmation.
- Confirming trust connects successfully.
- Smoke test returns `hhc-ssh-ok`.
- Disconnect succeeds.
- Restarting the app keeps server profiles.
- The second connection does not ask for the same host key again.
- A changed host key blocks connection.
- Deleting a server cleans DB rows, trusted host key records, and Keychain credentials.

## 13. Completion criteria

Phase 1 is complete only when:

1. The app runs.
2. Server profiles persist.
3. Credentials stay in Keychain.
4. Host key trust works.
5. Password authentication can connect to a real server.
6. `printf hhc-ssh-ok` runs remotely.
7. Disconnect releases NIO resources.
8. Unit tests pass.
9. Manual acceptance passes.

## 14. Later phase boundary

- **Phase 2:** cloud provider foundation and simplified command panel. Add `CloudProviderAdapter`, cloud account settings, and Tencent Cloud read-only instance discovery; reuse Phase 1 `execute` for commands and do not introduce PTY yet.
- **Phase 3:** dashboard, SFTP validation, and file manager. The dashboard can combine SSH metrics and cloud metrics.
- **Phase 4:** security groups and environment configuration. Cloud security groups go through provider adapters; OS-internal configuration remains capability-detected SSH work.
- **Phase 5:** GitLab deployment.
- **Phase 6:** private package registries.
- **Phase 7:** more cloud providers, advanced cloud resource management, snapshots, disks, and billing data.
- **Phase 8:** Windows native technical validation with WinUI 3, Windows App SDK, and .NET/C#, starting by recreating the real SSH MVP.
