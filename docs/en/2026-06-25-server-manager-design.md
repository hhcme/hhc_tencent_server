# HHC Server Manager - Design Document

> A macOS native, SSH-first server management client. The product aims to provide a Baota-like desktop experience across multiple cloud vendors and self-hosted Linux servers without relying on cloud vendor APIs.

## 1. Overview

### Goal

Build a macOS native client that connects to remote Linux servers over SSH and provides common server management capabilities from one local desktop application.

The product is vendor-neutral. Tencent Cloud, Alibaba Cloud, Huawei Cloud, and self-hosted servers are represented as groups or labels only. Connection and management behavior should remain SSH-based.

### Core capabilities

- Operations: SSH command panel, terminal direction, file manager, server monitoring.
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

Phase 1 does not include the full terminal, SFTP file manager, dashboard, deployment, or package registry installation.

## 2. Technology

| Layer | Choice |
|-------|--------|
| Language | Swift 6.1+ |
| UI | SwiftUI, with AppKit where needed |
| SSH | SwiftNIO SSH 0.13.x for exec/shell channels |
| Storage | SQLite + GRDB 7.x |
| Secrets | macOS Keychain |
| Minimum OS | macOS 14 |

SwiftNIO SSH versioning matters. Newer releases have different Swift toolchain requirements, so the project should commit `Package.resolved` and pin the Xcode/Swift toolchain in CI.

## 3. Architecture

Recommended service boundaries:

- `AppState`: main-actor observable application state.
- `ServerRepository`: SQLite persistence for server profiles.
- `KeychainService`: password, private key, and passphrase storage.
- `ServerManagementService`: orchestrates server CRUD and credential lifecycle.
- `SSHManager`: actor-based connection pool.
- `SSHConnection`: wraps one SwiftNIO SSH connection.
- `HostKeyTrustStore`: host key lookup, trust, mismatch handling, and persistence.

SwiftNIO details such as `Channel`, `EventLoopGroup`, and authentication delegates should stay inside the SSH service layer. View models should call async APIs and observe state changes.

## 4. SSH connection model

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
8. A smoke-test command verifies the connection.
9. The connection enters the pool.

Only idempotent operations may be retried automatically after a network interruption.

## 5. Credential and host key policy

Credentials:

- Passwords and private keys must be stored in Keychain, not SQLite.
- Private key file paths must not be the only stored credential.
- If the app references a local private key file, it must use a security-scoped bookmark.
- Passphrases may be stored separately in Keychain only when the user opts in.

Host keys:

- First connection prompts the user to trust the host key.
- Subsequent connections must compare fingerprints.
- A fingerprint mismatch must not be silently overwritten.
- The UI must show both old and new fingerprints when a mismatch occurs.

## 6. Data model

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
```

Keychain records:

- `ssh_password_<keychain_ref>`
- `ssh_private_key_<keychain_ref>`
- `ssh_private_key_passphrase_<keychain_ref>`
- `ssh_key_bookmark_<keychain_ref>` when local file references are supported
- `webhook_secret_<project_id>` for future deployment automation

## 7. Feature modules

### Dashboard

The dashboard is Linux-oriented and should start with capability detection. It should not assume all servers have `/proc`, systemd, or the same command output format.

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

## 8. Roadmap

1. Phase 1: app skeleton, server CRUD, Keychain, host key trust, real SSH command.
2. Phase 2: dashboard and simplified command panel.
3. Phase 3: SFTP validation and file manager.
4. Phase 4: environment management.
5. Phase 5: GitLab deployment.
6. Phase 6: private package registries.

## 9. Non-functional requirements

- SSH work must not block the UI.
- All remote operations need timeouts.
- Only idempotent operations can be retried automatically.
- Dangerous operations require confirmation.
- Errors must be actionable.
- SSH, Keychain, and database behavior should be testable through protocols.
