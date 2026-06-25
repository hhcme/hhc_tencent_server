# HHC Server Manager - Design Document

> A macOS native, SSH-first server management client. The product aims to provide a Baota-like desktop experience across multiple cloud vendors and self-hosted Linux servers, with optional cloud provider API enhancements for inventory, cloud-side metrics, security groups, and power operations.

## 1. Overview

### Goal

Build a macOS native client that connects to remote Linux servers over SSH and provides common server management capabilities from one local desktop application.

The product direction is **SSH-first + optional Cloud API enhancement**. SSH remains the universal management path. When users explicitly configure Tencent Cloud, Alibaba Cloud, Huawei Cloud, or another provider account, cloud APIs can enhance instance discovery, resource metadata, cloud monitoring, security groups, and power operations.

### Core capabilities

- Operations: SSH command panel, terminal direction, file manager, server monitoring.
- Cloud resource enhancement: instance discovery, metadata, cloud metrics, security groups, start/stop/reboot.
- Environment management: systemd, Nginx, firewall, cron, and environment variables.
- GitLab deployment: manual deployment, webhook automation, logs, and rollback.
- Private package registries: Verdaccio for npm and candidate Dart/Flutter pub registry support.

### MVP boundary

The first milestone is a real SSH minimum viable product:

1. Save a server profile locally.
2. Store credentials in macOS Keychain.
3. Verify and persist the SSH host key fingerprint.
4. Establish a real SSH connection.
5. Run one remote command.
6. Disconnect cleanly.

Phase 1 does not include the full terminal, SFTP file manager, dashboard, cloud provider APIs, deployment, or package registry installation.

## 2. Technology

| Layer | Choice |
|-------|--------|
| Language | Swift 6.1+ |
| UI | SwiftUI, with AppKit where needed |
| SSH | SwiftNIO SSH 0.13.x for exec/shell channels |
| Cloud APIs | Optional provider adapters for Tencent Cloud, Alibaba Cloud, and Huawei Cloud |
| Storage | SQLite + GRDB 7.x |
| Secrets | macOS Keychain |
| Minimum OS | macOS 14 |

SwiftNIO SSH versioning matters. Newer releases have different Swift toolchain requirements, so the project should commit `Package.resolved` and pin the Xcode/Swift toolchain in CI.

The current implementation priority is the macOS native client. A Windows native client should start after the macOS core features stabilize. The recommended Windows direction is WinUI 3 + Windows App SDK + .NET/C#. See [Windows native client strategy](2026-06-25-windows-native-client-strategy.md).

## 3. Architecture

Recommended service boundaries:

- `AppState`: main-actor observable application state.
- `ServerRepository`: SQLite persistence for server profiles.
- `KeychainService`: password, private key, and passphrase storage.
- `ServerManagementService`: orchestrates server CRUD and credential lifecycle.
- `SSHManager`: actor-based connection pool.
- `SSHConnection`: wraps one SwiftNIO SSH connection.
- `HostKeyTrustStore`: host key lookup, trust, mismatch handling, and persistence.
- `CloudProviderRegistry`: registers provider adapters and exposes capabilities.
- `CloudAccountStore`: stores cloud account metadata and Keychain references.
- `CloudInstanceSyncService`: imports and syncs cloud instances.
- `CloudMetricService`: queries cloud-side metrics when available.

SwiftNIO details such as `Channel`, `EventLoopGroup`, and authentication delegates should stay inside the SSH service layer. View models should call async APIs and observe state changes.

## 4. Product Navigation

The product uses a two-level navigation model:

1. **Server Browser**: the app starts with a server list for browsing, grouping, search, filtering, selected-server summary, and Open/Connect/Delete actions.
2. **Server Workspace**: opening a server enters a dedicated workspace for that server. The workspace has server-scoped navigation on the left and a toolbar with back-to-list, current server switcher, and common actions.

Startup screen:

```text
Toolbar: Search / Add / Cloud / More
├── Source List
│   ├── All Servers
│   ├── Groups
│   └── Cloud / Manual SSH
└── Server table + selected summary
    └── Open / Connect / Delete
```

Workspace:

```text
Toolbar: Servers / Current Server Switcher / Actions
├── Server tools
│   ├── Overview
│   ├── Terminal
│   └── Files
└── Current server workspace
```

The server switcher changes the active workspace context without forcing the user back to the startup list.

## 5. SSH connection model

The SSH layer should support:

- TCP connection timeout.
- `NIOSSHHandler` setup.
- Server authentication delegate for host key verification.
- User authentication delegate for password and supported private key authentication.
- Session child channels.
- Exec requests for command execution.
- stdout, stderr, and exit status collection.
- Graceful disconnect and event loop shutdown.

Connection lifecycle:

1. User selects a server.
2. The app loads credentials from Keychain.
3. TCP and SSH handshake start.
4. The host key is verified against trusted records.
5. Unknown host keys require explicit user confirmation.
6. Changed host keys block the connection.
7. User authentication runs.
8. The smoke-test command `printf hhc-ssh-ok` verifies the connection.
9. The connection enters the pool.

Only idempotent operations may be retried automatically after a network interruption.

## 6. Cloud Provider API enhancement

Cloud APIs complement SSH. They should be used for cloud-resource information and cloud-control operations, while SSH remains responsible for server-internal operations.

Good Cloud API use cases:

- Instance inventory and import.
- Instance ID, region, zone, type, image, and billing metadata.
- Public/private IP, VPC, subnet, and EIP information.
- Cloud-side instance status.
- Cloud metrics such as CPU, network, and cloud disk metrics.
- Security group viewing and updates.
- Start, stop, reboot, snapshot, and disk operations.

SSH-owned capabilities:

- systemd, Nginx, cron, environment variables.
- File manager and deployment.
- Process-level details.
- Private registry installation.

Adapter shape:

```swift
protocol CloudProviderAdapter: Sendable {
    var providerId: CloudProviderID { get }
    var displayName: String { get }
    var capabilities: Set<CloudCapability> { get }

    func validateCredentials(_ credential: CloudCredential) async throws
    func listRegions(account: CloudProviderAccount) async throws -> [CloudRegion]
    func listInstances(account: CloudProviderAccount, region: String) async throws -> [CloudInstance]
    func fetchMetrics(
        account: CloudProviderAccount,
        instance: CloudInstanceRef,
        query: CloudMetricQuery
    ) async throws -> [CloudMetricSeries]
    func performAction(
        _ action: CloudInstanceAction,
        account: CloudProviderAccount,
        instance: CloudInstanceRef
    ) async throws
}
```

Provider priority:

1. Tencent Cloud adapter for read-only CVM discovery and metrics.
2. Alibaba Cloud adapter for ECS discovery and CloudMonitor.
3. Huawei Cloud adapter for ECS details and Cloud Eye.

## 7. Credential and host key policy

Credentials:

- Passwords and private keys must be stored in Keychain, not SQLite.
- Private key file paths must not be the only stored credential.
- If the app references a local private key file, it must use a security-scoped bookmark.
- Passphrases may be stored separately in Keychain only when the user opts in.
- Cloud API SecretId/SecretKey, AccessKey, and tokens must also live in Keychain.

Host keys:

- First connection prompts the user to trust the host key.
- Subsequent connections must compare fingerprints.
- A fingerprint mismatch must not be silently overwritten.
- The UI must show both old and new fingerprints when a mismatch occurs.

## 8. Data model

Core tables:

