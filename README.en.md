# HHC Server Manager

English | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to manage multiple Linux servers through SSH and provide a desktop experience similar to Baota Panel, with optional cloud provider API enhancements for instance discovery, cloud-side metrics, security groups, and power operations.

The repository is in early macOS implementation. The app can already save server profiles, store SSH and cloud credentials in Keychain, verify SSH host keys, run a real OpenSSH smoke test, execute single remote commands, and persist command/cloud metadata in SQLite.

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
- Real OpenSSH smoke test, simplified single-command panel, and persisted command metadata history.
- Cloud account metadata and cloud credential storage foundation.
- Cloud provider adapter protocol, capability registry, normalized errors, and timeout wrapper.
- Tencent Cloud read-only adapter with TC3 request signing plus Region and CVM instance query parsing.
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
   Combine SSH metrics with cloud metrics; validate SFTP before directory browsing, upload, download, and editing.
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

The macOS app is now under active implementation. Phase 1 foundations are in place, and Phase 2 foundations have started: SwiftUI app structure, local SQLite persistence, Keychain-backed SSH/cloud credentials, host-key trust, OpenSSH-based real command execution, command metadata history, cloud account metadata, cloud instance links, provider adapter registry, normalized cloud errors, Tencent Cloud TC3 request signing, Region/CVM instance response parsing, operation logs, unit tests, and GitHub Actions CI. Command output remains session-scoped and is not persisted by default. Dashboard, SFTP, deployment, package registry, and Windows native work remain planned later phases.

## Contributing

Contributions to design discussions, implementation, testing, and documentation improvements are welcome. Please read:

- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)

## License

This project is open source under the [MIT License](LICENSE).
