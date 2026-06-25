# HHC Server Manager

English | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to manage multiple Linux servers through SSH and provide a desktop experience similar to Baota Panel, with optional cloud provider API enhancements for instance discovery, cloud-side metrics, security groups, and power operations.

The repository is in early macOS implementation. The app can already save server profiles, store SSH and cloud credentials in Keychain, verify SSH host keys, run a real OpenSSH smoke test, execute single remote commands, browse remote directories, queue single-file transfers, manage systemd/Cron/Nginx/Environment foundations, inspect firewall rules, and persist command/cloud/remote-change metadata in SQLite.

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
- Tencent Cloud adapter with TC3 request signing plus Region, CVM instance query parsing, and Cloud Monitor CPU metric query support.
- Cloud import sheet for verifying Tencent Cloud accounts, loading regions, syncing CVM instances, and importing instances as SSH profiles.
- Dashboard foundations with SSH-based OS/capability detection plus load, memory, disk, CPU, network, process summary metric cards, linked Tencent Cloud CVM CPU metrics, manual refresh, and auto-refresh.
- Remote file browser foundations with path navigation, directory listing, file metadata display, queued single-file upload/download through OpenSSH/scp, visible transfer states, current-transfer cancellation, pending-queue clearing, rename, chmod-based permission changes, recoverable move-to-trash, and lightweight UTF-8 text editing with backup-on-save and Save As.
- Services foundations with systemd unit listing, state display, journal reading, and confirmed start/stop/restart/reload actions.
- Cron foundations with crontab reading, entry parsing, add/enable/disable/delete flows, and pre-install remote backups.
- Nginx foundations with dynamic config path discovery, guarded config editing, remote backups, `nginx -t`, automatic rollback on failed tests, confirmed reload, and remote-change audit records.
- Firewall foundations with read-only backend detection and rule display for firewalld, ufw, nftables, and iptables.
- Environment file foundations with guarded discovery and editing for common `.env`, `/etc/default`, `/etc/sysconfig`, and systemd drop-in files, including remote backups and audit records.
- Optional cloud account integration through provider adapters.
- Cloud instance discovery, resource metadata, cloud metrics, security groups, and power operations.
- Simplified command panel and server dashboard.
- SFTP file manager.
- systemd, Nginx, firewall, cron, and environment management.
- GitLab deployment, logs, rollback, and webhook automation.
- Verdaccio npm registry and Dart/Flutter private pub registry management.

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
   Combine SSH metrics with linked Tencent Cloud CVM CPU metrics first; ship SSH-bootstrap directory browsing, lightweight editing, and queued single-file transfers, then harden SFTP, progress reporting, more cloud metrics, and batch transfer workflows.
4. **Phase 4: Security groups and environment configuration**
   Security group viewing/updating, systemd, Nginx, firewall, cron, and environment variables.
5. **Phase 5: GitLab deployment**
   Manual deployment, deployment logs, rollback, and webhook automation.
6. **Phase 6: Private package registries**
   Verdaccio and Dart/Flutter private package registry management.
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

The macOS app is now under active implementation. Phase 1 foundations are in place, Phase 2 foundations are largely in place, Phase 3 Dashboard/file browser foundations have started, and Phase 4 Services/Cron/Nginx/Firewall/Environment has begun: SwiftUI app structure, local SQLite persistence, Keychain-backed SSH/cloud credentials, host-key trust, OpenSSH-based real command execution with cancellation, command metadata history with reruns, split stdout/stderr output, cloud account metadata, cloud instance links, cloud instance sync/import UI foundations, provider adapter registry, normalized cloud errors, Tencent Cloud TC3 request signing, Region/CVM instance response parsing, SSH-based Dashboard capability and metric collection including network and process summaries, Dashboard per-metric warning fallback, manual and auto-refresh, remote directory browsing, queued single-file upload/download with visible task states, current-transfer cancellation and pending-queue clearing, rename, chmod-based permission changes, recoverable move-to-trash, lightweight UTF-8 text editing with backup-on-save and Save As, systemd service listing/logs/actions, crontab reading and Cron entry management, dynamic Nginx config discovery/read/edit/test/reload with rollback, read-only firewall detection/rules display, guarded environment file discovery/editing with backups, remote change audit logs, unit tests, and GitHub Actions CI. Command output remains session-scoped and is not persisted by default. SFTP hardening, progress percentages, batch transfers, security groups, firewall write operations, deployment, package registry, and Windows native work remain planned later phases.

## Contributing

Contributions to design discussions, implementation, testing, and documentation improvements are welcome. Please read:

- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)

## License

This project is open source under the [MIT License](LICENSE).