```sql
CREATE TABLE server_profiles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    host TEXT NOT NULL,
    port INTEGER NOT NULL DEFAULT 22,
    auth_type TEXT NOT NULL,
    username TEXT NOT NULL,
    keychain_ref TEXT NOT NULL,
    group_name TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE trusted_host_keys (
    id TEXT PRIMARY KEY,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    host TEXT NOT NULL,
    port INTEGER NOT NULL,
    algorithm TEXT NOT NULL,
    fingerprint_sha256 TEXT NOT NULL,
    raw_public_key TEXT,
    trusted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(server_id, algorithm, fingerprint_sha256)
);

CREATE TABLE cloud_provider_accounts (
    id TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    keychain_ref TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE cloud_instance_links (
    id TEXT PRIMARY KEY,
    server_id TEXT REFERENCES server_profiles(id) ON DELETE SET NULL,
    account_id TEXT NOT NULL REFERENCES cloud_provider_accounts(id) ON DELETE CASCADE,
    provider_id TEXT NOT NULL,
    region_id TEXT NOT NULL,
    instance_id TEXT NOT NULL,
    display_name TEXT,
    public_ip TEXT,
    private_ip TEXT,
    status TEXT,
    instance_type TEXT,
    zone_id TEXT,
    vpc_id TEXT,
    raw_json TEXT,
    last_synced_at DATETIME,
    UNIQUE(account_id, region_id, instance_id)
);
```

Keychain records:

- `ssh_password_<keychain_ref>`
- `ssh_private_key_<keychain_ref>`
- `ssh_private_key_passphrase_<keychain_ref>`
- `ssh_key_bookmark_<keychain_ref>` when local file references are supported
- `cloud_tencent_secret_id_<keychain_ref>` and `cloud_tencent_secret_key_<keychain_ref>`
- `cloud_alibaba_access_key_id_<keychain_ref>` and `cloud_alibaba_access_key_secret_<keychain_ref>`
- `cloud_huawei_access_key_id_<keychain_ref>` and `cloud_huawei_secret_access_key_<keychain_ref>`
- `webhook_secret_<project_id>` for future deployment automation

## 9. Feature modules

### Dashboard

The dashboard is Linux-oriented and should start with capability detection. It should not assume all servers have `/proc`, systemd, or the same command output format. When cloud accounts are linked, the dashboard can combine SSH-collected metrics and cloud-side metrics.

### Terminal

Phase 2 starts with a simplified command panel based on exec requests. A full PTY terminal is a later enhancement.

### File manager

SwiftNIO SSH provides SSH channels, not a high-level SFTP client. Phase 3 must begin with SFTP technical validation before committing to the file manager implementation.

### Environment management

systemd, Nginx, firewall, cron, and environment handling must be adapter-based and capability-driven. Do not assume firewalld, Debian-style Nginx paths, or systemd are always available.

### Deployment

Git operations such as `git reset --hard` must run only inside whitelisted deployment directories. The previous commit should be recorded before destructive operations.

For GitLab webhooks, validate `X-Gitlab-Token` with constant-time comparison. HMAC can be added later for custom proxy flows.

### Package registries

Verdaccio should be installed with an explicit stable version, not a floating pre-release. Dart/Flutter pub registry support should be revalidated before Phase 6 because server options and maintenance status can change.

## 10. Roadmap

1. Phase 1: app skeleton, server CRUD, Keychain, host key trust, real SSH command.
2. Phase 2: cloud provider foundation, cloud account settings, Tencent Cloud read-only discovery, and simplified command panel.
3. Phase 3: dashboard combining SSH metrics and cloud metrics, plus SFTP validation and file manager.
4. Phase 4: security group management and environment management.
5. Phase 5: GitLab deployment.
6. Phase 6: private package registries.
7. Phase 7: more providers, snapshots, disks, billing, and advanced cloud resource management.
8. Phase 8: Windows native client with WinUI 3, Windows App SDK, .NET/C#, Windows Credential Manager, and a real SSH MVP.

## 11. Non-functional requirements

- SSH work must not block the UI.
- Cloud API calls must be rate-limited, cancellable, and audited when they change remote state.
- All remote operations need timeouts.
- Only idempotent operations can be retried automatically.
- Dangerous operations require confirmation.
- Errors must be actionable.
- SSH, Keychain, and database behavior should be testable through protocols.
