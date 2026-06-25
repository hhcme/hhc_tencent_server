# HHC Server Manager

English | [中文](README.zh-CN.md)

HHC Server Manager is an open-source macOS native server management client. It aims to manage multiple Linux servers through SSH and provide a desktop experience similar to Baota Panel, while avoiding any dependency on cloud vendor APIs.

The repository is currently in the design and Phase 1 planning stage. The first milestone is not a mocked UI. It is a secure, real, verifiable SSH MVP: save a server profile, store credentials, verify the host key, connect to a remote server, run a smoke-test command, and disconnect cleanly.

## Why

Many server management tools depend on web panels, cloud consoles, or heavy server-side agents. This project starts from a native macOS client and relies on common SSH capabilities as much as possible.

Target users include:

- Individual developers who manage several cloud servers.
- Small teams that want one place to manage Tencent Cloud, Alibaba Cloud, Huawei Cloud, or self-hosted Linux servers.
- Developers who prefer local desktop workflows for server configuration, deployment, and package registry management.

## Planned Features

- Server list, groups, search, and connection states.
- Password and private-key authentication.
- Sensitive credentials stored in macOS Keychain.
- First-use SSH host key trust and follow-up verification.
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
| Database | SQLite + GRDB 7.x |
| Credentials | macOS Keychain |
| Minimum OS | macOS 14 |

## Roadmap

1. **Phase 1: App skeleton and real SSH MVP**
   macOS app, server CRUD, Keychain, host key trust, real SSH connection, and `printf hhc-ssh-ok` smoke test.
2. **Phase 2: Dashboard and simplified command panel**
   System metrics, system information, process list, and command history.
3. **Phase 3: File manager**
   SFTP technical validation first, then directory browsing, upload, download, and editing.
4. **Phase 4: Environment configuration**
   systemd, Nginx, firewall, cron, and environment variables.
5. **Phase 5: GitLab deployment**
   Manual deployment, deployment logs, rollback, and webhook automation.
6. **Phase 6: Private package registries**
   Verdaccio and Dart/Flutter private package registry management.

## Documentation

- [Documentation index](docs/README.md)
- [Design document](docs/en/2026-06-25-server-manager-design.md)
- [Phase 1 implementation plan](docs/en/2026-06-25-phase1-ssh-connection.md)
- [中文设计文档](docs/superpowers/specs/2026-06-25-server-manager-design.md)
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
