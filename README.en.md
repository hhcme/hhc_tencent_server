# HHC Server Manager

English | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to manage multiple Linux servers through SSH and provide a desktop experience similar to Baota Panel, with optional cloud provider API enhancements for instance discovery, cloud-side metrics, security groups, and power operations.

The repository is in active macOS implementation, with Windows native Phase 8 technical validation now started. The macOS app can already save server profiles, store SSH and cloud credentials in Keychain, verify SSH host keys, run real OpenSSH smoke tests, execute single remote commands, browse and edit remote files, queue rsync/sftp/scp-backed batch transfers with running byte/speed/ETA progress, limited concurrency, audited finished-transfer cleanup, and retryable interrupted transfers, show SSH and linked-cloud dashboard metrics, inspect and mutate selected cloud/security resources with runtime permission-based capability downgrade, filtered resource summaries, and Markdown report copy, manage systemd/Cron/Nginx/Firewall/Environment foundations including read-only `/etc/cron.d` discovery, run GitLab-style deployment workflows, manage Verdaccio npm registry foundations with real isolated lifecycle validation, persist command/cloud/deployment/registry/remote-change metadata in SQLite, and show recent audit records in the server workspace. The Windows tree now has a WinUI 3 / Windows App SDK / .NET solution skeleton and CI-covered domain, SQLite, Credential Manager boundary, host-key trust, OpenSSH `known_hosts` paste/file import, SSH adapter, MVVM, DI, connection-state foundations, password/private-key server CRUD flows, and a cancellable connected single-command runner; full WinUI/MSIX/runtime validation still requires a Windows host.

## Why

Many server management tools depend on web panels, cloud consoles, or heavy server-side agents. This project starts from a native macOS client, uses common SSH capabilities for server-internal operations, and uses cloud APIs only where the cloud platform is the better source of truth.

Target users include:

- Individual developers who manage several cloud servers.
- Small teams that want one place to manage Tencent Cloud, Alibaba Cloud, Huawei Cloud, or self-hosted Linux servers.
- Developers who prefer local desktop workflows for server configuration, deployment, and package registry management.

## Features

- Server list, groups, search, and connection states.
- Password and private-key authentication.
- Sensitive credentials stored in macOS Keychain.
- First-use SSH host key trust and follow-up verification.
- Real OpenSSH smoke test, cancellable single-command panel, persisted command metadata history, stdout/stderr split output, and history reruns.
- Cloud account metadata and cloud credential storage foundation.
- Cloud provider adapter protocol, capability registry, normalized errors, and timeout wrapper.
- Tencent Cloud, Alibaba Cloud, and Huawei Cloud adapters covering instance discovery, selected power/disk/snapshot/security-group operations, and linked dashboard metrics with mock-backed tests.
- Tencent Cloud security group foundations with VPC security group/rule read APIs, confirmed single-rule add/remove actions, and audit records for the linked account and region.
- Cloud import sheet for verifying Tencent Cloud accounts, loading regions, syncing CVM instances, and importing instances as SSH profiles.
- Dashboard foundations with SSH-based OS/capability detection plus load, memory, disk, CPU, network, process summary metric cards, linked cloud metrics, manual refresh, and auto-refresh.
- Remote file browser foundations with path navigation, directory listing, file metadata display, limited-concurrency batch upload/download through OpenSSH/rsync/sftp/scp, byte/speed/ETA progress, rsync append-verify resume, SFTP `put -a` / `get -a` fallback resume, current-transfer cancellation, pending-queue clearing, audited finished-transfer history cleanup, retry for failed/cancelled/interrupted transfers, rename, chmod-based permission changes, recoverable move-to-trash, and lightweight UTF-8 text editing with backup-on-save and Save As.
- Services foundations with systemd unit listing, state display, journal reading, and confirmed start/stop/restart/reload actions.
- Cron foundations with writable user crontab entries, read-only `/etc/cron.d` discovery with source/run-as metadata, add/enable/disable/delete flows, and pre-install remote backups.
- Nginx foundations with dynamic config path discovery, guarded config editing, remote backups, `nginx -t`, automatic rollback on failed tests, confirmed reload, and remote-change audit records.
- Firewall foundations with backend detection and limited rule actions for firewalld, ufw, nftables, and iptables; nftables only edits existing compatible filter chains and HHC-marked rules.
- Environment file foundations with guarded discovery and editing for common `.env`, `/etc/default`, `/etc/sysconfig`, and systemd drop-in files, including remote backups and audit records.
- Audit workspace for per-server remote change logs and current-server local operation logs.
- Optional cloud account integration through provider adapters.
- Cloud instance discovery, resource metadata, cloud metrics, security groups, and power operations.
- Simplified command panel and server dashboard.
- SFTP file manager.
- systemd, Nginx, firewall, cron, and environment management.
- GitLab-style deployments with project CRUD, command previews, logs, rollback, local webhook listener, and live run/log refresh.
- Verdaccio npm registry management with preflight, install, service control, users, package listing, backup/restore, Nginx proxy support, and npm smoke tests, plus Dart/Flutter external Hosted Pub Repository configuration assistance.
- Guarded real-server Verdaccio lifecycle coverage for isolated install, user creation, npm publish/install smoke, restart, config backup, and backup/restore; production deployment and proxy exposure still require environment-specific validation.
- Windows native Phase 8 solution skeleton with WinUI 3, Windows App SDK, .NET, CI-covered SQLite/core tests, Windows Credential Manager boundaries, password/private-key server CRUD flows, host-key trust, SSH adapter foundations, cancellable connected single-command execution, and an opt-in Windows real SSH integration test entrypoint.

