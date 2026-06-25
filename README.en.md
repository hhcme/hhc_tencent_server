# HHC Server Manager

English | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to manage multiple Linux servers through SSH and provide a desktop experience similar to Baota Panel, with optional cloud provider API enhancements for instance discovery, cloud-side metrics, security groups, and power operations.

The repository is currently in the design and Phase 1 planning stage. The first milestone is not a mocked UI. It is a secure, real, verifiable SSH MVP: save a server profile, store credentials, verify the host key, connect to a remote server, run a smoke-test command, and disconnect cleanly.

## Why

Many server management tools depend on web panels, cloud consoles, or heavy server-side agents. This project starts from a native macOS client, uses common SSH capabilities for server-internal operations, and uses cloud APIs only where the cloud platform is the better source of truth.

Target users include:

- Individual developers who manage several cloud servers.
- Small teams that want one place to manage Tencent Cloud, Alibaba Cloud, Huawei Cloud, or self-hosted Linux servers.
- Developers who prefer local desktop workflows for server configuration, deployment, and package registry management.

## Planned Features

- Server list, groups, search, and connection states.
- Password and private-key authentication.
- Sensitive credentials stored in macOS Keychain.
- First-use SSH host key trust and follow-up verification.
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
| SSH | SwiftNIO SSH 0.13.x |
| Cloud APIs | Optional provider adapters |
| Database | SQLite + GRDB 7.x |
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
- [Design document](docs/en/2026-06-25-server-manager-design.md)
- [Cloud provider API enhancement](docs/en/2026-06-25-cloud-provider-integration.md)
- [Windows native client strategy](docs/en/2026-06-25-windows-native-client-strategy.md)
- [Phase 1 implementation plan](docs/en/2026-06-25-phase1-ssh-connection.md)
- [中文设计文档](docs/superpowers/specs/2026-06-25-server-manager-design.md)
- [中文云厂商 API 增强层设计](docs/superpowers/specs/2026-06-25-cloud-provider-integration.md)
- [中文 Windows 原生版技术选型](docs/superpowers/specs/2026-06-25-windows-native-client-strategy.md)
- [中文 Phase 1 计划](docs/superpowers/plans/2026-06-25-phase1-ssh-connection.md)

## Development Status

There is no application code yet. The repository first captures architecture, boundaries, open-source collaboration rules, and the Phase 1 plan so implementation does not need to revisit security, dependency, host-key trust, private-key storage, and concurrency decisions later.

## Contributing

Contributions to design discussions, implementation, testing, and documentation translation are welcome. Please read:

- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)

## License

This project is open source under the [MIT License](LICENSE).