## Technology Direction

| Layer | Choice |
|-------|--------|
| Language | Swift 6.1+ |
| UI | SwiftUI, with AppKit where needed |
| SSH | Current bootstrap: system OpenSSH adapter; target core: SwiftNIO SSH 0.13.x |
| Cloud APIs | Optional provider adapters |
| Database | Current bootstrap: SQLite C API; target persistence layer may move to GRDB 7.x |
| Credentials | macOS Keychain |
| Minimum OS | macOS 14 |

## Roadmap

1. **Phase 1: App skeleton and real SSH MVP**
   macOS app, server CRUD, Keychain, host key trust, real SSH connection, and `printf hhc-ssh-ok` smoke test.
2. **Phase 2: Cloud provider foundation and simplified command panel**
   Cloud accounts, provider adapters, Tencent Cloud read-only instance discovery, and command history.
3. **Phase 3: Dashboard and file manager**
   Combine SSH metrics with linked Tencent Cloud CVM CPU metrics first; ship SSH-bootstrap directory browsing, lightweight editing, limited-concurrency queued transfers, byte/speed/ETA progress reporting, rsync append-verify resume, SFTP `put -a` / `get -a` fallback, and more cloud metrics, then harden native SFTP transfer workflows.
4. **Phase 4: Security groups and environment configuration**
   Security group viewing/updating, systemd, Nginx, firewall, cron, and environment variables.
5. **Phase 5: GitLab deployment**
   Manual deployment, deployment logs, rollback, and webhook automation.
6. **Phase 6: Private package registries**
   Verdaccio management and Dart/Flutter external Hosted Pub Repository configuration assistance; self-hosted pub registry installation stays research-only until real publish/get validation passes.
7. **Phase 7: Advanced cloud resource management**
   More providers, snapshots, disks, billing status, and advanced cloud operations.
8. **Phase 8: Windows native technical validation**
   WinUI 3, Windows App SDK, .NET, Windows Credential Manager, and real SSH smoke test.

## Documentation

- [Documentation index](docs/README.md)
- [macOS MVP design snapshots](docs/assets/design/macos-mvp-v0.2/README.md)
- Detailed design and implementation documents are maintained in Chinese to avoid duplicated planning drift.
- [macOS MVP design note](docs/superpowers/specs/2026-06-25-macos-mvp-design.md)
- [Design document](docs/superpowers/specs/2026-06-25-server-manager-design.md)
- [Cloud provider API enhancement](docs/superpowers/specs/2026-06-25-cloud-provider-integration.md)
- [Windows native client strategy](docs/superpowers/specs/2026-06-25-windows-native-client-strategy.md)
- [All phase implementation plans](docs/superpowers/plans/README.md)

## Development Status

The macOS app is now under active implementation. Phase 1 through Phase 6 foundations are in place across SSH, optional cloud APIs, dashboard, file management, security/environment tools, deployments, and private registry management: SwiftUI app structure, local SQLite persistence, Keychain-backed SSH/cloud credentials, host-key trust, OpenSSH-based real command execution with cancellation, command metadata history with reruns, split stdout/stderr output, cloud account metadata, cloud instance links, Tencent/Alibaba/Huawei adapters, linked-cloud dashboard metrics, remote directory browsing and editing, limited-concurrency rsync/sftp/scp batch transfers with byte/speed/ETA progress, rsync `--append-verify` resume, SFTP `put -a` / `get -a` fallback, and retry for interrupted history, systemd/Cron/Nginx/Firewall/Environment workflows, read-only `/etc/cron.d` discovery, remote change audit logs, GitLab-style deployment runs/logs/rollback/webhook listener, Verdaccio preflight/install/service/users/packages/backup/restore/Nginx proxy/npm smoke flows, Cloud Resources search/action summaries/Markdown reports, unit tests, CI, and real-server smoke validation for SSH, transfers, Phase 4 systemd/Cron/Environment controlled writes, temporary deployment, and isolated Verdaccio install/publish/restart/backup/restore. Windows native Phase 8 has started with a WinUI 3 / Windows App SDK / .NET solution skeleton, CI-covered core layers, and an opt-in Windows-only real SSH/Credential Manager integration test. Command output remains session-scoped and is not persisted by default. SwiftNIO/libssh2 SFTP hardening, native transfer queue, production deployment validation, real multi-cloud write-operation validation, production Verdaccio/proxy validation, and full Windows-host validation remain planned work.

## Contributing

Contributions to design discussions, implementation, testing, and documentation improvements are welcome. Please read:

- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)

## License

This project is open source under the [MIT License](LICENSE).
